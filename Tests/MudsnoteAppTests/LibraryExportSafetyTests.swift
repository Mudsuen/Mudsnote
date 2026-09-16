import AppKit
import Foundation
import MudsnoteCore
import Testing
@testable import Mudsnote

@Suite(.serialized)
struct LibraryExportSafetyTests {
    @MainActor
    @Test
    func exportingToOriginalPathPreservesDocument() throws {
        try withLibrary { controller, store, root, source in
            let before = try Data(contentsOf: source)
            #expect(try controller.exportSelectedMarkdownForLibrary(to: source) == source)
            #expect(try Data(contentsOf: source) == before)
            #expect(try store.loadNote(at: source).body == "Original body")
        }
    }

    @MainActor
    @Test
    func missingExportSourceDoesNotDeleteExistingDestination() throws {
        try withLibrary { controller, _, root, source in
            let destination = root.appendingPathComponent("Existing.md")
            try "Keep this export".write(to: destination, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: source)
            #expect(throws: (any Error).self) {
                try controller.exportSelectedMarkdownForLibrary(to: destination)
            }
            #expect(try String(contentsOf: destination, encoding: .utf8) == "Keep this export")
        }
    }

    @MainActor
    @Test
    func exportUsesRenamedDocumentAfterSavingEdits() throws {
        try withLibrary { controller, store, root, _ in
            controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
                markdown: "# Renamed\n\nNew body", theme: controller.theme
            ))
            controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
            let destination = root.appendingPathComponent("Export.md")
            #expect(try controller.exportSelectedMarkdownForLibrary(to: destination) == destination)
            let exported = try store.loadNote(at: destination)
            #expect(exported.title == "Renamed")
            #expect(exported.body == "New body")
        }
    }

    @MainActor
    private func withLibrary(_ body: (LibraryWindowController, NoteStore, URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.export-safety." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let source = try store.saveNewNote(title: "Original", body: "Original body")
        let controller = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        try body(controller, store, root, source)
    }
}
