import AppKit
import Foundation
import MudsnoteCore

extension NSAttributedString.Key {
    static let qmParagraphKind = NSAttributedString.Key("MudsnoteParagraphKind")
    static let qmCode = NSAttributedString.Key("MudsnoteCode")
    static let qmLinkURL = NSAttributedString.Key("MudsnoteLinkURL")
    static let qmTag = NSAttributedString.Key("MudsnoteTag")
}

enum MarkdownParagraphKind: Equatable {
    case paragraph
    case heading(level: Int)
    case bullet
    case ordered(index: Int)
    case checklist(checked: Bool)

    var prefix: String {
        switch self {
        case .paragraph, .heading:
            return ""
        case .bullet:
            return "\u{2022} "
        case .ordered(let index):
            return "\(index). "
        case .checklist(let checked):
            return checked ? "\u{2611} " : "\u{2610} "
        }
    }

    var prefixLength: Int {
        prefix.utf16.count
    }

    var encodedValue: String {
        switch self {
        case .paragraph:
            return "paragraph"
        case .heading(let level):
            return "heading:\(level)"
        case .bullet:
            return "bullet"
        case .ordered(let index):
            return "ordered:\(index)"
        case .checklist(let checked):
            return checked ? "check:1" : "check:0"
        }
    }

    static func decode(_ rawValue: Any?) -> MarkdownParagraphKind? {
        guard let string = rawValue as? String else { return nil }

        if string == "paragraph" { return .paragraph }
        if string == "bullet" { return .bullet }
        if string == "check:1" { return .checklist(checked: true) }
        if string == "check:0" { return .checklist(checked: false) }
        if string.hasPrefix("heading:"),
           let level = Int(string.replacingOccurrences(of: "heading:", with: "")) {
            return .heading(level: level)
        }
        if string.hasPrefix("ordered:"),
           let index = Int(string.replacingOccurrences(of: "ordered:", with: "")) {
            return .ordered(index: index)
        }

        return nil
    }
}

struct MarkdownEditorTheme {
    let textColor: NSColor
    let mutedTextColor: NSColor
    let accentColor: NSColor
    let bodyFont: NSFont
    let boldFont: NSFont
    let italicFont: NSFont
    let codeFont: NSFont

    func font(for paragraphKind: MarkdownParagraphKind) -> NSFont {
        switch paragraphKind {
        case .heading(let level):
            let size = max(24 - CGFloat(level * 2), 16)
            return NSFont.systemFont(ofSize: size, weight: .bold)
        default:
            return bodyFont
        }
    }

    func paragraphStyle(for paragraphKind: MarkdownParagraphKind) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 6

        switch paragraphKind {
        case .bullet, .ordered, .checklist:
            let tab = NSTextTab(textAlignment: .left, location: 16, options: [:])
            style.tabStops = [tab]
            style.defaultTabInterval = 16
            style.firstLineHeadIndent = 0
            style.headIndent = 16
        default:
            style.firstLineHeadIndent = 0
            style.headIndent = 0
        }

        return style
    }

    func baseAttributes(for paragraphKind: MarkdownParagraphKind) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: paragraphKind),
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle(for: paragraphKind),
            .qmParagraphKind: paragraphKind.encodedValue
        ]
    }
}

@MainActor
protocol MarkdownTextViewCommands: AnyObject {
    func markdownTextViewInsertNewline(_ textView: MarkdownTextView)
    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool
    func markdownTextViewToggleBold(_ textView: MarkdownTextView)
    func markdownTextViewToggleItalic(_ textView: MarkdownTextView)
    func markdownTextViewToggleHeading(_ textView: MarkdownTextView)
    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView)
    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView)
    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView)
    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool
}

final class MarkdownTextView: NSTextView {
    weak var commandDelegate: MarkdownTextViewCommands?

