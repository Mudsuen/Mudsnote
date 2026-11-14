import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test(arguments: [true, false])
    func librarySaveRenameKeepsSelection(background: Bool) async throws {
        let suite = "mudsnote.library-save-selection.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let original = try store.saveNewNote(title: "Original", body: "Before")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.showWindowAndFocus()
        controller.showLibraryNavigationPage(.list, scope: .all)
        await controller.waitForActiveNoteLoadForLibrary()
        #expect(controller.selectedMarkdownFileURLsForLibrary() == [original])
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Renamed\n\nSaved body", theme: controller.theme, baseURL: original))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        if background { controller.flushBackgroundAutosaveForTesting() }
        else { _ = try controller.saveCurrentNoteForLibrary() }
        let saved = try #require(controller.selectedURL)
        #expect(saved != original)
        #expect(controller.selectedMarkdownFileURLsForLibrary() == [saved])
        #expect(controller.note(at: controller.tableView.selectedRow)?.title == "Renamed")
        #expect(controller.activeDocumentTab.title == "Renamed")
        #expect(try store.loadNote(at: saved).body == "Saved body")
    }
}
