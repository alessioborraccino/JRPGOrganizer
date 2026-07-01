import Foundation
import FoundationModels
import Observation
import SwiftData

public enum AIOrganizerError: LocalizedError {
    case modelUnavailable(String)
    case noRawEntries
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            "On-device Apple Intelligence is unavailable: \(reason)"
        case .noRawEntries:
            "This guide has no imported rows to organize."
        case .generationFailed(let reason):
            "On-device organization failed: \(reason)"
        }
    }
}

@MainActor
@Observable
public final class GuideAIOrganizer {
    public private(set) var isOrganizing = false
    public private(set) var organizingGameID: UUID?
    public private(set) var statusMessage: String?
    public private(set) var errorMessage: String?
    public private(set) var organizedChunkCount = 0
    public private(set) var totalChunkCount = 0
    public private(set) var fallbackChunkCount = 0

    public var organizationProgress: Double {
        guard totalChunkCount > 0 else { return 0 }
        return min(Double(organizedChunkCount) / Double(totalChunkCount), 1)
    }

    private let client: AppleFoundationOrganizerClient

    public init(client: AppleFoundationOrganizerClient = AppleFoundationOrganizerClient()) {
        self.client = client
    }

    public func isOrganizing(_ game: SavedGame) -> Bool {
        isOrganizing && organizingGameID == game.id
    }

    public func organize(_ game: SavedGame, modelContainer: ModelContainer) async {
        guard !isOrganizing else { return }

        let gameID = game.id

        isOrganizing = true
        organizingGameID = game.id
        errorMessage = nil
        statusMessage = "Checking on-device model..."
        organizedChunkCount = 0
        totalChunkCount = 0
        fallbackChunkCount = 0

        do {
            let worker = AIOrganizerWorker(
                modelContainer: modelContainer,
                client: client
            )
            let completion = try await worker.organize(gameID: gameID) { [weak self] update in
                guard let self else { return }
                statusMessage = update.statusMessage
                organizedChunkCount = update.organizedChunkCount
                totalChunkCount = update.totalChunkCount
                fallbackChunkCount = update.fallbackChunkCount
            }
            statusMessage = completion.statusMessage
            organizedChunkCount = completion.organizedChunkCount
            totalChunkCount = completion.totalChunkCount
            fallbackChunkCount = completion.fallbackChunkCount
        } catch {
            errorMessage = error.organizerGenerationMessage
            statusMessage = nil
        }

        isOrganizing = false
        organizingGameID = nil
    }

    public func clearError() {
        errorMessage = nil
    }

    nonisolated fileprivate static func makeEntries(
        from organizedChunk: OrganizedChunkResponse,
        chunk: AIOrganizerChunk,
        previousCompletedSignatures: Set<String>
    ) -> [OrganizedEntryDraft] {
        let rawEntryByID = Dictionary(uniqueKeysWithValues: chunk.entries.map { ($0.id.uuidString, $0) })
        let encoder = JSONEncoder()

        return organizedChunk.entries.enumerated().compactMap { outputIndex, output in
            let sourceEntries = output.sourceEntryIDs.compactMap { rawEntryByID[$0] }
            guard !sourceEntries.isEmpty else { return nil }

            let sourceIDs = sourceEntries.map { $0.id.uuidString }
            let sourceIDsJSON = (try? String(data: encoder.encode(sourceIDs), encoding: .utf8)) ?? "[]"
            let firstSource = sourceEntries.min { $0.sortOrder < $1.sortOrder } ?? sourceEntries[0]
            let requestedEntryKind = WalkthroughEntryKind(rawValue: output.entryKind.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .callout
            let contentKind = Self.validatedContentKind(
                Self.normalizedContentKind(output.contentKind),
                output: output,
                sourceEntries: sourceEntries,
                requestedEntryKind: requestedEntryKind
            )
            let entryKind = normalizedEntryKind(requestedEntryKind, contentKind: contentKind)
            let mediaSource = sourceEntries.first { $0.imageURL != nil }
            let title = Self.validatedTitle(
                output.title,
                contentKind: contentKind,
                sourceEntries: sourceEntries
            )

            var entry = OrganizedEntryDraft(
                sortOrder: firstSource.sortOrder * 100 + outputIndex,
                chapterTitle: firstSource.chapterTitle,
                guideSection: firstSource.guideSection,
                sourceURL: firstSource.sourceURL,
                location: firstSource.location,
                entryKind: entryKind,
                contentKind: contentKind,
                title: title,
                body: output.body.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceEntryIDsJSON: sourceIDsJSON,
                imageURL: mediaSource?.imageURL,
                imageCaption: mediaSource?.imageCaption
            )
            entry.isCompleted = previousCompletedSignatures.contains(entry.progressSignature)
            return entry
        }
    }

    nonisolated fileprivate static func makeFallbackResponse(for chunk: AIOrganizerChunk) -> OrganizedChunkResponse {
        OrganizedChunkResponse(
            entries: chunk.entries.flatMap(makeFallbackEntries)
        )
    }

    nonisolated private static func makeFallbackEntries(for entry: AIOrganizerSourceEntry) -> [OrganizedChunkEntry] {
        let labelledSections = splitLabelledSections(for: entry)
        guard !labelledSections.isEmpty else {
            let contentKind = fallbackContentKind(for: entry)
            let entryKind = normalizedEntryKind(entry.entryKind, contentKind: contentKind)

            return [
                OrganizedChunkEntry(
                    entryKind: entryKind.rawValue,
                    contentKind: contentKind.rawValue,
                    title: fallbackTitle(for: entry, contentKind: contentKind),
                    body: entry.body.isEmpty ? entry.title : entry.body,
                    sourceEntryIDs: [entry.id.uuidString]
                )
            ]
        }

        return labelledSections.map { section in
            OrganizedChunkEntry(
                entryKind: normalizedEntryKind(entry.entryKind, contentKind: section.contentKind).rawValue,
                contentKind: section.contentKind.rawValue,
                title: section.title,
                body: section.body,
                sourceEntryIDs: [entry.id.uuidString]
            )
        }
    }

    nonisolated private static func fallbackTitle(
        for entry: AIOrganizerSourceEntry,
        contentKind: OrganizedContentKind
    ) -> String {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !isGenericImportedTitle(title) {
            return title
        }

        switch contentKind {
        case .storyStep:
            return "Checklist"
        case .loot:
            return equipmentText(entry) ? "Equipment" : "Loot"
        case .enemy:
            return "Enemies"
        case .boss:
            return "Boss"
        case .shop:
            return "Shop"
        case .sidequest:
            return "Sidequest"
        case .note:
            return equipmentText(entry) ? "Equipment" : "Note"
        case .image:
            return "Image"
        case .map:
            return "Map"
        }
    }

    nonisolated private static func fallbackContentKind(for entry: AIOrganizerSourceEntry) -> OrganizedContentKind {
        if entry.imageURL != nil {
            return entry.calloutKind == .map ? .map : .image
        }

        if let calloutKind = entry.calloutKind {
            switch calloutKind {
            case .loot:
                return .loot
            case .enemy:
                return .enemy
            case .shop:
                return .shop
            case .quest:
                return .sidequest
            case .battle:
                return fallbackText(entry).localizedCaseInsensitiveContains("boss") ? .boss : .note
            case .image:
                return .image
            case .map:
                return .map
            case .important, .tip, .version, .warning, .reference, .sourceSpoiler:
                break
            }
        }

        if looksLikeBossReference(entry) {
            return .boss
        }
        if looksLikeEnemyReference(entry) {
            return .enemy
        }
        if looksLikeShopReference(entry) {
            return .shop
        }
        if looksLikeLootReference(entry) {
            return .loot
        }
        if equipmentText(entry) {
            return .note
        }
        if looksLikeSidequestText(title: entry.title, body: entry.body, guideSections: [entry.guideSection]) {
            return .sidequest
        }

        return entry.entryKind == .task ? .storyStep : .note
    }

    nonisolated private static func fallbackText(_ entry: AIOrganizerSourceEntry) -> String {
        "\(entry.title) \(entry.body)"
    }

    nonisolated private static func isGenericImportedTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "story step"
            || normalized == "completion"
            || normalized == "reference"
            || normalized == "checklist"
    }