    override func insertNewline(_ sender: Any?) {
        commandDelegate?.markdownTextViewInsertNewline(self)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let text = string as? String,
           text.count == 1,
           commandDelegate?.markdownTextView(self, shouldInterceptInsertedText: text) == true {
            return
        }

        super.insertText(string, replacementRange: replacementRange)
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard let string = pasteboard.string(forType: .string) else {
            super.paste(sender)
            return
        }

        insertText(string, replacementRange: selectedRange())
    }

    override func mouseDown(with event: NSEvent) {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer else {
            super.mouseDown(with: event)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        if commandDelegate?.markdownTextView(self, didClickCharacterAt: characterIndex) == true {
            return
        }

        super.mouseDown(with: event)
    }
}

enum MarkdownRichTextCodec {
    static func render(markdown: String, theme: MarkdownEditorTheme) -> NSMutableAttributedString {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let output = NSMutableAttributedString()

        for (index, line) in lines.enumerated() {
            output.append(renderLine(line, theme: theme))
            if index < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph)))
            }
        }

        return output
    }

    static func renderLine(_ line: String, theme: MarkdownEditorTheme) -> NSMutableAttributedString {
        let kind = paragraphKind(for: line)
        let paragraphString = NSMutableAttributedString()
        let baseAttributes = theme.baseAttributes(for: kind)

        let prefix = kind.prefix
        if !prefix.isEmpty {
            let prefixAttributes = baseAttributes.merging([
                .foregroundColor: theme.mutedTextColor,
                .font: prefixFont(for: kind, theme: theme),
                .baselineOffset: 0.8
            ]) { _, new in new }
            paragraphString.append(NSAttributedString(string: prefix, attributes: prefixAttributes))
        }

        let content = markdownContent(from: line, kind: kind)
        paragraphString.append(parseInlineMarkdown(content, paragraphKind: kind, theme: theme))

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
        var lines: [String] = []
        var location = 0

        while location < nsString.length {
            let paragraphRange = nsString.paragraphRange(for: NSRange(location: location, length: 0))
            let hasTrailingNewline = nsString.substring(with: paragraphRange).hasSuffix("\n")
            let lineRange = NSRange(
                location: paragraphRange.location,
                length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
            )
            let lineText = nsString.substring(with: lineRange)
            lines.append(serializeLine(range: lineRange, visibleText: lineText, in: attributedString, theme: theme))
            location = NSMaxRange(paragraphRange)
        }

        if nsString.length == 0 {
            return ""
        }

        if attributedString.string.hasSuffix("\n") {
            return lines.joined(separator: "\n") + "\n"
        }

        return lines.joined(separator: "\n")
    }

    static func paragraphKind(at range: NSRange, in attributedString: NSAttributedString) -> MarkdownParagraphKind {
        if range.length == 0 {
            return .paragraph
        }

        if let encoded = attributedString.attribute(.qmParagraphKind, at: range.location, effectiveRange: nil),
           let kind = MarkdownParagraphKind.decode(encoded) {
            return kind
        }

        let visibleText = (attributedString.string as NSString).substring(with: range)
        return inferredParagraphKind(fromVisibleText: visibleText)
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
        serializeInline(range: range, in: attributedString, paragraphKind: paragraphKind, theme: theme)
    }

    private static func serializeLine(range: NSRange, visibleText: String, in attributedString: NSAttributedString, theme: MarkdownEditorTheme) -> String {
        let kind = paragraphKind(at: range, in: attributedString)
        let contentRange = rangeAfterVisiblePrefix(for: range, in: attributedString, kind: kind)
        let contentMarkdown = serializeInline(range: contentRange, in: attributedString, paragraphKind: kind, theme: theme)

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
        theme: MarkdownEditorTheme
    ) -> String {
        guard range.length > 0 else { return "" }

        var markdown = ""
        var location = range.location
        let baseFont = theme.font(for: paragraphKind)

        while location < NSMaxRange(range) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = attributedString.attributes(at: location, effectiveRange: &effectiveRange)
            let clippedRange = NSIntersectionRange(effectiveRange, range)
            let text = (attributedString.string as NSString).substring(with: clippedRange)
            markdown += serializeRun(text: text, attributes: attributes, baseFont: baseFont)
            location = NSMaxRange(clippedRange)
        }

        return markdown
    }

    private static func serializeRun(text: String, attributes: [NSAttributedString.Key: Any], baseFont: NSFont) -> String {
        if text.isEmpty { return "" }

        if (attributes[.qmTag] as? Bool) == true {
            return text
        }

        if let url = attributes[.qmLinkURL] as? String {
            return "[\(text)](\(url))"
        }

        var wrapped = text

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
            let traits = NSFontManager.shared.traits(of: font)
            let baseTraits = NSFontManager.shared.traits(of: baseFont)
            let isBold = traits.contains(.boldFontMask) && !baseTraits.contains(.boldFontMask)
            let isItalic = traits.contains(.italicFontMask) && !baseTraits.contains(.italicFontMask)

            if isBold && isItalic {
                wrapped = "***\(wrapped)***"
            } else if isBold {
                wrapped = "**\(wrapped)**"
            } else if isItalic {
                wrapped = "*\(wrapped)*"
            }
        }

        return wrapped
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

        if firstMatch(#"^\s*[-*+]\s*(.*)$"#, in: line) != nil {
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
            return capture(#"^\s*[-*+]\s*(.*)$"#, in: line, group: 1) ?? line
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

    private static func parseInlineMarkdown(_ source: String, paragraphKind: MarkdownParagraphKind, theme: MarkdownEditorTheme) -> NSMutableAttributedString {
        let output = NSMutableAttributedString()
        let baseAttributes = theme.baseAttributes(for: paragraphKind)
        var index = source.startIndex

        while index < source.endIndex {
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
                output.append(attributed(content, base: baseAttributes, extra: [.font: theme.italicFont]))
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

            if source[index...].hasPrefix("`"),
               let end = source[source.index(after: index)...].range(of: "`") {
                let content = String(source[source.index(after: index)..<end.lowerBound])
                output.append(attributed(content, base: baseAttributes, extra: [.font: theme.codeFont, .qmCode: true, .foregroundColor: theme.accentColor]))
                index = end.upperBound
                continue
            }

            if source[index...].hasPrefix("["),
               let closeBracket = source[index...].range(of: "]("),
               let closeParen = source[closeBracket.upperBound...].firstIndex(of: ")") {
                let label = String(source[source.index(after: index)..<closeBracket.lowerBound])
                let url = String(source[closeBracket.upperBound..<closeParen])
                output.append(attributed(label, base: baseAttributes, extra: [
                    .foregroundColor: theme.accentColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                    .qmLinkURL: url
                ]))
                index = source.index(after: closeParen)
                continue
            }

            if source[index] == "#",
               (index == source.startIndex || source[source.index(before: index)].isWhitespace) {
                let tagEnd = source[index...].dropFirst().firstIndex(where: { !$0.isTagCharacter }) ?? source.endIndex
                if tagEnd > source.index(after: index) {
                let token = String(source[index..<tagEnd])
                output.append(attributed(token, base: baseAttributes, extra: [
                    .foregroundColor: NSColor.systemBlue.withAlphaComponent(0.96),
                    .qmTag: true
                ]))
                index = tagEnd
                continue
                }
            }

            output.append(attributed(String(source[index]), base: baseAttributes))
            index = source.index(after: index)
        }

        if output.length == 0 {
            output.append(NSAttributedString(string: "", attributes: baseAttributes))
        }
        return output
    }

    private static func attributed(_ string: String, base: [NSAttributedString.Key: Any], extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        NSAttributedString(string: string, attributes: base.merging(extra) { _, new in new })
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

    private static func rangeAfterVisiblePrefix(for range: NSRange, in attributedString: NSAttributedString, kind: MarkdownParagraphKind) -> NSRange {
        let prefixLength = visiblePrefixLength(for: range, in: attributedString, kind: kind)
        return NSRange(location: range.location + prefixLength, length: max(range.length - prefixLength, 0))
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

        return self == "_" || self == "-"
    }
}
