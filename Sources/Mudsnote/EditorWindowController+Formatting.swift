import AppKit
import Carbon.HIToolbox

private struct FormattingUndoSnapshot {
    let content: NSAttributedString
    let selection: NSRange
}

extension EditorWindowController {

    func makeSelectionFormattingMenu() -> NSMenu? {
        guard editorTextView.selectedRange().length > 0 else { return nil }
        let menu = NSMenu(title: "快捷格式")
        let enabled = noteStore.enabledSelectionToolbarOptions
        let items: [(SelectionToolbarOption, String, String, ToolbarAction)] = [
            (.bold, "加粗", "bold", .bold),
            (.italic, "斜体", "italic", .italic),
            (.underline, "下划线", "underline", .underline),
            (.strikethrough, "删除线", "strikethrough", .strikethrough),
            (.highlight, "高亮", "highlighter", .highlight),
            (.checklist, "待办列表", "checkmark.square", .checklist),
            (.bulletList, "项目符号列表", "list.bullet", .bulletList),
            (.orderedList, "编号列表", "list.number", .orderedList)
        ]
        for (option, title, symbolName, action) in items where enabled.contains(option) {
            let item = NSMenuItem(
                title: title,
                action: #selector(selectionFormattingMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = action.rawValue
            item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            menu.addItem(item)
        }
        return menu
    }

    // MARK: - Paragraph kind

    func demoteAutomaticTitleFormattingIfNeeded() -> Bool {
        guard isFloatingNoteMode,
              hasAutomaticTitleFormatting,
              let storage = editorTextView.textStorage,
              storage.length > 0 else {
            return false
        }

        let lineRange = visibleLineRangeForSelection()
        guard lineRange.location == 0 else { return false }
        let kind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        guard case .heading = kind else {
            hasAutomaticTitleFormatting = false
            return false
        }

        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: kind)
        let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
            range: contentRange,
            in: storage,
            paragraphKind: kind,
            theme: theme
        )
        let replacement = MarkdownRichTextCodec.renderLine(inlineMarkdown, theme: theme)
        let selectionOffset = max(editorTextView.selectedRange().location - contentRange.location, 0)

