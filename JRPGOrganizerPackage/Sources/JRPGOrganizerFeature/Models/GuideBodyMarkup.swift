import Foundation

enum GuideBodyMarkup {
    static let tableStartMarker = "[[JRPG_SOURCE_TABLE_V1]]"
    static let tableEndMarker = "[[/JRPG_SOURCE_TABLE_V1]]"
    private static let listStartMarkerPrefix = "[[JRPG_SOURCE_LIST_V1"
    private static let listEndMarker = "[[/JRPG_SOURCE_LIST_V1]]"

    struct Table: Hashable, Sendable {
        var rows: [TableRow]
    }

    struct TableRow: Hashable, Sendable {
        var cells: [String]
        var isHeader: Bool
    }

    struct SourceList: Hashable, Sendable {
        var items: [String]
        var isOrdered: Bool
    }

    enum Block: Hashable, Sendable {
        case paragraph(String)
        case table(Table)
        case sourceList(SourceList)
    }

    static func hasTable(in text: String) -> Bool {
        text.contains(tableStartMarker) && text.contains(tableEndMarker)
    }

    static func hasStructuredMarkup(in text: String) -> Bool {
        hasTable(in: text) || text.contains(listStartMarkerPrefix)
    }

    static func encodeTable(rows: [TableRow]) -> String {
        let encodedRows = rows
            .filter { !$0.cells.isEmpty }
            .map { row in
                let prefix = row.isHeader ? "H" : "R"
                let cells = row.cells.map(sanitizedCell).joined(separator: "\t")
                return "\(prefix)\t\(cells)"
            }

        guard !encodedRows.isEmpty else { return "" }
        return ([tableStartMarker] + encodedRows + [tableEndMarker]).joined(separator: "\n")
    }

    static func encodeList(items: [String], isOrdered: Bool) -> String {
        let encodedItems = items
            .map(sanitizedCell)
            .filter { !$0.isEmpty }
            .map { "I\t\($0)" }

        guard !encodedItems.isEmpty else { return "" }
        let startMarker = "\(listStartMarkerPrefix) ordered=\(isOrdered ? "1" : "0")]]"
        return ([startMarker] + encodedItems + [listEndMarker]).joined(separator: "\n")
    }

    static func encodingRecognizedSourceLists(in text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var output: [String] = []
        var index = 0

        while index < lines.count {
            guard let firstItem = sourceListItem(from: lines[index]) else {
                output.append(lines[index])
                index += 1
                continue
            }

            var items = [firstItem.text]
            var nextIndex = index + 1
            while nextIndex < lines.count,
                  let nextItem = sourceListItem(from: lines[nextIndex]),
                  nextItem.isOrdered == firstItem.isOrdered {
                items.append(nextItem.text)
                nextIndex += 1
            }

            if items.count > 1 {
                output.append(encodeList(items: items, isOrdered: firstItem.isOrdered))
            } else {
                output.append(lines[index])
            }
            index = nextIndex
        }

        return output.joined(separator: "\n")
    }

    static func blocks(from text: String) -> [Block] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var blocks: [Block] = []
        var paragraphLines: [String] = []
        var tableRows: [TableRow] = []
        var listItems: [String] = []
        var activeListIsOrdered = false
        var isReadingTable = false
        var isReadingList = false

        func flushParagraph() {
            let paragraph = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph))
            }
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func flushTable() {
            let rows = tableRows.filter { !$0.cells.isEmpty }
            if !rows.isEmpty {
                blocks.append(.table(Table(rows: rows)))
            }
            tableRows.removeAll(keepingCapacity: true)
        }

        func flushList() {
            let items = listItems
                .map(sanitizedCell)
                .filter { !$0.isEmpty }
            if !items.isEmpty {
                blocks.append(.sourceList(SourceList(items: items, isOrdered: activeListIsOrdered)))
            }
            listItems.removeAll(keepingCapacity: true)
        }

        for line in normalized.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine == tableStartMarker {
                flushParagraph()
                tableRows.removeAll(keepingCapacity: true)
                isReadingTable = true
                continue
            }

            if trimmedLine == tableEndMarker {
                flushTable()
                isReadingTable = false
                continue
            }

            if trimmedLine.hasPrefix(listStartMarkerPrefix) {
                flushParagraph()
                listItems.removeAll(keepingCapacity: true)
                activeListIsOrdered = trimmedLine.contains("ordered=1")
                isReadingList = true
                continue
            }

            if trimmedLine == listEndMarker {
                flushList()
                isReadingList = false
                continue
            }

            if isReadingTable {
                if let row = decodedTableRow(from: line) {
                    tableRows.append(row)
                }
                continue
            }

            if isReadingList {
                if let item = decodedListItem(from: line) {
                    listItems.append(item)
                }
                continue
            }

            if trimmedLine.isEmpty {
                flushParagraph()
            } else {
                paragraphLines.append(line)
            }
        }

        if isReadingTable {
            paragraphLines.append(tableStartMarker)
            paragraphLines.append(contentsOf: tableRows.map(encodedRow))
        }

        if isReadingList {
            paragraphLines.append("\(listStartMarkerPrefix) ordered=\(activeListIsOrdered ? "1" : "0")]]")
            paragraphLines.append(contentsOf: listItems.map { "I\t\($0)" })
        }

        flushParagraph()
        return blocks
    }

    private static func decodedTableRow(from line: String) -> TableRow? {
        let parts = line.components(separatedBy: "\t")
        guard let kind = parts.first, kind == "H" || kind == "R" else { return nil }

        let cells = parts.dropFirst()
            .map(sanitizedCell)
            .filter { !$0.isEmpty }
        guard !cells.isEmpty else { return nil }
        return TableRow(cells: cells, isHeader: kind == "H")
    }

    private static func decodedListItem(from line: String) -> String? {
        let parts = line.components(separatedBy: "\t")
        guard parts.first == "I" else { return nil }
        let item = parts.dropFirst().joined(separator: " ")
        let cleanedItem = sanitizedCell(item)
        return cleanedItem.isEmpty ? nil : cleanedItem
    }

    private static func encodedRow(_ row: TableRow) -> String {
        let prefix = row.isHeader ? "H" : "R"
        return "\(prefix)\t\(row.cells.map(sanitizedCell).joined(separator: "\t"))"
    }

    private static func sourceListItem(from line: String) -> (text: String, isOrdered: Bool)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let bulletPattern = #"^[-*•+]\s+(.+)$"#
        if let item = captureGroup(in: trimmed, pattern: bulletPattern) {
            return (item, false)
        }

        let orderedPattern = #"^(?:\d+|[A-Za-z])[\.\)]\s+(.+)$"#
        if let item = captureGroup(in: trimmed, pattern: orderedPattern) {
            return (item, true)
        }

        return nil
    }

    private static func captureGroup(in text: String, pattern: String) -> String? {
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let match = String(text[range])
        guard let groupRange = match.range(of: pattern, options: .regularExpression) else {
            return nil
        }

        let nsMatch = match as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(
                in: match,
                range: NSRange(location: 0, length: nsMatch.length)
              ),
              result.numberOfRanges > 1 else {
            return String(match[groupRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let captureRange = result.range(at: 1)
        guard captureRange.location != NSNotFound else { return nil }
        let captured = nsMatch.substring(with: captureRange)
        return sanitizedCell(captured)
    }

    private static func sanitizedCell(_ cell: String) -> String {
        cell
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
