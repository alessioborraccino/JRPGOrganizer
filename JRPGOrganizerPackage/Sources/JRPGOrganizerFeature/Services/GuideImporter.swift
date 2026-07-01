import Foundation
import Observation
import SwiftData
import SwiftSoup

public enum ImportError: LocalizedError {
    case invalidRootURL
    case blockedBySource
    case badHTTPStatus(Int)
    case noContentContainer(URL)
    case noGuidePagesFound
    case invalidResponseEncoding(URL)

    public var errorDescription: String? {
        switch self {
        case .invalidRootURL:
            "The guide URL is invalid."
        case .blockedBySource:
            "Neoseeker returned a browser challenge. Retry later from a normal connection."
        case .badHTTPStatus(let statusCode):
            "Neoseeker returned HTTP \(statusCode)."
        case .noContentContainer(let url):
            "Could not find the guide content on \(url.absoluteString)."
        case .noGuidePagesFound:
            "Could not find any importable guide pages."
        case .invalidResponseEncoding(let url):
            "Could not read the response from \(url.absoluteString)."
        }
    }
}

public enum GuideImportKind: String, Codable, Sendable {
    case dragonQuestXIWalkthrough
    case neoseekerFAQWalkthrough
}

public struct GuideDefinition: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let rootURLString: String
    public let sourceDescription: String
    public let importKind: GuideImportKind
    public let systemImage: String

    public init(
        id: String,
        title: String,
        rootURLString: String,
        sourceDescription: String,
        importKind: GuideImportKind,
        systemImage: String
    ) {
        self.id = id
        self.title = title
        self.rootURLString = rootURLString
        self.sourceDescription = sourceDescription
        self.importKind = importKind
        self.systemImage = systemImage
    }

    public static let dragonQuestXI = GuideDefinition(
        id: "dragon-quest-xi",
        title: "Dragon Quest XI: Echoes of an Elusive Age",
        rootURLString: "https://www.neoseeker.com/dragon-quest-xi/walkthrough",
        sourceDescription: "Neoseeker walkthrough",
        importKind: .dragonQuestXIWalkthrough,
        systemImage: "sparkles"
    )

    public static let finalFantasyVII = GuideDefinition(
        id: "final-fantasy-vii",
        title: "Final Fantasy VII",
        rootURLString: "https://www.neoseeker.com/final-fantasy-vii/faqs/2706754-q.html",
        sourceDescription: "Neoseeker FAQ/Walkthrough",
        importKind: .neoseekerFAQWalkthrough,
        systemImage: "7.circle"
    )

    public static let all: [GuideDefinition] = [
        .dragonQuestXI,
        .finalFantasyVII,
    ]

    public var supportsReaderOrganization: Bool {
        importKind == .neoseekerFAQWalkthrough
    }
}

public struct GuidePage: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let guideSection: String
    public let title: String
    public let url: URL
}

@MainActor
@Observable
public final class GuideImporter {
    public private(set) var isImporting = false
    public private(set) var importingGuideID: String?
    public private(set) var statusMessage: String?
    public private(set) var errorMessage: String?
    public private(set) var importedPageCount = 0
    public private(set) var totalPageCount = 0

    public var importProgress: Double {
        guard totalPageCount > 0 else { return 0 }
        return min(Double(importedPageCount) / Double(totalPageCount), 1)
    }

    private let fetcher: GuideFetcher
    private let rootParser: GuideRootParser
    private let chapterParser: GuideChapterParser

    public init(
        fetcher: GuideFetcher = GuideFetcher(),
        rootParser: GuideRootParser = GuideRootParser(),
        chapterParser: GuideChapterParser = GuideChapterParser()
    ) {
        self.fetcher = fetcher
        self.rootParser = rootParser
        self.chapterParser = chapterParser
    }

    public func isImporting(_ guide: GuideDefinition) -> Bool {
        isImporting && importingGuideID == guide.id
    }

    public func importGuide(_ guide: GuideDefinition, into modelContext: ModelContext) async {
        guard !isImporting else { return }

        isImporting = true
        importingGuideID = guide.id
        errorMessage = nil
        statusMessage = "Preparing \(guide.title)..."
        importedPageCount = 0
        totalPageCount = 0

        do {
            let progress = try existingProgress(for: guide, in: modelContext)
            let game = try await buildSavedGame(for: guide, applying: progress)
            try removeExistingGame(for: guide, in: modelContext)
            modelContext.insert(game)
            try modelContext.save()
            statusMessage = "Imported \(game.totalTaskCount) checklist steps."
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            statusMessage = nil
        }

        isImporting = false
        importingGuideID = nil
    }

    public func clearError() {
        errorMessage = nil
    }

    private func buildSavedGame(
        for guide: GuideDefinition,
        applying progress: GuideProgressSnapshot
    ) async throws -> SavedGame {
        switch guide.importKind {
        case .dragonQuestXIWalkthrough:
            try await buildDragonQuestXIGuide(for: guide, applying: progress)
        case .neoseekerFAQWalkthrough:
            try await buildFAQGuide(for: guide, applying: progress)
        }
    }

