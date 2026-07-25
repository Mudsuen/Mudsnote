import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore

extension NSAttributedString.Key {
    static let qmParagraphKind = NSAttributedString.Key("MudsnoteParagraphKind")
    static let qmCode = NSAttributedString.Key("MudsnoteCode")
    static let qmLinkURL = NSAttributedString.Key("MudsnoteLinkURL")
    static let qmAutomaticLink = NSAttributedString.Key("MudsnoteAutomaticLink")
    static let qmTag = NSAttributedString.Key("MudsnoteTag")
    static let qmImageMarkdown = NSAttributedString.Key("MudsnoteImageMarkdown")
    static let qmImageFilePath = NSAttributedString.Key("MudsnoteImageFilePath")
    static let qmAttachmentMarkdown = NSAttributedString.Key("MudsnoteAttachmentMarkdown")
    static let qmAttachmentFilePath = NSAttributedString.Key("MudsnoteAttachmentFilePath")
    static let qmAttachmentMetadata = NSAttributedString.Key("MudsnoteAttachmentMetadata")
    static let qmTableID = NSAttributedString.Key("MudsnoteTableID")
    static let qmTableRow = NSAttributedString.Key("MudsnoteTableRow")
    static let qmTableColumn = NSAttributedString.Key("MudsnoteTableColumn")
    static let qmTableColumnCount = NSAttributedString.Key("MudsnoteTableColumnCount")
    static let qmTableColumnAlignment = NSAttributedString.Key("MudsnoteTableColumnAlignment")
    static let qmTablePlaceholder = NSAttributedString.Key("MudsnoteTablePlaceholder")
    static let qmTableTerminalNewline = NSAttributedString.Key("MudsnoteTableTerminalNewline")
    static let qmSearchHighlight = NSAttributedString.Key("MudsnoteSearchHighlight")
    static let qmHighlight = NSAttributedString.Key("MudsnoteHighlight")
}

final class MarkdownImageAttachmentReference: NSObject {
    let range: NSRange
    let path: String
    let naturalSize: NSSize
    let displaySize: NSSize

    init(range: NSRange, path: String, naturalSize: NSSize, displaySize: NSSize) {
        self.range = range
        self.path = path
        self.naturalSize = naturalSize
        self.displaySize = displaySize
    }
}

private final class MarkdownImageResizeMenuCommand: NSObject {
    let fileURL: URL
    let preferredWidth: Double?

    init(fileURL: URL, preferredWidth: Double?) {
        self.fileURL = fileURL
        self.preferredWidth = preferredWidth
    }
}

final class MarkdownAttachmentReference: NSObject {
    let path: String
    let markdown: String
    let metadata: String

    init(path: String, markdown: String, metadata: String) {
        self.path = path
        self.markdown = markdown
        self.metadata = metadata
    }
}

final class MarkdownLinkReference: NSObject {
    let range: NSRange
    let label: String
    let url: String

    init(range: NSRange, label: String, url: String) {
        self.range = range
        self.label = label
        self.url = url
    }
}

enum MarkdownLinkDestination: Equatable {
    case localMarkdown(URL)
    case external(URL)
}

func markdownLinkDestination(_ rawValue: String, relativeTo sourceURL: URL?) -> MarkdownLinkDestination? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let sourceURL,
       let localURL = MarkdownLocalLinkResolver.fileURL(for: trimmed, relativeTo: sourceURL) {
        guard FileManager.default.fileExists(atPath: localURL.path) else { return nil }
        return .localMarkdown(localURL)
    }

    guard let externalURL = openableMarkdownLinkURL(trimmed) else { return nil }
    return .external(externalURL)
}

func openableMarkdownLinkURL(_ rawValue: String) -> URL? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    if let url = URL(string: trimmed),
       let scheme = url.scheme?.lowercased(),
       ["http", "https", "mailto", "tel"].contains(scheme) {
        return url
    }

    guard !trimmed.contains(":") else { return nil }
    return URL(string: "https://\(trimmed)")
}

let markdownItalicObliqueness: CGFloat = 0.16

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
    var lineSpacing: CGFloat = 2
    var paragraphSpacing: CGFloat = 6

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
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = paragraphSpacing

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
    func markdownTextViewToggleUnderline(_ textView: MarkdownTextView)
    func markdownTextViewToggleStrikethrough(_ textView: MarkdownTextView)
    func markdownTextViewToggleHeading(_ textView: MarkdownTextView)
    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView)
    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView)
    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView)
    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, didDoubleClickAttachmentAt index: Int) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, didCommandClickLinkAt index: Int) -> Bool
    func markdownTextView(_ textView: MarkdownTextView, pasteAttachmentsFrom pasteboard: NSPasteboard) -> Bool
}

extension MarkdownTextViewCommands {
    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool {
        false
    }

    func markdownTextView(_ textView: MarkdownTextView, didDoubleClickAttachmentAt index: Int) -> Bool {
        false
    }

    func markdownTextView(_ textView: MarkdownTextView, didCommandClickLinkAt index: Int) -> Bool {
        false
    }

    func markdownTextView(_ textView: MarkdownTextView, pasteAttachmentsFrom pasteboard: NSPasteboard) -> Bool {
        false
    }
}

private final class ConciseEditorContextMenu: NSMenu {
    var isSealed = false

    override func addItem(_ newItem: NSMenuItem) {
        guard !isSealed || newItem.identifier?.rawValue == "mudsnote.editor.context-menu.allowed" else { return }
        super.addItem(newItem)
    }

