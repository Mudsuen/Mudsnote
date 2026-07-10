import XCTest
@testable import MudsnoteCompanion

final class MudsnoteCompanionTests: XCTestCase {
    func testMarkdownBlockFormat() {
        let date = Date(timeIntervalSince1970: 1_717_747_920)
        let block = MarkdownFileStore.markdownBlock(
            body: "把 iCloud 文件夹作为唯一数据源。",
            tags: "#闪念",
            attachmentReferences: [
                MarkdownAttachmentReference(relativePath: "Attachments/2026/06/IMG-test.jpg", kind: .image),
                MarkdownAttachmentReference(relativePath: "Attachments/2026/06/audio-test.m4a", kind: .audio)
            ],
            attachmentTags: ["#图片"],
            now: date
        )

        XCTAssertTrue(block.contains("## 2024-06-07"))
        XCTAssertTrue(block.contains("![Image](Attachments/2026/06/IMG-test.jpg)"))
        XCTAssertTrue(block.contains("[Audio](Attachments/2026/06/audio-test.m4a)"))
        XCTAssertTrue(block.contains("#闪念 #图片"))
    }

    func testInboxParserFindsMemoBlocks() {
        let markdown = """
        # Inbox

        ## 2026-06-07 14:32

        第一条

        #闪念

        ## 2026-06-07 14:35

        ![Image](Attachments/2026/06/IMG.jpg)

        #图片

        <!-- mudsnote-write:1e989c6a-2aae-47c5-a8e7-4c7d854cb2d8 -->
        """

        let blocks = InboxParser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.first?.dateText, "2026-06-07 14:35")
        XCTAssertFalse(blocks.first?.body.contains("mudsnote-write") ?? true)
        XCTAssertEqual(
            blocks.first?.writeMarker,
            "<!-- mudsnote-write:1e989c6a-2aae-47c5-a8e7-4c7d854cb2d8 -->"
        )
        XCTAssertEqual(blocks.last?.tags, ["#闪念"])
    }

    @MainActor
    func testInboxRewritePreservesHiddenWriteMarker() {
        let marker = "<!-- mudsnote-write:1e989c6a-2aae-47c5-a8e7-4c7d854cb2d8 -->"
        let memo = MemoBlock(
            id: "memo",
            dateText: "2026-06-07 14:35",
            body: "Visible body",
            tags: [],
            writeMarker: marker
        )

        let rewritten = AppModel.inboxMarkdown(forDisplayItems: [memo])
        XCTAssertTrue(rewritten.contains(marker))
        let reparsed = InboxParser.parse(rewritten)
        XCTAssertEqual(reparsed.first?.body, "Visible body")
        XCTAssertEqual(reparsed.first?.writeMarker, marker)
    }

    func testCaptureTargetRelativePaths() {
        let date = Date(timeIntervalSince1970: 1_717_747_920)

        XCTAssertEqual(CaptureTarget.inbox.relativePath(now: date), "Inbox.md")
        XCTAssertEqual(CaptureTarget.daily(date).relativePath(now: date), "Daily/2024-06-07.md")
        XCTAssertEqual(CaptureTarget.recent("Projects/Launch.md").relativePath(now: date), "Projects/Launch.md")
    }

    func testAttachmentOnlyDraftCanSend() {
        let draft = CaptureDraft(
            body: "",
            attachments: [.image(data: Data([0x01, 0x02]), preferredExtension: "jpg")]
        )

        XCTAssertTrue(draft.canSend)
    }

    func testPendingQueueRoundTripsISO8601Dates() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".mudsnote"),
            withIntermediateDirectories: true
        )

        let pending = PendingWrite(
            id: UUID(uuidString: "B7586F89-FD45-4E9B-BF3F-2FEC138D9A28")!,
            createdAt: Date(timeIntervalSince1970: 1_717_747_920),
            targetRelativePath: "Inbox.md",
            markdownBlock: "\n## 2024-06-07 12:12\n\nRecover me\n\n",
            attachments: []
        )
        let firstQueue = PendingWriteQueue(root: root)
        try await firstQueue.load()
        try await firstQueue.enqueue(pending)

        let restoredQueue = PendingWriteQueue(root: root)
        try await restoredQueue.load()
        let restoredCount = await restoredQueue.pendingCount()
        XCTAssertEqual(restoredCount, 1)
    }

    func testPendingWriteIsIdempotentAcrossReplay() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        let pending = PendingWrite(
            id: UUID(uuidString: "1E989C6A-2AAE-47C5-A8E7-4C7D854CB2D8")!,
            createdAt: Date(timeIntervalSince1970: 1_717_747_920),
            targetRelativePath: "Inbox.md",
            markdownBlock: "\n## 2024-06-07 12:12\n\nWrite once\n\n",
            attachments: []
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)

        try await store.performPendingWrite(pending)
        try await store.performPendingWrite(pending)

        let markdown = try String(contentsOf: root.appendingPathComponent("Inbox.md"), encoding: .utf8)
        XCTAssertEqual(markdown.components(separatedBy: "Write once").count - 1, 1)
        XCTAssertEqual(markdown.components(separatedBy: "mudsnote-write:").count - 1, 1)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MudsnoteCompanionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
