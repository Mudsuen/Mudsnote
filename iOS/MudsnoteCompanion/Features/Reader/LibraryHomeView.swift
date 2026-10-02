import SwiftUI
import ImageIO
import UIKit

struct NotesListSearchTaskID: Hashable {
    var query: String
    var libraryRevision: Int
}

struct NoteListPageWindow: Equatable {
    static let pageSize = 300
    private(set) var visibleCount = pageSize

    mutating func reset() {
        visibleCount = Self.pageSize
    }

    mutating func revealNext(totalCount: Int) {
        visibleCount = min(totalCount, visibleCount + Self.pageSize)
    }

    func visibleItems<Element>(from items: [Element]) -> [Element] {
        Array(items.prefix(visibleCount))
    }

    func hasMore(totalCount: Int) -> Bool {
        visibleCount < totalCount
    }
}

enum HomeTimelineEntry: Identifiable {
    case file(RecentMarkdownFile)
    case memo(MemoBlock)

    private static let memoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    var id: String {
        switch self {
        case .file(let file): "file:\(file.id)"
        case .memo(let memo): "memo:\(memo.id)"
        }
    }

    var date: Date {
        switch self {
        case .file(let file): file.modifiedAt
        case .memo(let memo):
            Self.memoDateFormatter.date(from: memo.dateText) ?? .distantPast
        }
    }

    var title: String {
        switch self {
        case .file(let file):
            return file.title
        case .memo(let memo):
            let firstLine = memo.body
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty }
            return firstLine?.trimmingCharacters(in: CharacterSet(charactersIn: "#>*+- "))
                ?? String(localized: "Untitled memo")
        }
    }

    var fileNeedingContent: RecentMarkdownFile? {
        guard case .file(let file) = self, !file.isContentLoaded else {
            return nil
        }
        return file
    }

    var isPinned: Bool {
        guard case .file(let file) = self else { return false }
        return file.isPinned
    }
}

struct HomeTimelineSection: Identifiable {
    var id: String
    var title: String?
    var entries: [HomeTimelineEntry]
}

struct HomeTimelineProjection {
    var sections: [HomeTimelineSection] = []
    var entryCount = 0
    var hasMoreEntries = false
    var smartFolderCounts: [UUID: Int] = [:]
}

enum HomeTimelinePresentation {
    static func sections(
        for entries: [HomeTimelineEntry],
        sortedBy order: NoteSortOrder,
        groupByDate: Bool,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [HomeTimelineSection] {
        let pinnedEntries = entries.filter(\.isPinned)
        let otherEntries = entries.filter { !$0.isPinned }
        var sections: [HomeTimelineSection] = []
        if !pinnedEntries.isEmpty {
            sections.append(
                HomeTimelineSection(
                    id: "pinned",
                    title: String(localized: "Pinned"),
                    entries: pinnedEntries
                )
            )
        }
        guard !otherEntries.isEmpty else { return sections }
        guard groupByDate, order != .title else {
            sections.append(
                HomeTimelineSection(
                    id: "notes",
                    title: pinnedEntries.isEmpty ? nil : String(localized: "Notes"),
                    entries: otherEntries
                )
            )
            return sections
        }

        for entry in otherEntries {
            let bucket = NoteListPresentation.dateBucket(
                for: entry.date,
                now: now,
                calendar: calendar
            )
            if sections.last?.id == bucket.id {
                sections[sections.count - 1].entries.append(entry)
            } else {
                sections.append(
                    HomeTimelineSection(
                        id: bucket.id,
                        title: bucket.title,
                        entries: [entry]
                    )
                )
            }
        }
        return sections
    }
}

enum HomeFolderScope {
    static func contains(
        fileRelativePath: String,
        folderRelativePath: String
    ) -> Bool {
        guard !folderRelativePath.isEmpty else { return true }
        let parentPath = (fileRelativePath as NSString).deletingLastPathComponent
        return parentPath == folderRelativePath
            || parentPath.hasPrefix(folderRelativePath + "/")
    }
}

struct NotesTopBarAppearance: Equatable {
    var isToolbarBackgroundVisible: Bool
    var usesSystemScrollEdgeBlur: Bool
    var usesAdaptiveCanvas: Bool
    var scrollEdgeBottom: CGFloat

    static let notes = NotesTopBarAppearance(
        isToolbarBackgroundVisible: true,
        usesSystemScrollEdgeBlur: true,
        usesAdaptiveCanvas: true,
        scrollEdgeBottom: 128
    )

    func scrollEdgeExtensionHeight(chromeBottom: CGFloat) -> CGFloat {
        max(0, scrollEdgeBottom - chromeBottom)
    }
}

struct HomeChromeMotion {
    enum Title: Equatable {
        case notes
        case folders
    }

    enum TitleTransition: Equatable {
        case opacity
    }

    static let titleTransition = TitleTransition.opacity
    static let titleDuration = 0.12

    static func titleDuration(
        from previous: Title,
        to next: Title,
        reduceMotion: Bool
    ) -> TimeInterval {
        guard !reduceMotion, previous != next else { return 0 }
        return titleDuration
    }

    static func titleAnimation(reduceMotion: Bool) -> Animation? {
        let duration = titleDuration(
            from: .notes,
            to: .folders,
            reduceMotion: reduceMotion
        )
        return duration > 0 ? .easeOut(duration: duration) : nil
    }

    static func captureDismissDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : 0.18
    }

    static func captureDismissAnimation(reduceMotion: Bool) -> Animation? {
        let duration = captureDismissDuration(reduceMotion: reduceMotion)
        return duration > 0 ? .easeOut(duration: duration) : nil
    }
}

struct DirectoryDrawerMotion {
    enum DragAxis: Equatable {
        case undecided
        case horizontal
        case vertical
    }

    struct Presentation: Equatable {
        var reveal: CGFloat
        var progress: CGFloat
        var contentOffset: CGFloat
        var drawerOffset: CGFloat
        var cornerRadius: CGFloat
        var scrimOpacity: CGFloat
        var shadowOpacity: CGFloat
    }

    enum HapticTiming: Equatable {
        case atSettlementStart
    }

    static func settlingAnimation(reduceMotion: Bool) -> Animation {
        if reduceMotion {
            return .easeOut(duration: 0.16)
        }
        return .interactiveSpring(
            response: 0.28,
            dampingFraction: 0.88,
            blendDuration: 0.08
        )
    }

    static func reveal(
        isOpen: Bool,
        translation: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        guard width > 0 else { return 0 }
        let restingReveal = isOpen ? width : 0
        return min(width, max(0, restingReveal + translation))
    }

    static func presentation(
        isOpen: Bool,
        translation: CGFloat,
        width: CGFloat
    ) -> Presentation {
        let reveal = reveal(
            isOpen: isOpen,
            translation: translation,
            width: width
        )
        let progress = reveal / max(width, 1)
        return Presentation(
            reveal: reveal,
            progress: progress,
            contentOffset: 0,
            drawerOffset: reveal - width,
            cornerRadius: 0,
            scrimOpacity: 0.20 * progress,
            shadowOpacity: 0.18 * progress
        )
    }

