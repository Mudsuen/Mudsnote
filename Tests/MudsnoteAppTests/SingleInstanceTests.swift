import AppKit
import Foundation
@_spi(Testing) import MudsnoteCore
import Testing
@testable import Mudsnote

extension MarkdownRichEditorTests {
    @Test func leaseExcludesConcurrentOwnersAndReleasesOnClose() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var owner: InstanceLease? = try InstanceLease(directory: root)
        #expect(owner?.isOwner == true)
        let contender = try InstanceLease(directory: root)
        #expect(!contender.isOwner)
        owner = nil
        let replacement = try InstanceLease(directory: root)
        #expect(replacement.isOwner)
        withExtendedLifetime((contender, replacement)) {}
    }

    @Test func fixturesRequireFullIsolationAndUseNotesIdentity() throws {
        #expect(throws: (any Error).self) {
            try SingleInstanceCoordinator.coordinationDirectory(arguments: ["--visual-qa-notes-dir", "/tmp/notes"])
        }
        let arguments = ["--visual-qa-notes-dir", "/tmp/notes", "--visual-qa-defaults-suite", "test.notes",
                         "--visual-qa-app-support-dir", "/tmp/support"]
        let first = try SingleInstanceCoordinator.coordinationDirectory(arguments: arguments)
        let sameNotes = try SingleInstanceCoordinator.coordinationDirectory(arguments: arguments + ["--floating-note"])
        let production = try SingleInstanceCoordinator.coordinationDirectory(arguments: [])
        #expect(first == sameNotes)
        #expect(first != production)
        #expect(try SingleInstanceCoordinator.coordinationDirectory(arguments: arguments.map {
            $0 == "/tmp/notes" ? "/tmp/other-notes" : $0
        }) != first)
    }

    @Test func floatingWindowReusesAliasesHiddenWindowsAndCurrentDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "mudsnote.instance-tests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: root.appendingPathComponent("Support"))
        store.notesDirectory = root.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: store.notesDirectory, withIntermediateDirectories: true)
        let first = try store.saveNewNote(title: "First", body: "Fixture body", in: store.notesDirectory)
        let second = try store.saveNewNote(title: "Second", body: "Another fixture", in: store.notesDirectory)
        store.primaryFloatingNoteURL = first
        let app = AppController(noteStore: store, arguments: [])
        var controllers: [EditorWindowController] = []
        defer {
            controllers.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        app.openEditor(for: first)
        let initial = try #require(app.existingFloatingController(for: first))
        controllers.append(initial)
        let alias = root.appendingPathComponent("Alias.md")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: first)
        let hardLink = root.appendingPathComponent("Hard.md")
        try FileManager.default.linkItem(at: first, to: hardLink)
        app.openEditor(for: alias)
        app.openFloatingNote(hardLink, requestedBy: initial)
        #expect(app.existingFloatingController(for: alias) === initial)
        #expect(app.existingFloatingController(for: hardLink) === initial)
        // The shortcut adopts an already-open controller, including a hidden one.
        initial.hideWindowForToggle()
        app.showFloatingNote()
        #expect(app.existingFloatingController(for: first) === initial)
        #expect(initial.window?.isVisible == true)
        app.showFloatingNote()
        #expect(initial.window?.isVisible == false)
        app.showFloatingNote()
        #expect(initial.window?.isVisible == true)
        // A controller's live document identity wins over its original dictionary key.
        initial.loadFloatingNote(at: second)
        app.openEditor(for: second)
        #expect(app.existingFloatingController(for: second) === initial)
        app.openEditor(for: first)
        let reopenedFirst = try #require(app.existingFloatingController(for: first))
        controllers.append(reopenedFirst)
        #expect(reopenedFirst !== initial)
        #expect(app.existingFloatingController(for: second) === initial)
        // Non-primary windows must also stay retained after a document switch;
        // reopening their old path must not overwrite the registry entry.
        let third = try store.saveNewNote(title: "Third", body: "Third fixture", in: store.notesDirectory)
        reopenedFirst.loadFloatingNote(at: third)
        app.openEditor(for: first)
        let anotherFirst = try #require(app.existingFloatingController(for: first))
        controllers.append(anotherFirst)
        #expect(anotherFirst !== reopenedFirst)
        #expect(app.existingFloatingController(for: third) === reopenedFirst)
        initial.close()
        app.openEditor(for: second)
        let replacement = try #require(app.existingFloatingController(for: second))
        controllers.append(replacement)
        #expect(replacement !== initial)
    }
}
