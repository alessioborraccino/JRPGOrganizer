import Foundation
import Observation
import SwiftData

@MainActor
final class ReaderProgressController {
    private var taskIndexByID: [UUID: Int] = [:]
    private var entryStates: [UUID: EntryDisplayState] = [:]
    private var entryStatesBySortOrder: [Int: [EntryDisplayState]] = [:]
    private var entryStateSortOrders: [Int] = []
    private var chapterStates: [Int: ChapterProgressDisplayState] = [:]
    private var chapterTaskIndexBoundsBySortOrder: [Int: Range<Int>] = [:]
    private var firstChapterSortOrder: Int?
    private var orderedTasks: [TaskProgressItem] = []
    private var bookmarkSortOrder: Int?
    private var hasExplicitBookmark = false
    private var readerLayerRaw = WalkthroughReaderLayer.raw.rawValue
    private var gameID: UUID?
    private var modelContainer: ModelContainer?
    private var pendingSaveTask: Task<Void, Never>?
    private var pendingLastViewedChange: WalkthroughLastViewedChange?

    let summary = ReaderProgressSummary()
    var spoilerBoundary: Int?
    var lastCompletedTaskSortOrder: Int?
    var currentTaskSortOrder: Int? {
        bookmarkSortOrder
    }

    init() {}

    func configure(
        gameID: UUID,
        modelContainer: ModelContainer,
        timelineState: ReaderTimelineState,
        explicitBookmarkSortOrder: Int?,
        usesExplicitBookmark: Bool
    ) {
        self.gameID = gameID
        self.modelContainer = modelContainer

        taskIndexByID.removeAll(keepingCapacity: true)
        entryStates.removeAll(keepingCapacity: true)
        entryStatesBySortOrder.removeAll(keepingCapacity: true)
        entryStateSortOrders.removeAll(keepingCapacity: true)
        chapterStates.removeAll(keepingCapacity: true)
        chapterTaskIndexBoundsBySortOrder.removeAll(keepingCapacity: true)
        pendingLastViewedChange = nil
        pendingSaveTask?.cancel()
        pendingSaveTask = nil
        readerLayerRaw = timelineState.entries.first?.readerLayerRaw ?? WalkthroughReaderLayer.raw.rawValue

        orderedTasks = timelineState.entries.compactMap { entry in
            guard entry.entryKind == .task else { return nil }
            return TaskProgressItem(
                id: entry.id,
                sortOrder: entry.sortOrder,
                signature: entry.progressSignature,
                readerLayerRaw: entry.readerLayerRaw
            )
        }

        hasExplicitBookmark = usesExplicitBookmark
        bookmarkSortOrder = usesExplicitBookmark
            ? explicitBookmarkSortOrder
            : Self.derivedBookmarkSortOrder(from: timelineState.entries) ?? orderedTasks.first?.sortOrder
        summary.totalTaskCount = orderedTasks.count
        taskIndexByID = Dictionary(uniqueKeysWithValues: orderedTasks.enumerated().map { index, task in
            (task.id, index)
        })
        let bookmarkIndex = taskIndex(forBookmarkSortOrder: bookmarkSortOrder)
        summary.completedTaskCount = clampedCompletedCount(for: bookmarkIndex)

        spoilerBoundary = spoilerBoundarySortOrder(forBookmarkIndex: bookmarkIndex)
        lastCompletedTaskSortOrder = bookmarkSortOrder
        configureChapterStates(from: timelineState.chapters, bookmarkIndex: bookmarkIndex)
    }

    func entryState(for entry: EntrySnapshot) -> EntryDisplayState {
        if let state = entryStates[entry.id] {
            return state
        }

        let state = EntryDisplayState(
            sortOrder: entry.sortOrder,
            isTask: entry.entryKind == .task,
            isCurrent: isCurrent(entry),
            isSpoiled: isSpoiled(sortOrder: entry.sortOrder),
            isExpanded: false
        )
        entryStates[entry.id] = state
        registerEntryState(state, sortOrder: entry.sortOrder)
        return state
    }

