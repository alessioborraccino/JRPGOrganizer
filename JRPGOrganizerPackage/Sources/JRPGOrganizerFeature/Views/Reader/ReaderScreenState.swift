import Observation
import SwiftUI

let readerExpansionAnimation = Animation.snappy(duration: 0.22, extraBounce: 0.04)
let readerProgressRevealAnimation = Animation.smooth(duration: 0.28)

@MainActor
@Observable
final class ReaderScreenState {
    var isLoading = true
    var isShowingContents = false
    var selectedImage: GuideImagePresentation?
    var scrollRequest: ReaderScrollRequest?
    var loadErrorMessage: String?
    var contents: [TableOfContentsItem] = []
    var visibleChapterRows: [TimelineRow] = []
    var hiddenCurrentChapterRowCount = 0
    var previousChapter: TableOfContentsItem?
    var nextChapter: TableOfContentsItem?
    var currentChapterProgressText = "Chapter 0 of 0"
    var currentChapterProgressState: ChapterProgressDisplayState?
    var currentMarkerChapterSortOrder: Int?

    var hasMoreCurrentChapterRows: Bool {
        hiddenCurrentChapterRowCount > 0
    }
}

enum ReaderLayout {
    static let horizontalPadding: CGFloat = 16
    static let initialChapterRowLimit = 12
    static let chapterRowBatchSize = 18
}

struct ReaderScrollRequest: Equatable {
    let id = UUID()
    let targetRowID: String
    var isAnimated = false
}