    private func buildDragonQuestXIGuide(
        for guide: GuideDefinition,
        applying progress: GuideProgressSnapshot
    ) async throws -> SavedGame {
        guard let rootURL = URL(string: guide.rootURLString) else {
            throw ImportError.invalidRootURL
        }

        let rootHTML = try await fetcher.fetchHTML(from: rootURL)
        let pages = try rootParser.parseChronologicalPages(html: rootHTML, rootURL: rootURL)
        let mediaPages = try rootParser.parseMapPages(html: rootHTML, rootURL: rootURL)
        guard !pages.isEmpty else { throw ImportError.noGuidePagesFound }

        totalPageCount = pages.count + mediaPages.count

        let game = SavedGame(
            title: guide.title,
            rootURL: guide.rootURLString,
            dateDownloaded: .now
        )

        var sortOrder = 0
        var stepNumber = 1
        var importedCount = 0

        for (index, page) in pages.enumerated() {
            try Task.checkCancellation()
            importedPageCount = importedCount
            statusMessage = "Downloading Chapter \(index + 1) of \(pages.count)..."

            let html = try await fetcher.fetchHTMLWithRetry(from: page.url)
            let parsedEntries = try chapterParser.parseWikiPage(
                html: html,
                page: page,
                startingSortOrder: sortOrder,
                startingStepNumber: stepNumber
            )

            append(parsedEntries, to: game)
            sortOrder += parsedEntries.count
            stepNumber += parsedEntries.filter { $0.entryKind == .task }.count
            importedCount += 1
            importedPageCount = importedCount

            if index < pages.indices.last ?? 0 {
                try await Task.sleep(for: .milliseconds(350))
            }
        }

        for (index, page) in mediaPages.enumerated() {
            try Task.checkCancellation()
            importedPageCount = importedCount
            statusMessage = "Downloading Maps \(index + 1) of \(mediaPages.count)..."

            let html = try await fetcher.fetchHTMLWithRetry(from: page.url)
            let parsedEntries = try chapterParser.parseImagesOnly(
                html: html,
                page: page,
                startingSortOrder: sortOrder,
                defaultKind: .map
            )

            append(parsedEntries, to: game)
            sortOrder += parsedEntries.count
            importedCount += 1
            importedPageCount = importedCount

            if index < mediaPages.indices.last ?? 0 {
                try await Task.sleep(for: .milliseconds(250))
            }
        }

        apply(progress, to: game)
        return game
    }

    private func buildFAQGuide(
        for guide: GuideDefinition,
        applying progress: GuideProgressSnapshot
    ) async throws -> SavedGame {
        guard let rootURL = URL(string: guide.rootURLString) else {
            throw ImportError.invalidRootURL
        }

        totalPageCount = 1
        importedPageCount = 0
        statusMessage = "Downloading Guide 1 of 1..."

        let html = try await fetcher.fetchHTMLWithRetry(from: rootURL)
        let page = GuidePage(
            guideSection: "Original FAQ/Walkthrough",
            title: "Final Fantasy VII FAQ/Walkthrough",
            url: rootURL
        )
        let parsedEntries = try chapterParser.parseFAQPage(
            html: html,
            page: page,
            startingSortOrder: 0,
            startingStepNumber: 1
        )
        guard !parsedEntries.isEmpty else { throw ImportError.noGuidePagesFound }

        let game = SavedGame(
            title: guide.title,
            rootURL: guide.rootURLString,
            dateDownloaded: .now
        )
        append(parsedEntries, to: game)
        apply(progress, to: game)
        importedPageCount = 1
        return game
    }

    private func append(_ entries: [WalkthroughEntry], to game: SavedGame) {
        for entry in entries {
            entry.game = game
            game.entries.append(entry)
        }
    }

    private func existingProgress(
        for guide: GuideDefinition,
        in modelContext: ModelContext
    ) throws -> GuideProgressSnapshot {
        let rootURLString = guide.rootURLString
        let descriptor = FetchDescriptor<SavedGame>(
            predicate: #Predicate { game in
                game.rootURL == rootURLString
            }
        )
        let existingGames = try modelContext.fetch(descriptor)
        let completedSignatures = existingGames
            .flatMap { game in
                Array(game.completedTaskSignatures(for: .raw))
            }

        return GuideProgressSnapshot(
            completedTaskSignatures: Set(completedSignatures),
            lastViewedSortOrder: existingGames.first?.lastViewedSortOrder,
            lastViewedEntrySignature: existingGames.first?.lastViewedEntrySignature
        )
    }

    private func apply(_ progress: GuideProgressSnapshot, to game: SavedGame) {
        for entry in game.entries where entry.entryKind == .task {
            entry.isCompleted = progress.completedTaskSignatures.contains(entry.progressSignature)
        }

        if let lastViewedEntrySignature = progress.lastViewedEntrySignature,
           let matchingEntry = game.sortedEntries.first(where: { $0.progressSignature == lastViewedEntrySignature }) {
            game.lastViewedSortOrder = matchingEntry.sortOrder
            game.lastViewedEntrySignature = lastViewedEntrySignature
        } else {
            game.lastViewedSortOrder = progress.lastViewedSortOrder
            game.lastViewedEntrySignature = progress.lastViewedEntrySignature
        }

        game.refreshCachedProgressCounts()
    }

    private func removeExistingGame(for guide: GuideDefinition, in modelContext: ModelContext) throws {
        let rootURLString = guide.rootURLString
        let descriptor = FetchDescriptor<SavedGame>(
            predicate: #Predicate { game in
                game.rootURL == rootURLString
            }
        )
        let existingGames = try modelContext.fetch(descriptor)
        for existingGame in existingGames {
            modelContext.delete(existingGame)
        }
    }
}

private struct GuideProgressSnapshot {
    let completedTaskSignatures: Set<String>
    let lastViewedSortOrder: Int?
    let lastViewedEntrySignature: String?
}

public struct GuideFetcher: Sendable {
    public init() {}

    public func fetchHTMLWithRetry(from url: URL, maxAttempts: Int = 3) async throws -> String {
        var lastError: Error?

        for attempt in 0..<maxAttempts {
            do {
                return try await fetchHTML(from: url)
            } catch {
                lastError = error
                guard attempt < maxAttempts - 1 else { break }
                let delay = UInt64(pow(2.0, Double(attempt))) * 500_000_000
                try await Task.sleep(nanoseconds: delay)
            }
        }

        throw lastError ?? ImportError.invalidResponseEncoding(url)
    }

    public func fetchHTML(from url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 403 {
                throw ImportError.blockedBySource
            }
            throw ImportError.badHTTPStatus(httpResponse.statusCode)
        }

        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.invalidResponseEncoding(url)
        }

        if html.localizedCaseInsensitiveContains("Just a moment...")
            && html.localizedCaseInsensitiveContains("Cloudflare") {
            throw ImportError.blockedBySource
        }

        return html
    }
}

public struct GuideRootParser: Sendable {
    private let chronologicalSections: [String] = [
        "Walkthrough Act 1",
        "Interludes: Definitive Edition",
        "Walkthrough Act 2",
        "Walkthrough Act 3",
        "Definitive Edition Bonus Content",
    ]

    public init() {}

