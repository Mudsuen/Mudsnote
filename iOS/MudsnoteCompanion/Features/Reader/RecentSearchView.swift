import QuickLook
import SwiftUI

enum LibraryDestination: Hashable {
    case allNotes
    case inbox
    case daily
    case templates
    case attachments
    case tag(String)
    case settings
}

struct LibraryHomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var searchQuery = ""
    var chooseFolder: () -> Void

    private var filteredFiles: [RecentMarkdownFile] {
        guard !searchQuery.isEmpty else { return [] }
        return appModel.libraryFiles.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery)
                || $0.relativePath.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if searchQuery.isEmpty {
                    VStack(alignment: .leading, spacing: 22) {
                        accountSection
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
            .background(NotesCloneColors.background)
            .refreshable {
                await appModel.refreshInbox()
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        chooseFolder()
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
                    .accessibilityLabel("Choose library folder")
                }
            }
            .safeAreaInset(edge: .bottom) {
                NotesBottomCommandBar(searchText: $searchQuery) {
                    appModel.showCapture(.audio)
                } newNote: {
                    appModel.showCapture(.text)
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
                        files: appModel.libraryFiles.filter { $0.relativePath.hasPrefix("Daily/") }
                    )
                } label: {
                    NotesFolderRow(title: String(localized: "Daily"), systemImage: "calendar", count: appModel.librarySummary.dailyCount)
                }

                NavigationLink {
                    FolderNotesListView(title: String(localized: "All Notes"), files: appModel.libraryFiles)
                } label: {
                    NotesFolderRow(title: String(localized: "All Notes"), systemImage: "doc.text", count: appModel.librarySummary.allNotesCount)
                }
                .accessibilityIdentifier("all-notes-link")

                NavigationLink {
                    FolderNotesListView(
                        title: String(localized: "Templates"),
                        files: appModel.libraryFiles.filter { $0.relativePath.hasPrefix("Templates/") }
                    )
                } label: {
                    NotesFolderRow(title: String(localized: "Templates"), systemImage: "folder", count: appModel.librarySummary.templateCount)
                }

                NavigationLink {
                    AttachmentLibraryView()
                } label: {
                    NotesFolderRow(title: String(localized: "Attachments"), systemImage: "paperclip", count: appModel.librarySummary.attachmentCount)
                }
                .accessibilityIdentifier("attachments-link")

                NavigationLink {
                    SettingsRulesView(chooseFolder: chooseFolder)
                } label: {
                    NotesFolderRow(title: String(localized: "Settings"), systemImage: "gearshape", count: nil)
                }
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
                        TagMemoListView(tag: tag.name)
                    } label: {
                        TagChip(title: tag.name)
                    }
                    .buttonStyle(.plain)
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
            if filteredFiles.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: MudsnoteRadius.card))
            } else {
                notesCard {
                    ForEach(filteredFiles) { file in
                        Button {
                            appModel.openFile(file)
                        } label: {
                            RecentFileRow(file: file)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
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

struct FolderNotesListView: View {
    @EnvironmentObject private var appModel: AppModel
    var title: String
    var files: [RecentMarkdownFile]

    var body: some View {
        List {
            if files.isEmpty {
                Text("No Notes")
                    .foregroundStyle(MudsnoteColors.muted)
            } else {
                ForEach(files) { file in
                    Button {
                        appModel.openFile(file)
                    } label: {
                        RecentFileRow(file: file)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("markdown-file-row-\(file.id)")
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
    var record: () -> Void
    var newNote: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 19, weight: .medium))
                TextField("Search", text: $searchText)
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
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
                    .foregroundStyle(.black)
                    .frame(width: 54, height: 54)
                    .background(MudsnoteColors.primary, in: Circle())
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

struct TagMemoListView: View {
    @EnvironmentObject private var appModel: AppModel
    var tag: String

    private var memos: [MemoBlock] {
        appModel.inboxItems.filter { $0.tags.contains(tag) }
    }

    var body: some View {
        List {
            if memos.isEmpty {
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
            } else {
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
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable {
            await appModel.refreshInbox()
        }
        .background(MudsnoteColors.canvas)
        .navigationTitle(tag)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(file.title)
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(MudsnoteColors.text)
            Text(file.relativePath)
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
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
