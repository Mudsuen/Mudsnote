import AppKit
import Foundation
import MudsnoteCore

extension NSAttributedString.Key {
    static let qmParagraphKind = NSAttributedString.Key("MudsnoteParagraphKind")
    static let qmCode = NSAttributedString.Key("MudsnoteCode")
    static let qmLinkURL = NSAttributedString.Key("MudsnoteLinkURL")
    static let qmTag = NSAttributedString.Key("MudsnoteTag")
    static let qmImageMarkdown = NSAttributedString.Key("MudsnoteImageMarkdown")
    static let qmAttachmentMarkdown = NSAttributedString.Key("MudsnoteAttachmentMarkdown")
    static let qmAttachmentFilePath = NSAttributedString.Key("MudsnoteAttachmentFilePath")
    static let qmAttachmentMetadata = NSAttributedString.Key("MudsnoteAttachmentMetadata")
    static let qmTableID = NSAttributedString.Key("MudsnoteTableID")
    static let qmTableRow = NSAttributedString.Key("MudsnoteTableRow")
    static let qmTableColumn = NSAttributedString.Key("MudsnoteTableColumn")
    static let qmTableColumnCount = NSAttributedString.Key("MudsnoteTableColumnCount")
    static let qmTablePlaceholder = NSAttributedString.Key("MudsnoteTablePlaceholder")
    static let qmTableTerminalNewline = NSAttributedString.Key("MudsnoteTableTerminalNewline")
    static let qmSearchHighlight = NSAttributedString.Key("MudsnoteSearchHighlight")
    static let qmHighlight = NSAttributedString.Key("MudsnoteHighlight")
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
    let menuItem: NSMenuItem
    var onDismiss: (() -> Void)?

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
        contentTintColor = menuItem.state == .on ? .controlAccentColor : .labelColor
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 32).isActive = true
        heightAnchor.constraint(equalToConstant: 28).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func performMenuItem() {
        if let submenu = menuItem.submenu {
            submenu.popUp(positioning: nil, at: NSPoint(x: bounds.minX, y: bounds.maxY + 4), in: self)
            onDismiss?()
            return
        }
        onDismiss?()
        guard let action = menuItem.action else { return }
        NSApp.sendAction(action, to: menuItem.target, from: menuItem)
    }
}

final class MarkdownTextView: NSTextView, NSMenuDelegate {
    private static let allowedContextMenuItemIdentifier = NSUserInterfaceItemIdentifier("mudsnote.editor.context-menu.allowed")
    weak var commandDelegate: MarkdownTextViewCommands?
    var onTextInputStateChanged: (() -> Void)?
    var configureContextMenu: ((NSMenu, NSEvent) -> Void)?
    var selectionMenuProvider: (() -> NSMenu?)?
    private var selectionFormattingPanel: NSPanel?
    var pasteboardForPaste: () -> NSPasteboard = { .general }
    var markdownPasteTheme: MarkdownEditorTheme?

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

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        if didHitChecklistPrefix(at: containerPoint, layoutManager: layoutManager, textContainer: textContainer)
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

