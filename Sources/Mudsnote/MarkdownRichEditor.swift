import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore

private final class MetadataTagButton: NSButton {
    private let tagName: String
    private let onRemove: ((String) -> Void)?

    init(tag: String, onRemove: ((String) -> Void)?) {
        self.tagName = tag
        self.onRemove = onRemove
        super.init(frame: .zero)
        title = "#\(tag)"
        font = .systemFont(ofSize: 11, weight: .regular)
        bezelStyle = .shadowlessSquare
        isBordered = false
        contentTintColor = .secondaryLabelColor
        target = self
        action = #selector(showTagActions)
        isEnabled = onRemove != nil
        setAccessibilityLabel("标签 #\(tag)")
        toolTip = "管理标签 #\(tag)"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func showTagActions() {
        guard onRemove != nil else { return }
        let menu = NSMenu()
        let remove = NSMenuItem(title: "移除标签 #\(tagName)", action: #selector(removeTag), keyEquivalent: "")
        remove.target = self
        menu.addItem(remove)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.maxY + 2), in: self)
    }

    @objc private func removeTag() {
        onRemove?(tagName)
    }
}

private final class InlineMetadataTagComboBox: NSComboBox {
    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var hasFinished = false

    @objc private func commitValue() {
        guard !hasFinished else { return }
        hasFinished = true
        onCommit?(stringValue)
    }

    override func textDidEndEditing(_ notification: Notification) {
        let movement = notification.userInfo?["NSTextMovement"] as? Int
        if movement == NSReturnTextMovement || movement == NSTabTextMovement || movement == NSBacktabTextMovement {
            commitValue()
        } else if !hasFinished {
            hasFinished = true
            onCancel?()
        }
        super.textDidEndEditing(notification)
    }

    override func cancelOperation(_ sender: Any?) {
        guard !hasFinished else { return }
        hasFinished = true
        onCancel?()
    }

