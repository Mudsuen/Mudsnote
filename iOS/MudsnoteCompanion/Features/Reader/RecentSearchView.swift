import QuickLook
import SwiftUI

struct LibraryHomeView: View {
    private struct SearchTaskID: Hashable {
        var query: String
        var scope: MarkdownSearchScope
        var libraryRevision: Int
    }

    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isSearchFocused: Bool
    @State private var searchQuery = ""
    @State private var searchScope = MarkdownSearchScope.all
    @State private var isCreatingFolder = false
    @State private var newFolderName = ""
    @State private var smartFolderEditor: SmartFolderDefinition?
    @State private var smartFolderToDelete: SmartFolderDefinition?
    var chooseFolder: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                if normalizedSearchQuery.isEmpty {
                    VStack(alignment: .leading, spacing: 22) {
                        accountSection
                        if !appModel.smartFolders.isEmpty {
                            smartFoldersSection
                        }
                        if !appModel.folders.isEmpty {
                            foldersSection
                        }
                        if !appModel.tagSummaries.isEmpty {
                            tagsSection
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                } else {
                    searchSection
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NotesCloneColors.background)
            .refreshable {
                await appModel.refreshInbox()
            }
            .navigationTitle("Folders")
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        newFolderName = ""
                        isCreatingFolder = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(MudsnoteColors.text)
                            .frame(width: 40, height: 40)
                            .background(MudsnoteColors.card, in: Circle())
                            .overlay {
                                Circle().stroke(MudsnoteColors.line, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New Folder")
                    .accessibilityIdentifier("new-folder-button")
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
            .safeAreaInset(edge: .bottom) {
                NotesBottomCommandBar(
                    searchText: $searchQuery,
                    searchFocused: $isSearchFocused
                ) {
                    isSearchFocused = false
                    appModel.showCapture(.audio)
                } newNote: {
                    isSearchFocused = false
                    appModel.createStandaloneNote()
                } quickNote: {
                    isSearchFocused = false
                    appModel.showCapture(.text)
                }
            }
        }
    }

    @ViewBuilder
    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotesSectionHeader(title: String(localized: "Folders"))
            notesCard {
                ForEach(appModel.folders) { folder in
                    NavigationLink {
                        LibraryFolderView(folder: folder)
                    } label: {
                        NotesFolderRow(
                            title: folder.name,
                            systemImage: "folder.fill",
                            count: folder.totalNoteCount
                        )
                    }
                    .accessibilityIdentifier("folder-row-\(folder.relativePath)")
                    .modifier(FolderLifecycleActions(folder: folder))
                }
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotesSectionHeader(title: rootSectionTitle)

            notesCard {
                NavigationLink {
                    InboxStreamView()
                } label: {
                    NotesFolderRow(title: String(localized: "Inbox"), systemImage: "tray.full", count: appModel.librarySummary.inboxCount)
                }

                NavigationLink {
                    FolderNotesListView(
                        title: String(localized: "Daily"),
                        scope: .pathPrefix("Daily/")
                    )
                } label: {
                    NotesFolderRow(title: String(localized: "Daily"), systemImage: "calendar", count: appModel.librarySummary.dailyCount)
                }

                NavigationLink {
                    FolderNotesListView(title: String(localized: "All Notes"), scope: .all)
                } label: {
                    NotesFolderRow(title: String(localized: "All Notes"), systemImage: "doc.text", count: appModel.librarySummary.allNotesCount)
                }
                .accessibilityIdentifier("all-notes-link")

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

                NavigationLink {
                    SettingsRulesView(chooseFolder: chooseFolder)
                } label: {
                    NotesFolderRow(title: String(localized: "Settings"), systemImage: "gearshape", count: nil)
                }
                .accessibilityIdentifier("settings-link")
            }
        }
    }

    @ViewBuilder
    private var smartFoldersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotesSectionHeader(title: String(localized: "Smart Folders"))
            notesCard {
                ForEach(appModel.smartFolders) { definition in
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

            if searchIsPending {
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
                        Button {
                            isSearchFocused = false
                            appModel.openSearchResult(result)
                        } label: {
                            SearchResultRow(
                                result: result,
                                query: appModel.completedSearchQuery
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search-result-\(result.id)")
                    }
                }
            }
        }
    }

    private var normalizedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
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
        appModel.libraryFiles.lazy.filter {
            $0.relativePath != "Inbox.md" && definition.matches(file: $0)
        }.count + appModel.inboxItems.lazy.filter { definition.matches(memo: $0) }.count
    }