        suppressTextDidChange = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(
            location: min(lineRange.location + selectionOffset, storage.length),
            length: 0
        ))
        hasAutomaticTitleFormatting = false
        updateTypingAttributesFromInsertionPoint()
        userDidEdit()
        return true
    }

    func handleStructuredNewline() -> Bool {
        guard let storage = editorTextView.textStorage else { return false }

        let lineRange = visibleLineRangeForSelection()
        let kind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: kind)
        let content = (storage.string as NSString).substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .paragraph:
            return false
        case .heading:
            insertStructuredLine(kind: .paragraph, inlineMarkdown: "")
            return true
        case .bullet, .ordered, .checklist:
            if content.isEmpty {
                convertCurrentLineToParagraph()
            } else {
                let nextKind: MarkdownParagraphKind
                switch kind {
                case .ordered(let index): nextKind = .ordered(index: index + 1)
                case .checklist: nextKind = .checklist(checked: false)
                default: nextKind = kind
                }
                insertStructuredLine(kind: nextKind, inlineMarkdown: "")
            }
            return true
        }
    }

    func toggleParagraphKind(_ target: MarkdownParagraphKind) {
        guard let storage = editorTextView.textStorage else { return }
        if case .heading = target {
            hasAutomaticTitleFormatting = false
        }

        let undoSnapshot = formattingUndoSnapshot()
        let ranges = selectedLineRanges()
        var renderedLines: [NSAttributedString] = []
        let currentKinds = ranges.map { MarkdownRichTextCodec.paragraphKind(at: $0, in: storage) }
        let shouldResetToParagraph = currentKinds.allSatisfy { sameParagraphCategory($0, target) }

        for (index, lineRange) in ranges.enumerated() {
            let currentKind = currentKinds[index]
            let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: currentKind)
            let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(range: contentRange, in: storage, paragraphKind: currentKind, theme: theme)
            let nextKind: MarkdownParagraphKind

            if shouldResetToParagraph {
                nextKind = .paragraph
            } else {
                switch target {
                case .ordered: nextKind = .ordered(index: index + 1)
                default: nextKind = target
                }
            }

            let lineMarkdown = MarkdownRichTextCodec.markdownLine(for: nextKind, inlineContent: inlineMarkdown)
            renderedLines.append(MarkdownRichTextCodec.renderLine(lineMarkdown, theme: theme))
        }

        let replacement = joinRenderedLines(renderedLines)
        let fullRange = combinedRange(of: ranges)
        let selectionLocation = fullRange.location + replacement.length

        suppressTextDidChange = true
        storage.replaceCharacters(in: fullRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: target.undoActionName)
        userDidEdit()
    }

    func convertCurrentLineToParagraph() {
        guard let storage = editorTextView.textStorage else { return }
        let undoSnapshot = formattingUndoSnapshot()
        let lineRange = visibleLineRangeForSelection()
        let replacement = MarkdownRichTextCodec.renderLine("", theme: theme)

        suppressTextDidChange = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: "段落")
        userDidEdit()
    }

    func insertStructuredLine(kind: MarkdownParagraphKind, inlineMarkdown: String) {
        guard let storage = editorTextView.textStorage else { return }
        let undoSnapshot = formattingUndoSnapshot()
        let selection = editorTextView.selectedRange()
        let markdownLine = MarkdownRichTextCodec.markdownLine(for: kind, inlineContent: inlineMarkdown)
        let renderedLine = MarkdownRichTextCodec.renderLine(markdownLine, theme: theme)
        let replacement = NSMutableAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph))
        replacement.append(renderedLine)

        suppressTextDidChange = true
        storage.replaceCharacters(in: selection, with: replacement)
        suppressTextDidChange = false

        let cursorLocation = selection.location + 1 + kind.prefixLength
        editorTextView.setSelectedRange(NSRange(location: cursorLocation, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: kind.undoActionName)
        userDidEdit()
    }

    func toggleChecklistIfNeeded(atCharacterIndex index: Int) -> Bool {
        guard let storage = editorTextView.textStorage, storage.length > 0 else { return false }

        let safeIndex = min(max(index, 0), max(storage.length - 1, 0))
        let string = storage.string as NSString
        let paragraphRange = string.paragraphRange(for: NSRange(location: safeIndex, length: 0))
        let visibleRange = NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (string.substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0), 0))
        let kind = MarkdownRichTextCodec.paragraphKind(at: visibleRange, in: storage)

        guard case .checklist(let checked) = kind else { return false }
        let prefixRange = NSRange(location: visibleRange.location, length: min(kind.prefixLength, visibleRange.length))
        guard NSLocationInRange(safeIndex, prefixRange) else { return false }

        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: visibleRange, in: storage, kind: kind)
        let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(range: contentRange, in: storage, paragraphKind: kind, theme: theme)
        let replacement = MarkdownRichTextCodec.renderLine(
            MarkdownRichTextCodec.markdownLine(for: .checklist(checked: !checked), inlineContent: inlineMarkdown),
            theme: theme
        )

        let undoSnapshot = formattingUndoSnapshot()
        suppressTextDidChange = true
        storage.replaceCharacters(in: visibleRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: min(visibleRange.location + replacement.length, storage.length), length: 0))
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: "待办列表")
        userDidEdit()
        return true
    }

    // MARK: - Inline font traits

    func applyLinkURL(_ url: String?, label: String? = nil, to reference: MarkdownLinkReference) {
        guard let storage = editorTextView.textStorage,
              reference.range.location >= 0,
              NSMaxRange(reference.range) <= storage.length,
              storage.attribute(.qmLinkURL, at: reference.range.location, effectiveRange: nil) != nil else {
            return
        }

        let undoSnapshot = formattingUndoSnapshot()
        suppressTextDidChange = true
        storage.beginEditing()
        if let url {
            if let label {
                storage.replaceCharacters(in: reference.range, with: label)
            }
            let updatedRange = NSRange(location: reference.range.location, length: (label ?? reference.label).utf16.count)
            storage.removeAttribute(.qmAutomaticLink, range: updatedRange)
            storage.addAttribute(.qmLinkURL, value: url, range: updatedRange)
            storage.addAttribute(.foregroundColor, value: theme.accentColor, range: updatedRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: updatedRange)
        } else {
            storage.removeAttribute(.qmAutomaticLink, range: reference.range)
            storage.removeAttribute(.qmLinkURL, range: reference.range)
            storage.removeAttribute(.underlineStyle, range: reference.range)
            storage.addAttribute(.foregroundColor, value: theme.textColor, range: reference.range)
        }
        storage.endEditing()
        suppressTextDidChange = false

        let selectedLength = url == nil ? reference.range.length : (label ?? reference.label).utf16.count
        editorTextView.setSelectedRange(NSRange(location: reference.range.location, length: selectedLength))
        updateTypingAttributesFromInsertionPoint()
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: url == nil ? "移除链接" : "编辑链接")
        userDidEdit()
    }

    func toggleInlineFontTrait(_ trait: NSFontTraitMask) {
        if trait.contains(.italicFontMask) {
            toggleItalicFormatting()
            return
        }

        let selection = formattingSelection()

        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            typing[.font] = toggledFont(from: currentFont, trait: trait)
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let undoSnapshot = formattingUndoSnapshot()
        suppressTextDidChange = true
        storage.beginEditing()
        var location = selection.location

        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let font = (storage.attribute(.font, at: location, effectiveRange: &effectiveRange) as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            storage.addAttribute(.font, value: toggledFont(from: font, trait: trait), range: clippedRange)
            location = NSMaxRange(clippedRange)
        }

        storage.endEditing()
        suppressTextDidChange = false
        editorTextView.setSelectedRange(selection)
        rememberEditorSelectionForToolbarActions()
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: trait.undoActionName)
        userDidEdit()
    }

    private func toggleItalicFormatting() {
        let selection = formattingSelection()

        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            if isItalicActive(font: currentFont, obliqueness: typing[.obliqueness]) {
                typing[.font] = NSFontManager.shared.convert(currentFont, toNotHaveTrait: .italicFontMask)
                typing.removeValue(forKey: .obliqueness)
            } else {
                typing[.font] = NSFontManager.shared.convert(currentFont, toHaveTrait: .italicFontMask)
                typing[.obliqueness] = markdownItalicObliqueness
            }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let undoSnapshot = formattingUndoSnapshot()
        suppressTextDidChange = true
        storage.beginEditing()
        var location = selection.location

        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let attributes = storage.attributes(at: location, effectiveRange: &effectiveRange)
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)

            if isItalicActive(font: font, obliqueness: attributes[.obliqueness]) {
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toNotHaveTrait: .italicFontMask), range: clippedRange)
                storage.removeAttribute(.obliqueness, range: clippedRange)
            } else {
                storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask), range: clippedRange)
                storage.addAttribute(.obliqueness, value: markdownItalicObliqueness, range: clippedRange)
            }
            location = NSMaxRange(clippedRange)
        }

        storage.endEditing()
        suppressTextDidChange = false
        editorTextView.setSelectedRange(selection)
        rememberEditorSelectionForToolbarActions()
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: "斜体")
        userDidEdit()
    }

    private func toggledFont(from font: NSFont, trait: NSFontTraitMask) -> NSFont {
        let traits = NSFontManager.shared.traits(of: font)
        if traits.contains(trait) {
            return NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        }
        return NSFontManager.shared.convert(font, toHaveTrait: trait)
    }

    // MARK: - Strikethrough / underline

    func applyStrikethrough() {
        toggleIntAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue)
    }

    func applyUnderline() {
        toggleIntAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue)
    }

    func toggleHighlightFormatting() {
        let selection = formattingSelection()
        guard selection.length > 0, let storage = editorTextView.textStorage else { return }
        let isHighlighted = (storage.attribute(.qmHighlight, at: selection.location, effectiveRange: nil) as? Bool) == true
        if isHighlighted {
            applyAttribute([:], removing: [.qmHighlight, .backgroundColor], actionName: "高亮")
        } else {
            applyAttribute([
                .qmHighlight: true,
                .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.38)
            ], actionName: "高亮")
        }
    }

    private func applyAttribute(
        _ attributes: [NSAttributedString.Key: Any],
        removing keys: [NSAttributedString.Key] = [],
        actionName: String = "格式"
    ) {
        let selection = formattingSelection()
        guard selection.length > 0, let storage = editorTextView.textStorage else { return }
        let undoSnapshot = formattingUndoSnapshot()
        suppressTextDidChange = true
        storage.beginEditing()
        keys.forEach { storage.removeAttribute($0, range: selection) }
        storage.addAttributes(attributes, range: selection)
        storage.endEditing()
        suppressTextDidChange = false
        editorTextView.setSelectedRange(selection)
        rememberEditorSelectionForToolbarActions()
        registerFormattingUndoIfNeeded(before: undoSnapshot, actionName: actionName)
        userDidEdit()
    }

    private func toggleIntAttribute(_ key: NSAttributedString.Key, enabledValue: Int) {
        let selection = formattingSelection()

        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let enabled = (typing[key] as? Int) == enabledValue
            if enabled { typing.removeValue(forKey: key) } else { typing[key] = enabledValue }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let enabled = (storage.attribute(key, at: selection.location, effectiveRange: nil) as? Int) == enabledValue

        let actionName = key == .underlineStyle ? "下划线" : "删除线"
        if enabled {
            applyAttribute([:], removing: [key], actionName: actionName)
        } else {
            applyAttribute([key: enabledValue], actionName: actionName)
        }
    }

    // MARK: - Toolbar state

    func updateToolbarSelectionState() {
        guard let storage = editorTextView.textStorage else { return }

        let selection = editorTextView.selectedRange()
        let probeLocation = max(min(
            selection.location == storage.length ? max(storage.length - 1, 0) : selection.location,
            storage.length == 0 ? 0 : storage.length - 1
        ), 0)

        let paragraphKind: MarkdownParagraphKind = {
            if storage.length == 0 { return .paragraph }
            let lineRange = visibleLineRangeForSelection()
            return MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        }()

        let attributes: [NSAttributedString.Key: Any] = {
            if selection.length == 0 { return editorTextView.typingAttributes }
            guard storage.length > 0 else { return editorTextView.typingAttributes }
            return storage.attributes(at: probeLocation, effectiveRange: nil)
        }()

        let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
        let traits = NSFontManager.shared.traits(of: font)

        setToolbarActionState(.heading, active: { if case .heading = paragraphKind { return true }; return false }())
        setToolbarActionState(.bold, active: traits.contains(.boldFontMask))
        setToolbarActionState(.italic, active: isItalicActive(font: font, obliqueness: attributes[.obliqueness]))
        setToolbarActionState(.underline, active: ((attributes[.underlineStyle] as? Int) ?? 0) != 0)
        setToolbarActionState(.strikethrough, active: ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0)
        setToolbarActionState(.highlight, active: (attributes[.qmHighlight] as? Bool) == true)
        setToolbarActionState(.bulletList, active: { if case .bullet = paragraphKind { return true }; return false }())
        setToolbarActionState(.orderedList, active: { if case .ordered = paragraphKind { return true }; return false }())
        setToolbarActionState(.checklist, active: { if case .checklist = paragraphKind { return true }; return false }())
    }

    func setToolbarActionState(_ action: ToolbarAction, active: Bool) {
        toolbarButtonsByAction[action]?.isActive = active
    }

    func rememberEditorSelectionForToolbarActions() {
        let selection = editorTextView.selectedRange()
        guard selection.length > 0, let storage = editorTextView.textStorage else { return }
        guard NSMaxRange(selection) <= storage.length else { return }
        lastEditorSelectionForToolbarAction = selection
    }

    // MARK: - Keyboard shortcuts

    func handleEditorShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch (modifiers, keyCode) {
        case ([.command], UInt16(kVK_ANSI_B)): toggleInlineFontTrait(.boldFontMask); return true
        case ([.command], UInt16(kVK_ANSI_I)): toggleInlineFontTrait(.italicFontMask); return true
        case ([.command], UInt16(kVK_ANSI_U)): applyUnderline(); return true
        case ([.command, .shift], UInt16(kVK_ANSI_X)): applyStrikethrough(); return true
        case ([.command, .option], UInt16(kVK_ANSI_1)): toggleParagraphKind(.heading(level: 1)); return true
        case ([.command, .option], UInt16(kVK_ANSI_2)): toggleParagraphKind(.heading(level: 2)); return true
        case ([.command, .option], UInt16(kVK_ANSI_3)): toggleParagraphKind(.heading(level: 3)); return true
        case ([.command, .shift], UInt16(kVK_ANSI_7)): toggleParagraphKind(.ordered(index: 1)); return true
        case ([.command, .shift], UInt16(kVK_ANSI_8)): toggleParagraphKind(.bullet); return true
        case ([.command, .shift], UInt16(kVK_ANSI_9)): toggleParagraphKind(.checklist(checked: false)); return true
        default: return false
        }
    }

    // MARK: - Button actions

    @objc func toolbarButtonPressed(_ sender: NSButton) {
        guard let action = ToolbarAction(rawValue: sender.tag) else { return }
        performToolbarAction(action)
    }

    @objc private func selectionFormattingMenuItemPressed(_ sender: NSMenuItem) {
        guard let action = ToolbarAction(rawValue: sender.tag) else { return }
        performToolbarAction(action)
    }

    private func performToolbarAction(_ action: ToolbarAction) {
        focusEditorForToolbarAction()
        defer {
            rememberEditorSelectionForToolbarActions()
            activeToolbarActionSelection = nil
        }
        switch action {
        case .heading: toggleParagraphKind(.heading(level: 1))
        case .bold: toggleInlineFontTrait(.boldFontMask)
        case .italic: toggleInlineFontTrait(.italicFontMask)
        case .strikethrough: applyStrikethrough()
        case .underline: applyUnderline()
        case .highlight: toggleHighlightFormatting()
        case .checklist: toggleParagraphKind(.checklist(checked: false))
        case .orderedList: toggleParagraphKind(.ordered(index: 1))
        case .bulletList: toggleParagraphKind(.bullet)
        }
        updateToolbarSelectionState()
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
    }

    // MARK: - Helpers

    private func sameParagraphCategory(_ lhs: MarkdownParagraphKind, _ rhs: MarkdownParagraphKind) -> Bool {
        switch (lhs, rhs) {
        case (.heading(let lhsLevel), .heading(let rhsLevel)):
            return lhsLevel == rhsLevel
        case (.bullet, .bullet), (.ordered, .ordered), (.checklist, .checklist), (.paragraph, .paragraph):
            return true
        default:
            return false
        }
    }

    func focusEditorForToolbarAction() {
        let selection = toolbarActionSelection()
        activeToolbarActionSelection = selection
        window?.makeFirstResponder(editorTextView)

        if let storage = editorTextView.textStorage {
            let location = min(selection.location, storage.length)
            let length = min(selection.length, max(storage.length - location, 0))
            editorTextView.setSelectedRange(NSRange(location: location, length: length))
        }
    }

    private func formattingSelection() -> NSRange {
        guard
            let selection = activeToolbarActionSelection,
            let storage = editorTextView.textStorage,
            selection.length > 0,
            NSMaxRange(selection) <= storage.length
        else {
            return editorTextView.selectedRange()
        }

        editorTextView.setSelectedRange(selection)
        return selection
    }

    private func toolbarActionSelection() -> NSRange {
        let selection = editorTextView.selectedRange()
        if selection.length > 0 {
            return selection
        }

        guard
            let cached = lastEditorSelectionForToolbarAction,
            let storage = editorTextView.textStorage,
            cached.length > 0,
            NSMaxRange(cached) <= storage.length
        else {
            return selection
        }

        return cached
    }

    private func joinRenderedLines(_ lines: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph)))
            }
            result.append(line)
        }
        return result
    }

    private func combinedRange(of ranges: [NSRange]) -> NSRange {
        guard let first = ranges.first, let last = ranges.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    private func isItalicActive(font: NSFont, obliqueness: Any?) -> Bool {
        if NSFontManager.shared.traits(of: font).contains(.italicFontMask) {
            return true
        }
        if let number = obliqueness as? NSNumber {
            return abs(number.doubleValue) > 0.001
        }
        if let value = obliqueness as? CGFloat {
            return abs(value) > 0.001
        }
        if let value = obliqueness as? Double {
            return abs(value) > 0.001
        }
        return false
    }

    private func formattingUndoSnapshot() -> FormattingUndoSnapshot? {
        guard let storage = editorTextView.textStorage else { return nil }
        return FormattingUndoSnapshot(
            content: NSAttributedString(attributedString: storage),
            selection: editorTextView.selectedRange()
        )
    }

    private func registerFormattingUndoIfNeeded(before: FormattingUndoSnapshot?, actionName: String) {
        guard let before,
              let after = formattingUndoSnapshot(),
              !before.content.isEqual(to: after.content),
              let undoManager = editorTextView.undoManager else {
            return
        }

        undoManager.registerUndo(withTarget: self) { target in
            target.restoreFormattingSnapshot(before, inverseSnapshot: after, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func restoreFormattingSnapshot(
        _ snapshot: FormattingUndoSnapshot,
        inverseSnapshot: FormattingUndoSnapshot,
        actionName: String
    ) {
        editorTextView.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreFormattingSnapshot(inverseSnapshot, inverseSnapshot: snapshot, actionName: actionName)
        }
        editorTextView.undoManager?.setActionName(actionName)
        applyFormattingSnapshot(snapshot)
    }

    private func applyFormattingSnapshot(_ snapshot: FormattingUndoSnapshot) {
        guard let storage = editorTextView.textStorage else { return }

        suppressTextDidChange = true
        storage.setAttributedString(snapshot.content)
        suppressTextDidChange = false

        let location = min(snapshot.selection.location, storage.length)
        let length = min(snapshot.selection.length, max(storage.length - location, 0))
        editorTextView.setSelectedRange(NSRange(location: location, length: length))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        updateToolbarSelectionState()
        rememberEditorSelectionForToolbarActions()
        userDidEdit()
    }
}

private extension MarkdownParagraphKind {
    var undoActionName: String {
        switch self {
        case .paragraph: return "段落"
        case .heading: return "标题"
        case .bullet: return "项目符号列表"
        case .ordered: return "编号列表"
        case .checklist: return "待办列表"
        }
    }
}

private extension NSFontTraitMask {
    var undoActionName: String {
        if contains(.boldFontMask) { return "加粗" }
        if contains(.italicFontMask) { return "斜体" }
        return "格式"
    }
}
