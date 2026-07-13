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
    @Published var folders: [LibraryFolderNode] = []
    @Published var trashedFiles: [TrashedMarkdownFile] = []
    @Published var attachments: [LibraryAttachment] = []
    @Published var selectedMemo: MemoBlock?
    @Published var selectedDocument: MarkdownDocument?
    @Published var librarySummary = LibrarySummary()
    @Published var tagSummaries: [TagSummary] = []
    @Published var draft = CaptureDraft() {
        didSet { scheduleDraftPersistenceIfNeeded() }
    }
    @Published var captureRoute: CaptureRoute = .text
    @Published var isCapturePresented = false
    @Published var isSendingDraft = false
    @Published private(set) var isAudioTransitioning = false
    @Published private(set) var isTranscribingAudio = false
    @Published private(set) var attachmentPreparationCount = 0
    @Published var statusToast: StatusToast?
    @Published var query = ""
    @Published var syncStatus: SyncStatus = .idle
    @Published var conflictWarnings: [String] = []
    @Published private(set) var searchResults: [MarkdownSearchResult] = []
    @Published private(set) var isSearching = false
    @Published private(set) var completedSearchQuery = ""
    @Published private(set) var completedSearchScope = MarkdownSearchScope.all
    @Published private(set) var libraryRevision = 0
    @Published private(set) var draftRecoveryIssue: String?

    let folderAccess: FolderAccessService
    let fileStore: MarkdownFileStore
    let draftRecoveryStore: CaptureDraftRecoveryStore
    let audioRecorder = AudioCaptureService()

    private var queue: PendingWriteQueue?
    private var pendingCaptureRoute: CaptureRoute?
    private var activeSearchQuery = ""
    private var activeSearchScope = MarkdownSearchScope.all
    private var searchGeneration = 0
    private var libraryConfigurationID = UUID()
    private var draftPersistenceTask: Task<Void, Never>?
    private var draftRecoveryEnabled = false
    private var recoveredDraftNeedsAnnouncement = false
    private var queueRecoveryWarning: String?

    var isPreparingAttachment: Bool { attachmentPreparationCount > 0 }

    var conflictFiles: [RecentMarkdownFile] {
        let paths = Set(conflictWarnings)
        return libraryFiles.filter { paths.contains($0.relativePath) }
    }

    var recoveryWarnings: [String] {
        let conflictPaths = Set(conflictFiles.map(\.relativePath))
        return conflictWarnings.filter { !conflictPaths.contains($0) }
    }

    var allFolders: [LibraryFolderNode] {
        folders.flatMap(\.flattened)
    }

    init(
        bootstrapImmediately: Bool = true,
        folderAccess: FolderAccessService = FolderAccessService(),
        fileStore: MarkdownFileStore = MarkdownFileStore(),
        draftRecoveryStore: CaptureDraftRecoveryStore = CaptureDraftRecoveryStore(),
        restoreDraftImmediately: Bool? = nil
    ) {
        self.folderAccess = folderAccess
        self.fileStore = fileStore
        self.draftRecoveryStore = draftRecoveryStore
        draftRecoveryEnabled = true
        if restoreDraftImmediately ?? bootstrapImmediately {
            Task { await restoreCaptureDraftIfNeeded() }
        }
        if bootstrapImmediately {
            Task { await bootstrap() }
        }
    }

    func bootstrap() async {
        let configurationID = beginLibraryConfiguration()
        do {
            guard libraryConfigurationID == configurationID else { return }
            if let root = try folderAccess.resolvePersistedFolder() {
                _ = try await configureFolder(root, configurationID: configurationID)
            } else if libraryConfigurationID == configurationID {
                folderStatus = .missing
            }
        } catch {
            guard libraryConfigurationID == configurationID else { return }
            folderStatus = .error(error.localizedDescription)
            statusToast = .error(String(localized: "Folder access failed"))
        }
    }

    func selectFolder(_ url: URL) {
        let configurationID = beginLibraryConfiguration()
        if case .recent = draft.target {
            draft.target = .inbox
        }
        Task {
            do {
                guard libraryConfigurationID == configurationID else { return }
                try folderAccess.persistFolder(url)
                guard try await configureFolder(url, configurationID: configurationID) else { return }
                if libraryConfigurationID == configurationID {
                    statusToast = .saved(String(localized: "Folder ready"))
                }
            } catch {
                guard libraryConfigurationID == configurationID else { return }
                folderStatus = .error(error.localizedDescription)
                statusToast = .error(String(localized: "Could not prepare folder"))
            }
        }
    }

    func forgetFolderAndChooseAgain() {
        libraryConfigurationID = UUID()
        folderAccess.forgetPersistedFolder()
        folderStatus = .missing
        inboxItems = []
        libraryFiles = []
        recentFiles = []
        folders = []
        trashedFiles = []
        attachments = []
        librarySummary = LibrarySummary()
        tagSummaries = []
        conflictWarnings = []
        queueRecoveryWarning = nil
        searchResults = []
        isSearching = false
        libraryRevision += 1
        queue = nil
        if case .recent = draft.target {
            draft.target = .inbox
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

    func persistCaptureDraftNow() {
        guard draftRecoveryEnabled else { return }
        draftPersistenceTask?.cancel()
        let snapshot = draft
        draftPersistenceTask = Task { await persistCaptureDraft(snapshot) }
    }

    func retryCaptureDraftRecovery() {
        Task { await restoreCaptureDraftIfNeeded() }
    }

    func discardUnrecoverableCaptureDraft() {
        draftPersistenceTask?.cancel()
        Task {
            do {
                try await draftRecoveryStore.clear()
                draftRecoveryIssue = nil
                statusToast = .saved(String(localized: "Unrecoverable quick note discarded"))
                if draft.canSend { scheduleDraftPersistenceIfNeeded() }
            } catch {
                statusToast = .error(String(localized: "Could not discard the saved quick note"))
            }
        }
    }

    func sendDraft(continueCapturing: Bool = true) {
        guard draft.canSend,
              !isSendingDraft,
              !isPreparingAttachment,
              !isAudioTransitioning,
              !isTranscribingAudio,
              !audioRecorder.isRecording else { return }
        let submittedDraft = draft
        let canUseInboxDelta = submittedDraft.target == .inbox && submittedDraft.attachments.isEmpty
        isSendingDraft = true
        Task {
            defer { isSendingDraft = false }
            do {
                try await appendDraft(submittedDraft)
                let finished = finishSubmission(submittedDraft, continueCapturing: continueCapturing)
                statusToast = .saved(
                    finished
                        ? (continueCapturing
                            ? String(localized: "Saved. Ready for next")
                            : String(localized: "Saved"))
                        : String(localized: "Saved. New changes kept")
                )
                await refreshAfterWrite(canUseInboxDelta: canUseInboxDelta)
            } catch {
                if let draftSaveError = error as? DraftSaveError,
                   case .queuedForReplay = draftSaveError {
                    _ = finishSubmission(submittedDraft, continueCapturing: continueCapturing)
                    syncStatus = .pending
                    statusToast = .pending(String(localized: "Saved to pending queue"))
                    return
                }
                if let draftSaveError = error as? DraftSaveError {
                    statusToast = .error(draftSaveError.localizedDescription)
                    return
                }
                statusToast = .error(String(localized: "Could not save. Draft kept open"))
            }
        }
    }

    func attachPhoto(_ item: PhotosPickerItem?) {
        guard let item, !isSendingDraft else { return }
        attachmentPreparationCount += 1
        Task {
            defer { attachmentPreparationCount -= 1 }
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

    private func scheduleDraftPersistenceIfNeeded() {
        guard draftRecoveryEnabled else { return }
        draftPersistenceTask?.cancel()
        let snapshot = draft
        draftPersistenceTask = Task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await persistCaptureDraft(snapshot)
        }
    }

    private func persistCaptureDraft(_ snapshot: CaptureDraft) async {
        do {
            try await draftRecoveryStore.save(snapshot)
        } catch {
            guard !Task.isCancelled else { return }
            statusToast = .error(String(localized: "Could not protect the quick note draft"))
        }
    }

    private func restoreCaptureDraftIfNeeded() async {
        do {
            guard let recovered = try await draftRecoveryStore.load(),
                  !draft.canSend else { return }
            draftRecoveryEnabled = false
            draft = recovered
            draftRecoveryEnabled = true
            draftRecoveryIssue = nil
            recoveredDraftNeedsAnnouncement = true
            announceRecoveredDraftIfPossible()
        } catch {
            draftRecoveryIssue = error.localizedDescription
            statusToast = .error(String(localized: "Quick note recovery needs attention"))
        }
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

    func refreshAfterSceneActivation() async {
        guard case .ready = folderStatus,
              let queue,
              !isSendingDraft else { return }

        let pendingCount: Int
        do {
            let queueLoadResult = try await queue.load()
            if case .quarantined(let filename) = queueLoadResult {
                queueRecoveryWarning = Self.queueRecoveryWarning(filename: filename)
                statusToast = .pending(String(localized: "Damaged pending captures were preserved"))
            }

            pendingCount = await queue.pendingCount()
            if pendingCount > 0 {
                try await queue.replay { [fileStore] item in
                    try await fileStore.performPendingWrite(item)
                }
            }
        } catch {
            let remainingCount = await queue.pendingCount()
            if remainingCount > 0 { syncStatus = .pending }
            statusToast = .error(String(localized: "Queue replay failed"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return
        }

        do {
            let snapshot = try await fileStore.loadLibrarySnapshot()
            let remainingCount = await queue.pendingCount()
            apply(snapshot, pendingCount: remainingCount)
            libraryRevision += 1
            await refreshActiveSearchIfNeeded()
            if pendingCount > 0, remainingCount == 0 {
                statusToast = .saved(String(localized: "Pending queue replayed"))
            }
        } catch {
            statusToast = .error(String(localized: "Inbox refresh failed"))
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

    func createStandaloneNote(inFolder relativeFolderPath: String? = nil) {
        guard case .ready = folderStatus else { return }
        Task {
            do {
                let document = try await fileStore.createMarkdownDocument(
                    inFolder: relativeFolderPath
                )
                await refreshInbox()
                selectedDocument = document
            } catch {
                statusToast = .error(String(localized: "Could not create note"))
            }
        }
    }

    func discardEmptyNewDocumentIfNeeded(_ document: MarkdownDocument, markdown: String) {
        guard document.isNew, markdown.isEmpty else { return }
        Task {
            do {
                try await fileStore.discardEmptyNewMarkdownDocument(
                    relativePath: document.relativePath
                )
                if selectedDocument?.id == document.id { selectedDocument = nil }
                await refreshInbox()
            } catch {
                statusToast = .error(String(localized: "Could not discard empty note"))
            }
        }
    }

    func canMoveToRecentlyDeleted(_ file: RecentMarkdownFile) -> Bool {
        file.relativePath != "Inbox.md" && !file.relativePath.hasPrefix("Daily/")
    }

    func moveToRecentlyDeleted(_ file: RecentMarkdownFile) {
        guard canMoveToRecentlyDeleted(file) else {
            statusToast = .error(String(localized: "Inbox and Daily notes cannot be moved to Recently Deleted."))
            return
        }
        Task {
            do {
                try await fileStore.trashMarkdownDocument(relativePath: file.relativePath)
                if selectedDocument?.relativePath == file.relativePath {
                    selectedDocument = nil
                }
                statusToast = .saved(String(localized: "Moved to Recently Deleted"))
                await refreshInbox()
                await refreshActiveSearchIfNeeded()
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func moveToRecentlyDeleted(_ files: [RecentMarkdownFile]) async -> Bool {
        guard !files.isEmpty else { return false }
        guard files.allSatisfy(canMoveToRecentlyDeleted) else {
            statusToast = .error(String(localized: "Inbox and Daily notes cannot be moved to Recently Deleted."))
            return false
        }
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            _ = try await fileStore.trashMarkdownDocuments(
                relativePaths: files.map(\.relativePath)
            )
            if let selectedDocument,
               files.contains(where: { $0.relativePath == selectedDocument.relativePath }) {
                self.selectedDocument = nil
            }
            statusToast = .saved(String(localized: "Selected Notes Moved to Recently Deleted"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            await refreshInbox()
            return false
        }
    }

    func togglePinned(_ file: RecentMarkdownFile) {
        Task {
            do {
                try await fileStore.setPinned(!file.isPinned, relativePath: file.relativePath)
                statusToast = .saved(
                    file.isPinned ? String(localized: "Unpinned") : String(localized: "Pinned")
                )
                await refreshInbox()
                await refreshActiveSearchIfNeeded()
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func setPinned(_ files: [RecentMarkdownFile], isPinned: Bool) async -> Bool {
        guard !files.isEmpty else { return false }
        do {
            try await fileStore.setPinned(
                isPinned,
                relativePaths: files.map(\.relativePath)
            )
            statusToast = .saved(
                isPinned
                    ? String(localized: "Selected Notes Pinned")
                    : String(localized: "Selected Notes Unpinned")
            )
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    func duplicate(_ file: RecentMarkdownFile) {
        guard canMoveToRecentlyDeleted(file) else {
            statusToast = .error(String(localized: "Inbox and Daily notes cannot be duplicated."))
            return
        }
        Task {
            do {
                _ = try await fileStore.duplicateMarkdownDocument(
                    relativePath: file.relativePath
                )
                statusToast = .saved(String(localized: "Note Duplicated"))
                await refreshInbox()
                await refreshActiveSearchIfNeeded()
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    func keepConflictCopy(_ file: RecentMarkdownFile) {
        Task {
            do {
                let recovered = try await fileStore.keepConflictCopy(
                    relativePath: file.relativePath
                )
                if selectedDocument?.relativePath == file.relativePath {
                    selectedDocument = try await fileStore.loadMarkdownDocument(
                        relativePath: recovered.relativePath
                    )
                }
                statusToast = .saved(String(localized: "Conflict Kept as Note"))
                await refreshInbox()
                await refreshActiveSearchIfNeeded()
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func createFolder(named name: String, parent: String? = nil) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            _ = try await fileStore.createFolder(named: name, parentRelativePath: parent)
            statusToast = .saved(String(localized: "Folder Created"))
            await refreshInbox()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func renameFolder(_ folder: LibraryFolderNode, to name: String) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            _ = try await fileStore.renameFolder(relativePath: folder.relativePath, to: name)
            statusToast = .saved(String(localized: "Folder Renamed"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func moveFolder(_ folder: LibraryFolderNode, to parent: LibraryFolderNode?) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            let movedPath = try await fileStore.moveFolder(
                relativePath: folder.relativePath,
                toParent: parent?.relativePath
            )
            if let selectedDocument,
               selectedDocument.relativePath.hasPrefix(folder.relativePath + "/") {
                let updatedPath = movedPath
                    + selectedDocument.relativePath.dropFirst(folder.relativePath.count)
                self.selectedDocument = try await fileStore.loadMarkdownDocument(
                    relativePath: updatedPath
                )
            }
            statusToast = .saved(String(localized: "Folder Moved"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteFolder(_ folder: LibraryFolderNode) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            try await fileStore.trashFolder(relativePath: folder.relativePath)
            if let selectedDocument,
               selectedDocument.relativePath.hasPrefix(folder.relativePath + "/") {
                self.selectedDocument = nil
            }
            statusToast = .saved(String(localized: "Folder Moved to Recently Deleted"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    func move(_ file: RecentMarkdownFile, to folder: LibraryFolderNode) {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return
        }
        Task {
            do {
                let moved = try await fileStore.moveMarkdownDocument(
                    relativePath: file.relativePath,
                    toFolder: folder.relativePath
                )
                if selectedDocument?.relativePath == file.relativePath {
                    selectedDocument = try await fileStore.loadMarkdownDocument(
                        relativePath: moved.relativePath
                    )
                }
                statusToast = .saved(String(localized: "Note Moved"))
                await refreshInbox()
                await refreshActiveSearchIfNeeded()
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func move(_ files: [RecentMarkdownFile], to folder: LibraryFolderNode) async -> Bool {
        guard !files.isEmpty else { return false }
        guard files.allSatisfy(canMoveToRecentlyDeleted) else {
            statusToast = .error(String(localized: "Inbox and Daily notes cannot be moved between folders."))
            return false
        }
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            _ = try await fileStore.moveMarkdownDocuments(
                relativePaths: files.map(\.relativePath),
                toFolder: folder.relativePath
            )
            if let selectedDocument,
               files.contains(where: {
                   $0.relativePath == selectedDocument.relativePath
               }) {
                self.selectedDocument = nil
            }
            statusToast = .saved(String(localized: "Selected Notes Moved"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            await refreshInbox()
            return false
        }
    }

    func restore(_ item: TrashedMarkdownFile) {
        Task {
            do {
                _ = try await fileStore.restoreTrashedMarkdownDocument(id: item.id)
                statusToast = .saved(String(localized: "Restored"))
                await refreshInbox()
                await refreshActiveSearchIfNeeded()
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func restore(_ items: [TrashedMarkdownFile]) async -> Bool {
        guard !items.isEmpty else { return false }
        do {
            _ = try await fileStore.restoreTrashedMarkdownDocuments(
                ids: items.map(\.id)
            )
            statusToast = .saved(String(localized: "Selected Notes Restored"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            await refreshInbox()
            return false
        }
    }

    func permanentlyDelete(_ item: TrashedMarkdownFile) {
        Task {
            do {
                try await fileStore.permanentlyDeleteTrashedMarkdownDocument(id: item.id)
                statusToast = .saved(String(localized: "Deleted Permanently"))
                await refreshInbox()
            } catch {
                statusToast = .error(error.localizedDescription)
            }
        }
    }

    @discardableResult
    func permanentlyDelete(_ items: [TrashedMarkdownFile]) async -> Bool {
        guard !items.isEmpty else { return false }
        do {
            try await fileStore.permanentlyDeleteTrashedMarkdownDocuments(
                ids: items.map(\.id)
            )
            statusToast = .saved(String(localized: "Selected Notes Deleted Permanently"))
            await refreshInbox()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            await refreshInbox()
            return false
        }
    }

    func searchLibrary(
        query: String,
        scope: MarkdownSearchScope = .all
    ) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        activeSearchQuery = trimmed
        activeSearchScope = scope
        guard !trimmed.isEmpty else {
            searchResults = []
            isSearching = false
            completedSearchQuery = ""
            completedSearchScope = scope
            return
        }
        isSearching = true
        do {
            let results = try await fileStore.search(query: trimmed, scope: scope)
            guard !Task.isCancelled,
                  searchGeneration == generation,
                  activeSearchQuery == trimmed,
                  activeSearchScope == scope else { return }
            searchResults = results
            completedSearchQuery = trimmed
            completedSearchScope = scope
        } catch is CancellationError {
            if searchGeneration == generation { isSearching = false }
            return
        } catch {
            guard searchGeneration == generation else { return }
            searchResults = []
            completedSearchQuery = trimmed
            completedSearchScope = scope
            statusToast = .error(String(localized: "Search could not be completed"))
        }
        if searchGeneration == generation { isSearching = false }
    }

    func clearSearch() {
        searchGeneration += 1
        activeSearchQuery = ""
        activeSearchScope = .all
        searchResults = []
        isSearching = false
        completedSearchQuery = ""
        completedSearchScope = .all
    }

    func openSearchResult(_ result: MarkdownSearchResult) {
        switch result.destination {
        case .file(let file):
            openFile(file)
        case .memo(let memo):
            selectedMemo = memo
        }
    }

    func saveDocument(
        _ document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String,
        announce: Bool = true
    ) async -> MarkdownDocument? {
        do {
            let updated: MarkdownDocument
            if document.isNew {
                updated = try await fileStore.finalizeNewMarkdownDocument(
                    relativePath: document.relativePath,
                    markdown: markdown,
                    expectedMarkdown: expectedMarkdown
                )
            } else {
                updated = try await fileStore.saveMarkdownDocument(
                    relativePath: document.relativePath,
                    markdown: markdown,
                    expectedMarkdown: expectedMarkdown
                )
            }
            selectedDocument = updated
            if announce { statusToast = .saved(String(localized: "Saved")) }
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func saveMemo(
        _ memo: MemoBlock,
        body: String,
        expectedBody: String,
        announce: Bool = true
    ) async -> MemoBlock? {
        do {
            try await fileStore.applyInboxMutation(
                .replaceBody(memoID: memo.id, expectedBody: expectedBody, newBody: body)
            )
            await refreshInboxDelta()
            guard let updated = inboxItems.first(where: { $0.id == memo.id }) else {
                throw InboxMutationError.memoNotFound
            }
            selectedMemo = updated
            if announce { statusToast = .saved(String(localized: "Saved")) }
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func reloadDocument(_ document: MarkdownDocument) async -> MarkdownDocument? {
        do {
            let reloaded = try await fileStore.loadMarkdownDocument(relativePath: document.relativePath)
            selectedDocument = reloaded
            return reloaded
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func reloadMemo(_ memo: MemoBlock) async -> MemoBlock? {
        await refreshInboxDelta()
        return inboxItems.first { $0.id == memo.id }
    }

    func attachPhoto(
        _ item: PhotosPickerItem?,
        to document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        guard let item, attachmentPreparationCount == 0 else { return nil }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw CaptureAttachmentError.empty
            }
            let attachment = try CaptureAttachment.validatedImage(data: data)
            let updated = try await fileStore.attachToMarkdownDocument(
                relativePath: document.relativePath,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown,
                attachment: attachment
            )
            selectedDocument = updated
            statusToast = .saved(String(localized: "Image attached"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func attachFile(
        _ url: URL,
        to document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        guard attachmentPreparationCount == 0 else { return nil }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw CaptureAttachmentError.empty }
            if let byteCount = values.fileSize,
               byteCount > CaptureAttachmentPolicy.maximumFileBytes {
                throw CaptureAttachmentError.tooLarge(
                    maximumBytes: CaptureAttachmentPolicy.maximumFileBytes
                )
            }
            let attachment = try CaptureAttachment.validatedFile(
                data: Data(contentsOf: url, options: .mappedIfSafe),
                suggestedName: url.lastPathComponent
            )
            let updated = try await fileStore.attachToMarkdownDocument(
                relativePath: document.relativePath,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown,
                attachment: attachment
            )
            selectedDocument = updated
            statusToast = .saved(String(localized: "File attached"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func attachAudio(
        _ data: Data,
        to document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        guard attachmentPreparationCount == 0 else { return nil }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        do {
            let attachment = try CaptureAttachment.validatedAudio(data: data)
            let updated = try await fileStore.attachToMarkdownDocument(
                relativePath: document.relativePath,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown,
                attachment: attachment
            )
            selectedDocument = updated
            statusToast = .saved(String(localized: "Audio attached"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func removeAttachment(
        line: String,
        from document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        do {
            let updated = try await fileStore.removeAttachmentFromMarkdownDocument(
                relativePath: document.relativePath,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown,
                attachmentLine: line
            )
            selectedDocument = updated
            statusToast = .saved(String(localized: "Attachment removed from note"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func renameAttachment(
        line: String,
        path: String,
        to name: String,
        in document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        do {
            let updated = try await fileStore.renameAttachmentInMarkdownDocument(
                relativePath: document.relativePath,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown,
                attachmentLine: line,
                attachmentRelativePath: path,
                to: name
            )
            selectedDocument = updated
            statusToast = .saved(String(localized: "Attachment Renamed"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    private func refreshActiveSearchIfNeeded() async {
        guard !activeSearchQuery.isEmpty else { return }
        await searchLibrary(query: activeSearchQuery, scope: activeSearchScope)
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
        let pendingCount = await queue?.pendingCount() ?? 0
        apply(snapshot, pendingCount: pendingCount)
    }

    private func apply(_ snapshot: MarkdownLibrarySnapshot, pendingCount: Int) {
        inboxItems = snapshot.inboxItems
        libraryFiles = snapshot.allFiles
        recentFiles = snapshot.recentFiles
        folders = snapshot.folders
        trashedFiles = snapshot.trashedFiles
        attachments = snapshot.attachments
        librarySummary = snapshot.summary
        tagSummaries = Self.tagSummaries(from: inboxItems, files: libraryFiles)
        conflictWarnings = snapshot.conflictWarnings
        if let queueRecoveryWarning {
            conflictWarnings.append(queueRecoveryWarning)
        }
        if conflictWarnings.isEmpty == false {
            syncStatus = .conflict
        } else if pendingCount > 0 {
            syncStatus = .pending
        } else {
            syncStatus = .idle
        }
    }

    private func beginLibraryConfiguration() -> UUID {
        let configurationID = UUID()
        libraryConfigurationID = configurationID
        folderStatus = .loading
        searchGeneration += 1
        activeSearchQuery = ""
        activeSearchScope = .all
        searchResults = []
        isSearching = false
        completedSearchQuery = ""
        completedSearchScope = .all
        queueRecoveryWarning = nil
        return configurationID
    }

    private func configureFolder(_ root: URL, configurationID: UUID) async throws -> Bool {
        guard libraryConfigurationID == configurationID else { return false }
        try folderAccess.withAccess(to: root) {
            try FolderInitializer.initialize(root)
        }
        guard libraryConfigurationID == configurationID else { return false }
        await fileStore.configure(root: root)
        guard libraryConfigurationID == configurationID else { return false }
        let nextQueue = PendingWriteQueue(root: root)
        let queueLoadResult = try await nextQueue.load()
        switch queueLoadResult {
        case .ready:
            queueRecoveryWarning = nil
        case .quarantined(let filename):
            queueRecoveryWarning = Self.queueRecoveryWarning(filename: filename)
        }
        guard libraryConfigurationID == configurationID else { return false }
        var replayFailed = false
        do {
            try await nextQueue.replay { [fileStore] item in
                try await fileStore.performPendingWrite(item)
            }
        } catch {
            replayFailed = true
        }
        guard libraryConfigurationID == configurationID else { return false }
        let snapshot = try await fileStore.loadLibrarySnapshot()
        let pendingCount = await nextQueue.pendingCount()
        guard libraryConfigurationID == configurationID else { return false }
        queue = nextQueue
        apply(snapshot, pendingCount: pendingCount)
        folderStatus = .ready(root)
        libraryRevision += 1
        announceRecoveredDraftIfPossible()
        if replayFailed {
            syncStatus = .pending
            statusToast = .pending(String(localized: "Pending captures need attention"))
        } else if queueRecoveryWarning != nil {
            statusToast = .pending(String(localized: "Damaged pending captures were preserved"))
        }
        presentPendingCaptureIfPossible()
        return true
    }

    private static func queueRecoveryWarning(filename: String) -> String {
        String(
            format: String(localized: "pending.queue_quarantined.format"),
            locale: .current,
            filename
        )
    }

    private func announceRecoveredDraftIfPossible() {
        guard recoveredDraftNeedsAnnouncement,
              case .ready = folderStatus else { return }
        recoveredDraftNeedsAnnouncement = false
        statusToast = .pending(String(localized: "Unsaved quick note restored"))
    }

    private func appendDraft(_ draft: CaptureDraft) async throws {
        guard let root = folderAccess.currentRoot, let queue else {
            throw FolderAccessError.missingFolder
        }

        let pending = try await fileStore.preparePendingWrite(for: draft, root: root)
        do {
            try await queue.enqueue(pending)
        } catch {
            throw DraftSaveError.pendingQueueRejected(error.localizedDescription)
        }
        do {
            try await fileStore.performPendingWrite(pending)
            try await queue.remove(id: pending.id)
        } catch {
            throw DraftSaveError.queuedForReplay
        }
    }

    @discardableResult
    private func finishSubmission(_ submittedDraft: CaptureDraft, continueCapturing: Bool) -> Bool {
        guard draft == submittedDraft else { return false }
        draft = CaptureDraft(target: submittedDraft.target)
        captureRoute = .text
        if !continueCapturing {
            isCapturePresented = false
        }
        return true
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

    private static func tagSummaries(
        from memos: [MemoBlock],
        files: [RecentMarkdownFile]
    ) -> [TagSummary] {
        var summaries: [String: TagSummary] = [:]
        func countTags(_ tags: [String]) {
            var countedInNote = Set<String>()
            for tag in tags {
                let key = tag.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: .current
                )
                guard countedInNote.insert(key).inserted else { continue }
                if var summary = summaries[key] {
                    summary.count += 1
                    summaries[key] = summary
                } else {
                    summaries[key] = TagSummary(name: tag, count: 1)
                }
            }
        }
        for memo in memos {
            countTags(memo.tags)
        }
        for file in files where file.relativePath != "Inbox.md" {
            countTags(file.tags)
        }

        return summaries.values
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
    case queuedForReplay

    var errorDescription: String? {
        switch self {
        case .pendingQueueRejected(let reason):
            return String(
                format: String(localized: "draft.kept_open.format"),
                locale: .current,
                reason
            )
        case .queuedForReplay:
            return String(localized: "Saved to pending queue")
        }
    }
}

struct TagSummary: Equatable, Identifiable {
    var name: String
    var count: Int

    var id: String { name }
}

private extension LibraryFolderNode {
    var flattened: [LibraryFolderNode] {
        [self] + children.flatMap(\.flattened)
    }
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
