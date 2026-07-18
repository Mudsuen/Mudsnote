import SwiftUI
import UIKit

@main
struct MudsnoteCompanionApp: App {
    @StateObject private var appModel: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        MudsnoteUITestLaunchConfiguration.prepareIfNeeded()
        _appModel = StateObject(wrappedValue: AppModel())
        AppShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .task {
                    appModel.consumeSystemEntryRequest()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        appModel.consumeSystemEntryRequest()
                        Task { await appModel.refreshAfterSceneActivation() }
                    } else {
                        appModel.persistCaptureDraftNow()
                    }
                }
                .onOpenURL { url in
                    appModel.handle(url: url)
                }
                .preferredColorScheme(.dark)
        }
    }
}

private enum MudsnoteUITestLaunchConfiguration {
    private static let resetArgument = "-ui-testing-reset"
    private static let fixtureFolderArgument = "-ui-testing-fixture-folder"
    private static let invalidBookmarkArgument = "-ui-testing-invalid-bookmark"
    private static let damagedDraftArgument = "-ui-testing-damaged-draft"
    private static let damagedQueueArgument = "-ui-testing-damaged-queue"
    private static let conflictCopyArgument = "-ui-testing-conflict-copy"
    private static let fileTagArgument = "-ui-testing-file-tag"
    private static let batchNotesArgument = "-ui-testing-batch-notes"
    private static let ocrAttachmentArgument = "-ui-testing-ocr-attachment"
    private static let audioTranscriptArgument = "-ui-testing-audio-transcript"
    private static let attachmentErrorArgument = "-ui-testing-attachment-error"
    private static let interruptedWriteArgument = "-ui-testing-interrupted-write"
    private static let searchRouteArgument = "-ui-testing-search-route"
    private static let inboxFolderArgument = "-ui-testing-inbox-folder"
    private static let fixtureFolderName = "MudsnoteUITestLibrary"

    static func prepareIfNeeded() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains(resetArgument)
                || arguments.contains(fixtureFolderArgument)
                || arguments.contains(invalidBookmarkArgument)
                || arguments.contains(damagedDraftArgument)
                || arguments.contains(damagedQueueArgument)
                || arguments.contains(conflictCopyArgument)
                || arguments.contains(fileTagArgument)
                || arguments.contains(batchNotesArgument)
                || arguments.contains(ocrAttachmentArgument)
                || arguments.contains(audioTranscriptArgument)
                || arguments.contains(attachmentErrorArgument)
                || arguments.contains(interruptedWriteArgument)
                || arguments.contains(searchRouteArgument)
                || arguments.contains(inboxFolderArgument)
        else { return }