    override func keyDown(with event: NSEvent) {
        dismissSelectionFormattingPanel()
        if commandDelegate?.markdownTextView(self, handleKeyDown: event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
        configureContextMenu?(menu, event)
        sealContextMenu(menu)
        menu.delegate = self
        return menu
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
        let undoItem = NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        undoItem.keyEquivalentModifierMask = [.command]
        undoItem.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "撤销")
        menu.addItem(undoItem)
        menu.addItem(.separator())
        if let translationItem = nativeMenu.items.first(where: {
            let title = $0.title.lowercased()
            return title.hasPrefix("translate") || title.hasPrefix("翻译")
        }), let copiedItem = translationItem.copy() as? NSMenuItem {
            copiedItem.title = "翻译"
            menu.addItem(copiedItem)
            menu.addItem(.separator())
        }

        let commands: [(String, Selector, String)] = [
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("拷贝", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v")
        ]
        for (title, action, keyEquivalent) in commands {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
            item.keyEquivalentModifierMask = [.command]
            menu.addItem(item)
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
        super.mouseDragged(with: event)
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

        for item in menu.items where !item.isSeparatorItem {
            let button = SelectionFormattingPanelButton(menuItem: item)
            button.onDismiss = { [weak self] in self?.dismissSelectionFormattingPanel() }
            stack.addArrangedSubview(button)
        }
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

        let selectionWindowRect = convert(selectionRect, to: nil)
        let selectionScreenRect = hostWindow.convertToScreen(selectionWindowRect)
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
        panel.setFrameOrigin(NSPoint(
            x: selectionScreenRect.midX - panelSize.width / 2,
            y: selectionScreenRect.minY - panelSize.height - 6
        ))
        selectionFormattingPanel = panel
        hostWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        hostWindow.makeFirstResponder(self)
    }

    private func dismissSelectionFormattingPanel() {
        guard let panel = selectionFormattingPanel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        selectionFormattingPanel = nil
    }

    func fileAttachmentReference(at event: NSEvent) -> MarkdownAttachmentReference? {
        guard let characterIndex = characterIndex(at: event) else { return nil }
        return fileAttachmentReference(atCharacterIndex: characterIndex)
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

enum MarkdownRichTextCodec {
    private static let tablePlaceholder = "\u{200B}"

    private struct ParsedMarkdownTable {
        let rows: [[String]]
        let consumedLineCount: Int
    }

    @MainActor
    static func render(markdown: String, theme: MarkdownEditorTheme, baseURL: URL? = nil) -> NSMutableAttributedString {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let output = NSMutableAttributedString()

        var lineIndex = 0
        while lineIndex < lines.count {
            if let table = parsedMarkdownTable(in: lines, startingAt: lineIndex) {
                let nextLineIndex = lineIndex + table.consumedLineCount
                output.append(renderTable(
                    rows: table.rows,
                    representsFollowingMarkdownLine: nextLineIndex < lines.count,
                    theme: theme,
                    baseURL: baseURL
                ))
                lineIndex = nextLineIndex
                continue
            }

            output.append(renderLine(lines[lineIndex], theme: theme, baseURL: baseURL))
            if lineIndex < lines.count - 1 {
                output.append(NSAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph)))
            }
            lineIndex += 1
        }

        return output
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

            let paragraphRange = nsString.paragraphRange(for: NSRange(location: location, length: 0))
            let hasTrailingNewline = nsString.substring(with: paragraphRange).hasSuffix("\n")
            let lineRange = NSRange(
                location: paragraphRange.location,
                length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0)
            )
            let lineText = nsString.substring(with: lineRange)
            lines.append(serializeLine(
                range: lineRange,
                visibleText: lineText,
                in: attributedString,
                theme: theme,
                context: context
            ))
            location = NSMaxRange(paragraphRange)
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
                    .qmTableColumnCount: columnCount
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

        var rows = [header]
        var nextIndex = index + 2
        while nextIndex < lines.count,
              let row = markdownTableCells(in: lines[nextIndex]),
              row.count == header.count,
              !row.allSatisfy(isMarkdownTableSeparatorCell) {
            rows.append(row)
            nextIndex += 1
        }
        return ParsedMarkdownTable(rows: rows, consumedLineCount: nextIndex - index)
    }

    private static func markdownTableCells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return nil }
        let cells = trimmed
            .split(separator: "|", omittingEmptySubsequences: false)
            .dropFirst()
            .dropLast()
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isMarkdownTableSeparatorCell(_ cell: String) -> Bool {
        let stripped = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return stripped.count >= 3 && stripped.allSatisfy { $0 == "-" }
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
                markdownLines.append("| " + Array(repeating: "---", count: columnCount).joined(separator: " | ") + " |")
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
               let closeParen = source[closeBracket.upperBound...].firstIndex(of: ")") {
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
               let closeParen = source[closeBracket.upperBound...].firstIndex(of: ")") {
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
        return output
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
              let image = NSImage(contentsOf: imageURL),
              image.size.width > 0,
              image.size.height > 0
        else {
            return nil
        }

        let maxSize = NSSize(width: 420, height: 240)
        let scale = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
        let displaySize = NSSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )

        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = NSRect(x: 0, y: -4, width: displaySize.width, height: displaySize.height)

        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.addAttributes(baseAttributes.merging([
            .qmImageMarkdown: markdown,
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
