import SwiftUI
import AVFoundation
import AVKit
import PencilKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

enum ReaderInsertionPosition {
    static func offset(at point: CGPoint, width: CGFloat, text: AttributedString, font: UIFont) -> Int {
        var styled = text
        // Use the same font and inline traits as the rendered SwiftUI Text.
        for run in styled.runs {
            var resolved = font
            if let intent = run.inlinePresentationIntent {
                var traits = font.fontDescriptor.symbolicTraits
                if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
                if intent.contains(.emphasized) { traits.insert(.traitItalic) }
                resolved = font.withTraits(traits)
            }
            styled[run.range].uiKit.font = resolved
        }
        let storage = NSTextStorage(attributedString: NSAttributedString(styled))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var fraction: CGFloat = 0
        let index = manager.characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
        guard index < storage.length else { return storage.length }
        let character = (storage.string as NSString).rangeOfComposedCharacterSequence(at: index)
        return fraction > 0.5 ? NSMaxRange(character) : character.location
    }

    private static func sourceRange(_ position: AttributedString.MarkdownSourcePosition, in source: String) -> NSRange? {
        // Markdown columns are UTF-8 byte positions with an inclusive end.
        // Convert the complete span explicitly before using UITextView's UTF-16 offsets.
        let lines = source.components(separatedBy: "\n")
        guard lines.indices.contains(position.startLine - 1),
              lines.indices.contains(position.endLine - 1) else { return nil }
        let start = lines.prefix(position.startLine - 1).reduce(0) { $0 + $1.utf8.count + 1 } + position.startColumn - 1
        let end = lines.prefix(position.endLine - 1).reduce(0) { $0 + $1.utf8.count + 1 } + position.endColumn
        guard start >= 0, end >= start, end <= source.utf8.count,
              let lower = String.Index(source.utf8.index(source.utf8.startIndex, offsetBy: start), within: source),
              let upper = String.Index(source.utf8.index(source.utf8.startIndex, offsetBy: end), within: source) else { return nil }
        return NSRange(lower..<upper, in: source)
    }

    static func sourceOffset(
        in markdown: String,
        location: NoteFindLocation,
        displayedSource: String,
        renderedOffset: Int,
        inlineMarkdown: Bool = true
    ) -> Int {
        let blocks = MarkdownRenderBlock.parseWithRanges(markdown)
        guard blocks.indices.contains(location.blockIndex) else { return 0 }
        let item = blocks[location.blockIndex]
        let block = (markdown as NSString).substring(with: item.range) as NSString
        var searchStart = 0
        var searchOptions: NSString.CompareOptions = []
        if case .line = item.block {
            // The visible text follows heading, quote, or checklist markers.
            searchOptions = .backwards
        } else if case .code = item.block {
            let firstNewline = block.range(of: "\n")
            if firstNewline.location != NSNotFound { searchStart = NSMaxRange(firstNewline) }
        }
        if case .table(let headers, let rows) = item.block, let cellIndex = location.cellIndex {
            let cells = headers + rows.flatMap { $0 }
            for cell in cells.prefix(cellIndex) {
                let found = block.range(of: cell, range: NSRange(location: searchStart, length: block.length - searchStart))
                if found.location != NSNotFound { searchStart = NSMaxRange(found) }
            }
        }
        // Unordered list bullets are presentation only; their source marker may be - or *.
        let bulletLength = displayedSource.hasPrefix("• ") ? 2 : 0
        let text = String(displayedSource.dropFirst(bulletLength))
        let renderedOffset = max(0, renderedOffset - bulletLength)
        let found = block.range(of: text, options: searchOptions, range: NSRange(location: searchStart, length: block.length - searchStart))
        let base = item.range.location + (found.location == NSNotFound ? 0 : found.location)
        guard inlineMarkdown,
              let parsed = try? AttributedString(markdown: text, options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                appliesSourcePositionAttributes: true
              )) else {
            return min(markdown.utf16.count, base + min(renderedOffset, text.utf16.count))
        }
        var visibleStart = 0
        for run in parsed.runs {
            let length = String(parsed[run.range].characters).utf16.count
            if renderedOffset < visibleStart + length,
               let position = run.markdownSourcePosition,
               let range = sourceRange(position, in: text) {
                return base + range.location + min(renderedOffset - visibleStart, length)
            }
            visibleStart += length
        }
        // End-of-line taps belong before closing inline markup, when present.
        if let run = parsed.runs.last,
           let position = run.markdownSourcePosition,
           let range = sourceRange(position, in: text) {
            return base + NSMaxRange(range)
        }
        return base + min(renderedOffset, text.utf16.count)
    }
}