    public func parseChronologicalPages(html: String, rootURL: URL) throws -> [GuidePage] {
        let document = try SwiftSoup.parse(html, rootURL.absoluteString)
        let content = try wikiContent(in: document, url: rootURL)

        var currentSection: String?
        var pages: [GuidePage] = []
        var seenURLs = Set<URL>()

        for element in content.children().array() {
            let tag = element.tagName().lowercased()
            let text = normalizedText(element)

            if tag == "p", let heading = sectionHeading(matching: text) {
                currentSection = heading
                continue
            }

            if tag == "p", isSectionBreak(text) {
                currentSection = nil
                continue
            }

            guard tag == "ul", let currentSection else { continue }

            let links = try element.select("a[href]").array()
            for link in links {
                let title = normalizedText(link)
                let href = try link.attr("abs:href")
                guard !title.isEmpty,
                      let url = URL(string: href),
                      !seenURLs.contains(url),
                      chronologicalSections.contains(currentSection) else {
                    continue
                }

                seenURLs.insert(url)
                pages.append(GuidePage(guideSection: currentSection, title: title, url: url))
            }
        }

        return pages
    }

    public func parseMapPages(html: String, rootURL: URL) throws -> [GuidePage] {
        let document = try SwiftSoup.parse(html, rootURL.absoluteString)
        let content = try wikiContent(in: document, url: rootURL)

        var isReferenceSection = false
        var pages: [GuidePage] = []
        var seenURLs = Set<URL>()

        for element in content.children().array() {
            let tag = element.tagName().lowercased()
            let text = normalizedText(element)

            if tag == "p" {
                if text == "Reference/Compendium Pages" || text == "Reference/Compendium Pages:" {
                    isReferenceSection = true
                    continue
                }
                if isSectionBreak(text), !text.localizedCaseInsensitiveContains("Reference/Compendium") {
                    isReferenceSection = false
                    continue
                }
            }

            guard isReferenceSection, tag == "ul" else { continue }

            let links = try element.select("a[href]").array()
            for link in links {
                let title = normalizedText(link)
                let href = try link.attr("abs:href")
                guard title.localizedCaseInsensitiveContains("Maps"),
                      let url = URL(string: href),
                      !seenURLs.contains(url) else {
                    continue
                }

                seenURLs.insert(url)
                pages.append(GuidePage(guideSection: "Reference Maps", title: title, url: url))
            }
        }

        return pages
    }

    private func sectionHeading(matching text: String) -> String? {
        chronologicalSections.first { section in
            text == section || text == "\(section):"
        }
    }

    private func isSectionBreak(_ text: String) -> Bool {
        if text == "Reference/Compendium Pages" || text == "Reference/Compendium Pages:" {
            return true
        }
        return text.count < 120 && text.hasSuffix(":")
    }
}

public struct GuideChapterParser: Sendable {
    private let faqSections: Set<String> = [
        "Walkthrough - Disc 1",
        "Walkthrough - Disc 2",
        "Walkthrough - Disc 3",
        "Missable Items Walkthrough",
        "Sidequests/Mini-Games",
    ]

    public init() {}

    public func parseWikiPage(
        html: String,
        page: GuidePage,
        startingSortOrder: Int,
        startingStepNumber: Int
    ) throws -> [WalkthroughEntry] {
        let document = try SwiftSoup.parse(html, page.url.absoluteString)
        let content = try wikiContent(in: document, url: page.url)

        var entries: [WalkthroughEntry] = []
        var currentLocation = page.title
        var sortOrder = startingSortOrder
        var stepNumber = startingStepNumber
        var seenImageURLs = Set<String>()

        for element in content.children().array() {
            let tag = element.tagName().lowercased()
            let className = (try? element.className()) ?? ""
            let text = normalizedText(element)

            if tag == "h2" || tag == "h3" {
                currentLocation = text
                continue
            }

            appendImageEntries(
                from: element,
                page: page,
                currentLocation: currentLocation,
                defaultKind: nil,
                entries: &entries,
                sortOrder: &sortOrder,
                seenImageURLs: &seenImageURLs
            )

            if shouldSkip(tag: tag, className: className, text: text) {
                continue
            }

            if let calloutKind = calloutKind(tag: tag, className: className, text: text) {
                appendCalloutEntries(
                    from: element,
                    calloutKind: calloutKind,
                    chapterTitle: page.title,
                    guideSection: page.guideSection,
                    sourceURL: page.url.absoluteString,
                    location: currentLocation,
                    entries: &entries,
                    sortOrder: &sortOrder
                )
                continue
            }

            if tag == "p" {
                let body = sourceBodyText(from: element)
                guard body.count > 15 else { continue }
                let mode = mode(forTaskText: text)
                entries.append(
                    WalkthroughEntry(
                        sortOrder: sortOrder,
                        stepNumber: stepNumber,
                        chapterTitle: page.title,
                        guideSection: page.guideSection,
                        sourceURL: page.url.absoluteString,
                        location: currentLocation,
                        entryKind: .task,
                        mode: mode,
                        title: taskTitle(for: mode),
                        body: body
                    )
                )
                sortOrder += 1
                stepNumber += 1
                continue
            }

            if tag == "ul" || tag == "ol" {
                appendListTasks(
                    from: element,
                    page: page,
                    guideSection: page.guideSection,
                    currentLocation: currentLocation,
                    chapterTitle: nil,
                    entries: &entries,
                    sortOrder: &sortOrder,
                    stepNumber: &stepNumber
                )
            }
        }

        return entries
    }

    public func parseImagesOnly(
        html: String,
        page: GuidePage,
        startingSortOrder: Int,
        defaultKind: WalkthroughCalloutKind
    ) throws -> [WalkthroughEntry] {
        let document = try SwiftSoup.parse(html, page.url.absoluteString)
        let content = try wikiContent(in: document, url: page.url)

        var entries: [WalkthroughEntry] = []
        var currentLocation = page.title
        var sortOrder = startingSortOrder
        var seenImageURLs = Set<String>()

        for element in content.children().array() {
            let tag = element.tagName().lowercased()
            let text = normalizedText(element)

            if (tag == "h2" || tag == "h3" || tag == "h4"), !text.isEmpty {
                currentLocation = text
                continue
            }

            appendImageEntries(
                from: element,
                page: page,
                currentLocation: currentLocation,
                defaultKind: defaultKind,
                entries: &entries,
                sortOrder: &sortOrder,
                seenImageURLs: &seenImageURLs
            )
        }

        return entries
    }

