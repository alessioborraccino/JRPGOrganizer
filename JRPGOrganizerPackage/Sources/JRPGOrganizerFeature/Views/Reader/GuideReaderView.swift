import Observation
import SwiftData
import SwiftUI
public struct GuideReaderView: View {
    @Environment(\.modelContext) private var modelContext
    private let gameID: UUID
    private let gameTitle: String
    private let fallbackLastViewedSortOrder: Int?

    @State private var viewModel = ViewModel()

    public init(game: SavedGame) {
        gameID = game.id
        gameTitle = game.title
        fallbackLastViewedSortOrder = game.lastViewedSortOrder
    }

    public var body: some View {
        @Bindable var screen = viewModel.screen

        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        if screen.isLoading {
                            ProgressView("Loading guide...")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .cardSurface()
                                .padding(.horizontal, ReaderLayout.horizontalPadding)
                                .padding(.vertical, 8)
                        } else if let loadErrorMessage = screen.loadErrorMessage {
                            ContentUnavailableView(
                                "Guide Unavailable",
                                systemImage: "exclamationmark.triangle",
                                description: Text(loadErrorMessage)
                            )
                            .padding()
                            .cardSurface()
                            .padding(.horizontal, ReaderLayout.horizontalPadding)
                            .padding(.vertical, 8)
                        } else {
                            if screen.previousChapter != nil || screen.nextChapter != nil {
                                ChapterNavigationCard(
                                    previousChapter: screen.previousChapter,
                                    nextChapter: screen.nextChapter,
                                    onPrevious: { viewModel.jump(to: $0) },
                                    onNext: { viewModel.jump(to: $0) }
                                )
                                .padding(.horizontal, ReaderLayout.horizontalPadding)
                                .padding(.top, 12)
                                .padding(.bottom, 2)
                            }

                            ForEach(screen.visibleChapterRows) { row in
                                rowView(row)
                                    .id(row.id)
                            }

                            if screen.hasMoreCurrentChapterRows {
                                ChapterRowsLoadingSentinel(
                                    remainingCount: screen.hiddenCurrentChapterRowCount,
                                    onRevealMore: viewModel.revealMoreCurrentChapterRows
                                )
                                .padding(.horizontal, ReaderLayout.horizontalPadding)
                                .padding(.top, 10)
                                .padding(.bottom, 20)
                            } else if screen.previousChapter != nil || screen.nextChapter != nil {
                                ChapterNavigationCard(
                                    previousChapter: screen.previousChapter,
                                    nextChapter: screen.nextChapter,
                                    onPrevious: { viewModel.jump(to: $0) },
                                    onNext: { viewModel.jump(to: $0) }
                                )
                                .padding(.horizontal, ReaderLayout.horizontalPadding)
                                .padding(.top, 14)
                                .padding(.bottom, 28)
                            }
                        }
                    } header: {
                        ReaderPinnedControls(
                            progressSummary: viewModel.progressSummary,
                            chapterText: screen.currentChapterProgressText
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .onChange(of: screen.scrollRequest) { _, request in
                guard let request else { return }
                if request.isAnimated {
                    withAnimation(.easeOut(duration: 0.16)) {
                        scrollProxy.scrollTo(request.targetRowID, anchor: .bottom)
                    }
                    return
                }

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    scrollProxy.scrollTo(request.targetRowID, anchor: .center)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !screen.isLoading,
               screen.loadErrorMessage == nil,
               let chapterProgressState = screen.currentChapterProgressState {
                ChapterProgressBottomToolbar(
                    progressState: chapterProgressState,
                    onMoveToStart: {
                        viewModel.setCurrentChapterPosition(.start)
                    },
                    onMoveToEnd: {
                        viewModel.setCurrentChapterPosition(.end)
                    }
                )
            }
        }
        .background(JRPGTheme.appBackground.ignoresSafeArea())
        .navigationTitle(gameTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(JRPGTheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    screen.isShowingContents = true
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Contents")
            }
        }
        .task {
            await viewModel.loadEntriesIfNeeded(
                gameID: gameID,
                fallbackLastViewedSortOrder: fallbackLastViewedSortOrder,
                modelContainer: modelContext.container
            )
        }
        .sheet(isPresented: $screen.isShowingContents) {
            TableOfContentsView(
                items: screen.contents,
                currentSortOrder: screen.currentMarkerChapterSortOrder
            ) { item in
                screen.isShowingContents = false
                viewModel.jump(to: item)
            }
        }
        .fullScreenCover(item: $screen.selectedImage) { image in
            GuideImageViewer(presentation: image)
        }
        .onDisappear {
            viewModel.flushPendingSave()
        }
    }

    @ViewBuilder
    private func rowView(_ row: TimelineRow) -> some View {
        switch row {
        case .chapterHeader(let title, let section, _):
            ChapterHeaderRow(title: title, section: section)
                .padding(.horizontal, ReaderLayout.horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 6)
        case .locationHeader(let title, _):
            LocationHeaderRow(title: title)
                .padding(.horizontal, ReaderLayout.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, 3)
        case .entry(let entry):
            EntryRow(
                entry: entry,
                displayState: viewModel.entryState(for: entry),
                onToggleTask: {
                    viewModel.toggle(entry)
                },
                onToggleCalloutExpansion: {
                    viewModel.toggleCalloutExpansion(entry)
                },
                onOpenImage: { url, kind in
                    viewModel.openImage(url: url, kind: kind)
                }
            )
            .padding(.horizontal, ReaderLayout.horizontalPadding)
            .padding(.vertical, 5)
        }
    }
}