    func isCurrent(_ entry: EntrySnapshot) -> Bool {
        entry.entryKind == .task && entry.sortOrder == bookmarkSortOrder
    }

    func chapterProgressState(selectedSortOrder: Int?) -> ChapterProgressDisplayState? {
        if let selectedSortOrder {
            return chapterStates[selectedSortOrder]
        }

        guard let firstChapterSortOrder else { return nil }
        return chapterStates[firstChapterSortOrder]
    }

    func toggle(_ entry: EntrySnapshot) -> Bool {
        setBookmark(at: entry)
    }

    func setBookmark(for entries: [EntrySnapshot], position: ChapterBookmarkPosition) {
        guard let firstEntry = entries.first else { return }

        switch position {
        case .start:
            setBookmark(at: firstEntry)
        case .end:
            guard let lastEntry = entries.last else { return }
            setBookmark(at: lastEntry)
        }
    }

    @discardableResult
    private func setBookmark(at entry: EntrySnapshot) -> Bool {
        guard entry.entryKind == .task else { return false }
        return setBookmark(to: TaskProgressItem(
            id: entry.id,
            sortOrder: entry.sortOrder,
            signature: entry.progressSignature,
            readerLayerRaw: entry.readerLayerRaw
        ))
    }

    @discardableResult
    private func setBookmark(to task: TaskProgressItem?) -> Bool {
        guard let gameID else { return false }
        let newBookmarkSortOrder = task?.sortOrder
        let oldBookmarkSortOrder = bookmarkSortOrder
        let newBookmarkIndex = task.map { taskIndexByID[$0.id] ?? taskIndex(forBookmarkSortOrder: $0.sortOrder) } ?? -1
        let oldBoundary = spoilerBoundary
        guard bookmarkSortOrder != newBookmarkSortOrder || !hasExplicitBookmark else { return false }

        hasExplicitBookmark = true
        bookmarkSortOrder = newBookmarkSortOrder
        updateBookmarkProgressState(
            oldBookmarkSortOrder: oldBookmarkSortOrder,
            newBookmarkSortOrder: newBookmarkSortOrder,
            newBookmarkIndex: newBookmarkIndex
        )

        spoilerBoundary = spoilerBoundarySortOrder(forBookmarkIndex: newBookmarkIndex)
        lastCompletedTaskSortOrder = bookmarkSortOrder
        updateEntrySpoilerStates(oldBoundary: oldBoundary, newBoundary: spoilerBoundary)

        pendingLastViewedChange = WalkthroughLastViewedChange(
            gameID: gameID,
            sortOrder: newBookmarkSortOrder,
            signature: task?.signature ?? "",
            readerLayerRaw: task?.readerLayerRaw ?? readerLayerRaw,
            completedTaskCount: summary.completedTaskCount,
            totalTaskCount: summary.totalTaskCount
        )
        savePendingChangesInBackground()
        return true
    }

    func flushPendingSave() {
        savePendingChangesInBackground()
    }

    private func configureChapterStates(from chapters: [ChapterSlice], bookmarkIndex: Int) {
        firstChapterSortOrder = chapters.first?.sortOrder

        for chapter in chapters {
            let taskEntries: [EntrySnapshot] = chapter.rows.compactMap { row in
                guard case .entry(let entry) = row, entry.entryKind == .task else { return nil }
                return entry
            }
            guard !taskEntries.isEmpty else { continue }

            let taskIndexes = taskEntries.compactMap { taskIndexByID[$0.id] }
            guard let lowerIndex = taskIndexes.min(),
                  let upperIndex = taskIndexes.max() else {
                continue
            }

            let taskIndexBounds = lowerIndex..<(upperIndex + 1)
            chapterTaskIndexBoundsBySortOrder[chapter.sortOrder] = taskIndexBounds

            chapterStates[chapter.sortOrder] = ChapterProgressDisplayState(
                completed: completedTaskCount(in: taskIndexBounds, bookmarkIndex: bookmarkIndex),
                total: taskEntries.count
            )
        }
    }