    public func parseFAQPage(
        html: String,
        page: GuidePage,
        startingSortOrder: Int,
        startingStepNumber: Int
    ) throws -> [WalkthroughEntry] {
        let document = try SwiftSoup.parse(html, page.url.absoluteString)
        guard let content = try document.select("#markupfaq #faqtxt").first() else {
            throw ImportError.noContentContainer(page.url)
        }

        var entries: [WalkthroughEntry] = []
        var activeGuideSection: String?
        var currentLocation = page.title
        var sortOrder = startingSortOrder
        var stepNumber = startingStepNumber
        var seenImageURLs = Set<String>()

        for element in content.children().array() {
            let tag = element.tagName().lowercased()
            let className = (try? element.className()) ?? ""
            let text = normalizedText(element)

            if tag == "h2" {
                if faqSections.contains(text) {
                    activeGuideSection = text
                    currentLocation = text
                } else if activeGuideSection != nil {
                    activeGuideSection = nil
                }
                continue
            }

            guard let activeGuideSection else { continue }

            if tag == "h3" || tag == "h4" {
                currentLocation = text
                continue
            }

            let pageForActiveSection = GuidePage(
                guideSection: activeGuideSection,
                title: page.title,
                url: page.url
            )

            appendImageEntries(
                from: element,
                page: pageForActiveSection,
                currentLocation: currentLocation,
                defaultKind: nil,
                entries: &entries,
                sortOrder: &sortOrder,
                seenImageURLs: &seenImageURLs
            )

            if shouldSkip(tag: tag, className: className, text: text) {
                continue
            }

            if let calloutKind = calloutKind(tag: tag, className: className, text: text) {
                appendCalloutEntries(
                    from: element,
                    calloutKind: calloutKind,
                    chapterTitle: faqChapterTitle(
                        page: page,
                        activeGuideSection: activeGuideSection,
                        currentLocation: currentLocation
                    ),
                    guideSection: activeGuideSection,
                    sourceURL: page.url.absoluteString,
                    location: currentLocation,
                    modeGuideSection: activeGuideSection,
                    entries: &entries,
                    sortOrder: &sortOrder
                )
                continue
            }

            if tag == "p" || tag == "pre" {
                let body = sourceBodyText(from: element)
                let classificationText = normalizedText(element)
                guard body.count > 15 else { continue }
                let mode = mode(forFAQTaskText: classificationText, guideSection: activeGuideSection)
                entries.append(
                    WalkthroughEntry(
                        sortOrder: sortOrder,
                        stepNumber: stepNumber,
                        chapterTitle: faqChapterTitle(
                            page: page,
                            activeGuideSection: activeGuideSection,
                            currentLocation: currentLocation
                        ),
                        guideSection: activeGuideSection,
                        sourceURL: page.url.absoluteString,
                        location: currentLocation,
                        entryKind: .task,
                        mode: mode,
                        title: taskTitle(for: mode),
                        body: body
                    )
                )
                sortOrder += 1
                stepNumber += 1
                continue
            }

            if tag == "ul" || tag == "ol" {
                appendListTasks(
                    from: element,
                    page: page,
                    guideSection: activeGuideSection,
                    currentLocation: currentLocation,
                    chapterTitle: faqChapterTitle(
                        page: page,
                        activeGuideSection: activeGuideSection,
                        currentLocation: currentLocation
                    ),
                    entries: &entries,
                    sortOrder: &sortOrder,
                    stepNumber: &stepNumber
                )
            }
        }

        return entries
    }

    private func appendListTasks(
        from element: Element,
        page: GuidePage,
        guideSection: String,
        currentLocation: String,
        chapterTitle: String?,
        entries: inout [WalkthroughEntry],
        sortOrder: inout Int,
        stepNumber: inout Int
    ) {
        let items = element.children().array().filter { $0.tagName().lowercased() == "li" }
        for item in items {
            let itemText = sourceBodyText(from: item)
            guard itemText.count > 10 else { continue }
            let mode = mode(forFAQTaskText: itemText, guideSection: guideSection)
            entries.append(
                WalkthroughEntry(
                    sortOrder: sortOrder,
                    stepNumber: stepNumber,
                    chapterTitle: chapterTitle ?? page.title,
                    guideSection: guideSection,
                    sourceURL: page.url.absoluteString,
                    location: currentLocation,
                    entryKind: .task,
                    mode: mode,
                    title: taskTitle(for: mode),
                    body: itemText
                )
            )
            sortOrder += 1
            stepNumber += 1
        }
    }

    private func faqChapterTitle(
        page: GuidePage,
        activeGuideSection: String,
        currentLocation: String
    ) -> String {
        let location = currentLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !location.isEmpty, location != activeGuideSection {
            return location
        }
        return activeGuideSection.isEmpty ? page.title : activeGuideSection
    }

    private func appendImageEntries(
        from element: Element,
        page: GuidePage,
        currentLocation: String,
        defaultKind: WalkthroughCalloutKind?,
        entries: inout [WalkthroughEntry],
        sortOrder: inout Int,
        seenImageURLs: inout Set<String>
    ) {
        let images = (try? element.select("img[src], img[data-src]").array()) ?? []
        for image in images {
            guard let imageURL = guideImageURL(from: image, baseURL: page.url),
                  !seenImageURLs.contains(imageURL),
                  isGuideImageURL(imageURL, image: image) else {
                continue
            }

            seenImageURLs.insert(imageURL)
            let title = imageTitle(for: image, imageURL: imageURL)
            let caption = imageCaption(for: image, fallbackTitle: title)
            let kind = defaultKind ?? imageKind(for: title, page: page, currentLocation: currentLocation)
            entries.append(
                WalkthroughEntry(
                    sortOrder: sortOrder,
                    chapterTitle: page.title,
                    guideSection: page.guideSection,
                    sourceURL: page.url.absoluteString,
                    location: currentLocation,
                    entryKind: .callout,
                    mode: mode(for: kind),
                    calloutKind: kind,
                    title: title,
                    body: caption,
                    imageURL: imageURL,
                    imageCaption: caption
                )
            )
            sortOrder += 1
        }
    }