    static func dragAxis(
        for translation: CGSize,
        activationDistance: CGFloat = 6
    ) -> DragAxis {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= activationDistance else {
            return .undecided
        }
        return horizontal >= vertical ? .horizontal : .vertical
    }

    static func shouldOpen(
        isOpen: Bool,
        translation: CGFloat,
        projectedTranslation: CGFloat,
        width: CGFloat
    ) -> Bool {
        guard width > 0 else { return false }
        let currentReveal = reveal(
            isOpen: isOpen,
            translation: translation,
            width: width
        )
        let projectedReveal = reveal(
            isOpen: isOpen,
            translation: projectedTranslation,
            width: width
        )
        let projectedTravel = projectedReveal - currentReveal
        let minimumMomentumTravel = width * 0.08

        if abs(translation) >= minimumMomentumTravel,
           abs(projectedTravel) >= width * 0.12 {
            return projectedTravel > 0
        }
        return currentReveal >= width * 0.5
    }

    static func hapticTiming(wasOpen: Bool, willOpen: Bool) -> HapticTiming? {
        wasOpen == willOpen ? nil : .atSettlementStart
    }

    static func shouldAnimateTopChrome<Value: Equatable>(
        previous: Value,
        next: Value
    ) -> Bool {
        previous != next
    }
}

final class DirectoryHapticFeedback {
    private let generator = UIImpactFeedbackGenerator(style: .light)
    private var isPrepared = false

    func prepare() {
        guard !isPrepared else { return }
        generator.prepare()
        isPrepared = true
    }

    func impact() {
        generator.impactOccurred()
        isPrepared = false
    }

    func cancel() {
        isPrepared = false
    }
}

extension View {
    func notesTranslucentTopToolbar() -> some View {
        toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    @ViewBuilder
    func notesTopScrollEdgeBlur(
        isEnabled: Bool
    ) -> some View {
        if #available(iOS 26.0, *) {
            overlay(alignment: .top) {
                if isEnabled {
                    Color.clear
                        .frame(height: NotesTopBarAppearance.notes.scrollEdgeBottom)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(MudsnoteColors.line.opacity(0.45))
                                .frame(height: 0.5)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
        } else {
            self
        }
    }

    func suppressTopChromeAnimationWhenUnchanged<Value: Equatable>(
        previous: Value,
        next: Value
    ) -> some View {
        transaction { transaction in
            guard !DirectoryDrawerMotion.shouldAnimateTopChrome(
                previous: previous,
                next: next
            ) else { return }
            transaction.animation = nil
        }
    }

    @ViewBuilder
    func notesGlassBottomToolbar() -> some View {
        if #available(iOS 26.0, *) {
            toolbarBackground(.hidden, for: .bottomBar)
                .scrollEdgeEffectHidden(true, for: .bottom)
        } else {
            self
        }
    }
}

struct HomeTitleTransitionModifier: ViewModifier {
    @Binding var progress: CGFloat

    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGFloat.self) { proxy in
            let frame = proxy.frame(in: .scrollView(axis: .vertical))
            guard frame.height > 0 else { return 0 }
            return min(1, max(0, 1 - (frame.maxY / frame.height)))
        } action: { nextProgress in
            guard abs(progress - nextProgress) > 0.001 else { return }
            progress = nextProgress
        }
    }
}

struct LibraryHomeView: View {
    private struct SearchTaskID: Hashable {
        var query: String
        var scope: MarkdownSearchScope
        var folderRelativePath: String?
        var dateFilterRawValue: String?
        var libraryRevision: Int
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isSearchFocused = false
    @State private var searchQuery = ""
    @State private var searchScope = MarkdownSearchScope.all
    @State private var searchFolderPath = ""
    @State private var searchDateFilter: SmartFolderDateFilter?
    @State private var searchSuggestion: NotesSearchSuggestion?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isManagingFolders = false
    @State private var smartFolderEditor: SmartFolderDefinition?
    @State private var smartFolderToDelete: SmartFolderDefinition?
    @AppStorage("mudsnote.ios.compactDirectoryTags") private var compactDirectoryTags = true
    @State private var isDirectoryPresented = false
    @State private var directoryDragOffset: CGFloat = 0
    @State private var directoryDragAxis = DirectoryDrawerMotion.DragAxis.undecided
    @State private var directoryHapticFeedback = DirectoryHapticFeedback()
    @State private var directoryPanelWidth: CGFloat = 360
    @State private var topChromeContentInset: CGFloat = 116
    @State private var expandedDirectoryPaths = Set<String>()
    @State private var selectedHomeFolderPath = ""
    @State private var homeTimelineProjection = HomeTimelineProjection()
    @State private var homePageWindow = NoteListPageWindow()
    @State private var homeTitleCollapseProgress: CGFloat = 0
    @AppStorage("mudsnote.ios.homeNoteViewStyle") private var viewStyleRawValue = NoteViewStyle.gallery.rawValue
    @AppStorage("mudsnote.ios.homeNoteSortOrder") private var sortOrderRawValue = NoteSortOrder.modified.rawValue
    @AppStorage("mudsnote.ios.homeNoteSortDirection") private var sortDirectionRawValue = NoteSortDirection.standard.rawValue
    @AppStorage("mudsnote.ios.homeGroupNotesByDate") private var groupByDate = true
    @State private var isSelectingNotes = false
    @State private var selectedHomeEntryIDs = Set<String>()
    @State private var isShowingAttachments = false
    @State private var isConfirmingSelectedDeletion = false
    var chooseFolder: () -> Void

    private var viewStyle: NoteViewStyle {
        NoteViewStyle(rawValue: viewStyleRawValue) ?? .gallery
    }

    private var sortOrder: NoteSortOrder {
        NoteSortOrder(rawValue: sortOrderRawValue) ?? .modified
    }

    private var sortDirection: NoteSortDirection {
        NoteSortDirection(rawValue: sortDirectionRawValue) ?? .standard
    }

