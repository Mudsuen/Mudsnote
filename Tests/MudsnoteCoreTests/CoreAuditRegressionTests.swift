import Foundation
import Testing
@testable import MudsnoteCore

struct CoreAuditRegressionTests {
    private func makeStore() throws -> (store: NoteStore, root: URL, cleanup: () -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-core-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "mudsnote.core-audit.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let notesDir = root.appendingPathComponent("Notes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let store = NoteStore(
            defaults: defaults,
            legacyDefaults: nil,
            appSupportDirectory: root.appendingPathComponent("Support", isDirectory: true)
        )
        store.notesDirectory = notesDir
        return (store, root, {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        })
    }

    @Test func renameAndDeleteTagPreserveTrailingSharpInTagNames() throws {
        let env = try makeStore()
        defer { env.cleanup() }
        let noteURL = try env.store.saveNewNote(title: "Sharp", body: "Body", tags: ["C#", "C"])

        let renamedCount = try env.store.renameTag("C#", to: "F#")
        #expect(renamedCount == 1)
        #expect(try env.store.loadNote(at: noteURL).tags == ["F#", "C"])

        let deletedCount = try env.store.deleteTag("F#")
        #expect(deletedCount == 1)
        #expect(try env.store.loadNote(at: noteURL).tags == ["C"])
    }

    @Test func sameDirectoryRenamePreservesUnchangedOutgoingWikiLinks() throws {
        let env = try makeStore()
        defer { env.cleanup() }
        _ = try env.store.saveNewNote(title: "Other Note", body: "Target body")
        let sourceURL = env.store.notesDirectory.appendingPathComponent("Source.md")
        try "# Source\n\nSee [[Other Note]] for details.\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let renamed = try env.store.updateNote(at: sourceURL, title: "Renamed Source", body: "See [[Other Note]] for details.")
        let contents = try String(contentsOf: renamed, encoding: .utf8)
        #expect(contents.contains("[[Other Note]]"))
        #expect(!contents.contains("%20"))
    }

    @Test func moveFolderIntoSelfIsSafeNoOp() throws {
        let env = try makeStore()
        defer { env.cleanup() }
        let folder = try env.store.createFolder(named: "SelfMove", in: env.store.notesDirectory)
        let noteURL = try env.store.saveNewNote(title: "Inside", body: "Keep", in: folder)

        let moved = try env.store.moveFolder(at: folder, to: folder)
        #expect(moved == folder.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: noteURL.path))
    }

    @Test func isArchivedNoteIgnoresAncestorArchiveDirectoriesAboveLibraryRoot() throws {
        let env = try makeStore()
        defer { env.cleanup() }
        let archivedRoot = env.root.appendingPathComponent("Archive/LibraryNotes", isDirectory: true)
        try FileManager.default.createDirectory(at: archivedRoot, withIntermediateDirectories: true)
        env.store.configurePreferredDirectories([archivedRoot], defaultDirectory: archivedRoot)

        let activeNote = archivedRoot.appendingPathComponent("Work/active.md")
        let nestedArchiveNote = archivedRoot.appendingPathComponent("Archive/old.md")
        #expect(!env.store.isArchivedNote(at: activeNote))
        #expect(env.store.isArchivedNote(at: nestedArchiveNote))
    }

    @Test func cjkAdjacentPunctuationDoesNotCreateMandatoryLiteralTerms() {
        let query = NoteSearchQuery("苹果，香蕉(测试)")
        #expect(query.terms == ["苹果", "香蕉", "测试"])
        #expect(query.matches(title: "测试清单", body: "苹果和香蕉都在这里", tags: []))
    }

    @Test func aiMemorySyncIgnoresTimestampOnlyDiffAndFencedCodeHeadings() throws {
        let env = try makeStore()
        defer { env.cleanup() }
        let memoryDir = env.root.appendingPathComponent("Memory", isDirectory: true)
        try FileManager.default.createDirectory(at: memoryDir, withIntermediateDirectories: true)
        let memory = """
        ## Mudsnote Architecture

        ```bash
        # shell comment that is not a heading
        echo hello
        ```

        Keep local Markdown files.

        ## Unrelated Project

        Should not appear.
        """
        try memory.write(to: memoryDir.appendingPathComponent("MEMORY.md"), atomically: true, encoding: .utf8)

        let service = AIMemorySyncService(memoryDirectory: memoryDir, destinationRoot: env.store.notesDirectory)
        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let day2 = day1.addingTimeInterval(86_400)

        let first = try service.sync(lastSyncDate: nil, now: day1, force: false)
        let second = try service.sync(lastSyncDate: day1, now: day2, force: true)
        let contents = try String(contentsOf: first.destinationURL, encoding: .utf8)

        #expect(first.didWrite)
        #expect(!second.didWrite)
        #expect(contents.contains("Keep local Markdown files."))
        #expect(!contents.contains("Should not appear."))
    }

    @Test func codexRuntimeLocatorRejectsDirectoryNamedCodex() throws {
        let env = try makeStore()
        defer { env.cleanup() }
        let fakeDir = env.root.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeDir, withIntermediateDirectories: true)

        #expect(CodexRuntimeLocator.resolve(configuredPath: fakeDir.path, environmentPath: nil, homeDirectory: env.root.path) == nil)
    }

    @Test func noteOverviewRemapStandardizesAndDeduplicatesCards() {
        let oldURL = URL(fileURLWithPath: "/tmp/Notes/Old.md")
        let newURL = URL(fileURLWithPath: "/tmp/Notes/New.md")
        var overview = NoteOverview()
        let oldID = overview.add(oldURL)
        let newID = overview.add(newURL)
        let peerID = overview.add(URL(fileURLWithPath: "/tmp/Notes/Peer.md"))
        overview.connect(oldID, peerID)

        overview.remap(oldURL, to: newURL)
        #expect(overview.cards.filter { $0.url.standardizedFileURL == newURL.standardizedFileURL }.count == 1)
        #expect(overview.connections == [NoteOverview.Connection(from: newID, to: peerID)])
    }
}
