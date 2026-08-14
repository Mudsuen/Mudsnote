import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum CaptureRoute: String {
    case text
    case image
    case audio
}

enum NoteOpenMode {
    case read
    case edit
}

enum AudioCapturePhase: Equatable {
    case idle
    case requestingPermission
    case recording
    case stopping
    case transcribing
    case failed(String)
}

enum SystemEntryRequest {
    static let pendingRouteKey = "MudsnotePendingSystemRoute"
    static let pendingSearchKey = "MudsnotePendingSystemSearch"
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
    @Published var smartFolders: [SmartFolderDefinition] = []
    @Published var selectedMemo: MemoBlock?
    @Published var selectedDocument: MarkdownDocument?
    @Published var noteOpenMode: NoteOpenMode = .read
    @Published var isReaderExpanded = false
    @Published var librarySummary = LibrarySummary()
    @Published var tagSummaries: [TagSummary] = []
    @Published var draft = CaptureDraft() {
        didSet { scheduleDraftPersistenceIfNeeded() }
    }
    @Published var captureRoute: CaptureRoute = .text
    @Published var isCapturePresented = false
    @Published var isSendingDraft = false
    @Published private(set) var audioCapturePhase: AudioCapturePhase = .idle
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
    @Published private(set) var activeTagMutation: String?
    @Published private(set) var captureAttachmentIssue: String?
    @Published private(set) var captureSubmissionIssue: String?
    @Published private(set) var attachmentPresentationRevision = 0
    @Published private(set) var isLibrarySearchRequested = false
    @Published private(set) var isInitialLibraryLoading = true
    @Published private(set) var defaultCaptureFolderPath: String?
    @Published private(set) var recentCaptureFolders: [LibraryFolderNode] = []

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
    private var audioStartTask: Task<Void, Never>?
    private var audioStopTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var captureSessionID = UUID()
    private var transcriptionID: UUID?
    private var isSceneRefreshRunning = false
    private var sceneRefreshRequested = false
    private var draftRecoveryEnabled = false
    private var recoveredDraftNeedsAnnouncement = false
    private var queueRecoveryWarning: String?
    private let attachmentPresentationPreferences: AttachmentPresentationPreferences
    private let captureFolderPreferences: CaptureFolderPreferences
    private let libraryRefreshBarrier: @Sendable () async -> Void
    private let initialLibraryLoadBarrier: @Sendable () async -> Void
    private var captureTargetWasExplicitlySelected = false
    #if DEBUG
    private var shouldPresentAttachmentFailureFixture = ProcessInfo.processInfo.arguments.contains(
        "-ui-testing-attachment-error"
    )
    #endif

    var isPreparingAttachment: Bool { attachmentPreparationCount > 0 }

    var isAudioTransitioning: Bool {
        switch audioCapturePhase {
        case .requestingPermission, .stopping:
            true
        default:
            false
        }
    }

    var isTranscribingAudio: Bool {
        audioCapturePhase == .transcribing
    }

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

    var visibleLibraryFolders: [LibraryFolderNode] {
        folders.filter { !$0.isMergedInboxFolder }
    }

    var mergedInboxFolders: [LibraryFolderNode] {
        folders.filter(\.isMergedInboxFolder)
    }

    var primaryMergedInboxFolder: LibraryFolderNode? {
        mergedInboxFolders.first {
            $0.name.compare(
                "000-inbox",
                options: [.caseInsensitive, .widthInsensitive]
            ) == .orderedSame
        } ?? mergedInboxFolders.first
    }

    var showsMergedInbox: Bool {
        !mergedInboxFolders.isEmpty || !inboxItems.isEmpty
    }

    var mergedInboxFiles: [RecentMarkdownFile] {
        let roots = mergedInboxFolders.map(\.relativePath)
        guard !roots.isEmpty else { return [] }
        return libraryFiles.filter { file in
            roots.contains { root in
                file.relativePath.hasPrefix(root + "/")
            }
        }
    }

    var mergedInboxCount: Int {
        inboxItems.count + mergedInboxFiles.count
    }

    var defaultCaptureFolderLabel: String {
        allFolders.first {
            $0.relativePath == defaultCaptureFolderPath
        }?.name ?? String(localized: "Inbox")
    }

