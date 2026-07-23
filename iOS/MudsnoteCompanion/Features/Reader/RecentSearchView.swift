import SwiftUI
import ImageIO
import UIKit

private struct NotesListSearchTaskID: Hashable {
    var query: String
    var libraryRevision: Int
}

private enum HomeTimelineEntry: Identifiable {
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
}

private struct HomeTimelineSection: Identifiable {
    var id: String
    var title: String?
    var entries: [HomeTimelineEntry]
}

private struct HomeTimelineProjection {
    var sections: [HomeTimelineSection] = []
    var entryCount = 0
    var smartFolderCounts: [UUID: Int] = [:]
}

private final class DirectoryHapticFeedback {
    private let generator = UIImpactFeedbackGenerator(style: .medium)
    private var isPrepared = false

    func prepare() {
        guard !isPrepared else { return }
        generator.prepare()
        isPrepared = true
    }

    func impact() {
        generator.impactOccurred(intensity: 1)
        isPrepared = false
    }

    func cancel() {
        isPrepared = false
    }
}

private extension View {
    @ViewBuilder
    func homeNavigationSubtitle(_ subtitle: String?) -> some View {
        if #available(iOS 26.0, *), let subtitle {
            navigationSubtitle(subtitle)
        } else {
            self
        }
    }

    @ViewBuilder
    func homeTopScrollEdgeEffect() -> some View {
        if #available(iOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}

struct LibraryHomeView: View {
    private struct SearchTaskID: Hashable {
        var query: String
        var scope: MarkdownSearchScope
        var libraryRevision: Int
    }

    @EnvironmentObject private var appModel: AppModel
    @State private var isSearchFocused = false
    @State private var searchQuery = ""
    @State private var searchScope = MarkdownSearchScope.all
    @State private var searchSuggestion: NotesSearchSuggestion?
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var isManagingFolders = false
    @State private var smartFolderEditor: SmartFolderDefinition?
    @State private var smartFolderToDelete: SmartFolderDefinition?
    @State private var isDirectoryPresented = false
    @State private var directoryDragOffset: CGFloat = 0
    @State private var directoryHapticFeedback = DirectoryHapticFeedback()
    @State private var directoryPanelWidth: CGFloat = 360
    @State private var expandedDirectoryPaths = Set<String>()
    @State private var homeTimelineProjection = HomeTimelineProjection()
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
            homeContent
                .allowsHitTesting(directoryReveal(width: directoryPanelWidth) == 0)
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { updateDirectoryWidth(proxy.size.width) }
                            .onChange(of: proxy.size.width) { _, width in
                                updateDirectoryWidth(width)
                            }
                    }
                }
                .overlay(alignment: .leading) {
                    directoryOverlay(width: directoryPanelWidth)
            }
            .background(NotesCloneColors.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .homeNavigationSubtitle(homeNavigationSubtitle)
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
                isDirectoryPresented = false
                directoryDragOffset = 0
                finishSelectingHomeNotes()
            }
            .onAppear {
                refreshHomeTimelineProjection()
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
                refreshHomeTimelineProjection()
            }
            .onChange(of: sortDirectionRawValue) { _, _ in
                refreshHomeTimelineProjection()
            }
            .onChange(of: groupByDate) { _, _ in
                refreshHomeTimelineProjection()
            }
            .task(id: SearchTaskID(
                query: searchQuery,
                scope: searchScope,
                libraryRevision: appModel.libraryRevision
            )) {
                let trimmed = normalizedSearchQuery
                guard !trimmed.isEmpty else {
                    appModel.clearSearch()
                    return
                }
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                await appModel.searchLibrary(query: trimmed, scope: searchScope)
            }
            .toolbar {
                if isDirectoryPresented {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            newFolderName = ""
                            isCreatingFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                        }
                        .accessibilityLabel("New Folder")
                        .accessibilityIdentifier("new-folder-button")
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
                    ToolbarItem(placement: .topBarLeading) {
                        Button(allHomeEntriesSelected ? "Deselect All" : "Select All") {
                            toggleAllHomeEntries()
                        }
                        .accessibilityIdentifier("toggle-select-all-home-notes")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { finishSelectingHomeNotes() }
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
                        newNote: {
                            isSearchFocused = false
                            appModel.createNote()
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
    }

    @ViewBuilder
    private var homeContent: some View {
        if showsSearchExperience {
            ScrollView {
                searchSection
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(TapGesture().onEnded {
                if isSearchFocused { isSearchFocused = false }
            })
        } else {
            homeCardStream
        }
    }

    private var homeCardStream: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                if appModel.isInitialLibraryLoading, homeTimelineProjection.sections.isEmpty {
                    ProgressView("Loading Notes…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if homeTimelineProjection.sections.isEmpty {
                    ContentUnavailableView(
                        "No Notes",
                        systemImage: "note.text",
                        description: Text("Create a note or swipe right to open your folders.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
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
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .homeTopScrollEdgeEffect()
        .accessibilityIdentifier(viewStyle == .gallery ? "home-note-gallery" : "home-note-list")
    }

    private func makeHomeTimelineProjection() -> HomeTimelineProjection {
        let unsortedEntries = (
            appModel.libraryFiles
                .filter { $0.relativePath != "Inbox.md" }
                .map(HomeTimelineEntry.file)
                + appModel.inboxItems.map(HomeTimelineEntry.memo)
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

        var sections: [HomeTimelineSection] = []
        if !groupByDate || sortOrder == .title {
            if !entries.isEmpty {
                sections = [HomeTimelineSection(id: "notes", title: nil, entries: entries)]
            }
        } else {
            for entry in entries {
                let bucket = NoteListPresentation.dateBucket(
                    for: entry.date,
                    now: Date(),
                    calendar: .autoupdatingCurrent
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
        }
        let smartFolderCounts = Dictionary(uniqueKeysWithValues: appModel.smartFolders.map { definition in
            let count = appModel.libraryFiles.lazy.filter {
                $0.relativePath != "Inbox.md" && definition.matches(file: $0)
            }.count + appModel.inboxItems.lazy.filter {
                definition.matches(memo: $0)
            }.count
            return (definition.id, count)
        })
        return HomeTimelineProjection(
            sections: sections,
            entryCount: entries.count,
            smartFolderCounts: smartFolderCounts
        )
    }

    private func refreshHomeTimelineProjection() {
        homeTimelineProjection = makeHomeTimelineProjection()
    }

    private func updateDirectoryWidth(_ availableWidth: CGFloat) {
        let width = min(availableWidth * 0.86, 360)
        guard abs(width - directoryPanelWidth) > 0.5 else { return }
        directoryPanelWidth = width
    }

    private func directoryOverlay(width: CGFloat) -> some View {
        let reveal = directoryReveal(width: width)
        return ZStack(alignment: .leading) {
            if !isDirectoryPresented {
                Color.clear
                    .frame(width: 32)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(directoryDragGesture(width: width))
                    .accessibilityElement()
                    .accessibilityLabel("Swipe right for folders")
                    .accessibilityIdentifier("directory-swipe-edge")
            }

            if reveal > 0 {
                Color.black
                    .opacity(0.42 * reveal / max(width, 1))
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { closeDirectory() }
                    .gesture(directoryDragGesture(width: width))
                    .accessibilityElement()
                    .accessibilityLabel("Close Folders")
                    .accessibilityIdentifier("directory-backdrop")

                directoryPanel(width: width)
                    .offset(x: -width + reveal)
                    .highPriorityGesture(directoryDragGesture(width: width))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var navigationTitle: String {
        if isDirectoryPresented { return String(localized: "Folders") }
        if isSelectingNotes {
            return String(
                format: String(localized: "notes.selected.format"),
                locale: .current,
                selectedHomeEntryIDs.count
            )
        }
        return String(localized: "Notes")
    }

    private var homeNavigationSubtitle: String? {
        guard !isDirectoryPresented, !isSelectingNotes else { return nil }
        return String(
            format: String(localized: "notes.count.format"),
            locale: .current,
            homeTimelineProjection.entryCount
        )
    }

    private var allHomeEntryIDs: Set<String> {
        Set(homeTimelineProjection.sections.flatMap(\.entries).map(\.id))
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
        let selected = homeTimelineProjection.sections
            .flatMap(\.entries)
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
            .padding(.top, 8)
            .padding(.bottom, 110)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(MudsnoteColors.canvas)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(MudsnoteColors.line)
                .frame(width: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 12, x: 5)
        .accessibilityIdentifier("directory-drawer")
    }

    private func directoryReveal(width: CGFloat) -> CGFloat {
        if isDirectoryPresented {
            return min(width, max(0, width + directoryDragOffset))
        }
        return min(width, max(0, directoryDragOffset))
    }

    private func directoryDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                directoryHapticFeedback.prepare()
                if isDirectoryPresented {
                    directoryDragOffset = min(0, value.translation.width)
                } else {
                    directoryDragOffset = max(0, value.translation.width)
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let predicted = value.predictedEndTranslation.width
                let wasPresented = isDirectoryPresented
                let shouldOpen: Bool
                if isDirectoryPresented {
                    shouldOpen = horizontal > -width * 0.18 && predicted > -width * 0.45
                } else {
                    shouldOpen = horizontal > width * 0.18 || predicted > width * 0.45
                }
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.92)) {
                    isDirectoryPresented = shouldOpen
                    directoryDragOffset = 0
                }
                if shouldOpen != wasPresented {
                    directoryHapticFeedback.impact()
                } else {
                    directoryHapticFeedback.cancel()
                }
            }
    }

    private func closeDirectory() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.92)) {
            isDirectoryPresented = false
            directoryDragOffset = 0
            isManagingFolders = false
        }
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Folders")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(MudsnoteColors.text)

                    Spacer(minLength: 0)

                    NavigationLink {
                        SettingsRulesView(chooseFolder: chooseFolder)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MudsnoteColors.text)
                            .frame(width: 34, height: 34)
                            .background(MudsnoteColors.card, in: Circle())
                            .overlay {
                                Circle().stroke(MudsnoteColors.line, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Settings")
                    .accessibilityIdentifier("settings-link")
                }
                .padding(.horizontal, 2)

                notesCard {
                    NavigationLink {
                        InboxStreamView()
                    } label: {
                        NotesFolderRow(
                            title: "000-inbox",
                            systemImage: "tray",
                            count: appModel.mergedInboxCount
                        )
                    }
                    .accessibilityIdentifier("inbox-link")

                    ForEach(appModel.visibleLibraryFolders) { folder in
                        DirectoryFolderTree(
                            folder: folder,
                            depth: 0,
                            isManaging: isManagingFolders,
                            expandedPaths: $expandedDirectoryPaths,
                            systemImage: folderSystemImage
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                NotesSectionHeader(title: String(localized: "Library"))

                notesCard {
                    NavigationLink {
                        AttachmentLibraryView()
                    } label: {
                        NotesFolderRow(title: String(localized: "Attachments"), systemImage: "paperclip", count: appModel.librarySummary.attachmentCount)
                    }
                    .accessibilityIdentifier("attachments-link")

                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        NotesFolderRow(
                            title: String(localized: "Recently Deleted"),
                            systemImage: "trash",
                            count: appModel.librarySummary.recentlyDeletedCount
                        )
                    }
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
            NotesSectionHeader(title: String(localized: "Tags"))
            NavigationLink {
                TagsBrowserView()
            } label: {
                NotesFolderRow(
                    title: String(localized: "All Tags"),
                    systemImage: "number",
                    count: appModel.tagSummaries.count
                )
            }
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                    .stroke(MudsnoteColors.line, lineWidth: 1)
            }
            .accessibilityIdentifier("all-tags-link")

            FlowLayout(spacing: 10, rowSpacing: 10) {
                ForEach(appModel.tagSummaries) { tag in
                    NavigationLink {
                        TagNotesListView(tag: tag.name)
                    } label: {
                        TagChip(title: tag.name)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tag-link-\(tag.name)")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
            .overlay {
                RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                    .stroke(MudsnoteColors.line, lineWidth: 1)
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Search Scope", selection: $searchScope) {
                ForEach(MarkdownSearchScope.allCases) { scope in
                    Text(scope.label).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("search-scope-picker")

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
        )
    }

    private var searchIsPending: Bool {
        appModel.isSearching
            || appModel.completedSearchQuery != normalizedSearchQuery
            || appModel.completedSearchScope != searchScope
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

private struct DirectoryFolderTree: View {
    var folder: LibraryFolderNode
    var depth: Int
    var isManaging: Bool
    @Binding var expandedPaths: Set<String>
    var systemImage: (LibraryFolderNode) -> String

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
                        systemImage: systemImage
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
            NavigationLink {
                LibraryFolderView(folder: folder)
            } label: {
                NotesFolderRow(
                    title: folder.name,
                    systemImage: systemImage(folder),
                    count: folder.totalNoteCount,
                    showsChevron: false,
                    trailingAccessoryWidth: trailingAccessoryWidth,
                    indentation: CGFloat(depth) * 18
                )
            }
            .accessibilityIdentifier("folder-row-\(folder.relativePath)")
            .modifier(FolderLifecycleActions(folder: folder))
        }
    }
}

private struct SearchResultRow: View {
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

private struct SearchHighlightedText: View {
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

enum NoteSortOrder: String, CaseIterable, Identifiable {
    case modified
    case created
    case title

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .modified: "Date Edited"
        case .created: "Date Created"
        case .title: "Title"
        }
    }

    var dateBasis: NoteDateBasis {
        self == .created ? .created : .modified
    }
}

enum NoteSortDirection: String, CaseIterable, Identifiable {
    case standard
    case reversed

    var id: String { rawValue }

    func label(for order: NoteSortOrder) -> LocalizedStringKey {
        switch (order, self) {
        case (.title, .standard): "Ascending"
        case (.title, .reversed): "Descending"
        case (_, .standard): "Newest First"
        case (_, .reversed): "Oldest First"
        }
    }
}

enum NoteViewStyle: String, CaseIterable, Identifiable {
    case list
    case gallery

    var id: String { rawValue }
}

enum NoteDateBasis {
    case modified
    case created

    func date(for file: RecentMarkdownFile) -> Date {
        if self == .created, file.createdAt != .distantPast {
            return file.createdAt
        }
        return file.modifiedAt
    }
}

struct NoteDateSection: Identifiable, Equatable {
    var id: String
    var title: String?
    var files: [RecentMarkdownFile]
}

enum NoteListPresentation {
    static func sorted(
        _ files: [RecentMarkdownFile],
        by order: NoteSortOrder,
        direction: NoteSortDirection = .standard
    ) -> [RecentMarkdownFile] {
        files.sorted { lhs, rhs in
            let orderedAscending: Bool
            switch order {
            case .modified:
                if lhs.modifiedAt != rhs.modifiedAt {
                    orderedAscending = lhs.modifiedAt > rhs.modifiedAt
                    return direction == .standard ? orderedAscending : !orderedAscending
                }
            case .created:
                let lhsDate = lhs.createdAt == .distantPast ? lhs.modifiedAt : lhs.createdAt
                let rhsDate = rhs.createdAt == .distantPast ? rhs.modifiedAt : rhs.createdAt
                if lhsDate != rhsDate {
                    orderedAscending = lhsDate > rhsDate
                    return direction == .standard ? orderedAscending : !orderedAscending
                }
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame {
                    orderedAscending = comparison == .orderedAscending
                    return direction == .standard ? orderedAscending : !orderedAscending
                }
            }
            orderedAscending = lhs.relativePath.localizedStandardCompare(rhs.relativePath)
                == .orderedAscending
            return direction == .standard ? orderedAscending : !orderedAscending
        }
    }

    static func sections(
        for files: [RecentMarkdownFile],
        sortedBy order: NoteSortOrder,
        direction: NoteSortDirection = .standard,
        groupByDate: Bool,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [NoteDateSection] {
        let ordered = sorted(files, by: order, direction: direction)
        guard groupByDate, order != .title, !ordered.isEmpty else {
            return ordered.isEmpty ? [] : [NoteDateSection(id: "notes", title: nil, files: ordered)]
        }

        var sections: [NoteDateSection] = []
        for file in ordered {
            let date = order.dateBasis.date(for: file)
            let bucket = dateBucket(for: date, now: now, calendar: calendar)
            if sections.last?.id == bucket.id {
                sections[sections.count - 1].files.append(file)
            } else {
                sections.append(NoteDateSection(id: bucket.id, title: bucket.title, files: [file]))
            }
        }
        return sections
    }

    static func dateBucket(
        for date: Date,
        now: Date,
        calendar: Calendar
    ) -> (id: String, title: String) {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        if day >= today {
            return ("today", String(localized: "Today"))
        }
        if day >= (calendar.date(byAdding: .day, value: -1, to: today) ?? today) {
            return ("yesterday", String(localized: "Yesterday"))
        }
        if day >= (calendar.date(byAdding: .day, value: -7, to: today) ?? today) {
            return ("previous-7", String(localized: "Previous 7 Days"))
        }
        if day >= (calendar.date(byAdding: .day, value: -30, to: today) ?? today) {
            return ("previous-30", String(localized: "Previous 30 Days"))
        }
        let components = calendar.dateComponents([.year, .month], from: day)
        let id = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
        return (id, day.formatted(.dateTime.month(.wide).year()))
    }
}

private struct NoteListOptionsMenu: View {
    @Binding var viewStyleRawValue: String
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool
    var selectNotes: () -> Void

    var body: some View {
        Menu {
            Button(action: selectNotes) {
                Label("Select Notes", systemImage: "checkmark.circle")
            }
            Divider()
            NoteViewStyleMenuContent(viewStyleRawValue: $viewStyleRawValue)
            Divider()
            NoteListSortMenuContent(
                sortOrderRawValue: $sortOrderRawValue,
                sortDirectionRawValue: $sortDirectionRawValue,
                groupByDate: $groupByDate
            )
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Sort Notes")
        .accessibilityIdentifier("note-list-options")
    }
}

private struct HomeNoteOptionsMenu: View {
    @Binding var viewStyleRawValue: String
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool
    var selectNotes: () -> Void
    var viewAttachments: () -> Void

    var body: some View {
        HomeNoteOptionsButton(
            viewStyleRawValue: $viewStyleRawValue,
            sortOrderRawValue: $sortOrderRawValue,
            sortDirectionRawValue: $sortDirectionRawValue,
            groupByDate: $groupByDate,
            selectNotes: selectNotes,
            viewAttachments: viewAttachments
        )
        .frame(width: 28, height: 28)
    }
}

private struct HomeNoteOptionsButton: UIViewRepresentable {
    @Binding var viewStyleRawValue: String
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool
    var selectNotes: () -> Void
    var viewAttachments: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(
            UIImage(
                systemName: "ellipsis",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            ),
            for: .normal
        )
        button.tintColor = .label
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = String(localized: "More")
        button.accessibilityIdentifier = "home-note-options"
        button.menu = context.coordinator.makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        button.menu = context.coordinator.makeMenu()
    }

    @MainActor
    final class Coordinator {
        var parent: HomeNoteOptionsButton

        init(parent: HomeNoteOptionsButton) {
            self.parent = parent
        }

        func makeMenu() -> UIMenu {
            let viewStyle = NoteViewStyle(rawValue: parent.viewStyleRawValue) ?? .gallery
            let sortOrder = NoteSortOrder(rawValue: parent.sortOrderRawValue) ?? .modified
            let sortDirection = NoteSortDirection(rawValue: parent.sortDirectionRawValue) ?? .standard

            let viewAction = UIAction(
                title: String(localized: viewStyle == .gallery ? "View as List" : "View as Cards"),
                image: UIImage(systemName: viewStyle == .gallery ? "list.bullet" : "square.grid.2x2")
            ) { [weak self] _ in
                self?.parent.viewStyleRawValue = viewStyle == .gallery
                    ? NoteViewStyle.list.rawValue
                    : NoteViewStyle.gallery.rawValue
            }
            let viewGroup = UIMenu(options: .displayInline, children: [viewAction])

            let selectAction = UIAction(
                title: String(localized: "Select Notes"),
                image: UIImage(systemName: "checkmark.circle")
            ) { [weak self] _ in self?.parent.selectNotes() }

            let sortMenu = UIMenu(
                title: String(localized: "Sort By"),
                subtitle: sortSummary(sortOrder),
                image: UIImage(systemName: "arrow.up.arrow.down"),
                children: [sortOrderMenu(selected: sortOrder), sortDirectionMenu(
                    selected: sortDirection,
                    order: sortOrder
                )]
            )
            let groupMenu = UIMenu(
                title: String(localized: "Group By Date"),
                subtitle: parent.groupByDate ? String(localized: "On") : String(localized: "Off"),
                image: UIImage(systemName: "calendar"),
                children: groupActions(disabled: sortOrder == .title)
            )
            let attachmentsAction = UIAction(
                title: String(localized: "View Attachments"),
                image: UIImage(systemName: "paperclip")
            ) { [weak self] _ in self?.parent.viewAttachments() }
            let commandGroup = UIMenu(
                options: .displayInline,
                children: [selectAction, sortMenu, groupMenu, attachmentsAction]
            )
            return UIMenu(children: [viewGroup, commandGroup])
        }

        private func sortOrderMenu(selected: NoteSortOrder) -> UIMenu {
            let actions = NoteSortOrder.allCases.map { order in
                UIAction(
                    title: sortOrderTitle(order),
                    state: order == selected ? .on : .off
                ) { [weak self] _ in self?.parent.sortOrderRawValue = order.rawValue }
            }
            return UIMenu(options: .displayInline, children: actions)
        }

        private func sortDirectionMenu(
            selected: NoteSortDirection,
            order: NoteSortOrder
        ) -> UIMenu {
            let actions = NoteSortDirection.allCases.map { direction in
                UIAction(
                    title: sortDirectionTitle(direction, order: order),
                    state: direction == selected ? .on : .off
                ) { [weak self] _ in
                    self?.parent.sortDirectionRawValue = direction.rawValue
                }
            }
            return UIMenu(options: .displayInline, children: actions)
        }

        private func groupActions(disabled: Bool) -> [UIMenuElement] {
            [true, false].map { value in
                UIAction(
                    title: value ? String(localized: "On") : String(localized: "Off"),
                    attributes: disabled ? .disabled : [],
                    state: parent.groupByDate == value ? .on : .off
                ) { [weak self] _ in self?.parent.groupByDate = value }
            }
        }

        private func sortSummary(_ order: NoteSortOrder) -> String {
            switch order {
            case .modified: String(localized: "Default (Date Edited)")
            case .created: String(localized: "Date Created")
            case .title: String(localized: "Title")
            }
        }

        private func sortOrderTitle(_ order: NoteSortOrder) -> String {
            switch order {
            case .modified: String(localized: "Date Edited")
            case .created: String(localized: "Date Created")
            case .title: String(localized: "Title")
            }
        }

        private func sortDirectionTitle(
            _ direction: NoteSortDirection,
            order: NoteSortOrder
        ) -> String {
            switch (order, direction) {
            case (.title, .standard): String(localized: "Ascending")
            case (.title, .reversed): String(localized: "Descending")
            case (_, .standard): String(localized: "Newest First")
            case (_, .reversed): String(localized: "Oldest First")
            }
        }
    }
}

private struct NoteViewStyleMenuContent: View {
    @Binding var viewStyleRawValue: String

    private var viewStyle: NoteViewStyle {
        NoteViewStyle(rawValue: viewStyleRawValue) ?? .list
    }

    var body: some View {
        Button {
            viewStyleRawValue = viewStyle == .list
                ? NoteViewStyle.gallery.rawValue
                : NoteViewStyle.list.rawValue
        } label: {
            Label(
                viewStyle == .list ? "View as Gallery" : "View as List",
                systemImage: viewStyle == .list ? "square.grid.2x2" : "list.bullet"
            )
        }
        .accessibilityIdentifier("toggle-note-view-style")
    }
}

private struct NoteListSortMenuContent: View {
    @Binding var sortOrderRawValue: String
    @Binding var sortDirectionRawValue: String
    @Binding var groupByDate: Bool

    private var sortOrder: NoteSortOrder {
        NoteSortOrder(rawValue: sortOrderRawValue) ?? .modified
    }

    var body: some View {
        Picker("Sort By", selection: $sortOrderRawValue) {
            ForEach(NoteSortOrder.allCases) { order in
                Text(order.label).tag(order.rawValue)
            }
        }
        Picker("Order", selection: $sortDirectionRawValue) {
            ForEach(NoteSortDirection.allCases) { direction in
                Text(direction.label(for: sortOrder)).tag(direction.rawValue)
            }
        }
        Toggle("Group By Date", isOn: $groupByDate)
            .disabled(sortOrder == .title)
    }
}

private struct NoteListSearchResultsView: View {
    var query: String
    var results: [MarkdownSearchResult]
    var isPending: Bool
    var open: (MarkdownSearchResult) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if isPending {
                    ProgressView("Searching…")
                        .frame(maxWidth: .infinity)
                        .padding(32)
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    ForEach(results) { result in
                        Button {
                            open(result)
                        } label: {
                            SearchResultRow(result: result, query: query)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("list-search-result-\(result.id)")

                        if result.id != results.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
            .background(
                results.isEmpty ? Color.clear : MudsnoteColors.card,
                in: RoundedRectangle(cornerRadius: MudsnoteRadius.card)
            )
            .overlay {
                if !results.isEmpty {
                    RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                        .stroke(MudsnoteColors.line, lineWidth: 1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .scrollDismissesKeyboard(.interactively)
        .accessibilityIdentifier("note-list-search-results")
    }
}

struct NotesListCountLabel: View {
    var count: Int

    var body: some View {
        Text(
            String.localizedStringWithFormat(
                String(localized: "notes.count.format"),
                count
            )
        )
        .font(.subheadline)
        .foregroundStyle(MudsnoteColors.muted)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .accessibilityIdentifier("note-list-count")
    }
}

struct NotesListSectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(.title3, design: .rounded, weight: .bold))
            .foregroundStyle(MudsnoteColors.text)
            .textCase(nil)
            .padding(.bottom, 4)
            .listRowInsets(
                EdgeInsets(top: 0, leading: 0, bottom: 4, trailing: 0)
            )
            .accessibilityAddTraits(.isHeader)
    }
}

struct FolderNotesListView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isSearchFocused = false
    @AppStorage("mudsnote.ios.noteViewStyle") private var viewStyleRawValue = NoteViewStyle.list.rawValue
    @AppStorage("mudsnote.ios.noteSortOrder") private var sortOrderRawValue = NoteSortOrder.modified.rawValue
    @AppStorage("mudsnote.ios.noteSortDirection") private var sortDirectionRawValue = NoteSortDirection.standard.rawValue
    @AppStorage("mudsnote.ios.groupNotesByDate") private var groupByDate = true
    @State private var isSelecting = false
    @State private var selectedPaths = Set<String>()
    @State private var searchQuery = ""
    var title: String
    var scope: LibraryFileScope

    private var files: [RecentMarkdownFile] {
        scope.files(from: appModel.libraryFiles)
    }

    private var sortOrder: NoteSortOrder {
        NoteSortOrder(rawValue: sortOrderRawValue) ?? .modified
    }
    private var sortDirection: NoteSortDirection {
        NoteSortDirection(rawValue: sortDirectionRawValue) ?? .standard
    }
    private var viewStyle: NoteViewStyle {
        NoteViewStyle(rawValue: viewStyleRawValue) ?? .list
    }
    private var pinnedFiles: [RecentMarkdownFile] {
        NoteListPresentation.sorted(
            files.filter(\.isPinned),
            by: sortOrder,
            direction: sortDirection
        )
    }
    private var otherSections: [NoteDateSection] {
        NoteListPresentation.sections(
            for: files.filter { !$0.isPinned },
            sortedBy: sortOrder,
            direction: sortDirection,
            groupByDate: groupByDate
        )
    }
    private var selectedFiles: [RecentMarkdownFile] {
        files.filter { selectedPaths.contains($0.relativePath) }
    }
    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var scopedSearchResults: [MarkdownSearchResult] {
        appModel.searchResults.filter(scope.contains)
    }
    private var searchIsPending: Bool {
        appModel.isSearching || appModel.completedSearchQuery != normalizedSearchQuery
    }

    var body: some View {
        Group {
            if !normalizedSearchQuery.isEmpty {
                NoteListSearchResultsView(
                    query: normalizedSearchQuery,
                    results: scopedSearchResults,
                    isPending: searchIsPending
                ) { result in
                    isSearchFocused = false
                    appModel.openSearchResult(result)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    NotesListCountLabel(count: files.count)

                    if viewStyle == .gallery, !files.isEmpty {
                        noteGallery
                    } else {
                        List {
                            if files.isEmpty {
                                Text("No Notes")
                                    .foregroundStyle(MudsnoteColors.muted)
                            } else {
                                if !pinnedFiles.isEmpty {
                                    Section {
                                        ForEach(pinnedFiles) { file in
                                            noteRow(file)
                                        }
                                    } header: {
                                        NotesListSectionHeader(title: String(localized: "Pinned"))
                                    }
                                }
                                ForEach(otherSections) { section in
                                    Section {
                                        ForEach(section.files) { file in
                                            noteRow(file)
                                        }
                                    } header: {
                                        if let title = section.title {
                                            NotesListSectionHeader(title: title)
                                        } else if !pinnedFiles.isEmpty {
                                            NotesListSectionHeader(title: String(localized: "Notes"))
                                        }
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .listSectionSpacing(22)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
        .background(MudsnoteColors.canvas)
        .refreshable {
            await appModel.refreshInbox()
        }
        .navigationTitle(
            isSelecting
                ? String(
                    format: String(localized: "notes.selected.format"),
                    locale: .current,
                    selectedPaths.count
                )
                : title
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelecting {
                    Button(selectedPaths.count == files.count ? "Deselect All" : "Select All") {
                        if selectedPaths.count == files.count {
                            selectedPaths.removeAll()
                        } else {
                            selectedPaths = Set(files.map(\.relativePath))
                        }
                    }
                    .accessibilityIdentifier("toggle-select-all-notes")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if isSelecting {
                    Button("Done") { finishSelecting() }
                        .accessibilityIdentifier("finish-note-selection")
                } else {
                    NoteListOptionsMenu(
                        viewStyleRawValue: $viewStyleRawValue,
                        sortOrderRawValue: $sortOrderRawValue,
                        sortDirectionRawValue: $sortDirectionRawValue,
                        groupByDate: $groupByDate,
                        selectNotes: { isSelecting = true }
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                SelectedNotesActionBar(
                    files: selectedFiles,
                    destinations: appModel.allFolders,
                    finish: finishSelecting
                )
            }
        }
        .toolbar {
            listBottomToolbar
        }
        .notesNativeToolbarSearch(
            text: $searchQuery,
            isPresented: $isSearchFocused
        )
        .task(id: NotesListSearchTaskID(
            query: normalizedSearchQuery,
            libraryRevision: appModel.libraryRevision
        )) {
            guard !normalizedSearchQuery.isEmpty else {
                appModel.clearSearch()
                return
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await appModel.searchLibrary(query: normalizedSearchQuery)
        }
        .onDisappear {
            isSearchFocused = false
            appModel.clearSearch()
        }
        .onChange(of: files.map(\.relativePath)) { _, paths in
            selectedPaths.formIntersection(paths)
        }
    }

    @ToolbarContentBuilder
    private var listBottomToolbar: some ToolbarContent {
        if !isSelecting {
            NotesBottomCommandBar(
                searchText: $searchQuery,
                searchFocused: $isSearchFocused,
                newNote: {
                    isSearchFocused = false
                    appModel.createNote(inFolder: scope.newNoteFolder)
                }
            )
        }
    }

    private var noteGallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                if !pinnedFiles.isEmpty {
                    NoteGallerySection(
                        title: String(localized: "Pinned"),
                        files: pinnedFiles,
                        dateBasis: sortOrder.dateBasis,
                        isSelecting: isSelecting,
                        selectedPaths: selectedPaths,
                        toggleSelection: toggleSelection
                    )
                }
                ForEach(otherSections) { section in
                    NoteGallerySection(
                        title: section.title ?? (!pinnedFiles.isEmpty ? String(localized: "Notes") : nil),
                        files: section.files,
                        dateBasis: sortOrder.dateBasis,
                        isSelecting: isSelecting,
                        selectedPaths: selectedPaths,
                        toggleSelection: toggleSelection
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("note-gallery")
    }

    @ViewBuilder
    private func noteRow(_ file: RecentMarkdownFile) -> some View {
        if isSelecting {
            SelectableNoteFileRow(
                file: file,
                dateBasis: sortOrder.dateBasis,
                showsFolder: scope.newNoteFolder == nil,
                isSelected: selectedPaths.contains(file.relativePath)
            ) {
                if !selectedPaths.insert(file.relativePath).inserted {
                    selectedPaths.remove(file.relativePath)
                }
            }
        } else {
            NoteFileButton(
                file: file,
                dateBasis: sortOrder.dateBasis,
                showsFolder: scope.newNoteFolder == nil
            )
        }
    }

    private func finishSelecting() {
        selectedPaths.removeAll()
        isSelecting = false
    }

    private func toggleSelection(_ file: RecentMarkdownFile) {
        if !selectedPaths.insert(file.relativePath).inserted {
            selectedPaths.remove(file.relativePath)
        }
    }
}

enum LibraryFileScope {
    case all
    case pathPrefix(String)

    func files(from inventory: [RecentMarkdownFile]) -> [RecentMarkdownFile] {
        switch self {
        case .all:
            inventory
        case .pathPrefix(let prefix):
            inventory.filter { $0.relativePath.hasPrefix(prefix) }
        }
    }

    func contains(_ result: MarkdownSearchResult) -> Bool {
        switch (self, result.destination) {
        case (.all, _):
            true
        case (.pathPrefix(let prefix), .file(let file)):
            file.relativePath.hasPrefix(prefix)
        case (.pathPrefix, .memo):
            false
        }
    }

    var newNoteFolder: String? {
        switch self {
        case .all:
            nil
        case .pathPrefix(let prefix):
            prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
    }
}

struct LibraryFolderView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSearchFocused = false
    var folder: LibraryFolderNode
    @State private var isCreatingFolder = false
    @State private var isRenamingFolder = false
    @State private var isConfirmingDelete = false
    @State private var folderName = ""
    @State private var isSelecting = false
    @State private var selectedPaths = Set<String>()
    @State private var searchQuery = ""
    @AppStorage("mudsnote.ios.noteViewStyle") private var viewStyleRawValue = NoteViewStyle.list.rawValue
    @AppStorage("mudsnote.ios.noteSortOrder") private var sortOrderRawValue = NoteSortOrder.modified.rawValue
    @AppStorage("mudsnote.ios.noteSortDirection") private var sortDirectionRawValue = NoteSortDirection.standard.rawValue
    @AppStorage("mudsnote.ios.groupNotesByDate") private var groupByDate = true

    private var currentFolder: LibraryFolderNode {
        appModel.allFolders.first { $0.id == folder.id } ?? folder
    }

    private var directFiles: [RecentMarkdownFile] {
        appModel.libraryFiles.filter {
            ($0.relativePath as NSString).deletingLastPathComponent == folder.relativePath
        }
    }

    private var sortOrder: NoteSortOrder {
        NoteSortOrder(rawValue: sortOrderRawValue) ?? .modified
    }
    private var sortDirection: NoteSortDirection {
        NoteSortDirection(rawValue: sortDirectionRawValue) ?? .standard
    }
    private var viewStyle: NoteViewStyle {
        NoteViewStyle(rawValue: viewStyleRawValue) ?? .list
    }
    private var pinnedFiles: [RecentMarkdownFile] {
        NoteListPresentation.sorted(
            directFiles.filter(\.isPinned),
            by: sortOrder,
            direction: sortDirection
        )
    }
    private var otherSections: [NoteDateSection] {
        NoteListPresentation.sections(
            for: directFiles.filter { !$0.isPinned },
            sortedBy: sortOrder,
            direction: sortDirection,
            groupByDate: groupByDate
        )
    }
    private var moveDestinations: [LibraryFolderNode] {
        appModel.allFolders.filter {
            $0.relativePath != currentFolder.relativePath
                && !$0.relativePath.hasPrefix(currentFolder.relativePath + "/")
        }
    }
    private var selectedFiles: [RecentMarkdownFile] {
        directFiles.filter { selectedPaths.contains($0.relativePath) }
    }
    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var scopedSearchResults: [MarkdownSearchResult] {
        let directPaths = Set(directFiles.map(\.relativePath))
        return appModel.searchResults.filter { result in
            guard case .file(let file) = result.destination else { return false }
            return directPaths.contains(file.relativePath)
        }
    }
    private var searchIsPending: Bool {
        appModel.isSearching || appModel.completedSearchQuery != normalizedSearchQuery
    }

    var body: some View {
        Group {
            if !normalizedSearchQuery.isEmpty {
                NoteListSearchResultsView(
                    query: normalizedSearchQuery,
                    results: scopedSearchResults,
                    isPending: searchIsPending
                ) { result in
                    isSearchFocused = false
                    appModel.openSearchResult(result)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    NotesListCountLabel(count: directFiles.count)

                    if viewStyle == .gallery {
                        folderGallery
                    } else {
                        List {
                            if !isSelecting {
                                ForEach(currentFolder.children) { child in
                                    NavigationLink {
                                        LibraryFolderView(folder: child)
                                    } label: {
                                        LibraryFolderRow(
                                            title: child.name,
                                            subtitle: child.relativePath,
                                            systemImage: "folder.fill",
                                            count: child.totalNoteCount
                                        )
                                    }
                                    .accessibilityIdentifier("folder-row-\(child.relativePath)")
                                    .modifier(FolderLifecycleActions(folder: child))
                                }
                            }

                            if !pinnedFiles.isEmpty {
                                Section {
                                    ForEach(pinnedFiles) { file in
                                        noteRow(file)
                                    }
                                } header: {
                                    NotesListSectionHeader(title: String(localized: "Pinned"))
                                }
                            }
                            ForEach(otherSections) { section in
                                Section {
                                    ForEach(section.files) { file in
                                        noteRow(file)
                                    }
                                } header: {
                                    if let title = section.title {
                                        NotesListSectionHeader(title: title)
                                    } else if !pinnedFiles.isEmpty {
                                        NotesListSectionHeader(title: String(localized: "Notes"))
                                    }
                                }
                            }

                            if currentFolder.children.isEmpty, directFiles.isEmpty {
                                ContentUnavailableView("No Notes", systemImage: "folder")
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.insetGrouped)
                        .listSectionSpacing(22)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
        }
        .background(MudsnoteColors.canvas)
        .refreshable {
            await appModel.refreshInbox()
        }
        .navigationTitle(
            isSelecting
                ? String(
                    format: String(localized: "notes.selected.format"),
                    locale: .current,
                    selectedPaths.count
                )
                : currentFolder.name
        )
        .toolbar {
            folderNavigationToolbar
        }
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                SelectedNotesActionBar(
                    files: selectedFiles,
                    destinations: moveDestinations,
                    finish: finishSelecting
                )
            }
        }
        .toolbar {
            folderBottomToolbar
        }
        .notesNativeToolbarSearch(
            text: $searchQuery,
            isPresented: $isSearchFocused
        )
        .alert("New Folder", isPresented: $isCreatingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = folderName
                let parent = currentFolder.relativePath
                Task { _ = await appModel.createFolder(named: name, parent: parent) }
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Rename Folder", isPresented: $isRenamingFolder) {
            TextField("Folder Name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let name = folderName
                let target = currentFolder
                Task {
                    if await appModel.renameFolder(target, to: name) {
                        dismiss()
                    }
                }
            }
            .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Notes", role: .destructive) {
                let target = currentFolder
                Task {
                    if await appModel.deleteFolder(target) {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Notes in this folder will move to Recently Deleted. Other files will be preserved.")
        }
        .onChange(of: directFiles.map(\.relativePath)) { _, paths in
            selectedPaths.formIntersection(paths)
        }
        .task(id: NotesListSearchTaskID(
            query: normalizedSearchQuery,
            libraryRevision: appModel.libraryRevision
        )) {
            guard !normalizedSearchQuery.isEmpty else {
                appModel.clearSearch()
                return
            }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            await appModel.searchLibrary(query: normalizedSearchQuery)
        }
        .onDisappear {
            isSearchFocused = false
            appModel.clearSearch()
        }
    }

    @ToolbarContentBuilder
    private var folderNavigationToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button(selectedPaths.count == directFiles.count ? "Deselect All" : "Select All") {
                    toggleAllFolderNotesSelection()
                }
                .accessibilityIdentifier("toggle-select-all-notes")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                Button("Done") { finishSelecting() }
                    .accessibilityIdentifier("finish-note-selection")
            } else {
                folderActionsMenu
            }
        }
    }

    private var folderActionsMenu: some View {
        Menu {
            Button {
                isSelecting = true
            } label: {
                Label("Select Notes", systemImage: "checkmark.circle")
            }
            Divider()
            Button {
                folderName = ""
                isCreatingFolder = true
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Button {
                folderName = currentFolder.name
                isRenamingFolder = true
            } label: {
                Label("Rename Folder", systemImage: "pencil")
            }
            folderMoveMenu
            Button {
                appModel.createNote(inFolder: currentFolder.relativePath)
            } label: {
                Label("New Note", systemImage: "square.and.pencil")
            }
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
            Divider()
            NoteViewStyleMenuContent(viewStyleRawValue: $viewStyleRawValue)
            Divider()
            NoteListSortMenuContent(
                sortOrderRawValue: $sortOrderRawValue,
                sortDirectionRawValue: $sortDirectionRawValue,
                groupByDate: $groupByDate
            )
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Folder Actions")
        .accessibilityIdentifier("folder-actions")
    }

    private var folderMoveMenu: some View {
        Menu {
            if currentFolder.relativePath.contains("/") {
                Button {
                    moveCurrentFolder(to: nil)
                } label: {
                    Label("Top Level", systemImage: "tray")
                }
            }
            ForEach(moveDestinations) { destination in
                Button {
                    moveCurrentFolder(to: destination)
                } label: {
                    Label(destination.relativePath, systemImage: "folder")
                }
            }
        } label: {
            Label("Move Folder", systemImage: "folder.badge.arrow.forward")
        }
    }

    private func toggleAllFolderNotesSelection() {
        if selectedPaths.count == directFiles.count {
            selectedPaths.removeAll()
        } else {
            selectedPaths = Set(directFiles.map(\.relativePath))
        }
    }

    private func moveCurrentFolder(to destination: LibraryFolderNode?) {
        let target = currentFolder
        Task {
            let moved = await appModel.moveFolder(target, to: destination)
            if moved { dismiss() }
        }
    }

    @ToolbarContentBuilder
    private var folderBottomToolbar: some ToolbarContent {
        if !isSelecting {
            NotesBottomCommandBar(
                searchText: $searchQuery,
                searchFocused: $isSearchFocused,
                newNote: {
                    isSearchFocused = false
                    appModel.createNote(inFolder: currentFolder.relativePath)
                }
            )
        }
    }

    private var folderGallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22, pinnedViews: [.sectionHeaders]) {
                if !isSelecting, !currentFolder.children.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(currentFolder.children) { child in
                            NavigationLink {
                                LibraryFolderView(folder: child)
                            } label: {
                                LibraryFolderRow(
                                    title: child.name,
                                    subtitle: child.relativePath,
                                    systemImage: "folder.fill",
                                    count: child.totalNoteCount
                                )
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("folder-row-\(child.relativePath)")
                            .modifier(FolderLifecycleActions(folder: child))
                        }
                    }
                    .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(MudsnoteColors.line, lineWidth: 1)
                    }
                }

                if !pinnedFiles.isEmpty {
                    NoteGallerySection(
                        title: String(localized: "Pinned"),
                        files: pinnedFiles,
                        dateBasis: sortOrder.dateBasis,
                        isSelecting: isSelecting,
                        selectedPaths: selectedPaths,
                        toggleSelection: toggleSelection
                    )
                }
                ForEach(otherSections) { section in
                    NoteGallerySection(
                        title: section.title ?? (!pinnedFiles.isEmpty ? String(localized: "Notes") : nil),
                        files: section.files,
                        dateBasis: sortOrder.dateBasis,
                        isSelecting: isSelecting,
                        selectedPaths: selectedPaths,
                        toggleSelection: toggleSelection
                    )
                }

                if currentFolder.children.isEmpty, directFiles.isEmpty {
                    ContentUnavailableView("No Notes", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .accessibilityIdentifier("note-gallery")
    }

    @ViewBuilder
    private func noteRow(_ file: RecentMarkdownFile) -> some View {
        if isSelecting {
            SelectableNoteFileRow(
                file: file,
                dateBasis: sortOrder.dateBasis,
                showsFolder: false,
                isSelected: selectedPaths.contains(file.relativePath)
            ) {
                if !selectedPaths.insert(file.relativePath).inserted {
                    selectedPaths.remove(file.relativePath)
                }
            }
        } else {
            NoteFileButton(file: file, dateBasis: sortOrder.dateBasis, showsFolder: false)
        }
    }

    private func finishSelecting() {
        selectedPaths.removeAll()
        isSelecting = false
    }

    private func toggleSelection(_ file: RecentMarkdownFile) {
        if !selectedPaths.insert(file.relativePath).inserted {
            selectedPaths.remove(file.relativePath)
        }
    }
}

private struct FolderLifecycleActions: ViewModifier {
    @EnvironmentObject private var appModel: AppModel
    var folder: LibraryFolderNode
    var isManagementMode = false
    @State private var folderName = ""
    @State private var isCreatingSubfolder = false
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false
    @State private var isDropTargeted = false

    private var moveDestinations: [LibraryFolderNode] {
        appModel.allFolders.filter {
            $0.relativePath != folder.relativePath
                && !$0.relativePath.hasPrefix(folder.relativePath + "/")
        }
    }

    func body(content: Content) -> some View {
        dragAndDrop(content)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
                lifecycleMenuItems
            }
            .overlay(alignment: .trailing) {
                if isManagementMode {
                    HStack(spacing: 0) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(MudsnoteColors.muted)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .draggable(folder.relativePath)
                            .dropDestination(for: String.self) { sourcePaths, _ in
                                acceptDrop(sourcePaths)
                            } isTargeted: { targeted in
                                updateDropTarget(targeted)
                            }
                            .accessibilityIdentifier("folder-drag-handle-\(folder.relativePath)")

                        Menu {
                            lifecycleMenuItems
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(NotesCloneColors.folderYellow)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Folder Actions")
                        .accessibilityIdentifier("folder-management-\(folder.relativePath)")
                    }
                    .padding(.trailing, 10)
                }
            }
            .alert("New Subfolder", isPresented: $isCreatingSubfolder) {
                TextField("Folder Name", text: $folderName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = folderName
                    let parent = folder.relativePath
                    Task { _ = await appModel.createFolder(named: name, parent: parent) }
                }
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("Rename Folder", isPresented: $isRenaming) {
                TextField("Folder Name", text: $folderName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let name = folderName
                    let target = folder
                    Task { _ = await appModel.renameFolder(target, to: name) }
                }
                .disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .confirmationDialog(
                "Delete Folder?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Notes", role: .destructive) {
                    let target = folder
                    Task { _ = await appModel.deleteFolder(target) }
                }
            } message: {
                Text("Notes in this folder will move to Recently Deleted. Other files will be preserved.")
            }
    }

    @ViewBuilder
    private func dragAndDrop(_ content: Content) -> some View {
        if isManagementMode {
            content
                .dropDestination(for: String.self) { sourcePaths, _ in
                    acceptDrop(sourcePaths)
                } isTargeted: { targeted in
                    updateDropTarget(targeted)
                }
                .background(
                    NotesCloneColors.folderYellow.opacity(isDropTargeted ? 0.13 : 0),
                    in: RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                )
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                            .stroke(NotesCloneColors.folderYellow, lineWidth: 2)
                    }
                }
        } else {
            content
        }
    }

    private func acceptDrop(_ sourcePaths: [String]) -> Bool {
        guard let sourcePath = sourcePaths.first,
              sourcePath != folder.relativePath,
              !folder.relativePath.hasPrefix(sourcePath + "/"),
              let source = appModel.allFolders.first(where: {
                  $0.relativePath == sourcePath
              }) else { return false }
        let destination = folder
        Task { _ = await appModel.moveFolder(source, to: destination) }
        return true
    }

    private func updateDropTarget(_ targeted: Bool) {
        withAnimation(.easeInOut(duration: 0.16)) {
            isDropTargeted = targeted
        }
    }

    @ViewBuilder
    private var lifecycleMenuItems: some View {
        Button {
            folderName = ""
            isCreatingSubfolder = true
        } label: {
            Label("New Subfolder", systemImage: "folder.badge.plus")
        }
        Button {
            folderName = folder.name
            isRenaming = true
        } label: {
            Label("Rename Folder", systemImage: "pencil")
        }
        Menu {
            if folder.relativePath.contains("/") {
                Button {
                    let target = folder
                    Task { _ = await appModel.moveFolder(target, to: nil) }
                } label: {
                    Label("Top Level", systemImage: "tray")
                }
            }
            ForEach(moveDestinations) { destination in
                Button {
                    let target = folder
                    Task { _ = await appModel.moveFolder(target, to: destination) }
                } label: {
                    Label(destination.relativePath, systemImage: "folder")
                }
            }
        } label: {
            Label("Move Folder", systemImage: "folder.badge.arrow.forward")
        }
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            Label("Delete Folder", systemImage: "trash")
        }
    }
}

private struct SelectableNoteFileRow: View {
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis
    var showsFolder = true
    var isSelected: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? NotesCloneColors.folderYellow : MudsnoteColors.muted)
                RecentFileRow(
                    file: file,
                    dateBasis: dateBasis,
                    showsFolder: showsFolder
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("selectable-note-row-\(file.id)")
    }
}

private struct SelectedNotesActionBar: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isConfirmingDelete = false
    var files: [RecentMarkdownFile]
    var destinations: [LibraryFolderNode]
    var finish: () -> Void

    private var canMoveOrDelete: Bool {
        !files.isEmpty && files.allSatisfy(appModel.canMoveToRecentlyDeleted)
    }

    private var shouldPin: Bool {
        !files.allSatisfy(\.isPinned)
    }

    private var canMoveToTopLevel: Bool {
        files.contains {
            !(($0.relativePath as NSString).deletingLastPathComponent).isEmpty
        }
    }

    private var availableDestinations: [LibraryFolderNode] {
        destinations.filter { destination in
            files.contains {
                ($0.relativePath as NSString).deletingLastPathComponent
                    != destination.relativePath
            }
        }
    }

    var body: some View {
        HStack(spacing: 22) {
            Text(
                String(
                    format: String(localized: "notes.selected.format"),
                    locale: .current,
                    files.count
                )
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MudsnoteColors.muted)
            .frame(minWidth: 68, alignment: .leading)

            Spacer(minLength: 0)

            Menu {
                if canMoveToTopLevel {
                    Button {
                        let selected = files
                        Task {
                            if await appModel.moveNotes(selected, toFolder: nil) {
                                finish()
                            }
                        }
                    } label: {
                        Label("Top Level", systemImage: "tray")
                    }
                }
                ForEach(availableDestinations) { destination in
                    Button(destination.relativePath) {
                        let selected = files
                        Task {
                            if await appModel.moveNotes(
                                selected,
                                toFolder: destination.relativePath
                            ) {
                                finish()
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "folder")
                    .frame(width: 34, height: 34)
            }
            .disabled(
                !canMoveOrDelete
                    || (!canMoveToTopLevel && availableDestinations.isEmpty)
            )
            .accessibilityLabel("Move Selected Notes")
            .accessibilityIdentifier("move-selected-notes")

            Button {
                let selected = files
                let pin = shouldPin
                Task {
                    if await appModel.setPinned(selected, isPinned: pin) {
                        finish()
                    }
                }
            } label: {
                Image(systemName: shouldPin ? "pin" : "pin.slash")
                    .frame(width: 34, height: 34)
            }
            .disabled(files.isEmpty)
            .accessibilityLabel(shouldPin ? "Pin Selected Notes" : "Unpin Selected Notes")
            .accessibilityIdentifier("pin-selected-notes")

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .frame(width: 34, height: 34)
            }
            .disabled(!canMoveOrDelete)
            .accessibilityLabel("Delete Selected Notes")
            .accessibilityIdentifier("delete-selected-notes")
        }
        .font(.title3)
        .foregroundStyle(MudsnoteColors.text)
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(MudsnoteColors.line).frame(height: 1)
        }
        .confirmationDialog(
            "Delete Selected Notes?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let selected = files
                Task {
                    if await appModel.moveToRecentlyDeleted(selected) {
                        finish()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore these notes later from Recently Deleted.")
        }
    }
}

private struct NoteGallerySection: View {
    var title: String?
    var files: [RecentMarkdownFile]
    var dateBasis: NoteDateBasis
    var isSelecting: Bool
    var selectedPaths: Set<String>
    var toggleSelection: (RecentMarkdownFile) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(files) { file in
                    if isSelecting {
                        SelectableNoteGalleryCard(
                            file: file,
                            dateBasis: dateBasis,
                            isSelected: selectedPaths.contains(file.relativePath)
                        ) {
                            toggleSelection(file)
                        }
                    } else {
                        NoteGalleryFileButton(file: file, dateBasis: dateBasis)
                    }
                }
            }
        } header: {
            if let title {
                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(MudsnoteColors.text)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MudsnoteColors.canvas)
            }
        }
    }
}

private struct HomeTimelineCardSection: View {
    var section: HomeTimelineSection
    var isSelecting: Bool
    var selectedIDs: Set<String>
    var toggleSelection: (HomeTimelineEntry) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        Section {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(section.entries) { entry in
                    HomeTimelineGalleryEntryButton(
                        entry: entry,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(entry.id),
                        toggleSelection: { toggleSelection(entry) }
                    )
                }
            }
        } header: {
            if let title = section.title {
                HStack(spacing: 0) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MudsnoteColors.text)

                    Spacer(minLength: 0)
                }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MudsnoteColors.canvas)
                    .padding(.horizontal, -16)
                    .accessibilityIdentifier("home-section-header-\(section.id)")
            }
        }
    }
}

private struct HomeTimelineListSection: View {
    var section: HomeTimelineSection
    var isSelecting: Bool
    var selectedIDs: Set<String>
    var toggleSelection: (HomeTimelineEntry) -> Void

    var body: some View {
        Section {
            VStack(spacing: 0) {
                ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                    HomeTimelineListEntryButton(
                        entry: entry,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(entry.id),
                        toggleSelection: { toggleSelection(entry) }
                    )
                    if index < section.entries.count - 1 {
                        Divider().padding(.leading, 14)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(MudsnoteColors.line, lineWidth: 1)
            }
        } header: {
            if let title = section.title {
                HStack(spacing: 0) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(MudsnoteColors.text)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MudsnoteColors.canvas)
                .padding(.horizontal, -16)
                .accessibilityIdentifier("home-section-header-\(section.id)")
            }
        }
    }
}

private struct HomeTimelineGalleryEntryButton: View {
    var entry: HomeTimelineEntry
    var isSelecting: Bool
    var isSelected: Bool
    var toggleSelection: () -> Void

    var body: some View {
        if isSelecting {
            Button(action: toggleSelection) {
                galleryContent
                    .overlay(alignment: .topTrailing) {
                        selectionIndicator.padding(9)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("selectable-home-note-\(entry.id)")
        } else {
            switch entry {
            case .file(let file):
                NoteGalleryFileButton(file: file, dateBasis: .modified)
            case .memo(let memo):
                HomeMemoCardButton(memo: memo)
            }
        }
    }

    @ViewBuilder
    private var galleryContent: some View {
        switch entry {
        case .file(let file):
            NoteGalleryCard(file: file, dateBasis: .modified)
        case .memo(let memo):
            HomeMemoCard(memo: memo)
        }
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? NotesCloneColors.folderYellow : MudsnoteColors.muted)
    }
}

private struct HomeTimelineListEntryButton: View {
    @EnvironmentObject private var appModel: AppModel
    var entry: HomeTimelineEntry
    var isSelecting: Bool
    var isSelected: Bool
    var toggleSelection: () -> Void

    var body: some View {
        Button {
            if isSelecting {
                toggleSelection()
            } else {
                openEntry()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(
                            isSelected ? NotesCloneColors.folderYellow : MudsnoteColors.muted
                        )
                        .padding(.top, 12)
                }
                listContent
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
            isSelecting ? "selectable-home-note-\(entry.id)" : "home-list-note-\(entry.id)"
        )
    }

    @ViewBuilder
    private var listContent: some View {
        switch entry {
        case .file(let file):
            RecentFileRow(file: file, dateBasis: .modified)
        case .memo(let memo):
            HomeMemoListRow(memo: memo)
        }
    }

    private func openEntry() {
        switch entry {
        case .file(let file): appModel.openFile(file)
        case .memo(let memo): appModel.selectedMemo = memo
        }
    }
}

private struct HomeMemoCardButton: View {
    @EnvironmentObject private var appModel: AppModel
    var memo: MemoBlock

    var body: some View {
        Button {
            appModel.selectedMemo = memo
        } label: {
            HomeMemoCard(memo: memo)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home-memo-card-\(memo.id)")
        .contextMenu {
            Button {
                appModel.pinMemo(memo)
            } label: {
                Label("Pin", systemImage: "pin")
            }
            Button {
                appModel.addDefaultTag(to: memo)
            } label: {
                Label("Tag", systemImage: "number")
            }
            Button(role: .destructive) {
                appModel.deleteMemo(memo)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct HomeMemoCard: View {
    var memo: MemoBlock

    private var contentLines: [String] {
        memo.body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var title: String {
        contentLines.first?
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>*+- "))
            ?? String(localized: "Untitled memo")
    }

    private var preview: String { contentLines.dropFirst().joined(separator: " ") }
    private var dateText: String {
        memo.dateText.split(separator: " ").last.map(String.init) ?? memo.dateText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(MudsnoteColors.text)
                    .lineLimit(2)
                Text(preview.isEmpty ? String(localized: "No additional text") : preview)
                    .font(.subheadline)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(5)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: "tray")
                    Text("000-inbox").lineLimit(1)
                    Spacer(minLength: 0)
                    if memo.hasUncheckedChecklist { Image(systemName: "checklist") }
                    if memo.hasAttachments { Image(systemName: "paperclip") }
                }
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14).stroke(MudsnoteColors.line, lineWidth: 1)
            }
            Text(dateText)
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
                .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
    }
}

private struct HomeMemoListRow: View {
    var memo: MemoBlock

    private var lines: [String] {
        memo.body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NotesListRowContent(
            title: lines.first?.trimmingCharacters(in: CharacterSet(charactersIn: "#>*+- "))
                ?? String(localized: "Untitled memo"),
            dateText: memo.dateText.split(separator: " ").last.map(String.init) ?? memo.dateText,
            preview: lines.dropFirst().joined(separator: " "),
            folderName: "000-inbox",
            hasAttachments: memo.hasAttachments,
            hasUncheckedChecklist: memo.hasUncheckedChecklist
        )
    }
}

private struct HomeSelectedNotesActionBar: View {
    var count: Int
    var delete: () -> Void

    var body: some View {
        HStack {
            Text(
                String(
                    format: String(localized: "notes.selected.format"),
                    locale: .current,
                    count
                )
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MudsnoteColors.muted)
            Spacer(minLength: 0)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash").frame(width: 44, height: 44)
            }
            .disabled(count == 0)
            .accessibilityLabel("Delete Selected Notes")
            .accessibilityIdentifier("delete-selected-home-notes")
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(MudsnoteColors.line).frame(height: 1)
        }
    }
}

private struct NoteGalleryFileButton: View {
    @EnvironmentObject private var appModel: AppModel
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis

    var body: some View {
        Button {
            appModel.openFile(file)
        } label: {
            NoteGalleryCard(file: file, dateBasis: dateBasis)
                .contentShape(Rectangle())
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("markdown-file-row-\(file.id)")
        .modifier(NoteLifecycleActions(file: file))
    }
}

private struct SelectableNoteGalleryCard: View {
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis
    var isSelected: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            NoteGalleryCard(file: file, dateBasis: dateBasis)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(
                            isSelected ? NotesCloneColors.folderYellow : MudsnoteColors.muted
                        )
                        .padding(9)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("selectable-note-row-\(file.id)")
    }
}

private struct NoteGalleryCard: View {
    @EnvironmentObject private var appModel: AppModel
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis

    private var displayedDate: Date { dateBasis.date(for: file) }

    private var dateText: String {
        if Calendar.autoupdatingCurrent.isDateInToday(displayedDate) {
            return displayedDate.formatted(date: .omitted, time: .shortened)
        }
        return displayedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var folderName: String {
        let parent = (file.relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty ? String(localized: "Mudsnote") : (parent as NSString).lastPathComponent
    }

    private var galleryImage: LibraryAttachment? {
        guard let path = file.galleryImagePath else { return nil }
        return appModel.attachments.first {
            $0.relativePath == path && $0.kind == .image
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                Text(file.title)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(MudsnoteColors.text)
                    .lineLimit(2)
                galleryPreview
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(folderName)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if file.hasAttachments {
                        Image(systemName: "paperclip")
                    }
                }
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(MudsnoteColors.line, lineWidth: 1)
            }

            HStack(spacing: 5) {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.muted)
                Spacer(minLength: 0)
                if file.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(NotesCloneColors.folderYellow)
                        .accessibilityLabel("Pinned")
                        .accessibilityIdentifier("pin-indicator-\(file.id)")
                }
            }
            .padding(.horizontal, 2)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open Markdown file")
    }

    @ViewBuilder
    private var galleryPreview: some View {
        if let galleryImage {
            AttachmentImageThumbnail(attachment: galleryImage)
                .frame(height: file.galleryChecklistItems.isEmpty ? 88 : 64)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(MudsnoteColors.line, lineWidth: 1)
                }
            if !file.galleryChecklistItems.isEmpty {
                galleryChecklist(maximumItems: 2)
            }
        } else if !file.galleryChecklistItems.isEmpty {
            galleryChecklist(maximumItems: 4)
        } else {
            Text(file.preview.isEmpty ? String(localized: "No additional text") : file.preview)
                .font(.subheadline)
                .foregroundStyle(MudsnoteColors.muted)
                .lineLimit(5)
        }
    }

    private func galleryChecklist(maximumItems: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(file.galleryChecklistItems.prefix(maximumItems).enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(
                            item.isChecked ? NotesCloneColors.folderYellow : MudsnoteColors.muted
                        )
                    Text(item.text)
                        .font(.caption)
                        .foregroundStyle(MudsnoteColors.muted)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

struct NoteFileButton: View {
    @EnvironmentObject private var appModel: AppModel
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis = .modified
    var showsFolder = true

    var body: some View {
        Button {
            appModel.openFile(file)
        } label: {
            RecentFileRow(
                file: file,
                dateBasis: dateBasis,
                showsFolder: showsFolder
            )
                .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("markdown-file-row-\(file.id)")
        .modifier(NoteLifecycleActions(file: file))
    }
}

private struct NoteLifecycleActions: ViewModifier {
    @EnvironmentObject private var appModel: AppModel
    var file: RecentMarkdownFile
    @State private var noteName = ""
    @State private var isRenaming = false
    @State private var isMovePickerPresented = false

    private var currentFolder: String {
        (file.relativePath as NSString).deletingLastPathComponent
    }

    private var moveDestinations: [LibraryFolderNode] {
        appModel.allFolders.filter { $0.relativePath != currentFolder }
    }

    private var canMove: Bool {
        !currentFolder.isEmpty || !moveDestinations.isEmpty
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if appModel.canMoveToRecentlyDeleted(file) {
                    Button {
                        appModel.togglePinned(file)
                    } label: {
                        Label(file.isPinned ? "Unpin" : "Pin", systemImage: file.isPinned ? "pin.slash" : "pin")
                    }
                    .tint(.yellow)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if appModel.canMoveToRecentlyDeleted(file) {
                    Button(role: .destructive) {
                        appModel.moveToRecentlyDeleted(file)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    if canMove {
                        Button {
                            isMovePickerPresented = true
                        } label: {
                            Label("Move", systemImage: "folder")
                        }
                        .tint(NotesCloneColors.folderYellow)
                        .accessibilityIdentifier("swipe-move-note-\(file.id)")
                    }
                }
            }
            .contextMenu {
                Button {
                    appModel.openFile(file, mode: .edit)
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("edit-note-\(file.id)")

                if appModel.canMoveToRecentlyDeleted(file) {
                    Button {
                        appModel.togglePinned(file)
                    } label: {
                        Label(file.isPinned ? "Unpin" : "Pin", systemImage: file.isPinned ? "pin.slash" : "pin")
                    }
                    Button {
                        appModel.duplicate(file)
                    } label: {
                        Label("Duplicate Note", systemImage: "plus.square.on.square")
                    }
                    Button {
                        noteName = file.title
                        isRenaming = true
                    } label: {
                        Label("Rename Note", systemImage: "pencil")
                    }
                }
                if appModel.canMoveToRecentlyDeleted(file),
                   !currentFolder.isEmpty || !moveDestinations.isEmpty {
                    Menu {
                        if !currentFolder.isEmpty {
                            Button {
                                let path = file.relativePath
                                Task {
                                    _ = await appModel.moveNote(
                                        relativePath: path,
                                        toFolder: nil
                                    )
                                }
                            } label: {
                                Label("Top Level", systemImage: "tray")
                            }
                        }
                        ForEach(moveDestinations) { folder in
                            Button(folder.relativePath) {
                                appModel.move(file, to: folder)
                            }
                        }
                    } label: {
                        Label("Move Note", systemImage: "folder")
                    }
                }
                if appModel.canMoveToRecentlyDeleted(file) {
                    Button(role: .destructive) {
                        appModel.moveToRecentlyDeleted(file)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .alert("Rename Note", isPresented: $isRenaming) {
                TextField("Note Name", text: $noteName)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let path = file.relativePath
                    let name = noteName
                    Task { _ = await appModel.renameNote(relativePath: path, to: name) }
                }
                .disabled(noteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .sheet(isPresented: $isMovePickerPresented) {
                NoteMovePicker(file: file)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
    }
}

private struct NoteMovePicker: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    var file: RecentMarkdownFile
    @State private var movingDestination: String?

    private var currentFolder: String {
        (file.relativePath as NSString).deletingLastPathComponent
    }

    private var destinations: [LibraryFolderNode] {
        appModel.allFolders.filter { $0.relativePath != currentFolder }
    }

    var body: some View {
        NavigationStack {
            List {
                if !currentFolder.isEmpty {
                    destinationButton(
                        title: String(localized: "Notes"),
                        detail: String(localized: "Top Level"),
                        systemImage: "tray.full",
                        destination: nil
                    )
                }

                ForEach(destinations) { destination in
                    destinationButton(
                        title: destination.name,
                        detail: parentPath(for: destination),
                        systemImage: "folder.fill",
                        destination: destination.relativePath
                    )
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MudsnoteColors.canvas)
            .navigationTitle("Move Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("note-move-picker")
    }

    private func parentPath(for destination: LibraryFolderNode) -> String? {
        let parent = (destination.relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    private func destinationButton(
        title: String,
        detail: String?,
        systemImage: String,
        destination: String?
    ) -> some View {
        let destinationID = destination ?? "top-level"
        return Button {
            move(to: destination)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(NotesCloneColors.folderYellow)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(MudsnoteColors.text)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                }

                Spacer(minLength: 0)

                if movingDestination == destinationID {
                    ProgressView()
                        .tint(NotesCloneColors.folderYellow)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(MudsnoteColors.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(movingDestination != nil)
        .accessibilityIdentifier("move-note-destination-\(destinationID)")
    }

    private func move(to destination: String?) {
        let destinationID = destination ?? "top-level"
        movingDestination = destinationID
        let path = file.relativePath
        Task {
            if await appModel.moveNote(relativePath: path, toFolder: destination) != nil {
                dismiss()
            } else {
                movingDestination = nil
            }
        }
    }
}

struct RecentlyDeletedView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var pendingPermanentDelete: TrashedMarkdownFile?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    private var selectedItems: [TrashedMarkdownFile] {
        appModel.trashedFiles.filter { selectedIDs.contains($0.id) }
    }

    private func finishSelection() {
        isSelecting = false
        selectedIDs = []
    }

    var body: some View {
        List {
            if appModel.trashedFiles.isEmpty {
                ContentUnavailableView(
                    "No Recently Deleted Notes",
                    systemImage: "trash",
                    description: Text("Deleted notes appear here until you remove them permanently.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(appModel.trashedFiles) { item in
                    if isSelecting {
                        SelectableTrashedMarkdownRow(
                            item: item,
                            isSelected: selectedIDs.contains(item.id)
                        ) {
                            if !selectedIDs.insert(item.id).inserted {
                                selectedIDs.remove(item.id)
                            }
                        }
                    } else {
                        TrashedMarkdownRow(item: item)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    appModel.restore(item)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingPermanentDelete = item
                                } label: {
                                    Label("Delete Permanently", systemImage: "trash.slash")
                                }
                            }
                            .contextMenu {
                                Button {
                                    appModel.restore(item)
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                Button(role: .destructive) {
                                    pendingPermanentDelete = item
                                } label: {
                                    Label("Delete Permanently", systemImage: "trash.slash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MudsnoteColors.canvas)
        .refreshable {
            await appModel.refreshInbox()
        }
        .navigationTitle(
            isSelecting
                ? String(
                    format: String(localized: "notes.selected.format"),
                    locale: .current,
                    selectedIDs.count
                )
                : String(localized: "Recently Deleted")
        )
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button(
                        selectedIDs.count == appModel.trashedFiles.count
                            ? "Deselect All"
                            : "Select All"
                    ) {
                        if selectedIDs.count == appModel.trashedFiles.count {
                            selectedIDs = []
                        } else {
                            selectedIDs = Set(appModel.trashedFiles.map(\.id))
                        }
                    }
                    .accessibilityIdentifier("toggle-select-all-deleted-notes")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: finishSelection)
                        .accessibilityIdentifier("finish-deleted-note-selection")
                }
            } else if !appModel.trashedFiles.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            isSelecting = true
                        } label: {
                            Label("Select Notes", systemImage: "checkmark.circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Recently Deleted Options")
                    .accessibilityIdentifier("recently-deleted-options")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelecting {
                SelectedDeletedNotesActionBar(
                    items: selectedItems,
                    finish: finishSelection
                )
            }
        }
        .onChange(of: appModel.trashedFiles.map(\.id)) { _, availableIDs in
            selectedIDs.formIntersection(availableIDs)
            if availableIDs.isEmpty { finishSelection() }
        }
        .alert(
            "Delete Permanently?",
            isPresented: Binding(
                get: { pendingPermanentDelete != nil },
                set: { if !$0 { pendingPermanentDelete = nil } }
            ),
            presenting: pendingPermanentDelete
        ) { item in
            Button("Cancel", role: .cancel) {
                pendingPermanentDelete = nil
            }
            Button("Delete Permanently", role: .destructive) {
                pendingPermanentDelete = nil
                appModel.permanentlyDelete(item)
            }
        } message: { _ in
            Text("This action cannot be undone.")
        }
    }
}

private struct SelectableTrashedMarkdownRow: View {
    var item: TrashedMarkdownFile
    var isSelected: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? NotesCloneColors.folderYellow : MudsnoteColors.muted)
                TrashedMarkdownRow(item: item)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("selectable-trashed-row-\(item.id)")
    }
}

private struct SelectedDeletedNotesActionBar: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isConfirmingPermanentDelete = false
    var items: [TrashedMarkdownFile]
    var finish: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Text(
                String(
                    format: String(localized: "notes.selected.format"),
                    locale: .current,
                    items.count
                )
            )
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(MudsnoteColors.muted)
            .frame(minWidth: 68, alignment: .leading)

            Spacer(minLength: 0)

            Button {
                let selected = items
                Task {
                    if await appModel.restore(selected) {
                        finish()
                    }
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .frame(width: 38, height: 38)
            }
            .disabled(items.isEmpty)
            .accessibilityLabel("Restore Selected Notes")
            .accessibilityIdentifier("restore-selected-deleted-notes")

            Button(role: .destructive) {
                isConfirmingPermanentDelete = true
            } label: {
                Image(systemName: "trash.slash")
                    .frame(width: 38, height: 38)
            }
            .disabled(items.isEmpty)
            .accessibilityLabel("Delete Selected Notes Permanently")
            .accessibilityIdentifier("permanently-delete-selected-notes")
        }
        .font(.title3)
        .foregroundStyle(MudsnoteColors.text)
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(MudsnoteColors.line).frame(height: 1)
        }
        .confirmationDialog(
            "Delete Selected Notes Permanently?",
            isPresented: $isConfirmingPermanentDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                let selected = items
                Task {
                    if await appModel.permanentlyDelete(selected) {
                        finish()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

private struct TrashedMarkdownRow: View {
    var item: TrashedMarkdownFile

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(MudsnoteColors.text)
                .lineLimit(1)
            Text(item.originalRelativePath)
                .font(.subheadline)
                .foregroundStyle(MudsnoteColors.muted)
                .lineLimit(1)
            Text(item.trashedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
        }
        .padding(.vertical, 4)
    }
}

private enum NotesCloneColors {
    static let background = MudsnoteColors.canvas
    static let separator = MudsnoteColors.line
    static let folderYellow = Color(hex: 0xD7BD68)
    static let chip = Color(hex: 0x22262F)
}

struct NotesSectionHeader: View {
    var title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(MudsnoteColors.text)
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

struct NotesFolderRow: View {
    var title: String
    var systemImage: String
    var iconTint: Color = MudsnoteColors.text
    var count: Int?
    var showsChevron = true
    var trailingAccessoryWidth: CGFloat = 0
    var indentation: CGFloat = 0

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconTint)
                .frame(width: 36, height: 36)
                .background(iconTint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(MudsnoteColors.text)

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(.subheadline, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(MudsnoteColors.muted)
                    .frame(minWidth: 28, alignment: .trailing)
                    .accessibilityIdentifier("folder-count-\(title)")
            }

            ZStack(alignment: .trailing) {
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MudsnoteColors.muted.opacity(0.7))
                }
            }
            .frame(width: max(28, trailingAccessoryWidth), height: 44, alignment: .trailing)
        }
        .padding(.leading, 18 + indentation)
        .padding(.trailing, 18)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotesCloneColors.separator)
                .frame(height: 1)
                .padding(.leading, 72 + indentation)
        }
    }
}

struct TagChip: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(MudsnoteColors.muted)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(NotesCloneColors.chip, in: Capsule())
            .overlay {
                Capsule().stroke(MudsnoteColors.line, lineWidth: 1)
            }
    }
}

enum TagMatchMode: String, CaseIterable, Identifiable {
    case any
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: String(localized: "Any")
        case .all: String(localized: "All")
        }
    }
}

enum TagFilterState: Equatable {
    case inactive
    case included
    case excluded
}

struct TagSelectionFilter: Equatable {
    var included = Set<String>()
    var excluded = Set<String>()
    var matchMode = TagMatchMode.any

    var isEmpty: Bool { included.isEmpty && excluded.isEmpty }

    mutating func cycle(_ tag: String) {
        switch state(for: tag) {
        case .inactive:
            included.insert(tag)
        case .included:
            included.remove(tag)
            excluded.insert(tag)
        case .excluded:
            excluded.remove(tag)
        }
    }

    mutating func clear() {
        included.removeAll()
        excluded.removeAll()
    }

    func state(for tag: String) -> TagFilterState {
        if contains(tag, in: included) { return .included }
        if contains(tag, in: excluded) { return .excluded }
        return .inactive
    }

    func matches(tags: [String]) -> Bool {
        let candidateKeys = Set(tags.map(Self.key))
        guard !candidateKeys.isEmpty else { return false }
        let excludedKeys = Set(excluded.map(Self.key))
        guard candidateKeys.isDisjoint(with: excludedKeys) else { return false }

        let includedKeys = Set(included.map(Self.key))
        guard !includedKeys.isEmpty else { return true }
        switch matchMode {
        case .any:
            return !candidateKeys.isDisjoint(with: includedKeys)
        case .all:
            return includedKeys.isSubset(of: candidateKeys)
        }
    }

    private func contains(_ tag: String, in values: Set<String>) -> Bool {
        let key = Self.key(tag)
        return values.contains { Self.key($0) == key }
    }

    private static func key(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

private struct TagFilterChip: View {
    var title: String
    var state: TagFilterState

    var body: some View {
        HStack(spacing: 7) {
            if state != .inactive {
                Image(systemName: state == .included ? "checkmark" : "minus")
                    .font(.caption.weight(.bold))
            }
            Text(title)
                .strikethrough(state == .excluded)
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .foregroundStyle(state == .included ? Color.black : MudsnoteColors.text)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(chipBackground, in: Capsule())
        .overlay {
            Capsule().stroke(chipBorder, lineWidth: 1)
        }
    }

    private var chipBackground: Color {
        switch state {
        case .inactive: NotesCloneColors.chip
        case .included: NotesCloneColors.folderYellow
        case .excluded: MudsnoteColors.card
        }
    }

    private var chipBorder: Color {
        state == .inactive ? MudsnoteColors.line : NotesCloneColors.folderYellow.opacity(0.8)
    }
}

struct NotesBottomCommandBar: ToolbarContent {
    @Binding var searchText: String
    @Binding var searchFocused: Bool
    var newNote: () -> Void

    @ToolbarContentBuilder
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            DefaultToolbarItem(kind: .search, placement: .bottomBar)

            ToolbarSpacer(.fixed, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                }
                .tint(.primary)
                .accessibilityLabel("New note")
                .accessibilityIdentifier("new-note-button")
            }
        } else {
            ToolbarItem(placement: .bottomBar) {
                NotesToolbarSearchField(
                    searchText: $searchText,
                    searchFocused: $searchFocused,
                    drawsFallbackBackground: true
                )
            }

            ToolbarItem(placement: .bottomBar) {
                Button(action: newNote) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 20, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color.black)
                        .frame(width: 46, height: 46)
                        .background(.regularMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(MudsnoteColors.line, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
                .accessibilityIdentifier("new-note-button")
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func notesNativeToolbarSearch(
        text: Binding<String>,
        isPresented: Binding<Bool>
    ) -> some View {
        if #available(iOS 26.0, *) {
            searchable(
                text: text,
                isPresented: isPresented,
                placement: .toolbar,
                prompt: Text("Search")
            )
        } else {
            self
        }
    }
}

private struct NotesToolbarSearchField: View {
    @Binding var searchText: String
    @Binding var searchFocused: Bool
    var drawsFallbackBackground: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            NativeToolbarSearchField(
                text: $searchText,
                isFocused: $searchFocused
            )
            .accessibilityIdentifier("library-search-field")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("clear-library-search")
            }
        }
        .foregroundStyle(MudsnoteColors.text)
        .padding(.horizontal, 12)
        .frame(minWidth: 190, idealWidth: 226)
        .frame(height: 38)
        .background {
            if drawsFallbackBackground {
                Capsule().fill(.regularMaterial)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NativeToolbarSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = String(localized: "Search")
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .label
        field.tintColor = UIColor(MudsnoteColors.primary)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.accessibilityIdentifier = "library-search-field"
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textDidChange(_:)),
            for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text {
            field.text = text
        }
        let focusRequestChanged = context.coordinator.lastRequestedFocus != isFocused
        context.coordinator.lastRequestedFocus = isFocused
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        } else if focusRequestChanged, !isFocused, field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NativeToolbarSearchField
        var lastRequestedFocus: Bool?

        init(parent: NativeToolbarSearchField) {
            self.parent = parent
        }

        @objc func textDidChange(_ field: UITextField) {
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.isFocused = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFocused = false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0, currentX + size.width > maxWidth {
                currentX = 0
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: maxWidth, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX, currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += rowHeight + rowSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(size)
            )
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct SmartFolderEditorView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SmartFolderDefinition
    @State private var isSaving = false
    @State private var errorMessage: String?
    var isNew: Bool

    init(definition: SmartFolderDefinition, isNew: Bool) {
        _draft = State(initialValue: definition)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Smart Folder Name", text: $draft.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("smart-folder-name")
                }

                Section {
                    Picker("Match", selection: $draft.matchMode) {
                        ForEach(SmartFolderMatchMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("smart-folder-match-mode")
                } footer: {
                    Text("Choose whether notes must match all filters or any filter.")
                }

                Section {
                    if appModel.tagSummaries.isEmpty {
                        Text("No tags are currently used in your notes.")
                            .foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 10, rowSpacing: 10) {
                            ForEach(appModel.tagSummaries) { tag in
                                Button {
                                    cycleTag(tag.name)
                                } label: {
                                    TagFilterChip(
                                        title: tag.name,
                                        state: tagState(for: tag.name)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("smart-folder-tag-\(tag.name)")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Tap once to include a tag. Tap again to exclude it.")
                }

                Section("Filters") {
                    Picker("Date", selection: $draft.dateFilter) {
                        Text("Any Date").tag(nil as SmartFolderDateFilter?)
                        ForEach(SmartFolderDateFilter.allCases) { filter in
                            Text(filter.label).tag(Optional(filter))
                        }
                    }
                    .accessibilityIdentifier("smart-folder-date-filter")

                    Picker("Attachments", selection: $draft.attachmentFilter) {
                        Text("Any").tag(nil as SmartFolderAttachmentFilter?)
                        ForEach(SmartFolderAttachmentFilter.allCases) { filter in
                            Text(filter.label).tag(Optional(filter))
                        }
                    }
                    .accessibilityIdentifier("smart-folder-attachment-filter")

                    Picker("Checklists", selection: $draft.checklistFilter) {
                        Text("Any").tag(nil as SmartFolderChecklistFilter?)
                        ForEach(SmartFolderChecklistFilter.allCases) { filter in
                            Text(filter.label).tag(Optional(filter))
                        }
                    }
                    .accessibilityIdentifier("smart-folder-checklist-filter")

                    Picker("Pinned", selection: $draft.pinned) {
                        Text("Any").tag(nil as Bool?)
                        Text("Pinned Only").tag(Optional(true))
                        Text("Not Pinned").tag(Optional(false))
                    }
                    .accessibilityIdentifier("smart-folder-pinned-filter")
                }
            }
            .navigationTitle(isNew ? "New Smart Folder" : "Edit Smart Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("save-smart-folder")
                }
            }
            .interactiveDismissDisabled(isSaving)
            .alert("Could Not Save Smart Folder", isPresented: errorPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Try again.")
            }
        }
    }

    private var canSave: Bool {
        draft.normalized != nil
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        guard let normalized = draft.normalized else { return }
        isSaving = true
        Task {
            let succeeded = isNew
                ? await appModel.createSmartFolder(normalized)
                : await appModel.updateSmartFolder(normalized)
            isSaving = false
            if succeeded {
                dismiss()
            } else {
                errorMessage = appModel.statusToast?.message
                    ?? String(localized: "Could Not Save Smart Folder")
            }
        }
    }

    private func tagState(for tag: String) -> TagFilterState {
        let key = SmartFolderDefinition.tagKey(tag)
        if draft.includedTags.contains(where: { SmartFolderDefinition.tagKey($0) == key }) {
            return .included
        }
        if draft.excludedTags.contains(where: { SmartFolderDefinition.tagKey($0) == key }) {
            return .excluded
        }
        return .inactive
    }

    private func cycleTag(_ tag: String) {
        let key = SmartFolderDefinition.tagKey(tag)
        switch tagState(for: tag) {
        case .inactive:
            draft.includedTags.append(tag)
        case .included:
            draft.includedTags.removeAll { SmartFolderDefinition.tagKey($0) == key }
            draft.excludedTags.append(tag)
        case .excluded:
            draft.excludedTags.removeAll { SmartFolderDefinition.tagKey($0) == key }
        }
    }
}

struct SmartFolderNotesView: View {
    @EnvironmentObject private var appModel: AppModel
    var smartFolderID: UUID

    private var definition: SmartFolderDefinition? {
        appModel.smartFolders.first { $0.id == smartFolderID }
    }

    private var files: [RecentMarkdownFile] {
        guard let definition else { return [] }
        let now = Date()
        return appModel.libraryFiles.filter {
            $0.relativePath != "Inbox.md" && definition.matches(file: $0, now: now)
        }
    }

    private var memos: [MemoBlock] {
        guard let definition else { return [] }
        let now = Date()
        return appModel.inboxItems.filter { definition.matches(memo: $0, now: now) }
    }

    var body: some View {
        List {
            if files.isEmpty, memos.isEmpty {
                EmptyReaderStateView(
                    title: String(localized: "No Notes"),
                    message: String(localized: "No notes currently match this Smart Folder.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(MudsnoteColors.canvas)
                .listRowSeparator(.hidden)
            }
            if !files.isEmpty {
                Section("Notes") {
                    ForEach(files) { file in
                        NoteFileButton(file: file)
                    }
                }
            }
            if !memos.isEmpty {
                Section("Quick Notes") {
                    ForEach(memos) { memo in
                        MemoCardView(memo: memo)
                            .contentShape(Rectangle())
                            .onTapGesture { appModel.selectedMemo = memo }
                            .listRowInsets(.init(
                                top: 6,
                                leading: MudsnoteSpacing.safeHorizontal,
                                bottom: 6,
                                trailing: MudsnoteSpacing.safeHorizontal
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(MudsnoteColors.canvas)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MudsnoteColors.canvas)
        .navigationTitle(definition?.name ?? String(localized: "Smart Folder"))
        .refreshable { await appModel.refreshInbox() }
    }
}

struct TagsBrowserView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var filter = TagSelectionFilter()
    @State private var tagToRename: String?
    @State private var tagToDelete: String?
    @State private var tagName = ""

    private var files: [RecentMarkdownFile] {
        appModel.libraryFiles.filter { file in
            file.relativePath != "Inbox.md" && filter.matches(tags: file.tags)
        }
    }

    private var memos: [MemoBlock] {
        appModel.inboxItems.filter { filter.matches(tags: $0.tags) }
    }

    var body: some View {
        List {
            Section {
                FlowLayout(spacing: 10, rowSpacing: 10) {
                    ForEach(appModel.tagSummaries) { tag in
                        Menu {
                            Button {
                                beginRenamingTag(tag.name)
                            } label: {
                                Label("Rename Tag", systemImage: "pencil")
                            }
                            .accessibilityLabel("Rename \(tag.name)")
                            .accessibilityIdentifier("rename-tag-\(tag.name)")
                            .disabled(appModel.activeTagMutation != nil)

                            Button(role: .destructive) {
                                beginDeletingTag(tag.name)
                            } label: {
                                Label("Delete Tag", systemImage: "trash")
                            }
                            .accessibilityLabel("Delete \(tag.name)")
                            .accessibilityIdentifier("delete-tag-\(tag.name)")
                            .disabled(appModel.activeTagMutation != nil)
                        } label: {
                            TagFilterChip(
                                title: tag.name,
                                state: filter.state(for: tag.name)
                            )
                        } primaryAction: {
                            filter.cycle(tag.name)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tag-filter-\(tag.name)")
                        .id(tag.name)
                    }
                }
                .id(tagLayoutIdentity)
                .padding(.vertical, 8)

                if filter.included.count > 1 {
                    Picker("Match Tags", selection: $filter.matchMode) {
                        ForEach(TagMatchMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("tag-match-mode")
                }
            } footer: {
                Text("Tap once to include a tag. Tap again to exclude it.")
            }

            if files.isEmpty, memos.isEmpty {
                EmptyReaderStateView(
                    title: String(localized: "No Notes"),
                    message: String(localized: "No notes match these tags.")
                )
                .frame(maxWidth: .infinity)
                .listRowBackground(MudsnoteColors.canvas)
                .listRowSeparator(.hidden)
            }

            if !files.isEmpty {
                Section("Notes") {
                    ForEach(files) { file in
                        NoteFileButton(file: file)
                    }
                }
            }

            if !memos.isEmpty {
                Section("Quick Notes") {
                    ForEach(memos) { memo in
                        MemoCardView(memo: memo)
                            .contentShape(Rectangle())
                            .onTapGesture { appModel.selectedMemo = memo }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    appModel.deleteMemo(memo)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    appModel.pinMemo(memo)
                                } label: {
                                    Label("Pin", systemImage: "pin")
                                }
                                .tint(.yellow)
                            }
                            .listRowInsets(.init(
                                top: 6,
                                leading: MudsnoteSpacing.safeHorizontal,
                                bottom: 6,
                                trailing: MudsnoteSpacing.safeHorizontal
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(MudsnoteColors.canvas)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MudsnoteColors.canvas)
        .navigationTitle("All Tags")
        .refreshable { await appModel.refreshInbox() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !filter.isEmpty {
                    Button("Clear Filters") { filter.clear() }
                        .accessibilityIdentifier("clear-tag-filters")
                }
            }
        }
        .alert("Rename Tag", isPresented: tagRenamePresented) {
            TextField("Tag Name", text: $tagName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let source = tagToRename else { return }
                let name = tagName
                Task { _ = await appModel.renameTag(source, to: name) }
            }
            .disabled(!canRenameTag)
        } message: {
            Text("The tag will be renamed in every active note and quick note.")
        }
        .confirmationDialog(
            deleteTagTitle,
            isPresented: tagDeletePresented,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Tag", role: .destructive) {
                guard let source = tagToDelete else { return }
                Task { _ = await appModel.deleteTag(source) }
            }
        } message: {
            Text("The tag will be removed from every active note and quick note. This cannot be undone.")
        }
        .onChange(of: appModel.tagSummaries.map(\.name)) { _, tags in
            let activeKeys = Set(tags.map(tagKey))
            filter.included = filter.included.filter { activeKeys.contains(tagKey($0)) }
            filter.excluded = filter.excluded.filter { activeKeys.contains(tagKey($0)) }
        }
    }

    private func tagKey(_ tag: String) -> String {
        tag.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }

    private var tagLayoutIdentity: String {
        appModel.tagSummaries.map(\.name).joined(separator: "|")
    }

    private var tagRenamePresented: Binding<Bool> {
        Binding(
            get: { tagToRename != nil },
            set: { if !$0 { tagToRename = nil } }
        )
    }

    private var tagDeletePresented: Binding<Bool> {
        Binding(
            get: { tagToDelete != nil },
            set: { if !$0 { tagToDelete = nil } }
        )
    }

    private var deleteTagTitle: String {
        String(
            format: String(localized: "Remove %@?"),
            locale: .current,
            tagToDelete ?? ""
        )
    }

    private var canRenameTag: Bool {
        guard let source = tagToRename,
              let current = MarkdownTagSyntax.normalizedTag(source),
              let replacement = MarkdownTagSyntax.normalizedTag(tagName) else { return false }
        return current != replacement && appModel.activeTagMutation == nil
    }

    private func beginRenamingTag(_ tag: String) {
        tagToRename = tag
        tagName = String(tag.dropFirst())
    }

    private func beginDeletingTag(_ tag: String) {
        tagToDelete = tag
    }
}

struct TagNotesListView: View {
    @EnvironmentObject private var appModel: AppModel
    var tag: String

    private var files: [RecentMarkdownFile] {
        appModel.libraryFiles.filter { file in
            file.relativePath != "Inbox.md"
                && file.tags.contains(where: matchesTag)
        }
    }

    private var memos: [MemoBlock] {
        appModel.inboxItems.filter { memo in
            memo.tags.contains(where: matchesTag)
        }
    }

    var body: some View {
        List {
            if files.isEmpty, memos.isEmpty {
                EmptyReaderStateView(
                    title: String(localized: "No Notes"),
                    message: String(
                        format: String(localized: "notes.none_for_tag.format"),
                        locale: .current,
                        tag
                    )
                )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(MudsnoteColors.canvas)
                    .listRowSeparator(.hidden)
            }
            if !files.isEmpty {
                Section("Notes") {
                    ForEach(files) { file in
                        NoteFileButton(file: file)
                    }
                }
            }
            if !memos.isEmpty {
                Section("Quick Notes") {
                ForEach(memos) { memo in
                    MemoCardView(memo: memo)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            appModel.selectedMemo = memo
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                appModel.addDefaultTag(to: memo)
                            } label: {
                                Label("Tag", systemImage: "number")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                appModel.deleteMemo(memo)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                appModel.pinMemo(memo)
                            } label: {
                                Label("Pin", systemImage: "pin")
                            }
                            .tint(.yellow)
                        }
                        .listRowInsets(.init(top: 6, leading: MudsnoteSpacing.safeHorizontal, bottom: 6, trailing: MudsnoteSpacing.safeHorizontal))
                        .listRowSeparator(.hidden)
                        .listRowBackground(MudsnoteColors.canvas)
                }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await appModel.refreshInbox()
        }
        .background(MudsnoteColors.canvas)
        .navigationTitle(tag)
    }

    private func matchesTag(_ candidate: String) -> Bool {
        candidate.compare(
            tag,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            range: nil,
            locale: .current
        ) == .orderedSame
    }
}

struct AttachmentLibraryView: View {
    private enum Category: String, CaseIterable, Identifiable {
        case all
        case photos
        case videos
        case audio
        case documents

        var id: String { rawValue }

        var label: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .photos: "Photos"
            case .videos: "Videos"
            case .audio: "Audio"
            case .documents: "Documents"
            }
        }

        var systemImage: String {
            switch self {
            case .all: "square.grid.2x2"
            case .photos: "photo.on.rectangle"
            case .videos: "video"
            case .audio: "waveform"
            case .documents: "doc"
            }
        }
    }

    @EnvironmentObject private var appModel: AppModel
    @State private var attachmentPreview: PreparedAttachmentPreview?
    @State private var category = Category.all

    private var images: [LibraryAttachment] {
        appModel.attachments.filter { $0.kind == .image }
    }

    private var audio: [LibraryAttachment] {
        appModel.attachments.filter { $0.kind == .audio }
    }

    private var videos: [LibraryAttachment] {
        appModel.attachments.filter { $0.kind == .video }
    }

    private var documents: [LibraryAttachment] {
        appModel.attachments.filter { $0.kind == .other }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                categoryBar

            if appModel.attachments.isEmpty {
                ContentUnavailableView(
                    "No Attachments",
                    systemImage: "paperclip",
                        description: Text("Photos, videos, audio, and documents added to notes appear here.")
                )
            } else {
                    if category == .all || category == .photos {
                        attachmentImageSection
                    }
                    if category == .all || category == .videos {
                        attachmentListSection(
                            title: String(localized: "Videos"),
                            attachments: videos,
                            emptyTitle: String(localized: "No Videos"),
                            emptyImage: "video"
                        )
                    }
                    if category == .all || category == .audio {
                        attachmentListSection(
                            title: String(localized: "Audio"),
                            attachments: audio,
                            emptyTitle: String(localized: "No Audio"),
                            emptyImage: "waveform"
                        )
                    }
                    if category == .all || category == .documents {
                        attachmentListSection(
                            title: String(localized: "Documents"),
                            attachments: documents,
                            emptyTitle: String(localized: "No Documents"),
                            emptyImage: "doc"
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(MudsnoteColors.canvas)
        .refreshable {
            await appModel.refreshInbox()
        }
        .navigationTitle("Attachments")
        .fullScreenCover(item: $attachmentPreview) { preview in
            AttachmentQuickLookPreview(
                preview: preview,
                onDismiss: { attachmentPreview = nil },
                onSave: { editedURL in
                    Task {
                        await appModel.commitEditedAttachmentPreview(
                            preview,
                            editedURL: editedURL
                        )
                    }
                }
            )
            .ignoresSafeArea()
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Category.allCases) { candidate in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            category = candidate
                        }
                    } label: {
                        Label(candidate.label, systemImage: candidate.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                category == candidate ? Color.black : MudsnoteColors.text
                            )
                            .padding(.horizontal, 13)
                            .frame(height: 36)
                            .background(
                                category == candidate
                                    ? NotesCloneColors.folderYellow
                                    : MudsnoteColors.card,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("attachment-category-\(candidate.rawValue)")
                }
            }
        }
    }

    @ViewBuilder
    private var attachmentImageSection: some View {
        if !images.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Photos")
                    .font(.title3.bold())
                    .foregroundStyle(MudsnoteColors.text)
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ],
                    spacing: 12
                ) {
                    ForEach(images) { attachment in
                        attachmentImageCard(attachment)
                    }
                }
            }
        } else if category == .photos {
            ContentUnavailableView("No Photos", systemImage: "photo.on.rectangle")
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func attachmentListSection(
        title: String,
        attachments: [LibraryAttachment],
        emptyTitle: String,
        emptyImage: String
    ) -> some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.title3.bold())
                    .foregroundStyle(MudsnoteColors.text)
                VStack(spacing: 1) {
                    ForEach(attachments) { attachment in
                        attachmentRow(attachment)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        } else if category != .all {
            ContentUnavailableView(emptyTitle, systemImage: emptyImage)
                .frame(maxWidth: .infinity)
        }
    }

    private func attachmentImageCard(_ attachment: LibraryAttachment) -> some View {
        Button {
            openPreview(attachment)
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                AttachmentImageThumbnail(attachment: attachment)
                    .frame(height: 126)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                Text(attachment.fileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(MudsnoteColors.text)
                    .lineLimit(1)
                Text(attachmentMetadata(attachment))
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(1)
            }
            .padding(8)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("attachment-row-\(attachment.id)")
        .contextMenu { ownerActions(attachment) }
    }

    private func attachmentRow(_ attachment: LibraryAttachment) -> some View {
        Button {
            openPreview(attachment)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: attachment.kind.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(MudsnoteColors.primary)
                    .frame(width: 40, height: 40)
                    .background(
                        MudsnoteColors.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.fileName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(MudsnoteColors.text)
                        .lineLimit(1)
                    Text(attachmentMetadata(attachment))
                        .font(.caption)
                        .foregroundStyle(MudsnoteColors.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MudsnoteColors.muted)
            }
            .padding(12)
            .background(MudsnoteColors.card)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("attachment-row-\(attachment.id)")
        .contextMenu { ownerActions(attachment) }
    }

    @ViewBuilder
    private func ownerActions(_ attachment: LibraryAttachment) -> some View {
        if attachment.owners.count == 1, let owner = attachment.owners.first {
            Button {
                appModel.openAttachmentOwner(owner)
            } label: {
                Label("Show in Note", systemImage: "note.text")
            }
            .accessibilityIdentifier("show-attachment-in-note-\(attachment.id)")
        } else if !attachment.owners.isEmpty {
            Menu {
                ForEach(attachment.owners) { owner in
                    Button(owner.title) {
                        appModel.openAttachmentOwner(owner)
                    }
                }
            } label: {
                Label("Show in Note", systemImage: "note.text")
            }
        }
    }

    private func openPreview(_ attachment: LibraryAttachment) {
        Task {
            attachmentPreview = await appModel.prepareAttachmentPreview(for: attachment)
        }
    }

    private func attachmentMetadata(_ attachment: LibraryAttachment) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: attachment.byteCount,
            countStyle: .file
        )
        return "\(size) · \(attachment.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct AttachmentImageThumbnail: View {
    @EnvironmentObject private var appModel: AppModel
    var attachment: LibraryAttachment
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            MudsnoteColors.panel
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(MudsnoteColors.muted)
            }
        }
        .clipped()
        .task(id: attachment.id) {
            guard let data = await appModel.attachmentThumbnailData(for: attachment) else {
                return
            }
            image = Self.thumbnail(from: data)
        }
    }

    private static func thumbnail(from data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 640,
                ] as CFDictionary
              ) else { return nil }
        return UIImage(cgImage: image)
    }
}

struct LibraryFolderRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var count: Int?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.yellow)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(MudsnoteColors.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(1)
            }

            Spacer()

            if let count {
                Text("\(count)")
                    .foregroundStyle(MudsnoteColors.muted)
            }
        }
        .padding(.vertical, 3)
    }
}

struct RecentFileRow: View {
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis = .modified
    var showsFolder = true

    private var displayedDate: Date { dateBasis.date(for: file) }

    private var dateText: String {
        if Calendar.autoupdatingCurrent.isDateInToday(displayedDate) {
            return displayedDate.formatted(date: .omitted, time: .shortened)
        }
        return displayedDate.formatted(date: .abbreviated, time: .omitted)
    }

    private var folderName: String {
        let parent = (file.relativePath as NSString).deletingLastPathComponent
        return parent.isEmpty ? String(localized: "Mudsnote") : (parent as NSString).lastPathComponent
    }

    var body: some View {
        NotesListRowContent(
            title: file.title,
            dateText: dateText,
            preview: file.preview,
            folderName: showsFolder ? folderName : nil,
            checklistItems: file.galleryChecklistItems,
            hasAttachments: file.hasAttachments,
            hasUncheckedChecklist: file.hasUncheckedChecklist,
            isPinned: file.isPinned,
            pinIdentifier: "pin-indicator-\(file.id)"
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open Markdown file")
    }
}

struct NotesListRowContent: View {
    var title: String
    var dateText: String
    var preview: String
    var folderName: String?
    var checklistItems: [MarkdownGalleryChecklistItem] = []
    var hasAttachments = false
    var hasUncheckedChecklist = false
    var isPinned = false
    var pinIdentifier: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(MudsnoteColors.text)
                    .lineLimit(2)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(dateText)
                        .lineLimit(1)
                    detailBadges
                }
                .font(.subheadline)
                .foregroundStyle(MudsnoteColors.muted)

                noteDetails

                if let folderName {
                    HStack(spacing: 5) {
                        Image(systemName: "folder")
                        Text(folderName)
                    }
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NotesCloneColors.folderYellow)
                    .accessibilityLabel("Pinned")
                    .accessibilityIdentifier(pinIdentifier ?? "pin-indicator")
            }
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(MudsnoteColors.card)
    }

    @ViewBuilder
    private var noteDetails: some View {
        if !checklistItems.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(checklistItems.prefix(2).enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(
                                item.isChecked ? NotesCloneColors.folderYellow : MudsnoteColors.muted
                            )
                        Text(item.text)
                            .font(.subheadline)
                            .foregroundStyle(MudsnoteColors.muted)
                            .lineLimit(1)
                    }
                }
            }
        } else if !preview.isEmpty {
            Text(preview)
                .font(.subheadline)
                .foregroundStyle(MudsnoteColors.muted)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var detailBadges: some View {
        if hasUncheckedChecklist {
            Label("Open Tasks", systemImage: "checklist")
                .labelStyle(.iconOnly)
                .accessibilityLabel("Has Open Tasks")
        }
        if hasAttachments {
            Label("Has Attachments", systemImage: "paperclip")
                .labelStyle(.iconOnly)
                .accessibilityLabel("Has Attachments")
        }
    }
}

struct RecentSearchView: View {
    @EnvironmentObject private var appModel: AppModel

    var filteredFiles: [RecentMarkdownFile] {
        guard !appModel.query.isEmpty else { return appModel.recentFiles }
        return appModel.recentFiles.filter {
            $0.title.localizedCaseInsensitiveContains(appModel.query)
                || $0.relativePath.localizedCaseInsensitiveContains(appModel.query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filteredFiles.isEmpty {
                    EmptyReaderStateView(
                        title: String(localized: "No Recent Files"),
                        message: String(localized: "Inbox and Daily files appear here after the folder is initialized.")
                    )
                } else {
                    List(filteredFiles) { file in
                        RecentFileRow(file: file)
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .searchable(text: $appModel.query, prompt: "Search recent Markdown")
            .navigationTitle("Recent")
            .background(MudsnoteColors.canvas)
        }
    }
}
