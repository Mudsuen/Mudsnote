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
    var onTextInputStateChanged: (() -> Void)?

    private func updateHoverCursor(with event: NSEvent) {
        guard let layoutManager, let textContainer else {
            NSCursor.iBeam.set()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )

        if didHitChecklistPrefix(at: containerPoint, layoutManager: layoutManager, textContainer: textContainer) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
        addChecklistCursorRects()
    }

    override func didChangeText() {
        super.didChangeText()
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateHoverCursor(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverCursor(with: event)
        super.mouseMoved(with: event)
    }

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
        onTextInputStateChanged?()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        onTextInputStateChanged?()
    }

    override func unmarkText() {
        super.unmarkText()
        onTextInputStateChanged?()
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

        if didHitChecklistPrefix(at: containerPoint, layoutManager: layoutManager, textContainer: textContainer),
           commandDelegate?.markdownTextView(self, didClickCharacterAt: characterIndex) == true {
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }

    private func addChecklistCursorRects() {
        guard
            let layoutManager,
            let textContainer,
            let storage = textStorage,
            storage.length > 0
        else {
            return
        }

        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)
        guard visibleCharacterRange.length > 0 else { return }

        storage.enumerateAttribute(.attachment, in: visibleCharacterRange) { value, range, _ in
            guard
                value as? NSTextAttachment != nil,
                let kind = MarkdownParagraphKind.decode(storage.attribute(.qmParagraphKind, at: range.location, effectiveRange: nil)),
                case .checklist = kind
            else {
                return
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: range.location, length: 1), actualCharacterRange: nil)
            var hitRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).insetBy(dx: -2, dy: -2)
            hitRect.origin.x += textContainerInset.width
            hitRect.origin.y += textContainerInset.height
            addCursorRect(hitRect, cursor: .pointingHand)
        }
    }

    private func didHitChecklistPrefix(
        at point: NSPoint,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> Bool {
        guard let attachmentIndex = checklistAttachmentIndex(
            near: layoutManager.characterIndexForGlyph(
                at: layoutManager.glyphIndex(for: point, in: textContainer)
            )
        ) else {
            return false
        }

        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: attachmentIndex, length: 1),
            actualCharacterRange: nil
        )
        let hitRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .insetBy(dx: -2, dy: -2)
        return hitRect.contains(point)
    }

    private func checklistAttachmentIndex(near characterIndex: Int) -> Int? {
        guard let storage = textStorage, storage.length > 0 else { return nil }

        let candidates = [characterIndex, max(characterIndex - 1, 0)]
        for candidate in candidates where candidate >= 0 && candidate < storage.length {
            guard
                let kind = MarkdownParagraphKind.decode(
                    storage.attribute(.qmParagraphKind, at: candidate, effectiveRange: nil)
                ),
                case .checklist = kind,
                storage.attribute(.attachment, at: candidate, effectiveRange: nil) as? NSTextAttachment != nil
            else {
                continue
            }
            return candidate
        }

        return nil
    }
}

final class EditorScrollView: NSScrollView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
            textView.mouseDown(with: event)
            return
        }

        super.mouseDown(with: event)
    }
}

final class EditorClipView: NSClipView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        if let textView = documentView as? NSTextView {
            window?.makeFirstResponder(textView)
            textView.mouseDown(with: event)
            return
        }

        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRectsOutsideDocumentView()
    }

    override func cursorUpdate(with event: NSEvent) {
        guard !shouldDeferCursorManagement(for: event) else { return }
        NSCursor.iBeam.set()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !shouldDeferCursorManagement(for: event) else {
            super.mouseMoved(with: event)
            return
        }
        NSCursor.iBeam.set()
        super.mouseMoved(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !shouldDeferCursorManagement(for: event) else {
            super.mouseDragged(with: event)
            return
        }
        NSCursor.iBeam.set()
        super.mouseDragged(with: event)
    }

    private func shouldDeferCursorManagement(for event: NSEvent) -> Bool {
        guard let documentView else { return false }
        let point = convert(event.locationInWindow, from: nil)
        return documentView.frame.contains(point)
    }

    private func addCursorRectsOutsideDocumentView() {
        guard let documentView else {
            addCursorRect(bounds, cursor: .iBeam)
            return
        }

        let documentFrame = documentView.frame.intersection(bounds)
        guard !documentFrame.isNull, !documentFrame.isEmpty else {
            addCursorRect(bounds, cursor: .iBeam)
            return
        }

        let topRect = NSRect(
            x: bounds.minX,
            y: documentFrame.maxY,
            width: bounds.width,
            height: max(bounds.maxY - documentFrame.maxY, 0)
        )
        let bottomRect = NSRect(
            x: bounds.minX,
            y: bounds.minY,
            width: bounds.width,
            height: max(documentFrame.minY - bounds.minY, 0)
        )
        let leftRect = NSRect(
            x: bounds.minX,
            y: documentFrame.minY,
            width: max(documentFrame.minX - bounds.minX, 0),
            height: documentFrame.height
        )
        let rightRect = NSRect(
            x: documentFrame.maxX,
            y: documentFrame.minY,
            width: max(bounds.maxX - documentFrame.maxX, 0),
            height: documentFrame.height
        )

        for rect in [topRect, bottomRect, leftRect, rightRect] where rect.width > 0 && rect.height > 0 {
            addCursorRect(rect, cursor: .iBeam)
        }
    }
}