    nonisolated private static func looksLikeEnemyReference(_ entry: AIOrganizerSourceEntry) -> Bool {
        if entry.calloutKind == .enemy {
            return true
        }

        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !isGenericImportedTitle(entry.title),
           title == "enemy" || title == "enemies" || title.hasPrefix("enemies ") {
            return true
        }

        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return startsWithLabel(body, labels: ["enemy", "enemies", "enemies to encounter", "monsters"])
            || body.contains("enemies:")
            || body.contains("enemies -")
            || body.contains("enemies to encounter:")
    }

    nonisolated private static func looksLikeBossReference(_ entry: AIOrganizerSourceEntry) -> Bool {
        if entry.calloutKind == .battle {
            return true
        }

        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (!isGenericImportedTitle(entry.title) && (title == "boss" || title.hasPrefix("boss ")))
            || startsWithLabel(body, labels: ["boss", "boss battle"])
            || body.contains("boss:")
    }

    nonisolated private static func looksLikeShopReference(_ entry: AIOrganizerSourceEntry) -> Bool {
        if entry.calloutKind == .shop {
            return true
        }

        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (!isGenericImportedTitle(entry.title) && (title.contains("shop") || title.contains("store")))
            || startsWithLabel(body, labels: ["shop", "item shop", "weapon shop", "armor shop", "armour shop", "store"])
            || body.contains(" shop:")
            || body.contains(" shop -")
    }

    nonisolated private static func looksLikeLootReference(_ entry: AIOrganizerSourceEntry) -> Bool {
        if entry.calloutKind == .loot {
            return true
        }

        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let body = entry.body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels = ["items", "item", "loot", "treasure", "chests", "chest", "materia", "rewards", "recipe", "mini medal"]
        return (!isGenericImportedTitle(entry.title) && labels.contains { title == $0 || title.hasPrefix("\($0) ") })
            || startsWithLabel(body, labels: labels)
            || labels.contains { body.contains("\($0):") || body.contains("\($0) -") }
    }

    nonisolated private static func equipmentText(_ entry: AIOrganizerSourceEntry) -> Bool {
        equipmentText(fallbackText(entry))
    }

    nonisolated private static func equipmentText(_ text: String) -> Bool {
        let text = text.lowercased()
        return text.contains("equipment")
            || text.contains("equipped")
            || text.contains("weapon")
            || text.contains("sword")
            || text.contains("boomerang")
            || text.contains("armor")
            || text.contains("armour")
            || text.contains("accessory")
    }

