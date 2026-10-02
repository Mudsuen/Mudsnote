import SwiftUI
import ImageIO
import UIKit

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

struct NoteLifecycleActions: ViewModifier {
    @EnvironmentObject private var appModel: AppModel
    var file: RecentMarkdownFile
    @State private var noteName = ""
    @State private var isRenaming = false
    @State private var isMovePickerPresented = false
    @State private var isTagPickerPresented = false

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
                if appModel.canReorganize(file) {
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
                    if appModel.canReorganize(file), canMove {
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
                    Task {
                        if let document = await appModel.loadDocument(
                            relativePath: file.relativePath
                        ) {
                            UIPasteboard.general.string = document.markdown
                        }
                    }
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .accessibilityIdentifier("copy-note-\(file.id)")

                Button {
                    appModel.openFile(file, mode: .edit)
                } label: {
                    Label("Edit", systemImage: "square.and.pencil")
                }
                .accessibilityIdentifier("edit-note-\(file.id)")

                if appModel.canReorganize(file) {
                    Button {
                        isTagPickerPresented = true
                    } label: {
                        Label("Tag", systemImage: "number")
                    }
                    .accessibilityIdentifier("tag-note-\(file.id)")
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
                if appModel.canReorganize(file),
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
            .sheet(isPresented: $isTagPickerPresented) {
                NoteTagPickerView(
                    noteText: "\(file.title)\n\(file.preview)",
                    existingTags: file.tags,
                    addTag: { tag in
                        await appModel.addTag(tag, to: file)
                    }
                )
                .environmentObject(appModel)
            }
    }
}

struct NoteMovePicker: View {
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
