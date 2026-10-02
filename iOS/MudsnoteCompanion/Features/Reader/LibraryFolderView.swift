import SwiftUI
import ImageIO
import UIKit

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
        .notesGlassBottomToolbar()
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
                voiceInput: {
                    isSearchFocused = false
                    appModel.showCapture(.audio, inFolder: currentFolder.relativePath)
                },
                newNote: {
                    isSearchFocused = false
                    appModel.showCapture(.text, inFolder: currentFolder.relativePath)
                }
            )
        }
    }

    private var folderGallery: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
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

struct FolderLifecycleActions: ViewModifier {
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

struct SelectableNoteFileRow: View {
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

struct SelectedNotesActionBar: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isConfirmingDelete = false
    var files: [RecentMarkdownFile]
    var destinations: [LibraryFolderNode]
    var finish: () -> Void

    private var canMoveOrDelete: Bool {
        !files.isEmpty && files.allSatisfy(appModel.canReorganize)
    }

    private var canDelete: Bool {
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
            .disabled(!canDelete)
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

struct NoteGallerySection: View {
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
            }
        }
    }
}

struct HomeTimelineCardSection: View {
    @EnvironmentObject private var appModel: AppModel
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
                    .task(id: entry.fileNeedingContent?.relativePath) {
                        guard let file = entry.fileNeedingContent else { return }
                        await appModel.loadLibraryContentIfNeeded(for: file)
                    }
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
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("home-section-header-\(section.id)")
            }
        }
    }
}

struct HomeTimelineListSection: View {
    @EnvironmentObject private var appModel: AppModel
    var section: HomeTimelineSection
    var isSelecting: Bool
    var selectedIDs: Set<String>
    var toggleSelection: (HomeTimelineEntry) -> Void

    var body: some View {
        Section {
            LazyVStack(spacing: 10) {
                ForEach(section.entries) { entry in
                    HomeTimelineListEntryButton(
                        entry: entry,
                        isSelecting: isSelecting,
                        isSelected: selectedIDs.contains(entry.id),
                        toggleSelection: { toggleSelection(entry) }
                    )
                    .padding(.horizontal, 14)
                    .mudsnoteGlassSurface(
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(MudsnoteColors.line, lineWidth: 1)
                    }
                    .task(id: entry.fileNeedingContent?.relativePath) {
                        guard let file = entry.fileNeedingContent else { return }
                        await appModel.loadLibraryContentIfNeeded(for: file)
                    }
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
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("home-section-header-\(section.id)")
            }
        }
    }
}

struct HomeTimelineGalleryEntryButton: View {
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
            .foregroundStyle(isSelected ? MudsnoteColors.primary : MudsnoteColors.muted)
    }
}

struct HomeTimelineListEntryButton: View {
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
                            isSelected ? MudsnoteColors.primary : MudsnoteColors.muted
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

struct HomeMemoCardButton: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isTagPickerPresented = false
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
                UIPasteboard.general.string = memo.body
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            Button {
                appModel.pinMemo(memo)
            } label: {
                Label("Pin", systemImage: "pin")
            }
            Button {
                isTagPickerPresented = true
            } label: {
                Label("Tag", systemImage: "number")
            }
            Button(role: .destructive) {
                appModel.deleteMemo(memo)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $isTagPickerPresented) {
            NoteTagPickerView(
                noteText: memo.body,
                existingTags: memo.tags,
                addTag: { tag in
                    await appModel.addTag(tag, to: memo)
                }
            )
            .environmentObject(appModel)
        }
    }
}

struct HomeMemoCard: View {
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

    private var preview: String { contentLines.dropFirst().joined(separator: "\n") }
    private var dateText: String {
        memo.dateText.split(separator: " ").last.map(String.init) ?? memo.dateText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Image(systemName: "tray")
                    Text("000-inbox").lineLimit(1)
                    Spacer(minLength: 0)
                    if memo.hasUncheckedChecklist { Image(systemName: "checklist") }
                    if memo.hasAttachments { Image(systemName: "paperclip") }
                }
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
                Text(title)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(MudsnoteColors.text)
                    .lineLimit(2)
                if !preview.isEmpty {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(MudsnoteColors.muted)
                        .lineLimit(5)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .mudsnoteGlassSurface(in: RoundedRectangle(cornerRadius: 14))
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

struct HomeMemoListRow: View {
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
            preview: lines.dropFirst().joined(separator: "\n"),
            folderName: "000-inbox",
            hasAttachments: memo.hasAttachments,
            hasUncheckedChecklist: memo.hasUncheckedChecklist
        )
    }
}

struct HomeSelectedNotesActionBar: View {
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

struct NoteGalleryFileButton: View {
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

struct SelectableNoteGalleryCard: View {
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

struct NoteGalleryCard: View {
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
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(folderName)
                        .lineLimit(1)
                        .accessibilityIdentifier("gallery-folder-\(file.id)")
                    Spacer(minLength: 0)
                    if file.hasAttachments {
                        Image(systemName: "paperclip")
                    }
                }
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
                Text(file.title)
                    .font(.system(.body, design: .rounded, weight: .bold))
                    .foregroundStyle(MudsnoteColors.text)
                    .lineLimit(2)
                galleryPreview
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
            .mudsnoteGlassSurface(in: RoundedRectangle(cornerRadius: 14))
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
        } else if !file.preview.isEmpty {
            Text(file.preview)
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
