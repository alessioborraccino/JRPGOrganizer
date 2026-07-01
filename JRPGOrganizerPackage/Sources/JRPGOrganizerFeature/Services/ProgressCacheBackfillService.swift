import SwiftData

@ModelActor
actor ProgressCacheBackfillService {
    func backfillIfNeeded() throws {
        let games = try modelContext.fetch(FetchDescriptor<SavedGame>())
        var didUpdate = false

        for game in games where game.needsCachedProgressRefresh {
            game.refreshCachedProgressCounts()
            didUpdate = true
        }

        if didUpdate {
            try modelContext.save()
        }
    }
}
