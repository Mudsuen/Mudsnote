import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func focusEditorForLibraryAction() {
        guard selectedScope != .trash else { return }
        window?.makeFirstResponder(editorTextView)
    }

    func insertTableForLibrary() {
        if insertTableRowInCurrentMarkdownTableForLibrary() {
            return
        }

        let markdown = """
        | Column 1 | Column 2 |
        | --- | --- |
        |  |  |
        """
        insertMarkdownBlockForLibrary(markdown)
    }

    enum MarkdownTableCellDirection {
        case next
        case previous
    }

    struct MarkdownTableLocation {
        let lineRange: NSRange
        let columnIndex: Int
        let columnCount: Int
    }

    struct RichMarkdownTableSnapshot {
        let tableRange: NSRange
        let rows: [[String]]
        let cellRanges: [[NSRange]]
        let columnCount: Int
    }

    struct RichMarkdownTableLocation {
        let snapshot: RichMarkdownTableSnapshot
        let row: Int
        let column: Int
    }

    func moveMarkdownTableCellSelectionForLibrary(_ direction: MarkdownTableCellDirection) -> Bool {
        guard selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: editorTextView.selectedRange().location) {
            let flatIndex = location.row * location.snapshot.columnCount + location.column
            switch direction {
            case .next:
                let cellCount = location.snapshot.rows.count * location.snapshot.columnCount
                if flatIndex + 1 < cellCount {
                    let nextIndex = flatIndex + 1
                    moveEditorSelection(to: location.snapshot.cellRanges[nextIndex / location.snapshot.columnCount][nextIndex % location.snapshot.columnCount].location)
                    return true
                }

                var rows = location.snapshot.rows
                rows.append(Array(repeating: "", count: location.snapshot.columnCount))
                replaceRichMarkdownTable(
                    location.snapshot,
                    rows: rows,
                    selectedRow: rows.count - 1,
                    selectedColumn: 0
                )
                return true

            case .previous:
                let previousIndex = max(flatIndex - 1, 0)
                moveEditorSelection(to: location.snapshot.cellRanges[previousIndex / location.snapshot.columnCount][previousIndex % location.snapshot.columnCount].location)
                return true
            }
        }

        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }

        let currentLineRange = visibleLineRangeForSelection()
        let currentLine = string.substring(with: currentLineRange)
        guard markdownTableColumnCount(in: currentLine) != nil,
              !isMarkdownTableSeparatorLine(currentLine),
              let currentCell = markdownTableCellIndex(at: editorTextView.selectedRange().location, lineRange: currentLineRange, in: string),
              let currentCellStarts = markdownTableCellStartLocations(in: currentLine, lineStartLocation: currentLineRange.location) else {
            return false
        }

        switch direction {
        case .next:
            if currentCell + 1 < currentCellStarts.count {
                moveEditorSelection(to: currentCellStarts[currentCell + 1])
                return true
            }

            if let nextRow = adjacentMarkdownTableDataRow(after: currentLineRange, in: string),
               let nextStarts = markdownTableCellStartLocations(
                    in: string.substring(with: nextRow),
                    lineStartLocation: nextRow.location
               ),
               let firstStart = nextStarts.first {
                moveEditorSelection(to: firstStart)
                return true
            }

            let columnCount = currentCellStarts.count
            let insertedRowStart = insertEmptyMarkdownTableRow(after: currentLineRange, columnCount: columnCount, in: storage)
            moveEditorSelection(to: insertedRowStart)
            return true

        case .previous:
            if currentCell > 0 {
                moveEditorSelection(to: currentCellStarts[currentCell - 1])
                return true
            }

            if let previousRow = adjacentMarkdownTableDataRow(before: currentLineRange, in: string),
               let previousStarts = markdownTableCellStartLocations(
                    in: string.substring(with: previousRow),
                    lineStartLocation: previousRow.location
               ),
               let lastStart = previousStarts.last {
                moveEditorSelection(to: lastStart)
                return true
            }

            if let firstStart = currentCellStarts.first {
                moveEditorSelection(to: firstStart)
                return true
            }
            return false
        }
    }

    @discardableResult
    func insertTableRowInCurrentMarkdownTableForLibrary() -> Bool {
        guard selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: editorTextView.selectedRange().location) {
            var rows = location.snapshot.rows
            let insertionRow = min(location.row + 1, rows.count)
            rows.insert(Array(repeating: "", count: location.snapshot.columnCount), at: insertionRow)
            replaceRichMarkdownTable(
                location.snapshot,
                rows: rows,
                selectedRow: insertionRow,
                selectedColumn: min(location.column, location.snapshot.columnCount - 1)
            )
            return true
        }

        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }

        let currentLineRange = visibleLineRangeForSelection()
        let currentLine = string.substring(with: currentLineRange)
        guard markdownTableColumnCount(in: currentLine) != nil else { return false }

        var targetLineRange = currentLineRange
        var columnCount = markdownTableColumnCount(in: currentLine) ?? 2
        if !isMarkdownTableSeparatorLine(currentLine),
           let nextLineRange = lineRange(after: currentLineRange, in: string) {
            let nextLine = string.substring(with: nextLineRange)
            if isMarkdownTableSeparatorLine(nextLine),
               let nextColumnCount = markdownTableColumnCount(in: nextLine) {
                targetLineRange = nextLineRange
                columnCount = nextColumnCount
            }
        }

        moveEditorSelection(to: insertEmptyMarkdownTableRow(after: targetLineRange, columnCount: columnCount, in: storage))
        return true
    }

    func insertEmptyMarkdownTableRow(after targetLineRange: NSRange, columnCount: Int, in storage: NSTextStorage) -> Int {
        let insertionLocation = NSMaxRange(targetLineRange)
        let rowMarkdown = "\n" + emptyMarkdownTableRow(columnCount: columnCount)
        let rendered = MarkdownRichTextCodec.render(
            markdown: rowMarkdown,
            theme: theme,
            baseURL: selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: NSRange(location: insertionLocation, length: 0), with: rendered)
        suppressEditorChanges = false

        markDirty()
        return min(insertionLocation + 3, storage.length)
    }

    @discardableResult
    func deleteCurrentMarkdownTableRowForLibrary() -> Bool {
        guard selectedScope != .trash,
              editorTextView.selectedRange().length == 0,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: editorTextView.selectedRange().location) {
            guard location.row > 0 else { return false }
            var rows = location.snapshot.rows
            rows.remove(at: location.row)
            replaceRichMarkdownTable(
                location.snapshot,
                rows: rows,
                selectedRow: min(location.row, rows.count - 1),
                selectedColumn: min(location.column, location.snapshot.columnCount - 1)
            )
            return true
        }

        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }

        let currentLineRange = visibleLineRangeForSelection()
        let currentLine = string.substring(with: currentLineRange)
        guard markdownTableColumnCount(in: currentLine) != nil,
              !isMarkdownTableSeparatorLine(currentLine),
              isMarkdownTableDataRow(currentLineRange, in: string) else {
            return false
        }

        let deletionRange = fullLineDeletionRange(for: currentLineRange, in: string)
        let nextSelectionLocation = deletionRange.location

        suppressEditorChanges = true
        storage.replaceCharacters(in: deletionRange, with: NSAttributedString(string: ""))
        suppressEditorChanges = false

        markDirty()
        moveEditorSelection(to: nextSelectionLocation)
        return true
    }

    @discardableResult
    func insertMarkdownTableColumnForLibrary(atCharacterIndex characterIndex: Int) -> Bool {
        editMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex, operation: .insertAfter)
    }

    @discardableResult
    func deleteMarkdownTableColumnForLibrary(atCharacterIndex characterIndex: Int) -> Bool {
        editMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex, operation: .delete)
    }

    enum MarkdownTableColumnOperation {
        case insertAfter
        case delete
    }

    @discardableResult
    func editMarkdownTableColumnForLibrary(
        atCharacterIndex characterIndex: Int,
        operation: MarkdownTableColumnOperation
    ) -> Bool {
        guard selectedScope != .trash,
              let storage = editorTextView.textStorage else {
            return false
        }

        if let location = richMarkdownTableLocation(atCharacterIndex: characterIndex) {
            guard operation != .delete || location.snapshot.columnCount > 2 else { return false }
            var rows = location.snapshot.rows
            let selectedColumn: Int
            switch operation {
            case .insertAfter:
                selectedColumn = location.column + 1
                for rowIndex in rows.indices {
                    rows[rowIndex].insert("", at: selectedColumn)
                }
            case .delete:
                selectedColumn = min(location.column, location.snapshot.columnCount - 2)
                for rowIndex in rows.indices {
                    rows[rowIndex].remove(at: location.column)
                }
            }
            replaceRichMarkdownTable(
                location.snapshot,
                rows: rows,
                selectedRow: location.row,
                selectedColumn: selectedColumn
            )
            return true
        }

        let string = editorTextView.string as NSString
        guard let location = markdownTableLocation(atCharacterIndex: characterIndex, in: string),
              let lineRanges = markdownTableLineRanges(containing: location.lineRange, in: string),
              location.columnCount > 1 else {
            return false
        }

        if operation == .delete, location.columnCount <= 2 {
            return false
        }

        var replacementLines: [String] = []
        for lineRange in lineRanges {
            let line = string.substring(with: lineRange)
            guard var cells = markdownTableCells(in: line) else { return false }
            switch operation {
            case .insertAfter:
                cells.insert(isMarkdownTableSeparatorLine(line) ? "---" : "", at: min(location.columnIndex + 1, cells.count))
            case .delete:
                guard cells.indices.contains(location.columnIndex) else { return false }
                cells.remove(at: location.columnIndex)
            }
            replacementLines.append(markdownTableLine(cells: cells))
        }

        guard let firstRange = lineRanges.first,
              let lastRange = lineRanges.last else {
            return false
        }

        let tableRange = NSRange(location: firstRange.location, length: NSMaxRange(lastRange) - firstRange.location)
        let currentRowIndex = lineRanges.firstIndex { $0.location == location.lineRange.location } ?? 0
        let targetColumnIndex: Int
        switch operation {
        case .insertAfter:
            targetColumnIndex = location.columnIndex + 1
        case .delete:
            targetColumnIndex = min(location.columnIndex, max(location.columnCount - 2, 0))
        }

        let rendered = MarkdownRichTextCodec.render(
            markdown: replacementLines.joined(separator: "\n"),
            theme: theme,
            baseURL: selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: tableRange, with: rendered)
        suppressEditorChanges = false

        markDirty()
        let targetLineStart = firstRange.location + replacementLines.prefix(currentRowIndex).reduce(0) { partial, line in
            partial + (line as NSString).length + 1
        }
        if let targetStarts = markdownTableCellStartLocations(
            in: replacementLines[currentRowIndex],
            lineStartLocation: targetLineStart
        ), targetStarts.indices.contains(targetColumnIndex) {
            moveEditorSelection(to: targetStarts[targetColumnIndex])
        } else {
            moveEditorSelection(to: firstRange.location)
        }
        return true
    }

    func richMarkdownTableLocation(atCharacterIndex characterIndex: Int) -> RichMarkdownTableLocation? {
        guard let storage = editorTextView.textStorage,
              storage.length > 0 else {
            return nil
        }

        let probeLocation = max(0, min(characterIndex, storage.length - 1))
        guard tableAttributeString(.qmTableID, at: probeLocation, in: storage) != nil,
              let row = tableAttributeInteger(.qmTableRow, at: probeLocation, in: storage),
              let column = tableAttributeInteger(.qmTableColumn, at: probeLocation, in: storage),
              let snapshot = richMarkdownTableSnapshot(atCharacterIndex: probeLocation, in: storage),
              snapshot.rows.indices.contains(row),
              snapshot.cellRanges[row].indices.contains(column) else {
            return nil
        }
        return RichMarkdownTableLocation(snapshot: snapshot, row: row, column: column)
    }

    func richMarkdownTableSnapshot(
        atCharacterIndex characterIndex: Int,
        in storage: NSTextStorage
    ) -> RichMarkdownTableSnapshot? {
        guard storage.length > 0 else { return nil }
        let probeLocation = max(0, min(characterIndex, storage.length - 1))
        var tableRange = NSRange(location: 0, length: 0)
        guard let tableID = storage.attribute(
            .qmTableID,
            at: probeLocation,
            longestEffectiveRange: &tableRange,
            in: NSRange(location: 0, length: storage.length)
        ) as? String else {
            return nil
        }

        let string = storage.string as NSString
        var markdownByRow: [Int: [Int: String]] = [:]
        var rangesByRow: [Int: [Int: NSRange]] = [:]
        var columnCount = 0
        var cursor = tableRange.location
        while cursor < NSMaxRange(tableRange) {
            let paragraphRange = string.paragraphRange(for: NSRange(location: cursor, length: 0))
            let clippedParagraphRange = NSIntersectionRange(paragraphRange, tableRange)
            let hasTrailingNewline = clippedParagraphRange.length > 0
                && string.substring(with: clippedParagraphRange).hasSuffix("\n")
            let cellRange = NSRange(
                location: clippedParagraphRange.location,
                length: max(clippedParagraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
            )
            let metadataLocation = cellRange.length > 0 ? cellRange.location : clippedParagraphRange.location
            guard metadataLocation < storage.length,
                  tableAttributeString(.qmTableID, at: metadataLocation, in: storage) == tableID,
                  let row = tableAttributeInteger(.qmTableRow, at: metadataLocation, in: storage),
                  let column = tableAttributeInteger(.qmTableColumn, at: metadataLocation, in: storage) else {
                break
            }

            columnCount = max(
                columnCount,
                tableAttributeInteger(.qmTableColumnCount, at: metadataLocation, in: storage) ?? 0
            )
            let cellMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
                range: cellRange,
                in: storage,
                paragraphKind: .paragraph,
                theme: theme
            )
                .replacingOccurrences(of: "\u{200B}", with: "")
                .replacingOccurrences(of: "|", with: "\\|")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            markdownByRow[row, default: [:]][column] = cellMarkdown
            rangesByRow[row, default: [:]][column] = cellRange
            cursor = NSMaxRange(clippedParagraphRange)
        }

        guard columnCount >= 2,
              let maximumRow = markdownByRow.keys.max(),
              maximumRow >= 0 else {
            return nil
        }

        var rows: [[String]] = []
        var cellRanges: [[NSRange]] = []
        for row in 0...maximumRow {
            guard let rowMarkdown = markdownByRow[row],
                  let rowRanges = rangesByRow[row],
                  rowMarkdown.count == columnCount,
                  rowRanges.count == columnCount else {
                return nil
            }
            rows.append((0..<columnCount).map { rowMarkdown[$0] ?? "" })
            cellRanges.append((0..<columnCount).compactMap { rowRanges[$0] })
        }

        return RichMarkdownTableSnapshot(
            tableRange: tableRange,
            rows: rows,
            cellRanges: cellRanges,
            columnCount: columnCount
        )
    }

    func replaceRichMarkdownTable(
        _ snapshot: RichMarkdownTableSnapshot,
        rows: [[String]],
        selectedRow: Int,
        selectedColumn: Int
    ) {
        guard let storage = editorTextView.textStorage,
              !rows.isEmpty,
              rows.allSatisfy({ $0.count == rows[0].count }),
              rows[0].count >= 2 else {
            return
        }

        let lines = rows.enumerated().flatMap { rowIndex, row -> [String] in
            let rowLine = markdownTableLine(cells: row)
            guard rowIndex == 0 else { return [rowLine] }
            return [rowLine, markdownTableLine(cells: Array(repeating: "---", count: row.count))]
        }
        let source = lines.joined(separator: "\n")
        let rendered = MarkdownRichTextCodec.render(
            markdown: source,
            theme: theme,
            baseURL: selectedURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )

        suppressEditorChanges = true
        storage.replaceCharacters(in: snapshot.tableRange, with: rendered)
        suppressEditorChanges = false
        markDirty()

        if let replacement = richMarkdownTableSnapshot(atCharacterIndex: snapshot.tableRange.location, in: storage),
           replacement.cellRanges.indices.contains(selectedRow),
           replacement.cellRanges[selectedRow].indices.contains(selectedColumn) {
            moveEditorSelection(to: replacement.cellRanges[selectedRow][selectedColumn].location)
        } else {
            moveEditorSelection(to: snapshot.tableRange.location)
        }
    }

    func tableAttributeString(
        _ key: NSAttributedString.Key,
        at location: Int,
        in attributedString: NSAttributedString
    ) -> String? {
        attributedString.attribute(key, at: location, effectiveRange: nil) as? String
    }

    func tableAttributeInteger(
        _ key: NSAttributedString.Key,
        at location: Int,
        in attributedString: NSAttributedString
    ) -> Int? {
        if let value = attributedString.attribute(key, at: location, effectiveRange: nil) as? Int {
            return value
        }
        return (attributedString.attribute(key, at: location, effectiveRange: nil) as? NSNumber)?.intValue
    }

    func moveEditorSelection(to location: Int) {
        guard let storage = editorTextView.textStorage else { return }
        editorTextView.setSelectedRange(NSRange(location: max(0, min(location, storage.length)), length: 0))
        updateTypingAttributesFromInsertionPoint()
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
    }

    func lineRange(after range: NSRange, in string: NSString) -> NSRange? {
        let nextLocation = NSMaxRange(string.lineRange(for: range))
        guard nextLocation < string.length else { return nil }
        let paragraphRange = string.paragraphRange(for: NSRange(location: nextLocation, length: 0))
        let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
        return NSRange(
            location: paragraphRange.location,
            length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
        )
    }

    func lineRange(before range: NSRange, in string: NSString) -> NSRange? {
        guard range.location > 0 else { return nil }
        let previousProbeLocation = max(range.location - 1, 0)
        let paragraphRange = string.paragraphRange(for: NSRange(location: previousProbeLocation, length: 0))
        let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
        return NSRange(
            location: paragraphRange.location,
            length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
        )
    }

    func adjacentMarkdownTableDataRow(after range: NSRange, in string: NSString) -> NSRange? {
        var candidate = lineRange(after: range, in: string)
        while let candidateRange = candidate {
            let line = string.substring(with: candidateRange)
            guard markdownTableColumnCount(in: line) != nil else { return nil }
            if !isMarkdownTableSeparatorLine(line) {
                return candidateRange
            }
            candidate = lineRange(after: candidateRange, in: string)
        }
        return nil
    }

    func adjacentMarkdownTableDataRow(before range: NSRange, in string: NSString) -> NSRange? {
        var candidate = lineRange(before: range, in: string)
        while let candidateRange = candidate {
            let line = string.substring(with: candidateRange)
            guard markdownTableColumnCount(in: line) != nil else { return nil }
            if !isMarkdownTableSeparatorLine(line) {
                return candidateRange
            }
            candidate = lineRange(before: candidateRange, in: string)
        }
        return nil
    }

    func markdownTableLocation(atCharacterIndex characterIndex: Int, in string: NSString) -> MarkdownTableLocation? {
        guard string.length > 0 else { return nil }
        let safeLocation = max(0, min(characterIndex, string.length))
        let lineRange = visibleLineRange(atCharacterIndex: safeLocation, in: string)
        let line = string.substring(with: lineRange)
        guard let columnCount = markdownTableColumnCount(in: line),
              let columnIndex = markdownTableCellIndex(at: safeLocation, lineRange: lineRange, in: string) else {
            return nil
        }
        return MarkdownTableLocation(lineRange: lineRange, columnIndex: min(columnIndex, columnCount - 1), columnCount: columnCount)
    }

    func markdownTableLineRanges(containing range: NSRange, in string: NSString) -> [NSRange]? {
        guard markdownTableColumnCount(in: string.substring(with: range)) != nil else { return nil }

        var firstRange = range
        while let previousRange = lineRange(before: firstRange, in: string),
              markdownTableColumnCount(in: string.substring(with: previousRange)) != nil {
            firstRange = previousRange
        }

        var ranges = [firstRange]
        var currentRange = firstRange
        while let nextRange = lineRange(after: currentRange, in: string),
              markdownTableColumnCount(in: string.substring(with: nextRange)) != nil {
            ranges.append(nextRange)
            currentRange = nextRange
        }

        return ranges
    }

    func markdownTableColumnCount(atCharacterIndex characterIndex: Int) -> Int? {
        let string = editorTextView.string as NSString
        guard string.length > 0 else { return nil }
        return markdownTableLocation(atCharacterIndex: characterIndex, in: string)?.columnCount
    }

    func isMarkdownTableDataRow(atCharacterIndex characterIndex: Int) -> Bool {
        let string = editorTextView.string as NSString
        guard string.length > 0 else { return false }
        guard let tableLocation = markdownTableLocation(atCharacterIndex: characterIndex, in: string) else { return false }
        let visibleLineRange = tableLocation.lineRange
        let line = string.substring(with: visibleLineRange)
        return markdownTableColumnCount(in: line) != nil
            && !isMarkdownTableSeparatorLine(line)
            && isMarkdownTableDataRow(visibleLineRange, in: string)
    }

    func visibleLineRange(atCharacterIndex characterIndex: Int, in string: NSString) -> NSRange {
        let lineRange = string.paragraphRange(for: NSRange(location: max(0, min(characterIndex, string.length)), length: 0))
        let hasTrailingNewline = string.substring(with: lineRange).hasSuffix("\n")
        return NSRange(
            location: lineRange.location,
            length: max(lineRange.length - (hasTrailingNewline ? 1 : 0), 0)
        )
    }

    func isMarkdownTableDataRow(_ range: NSRange, in string: NSString) -> Bool {
        if let nextLineRange = lineRange(after: range, in: string) {
            let nextLine = string.substring(with: nextLineRange)
            if isMarkdownTableSeparatorLine(nextLine) {
                return false
            }
            if markdownTableColumnCount(in: nextLine) != nil {
                return true
            }
        }

        if let previousLineRange = lineRange(before: range, in: string) {
            let previousLine = string.substring(with: previousLineRange)
            if isMarkdownTableSeparatorLine(previousLine) {
                return true
            }
            return markdownTableColumnCount(in: previousLine) != nil
        }

        return false
    }

    func fullLineDeletionRange(for range: NSRange, in string: NSString) -> NSRange {
        let fullLineRange = string.lineRange(for: range)
        if NSMaxRange(fullLineRange) > NSMaxRange(range) {
            return fullLineRange
        }

        if range.location > 0,
           string.substring(with: NSRange(location: range.location - 1, length: 1)) == "\n" {
            return NSRange(location: range.location - 1, length: range.length + 1)
        }

        return fullLineRange
    }

    func markdownTableColumnCount(in line: String) -> Int? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }

        let columns = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
        let count = columns.count
        return count >= 2 ? count : nil
    }

    func isMarkdownTableSeparatorLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard markdownTableColumnCount(in: trimmed) != nil else { return false }

        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return cells.allSatisfy { cell in
            let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
        }
    }

    func emptyMarkdownTableRow(columnCount: Int) -> String {
        "| " + Array(repeating: " ", count: max(columnCount, 2)).joined(separator: " | ") + " |"
    }

    func markdownTableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard markdownTableColumnCount(in: trimmed) != nil else { return nil }
        return trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func markdownTableLine(cells: [String]) -> String {
        "| " + cells.joined(separator: " | ") + " |"
    }

    func markdownTableCellStartLocations(in line: String, lineStartLocation: Int) -> [Int]? {
        let lineString = line as NSString
        let pipeIndexes = markdownTablePipeIndexes(in: lineString)
        guard pipeIndexes.count >= 3 else { return nil }

        return (0..<(pipeIndexes.count - 1)).map { index in
            var start = pipeIndexes[index] + 1
            while start < pipeIndexes[index + 1],
                  lineString.substring(with: NSRange(location: start, length: 1)) == " " {
                start += 1
            }
            return lineStartLocation + min(start, pipeIndexes[index + 1])
        }
    }

    func markdownTableCellIndex(at location: Int, lineRange: NSRange, in string: NSString) -> Int? {
        let lineString = string.substring(with: lineRange) as NSString
        let pipeIndexes = markdownTablePipeIndexes(in: lineString)
        guard pipeIndexes.count >= 3 else { return nil }

        let localLocation = max(0, min(location - lineRange.location, lineString.length))
        for index in 0..<(pipeIndexes.count - 1) {
            if localLocation <= pipeIndexes[index + 1] {
                return index
            }
        }
        return pipeIndexes.count - 2
    }

    func markdownTablePipeIndexes(in line: NSString) -> [Int] {
        var indexes: [Int] = []
        for index in 0..<line.length where line.substring(with: NSRange(location: index, length: 1)) == "|" {
            indexes.append(index)
        }
        return indexes
    }
}
