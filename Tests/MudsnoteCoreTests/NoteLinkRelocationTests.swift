import Foundation
import Testing
@testable import MudsnoteCore

struct NoteLinkRelocationTests {
    @Test func concurrentMovesKeepBothDirectionsAndDoNotDeadlock() async throws {
        let fixture = try LinkRelocationFixture()
        let first = try fixture.note("A.md", "[B](B.md)")
        let second = try fixture.note("B.md", "[A](A.md)")
        let store = fixture.store
        let firstFolder = fixture.root.appendingPathComponent("One")
        let secondFolder = fixture.root.appendingPathComponent("Two")
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask { try store.moveNote(at: first, to: firstFolder) }
            group.addTask { try store.moveNote(at: second, to: secondFolder) }
            for try await _ in group {}
        }
        #expect(try fixture.read(firstFolder.appendingPathComponent("A.md")) == "[B](../Two/B.md)")
        #expect(try fixture.read(secondFolder.appendingPathComponent("B.md")) == "[A](../One/A.md)")
    }

    @Test func wikiAttachmentsAndDottedNamesKeepTheirIdentity() throws {
        let fixture = try LinkRelocationFixture()
        _ = try fixture.note("Attachments/spec.md", "# Spec")
        let dotted = try fixture.note("Target.v1.md", "# Versioned")
        let plain = try fixture.note("Target.md", "# Other")
        let source = try fixture.note("A.md", "[[Attachments/spec]] [[target.v1]]")
        _ = try fixture.store.moveNote(at: plain, to: fixture.root.appendingPathComponent("Plain"))
        #expect(try fixture.read(source) == "[[Attachments/spec]] [[target.v1]]")
        let moved = try fixture.store.moveNote(at: source, to: fixture.root.appendingPathComponent("Moved"))
        #expect(try fixture.read(moved) == "[[../Attachments/spec.md]] [[../Target.v1.md]]")
        #expect(fixture.store.knowledgeRelations(for: moved).outgoing.contains { $0.url == dotted })
    }

    @Test func movingSourcePreservesRelativeLinksAndFormatting() throws {
        let fixture = try LinkRelocationFixture()
        let target = try fixture.note("目标 笔记.md", "# Target")
        let source = try fixture.note("A.md", #"🙂 [标题 \] 内容](<目标%20笔记.md#小节> "tooltip") [[目标 笔记|别名]] [Web](https://example.com) [Here](#part)"#)
        let moved = try fixture.store.moveNote(at: source, to: fixture.root.appendingPathComponent("Nested"))
        let contents = try fixture.read(moved)
        #expect(contents.contains(#"[标题 \] 内容](<../%E7%9B%AE%E6%A0%87%20%E7%AC%94%E8%AE%B0.md#小节> "tooltip")"#))
        #expect(contents.contains("[[../%E7%9B%AE%E6%A0%87%20%E7%AC%94%E8%AE%B0.md|别名]]"))
        #expect(contents.contains("[Web](https://example.com) [Here](#part)"))
        #expect(fixture.store.knowledgeRelations(for: moved).outgoing.map(\.url) == [target])
    }

    @Test func movingTargetUpdatesIncomingLinksButNotCode() throws {
        let fixture = try LinkRelocationFixture()
        let target = try fixture.note("B.md", "# B")
        let source = try fixture.note("A.md", "[B](B.md#part) [[B|别名]]\n`[Example](B.md)`\n```\n[[B]]\n```")
        let moved = try fixture.store.moveNote(at: target, to: fixture.root.appendingPathComponent("Nested"))
        let contents = try fixture.read(source)
        #expect(contents == "[B](Nested/B.md#part) [[Nested/B.md|别名]]\n`[Example](B.md)`\n```\n[[B]]\n```")
        #expect(fixture.store.knowledgeRelations(for: moved).incoming.map(\.url) == [source])
    }

    @Test func renamingTargetUpdatesUniqueWikiFallbackAndPreservesOtherTitles() throws {
        let fixture = try LinkRelocationFixture()
        let target = try fixture.note("Target.md", "# Target\n\nOld")
        let source = try fixture.note("A.md", "[Original label](Target.md) [[target|alias]] [[OldPrefix/Target]]")
        let renamed = try fixture.store.updateNote(at: target, title: "Renamed", body: "New")
        let contents = try fixture.read(source)
        #expect(contents.contains("[Original label](\(renamed.lastPathComponent))"))
        #expect(contents.contains("[[\(renamed.lastPathComponent)|alias]]"))
        #expect(contents.contains("[[\(renamed.lastPathComponent)]]"))
        #expect(fixture.store.knowledgeRelations(for: source).outgoing.map(\.url) == [renamed])
        #expect(try fixture.store.loadNote(at: renamed).body == "New")
    }

    @Test func duplicateWikiNamesAreNotGuessed() throws {
        let fixture = try LinkRelocationFixture()
        let first = try fixture.note("One/Target.md", "# First")
        _ = try fixture.note("Two/Target.md", "# Second")
        let source = try fixture.note("A.md", "[[Target]] [Explicit](One/Target.md)")
        let moved = try fixture.store.moveNote(at: first, to: fixture.root.appendingPathComponent("Moved"))
        #expect(try fixture.read(source) == "[[Target]] [Explicit](Moved/Target.md)")
        #expect(FileManager.default.fileExists(atPath: moved.path))
    }

    @Test func folderMovesAndRenamesMaintainInternalIncomingAndOutgoingLinks() throws {
        let fixture = try LinkRelocationFixture()
        let outside = try fixture.note("Outside.md", "[Child](Folder/A.md)")
        _ = try fixture.note("Folder/A.md", "[B](B.md) [Outside](../Outside.md)")
        _ = try fixture.note("Folder/B.md", "[A](A.md)")
        let folder = fixture.root.appendingPathComponent("Folder")
        let moved = try fixture.store.moveFolder(at: folder, to: fixture.root.appendingPathComponent("Nested"))
        #expect(try fixture.read(outside) == "[Child](Nested/Folder/A.md)")
        #expect(try fixture.read(moved.appendingPathComponent("A.md")) == "[B](B.md) [Outside](../../Outside.md)")
        let renamed = try fixture.store.renamePreferredDirectory(moved, to: "Renamed")
        #expect(try fixture.read(outside) == "[Child](Nested/Renamed/A.md)")
        #expect(try fixture.read(renamed.appendingPathComponent("B.md")) == "[A](A.md)")
    }

    @Test func registeredOtherLibraryIncomingLinksAreMaintained() throws {
        let fixture = try LinkRelocationFixture()
        let other = fixture.container.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        fixture.store.addPreferredDirectory(other)
        let target = try fixture.note("B.md", "# B")
        let source = other.appendingPathComponent("A.md")
        try "[B](../Notes/B.md)".write(to: source, atomically: true, encoding: .utf8)
        _ = try fixture.store.moveNote(at: target, to: other)
        #expect(try fixture.read(source) == "[B](B.md)")
    }

    @Test func markdownAttachmentCollisionDoesNotGetRelocatedTwice() throws {
        let fixture = try LinkRelocationFixture()
        _ = try fixture.note("Attachments/spec.md", "# Source attachment")
        _ = try fixture.note("Other/Attachments/spec.md", "# Existing attachment")
        let source = try fixture.note("A.md", "[Attachment](Attachments/spec.md)")
        let moved = try fixture.store.moveNote(at: source, to: fixture.root.appendingPathComponent("Other"))
        #expect(try fixture.read(moved) == "[Attachment](Attachments/spec-2.md)")
        #expect(try fixture.read(fixture.root.appendingPathComponent("Other/Attachments/spec-2.md")) == "# Source attachment")
    }

    @Test func movingNoteOnlySkipsMarkdownAttachmentsActuallyCopied() throws {
        let fixture = try LinkRelocationFixture()
        let uncopied = try fixture.note("Attachments/spec(1).md", "# Parenthesized attachment")
        _ = try fixture.note("Attachments/plain.md", "# Copied attachment")
        _ = try fixture.note("Other/Attachments/plain.md", "# Existing attachment")
        let source = try fixture.note("A.md", "[Spec](Attachments/spec(1).md) [Plain](Attachments/plain.md)")

        let moved = try fixture.store.moveNote(at: source, to: fixture.root.appendingPathComponent("Other"))

        #expect(try fixture.read(moved) == "[Spec](../Attachments/spec%281%29.md) [Plain](Attachments/plain-2.md)")
        #expect(try fixture.read(uncopied) == "# Parenthesized attachment")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Other/Attachments/spec(1).md").path))
        #expect(try fixture.read(fixture.root.appendingPathComponent("Other/Attachments/plain-2.md")) == "# Copied attachment")
    }

    @Test func updatingNoteInAnotherFolderOnlySkipsMarkdownAttachmentsActuallyCopied() throws {
        let fixture = try LinkRelocationFixture()
        _ = try fixture.note("Attachments/spec(1).md", "# Parenthesized attachment")
        _ = try fixture.note("Attachments/plain.md", "# Copied attachment")
        _ = try fixture.note("Other/Attachments/plain.md", "# Existing attachment")
        let source = try fixture.note("A.md", "# Original")
        let body = "[Spec](Attachments/spec(1).md#details) [Plain](Attachments/plain.md)"

        let moved = try fixture.store.updateNote(
            at: source, title: "Updated", body: body,
            in: fixture.root.appendingPathComponent("Other")
        )

        #expect(try fixture.store.loadNote(at: moved).body == "[Spec](../Attachments/spec%281%29.md#details) [Plain](Attachments/plain-2.md)")
        #expect(try fixture.read(fixture.root.appendingPathComponent("Other/Attachments/plain-2.md")) == "# Copied attachment")
    }

    @Test func failedMoveRollsBackEveryReferenceAndPreservesSource() throws {
        for checkpoint in [NoteUpdateCommitCheckpoint.afterReferenceWrite, .afterStaging, .afterDestinationCommit] {
            let fixture = try LinkRelocationFixture()
            let target = try fixture.note("B.md", "# Original")
            let source = try fixture.note("A.md", "[B](B.md)")
            fixture.store.updateNoteCommitHook = { if $0 == checkpoint { throw CocoaError(.fileWriteUnknown) } }
            #expect(throws: Error.self) {
                _ = try fixture.store.moveNote(at: target, to: fixture.root.appendingPathComponent("Other"))
            }
            #expect(try fixture.read(source) == "[B](B.md)")
            #expect(try fixture.read(target) == "# Original")
            #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Other/B.md").path))
        }
    }

    @Test func externalSourceEditDuringCommitIsNeverDeleted() throws {
        for checkpoint in [NoteUpdateCommitCheckpoint.afterStaging, .afterDestinationCommit] {
            let fixture = try LinkRelocationFixture()
            let target = try fixture.note("B.md", "# Original")
            let source = try fixture.note("A.md", "[B](B.md)")
            fixture.store.updateNoteCommitHook = {
                if $0 == checkpoint { try "# External".write(to: target, atomically: true, encoding: .utf8) }
            }
            #expect(throws: Error.self) {
                _ = try fixture.store.moveNote(at: target, to: fixture.root.appendingPathComponent("Other"))
            }
            #expect(try fixture.read(target) == "# External")
            #expect(try fixture.read(source) == "[B](B.md)")
            #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Other/B.md").path))
        }
    }

    @Test func failedRollbackRetainsExternalReferenceEditAndOriginalBackup() throws {
        let fixture = try LinkRelocationFixture()
        let target = try fixture.note("B.md", "# Original")
        let source = try fixture.note("A.md", "[B](B.md)")
        fixture.store.updateNoteCommitHook = {
            if $0 == .afterReferenceWrite {
                try "External reference edit".write(to: source, atomically: true, encoding: .utf8)
                throw CocoaError(.fileWriteUnknown)
            }
        }
        #expect(throws: Error.self) {
            _ = try fixture.store.moveNote(at: target, to: fixture.root.appendingPathComponent("Other"))
        }
        #expect(try fixture.read(source) == "External reference edit")
        #expect(try fixture.read(target) == "# Original")
        let backups = try FileManager.default.contentsOfDirectory(
            at: fixture.support.appendingPathComponent("Recovery/LinkUpdates"), includingPropertiesForKeys: nil
        )
        let backup = try #require(backups.first)
        #expect(try fixture.read(backup.appendingPathComponent("0.md")) == "[B](B.md)")
    }

    @Test func failureCleanupDoesNotDeleteExternallyChangedDestination() throws {
        let fixture = try LinkRelocationFixture()
        let target = try fixture.note("B.md", "# Original")
        let destination = fixture.root.appendingPathComponent("Other/B.md")
        fixture.store.updateNoteCommitHook = {
            if $0 == .afterDestinationCommit {
                try "# External destination".write(to: destination, atomically: true, encoding: .utf8)
                throw CocoaError(.fileWriteUnknown)
            }
        }
        #expect(throws: Error.self) {
            _ = try fixture.store.moveNote(at: target, to: destination.deletingLastPathComponent())
        }
        #expect(try fixture.read(target) == "# Original")
        #expect(try fixture.read(destination) == "# External destination")
    }

    @Test func coordinatedTitleUpdateMaintainsLinks() throws {
        let fixture = try LinkRelocationFixture()
        let original = "# B\n\nOriginal"
        let target = try fixture.note("B.md", original)
        let source = try fixture.note("A.md", "[B](B.md)")
        let updated = try fixture.store.updateNote(
            at: target, title: "Renamed", body: "Changed",
            expectedContents: original, updatesInPlace: false
        )
        #expect(try fixture.read(source) == "[B](\(updated.url.lastPathComponent))")
        #expect(try fixture.store.loadNote(at: updated.url).body == "Changed")
    }
}

private final class LinkRelocationFixture {
    let container: URL
    let root: URL
    let support: URL
    let suite: String
    let defaults: UserDefaults
    let store: NoteStore

    init() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("mudsnote-link-move-\(UUID().uuidString)")
        root = container.appendingPathComponent("Notes")
        support = container.appendingPathComponent("Support")
        suite = "mudsnote.link-move-tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: support)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store.configurePreferredDirectories([root], defaultDirectory: root)
    }

    func note(_ path: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    deinit {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: container)
    }
}
