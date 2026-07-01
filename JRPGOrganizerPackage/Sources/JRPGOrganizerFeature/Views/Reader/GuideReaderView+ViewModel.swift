import SwiftData
import SwiftUI

extension GuideReaderView {
    @MainActor
    final class ViewModel {
        let screen = ReaderScreenState()

        private var timelineState = ReaderTimelineState()
        private let progressController = ReaderProgressController()
        private var selectedChapterSortOrder: Int?
        private var visibleChapterRowLimit = ReaderLayout.initialChapterRowLimit
        private var loadedLastViewedSortOrder: Int?
        private var fallbackLastViewedSortOrder: Int?

        var progressSummary: ReaderProgressSummary {
            progressController.summary
        }

        private var allCurrentChapterRows: [TimelineRow] {
            timelineState.chapterRows(selectedSortOrder: selectedChapterSortOrder)
        }

        private var visibleChapterRows: [TimelineRow] {
            guard !allCurrentChapterRows.isEmpty else { return [] }
            return Array(allCurrentChapterRows.prefix(visibleChapterRowLimit))
        }

        private var hiddenCurrentChapterRowCount: Int {
            let totalRows = allCurrentChapterRows.count
            return max(totalRows - min(visibleChapterRowLimit, totalRows), 0)
        }

        private var nextChapter: TableOfContentsItem? {
            timelineState.nextChapter(after: selectedChapterSortOrder)
        }

        private var previousChapter: TableOfContentsItem? {
            timelineState.previousChapter(before: selectedChapterSortOrder)
        }

        private var currentChapterProgressText: String {
            timelineState.chapterProgressText(selectedSortOrder: selectedChapterSortOrder)
        }

        private var currentChapterProgressState: ChapterProgressDisplayState? {
            progressController.chapterProgressState(selectedSortOrder: selectedChapterSortOrder)
        }

        private var currentMarkerChapterSortOrder: Int? {
            timelineState.chapterSortOrder(containing: progressController.currentTaskSortOrder)
        }

        private var resumeRowID: String? {
            preferredTargetRowIDForCurrentChapter(targetSortOrder: resumeTargetSortOrder)
        }

        func entryState(for entry: EntrySnapshot) -> EntryDisplayState {
            progressController.entryState(for: entry)
        }

        func toggle(_ entry: EntrySnapshot) {
            guard entry.entryKind == .task else { return }
            let didChange = withAnimation(readerProgressRevealAnimation) {
                progressController.toggle(entry)
            }
            if didChange {
                screen.currentMarkerChapterSortOrder = currentMarkerChapterSortOrder
            }
        }

        func setCurrentChapterPosition(_ position: ChapterBookmarkPosition) {
            updateWithoutAnimation {
                progressController.setBookmark(
                    for: timelineState.chapterTaskEntries(selectedSortOrder: selectedChapterSortOrder),
                    position: position
                )
            }
            screen.currentMarkerChapterSortOrder = currentMarkerChapterSortOrder
        }

        func toggleCalloutExpansion(_ entry: EntrySnapshot) {
            guard entry.isBodyExpandable || entry.imageURL != nil else { return }
            withAnimation(readerExpansionAnimation) {
                progressController.entryState(for: entry).isExpanded.toggle()
            }
        }

        func openImage(url: URL, kind: WalkthroughCalloutKind) {
            screen.selectedImage = GuideImagePresentation(url: url, kind: kind)
        }

        @MainActor
        func loadEntriesIfNeeded(
            gameID: UUID,
            fallbackLastViewedSortOrder: Int?,
            modelContainer: ModelContainer
        ) async {
            guard timelineState.entries.isEmpty else { return }
            screen.isLoading = true
            screen.loadErrorMessage = nil
            self.fallbackLastViewedSortOrder = fallbackLastViewedSortOrder

            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let loader = WalkthroughReaderLoader(modelContainer: modelContainer)
                    return try await loader.load(gameID: gameID)
                }.value