enum MarkdownSelectionProjection {
    static func attributedText(from blocks: [MarkdownRenderBlock]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for block in blocks {
            let projected: (text: String, font: UIFont, indentation: CGFloat)
            switch block {
            case .line(let line):
                guard MarkdownAttachmentLine(line) == nil else { continue }
                switch MarkdownLineStyle(line) {
                case .heading(let heading):
                    projected = (heading.title, heading.uiFont, 0)
                case .task(let checked, let text, let indentation):
                    projected = ("\(checked ? "☑︎" : "☐") \(text)", .preferredFont(forTextStyle: .body), CGFloat(indentation) * 16)
                case .unordered(let text, let indentation):
                    projected = ("• \(text)", .preferredFont(forTextStyle: .body), CGFloat(indentation) * 16)
                case .ordered(let marker, let text, let indentation):
                    projected = ("\(marker) \(text)", .preferredFont(forTextStyle: .body), CGFloat(indentation) * 16)
                case .quote(let text):
                    projected = (
                        text,
                        .preferredFont(forTextStyle: .body).withTraits(.traitItalic),
                        12
                    )
                case .thematicBreak:
                    projected = ("────────", .preferredFont(forTextStyle: .body), 0)
                case .paragraph(let text):
                    projected = (
                        plainInlineMarkdown(text),
                        .preferredFont(forTextStyle: .body),
                        0
                    )
                }
            case .table(let headers, let rows):
                let text = ([headers] + rows)
                    .map { $0.joined(separator: "\t") }
                    .joined(separator: "\n")
                projected = (text, .preferredFont(forTextStyle: .body), 0)
            case .code(_, let content):
                projected = (
                    content,
                    .monospacedSystemFont(ofSize: 15, weight: .regular),
                    0
                )
            }

            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = 12
            paragraph.firstLineHeadIndent = projected.indentation
            paragraph.headIndent = projected.indentation
            result.append(
                NSAttributedString(
                    string: projected.text + "\n",
                    attributes: [
                        .font: projected.font,
                        .paragraphStyle: paragraph,
                    ]
                )
            )
        }
        return result
    }

    private static func plainInlineMarkdown(_ source: String) -> String {
        guard let attributed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return source
        }
        return String(attributed.characters)
    }
}

struct MarkdownEditingCommand: Identifiable, Equatable {
    enum Kind: Equatable {
        case title
        case heading
        case subheading
        case body
        case bold
        case italic
        case underline
        case highlight
        case strikethrough
        case bullet
        case ordered
        case checklist
        case outdent
        case indent
        case quote
        case code
        case link
        case applyLink(draft: MarkdownLinkDraft, label: String, destination: String)
        case removeLink(draft: MarkdownLinkDraft)
        case applyNoteMention(range: NSRange, label: String, destination: String)
        case table
        case undo
        case redo
        case insertText(String)
        case applyTag(range: NSRange, tag: String)

        var identifier: String {
            switch self {
            case .title: "title"
            case .heading: "heading"
            case .subheading: "subheading"
            case .body: "body"
            case .bold: "bold"
            case .italic: "italic"
            case .underline: "underline"
            case .highlight: "highlight"
            case .strikethrough: "strikethrough"
            case .bullet: "bullet"
            case .ordered: "ordered"
            case .checklist: "checklist"
            case .outdent: "outdent"
            case .indent: "indent"
            case .quote: "quote"
            case .code: "code"
            case .link: "link"
            case .applyLink: "apply-link"
            case .removeLink: "remove-link"
            case .applyNoteMention: "apply-note-mention"
            case .table: "table"
            case .undo: "undo"
            case .redo: "redo"
            case .insertText: "insert-text"
            case .applyTag: "apply-tag"
            }
        }
    }

    let id = UUID()
    var kind: Kind
}

struct MarkdownLinkDraft: Identifiable, Equatable {
    let id = UUID()
    var range: NSRange
    var label: String
    var destination: String
    var isExisting: Bool
}