    nonisolated private static func startsWithLabel(_ text: String, labels: [String]) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return labels.contains { label in
            trimmed == label
                || trimmed.hasPrefix("\(label):")
                || trimmed.hasPrefix("\(label) -")
                || trimmed.hasPrefix("\(label) ")
        }
    }

    nonisolated private static func splitLabelledSections(for entry: AIOrganizerSourceEntry) -> [FallbackLabelledSection] {
        let text = (entry.body.isEmpty ? entry.title : entry.body)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 12 else { return [] }

        let matches = fallbackLabelMatches(in: text)
        guard !matches.isEmpty else { return [] }

        var sections: [FallbackLabelledSection] = []
        for (index, match) in matches.enumerated() {
            let bodyStart = match.range.upperBound
            let bodyEnd = index + 1 < matches.count ? matches[index + 1].range.lowerBound : text.endIndex
            guard bodyStart <= bodyEnd else { continue }
            let body = String(text[bodyStart..<bodyEnd])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ".;,- "))
            guard body.count >= 2 else { continue }

            sections.append(
                FallbackLabelledSection(
                    title: match.title,
                    body: body,
                    contentKind: match.contentKind,
                    isLeading: text[..<match.range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            )
        }

        guard sections.count > 1 || shouldTrustSingleLabelledSection(sections.first, entry: entry) else {
            return []
        }
        return sections
    }

    nonisolated private static func shouldTrustSingleLabelledSection(
        _ section: FallbackLabelledSection?,
        entry: AIOrganizerSourceEntry
    ) -> Bool {
        guard let section else { return false }
        if entry.entryKind == .callout {
            return true
        }
        guard section.isLeading else {
            return false
        }

        switch section.contentKind {
        case .enemy, .loot, .shop, .boss:
            return true
        case .storyStep, .sidequest, .note, .image, .map:
            return false
        }
    }

    nonisolated private static func fallbackLabelMatches(in text: String) -> [FallbackLabelMatch] {
        let labels: [(label: String, title: String, contentKind: OrganizedContentKind)] = [
            ("enemies to encounter", "Enemies", .enemy),
            ("enemies", "Enemies", .enemy),
            ("enemy", "Enemies", .enemy),
            ("bosses", "Bosses", .boss),
            ("boss", "Boss", .boss),
            ("items", "Items", .loot),
            ("item", "Items", .loot),
            ("key items", "Key Items", .loot),
            ("materia", "Materia", .loot),
            ("treasure", "Treasure", .loot),
            ("treasures", "Treasure", .loot),
            ("chests", "Chests", .loot),
            ("chest", "Chests", .loot),
            ("rewards", "Rewards", .loot),
            ("reward", "Rewards", .loot),
            ("enemy skills", "Enemy Skills", .loot),
            ("shops", "Shops", .shop),
            ("shop", "Shop", .shop),
            ("item shop", "Item Shop", .shop),
            ("weapon shop", "Weapon Shop", .shop),
            ("weapons", "Weapons", .shop),
            ("armor shop", "Armor Shop", .shop),
            ("armour shop", "Armour Shop", .shop),
            ("armor", "Armor", .shop),
            ("armour", "Armour", .shop),
            ("accessories", "Accessories", .shop),
            ("notes", "Notes", .note),
            ("note", "Note", .note),
            ("warning", "Warning", .note),
        ]

        let lowercasedText = text.lowercased()
        var matches: [FallbackLabelMatch] = []

        for candidate in labels {
            var searchStart = lowercasedText.startIndex
            while searchStart < lowercasedText.endIndex,
                  let range = lowercasedText.range(
                    of: candidate.label,
                    options: [.caseInsensitive],
                    range: searchStart..<lowercasedText.endIndex
                  ) {
                let afterLabel = range.upperBound
                let afterWhitespace = lowercasedText[afterLabel...].firstIndex { !$0.isWhitespace } ?? afterLabel
                guard afterWhitespace < lowercasedText.endIndex,
                      lowercasedText[afterWhitespace] == ":" || lowercasedText[afterWhitespace] == "-" else {
                    searchStart = afterLabel
                    continue
                }

                if isLabelBoundary(before: range.lowerBound, in: lowercasedText) {
                    let end = lowercasedText.index(after: afterWhitespace)
                    matches.append(
                        FallbackLabelMatch(
                            title: candidate.title,
                            contentKind: candidate.contentKind,
                            range: range.lowerBound..<end
                        )
                    )
                }
                searchStart = afterLabel
            }
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.range.lowerBound == rhs.range.lowerBound {
                    return lhs.range.upperBound > rhs.range.upperBound
                }
                return lhs.range.lowerBound < rhs.range.lowerBound
            }
            .reduce(into: [FallbackLabelMatch]()) { uniqueMatches, match in
                if let lastMatch = uniqueMatches.last {
                    guard match.range.lowerBound >= lastMatch.range.upperBound else { return }
                }
                uniqueMatches.append(match)
            }
    }

    nonisolated private static func isLabelBoundary(before index: String.Index, in text: String) -> Bool {
        guard index > text.startIndex else { return true }
        let previousIndex = text.index(before: index)
        let previousCharacter = text[previousIndex]
        return previousCharacter.isWhitespace
            || previousCharacter == "."
            || previousCharacter == ";"
            || previousCharacter == ","
            || previousCharacter == "("
            || previousCharacter == "["
    }

    nonisolated private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.localizedCaseInsensitiveContains($0) }
    }

    nonisolated private static func normalizedContentKind(_ rawValue: String) -> OrganizedContentKind {
        OrganizedContentKind(rawValue: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .note
    }

    nonisolated private static func validatedContentKind(
        _ requestedContentKind: OrganizedContentKind,
        output: OrganizedChunkEntry,
        sourceEntries: [AIOrganizerSourceEntry],
        requestedEntryKind: WalkthroughEntryKind
    ) -> OrganizedContentKind {
        let title = output.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = output.body.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceGuideSections = sourceEntries.map(\.guideSection)

        switch requestedContentKind {
        case .enemy:
            if sourceEntries.contains(where: { $0.calloutKind == .enemy })
                || looksLikeEnemyText(title: title, body: body) {
                return .enemy
            }
            return demotedContentKind(
                requestedEntryKind: requestedEntryKind,
                sourceEntries: sourceEntries,
                title: title,
                body: body
            )
        case .boss:
            if sourceEntries.contains(where: { $0.calloutKind == .battle })
                || looksLikeBossText(title: title, body: body) {
                return .boss
            }
            return demotedContentKind(
                requestedEntryKind: requestedEntryKind,
                sourceEntries: sourceEntries,
                title: title,
                body: body
            )
        case .shop:
            if sourceEntries.contains(where: { $0.calloutKind == .shop })
                || looksLikeShopText(title: title, body: body) {
                return .shop
            }
            return demotedContentKind(
                requestedEntryKind: requestedEntryKind,
                sourceEntries: sourceEntries,
                title: title,
                body: body
            )
        case .loot:
            if sourceEntries.contains(where: { $0.calloutKind == .loot })
                || looksLikeLootText(title: title, body: body)
                || sourceEntries.contains(where: looksLikeLootReference) {
                return .loot
            }
            return demotedContentKind(
                requestedEntryKind: requestedEntryKind,
                sourceEntries: sourceEntries,
                title: title,
                body: body
            )
        case .sidequest:
            if sourceEntries.contains(where: { $0.calloutKind == .quest })
                || looksLikeSidequestText(title: title, body: body, guideSections: sourceGuideSections) {
                return .sidequest
            }
            return demotedContentKind(
                requestedEntryKind: requestedEntryKind,
                sourceEntries: sourceEntries,
                title: title,
                body: body
            )
        case .storyStep, .note, .image, .map:
            return requestedContentKind
        }
    }

    nonisolated private static func demotedContentKind(
        requestedEntryKind: WalkthroughEntryKind,
        sourceEntries: [AIOrganizerSourceEntry],
        title: String,
        body: String
    ) -> OrganizedContentKind {
        if equipmentText("\(title) \(body)") || sourceEntries.contains(where: equipmentText) {
            return .note
        }
        if requestedEntryKind == .task,
           sourceEntries.allSatisfy({ $0.entryKind == .task }),
           sourceEntries.contains(where: { $0.mode == .walkthrough }) {
            return .storyStep
        }
        return .note
    }

    nonisolated private static func validatedTitle(
        _ outputTitle: String,
        contentKind: OrganizedContentKind,
        sourceEntries: [AIOrganizerSourceEntry]
    ) -> String {
        let title = outputTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty, !isGenericImportedTitle(title) {
            return title
        }

        if let sourceEntry = sourceEntries.first {
            return fallbackTitle(for: sourceEntry, contentKind: contentKind)
        }

        switch contentKind {
        case .storyStep:
            return "Checklist"
        case .loot:
            return "Loot"
        case .enemy:
            return "Enemies"
        case .boss:
            return "Boss"
        case .shop:
            return "Shop"
        case .sidequest:
            return "Sidequest"
        case .note:
            return "Note"
        case .image:
            return "Image"
        case .map:
            return "Map"
        }
    }

    nonisolated private static func looksLikeEnemyText(title: String, body: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (!isGenericImportedTitle(normalizedTitle)
                && (normalizedTitle == "enemy" || normalizedTitle == "enemies" || normalizedTitle.hasPrefix("enemies ")))
            || startsWithLabel(normalizedBody, labels: ["enemy", "enemies", "enemies to encounter", "monsters"])
            || normalizedBody.contains("enemies:")
            || normalizedBody.contains("enemies -")
            || normalizedBody.contains("enemies to encounter:")
    }

    nonisolated private static func looksLikeBossText(title: String, body: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (!isGenericImportedTitle(normalizedTitle)
                && (normalizedTitle == "boss" || normalizedTitle.hasPrefix("boss ")))
            || startsWithLabel(normalizedBody, labels: ["boss", "boss battle"])
            || normalizedBody.contains("boss:")
    }

    nonisolated private static func looksLikeShopText(title: String, body: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (!isGenericImportedTitle(normalizedTitle)
                && (normalizedTitle.contains("shop") || normalizedTitle.contains("store")))
            || startsWithLabel(normalizedBody, labels: ["shop", "item shop", "weapon shop", "armor shop", "armour shop", "store"])
            || normalizedBody.contains(" shop:")
            || normalizedBody.contains(" shop -")
    }

    nonisolated private static func looksLikeLootText(title: String, body: String) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels = ["items", "item", "loot", "treasure", "treasures", "chests", "chest", "materia", "rewards", "reward", "recipe", "mini medal"]
        return (!isGenericImportedTitle(normalizedTitle) && labels.contains { normalizedTitle == $0 || normalizedTitle.hasPrefix("\($0) ") })
            || startsWithLabel(normalizedBody, labels: labels)
            || labels.contains { normalizedBody.contains("\($0):") || normalizedBody.contains("\($0) -") }
            || normalizedBody.contains("chest containing")
            || normalizedBody.contains("treasure chest")
            || normalizedBody.contains("sparkly spot")
    }

    nonisolated private static func looksLikeSidequestText(
        title: String,
        body: String,
        guideSections: [String]
    ) -> Bool {
        if guideSections.contains(where: { $0.localizedCaseInsensitiveContains("Sidequests") }) {
            return true
        }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let labels = ["quest", "side quest", "sidequest", "mini-game", "minigame"]
        return (!isGenericImportedTitle(normalizedTitle)
                && labels.contains { normalizedTitle == $0 || normalizedTitle.hasPrefix("\($0) ") })
            || startsWithLabel(normalizedBody, labels: labels)
            || normalizedBody.contains(" quest:")
            || normalizedBody.contains(" side quest:")
    }

    nonisolated private static func normalizedEntryKind(
        _ requestedKind: WalkthroughEntryKind,
        contentKind: OrganizedContentKind
    ) -> WalkthroughEntryKind {
        switch contentKind {
        case .storyStep:
            .task
        case .sidequest:
            requestedKind == .task ? .task : .callout
        case .loot, .enemy, .boss, .shop, .note, .image, .map:
            .callout
        }
    }
}