    private func appendCalloutEntries(
        from element: Element,
        calloutKind: WalkthroughCalloutKind,
        chapterTitle: String,
        guideSection: String,
        sourceURL: String,
        location: String,
        modeGuideSection: String? = nil,
        entries: inout [WalkthroughEntry],
        sortOrder: inout Int
    ) {
        let content = calloutContent(from: element, fallbackTitle: calloutKind.label)
        entries.append(
            WalkthroughEntry(
                sortOrder: sortOrder,
                chapterTitle: chapterTitle,
                guideSection: guideSection,
                sourceURL: sourceURL,
                location: location,
                entryKind: .callout,
                mode: mode(for: calloutKind, guideSection: modeGuideSection),
                calloutKind: calloutKind,
                title: content.title,
                body: content.body
            )
        )
        sortOrder += 1

        appendNestedCalloutEntries(
            in: element,
            chapterTitle: chapterTitle,
            guideSection: guideSection,
            sourceURL: sourceURL,
            location: location,
            modeGuideSection: modeGuideSection,
            entries: &entries,
            sortOrder: &sortOrder
        )
    }

    private func appendNestedCalloutEntries(
        in element: Element,
        chapterTitle: String,
        guideSection: String,
        sourceURL: String,
        location: String,
        modeGuideSection: String?,
        entries: inout [WalkthroughEntry],
        sortOrder: inout Int
    ) {
        for child in element.children().array() {
            let tag = child.tagName().lowercased()
            let className = (try? child.className()) ?? ""
            let text = normalizedText(child)

            if shouldSkip(tag: tag, className: className, text: text) {
                continue
            }

            if let nestedKind = calloutKind(tag: tag, className: className, text: text) {
                if isSourceTableContainer(tag: tag, className: className) {
                    appendNestedCalloutEntries(
                        in: child,
                        chapterTitle: chapterTitle,
                        guideSection: guideSection,
                        sourceURL: sourceURL,
                        location: location,
                        modeGuideSection: modeGuideSection,
                        entries: &entries,
                        sortOrder: &sortOrder
                    )
                    continue
                }

                appendCalloutEntries(
                    from: child,
                    calloutKind: nestedKind,
                    chapterTitle: chapterTitle,
                    guideSection: guideSection,
                    sourceURL: sourceURL,
                    location: location,
                    modeGuideSection: modeGuideSection,
                    entries: &entries,
                    sortOrder: &sortOrder
                )
                continue
            }

            appendNestedCalloutEntries(
                in: child,
                chapterTitle: chapterTitle,
                guideSection: guideSection,
                sourceURL: sourceURL,
                location: location,
                modeGuideSection: modeGuideSection,
                entries: &entries,
                sortOrder: &sortOrder
            )
        }
    }

    private func shouldSkip(tag: String, className: String, text: String) -> Bool {
        if text.isEmpty { return true }
        if className.contains("section-vu") || className.contains("jsad") || className.contains("Mobile_inline") {
            return true
        }
        if text.localizedCaseInsensitiveContains("rdSmartLoad")
            || text.localizedCaseInsensitiveContains("relevantDigital")
            || text.localizedCaseInsensitiveContains("Advertisement") {
            return true
        }
        if tag == "hr" || tag == "center" {
            return true
        }
        return false
    }

    private func calloutKind(tag: String, className: String, text: String) -> WalkthroughCalloutKind? {
        let lowercaseText = text.lowercased()
        if className.contains("spoiler_header"), text != "Spoiler: null" {
            return .sourceSpoiler
        }
        if className.contains("alert-warning") {
            return .warning
        }
        if className.contains("alert-primary") {
            return .important
        }
        if className.contains("alert-success") {
            return .tip
        }
        if className.contains("alert-error") {
            return .battle
        }
        if className.contains("alert-secondary") {
            return .version
        }
        if className.contains("section-info") {
            return sectionInfoKind(for: text)
        }
        if className.contains("section_box") {
            if lowercaseText.contains("boss:") || lowercaseText.hasPrefix("boss") {
                return .battle
            }
            if lowercaseText.contains("missable") {
                return .warning
            }
            if containsCompletionKeyword(lowercaseText) {
                return .loot
            }
            return .reference
        }
        if className.contains("table-wrapper") {
            let containsItems = lowercaseText.contains("items") || lowercaseText.contains("materia")
            let containsEnemies = lowercaseText.contains("enemies")

            if containsItems && containsEnemies {
                return .reference
            }
            if containsEnemies {
                return .enemy
            }
            if containsCompletionKeyword(lowercaseText) || containsItems {
                return .loot
            }
            return .reference
        }
        if tag == "table" || className.contains("wikitable") {
            return sectionInfoKind(for: text)
        }
        return nil
    }

    private func sectionInfoKind(for text: String) -> WalkthroughCalloutKind {
        let lowercaseText = text.lowercased()
        if lowercaseText.hasPrefix("enemies to encounter") || lowercaseText.hasPrefix("enemies") {
            return .enemy
        }
        if lowercaseText.hasPrefix("item shop")
            || lowercaseText.hasPrefix("weapon shop")
            || lowercaseText.hasPrefix("armour shop")
            || lowercaseText.hasPrefix("armor shop")
            || lowercaseText.hasPrefix("roving emporium") {
            return .shop
        }
        if lowercaseText.hasPrefix("available quests") {
            return .quest
        }
        if containsCompletionKeyword(lowercaseText) {
            return .loot
        }
        return .reference
    }

    private func mode(for calloutKind: WalkthroughCalloutKind, guideSection: String? = nil) -> WalkthroughEntryMode {
        if let guideSection, guideSection.localizedCaseInsensitiveContains("Missable") {
            return .completion
        }

        switch calloutKind {
        case .loot, .shop, .quest:
            return .completion
        case .enemy, .reference, .image, .map:
            return .reference
        case .important, .tip, .battle, .version, .warning, .sourceSpoiler:
            return .walkthrough
        }
    }

    private func mode(forTaskText text: String) -> WalkthroughEntryMode {
        containsCompletionKeyword(text.lowercased()) ? .completion : .walkthrough
    }

