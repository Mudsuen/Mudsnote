import AppKit
import Carbon.HIToolbox
@_spi(Testing) import MudsnoteCore
import Testing
@testable import Mudsnote

extension MarkdownRichEditorTests {
    @MainActor
    func finishTagInputEvent() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor
    @Test
    func libraryTagInputWaitsForCompositionAndPreservesTextAndSelection() async throws {
        let harness = try makeEditorControllerHarness(draftID: "tag-ime", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "标题", body: "第一段\n\n保留空行😀")
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        let editor = controller.editorTextView
        let before = editor.string
        let selection = (before as NSString).range(of: "第一段")
        editor.setSelectedRange(selection)
        #expect(controller.window?.makeFirstResponder(editor) == true)
        editor.onAddMetadataTag?()
        let input = try #require(editor.allSubviews.compactMap { $0 as? NSComboBox }
            .first { $0.identifier?.rawValue == "InlineNoteTagInput" })
        let fieldEditor = try #require(input.currentEditor() as? NSTextView)
        #expect(!input.completes)
        fieldEditor.setMarkedText("xiangmu", selectedRange: NSRange(location: 7, length: 0),
            replacementRange: fieldEditor.selectedRange())
        #expect(fieldEditor.hasMarkedText())
        #expect(NSApp.sendAction(try #require(input.action), to: input.target, from: input))
        await finishTagInputEvent()
        #expect(controller.selectedTags.isEmpty)
        #expect(input.superview != nil)
        #expect(fieldEditor.hasMarkedText())
        fieldEditor.insertText("项目", replacementRange: fieldEditor.markedRange())
        #expect(!fieldEditor.hasMarkedText())
        #expect(NSApp.sendAction(try #require(input.action), to: input.target, from: input))
        await finishTagInputEvent()
        #expect(controller.selectedTags == ["项目"])
        #expect(editor.string == before)
        #expect(editor.selectedRange() == selection)
        #expect(controller.window?.firstResponder === editor)
        #expect(input.superview == nil)

        // Exercise the native field-editor Return path as well as the IME
        // action guard. The same keystroke must not reach the document.
        editor.onAddMetadataTag?()
        let nextInput = try #require(editor.allSubviews.compactMap { $0 as? NSComboBox }.first)
        let nextFieldEditor = try #require(nextInput.currentEditor() as? NSTextView)
        nextFieldEditor.insertText("另一个", replacementRange: nextFieldEditor.selectedRange())
        nextFieldEditor.keyDown(with: try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [], characters: "\r",
            windowNumber: try #require(controller.window).windowNumber))
        await finishTagInputEvent()
        #expect(controller.selectedTags.contains("另一个"))
        #expect(editor.string == before)
        #expect(editor.selectedRange() == selection)
        #expect(controller.window?.firstResponder === editor)
        #expect(nextInput.superview == nil)
        try controller.saveCurrentNoteIfNeeded()
        let noteURL = try #require(controller.selectedURL)
        #expect(try harness.store.loadNote(at: noteURL).tags == controller.selectedTags)
    }

    @MainActor
    @Test
    func libraryTagInputCancellationPreservesSelectionAndBlurRespectsSearch() async throws {
        let harness = try makeEditorControllerHarness(draftID: "tag-focus", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "Title", body: "Body\n\nKeep")
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        let editor = controller.editorTextView
        let before = editor.string
        let selection = (before as NSString).range(of: "Body")
        editor.setSelectedRange(selection)
        editor.onAddMetadataTag?()
        let input = try #require(editor.allSubviews.compactMap { $0 as? NSComboBox }.first)
        input.stringValue = "不要保存"
        input.cancelOperation(nil)
        await finishTagInputEvent()
        #expect(editor.string == before)
        #expect(editor.selectedRange() == selection)
        #expect(controller.window?.firstResponder === editor)
        #expect(controller.selectedTags.isEmpty)

        editor.onAddMetadataTag?()
        let secondInput = try #require(editor.allSubviews.compactMap { $0 as? NSComboBox }.first)
        secondInput.stringValue = "失焦取消"
        #expect(controller.window?.makeFirstResponder(controller.searchField) == true)
        await finishTagInputEvent()
        #expect(controller.window?.firstResponder === controller.searchField.currentEditor())
        #expect(secondInput.superview == nil)
        #expect(controller.selectedTags.isEmpty)
        #expect(editor.string == before)
    }

    @MainActor
    @Test
    func pendingTagInputCannotCommitIntoReplacementDocument() async throws {
        let harness = try makeEditorControllerHarness(draftID: "tag-document-switch", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "First", body: "First body")
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.editorTextView.onAddMetadataTag?()
        let input = try #require(controller.editorTextView.allSubviews.compactMap { $0 as? NSComboBox }.first)
        input.stringValue = "旧标签"
        #expect(NSApp.sendAction(try #require(input.action), to: input.target, from: input))
        controller.applyDocument(title: "Second", body: "Second body", tags: [])
        await finishTagInputEvent()
        #expect(controller.selectedTags.isEmpty)
        #expect(controller.editorTextView.string == "Second\n\nSecond body")
    }