private struct AIOrganizerProgressUpdate: Sendable {
    let statusMessage: String
    let organizedChunkCount: Int
    let totalChunkCount: Int
    let fallbackChunkCount: Int
}

private struct AIOrganizerCompletion: Sendable {
    let statusMessage: String
    let organizedChunkCount: Int
    let totalChunkCount: Int
    let fallbackChunkCount: Int
}

private struct FallbackLabelledSection: Sendable {
    let title: String
    let body: String
    let contentKind: OrganizedContentKind
    let isLeading: Bool
}

private struct FallbackLabelMatch: Sendable {
    let title: String
    let contentKind: OrganizedContentKind
    let range: Range<String.Index>
}

private actor AIOrganizerWorker {
    private let store: AIOrganizerStore
    private let client: AppleFoundationOrganizerClient

    init(modelContainer: ModelContainer, client: AppleFoundationOrganizerClient) {
        store = AIOrganizerStore(modelContainer: modelContainer)
        self.client = client
    }

    fileprivate func organize(
        gameID: UUID,
        progress: @escaping @MainActor @Sendable (AIOrganizerProgressUpdate) -> Void
    ) async throws -> AIOrganizerCompletion {
        await progress(
            AIOrganizerProgressUpdate(
                statusMessage: "Loading imported guide...",
                organizedChunkCount: 0,
                totalChunkCount: 0,
                fallbackChunkCount: 0
            )
        )

        let snapshot = try await store.loadGameSnapshot(gameID: gameID)
        guard !snapshot.rawEntries.isEmpty else {
            throw AIOrganizerError.noRawEntries
        }

        if let bypassReason = Self.organizationBypassReason(for: snapshot) {
            await progress(
                AIOrganizerProgressUpdate(
                    statusMessage: bypassReason,
                    organizedChunkCount: 1,
                    totalChunkCount: 1,
                    fallbackChunkCount: 0
                )
            )
            try await store.replaceOrganizedEntries([], gameID: gameID)
            return AIOrganizerCompletion(
                statusMessage: bypassReason,
                organizedChunkCount: 1,
                totalChunkCount: 1,
                fallbackChunkCount: 0
            )
        }

        let chunks = AIOrganizerChunk.makeChunks(from: snapshot.rawEntries)
        let localOnlyReason = Self.localOnlyReason(for: snapshot)
        let needsAnyModelCleanup = localOnlyReason == nil && chunks.contains(where: Self.shouldUseModelCleanup)

        await progress(
            AIOrganizerProgressUpdate(
                statusMessage: needsAnyModelCleanup ? "Checking on-device model..." : "Preparing fast local organization...",
                organizedChunkCount: 0,
                totalChunkCount: 1,
                fallbackChunkCount: 0
            )
        )

        let modelFallbackMessage: String?
        if let localOnlyReason {
            modelFallbackMessage = localOnlyReason
        } else if needsAnyModelCleanup {
            do {
                try await client.validateAvailability()
                modelFallbackMessage = nil
            } catch {
                modelFallbackMessage = error.foundationModelFallbackMessage
            }
        } else {
            modelFallbackMessage = "Fast local cleanup was enough for this import."
        }

        var activeModelFallbackMessage = modelFallbackMessage
        var fallbackChunkCount = chunks.count
        var chunkDrafts = chunks.map { chunk in
            GuideAIOrganizer.makeEntries(
                from: GuideAIOrganizer.makeFallbackResponse(for: chunk),
                chunk: chunk,
                previousCompletedSignatures: snapshot.previousCompletedSignatures
            )
        }

        let candidateIndexes = activeModelFallbackMessage == nil
            ? Self.modelCleanupCandidateIndexes(in: chunks)
            : []
        let totalWorkUnits = max(candidateIndexes.count + 2, 1)
        var successfulModelCleanupCount = 0

        await progress(
            AIOrganizerProgressUpdate(
                statusMessage: candidateIndexes.isEmpty ? "Saving organized guide..." : "Prepared fast local organization.",
                organizedChunkCount: 1,
                totalChunkCount: totalWorkUnits,
                fallbackChunkCount: fallbackChunkCount
            )
        )

        for (candidateOffset, chunkIndex) in candidateIndexes.enumerated() {
            try Task.checkCancellation()

            let chunk = chunks[chunkIndex]
            let status = "AI cleanup \(candidateOffset + 1) of \(candidateIndexes.count)..."
            await progress(
                AIOrganizerProgressUpdate(
                    statusMessage: status,
                    organizedChunkCount: candidateOffset + 1,
                    totalChunkCount: totalWorkUnits,
                    fallbackChunkCount: fallbackChunkCount
                )
            )

            do {
                let organizedChunk = try await organizeChunkRecovering(
                    chunk,
                    gameTitle: snapshot.title,
                    fallbackChunkCount: &fallbackChunkCount
                )
                chunkDrafts[chunkIndex] = GuideAIOrganizer.makeEntries(
                    from: organizedChunk,
                    chunk: chunk,
                    previousCompletedSignatures: snapshot.previousCompletedSignatures
                )
                fallbackChunkCount = max(fallbackChunkCount - 1, 0)
                successfulModelCleanupCount += 1
            } catch {
                activeModelFallbackMessage = error.foundationModelFallbackMessage
                break
            }

            await progress(
                AIOrganizerProgressUpdate(
                    statusMessage: status,
                    organizedChunkCount: candidateOffset + 2,
                    totalChunkCount: totalWorkUnits,
                    fallbackChunkCount: fallbackChunkCount
                )
            )
            await Task.yield()
        }

        let organizedEntries = chunkDrafts.flatMap(\.self)

        await progress(
            AIOrganizerProgressUpdate(
                statusMessage: "Saving organized guide...",
                organizedChunkCount: totalWorkUnits,
                totalChunkCount: totalWorkUnits,
                fallbackChunkCount: fallbackChunkCount
            )
        )

        try await store.replaceOrganizedEntries(
            organizedEntries.sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.title < rhs.title
                }
                return lhs.sortOrder < rhs.sortOrder
            },
            gameID: gameID
        )

        let finalStatus: String
        if let activeModelFallbackMessage {
            finalStatus = "Organized \(organizedEntries.count) reader rows. \(activeModelFallbackMessage) Used fast local cleanup for \(fallbackChunkCount) chunks."
        } else if fallbackChunkCount > 0 {
            finalStatus = "Organized \(organizedEntries.count) reader rows on device. AI cleaned \(successfulModelCleanupCount) chunks; fast local cleanup handled \(fallbackChunkCount)."
        } else {
            finalStatus = "Organized \(organizedEntries.count) reader rows on device."
        }

        return AIOrganizerCompletion(
            statusMessage: finalStatus,
            organizedChunkCount: totalWorkUnits,
            totalChunkCount: totalWorkUnits,
            fallbackChunkCount: fallbackChunkCount
        )
    }

    private static func localOnlyReason(for snapshot: AIOrganizerGameSnapshot) -> String? {
        return nil
    }

    private static func organizationBypassReason(for snapshot: AIOrganizerGameSnapshot) -> String? {
        let rootURL = snapshot.rootURL.lowercased()
        if rootURL.contains("dragon-quest-xi") {
            return "Dragon Quest XI is already imported as a structured reader. Using the imported timeline directly."
        }
        return nil
    }

    private static func modelCleanupCandidateIndexes(in chunks: [AIOrganizerChunk]) -> [Int] {
        chunks.indices
            .filter { shouldUseModelCleanup(chunks[$0]) }
            .prefix(maximumModelCleanupChunkCount)
            .map(\.self)
    }

    private static func shouldUseModelCleanup(_ chunk: AIOrganizerChunk) -> Bool {
        chunk.entries.contains { entry in
            guard entry.entryKind == .task else { return false }
            let text = "\(entry.title) \(entry.body)".lowercased()
            let hasReferenceLabel = text.contains("enemies")
                || text.contains("enemy:")
                || text.contains("items:")
                || text.contains("materia:")
                || text.contains("shop:")
                || text.contains("boss:")
                || text.contains("treasure:")
            let hasMixedSignals = (text.contains("enemies") || text.contains("enemy:"))
                && (text.contains("item") || text.contains("materia") || text.contains("treasure"))
            let isLongFAQBlock = entry.body.count > 900
                && (text.contains(":") || text.contains(" - "))
            return hasMixedSignals || (hasReferenceLabel && isLongFAQBlock)
        }
    }

    private static let maximumModelCleanupChunkCount = 8

    private func organizeChunkRecovering(
        _ chunk: AIOrganizerChunk,
        gameTitle: String,
        fallbackChunkCount: inout Int
    ) async throws -> OrganizedChunkResponse {
        do {
            return try await client.organize(chunk: chunk, gameTitle: gameTitle)
        } catch {
            if error.shouldStopFoundationOrganizerAttempts {
                throw error
            }

            guard chunk.entries.count > 1 else {
                fallbackChunkCount += 1
                return GuideAIOrganizer.makeFallbackResponse(for: chunk)
            }

            let splitChunks = chunk.split()
            var entries: [OrganizedChunkEntry] = []
            entries.reserveCapacity(chunk.entries.count)

            for splitChunk in splitChunks {
                do {
                    let response = try await client.organize(chunk: splitChunk, gameTitle: gameTitle)
                    entries.append(contentsOf: response.entries)
                } catch {
                    if error.shouldStopFoundationOrganizerAttempts {
                        throw error
                    }

                    fallbackChunkCount += 1
                    entries.append(contentsOf: GuideAIOrganizer.makeFallbackResponse(for: splitChunk).entries)
                }
            }

            return OrganizedChunkResponse(entries: entries)
        }
    }
}