    override func insertItem(_ newItem: NSMenuItem, at index: Int) {
        guard !isSealed || newItem.identifier?.rawValue == "mudsnote.editor.context-menu.allowed" else { return }
        super.insertItem(newItem, at: index)
    }
}

private final class SelectionFormattingPanelButton: NSButton {
    private(set) var menuItem: NSMenuItem
    var onPerform: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false

    init(menuItem: NSMenuItem) {
        self.menuItem = menuItem
        super.init(frame: .zero)
        target = self
        action = #selector(performMenuItem)
        image = menuItem.image
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        toolTip = menuItem.title
        setAccessibilityLabel(menuItem.title)
        bezelStyle = .toolbar
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        restoreArrowCursorAfterAction()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
    }

    private func updateAppearance() {
        let isApplied = menuItem.state == .on
        contentTintColor = isApplied ? .controlAccentColor : .labelColor
        let color: NSColor = if isApplied {
            .controlAccentColor.withAlphaComponent(isHovered ? 0.28 : 0.18)
        } else if isHovered {
            .selectedContentBackgroundColor.withAlphaComponent(0.16)
        } else {
            .clear
        }
        layer?.backgroundColor = color.cgColor
    }

    func update(menuItem: NSMenuItem) {
        self.menuItem = menuItem
        image = menuItem.image
        toolTip = menuItem.title
        setAccessibilityLabel(menuItem.title)
        updateAppearance()
    }

    @objc
    private func performMenuItem() {
        defer { restoreArrowCursorAfterAction() }
        if let submenu = menuItem.submenu {
            submenu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.maxY + 4), in: self)
            onPerform?()
            return
        }
        guard let action = menuItem.action else { return }
        NSApp.sendAction(action, to: menuItem.target, from: menuItem)
        onPerform?()
    }

    private func restoreArrowCursorAfterAction() {
        NSCursor.arrow.set()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window else { return }
            let pointer = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            guard bounds.contains(pointer) else { return }
            NSCursor.arrow.set()
        }
    }
}

final class MarkdownTextView: NSTextView, NSMenuDelegate {
    private struct ImageResizeDragState {
        let characterIndex: Int
        let initialPointerX: CGFloat
        let initialWidth: CGFloat
        let horizontalDirection: CGFloat
        let fileURL: URL
        let initialPersistedWidth: Double?
        var currentWidth: Double
    }

    private static let allowedContextMenuItemIdentifier = NSUserInterfaceItemIdentifier("mudsnote.editor.context-menu.allowed")
    private static let imageResizeEdgeHitWidth: CGFloat = 10
    weak var commandDelegate: MarkdownTextViewCommands?
    var onTextInputStateChanged: (() -> Void)?
    var configureContextMenu: ((NSMenu, NSEvent) -> Void)?
    var contextMenuOptionsProvider: (() -> Set<EditorContextMenuOption>)?
    var selectionMenuProvider: (() -> NSMenu?)?
    var onImageDisplayWidthChanged: ((URL, Double?) -> Void)?
    var imageDisplayWidthProvider: ((URL) -> Double?)?
    private var selectionFormattingPanel: NSPanel?
    private weak var selectionFormattingStack: NSStackView?
    private var imageResizeDragState: ImageResizeDragState?
    var isSelectionFormattingPanelVisible: Bool { selectionFormattingPanel?.isVisible == true }
    var selectionFormattingPanelFrame: NSRect? { selectionFormattingPanel?.frame }
    var pasteboardForPaste: () -> NSPasteboard = { .general }
    var markdownPasteTheme: MarkdownEditorTheme?

