import Foundation
import PhotosUI
import SwiftUI

enum CaptureRoute: String {
    case text
    case image
    case audio
}

enum SystemEntryRequest {
    static let pendingRouteKey = "MudsnotePendingSystemRoute"
}

@MainActor
final class AppModel: ObservableObject {
    @Published var folderStatus: FolderStatus = .loading
    @Published var inboxItems: [MemoBlock] = []
    @Published var libraryFiles: [RecentMarkdownFile] = []
    @Published var recentFiles: [RecentMarkdownFile] = []
    @Published var attachments: [LibraryAttachment] = []
    @Published var selectedMemo: MemoBlock?
    @Published var selectedDocument: MarkdownDocument?
    @Published var librarySummary = LibrarySummary()
    @Published var tagSummaries: [TagSummary] = []
    @Published var draft = CaptureDraft()
    @Published var captureRoute: CaptureRoute = .text
    @Published var isCapturePresented = false
    @Published var isSendingDraft = false
    @Published private(set) var isAudioTransitioning = false
    @Published private(set) var isTranscribingAudio = false
    @Published var statusToast: StatusToast?
    @Published var query = ""
    @Published var syncStatus: SyncStatus = .idle
    @Published var conflictWarnings: [String] = []

    let folderAccess = FolderAccessService()
    let fileStore = MarkdownFileStore()
    let audioRecorder = AudioCaptureService()

    private var queue: PendingWriteQueue?
    private var pendingCaptureRoute: CaptureRoute?

    init(bootstrapImmediately: Bool = true) {
        if bootstrapImmediately {
            Task { await bootstrap() }
        }
    }

    func bootstrap() async {
        do {
            if let root = try folderAccess.resolvePersistedFolder() {
                try await configureFolder(root)
            } else {
                folderStatus = .missing
            }
        } catch {
            folderStatus = .error(error.localizedDescription)
            statusToast = .error(String(localized: "Folder access failed"))
        }
    }

    func selectFolder(_ url: URL) {
        Task {
            do {
                try folderAccess.persistFolder(url)
                try await configureFolder(url)
                statusToast = .saved(String(localized: "Folder ready"))
            } catch {
                folderStatus = .error(error.localizedDescription)
                statusToast = .error(String(localized: "Could not prepare folder"))
            }
        }
    }

    func forgetFolderAndChooseAgain() {
        folderAccess.forgetPersistedFolder()
        folderStatus = .missing
        inboxItems = []
        libraryFiles = []
        recentFiles = []
        attachments = []
        librarySummary = LibrarySummary()
        tagSummaries = []
        conflictWarnings = []
        queue = nil
    }

    func showCapture(_ route: CaptureRoute = .text) {
        captureRoute = route
        isCapturePresented = true
    }

    func handle(url: URL) {
        guard url.scheme == "mudsnote" else { return }
        if url.host == "capture" {
            openSystemCapture(Self.captureRoute(from: url))
        }
    }

    func consumeSystemEntryRequest() {
        let defaults = UserDefaults.standard
        guard let value = defaults.string(forKey: SystemEntryRequest.pendingRouteKey),
              let route = CaptureRoute(rawValue: value) else {
            return
        }
        defaults.removeObject(forKey: SystemEntryRequest.pendingRouteKey)
        openSystemCapture(route)
    }

    func sendDraft(continueCapturing: Bool = true) {
        guard draft.canSend, !isSendingDraft else { return }
        let nextTarget = draft.target
        let canUseInboxDelta = nextTarget == .inbox && draft.attachments.isEmpty
        isSendingDraft = true
        Task {
            defer { isSendingDraft = false }
            do {
                try await appendCurrentDraft()
                draft = CaptureDraft(target: nextTarget)
                captureRoute = .text
                if !continueCapturing {
                    isCapturePresented = false
                }
                statusToast = .saved(
                    continueCapturing
                        ? String(localized: "Saved. Ready for next")
                        : String(localized: "Saved")
                )
                await refreshAfterWrite(canUseInboxDelta: canUseInboxDelta)
            } catch {
                if let draftSaveError = error as? DraftSaveError {
                    statusToast = .error(draftSaveError.localizedDescription)
                    return
                }
                let pendingCount = await queue?.pendingCount() ?? 0
                if pendingCount > 0 {
                    syncStatus = .pending
                    statusToast = .pending(String(localized: "Saved to pending queue"))
                } else {
                    statusToast = .error(String(localized: "Could not save. Draft kept open"))
                }
            }
        }
    }