    private var rootSectionTitle: String {
        if case .ready(let url) = appModel.folderStatus {
            return url.lastPathComponent
        }
        return "Mudsnote"
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
        by order: NoteSortOrder
    ) -> [RecentMarkdownFile] {
        files.sorted { lhs, rhs in
            switch order {
            case .modified:
                if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
            case .created:
                let lhsDate = lhs.createdAt == .distantPast ? lhs.modifiedAt : lhs.createdAt
                let rhsDate = rhs.createdAt == .distantPast ? rhs.modifiedAt : rhs.createdAt
                if lhsDate != rhsDate { return lhsDate > rhsDate }
            case .title:
                let comparison = lhs.title.localizedStandardCompare(rhs.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return lhs.relativePath.localizedStandardCompare(rhs.relativePath) == .orderedAscending
        }
    }

    static func sections(
        for files: [RecentMarkdownFile],
        sortedBy order: NoteSortOrder,
        groupByDate: Bool,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> [NoteDateSection] {
        let ordered = sorted(files, by: order)
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

    private static func dateBucket(
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
    @Binding var sortOrderRawValue: String
    @Binding var groupByDate: Bool
    var selectNotes: () -> Void

    var body: some View {
        Menu {
            Button(action: selectNotes) {
                Label("Select Notes", systemImage: "checkmark.circle")
            }
            Divider()
            NoteListSortMenuContent(
                sortOrderRawValue: $sortOrderRawValue,
                groupByDate: $groupByDate
            )
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Sort Notes")
        .accessibilityIdentifier("note-list-options")
    }
}

private struct NoteListSortMenuContent: View {
    @Binding var sortOrderRawValue: String
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
        Toggle("Group By Date", isOn: $groupByDate)
            .disabled(sortOrder == .title)
    }
}

struct FolderNotesListView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("mudsnote.ios.noteSortOrder") private var sortOrderRawValue = NoteSortOrder.modified.rawValue
    @AppStorage("mudsnote.ios.groupNotesByDate") private var groupByDate = true
    @State private var isSelecting = false
    @State private var selectedPaths = Set<String>()
    var title: String
    var scope: LibraryFileScope

    private var files: [RecentMarkdownFile] {
        scope.files(from: appModel.libraryFiles)
    }

    private var sortOrder: NoteSortOrder {
        NoteSortOrder(rawValue: sortOrderRawValue) ?? .modified
    }
    private var pinnedFiles: [RecentMarkdownFile] {
        NoteListPresentation.sorted(files.filter(\.isPinned), by: sortOrder)
    }
    private var otherSections: [NoteDateSection] {
        NoteListPresentation.sections(
            for: files.filter { !$0.isPinned },
            sortedBy: sortOrder,
            groupByDate: groupByDate
        )
    }
    private var selectedFiles: [RecentMarkdownFile] {
        files.filter { selectedPaths.contains($0.relativePath) }
    }

    var body: some View {
        List {
            if files.isEmpty {
                Text("No Notes")
                    .foregroundStyle(MudsnoteColors.muted)
            } else {
                if !pinnedFiles.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedFiles) { file in
                            noteRow(file)
                        }
                    }
                }
                ForEach(otherSections) { section in
                    Section {
                        ForEach(section.files) { file in
                            noteRow(file)
                        }
                    } header: {
                        if let title = section.title {
                            Text(title)
                        } else if !pinnedFiles.isEmpty {
                            Text("Notes")
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
                        sortOrderRawValue: $sortOrderRawValue,
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
        .onChange(of: files.map(\.relativePath)) { _, paths in
            selectedPaths.formIntersection(paths)
        }
    }

    @ViewBuilder
    private func noteRow(_ file: RecentMarkdownFile) -> some View {
        if isSelecting {
            SelectableNoteFileRow(
                file: file,
                dateBasis: sortOrder.dateBasis,
                isSelected: selectedPaths.contains(file.relativePath)
            ) {
                if !selectedPaths.insert(file.relativePath).inserted {
                    selectedPaths.remove(file.relativePath)
                }
            }
        } else {
            NoteFileButton(file: file, dateBasis: sortOrder.dateBasis)
        }
    }

    private func finishSelecting() {
        selectedPaths.removeAll()
        isSelecting = false
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
}

struct LibraryFolderView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    var folder: LibraryFolderNode
    @State private var isCreatingFolder = false
    @State private var isRenamingFolder = false
    @State private var isConfirmingDelete = false
    @State private var folderName = ""
    @State private var isSelecting = false
    @State private var selectedPaths = Set<String>()
    @AppStorage("mudsnote.ios.noteSortOrder") private var sortOrderRawValue = NoteSortOrder.modified.rawValue
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
    private var pinnedFiles: [RecentMarkdownFile] {
        NoteListPresentation.sorted(directFiles.filter(\.isPinned), by: sortOrder)
    }
    private var otherSections: [NoteDateSection] {
        NoteListPresentation.sections(
            for: directFiles.filter { !$0.isPinned },
            sortedBy: sortOrder,
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

    var body: some View {
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
                Section("Pinned") {
                    ForEach(pinnedFiles) { file in
                        noteRow(file)
                    }
                }
            }
            ForEach(otherSections) { section in
                Section {
                    ForEach(section.files) { file in
                        noteRow(file)
                    }
                } header: {
                    if let title = section.title {
                        Text(title)
                    } else if !pinnedFiles.isEmpty {
                        Text("Notes")
                    }
                }
            }

            if currentFolder.children.isEmpty, directFiles.isEmpty {
                ContentUnavailableView("No Notes", systemImage: "folder")
                    .listRowBackground(Color.clear)
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
                    selectedPaths.count
                )
                : currentFolder.name
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if isSelecting {
                    Button(selectedPaths.count == directFiles.count ? "Deselect All" : "Select All") {
                        if selectedPaths.count == directFiles.count {
                            selectedPaths.removeAll()
                        } else {
                            selectedPaths = Set(directFiles.map(\.relativePath))
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
                    Menu {
                        if currentFolder.relativePath.contains("/") {
                            Button {
                                let target = currentFolder
                                Task {
                                    if await appModel.moveFolder(target, to: nil) { dismiss() }
                                }
                            } label: {
                                Label("Top Level", systemImage: "tray")
                            }
                        }
                        ForEach(moveDestinations) { destination in
                            Button {
                                let target = currentFolder
                                Task {
                                    if await appModel.moveFolder(target, to: destination) { dismiss() }
                                }
                            } label: {
                                Label(destination.relativePath, systemImage: "folder")
                            }
                        }
                    } label: {
                        Label("Move Folder", systemImage: "folder.badge.arrow.forward")
                    }
                    Button {
                        appModel.createStandaloneNote(inFolder: currentFolder.relativePath)
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                    Divider()
                    NoteListSortMenuContent(
                        sortOrderRawValue: $sortOrderRawValue,
                        groupByDate: $groupByDate
                    )
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Folder Actions")
                .accessibilityIdentifier("folder-actions")
                }
            }
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
            Button("Move Notes to Recently Deleted", role: .destructive) {
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
    }

    @ViewBuilder
    private func noteRow(_ file: RecentMarkdownFile) -> some View {
        if isSelecting {
            SelectableNoteFileRow(
                file: file,
                dateBasis: sortOrder.dateBasis,
                isSelected: selectedPaths.contains(file.relativePath)
            ) {
                if !selectedPaths.insert(file.relativePath).inserted {
                    selectedPaths.remove(file.relativePath)
                }
            }
        } else {
            NoteFileButton(file: file, dateBasis: sortOrder.dateBasis)
        }
    }

    private func finishSelecting() {
        selectedPaths.removeAll()
        isSelecting = false
    }
}

private struct FolderLifecycleActions: ViewModifier {
    @EnvironmentObject private var appModel: AppModel
    var folder: LibraryFolderNode
    @State private var folderName = ""
    @State private var isCreatingSubfolder = false
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false

    private var moveDestinations: [LibraryFolderNode] {
        appModel.allFolders.filter {
            $0.relativePath != folder.relativePath
                && !$0.relativePath.hasPrefix(folder.relativePath + "/")
        }
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    isConfirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .contextMenu {
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
                Button("Move Notes to Recently Deleted", role: .destructive) {
                    let target = folder
                    Task { _ = await appModel.deleteFolder(target) }
                }
            } message: {
                Text("Notes in this folder will move to Recently Deleted. Other files will be preserved.")
            }
    }
}

private struct SelectableNoteFileRow: View {
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis
    var isSelected: Bool
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? NotesCloneColors.folderYellow : MudsnoteColors.muted)
                RecentFileRow(file: file, dateBasis: dateBasis)
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
            "Move Selected Notes to Recently Deleted?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Move to Recently Deleted", role: .destructive) {
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

private struct NoteFileButton: View {
    @EnvironmentObject private var appModel: AppModel
    var file: RecentMarkdownFile
    var dateBasis: NoteDateBasis = .modified

    var body: some View {
        Button {
            appModel.openFile(file)
        } label: {
            RecentFileRow(file: file, dateBasis: dateBasis)
        }
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

    private var currentFolder: String {
        (file.relativePath as NSString).deletingLastPathComponent
    }

    private var moveDestinations: [LibraryFolderNode] {
        appModel.allFolders.filter { $0.relativePath != currentFolder }
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
                }
            }
            .contextMenu {
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
                        Label("Move to Recently Deleted", systemImage: "trash")
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
                        Image(systemName: "ellipsis.circle")
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
    var iconTint: Color = NotesCloneColors.folderYellow
    var count: Int?

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 36, height: 36)
                .background(iconTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            Text(title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(MudsnoteColors.text)

            Spacer()

            if let count {
                Text("\(count)")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(MudsnoteColors.muted)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MudsnoteColors.muted.opacity(0.7))
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(NotesCloneColors.separator)
                .frame(height: 1)
                .padding(.leading, 72)
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

struct NotesBottomCommandBar: View {
    @Binding var searchText: String
    var searchFocused: FocusState<Bool>.Binding
    var record: () -> Void
    var newNote: () -> Void
    var quickNote: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                TextField("Search", text: $searchText)
                    .font(.body)
                    .focused(searchFocused)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .accessibilityIdentifier("library-search-field")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                    .accessibilityIdentifier("clear-library-search")
                }
                Button(action: record) {
                    Image(systemName: "mic")
                        .font(.system(size: 21, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .fixedSize()
                .accessibilityLabel("Voice input")

                Button(action: quickNote) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .fixedSize()
                .accessibilityLabel("Quick Note")
                .accessibilityIdentifier("quick-note-button")
            }
            .foregroundStyle(MudsnoteColors.text)
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(MudsnoteColors.panel, in: Capsule())
            .overlay {
                Capsule().stroke(MudsnoteColors.line, lineWidth: 1)
            }

            Button(action: newNote) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 23, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(Color.black)
                    .frame(width: 54, height: 54)
                    .background(NotesCloneColors.folderYellow, in: Circle())
                    .overlay {
                        Circle().stroke(MudsnoteColors.line.opacity(0.25), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("New note")
            .accessibilityIdentifier("new-note-button")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            LinearGradient(
                colors: [MudsnoteColors.canvas.opacity(0), MudsnoteColors.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
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
    @EnvironmentObject private var appModel: AppModel
    @State private var previewURL: URL?

    var body: some View {
        List {
            if appModel.attachments.isEmpty {
                ContentUnavailableView(
                    "No Attachments",
                    systemImage: "paperclip",
                    description: Text("Images and audio added to notes appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(appModel.attachments) { attachment in
                    Button {
                        Task {
                            previewURL = await appModel.previewURL(for: attachment)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: attachment.kind.systemImage)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(MudsnoteColors.primary)
                                .frame(width: 38, height: 38)
                                .background(MudsnoteColors.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

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
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("attachment-row-\(attachment.id)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(MudsnoteColors.canvas)
        .refreshable {
            await appModel.refreshInbox()
        }
        .navigationTitle("Attachments")
        .quickLookPreview($previewURL)
    }

    private func attachmentMetadata(_ attachment: LibraryAttachment) -> String {
        let size = ByteCountFormatter.string(
            fromByteCount: attachment.byteCount,
            countStyle: .file
        )
        return "\(size) · \(attachment.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
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
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(file.title)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(MudsnoteColors.text)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(dateText)
                        .foregroundStyle(MudsnoteColors.muted)
                    if !file.preview.isEmpty {
                        Text(file.preview)
                            .foregroundStyle(MudsnoteColors.muted)
                            .lineLimit(1)
                    }
                }
                .font(.subheadline)
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(folderName)
                    if file.hasAttachments {
                        Image(systemName: "paperclip")
                            .padding(.leading, 4)
                    }
                }
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if file.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NotesCloneColors.folderYellow)
                    .accessibilityLabel("Pinned")
                    .accessibilityIdentifier("pin-indicator-\(file.id)")
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowBackground(MudsnoteColors.card)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open Markdown file")
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
