import AppKit

extension EditorWindowController {

    // MARK: - Paragraph kind

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
        userDidEdit()
    }

    func convertCurrentLineToParagraph() {
        guard let storage = editorTextView.textStorage else { return }
        let lineRange = visibleLineRangeForSelection()
        let replacement = MarkdownRichTextCodec.renderLine("", theme: theme)

        suppressTextDidChange = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        userDidEdit()
    }

    func insertStructuredLine(kind: MarkdownParagraphKind, inlineMarkdown: String) {
        guard let storage = editorTextView.textStorage else { return }
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

        suppressTextDidChange = true
        storage.replaceCharacters(in: visibleRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: min(visibleRange.location + replacement.length, storage.length), length: 0))
        userDidEdit()
        return true
    }

    // MARK: - Inline font traits

    func toggleInlineFontTrait(_ trait: NSFontTraitMask) {
        let selection = editorTextView.selectedRange()

        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            typing[.font] = toggledFont(from: currentFont, trait: trait)
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
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

    private func applyAttribute(_ attributes: [NSAttributedString.Key: Any], removing keys: [NSAttributedString.Key] = []) {
        let selection = editorTextView.selectedRange()
        guard selection.length > 0, let storage = editorTextView.textStorage else { return }
        suppressTextDidChange = true
        storage.beginEditing()
        keys.forEach { storage.removeAttribute($0, range: selection) }
        storage.addAttributes(attributes, range: selection)
        storage.endEditing()
        suppressTextDidChange = false
        userDidEdit()
    }

    private func toggleIntAttribute(_ key: NSAttributedString.Key, enabledValue: Int) {
        let selection = editorTextView.selectedRange()

        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let enabled = (typing[key] as? Int) == enabledValue
            if enabled { typing.removeValue(forKey: key) } else { typing[key] = enabledValue }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let enabled = (storage.attribute(key, at: selection.location, effectiveRange: nil) as? Int) == enabledValue

        if enabled { applyAttribute([:], removing: [key]) } else { applyAttribute([key: enabledValue]) }
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
        setToolbarActionState(.italic, active: traits.contains(.italicFontMask))
        setToolbarActionState(.underline, active: ((attributes[.underlineStyle] as? Int) ?? 0) != 0)
        setToolbarActionState(.strikethrough, active: ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0)
        setToolbarActionState(.bulletList, active: { if case .bullet = paragraphKind { return true }; return false }())
        setToolbarActionState(.orderedList, active: { if case .ordered = paragraphKind { return true }; return false }())
        setToolbarActionState(.checklist, active: { if case .checklist = paragraphKind { return true }; return false }())
    }

    func setToolbarActionState(_ action: ToolbarAction, active: Bool) {
        toolbarButtonsByAction[action]?.isActive = active
        quickCaptureButtonsByAction[action]?.isActive = active
    }

    // MARK: - Keyboard shortcuts

    func handleEditorShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch (modifiers, keyCode) {
        case ([.command], 11): toggleInlineFontTrait(.boldFontMask); return true // b
        case ([.command], 34): toggleInlineFontTrait(.italicFontMask); return true // i
        case ([.command, .option], 18): toggleParagraphKind(.heading(level: 1)); return true // 1
        case ([.command, .shift], 26): toggleParagraphKind(.ordered(index: 1)); return true // 7
        case ([.command, .shift], 28): toggleParagraphKind(.bullet); return true // 8
        case ([.command, .shift], 25): toggleParagraphKind(.checklist(checked: false)); return true // 9
        default: return false
        }
    }

    // MARK: - Button actions

    @objc func toolbarButtonPressed(_ sender: NSButton) {
        guard let action = ToolbarAction(rawValue: sender.tag) else { return }
        switch action {
        case .heading: toggleParagraphKind(.heading(level: 1))
        case .bold: toggleInlineFontTrait(.boldFontMask)
        case .italic: toggleInlineFontTrait(.italicFontMask)
        case .strikethrough: applyStrikethrough()
        case .underline: applyUnderline()
        case .checklist: toggleParagraphKind(.checklist(checked: false))
        case .orderedList: toggleParagraphKind(.ordered(index: 1))
        case .bulletList: toggleParagraphKind(.bullet)
        }
    }

    @objc func quickCaptureActionPressed(_ sender: NSButton) {
        guard let action = QuickCaptureAction(rawValue: sender.tag) else { return }
        switch action {
        case .tag:
            showQuickCaptureTagMenu(from: sender)
        case .checklist:
            window?.makeFirstResponder(editorTextView)
            toggleParagraphKind(.checklist(checked: false))
        case .orderedList:
            window?.makeFirstResponder(editorTextView)
            toggleParagraphKind(.ordered(index: 1))
        case .bulletList:
            window?.makeFirstResponder(editorTextView)
            toggleParagraphKind(.bullet)
        }
    }

    // MARK: - Helpers

    private func sameParagraphCategory(_ lhs: MarkdownParagraphKind, _ rhs: MarkdownParagraphKind) -> Bool {
        switch (lhs, rhs) {
        case (.heading, .heading), (.bullet, .bullet), (.ordered, .ordered), (.checklist, .checklist), (.paragraph, .paragraph):
            return true
        default:
            return false
        }
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
}
