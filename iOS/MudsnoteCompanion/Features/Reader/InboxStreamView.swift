import SwiftUI

private enum InboxTimelineEntry: Identifiable {
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
}

private struct InboxTimelineSection: Identifiable {
    var id: String
    var title: String
    var entries: [InboxTimelineEntry]
}

struct InboxStreamView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirmingFolderDeletion = false

    private var timelineSections: [InboxTimelineSection] {
        let entries = (
            appModel.mergedInboxFiles.map(InboxTimelineEntry.file)
                + appModel.inboxItems.map(InboxTimelineEntry.memo)
        ).sorted { $0.date > $1.date }
        var sections: [InboxTimelineSection] = []
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
                    InboxTimelineSection(
                        id: bucket.id,
                        title: bucket.title,
                        entries: [entry]
                    )
                )
            }
        }
        return sections
    }

    private var isEmpty: Bool {
        timelineSections.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NotesListCountLabel(count: appModel.mergedInboxCount)

            List {
                if isEmpty {
                    EmptyReaderStateView(
                        title: String(localized: "No Notes Yet"),
                        message: String(localized: "Quick notes and notes saved in the Inbox folder appear here.")
                    )
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(timelineSections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                switch entry {
                                case .file(let file):
                                    NoteFileButton(file: file, showsFolder: false)
                                case .memo(let memo):
                                    InboxMemoRow(memo: memo)
                                }
                            }
                        } header: {
                            NotesListSectionHeader(title: section.title)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(22)
            .scrollContentBackground(.hidden)
        }
        .refreshable {
            await appModel.refreshInbox()
        }
        .background(MudsnoteColors.canvas)
        .navigationTitle("000-inbox")
        .toolbar {
            if let folder = appModel.primaryMergedInboxFolder {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            appModel.showCapture(.text, inFolder: folder.relativePath)
                        } label: {
                            Label("New Note", systemImage: "square.and.pencil")
                        }

                        Button(role: .destructive) {
                            isConfirmingFolderDeletion = true
                        } label: {
                            Label("Delete Folder", systemImage: "trash")
                        }
                        .accessibilityIdentifier("delete-inbox-folder")
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Folder Actions")
                    .accessibilityIdentifier("inbox-folder-actions")
                }
            }
        }
        .confirmationDialog(
            "Delete 000-inbox Folder?",
            isPresented: $isConfirmingFolderDeletion,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Notes", role: .destructive) {
                Task {
                    if await appModel.deleteMergedInboxFolders() {
                        dismiss()
                    }
                }
            }
        } message: {
            Text("Notes in this folder will move to Recently Deleted. Inbox.md quick notes are not affected.")
        }
    }
}

private struct InboxMemoRow: View {
    @EnvironmentObject private var appModel: AppModel
    var memo: MemoBlock

    private var contentLines: [String] {
        memo.body
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var title: String {
        guard let first = contentLines.first else {
            return String(localized: "Untitled memo")
        }
        return first.trimmingCharacters(
            in: CharacterSet(charactersIn: "#>*+- ")
        )
    }

    private var preview: String {
        contentLines.dropFirst().joined(separator: " ")
    }

    private var dateText: String {
        memo.dateText.split(separator: " ").last.map(String.init) ?? memo.dateText
    }

    var body: some View {
        Button {
            appModel.selectedMemo = memo
        } label: {
            NotesListRowContent(
                title: title,
                dateText: dateText,
                preview: preview,
                folderName: nil,
                hasAttachments: memo.hasAttachments
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("inbox-memo-row-\(memo.id)")
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
    }
}

struct MemoCardView: View {
    var memo: MemoBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(memo.dateText)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(MudsnoteColors.muted)
                Spacer()
                if !memo.tags.isEmpty {
                    Text(memo.tags.prefix(2).joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(MudsnoteColors.muted)
                        .lineLimit(1)
                }
            }
            Text(memo.preview)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(MudsnoteColors.text)
                .lineLimit(4)
                .multilineTextAlignment(.leading)
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
