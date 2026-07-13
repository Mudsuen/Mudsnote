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
    var chooseFolder: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                if normalizedSearchQuery.isEmpty {
                    VStack(alignment: .leading, spacing: 22) {
                        accountSection
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
                Button("Create") {
                    let name = newFolderName
                    Task { _ = await appModel.createFolder(named: name) }
                }
                .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NotesSectionHeader(title: String(localized: "Tags"))
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

private struct NoteListSortMenu: View {
    @Binding var sortOrderRawValue: String
    @Binding var groupByDate: Bool

    var body: some View {
        Menu {
            NoteListSortMenuContent(
                sortOrderRawValue: $sortOrderRawValue,
                groupByDate: $groupByDate
            )
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
        }
        .accessibilityLabel("Sort Notes")
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

    var body: some View {
        List {
            if files.isEmpty {
                Text("No Notes")
                    .foregroundStyle(MudsnoteColors.muted)
            } else {
                if !pinnedFiles.isEmpty {
                    Section("Pinned") {
                        ForEach(pinnedFiles) { file in
                            NoteFileButton(file: file, dateBasis: sortOrder.dateBasis)
                        }
                    }
                }
                ForEach(otherSections) { section in
                    Section {
                        ForEach(section.files) { file in
                            NoteFileButton(file: file, dateBasis: sortOrder.dateBasis)
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
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NoteListSortMenu(
                    sortOrderRawValue: $sortOrderRawValue,
                    groupByDate: $groupByDate
                )
            }
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
}

struct LibraryFolderView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    var folder: LibraryFolderNode
    @State private var isCreatingFolder = false
    @State private var isRenamingFolder = false
    @State private var isConfirmingDelete = false
    @State private var folderName = ""
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

    var body: some View {
        List {
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

            if !pinnedFiles.isEmpty {
                Section("Pinned") {
                    ForEach(pinnedFiles) { file in
                        NoteFileButton(file: file, dateBasis: sortOrder.dateBasis)
                    }
                }
            }
            ForEach(otherSections) { section in
                Section {
                    ForEach(section.files) { file in
                        NoteFileButton(file: file, dateBasis: sortOrder.dateBasis)
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
        .navigationTitle(currentFolder.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
                }
                if appModel.canMoveToRecentlyDeleted(file), !appModel.allFolders.isEmpty {
                    Menu {
                        ForEach(appModel.allFolders) { folder in
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
    }
}

struct RecentlyDeletedView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var pendingPermanentDelete: TrashedMarkdownFile?

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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(MudsnoteColors.canvas)
        .refreshable {
            await appModel.refreshInbox()
        }
        .navigationTitle("Recently Deleted")
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
