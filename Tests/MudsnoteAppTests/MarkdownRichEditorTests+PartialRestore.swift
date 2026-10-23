import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

private final class PartialRestoreFileManager: FileManager, @unchecked Sendable {
    var failureOnRestore: Int?
    private(set) var restoreAttempts = 0

    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if sourceURL.deletingLastPathComponent().lastPathComponent == "Trash" {
            restoreAttempts += 1
            if restoreAttempts == failureOnRestore { throw CocoaError(.fileWriteNoPermission) }
        }
        try super.moveItem(at: sourceURL, to: destinationURL)
    }
}

extension MarkdownRichEditorTests {
    @Test(arguments: [1, 2])
    func partialBatchRestoreUpdatesBothListsAndKeepsFailedNoteActionable(failureOrdinal: Int) throws {
        let suite = "mudsnote.partial-restore.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let manager = PartialRestoreFileManager()
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: manager,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        var originalURLs: [String: URL] = [:]
        var originalContents: [String: String] = [:]
        for index in 0..<2 {
            let original = try store.saveNewNote(title: "Restore \(index)", body: "Keep body \(index)")
            let content = try String(contentsOf: original, encoding: .utf8)
            let trash = try store.trashNote(at: original)
            originalURLs[trash.standardizedFileURL.path] = original
            originalContents[trash.standardizedFileURL.path] = content
        }
        let controller = LibraryWindowController(
            noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        defer { controller.close() }
        controller.selectedScope = .trash
        controller.reloadNotes(loadFirstIfNeeded: true)
        let noteRows = (0..<controller.tableView.numberOfRows).filter {
            controller.tableView(controller.tableView, pasteboardWriterForRow: $0) != nil
        }
        controller.tableView.selectRowIndexes(IndexSet(noteRows), byExtendingSelection: false)
        let selection = controller.selectedMarkdownFileURLsForLibrary()
        try #require(selection.count == 2)
        let failedTrashURL = selection[failureOrdinal - 1]
        let successfulTrashURL = selection[2 - failureOrdinal]
        let successfulURL = try #require(originalURLs[successfulTrashURL.standardizedFileURL.path])
        let failedOriginalURL = try #require(originalURLs[failedTrashURL.standardizedFileURL.path])
        let successfulContents = try #require(originalContents[successfulTrashURL.standardizedFileURL.path])
        let failedContents = try #require(originalContents[failedTrashURL.standardizedFileURL.path])
        manager.failureOnRestore = failureOrdinal

        #expect(throws: (any Error).self) { _ = try controller.restoreSelectedNoteForLibrary() }

        #expect(manager.restoreAttempts == 2)
        #expect(try String(contentsOf: successfulURL, encoding: .utf8) == successfulContents)
        #expect(!FileManager.default.fileExists(atPath: successfulTrashURL.path))
        #expect(try String(contentsOf: failedTrashURL, encoding: .utf8) == failedContents)
        #expect(!FileManager.default.fileExists(atPath: failedOriginalURL.path))
        #expect(controller.selectedScope == .trash)
        #expect(controller.noteListSearchResultsForLibrary().map { $0.url.resolvingSymlinksInPath() } == [failedTrashURL.resolvingSymlinksInPath()])
        #expect(controller.selectedMarkdownFileURLForLibrary()?.resolvingSymlinksInPath() == failedTrashURL.resolvingSymlinksInPath())
        #expect(controller.canRestoreSelectedNotesFromMenuForLibrary)

        #expect(controller.activateSourceScope(.all))
        #expect(controller.noteListSearchResultsForLibrary().map { $0.url.resolvingSymlinksInPath() } == [successfulURL.resolvingSymlinksInPath()])
        #expect(controller.activateSourceScope(.trash))
        #expect(controller.canRestoreSelectedNotesFromMenuForLibrary)
        manager.failureOnRestore = nil
        let retriedURL = try #require(try controller.restoreSelectedNoteForLibrary())

        #expect(retriedURL.resolvingSymlinksInPath() == failedOriginalURL.resolvingSymlinksInPath())
        #expect(try String(contentsOf: retriedURL, encoding: .utf8) == failedContents)
        #expect(store.listTrashedNotes().isEmpty)
        #expect(controller.trashedNotesSnapshot.isEmpty)
        #expect(Set(controller.sourceCountSnapshot.map { $0.url.resolvingSymlinksInPath() }) == Set(originalURLs.values.map { $0.resolvingSymlinksInPath() }))
    }

    @Test func trashSnapshotRemovalMatchesDirectoryAliasAfterSourceWasRestored() throws {
        let suite = "mudsnote.restore-alias.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        var trashURLs: [URL] = []
        for index in 0..<2 {
            trashURLs.append(try store.trashNote(at: store.saveNewNote(title: "Alias \(index)", body: "Body \(index)")))
        }
        let aliasDirectory = root.appendingPathComponent("TrashAlias")
        try FileManager.default.createSymbolicLink(at: aliasDirectory, withDestinationURL: store.trashDirectory())
        let controller = LibraryWindowController(
            noteStore: store, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        defer { controller.close() }
        controller.trashedNotesSnapshot = controller.trashedNotesSnapshot.map {
            $0.replacingURL(aliasDirectory.appendingPathComponent($0.url.lastPathComponent), modifiedAt: $0.modifiedAt)
        }
        _ = try store.restoreTrashedNote(at: trashURLs[0])
        #expect(!FileManager.default.fileExists(atPath: trashURLs[0].path))

        controller.removeNotesFromTrashSnapshot(at: [trashURLs[0]])

        #expect(controller.trashedNotesSnapshot.map(\.title) == ["Alias 1"])
        #expect(controller.trashedNotesSnapshot.first?.url.path == aliasDirectory.appendingPathComponent(trashURLs[1].lastPathComponent).path)
    }
}
