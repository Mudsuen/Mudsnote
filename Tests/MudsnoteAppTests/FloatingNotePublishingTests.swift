import AppKit
import Foundation
import CoreServices
import Testing
import MudsnoteCore
@testable import Mudsnote

@Suite(.serialized)
struct FloatingNotePublishingTests {
    @MainActor @Test
    func floatingAutosavePublishesBodyForLibraryWithoutClosingWindow() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "floating-publish-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let url = try store.saveNewNote(title: "", body: "")
        let editor = EditorWindowController(noteStore: store, panelOpacity: 1, fileURL: url,
            draftIDOverride: "floating-note", showsSaveButton: false,
            onSave: { _ in }, onClose: {}, onRequestSearch: {}, onRequestPreferences: {})
        defer { editor.close() }
        let library = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { library.close() }
        try library.openMarkdownDocumentForLibrary(at: url)
        editor.applyInitialContent(title: "Floating title", body: "Floating body")
        editor.markDocumentDirty()
        await editor.flushPendingDraftAutosaveForTesting()
        let loaded = try store.loadNote(at: url)
        #expect(loaded.title == "Floating title")
        #expect(loaded.body == "Floating body")
        #expect(!editor.isWindowClosed)
        library.handleLibraryFileSystemChangesForTesting([
            LibraryFileSystemChange(path: url.path, flags: FSEventStreamEventFlags(
                kFSEventStreamEventFlagItemModified | kFSEventStreamEventFlagItemIsFile))
        ])
        await library.waitForExternalLibraryRefreshForTesting()
        #expect(library.editorTextView.string.contains("Floating body"))
        editor.applyInitialContent(title: "", body: "")
        editor.markDocumentDirty()
        await editor.flushPendingDraftAutosaveForTesting()
        #expect(try store.loadNote(at: url).body.isEmpty)
        #expect(try store.loadNote(at: url).title.isEmpty)
    }

    @Test func serialPublishingUsesLastCommittedBaselineAndPreservesExternalConflict() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "floating-coordinator-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let url = try store.saveNewNote(title: "Original", body: "")
        let original = try String(contentsOf: url, encoding: .utf8)
        let coordinator = DraftPersistenceCoordinator(save: { try store.saveDraft($0) }, delete: { store.deleteDraft(id: $0) }, publish: { snapshot, target, expected in
            try store.updateNote(at: target, title: snapshot.title, body: snapshot.body, tags: snapshot.tags,
                                 expectedContents: expected, updatesInPlace: true)
        })
        func snapshot(_ body: String) -> DraftSnapshot {
            DraftSnapshot(id: "floating-test", sourcePath: url.path, selectedDirectoryPath: root.path,
                          title: "Floating", body: body, updatedAt: Date())
        }
        _ = try coordinator.flush(.publish(snapshot("One"), expectedContents: original))
        let second = try #require(try coordinator.flush(.publish(snapshot("Two"), expectedContents: original)))
        #expect(second.url == url)
        #expect(second.conflictedOriginalURL == nil)
        #expect(try store.loadNote(at: url).body == "Two")
        try "# External\n\nKeep external".write(to: url, atomically: true, encoding: .utf8)
        let conflict = try #require(try coordinator.flush(.publish(snapshot("Three"), expectedContents: original)))
        #expect(conflict.url != url)
        #expect(try store.loadNote(at: url).body == "Keep external")
        #expect(try store.loadNote(at: conflict.url).body == "Three")
        let continued = try #require(try coordinator.flush(.publish(snapshot("Four"), expectedContents: original)))
        #expect(continued.url == conflict.url)
        #expect(try store.loadNote(at: continued.url).body == "Four")
        #expect(store.loadDraft(id: "floating-test") == nil)
    }

    @Test func failedPublishingRetainsRecoverableDraft() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "floating-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        let snapshot = DraftSnapshot(id: "failed-floating", sourcePath: root.appendingPathComponent("note.md").path,
                                     selectedDirectoryPath: root.path, title: "Keep", body: "Recover me", updatedAt: Date())
        let coordinator = DraftPersistenceCoordinator(save: { try store.saveDraft($0) }, delete: { store.deleteDraft(id: $0) }, publish: { _, _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        #expect(throws: (any Error).self) { try coordinator.flush(.publish(snapshot, expectedContents: "")) }
        #expect(store.loadDraft(id: snapshot.id)?.body == "Recover me")
    }
}