    private func mode(forFAQTaskText text: String, guideSection: String) -> WalkthroughEntryMode {
        if guideSection.localizedCaseInsensitiveContains("Missable")
            || guideSection.localizedCaseInsensitiveContains("Sidequests") {
            return .completion
        }
        return mode(forTaskText: text)
    }

    private func taskTitle(for mode: WalkthroughEntryMode) -> String {
        switch mode {
        case .walkthrough:
            "Story Step"
        case .completion:
            "Completion"
        case .reference:
            "Reference"
        }
    }

    private func splitCalloutText(
        _ text: String,
        fallbackTitle: String
    ) -> (title: String, body: String) {
        let delimiters = [":", "."]
        for delimiter in delimiters {
            guard let range = text.range(of: delimiter) else { continue }
            let title = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if title.count >= 3, title.count <= 80, !body.isEmpty {
                return (title, body)
            }
        }
        return (fallbackTitle, text)
    }

    private func calloutContent(
        from element: Element,
        fallbackTitle: String
    ) -> (title: String, body: String) {
        let flattenedText = normalizedText(element)
        let splitContent = splitCalloutText(flattenedText, fallbackTitle: fallbackTitle)
        let title = structuredCalloutTitle(in: element) ?? splitContent.title

        let bodyParagraphs = calloutBodyParagraphs(in: element, title: title)
        let body = bodyParagraphs.joined(separator: "\n\n")
        let fallbackBody = stripTitlePrefix(from: splitContent.body, title: title)
        let cleanedBody = body.isEmpty ? fallbackBody : body

        return (
            title: title,
            body: cleanedBody.isEmpty ? flattenedText : cleanedBody
        )
    }

    private func structuredCalloutTitle(in element: Element) -> String? {
        for child in element.children().array() {
            if !isTitleCandidateInsideNestedCallout(child, root: element),
               let title = directTitleCandidate(from: child) {
                return title
            }
        }

        let selectors = [
            ".section-title",
            ".section-header",
            ".section_heading",
            ".section-info-title",
            ".alert-heading",
            "h1",
            "h2",
            "h3",
            "h4",
            "h5",
            "h6",
            "legend",
            "dt",
            "strong",
            "b",
        ]

        for selector in selectors {
            let candidates = (try? element.select(selector).array()) ?? []
            for candidate in candidates {
                guard !isTitleCandidateInsideNestedCallout(candidate, root: element),
                      !isTitleCandidateInsideTable(candidate, root: element),
                      let title = cleanCalloutTitle(normalizedText(candidate)) else {
                    continue
                }
                return title
            }
        }

        return nil
    }

    private func isTitleCandidateInsideNestedCallout(_ candidate: Element, root: Element) -> Bool {
        for ancestor in candidate.parents().array() {
            if ancestor === root {
                return false
            }
            if isCalloutElement(ancestor) {
                return true
            }
        }
        return false
    }

    private func isTitleCandidateInsideTable(_ candidate: Element, root: Element) -> Bool {
        for ancestor in candidate.parents().array() {
            if ancestor.tagName().lowercased() == "table" {
                return true
            }
            if ancestor === root {
                return false
            }
        }
        return false
    }

    private func directTitleCandidate(from element: Element) -> String? {
        let tag = element.tagName().lowercased()
        let className = ((try? element.className()) ?? "").lowercased()
        let isTitleTag = ["h1", "h2", "h3", "h4", "h5", "h6", "legend", "dt", "strong", "b"].contains(tag)
        let isTitleClass = className.contains("section-title")
            || className.contains("section-header")
            || className.contains("section_heading")
            || className.contains("section-info-title")
            || className.contains("alert-heading")
        guard isTitleTag || isTitleClass else { return nil }
        return cleanCalloutTitle(normalizedText(element))
    }

