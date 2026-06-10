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
        """

        let blocks = InboxParser.parse(markdown)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks.first?.dateText, "2026-06-07 14:35")
        XCTAssertEqual(blocks.last?.tags, ["#闪念"])
    }
}
