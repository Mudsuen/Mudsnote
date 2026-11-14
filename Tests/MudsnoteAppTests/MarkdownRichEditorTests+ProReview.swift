import AppKit
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test func proReviewPreservesFencesIndentationAndOriginalListMarkers() {
        let markdown = """
        # Title

        * outer
          - nested **literal**

        ```swift
        # not a heading
        let value = "**not bold**"
        ```

        ~~~~
        - not a list
        ~~~~
        """
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        #expect(MarkdownRichTextCodec.serialize(rendered, theme: theme) == markdown)
        let shortcut = MarkdownRichTextCodec.renderLine(" [ ] task", theme: theme)
        #expect(MarkdownRichTextCodec.serialize(shortcut, theme: theme) == "- [ ] task")
    }

    @Test func proReviewTypedMarkdownKeepsExistingFormattingAndLink() throws {
        let harness = try makeEditorControllerHarness(draftID: "pro-formatting", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = harness.controller
        let source = "**bold** [link](https://example.com) and **new**"
        let storage = try #require(controller.editorTextView.textStorage)
        storage.setAttributedString(MarkdownRichTextCodec.renderLine("**bold** [link](https://example.com)", theme: controller.theme))
        storage.append(NSAttributedString(string: " and **new**", attributes: controller.theme.baseAttributes(for: .paragraph)))
        controller.editorTextView.setSelectedRange(NSRange(location: storage.length, length: 0))
        controller.interpretTypedMarkdownIfNeeded()
        #expect(MarkdownRichTextCodec.serialize(storage, theme: controller.theme) == source)
    }

    @Test func proReviewLibraryDocumentAndSourceModeClearOldUndo() throws {
        let harness = try makeEditorControllerHarness(draftID: "pro-undo", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = LibraryWindowController(noteStore: harness.store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.applyDocument(title: "First", body: "First body", tags: [])
        let oldID = controller.documentIdentity
        let undo = try #require(controller.editorTextView.undoManager)
        undo.registerUndo(withTarget: controller) { target in
            target.editorTextView.string = "Old document must not return"
        }
        #expect(undo.canUndo)
        controller.applyDocument(title: "Second", body: "Second body", tags: [])
        #expect(!undo.canUndo)
        #expect(controller.documentIdentity != oldID)
        #expect(controller.editorTextView.string.contains("Second body"))
    }

    @Test func proReviewSourceModeInsertsLiteralAttachmentMarkdown() throws {
        let harness = try makeEditorControllerHarness(draftID: "pro-source", showsSaveButton: false)
        defer { harness.tearDown() }
        let controller = LibraryWindowController(noteStore: harness.store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.applyDocument(title: "Source", body: "", tags: [])
        controller.isEditorShowingMarkdownSource = true
        controller.editorTextView.isRichText = false
        controller.editorTextView.string = ""
        controller.editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        let markdown = "![sample](Attachments/sample.png)"
        controller.replaceSelectionWithRenderedMarkdown(markdown)
        #expect(controller.editorTextView.string == markdown)
        #expect(!controller.editorTextView.string.contains("\u{FFFC}"))
    }

    @Test func proReviewSearchUsesUpdatedStoreIndex() async throws {
        let harness = try makeEditorControllerHarness(draftID: "pro-search", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "First", body: "needle")
        let search = DebouncedNoteSearchController(noteStore: harness.store, limit: 10)
        var titles: [String] = []
        search.submit(query: "needle", delay: .zero) { titles = $0.results.map(\.title) }
        await search.waitForCurrentSearchForTesting()
        #expect(titles == ["First"])
        _ = try harness.store.saveNewNote(title: "Second", body: "needle")
        search.submit(query: "needle", delay: .zero) { titles = $0.results.map(\.title) }
        await search.waitForCurrentSearchForTesting()
        #expect(Set(titles) == ["First", "Second"])
    }

    @Test func proReviewAttachmentInventoryProtectsReferencesDraftsAndIncompleteScans() throws {
        let harness = try makeEditorControllerHarness(draftID: "pro-attachments", showsSaveButton: false)
        defer { harness.tearDown() }
        let root = harness.store.notesDirectory
        let attachmentRoot = root.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachmentRoot, withIntermediateDirectories: true)
        for name in ["reference.png", "draft.png", "unknown.png"] {
            try Data([1]).write(to: attachmentRoot.appendingPathComponent(name))
        }
        let noteURL = root.appendingPathComponent("Reference.md")
        try "![Photo][image]\n\n[image]: Attachments/reference.png".write(to: noteURL, atomically: true, encoding: .utf8)
        try harness.store.saveDraft(DraftSnapshot(id: "attachment-draft", sourcePath: noteURL.path,
            selectedDirectoryPath: root.path, title: "Draft", body: "![Draft](Attachments/draft.png)", tags: [], updatedAt: Date()))
        let protected = try harness.store.protectedAttachmentReferenceSources()
        let items = LibraryAttachmentInventory.build(roots: [root], protectedSources: protected)
        #expect(items.first { $0.filename == "reference.png" }?.state == .referenced)
        #expect(items.first { $0.filename == "draft.png" }?.state == .referenced)
        try Data([0xFF, 0xFE]).write(to: root.appendingPathComponent("Unreadable.md"))
        let incomplete = LibraryAttachmentInventory.build(roots: [root], protectedSources: protected)
        #expect(incomplete.first { $0.filename == "unknown.png" }?.state == .unknown)
    }

    @Test func proReviewTagMutationRejectsStaleSourceWithoutOverwriting() throws {
        let harness = try makeEditorControllerHarness(draftID: "pro-tag-cas", showsSaveButton: false)
        defer { harness.tearDown() }
        let url = try harness.store.saveNewNote(title: "CAS", body: "original")
        let source = try String(contentsOf: url, encoding: .utf8)
        try "external edit".write(to: url, atomically: true, encoding: .utf8)
        #expect(throws: Error.self) {
            try harness.store.replaceTagMutationContents(at: url, expected: source, replacement: "must not write")
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "external edit")
    }
}