    private func updateHoverCursor(with event: NSEvent) {
        if imageResizeDragState != nil {
            NSCursor.resizeLeftRight.set()
            return
        }
        guard let layoutManager, let textContainer else {
            NSCursor.iBeam.set()
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        if imageResizeEdge(at: event) != nil {
            NSCursor.resizeLeftRight.set()
        } else if didHitChecklistPrefix(at: containerPoint, layoutManager: layoutManager, textContainer: textContainer)
            || imageAttachmentReference(atCharacterIndex: characterIndex) != nil
            || fileAttachmentReference(atCharacterIndex: characterIndex) != nil
            || linkReference(atCharacterIndex: characterIndex) != nil {
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
        if imageResizeDragState != nil {
            addCursorRect(bounds, cursor: .resizeLeftRight)
            return
        }
        addCursorRect(bounds, cursor: .iBeam)
        addChecklistCursorRects()
    }

    override func didChangeText() {
        super.didChangeText()
        if let textStorage, let theme = markdownPasteTheme {
            MarkdownRichTextCodec.refreshAutomaticLinks(
                in: textStorage,
                around: selectedRange().location,
                theme: theme
            )
        }
        window?.invalidateCursorRects(for: self)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateHoverCursor(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverCursor(with: event)
        super.mouseMoved(with: event)
    }

    override func keyDown(with event: NSEvent) {
        dismissSelectionFormattingPanel()
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == UInt16(kVK_Tab),
           modifiers.isSubset(of: [.shift]),
           indentSelectedParagraphs(outdent: modifiers.contains(.shift)) {
            return
        }
        if handleFormattingShortcut(event) {
            return
        }
        if [UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter)].contains(event.keyCode),
           modifiers == [.shift] {
            insertSoftLineBreak()
            return
        }
        if commandDelegate?.markdownTextView(self, handleKeyDown: event) == true {
            return
        }
        super.keyDown(with: event)
    }

    @discardableResult
    func indentSelectedParagraphs(outdent: Bool) -> Bool {
        guard let textStorage else { return false }
        let selection = selectedRange()
        guard selection.length > 0 else { return false }

        let string = textStorage.string as NSString
        let boundedSelection = NSIntersectionRange(selection, NSRange(location: 0, length: string.length))
        guard boundedSelection.length > 0 else { return false }
        let paragraphRange = string.paragraphRange(for: boundedSelection)
        let paragraphText = string.substring(with: paragraphRange) as NSString
        var lineStarts: [Int] = [paragraphRange.location]
        var cursor = 0
        while cursor < paragraphText.length {
            let newline = paragraphText.range(
                of: "\n",
                options: [],
                range: NSRange(location: cursor, length: paragraphText.length - cursor)
            )
            guard newline.location != NSNotFound, NSMaxRange(newline) < paragraphText.length else { break }
            lineStarts.append(paragraphRange.location + NSMaxRange(newline))
            cursor = NSMaxRange(newline)
        }
        guard lineStarts.count > 1 else { return false }

        let editableStarts = outdent
            ? lineStarts.filter { start in
                start < textStorage.length && (textStorage.string as NSString).substring(with: NSRange(location: start, length: 1)) == "\t"
            }
            : lineStarts
        guard !editableStarts.isEmpty else { return true }
        guard shouldChangeText(in: paragraphRange, replacementString: nil) else { return true }

        textStorage.beginEditing()
        for start in editableStarts.reversed() {
            if outdent {
                textStorage.deleteCharacters(in: NSRange(location: start, length: 1))
            } else {
                let attributes = start < textStorage.length ? textStorage.attributes(at: start, effectiveRange: nil) : typingAttributes
                textStorage.insert(NSAttributedString(string: "\t", attributes: attributes), at: start)
            }
        }
        textStorage.endEditing()

        let selectionStartDelta = editableStarts.filter { $0 <= selection.location }.count * (outdent ? -1 : 1)
        let selectionEnd = NSMaxRange(selection)
        let selectionEndDelta = editableStarts.filter { $0 < selectionEnd }.count * (outdent ? -1 : 1)
        let newLocation = max(selection.location + selectionStartDelta, 0)
        let newEnd = max(selectionEnd + selectionEndDelta, newLocation)
        setSelectedRange(NSRange(location: newLocation, length: newEnd - newLocation))
        didChangeText()
        return true
    }

    func insertSoftLineBreak() {
        insertText("\u{2028}", replacementRange: selectedRange())
    }

    private func handleFormattingShortcut(_ event: NSEvent) -> Bool {
        guard let commandDelegate else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (modifiers, event.keyCode) {
        case ([.command], UInt16(kVK_ANSI_B)):
            commandDelegate.markdownTextViewToggleBold(self)
        case ([.command], UInt16(kVK_ANSI_I)):
            commandDelegate.markdownTextViewToggleItalic(self)
        case ([.command], UInt16(kVK_ANSI_U)):
            commandDelegate.markdownTextViewToggleUnderline(self)
        case ([.command, .shift], UInt16(kVK_ANSI_X)):
            commandDelegate.markdownTextViewToggleStrikethrough(self)
        case ([.command, .option], UInt16(kVK_ANSI_1)):
            commandDelegate.markdownTextViewToggleHeading(self)
        case ([.command, .shift], UInt16(kVK_ANSI_7)):
            commandDelegate.markdownTextViewToggleOrderedList(self)
        case ([.command, .shift], UInt16(kVK_ANSI_8)):
            commandDelegate.markdownTextViewToggleBulletList(self)
        case ([.command, .shift], UInt16(kVK_ANSI_9)):
            commandDelegate.markdownTextViewToggleChecklist(self)
        default:
            return false
        }
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == [.command], event.keyCode == UInt16(kVK_ANSI_Z) {
            dismissSelectionFormattingPanel()
            undoManager?.undo()
            return true
        }
        if modifiers == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_Z) {
            dismissSelectionFormattingPanel()
            undoManager?.redo()
            return true
        }
        if handleFormattingShortcut(event) {
            DispatchQueue.main.async { [weak self] in self?.refreshSelectionFormattingPanel() }
            return true
        }
        if modifiers == [.command], event.keyCode == 9,
           pasteContents(from: pasteboardForPaste()) {
            return true
        }
        return super.performKeyEquivalent(with: event)
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
        if !pasteContents(from: pasteboardForPaste()) {
            super.paste(sender)
        }
    }

    @discardableResult
    func pasteContents(from pasteboard: NSPasteboard) -> Bool {
        if commandDelegate?.markdownTextView(self, pasteAttachmentsFrom: pasteboard) == true {
            return true
        }
        if let markdownPasteTheme,
           let importedMarkdown = MarkdownRichPasteNormalizer.markdown(from: pasteboard, theme: markdownPasteTheme) {
            let markdown = markdownWithInsertionBoundaries(importedMarkdown)
            let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: markdownPasteTheme)
            insertText(rendered, replacementRange: selectedRange())
            return true
        }
        guard let string = pasteboard.string(forType: .string) else { return false }
        insertText(string, replacementRange: selectedRange())
        return true
    }

    private func markdownWithInsertionBoundaries(_ markdown: String) -> String {
        let selection = selectedRange()
        let current = string as NSString
        var result = markdown

        if selection.location > 0,
           current.substring(with: NSRange(location: selection.location - 1, length: 1)) != "\n" {
            result = "\n" + result
        }
        if NSMaxRange(selection) < current.length,
           current.substring(with: NSRange(location: NSMaxRange(selection), length: 1)) != "\n",
           !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let selectionBeforeContextClick = selectedRange()
        let clickedTrailingWhitespace = isEventInTrailingLineWhitespace(event)
        let nativeMenu = super.menu(for: event) ?? NSMenu()
        if clickedTrailingWhitespace {
            setSelectedRange(selectionBeforeContextClick)
        }

        let menu = conciseEditingMenu(from: nativeMenu)
        appendImageResizeMenuIfNeeded(to: menu, for: event)
        configureContextMenu?(menu, event)
        sealContextMenu(menu)
        menu.delegate = self
        return menu
    }

