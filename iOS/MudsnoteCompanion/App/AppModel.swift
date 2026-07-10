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
    @Published var folderStatus: FolderStatus = .missing
    @Published var inboxItems: [MemoBlock] = []
    @Published var recentFiles: [RecentMarkdownFile] = []
    @Published var selectedMemo: MemoBlock?
    @Published var librarySummary = LibrarySummary()
    @Published var tagSummaries: [TagSummary] = []
    @Published var draft = CaptureDraft()
    @Published var captureRoute: CaptureRoute = .text
    @Published var isCapturePresented = false
    @Published var isSendingDraft = false
    @Published var statusToast: StatusToast?
    @Published var query = ""
    @Published var syncStatus: SyncStatus = .idle
    @Published var conflictWarnings: [String] = []

    let folderAccess = FolderAccessService()
    let fileStore = MarkdownFileStore()
    let audioRecorder = AudioCaptureService()

    private var queue: PendingWriteQueue?

    init() {
        Task { await bootstrap() }
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
            statusToast = .error("Folder access failed")
        }
    }

    func selectFolder(_ url: URL) {
        Task {
            do {
                try folderAccess.persistFolder(url)
                try await configureFolder(url)
                statusToast = .saved("Folder ready")
            } catch {
                folderStatus = .error(error.localizedDescription)
                statusToast = .error("Could not prepare folder")
            }
        }
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
                statusToast = .saved(continueCapturing ? "Saved. Ready for next" : "Saved")
                await refreshInbox()
            } catch {
                let pendingCount = await queue?.pendingCount() ?? 0
                if pendingCount > 0 {
                    syncStatus = .pending
                    statusToast = .pending("Saved to pending queue")
                } else {
                    statusToast = .error("Could not save. Draft kept open")
                }
            }
        }
    }

    func attachPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    statusToast = .error("Image data unavailable")
                    return
                }
                draft.attachments.append(.image(data: data, preferredExtension: "jpg"))
                statusToast = .saved("Image attached")
            } catch {
                statusToast = .error("Image import failed")
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
                let data = try Data(contentsOf: url)
                let preferredExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension.lowercased()
                draft.attachments.append(.image(data: data, preferredExtension: preferredExtension))
                statusToast = .saved("Image attached")
            } catch {
                statusToast = .error("Image import failed")
            }
        }
    }

    func toggleAudioRecording() {
        Task {
            do {
                if audioRecorder.isRecording {
                    if let recording = try audioRecorder.stop() {
                        if draft.body.isEmpty {
                            draft.body = "转写中..."
                        }
                        draft.attachments.append(.audio(data: recording.data, preferredExtension: "m4a"))
                        statusToast = .saved("Audio attached")
                        Task {
                            await transcribe(recording)
                        }
                    }
                } else {
                    try audioRecorder.start()
                    statusToast = .pending("Recording")
                }
            } catch {
                statusToast = .error("Audio recording failed")
            }
        }
    }

    private func transcribe(_ recording: RecordedAudio) async {
        defer {
            try? FileManager.default.removeItem(at: recording.temporaryURL)
        }

        do {
            let text = try await audioRecorder.transcribe(url: recording.temporaryURL)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                if draft.body == "转写中..." {
                    draft.body = "转写：未识别到语音。"
                }
                return
            }

            if draft.body == "转写中..." || draft.body == "转写：未识别到语音。" {
                draft.body = trimmed
            } else {
                draft.body += "\n\n\(trimmed)"
            }
            statusToast = .saved("Transcribed")
        } catch {
            if draft.body == "转写中..." {
                draft.body = "转写：语音转写不可用，请在真机授权后重试。"
            }
            statusToast = .error("Transcription unavailable")
        }
    }

    func replayQueue() {
        Task {
            do {
                try await queue?.replay { [fileStore] item in
                    try await fileStore.performPendingWrite(item)
                }
                statusToast = .saved("Pending queue replayed")
                await refreshInbox()
            } catch {
                statusToast = .error("Queue replay failed")
            }
        }
    }

    func deleteMemo(_ memo: MemoBlock) {
        Task {
            do {
                try await rewriteInboxItems(inboxItems.filter { $0.id != memo.id })
                statusToast = .saved("Deleted")
                await refreshInbox()
            } catch {
                statusToast = .error("Delete failed")
            }
        }
    }

    func pinMemo(_ memo: MemoBlock) {
        Task {
            do {
                let remaining = inboxItems.filter { $0.id != memo.id }
                try await rewriteInboxItems([memo] + remaining)
                statusToast = .saved("Pinned")
                await refreshInbox()
            } catch {
                statusToast = .error("Pin failed")
            }
        }
    }

    func addDefaultTag(to memo: MemoBlock) {
        Task {
            do {
                let updated = inboxItems.map { item in
                    guard item.id == memo.id else { return item }
                    var copy = item
                    if !copy.body.split(whereSeparator: \.isWhitespace).contains("#tag") {
                        copy.body += copy.body.isEmpty ? "#tag" : "\n\n#tag"
                    }
                    return copy
                }
                try await rewriteInboxItems(updated)
                statusToast = .saved("Tagged")
                await refreshInbox()
            } catch {
                statusToast = .error("Tag failed")
            }
        }
    }

    func refreshInbox() async {
        guard let root = folderAccess.currentRoot else { return }
        do {
            let inbox = root.appendingPathComponent("Inbox.md")
            let body = try String(contentsOf: inbox, encoding: .utf8)
            inboxItems = InboxParser.parse(body)
            recentFiles = try MarkdownFileStore.recentFiles(in: root)
            librarySummary = try MarkdownFileStore.librarySummary(
                in: root,
                inboxCount: inboxItems.count,
                allNotesCount: recentFiles.count
            )
            tagSummaries = Self.tagSummaries(from: inboxItems)
            conflictWarnings = try MarkdownFileStore.conflictWarnings(in: root)
            let pendingCount = await queue?.pendingCount() ?? 0
            if conflictWarnings.isEmpty == false {
                syncStatus = .conflict
            } else if pendingCount > 0 {
                syncStatus = .pending
            } else {
                syncStatus = .idle
            }
        } catch {
            statusToast = .error("Inbox refresh failed")
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
            statusToast = .pending("Pending captures need attention")
        }
        await refreshInbox()
    }

    private func appendCurrentDraft() async throws {
        guard let root = folderAccess.currentRoot, let queue else {
            throw FolderAccessError.missingFolder
        }

        let pending = try await fileStore.preparePendingWrite(for: draft, root: root)
        try await queue.enqueue(pending)
        try await fileStore.performPendingWrite(pending)
        try await queue.remove(id: pending.id)
    }

    private func rewriteInboxItems(_ items: [MemoBlock]) async throws {
        guard let root = folderAccess.currentRoot else {
            throw FolderAccessError.missingFolder
        }
        try folderAccess.withAccess(to: root) {
            let markdown = Self.inboxMarkdown(forDisplayItems: items)
            try markdown.write(to: root.appendingPathComponent("Inbox.md"), atomically: true, encoding: .utf8)
        }
    }

    private func openSystemCapture(_ route: CaptureRoute) {
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

    static func inboxMarkdown(forDisplayItems items: [MemoBlock]) -> String {
        var output = "# Inbox\n\n"
        for memo in items.reversed() {
            output += "## \(memo.dateText)\n\n"
            output += memo.body.trimmingCharacters(in: .whitespacesAndNewlines)
            output += "\n\n"
            if let writeMarker = memo.writeMarker {
                output += writeMarker
                output += "\n\n"
            }
        }
        return output
    }
}

struct LibrarySummary: Equatable {
    var allNotesCount = 0
    var inboxCount = 0
    var dailyCount = 0
    var templateCount = 0
    var attachmentCount = 0
}

struct TagSummary: Equatable, Identifiable {
    var name: String
    var count: Int

    var id: String { name }
}

enum FolderStatus: Equatable {
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
