import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test(arguments: ["fresh", "deleteBackward", "deleteForward", "deleteLastCharacter"])
    func libraryPlainMultilinePasteOnlyFormatsFirstLineAsTitle(clearingAction: String) throws {
        let harness = try PlainTitlePasteHarness()
        defer { harness.tearDown() }
        let controller = harness.controller
        controller.createNewNoteForLibrary()
        let view = controller.editorTextView

        if clearingAction == "deleteLastCharacter" {
            view.insertText("X", replacementRange: view.selectedRange())
            view.deleteBackward(nil)
        } else if clearingAction != "fresh" {
            view.insertText("Old title\nOld body", replacementRange: view.selectedRange())
            view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
            if clearingAction == "deleteForward" {
                view.deleteForward(nil)
            } else {
                view.deleteBackward(nil)
            }
        }
        #expect(view.string.isEmpty)

        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        #expect(pasteboard.setString("Pasted title\nbody one\nbody two", forType: .string))
        #expect(pasteboard.data(forType: .html) == nil)
        #expect(pasteboard.data(forType: .rtf) == nil)
        #expect(MarkdownRichPasteNormalizer.markdown(from: pasteboard, theme: controller.theme) == nil)
        #expect(view.pasteContents(from: pasteboard))

        let storage = try #require(view.textStorage)
        let text = storage.string as NSString
        for (line, expectedKind) in [
            ("Pasted title", MarkdownParagraphKind.heading(level: 1)),
            ("body one", .paragraph),
            ("body two", .paragraph)
        ] {
            let range = text.range(of: line)
            try #require(range.location != NSNotFound)
            #expect(MarkdownRichTextCodec.paragraphKind(at: range, in: storage) == expectedKind)
        }
        #expect(controller.currentEditorDocument().title == "Pasted title")
        #expect(controller.currentEditorDocument().body == "body one\nbody two")

        let persistedURL = try controller.saveCurrentNoteForLibrary()
        let savedURL = try #require(persistedURL)
        let saved = try harness.store.loadNote(at: savedURL)
        #expect(saved.title == "Pasted title")
        #expect(saved.body == "body one\nbody two")
    }
}

@MainActor
private struct PlainTitlePasteHarness {
    let suite: String
    let defaults: UserDefaults
    let root: URL
    let store: NoteStore
    let controller: LibraryWindowController

    init() throws {
        suite = "mudsnote.plain-title-paste.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = NoteStore(defaults: defaults, legacyDefaults: nil,
                          appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        controller = LibraryWindowController(noteStore: store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
    }

    func tearDown() {
        controller.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }
}