enum MarkdownLinkEditing {
    static func draft(in markdown: String, selection: NSRange) -> MarkdownLinkDraft? {
        let source = markdown as NSString
        guard selection.location >= 0, NSMaxRange(selection) <= source.length else { return nil }

        let expression = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\n]+)\)"#)
        let matches = expression?.matches(
            in: markdown,
            range: NSRange(location: 0, length: source.length)
        ) ?? []
        if let match = matches.first(where: { contains(selection, in: $0.range) }) {
            return MarkdownLinkDraft(
                range: match.range,
                label: source.substring(with: match.range(at: 1)),
                destination: source.substring(with: match.range(at: 2)),
                isExisting: true
            )
        }

        return MarkdownLinkDraft(
            range: selection,
            label: source.substring(with: selection),
            destination: "",
            isExisting: false
        )
    }

    static func insertionEdit(
        for draft: MarkdownLinkDraft,
        label: String,
        destination: String
    ) -> MarkdownListEdit? {
        let cleanedLabel = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        guard !cleanedLabel.isEmpty,
              let normalizedDestination = normalizedDestination(destination) else { return nil }
        return MarkdownListEdit(
            range: draft.range,
            replacement: "[\(cleanedLabel)](\(normalizedDestination))",
            selection: NSRange(
                location: draft.range.location + 1,
                length: (cleanedLabel as NSString).length
            )
        )
    }

    static func removalEdit(for draft: MarkdownLinkDraft) -> MarkdownListEdit? {
        guard draft.isExisting else { return nil }
        return MarkdownListEdit(
            range: draft.range,
            replacement: draft.label,
            selection: NSRange(
                location: draft.range.location,
                length: (draft.label as NSString).length
            )
        )
    }

    static func normalizedDestination(_ value: String) -> String? {
        var destination = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }
        destination = destination
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
        let hasScheme = destination.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
            options: .regularExpression
        ) != nil
        if !hasScheme,
           !destination.hasPrefix("#"),
           !destination.hasPrefix("/"),
           !destination.hasPrefix("./"),
           !destination.hasPrefix("../") {
            destination = destination.contains("@")
                ? "mailto:\(destination)"
                : "https://\(destination)"
        }
        return destination
    }

    private static func contains(_ selection: NSRange, in range: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= range.location && selection.location <= NSMaxRange(range)
        }
        return selection.location >= range.location && NSMaxRange(selection) <= NSMaxRange(range)
    }
}

enum MarkdownInlineEditing {
    static func toggleEdit(
        in markdown: String,
        selection: NSRange,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length,
              !prefix.isEmpty,
              !suffix.isEmpty else { return nil }

        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length
        let selected = source.substring(with: selection)

        if selection.length >= prefixLength + suffixLength,
           selected.hasPrefix(prefix),
           selected.hasSuffix(suffix) {
            let contentRange = NSRange(
                location: prefixLength,
                length: selection.length - prefixLength - suffixLength
            )
            let content = (selected as NSString).substring(with: contentRange)
            return MarkdownListEdit(
                range: selection,
                replacement: content,
                selection: NSRange(location: selection.location, length: contentRange.length)
            )
        }

        if selection.location >= prefixLength,
           NSMaxRange(selection) + suffixLength <= source.length {
            let before = source.substring(with: NSRange(
                location: selection.location - prefixLength,
                length: prefixLength
            ))
            let after = source.substring(with: NSRange(
                location: NSMaxRange(selection),
                length: suffixLength
            ))
            if before == prefix, after == suffix {
                return MarkdownListEdit(
                    range: NSRange(
                        location: selection.location - prefixLength,
                        length: prefixLength + selection.length + suffixLength
                    ),
                    replacement: selected,
                    selection: NSRange(
                        location: selection.location - prefixLength,
                        length: selection.length
                    )
                )
            }
        }

        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        return MarkdownListEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(
                location: selection.location + prefixLength,
                length: (content as NSString).length
            )
        )
    }
}

enum MarkdownRenderBlock: Equatable {
    case line(String)
    case table(headers: [String], rows: [[String]])
    case code(language: String?, content: String)

    static func parse(_ markdown: String) -> [MarkdownRenderBlock] {
        parseWithRanges(markdown).map(\.block)
    }