@MainActor
private final class PrefixAttachmentCell: NSTextAttachmentCell {
    enum Style {
        case bullet
        case checklist(checked: Bool)
    }

    private let style: Style
    private let strokeColor: NSColor
    private let fillColor: NSColor

    init(style: Style, strokeColor: NSColor, fillColor: NSColor) {
        self.style = style
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        switch style {
        case .bullet:
            return NSSize(width: 11, height: 12)
        case .checklist:
            return NSSize(width: 13, height: 13)
        }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        switch style {
        case .bullet:
            drawBullet(in: cellFrame)
        case .checklist(let checked):
            drawChecklist(in: cellFrame, checked: checked, flipped: controlView?.isFlipped ?? false)
        }
    }

    private func drawBullet(in frame: NSRect) {
        let yOffset: CGFloat = 1.8
        let dotRect = NSRect(
            x: frame.midX - 3.25,
            y: frame.midY - 3.25 + yOffset,
            width: 6.5,
            height: 6.5
        )
        let dotPath = NSBezierPath(ovalIn: dotRect)
        fillColor.setFill()
        dotPath.fill()
    }

    private func drawChecklist(in frame: NSRect, checked: Bool, flipped: Bool) {
        let yOffset: CGFloat = 1.45
        let boxRect = NSRect(
            x: frame.origin.x + 0.5,
            y: frame.origin.y + 0.5 + yOffset,
            width: 11.5,
            height: 11.5
        )
        let boxPath = NSBezierPath(roundedRect: boxRect, xRadius: 3.1, yRadius: 3.1)
        boxPath.lineWidth = 1.35

        if checked {
            fillColor.setFill()
            boxPath.fill()
        } else {
            panelSubtleFillColor().withAlphaComponent(0.08).setFill()
            boxPath.fill()
        }

        strokeColor.setStroke()
        boxPath.stroke()

        guard checked else { return }

        func y(_ fractionFromTop: CGFloat) -> CGFloat {
            if flipped {
                return boxRect.minY + (boxRect.height * fractionFromTop)
            }
            return boxRect.maxY - (boxRect.height * fractionFromTop)
        }

        let checkPath = NSBezierPath()
        checkPath.lineWidth = 1.85
        checkPath.lineCapStyle = .round
        checkPath.lineJoinStyle = .round
        checkPath.move(to: NSPoint(x: boxRect.minX + 2.45, y: y(0.58)))
        checkPath.line(to: NSPoint(x: boxRect.minX + 5.05, y: y(0.79)))
        checkPath.line(to: NSPoint(x: boxRect.maxX - 2.2, y: y(0.30)))
        NSColor.white.withAlphaComponent(0.98).setStroke()
        checkPath.stroke()
    }
}

enum MarkdownRichTextCodec {
    @MainActor
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

    @MainActor
    static func renderLine(_ line: String, theme: MarkdownEditorTheme) -> NSMutableAttributedString {
        let kind = paragraphKind(for: line)
        let paragraphString = NSMutableAttributedString()
        let baseAttributes = theme.baseAttributes(for: kind)

        let prefix = kind.prefix
        if !prefix.isEmpty {
            paragraphString.append(renderPrefix(for: kind, theme: theme, baseAttributes: baseAttributes))
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