    var body: some View {
        NavigationStack {
            directoryStage(width: directoryPanelWidth)
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { updateDirectoryWidth(proxy.size.width) }
                            .onChange(of: proxy.size.width) { _, width in
                                updateDirectoryWidth(width)
                            }
                    }
            }
            .background(NotesCloneColors.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: $isShowingAttachments) {
                AttachmentLibraryView()
            }
            .onChange(of: searchQuery) { _, value in
                if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchSuggestion = nil
                }
            }
            .onDisappear {
                isSearchFocused = false
                resetDirectoryState()
                finishSelectingHomeNotes()
            }
            .onAppear {
                refreshHomeTimelineProjection(resetPagination: true)
                presentRequestedSearchIfNeeded()
                if ProcessInfo.processInfo.arguments.contains("-ui-testing-open-directory") {
                    isDirectoryPresented = true
                }
            }
            .onChange(of: appModel.isLibrarySearchRequested) { _, requested in
                if requested { presentRequestedSearchIfNeeded() }
            }
            .onChange(of: appModel.libraryRevision) { _, _ in
                refreshHomeTimelineProjection()
            }
            .onChange(of: viewStyleRawValue) { _, _ in
                refreshHomeTimelineProjection()
            }
            .onChange(of: sortOrderRawValue) { _, _ in
                refreshHomeTimelineProjection(resetPagination: true)
            }
            .onChange(of: sortDirectionRawValue) { _, _ in
                refreshHomeTimelineProjection(resetPagination: true)
            }
            .onChange(of: groupByDate) { _, _ in
                refreshHomeTimelineProjection(resetPagination: true)
            }
            .task(id: SearchTaskID(
                query: searchQuery,
                scope: searchScope,
                folderRelativePath: currentSearchFilter.folderRelativePath,
                dateFilterRawValue: currentSearchFilter.dateFilter?.rawValue,
                libraryRevision: appModel.libraryRevision
            )) {
                let trimmed = normalizedSearchQuery
                guard !trimmed.isEmpty else {
                    appModel.clearSearch()
                    return
                }
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await appModel.searchLibrary(
                    query: trimmed,
                    scope: searchScope,
                    filter: currentSearchFilter
                )
            }
            .toolbar {
                if !isSelectingNotes {
                    ToolbarItem(placement: .principal) {
                        homePrincipalTitle
                    }
                }

                if isSelectingNotes {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(allHomeEntriesSelected ? "Deselect All" : "Select All") {
                            toggleAllHomeEntries()
                        }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("toggle-select-all-home-notes")
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if isDirectoryPresented {
                                closeDirectory()
                            } else {
                                settleDirectory(open: true, emitsHaptic: true)
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                        }
                        .accessibilityLabel(
                            isDirectoryPresented ? "Close Folders" : "Open Folders"
                        )
                        .accessibilityIdentifier("directory-button")
                        .suppressTopChromeAnimationWhenUnchanged(
                            previous: "sidebar.left",
                            next: "sidebar.left"
                        )
                    }
                }

