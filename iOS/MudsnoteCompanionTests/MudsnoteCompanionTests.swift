import XCTest
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