    static func parseWithRanges(_ markdown: String) -> [(block: MarkdownRenderBlock, range: NSRange)] {
        let lines = markdown.components(separatedBy: .newlines)
        var offsets: [Int] = []
        var offset = 0
        for line in lines {
            offsets.append(offset)
            offset += line.utf16.count + 1
        }
        var blocks: [(block: MarkdownRenderBlock, range: NSRange)] = []
        var index = 0
        while index < lines.count {
            let sourceLine = lines[index]
            let start = offsets[index]
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                index += 1
                continue
            }

            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                let fence = String(line.prefix(3))
                let language = line.dropFirst(3)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var codeLines: [String] = []
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
                        .hasPrefix(fence) {
                    codeLines.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                let end = index < lines.count ? offsets[index] : markdown.utf16.count
                blocks.append((.code(
                    language: language.isEmpty ? nil : language,
                    content: codeLines.joined(separator: "\n")
                ), NSRange(location: start, length: end - start)))
                continue
            }

            if index + 1 < lines.count,
               let headers = cells(in: line),
               isSeparator(lines[index + 1], columnCount: headers.count) {
                var rows: [[String]] = []
                index += 2
                while index < lines.count, let row = cells(in: lines[index]), row.count == headers.count {
                    rows.append(row)
                    index += 1
                }
                let end = index < lines.count ? offsets[index] : markdown.utf16.count
                blocks.append((.table(headers: headers, rows: rows), NSRange(location: start, length: end - start)))
                continue
            }

            blocks.append((.line(sourceLine), NSRange(location: start, length: sourceLine.utf16.count)))
            index += 1
        }
        return blocks
    }

    private static func cells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return nil }
        let content = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isSeparator(_ line: String, columnCount: Int) -> Bool {
        guard let cells = cells(in: line), cells.count == columnCount else { return false }
        return cells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }
}

struct MarkdownHeading: Equatable {
    var level: Int
    var title: String

    init(level: Int, title: String) {
        self.level = level
        self.title = title
    }

    init?(_ line: String) {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              line.count > markerCount,
              line[line.index(line.startIndex, offsetBy: markerCount)] == " " else {
            return nil
        }
        let title = String(line.dropFirst(markerCount + 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        self.level = markerCount
        self.title = title
    }

    var font: Font {
        switch level {
        case 1: .title2.bold()
        case 2: .title3.bold()
        case 3: .headline
        default: .subheadline.weight(.semibold)
        }
    }

    var uiFont: UIFont {
        switch level {
        case 1: .preferredFont(forTextStyle: .title2).withTraits(.traitBold)
        case 2: .preferredFont(forTextStyle: .title3).withTraits(.traitBold)
        case 3: .preferredFont(forTextStyle: .headline)
        default: .preferredFont(forTextStyle: .subheadline).withTraits(.traitBold)
        }
    }
}

enum MarkdownLineStyle: Equatable {
    case heading(MarkdownHeading)
    case task(isChecked: Bool, text: String, indentation: Int)
    case unordered(text: String, indentation: Int)
    case ordered(marker: String, text: String, indentation: Int)
    case quote(String)
    case thematicBreak
    case paragraph(String)

    init(_ line: String) {
        if let heading = MarkdownHeading(line) {
            self = .heading(heading)
            return
        }

        let indentation = min(line.prefix { $0 == " " || $0 == "\t" }.reduce(0) {
            $0 + ($1 == "\t" ? 2 : 1)
        } / 2, 3)
        if let captures = Self.captures(
            in: line,
            pattern: #"^\s*[-*+]\s+\[([ xX])\]\s*(.*)$"#
        ) {
            self = .task(
                isChecked: captures[0].lowercased() == "x",
                text: captures[1],
                indentation: indentation
            )
            return
        }
        if line.range(
            of: #"^\s*(?:(?:-\s*){3,}|(?:\*\s*){3,}|(?:_\s*){3,})$"#,
            options: .regularExpression
        ) != nil {
            self = .thematicBreak
            return
        }
        if let captures = Self.captures(in: line, pattern: #"^\s*[-*+]\s+(.*)$"#) {
            self = .unordered(text: captures[0], indentation: indentation)
            return
        }
        if let captures = Self.captures(in: line, pattern: #"^\s*(\d+[.)])\s+(.*)$"#) {
            self = .ordered(
                marker: captures[0],
                text: captures[1],
                indentation: indentation
            )
            return
        }
        if let captures = Self.captures(in: line, pattern: #"^\s*>\s?(.*)$"#) {
            self = .quote(captures[0])
            return
        }
        self = .paragraph(line)
    }

    var visibleText: String {
        switch self {
        case .heading(let heading): heading.title
        case .task(_, let text, _), .unordered(let text, _), .ordered(_, let text, _): text
        case .quote(let text), .paragraph(let text): text
        case .thematicBreak: ""
        }
    }

    private static func captures(in value: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ) else { return nil }
        return (1..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }
}

struct NoteFindLocation: Hashable {
    var blockIndex: Int
    var cellIndex: Int?
}

enum MarkdownAudioTranscript {
    static func appending(_ transcript: String, to markdown: String) -> String {
        let body = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return markdown }
        var result = markdown
        if !result.isEmpty, !result.hasSuffix("\n") { result += "\n" }
        if !result.isEmpty { result += "\n" }
        result += "### \(String(localized: "Audio transcription"))\n\n"
        result += body
        result += "\n"
        return result
    }
}

struct NoteFindMatch: Identifiable, Equatable {
    var location: NoteFindLocation
    var occurrence: Int