    private func cleanCalloutTitle(_ rawTitle: String) -> String? {
        let title = rawTitle
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":.-–— "))

        guard title.count >= 2, title.count <= 90 else { return nil }
        let sentenceTerminators = CharacterSet(charactersIn: ".!?")
        if title.rangeOfCharacter(from: sentenceTerminators) != nil, title.count > 36 {
            return nil
        }
        return title
    }

    private func calloutBodyParagraphs(in element: Element, title: String) -> [String] {
        var paragraphs: [String] = []

        let ownText = stripTitlePrefix(from: normalizedOwnText(element), title: title)
        if !ownText.isEmpty {
            paragraphs.append(ownText)
        }

        for child in element.children().array() {
            appendReadableCalloutBlocks(
                from: child,
                title: title,
                paragraphs: &paragraphs
            )
        }

        if paragraphs.isEmpty {
            let fallback = stripTitlePrefix(from: normalizedText(element), title: title)
            if !fallback.isEmpty {
                paragraphs.append(fallback)
            }
        }

        return paragraphs.removingAdjacentDuplicates()
    }

    private func appendReadableCalloutBlocks(
        from element: Element,
        title: String,
        paragraphs: inout [String]
    ) {
        let tag = element.tagName().lowercased()
        if directTitleCandidate(from: element) == title {
            return
        }

        if tag == "br" {
            return
        }

        if isCalloutElement(element) {
            return
        }

        if containsCalloutDescendant(in: element) {
            let ownText = stripTitlePrefix(from: normalizedOwnText(element), title: title)
            if !ownText.isEmpty {
                paragraphs.append(ownText)
            }

            for child in element.children().array() {
                appendReadableCalloutBlocks(
                    from: child,
                    title: title,
                    paragraphs: &paragraphs
                )
            }
            return
        }

        if tag == "ul" || tag == "ol" {
            let items = element.children().array()
                .filter { $0.tagName().lowercased() == "li" }
                .map { stripTitlePrefix(from: sourceBodyText(from: $0), title: title) }
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                paragraphs.append(GuideBodyMarkup.encodeList(items: items, isOrdered: tag == "ol"))
            }
            return
        }

        if tag == "table" || tag == "tbody" || tag == "thead" {
            if let tableBlock = sourceTableBlock(from: element) {
                paragraphs.append(tableBlock)
            }
            return
        }

        if containsStructuredBlockDescendant(in: element) {
            let ownText = stripTitlePrefix(from: normalizedOwnText(element), title: title)
            if !ownText.isEmpty {
                paragraphs.append(ownText)
            }

            for child in element.children().array() {
                appendReadableCalloutBlocks(
                    from: child,
                    title: title,
                    paragraphs: &paragraphs
                )
            }
            return
        }

        let linkedItems = readableLinkedListItems(from: element, title: title)
        if !linkedItems.isEmpty {
            paragraphs.append(GuideBodyMarkup.encodeList(items: linkedItems, isOrdered: false))
            return
        }

        if isReadableBlockTag(tag) {
            let text = stripTitlePrefix(from: normalizedText(element), title: title)
            if !text.isEmpty {
                paragraphs.append(text)
            }
            return
        }

        let ownText = stripTitlePrefix(from: normalizedOwnText(element), title: title)
        if !ownText.isEmpty {
            paragraphs.append(ownText)
        }

        for child in element.children().array() {
            appendReadableCalloutBlocks(
                from: child,
                title: title,
                paragraphs: &paragraphs
            )
        }
    }

    private func containsStructuredBlockDescendant(in element: Element) -> Bool {
        for child in element.children().array() {
            let tag = child.tagName().lowercased()
            if tag == "table" || tag == "ul" || tag == "ol" {
                return true
            }
            if containsStructuredBlockDescendant(in: child) {
                return true
            }
        }
        return false
    }

    private func isCalloutElement(_ element: Element) -> Bool {
        let tag = element.tagName().lowercased()
        let className = (try? element.className()) ?? ""
        if isSourceTableContainer(tag: tag, className: className) {
            return false
        }

        let text = normalizedText(element)
        return calloutKind(tag: tag, className: className, text: text) != nil
    }

    private func isSourceTableContainer(tag: String, className: String) -> Bool {
        tag == "table" || className.lowercased().contains("table-wrapper")
    }

    private func containsCalloutDescendant(in element: Element) -> Bool {
        for child in element.children().array() {
            if isCalloutElement(child) || containsCalloutDescendant(in: child) {
                return true
            }
        }
        return false
    }

    private func sourceTableBlock(from element: Element) -> String? {
        let rows = ((try? element.select("tr").array()) ?? [])
            .compactMap(sourceTableRow)
        let tableBlock = GuideBodyMarkup.encodeTable(rows: rows)
        return tableBlock.isEmpty ? nil : tableBlock
    }

    private func sourceTableRow(from row: Element) -> GuideBodyMarkup.TableRow? {
        let cellElements = row.children().array().filter { child in
            let tag = child.tagName().lowercased()
            return tag == "th" || tag == "td"
        }
        guard !cellElements.isEmpty else { return nil }

        let cells = cellElements
            .map(normalizedText)
            .filter { !$0.isEmpty }
        guard !cells.isEmpty else { return nil }

        let isHeader = cellElements.contains {
            $0.tagName().lowercased() == "th"
        }
        return GuideBodyMarkup.TableRow(cells: cells, isHeader: isHeader)
    }

    private func sourceBodyText(from element: Element) -> String {
        let tag = element.tagName().lowercased()
        let shouldPreserveLines = tag == "pre" || containsLineBreakElement(in: element)
        let text = shouldPreserveLines
            ? sourceVisibleText(from: element, preserveSpacing: tag == "pre")
            : normalizedText(element)
        return GuideBodyMarkup.encodingRecognizedSourceLists(in: text)
    }

    private func containsLineBreakElement(in element: Element) -> Bool {
        ((try? element.select("br").isEmpty()) ?? true) == false
    }

    private func sourceVisibleText(from element: Element, preserveSpacing: Bool) -> String {
        var text = ""
        appendSourceVisibleText(from: element, into: &text)
        return normalizedSourceVisibleText(text, preserveSpacing: preserveSpacing)
    }

    private func appendSourceVisibleText(from node: Node, into text: inout String) {
        if let textNode = node as? TextNode {
            text += textNode.getWholeText()
            return
        }

        guard let element = node as? Element else { return }

        let tag = element.tagName().lowercased()
        if tag == "br" {
            appendLineBreak(to: &text)
            return
        }

        if tag == "script" || tag == "style" {
            return
        }

        let isBlock = Self.sourceTextBlockTags.contains(tag)
        if isBlock {
            appendLineBreak(to: &text)
        }

        for child in element.getChildNodes() {
            appendSourceVisibleText(from: child, into: &text)
        }

        if isBlock {
            appendLineBreak(to: &text)
        }
    }

    private static let sourceTextBlockTags: Set<String> = [
        "p",
        "div",
        "section",
        "article",
        "aside",
        "blockquote",
        "pre",
        "tr",
        "li",
    ]

    private func appendLineBreak(to text: inout String) {
        guard !text.isEmpty, !text.hasSuffix("\n") else { return }
        text += "\n"
    }

    private func normalizedSourceVisibleText(_ text: String, preserveSpacing: Bool) -> String {
        var lines = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { line in
                if preserveSpacing {
                    return line.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression)
                }

                return line
                    .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

        while lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
            lines.removeLast()
        }

        return lines.joined(separator: "\n")
    }

    private func readableLinkedListItems(from element: Element, title: String) -> [String] {
        guard title.looksLikeCalloutListTitle else { return [] }

        let links = ((try? element.select("a[href]").array()) ?? [])
            .filter { !normalizedText($0).isEmpty }
        guard links.count > 1 else { return [] }

        let items = links.compactMap { link -> String? in
            let linkText = normalizedText(link)
            let trailingText = trailingInlineText(after: link)
            let item = normalizedGuideListItem("\(linkText) \(trailingText)")
            guard item.isPlausibleGuideListItem else { return nil }
            return item
        }
        .removingAdjacentDuplicates()

        guard items.count > 1 else { return [] }
        return items
    }

    private func trailingInlineText(after element: Element) -> String {
        var parts: [String] = []
        var sibling = element.nextSibling()

        while let node = sibling {
            if let siblingElement = node as? Element {
                let tag = siblingElement.tagName().lowercased()
                if tag == "a" || tag == "br" || isReadableBlockTag(tag) || tag == "table" || tag == "ul" || tag == "ol" {
                    break
                }

                let text = normalizedGuideListItem(normalizedText(siblingElement))
                if !text.isEmpty {
                    parts.append(text)
                }
            } else if let textNode = node as? TextNode {
                let text = normalizedGuideListItem(textNode.getWholeText())
                if !text.isEmpty {
                    parts.append(text)
                }
            }

            sibling = node.nextSibling()
        }

        return parts.joined(separator: " ")
    }

    private func normalizedGuideListItem(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " \n\t,;•*-–—"))
    }

    private func isReadableBlockTag(_ tag: String) -> Bool {
        [
            "p",
            "div",
            "section",
            "blockquote",
            "article",
            "aside",
            "tr",
            "td",
            "li",
        ].contains(tag)
    }

    private func stripTitlePrefix(from text: String, title: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return "" }
        guard normalized.caseInsensitiveHasPrefix(title) else { return normalized }

        let titleEnd = normalized.index(normalized.startIndex, offsetBy: title.count)
        let suffix = normalized[titleEnd...]
            .trimmingCharacters(in: CharacterSet(charactersIn: ":.-–— \n\t"))
        return String(suffix)
    }

    private func imageKind(for title: String, page: GuidePage, currentLocation: String) -> WalkthroughCalloutKind {
        let haystack = "\(title) \(page.title) \(page.guideSection) \(currentLocation) \(page.url.lastPathComponent)".lowercased()
        return haystack.contains("map") ? .map : .image
    }

    private func imageTitle(for image: Element, imageURL: String) -> String {
        let candidates = [
            (try? image.attr("alt")) ?? "",
            (try? image.attr("title")) ?? "",
            URL(string: imageURL)?.lastPathComponent ?? "",
        ]

        for candidate in candidates {
            let cleaned = cleanImageTitle(candidate)
            if !cleaned.isEmpty {
                return cleaned
            }
        }

        return "Guide Image"
    }

    private func imageCaption(for image: Element, fallbackTitle: String) -> String {
        let title = cleanImageTitle((try? image.attr("title")) ?? "")
        if !title.isEmpty {
            return title
        }

        let alt = cleanImageTitle((try? image.attr("alt")) ?? "")
        if !alt.isEmpty {
            return alt
        }

        return fallbackTitle
    }

    private func cleanImageTitle(_ rawTitle: String) -> String {
        rawTitle
            .replacingOccurrences(of: #"\.(jpg|jpeg|png|gif|webp)$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^\d+px-"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func guideImageURL(from image: Element, baseURL: URL) -> String? {
        let candidates = [
            (try? image.attr("abs:data-src")) ?? "",
            (try? image.attr("data-src")) ?? "",
            (try? image.attr("abs:src")) ?? "",
            (try? image.attr("src")) ?? "",
        ]

        for candidate in candidates where !candidate.isEmpty {
            if candidate.hasPrefix("//") {
                return "https:\(candidate)"
            }
            if let absoluteURL = URL(string: candidate, relativeTo: baseURL)?.absoluteURL {
                return absoluteURL.absoluteString
            }
        }

        return nil
    }

    private func isGuideImageURL(_ imageURL: String, image: Element) -> Bool {
        let lowercasedURL = imageURL.lowercased()
        let className = ((try? image.className()) ?? "").lowercased()
        let alt = ((try? image.attr("alt")) ?? "").lowercased()

        if className.contains("img_ad")
            || lowercasedURL.contains("googlesyndication")
            || lowercasedURL.contains("doubleclick")
            || lowercasedURL.contains("/ads/")
            || alt == "tpc-ad"
            || alt == "measurement-ads" {
            return false
        }

        guard let host = URL(string: imageURL)?.host?.lowercased() else {
            return false
        }

        return host.contains("staticneo.com")
    }
}

