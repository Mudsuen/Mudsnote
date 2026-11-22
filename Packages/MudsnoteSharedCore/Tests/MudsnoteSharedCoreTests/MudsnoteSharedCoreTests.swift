import Foundation
import Testing
@testable import MudsnoteSharedCore

@Suite("MudsnoteSharedCore")
struct MudsnoteSharedCoreTests {
    @Test
    func yamlTagsNeverEmitHashCommentsAndReadLegacyHashTags() {
        let updated = MarkdownTagContract.replacingFrontMatterTags(
            in: "# Heading\n\nBody\n",
            with: ["#launch", "area/topic"],
            strict: true
        )
        #expect(updated == "---\ntags:\n  - launch\n  - area/topic\n---\n\n# Heading\n\nBody\n")

        let legacyMarkdown = "---\ntags:\n  - #launch\n  - \"#area/topic\"\n  - work\n---\n\nBody"
        #expect(MarkdownTagContract.frontMatterBareTags(in: legacyMarkdown, strict: true) == ["launch", "area/topic", "work"])
    }

    @Test
    func inlineTagExtractionIgnoresHexColorsNumbersAndCode() {
        let body = """
        Color #ff00aa and #abc123 and issue #123 and code `#notatag`
        ```css
        color: #project;
        ```
        Real tags #project and #area/topic
        """
        let extracted = MarkdownTagContract.extractingInlineTags(from: body)
        #expect(extracted.bareTags == ["project", "area/topic"])
        #expect(extracted.occurrenceCount == 2)
        #expect(extracted.body.contains("#ff00aa"))
        #expect(extracted.body.contains("#123"))
        #expect(extracted.body.contains("`#notatag`"))
    }

    @Test
    func attachmentRelativePathHandlesNestedFoldersAndLegacyFallback() throws {
        let dest = MarkdownAttachmentContract.relativeMarkdownDestination(
            attachmentRelativeToRoot: "Attachments/2026/06/hero photo.png",
            noteRelativeToRoot: "Work/Sub/plan.md"
        )
        #expect(dest == "../../Attachments/2026/06/hero%20photo.png")
        #expect(
            MarkdownAttachmentContract.normalizeVaultRelativePath(
                from: dest,
                noteRelativeToRoot: "Work/Sub/plan.md"
            ) == "Attachments/2026/06/hero photo.png"
        )
        #expect(
            MarkdownAttachmentContract.normalizeVaultRelativePath(
                from: "Attachments/2026/06/hero photo.png",
                noteRelativeToRoot: "Work/Sub/plan.md"
            ) == "Attachments/2026/06/hero photo.png"
        )

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-shared-attach-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let noteURL = root.appendingPathComponent("Work/Sub/plan.md")
        let attachURL = root.appendingPathComponent("Attachments/2026/06/hero photo.png")
        try FileManager.default.createDirectory(at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: attachURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("png".utf8).write(to: attachURL)

        let resolvedRelative = MarkdownAttachmentContract.resolveAttachmentURL(
            rawDestination: dest,
            noteURL: noteURL,
            libraryRoot: root
        )
        #expect(resolvedRelative?.standardizedFileURL.path == attachURL.resolvingSymlinksInPath().standardizedFileURL.path)

        let resolvedLegacy = MarkdownAttachmentContract.resolveAttachmentURL(
            rawDestination: "Attachments/2026/06/hero photo.png",
            noteURL: noteURL,
            libraryRoot: root
        )
        #expect(resolvedLegacy?.standardizedFileURL.path == attachURL.resolvingSymlinksInPath().standardizedFileURL.path)
    }

    @Test
    func derivedTitlePreservesVersionsNodeJSAndURLs() {
        #expect(MarkdownConflictContract.derivedTitle(fromFirstLine: "v1.2.3 发布说明") == "v1.2.3 发布说明")
        #expect(MarkdownConflictContract.derivedTitle(fromFirstLine: "Node.js 性能调优") == "Node.js 性能调优")
        #expect(MarkdownConflictContract.derivedTitle(fromFirstLine: "https://example.com/docs/guide") == "example.com/docs/guide")
        #expect(MarkdownConflictContract.derivedTitle(fromFirstLine: "First sentence. Second sentence.") == "First sentence")
    }

    @Test
    func sqliteFTSIndexSupportsIncrementalUpsertDeleteAndCJKSearch() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-sqlite-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("index.sqlite")
        let index = SQLiteFTSNoteIndex(databaseURL: dbURL)

        let r1 = SQLiteNoteIndexRecord(
            path: "/vault/a.md",
            modifiedAt: 100,
            createdAt: 90,
            fileSize: 42,
            title: "苹果架构设计",
            body: "深度学习与增量索引优化",
            snippet: "深度学习与增量索引优化",
            tags: ["architecture", "ios"]
        )
        let r2 = SQLiteNoteIndexRecord(
            path: "/vault/b.md",
            modifiedAt: 200,
            createdAt: 190,
            fileSize: 55,
            title: "Swift Concurrency",
            body: "Observable fine-grained state updates",
            snippet: "Observable",
            tags: ["swift"]
        )
        #expect(index.replaceAll(rootsKey: ["/vault"], records: [r1, r2]))
        #expect(index.loadAll(expectedRootsKey: ["/vault"])?.count == 2)

        let cjkHits = try #require(index.search(query: "增量索引"))
        #expect(cjkHits.map(\.path) == ["/vault/a.md"])

        let shortCJK = try #require(index.search(query: "苹果"))
        #expect(shortCJK.map(\.path) == ["/vault/a.md"])

        let updatedR2 = SQLiteNoteIndexRecord(
            path: "/vault/b.md",
            modifiedAt: 250,
            createdAt: 190,
            fileSize: 60,
            title: "Swift Concurrency",
            body: "Replaced content with SQLite FTS5",
            snippet: "SQLite FTS5",
            tags: ["swift", "sqlite"]
        )
        #expect(index.applyIncrementalChanges(rootsKey: ["/vault"], upserts: [updatedR2], deletes: ["/vault/a.md"]))
        #expect(index.loadAll(expectedRootsKey: ["/vault"])?.map(\.path) == ["/vault/b.md"])
        #expect(index.search(query: "增量索引")?.isEmpty == true)
        #expect(index.search(query: "SQLite FTS5")?.map(\.path) == ["/vault/b.md"])
    }

    @Test
    func vaultMetadataManifestRoundTripsWithCoordination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mudsnote-manifest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let manifest = VaultMetadataManifest(
            pinnedRelativePaths: ["Work/Plan.md", "Inbox.md"],
            folderOrder: ["Work", "Personal"],
            folderIcons: ["Work": "briefcase"]
        )
        try VaultMetadataManifest.save(manifest, in: root)
        let loaded = try #require(VaultMetadataManifest.load(in: root))
        #expect(loaded.pinnedRelativePaths == ["Work/Plan.md", "Inbox.md"])
        #expect(loaded.folderOrder == ["Work", "Personal"])
        #expect(loaded.folderIcons == ["Work": "briefcase"])
    }
}
