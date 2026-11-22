import Foundation
import Observation
import WidgetKit

/// Fine-grained `@Observable` state domains owned by `AppModel`.
/// Views observing a specific domain only re-render when that domain's properties mutate.
@MainActor
@Observable
final class LibraryDomainState {
    var folderStatus: FolderStatus = .loading
    var libraryFiles: [RecentMarkdownFile] = []
    var recentFiles: [RecentMarkdownFile] = []
    var folders: [LibraryFolderNode] = []
    var trashedFiles: [TrashedMarkdownFile] = []
    var attachments: [LibraryAttachment] = []
    var smartFolders: [SmartFolderDefinition] = []
    var librarySummary = LibrarySummary()
    var tagSummaries: [TagSummary] = []
    var libraryRevision = 0
    var isInitialLibraryLoading = true
    var hasMoreLibraryFiles = false
    var currentLibraryID = ""
}

@MainActor
@Observable
final class CaptureDomainState {
    var captureRoute: CaptureRoute = .text
    var isCapturePresented = false
    var isSendingDraft = false
    var audioCapturePhase: AudioCapturePhase = .idle
    var attachmentPreparationCount = 0
    var draftRecoveryIssue: String?
    var captureAttachmentIssue: String?
    var captureSubmissionIssue: String?
    var defaultCaptureFolderPath: String?
    var recentCaptureFolders: [LibraryFolderNode] = []
}

@MainActor
@Observable
final class SearchDomainState {
    var query = ""
    var searchResults: [MarkdownSearchResult] = []
    var isSearching = false
    var completedSearchQuery = ""
    var completedSearchScope = MarkdownSearchScope.all
    var completedSearchFilter = MarkdownSearchFilter()
    var isLibrarySearchRequested = false
}

@MainActor
@Observable
final class ReaderDomainState {
    var selectedDocument: MarkdownDocument?
    var selectedMemo: MemoBlock?
    var noteOpenMode: NoteOpenMode = .read
    var isReaderExpanded = false
    var attachmentPresentationRevision = 0
}

@MainActor
@Observable
final class SyncDomainState {
    var syncStatus: SyncStatus = .idle
    var conflictWarnings: [String] = []
    var statusToast: StatusToast?
    var activeTagMutation: String?
}

/// Shared App Group summary written by the main app and read by `QuickCaptureWidget`
/// so widgets can surface the latest pinned/recent note and pending sync count.
struct WidgetSharedSnapshot: Codable, Equatable {
    static let appGroupIdentifier = "group.app.mudsnote.companion"
    static let defaultsKey = "mudsnote.widget.sharedSnapshot.v1"

    var updatedAt: Date
    var totalNoteCount: Int
    var pinnedTitles: [String]
    var recentTitles: [String]
    var pendingSyncCount: Int

    static func save(_ snapshot: WidgetSharedSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        if let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            sharedDefaults.set(data, forKey: defaultsKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func load() -> WidgetSharedSnapshot? {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = sharedDefaults.data(forKey: defaultsKey) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSharedSnapshot.self, from: data)
    }
}
