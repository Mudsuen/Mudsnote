import SwiftUI
import ImageIO
import UIKit

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

struct SelectableTrashedMarkdownRow: View {
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

struct SelectedDeletedNotesActionBar: View {
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

struct TrashedMarkdownRow: View {
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

enum NotesCloneColors {
    static let background = MudsnoteColors.canvas
    static let separator = MudsnoteColors.line
    static let folderYellow = Color(hex: 0xD7BD68)
    static let chip = Color(hex: 0x22262F)
}