    var id: String {
        "\(location.blockIndex):\(location.cellIndex ?? -1):\(occurrence)"
    }
}

struct NoteAttachmentFindMatch: Identifiable, Equatable {
    var location: NoteFindLocation
    var relativePath: String
    var fileName: String
    var context: String
    var occurrence: Int

    var id: String {
        "attachment:\(location.blockIndex):\(relativePath):\(occurrence)"
    }
}

enum NoteFindResult: Identifiable, Equatable {
    case text(NoteFindMatch)
    case attachment(NoteAttachmentFindMatch)

    var id: String {
        switch self {
        case .text(let match): match.id
        case .attachment(let match): match.id
        }
    }

    var location: NoteFindLocation {
        switch self {
        case .text(let match): match.location
        case .attachment(let match): match.location
        }
    }

    var sortOrder: Int {
        switch self {
        case .text: 0
        case .attachment: 1
        }
    }
}

enum NoteFindIndex {
    static func matches(
        in blocks: [MarkdownRenderBlock],
        query: String
    ) -> [NoteFindMatch] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var results: [NoteFindMatch] = []
        for (blockIndex, block) in blocks.enumerated() {
            switch block {
            case .line(let line):
                guard MarkdownAttachmentLine(line) == nil else { continue }
                let location = NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
                results.append(contentsOf: matches(
                    in: visibleText(for: line),
                    term: term,
                    location: location
                ))
            case .table(let headers, let rows):
                let cells = headers + rows.flatMap { $0 }
                for (cellIndex, cell) in cells.enumerated() {
                    let location = NoteFindLocation(
                        blockIndex: blockIndex,
                        cellIndex: cellIndex
                    )
                    results.append(contentsOf: matches(
                        in: visibleText(for: cell),
                        term: term,
                        location: location
                    ))
                }
            case .code(_, let content):
                let location = NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
                results.append(contentsOf: matches(
                    in: content,
                    term: term,
                    location: location
                ))
            }
        }
        return results
    }

    static func attachmentMatches(
        in blocks: [MarkdownRenderBlock],
        documents: [AttachmentSearchDocument],
        query: String
    ) -> [NoteAttachmentFindMatch] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        let documentsByPath = Dictionary(
            documents.map { ($0.relativePath, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var results: [NoteAttachmentFindMatch] = []
        for (blockIndex, block) in blocks.enumerated() {
            guard case .line(let line) = block,
                  let attachment = MarkdownAttachmentLine(line),
                  let document = documentsByPath[attachment.path] else { continue }
            let searchableText = document.fileName + "\n" + document.text
            let matchedRanges = ranges(in: searchableText, term: term)
            let location = NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
            for (occurrence, range) in matchedRanges.enumerated() {
                results.append(NoteAttachmentFindMatch(
                    location: location,
                    relativePath: document.relativePath,
                    fileName: document.fileName,
                    context: excerpt(in: searchableText, around: range),
                    occurrence: occurrence
                ))
            }
        }
        return results
    }

    static func visibleText(for markdown: String) -> String {
        let source = MarkdownLineStyle(markdown).visibleText
        return String(MarkdownInlineRendering.attributedText(for: source).characters)
    }

    static func highlightedText(
        for markdown: String,
        query: String,
        location: NoteFindLocation,
        activeMatch: NoteFindMatch?,
        rendersInlineMarkdown: Bool = true
    ) -> AttributedString {
        let rendered = rendersInlineMarkdown
            ? MarkdownInlineRendering.attributedText(for: markdown)
            : AttributedString(markdown)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return rendered }

        let attributed = NSMutableAttributedString(
            attributedString: NSAttributedString(rendered)
        )
        for (occurrence, range) in ranges(in: attributed.string, term: term).enumerated() {
            let isActive = activeMatch?.location == location
                && activeMatch?.occurrence == occurrence
            attributed.addAttribute(
                .backgroundColor,
                value: isActive
                    ? UIColor.systemOrange
                    : UIColor.systemYellow.withAlphaComponent(0.55),
                range: range
            )
            if isActive {
                attributed.addAttribute(.foregroundColor, value: UIColor.black, range: range)
            }
        }
        return AttributedString(attributed)
    }

    private static func matches(
        in text: String,
        term: String,
        location: NoteFindLocation
    ) -> [NoteFindMatch] {
        ranges(in: text, term: term).indices.map {
            NoteFindMatch(location: location, occurrence: $0)
        }
    }

    private static func ranges(in text: String, term: String) -> [NSRange] {
        let source = text as NSString
        guard source.length > 0 else { return [] }
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let match = source.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound else { break }
            results.append(match)
            let nextLocation = NSMaxRange(match)
            guard nextLocation < source.length else { break }
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        return results
    }

    private static func excerpt(in text: String, around range: NSRange) -> String {
        let source = text as NSString
        let radius = 64
        let start = max(0, range.location - radius)
        let end = min(source.length, NSMaxRange(range) + radius)
        let excerpt = source.substring(with: NSRange(location: start, length: end - start))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (start > 0 ? "…" : "") + excerpt + (end < source.length ? "…" : "")
    }
}

enum MarkdownTableEditing {
    static func insertionEdit(in markdown: String, selection: NSRange) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }

        let needsLeadingNewline = selection.location > 0
            && source.character(at: selection.location - 1) != 10
        let needsTrailingNewline = NSMaxRange(selection) < source.length
            && source.character(at: NSMaxRange(selection)) != 10
        let leading = needsLeadingNewline ? "\n" : ""
        let trailing = needsTrailingNewline ? "\n" : ""
        let table = "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |"
        let replacement = leading + table + trailing
        let firstCellOffset = (leading + "| Column 1 | Column 2 |\n| --- | --- |\n| ") as NSString
        return MarkdownListEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + firstCellOffset.length, length: 0)
        )
    }
}

struct MarkdownListEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

enum MarkdownParagraphEditing {
    enum Style {
        case title
        case heading
        case subheading
        case body

        var prefix: String? {
            switch self {
            case .title: "# "
            case .heading: "## "
            case .subheading: "### "
            case .body: nil
            }
        }
    }

    static func styleEdit(
        in markdown: String,
        selection: NSRange,
        style: Style
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }

        let lineRange = source.lineRange(for: selection)
        let block = source.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }

        let headingExpression = try? NSRegularExpression(
            pattern: #"^([ \t]*)#{1,6}[ \t]+"#
        )
        let indentationExpression = try? NSRegularExpression(pattern: #"^[ \t]*"#)
        lines = lines.map { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return line
            }

            let fullRange = NSRange(location: 0, length: (line as NSString).length)
            let body = headingExpression?.stringByReplacingMatches(
                in: line,
                range: fullRange,
                withTemplate: "$1"
            ) ?? line
            guard let prefix = style.prefix else { return body }

            let bodyRange = NSRange(location: 0, length: (body as NSString).length)
            let indentationRange = indentationExpression?.firstMatch(
                in: body,
                range: bodyRange
            )?.range ?? NSRange(location: 0, length: 0)
            let bodySource = body as NSString
            let indentation = bodySource.substring(with: indentationRange)
            let content = bodySource.substring(from: NSMaxRange(indentationRange))
            return indentation + prefix + content
        }

        var replacement = lines.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        return MarkdownListEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }
}

enum MarkdownInlineRendering {
    private static let underlineStart = "\u{E000}"
    private static let underlineEnd = "\u{E001}"
    private static let highlightStart = "\u{E002}"
    private static let highlightEnd = "\u{E003}"

    static func attributedText(for markdown: String) -> AttributedString {
        let prepared = markdown
            .replacingOccurrences(of: "<u>", with: underlineStart)
            .replacingOccurrences(of: "</u>", with: underlineEnd)
            .replacingOccurrences(of: "<mark>", with: highlightStart)
            .replacingOccurrences(of: "</mark>", with: highlightEnd)
        let parsed = (try? AttributedString(markdown: prepared))
            ?? AttributedString(prepared)
        let attributed = NSMutableAttributedString(
            attributedString: NSAttributedString(parsed)
        )
        applyDelimitedStyle(
            in: attributed,
            start: underlineStart,
            end: underlineEnd,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        applyDelimitedStyle(
            in: attributed,
            start: highlightStart,
            end: highlightEnd,
            attributes: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.48)]
        )
        MarkdownDataDetection.apply(to: attributed)
        attributed.enumerateAttribute(
            .link,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, range, _ in
            guard value != nil else { return }
            attributed.addAttribute(
                .foregroundColor,
                value: UIColor.systemYellow,
                range: range
            )
        }
        return AttributedString(attributed)
    }

    private static func applyDelimitedStyle(
        in attributed: NSMutableAttributedString,
        start: String,
        end: String,
        attributes: [NSAttributedString.Key: Any]
    ) {
        while true {
            let source = attributed.string as NSString
            let opening = source.range(of: start)
            guard opening.location != NSNotFound else { break }
            let trailingRange = NSRange(
                location: NSMaxRange(opening),
                length: source.length - NSMaxRange(opening)
            )
            let closing = source.range(of: end, range: trailingRange)
            guard closing.location != NSNotFound else {
                attributed.deleteCharacters(in: opening)
                continue
            }
            let contentLength = closing.location - NSMaxRange(opening)
            attributed.deleteCharacters(in: closing)
            attributed.deleteCharacters(in: opening)
            if contentLength > 0 {
                attributed.addAttributes(
                    attributes,
                    range: NSRange(location: opening.location, length: contentLength)
                )
            }
        }
        attributed.mutableString.replaceOccurrences(
            of: end,
            with: "",
            range: NSRange(location: 0, length: attributed.length)
        )
    }
}