    @MainActor
    @Test
    func libraryTagReturnDoesNotAddNewlineAndCompositionDismissesSuggestions() throws {
        let harness = try makeEditorControllerHarness(draftID: "tag-return", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "Title", body: "Body")
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        let editor = controller.editorTextView
        let prefix = "Title\n\n😀 正文\t"
        editor.textStorage?.setAttributedString(NSAttributedString(string: prefix + "#项目",
            attributes: controller.theme.baseAttributes(for: .paragraph)))
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.onTextInputStateChanged?()
        #expect(!controller.editorSuggestionController.view.isHidden)
        let event = try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [], characters: "\r")
        #expect(controller.markdownTextView(editor, handleKeyDown: event))
        #expect(editor.string == prefix)
        #expect(editor.selectedRange() == NSRange(location: prefix.utf16.count, length: 0))
        #expect(controller.selectedTags == ["项目"])
        controller.markdownTextViewInsertNewline(editor)
        #expect(editor.string == prefix + "\n")

        editor.insertText("#另一", replacementRange: editor.selectedRange())
        #expect(!controller.editorSuggestionController.view.isHidden)
        editor.setMarkedText("xiang", selectedRange: NSRange(location: 5, length: 0),
            replacementRange: editor.selectedRange())
        let markedSnapshot = editor.string
        #expect(controller.editorSuggestionController.view.isHidden)
        #expect(!controller.markdownTextView(editor, handleKeyDown: event))
        #expect(!controller.commitSelectedMetadataTagIfNeeded(insertingTrailingText: ""))
        #expect(editor.string == markedSnapshot)
        #expect(editor.hasMarkedText())
        editor.unmarkText()
    }

    @MainActor
    @Test
    func floatingSuggestionRangesUseUTF16AndTagReturnPreservesExistingWhitespace() throws {
        let harness = try makeEditorControllerHarness(draftID: "tag-unicode", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let editor = controller.editorTextView
        for prefix in ["😀 文字 ", "前文\t", "e\u{0301} ", "上一段\n😀\t"] {
            for token in ["#项目", "@目标", "/h1"] {
                editor.textStorage?.setAttributedString(NSAttributedString(string: prefix + token,
                    attributes: controller.theme.baseAttributes(for: .paragraph)))
                editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
                let expected = NSRange(location: prefix.utf16.count, length: token.utf16.count)
                switch token.first {
                case "#":
                    #expect(controller.currentTagToken()?.replacementRange == expected)
                    #expect(controller.commitPendingTagIfNeeded())
                    #expect(editor.string == prefix)
                    #expect(editor.selectedRange().location == prefix.utf16.count)
                case "@":
                    #expect(controller.currentNoteMentionToken()?.replacementRange == expected)
                default:
                    guard case .slash(_, let range, _) = controller.currentInlineSuggestionContext() else {
                        Issue.record("Expected slash command context")
                        continue
                    }
                    #expect(range == expected)
                }
            }
        }
    }

    @MainActor
    @Test
    func floatingTagReturnAcceptsTheHighlightedSuggestion() throws {
        let harness = try makeEditorControllerHarness(draftID: "tag-candidate", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.knownTagsForSuggestions = ["project", "product"]
        let editor = controller.editorTextView
        editor.insertText("#pro", replacementRange: editor.selectedRange())
        controller.updateInlineSuggestions()
        guard case .tags(_, _, let items) = controller.inlineSuggestionContext,
              let index = items.firstIndex(of: "project") else {
            Issue.record("Expected existing project tag suggestion")
            return
        }
        controller.suggestionController.moveSelection(delta: index)
        #expect(controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [], characters: "\r")))
        #expect(controller.activeTags == ["project"])
        #expect(editor.string.isEmpty)
        #expect(editor.selectedRange() == NSRange(location: 0, length: 0))
    }

    @MainActor
    @Test
    func floatingCompositionDoesNotAcceptStaleSuggestionOrClosePanelOnEscape() throws {
        let harness = try makeEditorControllerHarness(draftID: "tag-panel-ime", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let editor = controller.editorTextView
        let panel = try #require(controller.window as? QuickEntryPanel)
        #expect(panel.makeFirstResponder(editor))
        editor.insertText("#项目", replacementRange: editor.selectedRange())
        controller.updateInlineSuggestions()
        #expect(controller.isSuggestionVisible)
        editor.setMarkedText("xiang", selectedRange: NSRange(location: 5, length: 0),
            replacementRange: editor.selectedRange())
        #expect(!controller.isSuggestionVisible)
        #expect(!controller.handleShortcutEvent(try keyEvent(keyCode: UInt16(kVK_Return), modifiers: [], characters: "\r")))
        #expect(!controller.commitPendingTagIfNeeded())
        var didEscape = false
        var didIntercept = false
        panel.onEscape = { didEscape = true }
        panel.onEditorCommand = { _ in didIntercept = true; return true }
        panel.sendEvent(try keyEvent(keyCode: UInt16(kVK_Escape), modifiers: [], characters: "\u{1b}",
            windowNumber: panel.windowNumber))
        #expect(!didEscape)
        #expect(!didIntercept)
    }
}
