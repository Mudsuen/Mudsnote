import AppKit
import Foundation

extension EditorWindowController {

    func userDidEdit() {
        guard !suppressTextDidChange else { return }
        interpretTypedMarkdownIfNeeded()
        updateTypingAttributesFromInsertionPoint()
        updateToolbarSelectionState()
        updateInlineSuggestions()
        refreshChrome()
        markDocumentDirty()
    }

    func interpretTypedMarkdownIfNeeded() {
        guard let storage = editorTextView.textStorage else { return }

        let currentLineRange = visibleLineRangeForSelection()
        let currentText = (storage.string as NSString).substring(with: currentLineRange)
        guard MarkdownRichTextCodec.shouldInterpretMarkdown(in: currentText) else { return }

        let selection = editorTextView.selectedRange()
        let selectionStartOffset = max(selection.location - currentLineRange.location, 0)
        let selectionEndOffset = max(NSMaxRange(selection) - currentLineRange.location, 0)
        let rendered = MarkdownRichTextCodec.renderLine(currentText, theme: theme)
        let clampedStart = min(selectionStartOffset, rendered.length)
        let clampedEnd = min(selectionEndOffset, rendered.length)
        let newSelection = NSRange(
            location: currentLineRange.location + clampedStart,
            length: max(clampedEnd - clampedStart, 0)
        )

        suppressTextDidChange = true
        storage.replaceCharacters(in: currentLineRange, with: rendered)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(newSelection)
    }

    func updateTypingAttributesFromInsertionPoint() {
        guard let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        let location = max(min(selection.location, storage.length), 0)

        if storage.length == 0 || location == 0 {
            editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
            return
        }

        let lineRange = visibleLineRangeForSelection()
        let paragraphKind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: paragraphKind)

        if location <= contentRange.location {
            editorTextView.typingAttributes = theme.baseAttributes(for: paragraphKind)
            return
        }

        let probeLocation = max(min(location - 1, storage.length - 1), contentRange.location)
        let attrs = storage.attributes(at: probeLocation, effectiveRange: nil)
        editorTextView.typingAttributes = attrs
    }

    func visibleLineRangeForSelection() -> NSRange {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let paragraphRange = string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: 0))
        return NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (string.substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0), 0))
    }

    func selectedLineRanges() -> [NSRange] {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let fullRange = string.lineRange(for: selection)
        var ranges: [NSRange] = []
        var location = fullRange.location

        while location < NSMaxRange(fullRange) {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
            let visibleRange = NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0))
            ranges.append(visibleRange)
            location = NSMaxRange(paragraphRange)
        }

        if ranges.isEmpty { ranges.append(.init(location: 0, length: 0)) }
        return ranges
    }

    func replaceText(in range: NSRange, with replacement: String, attributes: [NSAttributedString.Key: Any]? = nil) {
        guard let storage = editorTextView.textStorage else { return }
        suppressTextDidChange = true
        storage.replaceCharacters(
            in: range,
            with: NSAttributedString(string: replacement, attributes: attributes ?? editorTextView.typingAttributes)
        )
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
    }

    func insertTextAtSelection(_ text: String, attributes: [NSAttributedString.Key: Any]? = nil) {
        replaceText(in: editorTextView.selectedRange(), with: text, attributes: attributes)
    }

    func scrollSelectionToVisible() {
        guard let layoutManager = editorTextView.layoutManager,
              let textContainer = editorTextView.textContainer else {
            editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
    }

    func handleShortcutEvent(_ event: NSEvent) -> Bool {
        if let saveShortcut, saveShortcut.matches(event) {
            savePressed()
            return true
        }

        if isSuggestionVisible {
            switch event.keyCode {
            case 125:
                suggestionController.moveSelection(delta: 1)
                return true
            case 126:
                suggestionController.moveSelection(delta: -1)
                return true
            case 36, 76:
                if commitPendingTagIfNeeded(insertingTrailingText: "\n") {
                    dismissInlineSuggestions()
                    return true
                }
                suggestionController.acceptSelection()
                return true
            case 53:
                dismissInlineSuggestions()
                return true
            default:
                break
            }
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if handleEditorShortcut(keyCode: event.keyCode, modifiers: modifiers) { return true }

        if modifiers.intersection([.command, .option]).isEmpty == false {
            window?.makeFirstResponder(editorTextView)
            editorTextView.keyDown(with: event)
            return true
        }

        return false
    }

    func performStandardEditCommand(_ selector: Selector) -> Bool {
        let textResponder = (window?.firstResponder as? NSText) ?? editorTextView

        switch selector {
        case #selector(NSText.copy(_:)):
            textResponder.copy(self)
            return true
        case #selector(NSText.cut(_:)):
            textResponder.cut(self)
            return true
        case #selector(NSText.paste(_:)):
            textResponder.paste(self)
            return true
        case #selector(NSResponder.selectAll(_:)):
            textResponder.selectAll(self)
            return true
        case #selector(UndoManager.undo):
            textResponder.undoManager?.undo()
            return true
        case #selector(UndoManager.redo):
            textResponder.undoManager?.redo()
            return true
        default:
            break
        }

        return false
    }
}