    func attachPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    statusToast = .error(String(localized: "Image data unavailable"))
                    return
                }
                let attachment = try CaptureAttachment.validatedImage(data: data)
                try appendAttachment(attachment)
                statusToast = .saved(String(localized: "Image attached"))
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    func attachImageFile(_ url: URL) {
        Task {
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer {
                    if accessed { url.stopAccessingSecurityScopedResource() }
                }
                if let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                   fileSize > CaptureAttachmentPolicy.maximumImageBytes {
                    throw CaptureAttachmentError.tooLarge(
                        maximumBytes: CaptureAttachmentPolicy.maximumImageBytes
                    )
                }
                let data = try Data(contentsOf: url)
                let attachment = try CaptureAttachment.validatedImage(
                    data: data,
                    suggestedExtension: url.pathExtension
                )
                try appendAttachment(attachment)
                statusToast = .saved(String(localized: "Image attached"))
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    func toggleAudioRecording() {
        guard !isAudioTransitioning, !isTranscribingAudio else { return }
        isAudioTransitioning = true
        Task {
            defer { isAudioTransitioning = false }
            do {
                if audioRecorder.isRecording {
                    if let recording = try audioRecorder.stop() {
                        let attachment: CaptureAttachment
                        do {
                            attachment = try CaptureAttachment.validatedAudio(data: recording.data)
                            try appendAttachment(attachment)
                        } catch {
                            try? FileManager.default.removeItem(at: recording.temporaryURL)
                            throw error
                        }
                        statusToast = .saved(String(localized: "Audio attached"))
                        isTranscribingAudio = true
                        Task {
                            await transcribe(recording)
                        }
                    }
                } else {
                    try await audioRecorder.start()
                    statusToast = .pending(String(localized: "Recording"))
                }
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    func cancelAudioRecording() {
        guard audioRecorder.isRecording else { return }
        audioRecorder.cancel()
    }

    private func appendAttachment(_ attachment: CaptureAttachment) throws {
        try CaptureAttachmentPolicy.validateAppending(attachment, to: draft.attachments)
        draft.attachments.append(attachment)
    }

    private func transcribe(_ recording: RecordedAudio) async {
        defer {
            try? FileManager.default.removeItem(at: recording.temporaryURL)
            isTranscribingAudio = false
        }

        do {
            let text = try await audioRecorder.transcribe(url: recording.temporaryURL)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                statusToast = .pending(String(localized: "No speech detected. Audio kept."))
                return
            }

            if draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draft.body = trimmed
            } else {
                draft.body += "\n\n\(trimmed)"
            }
            statusToast = .saved(String(localized: "Transcribed"))
        } catch {
            statusToast = .error(error.localizedDescription)
        }
    }

    func replayQueue() {
        Task {
            do {
                try await queue?.replay { [fileStore] item in
                    try await fileStore.performPendingWrite(item)
                }
                statusToast = .saved(String(localized: "Pending queue replayed"))
                await refreshInbox()
            } catch {
                statusToast = .error(String(localized: "Queue replay failed"))
            }
        }
    }

    func deleteMemo(_ memo: MemoBlock) {
        Task {
            do {
                try await fileStore.applyInboxMutation(.delete(memoID: memo.id))
                statusToast = .saved(String(localized: "Deleted"))
                await refreshInboxDelta()
            } catch {
                statusToast = .error(String(localized: "Delete failed"))
            }
        }
    }

    func pinMemo(_ memo: MemoBlock) {
        Task {
            do {
                try await fileStore.applyInboxMutation(.pin(memoID: memo.id))
                statusToast = .saved(String(localized: "Pinned"))
                await refreshInboxDelta()
            } catch {
                statusToast = .error(String(localized: "Pin failed"))
            }
        }
    }

    func addDefaultTag(to memo: MemoBlock) {
        Task {
            do {
                try await fileStore.applyInboxMutation(.addTag(memoID: memo.id, tag: "#tag"))
                statusToast = .saved(String(localized: "Tagged"))
                await refreshInboxDelta()
            } catch {
                statusToast = .error(String(localized: "Tag failed"))
            }
        }
    }

    func openFile(_ file: RecentMarkdownFile) {
        Task {
            do {
                selectedDocument = try await fileStore.loadMarkdownDocument(
                    relativePath: file.relativePath
                )
            } catch {
                statusToast = .error(String(localized: "Could not open Markdown file"))
            }
        }
    }

    func previewURL(for attachment: LibraryAttachment) async -> URL? {
        do {
            return try await fileStore.prepareAttachmentPreview(
                relativePath: attachment.relativePath
            )
        } catch {
            statusToast = .error(String(localized: "Could not open attachment"))
            return nil
        }
    }

    func refreshInbox() async {
        guard folderAccess.currentRoot != nil else { return }
        do {
            let snapshot = try await fileStore.loadLibrarySnapshot()
            await apply(snapshot)
        } catch {
            statusToast = .error(String(localized: "Inbox refresh failed"))
        }
    }

    private func refreshAfterWrite(canUseInboxDelta: Bool) async {
        if canUseInboxDelta {
            await refreshInboxDelta()
        } else {
            await refreshInbox()
        }
    }

    private func refreshInboxDelta() async {
        guard folderAccess.currentRoot != nil else { return }
        do {
            let snapshot = try await fileStore.loadInboxDeltaSnapshot()
            await apply(snapshot)
        } catch {
            await refreshInbox()
        }
    }

    private func apply(_ snapshot: MarkdownLibrarySnapshot) async {
        inboxItems = snapshot.inboxItems
        libraryFiles = snapshot.allFiles
        recentFiles = snapshot.recentFiles
        attachments = snapshot.attachments
        librarySummary = snapshot.summary
        tagSummaries = Self.tagSummaries(from: inboxItems)
        conflictWarnings = snapshot.conflictWarnings
        let pendingCount = await queue?.pendingCount() ?? 0
        if conflictWarnings.isEmpty == false {
            syncStatus = .conflict
        } else if pendingCount > 0 {
            syncStatus = .pending
        } else {
            syncStatus = .idle
        }
    }

    private func configureFolder(_ root: URL) async throws {
        try folderAccess.withAccess(to: root) {
            try FolderInitializer.initialize(root)
        }
        await fileStore.configure(root: root)
        queue = PendingWriteQueue(root: root)
        folderStatus = .ready(root)
        try await queue?.load()
        do {
            try await queue?.replay { [fileStore] item in
                try await fileStore.performPendingWrite(item)
            }
        } catch {
            syncStatus = .pending
            statusToast = .pending(String(localized: "Pending captures need attention"))
        }
        await refreshInbox()
        presentPendingCaptureIfPossible()
    }

    private func appendCurrentDraft() async throws {
        guard let root = folderAccess.currentRoot, let queue else {
            throw FolderAccessError.missingFolder
        }

        let pending = try await fileStore.preparePendingWrite(for: draft, root: root)
        do {
            try await queue.enqueue(pending)
        } catch {
            throw DraftSaveError.pendingQueueRejected(error.localizedDescription)
        }
        try await fileStore.performPendingWrite(pending)
        try await queue.remove(id: pending.id)
    }

    private func openSystemCapture(_ route: CaptureRoute) {
        guard case .ready = folderStatus else {
            pendingCaptureRoute = route
            return
        }
        showCapture(route)
    }

    func presentPendingCaptureIfPossible() {
        guard case .ready = folderStatus,
              let route = pendingCaptureRoute else { return }
        pendingCaptureRoute = nil
        showCapture(route)
    }

    private static func captureRoute(from url: URL) -> CaptureRoute {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let mode = components.queryItems?.first(where: { $0.name == "mode" })?.value,
              let route = CaptureRoute(rawValue: mode) else {
            return .text
        }
        return route
    }

    private static func tagSummaries(from memos: [MemoBlock]) -> [TagSummary] {
        let counts = memos
            .flatMap(\.tags)
            .reduce(into: [String: Int]()) { partialResult, tag in
                partialResult[tag, default: 0] += 1
            }

        return counts
            .map { TagSummary(name: $0.key, count: $0.value) }
            .sorted {
                if $0.count == $1.count {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.count > $1.count
            }
    }

}

enum DraftSaveError: LocalizedError {
    case pendingQueueRejected(String)

    var errorDescription: String? {
        switch self {
        case .pendingQueueRejected(let reason):
            return String(
                format: String(localized: "draft.kept_open.format"),
                locale: .current,
                reason
            )
        }
    }
}

struct TagSummary: Equatable, Identifiable {
    var name: String
    var count: Int

    var id: String { name }
}

enum FolderStatus: Equatable {
    case loading
    case missing
    case ready(URL)
    case error(String)
}

enum SyncStatus: Equatable {
    case idle
    case pending
    case conflict
}

struct StatusToast: Equatable, Identifiable {
    let id = UUID()
    var style: Style
    var message: String

    enum Style {
        case saved
        case pending
        case error
    }

    static func saved(_ message: String) -> StatusToast {
        StatusToast(style: .saved, message: message)
    }

    static func pending(_ message: String) -> StatusToast {
        StatusToast(style: .pending, message: message)
    }

    static func error(_ message: String) -> StatusToast {
        StatusToast(style: .error, message: message)
    }
}