        let access = FolderAccessService()
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fixtureFolderName, isDirectory: true)

        if arguments.contains(resetArgument) {
            access.forgetPersistedFolder()
            UserDefaults.standard.removeObject(forKey: SystemEntryRequest.pendingRouteKey)
            UserDefaults.standard.removeObject(forKey: SystemEntryRequest.pendingSearchKey)
            UserDefaults.standard.removeObject(forKey: "mudsnote.ios.noteViewStyle")
            UserDefaults.standard.removeObject(forKey: "mudsnote.ios.noteSortOrder")
            UserDefaults.standard.removeObject(forKey: "mudsnote.ios.noteSortDirection")
            UserDefaults.standard.removeObject(forKey: "mudsnote.ios.groupNotesByDate")
            UserDefaults.standard.removeObject(
                forKey: AttachmentPresentationPreferences.defaultsKey
            )
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: CaptureDraftRecoveryStore.defaultDirectory)
        }

        if arguments.contains(searchRouteArgument) {
            UserDefaults.standard.set(true, forKey: SystemEntryRequest.pendingSearchKey)
        }

        if arguments.contains(fixtureFolderArgument) {
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try FolderInitializer.initialize(root)
                let galleryFixtureImage = UIGraphicsImageRenderer(
                    size: CGSize(width: 720, height: 480)
                ).image { context in
                    UIColor(red: 0.92, green: 0.76, blue: 0.28, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 720, height: 480))
                    let configuration = UIImage.SymbolConfiguration(
                        pointSize: 180,
                        weight: .regular
                    )
                    let symbol = UIImage(
                        systemName: "note.text",
                        withConfiguration: configuration
                    )?.withTintColor(.black, renderingMode: .alwaysOriginal)
                    symbol?.draw(
                        in: CGRect(x: 250, y: 150, width: 220, height: 180)
                    )
                }
                if let image = galleryFixtureImage.pngData() {
                    try image.write(
                        to: root.appendingPathComponent("Attachments/ui-test.png"),
                        options: .atomic
                    )
                }
                try Data("Quick Look fixture".utf8).write(
                    to: root.appendingPathComponent("Attachments/ui-test.txt"),
                    options: .atomic
                )
                try Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]).write(
                    to: root.appendingPathComponent("Attachments/ui-test.mp4"),
                    options: .atomic
                )
                let pdfRenderer = UIGraphicsPDFRenderer(
                    bounds: CGRect(x: 0, y: 0, width: 612, height: 792)
                )
                let pdfData = pdfRenderer.pdfData { context in
                    context.beginPage()
                    NSString(string: "Launch Brief").draw(
                        at: CGPoint(x: 54, y: 64),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 30, weight: .bold),
                            .foregroundColor: UIColor.black,
                        ]
                    )
                    NSString(string: "Review and mark up this scanned document.").draw(
                        at: CGPoint(x: 54, y: 118),
                        withAttributes: [
                            .font: UIFont.systemFont(ofSize: 18),
                            .foregroundColor: UIColor.darkGray,
                        ]
                    )
                }
                try pdfData.write(
                    to: root.appendingPathComponent("Attachments/ui-test.pdf"),
                    options: .atomic
                )
                let projects = root.appendingPathComponent("Projects", isDirectory: true)
                try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
                try "# UI Lifecycle\n\nRestore this note end to end.\n\nContact support@example.com or +1 (415) 555-0123.\n\n[Video](Attachments/ui-test.mp4)\n\n[Scanned Brief](Attachments/ui-test.pdf)\n\n[QA Document](Attachments/ui-test.txt)\n\n| Item | Status |\n| --- | --- |\n| Preview | Ready |\n".write(
                    to: projects.appendingPathComponent("UI Lifecycle.md"),
                    atomically: true,
                    encoding: .utf8
                )
                if arguments.contains(inboxFolderArgument) {
                    let inboxFolder = root.appendingPathComponent("Inbox", isDirectory: true)
                    try FileManager.default.createDirectory(
                        at: inboxFolder,
                        withIntermediateDirectories: true
                    )
                    try "# Filed Note\n\nStored as a Markdown file.\n".write(
                        to: inboxFolder.appendingPathComponent("Filed Note.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                    let inbox = root.appendingPathComponent("Inbox.md")
                    let existingInbox = try String(contentsOf: inbox, encoding: .utf8)
                    try (existingInbox + "\n## 2026-07-18 19:00\n\nOriginal inbox memo\n").write(
                        to: inbox,
                        atomically: true,
                        encoding: .utf8
                    )
                }
                if arguments.contains(fileTagArgument) {
                    try "# UI Lifecycle\n\nRestore this note end to end.\n\n#project #work\n".write(
                        to: projects.appendingPathComponent("UI Lifecycle.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                    let inbox = root.appendingPathComponent("Inbox.md")
                    let existingInbox = try String(contentsOf: inbox, encoding: .utf8)
                    try (existingInbox + "\n## 2026-07-13 20:00\n\nTagged quick capture\n\n#project #quick\n").write(
                        to: inbox,
                        atomically: true,
                        encoding: .utf8
                    )
                }
                if arguments.contains(conflictCopyArgument) {
                    try "# Conflicted UI Lifecycle\n\nReview both versions safely.\n".write(
                        to: projects.appendingPathComponent("UI Lifecycle conflicted copy.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
                if arguments.contains(batchNotesArgument) {
                    try """
                    # Second UI Note

                    ![Gallery preview](Attachments/ui-test.png)

                    - [x] Capture the idea
                    - [ ] Refine the draft
                    - [ ] Ship the note
                    """.write(
                        to: projects.appendingPathComponent("Second UI Note.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
                if arguments.contains(ocrAttachmentArgument) {
                    let image = UIGraphicsImageRenderer(
                        size: CGSize(width: 1_400, height: 420)
                    ).image { context in
                        UIColor.white.setFill()
                        context.fill(CGRect(x: 0, y: 0, width: 1_400, height: 420))
                        NSString(string: "ORBITAL 428").draw(
                            at: CGPoint(x: 80, y: 120),
                            withAttributes: [
                                .font: UIFont.systemFont(ofSize: 112, weight: .bold),
                                .foregroundColor: UIColor.black,
                            ]
                        )
                    }
                    guard let imageData = image.pngData() else {
                        throw CaptureAttachmentError.empty
                    }
                    try imageData.write(
                        to: root.appendingPathComponent("Attachments/ocr-search.png"),
                        options: .atomic
                    )
                    try "# OCR Attachment\n\n![Image](Attachments/ocr-search.png)\n".write(
                        to: projects.appendingPathComponent("OCR Attachment.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
                if arguments.contains(audioTranscriptArgument) {
                    try Data("audio transcript fixture".utf8).write(
                        to: root.appendingPathComponent("Attachments/ui-transcript.m4a"),
                        options: .atomic
                    )
                    try """
                    # Recorded Meeting

                    [Audio](Attachments/ui-transcript.m4a)

                    ### Audio transcription

                    Project ORBITAL is approved for launch.
                    """.write(
                        to: projects.appendingPathComponent("Recorded Meeting.md"),
                        atomically: true,
                        encoding: .utf8
                    )
                }
                try access.persistFolder(root)

                if arguments.contains(damagedQueueArgument) {
                    try Data("damaged pending queue".utf8).write(
                        to: root.appendingPathComponent(".mudsnote/queue.json"),
                        options: .atomic
                    )
                }
                if arguments.contains(interruptedWriteArgument) {
                    let interruptedWrites = (0..<PendingWriteQueuePolicy.maximumItemCount).map { index in
                        PendingWrite(
                            id: UUID(),
                            createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                            targetRelativePath: "../blocked-\(index).md",
                            markdownBlock: "Interrupted write fixture",
                            attachments: []
                        )
                    }
                    try JSONEncoder.pretty.encode(interruptedWrites).write(
                        to: root.appendingPathComponent(".mudsnote/queue.json"),
                        options: .atomic
                    )
                }
            } catch {
                assertionFailure("Could not prepare the Mudsnote UI-test library: \(error)")
            }
        }

        if arguments.contains(invalidBookmarkArgument) {
            UserDefaults.standard.set(
                Data("invalid-bookmark".utf8),
                forKey: FolderAccessService.DefaultsKey.bookmarkData
            )
        }

        if arguments.contains(damagedDraftArgument) {
            try? FileManager.default.createDirectory(
                at: CaptureDraftRecoveryStore.defaultDirectory,
                withIntermediateDirectories: true
            )
            try? Data("damaged-draft".utf8).write(
                to: CaptureDraftRecoveryStore.defaultDirectory.appendingPathComponent("draft.json"),
                options: .atomic
            )
        }
        #endif
    }
}
