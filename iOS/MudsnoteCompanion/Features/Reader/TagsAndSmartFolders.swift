import SwiftUI
import ImageIO
import UIKit

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
            definition.matches(file: $0, now: now)
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
            filter.matches(tags: file.tags)
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
    @State private var memoForTagging: MemoBlock?
    var tag: String

    private var files: [RecentMarkdownFile] {
        appModel.libraryFiles.filter { file in
            file.tags.contains(where: matchesTag)
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
                                memoForTagging = memo
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
        .sheet(item: $memoForTagging) { memo in
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

    private func matchesTag(_ candidate: String) -> Bool {
        candidate.compare(
            tag,
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            range: nil,
            locale: .current
        ) == .orderedSame
    }
}
