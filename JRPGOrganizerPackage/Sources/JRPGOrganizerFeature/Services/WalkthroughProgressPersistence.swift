import Foundation
import SwiftData

public struct WalkthroughProgressChange: Sendable {
    public let id: String
    public let gameID: UUID
    public let readerLayerRaw: String
    public let entryID: UUID
    public let entrySignature: String
    public let isCompleted: Bool
    public let updatedAt: Date

    public init(
        gameID: UUID,
        readerLayerRaw: String,
        entryID: UUID,
        entrySignature: String,
        isCompleted: Bool,
        updatedAt: Date = .now
    ) {
        self.id = WalkthroughProgressRecord.makeID(
            gameID: gameID,
            readerLayerRaw: readerLayerRaw,
            entryID: entryID
        )
        self.gameID = gameID
        self.readerLayerRaw = readerLayerRaw
        self.entryID = entryID
        self.entrySignature = entrySignature
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }
}

public struct WalkthroughLastViewedChange: Sendable {
    public let gameID: UUID
    public let sortOrder: Int?
    public let signature: String?
    public let readerLayerRaw: String?
    public let completedTaskCount: Int?
    public let totalTaskCount: Int?

    public init(
        gameID: UUID,
        sortOrder: Int?,
        signature: String?,
        readerLayerRaw: String? = nil,
        completedTaskCount: Int? = nil,
        totalTaskCount: Int? = nil
    ) {
        self.gameID = gameID
        self.sortOrder = sortOrder
        self.signature = signature
        self.readerLayerRaw = readerLayerRaw
        self.completedTaskCount = completedTaskCount
        self.totalTaskCount = totalTaskCount
    }
}

@ModelActor
public actor WalkthroughProgressPersistence {
    public func apply(
        changes: [WalkthroughProgressChange],
        lastViewed: WalkthroughLastViewedChange?
    ) throws {
        guard !changes.isEmpty || lastViewed != nil else { return }

        var gameCache: [UUID: SavedGame] = [:]

        for change in changes {
            try upsert(change, gameCache: &gameCache)
        }

        if let lastViewed {
            let game = try savedGame(id: lastViewed.gameID, gameCache: &gameCache)
            game?.lastViewedSortOrder = lastViewed.sortOrder
            game?.lastViewedEntrySignature = lastViewed.signature
            if let readerLayerRaw = lastViewed.readerLayerRaw,
               let layer = WalkthroughReaderLayer(rawValue: readerLayerRaw),
               let completedTaskCount = lastViewed.completedTaskCount,
               let totalTaskCount = lastViewed.totalTaskCount {
                game?.applyCachedBookmarkCompletionCount(
                    layer: layer,
                    completedTaskCount: completedTaskCount,
                    totalTaskCount: totalTaskCount
                )
            }
        }

        try modelContext.save()
    }

    private func upsert(
        _ change: WalkthroughProgressChange,
        gameCache: inout [UUID: SavedGame]
    ) throws {
        let recordID = change.id
        let layer = WalkthroughReaderLayer(rawValue: change.readerLayerRaw) ?? .raw
        let game = try savedGame(id: change.gameID, gameCache: &gameCache)
        if let game {
            ensureCachedProgressCounts(on: game)
        }

        var descriptor = FetchDescriptor<WalkthroughProgressRecord>(
            predicate: #Predicate { record in
                record.id == recordID
            }
        )
        descriptor.fetchLimit = 1

        if let record = try modelContext.fetch(descriptor).first {
            let oldValue = record.isCompleted
            record.entrySignature = change.entrySignature
            record.isCompleted = change.isCompleted
            record.updatedAt = change.updatedAt
            if let game {
                applyCachedCompletionDelta(
                    to: game,
                    layer: layer,
                    oldValue: oldValue,
                    newValue: change.isCompleted
                )
            }
            return
        }

        let oldValue = fallbackCompletion(for: change, layer: layer, game: game)
        let record = WalkthroughProgressRecord(
            id: recordID,
            gameID: change.gameID,
            readerLayer: layer,
            entryID: change.entryID,
            entrySignature: change.entrySignature,
            isCompleted: change.isCompleted,
            updatedAt: change.updatedAt
        )
        record.game = game
        modelContext.insert(record)

        if let game {
            applyCachedCompletionDelta(
                to: game,
                layer: layer,
                oldValue: oldValue,
                newValue: change.isCompleted
            )
        }
    }

    private func savedGame(
        id gameID: UUID,
        gameCache: inout [UUID: SavedGame]
    ) throws -> SavedGame? {
        if let cachedGame = gameCache[gameID] {
            return cachedGame
        }

        var descriptor = FetchDescriptor<SavedGame>(
            predicate: #Predicate { game in
                game.id == gameID
            }
        )
        descriptor.fetchLimit = 1

        let game = try modelContext.fetch(descriptor).first
        gameCache[gameID] = game
        return game
    }

    private func ensureCachedProgressCounts(on game: SavedGame) {
        if game.needsCachedProgressRefresh {
            game.refreshCachedProgressCounts()
        }
    }

    private func fallbackCompletion(
        for change: WalkthroughProgressChange,
        layer: WalkthroughReaderLayer,
        game: SavedGame?
    ) -> Bool {
        guard let game else { return false }

        switch layer {
        case .raw:
            return game.entries.first { $0.id == change.entryID }?.isCompleted ?? false
        case .organized:
            return game.organizedEntries.first { $0.id == change.entryID }?.isCompleted ?? false
        }
    }

    private func applyCachedCompletionDelta(
        to game: SavedGame,
        layer: WalkthroughReaderLayer,
        oldValue: Bool,
        newValue: Bool
    ) {
        guard oldValue != newValue else { return }
        let delta = newValue ? 1 : -1

        switch layer {
        case .raw:
            game.rawCompletedTaskCount = clamped(
                (game.rawCompletedTaskCount ?? 0) + delta,
                maximum: game.rawTotalTaskCount ?? 0
            )
        case .organized:
            game.organizedCompletedTaskCount = clamped(
                (game.organizedCompletedTaskCount ?? 0) + delta,
                maximum: game.organizedTotalTaskCount ?? 0
            )
        }
    }

    private func clamped(_ count: Int, maximum: Int) -> Int {
        min(max(count, 0), max(maximum, 0))
    }
}