                guard !Task.isCancelled else { return }
                timelineState = result.timelineState
                progressController.configure(
                    gameID: gameID,
                    modelContainer: modelContainer,
                    timelineState: result.timelineState,
                    explicitBookmarkSortOrder: result.hasExplicitBookmark ? result.bookmarkSortOrder : nil,
                    usesExplicitBookmark: result.hasExplicitBookmark
                )
                loadedLastViewedSortOrder = result.lastViewedSortOrder
                selectChapterForCurrentMode(containing: resumeTargetSortOrder)
                if let resumeRowID {
                    revealCurrentChapterRows(containing: resumeRowID)
                    screen.scrollRequest = ReaderScrollRequest(targetRowID: resumeRowID)
                }
                screen.isLoading = false
            } catch {
                screen.loadErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                screen.isLoading = false
            }
        }

        private var resumeTargetSortOrder: Int? {
            progressController.currentTaskSortOrder
                ?? loadedLastViewedSortOrder
                ?? fallbackLastViewedSortOrder
                ?? timelineState.lastTaskSortOrder
        }

        private func selectChapterForCurrentMode(containing sortOrder: Int?) {
            setSelectedChapterSortOrder(timelineState.chapterSortOrder(
                containing: sortOrder ?? selectedChapterSortOrder
            ))
        }

        func jump(to item: TableOfContentsItem) {
            setSelectedChapterSortOrder(item.sortOrder)
            let targetRowID = preferredTargetRowIDForCurrentChapter(targetSortOrder: item.sortOrder)
                ?? item.targetRowID
            revealCurrentChapterRows(containing: targetRowID)
            screen.scrollRequest = ReaderScrollRequest(targetRowID: targetRowID)
        }

        func revealMoreCurrentChapterRows() {
            let totalRows = allCurrentChapterRows.count
            guard visibleChapterRowLimit < totalRows else { return }

            setVisibleChapterRowLimit(
                min(visibleChapterRowLimit + ReaderLayout.chapterRowBatchSize, totalRows)
            )
        }

        func flushPendingSave() {
            progressController.flushPendingSave()
        }

        private func setSelectedChapterSortOrder(_ sortOrder: Int?) {
            updateWithoutAnimation {
                selectedChapterSortOrder = sortOrder
                visibleChapterRowLimit = ReaderLayout.initialChapterRowLimit
                refreshScreenState()
            }
        }

        private func revealCurrentChapterRows(containing rowID: String) {
            let rows = allCurrentChapterRows
            guard let rowIndex = rows.firstIndex(where: { $0.id == rowID }) else { return }
            let requiredLimit = min(
                rows.count,
                max(
                    ReaderLayout.initialChapterRowLimit,
                    rowIndex + 1 + ReaderLayout.chapterRowBatchSize
                )
            )
            updateWithoutAnimation {
                visibleChapterRowLimit = requiredLimit
                refreshScreenState()
            }
        }

        private func preferredTargetRowIDForCurrentChapter(targetSortOrder: Int?) -> String? {
            currentTaskRowIDForCurrentChapter
                ?? firstTaskRowIDForCurrentChapter
                ?? timelineState.resumeRowID(
                    selectedSortOrder: selectedChapterSortOrder,
                    targetSortOrder: targetSortOrder
                )
        }

        private var currentTaskRowIDForCurrentChapter: String? {
            for row in allCurrentChapterRows {
                guard case .entry(let entry) = row,
                      entry.entryKind == .task,
                      progressController.isCurrent(entry) else {
                    continue
                }
                return row.id
            }

            return nil
        }

        private var firstTaskRowIDForCurrentChapter: String? {
            for row in allCurrentChapterRows {
                guard case .entry(let entry) = row, entry.entryKind == .task else {
                    continue
                }
                return row.id
            }

            return nil
        }

        private func setVisibleChapterRowLimit(_ rowLimit: Int) {
            updateWithoutAnimation {
                visibleChapterRowLimit = max(ReaderLayout.initialChapterRowLimit, rowLimit)
                refreshScreenState()
            }
        }

        @discardableResult
        private func updateWithoutAnimation<Result>(_ updates: () -> Result) -> Result {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            return withTransaction(transaction, updates)
        }

        private func refreshScreenState() {
            screen.contents = timelineState.contents
            screen.visibleChapterRows = visibleChapterRows
            screen.hiddenCurrentChapterRowCount = hiddenCurrentChapterRowCount
            screen.previousChapter = previousChapter
            screen.nextChapter = nextChapter
            screen.currentChapterProgressText = currentChapterProgressText
            screen.currentChapterProgressState = currentChapterProgressState
            screen.currentMarkerChapterSortOrder = currentMarkerChapterSortOrder
        }
    }
}
