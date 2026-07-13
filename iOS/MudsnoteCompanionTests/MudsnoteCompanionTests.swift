import XCTest
import UIKit
@testable import MudsnoteCompanion

final class MudsnoteCompanionTests: XCTestCase {
    func testAudioCaptureErrorsExplainRecovery() {
        XCTAssertNotNil(AudioCaptureError.microphonePermissionDenied.errorDescription)
        XCTAssertNotNil(AudioCaptureError.couldNotStart.errorDescription)
        XCTAssertNotNil(SpeechTranscriptionError.notAuthorized.errorDescription)
        XCTAssertNotNil(SpeechTranscriptionError.recognizerUnavailable.errorDescription)
        XCTAssertNotNil(SpeechTranscriptionError.timedOut.errorDescription)
    }

    @MainActor
    func testSystemCaptureWaitsForLibraryBeforePresenting() {
        let model = AppModel(bootstrapImmediately: false)
        model.handle(url: URL(string: "mudsnote://capture?mode=audio")!)

        XCTAssertFalse(model.isCapturePresented)
        XCTAssertEqual(model.folderStatus, .loading)

        model.folderStatus = .ready(URL(fileURLWithPath: "/tmp/MudsnoteLibrary"))
        model.presentPendingCaptureIfPossible()

        XCTAssertTrue(model.isCapturePresented)
        XCTAssertEqual(model.captureRoute, .audio)
    }

    @MainActor
    func testLatestFolderSelectionWinsAndOnlyPublishesReadySnapshot() async throws {
        let firstRoot = try temporaryRoot()
        let secondRoot = try temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        let suiteName = "MudsnoteCompanionTests.switch.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let access = FolderAccessService(defaults: defaults)
        let model = AppModel(bootstrapImmediately: false, folderAccess: access)
        model.draft.target = .recent("Projects/Old.md")

        model.selectFolder(firstRoot)
        model.selectFolder(secondRoot)

        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if case .ready(let root) = model.folderStatus, root == secondRoot {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }

        guard case .ready(let selectedRoot) = model.folderStatus else {
            return XCTFail("The latest folder never became ready")
        }
        XCTAssertEqual(selectedRoot, secondRoot)
        XCTAssertEqual(access.currentRoot, secondRoot)
        XCTAssertEqual(model.draft.target, .inbox)
        XCTAssertEqual(model.libraryFiles.count, 2)
        XCTAssertEqual(model.libraryRevision, 1)
    }

    @MainActor
    func testSceneActivationReloadsSharedQueueAndExternalMarkdownChanges() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let suiteName = "MudsnoteCompanionTests.resume.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let access = FolderAccessService(defaults: defaults)
        let model = AppModel(bootstrapImmediately: false, folderAccess: access)
        model.selectFolder(root)

        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if case .ready = model.folderStatus { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard case .ready = model.folderStatus else {
            return XCTFail("The test library never became ready")
        }

        try "# External note\n\nChanged while the app was inactive.\n".write(
            to: root.appendingPathComponent("External.md"),
            atomically: true,
            encoding: .utf8
        )
        let extensionQueue = PendingWriteQueue(root: root)
        try await extensionQueue.load()
        try await extensionQueue.enqueue(
            PendingWrite(
                id: UUID(),
                createdAt: .now,
                targetRelativePath: "Inbox.md",
                markdownBlock: "Captured by an extension while inactive\n",
                attachments: []
            )
        )

        let revisionBeforeResume = model.libraryRevision
        await model.refreshAfterSceneActivation()

        XCTAssertTrue(model.libraryFiles.contains { $0.relativePath == "External.md" })
        XCTAssertGreaterThan(model.libraryRevision, revisionBeforeResume)
        XCTAssertEqual(model.syncStatus, .idle)
        XCTAssertTrue(
            try String(contentsOf: root.appendingPathComponent("Inbox.md"), encoding: .utf8)
                .contains("Captured by an extension while inactive")
        )
        let verificationQueue = PendingWriteQueue(root: root)
        try await verificationQueue.load()
        let remainingCount = await verificationQueue.pendingCount()
        XCTAssertEqual(remainingCount, 0)
    }

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

    func testStandaloneNotesAreCreatedAsUniquePortableMarkdownFiles() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let first = try await store.createMarkdownDocument()
        let second = try await store.createMarkdownDocument()
        let project = try await store.createMarkdownDocument(inFolder: "Projects")

