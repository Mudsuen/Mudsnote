import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore

enum MarkdownRichTextCodec {
    private static let tablePlaceholder = "\u{200B}"
    @MainActor
    private static let automaticLinkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    private struct ParsedMarkdownTable {
        let rows: [[String]]
        let alignments: [String]
        let consumedLineCount: Int
    }

    @MainActor
    static func render(
        markdown: String,
        theme: MarkdownEditorTheme,
        baseURL: URL? = nil,
        imageDisplayWidthProvider: ((URL) -> Double?)? = nil
    ) -> NSMutableAttributedString {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let output = NSMutableAttributedString()

        var lineIndex = 0
        while lineIndex < lines.count {
            if let table = parsedMarkdownTable(in: lines, startingAt: lineIndex) {
                let nextLineIndex = lineIndex + table.consumedLineCount
                output.append(renderTable(
                    rows: table.rows,
                    alignments: table.alignments,
                    representsFollowingMarkdownLine: nextLineIndex < lines.count,
                    theme: theme,
                    baseURL: baseURL
                ))
                lineIndex = nextLineIndex
                continue
            }

            let firstLine = removingHardLineBreakMarker(from: lines[lineIndex])
            let kind = paragraphKind(for: firstLine)
            output.append(renderLine(firstLine, theme: theme, baseURL: baseURL))

            while hasHardLineBreakMarker(lines[lineIndex]), lineIndex + 1 < lines.count {
                lineIndex += 1
                output.append(NSAttributedString(
                    string: "\u{2028}",
                    attributes: theme.baseAttributes(for: kind)
                ))
                let continuation = removingHardLineBreakMarker(from: lines[lineIndex])
                output.append(parseInlineMarkdown(
                    continuation,
                    paragraphKind: kind,
                    theme: theme,
                    baseURL: baseURL
                ))
            }
            if lineIndex < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph)))
            }
            lineIndex += 1
        }

        if let imageDisplayWidthProvider {
            applyImageDisplayWidths(
                to: output,
                imageDisplayWidthProvider: imageDisplayWidthProvider
            )
        }
        return output
    }

    private static func applyImageDisplayWidths(
        to attributedString: NSAttributedString,
        imageDisplayWidthProvider: (URL) -> Double?
    ) {
        attributedString.enumerateAttribute(
            .qmImageFilePath,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, range, _ in
            guard let path = value as? String,
                  let attachment = attributedString.attribute(
                    .attachment,
                    at: range.location,
                    effectiveRange: nil
                  ) as? NSTextAttachment,
                  let naturalSize = naturalImageSize(for: attachment) else {
                return
            }
            let displaySize = MarkdownImageDisplaySizing.displaySize(
                for: naturalSize,
                preferredWidth: imageDisplayWidthProvider(URL(fileURLWithPath: path))
            )
            attachment.bounds = NSRect(
                x: 0,
                y: -4,
                width: displaySize.width,
                height: displaySize.height
            )
        }
    }

    static func naturalImageSize(for attachment: NSTextAttachment) -> NSSize? {
        if let cell = attachment.attachmentCell as? AsyncImageAttachmentCell {
            return cell.naturalSize
        }
        return attachment.image?.size
    }

    @MainActor
    static func renderLine(_ line: String, theme: MarkdownEditorTheme, baseURL: URL? = nil) -> NSMutableAttributedString {
        let kind = paragraphKind(for: line)
        let paragraphString = NSMutableAttributedString()
        let baseAttributes = theme.baseAttributes(for: kind)

        let prefix = kind.prefix
        if !prefix.isEmpty {
            paragraphString.append(renderPrefix(for: kind, theme: theme, baseAttributes: baseAttributes))
        }

        let content = markdownContent(from: line, kind: kind)
        paragraphString.append(parseInlineMarkdown(content, paragraphKind: kind, theme: theme, baseURL: baseURL))

        if paragraphString.length == 0 {
            paragraphString.append(NSAttributedString(string: "", attributes: baseAttributes))
        } else {
            paragraphString.addAttribute(.paragraphStyle, value: theme.paragraphStyle(for: kind), range: NSRange(location: 0, length: paragraphString.length))
            paragraphString.addAttribute(.qmParagraphKind, value: kind.encodedValue, range: NSRange(location: 0, length: paragraphString.length))
        }

        return paragraphString
    }

    static func serialize(_ attributedString: NSAttributedString, theme: MarkdownEditorTheme) -> String {
        let nsString = attributedString.string as NSString
        let context = SerializationContext(attributedString: attributedString)
        var lines: [String] = []
        var location = 0

        while location < nsString.length {
            if let table = serializedTable(
                startingAt: location,
                in: attributedString,
                theme: theme,
                context: context
            ) {
                lines.append(table.markdown)
                location = table.endLocation
                continue
            }

            let remainingRange = NSRange(location: location, length: nsString.length - location)
            let newlineRange = nsString.range(of: "\n", options: [], range: remainingRange)
            let hasTrailingNewline = newlineRange.location != NSNotFound
            let lineRange = NSRange(
                location: location,
                length: hasTrailingNewline ? newlineRange.location - location : nsString.length - location
            )
            let lineText = nsString.substring(with: lineRange)
            lines.append(serializeLine(
                range: lineRange,
                visibleText: lineText,
                in: attributedString,
                theme: theme,
                context: context
            ))
            location = hasTrailingNewline ? NSMaxRange(newlineRange) : nsString.length
        }

        if nsString.length == 0 {
            return ""
        }

        if attributedString.string.hasSuffix("\n") {
            let finalLocation = attributedString.length - 1
            if attributedString.attribute(.qmTableID, at: finalLocation, effectiveRange: nil) != nil,
               attributedString.attribute(.qmTableTerminalNewline, at: finalLocation, effectiveRange: nil) == nil {
                return lines.joined(separator: "\n")
            }
            return lines.joined(separator: "\n") + "\n"
        }

        return lines.joined(separator: "\n")
    }

    @MainActor
    private static func renderTable(
        rows: [[String]],
        alignments: [String],
        representsFollowingMarkdownLine: Bool,
        theme: MarkdownEditorTheme,
        baseURL: URL?
    ) -> NSAttributedString {
        guard let columnCount = rows.first?.count, columnCount >= 2 else {
            return NSAttributedString()
        }

        let tableID = UUID().uuidString
        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true
        table.hidesEmptyCells = false
        // Keep the trailing stroke inside the text container's drawable bounds.
        table.setContentWidth(99.25, type: .percentageValueType)

        let output = NSMutableAttributedString()
        for (rowIndex, row) in rows.enumerated() {
            for columnIndex in 0..<columnCount {
                let block = NSTextTableBlock(
                    table: table,
                    startingRow: rowIndex,
                    rowSpan: 1,
                    startingColumn: columnIndex,
                    columnSpan: 1
                )
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(panelSeparatorColor(alpha: 0.5))
                block.setWidth(9, type: .absoluteValueType, for: .padding, edge: .minX)
                block.setWidth(9, type: .absoluteValueType, for: .padding, edge: .maxX)
                block.setWidth(6, type: .absoluteValueType, for: .padding, edge: .minY)
                block.setWidth(6, type: .absoluteValueType, for: .padding, edge: .maxY)
                if rowIndex == 0 {
                    block.backgroundColor = panelPrimaryTextColor().withAlphaComponent(0.09)
                }

                let paragraphStyle = theme.paragraphStyle(for: .paragraph).mutableCopy() as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()
                paragraphStyle.textBlocks = [block]
                paragraphStyle.paragraphSpacing = 0
                paragraphStyle.lineSpacing = 0

                let rawContent = row.indices.contains(columnIndex) ? row[columnIndex] : ""
                let isPlaceholder = rawContent.isEmpty
                let visibleContent = isPlaceholder ? tablePlaceholder : rawContent
                let cell = parseInlineMarkdown(
                    visibleContent,
                    paragraphKind: .paragraph,
                    theme: theme,
                    baseURL: baseURL
                )
                let cellRange = NSRange(location: 0, length: cell.length)
                cell.addAttributes([
                    .paragraphStyle: paragraphStyle,
                    .qmParagraphKind: MarkdownParagraphKind.paragraph.encodedValue,
                    .qmTableID: tableID,
                    .qmTableRow: rowIndex,
                    .qmTableColumn: columnIndex,
                    .qmTableColumnCount: columnCount,
                    .qmTableColumnAlignment: alignments.indices.contains(columnIndex)
                        ? alignments[columnIndex]
                        : "---"
                ], range: cellRange)
                if isPlaceholder {
                    cell.addAttribute(.qmTablePlaceholder, value: true, range: cellRange)
                }
                output.append(cell)

                let newlineAttributes = cell.length > 0
                    ? cell.attributes(at: max(cell.length - 1, 0), effectiveRange: nil)
                    : theme.baseAttributes(for: .paragraph)
                output.append(NSAttributedString(string: "\n", attributes: newlineAttributes))
            }
        }
        if representsFollowingMarkdownLine, output.length > 0 {
            output.addAttribute(
                .qmTableTerminalNewline,
                value: true,
                range: NSRange(location: output.length - 1, length: 1)
            )
        }
        return output
    }

    private static func parsedMarkdownTable(in lines: [String], startingAt index: Int) -> ParsedMarkdownTable? {
        guard index + 1 < lines.count,
              let header = markdownTableCells(in: lines[index]),
              let separator = markdownTableCells(in: lines[index + 1]),
              header.count == separator.count,
              separator.allSatisfy(isMarkdownTableSeparatorCell) else {
            return nil
        }
        let alignments = separator.compactMap(markdownTableAlignment)
        guard alignments.count == header.count else { return nil }

        var rows = [header]
        var nextIndex = index + 2
        while nextIndex < lines.count,
              let row = markdownTableCells(in: lines[nextIndex]),
              row.count == header.count,
              !row.allSatisfy(isMarkdownTableSeparatorCell) {
            rows.append(row)
            nextIndex += 1
        }
        return ParsedMarkdownTable(
            rows: rows,
            alignments: alignments,
            consumedLineCount: nextIndex - index
        )
    }

    private static func markdownTableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }
        let interior = trimmed.dropFirst().dropLast()
        var cells: [String] = []
        var cell = ""
        var pendingBackslashes = 0

        func appendPendingBackslashes(removingEscape: Bool = false) {
            let count = max(pendingBackslashes - (removingEscape ? 1 : 0), 0)
            if count > 0 {
                cell.append(String(repeating: "\\", count: count))
            }
            pendingBackslashes = 0
        }

        for character in interior {
            if character == "\\" {
                pendingBackslashes += 1
                continue
            }
            if character == "|" {
                if pendingBackslashes > 0 {
                    appendPendingBackslashes(removingEscape: true)
                    cell.append("|")
                } else {
                    cells.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
                    cell = ""
                }
                continue
            }
            appendPendingBackslashes()
            cell.append(character)
        }
        appendPendingBackslashes()
        cells.append(cell.trimmingCharacters(in: .whitespacesAndNewlines))
        return cells.count >= 2 ? cells : nil
    }

    private static func isMarkdownTableSeparatorCell(_ cell: String) -> Bool {
        let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
    }

    private static func markdownTableAlignment(_ cell: String) -> String? {
        guard isMarkdownTableSeparatorCell(cell) else { return nil }
        let hasLeadingColon = cell.hasPrefix(":")
        let hasTrailingColon = cell.hasSuffix(":")
        switch (hasLeadingColon, hasTrailingColon) {
        case (true, true): return ":---:"
        case (true, false): return ":---"
        case (false, true): return "---:"
        case (false, false): return "---"
        }
    }

    private static func serializedTable(
        startingAt location: Int,
        in attributedString: NSAttributedString,
        theme: MarkdownEditorTheme,
        context: SerializationContext
    ) -> (markdown: String, endLocation: Int)? {
        guard location >= 0, location < attributedString.length,
              let tableID = attributedString.attribute(.qmTableID, at: location, effectiveRange: nil) as? String else {
            return nil
        }

        let nsString = attributedString.string as NSString
        var rows: [Int: [Int: String]] = [:]
        var alignments: [Int: String] = [:]
        var columnCount = 0
        var cursor = location

        while cursor < nsString.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: cursor, length: 0))
            let contentLength = max(
                paragraphRange.length - (nsString.substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0),
                0
            )
            let contentRange = NSRange(location: paragraphRange.location, length: contentLength)
            let metadataLocation = contentRange.length > 0 ? contentRange.location : paragraphRange.location
            guard metadataLocation < attributedString.length,
                  attributedString.attribute(.qmTableID, at: metadataLocation, effectiveRange: nil) as? String == tableID,
                  let row = attributedString.attribute(.qmTableRow, at: metadataLocation, effectiveRange: nil) as? Int,
                  let column = attributedString.attribute(.qmTableColumn, at: metadataLocation, effectiveRange: nil) as? Int else {
                break
            }

            columnCount = max(
                columnCount,
                attributedString.attribute(.qmTableColumnCount, at: metadataLocation, effectiveRange: nil) as? Int ?? 0
            )
            if alignments[column] == nil,
               let alignment = attributedString.attribute(
                   .qmTableColumnAlignment,
                   at: metadataLocation,
                   effectiveRange: nil
               ) as? String {
                alignments[column] = alignment
            }
            let markdown = serializeInline(
                range: contentRange,
                in: attributedString,
                paragraphKind: .paragraph,
                theme: theme,
                context: context
            )
                .replacingOccurrences(of: tablePlaceholder, with: "")
                .replacingOccurrences(of: "|", with: "\\|")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            rows[row, default: [:]][column] = markdown
            cursor = NSMaxRange(paragraphRange)
        }

        guard columnCount >= 2, let maximumRow = rows.keys.max() else { return nil }
        var markdownLines: [String] = []
        for row in 0...maximumRow {
            let cells = (0..<columnCount).map { rows[row]?[$0] ?? "" }
            markdownLines.append("| " + cells.joined(separator: " | ") + " |")
            if row == 0 {
                let separatorCells = (0..<columnCount).map { alignments[$0] ?? "---" }
                markdownLines.append("| " + separatorCells.joined(separator: " | ") + " |")
            }
        }
        return (markdownLines.joined(separator: "\n"), cursor)
    }

    static func paragraphKind(at range: NSRange, in attributedString: NSAttributedString) -> MarkdownParagraphKind {
        if range.length == 0 {
            return .paragraph
        }

        if let kind = storedParagraphKind(at: range, in: attributedString) {
            if kind.isListKind, !visibleListPrefixIsComplete(for: kind, in: range, attributedString: attributedString) {
                let visibleText = (attributedString.string as NSString).substring(with: range)
                return inferredParagraphKind(fromVisibleText: visibleText)
            }
            return kind
        }

        let visibleText = (attributedString.string as NSString).substring(with: range)
        return inferredParagraphKind(fromVisibleText: visibleText)
    }

    static func storedParagraphKind(at range: NSRange, in attributedString: NSAttributedString) -> MarkdownParagraphKind? {
        guard range.length > 0 else { return nil }
        guard range.location >= 0, range.location < attributedString.length else { return nil }
        guard let encoded = attributedString.attribute(.qmParagraphKind, at: range.location, effectiveRange: nil) else {
            return nil
        }
        return MarkdownParagraphKind.decode(encoded)
    }

    static func applyParagraphKind(_ kind: MarkdownParagraphKind, to range: NSRange, in textStorage: NSTextStorage, theme: MarkdownEditorTheme) {
        let attributes = theme.baseAttributes(for: kind)
        textStorage.addAttributes(attributes, range: range)

        let prefixLength = visiblePrefixLength(for: range, in: textStorage, kind: kind)
        if prefixLength > 0, prefixLength <= range.length {
            textStorage.addAttributes([
                .foregroundColor: theme.mutedTextColor,
                .qmParagraphKind: kind.encodedValue
            ], range: NSRange(location: range.location, length: prefixLength))
        }
    }

    static func shouldInterpretMarkdown(in text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        if firstMatch(#"^\s*[-*+]\s$"#, in: text) != nil {
            return true
        }

        return trimmed.hasPrefix("#")
            || trimmed.hasPrefix("- ")
            || trimmed.hasPrefix("* ")
            || trimmed.hasPrefix("+ ")
            || trimmed.hasPrefix("[]")
            || trimmed.hasPrefix("[ ]")
            || trimmed.hasPrefix("【】")
            || trimmed.hasPrefix("1.")
            || trimmed.contains(" #")
            || trimmed.hasPrefix("#")
            || trimmed.contains("**")
            || trimmed.contains("~~")
            || trimmed.contains("`")
            || trimmed.contains("[")
            || trimmed.contains("<u>")
    }

    static func markdownLine(for kind: MarkdownParagraphKind, inlineContent: String) -> String {
        switch kind {
        case .paragraph:
            return inlineContent
        case .heading(let level):
            guard !inlineContent.isEmpty else { return String(repeating: "#", count: max(level, 1)) + " " }
            return String(repeating: "#", count: max(level, 1)) + " " + inlineContent
        case .bullet:
            return "- " + inlineContent
        case .ordered(let index):
            return "\(max(index, 1)). " + inlineContent
        case .checklist(let checked):
            return checked ? "- [x] " + inlineContent : "- [ ] " + inlineContent
        }
    }

    static func visibleContentRange(for range: NSRange, in attributedString: NSAttributedString, kind: MarkdownParagraphKind) -> NSRange {
        rangeAfterVisiblePrefix(for: range, in: attributedString, kind: kind)
    }

    static func serializeVisibleContent(
        range: NSRange,
        in attributedString: NSAttributedString,
        paragraphKind: MarkdownParagraphKind,
        theme: MarkdownEditorTheme
    ) -> String {
        serializeInline(
            range: range,
            in: attributedString,
            paragraphKind: paragraphKind,
            theme: theme,
            context: SerializationContext(attributedString: attributedString)
        )
    }

    private static func serializeLine(
        range: NSRange,
        visibleText: String,
        in attributedString: NSAttributedString,
        theme: MarkdownEditorTheme,
        context: SerializationContext
    ) -> String {
        let kind = paragraphKind(at: range, in: attributedString)
        let contentRange = rangeAfterVisiblePrefix(for: range, in: attributedString, kind: kind)
        let contentMarkdown = serializeInline(
            range: contentRange,
            in: attributedString,
            paragraphKind: kind,
            theme: theme,
            context: context
        )

        switch kind {
        case .paragraph:
            return contentMarkdown
        case .heading(let level):
            guard !contentMarkdown.isEmpty else { return "" }
            return String(repeating: "#", count: max(level, 1)) + " " + contentMarkdown
        case .bullet:
            return contentMarkdown.isEmpty ? "- " : "- " + contentMarkdown
        case .ordered(let index):
            return "\(max(index, 1)). " + contentMarkdown
        case .checklist(let checked):
            let marker = checked ? "- [x] " : "- [ ] "
            return marker + contentMarkdown
        }
    }

    private static func serializeInline(
        range: NSRange,
        in attributedString: NSAttributedString,
        paragraphKind: MarkdownParagraphKind,
        theme: MarkdownEditorTheme,
        context: SerializationContext
    ) -> String {
        guard range.length > 0 else { return "" }

        var markdown = ""
        var location = range.location
        let baseFont = theme.font(for: paragraphKind)

        while location < NSMaxRange(range) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = attributedString.attributes(at: location, effectiveRange: &effectiveRange)
            let clippedRange = NSIntersectionRange(effectiveRange, range)
            let text = context.string.substring(with: clippedRange)
            markdown += serializeRun(
                text: text,
                attributes: attributes,
                baseFont: baseFont,
                context: context
            )
            location = NSMaxRange(clippedRange)
        }

        return markdown
    }

    private static func serializeRun(
        text: String,
        attributes: [NSAttributedString.Key: Any],
        baseFont: NSFont,
        context: SerializationContext
    ) -> String {
        if text.isEmpty { return "" }

        if let imageMarkdown = attributes[.qmImageMarkdown] as? String {
            return imageMarkdown
        }

        if let attachmentMarkdown = attributes[.qmAttachmentMarkdown] as? String {
            return attachmentMarkdown
        }

        if (attributes[.qmTag] as? Bool) == true {
            return text
        }

        if (attributes[.qmAutomaticLink] as? Bool) == true {
            return text
        }

        if let url = attributes[.qmLinkURL] as? String {
            return "[\(text)](\(url))"
        }

        var wrapped = text.replacingOccurrences(of: "\u{2028}", with: "  \n")

        if (attributes[.qmCode] as? Bool) == true {
            return "`\(wrapped)`"
        }

        if let underline = attributes[.underlineStyle] as? Int, underline != 0 {
            wrapped = "<u>\(wrapped)</u>"
        }

        if let strike = attributes[.strikethroughStyle] as? Int, strike != 0 {
            wrapped = "~~\(wrapped)~~"
        }

        if let font = attributes[.font] as? NSFont {
            let traits = context.traits(for: font)
            let baseTraits = context.traits(for: baseFont)
            let isBold = traits.contains(.boldFontMask) && !baseTraits.contains(.boldFontMask)
            let isItalic = (traits.contains(.italicFontMask) && !baseTraits.contains(.italicFontMask))
                || isObliqued(attributes[.obliqueness])

            if isBold && isItalic {
                wrapped = "***\(wrapped)***"
            } else if isBold {
                wrapped = "**\(wrapped)**"
            } else if isItalic {
                wrapped = "*\(wrapped)*"
            }
        }

        if (attributes[.qmHighlight] as? Bool) == true {
            wrapped = "<mark>\(wrapped)</mark>"
        }

        return wrapped
    }

    private static func hasHardLineBreakMarker(_ line: String) -> Bool {
        line.hasSuffix("  ")
    }

    private static func removingHardLineBreakMarker(from line: String) -> String {
        guard hasHardLineBreakMarker(line) else { return line }
        return String(line.dropLast(2))
    }

    private final class SerializationContext {
        let string: NSString
        private var traitsByFont: [ObjectIdentifier: NSFontTraitMask] = [:]

        init(attributedString: NSAttributedString) {
            string = attributedString.string as NSString
        }

        func traits(for font: NSFont) -> NSFontTraitMask {
            let identity = ObjectIdentifier(font)
            if let cached = traitsByFont[identity] {
                return cached
            }

            let traits = NSFontManager.shared.traits(of: font)
            traitsByFont[identity] = traits
            return traits
        }
    }

    private static func paragraphKind(for line: String) -> MarkdownParagraphKind {
        let nsLine = line as NSString

        if let match = firstMatch(#"^(#{1,6})\s+(.+)$"#, in: line) {
            let hashes = nsLine.substring(with: match.range(at: 1))
            return .heading(level: hashes.count)
        }

        if firstMatch(#"^\s*(?:\[\]|\[\s\]|【】)\s*(.*)$"#, in: line) != nil {
            return .checklist(checked: false)
        }

        if let match = firstMatch(#"^\s*[-*+]\s+\[( |x|X)\]\s*(.*)$"#, in: line) {
            let checkedRaw = nsLine.substring(with: match.range(at: 1)).lowercased()
            return .checklist(checked: checkedRaw == "x")
        }

        if firstMatch(#"^\s*[-*+]\s+(.*)$"#, in: line) != nil {
            return .bullet
        }

        if let match = firstMatch(#"^\s*(\d+)\.\s*(.*)$"#, in: line) {
            let index = Int(nsLine.substring(with: match.range(at: 1))) ?? 1
            return .ordered(index: index)
        }

        return .paragraph
    }

    private static func inferredParagraphKind(fromVisibleText line: String) -> MarkdownParagraphKind {
        if line.hasPrefix("\u{2022} ") {
            return .bullet
        }
        if line.hasPrefix("\u{2610} ") {
            return .checklist(checked: false)
        }
        if line.hasPrefix("\u{2611} ") {
            return .checklist(checked: true)
        }
        if let match = firstMatch(#"^(\d+)\.\s"#, in: line) {
            let index = Int((line as NSString).substring(with: match.range(at: 1))) ?? 1
            return .ordered(index: index)
        }
        return .paragraph
    }

    private static func markdownContent(from line: String, kind: MarkdownParagraphKind) -> String {
        let nsLine = line as NSString

        switch kind {
        case .heading:
            return capture(#"^(#{1,6})\s+(.+)$"#, in: line, group: 2) ?? line
        case .bullet:
            return capture(#"^\s*[-*+]\s+(.*)$"#, in: line, group: 1) ?? line
        case .ordered:
            return capture(#"^\s*\d+\.\s*(.*)$"#, in: line, group: 1) ?? line
        case .checklist:
            if let content = capture(#"^\s*(?:\[\]|\[\s\]|【】)\s*(.*)$"#, in: line, group: 1) {
                return content
            }
            return capture(#"^\s*[-*+]\s+\[(?: |x|X)\]\s*(.*)$"#, in: line, group: 1) ?? nsLine.substring(from: 0)
        case .paragraph:
            return line
        }
    }

    @MainActor
    private static func parseInlineMarkdown(
        _ source: String,
        paragraphKind: MarkdownParagraphKind,
        theme: MarkdownEditorTheme,
        baseURL: URL? = nil
    ) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        let baseAttributes = theme.baseAttributes(for: paragraphKind)
        var index = source.startIndex

        while index < source.endIndex {
            if source[index...].hasPrefix("!["),
               let closeBracket = source[source.index(index, offsetBy: 2)...].range(of: "]("),
               let closeParen = closingLinkParenthesis(in: source, after: closeBracket.upperBound) {
                let label = String(source[source.index(index, offsetBy: 2)..<closeBracket.lowerBound])
                let path = String(source[closeBracket.upperBound..<closeParen])
                let markdown = String(source[index...closeParen])
                if let imageAttachment = imageAttachmentString(
                    label: label,
                    path: path,
                    markdown: markdown,
                    paragraphKind: paragraphKind,
                    theme: theme,
                    baseAttributes: baseAttributes,
                    baseURL: baseURL
                ) {
                    output.append(imageAttachment)
                    index = source.index(after: closeParen)
                    continue
                }
            }

            if source[index...].hasPrefix("**"),
               let end = source[index...].dropFirst(2).range(of: "**") {
                let content = String(source[source.index(index, offsetBy: 2)..<end.lowerBound])
                output.append(attributed(content, base: baseAttributes, extra: [.font: theme.boldFont]))
                index = end.upperBound
                continue
            }

            if source[index...].hasPrefix("*"),
               let end = source[source.index(after: index)...].range(of: "*") {
                let content = String(source[source.index(after: index)..<end.lowerBound])
                output.append(attributed(content, base: baseAttributes, extra: [
                    .font: theme.italicFont,
                    .obliqueness: markdownItalicObliqueness
                ]))
                index = end.upperBound
                continue
            }

            if source[index...].hasPrefix("~~"),
               let end = source[index...].dropFirst(2).range(of: "~~") {
                let content = String(source[source.index(index, offsetBy: 2)..<end.lowerBound])
                output.append(attributed(content, base: baseAttributes, extra: [.strikethroughStyle: NSUnderlineStyle.single.rawValue]))
                index = end.upperBound
                continue
            }

            if source[index...].hasPrefix("<u>"),
               let end = source[index...].range(of: "</u>") {
                let contentStart = source.index(index, offsetBy: 3)
                let content = String(source[contentStart..<end.lowerBound])
                output.append(attributed(content, base: baseAttributes, extra: [.underlineStyle: NSUnderlineStyle.single.rawValue]))
                index = end.upperBound
                continue
            }

            if source[index...].hasPrefix("<mark>"),
               let end = source[index...].range(of: "</mark>") {
                let contentStart = source.index(index, offsetBy: 6)
                let content = String(source[contentStart..<end.lowerBound])
                let highlighted = parseInlineMarkdown(
                    content,
                    paragraphKind: paragraphKind,
                    theme: theme,
                    baseURL: baseURL
                )
                if highlighted.length > 0 {
                    highlighted.addAttributes([
                        .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.38),
                        .qmHighlight: true
                    ], range: NSRange(location: 0, length: highlighted.length))
                }
                output.append(highlighted)
                index = end.upperBound
                continue
            }

            if source[index...].hasPrefix("`"),
               let end = source[source.index(after: index)...].range(of: "`") {
                let content = String(source[source.index(after: index)..<end.lowerBound])
                guard !content.isEmpty else {
                    output.append(attributed(String(source[index]), base: baseAttributes))
                    index = source.index(after: index)
                    continue
                }
                output.append(attributed(content, base: baseAttributes, extra: [.font: theme.codeFont, .qmCode: true, .foregroundColor: theme.accentColor]))
                index = end.upperBound
                continue
            }

            if source[index...].hasPrefix("["),
               let closeBracket = source[index...].range(of: "]("),
               let closeParen = closingLinkParenthesis(in: source, after: closeBracket.upperBound) {
                let label = String(source[source.index(after: index)..<closeBracket.lowerBound])
                let url = String(source[closeBracket.upperBound..<closeParen])
                let markdown = String(source[index...closeParen])
                if let attachment = fileAttachmentString(
                    label: label,
                    path: url,
                    markdown: markdown,
                    paragraphKind: paragraphKind,
                    theme: theme,
                    baseAttributes: baseAttributes,
                    baseURL: baseURL
                ) {
                    output.append(attachment)
                    index = source.index(after: closeParen)
                    continue
                }
                output.append(attributed(label, base: baseAttributes, extra: [
                    .foregroundColor: theme.accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .qmLinkURL: url
                ]))
                index = source.index(after: closeParen)
                continue
            }

            output.append(attributed(String(source[index]), base: baseAttributes))
            index = source.index(after: index)
        }

        if output.length == 0 {
            output.append(NSAttributedString(string: "", attributes: baseAttributes))
        }
        applyAutomaticLinks(in: output, range: NSRange(location: 0, length: output.length), theme: theme)
        return output
    }

    private static func closingLinkParenthesis(
        in source: String,
        after destinationStart: String.Index
    ) -> String.Index? {
        var nestedDepth = 0
        var isEscaped = false
        var cursor = destinationStart
        while cursor < source.endIndex {
            let character = source[cursor]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "(" {
                nestedDepth += 1
            } else if character == ")" {
                if nestedDepth == 0 {
                    return cursor
                }
                nestedDepth -= 1
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    @MainActor
    static func refreshAutomaticLinks(
        in textStorage: NSTextStorage,
        around location: Int,
        theme: MarkdownEditorTheme
    ) {
        guard textStorage.length > 0,
              var refreshRange = automaticLinkRefreshRange(
                in: textStorage.mutableString,
                around: location
              ) else {
            return
        }

        let probeLocation = min(max(location - 1, 0), textStorage.length - 1)
        var effectiveRange = NSRange()
        if (textStorage.attribute(
            .qmAutomaticLink,
            at: probeLocation,
            effectiveRange: &effectiveRange
        ) as? Bool) == true {
            refreshRange = NSUnionRange(refreshRange, effectiveRange)
        }
        applyAutomaticLinks(in: textStorage, range: refreshRange, theme: theme)
    }

    static func automaticLinkRefreshRange(
        in string: NSString,
        around location: Int
    ) -> NSRange? {
        guard string.length > 0 else { return nil }

        let maximumLookaround = 4_096
        let caret = min(max(location, 0), string.length)
        var tokenBoundary = caret
        if caret > 0 {
            let previousCharacter = string.character(at: caret - 1)
            if let scalar = UnicodeScalar(previousCharacter),
               CharacterSet.whitespacesAndNewlines.contains(scalar) {
                tokenBoundary = caret - 1
            }
        }

        let lowerBound = max(tokenBoundary - maximumLookaround, 0)
        let precedingRange = NSRange(
            location: lowerBound,
            length: tokenBoundary - lowerBound
        )
        let precedingWhitespace = string.rangeOfCharacter(
            from: .whitespacesAndNewlines,
            options: .backwards,
            range: precedingRange
        )
        let start = precedingWhitespace.location == NSNotFound
            ? lowerBound
            : NSMaxRange(precedingWhitespace)

        let upperBound = min(tokenBoundary + maximumLookaround, string.length)
        let followingRange = NSRange(
            location: tokenBoundary,
            length: upperBound - tokenBoundary
        )
        let followingWhitespace = string.rangeOfCharacter(
            from: .whitespacesAndNewlines,
            range: followingRange
        )
        let end = followingWhitespace.location == NSNotFound
            ? upperBound
            : followingWhitespace.location

        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    @MainActor
    private static func applyAutomaticLinks(
        in attributedString: NSMutableAttributedString,
        range: NSRange,
        theme: MarkdownEditorTheme
    ) {
        guard range.length > 0,
              let detector = automaticLinkDetector else { return }

        attributedString.enumerateAttribute(.qmAutomaticLink, in: range) { value, effectiveRange, _ in
            guard (value as? Bool) == true else { return }
            attributedString.removeAttribute(.qmAutomaticLink, range: effectiveRange)
            attributedString.removeAttribute(.qmLinkURL, range: effectiveRange)
            attributedString.removeAttribute(.underlineStyle, range: effectiveRange)
            attributedString.addAttribute(.foregroundColor, value: theme.textColor, range: effectiveRange)
        }

        let fragment = attributedString.attributedSubstring(from: range).string
        let fragmentRange = NSRange(location: 0, length: (fragment as NSString).length)
        for match in detector.matches(in: fragment, range: fragmentRange) {
            let matchRange = NSRange(
                location: range.location + match.range.location,
                length: match.range.length
            )
            guard matchRange.length > 0,
                  matchRange.location >= 0,
                  NSMaxRange(matchRange) <= attributedString.length,
                  attributedString.attribute(.qmLinkURL, at: matchRange.location, effectiveRange: nil) == nil,
                  attributedString.attribute(.qmCode, at: matchRange.location, effectiveRange: nil) == nil,
                  attributedString.attribute(.qmAttachmentMarkdown, at: matchRange.location, effectiveRange: nil) == nil,
                  let url = match.url else { continue }
            attributedString.addAttributes([
                .qmLinkURL: url.absoluteString,
                .qmAutomaticLink: true,
                .foregroundColor: theme.accentColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: matchRange)
        }
    }

    private static func attributed(_ string: String, base: [NSAttributedString.Key: Any], extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        NSAttributedString(string: string, attributes: base.merging(extra) { _, new in new })
    }

    @MainActor
    private static func fileAttachmentString(
        label: String,
        path: String,
        markdown: String,
        paragraphKind: MarkdownParagraphKind,
        theme: MarkdownEditorTheme,
        baseAttributes: [NSAttributedString.Key: Any],
        baseURL: URL?
    ) -> NSAttributedString? {
        guard let fileURL = localFileURL(path: path, baseURL: baseURL),
              FileManager.default.fileExists(atPath: fileURL.path),
              !isImageFile(fileURL) else {
            return nil
        }
        // Notes remain navigable text links instead of generic file previews.
        if case .localMarkdown = markdownLinkDestination(path, relativeTo: baseURL) {
            return nil
        }
        let metadata = attachmentMetadataText(for: fileURL)

        let attachment = NSTextAttachment()
        attachment.attachmentCell = FileAttachmentPreviewCell(fileURL: fileURL, label: label)
        attachment.bounds = NSRect(x: 0, y: -10, width: 260, height: 38)

        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.addAttributes(baseAttributes.merging([
            .qmAttachmentMarkdown: markdown,
            .qmAttachmentFilePath: fileURL.path,
            .qmAttachmentMetadata: metadata,
            .toolTip: "\(metadata)\n\(fileURL.path)",
            .paragraphStyle: theme.paragraphStyle(for: paragraphKind),
            .qmParagraphKind: paragraphKind.encodedValue
        ]) { _, new in new }, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    static func attachmentMetadataText(for fileURL: URL) -> String {
        let extensionLabel: String
        let pathExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        if pathExtension.isEmpty {
            extensionLabel = "File"
        } else {
            extensionLabel = pathExtension.uppercased()
        }

        guard
            let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
            let fileSize = values.fileSize
        else {
            return extensionLabel
        }

        let size = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
        return "\(extensionLabel) · \(size)"
    }

    @MainActor
    private static func imageAttachmentString(
        label: String,
        path: String,
        markdown: String,
        paragraphKind: MarkdownParagraphKind,
        theme: MarkdownEditorTheme,
        baseAttributes: [NSAttributedString.Key: Any],
        baseURL: URL?
    ) -> NSAttributedString? {
        guard let imageURL = localImageURL(path: path, baseURL: baseURL),
              let naturalSize = MarkdownImageDecoding.pixelSize(at: imageURL)
        else {
            return nil
        }

        let displaySize = MarkdownImageDisplaySizing.fitSize(for: naturalSize)

        let attachment = NSTextAttachment()
        attachment.attachmentCell = AsyncImageAttachmentCell(
            imageURL: imageURL,
            naturalSize: naturalSize
        )
        attachment.bounds = NSRect(x: 0, y: -4, width: displaySize.width, height: displaySize.height)

        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.addAttributes(baseAttributes.merging([
            .qmImageMarkdown: markdown,
            .qmImageFilePath: imageURL.path,
            .toolTip: label.isEmpty ? imageURL.lastPathComponent : label,
            .paragraphStyle: theme.paragraphStyle(for: paragraphKind),
            .qmParagraphKind: paragraphKind.encodedValue
        ]) { _, new in new }, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    private static func localImageURL(path: String, baseURL: URL?) -> URL? {
        guard let fileURL = localFileURL(path: path, baseURL: baseURL),
              isImageFile(fileURL) else {
            return nil
        }
        return fileURL
    }

    private static func localFileURL(path: String, baseURL: URL?) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme {
            guard scheme == "file" else { return nil }
            return url.standardizedFileURL
        }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded).standardizedFileURL
        }

        guard let baseURL else { return nil }
        return baseURL.deletingLastPathComponent()
            .appendingPathComponent(decoded)
            .standardizedFileURL
    }

    private static func isImageFile(_ url: URL) -> Bool {
        ["apng", "avif", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"]
            .contains(url.pathExtension.lowercased())
    }

    private static func isObliqued(_ value: Any?) -> Bool {
        if let number = value as? NSNumber {
            return abs(number.doubleValue) > 0.001
        }
        if let value = value as? CGFloat {
            return abs(value) > 0.001
        }
        if let value = value as? Double {
            return abs(value) > 0.001
        }
        return false
    }

    private static func firstMatch(_ pattern: String, in line: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length))
    }

    private static func capture(_ pattern: String, in line: String, group: Int) -> String? {
        guard let match = firstMatch(pattern, in: line), match.numberOfRanges > group else { return nil }
        return (line as NSString).substring(with: match.range(at: group))
    }

    private static func visiblePrefixLength(for range: NSRange, in attributedString: NSAttributedString, kind: MarkdownParagraphKind) -> Int {
        let lineText = (attributedString.string as NSString).substring(with: range)
        switch kind {
        case .paragraph, .heading:
            return 0
        case .bullet, .checklist:
            guard visibleListPrefixIsComplete(for: kind, in: range, attributedString: attributedString) else { return 0 }
            return min(kind.prefixLength, lineText.utf16.count)
        case .ordered:
            if let match = firstMatch(#"^\d+\.\s"#, in: lineText) {
                return match.range.length
            }
            return min(kind.prefixLength, lineText.utf16.count)
        }
    }

    private static func prefixFont(for kind: MarkdownParagraphKind, theme: MarkdownEditorTheme) -> NSFont {
        switch kind {
        case .bullet:
            return NSFont.systemFont(ofSize: 13, weight: .semibold)
        case .checklist:
            return NSFont.systemFont(ofSize: 14, weight: .semibold)
        case .ordered:
            return NSFont.systemFont(ofSize: 13, weight: .semibold)
        default:
            return theme.bodyFont
        }
    }

    private static func listPrefixVerticalOffset(for kind: MarkdownParagraphKind, theme: MarkdownEditorTheme) -> CGFloat {
        switch kind {
        case .bullet:
            return 0
        case .checklist:
            return 0
        case .ordered:
            return 0.8
        default:
            return 0.8
        }
    }

    @MainActor
    private static func renderPrefix(
        for kind: MarkdownParagraphKind,
        theme: MarkdownEditorTheme,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        switch kind {
        case .bullet:
            return prefixWithAttachment(
                PrefixAttachmentCell(
                    style: .bullet,
                    strokeColor: theme.textColor.withAlphaComponent(0.88),
                    fillColor: theme.textColor.withAlphaComponent(0.88)
                ),
                kind: kind,
                theme: theme,
                baseAttributes: baseAttributes
            )
        case .checklist(let checked):
            let strokeColor = checked
                ? theme.accentColor.withAlphaComponent(0.96)
                : theme.textColor.withAlphaComponent(0.82)
            let fillColor = checked
                ? theme.accentColor.withAlphaComponent(0.94)
                : theme.textColor.withAlphaComponent(0.10)
            return prefixWithAttachment(
                PrefixAttachmentCell(
                    style: .checklist(checked: checked),
                    strokeColor: strokeColor,
                    fillColor: fillColor
                ),
                kind: kind,
                theme: theme,
                baseAttributes: baseAttributes
            )
        case .ordered:
            let prefixAttributes = baseAttributes.merging([
                .foregroundColor: theme.textColor.withAlphaComponent(0.82),
                .font: prefixFont(for: kind, theme: theme),
                .baselineOffset: listPrefixVerticalOffset(for: kind, theme: theme)
            ]) { _, new in new }
            return NSAttributedString(string: kind.prefix, attributes: prefixAttributes)
        default:
            let prefixAttributes = baseAttributes.merging([
                .foregroundColor: theme.mutedTextColor,
                .font: prefixFont(for: kind, theme: theme),
                .baselineOffset: 0.8
            ]) { _, new in new }
            return NSAttributedString(string: kind.prefix, attributes: prefixAttributes)
        }
    }

    @MainActor
    private static func prefixWithAttachment(
        _ cell: PrefixAttachmentCell,
        kind: MarkdownParagraphKind,
        theme: MarkdownEditorTheme,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        let cellSize = cell.cellSize()
        attachment.bounds = NSRect(
            x: 0,
            y: listPrefixVerticalOffset(for: kind, theme: theme),
            width: cellSize.width,
            height: cellSize.height
        )
        let prefix = NSMutableAttributedString(attachment: attachment)
        prefix.append(NSAttributedString(string: " ", attributes: baseAttributes))
        return prefix
    }

    private static func rangeAfterVisiblePrefix(for range: NSRange, in attributedString: NSAttributedString, kind: MarkdownParagraphKind) -> NSRange {
        let prefixLength = visiblePrefixLength(for: range, in: attributedString, kind: kind)
        return NSRange(location: range.location + prefixLength, length: max(range.length - prefixLength, 0))
    }

    static func needsParagraphResetAfterListPrefixEdit(range: NSRange, in attributedString: NSAttributedString) -> Bool {
        guard let kind = storedParagraphKind(at: range, in: attributedString), kind.isListKind else { return false }
        return !visibleListPrefixIsComplete(for: kind, in: range, attributedString: attributedString)
    }

    static func paragraphContentRangeAfterListPrefixEdit(
        for range: NSRange,
        in attributedString: NSAttributedString,
        storedKind: MarkdownParagraphKind
    ) -> NSRange {
        guard range.length > 0 else { return range }
        guard storedKind.usesAttachmentPrefix else { return range }

        let nsString = attributedString.string as NSString
        let upperBound = NSMaxRange(range)
        var contentLocation = range.location

        if contentLocation < upperBound {
            let firstCharacter = nsString.substring(with: NSRange(location: contentLocation, length: 1))
            let hasAttachment = attributedString.attribute(.attachment, at: contentLocation, effectiveRange: nil) as? NSTextAttachment != nil
            if hasAttachment || firstCharacter == "\u{FFFC}" {
                contentLocation += 1
            }
        }

        if contentLocation < upperBound,
           nsString.substring(with: NSRange(location: contentLocation, length: 1)) == " " {
            contentLocation += 1
        }

        return NSRange(location: contentLocation, length: max(upperBound - contentLocation, 0))
    }

    private static func visibleListPrefixIsComplete(
        for kind: MarkdownParagraphKind,
        in range: NSRange,
        attributedString: NSAttributedString
    ) -> Bool {
        guard kind.isListKind else { return true }
        guard range.length > 0 else { return false }

        let nsString = attributedString.string as NSString

        switch kind {
        case .bullet, .checklist:
            guard range.length >= 2 else { return false }
            let hasAttachment = attributedString.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment != nil
            guard hasAttachment else { return false }
            return nsString.substring(with: NSRange(location: range.location + 1, length: 1)) == " "
        case .ordered:
            let lineText = nsString.substring(with: range)
            return firstMatch(#"^\d+\.\s"#, in: lineText) != nil
        default:
            return true
        }
    }
}

private extension MarkdownParagraphKind {
    var isListKind: Bool {
        switch self {
        case .bullet, .ordered, .checklist:
            return true
        default:
            return false
        }
    }

    var usesAttachmentPrefix: Bool {
        switch self {
        case .bullet, .checklist:
            return true
        default:
            return false
        }
    }
}

extension Character {
    var isTagCharacter: Bool {
        if isWhitespace {
            return false
        }

        if isLetter || isNumber {
            return true
        }

        return self == "_" || self == "-" || self == "/"
    }
}
