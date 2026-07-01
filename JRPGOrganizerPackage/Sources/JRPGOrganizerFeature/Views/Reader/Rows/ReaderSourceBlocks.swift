import SwiftUI

struct ReaderBodyText: View {
    let text: String
    let font: Font
    let foregroundColor: Color
    var isStruckThrough = false
    var paragraphSpacing: CGFloat = 8

    var body: some View {
        ReaderSourceBlocksView(
            blocks: GuideBodyMarkup.blocks(from: text),
            font: font,
            foregroundColor: foregroundColor,
            isStruckThrough: isStruckThrough,
            paragraphSpacing: paragraphSpacing
        )
    }
}

struct ReaderSourceBlocksView: View {
    let blocks: [GuideBodyMarkup.Block]
    let font: Font
    let foregroundColor: Color
    var isStruckThrough = false
    var paragraphSpacing: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: paragraphSpacing) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let paragraph):
                    ReaderParagraphText(
                        paragraph: paragraph,
                        font: font,
                        foregroundColor: foregroundColor,
                        isStruckThrough: isStruckThrough,
                        paragraphSpacing: paragraphSpacing
                    )
                case .table(let table):
                    ReaderSourceTableView(table: table)
                case .sourceList(let list):
                    ReaderSourceListView(list: list)
                }
            }
        }
    }
}

private struct ReaderParagraphText: View {
    let paragraph: String
    let font: Font
    let foregroundColor: Color
    let isStruckThrough: Bool
    let paragraphSpacing: CGFloat

    private var paragraphs: [String] {
        paragraph.readerParagraphs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: paragraphSpacing) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph)
                    .font(font)
                    .strikethrough(isStruckThrough)
                    .foregroundStyle(foregroundColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ReaderSourceTableView: View {
    let table: GuideBodyMarkup.Table

    private var columnCount: Int {
        table.rows.map(\.cells.count).max() ?? 0
    }

    var body: some View {
        Group {
            if columnCount <= 1 {
                singleColumnTable
            } else {
                multiColumnTable
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var singleColumnTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                cellView(
                    text: row.cells.first ?? "",
                    isHeader: row.isHeader,
                    fillAvailableWidth: true
                )
            }
        }
        .clipShape(.rect(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(JRPGTheme.cardBorder, lineWidth: 1)
        }
    }

    private var multiColumnTable: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { columnIndex in
                            cellView(
                                text: cellText(row: row, columnIndex: columnIndex),
                                isHeader: row.isHeader,
                                fillAvailableWidth: false
                            )
                        }
                    }
                }
            }
            .clipShape(.rect(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(JRPGTheme.cardBorder, lineWidth: 1)
            }
        }
    }

    private func cellText(row: GuideBodyMarkup.TableRow, columnIndex: Int) -> String {
        guard columnIndex < row.cells.count else { return "" }
        return row.cells[columnIndex]
    }

    private func cellView(text: String, isHeader: Bool, fillAvailableWidth: Bool) -> some View {
        TableCellText(text: text, isHeader: isHeader)
            .frame(
                minWidth: fillAvailableWidth ? nil : cellMinimumWidth,
                maxWidth: fillAvailableWidth ? .infinity : cellMaximumWidth,
                alignment: .leading
            )
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(isHeader ? JRPGTheme.pinnedControlBackground : JRPGTheme.recessedBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(JRPGTheme.cardBorder)
                    .frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(JRPGTheme.cardBorder)
                    .frame(height: 0.5)
            }
    }

    private var cellMinimumWidth: CGFloat {
        switch columnCount {
        case 0...2:
            116
        case 3:
            104
        default:
            92
        }
    }

    private var cellMaximumWidth: CGFloat {
        switch columnCount {
        case 0...2:
            260
        case 3:
            220
        default:
            180
        }
    }
}

private struct TableCellText: View {
    let text: String
    let isHeader: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            textView(lineLimit: 1)
            textView(lineLimit: 2)
            textView(lineLimit: nil)
        }
    }

    private func textView(lineLimit: Int?) -> some View {
        Text(text)
            .font(isHeader ? .caption.weight(.semibold) : .callout.weight(.medium))
            .foregroundStyle(isHeader ? JRPGTheme.secondaryText : JRPGTheme.primaryText)
            .lineLimit(lineLimit)
            .minimumScaleFactor(isHeader ? 0.82 : 0.78)
            .fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

private struct ReaderSourceListView: View {
    let list: GuideBodyMarkup.SourceList

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(marker(for: index))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(JRPGTheme.secondaryText)
                        .monospacedDigit()
                        .frame(minWidth: list.isOrdered ? 24 : 10, alignment: .trailing)

                    Text(item)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(JRPGTheme.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func marker(for index: Int) -> String {
        list.isOrdered ? "\(index + 1)." : "•"
    }
}

extension String {
    func readerListItems() -> [String] {
        let normalized = replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !GuideBodyMarkup.hasStructuredMarkup(in: normalized) else { return [] }

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let explicitItems = lines.compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("•")
                    || trimmed.hasPrefix("- ")
                    || trimmed.hasPrefix("– ")
                    || trimmed.hasPrefix("— ")
                    || trimmed.hasPrefix("* ") else {
                return nil
            }
            return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "•-–—* "))
        }
        return explicitItems.count > 1 ? explicitItems : []
    }

    var readerParagraphs: [String] {
        let normalized = replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"\n[ \t]*\n+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let explicitParagraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if explicitParagraphs.count > 1 {
            return explicitParagraphs
        }

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if lines.count > 1 {
            return lines
        }

        guard normalized.count > 520 else {
            return [normalized]
        }

        let sentenceSeparated = normalized
            .replacingOccurrences(
                of: #"(?<=[.!?])\s+(?=[A-Z0-9"“])"#,
                with: "\u{2029}",
                options: .regularExpression
            )
            .components(separatedBy: "\u{2029}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard sentenceSeparated.count >= 4 else {
            return [normalized]
        }

        var paragraphs: [String] = []
        var active = ""
        for sentence in sentenceSeparated {
            if !active.isEmpty, active.count + sentence.count > 280 {
                paragraphs.append(active)
                active = sentence
            } else if active.isEmpty {
                active = sentence
            } else {
                active += " \(sentence)"
            }
        }
        if !active.isEmpty {
            paragraphs.append(active)
        }
        return paragraphs
    }
}
