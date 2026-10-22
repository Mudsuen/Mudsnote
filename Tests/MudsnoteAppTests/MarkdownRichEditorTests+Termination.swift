import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test(arguments: [false, true])
    func failedAutosaveAfterNavigationBlocksExitAndKeepsRecoverableEdit(returnToEditedNote: Bool) async throws {
        let suite = "mudsnote.library-exit-failed-save.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        _ = try store.saveNewNote(title: "First", body: "First body")
        _ = try store.saveNewNote(title: "Second", body: "Second body")
        let failsPersistence = MutableBoolFlag(true)
        store.updateNoteCommitHook = { _ in
            if failsPersistence.get() { throw CocoaError(.fileWriteNoPermission) }
        }
        let recorder = BlockingAutosaveRecorder()
        var errors: [String] = []
        var savedURLs: [URL] = []
        let controller = LibraryWindowController(
            noteStore: store, backgroundAutosaveWillPersist: recorder.record,
            persistenceErrorHandler: { errors.append($0.localizedDescription) },
            onOpenInSeparateWindow: { _ in }, onSave: { savedURLs.append($0) }, onClose: {}
        )
        defer {
            failsPersistence.set(false)
            recorder.releaseFirstWrite.signal()
            controller.drainBackgroundAutosaves()
            controller.close()
        }
        let editedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Retained Renamed\n\nRetained failure edit", theme: controller.theme
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        controller.triggerBackgroundAutosaveForTesting()
        let firstStarted = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: recorder.firstWriteStarted.wait(timeout: .now() + 2))
            }
        }
        #expect(firstStarted == .success)
        let otherRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let url = controller.tableView(controller.tableView, pasteboardWriterForRow: row) as? NSURL else { return false }
            return (url as URL).standardizedFileURL != editedURL.standardizedFileURL
        })
        controller.tableView.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        let otherURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        let otherContents = try String(contentsOf: otherURL, encoding: .utf8)
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        recorder.releaseFirstWrite.signal()
        await controller.waitForBackgroundAutosaveForTesting()

        #expect(AppController.terminationReply(editorControllers: [], libraryController: controller) == .terminateCancel)
        #expect(!controller.windowShouldClose(try #require(controller.window)))
        #expect(errors.count == 2)
        #expect(errors.allSatisfy { $0.contains("Retained Renamed") })
        #expect(controller.failedBackgroundAutosaveSnapshots.values.map(\.body) == ["Retained failure edit"])
        #expect(try String(contentsOf: otherURL, encoding: .utf8) == otherContents)

        if returnToEditedNote {
            let originalRow = try #require((0..<controller.tableView.numberOfRows).first { row in
                guard let url = controller.tableView(controller.tableView, pasteboardWriterForRow: row) as? NSURL else { return false }
                return (url as URL).standardizedFileURL == editedURL.standardizedFileURL
            })
            controller.tableView.selectRowIndexes(IndexSet(integer: originalRow), byExtendingSelection: false)
            await controller.waitForActiveNoteLoadForLibrary()
            #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        }
        failsPersistence.set(false)
        #expect(AppController.terminationReply(editorControllers: [], libraryController: controller) == .terminateNow)
        let recoveredURL = try #require(savedURLs.last)
        #expect(try store.loadNote(at: recoveredURL).body == "Retained failure edit")
        #expect(controller.failedBackgroundAutosaveSnapshots.isEmpty)
        #expect(try String(contentsOf: otherURL, encoding: .utf8) == otherContents)
        if returnToEditedNote {
            #expect(controller.currentEditorMarkdownBody() == "Retained failure edit")
        }
    }

    @Test(arguments: [false, true])
    func newerAutosaveSupersedesFailedRevisionBeforeRenameAndQuit(finalAutosaveSucceeds: Bool) async throws {
        let suite = "mudsnote.library-exit-save-supersession.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let originalURL = try store.saveNewNote(title: "Original", body: "Original body")
        let failsPersistence = MutableBoolFlag(true)
        store.updateNoteCommitHook = { _ in
            if failsPersistence.get() { throw CocoaError(.fileWriteNoPermission) }
        }
        var errors: [String] = []
        let controller = LibraryWindowController(
            noteStore: store, persistenceErrorHandler: { errors.append($0.localizedDescription) },
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        defer {
            failsPersistence.set(false)
            controller.drainBackgroundAutosaves()
            controller.close()
        }
        func edit(title: String, body: String) {
            controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
                markdown: "# \(title)\n\n\(body)", theme: controller.theme
            ))
            controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
            controller.triggerBackgroundAutosaveForTesting()
        }
        edit(title: "First Renamed", body: "Superseded edit")
        await controller.waitForBackgroundAutosaveForTesting()
        #expect(controller.failedBackgroundAutosaveSnapshots.count == 1)

        failsPersistence.set(!finalAutosaveSucceeds)
        edit(title: "Latest Renamed", body: "Latest retained edit")
        await controller.waitForBackgroundAutosaveForTesting()
        if finalAutosaveSucceeds {
            #expect(controller.failedBackgroundAutosaveSnapshots.isEmpty)
            #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        } else {
            #expect(controller.failedBackgroundAutosaveSnapshots.values.map(\.body) == ["Latest retained edit"])
        }
        failsPersistence.set(false)

        #expect(AppController.terminationReply(editorControllers: [], libraryController: controller) == .terminateNow)
        #expect(errors.isEmpty)
        #expect(controller.failedBackgroundAutosaveSnapshots.isEmpty)
        let finalURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        #expect(finalURL != originalURL)
        #expect(try store.loadNote(at: finalURL).title == "Latest Renamed")
        #expect(try store.loadNote(at: finalURL).body == "Latest retained edit")
        let markdownFiles = try FileManager.default.contentsOfDirectory(
            at: store.notesDirectory, includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }
        #expect(markdownFiles.map { $0.resolvingSymlinksInPath() } == [finalURL.resolvingSymlinksInPath()])
    }

    @Test(arguments: [false, true])
    func libraryCloseAndQuitWaitForPendingAutosave(closesWindow: Bool) throws {
        let suite = "mudsnote.library-exit-save.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        let note = try store.saveNewNote(title: "Exit Guard", body: "Original")
        let recorder = BlockingAutosaveRecorder()
        let controller = LibraryWindowController(
            noteStore: store, backgroundAutosaveWillPersist: recorder.record,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        defer {
            recorder.releaseFirstWrite.signal()
            controller.drainBackgroundAutosaves()
            controller.close()
        }
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Exit Guard\n\nEdit before exit", theme: controller.theme
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        controller.triggerBackgroundAutosaveForTesting()
        #expect(recorder.firstWriteStarted.wait(timeout: .now() + 2) == .success)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { recorder.releaseFirstWrite.signal() }

        if closesWindow {
            #expect(controller.windowShouldClose(try #require(controller.window)))
        } else {
            #expect(AppController.terminationReply(editorControllers: [], libraryController: controller) == .terminateNow)
        }

        // The disk read deliberately happens before any asynchronous test flush.
        #expect(try store.loadNote(at: note).body == "Edit before exit")
        #expect(!controller.backgroundAutosaveIsActive)
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
    }

    @Test func libraryQuitWaitsForPreviousNoteSaveAfterNavigation() throws {
        let suite = "mudsnote.library-exit-navigation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let store = NoteStore(defaults: defaults, legacyDefaults: nil,
                              appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        _ = try store.saveNewNote(title: "First", body: "First body")
        _ = try store.saveNewNote(title: "Second", body: "Second body")
        let recorder = BlockingAutosaveRecorder()
        let controller = LibraryWindowController(
            noteStore: store, backgroundAutosaveWillPersist: recorder.record,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {}
        )
        defer {
            recorder.releaseFirstWrite.signal()
            controller.drainBackgroundAutosaves()
            controller.close()
        }
        let editedURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# \(controller.titleField.stringValue)\n\nEdit then navigate and quit", theme: controller.theme
        ))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        controller.triggerBackgroundAutosaveForTesting()
        #expect(recorder.firstWriteStarted.wait(timeout: .now() + 2) == .success)
        let otherRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let url = controller.tableView(controller.tableView, pasteboardWriterForRow: row) as? NSURL else { return false }
            return (url as URL).standardizedFileURL != editedURL.standardizedFileURL
        })
        controller.tableView.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { recorder.releaseFirstWrite.signal() }

        #expect(AppController.terminationReply(editorControllers: [], libraryController: controller) == .terminateNow)
        #expect(try store.loadNote(at: editedURL).body == "Edit then navigate and quit")
        #expect(!controller.backgroundAutosaveIsActive)
    }
}
