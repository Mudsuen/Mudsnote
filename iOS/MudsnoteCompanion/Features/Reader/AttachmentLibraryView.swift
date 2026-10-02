import SwiftUI
import ImageIO
import UIKit

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

struct AttachmentImageThumbnail: View {
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
        .background(
            MudsnoteColors.card,
            in: RoundedRectangle(cornerRadius: MudsnoteRadius.card)
        )
        .overlay {
            RoundedRectangle(cornerRadius: MudsnoteRadius.card)
                .stroke(MudsnoteColors.line, lineWidth: 1)
        }
    }
}
