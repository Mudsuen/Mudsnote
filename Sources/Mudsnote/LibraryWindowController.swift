import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

@MainActor
final class LibraryWindowController: NSWindowController,
    NSWindowDelegate,
    NSSplitViewDelegate,
    NSToolbarDelegate,
    NSToolbarItemValidation,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSCollectionViewDataSource,
    NSCollectionViewDelegateFlowLayout,
    NSOutlineViewDataSource,
    NSOutlineViewDelegate,
    NSSearchFieldDelegate,
    NSTextFieldDelegate,
    NSTextViewDelegate,
    MarkdownTextViewCommands,
    WindowOpacityAdjusting
{
    let noteStore: NoteStore

    let sourceOutlineView = LibrarySourceOutlineView()

    let tableView = LibraryNoteTableView()

    let galleryCollectionView = LibraryGalleryCollectionView()

    let searchField = NSSearchField(string: "")

    let searchScopeControl = NSSegmentedControl(
        labels: ["当前", "所有"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    let noteListTitleLabel = NSTextField(labelWithString: "")

    let noteListCountLabel = NSTextField(labelWithString: "")

    let noteListEmptyLabel = NSTextField(labelWithString: "")

    let galleryEmptyLabel = NSTextField(labelWithString: "")

    let titleField = NSTextField(string: "")

    let editorTextView = MarkdownTextView(frame: .zero)

    let noteLinksView = NoteLinksView(frame: .zero)

    let attachmentQuickLookController = AttachmentQuickLookController()

    let createdDateLabel = NSTextField(labelWithString: "")

    let statusLabel = NSTextField(labelWithString: "")

    let wordCountLabel = NSTextField(labelWithString: "")

    var attachmentManagerWindowController: LibraryAttachmentManagerWindowController?

    var knowledgeGraphWindowController: KnowledgeGraphWindowController?

    static let toolbarIdentifier = NSToolbar.Identifier("mudsnote.library.toolbar")

    static let toggleSidebarToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.toggle-sidebar")

    static let navigationBackToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.navigation-back")

    static let navigationForwardToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.navigation-forward")

    static let sourceTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.source-separator")

    static let noteTrackingSeparatorToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-separator")

    static let noteListTitleToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.note-list-title")

    static let documentTabsToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.document-tabs")

    static let newNoteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.new-note")

    static let openSeparateToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.open-separate")

    static let moveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.move")

    static let saveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.save")

    static let deleteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.delete")

    static let restoreToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.restore")

    static let editorToolsToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.editor-tools")

    static let formatToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.format")

    static let checklistToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.checklist")

    static let linkToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.link")

    static let sidebarPresentationToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.sidebar-presentation")

    static let sourceModeToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.source-mode")

    static let revealToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.reveal")

    static let exportToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.export")

    static let moreToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.more")

    static let searchToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.search")

    enum EditorStatusKind {
        case normal
        case failure
    }

    let onOpenInSeparateWindow: (URL) -> Void

    let onSave: (URL) -> Void

    let onClose: () -> Void

    let noteLoader: @Sendable (URL) throws -> LoadedLibraryNote

    let fileModificationDateLoader: @Sendable (URL) -> Date?

    let thumbnailDecoder: @Sendable (URL) -> CGImage?

    let backgroundAutosaveWillPersist: @Sendable () -> Void

    let backgroundSourceCountWillLoad: @Sendable () -> Void

    let backgroundDeletionWillPersist: @Sendable () -> Void

    let usesCanonicalWindowSize: Bool

    let prefersExternalScreen: Bool

    var notes: [NoteSearchResult] = []

    var listRows: [LibraryNoteListRow] = [] {
        didSet { rebuildThumbnailRowIndex() }
    }

    var gallerySections: [LibraryGallerySection] = [] {
        didSet { rebuildGalleryIndexes() }
    }

    var galleryIndexPathsByNotePath: [String: IndexPath] = [:]

    var visualQASelectedURL: URL?

    var noteListSortOrder: LibraryNoteSortOrder = .dateEdited

    var groupsNoteListByDate = true

    var noteListViewMode: LibraryNoteViewMode = .list

    var sourceCountSnapshot: [NoteSearchResult] = [] {
        didSet { noteRelationsCache.removeAll() }
    }

    var trashedNotesSnapshot: [NoteSearchResult] = []

    var externallyOpenedDocumentsByPath: [String: NoteSearchResult] = [:]

    var selectedURL: URL?

    var selectedSourceContents: String?

    var selectedTags: [String] = []

    var isDirty = false

    var autosaveTask: Task<Void, Never>?

    let autosavePersistenceQueue = DispatchQueue(
        label: "local.codex.mudsnote.library-autosave",
        qos: .utility
    )

    let libraryMutationQueue = DispatchQueue(
        label: "local.codex.mudsnote.library-mutations",
        qos: .userInitiated
    )

    let launchNoteCacheQueue = DispatchQueue(
        label: "local.codex.mudsnote.library-launch-note-cache",
        qos: .utility
    )

    let backgroundAutosaveResultStore = LibraryBackgroundSaveResultStore()

    var backgroundAutosaveGeneration = 0

    var backgroundAutosaveIsActive = false

    var backgroundAutosaveNeedsLatest = false

    var backgroundAutosaveActiveEditorRevision: Int?

    var backgroundAutosaveActivePreviousURL: URL?

    var deferredFileSystemChangesDuringAutosave = Set<LibraryFileSystemChange>()

    var noteLoadTask: Task<Void, Never>?

    var noteLoadGeneration = 0

    var noteLoadFallbackURL: URL?

    var persistedLaunchFallbackURL: URL?

    var notePrefetchTask: Task<Void, Never>?

    var searchReloadWorkItem: DispatchWorkItem?

    var searchResultsTask: Task<Void, Never>?

    var editorMetricsRefreshTask: Task<Void, Never>?

    var editorSearchHighlightRefreshTask: Task<Void, Never>?

    var noteLinksRefreshTask: Task<Void, Never>?

    var noteLinksRefreshGeneration = 0

    var noteRelationsCache: [URL: (body: String, relations: KnowledgeRelations)] = [:]

    var knowledgeSynthesisTask: Task<Void, Never>?

    var knowledgeSynthesisGeneration = 0

    var knowledgeBackStack: [URL] = []

    var knowledgeForwardStack: [URL] = []

    var sidebarPresentationButtons: [NSButton] = []

    var sidebarHeaderView: NSView!

    let sidebarListHeaderContent = NSStackView()

    let sidebarAllNotesButton = NSButton()

    var searchResultsGeneration = 0

    var activeSearchSession: NoteSearchSession?

    var sourceSnapshotValidationTask: Task<Void, Never>?

    var sourceSnapshotValidationGeneration = 0

    var sourceCountRefreshTask: Task<Void, Never>?

    var sourceCountRefreshGeneration = 0

    var hasLoadedSourceCounts = false

    var pendingDeletionPaths = Set<String>()

    var pendingDeletionBatchCount = 0

    var pendingDeletionWaiters: [CheckedContinuation<Void, Never>] = []

    var sourceInboxDirectory: URL?

    var noteListToolbarTitleLeadingConstraint: NSLayoutConstraint?

    var hasPendingSearchReload = false

    var isSearchResultReloading = false

    var isLoadingInitialNote = false

    var suppressEditorChanges = false

    var hasEditorSearchHighlights = false

    var editorSearchHighlightRemovalScanCount = 0

    var editorContentRevision = 0

    var isEditorShowingMarkdownSource = false

    var suppressSelectionChanges = false

    var suppressGallerySelectionChanges = false

    var isCreatingNewNote = false

    var hasCenteredWindow = false

    var hasRequestedWindowPresentation = false

    var hasHydratedInitialNoteList = false

    var hasReleasedDeferredLaunchWork = false

    var selectedScope: LibraryScope = .all

    var sidebarPresentation: LibrarySidebarPresentation = .tree

    var lastTreeScope: LibraryScope = .all

    var lastListScope: LibraryScope = .all

    var selectedTreeNoteURL: URL?

    var documentTabs = [LibraryDocumentTab()]

    var activeDocumentTabID: UUID?

    let documentTabsStack = NSStackView()

    var documentTabsWidthConstraint: NSLayoutConstraint?

    var documentTabBarSignature = ""

    var isActivatingDocumentTab = false

    var activeDocumentTab: LibraryDocumentTab {
        documentTabs.first { $0.id == activeDocumentTabID } ?? documentTabs[0]
    }

    var sourceOutlineRootItems: [LibrarySourceOutlineItem] = []

    var sourceTreeNeedsScopeRebuild = false

    var sourceOutlineItemsByIdentifier: [String: LibrarySourceOutlineItem] = [:]

    var sourceOutlineItemsByScopeIdentifier: [String: LibrarySourceOutlineItem] = [:]

    var isSynchronizingSourceOutlineSelection = false

    var isRestoringSourceOutlineExpansion = false

    var sourceFolderRows: [LibraryFolderRow] = []

    var sourceFolderTreeRows: [LibraryFolderRow] = []

    var sourceTagNames: [String] = []

    var collapsedFolderPaths = Set<String>()

    var expandedFolderPaths = Set<String>()

    let loadedNoteCache = LoadedLibraryNoteCache(countLimit: 32)

    let thumbnailImageCache: NSCache<NSString, LibraryThumbnailCacheEntry> = {
        let cache = NSCache<NSString, LibraryThumbnailCacheEntry>()
        cache.countLimit = 96
        cache.totalCostLimit = 96 * 88 * 88 * 4
        return cache
    }()

    var thumbnailImageLoadTasks: [String: Task<Void, Never>] = [:]

    var thumbnailRowsByPath: [String: IndexSet] = [:]

    var thumbnailItemsByPath: [String: Set<IndexPath>] = [:]

    var pendingThumbnailReloadPaths = Set<String>()

    var thumbnailReloadScheduled = false

    var thumbnailImageDecodeCountForLibrary = 0

    var thumbnailReloadBatchCountForLibrary = 0

    var sourceFoldersLoaded = false

    var sourceFoldersLoading = false

    var sourceFolderLoadGeneration = 0

    var tagMutationInProgress = false

    var sourceTagsLoaded = false

    var sourceTagsLoading = false

    var sourceTagLoadGeneration = 0

    var fullLibrarySnapshotReloadScheduled = false

    var isFullLibrarySnapshotLoading = false

    var fullLibrarySnapshotReloadGeneration = 0

    var fileSystemMonitor: LibraryFileSystemMonitor?

    var internallyMutatedPaths: [String: Date] = [:]

    var internallyMutatedDirectoryPaths: [String: Date] = [:]

    var sourceFoldersSectionCollapsed = false

    var sourceTagsSectionCollapsed = false

    var inlineFolderEditOperation: InlineFolderEditOperation?

    var inlineFolderEditField: NSTextField?

    var isCommittingInlineFolderEdit = false

    var inlineFolderEditHasReceivedFocus = false

    var linkEditorSheetController: LinkEditorSheetController?

    let editorSuggestionController = SuggestionPopoverController()

    var editorSlashSuggestion: (replacementRange: NSRange, commands: [SlashCommand])?

    var editorTagSuggestion: (replacementRange: NSRange, items: [String])?

    var editorNoteSuggestion: (replacementRange: NSRange, items: [NoteLinkItem])?

    var editorNoteSuggestionQuery: String?

    var editorNoteSuggestions: [NoteLinkItem] = []

    var editorNoteSuggestionTask: Task<Void, Never>?

    var editorSlashSuggestionLastInput: (caret: Int, prefixStart: Int, prefix: String)?

    var slashCommandInputSourceSession: any SlashCommandInputSourceSessioning = SlashCommandInputSourceSession()

    var editorSlashSuggestionInspectionLengthForLibrary = 0

    var isApplyingStoredSplitLayout = false

    var splitLayoutPersistenceWorkItem: DispatchWorkItem?

    var windowFramePersistenceWorkItem: DispatchWorkItem?

    weak var librarySplitView: NSSplitView?

    var librarySplitViewController: NSSplitViewController?

    weak var sourceSplitViewItem: NSSplitViewItem?

    weak var noteListSplitViewItem: NSSplitViewItem?

    weak var sourceListView: NSView?

    weak var sidebarTreeView: NSView?

    weak var sidebarNoteListView: NSView?

    weak var editorStackView: NSStackView?

    var pinnedRelationsWidthConstraint: NSLayoutConstraint?

    weak var galleryScrollView: NSScrollView?

    static let sourceCountSnapshotLimit = Int.max

    nonisolated static let noteListResultLimit = Int.max

    let theme = MarkdownEditorTheme(
        textColor: panelPrimaryTextColor(),
        mutedTextColor: panelSecondaryTextColor(),
        accentColor: panelAccentColor(),
        bodyFont: .systemFont(ofSize: LibraryNotesLayout.editorBodyFontSize, weight: .regular),
        boldFont: .systemFont(ofSize: LibraryNotesLayout.editorBodyFontSize, weight: .bold),
        italicFont: NSFontManager.shared.convert(
            .systemFont(ofSize: LibraryNotesLayout.editorBodyFontSize, weight: .regular),
            toHaveTrait: .italicFontMask
        ),
        codeFont: .monospacedSystemFont(ofSize: LibraryNotesLayout.editorCodeFontSize, weight: .medium),
        lineSpacing: LibraryNotesLayout.editorLineSpacing,
        paragraphSpacing: LibraryNotesLayout.editorParagraphSpacing
    )

    init(
        noteStore: NoteStore,
        defersInitialNoteHydration: Bool = false,
        usesCanonicalWindowSize: Bool = false,
        prefersExternalScreen: Bool = false,
        noteLoader: (@Sendable (URL) throws -> (title: String, body: String, tags: [String]))? = nil,
        fileModificationDateLoader: (@Sendable (URL) -> Date?)? = nil,
        thumbnailDecoder: (@Sendable (URL) -> CGImage?)? = nil,
        backgroundAutosaveWillPersist: @escaping @Sendable () -> Void = {},
        backgroundSourceCountWillLoad: @escaping @Sendable () -> Void = {},
        backgroundDeletionWillPersist: @escaping @Sendable () -> Void = {},
        onOpenInSeparateWindow: @escaping (URL) -> Void,
        onSave: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        let migratedLayout = noteStore.migrateLibraryLayoutScaleIfNeeded(
            to: LibraryNotesLayout.storedLayoutScaleVersion,
            replacingDefaultPaneWidths: (source: 205, note: 200)
        )
        if migratedLayout {
            noteStore.libraryWindowFrame = LibraryNotesLayout.migratedDefaultWindowFrame(noteStore.libraryWindowFrame)
        }
        if let noteLoader {
            self.noteLoader = { url in
                let loaded = try noteLoader(url)
                return LoadedNoteDocument(
                    title: loaded.title,
                    body: loaded.body,
                    tags: loaded.tags,
                    sourceContents: try String(contentsOf: url, encoding: .utf8)
                )
            }
        } else {
            self.noteLoader = { try noteStore.loadNoteDocument(at: $0) }
        }
        self.fileModificationDateLoader = fileModificationDateLoader ?? Self.fileModificationDate(at:)
        self.thumbnailDecoder = thumbnailDecoder ?? Self.makeListThumbnailCGImage(at:)
        self.backgroundAutosaveWillPersist = backgroundAutosaveWillPersist
        self.backgroundSourceCountWillLoad = backgroundSourceCountWillLoad
        self.backgroundDeletionWillPersist = backgroundDeletionWillPersist
        self.usesCanonicalWindowSize = usesCanonicalWindowSize
        self.prefersExternalScreen = prefersExternalScreen
        self.onOpenInSeparateWindow = onOpenInSeparateWindow
        self.onSave = onSave
        self.onClose = onClose
        self.noteListSortOrder = LibraryNoteSortOrder(rawValue: noteStore.libraryNoteSortOrderRawValue) ?? .dateEdited
        self.groupsNoteListByDate = noteStore.libraryGroupsNotesByDate
        self.noteListViewMode = LibraryNoteViewMode(rawValue: noteStore.libraryNoteViewModeRawValue) ?? .list
        self.sidebarPresentation = LibrarySidebarPresentation(
            rawValue: noteStore.librarySidebarPresentationRawValue
        ) ?? .tree
        self.collapsedFolderPaths = noteStore.libraryCollapsedFolderPaths
        self.expandedFolderPaths = noteStore.libraryExpandedFolderPaths
        self.sourceFoldersSectionCollapsed = noteStore.libraryFoldersSectionCollapsed
        self.sourceTagsSectionCollapsed = noteStore.libraryTagsSectionCollapsed

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: LibraryNotesLayout.initialWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(MudsnoteBrand.appName) 笔记"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert(.fullSizeContentView)
        window.minSize = LibraryNotesLayout.minimumWindowSize
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        super.init(window: window)
        LibraryNoteRowView.selectionFillColor = selectedThemeColor.noteSelectionColor
        window.delegate = self
        buildUI()
        configureToolbar()
        if defersInitialNoteHydration {
            let preferredRootPaths = noteStore.preferredDirectories.map {
                $0.standardizedFileURL.path
            }
            let cachedPresentation = noteStore.cachedLibraryPresentationSnapshot(
                limit: Self.sourceCountSnapshotLimit
            ).filter { note in
                let notePath = note.url.standardizedFileURL.path
                return preferredRootPaths.contains {
                    notePath == $0 || notePath.hasPrefix($0 + "/")
                }
            }
            applyCachedSourceTags(from: cachedPresentation)
            reloadNotes(
                loadFirstIfNeeded: false,
                allNotesSnapshot: cachedPresentation.isEmpty
                    ? recentShellNoteResults(limit: Self.noteListResultLimit)
                    : cachedPresentation,
                refreshCounts: true
            )
        } else {
            hasHydratedInitialNoteList = true
            trashedNotesSnapshot = noteStore.listTrashedNotes(limit: Self.sourceCountSnapshotLimit)
            reloadNotes(
                loadFirstIfNeeded: true,
                allNotesSnapshot: allNoteResults(limit: Self.sourceCountSnapshotLimit)
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()

    let noteListTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    let noteListWeekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    let noteListShortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy/M/d"
        return formatter
    }()
}