    @discardableResult
    func resizeImage(
        atCharacterIndex characterIndex: Int,
        preferredWidth: Double?,
        persistsDisplayWidth: Bool = true
    ) -> Bool {
        guard let reference = imageAttachmentReference(atCharacterIndex: characterIndex),
              let textStorage,
              let attachment = textStorage.attribute(
                .attachment,
                at: reference.range.location,
                effectiveRange: nil
              ) as? NSTextAttachment else {
            return false
        }

        let displaySize = MarkdownImageDisplaySizing.displaySize(
            for: reference.naturalSize,
            preferredWidth: preferredWidth
        )
        attachment.bounds = NSRect(x: 0, y: -4, width: displaySize.width, height: displaySize.height)
        if let cell = attachment.attachmentCell as? NSCell {
            cell.setAccessibilityLabel("图片")
            cell.setAccessibilityValue("宽度 \(Int(displaySize.width.rounded())) 点")
        }
        layoutManager?.invalidateLayout(
            forCharacterRange: reference.range,
            actualCharacterRange: nil
        )
        layoutManager?.invalidateDisplay(forCharacterRange: reference.range)
        layoutManager?.ensureLayout(forCharacterRange: reference.range)
        needsDisplay = true
        displayIfNeeded()
        if persistsDisplayWidth {
            onImageDisplayWidthChanged?(URL(fileURLWithPath: reference.path), preferredWidth)
        }
        return true
    }

    @discardableResult
    func applyImageDisplayWidth(
        for fileURL: URL,
        preferredWidth: Double?,
        registersUndo: Bool = true
    ) -> Bool {
        guard let characterIndex = characterIndexForImage(at: fileURL) else {
            return false
        }
        let standardizedURL = fileURL.standardizedFileURL
        let previousWidth = imageDisplayWidthProvider?(standardizedURL)
        guard resizeImage(
            atCharacterIndex: characterIndex,
            preferredWidth: preferredWidth,
            persistsDisplayWidth: false
        ) else {
            return false
        }
        onImageDisplayWidthChanged?(standardizedURL, preferredWidth)
        if registersUndo, previousWidth != preferredWidth {
            registerImageResizeUndo(fileURL: standardizedURL, restoring: previousWidth)
        }
        return true
    }

    func imageResizeMenu(atCharacterIndex characterIndex: Int) -> NSMenu? {
        guard let reference = imageAttachmentReference(atCharacterIndex: characterIndex) else {
            return nil
        }
        let fileURL = URL(fileURLWithPath: reference.path).standardizedFileURL
        let availableWidth = MarkdownImageDisplaySizing.clampedWidth(
            max(visibleRect.width - (textContainerInset.width * 2) - 8, 80)
        )
        let menu = NSMenu(title: "图片大小")
        let commands: [(String, Double?)] = [
            ("适合编辑器", availableWidth),
            ("25%", availableWidth * 0.25),
            ("50%", availableWidth * 0.5),
            ("75%", availableWidth * 0.75),
            ("100%", availableWidth),
            ("原始大小", Double(reference.naturalSize.width))
        ]
        for (title, preferredWidth) in commands {
            let item = NSMenuItem(
                title: title,
                action: #selector(imageResizeMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = MarkdownImageResizeMenuCommand(
                fileURL: fileURL,
                preferredWidth: preferredWidth.map {
                    MarkdownImageDisplaySizing.clampedWidth(CGFloat($0))
                }
            )
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let reset = NSMenuItem(
            title: "重置自定义大小",
            action: #selector(imageResizeMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        reset.target = self
        reset.representedObject = MarkdownImageResizeMenuCommand(fileURL: fileURL, preferredWidth: nil)
        menu.addItem(reset)
        return menu
    }

    private func appendImageResizeMenuIfNeeded(to menu: NSMenu, for event: NSEvent) {
        guard let characterIndex = characterIndex(at: event),
              let submenu = imageResizeMenu(atCharacterIndex: characterIndex) else {
            return
        }
        if !menu.items.isEmpty {
            menu.addItem(.separator())
        }
        let item = NSMenuItem(title: "图片大小", action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "photo", accessibilityDescription: "图片大小")
        item.submenu = submenu
        menu.addItem(item)
    }

    @objc
    private func imageResizeMenuItemPressed(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? MarkdownImageResizeMenuCommand else {
            return
        }
        _ = applyImageDisplayWidth(
            for: command.fileURL,
            preferredWidth: command.preferredWidth
        )
    }

    private func characterIndexForImage(at fileURL: URL) -> Int? {
        guard let textStorage else { return nil }
        let path = fileURL.standardizedFileURL.path
        var match: Int?
        textStorage.enumerateAttribute(
            .qmImageFilePath,
            in: NSRange(location: 0, length: textStorage.length)
        ) { value, range, stop in
            guard let candidate = value as? String,
                  URL(fileURLWithPath: candidate).standardizedFileURL.path == path else {
                return
            }
            match = range.location
            stop.pointee = true
        }
        return match
    }

    private func registerImageResizeUndo(fileURL: URL, restoring preferredWidth: Double?) {
        undoManager?.registerUndo(withTarget: self) { target in
            _ = target.applyImageDisplayWidth(
                for: fileURL,
                preferredWidth: preferredWidth,
                registersUndo: true
            )
        }
        undoManager?.setActionName("调整图片大小")
    }

    func imageAttachmentFrame(atCharacterIndex characterIndex: Int) -> NSRect? {
        guard let reference = imageAttachmentReference(atCharacterIndex: characterIndex),
              let layoutManager,
              let textContainer else {
            return nil
        }
        layoutManager.ensureLayout(for: textContainer)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: reference.range,
            actualCharacterRange: nil
        )
        var frame = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        frame.origin.x += textContainerInset.width
        frame.origin.y += textContainerInset.height
        return frame
    }

    private func imageResizeEdge(at event: NSEvent) -> (characterIndex: Int, direction: CGFloat)? {
        guard let layoutManager,
              let textContainer,
              layoutManager.numberOfGlyphs > 0 else {
            return nil
        }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard let frame = imageAttachmentFrame(atCharacterIndex: characterIndex),
              point.y >= frame.minY,
              point.y <= frame.maxY else {
            return nil
        }

        let leftDistance = abs(point.x - frame.minX)
        let rightDistance = abs(point.x - frame.maxX)
        let nearestDistance = min(leftDistance, rightDistance)
        if nearestDistance <= Self.imageResizeEdgeHitWidth {
            return (characterIndex, leftDistance < rightDistance ? -1 : 1)
        }
        return nil
    }

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items.reversed()
        where item.identifier != Self.allowedContextMenuItemIdentifier {
            menu.removeItem(item)
        }
    }