    private func savePendingChangesInBackground() {
        pendingSaveTask?.cancel()
        let lastViewedChange = pendingLastViewedChange
        pendingLastViewedChange = nil

        guard lastViewedChange != nil else { return }
        guard let modelContainer else { return }

        pendingSaveTask = Task.detached(priority: .utility) {
            guard !Task.isCancelled else { return }
            do {
                let persistence = WalkthroughProgressPersistence(modelContainer: modelContainer)
                try await persistence.apply(changes: [], lastViewed: lastViewedChange)
            } catch {
                // Progress saves are best-effort; the reader state has already updated locally.
            }
        }
    }

    private static func derivedBookmarkSortOrder(from entries: [EntrySnapshot]) -> Int? {
        var bookmarkSortOrder: Int?
        for entry in entries where entry.entryKind == .task {
            guard entry.isCompleted else { break }
            bookmarkSortOrder = entry.sortOrder
        }
        return bookmarkSortOrder
    }

    private func taskIndex(forBookmarkSortOrder sortOrder: Int?) -> Int {
        guard let sortOrder else { return -1 }
        var low = 0
        var high = orderedTasks.count

        while low < high {
            let mid = (low + high) / 2
            if orderedTasks[mid].sortOrder <= sortOrder {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low - 1
    }

    private func updateBookmarkProgressState(
        oldBookmarkSortOrder: Int?,
        newBookmarkSortOrder: Int?,
        newBookmarkIndex: Int
    ) {
        summary.completedTaskCount = clampedCompletedCount(for: newBookmarkIndex)
        updateChapterCompletedCounts(bookmarkIndex: newBookmarkIndex)
        updateCurrentEntryStates(oldBookmarkSortOrder: oldBookmarkSortOrder, newBookmarkSortOrder: newBookmarkSortOrder)
    }

    private func updateChapterCompletedCounts(bookmarkIndex: Int) {
        for (chapterSortOrder, taskIndexBounds) in chapterTaskIndexBoundsBySortOrder {
            guard let chapterState = chapterStates[chapterSortOrder] else { continue }
            chapterState.completed = completedTaskCount(
                in: taskIndexBounds,
                bookmarkIndex: bookmarkIndex
            )
        }
    }

    private func updateCurrentEntryStates(oldBookmarkSortOrder: Int?, newBookmarkSortOrder: Int?) {
        for sortOrder in Set([oldBookmarkSortOrder, newBookmarkSortOrder].compactMap(\.self)) {
            let isCurrent = sortOrder == newBookmarkSortOrder
            for state in entryStatesBySortOrder[sortOrder] ?? [] where state.isTask && state.isCurrent != isCurrent {
                state.isCurrent = isCurrent
            }
        }
    }

    private func completedTaskCount(in taskIndexBounds: Range<Int>, bookmarkIndex: Int) -> Int {
        guard !taskIndexBounds.isEmpty, bookmarkIndex >= taskIndexBounds.lowerBound else {
            return 0
        }
        guard bookmarkIndex < taskIndexBounds.upperBound else {
            return taskIndexBounds.count
        }
        return bookmarkIndex - taskIndexBounds.lowerBound + 1
    }

    private func clampedCompletedCount(for bookmarkIndex: Int) -> Int {
        min(max(bookmarkIndex + 1, 0), summary.totalTaskCount)
    }

    private func spoilerBoundarySortOrder(forBookmarkIndex bookmarkIndex: Int) -> Int? {
        let nextTaskIndex = bookmarkIndex + 1
        guard orderedTasks.indices.contains(nextTaskIndex) else { return nil }
        return orderedTasks[nextTaskIndex].sortOrder
    }

    private func isSpoiled(sortOrder: Int) -> Bool {
        spoilerBoundary.map { sortOrder > $0 } ?? false
    }

    private func updateEntrySpoilerStates(oldBoundary: Int?, newBoundary: Int?) {
        guard oldBoundary != newBoundary,
              let affectedSortOrders = affectedSpoilerSortOrderBounds(oldBoundary: oldBoundary, newBoundary: newBoundary) else {
            return
        }

        let lowerIndex = affectedSortOrders.lowerExclusive.map { upperBound(for: $0) } ?? 0
        let upperIndex = affectedSortOrders.upperInclusive.map { upperBound(for: $0) } ?? entryStateSortOrders.count
        guard lowerIndex < upperIndex else { return }

        for sortOrder in entryStateSortOrders[lowerIndex..<upperIndex] {
            let isSpoiled = newBoundary.map { sortOrder > $0 } ?? false
            for state in entryStatesBySortOrder[sortOrder] ?? [] where state.isSpoiled != isSpoiled {
                state.isSpoiled = isSpoiled
            }
        }
    }

    private func affectedSpoilerSortOrderBounds(
        oldBoundary: Int?,
        newBoundary: Int?
    ) -> SpoilerSortOrderBounds? {
        switch (oldBoundary, newBoundary) {
        case (nil, nil):
            nil
        case (nil, let new?):
            SpoilerSortOrderBounds(lowerExclusive: new, upperInclusive: nil)
        case (let old?, nil):
            SpoilerSortOrderBounds(lowerExclusive: old, upperInclusive: nil)
        case (let old?, let new?) where new > old:
            SpoilerSortOrderBounds(lowerExclusive: old, upperInclusive: new)
        case (let old?, let new?):
            SpoilerSortOrderBounds(lowerExclusive: new, upperInclusive: old)
        }
    }

    private func registerEntryState(_ state: EntryDisplayState, sortOrder: Int) {
        let isNewSortOrder = entryStatesBySortOrder[sortOrder] == nil
        entryStatesBySortOrder[sortOrder, default: []].append(state)

        if isNewSortOrder {
            let insertionIndex = lowerBound(for: sortOrder)
            entryStateSortOrders.insert(sortOrder, at: insertionIndex)
        }
    }

    private func lowerBound(for sortOrder: Int) -> Int {
        var low = 0
        var high = entryStateSortOrders.count

        while low < high {
            let mid = (low + high) / 2
            if entryStateSortOrders[mid] < sortOrder {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
    }

    private func upperBound(for sortOrder: Int) -> Int {
        var low = 0
        var high = entryStateSortOrders.count

        while low < high {
            let mid = (low + high) / 2
            if entryStateSortOrders[mid] <= sortOrder {
                low = mid + 1
            } else {
                high = mid
            }
        }

        return low
    }

}

@MainActor
@Observable
final class ReaderProgressSummary {
    var completedTaskCount = 0
    var totalTaskCount = 0
}

@MainActor
@Observable
final class ChapterProgressDisplayState {
    var completed: Int
    var total: Int

    init(completed: Int, total: Int) {
        self.completed = completed
        self.total = total
    }

    var isComplete: Bool {
        completed == total
    }
}

@MainActor
@Observable
final class EntryDisplayState {
    let sortOrder: Int
    let isTask: Bool
    var isCurrent: Bool
    var isSpoiled: Bool
    var isExpanded: Bool

    init(sortOrder: Int, isTask: Bool, isCurrent: Bool, isSpoiled: Bool, isExpanded: Bool) {
        self.sortOrder = sortOrder
        self.isTask = isTask
        self.isCurrent = isCurrent
        self.isSpoiled = isSpoiled
        self.isExpanded = isExpanded
    }
}

struct TaskProgressItem: Sendable {
    let id: UUID
    let sortOrder: Int
    let signature: String
    let readerLayerRaw: String
}

struct SpoilerSortOrderBounds {
    let lowerExclusive: Int?
    let upperInclusive: Int?
}
