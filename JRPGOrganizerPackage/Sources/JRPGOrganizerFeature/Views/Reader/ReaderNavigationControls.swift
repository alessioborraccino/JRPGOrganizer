import SwiftUI

struct ReaderPinnedControls: View {
    let progressSummary: ReaderProgressSummary
    let chapterText: String

    var body: some View {
        HStack(spacing: 10) {
            Text(chapterText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(JRPGTheme.secondaryText)

            Spacer(minLength: 8)

            Text("\(progressSummary.completedTaskCount)/\(progressSummary.totalTaskCount)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(JRPGTheme.secondaryText)
        }
        .padding(.horizontal, ReaderLayout.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(JRPGTheme.pinnedControlBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JRPGTheme.cardBorder)
                .frame(height: 1)
        }
    }
}

struct ChapterProgressBottomToolbar: View {
    let progressState: ChapterProgressDisplayState
    let onMoveToStart: () -> Void
    let onMoveToEnd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("Current Bookmark", systemImage: "bookmark.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JRPGTheme.secondaryText)

                Spacer(minLength: 8)

                Text("\(progressState.completed)/\(progressState.total)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(JRPGTheme.secondaryText)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    bookmarkPositionButton(
                        title: "First Step",
                        systemImage: "backward.end.fill",
                        action: onMoveToStart
                    )
                    .disabled(progressState.completed == 1)

                    bookmarkPositionButton(
                        title: "Last Step",
                        systemImage: "forward.end.fill",
                        action: onMoveToEnd
                    )
                    .disabled(progressState.isComplete)
                }

                HStack(spacing: 10) {
                    bookmarkPositionButton(
                        title: "First",
                        systemImage: "backward.end.fill",
                        action: onMoveToStart
                    )
                    .disabled(progressState.completed == 1)

                    bookmarkPositionButton(
                        title: "Last",
                        systemImage: "forward.end.fill",
                        action: onMoveToEnd
                    )
                    .disabled(progressState.isComplete)
                }
            }
        }
        .padding(.horizontal, ReaderLayout.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JRPGTheme.navigationBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(JRPGTheme.cardBorder)
                .frame(height: 1)
        }
    }

    private func bookmarkPositionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }
}

struct ChapterRowsLoadingSentinel: View {
    let remainingCount: Int
    let onRevealMore: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            Text("Loading More Steps")
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            Text("\(remainingCount) left")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JRPGTheme.secondaryText)
        }
        .foregroundStyle(JRPGTheme.primaryText)
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(JRPGTheme.cardBackground, in: .rect(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(JRPGTheme.cardBorder, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading more steps")
        .task(id: remainingCount) {
            guard remainingCount > 0 else { return }
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onRevealMore()
            }
        }
    }
}

struct ChapterNavigationCard: View {
    let previousChapter: TableOfContentsItem?
    let nextChapter: TableOfContentsItem?
    let onPrevious: (TableOfContentsItem) -> Void
    let onNext: (TableOfContentsItem) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let previousChapter {
                chapterButton(
                    label: "Previous",
                    title: previousChapter.title,
                    systemImage: "chevron.left.circle.fill",
                    isPrevious: true
                ) {
                    onPrevious(previousChapter)
                }
            }

            if previousChapter != nil, nextChapter != nil {
                Divider()
                    .padding(.vertical, 4)
            }

            if let nextChapter {
                chapterButton(
                    label: "Next",
                    title: nextChapter.title,
                    systemImage: "chevron.right.circle.fill",
                    isPrevious: false
                ) {
                    onNext(nextChapter)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(JRPGTheme.cardBackground, in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(JRPGTheme.cardBorder, lineWidth: 1)
        }
    }

    private func chapterButton(
        label: String,
        title: String,
        systemImage: String,
        isPrevious: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isPrevious {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(JRPGTheme.accent)
                }

                VStack(alignment: isPrevious ? .leading : .trailing, spacing: 2) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JRPGTheme.secondaryText)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(JRPGTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .frame(maxWidth: .infinity, alignment: isPrevious ? .leading : .trailing)

                if !isPrevious {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(JRPGTheme.accent)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(title)
    }
}
