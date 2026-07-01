import Foundation
import SwiftData

@ModelActor
actor WalkthroughReaderLoader {
    func load(gameID: UUID) throws -> ReaderLoadResult {
        var descriptor = FetchDescriptor<SavedGame>(
            predicate: #Predicate { game in
                game.id == gameID
            }
        )
        descriptor.fetchLimit = 1

        guard let game = try modelContext.fetch(descriptor).first else {
            throw ReaderLoadError.gameNotFound
        }

        let layer = game.activeReaderLayer
        let progressLookup = EntryProgressLookup(
            gameID: game.id,
            layer: layer,
            records: game.progressRecords
        )

        let entries = if layer == .organized {
            game.organizedEntries
                .filter { $0.organizerVersion == OrganizedWalkthroughEntry.currentOrganizerVersion }
                .map { EntrySnapshot(entry: $0, progressLookup: progressLookup) }
        } else {
            game.entries.map { EntrySnapshot(entry: $0, progressLookup: progressLookup) }
        }

        let sortedEntries = entries.sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.sortOrder < rhs.sortOrder
        }

        let bookmark = Self.bookmarkSortOrder(
            lastViewedSortOrder: game.lastViewedSortOrder,
            lastViewedEntrySignature: game.lastViewedEntrySignature,
            entries: sortedEntries
        )

        return ReaderLoadResult(
            timelineState: ReaderTimelineState(entries: sortedEntries),
            lastViewedSortOrder: game.lastViewedSortOrder,
            hasExplicitBookmark: game.lastViewedEntrySignature != nil,
            bookmarkSortOrder: bookmark
        )
    }

    private static func bookmarkSortOrder(
        lastViewedSortOrder: Int?,
        lastViewedEntrySignature: String?,
        entries: [EntrySnapshot]
    ) -> Int? {
        guard let lastViewedEntrySignature else { return nil }
        guard !lastViewedEntrySignature.isEmpty else { return nil }

        return entries.first { entry in
            entry.entryKind == .task && entry.progressSignature == lastViewedEntrySignature
        }?.sortOrder ?? lastViewedSortOrder
    }
}

enum ReaderLoadError: LocalizedError {
    case gameNotFound

    var errorDescription: String? {
        switch self {
        case .gameNotFound:
            "The saved guide could not be loaded."
        }
    }
}

struct ReaderLoadResult: Sendable {
    let timelineState: ReaderTimelineState
    let lastViewedSortOrder: Int?
    let hasExplicitBookmark: Bool
    let bookmarkSortOrder: Int?
}
