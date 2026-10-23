import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

private final class DeletionExitFileManager: FileManager, @unchecked Sendable {
    var deniedSourcePath: String?

    override func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        if sourceURL.standardizedFileURL.path == deniedSourcePath {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: sourceURL, to: destinationURL)
    }
}

@MainActor
private final class DeletionExitErrors {
    var messages: [String] = []
}

@MainActor
private struct DeletionExitHarness {
    let suite: String
    let defaults: UserDefaults
    let root: URL
    let store: NoteStore
    let manager: DeletionExitFileManager
    let controller: LibraryWindowController
    let blocker: BlockingAutosaveRecorder
    let errors: DeletionExitErrors
    let sourceURLs: [URL]

    init(noteCount: Int, permanentlyDeletes: Bool = false) throws {
        suite = "mudsnote.deletion-exit.\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        manager = DeletionExitFileManager()
        store = NoteStore(defaults: defaults, legacyDefaults: nil, fileManager: manager,
                          appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        var urls: [URL] = []
        for index in 0..<noteCount {
            let url = try store.saveNewNote(title: "Deletion \(index)", body: "Preserved body \(index)")
            urls.append(permanentlyDeletes ? try store.trashNote(at: url) : url)
        }
        sourceURLs = urls
        let blocker = BlockingAutosaveRecorder()
        let errors = DeletionExitErrors()
        self.blocker = blocker
        self.errors = errors
        controller = LibraryWindowController(
            noteStore: store, persistenceErrorHandler: { errors.messages.append($0.localizedDescription) },
            backgroundDeletionWillPersist: blocker.record,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        if permanentlyDeletes {
            controller.selectedScope = .trash
            controller.reloadNotes(loadFirstIfNeeded: true)
        }
    }

    func tearDown() {
        blocker.releaseFirstWrite.signal()
        controller.drainBackgroundDeletions()
        controller.close()
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root)
    }

    func requestExit(closesWindow: Bool) throws -> Bool {
        if closesWindow { return controller.windowShouldClose(try #require(controller.window)) }
        return AppController.terminationReply(editorControllers: [], libraryController: controller) == .terminateNow
    }

    func releasePersistenceSoon() {
        let blocker = blocker
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { blocker.releaseFirstWrite.signal() }
    }
}

extension MarkdownRichEditorTests {
    @Test(arguments: [false, true])
    func libraryExitFinishesEveryPendingDeletionBatch(closesWindow: Bool) throws {
        let harness = try DeletionExitHarness(noteCount: 2)
        defer { harness.tearDown() }
        let controller = harness.controller
        try controller.deleteSelectedNotesInBackgroundForLibrary()
        #expect(harness.blocker.firstWriteStarted.wait(timeout: .now() + 2) == .success)
        try controller.deleteSelectedNotesInBackgroundForLibrary()
        #expect(controller.pendingDeletionBatchCount == 2)
        #expect(controller.noteListSearchResultsForLibrary().isEmpty)
        #expect(harness.sourceURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        harness.releasePersistenceSoon()

        #expect(try harness.requestExit(closesWindow: closesWindow))

        #expect(controller.pendingDeletionBatchCount == 0)
        #expect(controller.pendingDeletionPaths.isEmpty)
        #expect(harness.sourceURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        #expect(Set(harness.store.listTrashedNotes().map(\.title)) == ["Deletion 0", "Deletion 1"])
        #expect(harness.errors.messages.isEmpty)
        // Already queued main callbacks must not apply a consumed batch twice.
        #expect(controller.finishBackgroundDeletion(batchID: 1) == nil)
        #expect(controller.finishBackgroundDeletion(batchID: 2) == nil)
        #expect(controller.trashedNotesSnapshot.count == 2)
    }

    @Test(arguments: [false, true])
    func libraryExitFinishesPendingPermanentDeletion(closesWindow: Bool) throws {
        let harness = try DeletionExitHarness(noteCount: 1, permanentlyDeletes: true)
        defer { harness.tearDown() }
        try harness.controller.deleteSelectedNotesInBackgroundForLibrary()
        #expect(harness.blocker.firstWriteStarted.wait(timeout: .now() + 2) == .success)
        #expect(FileManager.default.fileExists(atPath: harness.sourceURLs[0].path))
        harness.releasePersistenceSoon()

        #expect(try harness.requestExit(closesWindow: closesWindow))

        #expect(!FileManager.default.fileExists(atPath: harness.sourceURLs[0].path))
        #expect(harness.store.listTrashedNotes().isEmpty)
        #expect(harness.controller.pendingDeletionBatchCount == 0)
        #expect(harness.errors.messages.isEmpty)
    }

    @Test(arguments: [false, true])
    func failedPendingDeletionRestoresNoteAndCancelsExitOnce(closesWindow: Bool) throws {
        let harness = try DeletionExitHarness(noteCount: 2)
        defer { harness.tearDown() }
        let controller = harness.controller
        let failedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        let original = try String(contentsOf: failedURL, encoding: .utf8)
        harness.manager.deniedSourcePath = failedURL.standardizedFileURL.path
        try controller.deleteSelectedNotesInBackgroundForLibrary()
        #expect(harness.blocker.firstWriteStarted.wait(timeout: .now() + 2) == .success)
        try controller.deleteSelectedNotesInBackgroundForLibrary()
        harness.releasePersistenceSoon()

        #expect(try !harness.requestExit(closesWindow: closesWindow))

        #expect(try String(contentsOf: failedURL, encoding: .utf8) == original)
        #expect(controller.noteListSearchResultsForLibrary().map(\.url.standardizedFileURL) == [failedURL.standardizedFileURL])
        #expect(harness.store.listTrashedNotes().count == 1)
        #expect(controller.pendingDeletionBatchCount == 0)
        #expect(controller.pendingDeletionPaths.isEmpty)
        #expect(harness.errors.messages.count == 1)
        #expect(controller.finishBackgroundDeletion(batchID: 1) == nil)
        #expect(controller.finishBackgroundDeletion(batchID: 2) == nil)
        #expect(try harness.requestExit(closesWindow: closesWindow))
        #expect(harness.errors.messages.count == 1)
    }
}