private func wikiContent(in document: Document, url: URL) throws -> Element {
    if let content = try document.select("article#wiki-content .mw-parser-output").first()
        ?? document.select("#wiki-content .mw-parser-output").first()
        ?? document.getElementById("wiki-content") {
        return content
    }

    throw ImportError.noContentContainer(url)
}

private func normalizedText(_ element: Element) -> String {
    ((try? element.text()) ?? "")
        .replacingOccurrences(of: "\u{00a0}", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func normalizedOwnText(_ element: Element) -> String {
    element.ownText()
        .replacingOccurrences(of: "\u{00a0}", with: " ")
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private extension String {
    func caseInsensitiveHasPrefix(_ prefix: String) -> Bool {
        guard count >= prefix.count else { return false }
        let range = startIndex..<index(startIndex, offsetBy: prefix.count)
        return self[range].localizedCaseInsensitiveCompare(prefix) == .orderedSame
    }

    var looksLikeCalloutListTitle: Bool {
        let normalized = lowercased()
        return normalized.contains("enemy")
            || normalized.contains("enemies")
            || normalized.contains("monster")
            || normalized.contains("monsters")
            || normalized.contains("sparkly")
            || normalized.contains("treasure")
            || normalized.contains("chest")
            || normalized.contains("loot")
            || normalized.contains("items")
            || normalized.contains("shop")
            || normalized.contains("quest")
            || normalized.contains("materia")
    }

    var isPlausibleGuideListItem: Bool {
        guard count >= 2, count <= 90 else { return false }
        let sentenceTerminators = CharacterSet(charactersIn: ".!?")
        return rangeOfCharacter(from: sentenceTerminators) == nil
    }
}

private extension Array where Element == String {
    func removingAdjacentDuplicates() -> [String] {
        reduce(into: [String]()) { result, item in
            guard result.last != item else { return }
            result.append(item)
        }
    }
}

private func containsCompletionKeyword(_ text: String) -> Bool {
    let keywords = [
        "chest",
        "treasure",
        "mini medal",
        "quest",
        "recipe",
        "forge",
        "sparkly spot",
        "trophy",
        "accolade",
        "miscellaneous item",
        "available quest",
        "item shop",
        "weapon shop",
        "armour shop",
        "armor shop",
        "roving emporium",
        "missable",
        "items",
        "materia",
        "weapon",
        "armor",
        "armour",
    ]
    return keywords.contains { text.localizedCaseInsensitiveContains($0) }
}