@ModelActor
private actor AIOrganizerStore {
    func loadGameSnapshot(gameID: UUID) throws -> AIOrganizerGameSnapshot {
        let game = try savedGame(id: gameID)
        let progressStates = game.progressRecords.reduce(into: [String: Bool]()) { states, record in
            guard record.readerLayer == .organized else { return }
            states[record.entrySignature] = record.isCompleted
        }
        let completedSignatures: Set<String>
        if progressStates.isEmpty {
            completedSignatures = Set(
                game.organizedEntries
                    .filter { $0.organizerVersion == OrganizedWalkthroughEntry.currentOrganizerVersion }
                    .filter { $0.entryKind == .task && $0.isCompleted }
                    .map(\.progressSignature)
            )
        } else {
            completedSignatures = Set(progressStates.compactMap { signature, isCompleted in
                isCompleted ? signature : nil
            })
        }

        let rawEntries = game.entries
            .map(AIOrganizerSourceEntry.init(entry:))
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.sortOrder < rhs.sortOrder
            }

        return AIOrganizerGameSnapshot(
            title: game.title,
            rootURL: game.rootURL,
            rawEntries: rawEntries,
            previousCompletedSignatures: completedSignatures
        )
    }

    func replaceOrganizedEntries(_ drafts: [OrganizedEntryDraft], gameID: UUID) throws {
        let game = try savedGame(id: gameID)

        for entry in game.organizedEntries {
            modelContext.delete(entry)
        }
        game.organizedEntries.removeAll()

        for draft in drafts {
            let entry = draft.makeModel()
            entry.game = game
            modelContext.insert(entry)
            game.organizedEntries.append(entry)
        }

        game.refreshCachedProgressCounts()
        try modelContext.save()
    }

    private func savedGame(id gameID: UUID) throws -> SavedGame {
        var descriptor = FetchDescriptor<SavedGame>(
            predicate: #Predicate { game in
                game.id == gameID
            }
        )
        descriptor.fetchLimit = 1

        guard let game = try modelContext.fetch(descriptor).first else {
            throw AIOrganizerError.generationFailed("The saved guide could not be loaded.")
        }
        return game
    }
}

