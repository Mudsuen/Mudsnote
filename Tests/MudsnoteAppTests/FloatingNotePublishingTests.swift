import AppKit
import Foundation
import CoreServices
import Testing
import MudsnoteCore
@testable import Mudsnote

@Suite(.serialized)
struct FloatingNotePublishingTests {
    @MainActor @Test
    func legacyFloatingDraftBecomesOneLibraryNoteAndReopensLatestContents() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "floating-primary-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let pinned = try store.saveNewNote(title: "Ordinary pin", body: "Keep")
        store.setLibraryNotePinned(true, at: pinned)
        let library = LibraryWindowController(noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { library.close() }
        try store.saveDraft(DraftSnapshot(id: "floating-note", sourcePath: nil,
            selectedDirectoryPath: store.notesDirectory.path, title: "Flow",
            body: "Recovered **body**", tags: ["work"], updatedAt: Date()))
        let url = try store.preparePrimaryFloatingNote()
        #expect(store.loadDraft(id: "floating-note") == nil)
        #expect(store.primaryFloatingNoteURL == url)
        #expect(try store.loadNote(at: url).body == "Recovered **body**")
        #expect(try store.loadNote(at: url).tags == ["work"])
        library.updateFloatingNotePaths([url.path])
        await library.waitForSourceSnapshotValidationForLibrary()
        #expect(library.listRows.compactMap(\.note).prefix(2).map(\.url) == [url, pinned])
        #expect(library.listRows.compactMap { row -> String? in
            if case .group(let title) = row { return title }; return nil
        }.prefix(2) == ["浮窗笔记", "置顶"])
        let editor = EditorWindowController(noteStore: store, panelOpacity: 1, fileURL: url,
            draftIDOverride: "floating-note", showsSaveButton: false,
            onSave: { _ in }, onClose: {}, onRequestSearch: {}, onRequestPreferences: {})
        defer { editor.close() }
        editor.applyInitialContent(title: "Flow", body: "Continued in floating window")
        editor.markDocumentDirty()
        await editor.flushPendingDraftAutosaveForTesting()
        #expect(try store.loadNote(at: url).body == "Continued in floating window")
        let reopenedStore = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        let reopened = try reopenedStore.preparePrimaryFloatingNote()
        #expect(reopened == url)
        #expect(store.listNotes(limit: 10).count == 2)
        #expect(try reopenedStore.loadNote(at: reopened).body == "Continued in floating window")
        library.updateFloatingNotePaths([])
        #expect(library.listRows.compactMap(\.note).first?.url == pinned)
        editor.close()
        let renamed = try store.updateNote(at: url, title: "Renamed Flow", body: "Edited in library")
        #expect(store.primaryFloatingNoteURL == renamed)
        #expect(try reopenedStore.preparePrimaryFloatingNote() == renamed)
    }

    @Test func primaryFloatingDraftConversionFailurePreservesRecovery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "floating-primary-failure-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let blockedDirectory = root.appendingPathComponent("not-a-directory")
        try "keep".write(to: blockedDirectory, atomically: true, encoding: .utf8)
        try store.saveDraft(DraftSnapshot(id: "floating-note", sourcePath: nil,
            selectedDirectoryPath: blockedDirectory.path, title: "Flow", body: "Do not lose",
            tags: [], updatedAt: Date()))
        #expect(throws: (any Error).self) { try store.preparePrimaryFloatingNote() }
        #expect(store.loadDraft(id: "floating-note")?.body == "Do not lose")
        #expect(store.primaryFloatingNoteURL == nil)
    }

    @Test func primaryFloatingDraftCheckpointDoesNotDuplicateOrOverwriteExternalEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "floating-primary-retry-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let url = try store.saveNewNote(title: "Flow", body: "Body")
        let checkpoint = DraftSnapshot(id: "floating-note", sourcePath: url.path,
            selectedDirectoryPath: store.notesDirectory.path, title: "Flow", body: "Body",
            tags: [], updatedAt: Date())
        try store.saveDraft(checkpoint)
        #expect(try store.preparePrimaryFloatingNote() == url)
        #expect(store.listNotes(limit: 10).count == 1)
        try "# Flow\n\nExternal change".write(to: url, atomically: true, encoding: .utf8)
        try store.saveDraft(checkpoint)
        let recovered = try store.preparePrimaryFloatingNote()
        #expect(recovered != url)
        #expect(try store.loadNote(at: url).body == "External change")
        #expect(try store.loadNote(at: recovered).body == "Body")
    }

    @Test func floatingNotesRankAbovePinsBeforeResultLimitAndAppearOnce() {
        let now = Date()
        let notes = (0..<10).map { index in
            NoteSearchResult(url: URL(fileURLWithPath: "/tmp/note-\(index).md"),
                title: "Note \(index)", snippet: "", modifiedAt: now.addingTimeInterval(Double(-index)))
        }
        let floating = notes[9].url.path
        let pinned = notes[8].url.path
        for sort in [LibraryNoteSortOrder.dateEdited, .dateCreated, .title] {
            let ranked = LibraryNoteListProjection.rankedPrefix(notes, limit: 2,
                sortOrder: sort, groupsByDate: true, includesPinnedGroup: true,
                pinnedPaths: [pinned, floating], floatingPaths: [floating], where: { _ in true })
            #expect(ranked.map(\.url.path) == [floating, pinned])
            let rows = LibraryNoteListProjection.rows(for: ranked, sortOrder: sort,
                groupsByDate: true, includesPinnedGroup: true,
                pinnedPaths: [pinned, floating], floatingPaths: [floating])
            #expect(rows.compactMap(\.note).map(\.url.path) == [floating, pinned])
            #expect(rows.compactMap { row -> String? in
                if case .group(let title) = row { return title }; return nil
            } == ["浮窗笔记", "置顶"])
        }
        let ordinary = LibraryNoteListProjection.rows(for: notes, sortOrder: .dateEdited,
            groupsByDate: false, includesPinnedGroup: false,
            pinnedPaths: [pinned], floatingPaths: [floating])
        #expect(ordinary.compactMap(\.note).map(\.url) == notes.map(\.url))
    }

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