                if isDirectoryPresented {
                    ToolbarItem(placement: .topBarTrailing) {
                        if isManagingFolders {
                            Button {
                                newFolderName = ""
                                isCreatingFolder = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                            }
                            .accessibilityLabel("New Folder")
                            .accessibilityIdentifier("new-folder-button")
                        } else {
                            NavigationLink {
                                SettingsRulesView(chooseFolder: chooseFolder)
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .accessibilityLabel("Settings")
                            .accessibilityIdentifier("sidebar-settings-button")
                        }
                    }

                    if #available(iOS 26.0, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isSearchFocused = false
                            searchQuery = ""
                            searchSuggestion = nil
                            withAnimation(.snappy(duration: 0.28, extraBounce: 0.08)) {
                                isManagingFolders.toggle()
                            }
                        } label: {
                            Group {
                                if isManagingFolders {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 17, weight: .semibold))
                                        .accessibilityIdentifier("finish-folder-editing-icon")
                                } else {
                                    Text("Edit")
                                }
                            }
                            .frame(minWidth: 34, minHeight: 24)
                            .transition(.blurReplace)
                        }
                        .accessibilityLabel(isManagingFolders ? "Done" : "Edit")
                        .accessibilityIdentifier("edit-folders-button")
                    }
                } else if isSelectingNotes {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(
                                String(
                                    format: String(localized: "notes.selected.format"),
                                    locale: .current,
                                    selectedHomeEntryIDs.count
                                )
                            )
                            .font(.headline)
                            Text(
                                localizedNoteCount(allHomeSelectableEntries.count)
                            )
                            .font(.caption)
                            .foregroundStyle(MudsnoteColors.muted)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("home-note-selection-summary")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button { finishSelectingHomeNotes() } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(MudsnoteColors.primary)
                        }
                            .accessibilityLabel("Done")
                            .accessibilityIdentifier("finish-home-note-selection")
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        HomeNoteOptionsMenu(
                            viewStyleRawValue: $viewStyleRawValue,
                            sortOrderRawValue: $sortOrderRawValue,
                            sortDirectionRawValue: $sortDirectionRawValue,
                            groupByDate: $groupByDate,
                            selectNotes: { isSelectingNotes = true },
                            viewAttachments: { isShowingAttachments = true }
                        )
                    }

                }
            }
            .alert("New Folder", isPresented: $isCreatingFolder) {
                TextField("Folder Name", text: $newFolderName)
                Button("Cancel", role: .cancel) {}
                Button("Make Into Smart Folder") {
                    smartFolderEditor = SmartFolderDefinition(name: newFolderName)
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Create") {
                    let name = newFolderName
                    Task { _ = await appModel.createFolder(named: name) }
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .sheet(item: $smartFolderEditor) { definition in
                SmartFolderEditorView(
                    definition: definition,
                    isNew: !appModel.smartFolders.contains(where: { $0.id == definition.id })
                )
                .environmentObject(appModel)
            }
            .confirmationDialog(
                "Delete Smart Folder?",
                isPresented: smartFolderDeletePresented,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Smart Folder", role: .destructive) {
                    guard let smartFolderToDelete else { return }
                    Task { _ = await appModel.deleteSmartFolder(smartFolderToDelete) }
                }
            } message: {
                Text("Notes stay in their original folders.")
            }
            .toolbar {
                if !isSelectingNotes {
                    NotesBottomCommandBar(
                        searchText: $searchQuery,
                        searchFocused: $isSearchFocused,
                        voiceInput: {
                            isSearchFocused = false
                            appModel.showCapture(
                                .audio,
                                inFolder: selectedHomeFolderPath.isEmpty
                                    ? nil
                                    : selectedHomeFolderPath
                            )
                        },
                        newNote: {
                            isSearchFocused = false
                            appModel.showCapture(
                                .text,
                                inFolder: selectedHomeFolderPath.isEmpty
                                    ? nil
                                    : selectedHomeFolderPath
                            )
                        }
                    )
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isSelectingNotes {
                    HomeSelectedNotesActionBar(
                        count: selectedHomeEntryIDs.count,
                        delete: { isConfirmingSelectedDeletion = true }
                    )
                }
            }
            .confirmationDialog(
                "Delete Selected Notes?",
                isPresented: $isConfirmingSelectedDeletion,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) { deleteSelectedHomeEntries() }
            }
        }
        .notesNativeToolbarSearch(
            text: $searchQuery,
            isPresented: $isSearchFocused
        )
        .notesTranslucentTopToolbar()
        .notesGlassBottomToolbar()
        .onChange(of: appModel.currentLibraryID, initial: true) {
            restoreLibraryFolderSelection()
        }
        .onChange(of: appModel.libraryRevision) {
            reconcileLibraryFolderSelection()
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if showsSearchExperience {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    homeLargeTitleHeader
                    searchSection
                }
                    .padding(.horizontal, 18)
                    .padding(.top, topContentPadding + 12)
                    .padding(.bottom, 110)
            }
            .scrollClipDisabled()
            .scrollDismissesKeyboard(.interactively)
            .notesTopScrollEdgeBlur(isEnabled: !isDirectoryPresented)
            .simultaneousGesture(TapGesture().onEnded {
                if isSearchFocused { isSearchFocused = false }
            })
        } else {
            homeCardStream
        }
    }

    private var homeCardStream: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if !isSelectingNotes {
                    homeLargeTitleHeader
                }

                LazyVStack(alignment: .leading, spacing: 22) {
                    if appModel.isInitialLibraryLoading, homeTimelineProjection.sections.isEmpty {
                        ProgressView("Loading Notes…")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if homeTimelineProjection.sections.isEmpty {
                        VStack {
                            ContentUnavailableView(
                                "No Notes",
                                systemImage: "note.text",
                                description: Text(
                                    selectedHomeFolderPath.isEmpty
                                        ? "Create a note or swipe right to open your folders."
                                        : "This folder has no notes yet."
                                )
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                    } else {
                        ForEach(homeTimelineProjection.sections) { section in
                            if viewStyle == .gallery {
                                HomeTimelineCardSection(
                                    section: section,
                                    isSelecting: isSelectingNotes,
                                    selectedIDs: selectedHomeEntryIDs,
                                    toggleSelection: toggleHomeSelection
                                )
                            } else {
                                HomeTimelineListSection(
                                    section: section,
                                    isSelecting: isSelectingNotes,
                                    selectedIDs: selectedHomeEntryIDs,
                                    toggleSelection: toggleHomeSelection
                                )
                            }
                        }
                        if homeTimelineProjection.hasMoreEntries {
                            NoteListPaginationFooter(
                                pageToken: homePageWindow.visibleCount,
                                loadMore: revealNextHomePage
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, topContentPadding + 8)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .notesTopScrollEdgeBlur(isEnabled: !isDirectoryPresented)
        .accessibilityIdentifier(homeContentIdentifier)
    }

    private func makeHomeTimelineProjection() -> HomeTimelineProjection {
        let folderPath = selectedHomeFolderPath
        let visibleFiles = appModel.libraryFiles.filter { file in
            guard !folderPath.isEmpty else { return true }
            return HomeFolderScope.contains(
                fileRelativePath: file.relativePath,
                folderRelativePath: folderPath
            )
        }
        let unsortedEntries = (
            visibleFiles.map(HomeTimelineEntry.file)
                + (folderPath.isEmpty ? appModel.inboxItems.map(HomeTimelineEntry.memo) : [])
        )
        let entries = unsortedEntries.sorted { lhs, rhs in
            let standard: Bool
            switch sortOrder {
            case .modified, .created:
                if lhs.date != rhs.date {
                    standard = lhs.date > rhs.date
                    return sortDirection == .standard ? standard : !standard
                }
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame {
                    standard = comparison == .orderedAscending
                    return sortDirection == .standard ? standard : !standard
                }
            }
            standard = lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
            return sortDirection == .standard ? standard : !standard
        }

        let orderedEntries = entries.filter(\.isPinned) + entries.filter { !$0.isPinned }
        let visibleEntries = homePageWindow.visibleItems(from: orderedEntries)
        let sections = HomeTimelinePresentation.sections(
            for: visibleEntries,
            sortedBy: sortOrder,
            groupByDate: groupByDate
        )
        let smartFolderCounts = Dictionary(uniqueKeysWithValues: appModel.smartFolders.map { definition in
            let count = appModel.libraryFiles.lazy.filter {
                definition.matches(file: $0)
            }.count + appModel.inboxItems.lazy.filter {
                definition.matches(memo: $0)
            }.count
            return (definition.id, count)
        })
        return HomeTimelineProjection(
            sections: sections,
            entryCount: orderedEntries.count,
            hasMoreEntries: homePageWindow.hasMore(totalCount: orderedEntries.count),
            smartFolderCounts: smartFolderCounts
        )
    }

    private func refreshHomeTimelineProjection(resetPagination: Bool = false) {
        if resetPagination {
            homePageWindow.reset()
        }
        homeTimelineProjection = makeHomeTimelineProjection()
    }

    private func revealNextHomePage() {
        guard homePageWindow.hasMore(totalCount: homeTimelineProjection.entryCount) else {
            return
        }
        homePageWindow.revealNext(totalCount: homeTimelineProjection.entryCount)
        homeTimelineProjection = makeHomeTimelineProjection()
    }

    private func updateDirectoryWidth(_ availableWidth: CGFloat) {
        let minimumWidth = min(320, availableWidth)
        let width = min(max(availableWidth * 0.90, minimumWidth), 360)
        guard abs(width - directoryPanelWidth) > 0.5 else { return }
        directoryPanelWidth = width
    }

    private func directoryStage(width: CGFloat) -> some View {
        let presentation = directoryPresentation(width: width)
        let alignment: Alignment = layoutDirection == .leftToRight ? .leading : .trailing
        let physicalDirection: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return ZStack(alignment: alignment) {
            homeContent
                .background(NotesCloneColors.background)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: presentation.cornerRadius,
                        style: .continuous
                    )
                )
                .shadow(
                    color: .black.opacity(presentation.shadowOpacity),
                    radius: 14,
                    x: -4 * physicalDirection
                )
                .offset(x: presentation.contentOffset * physicalDirection)
                .allowsHitTesting(presentation.reveal <= 0)

            Color.black
                .opacity(presentation.scrimOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .offset(x: presentation.contentOffset * physicalDirection)
                .onTapGesture(perform: closeDirectory)
                .gesture(directoryDragGesture(width: width))
                .allowsHitTesting(presentation.reveal > 0)
                .accessibilityLabel("Close Folders")
                .accessibilityIdentifier("directory-backdrop")
                .accessibilityAddTraits(.isButton)
                .accessibilityHidden(presentation.reveal <= 0)

            directoryPanel(width: width)
                .offset(x: presentation.drawerOffset * physicalDirection)
                .simultaneousGesture(directoryDragGesture(width: width))
                .allowsHitTesting(presentation.reveal > 0)
                .accessibilityHidden(presentation.reveal <= 0)

            if !isDirectoryPresented {
                Color.clear
                    .frame(width: 32)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        directoryDragGesture(width: width, minimumDistance: 4)
                    )
                    .accessibilityElement()
                    .accessibilityLabel("Swipe right for folders")
                    .accessibilityIdentifier("directory-swipe-edge")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }

    private var navigationTitle: String {
        if isSelectingNotes {
            return String(
                format: String(localized: "notes.selected.format"),
                locale: .current,
                selectedHomeEntryIDs.count
            )
        }
        return ""
    }

    private var homePrincipalTitle: some View {
        ZStack {
            if isDirectoryPresented {
                Color.clear
            } else {
                homeCompactTitle
                    .transition(.opacity)
            }
        }
        .frame(minWidth: 92, minHeight: 36)
        .animation(
            HomeChromeMotion.titleAnimation(reduceMotion: reduceMotion),
            value: isDirectoryPresented
        )
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY + 12
        } action: { inset in
            guard inset > 0, abs(inset - topChromeContentInset) > 0.5 else { return }
            topChromeContentInset = inset
        }
    }

    private var homeLargeTitleHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(homeDisplayTitle)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(MudsnoteColors.text)
            Text(homeNoteCountText)
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(1 - homeTitleCollapseProgress)
        .scaleEffect(
            1 - (0.34 * homeTitleCollapseProgress),
            anchor: .topLeading
        )
        .offset(y: -8 * homeTitleCollapseProgress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(homeDisplayTitle)
        .accessibilityValue(homeNoteCountText)
        .accessibilityIdentifier("home-large-title")
        .accessibilityHidden(homeTitleCollapseProgress >= 0.99)
        .allowsHitTesting(homeTitleCollapseProgress < 0.99)
        .modifier(
            HomeTitleTransitionModifier(
                progress: $homeTitleCollapseProgress
            )
        )
    }

    private var homeCompactTitle: some View {
        VStack(spacing: -2) {
            Text(homeDisplayTitle)
                .font(.headline)
                .foregroundStyle(MudsnoteColors.text)
            Text(homeNoteCountText)
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
        }
        .opacity(homeTitleCollapseProgress)
        .scaleEffect(0.9 + (0.1 * homeTitleCollapseProgress))
        .offset(y: 4 * (1 - homeTitleCollapseProgress))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(homeDisplayTitle)
        .accessibilityValue(homeNoteCountText)
        .accessibilityIdentifier(
            homeTitleCollapseProgress >= 0.99
                ? "home-compact-title"
                : "home-compact-title-hidden"
        )
        .accessibilityHidden(homeTitleCollapseProgress < 0.99)
        .allowsHitTesting(false)
    }

    private var homeNoteCountText: String {
        localizedNoteCount(homeTimelineProjection.entryCount)
    }

    private var homeDisplayTitle: String {
        guard !selectedHomeFolderPath.isEmpty else {
            return String(localized: "Notes")
        }
        return appModel.allFolders.first {
            $0.relativePath == selectedHomeFolderPath
        }?.name ?? (selectedHomeFolderPath as NSString).lastPathComponent
    }

    private var homeContentIdentifier: String {
        let base = viewStyle == .gallery ? "home-note-gallery" : "home-note-list"
        guard !selectedHomeFolderPath.isEmpty else { return base }
        return "\(base)-folder:\(selectedHomeFolderPath)"
    }

    private var topContentPadding: CGFloat {
        max(0, topChromeContentInset)
    }

    private var allHomeNoteCount: Int {
        appModel.libraryFiles.count
    }

    private var directoryFolders: [LibraryFolderNode] {
        appModel.visibleLibraryFolders
    }

    private var allHomeSelectableEntries: [HomeTimelineEntry] {
        let folderPath = selectedHomeFolderPath
        let files = appModel.libraryFiles.filter { file in
            guard !folderPath.isEmpty else { return true }
            return HomeFolderScope.contains(
                fileRelativePath: file.relativePath,
                folderRelativePath: folderPath
            )
        }
        return files.map(HomeTimelineEntry.file)
            + (folderPath.isEmpty ? appModel.inboxItems.map(HomeTimelineEntry.memo) : [])
    }

    private var allHomeEntryIDs: Set<String> {
        Set(allHomeSelectableEntries.map(\.id))
    }

    private var allHomeEntriesSelected: Bool {
        !allHomeEntryIDs.isEmpty && selectedHomeEntryIDs == allHomeEntryIDs
    }

    private func toggleHomeSelection(_ entry: HomeTimelineEntry) {
        if !selectedHomeEntryIDs.insert(entry.id).inserted {
            selectedHomeEntryIDs.remove(entry.id)
        }
    }

    private func toggleAllHomeEntries() {
        selectedHomeEntryIDs = allHomeEntriesSelected ? [] : allHomeEntryIDs
    }

    private func finishSelectingHomeNotes() {
        selectedHomeEntryIDs = []
        isSelectingNotes = false
    }

    private func deleteSelectedHomeEntries() {
        let selected = allHomeSelectableEntries
            .filter { selectedHomeEntryIDs.contains($0.id) }
        for entry in selected {
            switch entry {
            case .file(let file): appModel.moveToRecentlyDeleted(file)
            case .memo(let memo): appModel.deleteMemo(memo)
            }
        }
        finishSelectingHomeNotes()
    }

    private func directoryPanel(width: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                accountSection
                if !appModel.smartFolders.isEmpty {
                    smartFoldersSection
                }
                if !appModel.tagSummaries.isEmpty {
                    tagsSection
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, topContentPadding + 8)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .notesTopScrollEdgeBlur(isEnabled: isDirectoryPresented)
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(MudsnoteColors.canvas)
        .overlay(alignment: .topLeading) {
            Text(String(localized: "Folders"))
                .font(.headline)
                .foregroundStyle(MudsnoteColors.text)
                .frame(width: width, height: 36)
                .padding(.top, max(0, topChromeContentInset - 48))
                .accessibilityIdentifier("folders-compact-title")
                .allowsHitTesting(false)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(MudsnoteColors.line)
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, x: 5)
        .accessibilityIdentifier("directory-drawer")
    }

    private func directoryPresentation(width: CGFloat) -> DirectoryDrawerMotion.Presentation {
        DirectoryDrawerMotion.presentation(
            isOpen: isDirectoryPresented,
            translation: directoryDragOffset,
            width: width
        )
    }

    private func directoryDragGesture(
        width: CGFloat,
        minimumDistance: CGFloat = 6
    ) -> some Gesture {
        DragGesture(minimumDistance: minimumDistance, coordinateSpace: .local)
            .onChanged { value in
                if directoryDragAxis == .undecided {
                    let resolvedAxis = DirectoryDrawerMotion.dragAxis(
                        for: value.translation
                    )
                    guard resolvedAxis != .undecided else { return }
                    directoryDragAxis = resolvedAxis
                    if resolvedAxis == .horizontal {
                        directoryHapticFeedback.cancel()
                        directoryHapticFeedback.prepare()
                    }
                }
                guard directoryDragAxis == .horizontal else { return }

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    let logicalTranslation = value.translation.width * directoryPhysicalDirection
                    if isDirectoryPresented {
                        directoryDragOffset = min(0, logicalTranslation)
                    } else {
                        directoryDragOffset = max(0, logicalTranslation)
                    }
                }
            }
            .onEnded { value in
                guard directoryDragAxis == .horizontal else {
                    directoryDragAxis = .undecided
                    directoryDragOffset = 0
                    directoryHapticFeedback.cancel()
                    return
                }
                directoryDragAxis = .undecided
                let horizontal = value.translation.width * directoryPhysicalDirection
                let predicted = value.predictedEndTranslation.width * directoryPhysicalDirection
                let wasPresented = isDirectoryPresented
                let shouldOpen = DirectoryDrawerMotion.shouldOpen(
                    isOpen: isDirectoryPresented,
                    translation: horizontal,
                    projectedTranslation: predicted,
                    width: width
                )
                settleDirectory(
                    open: shouldOpen,
                    emitsHaptic: shouldOpen != wasPresented
                )
            }
    }

    private func closeDirectory() {
        guard isDirectoryPresented else { return }
        settleDirectory(open: false, emitsHaptic: true)
    }

    private func selectAllNotes() {
        selectedHomeFolderPath = ""
        searchFolderPath = ""
        persistLibraryFolderSelection()
        selectedHomeEntryIDs.removeAll()
        homeTitleCollapseProgress = 0
        Task { @MainActor in
            await Task.yield()
            refreshHomeTimelineProjection(resetPagination: true)
            closeDirectory()
        }
    }

    private func selectHomeFolder(_ folder: LibraryFolderNode) {
        selectedHomeFolderPath = folder.relativePath
        searchFolderPath = folder.relativePath
        persistLibraryFolderSelection()
        selectedHomeEntryIDs.removeAll()
        homeTitleCollapseProgress = 0
        Task { @MainActor in
            await Task.yield()
            refreshHomeTimelineProjection(resetPagination: true)
            closeDirectory()
        }
    }

    private var selectedFolderDefaultsKey: String? {
        guard !appModel.currentLibraryID.isEmpty else { return nil }
        return "mudsnote.ios.selectedHomeFolderPath.\(appModel.currentLibraryID)"
    }

    private func restoreLibraryFolderSelection() {
        guard let key = selectedFolderDefaultsKey else {
            selectedHomeFolderPath = ""
            searchFolderPath = ""
            return
        }
        selectedHomeFolderPath = UserDefaults.standard.string(forKey: key) ?? ""
        searchFolderPath = selectedHomeFolderPath
        reconcileLibraryFolderSelection()
    }

    private func reconcileLibraryFolderSelection() {
        guard !selectedHomeFolderPath.isEmpty else { return }
        guard appModel.allFolders.contains(where: {
            $0.relativePath == selectedHomeFolderPath
        }) else {
            selectedHomeFolderPath = ""
            searchFolderPath = ""
            persistLibraryFolderSelection()
            refreshHomeTimelineProjection(resetPagination: true)
            return
        }
    }

    private func persistLibraryFolderSelection() {
        guard let key = selectedFolderDefaultsKey else { return }
        if selectedHomeFolderPath.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(selectedHomeFolderPath, forKey: key)
        }
    }

    private func settleDirectory(open: Bool, emitsHaptic: Bool) {
        if open {
            isSearchFocused = false
            finishSelectingHomeNotes()
        } else {
            isManagingFolders = false
        }

        let hapticTiming = emitsHaptic
            ? DirectoryDrawerMotion.hapticTiming(
                wasOpen: isDirectoryPresented,
                willOpen: open
            )
            : nil

        if hapticTiming != nil {
            directoryHapticFeedback.prepare()
            directoryHapticFeedback.impact()
        } else {
            directoryHapticFeedback.cancel()
        }

        withAnimation(DirectoryDrawerMotion.settlingAnimation(reduceMotion: reduceMotion)) {
            isDirectoryPresented = open
            directoryDragOffset = 0
        }
    }

    private var directoryPhysicalDirection: CGFloat {
        layoutDirection == .leftToRight ? 1 : -1
    }

    private func resetDirectoryState() {
        isDirectoryPresented = false
        directoryDragOffset = 0
        directoryDragAxis = .undecided
        isManagingFolders = false
        directoryHapticFeedback.cancel()
    }

    private func presentRequestedSearchIfNeeded() {
        guard appModel.consumeLibrarySearchRequest() else { return }
        searchQuery = ""
        searchSuggestion = nil
        Task { @MainActor in
            await Task.yield()
            isSearchFocused = true
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                notesCard {
                    Button(action: selectAllNotes) {
                        NotesFolderRow(
                            title: String(localized: "Notes"),
                            systemImage: "note.text",
                            count: allHomeNoteCount,
                            showsChevron: false,
                            isSelected: selectedHomeFolderPath.isEmpty
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(
                        selectedHomeFolderPath.isEmpty ? .isSelected : []
                    )
                    .accessibilityValue(
                        selectedHomeFolderPath.isEmpty ? String(localized: "Selected") : ""
                    )
                    .accessibilityIdentifier("all-notes-row")

                    ForEach(directoryFolders) { folder in
                        DirectoryFolderTree(
                            folder: folder,
                            depth: 0,
                            isManaging: isManagingFolders,
                            expandedPaths: $expandedDirectoryPaths,
                            selectedPath: selectedHomeFolderPath,
                            systemImage: folderSystemImage,
                            select: selectHomeFolder
                        )
                    }
                }
            }

            notesCard {
                HStack(spacing: 0) {
                    NavigationLink {
                        AttachmentLibraryView()
                    } label: {
                        LibraryUtilityButton(
                            systemImage: "paperclip",
                            count: appModel.librarySummary.attachmentCount
                        )
                    }
                    .accessibilityLabel("Attachments")
                    .accessibilityValue("\(appModel.librarySummary.attachmentCount)")
                    .accessibilityIdentifier("attachments-link")

                    Rectangle()
                        .fill(NotesCloneColors.separator)
                        .frame(width: 1, height: 30)
                        .accessibilityHidden(true)

                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        LibraryUtilityButton(
                            systemImage: "trash",
                            count: appModel.librarySummary.recentlyDeletedCount
                        )
                    }
                    .accessibilityLabel("Recently Deleted")
                    .accessibilityValue("\(appModel.librarySummary.recentlyDeletedCount)")
                    .accessibilityIdentifier("recently-deleted-link")
                }
            }
        }
    }

    private func folderSystemImage(for folder: LibraryFolderNode) -> String {
        let name = folder.name.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )

        if name.contains("inbox") || name.contains("收件") { return "tray" }
        if name.contains("project") || name.contains("项目") { return "hammer" }
        if name.contains("work") || name.contains("工作") { return "briefcase" }
        if name.contains("personal") || name.contains("个人") { return "person.crop.circle" }
        if name.contains("resource") || name.contains("reference") || name.contains("资料") {
            return "books.vertical"
        }
        if name.contains("archive") || name.contains("归档") { return "archivebox" }
        if name.contains("idea") || name.contains("灵感") { return "lightbulb" }
        if name.contains("study") || name.contains("学习") { return "graduationcap" }
        if name.contains("travel") || name.contains("旅行") { return "airplane" }
        return "folder"
    }

    @ViewBuilder
    private var smartFoldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotesSectionHeader(title: String(localized: "Smart Folders"))
            notesCard {
                ForEach(appModel.smartFolders) { definition in
                    if isManagingFolders {
                        ZStack(alignment: .trailing) {
                            NotesFolderRow(
                                title: definition.name,
                                systemImage: "folder.badge.gearshape",
                                count: smartFolderCount(definition),
                                showsChevron: false,
                                trailingAccessoryWidth: 44
                            )

                            Menu {
                                Button {
                                    smartFolderEditor = definition
                                } label: {
                                    Label("Edit Smart Folder", systemImage: "slider.horizontal.3")
                                }
                                Button(role: .destructive) {
                                    smartFolderToDelete = definition
                                } label: {
                                    Label("Delete Smart Folder", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(NotesCloneColors.folderYellow)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Folder Actions")
                            .accessibilityIdentifier("smart-folder-management-\(definition.id.uuidString)")
                            .padding(.trailing, 10)
                        }
                    } else {
                        NavigationLink {
                            SmartFolderNotesView(smartFolderID: definition.id)
                        } label: {
                            NotesFolderRow(
                                title: definition.name,
                                systemImage: "folder.badge.gearshape",
                                count: smartFolderCount(definition)
                            )
                        }
                        .accessibilityIdentifier("smart-folder-row-\(definition.id.uuidString)")
                        .contextMenu {
                            Button {
                                smartFolderEditor = definition
                            } label: {
                                Label("Edit Smart Folder", systemImage: "slider.horizontal.3")
                            }
                            .accessibilityIdentifier("edit-smart-folder-\(definition.id.uuidString)")

                            Button(role: .destructive) {
                                smartFolderToDelete = definition
                            } label: {
                                Label("Delete Smart Folder", systemImage: "trash")
                            }
                            .accessibilityIdentifier("delete-smart-folder-\(definition.id.uuidString)")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String(localized: "Tags"))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(MudsnoteColors.text)

                Spacer()

                Button {
                    compactDirectoryTags.toggle()
                } label: {
                    Image(systemName: compactDirectoryTags ? "list.bullet" : "square.grid.2x2")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(compactDirectoryTags ? "显示标签列表" : "显示小标签")
                .accessibilityIdentifier("directory-tag-layout-toggle")

                NavigationLink {
                    TagsBrowserView()
                } label: {
                    HStack(spacing: 6) {
                        Text("\(appModel.tagSummaries.count)")
                            .font(.system(.subheadline, design: .rounded))
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(MudsnoteColors.muted)
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("All Tags")
                .accessibilityValue("\(appModel.tagSummaries.count)")
                .accessibilityIdentifier("all-tags-link")
            }
            .padding(.horizontal, 2)

            if compactDirectoryTags {
                FlowLayout(spacing: 8, rowSpacing: 8) {
                    ForEach(appModel.tagSummaries) { tag in
                        NavigationLink {
                            TagNotesListView(tag: tag.name)
                        } label: {
                            Text(tag.name.hasPrefix("#") ? tag.name : "#" + tag.name)
                                .font(.subheadline)
                                .foregroundStyle(MudsnoteColors.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(MudsnoteColors.card, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tag.name)
                        .accessibilityIdentifier("tag-link-\(tag.name)")
                    }
                }
                .accessibilityIdentifier("directory-tag-chips")
            } else {
                notesCard {
                    ForEach(appModel.tagSummaries) { tag in
                        NavigationLink {
                            TagNotesListView(tag: tag.name)
                        } label: {
                            TagDirectoryRow(tag: tag)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tag.name)
                        .accessibilityValue("\(tag.count)")
                        .accessibilityIdentifier("tag-link-\(tag.name)")
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchFilters

            if normalizedSearchQuery.isEmpty {
                searchSuggestions
            }

            if searchSuggestion != nil {
                if suggestedSearchResults.isEmpty {
                    Text("No Results")
                        .foregroundStyle(.secondary)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
                } else {
                    notesCard {
                        ForEach(suggestedSearchResults) { result in
                            searchResultButton(result, query: "")
                        }
                    }
                }
            } else if normalizedSearchQuery.isEmpty {
                Text("Choose a suggestion or start typing.")
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
            } else if searchIsPending {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else if appModel.searchResults.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
            } else {
                notesCard {
                    ForEach(appModel.searchResults) { result in
                        searchResultButton(result, query: appModel.completedSearchQuery)
                    }
                }
            }
        }
    }

    private var searchFilters: some View {
        HStack(spacing: 8) {
            Menu {
                Button("All Folders") { searchFolderPath = "" }
                ForEach(appModel.visibleLibraryFolders) { folder in
                    Button(folder.relativePath) {
                        searchFolderPath = folder.relativePath
                    }
                }
            } label: {
                Label(searchFolderLabel, systemImage: "folder")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(MudsnoteColors.card, in: Capsule())
                    .overlay { Capsule().stroke(MudsnoteColors.line, lineWidth: 1) }
            }
            .accessibilityIdentifier("search-folder-filter")

            Menu {
                Button("Any Time") { searchDateFilter = nil }
                ForEach(SmartFolderDateFilter.allCases) { filter in
                    Button(filter.label) { searchDateFilter = filter }
                }
            } label: {
                Label(
                    searchDateFilter?.label ?? String(localized: "Any Time"),
                    systemImage: "calendar"
                )
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(MudsnoteColors.card, in: Capsule())
                .overlay { Capsule().stroke(MudsnoteColors.line, lineWidth: 1) }
            }
            .accessibilityIdentifier("search-date-filter")
        }
        .foregroundStyle(MudsnoteColors.text)
    }

    private var searchSuggestions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suggestions")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MudsnoteColors.muted)
                Spacer()
                if searchSuggestion != nil {
                    Button("Clear Filter") {
                        searchSuggestion = nil
                        isSearchFocused = false
                    }
                    .font(.caption.weight(.semibold))
                    .accessibilityIdentifier("clear-search-suggestion")
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(NotesSearchSuggestion.allCases) { suggestion in
                        Button {
                            searchSuggestion = suggestion
                            isSearchFocused = false
                            appModel.clearSearch()
                        } label: {
                            Label(suggestion.label, systemImage: suggestion.systemImage)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(
                                    searchSuggestion == suggestion
                                        ? Color.black
                                        : MudsnoteColors.text
                                )
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(
                                    searchSuggestion == suggestion
                                        ? NotesCloneColors.folderYellow
                                        : MudsnoteColors.card,
                                    in: Capsule()
                                )
                                .overlay {
                                    Capsule().stroke(MudsnoteColors.line, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search-suggestion-\(suggestion.id)")
                    }
                }
            }
        }
    }

    private func searchResultButton(
        _ result: MarkdownSearchResult,
        query: String
    ) -> some View {
        Button {
            isSearchFocused = false
            appModel.openSearchResult(result)
        } label: {
            SearchResultRow(result: result, query: query)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("search-result-\(result.id)")
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsSearchExperience: Bool {
        isSearchFocused || !normalizedSearchQuery.isEmpty || searchSuggestion != nil
    }

    private var suggestedSearchResults: [MarkdownSearchResult] {
        guard let searchSuggestion else { return [] }
        return searchSuggestion.results(
            files: appModel.libraryFiles,
            memos: appModel.inboxItems,
            scope: searchScope
        ).filter(searchResultMatchesCurrentFilter)
    }

    private var searchIsPending: Bool {
        appModel.isSearching
            || appModel.completedSearchQuery != normalizedSearchQuery
            || appModel.completedSearchScope != searchScope
            || appModel.completedSearchFilter != currentSearchFilter
    }

    private var currentSearchFilter: MarkdownSearchFilter {
        MarkdownSearchFilter(
            folderRelativePath: searchFolderPath,
            dateFilter: searchDateFilter
        )
    }

    private var searchFolderLabel: String {
        guard !searchFolderPath.isEmpty else { return String(localized: "All Folders") }
        return appModel.allFolders.first {
            $0.relativePath == searchFolderPath
        }?.name ?? (searchFolderPath as NSString).lastPathComponent
    }

    private func searchResultMatchesCurrentFilter(_ result: MarkdownSearchResult) -> Bool {
        switch result.destination {
        case .file(let file):
            currentSearchFilter.matches(file)
        case .memo:
            currentSearchFilter.folderRelativePath == nil
        }
    }

    private var smartFolderDeletePresented: Binding<Bool> {
        Binding(
            get: { smartFolderToDelete != nil },
            set: { if !$0 { smartFolderToDelete = nil } }
        )
    }

    private func smartFolderCount(_ definition: SmartFolderDefinition) -> Int {
        homeTimelineProjection.smartFolderCounts[definition.id] ?? 0
    }

    private func notesCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                .stroke(MudsnoteColors.line, lineWidth: 1)
        }
    }

}

struct DirectoryFolderTree: View {
    var folder: LibraryFolderNode
    var depth: Int
    var isManaging: Bool
    @Binding var expandedPaths: Set<String>
    var selectedPath: String
    var systemImage: (LibraryFolderNode) -> String
    var select: (LibraryFolderNode) -> Void

    private var isExpanded: Bool {
        expandedPaths.contains(folder.relativePath)
    }

    private var hasChildren: Bool {
        !folder.children.isEmpty
    }

    private var trailingAccessoryWidth: CGFloat {
        (isManaging ? 88 : 0) + 28
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                folderEntry

                if hasChildren {
                    Button {
                        withAnimation(.snappy(duration: 0.26, extraBounce: 0.04)) {
                            if !expandedPaths.insert(folder.relativePath).inserted {
                                expandedPaths.remove(folder.relativePath)
                            }
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MudsnoteColors.muted)
                            .frame(width: 44, height: 58)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, isManaging ? 88 : 0)
                    .accessibilityLabel(isExpanded ? "Collapse \(folder.name)" : "Expand \(folder.name)")
                    .accessibilityIdentifier("folder-disclosure-\(folder.relativePath)")
                }
            }

            if isExpanded {
                ForEach(folder.children) { child in
                    DirectoryFolderTree(
                        folder: child,
                        depth: depth + 1,
                        isManaging: isManaging,
                        expandedPaths: $expandedPaths,
                        selectedPath: selectedPath,
                        systemImage: systemImage,
                        select: select
                    )
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    @ViewBuilder
    private var folderEntry: some View {
        if isManaging {
            NotesFolderRow(
                title: folder.name,
                systemImage: systemImage(folder),
                count: folder.totalNoteCount,
                showsChevron: false,
                trailingAccessoryWidth: trailingAccessoryWidth,
                indentation: CGFloat(depth) * 18
            )
            .accessibilityIdentifier("folder-row-\(folder.relativePath)")
            .modifier(
                FolderLifecycleActions(
                    folder: folder,
                    isManagementMode: true
                )
            )
        } else {
            NotesFolderRow(
                title: folder.name,
                systemImage: systemImage(folder),
                count: folder.totalNoteCount,
                showsChevron: false,
                trailingAccessoryWidth: trailingAccessoryWidth,
                indentation: CGFloat(depth) * 18,
                isSelected: selectedPath == folder.relativePath
            )
            .contentShape(Rectangle())
            .onTapGesture { select(folder) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAddTraits(
                selectedPath == folder.relativePath ? .isSelected : []
            )
            .accessibilityAction {
                select(folder)
            }
            .accessibilityValue(
                selectedPath == folder.relativePath ? String(localized: "Selected") : ""
            )
            .accessibilityIdentifier("folder-row-\(folder.relativePath)")
            .modifier(FolderLifecycleActions(folder: folder))
        }
    }
}

struct SearchResultRow: View {
    var result: MarkdownSearchResult
    var query: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            SearchHighlightedText(text: result.title, query: query)
                .font(.body.weight(.semibold))
                .foregroundStyle(MudsnoteColors.text)
                .lineLimit(1)
            if !result.context.isEmpty {
                SearchHighlightedText(text: result.context, query: query)
                    .font(.subheadline)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(2)
            }
            SearchHighlightedText(text: result.location, query: query)
                .font(.caption)
                .foregroundStyle(MudsnoteColors.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(MudsnoteColors.line).frame(height: 1).padding(.leading, 18)
        }
    }
}

struct SearchHighlightedText: View {
    var text: String
    var query: String

    var body: some View {
        Text(highlightedText)
    }

    private var highlightedText: AttributedString {
        var attributed = AttributedString(text)
        for range in SearchHighlighting.ranges(in: text, query: query) {
            guard let lowerBound = AttributedString.Index(range.lowerBound, within: attributed),
                  let upperBound = AttributedString.Index(range.upperBound, within: attributed) else {
                continue
            }
            attributed[lowerBound..<upperBound].backgroundColor = Color.yellow.opacity(0.38)
            attributed[lowerBound..<upperBound].foregroundColor = MudsnoteColors.text
        }
        return attributed
    }
}

enum SearchHighlighting {
    static func ranges(in text: String, query: String) -> [Range<String.Index>] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
        var matches: [Range<String.Index>] = []
        for term in terms {
            var remaining = text.startIndex..<text.endIndex
            while let match = text.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: remaining,
                locale: .current
            ) {
                if !matches.contains(where: { $0.overlaps(match) }) {
                    matches.append(match)
                }
                guard match.upperBound < text.endIndex else { break }
                remaining = match.upperBound..<text.endIndex
            }
        }
        return matches.sorted { $0.lowerBound < $1.lowerBound }
    }
}