private struct AIOrganizerGameSnapshot: Sendable {
    let title: String
    let rootURL: String
    let rawEntries: [AIOrganizerSourceEntry]
    let previousCompletedSignatures: Set<String>
}

private struct AIOrganizerSourceEntry: Sendable {
    let id: UUID
    let sortOrder: Int
    let chapterTitle: String
    let guideSection: String
    let sourceURL: String
    let location: String
    let title: String
    let body: String
    let imageURL: String?
    let imageCaption: String?
    let entryKind: WalkthroughEntryKind
    let mode: WalkthroughEntryMode
    let calloutKind: WalkthroughCalloutKind?

    init(entry: WalkthroughEntry) {
        id = entry.id
        sortOrder = entry.sortOrder
        chapterTitle = entry.chapterTitle
        guideSection = entry.guideSection
        sourceURL = entry.sourceURL
        location = entry.location
        title = entry.title
        body = entry.body
        imageURL = entry.imageURL
        imageCaption = entry.imageCaption
        entryKind = entry.entryKind
        mode = entry.mode
        calloutKind = entry.calloutKind
    }
}

fileprivate struct OrganizedEntryDraft: Sendable {
    let sortOrder: Int
    let chapterTitle: String
    let guideSection: String
    let sourceURL: String
    let location: String
    let entryKind: WalkthroughEntryKind
    let contentKind: OrganizedContentKind
    let title: String
    let body: String
    let sourceEntryIDsJSON: String
    let imageURL: String?
    let imageCaption: String?
    var isCompleted: Bool

    init(
        sortOrder: Int,
        chapterTitle: String,
        guideSection: String,
        sourceURL: String,
        location: String,
        entryKind: WalkthroughEntryKind,
        contentKind: OrganizedContentKind,
        title: String,
        body: String,
        sourceEntryIDsJSON: String,
        imageURL: String?,
        imageCaption: String?,
        isCompleted: Bool = false
    ) {
        self.sortOrder = sortOrder
        self.chapterTitle = chapterTitle
        self.guideSection = guideSection
        self.sourceURL = sourceURL
        self.location = location
        self.entryKind = entryKind
        self.contentKind = contentKind
        self.title = title
        self.body = body
        self.sourceEntryIDsJSON = sourceEntryIDsJSON
        self.imageURL = imageURL
        self.imageCaption = imageCaption
        self.isCompleted = isCompleted
    }

    var progressSignature: String {
        [
            "\(OrganizedWalkthroughEntry.currentOrganizerVersion)",
            sourceEntryIDsJSON,
            entryKind.rawValue,
            contentKind.rawValue,
            title,
            body,
            imageURL ?? "",
        ].joined(separator: "|")
    }

    func makeModel() -> OrganizedWalkthroughEntry {
        OrganizedWalkthroughEntry(
            sortOrder: sortOrder,
            chapterTitle: chapterTitle,
            guideSection: guideSection,
            sourceURL: sourceURL,
            location: location,
            entryKind: entryKind,
            contentKind: contentKind,
            title: title,
            body: body,
            isCompleted: isCompleted,
            sourceEntryIDsJSON: sourceEntryIDsJSON,
            imageURL: imageURL,
            imageCaption: imageCaption
        )
    }
}