    func configureCommitAction() {
        target = self
        action = #selector(commitValue)
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
    var minimumScrollableContentHeight: CGFloat = 0
    var onAddMetadataTag: (() -> Void)?
    @objc private func addMetadataTagPressed() { onAddMetadataTag?() }
    private var isAddingMetadataTag = false
    private var metadataTags: [String] = []
    private var metadataTagScrollView: NSScrollView?
    private weak var metadataTagStack: NSStackView?
    private var metadataTagAddButton: NSButton?
    private weak var metadataTagInput: InlineMetadataTagComboBox?

    func replaceAllContent(with attributedString: NSAttributedString) {
        textStorage?.setAttributedString(attributedString)
        metadataTags = []
        isAddingMetadataTag = false
        metadataTagScrollView?.removeFromSuperview()
        metadataTagScrollView = nil
        metadataTagStack = nil
        metadataTagAddButton = nil
        metadataTagInput = nil

        // This view is transparent. TextKit can invalidate only the new glyph
        // range after a shorter replacement, leaving pixels from the previous
        // document visible below it until another window redraw occurs.
        setNeedsDisplay(bounds)
        if let clipView = enclosingScrollView?.contentView {
            clipView.setNeedsDisplay(clipView.bounds)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        var constrainedSize = newSize
        constrainedSize.height = max(constrainedSize.height, minimumScrollableContentHeight)
        super.setFrameSize(constrainedSize)
        layoutMetadataTagBar()
    }

    func setMetadataTags(_ tags: [String], onRemove: ((String) -> Void)? = nil) {
        let normalized = MarkdownEditorDocument.normalizedTags(tags)
        guard normalized != metadataTags || metadataTagScrollView == nil || (normalized.isEmpty && !isAddingMetadataTag) else {
            updateMetadataTagSpacing(hasTags: !normalized.isEmpty || isAddingMetadataTag)
            layoutMetadataTagBar()
            return
        }
        metadataTags = normalized
        metadataTagScrollView?.removeFromSuperview()
        metadataTagScrollView = nil
        metadataTagStack = nil
        metadataTagAddButton = nil
        metadataTagInput = nil
        updateMetadataTagSpacing(hasTags: !normalized.isEmpty || isAddingMetadataTag)
        guard !normalized.isEmpty || isAddingMetadataTag else { return }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        for tag in normalized {
            let button = MetadataTagButton(tag: tag, onRemove: onRemove)
            stack.addArrangedSubview(button)
        }
        if onAddMetadataTag != nil {
            let addButton = NSButton(title: "+", target: self, action: #selector(addMetadataTagPressed))
            addButton.bezelStyle = .shadowlessSquare
            addButton.isBordered = false
            addButton.contentTintColor = .secondaryLabelColor
            addButton.font = .systemFont(ofSize: 12)
            addButton.identifier = NSUserInterfaceItemIdentifier("AddNoteTagButton")
            addButton.toolTip = "添加标签"
            addButton.setAccessibilityLabel("添加标签")
            stack.addArrangedSubview(addButton)
            metadataTagAddButton = addButton
        }
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: stack.fittingSize.width,
            height: 26
        )

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.documentView = stack
        addSubview(scroll)
        metadataTagScrollView = scroll
        metadataTagStack = stack
        layoutMetadataTagBar()
    }

    func beginAddingMetadataTag(suggestions: [String], onCommit: @escaping (String) -> Void) {
        if let input = metadataTagInput {
            window?.makeFirstResponder(input)
            return
        }
        if metadataTagStack == nil {
            isAddingMetadataTag = true
            setMetadataTags(metadataTags)
        }
        guard let stack = metadataTagStack, let addButton = metadataTagAddButton else { return }

        stack.removeArrangedSubview(addButton)
        addButton.removeFromSuperview()
        let input = InlineMetadataTagComboBox()
        input.identifier = NSUserInterfaceItemIdentifier("InlineNoteTagInput")
        input.placeholderString = "标签名称"
        input.setAccessibilityLabel("标签名称")
        input.completes = true
        input.addItems(withObjectValues: suggestions.filter { suggestion in
            !metadataTags.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
        })
        input.translatesAutoresizingMaskIntoConstraints = false
        input.widthAnchor.constraint(equalToConstant: 160).isActive = true
        input.heightAnchor.constraint(equalToConstant: 24).isActive = true
        input.onCommit = { [weak self] value in
            self?.finishAddingMetadataTag()
            onCommit(value)
        }
        input.onCancel = { [weak self] in self?.finishAddingMetadataTag() }
        input.configureCommitAction()
        stack.addArrangedSubview(input)
        metadataTagInput = input
        resizeMetadataTagStack()
        window?.makeFirstResponder(input)
        input.currentEditor()?.selectAll(nil)
        if let scroll = metadataTagScrollView {
            scrollToVisible(scroll.frame)
        }
        metadataTagScrollView?.contentView.scrollToVisible(input.frame)
    }

    private func finishAddingMetadataTag() {
        guard let stack = metadataTagStack, let input = metadataTagInput else { return }
        stack.removeArrangedSubview(input)
        input.removeFromSuperview()
        metadataTagInput = nil
        if let addButton = metadataTagAddButton {
            stack.addArrangedSubview(addButton)
        }
        resizeMetadataTagStack()
        isAddingMetadataTag = false
        if metadataTags.isEmpty { setMetadataTags([]) }
        window?.makeFirstResponder(self)
    }

    private func resizeMetadataTagStack() {
        guard let stack = metadataTagStack else { return }
        stack.frame.size = NSSize(width: stack.fittingSize.width, height: 26)
        metadataTagScrollView?.documentView = stack
        layoutMetadataTagBar()
    }

    private func updateMetadataTagSpacing(hasTags: Bool) {
        guard let storage = textStorage, storage.length > 0 else { return }
        let paragraphRange = (storage.string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        let existingReserve = storage.attribute(
            .qmMetadataTagReserve,
            at: 0,
            effectiveRange: nil
        ) as? CGFloat ?? 0
        let reserve: CGFloat = hasTags ? 36 : 0
        // Typing in the body must not invalidate the title's layout or caret.
        let currentStyle = storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        if existingReserve == reserve, (currentStyle?.paragraphSpacing ?? 0) >= reserve { return }
        let style = (storage.attribute(
            .paragraphStyle,
            at: 0,
            effectiveRange: nil
        ) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            ?? NSMutableParagraphStyle()
        style.paragraphSpacing = max(0, style.paragraphSpacing - existingReserve) + reserve
        storage.addAttributes([
            .paragraphStyle: style,
            .qmMetadataTagReserve: reserve,
        ], range: paragraphRange)
    }

    private func layoutMetadataTagBar() {
        guard let scroll = metadataTagScrollView,
              let layoutManager,
              let textContainer,
              let storage = textStorage,
              storage.length > 0 else { return }
        let paragraphRange = (storage.string as NSString).paragraphRange(
            for: NSRange(location: 0, length: 0)
        )
        layoutManager.ensureLayout(forCharacterRange: paragraphRange)
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: paragraphRange,
            actualCharacterRange: nil
        )
        let titleRect = layoutManager.boundingRect(
            forGlyphRange: glyphRange,
            in: textContainer
        )
        scroll.frame = NSRect(
            x: textContainerInset.width,
            y: textContainerInset.height + titleRect.maxY + 5,
            width: max(0, bounds.width - textContainerInset.width * 2),
            height: 26
        )
    }

    override func selectionRange(forProposedRange proposedCharRange: NSRange, granularity: NSSelectionGranularity) -> NSRange {
        let resolved = super.selectionRange(forProposedRange: proposedCharRange, granularity: granularity)
        guard granularity == .selectByWord else { return resolved }
        return wordSelection(forProposedRange: proposedCharRange, appKitSelection: resolved)
    }

    private func wordSelection(forProposedRange proposedCharRange: NSRange, appKitSelection: NSRange) -> NSRange {
        let trimmed = trimSelectionToWordBounds(appKitSelection)
        if trimmed.length > 0 { return trimmed }
        // AppKit returned a whitespace-only range (e.g. clicking on a newline
        // or blank line). Snap to the word immediately to the left of the
        // click point so the highlight stays on the word and does not extend
        // into blank lines or trailing whitespace.
        let snapped = wordLeftOf(proposedCharRange.location)
        if snapped.length > 0 { return trimSelectionToWordBounds(snapped) }
        return appKitSelection
    }

    private func trimSelectionToWordBounds(_ range: NSRange) -> NSRange {
        let string = self.string as NSString
        guard range.length > 0, string.length > 0 else { return range }
        let start = max(range.location, 0)
        var end = min(NSMaxRange(range), string.length)
        guard start < end else { return range }
        // Trim trailing spaces, tabs, hard newlines, and line separators so
        // double-click selection does not extend onto blank lines or trailing
        // whitespace. When the selection is entirely boundary whitespace we
        // return a zero-length range so the caller can detect the all-
        // whitespace case and snap to the enclosing word.
        while end > start, Self.isWordBoundaryWhitespace(character: string.character(at: end - 1)) {
            end -= 1
        }
        guard end > start else { return NSRange(location: start, length: 0) }
        return NSRange(location: start, length: end - start)
    }

    private func wordLeftOf(_ index: Int) -> NSRange {
        let string = self.string as NSString
        let length = string.length
        guard length > 0, index > 0 else { return NSRange(location: 0, length: 0) }
        var pos = max(0, min(index, length))
        // Walk left over boundary whitespace and newlines so the snap works
        // when the click sits on a blank line past the previous word.
        while pos > 0, Self.isWordBoundaryWhitespace(character: string.character(at: pos - 1)) {
            pos -= 1
        }
        guard pos > 0, Self.isWordCharacter(character: string.character(at: pos - 1)) else {
            return NSRange(location: 0, length: 0)
        }
        var wordStart = pos
        while wordStart > 0, Self.isWordCharacter(character: string.character(at: wordStart - 1)) {
            wordStart -= 1
        }
        var wordEnd = wordStart
        while wordEnd < length, Self.isWordCharacter(character: string.character(at: wordEnd)) {
            wordEnd += 1
        }
        return NSRange(location: wordStart, length: wordEnd - wordStart)
    }

    private static func isWordBoundaryWhitespace(character: unichar) -> Bool {
        switch character {
        case 0x20, 0x09, 0x0A, 0x0D, 0x2028, 0x2029:
            return true
        default:
            return false
        }
    }

    private static func isWordCharacter(character: unichar) -> Bool {
        // ASCII letter, digit, underscore.
        if character >= 0x41 && character <= 0x5A { return true }   // A-Z
        if character >= 0x61 && character <= 0x7A { return true }   // a-z
        if character >= 0x30 && character <= 0x39 { return true }   // 0-9
        if character == 0x5F { return true }                       // _
        // CJK Unified Ideographs (covers Chinese / Japanese kanji).
        if character >= 0x4E00 && character <= 0x9FFF { return true }
        // Hiragana and Katakana.
        if character >= 0x3040 && character <= 0x30FF { return true }
        // CJK Extension A.
        if character >= 0x3400 && character <= 0x4DBF { return true }
        return false
    }

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
    var pasteboardForPaste: () -> NSPasteboard = { .general }
    var markdownPasteTheme: MarkdownEditorTheme?
    private var isInterpretingShiftReturn = false

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
        updateMetadataTagSpacing(hasTags: !metadataTags.isEmpty || isAddingMetadataTag)
        layoutMetadataTagBar()
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
        if isShiftReturnKey(event) {
            // Keep the complete chord inside AppKit's text-input path. If we
            // insert directly and return here, the IME sees only the later
            // Shift-up event and may interpret it as a Chinese/English toggle.
            if hasMarkedText() {
                unmarkText()
            }
            isInterpretingShiftReturn = true
            defer { isInterpretingShiftReturn = false }
            super.keyDown(with: event)
            return
        }
        if commandDelegate?.markdownTextView(self, handleKeyDown: event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if isInterpretingShiftReturn,
           selector == #selector(insertNewline(_:)) {
            insertSoftLineBreak()
            return
        }
        super.doCommand(by: selector)
    }

    private func isShiftReturnKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return [UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter)].contains(event.keyCode)
            && modifiers == [.shift]
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
        // Never insert directly while an IME composition is in progress; let
        // the input context finish committing the marked text first. This
        // avoids corrupting the IME state machine (some input methods
        // interpret a direct insert during composition as a Chinese/English
        // toggle).
        if hasMarkedText() { return }
        // The first line is the note title and renders with the heading (title)
        // format. A soft line break inside it would carry the heading format
        // onto the next visual line. The title format should only apply to the
        // first line, so break out of the heading into a fresh body paragraph
        // instead.
        if isFirstLineHeadingParagraph() {
            commandDelegate?.markdownTextViewInsertNewline(self)
            return
        }
        insertText("\u{2028}", replacementRange: selectedRange())
    }

