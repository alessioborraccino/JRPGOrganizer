import Foundation
import SwiftData

@Model
public final class SavedGame {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var rootURL: String
    public var dateDownloaded: Date
    public var lastViewedSortOrder: Int?
    public var lastViewedEntrySignature: String?

    @Relationship(deleteRule: .cascade, inverse: \WalkthroughEntry.game)
    public var entries: [WalkthroughEntry]

    @Relationship(deleteRule: .cascade, inverse: \OrganizedWalkthroughEntry.game)
    public var organizedEntries: [OrganizedWalkthroughEntry]

    @Relationship(deleteRule: .cascade, inverse: \WalkthroughProgressRecord.game)
    public var progressRecords: [WalkthroughProgressRecord]

    public var rawCompletedTaskCount: Int?
    public var rawTotalTaskCount: Int?
    public var organizedCompletedTaskCount: Int?
    public var organizedTotalTaskCount: Int?
    public var progressCacheVersion: Int?

    public init(
        id: UUID = UUID(),
        title: String,
        rootURL: String,
        dateDownloaded: Date = .now,
        lastViewedSortOrder: Int? = nil,
        lastViewedEntrySignature: String? = nil,
        entries: [WalkthroughEntry] = [],
        organizedEntries: [OrganizedWalkthroughEntry] = [],
        progressRecords: [WalkthroughProgressRecord] = [],
        rawCompletedTaskCount: Int = 0,
        rawTotalTaskCount: Int = 0,
        organizedCompletedTaskCount: Int = 0,
        organizedTotalTaskCount: Int = 0,
        progressCacheVersion: Int = SavedGame.currentProgressCacheVersion
    ) {
        self.id = id
        self.title = title
        self.rootURL = rootURL
        self.dateDownloaded = dateDownloaded
        self.lastViewedSortOrder = lastViewedSortOrder
        self.lastViewedEntrySignature = lastViewedEntrySignature
        self.entries = entries
        self.organizedEntries = organizedEntries
        self.progressRecords = progressRecords
        self.rawCompletedTaskCount = rawCompletedTaskCount
        self.rawTotalTaskCount = rawTotalTaskCount
        self.organizedCompletedTaskCount = organizedCompletedTaskCount
        self.organizedTotalTaskCount = organizedTotalTaskCount
        self.progressCacheVersion = progressCacheVersion
    }

    public var sortedEntries: [WalkthroughEntry] {
        entries.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }

    public var taskEntries: [WalkthroughEntry] {
        entries.filter { $0.entryKind == .task }
    }