public struct AppleFoundationOrganizerClient: Sendable {
    public init() {}

    @MainActor
    public func validateAvailability() throws {
#if targetEnvironment(simulator)
        throw AIOrganizerError.modelUnavailable(
            "Foundation Models assets are not available reliably in Simulator. Use a physical Apple Intelligence device to test true AI organization."
        )
#else
        let model = Self.organizerModel
        guard case .available = model.availability else {
            throw AIOrganizerError.modelUnavailable(model.availability.organizerUnavailableReason)
        }
#endif
    }

    @MainActor
    fileprivate func organize(
        chunk: AIOrganizerChunk,
        gameTitle: String
    ) async throws -> OrganizedChunkResponse {
        let model = Self.organizerModel
        guard case .available = model.availability else {
            throw AIOrganizerError.modelUnavailable(model.availability.organizerUnavailableReason)
        }

        let session = LanguageModelSession(model: model, instructions: Self.systemPrompt)
        let response = try await session.respond(
            to: chunkPrompt(chunk: chunk, gameTitle: gameTitle),
            generating: OrganizedChunkResponse.self,
            includeSchemaInPrompt: true,
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0,
                maximumResponseTokens: 1_800
            )
        )
        return response.content
    }

    @MainActor
    private static var organizerModel: SystemLanguageModel {
        SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
    }

    private func chunkPrompt(chunk: AIOrganizerChunk, gameTitle: String) -> String {
        let payload = AIOrganizerChunkPayload(
            gameTitle: gameTitle,
            chapterTitle: chunk.chapterTitle,
            guideSection: chunk.guideSection,
            location: chunk.location,
            sourceEntries: chunk.entries.map(SourceEntryPayload.init(entry:))
        )
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static let systemPrompt = """
    You organize imported JRPG walkthrough rows into a cleaner native reader timeline.
    This is a private on-device transformation of user-imported videogame guide text.
    Be conservative. Do not invent facts, rewards, enemies, directions, quantities, or locations.
    Preserve source order. Split one mixed source row only when it clearly contains separate content types.
    Classify encounter lists as enemy, item/materia/chest/reward lists as loot, bosses as boss, shops as shop, optional quest/minigame actions as sidequest, images as image, maps as map, and uncertain context as note.
    storyStep and sidequest may be task entries. loot, enemy, boss, shop, note, image, and map must be callout entries.
    Every output entry must include at least one sourceEntryIDs value from the input.
    If an input image or map row is useful, preserve it as an image or map callout.
    """
}

private extension Error {
    var shouldStopFoundationOrganizerAttempts: Bool {
        if let generationError = self as? LanguageModelSession.GenerationError {
            switch generationError {
            case .assetsUnavailable:
                return true
            case .exceededContextWindowSize,
                 .guardrailViolation,
                 .unsupportedGuide,
                 .unsupportedLanguageOrLocale,
                 .decodingFailure,
                 .rateLimited,
                 .concurrentRequests,
                 .refusal:
                return false
            @unknown default:
                break
            }
        }

        let message = recursiveErrorDescription.lowercased()
        return message.contains("com.apple.unifiedassetframework")
            || message.contains("com.apple.modelcatalog")
            || message.contains("model catalog error")
            || message.contains("there are no underlying assets")
            || message.contains("failed to fetch model metadata")
            || message.contains("modelmanagerservices.modelmanagererror")
            || message.contains("com.apple.sensitivecontentanalysisml")
            || message.contains("com.apple.fm.language.instruct_300m.safety")
    }

    var foundationModelFallbackMessage: String {
        if case .modelUnavailable(let reason) = self as? AIOrganizerError {
            return "Apple Intelligence is unavailable: \(reason)"
        }

        if shouldStopFoundationOrganizerAttempts {
            return "Apple Intelligence model assets are not installed or not ready."
        }

        return "On-device generation failed."
    }