enum MarkdownDataDetection {
    private static let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
            | NSTextCheckingResult.CheckingType.phoneNumber.rawValue
            | NSTextCheckingResult.CheckingType.address.rawValue
    )

    static func apply(to attributed: NSMutableAttributedString) {
        guard attributed.length > 0, let detector else { return }
        let fullRange = NSRange(location: 0, length: attributed.length)
        for match in detector.matches(in: attributed.string, range: fullRange) {
            if !containsExistingLink(in: match.range, attributed: attributed) {
                guard let destination = destination(for: match, in: attributed.string) else {
                    continue
                }
                attributed.addAttribute(.link, value: destination, range: match.range)
            }
            attributed.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: match.range
            )
        }
    }

    private static func destination(
        for match: NSTextCheckingResult,
        in source: String
    ) -> URL? {
        switch match.resultType {
        case .link:
            return match.url
        case .phoneNumber:
            guard let phoneNumber = match.phoneNumber else { return nil }
            let dialable = phoneNumber.filter { character in
                character.isNumber || "+*#".contains(character)
            }
            guard !dialable.isEmpty else { return nil }
            return URL(string: "tel:\(dialable)")
        case .address:
            let address = (source as NSString).substring(with: match.range)
            var components = URLComponents(string: "https://maps.apple.com/")
            components?.queryItems = [URLQueryItem(name: "q", value: address)]
            return components?.url
        default:
            return nil
        }
    }

    private static func containsExistingLink(
        in range: NSRange,
        attributed: NSAttributedString
    ) -> Bool {
        var containsLink = false
        attributed.enumerateAttribute(.link, in: range) { value, _, stop in
            guard value != nil else { return }
            containsLink = true
            stop.pointee = true
        }
        return containsLink
    }
}

enum MarkdownListEditing {
    enum IndentationDirection {
        case increase
        case decrease
    }

    private enum Kind {
        case bullet(marker: String)
        case ordered(indent: String, number: Int, delimiter: String)
        case checklist(indent: String)
    }

    private struct Item {
        var prefix: String
        var body: String
        var kind: Kind
    }

    static func prefixEdit(
        in markdown: String,
        selection: NSRange,
        prefix: String
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }
        let lineRange = source.lineRange(for: selection)
        let block = source.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        if selection.length == 0,
           lines.allSatisfy({ $0.isEmpty }) {
            let replacement = prefix + (endsWithNewline ? "\n" : "")
            return MarkdownListEdit(
                range: lineRange,
                replacement: replacement,
                selection: NSRange(
                    location: lineRange.location + (prefix as NSString).length,
                    length: 0
                )
            )
        }

