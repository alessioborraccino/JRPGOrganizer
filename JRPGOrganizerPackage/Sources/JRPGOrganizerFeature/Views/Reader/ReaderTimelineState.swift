import Foundation

struct ReaderTimelineState: Sendable {
    var entries: [EntrySnapshot] = []
    var rows: [TimelineRow] = []
    var chapters: [ChapterSlice] = []
    var contents: [TableOfContentsItem] = []
    var lastTaskSortOrder: Int?

    init() {}

    init(entries: [EntrySnapshot]) {
        self.entries = entries
        lastTaskSortOrder = entries.last { $0.entryKind == .task }?.sortOrder
        rows = Self.makeRows(from: entries)
        chapters = Self.makeChapters(from: rows)
        contents = Self.makeContents(from: chapters)
    }

    func resumeRowID(targetSortOrder: Int?) -> String? {
        resumeRowID(selectedSortOrder: nil, targetSortOrder: targetSortOrder)
    }

    func resumeRowID(selectedSortOrder: Int?, targetSortOrder: Int?) -> String? {
        let rows = chapterRows(selectedSortOrder: selectedSortOrder)
        guard let targetSortOrder else {
            return rows.last?.id
        }

        return rows.firstEntryID(atOrAfter: targetSortOrder) ?? rows.lastEntryID
    }

    func chapterRows(selectedSortOrder: Int?) -> [TimelineRow] {
        selectedChapter(selectedSortOrder: selectedSortOrder)?.rows ?? []
    }

    func chapterTaskEntries(selectedSortOrder: Int?) -> [EntrySnapshot] {
        guard let chapter = selectedChapter(selectedSortOrder: selectedSortOrder) else { return [] }

        return chapter.rows.compactMap { row in
            guard case .entry(let entry) = row, entry.entryKind == .task else { return nil }
            return entry
        }
    }

    func chapterSortOrder(containing sortOrder: Int?) -> Int? {
        guard !chapters.isEmpty else { return nil }
        guard let sortOrder else { return chapters.first?.sortOrder }

        return chapters.last { $0.sortOrder <= sortOrder }?.sortOrder ?? chapters.first?.sortOrder
    }

    func nextChapter(after selectedSortOrder: Int?) -> TableOfContentsItem? {
        guard let selectedSortOrder else {
            return contents.dropFirst().first
        }
        return contents.first { $0.sortOrder > selectedSortOrder }
    }

    func previousChapter(before selectedSortOrder: Int?) -> TableOfContentsItem? {
        guard !contents.isEmpty else { return nil }
        guard let selectedSortOrder else { return nil }

        let selectedIndex = contents.firstIndex { $0.sortOrder == selectedSortOrder }
            ?? contents.lastIndex { $0.sortOrder < selectedSortOrder }
        guard let selectedIndex, selectedIndex > 0 else { return nil }
        return contents[selectedIndex - 1]
    }

    func chapterProgressText(selectedSortOrder: Int?) -> String {
        guard !chapters.isEmpty else { return "Chapter 0 of 0" }
        let selected = selectedChapter(selectedSortOrder: selectedSortOrder) ?? chapters[0]
        let index = chapters.firstIndex { $0.sortOrder == selected.sortOrder } ?? 0
        return "Chapter \(index + 1) of \(chapters.count)"
    }

    private func selectedChapter(selectedSortOrder: Int?) -> ChapterSlice? {
        guard !chapters.isEmpty else { return nil }
        guard let selectedSortOrder else { return chapters.first }

        return chapters.first { $0.sortOrder == selectedSortOrder }
            ?? chapters.last { $0.sortOrder <= selectedSortOrder }
            ?? chapters.first
    }

    private static func makeRows(from entries: [EntrySnapshot]) -> [TimelineRow] {
        var rows: [TimelineRow] = []
        rows.reserveCapacity(entries.count + 120)
        var currentChapter: String?
        var currentLocation: String?

        for entry in entries {
            if entry.chapterTitle != currentChapter {
                currentChapter = entry.chapterTitle
                currentLocation = nil
                rows.append(.chapterHeader(title: entry.chapterTitle, section: entry.guideSection, sortOrder: entry.sortOrder))
            }

            if entry.location != currentLocation {
                currentLocation = entry.location
                rows.append(.locationHeader(title: entry.location, sortOrder: entry.sortOrder))
            }

            rows.append(.entry(entry))
        }

        return rows
    }

    private static func makeChapters(from rows: [TimelineRow]) -> [ChapterSlice] {
        var chapters: [ChapterSlice] = []
        var activeTitle: String?
        var activeSubtitle: String?
        var activeSortOrder: Int?
        var activeRows: [TimelineRow] = []

        func finishActiveChapter() {
            guard let activeTitle, let activeSortOrder else { return }
            chapters.append(
                ChapterSlice(
                    title: activeTitle,
                    subtitle: activeSubtitle,
                    sortOrder: activeSortOrder,
                    rows: activeRows
                )
            )
        }

        for row in rows {
            if case .chapterHeader(let title, let section, let sortOrder) = row {
                finishActiveChapter()
                activeTitle = title
                activeSubtitle = section
                activeSortOrder = sortOrder
                activeRows = [row]
            } else if activeSortOrder != nil {
                activeRows.append(row)
            }
        }

        finishActiveChapter()
        return chapters
    }

    private static func makeContents(from chapters: [ChapterSlice]) -> [TableOfContentsItem] {
        chapters.map { chapter in
            TableOfContentsItem(
                title: chapter.title,
                subtitle: chapter.subtitle,
                sortOrder: chapter.sortOrder,
                targetRowID: chapter.rows.first?.id ?? "chapter-\(chapter.sortOrder)"
            )
        }
    }

}

extension Array where Element == TimelineRow {
    func firstEntryID(atOrAfter sortOrder: Int) -> String? {
        for row in self {
            guard case .entry(let entry) = row, entry.sortOrder >= sortOrder else {
                continue
            }
            return row.id
        }

        return nil
    }

    var lastEntryID: String? {
        for row in reversed() {
            guard case .entry = row else { continue }
            return row.id
        }

        return nil
    }
}