    public var sortedOrganizedEntries: [OrganizedWalkthroughEntry] {
        organizedEntries
            .filter { $0.organizerVersion == OrganizedWalkthroughEntry.currentOrganizerVersion }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    public var hasOrganizedEntries: Bool {
        (organizedTotalTaskCount ?? 0) > 0
    }

    public var activeReaderLayer: WalkthroughReaderLayer {
        hasOrganizedEntries ? .organized : .raw
    }

    public var completedTaskCount: Int {
        if hasOrganizedEntries {
            organizedCompletedTaskCount ?? 0
        } else {
            rawCompletedTaskCount ?? 0
        }
    }

    public var totalTaskCount: Int {
        if hasOrganizedEntries {
            organizedTotalTaskCount ?? 0
        } else {
            rawTotalTaskCount ?? 0
        }
    }

    public var completionProgress: Double {
        guard totalTaskCount > 0 else { return 0 }
        return Double(completedTaskCount) / Double(totalTaskCount)
    }

    public func completedTaskSignatures(for layer: WalkthroughReaderLayer) -> Set<String> {
        if let bookmarkSignatures = bookmarkedTaskSignatures(for: layer) {
            return bookmarkSignatures
        }

        let progressStates = progressStateBySignature(for: layer)

        if !progressStates.isEmpty {
            return Set(progressStates.compactMap { signature, isCompleted in
                isCompleted ? signature : nil
            })
        }

        switch layer {
        case .raw:
            return Set(taskEntries.filter(\.isCompleted).map(\.progressSignature))
        case .organized:
            return Set(
                sortedOrganizedEntries
                    .filter { $0.entryKind == .task && $0.isCompleted }
                    .map(\.progressSignature)
            )
        }
    }

    private func progressStateBySignature(for layer: WalkthroughReaderLayer) -> [String: Bool] {
        progressRecords.reduce(into: [:]) { states, record in
            guard record.readerLayer == layer else { return }
            states[record.entrySignature] = record.isCompleted
        }
    }

    public var needsCachedProgressRefresh: Bool {
        progressCacheVersion != Self.currentProgressCacheVersion
            || rawCompletedTaskCount == nil
            || rawTotalTaskCount == nil
            || organizedCompletedTaskCount == nil
            || organizedTotalTaskCount == nil
    }

    public func refreshCachedProgressCounts() {
        rawTotalTaskCount = computedRawTotalTaskCount
        rawCompletedTaskCount = computedRawCompletedTaskCount

        organizedTotalTaskCount = computedOrganizedTotalTaskCount
        organizedCompletedTaskCount = computedOrganizedCompletedTaskCount
        progressCacheVersion = Self.currentProgressCacheVersion
    }

    public func applyCachedBookmarkCompletionCount(
        layer: WalkthroughReaderLayer,
        completedTaskCount: Int,
        totalTaskCount: Int
    ) {
        rawCompletedTaskCount = rawCompletedTaskCount ?? 0
        rawTotalTaskCount = rawTotalTaskCount ?? 0
        organizedCompletedTaskCount = organizedCompletedTaskCount ?? 0
        organizedTotalTaskCount = organizedTotalTaskCount ?? 0

        let boundedTotal = max(totalTaskCount, 0)
        let boundedCompleted = min(max(completedTaskCount, 0), boundedTotal)

        switch layer {
        case .raw:
            rawCompletedTaskCount = boundedCompleted
            rawTotalTaskCount = boundedTotal
        case .organized:
            organizedCompletedTaskCount = boundedCompleted
            organizedTotalTaskCount = boundedTotal
        }

        progressCacheVersion = Self.currentProgressCacheVersion
    }

    public static let currentProgressCacheVersion = 3

    private var computedRawTotalTaskCount: Int {
        entries.reduce(into: 0) { count, entry in
            if entry.entryKind == .task {
                count += 1
            }
        }
    }

    private var computedRawCompletedTaskCount: Int {
        if let bookmarkedCount = bookmarkedTaskCount(for: .raw) {
            return bookmarkedCount
        }

        let progressStates = progressStateBySignature(for: .raw)
        return entries.reduce(into: 0) { count, entry in
            guard entry.entryKind == .task else { return }
            if progressStates[entry.progressSignature] ?? entry.isCompleted {
                count += 1
            }
        }
    }

    private var currentOrganizedEntries: [OrganizedWalkthroughEntry] {
        organizedEntries.filter {
            $0.organizerVersion == OrganizedWalkthroughEntry.currentOrganizerVersion
        }
    }

    private var computedOrganizedTotalTaskCount: Int {
        let currentOrganizedEntries = organizedEntries.filter {
            $0.organizerVersion == OrganizedWalkthroughEntry.currentOrganizerVersion
        }
        return currentOrganizedEntries.reduce(into: 0) { count, entry in
            if entry.entryKind == .task {
                count += 1
            }
        }
    }

    private var computedOrganizedCompletedTaskCount: Int {
        if let bookmarkedCount = bookmarkedTaskCount(for: .organized) {
            return bookmarkedCount
        }

        let progressStates = progressStateBySignature(for: .organized)
        return currentOrganizedEntries.reduce(into: 0) { count, entry in
            guard entry.entryKind == .task else { return }
            if progressStates[entry.progressSignature] ?? entry.isCompleted {
                count += 1
            }
        }
    }

    private func bookmarkedTaskCount(for layer: WalkthroughReaderLayer) -> Int? {
        guard let lastViewedEntrySignature else { return nil }
        guard !lastViewedEntrySignature.isEmpty else { return 0 }
        guard let lastViewedSortOrder else { return 0 }

        switch layer {
        case .raw:
            return entries.reduce(into: 0) { count, entry in
                if entry.entryKind == .task, entry.sortOrder <= lastViewedSortOrder {
                    count += 1
                }
            }
        case .organized:
            return currentOrganizedEntries.reduce(into: 0) { count, entry in
                if entry.entryKind == .task, entry.sortOrder <= lastViewedSortOrder {
                    count += 1
                }
            }
        }
    }

    private func bookmarkedTaskSignatures(for layer: WalkthroughReaderLayer) -> Set<String>? {
        guard let lastViewedEntrySignature else { return nil }
        guard !lastViewedEntrySignature.isEmpty else { return [] }
        guard let lastViewedSortOrder else { return [] }

        switch layer {
        case .raw:
            return Set(entries.compactMap { entry in
                guard entry.entryKind == .task, entry.sortOrder <= lastViewedSortOrder else { return nil }
                return entry.progressSignature
            })
        case .organized:
            return Set(currentOrganizedEntries.compactMap { entry in
                guard entry.entryKind == .task, entry.sortOrder <= lastViewedSortOrder else { return nil }
                return entry.progressSignature
            })
        }
    }
}