    init(
        bootstrapImmediately: Bool = true,
        folderAccess: FolderAccessService = FolderAccessService(),
        fileStore: MarkdownFileStore = MarkdownFileStore(),
        draftRecoveryStore: CaptureDraftRecoveryStore = CaptureDraftRecoveryStore(),
        restoreDraftImmediately: Bool? = nil,
        defaults: UserDefaults = .standard,
        libraryRefreshBarrier: @escaping @Sendable () async -> Void = {},
        initialLibraryLoadBarrier: @escaping @Sendable () async -> Void = {
            await Task.yield()
        }
    ) {
        self.folderAccess = folderAccess
        self.fileStore = fileStore
        self.draftRecoveryStore = draftRecoveryStore
        self.libraryRefreshBarrier = libraryRefreshBarrier
        self.initialLibraryLoadBarrier = initialLibraryLoadBarrier
        attachmentPresentationPreferences = AttachmentPresentationPreferences(defaults: defaults)
        captureFolderPreferences = CaptureFolderPreferences(defaults: defaults)
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
                isInitialLibraryLoading = false
                folderStatus = .missing
            }
        } catch {
            guard libraryConfigurationID == configurationID else { return }
            isInitialLibraryLoading = false
            folderStatus = .error(error.localizedDescription)
            statusToast = .error(String(localized: "Folder access failed"))
        }
    }

    func selectFolder(_ url: URL) {
        let configurationID = beginLibraryConfiguration()
        draft.target = .folder(nil)
        captureTargetWasExplicitlySelected = false
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
                isInitialLibraryLoading = false
                folderStatus = .error(error.localizedDescription)
                statusToast = .error(String(localized: "Could not prepare folder"))
            }
        }
    }

    func forgetFolderAndChooseAgain() {
        libraryConfigurationID = UUID()
        folderAccess.forgetPersistedFolder()
        isInitialLibraryLoading = false
        folderStatus = .missing
        inboxItems = []
        libraryFiles = []
        recentFiles = []
        folders = []
        trashedFiles = []
        attachments = []
        smartFolders = []
        librarySummary = LibrarySummary()
        tagSummaries = []
        conflictWarnings = []
        queueRecoveryWarning = nil
        searchResults = []
        isSearching = false
        libraryRevision += 1
        queue = nil
        draft.target = .folder(nil)
        defaultCaptureFolderPath = nil
        recentCaptureFolders = []
        captureTargetWasExplicitlySelected = false
    }

    func showCapture(
        _ route: CaptureRoute = .text,
        inFolder relativeFolderPath: String? = nil
    ) {
        endCaptureSession()
        captureSessionID = UUID()
        if let relativeFolderPath {
            captureTargetWasExplicitlySelected = true
            draft.target = .folder(relativeFolderPath)
        } else if !draft.canSend {
            captureTargetWasExplicitlySelected = false
            draft.target = .folder(defaultCaptureFolderPath)
        }
        captureRoute = route
        isCapturePresented = true
        #if DEBUG
        if shouldPresentAttachmentFailureFixture {
            shouldPresentAttachmentFailureFixture = false
            attachCameraPhoto(.photo(Data()))
        }
        #endif
    }

    func selectCaptureFolder(_ relativePath: String?) {
        captureTargetWasExplicitlySelected = true
        draft.target = .folder(relativePath)
    }

    func setDefaultCaptureFolder(_ relativePath: String) {
        captureFolderPreferences.setDefaultFolder(relativePath)
        refreshCaptureFolderPreferences()
        if !draft.canSend, !isCapturePresented {
            captureTargetWasExplicitlySelected = false
            draft.target = .folder(defaultCaptureFolderPath)
        }
    }

    func handle(url: URL) {
        guard url.scheme == "mudsnote" else { return }
        if url.host == "capture" {
            openSystemCapture(Self.captureRoute(from: url))
        } else if url.host == "search" {
            isLibrarySearchRequested = true
        }
    }

    @discardableResult
    func consumeLibrarySearchRequest() -> Bool {
        guard isLibrarySearchRequested else { return false }
        isLibrarySearchRequested = false
        return true
    }

    func consumeSystemEntryRequest() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: SystemEntryRequest.pendingSearchKey) {
            defaults.removeObject(forKey: SystemEntryRequest.pendingSearchKey)
            isLibrarySearchRequested = true
        }
        guard let value = defaults.string(forKey: SystemEntryRequest.pendingRouteKey),
              let route = CaptureRoute(rawValue: value) else {
            return
        }
        defaults.removeObject(forKey: SystemEntryRequest.pendingRouteKey)
        openSystemCapture(route)
    }

    func attachmentPresentationMode(
        notePath: String,
        attachmentPath: String
    ) -> AttachmentPresentationMode {
        _ = attachmentPresentationRevision
        return attachmentPresentationPreferences.mode(
            notePath: notePath,
            attachmentPath: attachmentPath
        )
    }

    func setAttachmentPresentationMode(
        _ mode: AttachmentPresentationMode,
        notePath: String,
        attachmentPath: String
    ) {
        attachmentPresentationPreferences.set(
            mode,
            notePath: notePath,
            attachmentPath: attachmentPath
        )
        attachmentPresentationRevision += 1
    }

    func setAllAttachmentPresentationModes(
        _ mode: AttachmentPresentationMode,
        notePath: String
    ) {
        attachmentPresentationPreferences.setAll(mode, notePath: notePath)
        attachmentPresentationRevision += 1
    }

    func moveAttachmentPresentationPreference(
        notePath: String,
        from oldPath: String,
        to newPath: String
    ) {
        attachmentPresentationPreferences.moveAttachment(
            notePath: notePath,
            from: oldPath,
            to: newPath
        )
        attachmentPresentationRevision += 1
    }

    func removeAttachmentPresentationPreference(
        notePath: String,
        attachmentPath: String
    ) {
        attachmentPresentationPreferences.removeAttachment(
            notePath: notePath,
            attachmentPath: attachmentPath
        )
        attachmentPresentationRevision += 1
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
              !audioRecorder.isRecording else { return }
        cancelTranscription()
        captureSubmissionIssue = nil
        let submittedDraft = draft
        let canUseInboxDelta = false
        isSendingDraft = true
        Task {
            defer { isSendingDraft = false }
            do {
                let createdFile = try await appendDraft(submittedDraft)
                applyCreatedProjection(createdFile)
                captureSubmissionIssue = nil
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
                    statusToast = .pending(draftSaveError.localizedDescription)
                    return
                }
                if let draftSaveError = error as? DraftSaveError {
                    captureSubmissionIssue = draftSaveError.localizedDescription
                    return
                }
                captureSubmissionIssue = String(localized: "Could not save. Draft kept open")
            }
        }
    }

    func retryCaptureSubmission() {
        sendDraft(continueCapturing: false)
    }

    func attachPhoto(_ item: PhotosPickerItem?) {
        guard let item, !isSendingDraft else { return }
        attachmentPreparationCount += 1
        Task {
            defer { attachmentPreparationCount -= 1 }
            do {
                let attachment = try await photoLibraryAttachment(from: item)
                try appendAttachment(attachment)
                statusToast = .saved(attachmentAttachedMessage(attachment))
            } catch {
                reportCaptureAttachmentFailure(error.localizedDescription)
            }
        }
    }

    func attachCameraPhoto(_ media: CapturedCameraMedia) {
        guard !isSendingDraft, attachmentPreparationCount == 0 else { return }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        do {
            let attachment: CaptureAttachment
            switch media {
            case .photo(let data):
                attachment = try CaptureAttachment.validatedImage(data: data)
            case .video(let video):
                attachment = video
            }
            try appendAttachment(attachment)
            statusToast = .saved(attachmentAttachedMessage(attachment))
        } catch {
            reportCaptureAttachmentFailure(error.localizedDescription)
        }
    }

    private func photoLibraryAttachment(from item: PhotosPickerItem) async throws -> CaptureAttachment {
        if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try await item.loadTransferable(type: PhotoLibraryMovie.self) else {
                throw CaptureAttachmentError.empty
            }
            return try CaptureAttachment.validatedVideo(
                data: movie.data,
                suggestedName: movie.suggestedName
            )
        }
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw CaptureAttachmentError.empty
        }
        return try CaptureAttachment.validatedImage(data: data)
    }

    private func attachmentAttachedMessage(_ attachment: CaptureAttachment) -> String {
        switch attachment {
        case .image: String(localized: "Image attached")
        case .video: String(localized: "Video attached")
        case .audio: String(localized: "Audio attached")
        case .file: String(localized: "File attached")
        }
    }

    func attachFile(_ url: URL) async -> String? {
        guard !isSendingDraft, attachmentPreparationCount == 0 else { return nil }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        do {
            let attachment = try importedFileAttachment(from: url)
            try appendAttachment(attachment)
            captureAttachmentIssue = nil
            statusToast = .saved(String(localized: "File attached"))
            return nil
        } catch {
            reportCaptureAttachmentFailure(error.localizedDescription)
            return error.localizedDescription
        }
    }

    func attachScannedDocument(_ pages: [UIImage]) async -> String? {
        guard !isSendingDraft, attachmentPreparationCount == 0 else { return nil }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        do {
            let data = try ScannedDocumentPDF.data(for: pages)
            let attachment = try CaptureAttachment.validatedFile(
                data: data,
                suggestedName: ScannedDocumentPDF.suggestedFileName
            )
            try appendAttachment(attachment)
            captureAttachmentIssue = nil
            statusToast = .saved(String(localized: "Scanned document attached"))
            return nil
        } catch {
            reportCaptureAttachmentFailure(error.localizedDescription)
            return error.localizedDescription
        }
    }

    func reportCaptureAttachmentFailure(_ message: String) {
        captureAttachmentIssue = message
    }

    func dismissCaptureAttachmentIssue() {
        captureAttachmentIssue = nil
    }

    func toggleAudioRecording() {
        guard !isAudioTransitioning, !isTranscribingAudio else { return }
        if audioRecorder.isRecording {
            stopAudioRecording()
        } else {
            startAudioRecording()
        }
    }

    func startAudioRecording() {
        guard !audioRecorder.isRecording,
              !isAudioTransitioning,
              !isTranscribingAudio else { return }
        let sessionID = captureSessionID
        audioCapturePhase = .requestingPermission
        audioStartTask?.cancel()
        audioStartTask = Task {
            do {
                try await audioRecorder.start()
                try Task.checkCancellation()
                guard captureSessionID == sessionID, isCapturePresented else {
                    audioRecorder.cancel()
                    return
                }
                audioCapturePhase = .recording
                statusToast = .pending(String(localized: "Recording"))
            } catch is CancellationError {
                if captureSessionID == sessionID {
                    audioCapturePhase = .idle
                }
            } catch {
                guard captureSessionID == sessionID else { return }
                audioCapturePhase = .failed(error.localizedDescription)
                reportCaptureAttachmentFailure(error.localizedDescription)
            }
            if captureSessionID == sessionID {
                audioStartTask = nil
            }
        }
    }

    private func stopAudioRecording() {
        guard audioRecorder.isRecording,
              !isAudioTransitioning,
              !isTranscribingAudio else { return }
        let sessionID = captureSessionID
        audioCapturePhase = .stopping
        audioStopTask?.cancel()
        audioStopTask = Task {
            do {
                guard let recording = try await audioRecorder.stop() else { return }
                try Task.checkCancellation()
                guard captureSessionID == sessionID, isCapturePresented else {
                    try? FileManager.default.removeItem(at: recording.temporaryURL)
                    return
                }
                let attachment: CaptureAttachment
                do {
                    attachment = try CaptureAttachment.validatedAudio(data: recording.data)
                    try appendAttachment(attachment)
                } catch {
                    try? FileManager.default.removeItem(at: recording.temporaryURL)
                    throw error
                }
                statusToast = .saved(String(localized: "Audio attached"))
                persistCaptureDraftNow()
                let operationID = UUID()
                transcriptionID = operationID
                audioCapturePhase = .transcribing
                transcriptionTask?.cancel()
                transcriptionTask = Task {
                    await transcribe(
                        recording,
                        sessionID: sessionID,
                        operationID: operationID
                    )
                }
            } catch is CancellationError {
                if captureSessionID == sessionID {
                    audioCapturePhase = .idle
                }
            } catch {
                guard captureSessionID == sessionID else { return }
                audioCapturePhase = .failed(error.localizedDescription)
                reportCaptureAttachmentFailure(error.localizedDescription)
            }
            if captureSessionID == sessionID {
                audioStopTask = nil
            }
        }
    }

    func cancelAudioRecording() {
        audioStartTask?.cancel()
        audioStartTask = nil
        audioStopTask?.cancel()
        audioStopTask = nil
        audioRecorder.cancel()
        audioCapturePhase = .idle
    }

    func skipAudioTranscription() {
        guard isTranscribingAudio else { return }
        cancelTranscription()
        statusToast = .pending(String(localized: "Audio kept without transcript"))
    }

    func endCaptureSession() {
        captureSessionID = UUID()
        cancelAudioRecording()
        cancelTranscription()
    }

    private func appendAttachment(_ attachment: CaptureAttachment) throws {
        try CaptureAttachmentPolicy.validateAppending(attachment, to: draft.attachments)
        draft.attachments.append(attachment)
        captureAttachmentIssue = nil
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
            captureTargetWasExplicitlySelected = true
            draftRecoveryIssue = nil
            recoveredDraftNeedsAnnouncement = true
            announceRecoveredDraftIfPossible()
        } catch {
            draftRecoveryIssue = error.localizedDescription
            statusToast = .error(String(localized: "Quick note recovery needs attention"))
        }
    }

    private func transcribe(
        _ recording: RecordedAudio,
        sessionID: UUID,
        operationID: UUID
    ) async {
        defer {
            try? FileManager.default.removeItem(at: recording.temporaryURL)
            if captureSessionID == sessionID, transcriptionID == operationID {
                transcriptionID = nil
                transcriptionTask = nil
                audioCapturePhase = .idle
            }
        }

        do {
            let text = try await audioRecorder.transcribe(url: recording.temporaryURL)
            try Task.checkCancellation()
            guard captureSessionID == sessionID,
                  transcriptionID == operationID else { return }
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
        } catch is CancellationError {
            return
        } catch {
            guard captureSessionID == sessionID,
                  transcriptionID == operationID else { return }
            audioCapturePhase = .failed(error.localizedDescription)
            statusToast = .error(error.localizedDescription)
        }
    }

    private func cancelTranscription() {
        transcriptionID = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if isTranscribingAudio {
            audioCapturePhase = .idle
        }
    }

    func replayQueue() {
        Task {
            do {
                let replayResult = try await queue?.replay { [fileStore, weak self] item in
                    let createdFile = try await fileStore.performPendingWrite(item)
                    self?.applyCreatedProjection(createdFile)
                    self?.recordSuccessfulPendingWrite(item)
                }
                if let replayResult {
                    recordPreservedPendingWrites(replayResult)
                }
                statusToast = replayResult?.preservedFailureFilenames.isEmpty == false
                    ? .pending(String(localized: "Damaged pending captures were preserved"))
                    : .saved(String(localized: "Pending queue replayed"))
                await refreshInbox()
            } catch {
                statusToast = .error(String(localized: "Queue replay failed"))
            }
        }
    }

    func refreshAfterSceneActivation() async {
        if isSceneRefreshRunning {
            sceneRefreshRequested = true
            return
        }
        if isInitialLibraryLoading {
            sceneRefreshRequested = true
            return
        }
        guard case .ready = folderStatus,
              let queue,
              !isSendingDraft else { return }
        let configurationID = libraryConfigurationID
        isSceneRefreshRunning = true
        defer {
            isSceneRefreshRunning = false
            if sceneRefreshRequested {
                sceneRefreshRequested = false
                Task { await refreshAfterSceneActivation() }
            }
        }

        let pendingCount: Int
        var replayResult = PendingWriteReplayResult()
        do {
            let queueLoadResult = try await queue.load()
            guard libraryConfigurationID == configurationID else { return }
            if case .quarantined(let filename) = queueLoadResult {
                queueRecoveryWarning = Self.queueRecoveryWarning(filename: filename)
                statusToast = .pending(String(localized: "Damaged pending captures were preserved"))
            }

            pendingCount = await queue.pendingCount()
            if pendingCount > 0 {
                replayResult = try await queue.replay { [fileStore, weak self] item in
                    let createdFile = try await fileStore.performPendingWrite(item)
                    self?.applyCreatedProjection(createdFile)
                    self?.recordSuccessfulPendingWrite(item)
                }
                recordPreservedPendingWrites(replayResult)
            }
            guard libraryConfigurationID == configurationID else { return }
        } catch {
            guard libraryConfigurationID == configurationID else { return }
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
            guard libraryConfigurationID == configurationID else { return }
            apply(snapshot, pendingCount: remainingCount)
            libraryRevision += 1
            await refreshActiveSearchIfNeeded()
            if replayResult.preservedFailureFilenames.isEmpty == false {
                statusToast = .pending(String(localized: "Damaged pending captures were preserved"))
            } else if pendingCount > 0, remainingCount == 0 {
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

    @discardableResult
    func renameTag(_ tag: String, to name: String) async -> Bool {
        await mutateTag(tag, mutation: .rename(to: name))
    }

    @discardableResult
    func deleteTag(_ tag: String) async -> Bool {
        await mutateTag(tag, mutation: .delete)
    }

    private func mutateTag(
        _ tag: String,
        mutation: MarkdownTagMutation
    ) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing tags."))
            return false
        }
        guard activeTagMutation == nil else { return false }
        activeTagMutation = tag
        defer { activeTagMutation = nil }
        do {
            let result = try await fileStore.mutateTag(tag, mutation: mutation)
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            if let selectedDocument,
               result.changedPaths.contains(selectedDocument.relativePath) {
                self.selectedDocument = try await fileStore.loadMarkdownDocument(
                    relativePath: selectedDocument.relativePath
                )
            }
            if let selectedMemo {
                self.selectedMemo = inboxItems.first { $0.id == selectedMemo.id }
            }
            switch mutation {
            case .rename:
                statusToast = .saved(String(localized: "Tag Renamed"))
            case .delete:
                statusToast = .saved(String(localized: "Tag Deleted"))
            }
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    func openFile(_ file: RecentMarkdownFile, mode: NoteOpenMode = .read) {
        noteOpenMode = mode
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

    func createNote(inFolder relativeFolderPath: String? = nil) {
        noteOpenMode = .edit
        Task {
            do {
                let document = try await fileStore.createMarkdownDocument(
                    inFolder: relativeFolderPath
                )
                selectedDocument = document
                await refreshInbox()
            } catch {
                noteOpenMode = .read
                statusToast = .error(String(localized: "Could not create note"))
            }
        }
    }

    func loadDocument(relativePath: String) async -> MarkdownDocument? {
        do {
            return try await fileStore.loadMarkdownDocument(relativePath: relativePath)
        } catch {
            statusToast = .error(String(localized: "Could not open Markdown file"))
            return nil
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
        file.relativePath != "Inbox.md"
    }

    func canReorganize(_ file: RecentMarkdownFile) -> Bool {
        file.relativePath != "Inbox.md"
    }

    func moveToRecentlyDeleted(_ file: RecentMarkdownFile) {
        Task {
            _ = await trashNote(file)
        }
    }

    @discardableResult
    func trashNote(_ file: RecentMarkdownFile) async -> Bool {
        guard canMoveToRecentlyDeleted(file) else {
            statusToast = .error(String(localized: "Inbox cannot be deleted."))
            return false
        }
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            let trashed = try await fileStore.trashMarkdownDocument(
                relativePath: file.relativePath
            )
            applyTrashedProjection([trashed])
            if selectedDocument?.relativePath == file.relativePath {
                selectedDocument = nil
            }
            statusToast = .saved(String(localized: "Deleted"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func moveToRecentlyDeleted(_ files: [RecentMarkdownFile]) async -> Bool {
        guard !files.isEmpty else { return false }
        guard files.allSatisfy(canMoveToRecentlyDeleted) else {
            statusToast = .error(String(localized: "Inbox cannot be deleted."))
            return false
        }
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            let trashed = try await fileStore.trashMarkdownDocuments(
                relativePaths: files.map(\.relativePath)
            )
            applyTrashedProjection(trashed)
            if let selectedDocument,
               files.contains(where: { $0.relativePath == selectedDocument.relativePath }) {
                self.selectedDocument = nil
            }
            statusToast = .saved(String(localized: "Selected Notes Deleted"))
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
        guard canReorganize(file) else {
            statusToast = .error(String(localized: "Inbox cannot be duplicated."))
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

    @discardableResult
    func renameNote(relativePath: String, to name: String) async -> MarkdownDocument? {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before renaming notes."))
            return nil
        }
        do {
            let renamed = try await fileStore.renameMarkdownDocument(
                relativePath: relativePath,
                to: name
            )
            let document = try await fileStore.loadMarkdownDocument(
                relativePath: renamed.relativePath
            )
            attachmentPresentationPreferences.moveNote(
                from: relativePath,
                to: renamed.relativePath
            )
            attachmentPresentationRevision += 1
            if selectedDocument?.relativePath == relativePath {
                selectedDocument = document
            }
            statusToast = .saved(String(localized: "Note Renamed"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return document
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
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
    func createSmartFolder(_ definition: SmartFolderDefinition) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            let created = try await fileStore.createSmartFolder(definition)
            smartFolders.append(created)
            smartFolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            libraryRevision += 1
            statusToast = .saved(String(localized: "Smart Folder Created"))
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func updateSmartFolder(_ definition: SmartFolderDefinition) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            let updated = try await fileStore.updateSmartFolder(definition)
            guard let index = smartFolders.firstIndex(where: { $0.id == updated.id }) else {
                await refreshInbox()
                return true
            }
            smartFolders[index] = updated
            smartFolders.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            libraryRevision += 1
            statusToast = .saved(String(localized: "Smart Folder Updated"))
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteSmartFolder(_ definition: SmartFolderDefinition) async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            try await fileStore.deleteSmartFolder(id: definition.id)
            smartFolders.removeAll { $0.id == definition.id }
            libraryRevision += 1
            statusToast = .saved(String(localized: "Smart Folder Deleted"))
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
            let renamedPath = try await fileStore.renameFolder(
                relativePath: folder.relativePath,
                to: name
            )
            attachmentPresentationPreferences.moveFolder(
                from: folder.relativePath,
                to: renamedPath
            )
            attachmentPresentationRevision += 1
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
            attachmentPresentationPreferences.moveFolder(
                from: folder.relativePath,
                to: movedPath
            )
            attachmentPresentationRevision += 1
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
            statusToast = .saved(String(localized: "Folder Deleted"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func deleteMergedInboxFolders() async -> Bool {
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        let targets = mergedInboxFolders
        guard !targets.isEmpty else { return false }
        do {
            try await fileStore.trashMergedInboxFolders(
                relativePaths: targets.map(\.relativePath)
            )
            if let selectedDocument,
               targets.contains(where: {
                   selectedDocument.relativePath.hasPrefix($0.relativePath + "/")
               }) {
                self.selectedDocument = nil
            }
            statusToast = .saved(String(localized: "Folder Deleted"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return true
        } catch {
            statusToast = .error(error.localizedDescription)
            await refreshInbox()
            return false
        }
    }

    func move(_ file: RecentMarkdownFile, to folder: LibraryFolderNode) {
        Task {
            _ = await moveNote(
                relativePath: file.relativePath,
                toFolder: folder.relativePath
            )
        }
    }

    @discardableResult
    func moveNote(
        relativePath: String,
        toFolder targetFolder: String?
    ) async -> MarkdownDocument? {
        guard relativePath != "Inbox.md" else {
            statusToast = .error(String(localized: "Inbox cannot be moved between folders."))
            return nil
        }
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return nil
        }
        do {
            let moved = try await fileStore.moveMarkdownDocument(
                relativePath: relativePath,
                toFolder: targetFolder
            )
            let document = try await fileStore.loadMarkdownDocument(
                relativePath: moved.relativePath
            )
            attachmentPresentationPreferences.moveNote(
                from: relativePath,
                to: moved.relativePath
            )
            attachmentPresentationRevision += 1
            if selectedDocument?.relativePath == relativePath {
                selectedDocument = document
            }
            statusToast = .saved(String(localized: "Note Moved"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return document
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    @discardableResult
    func move(_ files: [RecentMarkdownFile], to folder: LibraryFolderNode) async -> Bool {
        await moveNotes(files, toFolder: folder.relativePath)
    }

    @discardableResult
    func moveNotes(
        _ files: [RecentMarkdownFile],
        toFolder targetFolder: String?
    ) async -> Bool {
        guard !files.isEmpty else { return false }
        guard files.allSatisfy(canReorganize) else {
            statusToast = .error(String(localized: "Inbox cannot be moved between folders."))
            return false
        }
        guard syncStatus != .pending else {
            statusToast = .error(String(localized: "Finish pending captures before changing folders."))
            return false
        }
        do {
            let originalPaths = Array(Set(files.map(\.relativePath))).sorted()
            let moved = try await fileStore.moveMarkdownDocuments(
                relativePaths: originalPaths,
                toFolder: targetFolder
            )
            for (oldPath, movedFile) in zip(originalPaths, moved) {
                attachmentPresentationPreferences.moveNote(
                    from: oldPath,
                    to: movedFile.relativePath
                )
            }
            attachmentPresentationRevision += 1
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
                attachmentPresentationPreferences.removeNote(item.originalRelativePath)
                attachmentPresentationRevision += 1
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
            items.forEach {
                attachmentPresentationPreferences.removeNote($0.originalRelativePath)
            }
            attachmentPresentationRevision += 1
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

    func attachmentSearchDocuments(in markdown: String) async throws -> [AttachmentSearchDocument] {
        try await fileStore.attachmentSearchDocuments(in: markdown)
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
                if announce {
                    updated = try await fileStore.finalizeNewMarkdownDocument(
                        relativePath: document.relativePath,
                        markdown: markdown,
                        expectedMarkdown: expectedMarkdown
                    )
                } else {
                    let autosaved = try await fileStore.saveMarkdownDocument(
                        relativePath: document.relativePath,
                        markdown: markdown,
                        expectedMarkdown: expectedMarkdown
                    )
                    updated = MarkdownDocument(
                        id: autosaved.id,
                        title: autosaved.title,
                        relativePath: autosaved.relativePath,
                        markdown: autosaved.markdown,
                        modifiedAt: autosaved.modifiedAt,
                        isNew: true
                    )
                }
            } else {
                updated = try await fileStore.saveMarkdownDocument(
                    relativePath: document.relativePath,
                    markdown: markdown,
                    expectedMarkdown: expectedMarkdown
                )
            }
            if selectedDocument?.relativePath == document.relativePath,
               updated.relativePath == document.relativePath {
                selectedDocument = updated
            }
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
            let attachment = try await photoLibraryAttachment(from: item)
            return await attachMediaAttachment(
                attachment,
                to: document,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown
            )
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func attachCameraPhoto(
        _ media: CapturedCameraMedia,
        to document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        guard attachmentPreparationCount == 0 else { return nil }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        let attachment: CaptureAttachment
        do {
            switch media {
            case .photo(let data):
                attachment = try CaptureAttachment.validatedImage(data: data)
            case .video(let video):
                attachment = video
            }
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
        return await attachMediaAttachment(
            attachment,
            to: document,
            markdown: markdown,
            expectedMarkdown: expectedMarkdown
        )
    }

    private func attachMediaAttachment(
        _ attachment: CaptureAttachment,
        to document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        do {
            let updated = try await fileStore.attachToMarkdownDocument(
                relativePath: document.relativePath,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown,
                attachment: attachment
            )
            selectedDocument = updated
            statusToast = .saved(attachmentAttachedMessage(attachment))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
            return updated
        } catch {
            statusToast = .error(error.localizedDescription)
            return nil
        }
    }

    func attachDrawing(
        _ data: Data,
        to document: MarkdownDocument,
        markdown: String,
        expectedMarkdown: String
    ) async -> MarkdownDocument? {
        guard attachmentPreparationCount == 0 else { return nil }
        attachmentPreparationCount += 1
        defer { attachmentPreparationCount -= 1 }
        do {
            let attachment = try CaptureAttachment.validatedImage(
                data: data,
                suggestedExtension: "png"
            )
            let updated = try await fileStore.attachToMarkdownDocument(
                relativePath: document.relativePath,
                markdown: markdown,
                expectedMarkdown: expectedMarkdown,
                attachment: attachment
            )
            selectedDocument = updated
            statusToast = .saved(String(localized: "Drawing attached"))
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
        do {
            let attachment = try importedFileAttachment(from: url)
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

    private func importedFileAttachment(from url: URL) throws -> CaptureAttachment {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw CaptureAttachmentError.empty }
        let isVideo = UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true
        let maximumBytes = isVideo
            ? CaptureAttachmentPolicy.maximumVideoBytes
            : CaptureAttachmentPolicy.maximumFileBytes
        if let byteCount = values.fileSize,
           byteCount > maximumBytes {
            throw CaptureAttachmentError.tooLarge(maximumBytes: maximumBytes)
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        if isVideo {
            return try CaptureAttachment.validatedVideo(
                data: data,
                suggestedName: url.lastPathComponent
            )
        }
        return try CaptureAttachment.validatedFile(data: data, suggestedName: url.lastPathComponent)
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

    func prepareAttachmentPreview(relativePath: String) async -> PreparedAttachmentPreview? {
        do {
            return try await fileStore.prepareAttachmentPreview(
                relativePath: relativePath
            )
        } catch {
            statusToast = .error(String(localized: "Could not open attachment"))
            return nil
        }
    }

    func prepareAttachmentPreview(for attachment: LibraryAttachment) async -> PreparedAttachmentPreview? {
        await prepareAttachmentPreview(relativePath: attachment.relativePath)
    }

    func commitEditedAttachmentPreview(
        _ preview: PreparedAttachmentPreview,
        editedURL: URL
    ) async {
        do {
            let changed = try await fileStore.commitEditedAttachmentPreview(
                preview,
                editedURL: editedURL
            )
            guard changed else { return }
            statusToast = .saved(String(localized: "PDF markup saved"))
            await refreshInbox()
            await refreshActiveSearchIfNeeded()
        } catch {
            statusToast = .error(error.localizedDescription)
        }
    }

    func attachmentThumbnailData(for attachment: LibraryAttachment) async -> Data? {
        guard attachment.kind == .image else { return nil }
        return try? await fileStore.loadAttachmentThumbnailData(
            relativePath: attachment.relativePath
        )
    }

    func openAttachmentOwner(_ owner: LibraryAttachment.Owner) {
        switch owner.destination {
        case .file(let relativePath):
            guard let file = libraryFiles.first(where: {
                $0.relativePath == relativePath
            }) else {
                statusToast = .error(String(localized: "Linked note not found"))
                return
            }
            openFile(file)
        case .memo(let id):
            guard let memo = inboxItems.first(where: { $0.id == id }) else {
                statusToast = .error(String(localized: "Linked note not found"))
                return
            }
            selectedMemo = memo
        }
    }

    func refreshInbox() async {
        guard folderAccess.currentRoot != nil else { return }
        do {
            await libraryRefreshBarrier()
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
        refreshCaptureFolderPreferences()
        trashedFiles = snapshot.trashedFiles
        attachments = snapshot.attachments
        smartFolders = snapshot.smartFolders
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
        libraryRevision += 1
    }

    private func applyTrashedProjection(_ items: [TrashedMarkdownFile]) {
        let paths = Set(items.map(\.originalRelativePath))
        guard !paths.isEmpty else { return }
        let directoryPaths = allFolders.map(\.relativePath)

        libraryFiles.removeAll { paths.contains($0.relativePath) }
        recentFiles.removeAll { paths.contains($0.relativePath) }
        folders = LibraryFolderNode.makeTree(
            directoryPaths: directoryPaths,
            files: libraryFiles
        )
        trashedFiles.removeAll { item in
            items.contains { $0.id == item.id }
        }
        trashedFiles.append(contentsOf: items)
        trashedFiles.sort { $0.trashedAt > $1.trashedAt }
        librarySummary.allNotesCount = libraryFiles.count
        librarySummary.recentlyDeletedCount = trashedFiles.count
        tagSummaries = Self.tagSummaries(from: inboxItems, files: libraryFiles)
        conflictWarnings.removeAll { paths.contains($0) }
        searchResults.removeAll { result in
            guard case .file(let file) = result.destination else { return false }
            return paths.contains(file.relativePath)
        }
        libraryRevision += 1
    }

    private func applyCreatedProjection(_ file: RecentMarkdownFile) {
        libraryFiles.removeAll { $0.relativePath == file.relativePath }
        libraryFiles.append(file)
        recentFiles.removeAll { $0.relativePath == file.relativePath }
        recentFiles.append(file)
        recentFiles.sort { $0.modifiedAt > $1.modifiedAt }
        folders = LibraryFolderNode.makeTree(
            directoryPaths: allFolders.map(\.relativePath),
            files: libraryFiles
        )
        librarySummary.allNotesCount = libraryFiles.count
        tagSummaries = Self.tagSummaries(from: inboxItems, files: libraryFiles)
        libraryRevision += 1
    }

    private func beginLibraryConfiguration() -> UUID {
        let configurationID = UUID()
        libraryConfigurationID = configurationID
        folderStatus = .loading
        isInitialLibraryLoading = true
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
        // Directory creation and iCloud-backed existence checks can block.
        // Perform them on the file-store actor so the launch spinner and
        // navigation shell remain responsive on the main actor.
        try await fileStore.configureAndInitialize(root: root)
        guard libraryConfigurationID == configurationID else { return false }
        defaultCaptureFolderPath = captureFolderPreferences.resolveDefaultFolder(
            libraryRoot: root
        )
        if !draft.canSend, !captureTargetWasExplicitlySelected {
            draft.target = .folder(defaultCaptureFolderPath)
        }
        let nextQueue = PendingWriteQueue(root: root)
        let queueLoadResult = try await nextQueue.load()
        switch queueLoadResult {
        case .ready:
            queueRecoveryWarning = try await nextQueue.preservedFailureFilenames()
                .first
                .map { Self.queueRecoveryWarning(filename: $0) }
        case .quarantined(let filename):
            queueRecoveryWarning = Self.queueRecoveryWarning(filename: filename)
        }
        guard libraryConfigurationID == configurationID else { return false }
        var replayFailed = false
        do {
            let replayResult = try await nextQueue.replay { [fileStore, weak self] item in
                let createdFile = try await fileStore.performPendingWrite(item)
                self?.applyCreatedProjection(createdFile)
                self?.recordSuccessfulPendingWrite(item)
            }
            recordPreservedPendingWrites(replayResult)
        } catch {
            replayFailed = true
        }
        guard libraryConfigurationID == configurationID else { return false }
        queue = nextQueue
        // A full iCloud-backed Markdown inventory can take seconds on a cold
        // launch. Folder access and queue recovery are already safe here, so
        // reveal the interactive shell before scanning and parsing every note.
        folderStatus = .ready(root)
        announceRecoveredDraftIfPossible()
        presentPendingCaptureIfPossible()
        await initialLibraryLoadBarrier()
        guard libraryConfigurationID == configurationID else { return false }
        let snapshot = try await fileStore.loadLibrarySnapshot()
        let pendingCount = await nextQueue.pendingCount()
        guard libraryConfigurationID == configurationID else { return false }
        apply(snapshot, pendingCount: pendingCount)
        isInitialLibraryLoading = false
        if sceneRefreshRequested {
            sceneRefreshRequested = false
            Task { await refreshAfterSceneActivation() }
        }
        if replayFailed {
            syncStatus = .pending
            statusToast = .pending(String(localized: "Pending captures need attention"))
        } else if queueRecoveryWarning != nil {
            statusToast = .pending(String(localized: "Damaged pending captures were preserved"))
        }
        return true
    }

    private static func queueRecoveryWarning(filename: String) -> String {
        String(
            format: String(localized: "pending.queue_quarantined.format"),
            locale: .current,
            filename
        )
    }

    private func recordPreservedPendingWrites(_ result: PendingWriteReplayResult) {
        guard let filename = result.preservedFailureFilenames.first else { return }
        queueRecoveryWarning = Self.queueRecoveryWarning(filename: filename)
    }

    private func announceRecoveredDraftIfPossible() {
        guard recoveredDraftNeedsAnnouncement,
              case .ready = folderStatus else { return }
        recoveredDraftNeedsAnnouncement = false
        statusToast = .pending(String(localized: "Unsaved quick note restored"))
    }

    private func appendDraft(_ draft: CaptureDraft) async throws -> RecentMarkdownFile {
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
            let createdFile = try await fileStore.performPendingWrite(pending)
            recordSuccessfulCaptureFolder(for: draft.target)
            do {
                try await queue.remove(id: pending.id)
            } catch {
                // The note is already durable and can be shown immediately.
                // Keep the queued item as an idempotent cleanup retry instead
                // of reporting the completed write as a failed capture.
                syncStatus = .pending
            }
            return createdFile
        } catch {
            throw DraftSaveError.queuedForReplay(error.localizedDescription)
        }
    }

    @discardableResult
    private func finishSubmission(_ submittedDraft: CaptureDraft, continueCapturing: Bool) -> Bool {
        guard draft == submittedDraft else { return false }
        captureTargetWasExplicitlySelected = false
        draft = CaptureDraft(target: .folder(defaultCaptureFolderPath))
        captureRoute = .text
        if !continueCapturing {
            withAnimation(
                HomeChromeMotion.captureDismissAnimation(
                    reduceMotion: UIAccessibility.isReduceMotionEnabled
                )
            ) {
                isCapturePresented = false
            }
        }
        return true
    }

    private func refreshCaptureFolderPreferences() {
        let resolvedDefault = captureFolderPreferences.resolveDefaultFolder(in: folders)
        defaultCaptureFolderPath = resolvedDefault
        recentCaptureFolders = captureFolderPreferences.recentFolders(
            in: folders,
            libraryRoot: folderAccess.currentRoot
        )

        let availablePaths = Set(allFolders.map(\.relativePath))
        if case .folder(let path?) = draft.target,
           !availablePaths.contains(path) {
            captureTargetWasExplicitlySelected = false
            draft.target = .folder(resolvedDefault)
        } else if !draft.canSend, !captureTargetWasExplicitlySelected {
            draft.target = .folder(resolvedDefault)
        }
    }

    private func recordSuccessfulCaptureFolder(for target: CaptureTarget) {
        captureFolderPreferences.recordSuccessfulSave(to: target.relativeFolderPath)
        recentCaptureFolders = captureFolderPreferences.recentFolders(
            in: folders,
            libraryRoot: folderAccess.currentRoot
        )
    }

    private func recordSuccessfulPendingWrite(_ pending: PendingWrite) {
        let rawParent = (pending.targetRelativePath as NSString).deletingLastPathComponent
        let parent = rawParent == "." || rawParent.isEmpty ? nil : rawParent
        captureFolderPreferences.recordSuccessfulSave(to: parent, at: pending.createdAt)
        recentCaptureFolders = captureFolderPreferences.recentFolders(
            in: folders,
            libraryRoot: folderAccess.currentRoot
        )
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
    case queuedForReplay(String)

    var errorDescription: String? {
        switch self {
        case .pendingQueueRejected(let reason):
            return String(
                format: String(localized: "draft.kept_open.format"),
                locale: .current,
                reason
            )
        case .queuedForReplay(let reason):
            return "\(String(localized: "Saved to pending queue")): \(reason)"
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
