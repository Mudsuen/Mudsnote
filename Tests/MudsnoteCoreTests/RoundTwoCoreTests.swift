import Darwin
import Foundation
import Testing
@testable import MudsnoteCore

struct RoundTwoCoreTests {
    @Test func rawDiskIndentationAndExistingFilenameSurviveBodyAndTagUpdates() throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        for (index, indent) in ["    ", "\t"].enumerated() {
            let editorBody = "\(indent)let first = 1\n\(indent)let second = 2\n\nTail  "
            let editorText = MarkdownEditorDocument.composeEditorText(title: "Demo", body: editorBody)
            #expect(MarkdownEditorDocument.parse(editorText: editorText).body == editorBody)
            let url = try fixture.write("2020-02-03-demo-\(index + 2).markdown",
                "# Demo\n\n\(indent)let first = 1\n\(indent)let second = 2\n\nTail\n")
            let loaded = try fixture.store.loadNoteDocument(at: url)
            #expect(loaded.body.hasPrefix(indent + "let first"))
            let saved = try fixture.store.updateNote(at: url, title: loaded.title,
                body: loaded.body.replacingOccurrences(of: "Tail", with: "Edited tail"), tags: ["review"],
                expectedContents: loaded.sourceContents, updatesInPlace: false)
            #expect(saved.url == url)
            let reopened = try fixture.store.loadNoteDocument(at: saved.url)
            #expect(reopened.body.hasPrefix(indent + "let first"))
            #expect(reopened.body.contains("\n" + indent + "let second"))
            #expect(reopened.tags == ["review"])
            #expect(try fixture.store.updateNote(at: url, title: loaded.title, body: reopened.body, tags: ["tag-only"]) == url)
        }
        for (index, content) in ["Untitled body", "# !!!\n\nPunctuation body"].enumerated() {
            let url = try fixture.write("2020-01-01-note-old-\(index)-2.md", content)
            let loaded = try fixture.store.loadNote(at: url)
            #expect(try fixture.store.updateNote(at: url, title: loaded.title, body: loaded.body + "\nChanged") == url)
        }
    }

    @Test func lexicalDestinationsRetainImagesEmbedsDefinitionsAndExactRanges() throws {
        let markdown = #"![x](Attachments/a\(b\).png "a)b") [[Attachments/spec|Alias]] ![[Attachments/embed]]"#
            + "\n![reference][image]\n[image]: <Attachments/ref.png> \"title )\"\n"
            + "`![code](Attachments/code.png)`\n```md\n[[Attachments/fenced]]\n```"
        let references = MarkdownNoteReferenceParser.destinations(in: markdown)
        #expect(references.map(\.destination) == ["Attachments/a(b).png", "Attachments/spec", "Attachments/embed", "Attachments/ref.png"])
        #expect(references.map(\.isEmbedded) == [true, false, true, false])
        #expect(references.last?.isDefinition == true)
        #expect(MarkdownNoteReferenceParser.references(in: markdown).map(\.destination) == ["Attachments/spec"])
        #expect((markdown as NSString).substring(with: try #require(references.first).destinationRange) == #"Attachments/a\(b\).png"#)
    }

    @Test func attachmentRelocationRewritesOnlyLiveDestinationRanges() throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        let image = try fixture.write("Attachments/photo(1).png", "original image")
        _ = try fixture.write("Moved/Attachments/photo(1).png", "existing different image")
        let body = #"![Preview](Attachments/photo(1).png?size=2#part "title )")"#
            + "\n![Ref][image]\n[image]: <Attachments/photo(1).png> \"reference title\"\n"
            + "`![Literal](Attachments/photo(1).png)`\n```md\n![Code](Attachments/photo(1).png)\n```"
        let note = try fixture.write("A.md", body)
        let moved = try fixture.store.moveNote(at: note, to: fixture.root.appendingPathComponent("Moved"))
        let text = try String(contentsOf: moved, encoding: .utf8)
        #expect(text.contains(#"![Preview](Attachments/photo%281%29-2.png?size=2#part "title )")"#))
        #expect(text.contains(#"[image]: <Attachments/photo%281%29-2.png> "reference title""#))
        #expect(text.contains("`![Literal](Attachments/photo(1).png)`"))
        #expect(text.contains("```md\n![Code](Attachments/photo(1).png)\n```"))
        #expect(try String(contentsOf: image, encoding: .utf8) == "original image")
    }

    @Test func recoveringTwoNotesReusesTheirRestoredAttachmentWithoutOverwritingACollision() throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        let body = #"![P](Attachments/p.png?size=2#part "title )")"#
        _ = try fixture.write("Project/A.md", body)
        _ = try fixture.write("Project/B.md", body)
        _ = try fixture.write("Project/Attachments/p.png", "shared original")
        let trash = try fixture.store.trashFolder(at: fixture.root.appendingPathComponent("Project"))
        let collision = try fixture.write("Project/Attachments/p.png", "existing different image")
        let restoredA = try fixture.store.restoreTrashedNote(at: trash.appendingPathComponent("A.md"))
        #expect(try String(contentsOf: restoredA, encoding: .utf8).contains("Attachments/p-2.png?size=2#part"))
        #expect(FileManager.default.fileExists(atPath: trash.appendingPathComponent("Attachments/p.png").path))
        let restoredB = try fixture.store.restoreTrashedNote(at: trash.appendingPathComponent("B.md"))
        #expect(try String(contentsOf: restoredB, encoding: .utf8) == String(contentsOf: restoredA, encoding: .utf8))
        #expect(try String(contentsOf: collision, encoding: .utf8) == "existing different image")
        #expect(try String(contentsOf: fixture.root.appendingPathComponent("Project/Attachments/p-2.png"), encoding: .utf8) == "shared original")
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Project/Attachments/p-3.png").path))
    }

    @Test func failedNestedRestoreRemovesOnlyItsCreatedSiblingAttachments() throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        let body = "![new](../Attachments/new.png)\n![shared](../Attachments/shared.png)\n![collision](../Attachments/collision.png)"
        _ = try fixture.write("Project/Nested/A.md", body)
        for name in ["new", "shared", "collision"] { _ = try fixture.write("Project/Attachments/\(name).png", "original \(name)") }
        let trash = try fixture.store.trashFolder(at: fixture.root.appendingPathComponent("Project"))
        let shared = try fixture.write("Project/Attachments/shared.png", "original shared")
        let collision = try fixture.write("Project/Attachments/collision.png", "existing different")
        fixture.store.updateNoteCommitHook = { checkpoint in
            if checkpoint == .afterDestinationCommit { throw CocoaError(.fileWriteUnknown) }
        }
        #expect(throws: CocoaError.self) { try fixture.store.restoreTrashedNote(at: trash.appendingPathComponent("Nested/A.md")) }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Project/Nested/A.md").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Project/Attachments/new.png").path))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("Project/Attachments/collision-2.png").path))
        #expect(try String(contentsOf: shared, encoding: .utf8) == "original shared")
        #expect(try String(contentsOf: collision, encoding: .utf8) == "existing different")
        #expect(try String(contentsOf: trash.appendingPathComponent("Nested/A.md"), encoding: .utf8) == body)
        for name in ["new", "shared", "collision"] {
            #expect(try String(contentsOf: trash.appendingPathComponent("Attachments/\(name).png"), encoding: .utf8) == "original \(name)")
        }
    }

    @Test func invalidExplicitCodexPathDoesNotDiscoverAnotherExecutable() throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        let executable = try fixture.write("bin/codex", "#!/bin/sh\nexit 0\n")
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        #expect(CodexRuntimeLocator.resolve(configuredPath: fixture.root.appendingPathComponent("missing").path,
            environmentPath: executable.deletingLastPathComponent().path, homeDirectory: fixture.container.path) == nil)
        #expect(CodexRuntimeLocator.resolve(configuredPath: executable.path,
            environmentPath: nil, homeDirectory: fixture.container.path) == executable)
    }

    @Test func ownedChildCancellationHandlesUnreadInputAndIgnoredTermination() async throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        let script = try fixture.write("child.py", """
        import os, signal, time
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        open('ready', 'w').write(str(os.getpid()))
        time.sleep(60)
        """)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [script.path]
        process.currentDirectoryURL = fixture.root
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let task = Task { try await CodexProcessExecution.runPrepared(process,
            prompt: String(repeating: "large synthetic input\n", count: 300_000), workingDirectory: fixture.root,
            terminationGrace: .milliseconds(100)) }
        defer { task.cancel(); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        let launchDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("ready").path) {
            try #require(ContinuousClock.now < launchDeadline)
            try await Task.sleep(for: .milliseconds(10))
        }
        let started = ContinuousClock.now
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        defer { watchdog.cancel() }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled child returned success") }
        catch is CancellationError {} catch { Issue.record("Unexpected cancellation error: \(error)") }
        #expect(started.duration(to: .now) < .seconds(1))
        #expect(!process.isRunning)
        #expect(try !FileManager.default.contentsOfDirectory(atPath: fixture.root.path).contains { $0.hasPrefix("mudsnote-input-") })
    }

    @Test @MainActor func cancellationBeforePreparedLaunchCreatesNoChild() async throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        let task = Task { try await CodexProcessExecution.runPrepared(process, prompt: "synthetic", workingDirectory: fixture.root) }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled launch succeeded") } catch is CancellationError {}
        #expect(!process.isRunning)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).isEmpty)
    }

    @Test func preparedInputFileDeliversUnicodeWithoutCredentialPreparation() async throws {
        let fixture = try RoundTwoStoreFixture()
        defer { fixture.remove() }
        let outputURL = fixture.root.appendingPathComponent("received.txt")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        process.environment = [:]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let prompt = String(repeating: "Synthetic 汉字🙂\n", count: 4_000)
        #expect(try await CodexProcessExecution.runPrepared(process, prompt: prompt, workingDirectory: fixture.root) == 0)
        #expect(try String(contentsOf: outputURL, encoding: .utf8) == prompt)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent(".codex").path))
    }
}

private final class RoundTwoStoreFixture: @unchecked Sendable {
    let container: URL, root: URL, store: NoteStore
    let defaults: UserDefaults
    let suite = "mudsnote.round-two-core.\(UUID().uuidString)"
    init() throws {
        container = FileManager.default.temporaryDirectory.appendingPathComponent("mudsnote-round-two-\(UUID().uuidString)")
        root = container.appendingPathComponent("Notes")
        defaults = try #require(UserDefaults(suiteName: suite))
        store = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: container.appendingPathComponent("Support"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store.configurePreferredDirectories([root], defaultDirectory: root)
    }
    func write(_ path: String, _ text: String) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    func remove() { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: container) }
}
