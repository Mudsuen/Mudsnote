import AppKit
import Foundation
import Testing
@testable import Mudsnote
@testable import MudsnoteCore

extension MarkdownRichEditorTests {
    @Test(arguments: ["    ", "\t"])
    func roundTwoDiskIndentationSurvivesAutosaveAndCommandSave(indent: String) async throws {
        let harness = try makeEditorControllerHarness(draftID: "round-two-indent", showsSaveButton: false)
        defer { harness.tearDown() }
        let root = harness.store.notesDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("2020-01-02-demo-2.md")
        try "# Demo\n\n\(indent)let x = 1\n\(indent)let y = 2\n\nTail\n".write(to: url, atomically: true, encoding: .utf8)
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        await controller.waitForActiveNoteLoadForLibrary()
        for (index, tail) in ["Autosaved tail", "Manually saved tail"].enumerated() {
            let loaded = try harness.store.loadNote(at: url)
            #expect(loaded.body.hasPrefix(indent + "let x"))
            controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
                markdown: "# Demo\n\n\(indent)let x = 1\n\(indent)let y = 2\n\n\(tail)", theme: controller.theme))
            controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
            if index == 0 {
                controller.triggerBackgroundAutosaveForTesting()
                await controller.waitForBackgroundAutosaveForTesting()
            } else { #expect(try controller.saveCurrentNoteForLibrary() == url) }
            #expect(controller.selectedMarkdownFileURLForLibrary() == url)
            #expect(try harness.store.loadNote(at: url).body == "\(indent)let x = 1\n\(indent)let y = 2\n\n\(tail)")
        }
        let timestamp = Date(timeIntervalSince1970: 1_600_000_000)
        try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: url.path)
        _ = try controller.saveCurrentNoteForLibrary()
        #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == timestamp)
    }

    @Test func roundTwoPreviousDocumentFailureDoesNotChangeCurrentStatusOrBlockCommandSave() async throws {
        let harness = try makeEditorControllerHarness(draftID: "round-two-save-owner", showsSaveButton: false)
        defer { harness.tearDown() }
        _ = try harness.store.saveNewNote(title: "A", body: "A body")
        _ = try harness.store.saveNewNote(title: "B", body: "B body")
        let blocked = BlockingAutosaveRecorder()
        let failing = MutableBoolFlag(true)
        harness.store.updateNoteCommitHook = { _ in if failing.get() { throw CocoaError(.fileWriteNoPermission) } }
        let controller = LibraryWindowController(noteStore: harness.store, backgroundAutosaveWillPersist: blocked.record,
            persistenceErrorHandler: { _ in }, onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer {
            failing.set(false); blocked.releaseFirstWrite.signal()
            controller.drainBackgroundAutosaves(); controller.close()
        }
        let original = try #require(controller.selectedMarkdownFileURLForLibrary())
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# Renamed failing A\n\nRetained A edit", theme: controller.theme))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        controller.triggerBackgroundAutosaveForTesting()
        let started = await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: blocked.firstWriteStarted.wait(timeout: .now() + 2)) }
        }
        try #require(started == .success)
        let otherRow = try #require((0..<controller.tableView.numberOfRows).first { row in
            guard let url = controller.tableView(controller.tableView, pasteboardWriterForRow: row) as? NSURL else { return false }
            return (url as URL).standardizedFileURL != original.standardizedFileURL
        })
        controller.tableView.selectRowIndexes(IndexSet(integer: otherRow), byExtendingSelection: false)
        await controller.waitForActiveNoteLoadForLibrary()
        let otherURL = try #require(controller.selectedMarkdownFileURLForLibrary())
        let status = controller.statusLabel.stringValue
        blocked.releaseFirstWrite.signal()
        await controller.waitForBackgroundAutosaveForTesting()
        #expect(controller.statusLabel.stringValue == status)
        #expect(controller.failedBackgroundAutosaveSnapshots.values.map(\.body) == ["Retained A edit"])
        let title = try harness.store.loadNote(at: otherURL).title
        controller.editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(
            markdown: "# \(title)\n\nSaved B edit", theme: controller.theme))
        controller.textDidChange(Notification(name: NSText.didChangeNotification, object: controller.editorTextView))
        #expect(try controller.saveCurrentNoteForLibrary() == otherURL)
        #expect(try harness.store.loadNote(at: otherURL).body == "Saved B edit")
        #expect(controller.failedBackgroundAutosaveSnapshots.values.map(\.body) == ["Retained A edit"])
        #expect(!controller.prepareForApplicationTermination())
    }

    @Test func roundTwoTableNavigationAlignmentUndoAndSourceModeStayConsistent() throws {
        let harness = try makeEditorControllerHarness(draftID: "round-two-table", showsSaveButton: false)
        defer { harness.tearDown() }
        let body = "| Left | Center | Right |\n| :--- | :---: | ---: |\n| 汉字 | a\\|b | end |"
        let url = try harness.store.saveNewNote(title: "Table", body: body)
        let controller = LibraryWindowController(noteStore: harness.store,
            onOpenInSeparateWindow: { _ in }, onSave: { _ in }, onClose: {})
        defer { controller.close() }
        controller.showWindow(nil)
        controller.window?.makeFirstResponder(controller.editorTextView)
        let before = controller.serializedEditorMarkdown()
        let first = try #require(tableCellRange(row: 0, column: 0, in: controller.editorTextView.attributedString()))
        controller.editorTextView.setSelectedRange(NSRange(location: first.location, length: 0))
        #expect(controller.moveMarkdownTableCellSelectionForLibrary(.next))
        #expect(controller.serializedEditorMarkdown() == before)
        #expect(!controller.currentNoteHasUnsavedChangesForLibrary)
        let last = try #require(tableCellRange(row: 1, column: 2, in: controller.editorTextView.attributedString()))
        controller.editorTextView.setSelectedRange(NSRange(location: last.location, length: 0))
        #expect(controller.moveMarkdownTableCellSelectionForLibrary(.next))
        #expect(controller.serializedEditorMarkdown().contains("| :--- | :---: | ---: |"))
        let appended = controller.serializedEditorMarkdown()
        let undo = try #require(controller.editorTextView.undoManager)
        undo.undo()
        #expect(controller.serializedEditorMarkdown() == before)
        #expect(controller.editorTextView.selectedRange().location == last.location)
        undo.redo()
        #expect(controller.serializedEditorMarkdown() == appended)
        let left = try #require(tableCellRange(row: 0, column: 0, in: controller.editorTextView.attributedString()))
        #expect(controller.deleteMarkdownTableColumnForLibrary(atCharacterIndex: left.location))
        #expect(controller.serializedEditorMarkdown().contains("| :---: | ---: |"))
        undo.undo()
        controller.toggleEditorSourceModePressed()
        let sourcePosition = (controller.editorTextView.string as NSString).range(of: "Center").location
        #expect(controller.insertMarkdownTableColumnForLibrary(atCharacterIndex: sourcePosition))
        #expect(controller.editorTextView.string.contains("| :--- | :---: | --- | ---: |"))
        #expect(controller.editorTextView.string.contains("a\\|b"))
        #expect(controller.editorTextView.attributedString().attribute(.qmTableID, at: sourcePosition, effectiveRange: nil) == nil)
        #expect(try controller.saveCurrentNoteForLibrary() == url)
        #expect(try harness.store.loadNote(at: url).body.contains("| :--- | :---: | --- | ---: |"))
    }

    @Test func roundTwoInventoryProtectsAllSupportedTargetsAndNeverOpensSyntheticSourcePaths() throws {
        let harness = try makeEditorControllerHarness(draftID: "round-two-inventory", showsSaveButton: false)
        defer { harness.tearDown() }
        let root = harness.store.notesDirectory, attachments = root.appendingPathComponent("Attachments")
        try FileManager.default.createDirectory(at: attachments, withIntermediateDirectories: true)
        for name in ["spec.md", "embed.md", "a(b).png", "ref.png", "draft.png", "unused.png"] {
            try Data([1]).write(to: attachments.appendingPathComponent(name))
        }
        let markdown = #"[[Attachments/spec|Alias]] ![[Attachments/embed]] ![x](Attachments/a\(b\).png "a)b")"#
            + "\n![Reference][image]\n[image]: Attachments/ref.png\n`![Code](Attachments/unused.png)`"
        try markdown.write(to: root.appendingPathComponent("Note.md"), atomically: true, encoding: .utf8)
        try harness.store.saveDraft(DraftSnapshot(id: "new-protected", sourcePath: nil, selectedDirectoryPath: root.path,
            title: "Draft", body: "![draft](Attachments/draft.png)", tags: [], updatedAt: Date()))
        let items = LibraryAttachmentInventory.build(roots: [root], noteStore: harness.store)
        #expect(items.filter { $0.state == .referenced }.count == 5)
        #expect(items.first { $0.filename == "unused.png" }?.state == .unreferenced)
        let draft = try #require(items.first { $0.filename == "draft.png" })
        #expect(draft.referencingNotes.isEmpty)
        #expect(draft.protectedSources.map(\.kind) == [.draft])
        let controller = LibraryAttachmentManagerWindowController(rootsProvider: { [root] }, onOpenNote: { _ in Issue.record("Opened a synthetic draft path") })
        defer { controller.close() }
        controller.loadAttachmentItemsForTesting([draft]); controller.selectAttachmentForTesting(at: 0)
        #expect(!controller.canOpenSelectedAttachmentSourceForTesting)
        let incomplete = LibraryAttachmentInventory.build(roots: [root, harness.root.appendingPathComponent("Unavailable")])
        #expect(incomplete.first { $0.filename == "unused.png" }?.state == .unknown)
    }

    @Test func roundTwoAttachmentScanOwnsCancellationSelectionDeletionAndFailureState() async throws {
        let harness = try makeEditorControllerHarness(draftID: "round-two-scan", showsSaveButton: false)
        defer { harness.tearDown() }
        let file = harness.root.appendingPathComponent("synthetic-unused.png")
        try Data([1]).write(to: file)
        let item = LibraryAttachmentItem(url: file, state: .unreferenced, byteCount: 1, referencingNotes: [])
        let probe = RoundTwoScanProbe(item: item)
        let controller = LibraryAttachmentManagerWindowController(rootsProvider: { [harness.root] },
            inventoryLoader: { _ in LibraryAttachmentScan(items: try probe.load()) }, removeAttachment: { try FileManager.default.removeItem(at: $0) }, onOpenNote: { _ in })
        defer { controller.close() }
        controller.loadAttachmentItemsForTesting([item]); controller.selectAttachmentForTesting(at: 0)
        controller.refreshAttachmentInventoryForTesting()
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while probe.calls == 0 { try #require(ContinuousClock.now < deadline); await Task.yield() }
        controller.refreshAttachmentInventoryForTesting()
        await controller.waitForAttachmentInventoryForTesting()
        #expect(controller.selectedAttachmentPathForTesting == file.path)
        while probe.cancellations == 0 { try #require(ContinuousClock.now < deadline); await Task.yield() }
        #expect(probe.cancellations == 1)
        #expect(!probe.observedMainThread)
        let callsBeforeDelete = probe.calls
        controller.deleteSelectedAttachmentForTesting()
        await controller.waitForAttachmentInventoryForTesting()
        #expect(probe.calls == callsBeforeDelete + 1)
        #expect(controller.attachmentItemsForTesting.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        probe.fail()
        controller.refreshAttachmentInventoryForTesting()
        await controller.waitForAttachmentInventoryForTesting()
        #expect(controller.attachmentSummaryForTesting == "扫描失败，请重试")
        #expect(!controller.showsEmptyAttachmentMessageForTesting)
        let unavailable = LibraryAttachmentManagerWindowController(
            rootsProvider: { [harness.root.appendingPathComponent("Unavailable")] }, onOpenNote: { _ in })
        defer { unavailable.close() }
        unavailable.refreshAttachmentInventoryForTesting()
        await unavailable.waitForAttachmentInventoryForTesting()
        #expect(unavailable.attachmentSummaryForTesting.contains("引用扫描不完整"))
        #expect(!unavailable.showsEmptyAttachmentMessageForTesting)
    }
}

private final class RoundTwoScanProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let item: LibraryAttachmentItem
    private var count = 0, cancelled = 0
    private var main = false, fails = false
    init(item: LibraryAttachmentItem) { self.item = item }
    var calls: Int { lock.lock(); defer { lock.unlock() }; return count }
    var cancellations: Int { lock.lock(); defer { lock.unlock() }; return cancelled }
    var observedMainThread: Bool { lock.lock(); defer { lock.unlock() }; return main }
    func fail() { lock.lock(); fails = true; lock.unlock() }
    func load() throws -> [LibraryAttachmentItem] {
        lock.lock(); count += 1; let call = count; let shouldFail = fails
        main = main || Thread.isMainThread; lock.unlock()
        if shouldFail { throw CocoaError(.fileReadNoPermission) }
        if call == 1 {
            let deadline = Date().addingTimeInterval(3)
            while !Task.isCancelled, Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
            if Task.isCancelled { lock.lock(); cancelled += 1; lock.unlock(); throw CancellationError() }
        }
        return [item]
    }
}
