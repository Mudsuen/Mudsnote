import XCTest
import PencilKit
import UIKit
@testable import MudsnoteCompanion

final class MudsnoteCompanionTests: XCTestCase {
    func testCameraPhotoProducesAValidatedJPEGAttachment() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 18)).image { context in
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 24, height: 18))
        }

        let data = try CameraPhotoCapture.jpegData(for: image)
        let attachment = try CaptureAttachment.validatedImage(data: data)

        XCTAssertFalse(data.isEmpty)
        XCTAssertEqual(attachment.preferredExtension, "jpg")
    }

    func testCameraPhotoRejectsAnEmptyImage() {
        XCTAssertThrowsError(try CameraPhotoCapture.jpegData(for: UIImage())) { error in
            XCTAssertEqual(error as? CameraPhotoCapture.Error, .invalidImage)
        }
    }

    func testCameraVideoProducesAPortableVideoAttachment() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Camera Clip.mov")
        try Data([0x00, 0x01, 0x02]).write(to: url)

        let attachment = try CameraPhotoCapture.videoAttachment(at: url)

        XCTAssertEqual(attachment.referenceKind, .video)
        XCTAssertEqual(attachment.preferredExtension, "mov")
        XCTAssertEqual(attachment.filePrefix, "Camera Clip")
    }

    func testMarkdownTagSyntaxRewritesOnlyVisibleExactTags() throws {
        let markdown = """
        # Heading

        Visible #Project and #project.
        `#project` and ``#project`` stay code.
        https://example.com/#project and (#project) stay destinations.

        ~~~text
        #project
        ~~~
        """

        XCTAssertEqual(MarkdownTagSyntax.normalizedTag(" client-work "), "#client-work")
        XCTAssertEqual(MarkdownTagSyntax.normalizedTag("#项目_2"), "#项目_2")
        XCTAssertNil(MarkdownTagSyntax.normalizedTag("two words"))
        XCTAssertNil(MarkdownTagSyntax.normalizedTag("#bad/tag"))
        XCTAssertEqual(MarkdownTagSyntax.tags(in: markdown), ["#Project"])

        let renamed = try XCTUnwrap(MarkdownTagSyntax.rewriting(
            markdown,
            tag: "#PROJECT",
            mutation: .rename(to: "#client")
        ))
        XCTAssertEqual(renamed.occurrenceCount, 2)
        XCTAssertTrue(renamed.markdown.contains("Visible #client and #client."))
        XCTAssertTrue(renamed.markdown.contains("`#project` and ``#project``"))
        XCTAssertTrue(renamed.markdown.contains("https://example.com/#project and (#project)"))
        XCTAssertTrue(renamed.markdown.contains("~~~text\n#project\n~~~"))

        let deleted = try XCTUnwrap(MarkdownTagSyntax.rewriting(
            "before #project after\n#project #keep\nend #PROJECT",
            tag: "project",
            mutation: .delete
        ))
        XCTAssertEqual(deleted.occurrenceCount, 3)
        XCTAssertEqual(deleted.markdown, "before after\n#keep\nend")
    }

    func testTagMutationRenamesAndDeletesAcrossNotesAndInbox() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try "# Alpha\n\n#project #work\n`#project`\n".write(
            to: projects.appendingPathComponent("Alpha.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Beta\n\nReview #PROJECT.\n".write(
            to: projects.appendingPathComponent("Beta.md"),
            atomically: true,
            encoding: .utf8
        )
        let inboxURL = root.appendingPathComponent("Inbox.md")
        let inbox = try String(contentsOf: inboxURL, encoding: .utf8)
        try (inbox + "\n## 2026-07-15 07:10\n\nQuick #project\n").write(
            to: inboxURL,
            atomically: true,
            encoding: .utf8
        )
        let trashNote = root.appendingPathComponent(".mudsnote/Trash/hidden.md")
        try "#project\n".write(to: trashNote, atomically: true, encoding: .utf8)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        _ = try await store.loadLibrarySnapshot()
        let renamed = try await store.mutateTag("#Project", mutation: .rename(to: "#client"))

        XCTAssertEqual(renamed.occurrenceCount, 3)
        XCTAssertEqual(Set(renamed.changedPaths), [
            "Inbox.md",
            "Projects/Alpha.md",
            "Projects/Beta.md",
        ])
        XCTAssertTrue(
            try String(contentsOf: projects.appendingPathComponent("Alpha.md"), encoding: .utf8)
                .contains("#client #work\n`#project`")
        )
        XCTAssertTrue(
            try String(contentsOf: projects.appendingPathComponent("Beta.md"), encoding: .utf8)
                .contains("Review #client.")
        )
        XCTAssertTrue(try String(contentsOf: inboxURL, encoding: .utf8).contains("Quick #client"))
        XCTAssertEqual(try String(contentsOf: trashNote, encoding: .utf8), "#project\n")

        let snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.contains { $0.tags.contains("#client") })
        XCTAssertTrue(snapshot.inboxItems.contains { $0.tags == ["#client"] })

        let deleted = try await store.mutateTag("client", mutation: .delete)
        XCTAssertEqual(deleted.occurrenceCount, 3)
        XCTAssertFalse(try String(contentsOf: inboxURL, encoding: .utf8).contains("#client"))
        do {
            _ = try await store.mutateTag("#missing", mutation: .delete)
            XCTFail("Missing tags should not report a successful mutation")
        } catch {
            XCTAssertEqual(error as? MarkdownTagMutationError, .notFound)
        }
    }

    func testTagSelectionFilterSupportsAnyAllAndExclusions() {
        var filter = TagSelectionFilter()

        XCTAssertTrue(filter.matches(tags: ["#project"]))
        XCTAssertFalse(filter.matches(tags: []))

        filter.cycle("#project")
        XCTAssertEqual(filter.state(for: "#PROJECT"), .included)
        XCTAssertTrue(filter.matches(tags: ["#Project", "#work"]))
        XCTAssertFalse(filter.matches(tags: ["#quick"]))

        filter.cycle("#quick")
        XCTAssertTrue(filter.matches(tags: ["#quick"]))
        filter.matchMode = .all
        XCTAssertTrue(filter.matches(tags: ["#project", "#quick"]))
        XCTAssertFalse(filter.matches(tags: ["#project", "#work"]))

        filter.cycle("#quick")
        XCTAssertEqual(filter.state(for: "#quick"), .excluded)
        XCTAssertFalse(filter.matches(tags: ["#project", "#quick"]))
        XCTAssertTrue(filter.matches(tags: ["#project", "#work"]))

        filter.cycle("#quick")
        filter.clear()
        XCTAssertTrue(filter.isEmpty)
        XCTAssertTrue(filter.matches(tags: ["#work"]))
    }

    func testSmartFolderDefinitionNormalizesAndMatchesAllSupportedFilters() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z"))
        let recent = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: now))
        let old = try XCTUnwrap(calendar.date(byAdding: .day, value: -45, to: now))

        let normalized = try XCTUnwrap(SmartFolderDefinition(
            name: "  Active Projects  ",
            includedTags: ["project", "#PROJECT", "#work"],
            excludedTags: ["#archive", "#Project"],
            dateFilter: .editedPast7Days,
            attachmentFilter: .withAttachments,
            checklistFilter: .withUncheckedItems,
            pinned: true
        ).normalized)
        XCTAssertEqual(normalized.name, "Active Projects")
        XCTAssertEqual(normalized.includedTags, ["#project", "#work"])
        XCTAssertEqual(normalized.excludedTags, ["#archive"])
        XCTAssertEqual(normalized.filterCount, 7)

        let matchingFile = RecentMarkdownFile(
            id: "Plan.md",
            relativePath: "Plan.md",
            title: "Plan",
            modifiedAt: recent,
            createdAt: old,
            preview: "",
            hasAttachments: true,
            hasChecklist: true,
            hasUncheckedChecklist: true,
            isPinned: true,
            tags: ["#Project", "#work"]
        )
        XCTAssertTrue(normalized.matches(file: matchingFile, now: now, calendar: calendar))

        var rejected = matchingFile
        rejected.tags.append("#archive")
        XCTAssertFalse(normalized.matches(file: rejected, now: now, calendar: calendar))
        rejected = matchingFile
        rejected.hasUncheckedChecklist = false
        XCTAssertFalse(normalized.matches(file: rejected, now: now, calendar: calendar))

        let any = try XCTUnwrap(SmartFolderDefinition(
            name: "Any Project Signal",
            matchMode: .any,
            includedTags: ["#quick"],
            attachmentFilter: .withAttachments
        ).normalized)
        XCTAssertTrue(any.matches(file: matchingFile, now: now, calendar: calendar))

        let memo = MemoBlock(
            id: "memo",
            dateText: "2026-07-15 08:30",
            body: "- [ ] Follow up\n![Photo](Attachments/photo.png)",
            tags: ["#quick"]
        )
        XCTAssertTrue(any.matches(memo: memo, now: now, calendar: calendar))
        XCTAssertNil(SmartFolderDefinition(name: "No Filters").normalized)
        XCTAssertNil(SmartFolderDefinition(name: "Bad/Name", includedTags: ["#project"]).normalized)
    }

    func testSearchSuggestionsProduceStructuredScopedResultsWithoutFakeQueries() throws {
        let now = Date()
        let memoDateFormatter = DateFormatter()
        memoDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        memoDateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let attached = RecentMarkdownFile(
            id: "Attached.md",
            relativePath: "Projects/Attached.md",
            title: "Attached",
            modifiedAt: now,
            preview: "Reference file",
            hasAttachments: true
        )
        let pinned = RecentMarkdownFile(
            id: "Pinned.md",
            relativePath: "Pinned.md",
            title: "Pinned",
            modifiedAt: now.addingTimeInterval(-3 * 24 * 60 * 60),
            isPinned: true
        )
        let checklist = RecentMarkdownFile(
            id: "Checklist.md",
            relativePath: "Checklist.md",
            title: "Checklist",
            modifiedAt: now.addingTimeInterval(-120),
            hasChecklist: true,
            hasUncheckedChecklist: true
        )
        let memo = MemoBlock(
            id: "attachment-memo",
            dateText: memoDateFormatter.string(from: now),
            body: "Quick reference\n![Photo](Attachments/photo.png)",
            tags: []
        )
        let files = [attached, pinned, checklist]

        let allAttachments = NotesSearchSuggestion.attachments.results(
            files: files,
            memos: [memo],
            scope: .all,
            now: now
        )
        XCTAssertEqual(Set(allAttachments.map(\.id)), ["file:Projects/Attached.md", "memo:attachment-memo"])
        XCTAssertEqual(
            NotesSearchSuggestion.attachments.results(
                files: files,
                memos: [memo],
                scope: .notes,
                now: now
            ).map(\.id),
            ["file:Projects/Attached.md"]
        )
        XCTAssertEqual(
            NotesSearchSuggestion.attachments.results(
                files: files,
                memos: [memo],
                scope: .inbox,
                now: now
            ).map(\.id),
            ["memo:attachment-memo"]
        )
        XCTAssertEqual(
            NotesSearchSuggestion.pinned.results(
                files: files,
                memos: [memo],
                scope: .all,
                now: now
            ).map(\.id),
            ["file:Pinned.md"]
        )
        XCTAssertEqual(
            NotesSearchSuggestion.checklists.results(
                files: files,
                memos: [memo],
                scope: .all,
                now: now
            ).map(\.id),
            ["file:Checklist.md"]
        )
        XCTAssertEqual(
            Set(NotesSearchSuggestion.editedToday.results(
                files: files,
                memos: [memo],
                scope: .all,
                now: now
            ).map(\.id)),
            ["file:Projects/Attached.md", "file:Checklist.md", "memo:attachment-memo"]
        )
    }

    func testSmartFolderStorePersistsLifecycleWithoutMovingNotes() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let noteURL = root.appendingPathComponent("Project.md")
        let markdown = "# Project\n\nShip it. #project\n"
        try markdown.write(to: noteURL, atomically: true, encoding: .utf8)

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let created = try await store.createSmartFolder(SmartFolderDefinition(
            name: "Projects",
            includedTags: ["#project"]
        ))
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.smartFolders, [created])
        XCTAssertTrue(snapshot.smartFolders[0].matches(file: try XCTUnwrap(
            snapshot.allFiles.first { $0.relativePath == "Project.md" }
        )))
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), markdown)

        await XCTAssertThrowsErrorAsync(
            try await store.createSmartFolder(SmartFolderDefinition(
                name: "projects",
                includedTags: ["#work"]
            ))
        ) { error in
            XCTAssertEqual(error as? SmartFolderStoreError, .duplicateName)
        }

        var updated = created
        updated.name = "Active Projects"
        updated.matchMode = .any
        updated.includedTags.append("#work")
        _ = try await store.updateSmartFolder(updated)

        let reopenedStore = MarkdownFileStore()
        await reopenedStore.configure(root: root)
        snapshot = try await reopenedStore.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.smartFolders, [try XCTUnwrap(updated.normalized)])
        XCTAssertTrue(FileManager.default.fileExists(atPath: noteURL.path))

        try await reopenedStore.deleteSmartFolder(id: created.id)
        snapshot = try await reopenedStore.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.smartFolders.isEmpty)
        XCTAssertEqual(try String(contentsOf: noteURL, encoding: .utf8), markdown)
    }

    func testDamagedSmartFolderMetadataDoesNotBlockLibraryOrGetOverwritten() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let configurationURL = root.appendingPathComponent(".mudsnote/smart-folders.json")
        let damagedData = Data("not-json".utf8)
        try damagedData.write(to: configurationURL)
        try "# Still Available\n".write(
            to: root.appendingPathComponent("Available.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.smartFolders.isEmpty)
        XCTAssertTrue(snapshot.allFiles.contains { $0.relativePath == "Available.md" })
        XCTAssertEqual(try Data(contentsOf: configurationURL), damagedData)

        await XCTAssertThrowsErrorAsync(
            try await store.createSmartFolder(SmartFolderDefinition(
                name: "Projects",
                includedTags: ["#project"]
            ))
        ) { error in
            XCTAssertEqual(error as? SmartFolderStoreError, .damagedConfiguration)
        }
        XCTAssertEqual(try Data(contentsOf: configurationURL), damagedData)
    }

    @MainActor
    func testDrawingExportProducesBoundedPortablePNG() throws {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 20, y: 30),
                timeOffset: 0,
                size: CGSize(width: 5, height: 5),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 120, y: 80),
                timeOffset: 0.1,
                size: CGSize(width: 5, height: 5),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 220, y: 130),
                timeOffset: 0.2,
                size: CGSize(width: 5, height: 5),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        ]
        let stroke = PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
        let drawing = PKDrawing(strokes: [stroke])
        let data = try MarkdownDrawingExport.pngData(
            for: drawing,
            screenScale: 3
        )
        let image = try XCTUnwrap(UIImage(data: data))
        let pixelData = try XCTUnwrap(image.cgImage?.dataProvider?.data as Data?)

        XCTAssertEqual(data.prefix(8), Data([137, 80, 78, 71, 13, 10, 26, 10]))
        XCTAssertTrue(pixelData.contains { $0 < 200 }, "The exported PNG should contain visible ink")
        XCTAssertLessThanOrEqual(max(image.size.width * image.scale, image.size.height * image.scale), 4_096)
        XCTAssertThrowsError(try MarkdownDrawingExport.pngData(for: PKDrawing()))
    }

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
                MarkdownAttachmentReference(relativePath: "Attachments/2026/06/launch-test.mp4", kind: .video),
                MarkdownAttachmentReference(relativePath: "Attachments/2026/06/audio-test.m4a", kind: .audio)
            ],
            attachmentTags: ["#图片"],
            now: date
        )

        XCTAssertTrue(block.contains("## 2024-06-07"))
        XCTAssertTrue(block.contains("![Image](Attachments/2026/06/IMG-test.jpg)"))
        XCTAssertTrue(block.contains("[Video](Attachments/2026/06/launch-test.mp4)"))
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
        let video = try CaptureAttachment.validatedVideo(
            data: Data([0x04, 0x05, 0x06]),
            suggestedName: "Launch Clip.mp4"
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
            attachments: [image, video, audio, file],
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

    func testVideoAttachmentRejectsNonVideoSuffix() {
        XCTAssertThrowsError(
            try CaptureAttachment.validatedVideo(
                data: Data([0x01]),
                suggestedName: "Not a Movie.pdf"
            )
        ) { error in
            XCTAssertEqual(error as? CaptureAttachmentError, .unsupportedVideo)
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
        let largeVideo = try CaptureAttachment.validatedVideo(
            data: Data(
                count: CaptureAttachmentPolicy.maximumDraftBytes
                    - CaptureAttachmentPolicy.maximumAudioBytes + 1
            ),
            suggestedName: "Large.mov"
        )
        XCTAssertThrowsError(
            try CaptureAttachmentPolicy.validateAppending(largeVideo, to: [largeAudio])
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

    func testAttachmentInventoryLinksFilesBackToNotesAndRefreshesInboxOwners() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let attachments = root.appendingPathComponent("Attachments", isDirectory: true)
        try Data([0x01, 0x02]).write(to: attachments.appendingPathComponent("photo.png"))
        try Data([0x03, 0x04]).write(to: attachments.appendingPathComponent("voice.m4a"))
        try Data("document".utf8).write(to: attachments.appendingPathComponent("brief.txt"))
        try "# Project Brief\n\n![Photo](Attachments/photo.png)\n\n[Brief](Attachments/brief.txt)\n".write(
            to: root.appendingPathComponent("Project Brief.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Inbox\n\n## 2026-07-15 09:00\n\nVoice memo\n\n[Audio](Attachments/voice.m4a)\n".write(
            to: root.appendingPathComponent("Inbox.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        var snapshot = try await store.loadLibrarySnapshot()

        let photo = try XCTUnwrap(snapshot.attachments.first {
            $0.relativePath == "Attachments/photo.png"
        })
        XCTAssertEqual(photo.kind, .image)
        XCTAssertEqual(photo.owners.map(\.title), ["Project Brief"])
        XCTAssertEqual(photo.owners.map(\.destination), [.file("Project Brief.md")])
        let thumbnailData = try await store.loadAttachmentThumbnailData(
            relativePath: photo.relativePath
        )
        XCTAssertEqual(thumbnailData, Data([0x01, 0x02]))

        let voice = try XCTUnwrap(snapshot.attachments.first {
            $0.relativePath == "Attachments/voice.m4a"
        })
        XCTAssertEqual(voice.kind, .audio)
        XCTAssertEqual(voice.owners.map(\.destination), [.memo("2026-07-15 09:00-0")])

        try "# Inbox\n\n## 2026-07-15 09:00\n\nVoice memo without attachment\n".write(
            to: root.appendingPathComponent("Inbox.md"),
            atomically: true,
            encoding: .utf8
        )
        snapshot = try await store.loadInboxDeltaSnapshot()
        XCTAssertTrue(
            snapshot.attachments.first {
                $0.relativePath == "Attachments/voice.m4a"
            }?.owners.isEmpty == true
        )
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

    func testBatchRecentlyDeletedLifecyclePrevalidatesRestoresPinsAndDeletes() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        for folder in ["A", "B"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
            try "# \(folder)\n".write(
                to: root.appendingPathComponent("\(folder)/Same.md"),
                atomically: true,
                encoding: .utf8
            )
        }

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.setPinned(true, relativePaths: ["A/Same.md", "B/Same.md"])
        let trashed = try await store.trashMarkdownDocuments(
            relativePaths: ["A/Same.md", "B/Same.md"]
        )
        let missingID = UUID().uuidString.lowercased()

        await XCTAssertThrowsErrorAsync(
            try await store.restoreTrashedMarkdownDocuments(
                ids: [trashed[0].id, missingID]
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .noteNotFound)
        }
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.trashedFiles.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A/Same.md").path))

        try "# Replacement\n".write(
            to: root.appendingPathComponent("A/Same.md"),
            atomically: true,
            encoding: .utf8
        )
        let restored = try await store.restoreTrashedMarkdownDocuments(ids: trashed.map(\.id))
        XCTAssertEqual(Set(restored.map(\.relativePath)), ["A/Same 2.md", "B/Same.md"])
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.trashedFiles.isEmpty)
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == "A/Same 2.md" }?.isPinned == true)
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == "B/Same.md" }?.isPinned == true)

        let retrash = try await store.trashMarkdownDocuments(
            relativePaths: restored.map(\.relativePath)
        )
        await XCTAssertThrowsErrorAsync(
            try await store.permanentlyDeleteTrashedMarkdownDocuments(
                ids: [retrash[0].id, missingID]
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .noteNotFound)
        }
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.trashedFiles.count, 2)

        try await store.permanentlyDeleteTrashedMarkdownDocuments(ids: retrash.map(\.id))
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.trashedFiles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("A/Same 2.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("B/Same.md").path))
    }

    func testInterruptedBatchPermanentDeleteStagingRecoversOnRefresh() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try "# Recover me\n".write(
            to: root.appendingPathComponent("Recover.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let trashed = try await store.trashMarkdownDocument(relativePath: "Recover.md")
        let trashRoot = root.appendingPathComponent(".mudsnote/Trash", isDirectory: true)
        let staging = trashRoot.appendingPathComponent(".delete-interrupted", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        for suffix in ["md", "json"] {
            let name = "\(trashed.id.lowercased()).\(suffix)"
            try FileManager.default.moveItem(
                at: trashRoot.appendingPathComponent(name),
                to: staging.appendingPathComponent(name)
            )
        }

        let snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.trashedFiles.map(\.id), [trashed.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: trashRoot.appendingPathComponent("\(trashed.id.lowercased()).md").path
        ))
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

    func testFolderMoveRewritesPinnedAndRecentlyDeletedPaths() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Archive/Sub", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Active\n".write(
            to: root.appendingPathComponent("Archive/Sub/Active.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Deleted\n".write(
            to: root.appendingPathComponent("Archive/Sub/Deleted.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.setPinned(true, relativePath: "Archive/Sub/Active.md")
        let trashed = try await store.trashMarkdownDocument(
            relativePath: "Archive/Sub/Deleted.md"
        )

        let moved = try await store.moveFolder(
            relativePath: "Archive",
            toParent: "Projects"
        )
        XCTAssertEqual(moved, "Projects/Archive")
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(
            snapshot.allFiles.first { $0.relativePath == "Projects/Archive/Sub/Active.md" }?.isPinned == true
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Archive").path))

        let restored = try await store.restoreTrashedMarkdownDocument(id: trashed.id)
        XCTAssertEqual(restored.relativePath, "Projects/Archive/Sub/Deleted.md")
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.contains { $0.relativePath == restored.relativePath })

        await XCTAssertThrowsErrorAsync(
            try await store.moveFolder(
                relativePath: "Projects",
                toParent: "Projects/Archive/Sub"
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .invalidFolder)
        }
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

    func testRenameNoteAvoidsCollisionsPreservesContentAndPinState() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        let markdown = "# Plan\n\nPortable body\n"
        try markdown.write(
            to: root.appendingPathComponent("Projects/Plan.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Existing\n".write(
            to: root.appendingPathComponent("Projects/Roadmap.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.setPinned(true, relativePath: "Projects/Plan.md")
        let renamed = try await store.renameMarkdownDocument(
            relativePath: "Projects/Plan.md",
            to: "Roadmap"
        )

        XCTAssertEqual(renamed.relativePath, "Projects/Roadmap 2.md")
        XCTAssertEqual(
            try String(
                contentsOf: root.appendingPathComponent(renamed.relativePath),
                encoding: .utf8
            ),
            markdown
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Projects/Plan.md").path
        ))
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.first {
            $0.relativePath == renamed.relativePath
        }?.isPinned == true)

        let final = try await store.renameMarkdownDocument(
            relativePath: renamed.relativePath,
            to: "Final.md"
        )
        XCTAssertEqual(final.relativePath, "Projects/Final.md")
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.first {
            $0.relativePath == final.relativePath
        }?.isPinned == true)

        await XCTAssertThrowsErrorAsync(
            try await store.renameMarkdownDocument(
                relativePath: final.relativePath,
                to: "../Escape"
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .invalidNoteName)
        }
        await XCTAssertThrowsErrorAsync(
            try await store.renameMarkdownDocument(
                relativePath: "Inbox.md",
                to: "Renamed"
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .protectedNote)
        }
    }

    func testDuplicateNotePreservesMarkdownWithoutCopyingPinState() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        let markdown = "# Plan\n\n[Brief](Attachments/shared.txt)\n"
        try markdown.write(
            to: root.appendingPathComponent("Projects/Plan.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data("shared".utf8).write(to: root.appendingPathComponent("Attachments/shared.txt"))

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.setPinned(true, relativePath: "Projects/Plan.md")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await store.duplicateMarkdownDocument(
            relativePath: "Projects/Plan.md",
            now: now
        )
        let second = try await store.duplicateMarkdownDocument(
            relativePath: "Projects/Plan.md",
            now: now.addingTimeInterval(1)
        )

        XCTAssertEqual(first.relativePath, "Projects/Plan Copy.md")
        XCTAssertEqual(second.relativePath, "Projects/Plan Copy 2.md")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(first.relativePath), encoding: .utf8),
            markdown
        )
        let snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == "Projects/Plan.md" }?.isPinned == true)
        XCTAssertFalse(snapshot.allFiles.first { $0.relativePath == first.relativePath }?.isPinned == true)
        XCTAssertFalse(snapshot.allFiles.first { $0.relativePath == second.relativePath }?.isPinned == true)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("Attachments/shared.txt")),
            Data("shared".utf8)
        )
    }

    func testConflictCopyRecoveryAvoidsOverwriteAndPreservesPinAndContent() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Original\n".write(
            to: root.appendingPathComponent("Projects/Plan.md"),
            atomically: true,
            encoding: .utf8
        )
        let conflictMarkdown = "# Conflict version\n\nKeep every edit.\n"
        try conflictMarkdown.write(
            to: root.appendingPathComponent("Projects/Plan conflicted copy.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Ordinary note\n".write(
            to: root.appendingPathComponent("Projects/Conflict Resolution.md"),
            atomically: true,
            encoding: .utf8
        )
        try Data("not markdown".utf8).write(
            to: root.appendingPathComponent("Projects/file conflicted copy.txt")
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        try await store.setPinned(true, relativePath: "Projects/Plan conflicted copy.md")
        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.conflictWarnings, ["Projects/Plan conflicted copy.md"])

        let recovered = try await store.keepConflictCopy(
            relativePath: "Projects/Plan conflicted copy.md"
        )

        XCTAssertEqual(recovered.relativePath, "Projects/Plan 2.md")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent(recovered.relativePath), encoding: .utf8),
            conflictMarkdown
        )
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("Projects/Plan.md"), encoding: .utf8),
            "# Original\n"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("Projects/Plan conflicted copy.md").path
            )
        )
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.conflictWarnings.isEmpty)
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == recovered.relativePath }?.isPinned == true)
    }

    func testBatchNoteLifecycleMovesPinsAndRejectsProtectedSelectionAtomically() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        for folder in ["A", "B", "Archive"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(folder, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        try "# First\n".write(
            to: root.appendingPathComponent("A/Same.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Second\n".write(
            to: root.appendingPathComponent("B/Same.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Protected\n".write(
            to: root.appendingPathComponent("Daily/Protected.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let originalPaths = ["A/Same.md", "B/Same.md"]
        try await store.setPinned(true, relativePaths: originalPaths)
        let moved = try await store.moveMarkdownDocuments(
            relativePaths: originalPaths,
            toFolder: "Archive"
        )
        let movedPaths = moved.map(\.relativePath)
        XCTAssertEqual(Set(movedPaths), Set(["Archive/Same.md", "Archive/Same 2.md"]))

        var snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(
            snapshot.allFiles.filter { movedPaths.contains($0.relativePath) }
                .allSatisfy(\.isPinned)
        )
        await XCTAssertThrowsErrorAsync(
            try await store.trashMarkdownDocuments(
                relativePaths: [movedPaths[0], "Daily/Protected.md"]
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownLifecycleError, .protectedNote)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(movedPaths[0]).path))
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertTrue(snapshot.trashedFiles.isEmpty)

        try await store.setPinned(false, relativePaths: movedPaths)
        let trashed = try await store.trashMarkdownDocuments(relativePaths: movedPaths)
        XCTAssertEqual(trashed.count, 2)
        snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.trashedFiles.count, 2)
        XCTAssertFalse(snapshot.allFiles.contains { movedPaths.contains($0.relativePath) })
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

    func testAttachmentReferenceSearchParserIgnoresCodeAndTraversal() {
        let markdown = """
        ![Receipt](Attachments/receipt%202026.png)
        [Scan](Attachments/report.pdf)
        ![[Attachments/handwriting.jpg]]
        ![Duplicate](Attachments/receipt%202026.png)
        [Outside](../Secrets/private.pdf)
        ```markdown
        ![Example](Attachments/not-real.png)
        ```
        """

        XCTAssertEqual(
            MarkdownAttachmentSearch.relativePaths(in: markdown),
            [
                "Attachments/receipt 2026.png",
                "Attachments/report.pdf",
                "Attachments/handwriting.jpg",
            ]
        )
    }

    func testFindInNoteAttachmentMatchesOnlyReferencedDocumentsInBlockOrder() {
        let blocks = MarkdownRenderBlock.parse("""
        # Trip

        ![Receipt](Attachments/receipt.png)

        [Scan](Attachments/report.pdf)
        """)
        let matches = NoteFindIndex.attachmentMatches(
            in: blocks,
            documents: [
                AttachmentSearchDocument(
                    relativePath: "Attachments/report.pdf",
                    text: "The ORBITAL total is 428. ORBITAL is approved."
                ),
                AttachmentSearchDocument(
                    relativePath: "Attachments/receipt.png",
                    text: "ORBITAL receipt"
                ),
                AttachmentSearchDocument(
                    relativePath: "Attachments/unreferenced.png",
                    text: "ORBITAL must not appear"
                ),
            ],
            query: "orbital"
        )

        XCTAssertEqual(matches.map(\.relativePath), [
            "Attachments/receipt.png",
            "Attachments/report.pdf",
            "Attachments/report.pdf",
        ])
        XCTAssertEqual(matches.map(\.occurrence), [0, 0, 1])
        XCTAssertTrue(matches.allSatisfy { $0.context.localizedCaseInsensitiveContains("orbital") })
    }

    func testAttachmentOCRSearchCombinesNoteMetadataAndCachedRecognizedText() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let attachment = root.appendingPathComponent("Attachments/receipt.png")
        try Data([0x01]).write(to: attachment, options: .atomic)
        try "# Quarterly Review\n\n![Receipt](Attachments/receipt.png)\n".write(
            to: root.appendingPathComponent("Quarterly Review.md"),
            atomically: true,
            encoding: .utf8
        )
        let recognizer = StubAttachmentTextRecognizer(text: "Project Orbital invoice total 428")
        let cacheURL = root.appendingPathComponent(".test-cache/attachment-text.json")
        let index = AttachmentTextIndex(recognizer: recognizer, cacheURL: cacheURL)
        let store = MarkdownFileStore(attachmentTextIndex: index)
        await store.configure(root: root)
        _ = try await store.loadLibrarySnapshot()

        let combined = try await store.search(query: "quarterly orbital")
        XCTAssertEqual(combined.count, 1)
        XCTAssertEqual(
            combined.first?.location,
            "Quarterly Review.md · receipt.png"
        )
        XCTAssertEqual(combined.first?.context, "Project Orbital invoice total 428")
        _ = try await store.search(query: "orbital")
        let cachedCallCount = await recognizer.callCount()
        XCTAssertEqual(cachedCallCount, 1)

        let restoredRecognizer = StubAttachmentTextRecognizer(
            text: "Project Orbital invoice total 428"
        )
        let restoredIndex = AttachmentTextIndex(
            recognizer: restoredRecognizer,
            cacheURL: cacheURL
        )
        let restoredStore = MarkdownFileStore(attachmentTextIndex: restoredIndex)
        await restoredStore.configure(root: root)
        _ = try await restoredStore.loadLibrarySnapshot()
        let restoredResults = try await restoredStore.search(query: "orbital")
        XCTAssertEqual(restoredResults.count, 1)
        let restoredCacheCallCount = await restoredRecognizer.callCount()
        XCTAssertEqual(restoredCacheCallCount, 0)

        try Data([0x01, 0x02]).write(to: attachment, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)],
            ofItemAtPath: attachment.path
        )
        _ = try await restoredStore.search(query: "orbital")
        let invalidatedCallCount = await restoredRecognizer.callCount()
        XCTAssertEqual(invalidatedCallCount, 1)
    }

    func testVisionRecognizerReadsLargePrintedAttachmentText() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("ocr.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1_400, height: 420)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_400, height: 420))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 112, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            NSString(string: "ORBITAL 428").draw(
                at: CGPoint(x: 80, y: 120),
                withAttributes: attributes
            )
        }
        try XCTUnwrap(image.pngData()).write(to: url, options: .atomic)

        let text = try await VisionAttachmentTextRecognizer().recognizeText(at: url)

        XCTAssertTrue(text.localizedCaseInsensitiveContains("ORBITAL"))
        XCTAssertTrue(text.contains("428"))

        let pdfURL = root.appendingPathComponent("scan.pdf")
        let pdfBounds = CGRect(x: 0, y: 0, width: 1_200, height: 500)
        let pdfData = UIGraphicsPDFRenderer(bounds: pdfBounds).pdfData { renderer in
            renderer.beginPage()
            UIColor.white.setFill()
            renderer.cgContext.fill(pdfBounds)
            NSString(string: "NEBULA 731").draw(
                at: CGPoint(x: 80, y: 150),
                withAttributes: [
                    .font: UIFont.systemFont(ofSize: 104, weight: .bold),
                    .foregroundColor: UIColor.black,
                ]
            )
        }
        try pdfData.write(to: pdfURL, options: .atomic)

        let pdfText = try await VisionAttachmentTextRecognizer().recognizeText(at: pdfURL)

        XCTAssertTrue(pdfText.localizedCaseInsensitiveContains("NEBULA"))
        XCTAssertTrue(pdfText.contains("731"))
    }

    func testSearchHighlightingMatchesMultipleTermsWithoutCaseOrDiacriticSensitivity() {
        let text = "Résumé restore RESTORE"
        let matches = SearchHighlighting.ranges(
            in: text,
            query: "resume restore"
        ).map { String(text[$0]) }

        XCTAssertEqual(matches, ["Résumé", "restore", "RESTORE"])
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
        XCTAssertEqual(try Data(contentsOf: preview.url), bytes)
        XCTAssertEqual(preview.relativePath, "Attachments/preview.png")
        XCTAssertTrue(preview.url.path.hasPrefix(FileManager.default.temporaryDirectory.path))
        XCTAssertFalse(preview.isPDF)

        do {
            _ = try await store.prepareAttachmentPreview(relativePath: "../outside.png")
            XCTFail("Path traversal should be rejected")
        } catch {
            XCTAssertEqual(error as? AttachmentPreviewError, .invalidPath)
        }
    }

    func testPDFPreviewMarkupCommitsAtomicallyAndRejectsExternalChanges() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let attachment = root.appendingPathComponent("Attachments/scan.pdf")
        let original = Data("%PDF-1.7 original".utf8)
        try original.write(to: attachment, options: .atomic)
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let preview = try await store.prepareAttachmentPreview(
            relativePath: "Attachments/scan.pdf"
        )
        XCTAssertTrue(preview.isPDF)
        let unchanged = try await store.commitEditedAttachmentPreview(
            preview,
            editedURL: preview.url
        )
        XCTAssertFalse(unchanged)
        let edited = Data("%PDF-1.7 annotated".utf8)
        try edited.write(to: preview.url, options: .atomic)
        let committed = try await store.commitEditedAttachmentPreview(
            preview,
            editedURL: preview.url
        )
        XCTAssertTrue(committed)
        XCTAssertEqual(try Data(contentsOf: attachment), edited)

        let stalePreview = try await store.prepareAttachmentPreview(
            relativePath: "Attachments/scan.pdf"
        )
        let external = Data("%PDF-1.7 external".utf8)
        try external.write(to: attachment, options: .atomic)
        try Data("%PDF-1.7 stale markup".utf8).write(
            to: stalePreview.url,
            options: .atomic
        )
        do {
            _ = try await store.commitEditedAttachmentPreview(
                stalePreview,
                editedURL: stalePreview.url
            )
            XCTFail("External attachment edits must not be overwritten")
        } catch {
            XCTAssertEqual(error as? AttachmentPreviewError, .changedExternally)
        }
        XCTAssertEqual(try Data(contentsOf: attachment), external)
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
        let expectedModifiedAt = Date(timeIntervalSince1970: 1_717_777_777)
        var resourceValues = URLResourceValues()
        resourceValues.contentModificationDate = expectedModifiedAt
        var mutableDocumentURL = documentURL
        try mutableDocumentURL.setResourceValues(resourceValues)
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let document = try await store.loadMarkdownDocument(relativePath: "Projects/Launch.md")
        XCTAssertEqual(document.title, "Launch")
        XCTAssertEqual(document.relativePath, "Projects/Launch.md")
        XCTAssertTrue(document.markdown.contains("Commercial-ready reader"))
        XCTAssertEqual(try XCTUnwrap(document.modifiedAt).timeIntervalSince1970,
                       expectedModifiedAt.timeIntervalSince1970,
                       accuracy: 1)

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
        let actualModifiedAt = try documentURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        XCTAssertEqual(saved.modifiedAt, actualModifiedAt)

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

    func testMarkdownDocumentStoresPortableRecordedAudioAttachment() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let documentURL = root.appendingPathComponent("Projects/Meeting.md")
        try FileManager.default.createDirectory(
            at: documentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Meeting\n".write(to: documentURL, atomically: true, encoding: .utf8)
        let audioData = Data([0x00, 0x01, 0x02, 0x03])
        let audio = try CaptureAttachment.validatedAudio(data: audioData)
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let original = try await store.loadMarkdownDocument(relativePath: "Projects/Meeting.md")
        let now = try XCTUnwrap(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 7,
            day: 13,
            hour: 19,
            minute: 30
        )))

        let updated = try await store.attachToMarkdownDocument(
            relativePath: original.relativePath,
            markdown: original.markdown,
            expectedMarkdown: original.markdown,
            attachment: audio,
            now: now
        )

        let relativePath = "Attachments/2026/07/audio-20260713-193000.m4a"
        XCTAssertTrue(updated.markdown.contains("[Audio](\(relativePath))"))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(relativePath)), audioData)
        let snapshot = try await store.loadLibrarySnapshot()
        XCTAssertEqual(snapshot.attachments.first { $0.relativePath == relativePath }?.kind, .audio)
        XCTAssertTrue(snapshot.allFiles.first { $0.relativePath == original.relativePath }?.hasAttachments == true)
    }

    func testRecordedAudioTranscriptPersistsAsEditableSearchableMarkdown() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let documentURL = root.appendingPathComponent("Meeting.md")
        try "# Meeting\n".write(to: documentURL, atomically: true, encoding: .utf8)
        let store = MarkdownFileStore()
        await store.configure(root: root)
        let original = try await store.loadMarkdownDocument(relativePath: "Meeting.md")
        let attached = try await store.attachToMarkdownDocument(
            relativePath: original.relativePath,
            markdown: original.markdown,
            expectedMarkdown: original.markdown,
            attachment: try CaptureAttachment.validatedAudio(data: Data([0x01, 0x02]))
        )
        let transcript = MarkdownAudioTranscript.appending(
            "Project ORBITAL is approved.",
            to: attached.markdown
        )
        let saved = try await store.saveMarkdownDocument(
            relativePath: attached.relativePath,
            markdown: transcript,
            expectedMarkdown: attached.markdown
        )

        XCTAssertTrue(saved.markdown.contains("[Audio](Attachments/"))
        XCTAssertTrue(saved.markdown.contains("### Audio transcription"))
        XCTAssertTrue(saved.markdown.contains("Project ORBITAL is approved."))
        XCTAssertEqual(
            MarkdownAudioTranscript.appending("  \n", to: saved.markdown),
            saved.markdown
        )
        let results = try await store.search(query: "orbital")
        XCTAssertEqual(results.map(\.location), ["Meeting.md"])
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

    func testAttachmentRenameMovesFileAndProtectsSharedReferences() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Files\n".write(
            to: root.appendingPathComponent("Projects/Files.md"),
            atomically: true,
            encoding: .utf8
        )
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
        let attached = try await store.attachToMarkdownDocument(
            relativePath: original.relativePath,
            markdown: original.markdown,
            expectedMarkdown: original.markdown,
            attachment: attachment,
            now: now
        )
        let oldPath = "Attachments/2026/07/Launch Brief-20260713-120000.pdf"
        let oldLine = "[Launch Brief-20260713-120000.pdf](\(oldPath))"

        let renamed = try await store.renameAttachmentInMarkdownDocument(
            relativePath: attached.relativePath,
            markdown: attached.markdown,
            expectedMarkdown: attached.markdown,
            attachmentLine: oldLine,
            attachmentRelativePath: oldPath,
            to: "Investor Brief.pdf"
        )
        let newPath = "Attachments/2026/07/Investor Brief.pdf"
        XCTAssertTrue(renamed.markdown.contains("[Investor Brief.pdf](\(newPath))"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(oldPath).path))
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent(newPath)),
            Data("portable pdf".utf8)
        )

        try "[Shared](\(newPath))\n".write(
            to: root.appendingPathComponent("Projects/Shared.md"),
            atomically: true,
            encoding: .utf8
        )
        await XCTAssertThrowsErrorAsync(
            try await store.renameAttachmentInMarkdownDocument(
                relativePath: renamed.relativePath,
                markdown: renamed.markdown,
                expectedMarkdown: renamed.markdown,
                attachmentLine: "[Investor Brief.pdf](\(newPath))",
                attachmentRelativePath: newPath,
                to: "Unsafe Rename"
            )
        ) { error in
            XCTAssertEqual(error as? MarkdownDocumentError, .attachmentReferencedElsewhere)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(newPath).path))
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
            - [ ] Publish the release notes
            Follow up with the release notes.
            #release #发布 #Release
            `#inline-code`
            ```swift
            #ignored-code
            ```
            """,
            fallbackTitle: "Fallback"
        )

        XCTAssertEqual(metadata.title, "Launch Plan")
        XCTAssertEqual(metadata.preview, "Ship the iPhone build Publish the release notes Follow up with the release notes.")
        XCTAssertTrue(metadata.hasAttachments)
        XCTAssertEqual(metadata.galleryImagePath, "Attachments/cover.png")
        XCTAssertEqual(
            metadata.galleryChecklistItems,
            [
                MarkdownGalleryChecklistItem(text: "Ship the iPhone build", isChecked: true),
                MarkdownGalleryChecklistItem(text: "Publish the release notes", isChecked: false),
            ]
        )
        XCTAssertTrue(metadata.hasChecklist)
        XCTAssertTrue(metadata.hasUncheckedChecklist)
        XCTAssertEqual(Set(metadata.tags), Set(["#release", "#发布"]))
        let unchecked = MarkdownListMetadata.extract(
            from: "- [ ] Follow up",
            fallbackTitle: "Task"
        )
        XCTAssertTrue(unchecked.hasChecklist)
        XCTAssertTrue(unchecked.hasUncheckedChecklist)
        XCTAssertEqual(
            MarkdownListMetadata.extract(from: "Plain body", fallbackTitle: "File Name").title,
            "Plain body"
        )
    }

    func testLibrarySnapshotIndexesTagsFromOrdinaryMarkdownNotes() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "# Tagged Plan\n\nShip it. #project #发布\n".write(
            to: root.appendingPathComponent("Projects/Tagged Plan.md"),
            atomically: true,
            encoding: .utf8
        )

        let store = MarkdownFileStore()
        await store.configure(root: root)
        let snapshot = try await store.loadLibrarySnapshot()
        let file = try XCTUnwrap(
            snapshot.allFiles.first { $0.relativePath == "Projects/Tagged Plan.md" }
        )
        XCTAssertEqual(Set(file.tags), Set(["#project", "#发布"]))
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

    func testMarkdownHeadingSectionsCollapseByLevelAndRevealFindTargets() {
        let blocks: [MarkdownRenderBlock] = [
            .line("# Plan"),
            .line("Overview"),
            .line("## Tasks"),
            .line("Ship the app"),
            .line("# Notes"),
            .line("Done")
        ]

        XCTAssertEqual(MarkdownHeading("# Plan"), MarkdownHeading(level: 1, title: "Plan"))
        XCTAssertNil(MarkdownHeading("#tag"))
        XCTAssertTrue(MarkdownSectionProjection.hasCollapsibleContent(after: 0, in: blocks))
        XCTAssertTrue(MarkdownSectionProjection.hasCollapsibleContent(after: 2, in: blocks))
        XCTAssertEqual(
            MarkdownSectionProjection.visibleIndices(in: blocks, collapsed: [0]),
            [0, 4, 5]
        )
        XCTAssertEqual(
            MarkdownSectionProjection.visibleIndices(in: blocks, collapsed: [2]),
            [0, 1, 2, 4, 5]
        )
        XCTAssertEqual(
            MarkdownSectionProjection.collapsedHeadings(
                containing: 3,
                in: blocks,
                collapsed: [0, 2]
            ),
            [0, 2]
        )
        XCTAssertEqual(
            MarkdownSectionProjection.collapsedHeadings(
                containing: 5,
                in: blocks,
                collapsed: [0, 2]
            ),
            []
        )
    }

    func testInlineMarkdownFormattingTogglesInsteadOfNestingMarkers() throws {
        let wrapped = try XCTUnwrap(MarkdownInlineEditing.toggleEdit(
            in: "Ship it",
            selection: NSRange(location: 0, length: 4),
            prefix: "~~",
            suffix: "~~",
            placeholder: "strikethrough"
        ))
        XCTAssertEqual(wrapped.range, NSRange(location: 0, length: 4))
        XCTAssertEqual(wrapped.replacement, "~~Ship~~")
        XCTAssertEqual(wrapped.selection, NSRange(location: 2, length: 4))

        let unwrappedContent = try XCTUnwrap(MarkdownInlineEditing.toggleEdit(
            in: "~~Ship~~ it",
            selection: NSRange(location: 2, length: 4),
            prefix: "~~",
            suffix: "~~",
            placeholder: "strikethrough"
        ))
        XCTAssertEqual(unwrappedContent.range, NSRange(location: 0, length: 8))
        XCTAssertEqual(unwrappedContent.replacement, "Ship")
        XCTAssertEqual(unwrappedContent.selection, NSRange(location: 0, length: 4))

        let unwrappedMarkers = try XCTUnwrap(MarkdownInlineEditing.toggleEdit(
            in: "~~Ship~~ it",
            selection: NSRange(location: 0, length: 8),
            prefix: "~~",
            suffix: "~~",
            placeholder: "strikethrough"
        ))
        XCTAssertEqual(unwrappedMarkers.replacement, "Ship")
        XCTAssertEqual(unwrappedMarkers.selection, NSRange(location: 0, length: 4))

        let placeholder = try XCTUnwrap(MarkdownInlineEditing.toggleEdit(
            in: "",
            selection: NSRange(location: 0, length: 0),
            prefix: "**",
            suffix: "**",
            placeholder: "bold"
        ))
        XCTAssertEqual(placeholder.replacement, "**bold**")
        XCTAssertEqual(placeholder.selection, NSRange(location: 2, length: 4))

        let underline = try XCTUnwrap(MarkdownInlineEditing.toggleEdit(
            in: "Important",
            selection: NSRange(location: 0, length: 9),
            prefix: "<u>",
            suffix: "</u>",
            placeholder: "underline"
        ))
        XCTAssertEqual(underline.replacement, "<u>Important</u>")
        XCTAssertEqual(underline.selection, NSRange(location: 3, length: 9))

        let highlight = try XCTUnwrap(MarkdownInlineEditing.toggleEdit(
            in: "Notice",
            selection: NSRange(location: 0, length: 6),
            prefix: "<mark>",
            suffix: "</mark>",
            placeholder: "highlight"
        ))
        XCTAssertEqual(highlight.replacement, "<mark>Notice</mark>")
        XCTAssertEqual(highlight.selection, NSRange(location: 6, length: 6))

        let unhighlight = try XCTUnwrap(MarkdownInlineEditing.toggleEdit(
            in: "<mark>Notice</mark>",
            selection: NSRange(location: 6, length: 6),
            prefix: "<mark>",
            suffix: "</mark>",
            placeholder: "highlight"
        ))
        XCTAssertEqual(unhighlight.replacement, "Notice")
        XCTAssertEqual(unhighlight.selection, NSRange(location: 0, length: 6))
    }

    func testInlineHTMLFormattingRendersAndIndexesWithoutLeakingMarkers() {
        let rendered = NSAttributedString(
            MarkdownInlineRendering.attributedText(
                for: "**Bold** and <u>underlined</u> plus <mark>highlighted</mark> with [Link](https://example.com)"
            )
        )
        XCTAssertEqual(rendered.string, "Bold and underlined plus highlighted with Link")
        let underlinedRange = (rendered.string as NSString).range(of: "underlined")
        XCTAssertEqual(
            rendered.attribute(
                .underlineStyle,
                at: underlinedRange.location,
                effectiveRange: nil
            ) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        let highlightedRange = (rendered.string as NSString).range(of: "highlighted")
        XCTAssertNotNil(
            rendered.attribute(
                .backgroundColor,
                at: highlightedRange.location,
                effectiveRange: nil
            ) as? UIColor
        )
        XCTAssertEqual(
            NoteFindIndex.visibleText(for: "Find <u>important</u> and <mark>urgent</mark> text"),
            "Find important and urgent text"
        )

        let metadata = MarkdownListMetadata.extract(
            from: "<mark>Important title</mark>\n\nKeep <u>this preview</u> <mark>clean</mark>",
            fallbackTitle: "Fallback"
        )
        XCTAssertEqual(metadata.title, "Important title")
        XCTAssertEqual(metadata.preview, "Keep this preview clean")
    }

    func testRenderedMarkdownDetectsActionableContentWithoutOverridingExplicitLinks() throws {
        let rendered = NSAttributedString(
            MarkdownInlineRendering.attributedText(
                for: "Email support@example.com, call +1 (415) 555-0123, visit 1 Apple Park Way, Cupertino, CA 95014, or use [Help](https://muds.top/help)."
            )
        )
        let source = rendered.string as NSString
        let emailRange = source.range(of: "support@example.com")
        let phoneRange = source.range(of: "+1 (415) 555-0123")
        let addressRange = source.range(of: "1 Apple Park Way, Cupertino, CA 95014")
        let helpRange = source.range(of: "Help")

        let emailURL = try XCTUnwrap(
            rendered.attribute(.link, at: emailRange.location, effectiveRange: nil) as? URL
        )
        XCTAssertEqual(emailURL.absoluteString, "mailto:support@example.com")
        XCTAssertEqual(
            rendered.attribute(.underlineStyle, at: emailRange.location, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )

        let phoneURL = try XCTUnwrap(
            rendered.attribute(.link, at: phoneRange.location, effectiveRange: nil) as? URL
        )
        XCTAssertEqual(phoneURL.absoluteString, "tel:+14155550123")
        XCTAssertEqual(
            rendered.attribute(.underlineStyle, at: phoneRange.location, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )

        let addressURL = try XCTUnwrap(
            rendered.attribute(.link, at: addressRange.location, effectiveRange: nil) as? URL
        )
        XCTAssertEqual(addressURL.host, "maps.apple.com")
        XCTAssertEqual(
            URLComponents(url: addressURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "q" })?.value,
            "1 Apple Park Way, Cupertino, CA 95014"
        )

        let explicitURL = try XCTUnwrap(
            rendered.attribute(.link, at: helpRange.location, effectiveRange: nil) as? URL
        )
        XCTAssertEqual(explicitURL.absoluteString, "https://muds.top/help")
    }

    func testMarkdownLinkEditingAddsUpdatesAndRemovesPortableLinks() throws {
        let selectedDraft = try XCTUnwrap(MarkdownLinkEditing.draft(
            in: "Read Mudsnote today",
            selection: NSRange(location: 5, length: 8)
        ))
        XCTAssertEqual(selectedDraft.label, "Mudsnote")
        XCTAssertFalse(selectedDraft.isExisting)

        let inserted = try XCTUnwrap(MarkdownLinkEditing.insertionEdit(
            for: selectedDraft,
            label: selectedDraft.label,
            destination: "muds.top/docs (ios)"
        ))
        XCTAssertEqual(
            inserted.replacement,
            "[Mudsnote](https://muds.top/docs%20%28ios%29)"
        )
        XCTAssertEqual(inserted.selection, NSRange(location: 6, length: 8))

        let existingMarkdown = "Read [Mudsnote](https://muds.top) today"
        let existingDraft = try XCTUnwrap(MarkdownLinkEditing.draft(
            in: existingMarkdown,
            selection: NSRange(location: 9, length: 0)
        ))
        XCTAssertTrue(existingDraft.isExisting)
        XCTAssertEqual(existingDraft.label, "Mudsnote")
        XCTAssertEqual(existingDraft.destination, "https://muds.top")

        let updated = try XCTUnwrap(MarkdownLinkEditing.insertionEdit(
            for: existingDraft,
            label: "Mudsnote Docs",
            destination: "https://muds.top/docs"
        ))
        XCTAssertEqual(updated.range, existingDraft.range)
        XCTAssertEqual(updated.replacement, "[Mudsnote Docs](https://muds.top/docs)")

        let removed = try XCTUnwrap(MarkdownLinkEditing.removalEdit(for: existingDraft))
        XCTAssertEqual(removed.range, existingDraft.range)
        XCTAssertEqual(removed.replacement, "Mudsnote")
        XCTAssertEqual(removed.selection, NSRange(location: 5, length: 8))

        XCTAssertEqual(
            MarkdownLinkEditing.normalizedDestination("hello@example.com"),
            "mailto:hello@example.com"
        )
        XCTAssertNil(MarkdownLinkEditing.normalizedDestination("   "))
    }

    func testMarkdownNoteLinksArePortableRelativeAndTraversalSafe() throws {
        XCTAssertEqual(
            MarkdownNoteLink.relativeDestination(
                from: "Inbox.md",
                to: "Projects/UI Lifecycle.md"
            ),
            "./Projects/UI%20Lifecycle.md"
        )
        XCTAssertEqual(
            MarkdownNoteLink.relativeDestination(
                from: "Projects/Current.md",
                to: "Projects/Next.md"
            ),
            "./Next.md"
        )
        XCTAssertEqual(
            MarkdownNoteLink.relativeDestination(
                from: "Projects/Current.md",
                to: "Reference/设计规范.md"
            ),
            "../Reference/%E8%AE%BE%E8%AE%A1%E8%A7%84%E8%8C%83.md"
        )
        XCTAssertEqual(
            MarkdownNoteLink.resolvedRelativePath(
                for: "../Reference/%E8%AE%BE%E8%AE%A1%E8%A7%84%E8%8C%83.md#section",
                from: "Projects/Current.md"
            ),
            "Reference/设计规范.md"
        )
        XCTAssertNil(MarkdownNoteLink.relativeDestination(
            from: "Projects/Current.md",
            to: "Projects/Current.md"
        ))
        XCTAssertNil(MarkdownNoteLink.resolvedRelativePath(
            for: "../Outside.md",
            from: "Inbox.md"
        ))
        XCTAssertNil(MarkdownNoteLink.resolvedRelativePath(
            for: "https://example.com/Note.md",
            from: "Inbox.md"
        ))

        let rendered = MarkdownInlineRendering.attributedText(
            for: "See [UI Lifecycle](Projects/UI%20Lifecycle.md)"
        )
        XCTAssertEqual(
            rendered.runs.compactMap(\.link).first?.relativeString,
            "Projects/UI%20Lifecycle.md"
        )
        XCTAssertNil(MarkdownAttachmentLine(
            "[UI Lifecycle](./Projects/UI%20Lifecycle.md)"
        ))
        XCTAssertNil(MarkdownAttachmentLine(
            "[Website](https://example.com)"
        ))
        XCTAssertEqual(
            MarkdownAttachmentLine("[Scan](Attachments/Scanned%20Document.pdf)")?.kind,
            .file
        )
        XCTAssertEqual(
            MarkdownAttachmentLine("[Video](Attachments/Launch%20Clip.mp4)")?.kind,
            .video
        )
        XCTAssertEqual(LibraryAttachment.Kind(fileExtension: "m4v"), .video)
    }

    func testNoteLinksSurviveRenameSingleMoveFolderRenameAndBatchMove() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let projects = root.appendingPathComponent("Projects", isDirectory: true)
        let reference = root.appendingPathComponent("Reference", isDirectory: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: reference, withIntermediateDirectories: true)
        try "# Source\n\n[Target](./Target.md)\n\n[Web](https://example.com)\n".write(
            to: projects.appendingPathComponent("Source.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Target\n\n[Other](../Reference/Other.md)\n".write(
            to: projects.appendingPathComponent("Target.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Other\n\n[Target](../Projects/Target.md)\n".write(
            to: reference.appendingPathComponent("Other.md"),
            atomically: true,
            encoding: .utf8
        )
        let store = MarkdownFileStore()
        await store.configure(root: root)

        let renamed = try await store.renameMarkdownDocument(
            relativePath: "Projects/Target.md",
            to: "Renamed"
        )
        XCTAssertEqual(renamed.relativePath, "Projects/Renamed.md")
        XCTAssertTrue(try String(
            contentsOf: projects.appendingPathComponent("Source.md"),
            encoding: .utf8
        ).contains("[Target](./Renamed.md)"))
        XCTAssertTrue(try String(
            contentsOf: reference.appendingPathComponent("Other.md"),
            encoding: .utf8
        ).contains("[Target](../Projects/Renamed.md)"))

        let moved = try await store.moveMarkdownDocument(
            relativePath: renamed.relativePath,
            toFolder: "Reference"
        )
        XCTAssertEqual(moved.relativePath, "Reference/Renamed.md")
        XCTAssertTrue(try String(
            contentsOf: projects.appendingPathComponent("Source.md"),
            encoding: .utf8
        ).contains("[Target](../Reference/Renamed.md)"))
        XCTAssertTrue(try String(
            contentsOf: reference.appendingPathComponent("Renamed.md"),
            encoding: .utf8
        ).contains("[Other](./Other.md)"))
        XCTAssertTrue(try String(
            contentsOf: projects.appendingPathComponent("Source.md"),
            encoding: .utf8
        ).contains("[Web](https://example.com)"))

        let renamedFolder = try await store.renameFolder(
            relativePath: "Reference",
            to: "Knowledge"
        )
        XCTAssertEqual(renamedFolder, "Knowledge")
        XCTAssertTrue(try String(
            contentsOf: projects.appendingPathComponent("Source.md"),
            encoding: .utf8
        ).contains("[Target](../Knowledge/Renamed.md)"))

        let batchMoved = try await store.moveMarkdownDocuments(
            relativePaths: ["Knowledge/Renamed.md", "Knowledge/Other.md"],
            toFolder: "Projects"
        )
        XCTAssertEqual(Set(batchMoved.map(\.relativePath)), Set([
            "Projects/Renamed.md",
            "Projects/Other.md",
        ]))
        XCTAssertTrue(try String(
            contentsOf: projects.appendingPathComponent("Source.md"),
            encoding: .utf8
        ).contains("[Target](./Renamed.md)"))
        XCTAssertTrue(try String(
            contentsOf: projects.appendingPathComponent("Renamed.md"),
            encoding: .utf8
        ).contains("[Other](./Other.md)"))
        XCTAssertTrue(try String(
            contentsOf: projects.appendingPathComponent("Other.md"),
            encoding: .utf8
        ).contains("[Target](./Renamed.md)"))
    }

    func testFindInNoteIndexesRenderedMarkdownQuotesAndTableCells() throws {
        let blocks = MarkdownRenderBlock.parse(
            "# Plan\n\n**Restore** this note, then restore it.\n\n> RESTORE quote\n\n| Item | Status |\n| --- | --- |\n| Restore | Ready |\n\n[Backup](Attachments/restore.txt)"
        )
        let matches = NoteFindIndex.matches(in: blocks, query: "restore")

        XCTAssertEqual(matches.count, 4)
        XCTAssertEqual(
            matches.map(\.location),
            [
                NoteFindLocation(blockIndex: 1, cellIndex: nil),
                NoteFindLocation(blockIndex: 1, cellIndex: nil),
                NoteFindLocation(blockIndex: 2, cellIndex: nil),
                NoteFindLocation(blockIndex: 3, cellIndex: 2)
            ]
        )
        XCTAssertEqual(matches.map(\.occurrence), [0, 1, 0, 0])
        XCTAssertEqual(NoteFindIndex.visibleText(for: "**Restore** this"), "Restore this")
        XCTAssertTrue(NoteFindIndex.matches(in: blocks, query: "   ").isEmpty)

        let highlighted = NoteFindIndex.highlightedText(
            for: "Restore and restore",
            query: "restore",
            location: NoteFindLocation(blockIndex: 0, cellIndex: nil),
            activeMatch: NoteFindMatch(
                location: NoteFindLocation(blockIndex: 0, cellIndex: nil),
                occurrence: 1
            )
        )
        let rendered = NSAttributedString(highlighted)
        XCTAssertNotNil(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(
            rendered.attribute(.backgroundColor, at: 12, effectiveRange: nil) as? UIColor,
            UIColor.systemOrange
        )
    }

    func testMarkdownParagraphStylesAreNativeAndIdempotent() throws {
        let source = "Intro\n## Existing\n#tag stays\n"
        let existingRange = (source as NSString).range(of: "## Existing")
        let titleEdit = try XCTUnwrap(MarkdownParagraphEditing.styleEdit(
            in: source,
            selection: existingRange,
            style: .title
        ))
        let titled = (source as NSString).replacingCharacters(
            in: titleEdit.range,
            with: titleEdit.replacement
        )
        XCTAssertEqual(titled, "Intro\n# Existing\n#tag stays\n")

        let repeatedTitleEdit = try XCTUnwrap(MarkdownParagraphEditing.styleEdit(
            in: titled,
            selection: (titled as NSString).range(of: "# Existing"),
            style: .title
        ))
        XCTAssertEqual(repeatedTitleEdit.replacement, "# Existing\n")

        let bodyEdit = try XCTUnwrap(MarkdownParagraphEditing.styleEdit(
            in: titled,
            selection: (titled as NSString).range(of: "# Existing"),
            style: .body
        ))
        XCTAssertEqual(bodyEdit.replacement, "Existing\n")

        let multiple = "First\n### Second\n\n"
        let headingEdit = try XCTUnwrap(MarkdownParagraphEditing.styleEdit(
            in: multiple,
            selection: NSRange(location: 0, length: (multiple as NSString).length),
            style: .heading
        ))
        XCTAssertEqual(headingEdit.replacement, "## First\n## Second\n\n")

        let tagEdit = try XCTUnwrap(MarkdownParagraphEditing.styleEdit(
            in: "#tag stays",
            selection: NSRange(location: 0, length: 10),
            style: .body
        ))
        XCTAssertEqual(tagEdit.replacement, "#tag stays")
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
        XCTAssertThrowsError(try ScannedDocumentPDF.data(for: [UIImage()])) { error in
            XCTAssertEqual(error as? ScannedDocumentPDF.Error, .invalidPage)
        }
    }

    @MainActor
    func testQuickCaptureAcceptsScannedDocumentAsPortableFile() async throws {
        let model = AppModel(
            bootstrapImmediately: false,
            restoreDraftImmediately: false
        )
        let page = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 500)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 500))
            UIColor.black.setFill()
            context.fill(CGRect(x: 30, y: 40, width: 240, height: 20))
        }

        let errorMessage = await model.attachScannedDocument([page, page])

        XCTAssertNil(errorMessage)
        XCTAssertTrue(model.draft.canSend)
        XCTAssertEqual(model.draft.attachments.count, 1)
        guard case .file(let data, let fileExtension, let baseName) = model.draft.attachments[0] else {
            return XCTFail("The scan should use the portable file attachment pipeline")
        }
        XCTAssertEqual(fileExtension, "pdf")
        XCTAssertEqual(baseName, "Scanned Document")
        XCTAssertTrue(data.starts(with: Data("%PDF".utf8)))
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        XCTAssertEqual(try XCTUnwrap(CGPDFDocument(provider)).numberOfPages, 2)

        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try FolderInitializer.initialize(root)
        let pending = try await MarkdownFileStore().preparePendingWrite(
            for: model.draft,
            root: root,
            now: Date(timeIntervalSince1970: 1_752_384_000)
        )
        XCTAssertEqual(pending.targetRelativePath, "Inbox.md")
        XCTAssertEqual(pending.attachments.count, 1)
        XCTAssertTrue(pending.attachments[0].relativePath.contains("/Scanned Document-"))
        XCTAssertTrue(pending.attachments[0].relativePath.hasSuffix(".pdf"))
        XCTAssertTrue(pending.markdownBlock.contains("[Scanned Document-"))
        XCTAssertTrue(pending.markdownBlock.contains("](Attachments/"))
        XCTAssertTrue(pending.markdownBlock.contains("#附件"))
    }

    @MainActor
    func testQuickCaptureAcceptsGenericFileAndPreservesPortableName() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Launch Brief.v2.pdf")
        let sourceData = Data("portable quick-capture file".utf8)
        try sourceData.write(to: sourceURL, options: .atomic)
        let model = AppModel(
            bootstrapImmediately: false,
            restoreDraftImmediately: false
        )

        let errorMessage = await model.attachFile(sourceURL)

        XCTAssertNil(errorMessage)
        XCTAssertTrue(model.draft.canSend)
        XCTAssertEqual(model.draft.attachments.count, 1)
        guard case .file(let data, let fileExtension, let baseName) = model.draft.attachments[0] else {
            return XCTFail("The selected document should use the portable file attachment pipeline")
        }
        XCTAssertEqual(data, sourceData)
        XCTAssertEqual(fileExtension, "pdf")
        XCTAssertEqual(baseName, "Launch Brief.v2")
    }

    @MainActor
    func testQuickCaptureRejectsOversizedGenericFileWithoutChangingDraft() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Too Large.zip")
        try Data().write(to: sourceURL, options: .atomic)
        let file = try FileHandle(forWritingTo: sourceURL)
        try file.truncate(
            atOffset: UInt64(CaptureAttachmentPolicy.maximumFileBytes + 1)
        )
        try file.close()
        let model = AppModel(
            bootstrapImmediately: false,
            restoreDraftImmediately: false
        )

        let errorMessage = await model.attachFile(sourceURL)

        XCTAssertEqual(
            errorMessage,
            CaptureAttachmentError.tooLarge(
                maximumBytes: CaptureAttachmentPolicy.maximumFileBytes
            ).localizedDescription
        )
        XCTAssertTrue(model.draft.attachments.isEmpty)
        XCTAssertFalse(model.draft.canSend)
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
        XCTAssertEqual(
            NoteListPresentation.sorted(files, by: .title, direction: .reversed).map(\.title),
            ["Charlie", "Beta", "Alpha"]
        )
        XCTAssertEqual(
            NoteListPresentation.sorted(files, by: .modified, direction: .reversed).map(\.title),
            ["Charlie", "Beta", "Alpha"]
        )
        let sections = NoteListPresentation.sections(
            for: files,
            sortedBy: .modified,
            groupByDate: true,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(sections.map(\.id), ["today", "yesterday", "previous-7"])
        XCTAssertEqual(sections.flatMap(\.files).map(\.title), ["Alpha", "Beta", "Charlie"])
        let reversedSections = NoteListPresentation.sections(
            for: files,
            sortedBy: .modified,
            direction: .reversed,
            groupByDate: true,
            now: now,
            calendar: calendar
        )
        XCTAssertEqual(reversedSections.map(\.id), ["previous-7", "yesterday", "today"])
        XCTAssertEqual(reversedSections.flatMap(\.files).map(\.title), ["Charlie", "Beta", "Alpha"])
        XCTAssertEqual(
            NoteListPresentation.sections(for: files, sortedBy: .title, groupByDate: true).count,
            1
        )
    }

    func testLibraryFileScopeFiltersSearchResultsAndDerivesNewNoteFolder() {
        let project = RecentMarkdownFile(
            id: "Projects/Plan.md",
            relativePath: "Projects/Plan.md",
            title: "Plan",
            modifiedAt: .now
        )
        let daily = RecentMarkdownFile(
            id: "Daily/2026-07-17.md",
            relativePath: "Daily/2026-07-17.md",
            title: "2026-07-17",
            modifiedAt: .now
        )
        let projectResult = MarkdownSearchResult(
            id: "file:\(project.relativePath)",
            title: project.title,
            context: "Launch plan",
            location: project.relativePath,
            score: 1,
            modifiedAt: project.modifiedAt,
            destination: .file(project)
        )
        let dailyResult = MarkdownSearchResult(
            id: "file:\(daily.relativePath)",
            title: daily.title,
            context: "Daily plan",
            location: daily.relativePath,
            score: 1,
            modifiedAt: daily.modifiedAt,
            destination: .file(daily)
        )
        let memo = MemoBlock(id: "memo", dateText: "10:00", body: "Inbox plan", tags: [])
        let memoResult = MarkdownSearchResult(
            id: "memo:memo",
            title: "Inbox plan",
            context: "Inbox plan",
            location: "Inbox",
            score: 1,
            modifiedAt: .now,
            destination: .memo(memo)
        )

        XCTAssertTrue(LibraryFileScope.all.contains(projectResult))
        XCTAssertTrue(LibraryFileScope.all.contains(memoResult))
        XCTAssertTrue(LibraryFileScope.pathPrefix("Daily/").contains(dailyResult))
        XCTAssertFalse(LibraryFileScope.pathPrefix("Daily/").contains(projectResult))
        XCTAssertFalse(LibraryFileScope.pathPrefix("Daily/").contains(memoResult))
        XCTAssertNil(LibraryFileScope.all.newNoteFolder)
        XCTAssertEqual(LibraryFileScope.pathPrefix("/Daily/").newNoteFolder, "Daily")
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

private actor StubAttachmentTextRecognizer: AttachmentTextRecognizing {
    private let text: String
    private var calls = 0

    init(text: String) {
        self.text = text
    }

    func recognizeText(at url: URL) async throws -> String {
        calls += 1
        return text
    }

    func callCount() -> Int { calls }
}