    var organizerGenerationMessage: String {
        guard let generationError = self as? LanguageModelSession.GenerationError else {
            return (self as? LocalizedError)?.errorDescription ?? localizedDescription
        }

        switch generationError {
        case .exceededContextWindowSize(let context):
            return "the guide section was too large for the on-device model. \(context.debugDescription)"
        case .assetsUnavailable(let context):
            return "Apple Intelligence assets are unavailable. \(context.debugDescription)"
        case .guardrailViolation(let context):
            return "Apple Intelligence guardrails blocked this guide section. \(context.debugDescription)"
        case .unsupportedGuide(let context):
            return "the structured output schema is unsupported. \(context.debugDescription)"
        case .unsupportedLanguageOrLocale(let context):
            return "the current language or locale is unsupported. \(context.debugDescription)"
        case .decodingFailure(let context):
            return "the model returned output that could not be decoded. \(context.debugDescription)"
        case .rateLimited(let context):
            return "the on-device model is rate limited. \(context.debugDescription)"
        case .concurrentRequests(let context):
            return "another on-device model request is already running. \(context.debugDescription)"
        case .refusal(_, let context):
            return "the model refused this guide section. \(context.debugDescription)"
        @unknown default:
            return generationError.localizedDescription
        }
    }

    private var recursiveErrorDescription: String {
        var parts: [String] = [
            localizedDescription,
            String(reflecting: self),
        ]
        appendNSErrorDescriptions(from: self as NSError, to: &parts)
        return parts.joined(separator: " ")
    }

    private func appendNSErrorDescriptions(from error: NSError, to parts: inout [String]) {
        parts.append(error.domain)
        parts.append(error.localizedDescription)

        if let reason = error.localizedFailureReason {
            parts.append(reason)
        }

        if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            appendNSErrorDescriptions(from: underlyingError, to: &parts)
        }

        if let underlyingErrors = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            for underlyingError in underlyingErrors {
                appendNSErrorDescriptions(from: underlyingError, to: &parts)
            }
        }
    }
}

private extension SystemLanguageModel.Availability {
    var organizerUnavailableReason: String {
        switch self {
        case .available:
            "available"
        case .unavailable(let reason):
            reason.organizerMessage
        }
    }
}

private extension SystemLanguageModel.Availability.UnavailableReason {
    var organizerMessage: String {
        switch self {
        case .deviceNotEligible:
            "this device is not eligible for Apple Intelligence."
        case .appleIntelligenceNotEnabled:
            "Apple Intelligence is not enabled."
        case .modelNotReady:
            "the on-device model is not ready yet."
        @unknown default:
            "the on-device model is unavailable."
        }
    }
}

fileprivate struct AIOrganizerChunk: Sendable {
    let chapterTitle: String
    let guideSection: String
    let location: String
    let entries: [AIOrganizerSourceEntry]

    func split() -> [AIOrganizerChunk] {
        guard entries.count > 1 else { return [self] }
        let midpoint = max(entries.count / 2, 1)
        return [
            replacingEntries(Array(entries[..<midpoint])),
            replacingEntries(Array(entries[midpoint...])),
        ].filter { !$0.entries.isEmpty }
    }

    private func replacingEntries(_ entries: [AIOrganizerSourceEntry]) -> AIOrganizerChunk {
        AIOrganizerChunk(
            chapterTitle: chapterTitle,
            guideSection: guideSection,
            location: location,
            entries: entries
        )
    }

    static func makeChunks(from entries: [AIOrganizerSourceEntry]) -> [AIOrganizerChunk] {
        var chunks: [AIOrganizerChunk] = []
        var activeEntries: [AIOrganizerSourceEntry] = []
        var activeChapter = ""
        var activeSection = ""
        var activeLocation = ""
        var activeCharacterCount = 0

        func finishActiveChunk() {
            guard !activeEntries.isEmpty else { return }
            chunks.append(
                AIOrganizerChunk(
                    chapterTitle: activeChapter,
                    guideSection: activeSection,
                    location: activeLocation,
                    entries: activeEntries
                )
            )
            activeEntries.removeAll(keepingCapacity: true)
            activeCharacterCount = 0
        }

        for entry in entries {
            let locationChanged = !activeEntries.isEmpty
                && (entry.chapterTitle != activeChapter || entry.guideSection != activeSection || entry.location != activeLocation)
            let nextCharacterCount = activeCharacterCount + entry.title.count + entry.body.count
            if locationChanged || activeEntries.count >= 8 || nextCharacterCount > 2_200 {
                finishActiveChunk()
            }

            if activeEntries.isEmpty {
                activeChapter = entry.chapterTitle
                activeSection = entry.guideSection
                activeLocation = entry.location
            }

            activeEntries.append(entry)
            activeCharacterCount += entry.title.count + entry.body.count
        }

        finishActiveChunk()
        return chunks
    }
}

private struct AIOrganizerChunkPayload: Encodable {
    let gameTitle: String
    let chapterTitle: String
    let guideSection: String
    let location: String
    let sourceEntries: [SourceEntryPayload]
}

private struct SourceEntryPayload: Encodable {
    let id: String
    let sortOrder: Int
    let entryKind: String
    let mode: String
    let calloutKind: String?
    let title: String
    let body: String
    let imageURL: String?
    let imageCaption: String?

    init(entry: AIOrganizerSourceEntry) {
        id = entry.id.uuidString
        sortOrder = entry.sortOrder
        entryKind = entry.entryKind.rawValue
        mode = entry.mode.rawValue
        calloutKind = entry.calloutKind?.rawValue
        title = entry.title
        body = entry.body
        imageURL = entry.imageURL
        imageCaption = entry.imageCaption
    }
}

@Generable(description: "A conservative organization of one imported walkthrough chunk.")
struct OrganizedChunkResponse: Sendable {
    @Guide(description: "Organized reader rows, in source order.", .maximumCount(16))
    let entries: [OrganizedChunkEntry]
}

@Generable(description: "One organized reader row derived only from provided source rows.")
struct OrganizedChunkEntry: Sendable {
    @Guide(description: "Either task or callout.", .anyOf(["task", "callout"]))
    let entryKind: String

    @Guide(description: "One of storyStep, loot, enemy, boss, shop, sidequest, note, image, or map.", .anyOf(["storyStep", "loot", "enemy", "boss", "shop", "sidequest", "note", "image", "map"]))
    let contentKind: String

    @Guide(description: "Short label for the row.")
    let title: String

    @Guide(description: "Reader text for the row. Do not invent facts.")
    let body: String

    @Guide(description: "UUID strings of the input source rows used for this output row.", .minimumCount(1), .maximumCount(8))
    let sourceEntryIDs: [String]
}