    func markCurrentContextMenuItemsAsAllowed(in menu: NSMenu) {
        menu.items.forEach { $0.identifier = Self.allowedContextMenuItemIdentifier }
    }

    func sealContextMenu(_ menu: NSMenu) {
        markCurrentContextMenuItemsAsAllowed(in: menu)
        (menu as? ConciseEditorContextMenu)?.isSealed = true
    }

    func isEventInTrailingLineWhitespace(_ event: NSEvent) -> Bool {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else {
            return true
        }

        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        guard containerPoint.x >= 0, containerPoint.y >= 0 else { return false }

        let glyphIndex = min(
            layoutManager.glyphIndex(for: containerPoint, in: textContainer),
            layoutManager.numberOfGlyphs - 1
        )
        let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard lineRect.contains(NSPoint(x: lineRect.midX, y: containerPoint.y)) else { return true }

        let usedRect = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        return containerPoint.x > usedRect.maxX + 1
    }

    func conciseEditingMenu(from nativeMenu: NSMenu) -> NSMenu {
        let menu = ConciseEditorContextMenu()
        menu.allowsContextMenuPlugIns = false
        let options = contextMenuOptionsProvider?() ?? Set(EditorContextMenuOption.allCases)
        var groups: [[NSMenuItem]] = []

        if options.contains(.undo) {
            let undoItem = NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
            undoItem.keyEquivalentModifierMask = [.command]
            undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销")
            groups.append([undoItem])
        }
        if options.contains(.translate), let translationItem = nativeMenu.items.first(where: {
            let title = $0.title.lowercased()
            return title.hasPrefix("translate") || title.hasPrefix("翻译")
        }), let copiedItem = translationItem.copy() as? NSMenuItem {
            copiedItem.title = "翻译"
            groups.append([copiedItem])
        }

        let commands: [(EditorContextMenuOption, String, Selector, String)] = [
            (.cut, "剪切", #selector(NSText.cut(_:)), "x"),
            (.copy, "拷贝", #selector(NSText.copy(_:)), "c"),
            (.paste, "粘贴", #selector(NSText.paste(_:)), "v")
        ]
        let editingItems = commands.compactMap { option, title, action, keyEquivalent -> NSMenuItem? in
            guard options.contains(option) else { return nil }
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
            item.keyEquivalentModifierMask = [.command]
            return item
        }
        if !editingItems.isEmpty { groups.append(editingItems) }

        for (index, group) in groups.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            group.forEach(menu.addItem)
        }
        return menu
    }

    override func mouseDown(with event: NSEvent) {
        dismissSelectionFormattingPanel()
        let selectionBeforeMouseDown = selectedRange()
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

        if event.type == .leftMouseDown,
           let resizeEdge = imageResizeEdge(at: event),
           let reference = imageAttachmentReference(atCharacterIndex: resizeEdge.characterIndex) {
            imageResizeDragState = ImageResizeDragState(
                characterIndex: resizeEdge.characterIndex,
                initialPointerX: point.x,
                initialWidth: reference.displaySize.width,
                horizontalDirection: resizeEdge.direction,
                fileURL: URL(fileURLWithPath: reference.path),
                initialPersistedWidth: imageDisplayWidthProvider?(
                    URL(fileURLWithPath: reference.path).standardizedFileURL
                ),
                currentWidth: Double(reference.displaySize.width)
            )
            window?.invalidateCursorRects(for: self)
            NSCursor.resizeLeftRight.set()
            return
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == [.command],
           linkReference(atCharacterIndex: characterIndex) != nil,
           commandDelegate?.markdownTextView(self, didCommandClickLinkAt: characterIndex) == true {
            return
        }

        if event.clickCount >= 2,
           fileAttachmentReference(atCharacterIndex: characterIndex) != nil,
           commandDelegate?.markdownTextView(self, didDoubleClickAttachmentAt: characterIndex) == true {
            return
        }

        if didHitChecklistPrefix(at: containerPoint, layoutManager: layoutManager, textContainer: textContainer),
           commandDelegate?.markdownTextView(self, didClickCharacterAt: characterIndex) == true {
            return
        }

        super.mouseDown(with: event)
        let selectionAfterMouseDown = selectedRange()
        if selectionAfterMouseDown.length > 0,
           selectionAfterMouseDown != selectionBeforeMouseDown {
            showSelectionMenuIfNeeded()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if var resize = imageResizeDragState {
            let pointerX = convert(event.locationInWindow, from: nil).x
            let width = MarkdownImageDisplaySizing.clampedWidth(
                resize.initialWidth
                    + (pointerX - resize.initialPointerX) * resize.horizontalDirection
            )
            guard resizeImage(
                atCharacterIndex: resize.characterIndex,
                preferredWidth: width,
                persistsDisplayWidth: false
            ) else {
                imageResizeDragState = nil
                window?.invalidateCursorRects(for: self)
                return
            }
            resize.currentWidth = width
            imageResizeDragState = resize
            NSCursor.resizeLeftRight.set()
            return
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let resize = imageResizeDragState {
            imageResizeDragState = nil
            if abs(resize.currentWidth - Double(resize.initialWidth)) > 0.5 {
                onImageDisplayWidthChanged?(resize.fileURL, resize.currentWidth)
                registerImageResizeUndo(
                    fileURL: resize.fileURL.standardizedFileURL,
                    restoring: resize.initialPersistedWidth
                )
            }
            window?.invalidateCursorRects(for: self)
            updateHoverCursor(with: event)
            return
        }
        super.mouseUp(with: event)
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        var actions = super.accessibilityCustomActions() ?? []
        guard let fileURL = selectedImageFileURL() else { return actions }
        let fitAction = NSAccessibilityCustomAction(name: "图片适合编辑器") { [weak self] in
            guard let self else { return false }
            let width = MarkdownImageDisplaySizing.clampedWidth(
                max(self.visibleRect.width - (self.textContainerInset.width * 2) - 8, 80)
            )
            return self.applyImageDisplayWidth(for: fileURL, preferredWidth: width)
        }
        let resetAction = NSAccessibilityCustomAction(name: "重置图片大小") { [weak self] in
            self?.applyImageDisplayWidth(for: fileURL, preferredWidth: nil) ?? false
        }
        actions.append(contentsOf: [fitAction, resetAction])
        return actions
    }

    private func selectedImageFileURL() -> URL? {
        guard let textStorage, textStorage.length > 0 else { return nil }
        let location = min(selectedRange().location, textStorage.length - 1)
        guard let path = textStorage.attribute(
            .qmImageFilePath,
            at: location,
            effectiveRange: nil
        ) as? String else {
            return nil
        }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    func showSelectionMenuIfNeeded() {
        dismissSelectionFormattingPanel()
        let selection = selectedRange()
        guard selection.length > 0,
              let menu = selectionMenuProvider?(),
              !menu.items.isEmpty,
              let layoutManager,
              let textContainer else { return }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
        var selectionRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        selectionRect.origin.x += textContainerInset.width
        selectionRect.origin.y += textContainerInset.height
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 7, bottom: 6, right: 7)

        populateSelectionFormattingStack(stack, with: menu)
        guard let hostWindow = window else { return }
        let panelSize = NSSize(width: CGFloat(stack.arrangedSubviews.count * 34 + 14), height: 40)
        let surface = NSVisualEffectView(frame: NSRect(origin: .zero, size: panelSize))
        surface.material = .menu
        surface.state = .active
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 10
        surface.layer?.masksToBounds = true
        surface.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            stack.topAnchor.constraint(equalTo: surface.topAnchor),
            stack.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = true
        panel.contentView = surface
        let selectionWindowRect = convert(selectionRect, to: nil)
        let selectionScreenRect = hostWindow.convertToScreen(selectionWindowRect)
        panel.setFrameOrigin(Self.selectionFormattingPanelOrigin(
            centeredAtPointerX: NSEvent.mouseLocation.x,
            verticalOrigin: selectionScreenRect.minY - panelSize.height - 6,
            panelSize: panelSize,
            visibleFrame: hostWindow.screen?.visibleFrame
        ))
        selectionFormattingPanel = panel
        selectionFormattingStack = stack
        hostWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        hostWindow.makeFirstResponder(self)
    }

    nonisolated static func selectionFormattingPanelOrigin(
        centeredAtPointerX pointerX: CGFloat,
        verticalOrigin: CGFloat,
        panelSize: NSSize,
        visibleFrame: NSRect?
    ) -> NSPoint {
        var origin = NSPoint(
            x: pointerX - panelSize.width / 2,
            y: verticalOrigin
        )
        guard let visibleFrame else { return origin }
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.maxX - panelSize.width, visibleFrame.minX))
        return origin
    }

    private func populateSelectionFormattingStack(_ stack: NSStackView, with menu: NSMenu) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in menu.items where !item.isSeparatorItem {
            let button = SelectionFormattingPanelButton(menuItem: item)
            button.onPerform = { [weak self] in
                DispatchQueue.main.async { self?.refreshSelectionFormattingPanel() }
            }
            stack.addArrangedSubview(button)
        }
    }

    private func refreshSelectionFormattingPanel() {
        guard selectionFormattingPanel != nil,
              selectedRange().length > 0,
              let stack = selectionFormattingStack,
              let menu = selectionMenuProvider?(),
              !menu.items.isEmpty else {
            dismissSelectionFormattingPanel()
            return
        }
        let items = menu.items.filter { !$0.isSeparatorItem }
        let buttons = stack.arrangedSubviews.compactMap { $0 as? SelectionFormattingPanelButton }
        if buttons.count == items.count,
           zip(buttons, items).allSatisfy({ pair in pair.0.menuItem.title == pair.1.title }) {
            for (button, item) in zip(buttons, items) {
                button.update(menuItem: item)
            }
        } else {
            populateSelectionFormattingStack(stack, with: menu)
        }
    }

    private func dismissSelectionFormattingPanel() {
        guard let panel = selectionFormattingPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        selectionFormattingPanel = nil
        selectionFormattingStack = nil
    }

    func fileAttachmentReference(at event: NSEvent) -> MarkdownAttachmentReference? {
        guard let characterIndex = characterIndex(at: event) else { return nil }
        return fileAttachmentReference(atCharacterIndex: characterIndex)
    }

    func imageAttachmentReference(atCharacterIndex characterIndex: Int) -> MarkdownImageAttachmentReference? {
        guard let textStorage,
              characterIndex >= 0,
              characterIndex < textStorage.length else {
            return nil
        }
        var effectiveRange = NSRange(location: 0, length: 0)
        guard let path = textStorage.attribute(
            .qmImageFilePath,
            at: characterIndex,
            effectiveRange: &effectiveRange
        ) as? String,
        let attachment = textStorage.attribute(
            .attachment,
            at: characterIndex,
            effectiveRange: nil
        ) as? NSTextAttachment,
        let naturalSize = MarkdownRichTextCodec.naturalImageSize(for: attachment),
        naturalSize.width > 0,
        naturalSize.height > 0 else {
            return nil
        }
        return MarkdownImageAttachmentReference(
            range: effectiveRange,
            path: path,
            naturalSize: naturalSize,
            displaySize: attachment.bounds.size
        )
    }

    func linkReference(at event: NSEvent) -> MarkdownLinkReference? {
        guard let characterIndex = characterIndex(at: event) else { return nil }
        return linkReference(atCharacterIndex: characterIndex)
    }

    func linkReference(atCharacterIndex characterIndex: Int) -> MarkdownLinkReference? {
        guard let textStorage,
              characterIndex >= 0,
              characterIndex < textStorage.length else {
            return nil
        }

        var effectiveRange = NSRange(location: 0, length: 0)
        guard let url = textStorage.attribute(
            .qmLinkURL,
            at: characterIndex,
            effectiveRange: &effectiveRange
        ) as? String,
        effectiveRange.length > 0 else {
            return nil
        }
        let label = (textStorage.string as NSString).substring(with: effectiveRange)
        return MarkdownLinkReference(range: effectiveRange, label: label, url: url)
    }

    func linkReference(for selection: NSRange) -> MarkdownLinkReference? {
        guard let textStorage,
              selection.location >= 0,
              NSMaxRange(selection) <= textStorage.length else {
            return nil
        }

        if selection.length == 0 {
            return linkReference(atCharacterIndex: selection.location)
        }

        guard let reference = linkReference(atCharacterIndex: selection.location),
              NSMaxRange(selection) <= NSMaxRange(reference.range) else {
            return nil
        }
        return reference
    }

    func characterIndex(at event: NSEvent) -> Int? {
        guard !isEventInTrailingLineWhitespace(event), let layoutManager, let textContainer else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: point.x - textContainerInset.width,
            y: point.y - textContainerInset.height
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }

    func fileAttachmentReference(atCharacterIndex characterIndex: Int) -> MarkdownAttachmentReference? {
        guard let textStorage, characterIndex >= 0, characterIndex < textStorage.length else { return nil }
        guard
            let path = textStorage.attribute(.qmAttachmentFilePath, at: characterIndex, effectiveRange: nil) as? String,
            let markdown = textStorage.attribute(.qmAttachmentMarkdown, at: characterIndex, effectiveRange: nil) as? String
        else { return nil }
        let metadata = textStorage.attribute(.qmAttachmentMetadata, at: characterIndex, effectiveRange: nil) as? String ?? ""
        return MarkdownAttachmentReference(path: path, markdown: markdown, metadata: metadata)
    }

    func fileAttachmentReferenceNearSelection() -> MarkdownAttachmentReference? {
        let selection = selectedRange()
        if selection.length > 0 {
            let upperBound = min(NSMaxRange(selection), textStorage?.length ?? 0)
            for index in selection.location..<upperBound {
                if let attachment = fileAttachmentReference(atCharacterIndex: index) {
                    return attachment
                }
            }
        }

        for index in [selection.location, selection.location - 1] where index >= 0 {
            if let attachment = fileAttachmentReference(atCharacterIndex: index) {
                return attachment
            }
        }
        return nil
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

@MainActor
private final class FileAttachmentPreviewCell: NSTextAttachmentCell {
    private let displayTitle: String
    private let subtitle: String
    private let icon: NSImage

    init(fileURL: URL, label: String) {
        let fallbackTitle = fileURL.lastPathComponent.isEmpty ? "Attachment" : fileURL.lastPathComponent
        self.displayTitle = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallbackTitle : label
        self.subtitle = MarkdownRichTextCodec.attachmentMetadataText(for: fileURL)
        self.icon = NSWorkspace.shared.icon(forFile: fileURL.path)
        self.icon.size = NSSize(width: 22, height: 22)
        super.init(textCell: "")
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func cellSize() -> NSSize {
        NSSize(width: 260, height: 38)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let rect = cellFrame.insetBy(dx: 1, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        panelSubtleFillColor().withAlphaComponent(0.22).setFill()
        path.fill()
        panelTertiaryTextColor().withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()

        let iconRect = NSRect(
            x: rect.minX + 9,
            y: rect.midY - 11,
            width: 22,
            height: 22
        )
        icon.draw(in: iconRect)

        let titleRect = NSRect(
            x: iconRect.maxX + 8,
            y: rect.minY + 16,
            width: rect.width - 48,
            height: 16
        )
        let subtitleRect = NSRect(
            x: iconRect.maxX + 8,
            y: rect.minY + 5,
            width: rect.width - 48,
            height: 13
        )
        drawClipped(displayTitle, in: titleRect, font: .systemFont(ofSize: 12, weight: .semibold), color: panelPrimaryTextColor())
        drawClipped(subtitle, in: subtitleRect, font: .systemFont(ofSize: 10, weight: .medium), color: panelTertiaryTextColor())
    }

    private func drawClipped(_ text: String, in rect: NSRect, font: NSFont, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
    }
}

enum MarkdownImageDecoding {
    static let maximumThumbnailPixelSize = 2_400

    static func pixelSize(at imageURL: URL) -> NSSize? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0,
              height.doubleValue > 0 else {
            return nil
        }
        return NSSize(width: width.doubleValue, height: height.doubleValue)
    }

    nonisolated static func thumbnail(
        at imageURL: URL,
        maximumPixelSize: Int = maximumThumbnailPixelSize
    ) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

private final class MarkdownDecodedImageCacheEntry: NSObject {
    let image: CGImage

    init(image: CGImage) {
        self.image = image
    }
}

actor MarkdownImageDecodeService {
    static let shared = MarkdownImageDecodeService()

    private let cache: NSCache<NSString, MarkdownDecodedImageCacheEntry>
    private(set) var decodeCount = 0

    init() {
        cache = NSCache<NSString, MarkdownDecodedImageCacheEntry>()
        cache.countLimit = 64
        cache.totalCostLimit = 128 * 1_024 * 1_024
    }

    func thumbnail(
        at imageURL: URL,
        maximumPixelSize: Int = MarkdownImageDecoding.maximumThumbnailPixelSize
    ) -> CGImage? {
        let standardizedURL = imageURL.standardizedFileURL
        let values = try? standardizedURL.resourceValues(forKeys: [
            .contentModificationDateKey,
            .fileSizeKey
        ])
        let modifiedAt = values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? -1
        let fileSize = values?.fileSize ?? -1
        let key = [
            standardizedURL.path,
            String(modifiedAt),
            String(fileSize),
            String(maximumPixelSize)
        ].joined(separator: "|") as NSString
        if let cached = cache.object(forKey: key) {
            return cached.image
        }
        guard let image = MarkdownImageDecoding.thumbnail(
            at: standardizedURL,
            maximumPixelSize: maximumPixelSize
        ) else {
            return nil
        }
        decodeCount += 1
        cache.setObject(
            MarkdownDecodedImageCacheEntry(image: image),
            forKey: key,
            cost: image.bytesPerRow * image.height
        )
        return image
    }

    func resetForTesting() {
        cache.removeAllObjects()
        decodeCount = 0
    }
}

@MainActor
final class AsyncImageAttachmentCell: NSTextAttachmentCell {
    private let imageURL: URL
    let naturalSize: NSSize
    private var decodeTask: Task<Void, Never>?
    private(set) var hasDecodedImage = false

    init(imageURL: URL, naturalSize: NSSize) {
        self.imageURL = imageURL
        self.naturalSize = naturalSize
        super.init(imageCell: NSImage(size: naturalSize))
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        decodeTask?.cancel()
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        beginDecodingIfNeeded(in: controlView)
        if hasDecodedImage {
            super.draw(withFrame: cellFrame, in: controlView)
        } else {
            let placeholder = NSBezierPath(roundedRect: cellFrame, xRadius: 8, yRadius: 8)
            panelSubtleFillColor().withAlphaComponent(0.18).setFill()
            placeholder.fill()
        }
    }

    func beginDecodingIfNeeded(in controlView: NSView?) {
        guard decodeTask == nil, !hasDecodedImage else { return }
        let imageURL = imageURL
        let naturalSize = naturalSize
        weak let textView = controlView as? NSTextView
        decodeTask = Task { [weak self, weak textView] in
            guard !Task.isCancelled,
                  let thumbnail = await MarkdownImageDecodeService.shared.thumbnail(at: imageURL),
                  !Task.isCancelled,
                  let self else {
                return
            }
            self.image = NSImage(cgImage: thumbnail, size: naturalSize)
            self.hasDecodedImage = true
            textView?.needsDisplay = true
        }
    }
}

enum MarkdownRichTextCodec {
    private static let tablePlaceholder = "\u{200B}"

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
        guard textStorage.length > 0 else { return }
        let string = textStorage.string as NSString
        let safeLocation = min(max(location, 0), max(string.length - 1, 0))
        let paragraphRange = string.paragraphRange(for: NSRange(location: safeLocation, length: 0))
        applyAutomaticLinks(in: textStorage, range: paragraphRange, theme: theme)
    }

    @MainActor
    private static func applyAutomaticLinks(
        in attributedString: NSMutableAttributedString,
        range: NSRange,
        theme: MarkdownEditorTheme
    ) {
        guard range.length > 0,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }

        attributedString.enumerateAttribute(.qmAutomaticLink, in: range) { value, effectiveRange, _ in
            guard (value as? Bool) == true else { return }
            attributedString.removeAttribute(.qmAutomaticLink, range: effectiveRange)
            attributedString.removeAttribute(.qmLinkURL, range: effectiveRange)
            attributedString.removeAttribute(.underlineStyle, range: effectiveRange)
            attributedString.addAttribute(.foregroundColor, value: theme.textColor, range: effectiveRange)
        }

        let text = attributedString.string as NSString
        for match in detector.matches(in: text as String, range: range) {
            let matchRange = match.range
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

        return self == "_" || self == "-"
    }
}