        let contentLines = lines.filter { !$0.isEmpty }
        let shouldRemove = !contentLines.isEmpty && contentLines.allSatisfy {
            $0.hasPrefix(prefix)
        }
        lines = lines.map { line in
            guard !line.isEmpty else { return line }
            return shouldRemove ? String(line.dropFirst(prefix.count)) : prefix + line
        }
        var replacement = lines.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        return MarkdownListEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }

    static func orderedEdit(
        in markdown: String,
        selection: NSRange
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }
        let lineRange = source.lineRange(for: selection)
        let block = source.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        if selection.length == 0,
           lines.allSatisfy({ $0.isEmpty }) {
            let prefix = "1. "
            let replacement = prefix + (endsWithNewline ? "\n" : "")
            return MarkdownListEdit(
                range: lineRange,
                replacement: replacement,
                selection: NSRange(
                    location: lineRange.location + (prefix as NSString).length,
                    length: 0
                )
            )
        }

        let expression = try? NSRegularExpression(pattern: #"^([ \t]*)[0-9]+[.)] "#)
        let contentLines = lines.filter { !$0.isEmpty }
        let shouldRemove = !contentLines.isEmpty && contentLines.allSatisfy { line in
            let value = line as NSString
            return expression?.firstMatch(
                in: line,
                range: NSRange(location: 0, length: value.length)
            ) != nil
        }
        var nextNumber = 1
        lines = lines.map { line in
            guard !line.isEmpty else { return line }
            let value = line as NSString
            if shouldRemove,
               let match = expression?.firstMatch(
                   in: line,
                   range: NSRange(location: 0, length: value.length)
               ) {
                let prefix = value.substring(with: match.range)
                let indentation = prefix.prefix { $0 == " " || $0 == "\t" }
                return String(indentation) + value.substring(from: NSMaxRange(match.range))
            }
            let indentation = line.prefix { $0 == " " || $0 == "\t" }
            let body = line.dropFirst(indentation.count)
            defer { nextNumber += 1 }
            return "\(indentation)\(nextNumber). \(body)"
        }
        var replacement = lines.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        return MarkdownListEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }

    static func returnEdit(in markdown: String, selection: NSRange) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let item = item(in: line) else { return nil }

        if item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let prefixLength = (item.prefix as NSString).length
            return MarkdownListEdit(
                range: NSRange(location: lineRange.location, length: prefixLength),
                replacement: "",
                selection: NSRange(location: lineRange.location, length: 0)
            )
        }

        let continuation: String
        switch item.kind {
        case .bullet(let marker):
            continuation = marker
        case .ordered(let indent, let number, let delimiter):
            continuation = "\(indent)\(number + 1)\(delimiter) "
        case .checklist(let indent):
            continuation = "\(indent)- [ ] "
        }
        let replacement = "\n" + continuation
        return MarkdownListEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(
                location: selection.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    static func backspaceEdit(in markdown: String, deletionRange: NSRange) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard deletionRange.length == 1,
              deletionRange.location >= 0,
              NSMaxRange(deletionRange) <= source.length else { return nil }
        let caret = NSMaxRange(deletionRange)
        let lineRange = source.lineRange(for: NSRange(location: caret, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let item = item(in: line) else { return nil }
        let prefixLength = (item.prefix as NSString).length
        guard caret == lineRange.location + prefixLength else { return nil }
        return MarkdownListEdit(
            range: NSRange(location: lineRange.location, length: prefixLength),
            replacement: "",
            selection: NSRange(location: lineRange.location, length: 0)
        )
    }

    static func indentationEdit(
        in markdown: String,
        selection: NSRange,
        direction: IndentationDirection
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }
        let lastSelectedCharacter = NSMaxRange(selection) - 1
        let selectionEndsWithNewline = selection.length > 0
            && source.character(at: lastSelectedCharacter) == 10
        let effectiveLength = selectionEndsWithNewline ? selection.length - 1 : selection.length
        let lineRange = source.lineRange(
            for: NSRange(location: selection.location, length: effectiveLength)
        )
        let block = source.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        var changed = false
        lines = lines.map { line in
            guard isListItem(line) else { return line }
            switch direction {
            case .increase:
                changed = true
                return "  " + line
            case .decrease:
                if line.hasPrefix("  ") {
                    changed = true
                    return String(line.dropFirst(2))
                }
                if line.hasPrefix("\t") || line.hasPrefix(" ") {
                    changed = true
                    return String(line.dropFirst())
                }
                return line
            }
        }
        guard changed else { return nil }
        var replacement = lines.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        return MarkdownListEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }

    private static func item(in line: String) -> Item? {
        if let groups = groups(for: #"^([ \t]*)(- \[[ xX]\] )(.*)$"#, in: line) {
            return Item(prefix: groups[0] + groups[1], body: groups[2], kind: .checklist(indent: groups[0]))
        }
        if let groups = groups(for: #"^([ \t]*)([-*+] )(.*)$"#, in: line) {
            return Item(prefix: groups[0] + groups[1], body: groups[2], kind: .bullet(marker: groups[0] + groups[1]))
        }
        if let groups = groups(for: #"^([ \t]*)([0-9]+)([.)]) (.*)$"#, in: line),
           let number = Int(groups[1]) {
            let prefix = groups[0] + groups[1] + groups[2] + " "
            return Item(prefix: prefix, body: groups[3], kind: .ordered(indent: groups[0], number: number, delimiter: groups[2]))
        }
        return nil
    }

    private static func groups(for pattern: String, in value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = value as NSString
        guard let match = expression.firstMatch(
            in: value,
            range: NSRange(location: 0, length: source.length)
        ) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
    }

    private static func isListItem(_ line: String) -> Bool {
        groups(for: #"^[ \t]*(?:[-*+] |[0-9]+[.)] )"#, in: line) != nil
    }
}