    private func isFirstLineHeadingParagraph() -> Bool {
        guard let storage = textStorage else { return false }
        let string = storage.string as NSString
        guard string.length > 0 else { return false }
        let selection = selectedRange()
        let caret = min(max(selection.location, 0), string.length)
        let paragraphLocation = caret == string.length
            && caret > 0
            && !string.hasSuffix("\n")
            ? caret - 1
            : caret
        let paragraphRange = string.paragraphRange(
            for: NSRange(location: paragraphLocation, length: 0)
        )
        guard paragraphRange.location == 0 else { return false }
        let kind = MarkdownRichTextCodec.paragraphKind(at: paragraphRange, in: storage)
        if case .heading = kind { return true }
        return false
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
           (window == nil || window?.firstResponder === self),
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

        let refreshesAutomaticLinks = Self.insertedTextCompletesAutomaticLinkToken(string)
        super.insertText(string, replacementRange: replacementRange)
        if refreshesAutomaticLinks,
           let textStorage,
           let theme = markdownPasteTheme {
            MarkdownRichTextCodec.refreshAutomaticLinks(
                in: textStorage,
                around: selectedRange().location,
                theme: theme
            )
        }
        onTextInputStateChanged?()
    }

    private static func insertedTextCompletesAutomaticLinkToken(_ value: Any) -> Bool {
        guard let text = value as? String else { return true }
        if text.utf16.count != 1 {
            return true
        }
        return text.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0)
        }
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

    override func deleteBackward(_ sender: Any?) {
        let removedSelection = selectedRange().length > 0
        super.deleteBackward(sender)
        if removedSelection {
            resetInlineTypingAttributesAfterSelectionDeletion()
        }
    }

    override func deleteForward(_ sender: Any?) {
        let removedSelection = selectedRange().length > 0
        super.deleteForward(sender)
        if removedSelection {
            resetInlineTypingAttributesAfterSelectionDeletion()
        }
    }

    @discardableResult
    func pasteContents(from pasteboard: NSPasteboard) -> Bool {
        if commandDelegate?.markdownTextView(self, pasteAttachmentsFrom: pasteboard) == true {
            return true
        }
        if let markdownPasteTheme,
           let importedMarkdown = MarkdownRichPasteNormalizer.markdown(from: pasteboard, theme: markdownPasteTheme) {
            let markdown = importedMarkdown.contains("\n")
                ? markdownWithInsertionBoundaries(importedMarkdown)
                : importedMarkdown
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

    private func resetInlineTypingAttributesAfterSelectionDeletion() {
        guard let theme = markdownPasteTheme else { return }
        var attributes = typingAttributes
        let paragraphKind = MarkdownParagraphKind.decode(attributes[.qmParagraphKind]) ?? .paragraph
        let paragraphAttributes = theme.baseAttributes(for: paragraphKind)
        attributes[.font] = paragraphAttributes[.font]
        attributes[.foregroundColor] = paragraphAttributes[.foregroundColor]
        attributes[.paragraphStyle] = paragraphAttributes[.paragraphStyle]
        [
            .obliqueness,
            .underlineStyle,
            .underlineColor,
            .strikethroughStyle,
            .strikethroughColor,
            .backgroundColor,
            .qmHighlight,
            .qmCode,
            .qmLinkURL,
            .qmAutomaticLink
        ].forEach { attributes.removeValue(forKey: $0) }
        typingAttributes = attributes
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

    func conciseEditingMenu(from _: NSMenu) -> NSMenu {
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
        if selectionAfterMouseDown.length == 0,
           selectionAfterMouseDown != selectionBeforeMouseDown,
           window?.firstResponder === self {
            // Resume AppKit's single blink cycle at the new insertion point,
            // instead of inheriting the previous position's almost-expired phase.
            updateInsertionPointStateAndRestartTimer(true)
        }
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

    func dismissSelectionFormattingPanel() {
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