        XCTAssertEqual(first.relativePath, "Untitled Note.md")
        XCTAssertEqual(second.relativePath, "Untitled Note 2.md")
        XCTAssertEqual(project.relativePath, "Projects/Untitled Note.md")
        XCTAssertTrue(first.isNew)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(first.relativePath), encoding: .utf8),
            ""
        )

        let saved = try await store.finalizeNewMarkdownDocument(
            relativePath: first.relativePath,
            markdown: "# Standalone note / launch\n",
            expectedMarkdown: ""
        )
        XCTAssertFalse(saved.isNew)
        XCTAssertEqual(saved.relativePath, "Standalone note - launch.md")
        XCTAssertEqual(saved.markdown, "# Standalone note / launch\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(first.relativePath).path))

        try await store.discardEmptyNewMarkdownDocument(relativePath: second.relativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(second.relativePath).path))
        try await store.discardEmptyNewMarkdownDocument(relativePath: saved.relativePath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(saved.relativePath).path))
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

        let rewritten = InboxParser.markdown(forDisplayItems: [memo])
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

    func testQuickCaptureDraftRecoversBodyTargetAndAttachmentsAcrossLaunches() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("CaptureDraft", isDirectory: true)
        let image = try CaptureAttachment.validatedImage(
            data: try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))
        )
        let audio = try CaptureAttachment.validatedAudio(data: Data([0x01, 0x02, 0x03]))
        let file = try CaptureAttachment.validatedFile(
            data: Data("launch brief".utf8),
            suggestedName: "Launch Brief.pdf"
        )
        let date = Date(timeIntervalSince1970: 1_752_384_000)
        var draft = CaptureDraft(
            body: "Recovered thought",
            tags: "#launch",
            target: .daily(date),
            attachments: [image, audio, file],
            createdAt: date
        )
        let store = CaptureDraftRecoveryStore(directory: directory)

        try await store.save(draft)
        XCTAssertEqual(
            try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup,
            true
        )
        let initialFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        draft.body += " updated"
        try await store.save(draft)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(),
            initialFiles.sorted()
        )

        let relaunchedStore = CaptureDraftRecoveryStore(directory: directory)
        let recovered = try await relaunchedStore.load()
        XCTAssertEqual(recovered, draft)
        try await relaunchedStore.save(CaptureDraft())
        let cleared = try await relaunchedStore.load()
        XCTAssertNil(cleared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testDamagedQuickCaptureRecoveryHasStableErrorAndCanBeCleared() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("CaptureDraft", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent("draft.json"),
            options: .atomic
        )
        let store = CaptureDraftRecoveryStore(directory: directory)

        do {
            _ = try await store.load()
            XCTFail("Damaged recovery should fail")
        } catch {
            XCTAssertEqual(error as? CaptureDraftRecoveryError, .damaged)
        }
        try await store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testEmptyDraftCannotPreparePendingWrite() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let store = MarkdownFileStore()

        await XCTAssertThrowsErrorAsync(
            try await store.preparePendingWrite(for: CaptureDraft(), root: root)
        ) { error in
            XCTAssertEqual(error as? CaptureDraftError, .empty)
        }
    }

    func testPendingWriteRejectsDamagedPathsAndAttachmentData() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let escapingTarget = PendingWrite(
            id: UUID(),
            createdAt: .now,
            targetRelativePath: "../outside.md",
            markdownBlock: "memo",
            attachments: []
        )
        await XCTAssertThrowsErrorAsync(try await store.performPendingWrite(escapingTarget)) { error in
            XCTAssertEqual(error as? PendingWriteValidationError, .invalidTargetPath)
        }

        let escapingAttachment = PendingWrite(
            id: UUID(),
            createdAt: .now,
            targetRelativePath: "Inbox.md",
            markdownBlock: "memo",
            attachments: [PendingAttachment(relativePath: "../outside.m4a", base64Data: "AQ==")]
        )
        await XCTAssertThrowsErrorAsync(try await store.performPendingWrite(escapingAttachment)) { error in
            XCTAssertEqual(error as? PendingWriteValidationError, .invalidAttachmentPath)
        }

        let damagedAttachment = PendingWrite(
            id: UUID(),
            createdAt: .now,
            targetRelativePath: "Inbox.md",
            markdownBlock: "memo",
            attachments: [PendingAttachment(relativePath: "Attachments/audio.m4a", base64Data: "invalid")]
        )
        await XCTAssertThrowsErrorAsync(try await store.performPendingWrite(damagedAttachment)) { error in
            XCTAssertEqual(error as? PendingWriteValidationError, .invalidAttachmentData)
        }
    }

    func testImageAttachmentUsesDetectedContentTypeInsteadOfMisleadingSuffix() throws {
        let pngData = try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))
        let attachment = try CaptureAttachment.validatedImage(
            data: pngData,
            suggestedExtension: "jpg"
        )

        XCTAssertEqual(attachment.preferredExtension, "png")
    }

    func testImageAttachmentRejectsNonImageData() {
        XCTAssertThrowsError(
            try CaptureAttachment.validatedImage(data: Data("not-an-image".utf8))
        ) { error in
            XCTAssertEqual(error as? CaptureAttachmentError, .unsupportedImage)
        }
    }

    func testAttachmentPolicyBoundsCountAndCombinedDraftSize() throws {
        let tinyAudio = try CaptureAttachment.validatedAudio(data: Data([0x01]))
        let existing = Array(
            repeating: tinyAudio,
            count: CaptureAttachmentPolicy.maximumAttachmentCount
        )
        XCTAssertThrowsError(
            try CaptureAttachmentPolicy.validateAppending(tinyAudio, to: existing)
        ) { error in
            XCTAssertEqual(
                error as? CaptureAttachmentError,
                .tooMany(maximum: CaptureAttachmentPolicy.maximumAttachmentCount)
            )
        }

        let largeAudio = try CaptureAttachment.validatedAudio(
            data: Data(count: CaptureAttachmentPolicy.maximumAudioBytes)
        )
        XCTAssertThrowsError(
            try CaptureAttachmentPolicy.validateAppending(largeAudio, to: [largeAudio])
        ) { error in
            XCTAssertEqual(
                error as? CaptureAttachmentError,
                .draftTooLarge(maximumBytes: CaptureAttachmentPolicy.maximumDraftBytes)
            )
        }
    }

    func testPendingQueuePolicyRejectsUnboundedGrowth() {
        let pending = PendingWrite(
            id: UUID(),
            createdAt: .now,
            targetRelativePath: "Inbox.md",
            markdownBlock: "memo",
            attachments: [PendingAttachment(relativePath: "Attachments/test", base64Data: "12345")]
        )

        XCTAssertThrowsError(
            try PendingWriteQueuePolicy.validate(
                existing: [pending],
                appending: pending,
                maximumItems: 10,
                maximumEncodedBytes: 9
            )
        ) { error in
            XCTAssertEqual(error as? PendingWriteQueueError, .tooLarge)
        }
        XCTAssertThrowsError(
            try PendingWriteQueuePolicy.validate(
                existing: [pending],
                appending: pending,
                maximumItems: 1,
                maximumEncodedBytes: 100
            )
        ) { error in
            XCTAssertEqual(error as? PendingWriteQueueError, .tooManyItems(maximum: 1))
        }
    }

    func testDamagedPendingQueueIsPreservedWithoutBlockingNewCaptures() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let queueURL = root.appendingPathComponent(".mudsnote/queue.json")
        let damaged = Data("truncated pending queue".utf8)
        try damaged.write(to: queueURL, options: .atomic)
        let queue = PendingWriteQueue(root: root)
        let now = Date(timeIntervalSince1970: 1_752_384_000)

        let result = try await queue.load(now: now)
        let quarantineName: String
        switch result {
        case .quarantined(let filename):
            quarantineName = filename
        case .ready:
            XCTFail("Expected the damaged queue to be quarantined")
            return
        }
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent(".mudsnote/\(quarantineName)")),
            damaged
        )
        let rebuiltItems = try JSONDecoder().decode(
            [PendingWrite].self,
            from: Data(contentsOf: queueURL)
        )
        XCTAssertEqual(rebuiltItems, [])

        let pending = PendingWrite(
            id: UUID(),
            createdAt: now,
            targetRelativePath: "Inbox.md",
            markdownBlock: "Recovered queue path\n",
            attachments: []
        )
        try await queue.enqueue(pending)
        let relaunched = PendingWriteQueue(root: root)
        let relaunchResult = try await relaunched.load()
        let pendingCount = await relaunched.pendingCount()
        XCTAssertEqual(relaunchResult, .ready)
        XCTAssertEqual(pendingCount, 1)
    }

    func testCorruptFolderBookmarkRequiresReselectionAndCanBeForgotten() throws {
        let suiteName = "MudsnoteCompanionTests.folder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-a-bookmark".utf8), forKey: FolderAccessService.DefaultsKey.bookmarkData)
        let service = FolderAccessService(defaults: defaults)

        XCTAssertThrowsError(try service.resolvePersistedFolder()) { error in
            XCTAssertEqual(error as? FolderAccessError, .bookmarkResolutionFailed)
        }
        XCTAssertNil(service.currentRoot)

        service.forgetPersistedFolder()
        XCTAssertNil(defaults.data(forKey: FolderAccessService.DefaultsKey.bookmarkData))
        XCTAssertNil(try service.resolvePersistedFolder())
    }

    func testFolderSelectionRejectsIndividualFile() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        try "# Note\n".write(to: file, atomically: true, encoding: .utf8)
        let suiteName = "MudsnoteCompanionTests.folder.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = FolderAccessService(defaults: defaults)

        XCTAssertThrowsError(try service.persistFolder(file)) { error in
            XCTAssertEqual(error as? FolderAccessError, .notDirectory)
        }
        XCTAssertNil(defaults.data(forKey: FolderAccessService.DefaultsKey.bookmarkData))
    }

    func testSimplifiedChineseCatalogIsEmbeddedAndFormatsDynamicCopy() throws {
        let localizationPath = try XCTUnwrap(
            Bundle.main.path(forResource: "zh-Hans", ofType: "lproj")
        )
        let bundle = try XCTUnwrap(Bundle(path: localizationPath))

        XCTAssertEqual(
            bundle.localizedString(forKey: "Choose a Markdown Folder", value: nil, table: nil),
            "选择 Markdown 文件夹"
        )
        let format = bundle.localizedString(
            forKey: "attachment.maximum_count.format",
            value: nil,
            table: nil
        )
        XCTAssertEqual(String(format: format, locale: Locale(identifier: "zh-Hans"), 8), "每条记录最多添加 8 个附件。")
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

    func testConcurrentQueueInstancesMergeInsteadOfClobberingPendingWrites() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let firstQueue = PendingWriteQueue(root: root)
        let secondQueue = PendingWriteQueue(root: root)
        try await firstQueue.load()
        try await secondQueue.load()

        let first = PendingWrite(
            id: UUID(),
            createdAt: .now,
            targetRelativePath: "Inbox.md",
            markdownBlock: "First",
            attachments: []
        )
        let second = PendingWrite(
            id: UUID(),
            createdAt: .now,
            targetRelativePath: "Inbox.md",
            markdownBlock: "Second",
            attachments: []
        )
        try await firstQueue.enqueue(first)
        try await secondQueue.enqueue(second)

        let verificationQueue = PendingWriteQueue(root: root)
        try await verificationQueue.load()
        let pendingCount = await verificationQueue.pendingCount()
        XCTAssertEqual(pendingCount, 2)
    }

    func testIntentCaptureWriterUsesDurableQueueAndCleansUpAfterSuccess() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        try await IntentCaptureWriter.write(
            CaptureDraft(body: "Captured from Shortcuts", target: .inbox),
            root: root
        )

        let inbox = try String(
            contentsOf: root.appendingPathComponent("Inbox.md"),
            encoding: .utf8
        )
        XCTAssertTrue(inbox.contains("Captured from Shortcuts"))
        let queue = PendingWriteQueue(root: root)
        try await queue.load()
        let pendingCount = await queue.pendingCount()
        XCTAssertEqual(pendingCount, 0)
    }

    func testLibrarySnapshotUsesOneExactInventoryBeyondRecentLimit() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        for index in 0..<30 {
            try "# Note \(index)\n".write(
                to: projects.appendingPathComponent("note-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }
        try Data([0x01]).write(
            to: root.appendingPathComponent("Attachments/image.png"),
            options: .atomic
        )
        try "# Conflict\n".write(
            to: projects.appendingPathComponent("note conflicted copy.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let snapshot = try await store.loadLibrarySnapshot()

        XCTAssertEqual(snapshot.summary.allNotesCount, 33)
        XCTAssertEqual(snapshot.summary.dailyCount, 1)
        XCTAssertEqual(snapshot.summary.attachmentCount, 1)
        XCTAssertEqual(snapshot.attachments.count, 1)
        XCTAssertEqual(snapshot.attachments.first?.relativePath, "Attachments/image.png")
        XCTAssertEqual(snapshot.attachments.first?.kind, .image)
        XCTAssertEqual(snapshot.allFiles.count, 33)
        XCTAssertEqual(snapshot.recentFiles.count, 24)
        XCTAssertEqual(snapshot.conflictWarnings, ["Projects/note conflicted copy.md"])
    }

    func testLibrarySnapshotBuildsNestedFolderTreeAndKeepsEmptyFolders() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects/Launch", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Archive/Empty", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Plan\n".write(
            to: root.appendingPathComponent("Projects/Plan.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Brief\n".write(
            to: root.appendingPathComponent("Projects/Launch/Brief.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let snapshot = try await store.loadLibrarySnapshot()

        XCTAssertEqual(snapshot.folders.map(\.name), ["Archive", "Projects"])
        let archive = try XCTUnwrap(snapshot.folders.first { $0.name == "Archive" })
        XCTAssertEqual(archive.totalNoteCount, 0)
        XCTAssertEqual(archive.children.map(\.name), ["Empty"])
        let projects = try XCTUnwrap(snapshot.folders.first { $0.name == "Projects" })
        XCTAssertEqual(projects.directNoteCount, 1)
        XCTAssertEqual(projects.totalNoteCount, 2)
        XCTAssertEqual(projects.children.map(\.relativePath), ["Projects/Launch"])
        XCTAssertFalse(snapshot.folders.contains { $0.name == "Attachments" })
        XCTAssertFalse(snapshot.folders.contains { $0.name == "Daily" })
    }

    func testFolderTreeRejectsHiddenAndSystemPathsAndBuildsMissingAncestors() {
        let files = [
            RecentMarkdownFile(
                id: "Work/Deep/Note.md",
                relativePath: "Work/Deep/Note.md",
                title: "Note",
                modifiedAt: .distantPast
            ),
            RecentMarkdownFile(
                id: ".private/Secret.md",
                relativePath: ".private/Secret.md",
                title: "Secret",
                modifiedAt: .distantPast
            ),
        ]

        let folders = LibraryFolderNode.makeTree(
            directoryPaths: ["Attachments/2026", "Daily/2026", ".mudsnote/cache"],
            files: files
        )

        XCTAssertEqual(folders.map(\.relativePath), ["Work"])
        XCTAssertEqual(folders.first?.children.map(\.relativePath), ["Work/Deep"])
        XCTAssertEqual(folders.first?.totalNoteCount, 1)
    }

    func testMarkdownTrashRestoreAvoidsCollisionAndRefreshesInventory() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        let original = projects.appendingPathComponent("Plan.md")
        try "# Original plan\n".write(to: original, atomically: true, encoding: .utf8)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.trashMarkdownDocument(
            relativePath: "Projects/Plan.md",
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: original.path))
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.trashedFiles.count, 1)
        XCTAssertEqual(snapshot.summary.recentlyDeletedCount, 1)
        let trashed = try XCTUnwrap(snapshot.trashedFiles.first)
        XCTAssertEqual(trashed.originalRelativePath, "Projects/Plan.md")

        try "# Replacement plan\n".write(to: original, atomically: true, encoding: .utf8)
        let restored = try await store.restoreTrashedMarkdownDocument(id: trashed.id)

        XCTAssertEqual(restored.relativePath, "Projects/Plan 2.md")
        XCTAssertEqual(
            try String(contentsOf: projects.appendingPathComponent("Plan 2.md"), encoding: .utf8),
            "# Original plan\n"
        )
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "# Replacement plan\n")
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.trashedFiles.isEmpty)
        XCTAssertEqual(snapshot.summary.recentlyDeletedCount, 0)
    }

    func testMarkdownTrashPermanentDeleteAndProtectedPaths() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let note = root.appendingPathComponent("Disposable.md")
        try "# Disposable\n".write(to: note, atomically: true, encoding: .utf8)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.trashMarkdownDocument(relativePath: "Disposable.md")
        let trashSnapshot = try await store.loadLibrarySnapshot()
        let trashed = try XCTUnwrap(trashSnapshot.trashedFiles.first)
        try await store.permanentlyDeleteTrashedMarkdownDocument(id: trashed.id)

        let snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.trashedFiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: note.path))
        await XCTAssertThrowsErrorAsync(
            try await store.trashMarkdownDocument(relativePath: "Inbox.md")
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .protectedNote)
        }
        let daily = try XCTUnwrap(snapshot.allFiles.first { $0.relativePath.hasPrefix("Daily/") })
        await XCTAssertThrowsErrorAsync(
            try await store.trashMarkdownDocument(relativePath: daily.relativePath)
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .protectedNote)
        }
    }

    func testFolderCreateRenameAndMoveNoteAvoidCollisions() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let projects = try await store.createFolder(named: "Projects")
        let duplicate = try await store.createFolder(named: "Projects")
        let nested = try await store.createFolder(
            named: "Launch",
            parentRelativePath: projects.relativePath
        )
        XCTAssertEqual(projects.relativePath, "Projects")
        XCTAssertEqual(duplicate.relativePath, "Projects 2")
        XCTAssertEqual(nested.relativePath, "Projects/Launch")

        let rootNote = root.appendingPathComponent("Plan.md")
        let existing = root.appendingPathComponent("Projects/Launch/Plan.md")
        try "# Root plan\n".write(to: rootNote, atomically: true, encoding: .utf8)
        try "# Existing plan\n".write(to: existing, atomically: true, encoding: .utf8)
        let moved = try await store.moveMarkdownDocument(
            relativePath: "Plan.md",
            toFolder: nested.relativePath
        )
        XCTAssertEqual(moved.relativePath, "Projects/Launch/Plan 2.md")

        let trashed = try await store.trashMarkdownDocument(
            relativePath: "Projects/Launch/Plan 2.md"
        )
        let renamed = try await store.renameFolder(
            relativePath: "Projects",
            to: "Active"
        )
        XCTAssertEqual(renamed, "Active")
        let restored = try await store.restoreTrashedMarkdownDocument(id: trashed.id)
        XCTAssertEqual(restored.relativePath, "Active/Launch/Plan 2.md")
    }

    func testFolderDeleteMovesMarkdownToTrashAndPreservesUnsupportedFiles() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let archive = root.appendingPathComponent("Archive/Sub", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        try "# One\n".write(
            to: root.appendingPathComponent("Archive/One.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Two\n".write(
            to: archive.appendingPathComponent("Two.md"),
            atomically: true,
            encoding: .utf8
        )
        try await store.trashFolder(relativePath: "Archive")

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Archive").path))
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.trashedFiles.count, 2)
        let nested = try XCTUnwrap(snapshot.trashedFiles.first { $0.originalRelativePath.hasSuffix("Sub/Two.md") })
        _ = try await store.restoreTrashedMarkdownDocument(id: nested.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Archive/Sub/Two.md").path))

        let protected = root.appendingPathComponent("Protected", isDirectory: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try "# Keep\n".write(
            to: protected.appendingPathComponent("Keep.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data([0x01]).write(to: protected.appendingPathComponent("keep.bin"))
        await XCTAssertThrowsErrorAsync(
            try await store.trashFolder(relativePath: "Protected")
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .folderContainsUnsupportedItems)
        }
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.contains { $0.relativePath == "Protected/Keep.md" })
        XCTAssertTrue(FileManager.default.fileExists(atPath: protected.appendingPathComponent("keep.bin").path))
    }

    func testFolderOperationsRejectReservedPathsAndInvalidNames() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let store = MarkdownFileStore()
        await store.configure(root: root)

        await XCTAssertThrowsErrorAsync(
            try await store.createFolder(named: "../Escape")
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .invalidFolderName)
        }
        await XCTAssertThrowsErrorAsync(
            try await store.createFolder(named: "Nested", parentRelativePath: "Attachments")
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .invalidFolder)
        }
        await XCTAssertThrowsErrorAsync(
            try await store.renameFolder(relativePath: "Daily", to: "Renamed")
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .invalidFolder)
        }
    }

    func testPinnedNoteSurvivesMoveFolderRenameTrashAndRestore() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let old = root.appendingPathComponent("Old.md")
        let newer = root.appendingPathComponent("Newer.md")
        try "# Old pinned\n".write(to: old, atomically: true, encoding: .utf8)
        try "# Newer\n".write(to: newer, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_600_000_000)],
            ofItemAtPath: old.path
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.setPinned(true, relativePath: "Old.md")
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.allFiles.first?.relativePath, "Old.md")
        XCTAssertTrue(snapshot.allFiles.first?.isPinned == true)

        let folder = try await store.createFolder(named: "Archive")
        let moved = try await store.moveMarkdownDocument(
            relativePath: "Old.md",
            toFolder: folder.relativePath
        )
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == moved.relativePath }?.isPinned == true)

        let renamed = try await store.renameFolder(relativePath: "Archive", to: "Filed")
        let renamedPath = "\(renamed)/Old.md"
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == renamedPath }?.isPinned == true)

        let trashed = try await store.trashMarkdownDocument(relativePath: renamedPath)
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertFalse(snapshot.allFiles.contains { $0.isPinned })
        let restored = try await store.restoreTrashedMarkdownDocument(id: trashed.id)
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(restored.relativePath, renamedPath)
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == renamedPath }?.isPinned == true)

        try await store.setPinned(false, relativePath: renamedPath)
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertFalse(snapshot.allFiles.first { $0.relativePath == renamedPath }?.isPinned == true)
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(renamedPath), encoding: .utf8),
            "# Old pinned\n"
        )
    }

    func testDamagedPinMetadataDoesNotBlockLibrary() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try Data("not-json".utf8).write(to: root.appendingPathComponent(".mudsnote/pins.json"))

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let snapshot = try await store.loadLibrarySnapshot()

        XCTAssertFalse(snapshot.allFiles.contains { $0.isPinned })
        let daily = try XCTUnwrap(snapshot.allFiles.first { $0.relativePath.hasPrefix("Daily/") })
        try await store.setPinned(true, relativePath: daily.relativePath)
        XCTAssertNoThrow(
            try JSONDecoder().decode(
                [String].self,
                from: Data(contentsOf: root.appendingPathComponent(".mudsnote/pins.json"))
            )
        )
    }

    func testFullTextSearchFindsFileContentAndIndividualInboxMemos() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let project = root.appendingPathComponent("Projects/Launch.md")
        try FileManager.default.createDirectory(
            at: project.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Launch\n\nCommercial architecture roadmap\n".write(
            to: project,
            atomically: true,
            encoding: .utf8
        )
        let inbox = root.appendingPathComponent("Inbox.md")
        try (try String(contentsOf: inbox, encoding: .utf8) + """

        ## 2026-07-13 09:00

        Unique inbox thought

        #strategy

        """).write(to: inbox, atomically: true, encoding: .utf8)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        _ = try await store.loadLibrarySnapshot()

        let fileResults = try await store.search(query: "commercial architecture")
        XCTAssertEqual(fileResults.map(\.location), ["Projects/Launch.md"])
        if case .file = try XCTUnwrap(fileResults.first).destination {
            // Expected file-level result.
        } else {
            XCTFail("Expected a file search result")
        }

        let memoResults = try await store.search(query: "unique strategy")
        XCTAssertEqual(memoResults.count, 1)
        XCTAssertEqual(memoResults.first?.location, String(localized: "Inbox"))
        if case .memo(let memo) = try XCTUnwrap(memoResults.first).destination {
            XCTAssertTrue(memo.body.contains("Unique inbox thought"))
        } else {
            XCTFail("Expected an individual Inbox memo result")
        }

        let fileQueryInInbox = try await store.search(
            query: "commercial architecture",
            scope: .inbox
        )
        let memoQueryInNotes = try await store.search(
            query: "unique strategy",
            scope: .notes
        )
        let fileQueryInNotes = try await store.search(
            query: "commercial architecture",
            scope: .notes
        )
        let memoQueryInInbox = try await store.search(
            query: "unique strategy",
            scope: .inbox
        )
        XCTAssertEqual(fileQueryInInbox, [])
        XCTAssertEqual(memoQueryInNotes, [])
        XCTAssertEqual(fileQueryInNotes.map(\.location), ["Projects/Launch.md"])
        XCTAssertEqual(memoQueryInInbox.map(\.location), [String(localized: "Inbox")])
    }

    @MainActor
    func testAppModelPublishesCompletedSearchIdentity() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try "# Scoped result\nNeedle body".write(
            to: root.appendingPathComponent("Scoped.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)
        _ = try await store.loadLibrarySnapshot()
        let model = AppModel(bootstrapImmediately: false, fileStore: store)

        await model.searchLibrary(query: "  needle  ", scope: .notes)

        XCTAssertEqual(model.completedSearchQuery, "needle")
        XCTAssertEqual(model.completedSearchScope, .notes)
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(model.searchResults.map(\.location), ["Scoped.md"])

        model.clearSearch()
        XCTAssertEqual(model.completedSearchQuery, "")
        XCTAssertEqual(model.completedSearchScope, .all)
        XCTAssertTrue(model.searchResults.isEmpty)
    }

    func testAttachmentPreviewCopiesAuthorizedFileAndRejectsTraversal() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let attachment = root.appendingPathComponent("Attachments/preview.png")
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        try bytes.write(to: attachment, options: .atomic)
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let preview = try await store.prepareAttachmentPreview(
            relativePath: "Attachments/preview.png"
        )
        XCTAssertEqual(try Data(contentsOf: preview), bytes)
        XCTAssertTrue(preview.path.hasPrefix(FileManager.default.temporaryDirectory.path))

        do {
            _ = try await store.prepareAttachmentPreview(relativePath: "../outside.png")
            XCTFail("Path traversal should be rejected")
        } catch {
            XCTAssertEqual(error as? AttachmentPreviewError, .invalidPath)
        }
    }

    func testMarkdownDocumentLoadsInsideAuthorizedLibraryAndRejectsTraversal() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let documentURL = root.appendingPathComponent("Projects/Launch.md")
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Launch\n\nCommercial-ready reader\n".write(
            to: documentURL,
            atomically: true,
            encoding: .utf8
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let document = try await store.loadMarkdownDocument(relativePath: "Projects/Launch.md")
        XCTAssertEqual(document.title, "Launch")
        XCTAssertEqual(document.relativePath, "Projects/Launch.md")
        XCTAssertTrue(document.markdown.contains("Commercial-ready reader"))

        do {
            _ = try await store.loadMarkdownDocument(relativePath: "../outside.md")
            XCTFail("Path traversal should be rejected")
        } catch {
            XCTAssertEqual(error as? MarkdownDocumentError, .invalidPath)
        }
    }

    func testMarkdownDocumentSaveRejectsExternalOverwrite() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let documentURL = root.appendingPathComponent("Daily/editable.md")
        try "# Original\n".write(to: documentURL, atomically: true, encoding: .utf8)
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let original = try await store.loadMarkdownDocument(relativePath: "Daily/editable.md")

        let saved = try await store.saveMarkdownDocument(
            relativePath: original.relativePath,
            markdown: "# Updated\n",
            expectedMarkdown: original.markdown
        )
        XCTAssertEqual(saved.markdown, "# Updated\n")
        XCTAssertEqual(try String(contentsOf: documentURL, encoding: .utf8), "# Updated\n")

        try "# External change\n".write(to: documentURL, atomically: true, encoding: .utf8)
        await XCTAssertThrowsErrorAsync(
            try await store.saveMarkdownDocument(
                relativePath: original.relativePath,
                markdown: "# Stale edit\n",
                expectedMarkdown: saved.markdown
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownDocumentError, .changedExternally)
        }
        XCTAssertEqual(try String(contentsOf: documentURL, encoding: .utf8), "# External change\n")
    }

    func testMarkdownDocumentAttachmentInsertRemoveCollisionAndConflictRollback() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let documentURL = root.appendingPathComponent("Projects/Photos.md")
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Photos\n".write(to: documentURL, atomically: true, encoding: .utf8)
        let image = try CaptureAttachment.validatedImage(
            data: try XCTUnwrap(Data(base64Encoded: Self.onePixelPNG))
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let original = try await store.loadMarkdownDocument(relativePath: "Projects/Photos.md")
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 12
        )))

        let first = try await store.attachToMarkdownDocument(
            relativePath: original.relativePath,
            markdown: original.markdown,
            expectedMarkdown: original.markdown,
            attachment: image,
            now: now
        )
        let second = try await store.attachToMarkdownDocument(
            relativePath: first.relativePath,
            markdown: first.markdown,
            expectedMarkdown: first.markdown,
            attachment: image,
            now: now
        )
        XCTAssertTrue(first.markdown.contains("![Image](Attachments/2026/07/IMG-20260713-120000.png)"))
        XCTAssertTrue(second.markdown.contains("![Image](Attachments/2026/07/IMG-20260713-120000-2.png)"))

        let attachmentFolder = root.appendingPathComponent("Attachments/2026/07")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: attachmentFolder.path).count, 2)
        let removed = try await store.removeAttachmentFromMarkdownDocument(
            relativePath: second.relativePath,
            markdown: second.markdown,
            expectedMarkdown: second.markdown,
            attachmentLine: "![Image](Attachments/2026/07/IMG-20260713-120000.png)"
        )
        XCTAssertFalse(removed.markdown.contains("IMG-20260713-120000.png"))
        XCTAssertTrue(removed.markdown.contains("IMG-20260713-120000-2.png"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: attachmentFolder.path).count, 2)
        await XCTAssertThrowsErrorAsync(
            try await store.attachToMarkdownDocument(
                relativePath: removed.relativePath,
                markdown: removed.markdown,
                expectedMarkdown: second.markdown,
                attachment: image,
                now: now
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownDocumentError, .changedExternally)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: attachmentFolder.path).count, 2)
    }

    func testMarkdownDocumentStoresPortableGenericFileAttachment() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let documentURL = root.appendingPathComponent("Projects/Files.md")
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Files\n".write(to: documentURL, atomically: true, encoding: .utf8)
        let attachment = try CaptureAttachment.validatedFile(
            data: Data("portable pdf".utf8),
            suggestedName: "Launch Brief.pdf"
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let original = try await store.loadMarkdownDocument(relativePath: "Projects/Files.md")
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 12
        )))

        let updated = try await store.attachToMarkdownDocument(
            relativePath: original.relativePath,
            markdown: original.markdown,
            expectedMarkdown: original.markdown,
            attachment: attachment,
            now: now
        )

        let relativePath = "Attachments/2026/07/Launch Brief-20260713-120000.pdf"
        XCTAssertTrue(updated.markdown.contains("[Launch Brief-20260713-120000.pdf](\(relativePath))"))
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent(relativePath)),
            Data("portable pdf".utf8)
        )
        XCTAssertEqual(MarkdownAttachmentLine("[Brief](\(relativePath))")?.kind, .file)
    }

    func testInboxMemoEditRejectsStaleBody() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let inbox = root.appendingPathComponent("Inbox.md")
        try """
        # Inbox

        ## 2026-07-13 10:00

        Original memo

        """.write(to: inbox, atomically: true, encoding: .utf8)
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let memo = try XCTUnwrap(InboxParser.parse(try String(contentsOf: inbox, encoding: .utf8)).first)

        try await store.applyInboxMutation(
            .replaceBody(memoID: memo.id, expectedBody: memo.body, newBody: "Edited memo")
        )
        XCTAssertTrue(try String(contentsOf: inbox, encoding: .utf8).contains("Edited memo"))

        await XCTAssertThrowsErrorAsync(
            try await store.applyInboxMutation(
                .replaceBody(memoID: memo.id, expectedBody: memo.body, newBody: "Stale overwrite")
            )
        ) { error in
            XCTAssertEqual(error as? InboxMutationError, .memoChanged)
        }
    }

    func testAuthorizedLibraryPathRejectsAbsoluteAndEscapingReferences() {
        let root = URL(fileURLWithPath: "/tmp/MudsnoteLibrary", isDirectory: true)

        XCTAssertEqual(
            AuthorizedLibraryPath.resolve("Attachments/2026/image.png", within: root)?.path,
            "/tmp/MudsnoteLibrary/Attachments/2026/image.png"
        )
        XCTAssertNil(AuthorizedLibraryPath.resolve("../private.txt", within: root))
        XCTAssertNil(AuthorizedLibraryPath.resolve("/etc/passwd", within: root))
        XCTAssertNil(
            AuthorizedLibraryPath.resolve(
                "Daily/2026-07-12.md",
                within: root,
                constrainedTo: "Attachments"
            )
        )
    }

    func testAuthorizedLibraryPathRejectsSymlinkEscape() throws {
        let root = try temporaryRoot()
        let outside = try temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let link = root.appendingPathComponent("LinkedOutside", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        XCTAssertNil(
            AuthorizedLibraryPath.resolve("LinkedOutside/private.md", within: root)
        )
    }

    func testInboxDeltaRefreshAvoidsUnrelatedLibraryRescan() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let baseline = try await store.loadLibrarySnapshot()
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try "# Added externally\n".write(
            to: projects.appendingPathComponent("external.md"),
            atomically: true,
            encoding: .utf8
        )
        let inbox = root.appendingPathComponent("Inbox.md")
        let inboxAppend = """
        ## 2026-07-11 18:45

        Incremental refresh memo

        """
        try (try String(contentsOf: inbox, encoding: .utf8) + inboxAppend).write(
            to: inbox,
            atomically: true,
            encoding: .utf8
        )

        let delta = try await store.loadInboxDeltaSnapshot()
        XCTAssertEqual(delta.summary.allNotesCount, baseline.summary.allNotesCount)
        XCTAssertEqual(delta.summary.inboxCount, 1)
        XCTAssertEqual(delta.inboxItems.first?.body, "Incremental refresh memo")
        XCTAssertEqual(delta.recentFiles.first?.relativePath, "Inbox.md")
        XCTAssertFalse(delta.recentFiles.contains { $0.relativePath == "Projects/external.md" })

        let refreshed = try await store.loadLibrarySnapshot()
        XCTAssertEqual(refreshed.summary.allNotesCount, baseline.summary.allNotesCount + 1)
        XCTAssertTrue(refreshed.recentFiles.contains { $0.relativePath == "Projects/external.md" })
    }

    func testInboxMutationRereadsDiskAndPreservesExternalAppend() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let inbox = root.appendingPathComponent("Inbox.md")
        let original = """
        # Inbox

        ## 2026-07-11 09:00

        Original memo

        <!-- mudsnote-write:1e989c6a-2aae-47c5-a8e7-4c7d854cb2d8 -->

        """
        try original.write(to: inbox, atomically: true, encoding: .utf8)
        let staleMemo = try XCTUnwrap(InboxParser.parse(original).first)

        let externalAppend = """
        ## 2026-07-11 09:01

        Added outside the app

        """
        try (original + externalAppend).write(to: inbox, atomically: true, encoding: .utf8)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.applyInboxMutation(.addTag(memoID: staleMemo.id, tag: "review"))

        let updated = try String(contentsOf: inbox, encoding: .utf8)
        let memos = InboxParser.parse(updated)
        XCTAssertEqual(memos.count, 2)
        XCTAssertTrue(memos.contains { $0.body.contains("Added outside the app") })
        let originalMemo = try XCTUnwrap(memos.first { $0.body.contains("Original memo") })
        XCTAssertTrue(originalMemo.body.contains("#review"))
        XCTAssertEqual(
            originalMemo.writeMarker,
            "<!-- mudsnote-write:1e989c6a-2aae-47c5-a8e7-4c7d854cb2d8 -->"
        )
    }

    func testPerformanceLargeLibrarySnapshot() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for index in 0..<1_000 {
            try "# Performance Note \(index)\n\nBody \(index)\n".write(
                to: archive.appendingPathComponent("note-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = MarkdownFileStore()
        await store.configure(root: root)
        measureAsync {
            let snapshot = try await store.loadLibrarySnapshot()
            XCTAssertEqual(snapshot.summary.allNotesCount, 1_002)
            XCTAssertEqual(snapshot.recentFiles.count, 24)
        }
    }

    func testPerformanceInboxDeltaRefreshInLargeLibrary() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        let archive = root.appendingPathComponent("Archive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        for index in 0..<1_000 {
            try "# Performance Note \(index)\n\nBody \(index)\n".write(
                to: archive.appendingPathComponent("note-\(index).md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = MarkdownFileStore()
        await store.configure(root: root)
        _ = try await store.loadLibrarySnapshot()
        let inbox = root.appendingPathComponent("Inbox.md")
        try (try String(contentsOf: inbox, encoding: .utf8) + """
        ## 2026-07-11 18:46

        Performance delta memo

        """).write(to: inbox, atomically: true, encoding: .utf8)

        measureAsync {
            let snapshot = try await store.loadInboxDeltaSnapshot()
            XCTAssertEqual(snapshot.summary.allNotesCount, 1_002)
            XCTAssertEqual(snapshot.recentFiles.first?.relativePath, "Inbox.md")
        }
    }

    func testMarkdownListMetadataExtractsHeadingPreviewAndAttachments() {
        let metadata = MarkdownListMetadata.extract(
            from: """
            # Launch Plan

            ![Cover](Attachments/cover.png)
            - [x] **Ship** the iPhone build
            Follow up with the release notes.
            """,
            fallbackTitle: "Fallback"
        )

        XCTAssertEqual(metadata.title, "Launch Plan")
        XCTAssertEqual(metadata.preview, "Ship the iPhone build Follow up with the release notes.")
        XCTAssertTrue(metadata.hasAttachments)
        XCTAssertEqual(
            MarkdownListMetadata.extract(from: "Plain body", fallbackTitle: "File Name").title,
            "Plain body"
        )
    }

    func testMarkdownTableInsertionAndRenderedBlockParsing() throws {
        let edit = try XCTUnwrap(MarkdownTableEditing.insertionEdit(
            in: "Intro",
            selection: NSRange(location: 5, length: 0)
        ))
        let updated = ("Intro" as NSString).replacingCharacters(
            in: edit.range,
            with: edit.replacement
        )
        XCTAssertEqual(
            updated,
            "Intro\n| Column 1 | Column 2 |\n| --- | --- |\n|  |  |"
        )
        XCTAssertEqual(
            edit.selection.location,
            (updated as NSString).range(of: "|  |  |").location + 2
        )
        XCTAssertEqual(
            MarkdownRenderBlock.parse("# Plan\n\n| Owner | Status |\n| :--- | ---: |\n| Donald | Ready |\n\nDone"),
            [
                .line("# Plan"),
                .table(headers: ["Owner", "Status"], rows: [["Donald", "Ready"]]),
                .line("Done")
            ]
        )
    }

    func testScannedDocumentCreatesPortableMultiPagePDF() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 500))
        let first = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 500))
            UIColor.black.setFill()
            context.fill(CGRect(x: 30, y: 40, width: 240, height: 20))
        }
        let data = try ScannedDocumentPDF.data(for: [first, first])
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        XCTAssertEqual(try XCTUnwrap(CGPDFDocument(provider)).numberOfPages, 2)
        XCTAssertThrowsError(try ScannedDocumentPDF.data(for: []))
    }

    @MainActor
    func testMarkdownEditorPresentationKeepsSourceWhileRenderingSyntax() throws {
        let markdown = "# Heading\n\n- Bullet\n- [ ] Ship editor\n- [x] Keep Markdown\n\n**Bold** and `code` with [Link](https://example.com)"
        let view = MarkdownRichTextView()
        view.text = markdown

        MarkdownEditorPresentation.apply(to: view, displaysSource: false)
        XCTAssertEqual(view.text, markdown)
        let storage = try XCTUnwrap(view.textStorage)
        let source = markdown as NSString
        let headingMarker = source.range(of: "#")
        let headingText = source.range(of: "Heading")
        let boldText = source.range(of: "Bold")
        let linkText = source.range(of: "Link")
        let markerColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: headingMarker.location, effectiveRange: nil) as? UIColor)
        XCTAssertEqual(markerColor.cgColor.alpha, 0, accuracy: 0.01)
        let headingFont = try XCTUnwrap(storage.attribute(.font, at: headingText.location, effectiveRange: nil) as? UIFont)
        let boldFont = try XCTUnwrap(storage.attribute(.font, at: boldText.location, effectiveRange: nil) as? UIFont)
        XCTAssertGreaterThan(headingFont.pointSize, 20)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertNotNil(storage.attribute(.underlineStyle, at: linkText.location, effectiveRange: nil))
        XCTAssertEqual(view.bulletMarkers.count, 1)
        XCTAssertEqual(view.checklistMarkers.map(\.checked), [false, true])
        let firstMarker = try XCTUnwrap(view.checklistMarkers.first)
        let toggled = try XCTUnwrap(MarkdownEditorPresentation.togglingChecklist(
            in: markdown,
            marker: firstMarker
        ))
        XCTAssertTrue(toggled.contains("- [x] Ship editor"))
        XCTAssertTrue(toggled.contains("- [x] Keep Markdown"))

        MarkdownEditorPresentation.apply(to: view, displaysSource: true)
        XCTAssertEqual(view.text, markdown)
        let sourceMarkerColor = try XCTUnwrap(storage.attribute(.foregroundColor, at: headingMarker.location, effectiveRange: nil) as? UIColor)
        XCTAssertGreaterThan(sourceMarkerColor.cgColor.alpha, 0.9)
        XCTAssertTrue(view.checklistMarkers.isEmpty)
        XCTAssertTrue(view.bulletMarkers.isEmpty)
    }

    func testMarkdownListsContinueWithNativeReturnSemantics() {
        XCTAssertEqual(
            MarkdownListEditing.returnEdit(
                in: "- Ship",
                selection: NSRange(location: 6, length: 0)
            ),
            MarkdownListEdit(
                range: NSRange(location: 6, length: 0),
                replacement: "\n- ",
                selection: NSRange(location: 9, length: 0)
            )
        )
        XCTAssertEqual(
            MarkdownListEditing.returnEdit(
                in: "  7) Review",
                selection: NSRange(location: 11, length: 0)
            )?.replacement,
            "\n  8) "
        )
        XCTAssertEqual(
            MarkdownListEditing.returnEdit(
                in: "- [x] Complete",
                selection: NSRange(location: 14, length: 0)
            )?.replacement,
            "\n- [ ] "
        )
    }

    func testReturnOnEmptyMarkdownListItemExitsList() {
        for markdown in ["- ", "- [ ] ", "12. "] {
            let length = (markdown as NSString).length
            XCTAssertEqual(
                MarkdownListEditing.returnEdit(
                    in: markdown,
                    selection: NSRange(location: length, length: 0)
                ),
                MarkdownListEdit(
                    range: NSRange(location: 0, length: length),
                    replacement: "",
                    selection: NSRange(location: 0, length: 0)
                )
            )
        }
    }

    func testBackspaceAtMarkdownListContentStartRemovesFormatting() {
        let markdown = "Intro\n- [ ] Item"
        XCTAssertEqual(
            MarkdownListEditing.backspaceEdit(
                in: markdown,
                deletionRange: NSRange(location: 11, length: 1)
            ),
            MarkdownListEdit(
                range: NSRange(location: 6, length: 6),
                replacement: "",
                selection: NSRange(location: 6, length: 0)
            )
        )
        XCTAssertNil(
            MarkdownListEditing.backspaceEdit(
                in: markdown,
                deletionRange: NSRange(location: 12, length: 1)
            )
        )
    }

    func testMarkdownListIndentationChangesOnlySelectedListLines() throws {
        let markdown = "- One\n1. Two\nBody"
        let indented = try XCTUnwrap(
            MarkdownListEditing.indentationEdit(
                in: markdown,
                selection: NSRange(location: 0, length: 12),
                direction: .increase
            )
        )
        XCTAssertEqual(indented.range, NSRange(location: 0, length: 13))
        XCTAssertEqual(indented.replacement, "  - One\n  1. Two\n")
        XCTAssertEqual(indented.selection, NSRange(location: 0, length: 17))

        let nested = indented.replacement + "Body"
        let outdented = try XCTUnwrap(
            MarkdownListEditing.indentationEdit(
                in: nested,
                selection: indented.selection,
                direction: .decrease
            )
        )
        XCTAssertEqual(outdented.replacement, "- One\n1. Two\n")
        XCTAssertNil(
            MarkdownListEditing.indentationEdit(
                in: markdown,
                selection: NSRange(location: 0, length: 12),
                direction: .decrease
            )
        )
    }

    func testLibrarySnapshotPublishesAndRefreshesListMetadata() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let noteURL = root.appendingPathComponent("Projects/Plan.md")
        try FileManager.default.createDirectory(
            at: noteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# First Title\nInitial preview".write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        var snapshot = try await store.loadLibrarySnapshot()
        var note = try XCTUnwrap(snapshot.allFiles.first { $0.relativePath == "Projects/Plan.md" })
        XCTAssertEqual(note.title, "First Title")
        XCTAssertEqual(note.preview, "Initial preview")
        XCTAssertFalse(note.hasAttachments)

        try "# Updated Title\nUpdated preview\n![Photo](Attachments/photo.jpg)".write(
            to: noteURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)],
            ofItemAtPath: noteURL.path
        )
        snapshot = try await store.loadLibrarySnapshot()
        note = try XCTUnwrap(snapshot.allFiles.first { $0.relativePath == "Projects/Plan.md" })
        XCTAssertEqual(note.title, "Updated Title")
        XCTAssertEqual(note.preview, "Updated preview")
        XCTAssertTrue(note.hasAttachments)
        XCTAssertNotEqual(note.createdAt, .distantPast)
    }

    func testNoteListPresentationSortsAndBuildsDateSections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-13T12:00:00Z"))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: now))
        let lastWeek = try XCTUnwrap(calendar.date(byAdding: .day, value: -5, to: now))
        let files = [
            RecentMarkdownFile(id: "B.md", relativePath: "B.md", title: "Beta", modifiedAt: yesterday),
            RecentMarkdownFile(id: "A.md", relativePath: "A.md", title: "Alpha", modifiedAt: now),
            RecentMarkdownFile(id: "C.md", relativePath: "C.md", title: "Charlie", modifiedAt: lastWeek),
        ]

        XCTAssertEqual(NoteListPresentation.sorted(files, by: .title).map(\.title), ["Alpha", "Beta", "Charlie"])
        let sections = NoteListPresentation.sections(
            for: files,
            sortedBy: .modified,
            groupByDate: true,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(sections.map(\.id), ["today", "yesterday", "previous-7"])
        XCTAssertEqual(sections.flatMap(\.files).map(\.title), ["Alpha", "Beta", "Charlie"])
        XCTAssertEqual(
            NoteListPresentation.sections(for: files, sortedBy: .title, groupByDate: true).count,
            1
        )
    }

    func testPerformanceMaximumAttachmentDraftPreparation() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let attachmentData = Data(count: 4 * 1_024 * 1_024)
        let draft = CaptureDraft(
            body: "Maximum attachment performance fixture",
            attachments: (0..<CaptureAttachmentPolicy.maximumAttachmentCount).map { _ in
                .audio(data: attachmentData, preferredExtension: "m4a")
            }
        )

        measureAsync(timeout: 20) {
            let pending = try await store.preparePendingWrite(for: draft, root: root)
            XCTAssertEqual(pending.attachments.count, CaptureAttachmentPolicy.maximumAttachmentCount)
        }
    }

    private func measureAsync(
        timeout: TimeInterval = 10,
        operation: @escaping () async throws -> Void
    ) {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let completed = DispatchSemaphore(value: 0)
            var operationError: Error?
            Task {
                do {
                    try await operation()
                } catch {
                    operationError = error
                }
                completed.signal()
            }
            let waitResult = completed.wait(timeout: .now() + timeout)
            XCTAssertEqual(waitResult, .success, "Asynchronous performance iteration timed out")
            if let operationError {
                XCTFail("Performance fixture failed: \(operationError)")
            }
        }
    }

    private func XCTAssertThrowsErrorAsync<T>(
        _ expression: @autoclosure () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ errorHandler: (Error) -> Void
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected expression to throw", file: file, line: line)
        } catch {
            errorHandler(error)
        }
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MudsnoteCompanionTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static let onePixelPNG =
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
}
