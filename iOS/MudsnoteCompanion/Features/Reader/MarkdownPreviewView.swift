import SwiftUI
import AVFoundation
import AVKit
import PencilKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

enum NoteMetadataPresentation {
    static func documentText(
        modifiedAt: Date?,
        fallbackDate: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: modifiedAt ?? fallbackDate)
    }
}

struct MarkdownFrontMatterProjection: Equatable {
    var metadata: String?
    var body: String

    init(_ markdown: String) {
        let lines = markdown.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let closingIndex = lines.indices.dropFirst().first(where: {
                  let marker = lines[$0].trimmingCharacters(in: .whitespacesAndNewlines)
                  return marker == "---" || marker == "..."
              })
        else {
            metadata = nil
            body = markdown
            return
        }

        metadata = lines[...closingIndex].joined(separator: "\n")
        body = lines.dropFirst(closingIndex + 1).joined(separator: "\n")
    }

    func replacingBody(with updatedBody: String) -> String {
        guard let metadata else { return updatedBody }
        return "\(metadata)\n\(updatedBody)"
    }
}

struct MarkdownTitleBodyProjection: Equatable {
    var title: String?
    var body: String

    init(_ markdown: String) {
        var lines = markdown.components(separatedBy: "\n")
        guard let titleIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }), lines[titleIndex].hasPrefix("# "), !lines[titleIndex].hasPrefix("## ")
        else {
            title = nil
            body = markdown
            return
        }
        title = String(lines[titleIndex].dropFirst(2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lines.remove(at: titleIndex)
        while lines.first?.isEmpty == true { lines.removeFirst() }
        body = lines.joined(separator: "\n")
    }

    func replacing(title: String?, body updatedBody: String) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBody = updatedBody.trimmingCharacters(in: .newlines)
        guard !trimmedTitle.isEmpty else { return trimmedBody }
        guard !trimmedBody.isEmpty else { return "# \(trimmedTitle)\n" }
        return "# \(trimmedTitle)\n\n\(trimmedBody)"
    }
}

// A reader reevaluates during sheet, keyboard, and scroll updates. Parse each
// revision once rather than repeating full-document work for every projection.
final class MarkdownReaderProjectionCache {
    private var markdown: String?
    private var frontMatter = MarkdownFrontMatterProjection("")
    private var titleBody = MarkdownTitleBodyProjection("")
    private var blocks: [MarkdownRenderBlock]?
    private var selectionText: NSAttributedString?
    private var selectionTypeSize: DynamicTypeSize?

    func projections(for source: String) -> (MarkdownFrontMatterProjection, MarkdownTitleBodyProjection) {
        if markdown != source {
            markdown = source
            frontMatter = MarkdownFrontMatterProjection(source)
            titleBody = MarkdownTitleBodyProjection(frontMatter.body)
            blocks = nil
            selectionText = nil
        }
        return (frontMatter, titleBody)
    }

    func renderBlocks(for source: String) -> [MarkdownRenderBlock] {
        let (_, projection) = projections(for: source)
        if let blocks { return blocks }
        let parsed = MarkdownRenderBlock.parse(projection.body)
        blocks = parsed
        return parsed
    }

    func selectionText(for source: String, typeSize: DynamicTypeSize) -> NSAttributedString {
        let blocks = renderBlocks(for: source)
        if selectionTypeSize == typeSize, let selectionText { return selectionText }
        let projected = MarkdownSelectionProjection.attributedText(from: blocks)
        selectionText = projected
        selectionTypeSize = typeSize
        return projected
    }
}

struct MarkdownNoteMentionDraft: Equatable {
    var query: String
    var replacementRange: NSRange
}

struct EditorHeaderHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum NoteMentionRanker {
    static func rank(
        _ notes: [RecentMarkdownFile],
        query: String
    ) -> [RecentMarkdownFile] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else {
            return notes.sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                if $0.modifiedAt != $1.modifiedAt { return $0.modifiedAt > $1.modifiedAt }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        let foldedTerm = folded(term)
        return notes.compactMap { note -> (RecentMarkdownFile, Int)? in
            let title = folded(note.title)
            let path = folded(note.relativePath)
            let preview = folded(note.preview)
            let tags = note.tags.map(folded)
            let score: Int
            if title == foldedTerm {
                score = 1_000
            } else if title.hasPrefix(foldedTerm) {
                score = 900 - max(title.count - foldedTerm.count, 0)
            } else if title.contains(foldedTerm) {
                score = 760
            } else if tags.contains(where: { $0.contains(foldedTerm) }) {
                score = 680
            } else if path.contains(foldedTerm) {
                score = 560
            } else if preview.contains(foldedTerm) {
                score = 420
            } else {
                return nil
            }
            return (note, score + (note.isPinned ? 20 : 0))
        }
        .sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            if $0.0.modifiedAt != $1.0.modifiedAt {
                return $0.0.modifiedAt > $1.0.modifiedAt
            }
            return $0.0.title.localizedStandardCompare($1.0.title) == .orderedAscending
        }
        .map(\.0)
    }

    private static func folded(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}

struct MarkdownPreviewView: View {
    private enum Source {
        case memo(MemoBlock)
        case document(MarkdownDocument)
    }

    private enum SaveState {
        case idle
        case saving
        case saved
        case failed
    }

    private enum EditorDisplayMode: String {
        case rich
        case source
    }

    private struct AutosaveID: Hashable {
        var markdown: String
        var isEditing: Bool
    }

    private struct FindAttachmentLoadID: Hashable {
        var relativePath: String
        var markdown: String
        var isFinding: Bool
        var includesAttachments: Bool
    }

    private struct RenderedBlockItem: Identifiable {
        var index: Int
        var block: MarkdownRenderBlock

        var id: Int { index }
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var source: Source
    @State private var draftMarkdown: String
    @State private var originalMarkdown: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var readerProjectionCache = MarkdownReaderProjectionCache()
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var isSaveProgressVisible = false
    @State private var saveState: SaveState = .idle
    @State private var isSaveFailurePresented = false
    @State private var hasSaveConflict = false
    @State private var editorFocused = false
    @State private var readerInsertionOffset: Int?
    @State private var readerTextWidths: [NoteFindLocation: CGFloat] = [:]
    @State private var editingCommand: MarkdownEditingCommand?
    @State private var linkDraft: MarkdownLinkDraft?
    @State private var tagDraft: MarkdownInlineTagDraft?
    @State private var backlinks: [RecentMarkdownFile] = []
    @State private var backlinksFailed = false
    @State private var backlinksLoading = false
    @State private var backlinkRetry = 0
    @State private var noteMentionDraft: MarkdownNoteMentionDraft?
    @State private var editorHeaderHeight: CGFloat = 0
    @State private var editorScrollOffset: CGFloat = 0
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false
    @State private var isScannerPresented = false
    @State private var isDrawingPresented = false
    @State private var cameraErrorMessage: String?
    @State private var scanErrorMessage: String?
    @State private var attachmentPreview: PreparedAttachmentPreview?
    @State private var attachmentBeingRenamed: MarkdownAttachmentLine?
    @State private var attachmentName = ""
    @State private var editorDisplayMode: EditorDisplayMode = .rich
    @State private var accessedRoot: URL?
    @State private var accessRevision = 0
    @StateObject private var noteAudioRecorder = AudioCaptureService()
    @State private var isAudioTransitioning = false
    @State private var isTranscribingDocumentAudio = false
    @State private var pendingAudioRecording: RecordedAudio?
    @State private var isAudioAttachmentFailurePresented = false
    @State private var noteName = ""
    @State private var isRenamingNote = false
    @State private var isConfirmingNoteDeletion = false
    @State private var isFindingInNote = false
    @State private var findQuery = ""
    @State private var activeFindIndex = 0
    @State private var includesAttachmentsInFind = false
    @State private var findAttachmentDocuments: [AttachmentSearchDocument] = []
    @State private var isLoadingFindAttachments = false
    @State private var linkedSourceHistory: [Source] = []
    @State private var exportedPDF: ExportedNotePDF?
    @State private var isExportingPDF = false
    @State private var pdfExportErrorMessage: String?
    @FocusState private var isFindFocused: Bool
    private let requestEditing: () -> Void
    private let editingChanged: (Bool) -> Void

    init(
        memo: MemoBlock,
        startsEditing: Bool = false,
        requestEditing: @escaping () -> Void = {},
        editingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let migration = MarkdownTagSyntax.extractingInlineTags(from: memo.body)
        var seen = Set<String>()
        var migratedMemo = memo
        migratedMemo.tags = (memo.tags + migration.tags).filter {
            seen.insert(MarkdownTagSyntax.key($0)).inserted
        }
        _source = State(initialValue: .memo(migratedMemo))
        _draftMarkdown = State(initialValue: migration.body)
        _originalMarkdown = State(initialValue: memo.body)
        _isEditing = State(initialValue: startsEditing)
        self.requestEditing = requestEditing
        self.editingChanged = editingChanged
    }

    init(
        document: MarkdownDocument,
        startsEditing: Bool = false,
        requestEditing: @escaping () -> Void = {},
        editingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        let migration = MarkdownTagSyntax.migratingInlineTagsToFrontMatter(
            in: document.markdown
        )
        _source = State(initialValue: .document(document))
        _draftMarkdown = State(initialValue: migration.body)
        _originalMarkdown = State(initialValue: document.markdown)
        _isEditing = State(initialValue: document.isNew || startsEditing)
        self.requestEditing = requestEditing
        self.editingChanged = editingChanged
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    ZStack(alignment: .topLeading) {
                        MarkdownTextEditor(
                            text: editableBodyMarkdown,
                            isFocused: $editorFocused,
                            command: $editingCommand,
                            linkDraft: $linkDraft,
                            tagDraft: $tagDraft,
                            noteMentionDraft: $noteMentionDraft,
                            contentTopInset: editorHeaderHeight + 8,
                            scrollOffset: $editorScrollOffset,
                            displaysSource: editorDisplayMode == .source,
                            initialInsertionOffset: readerInsertionOffset,
                            onCommitTag: commitInlineTag
                        )
                        .accessibilityIdentifier("markdown-editor")

                        noteHeader(isEditing: true, showsMetadata: true)
                            .padding(.bottom, 8)
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: EditorHeaderHeightPreferenceKey.self,
                                        value: geometry.size.height
                                    )
                                }
                            }
                            .offset(y: -max(editorScrollOffset, 0))

                        VStack {
                            Spacer()
                            if let tagDraft,
                               !rankedTagSuggestions(for: tagDraft.query).isEmpty {
                                MarkdownTagSuggestions(
                                    tags: Array(rankedTagSuggestions(for: tagDraft.query).prefix(6)),
                                    knownTags: Set(knownTagSuggestions.map(MarkdownTagSyntax.key)),
                                    select: acceptInlineTag
                                )
                                .padding(.bottom, 8)
                            } else if let noteMentionDraft,
                                      !rankedMentionNotes(for: noteMentionDraft.query).isEmpty {
                                MarkdownNoteMentionSuggestions(
                                    notes: Array(
                                        rankedMentionNotes(for: noteMentionDraft.query).prefix(6)
                                    ),
                                    select: acceptNoteMention
                                )
                                .padding(.bottom, 8)
                            }
                        }
                    }
                    .padding(MudsnoteSpacing.safeHorizontal)
                    .clipped()
                    .onPreferenceChange(EditorHeaderHeightPreferenceKey.self) {
                        editorHeaderHeight = $0
                    }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        metadataLabel
                            .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
                            .padding(.top, MudsnoteSpacing.safeHorizontal)
                            .padding(.bottom, 8)

                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    noteHeader(isEditing: false, showsMetadata: false)
                                    markdownBody
                                        .environment(\.openURL, OpenURLAction { url in
                                            handleMarkdownURL(url)
                                        })
                                        .accessibilityElement(children: .contain)
                                        .accessibilityIdentifier("rendered-markdown")
                                    backlinkSection
                                }
                                    .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
                                    .padding(.top, MudsnoteSpacing.safeHorizontal)
                                    .padding(.bottom, MudsnoteSpacing.safeHorizontal)
                            }
                            .onChange(of: findQuery) { _, _ in
                                activeFindIndex = 0
                                scrollToActiveFindMatch(using: proxy)
                            }
                            .onChange(of: activeFindIndex) { _, _ in
                                scrollToActiveFindMatch(using: proxy)
                            }
                            .onChange(of: findResults.map(\.id)) { _, _ in
                                activeFindIndex = min(
                                    activeFindIndex,
                                    max(0, findResults.count - 1)
                                )
                                scrollToActiveFindMatch(using: proxy)
                            }

                        }
                    }
                }
            }
            .background {
                MudsnoteColors.panel.opacity(0.78)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEditing {
                    markdownToolbar
                } else if isFindingInNote {
                    noteFindBar
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .background {
            MudsnoteReaderSheetBackground()
        }
        .interactiveDismissDisabled(
            (isEditing && draftMarkdown != originalMarkdown)
                || noteAudioRecorder.isRecording
                || isAudioTransitioning
                || pendingAudioRecording != nil
        )
        .task(id: "\(currentSourceRelativePath)|\(appModel.libraryRevision)|\(isEditing)|\(backlinkRetry)") {
            backlinks = []
            backlinksFailed = false
            guard !isEditing, case .document = source else { return }
            backlinksLoading = true
            do {
                let result = try await appModel.fileStore.backlinks(to: currentSourceRelativePath)
                try Task.checkCancellation()
                backlinks = result
                backlinksLoading = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                backlinksFailed = true
                backlinksLoading = false
            }
        }
        .onAppear {
            beginLibraryAccess()
            editingChanged(isEditing)
            if isEditing {
                focusEditorAfterPresentation()
            }
        }
        .onChange(of: isEditing) { _, editing in
            editingChanged(editing)
        }
        .onDisappear {
            if case .document(let document) = source {
                appModel.discardEmptyNewDocumentIfNeeded(document, markdown: draftMarkdown)
            }
            noteAudioRecorder.cancel()
            discardPendingAudioRecording()
            endLibraryAccess()
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard item != nil else { return }
            Task { await attachPhoto(item) }
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .any(of: [.images, .videos])
        )
        .task(id: AutosaveID(markdown: draftMarkdown, isEditing: isEditing)) {
            guard isEditing, !hasSaveConflict, draftMarkdown != originalMarkdown else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, !hasSaveConflict else { return }
            await persistDraft(finishEditing: false, announce: false)
        }
        .task(id: FindAttachmentLoadID(
            relativePath: currentSourceRelativePath,
            markdown: draftMarkdown,
            isFinding: isFindingInNote,
            includesAttachments: includesAttachmentsInFind
        )) {
            await loadFindAttachmentDocumentsIfNeeded()
        }
        .alert("Couldn’t Save Note", isPresented: $isSaveFailurePresented) {
            if hasSaveConflict {
                Button("Save a Copy") {
                    Task { await saveConflictedDraftAsCopy() }
                }
            }
            Button("Keep Editing", role: .cancel) {
                editorFocused = true
            }
            Button("Reopen Saved Version", role: .destructive) {
                Task { await reloadSavedVersion() }
            }
        } message: {
            if hasSaveConflict {
                Text("This note changed elsewhere. Save a copy to keep both versions.")
            } else {
                Text("Your edits are still here. Try saving again.")
            }
        }
        .alert("Couldn’t Attach Audio", isPresented: $isAudioAttachmentFailurePresented) {
            Button("Keep Editing", role: .cancel) {
                editorFocused = true
            }
            Button("Retry") {
                Task { await retryPendingAudioRecording() }
            }
            Button("Discard Recording", role: .destructive) {
                discardPendingAudioRecording()
            }
        } message: {
            Text("The recording is still available. Retry after resolving the note conflict, or discard it.")
        }
        .alert("Rename Note", isPresented: $isRenamingNote) {
            TextField("Note Name", text: $noteName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                Task { await renameCurrentDocument(to: noteName) }
            }
            .disabled(noteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .confirmationDialog(
            "Delete Note?",
            isPresented: $isConfirmingNoteDeletion,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await trashCurrentDocument() }
            }
        } message: {
            Text("You can restore this note from Recently Deleted.")
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task { await attachFile(url) }
        }
        .sheet(item: $linkDraft) { draft in
            MarkdownLinkEditorSheet(
                draft: draft,
                notes: linkableNotes,
                sourceRelativePath: currentSourceRelativePath,
                onApply: { label, destination in
                    linkDraft = nil
                    applyLinkCommand(
                        .applyLink(draft: draft, label: label, destination: destination)
                    )
                },
                onRemove: draft.isExisting ? {
                    linkDraft = nil
                    applyLinkCommand(.removeLink(draft: draft))
                } : nil
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $exportedPDF) { export in
            NoteActivityView(activityItems: [export.url])
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("Couldn’t Export PDF", isPresented: Binding(
            get: { pdfExportErrorMessage != nil },
            set: { if !$0 { pdfExportErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { pdfExportErrorMessage = nil }
        } message: {
            Text(pdfExportErrorMessage ?? "Try exporting the note again.")
        }
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
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPhotoCaptureView(
                onComplete: { result in
                    isCameraPresented = false
                    switch result {
                    case .success(let media):
                        Task { await attachCameraPhoto(media) }
                    case .failure(let error):
                        cameraErrorMessage = error.localizedDescription
                    }
                },
                onCancel: {
                    isCameraPresented = false
                    editorFocused = true
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            DocumentScannerView(
                onComplete: { result in
                    isScannerPresented = false
                    switch result {
                    case .success(let pages):
                        Task { await attachScannedDocument(pages) }
                    case .failure(let error):
                        scanErrorMessage = error.localizedDescription
                    }
                },
                onCancel: { isScannerPresented = false }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $isDrawingPresented) {
            MarkdownDrawingEditor(
                onCancel: { isDrawingPresented = false },
                onSave: { data in
                    isDrawingPresented = false
                    Task { await attachDrawing(data) }
                }
            )
        }
        .alert("Couldn’t Scan Document", isPresented: Binding(
            get: { scanErrorMessage != nil },
            set: { if !$0 { scanErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { scanErrorMessage = nil }
        } message: {
            Text(scanErrorMessage ?? "Try scanning the document again.")
        }
        .alert("Couldn’t Capture Photo or Video", isPresented: Binding(
            get: { cameraErrorMessage != nil },
            set: { if !$0 { cameraErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                cameraErrorMessage = nil
                editorFocused = true
            }
        } message: {
            Text(cameraErrorMessage ?? "Try capturing the photo or video again.")
        }
        .alert("Rename Attachment", isPresented: Binding(
            get: { attachmentBeingRenamed != nil },
            set: { if !$0 { attachmentBeingRenamed = nil } }
        )) {
            TextField("Attachment Name", text: $attachmentName)
            Button("Cancel", role: .cancel) { attachmentBeingRenamed = nil }
            Button("Rename") {
                guard let attachment = attachmentBeingRenamed else { return }
                let name = attachmentName
                attachmentBeingRenamed = nil
                Task { await renameAttachment(attachment, to: name) }
            }
            .disabled(attachmentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func beginEditingFromReader(at offset: Int) {
        guard !isEditing else { return }
        if !appModel.isReaderExpanded {
            requestEditing()
        }
        readerInsertionOffset = offset
        isEditing = true
        focusEditorAfterPresentation()
    }

    private var metadataLabel: some View {
        ZStack(alignment: .trailing) {
            Text(metadata)
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("note-modified-date")

            if noteAudioRecorder.isRecording {
                Text("Recording")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            } else if isTranscribingDocumentAudio {
                Text("Transcribing...")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if pendingAudioRecording != nil {
                Text("Audio Not Attached")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if isEditing {
                Text(saveStatusText)
                    .font(.caption)
                    .foregroundStyle(saveState == .failed ? Color.red : MudsnoteColors.muted)
                    .accessibilityIdentifier("markdown-save-status")
            }
        }
        .frame(minHeight: 18)
        .contextMenu {
            if !isEditing {
                readerContextMenuContent
            }
        }
    }

    private func applyLinkCommand(_ kind: MarkdownEditingCommand.Kind) {
        Task { @MainActor in
            await Task.yield()
            editingCommand = MarkdownEditingCommand(kind: kind)
            editorFocused = true
        }
    }

    private func canManage(_ document: MarkdownDocument) -> Bool {
        true
    }

    private var currentFile: RecentMarkdownFile? {
        guard case .document(let document) = source else { return nil }
        return appModel.libraryFiles.first { $0.relativePath == document.relativePath }
    }

    private var currentSourceRelativePath: String {
        switch source {
        case .memo:
            "Inbox.md"
        case .document(let document):
            document.relativePath
        }
    }

    private var linkableNotes: [RecentMarkdownFile] {
        appModel.libraryFiles
            .filter { $0.relativePath != currentSourceRelativePath }
            .sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    private var moveDestinations: [LibraryFolderNode] {
        guard case .document(let document) = source else { return [] }
        let currentFolder = (document.relativePath as NSString).deletingLastPathComponent
        return appModel.allFolders.filter { $0.relativePath != currentFolder }
    }

    private var canMoveToTopLevel: Bool {
        guard case .document(let document) = source else { return false }
        return !(document.relativePath as NSString).deletingLastPathComponent.isEmpty
    }

    private func renameCurrentDocument(to name: String) async {
        guard case .document(let document) = source,
              let renamed = await appModel.renameNote(
                relativePath: document.relativePath,
                to: name
              ) else { return }
        source = .document(renamed)
    }

    private func moveCurrentDocument(toFolder folder: String?) async {
        guard case .document(let document) = source,
              let moved = await appModel.moveNote(
                relativePath: document.relativePath,
                toFolder: folder
              ) else { return }
        source = .document(moved)
    }

    private func trashCurrentDocument() async {
        guard let file = currentFile else { return }
        if await appModel.trashNote(file) {
            dismiss()
        }
    }

    private var renderBlocks: [MarkdownRenderBlock] {
        readerProjectionCache.renderBlocks(for: draftMarkdown)
    }

    private var frontMatterProjection: MarkdownFrontMatterProjection {
        readerProjectionCache.projections(for: draftMarkdown).0
    }

    private var titleBodyProjection: MarkdownTitleBodyProjection {
        readerProjectionCache.projections(for: draftMarkdown).1
    }

    private var editableBodyMarkdown: Binding<String> {
        Binding(
            get: { titleBodyProjection.body },
            set: { updated in
                let body = titleBodyProjection.replacing(
                    title: titleBodyProjection.title,
                    body: updated
                )
                draftMarkdown = frontMatterProjection.replacingBody(with: body)
            }
        )
    }

    private var editableTitle: Binding<String> {
        Binding(
            get: { titleBodyProjection.title ?? "" },
            set: { updated in
                let body = titleBodyProjection.replacing(
                    title: updated,
                    body: titleBodyProjection.body
                )
                draftMarkdown = frontMatterProjection.replacingBody(with: body)
            }
        )
    }

    private var renderedMarkdown: String {
        titleBodyProjection.body
    }

    private var noteTags: [String] {
        switch source {
        case .memo(let memo): memo.tags
        case .document: MarkdownTagSyntax.tags(in: draftMarkdown)
        }
    }

    private var knownTagSuggestions: [String] {
        appModel.tagSummaries.map(\.name)
            + appModel.libraryFiles.flatMap(\.tags)
    }

    private func rankedTagSuggestions(for query: String) -> [String] {
        MarkdownTagSyntax.rankedInlineSuggestions(
            query: query,
            knownTags: knownTagSuggestions,
            activeTags: noteTags
        )
    }

    @ViewBuilder
    private func noteHeader(isEditing: Bool, showsMetadata: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsMetadata {
                metadataLabel
            }

            if titleBodyProjection.title != nil {
                if isEditing {
                    TextField("Title", text: editableTitle, axis: .vertical)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MudsnoteColors.text)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier("note-title-editor")
                } else {
                    Text(titleBodyProjection.title ?? "")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(MudsnoteColors.text)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("note-title")
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            beginEditingFromReader(at: 0)
                        }
                }
            }

            if !noteTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        Label("Tags", systemImage: "number")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MudsnoteColors.muted)
                        ForEach(noteTags, id: \.self) { tag in
                            Label {
                                Text(String(tag.dropFirst()))
                            } icon: {
                                Image(systemName: "number")
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MudsnoteColors.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(MudsnoteColors.card, in: Capsule())
                            .overlay {
                                Capsule().stroke(
                                    MudsnoteColors.primary.opacity(0.28),
                                    lineWidth: 1
                                )
                            }
                        }
                    }
                }
                .frame(height: 34)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("note-tag-bar")
            }
        }
    }

    @ViewBuilder
    private var backlinkSection: some View {
        if backlinksLoading {
            ProgressView().frame(maxWidth: .infinity)
        } else if backlinksFailed {
            Button("Retry backlinks", systemImage: "arrow.clockwise") { backlinkRetry += 1 }
                .accessibilityIdentifier("retry-note-backlinks")
        } else if !backlinks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Divider()
                Text("Backlinks")
                    .font(.subheadline.weight(.semibold))
                ForEach(backlinks) { note in
                    Button {
                        Task { await openLinkedNote(note) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.up.left")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title).lineLimit(2)
                                Text(note.relativePath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("note-backlink-\(note.relativePath)")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("note-backlinks")
        }
    }

    private func rankedMentionNotes(for query: String) -> [RecentMarkdownFile] {
        NoteMentionRanker.rank(
            linkableNotes,
            query: query
        )
    }

    private func acceptNoteMention(_ note: RecentMarkdownFile) {
        guard let noteMentionDraft,
              let destination = MarkdownNoteLink.relativeDestination(
                from: currentSourceRelativePath,
                to: note.relativePath
              ) else { return }
        self.noteMentionDraft = nil
        editingCommand = MarkdownEditingCommand(
            kind: .applyNoteMention(
                range: noteMentionDraft.replacementRange,
                label: note.title,
                destination: destination
            )
        )
        editorFocused = true
    }

    private func acceptInlineTag(_ tag: String) {
        guard let tagDraft else { return }
        self.tagDraft = nil
        editingCommand = MarkdownEditingCommand(
            kind: .applyTag(range: tagDraft.replacementRange, tag: tag)
        )
        editorFocused = true
    }

    private func commitInlineTag(_ input: String) {
        guard let tag = MarkdownTagSyntax.normalizedTag(input),
              !noteTags.contains(where: {
                  MarkdownTagSyntax.key($0) == MarkdownTagSyntax.key(tag)
              })
        else { return }

        switch source {
        case .document:
            if let updated = MarkdownTagSyntax.adding(tag, to: draftMarkdown) {
                draftMarkdown = updated
            }
        case .memo(var memo):
            memo.tags.append(tag)
            var seen = Set<String>()
            memo.tags = memo.tags.filter {
                seen.insert(MarkdownTagSyntax.key($0)).inserted
            }
            source = .memo(memo)
        }
    }

    private var presentationPreferenceNotePath: String {
        switch source {
        case .memo(let memo):
            "Inbox.md#\(memo.id)"
        case .document(let document):
            document.relativePath
        }
    }

    private var hasRenderedAttachments: Bool {
        renderBlocks.contains { block in
            guard case .line(let line) = block else { return false }
            return MarkdownAttachmentLine(line) != nil
        }
    }

    private func attachmentPresentationMode(
        for attachment: MarkdownAttachmentLine
    ) -> AttachmentPresentationMode {
        appModel.attachmentPresentationMode(
            notePath: presentationPreferenceNotePath,
            attachmentPath: attachment.path
        )
    }

    private func setAttachmentPresentationMode(
        _ mode: AttachmentPresentationMode,
        for attachment: MarkdownAttachmentLine
    ) {
        withAnimation(.snappy(duration: 0.22)) {
            appModel.setAttachmentPresentationMode(
                mode,
                notePath: presentationPreferenceNotePath,
                attachmentPath: attachment.path
            )
        }
    }

    private func setAllAttachmentPresentationModes(_ mode: AttachmentPresentationMode) {
        withAnimation(.snappy(duration: 0.22)) {
            appModel.setAllAttachmentPresentationModes(
                mode,
                notePath: presentationPreferenceNotePath
            )
        }
    }

    private var textFindMatches: [NoteFindMatch] {
        NoteFindIndex.matches(in: renderBlocks, query: findQuery)
    }

    private var attachmentFindMatches: [NoteAttachmentFindMatch] {
        guard includesAttachmentsInFind else { return [] }
        return NoteFindIndex.attachmentMatches(
            in: renderBlocks,
            documents: findAttachmentDocuments,
            query: findQuery
        )
    }

    private var findResults: [NoteFindResult] {
        (textFindMatches.map(NoteFindResult.text)
            + attachmentFindMatches.map(NoteFindResult.attachment))
            .sorted { lhs, rhs in
                if lhs.location.blockIndex == rhs.location.blockIndex {
                    return lhs.sortOrder < rhs.sortOrder
                }
                return lhs.location.blockIndex < rhs.location.blockIndex
            }
    }

    private var activeFindMatch: NoteFindMatch? {
        guard !findResults.isEmpty,
              case .text(let match) = findResults[min(activeFindIndex, findResults.count - 1)]
        else { return nil }
        return match
    }

    private var activeAttachmentFindMatch: NoteAttachmentFindMatch? {
        guard !findResults.isEmpty,
              case .attachment(let match) = findResults[min(activeFindIndex, findResults.count - 1)]
        else { return nil }
        return match
    }

    private var findCountLabel: String {
        let total = findResults.count
        let current = total == 0 ? 0 : min(activeFindIndex, total - 1) + 1
        return String(
            format: String(localized: "note.find_count.format"),
            locale: .current,
            current,
            total
        )
    }

    private var noteFindBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MudsnoteColors.muted)
                TextField("Find in Note", text: $findQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isFindFocused)
                    .submitLabel(.search)
                    .accessibilityIdentifier("find-in-note-field")
                if !findQuery.isEmpty {
                    Button {
                        findQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear Find")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 10))

            Menu {
                Toggle("Include Attachments", isOn: $includesAttachmentsInFind)
            } label: {
                Group {
                    if isLoadingFindAttachments {
                        ProgressView()
                    } else {
                        Image(systemName: includesAttachmentsInFind
                            ? "doc.text.magnifyingglass"
                            : "line.3.horizontal.decrease.circle")
                    }
                }
                .frame(width: 30, height: 34)
            }
            .accessibilityLabel("Find Options")
            .accessibilityIdentifier("find-in-note-options")

            Text(findCountLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(MudsnoteColors.muted)
                .frame(minWidth: 42)
                .accessibilityIdentifier("find-in-note-count")

            Button { stepFindMatch(by: -1) } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 30, height: 34)
            }
            .disabled(findResults.isEmpty)
            .accessibilityLabel("Previous Match")
            .accessibilityIdentifier("find-in-note-previous")

            Button { stepFindMatch(by: 1) } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 30, height: 34)
            }
            .disabled(findResults.isEmpty)
            .accessibilityLabel("Next Match")
            .accessibilityIdentifier("find-in-note-next")

            Button("Done", action: closeFindInNote)
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("finish-find-in-note")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(MudsnoteColors.line).frame(height: 1)
        }
    }

    private func beginFindingInNote() {
        isFindingInNote = true
        activeFindIndex = 0
        Task { @MainActor in
            await Task.yield()
            isFindFocused = true
        }
    }

    private func closeFindInNote() {
        isFindFocused = false
        findQuery = ""
        activeFindIndex = 0
        includesAttachmentsInFind = false
        findAttachmentDocuments = []
        isLoadingFindAttachments = false
        isFindingInNote = false
    }

    private func stepFindMatch(by offset: Int) {
        guard !findResults.isEmpty else { return }
        activeFindIndex = (activeFindIndex + offset + findResults.count) % findResults.count
    }

    private func scrollToActiveFindMatch(using proxy: ScrollViewProxy) {
        guard !findResults.isEmpty else { return }
        let result = findResults[min(activeFindIndex, findResults.count - 1)]
        Task { @MainActor in
            await Task.yield()
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(result.location.blockIndex, anchor: .center)
            }
        }
    }

    @MainActor
    private func loadFindAttachmentDocumentsIfNeeded() async {
        guard isFindingInNote, includesAttachmentsInFind else {
            findAttachmentDocuments = []
            isLoadingFindAttachments = false
            return
        }
        isLoadingFindAttachments = true
        do {
            let documents = try await appModel.attachmentSearchDocuments(in: draftMarkdown)
            try Task.checkCancellation()
            findAttachmentDocuments = documents
            isLoadingFindAttachments = false
            activeFindIndex = 0
        } catch is CancellationError {
            return
        } catch {
            findAttachmentDocuments = []
            isLoadingFindAttachments = false
        }
    }

    private var saveStatusText: LocalizedStringKey {
        switch saveState {
        case .idle: "Saved"
        case .saving: "Saving…"
        case .saved: "Saved"
        case .failed: "Not Saved"
        }
    }

    @ViewBuilder
    private var attachmentMenuContent: some View {
        Button {
            isPhotoPickerPresented = true
        } label: {
            Label("Choose Photo or Video", systemImage: "photo.on.rectangle.angled")
        }
        .accessibilityIdentifier("markdown-add-image")

        Button {
            editorFocused = false
            isCameraPresented = true
        } label: {
            Label("Take Photo or Video", systemImage: "camera")
        }
        .disabled(!CameraPhotoCapture.isAvailable)
        .accessibilityIdentifier("markdown-take-photo")

        Button {
            editorFocused = false
            isDrawingPresented = true
        } label: {
            Label("Add Drawing", systemImage: "pencil.tip.crop.circle")
        }
        .accessibilityIdentifier("markdown-add-drawing")

        Button {
            isFileImporterPresented = true
        } label: {
            Label("Add File", systemImage: "doc")
        }
        .accessibilityIdentifier("markdown-add-file")

        Button {
            isScannerPresented = true
        } label: {
            Label("Scan Document", systemImage: "doc.viewfinder")
        }
        .disabled(!VNDocumentCameraViewController.isSupported)
        .accessibilityIdentifier("markdown-scan-document")

        Button {
            editorFocused = true
            DispatchQueue.main.async {
                _ = CameraTextCapture.start()
            }
        } label: {
            Label("Scan Text", systemImage: "text.viewfinder")
        }
        .disabled(!CameraTextCapture.isAvailable)
        .accessibilityIdentifier("markdown-scan-text")
    }

    @ViewBuilder
    private var readerContextMenuContent: some View {
        Button {
            UIPasteboard.general.string = draftMarkdown
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .disabled(draftMarkdown.isEmpty)
        .accessibilityIdentifier("copy-note")

        if case .document(let document) = source {
            Button {
                Task { await exportCurrentDocumentAsPDF(document) }
            } label: {
                Label(
                    isExportingPDF ? "Exporting PDF…" : "Export as PDF",
                    systemImage: "doc.richtext"
                )
            }
            .disabled(isExportingPDF)
        }

        Button {
            beginFindingInNote()
        } label: {
            Label("Find in Note", systemImage: "magnifyingglass")
        }
        .disabled(draftMarkdown.isEmpty)

        if hasRenderedAttachments {
            Menu {
                Button("Set All to Small") { setAllAttachmentPresentationModes(.small) }
                Button("Set All to Large") { setAllAttachmentPresentationModes(.large) }
            } label: {
                Label("Attachment View", systemImage: "rectangle.grid.1x2")
            }
            .accessibilityIdentifier("attachment-view-menu")
        }

        if case .document(let document) = source,
           let file = currentFile {
            Divider()
            if canManage(document) {
                Button {
                    appModel.togglePinned(file)
                } label: {
                    Label(
                        file.isPinned ? "Unpin" : "Pin",
                        systemImage: file.isPinned ? "pin.slash" : "pin"
                    )
                }
                if canMoveToTopLevel || !moveDestinations.isEmpty {
                    Menu {
                        if canMoveToTopLevel {
                            Button {
                                Task { await moveCurrentDocument(toFolder: nil) }
                            } label: {
                                Label("Top Level", systemImage: "tray")
                            }
                        }
                        ForEach(moveDestinations) { folder in
                            Button(folder.relativePath) {
                                Task { await moveCurrentDocument(toFolder: folder.relativePath) }
                            }
                        }
                    } label: {
                        Label("Move Note", systemImage: "folder")
                    }
                }
                Button {
                    appModel.duplicate(file)
                } label: {
                    Label("Duplicate Note", systemImage: "plus.square.on.square")
                }
                Button {
                    noteName = document.title
                    isRenamingNote = true
                } label: {
                    Label("Rename Note", systemImage: "pencil")
                }
            }
            if appModel.canMoveToRecentlyDeleted(file) {
                Divider()
                Button(role: .destructive) {
                    isConfirmingNoteDeletion = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private var markdownToolbar: some View {
        if #available(iOS 26.0, *) {
            ZStack {
                Color.clear
                    .glassEffect(.regular, in: Capsule())
                    .allowsHitTesting(false)

                markdownToolbarContent
                    .padding(.horizontal, 8)
            }
                .frame(height: 50)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("markdown-glass-toolbar")
        } else {
            markdownToolbarContent
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(.regularMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(MudsnoteColors.line)
                        .frame(height: 0.5)
                }
        }
    }

    private var markdownToolbarContent: some View {
        let attachmentIsPreparing = appModel.isPreparingAttachment
        return HStack(spacing: 2) {
            if case .document = source {
                Menu {
                    attachmentMenuContent
                } label: {
                    Image(systemName: attachmentIsPreparing ? "hourglass" : "paperclip")
                        .frame(width: 42, height: 44)
                }
                .disabled(isSaving || appModel.isPreparingAttachment)
                .accessibilityLabel("Add Attachment")
                .accessibilityIdentifier("markdown-attachment-menu")
            }

            editorTriggerButton("#", accessibilityLabel: "Tag", text: "#")
            editorTriggerButton("@", accessibilityLabel: "Link to note", text: "@")
            formatButton("checklist", .checklist)
            formatButton("arrow.uturn.backward", .undo)
            formatButton("arrow.uturn.forward", .redo)

            Spacer(minLength: 4)
            if case .document = source {
                Button {
                    Task { await toggleDocumentAudioRecording() }
                } label: {
                    Image(systemName: audioButtonSystemImage)
                        .foregroundStyle(noteAudioRecorder.isRecording ? Color.red : MudsnoteColors.text)
                        .frame(width: 42, height: 44)
                }
                .disabled(
                    isSaving
                        || appModel.isPreparingAttachment
                        || isAudioTransitioning
                )
                .accessibilityLabel(audioButtonAccessibilityLabel)
                .accessibilityIdentifier("markdown-record-audio")
            }

            Button {
                Task { await finishEditingAfterPendingAutosave() }
            } label: {
                if isSaveProgressVisible {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .frame(width: 42, height: 44)
                }
            }
            .disabled(
                isSaveProgressVisible
                    || isAudioTransitioning
                    || noteAudioRecorder.isRecording
                    || pendingAudioRecording != nil
            )
            .accessibilityLabel("Save note")
            .accessibilityValue(isSaveProgressVisible ? "Saving" : "Ready")
            .accessibilityIdentifier("save-markdown-button")
        }
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(MudsnoteColors.text)
    }

    private func editorTriggerButton(
        _ title: String,
        accessibilityLabel: LocalizedStringKey,
        text: String
    ) -> some View {
        Button {
            editingCommand = MarkdownEditingCommand(kind: .insertText(text))
        } label: {
            Text(title)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(width: 42, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(text == "#" ? "markdown-insert-tag" : "markdown-insert-mention")
    }

    private func formatButton(_ systemImage: String, _ kind: MarkdownEditingCommand.Kind) -> some View {
        Button {
            editingCommand = MarkdownEditingCommand(kind: kind)
        } label: {
            Image(systemName: systemImage)
                .frame(width: 42, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("markdown-format-\(kind.identifier)")
    }

    private func handleMarkdownURL(_ url: URL) -> OpenURLAction.Result {
        guard let relativePath = MarkdownNoteLink.resolvedRelativePath(
            for: url.relativeString,
            from: currentSourceRelativePath
        ) else { return .systemAction }
        guard let target = appModel.libraryFiles.first(where: {
            $0.relativePath == relativePath
        }) else {
            appModel.statusToast = .error(String(localized: "Linked note not found"))
            return .handled
        }
        Task { await openLinkedNote(target) }
        return .handled
    }

    private func openLinkedNote(_ file: RecentMarkdownFile) async {
        guard file.relativePath != currentSourceRelativePath,
              let target = await appModel.loadDocument(relativePath: file.relativePath) else { return }
        linkedSourceHistory.append(source)
        showLinkedSource(.document(target))
    }

    private func showLinkedSource(_ linkedSource: Source) {
        closeFindInNote()
        isEditing = false
        editorFocused = false
        source = linkedSource
        switch linkedSource {
        case .memo(let memo):
            draftMarkdown = memo.body
            originalMarkdown = memo.body
            noteName = ""
        case .document(let document):
            draftMarkdown = document.markdown
            originalMarkdown = document.markdown
            noteName = document.title
        }
        saveState = .idle
        hasSaveConflict = false
    }

    private func focusEditorAfterPresentation() {
        Task { @MainActor in
            await Task.yield()
            editorFocused = true
        }
    }

    @MainActor
    private func exportCurrentDocumentAsPDF(_ document: MarkdownDocument) async {
        guard !isExportingPDF else { return }
        isExportingPDF = true
        defer { isExportingPDF = false }

        do {
            exportedPDF = try NotePDFExporter.export(
                title: document.title,
                markdown: draftMarkdown,
                modifiedAt: document.modifiedAt
            )
        } catch {
            pdfExportErrorMessage = error.localizedDescription
        }
    }

    private var markdownBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleRenderBlockItems) { item in
                Group {
                    switch item.block {
                    case .line(let line):
                        markdownLine(line, blockIndex: item.index)
                    case .table(let headers, let rows):
                        markdownTable(
                            headers: headers,
                            rows: rows,
                            blockIndex: item.index
                        )
                    case .code(let language, let content):
                        markdownCodeBlock(
                            language: language,
                            content: content,
                            blockIndex: item.index
                        )
                    }
                }
                .id(item.index)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            MarkdownDocumentSelectionOverlay(attributedText: previewSelectionText)
        }
    }

    private var previewSelectionText: NSAttributedString {
        readerProjectionCache.selectionText(for: draftMarkdown, typeSize: dynamicTypeSize)
    }

    private var visibleRenderBlockItems: [RenderedBlockItem] {
        renderBlocks.enumerated().map { index, block in
            RenderedBlockItem(index: index, block: block)
        }
    }

    private var metadata: String {
        switch source {
        case .memo(let memo): memo.dateText
        case .document(let document):
            NoteMetadataPresentation.documentText(modifiedAt: document.modifiedAt)
        }
    }

    @ViewBuilder
    private func markdownLine(
        _ line: String,
        blockIndex: Int
    ) -> some View {
        if let attachment = MarkdownAttachmentLine(line) {
            attachmentView(attachment, blockIndex: blockIndex)
        } else if case .heading(let heading) = MarkdownLineStyle(line) {
            markdownText(
                heading.title,
                location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil),
                selectionFont: heading.uiFont
            )
            .font(heading.font)
        } else if case .task(let isChecked, let text, let indentation) = MarkdownLineStyle(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(
                        isChecked ? Color(hex: 0xD7BD68) : MudsnoteColors.muted
                    )
                    .accessibilityLabel(isChecked ? "Completed" : "Not completed")
                markdownText(
                    text,
                    location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
                )
                .strikethrough(isChecked, color: MudsnoteColors.muted)
            }
            .padding(.leading, CGFloat(indentation) * 16)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("markdown-task-\(blockIndex)")
        } else if case .unordered(let text, let indentation) = MarkdownLineStyle(line) {
            markdownListRow(
                marker: "•",
                text: text,
                indentation: indentation,
                blockIndex: blockIndex
            )
        } else if case .ordered(let marker, let text, let indentation) = MarkdownLineStyle(line) {
            markdownListRow(
                marker: marker,
                text: text,
                indentation: indentation,
                blockIndex: blockIndex
            )
        } else if case .quote(let text) = MarkdownLineStyle(line) {
            markdownText(
                text,
                location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil),
                selectionFont: .preferredFont(forTextStyle: .body).withTraits(.traitItalic)
            )
                .font(.body.italic())
                .foregroundStyle(MudsnoteColors.muted)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(MudsnoteColors.line).frame(width: 3)
                }
        } else if case .thematicBreak = MarkdownLineStyle(line) {
            Divider()
                .overlay(MudsnoteColors.line)
                .accessibilityLabel("Separator")
        } else {
            markdownText(
                line,
                location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
            )
        }
    }

    private func markdownListRow(
        marker: String,
        text: String,
        indentation: Int,
        blockIndex: Int
    ) -> some View {
        markdownText(
            "\(marker) \(text)",
            location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
        )
        .padding(.leading, CGFloat(indentation) * 16)
    }

    private func markdownCodeBlock(
        language: String?,
        content: String,
        blockIndex: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MudsnoteColors.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                markdownText(
                    content,
                    location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil),
                    selectionFont: .monospacedSystemFont(ofSize: 15, weight: .regular),
                    rendersInlineMarkdown: false
                )
                .font(.system(.callout, design: .monospaced))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(MudsnoteColors.line, lineWidth: 1)
        }
        .accessibilityIdentifier("rendered-markdown-code-\(blockIndex)")
    }

    private func markdownTable(
        headers: [String],
        rows: [[String]],
        blockIndex: Int
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                markdownTableRow(
                    headers,
                    isHeader: true,
                    blockIndex: blockIndex,
                    cellOffset: 0
                )
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    markdownTableRow(
                        row,
                        isHeader: false,
                        blockIndex: blockIndex,
                        cellOffset: (index + 1) * headers.count
                    )
                        .background(index.isMultiple(of: 2) ? Color.clear : MudsnoteColors.card.opacity(0.45))
                    if index < rows.count - 1 { Divider() }
                }
            }
            .background(MudsnoteColors.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(MudsnoteColors.line, lineWidth: 1)
            }
        }
        .accessibilityIdentifier("rendered-markdown-table")
    }

    private func markdownTableRow(
        _ cells: [String],
        isHeader: Bool,
        blockIndex: Int,
        cellOffset: Int
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                markdownText(
                    cell,
                    location: NoteFindLocation(
                        blockIndex: blockIndex,
                        cellIndex: cellOffset + index
                    ),
                    selectionFont: .preferredFont(
                        forTextStyle: isHeader ? .headline : .body
                    )
                )
                    .font(isHeader ? .headline : .body)
                    .frame(width: 132, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                if index < cells.count - 1 { Divider() }
            }
        }
    }

    private func attachmentView(
        _ attachment: MarkdownAttachmentLine,
        blockIndex: Int
    ) -> some View {
        let presentationMode = attachmentPresentationMode(for: attachment)
        let findMatch = activeAttachmentFindMatch.flatMap { match in
            match.relativePath == attachment.path && match.location.blockIndex == blockIndex
                ? match
                : nil
        }
        return VStack(alignment: .leading, spacing: 8) {
            renderedAttachment(attachment, mode: presentationMode)
                .accessibilityValue(presentationMode.rawValue)

            if let findMatch {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Match in Attachment", systemImage: "doc.text.magnifyingglass")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.yellow)
                    Text(findMatch.context)
                        .font(.caption)
                        .foregroundStyle(MudsnoteColors.muted)
                        .lineLimit(2)
                }
                .accessibilityIdentifier("find-attachment-match-\(attachment.path)")
            }
        }
        .padding(findMatch == nil ? 0 : 6)
        .overlay {
            if findMatch != nil {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.yellow, lineWidth: 2)
            }
        }
        .contextMenu {
            Menu {
                attachmentPresentationButton(.small, attachment: attachment)
                attachmentPresentationButton(.large, attachment: attachment)
                attachmentPresentationButton(.plainLink, attachment: attachment)
            } label: {
                Label("View As", systemImage: "rectangle.expand.vertical")
            }
            .accessibilityIdentifier("attachment-view-as-menu")

            if case .document = source {
                Divider()
                if let url = localFileURL(for: attachment.path) {
                    ShareLink(item: url) {
                        Label("Share Attachment", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    let fileName = (attachment.path as NSString).lastPathComponent
                    attachmentName = (fileName as NSString).deletingPathExtension
                    attachmentBeingRenamed = attachment
                } label: {
                    Label("Rename Attachment", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    Task { await removeAttachment(attachment) }
                } label: {
                    Label("Remove from Note", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func renderedAttachment(
        _ attachment: MarkdownAttachmentLine,
        mode: AttachmentPresentationMode
    ) -> some View {
        switch mode {
        case .small:
            smallAttachment(attachment)
        case .large:
            largeAttachment(attachment)
        case .plainLink:
            plainAttachmentLink(attachment)
        }
    }

    @ViewBuilder
    private func largeAttachment(_ attachment: MarkdownAttachmentLine) -> some View {
        switch attachment.kind {
        case .image:
            if let image = localImage(for: attachment.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(MudsnoteColors.line, lineWidth: 1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        openAttachmentPreview(attachment.path)
                    }
                    .accessibilityIdentifier("preview-attachment-\(attachment.path)")
            } else {
                attachmentLabel(attachment)
            }
        case .video:
            if let url = localFileURL(for: attachment.path) {
                VideoAttachmentPlayer(url: url, title: attachment.path)
                    .accessibilityIdentifier("preview-attachment-\(attachment.path)")
            } else {
                attachmentLabel(attachment)
            }
        case .audio, .file:
            if attachment.kind == .audio, let url = localFileURL(for: attachment.path) {
                AudioAttachmentPlayer(url: url, title: attachment.path)
            } else if localFileURL(for: attachment.path) != nil {
                Button {
                    openAttachmentPreview(attachment.path)
                } label: {
                    attachmentLabel(attachment)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preview-attachment-\(attachment.path)")
            } else {
                attachmentLabel(attachment)
            }
        }
    }

    private func smallAttachment(_ attachment: MarkdownAttachmentLine) -> some View {
        Button {
            openAttachmentPreview(attachment.path)
        } label: {
            HStack(spacing: 12) {
                Group {
                    if attachment.kind == .image,
                       let image = localImage(for: attachment.path) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: attachment.systemImage)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(MudsnoteColors.primary)
                    }
                }
                .frame(width: 72, height: 54)
                .background(MudsnoteColors.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text((attachment.path as NSString).lastPathComponent)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(MudsnoteColors.text)
                        .lineLimit(1)
                    Text(attachmentKindLabel(attachment.kind))
                        .font(.caption)
                        .foregroundStyle(MudsnoteColors.muted)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MudsnoteColors.muted)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preview-attachment-\(attachment.path)")
    }

    private func plainAttachmentLink(_ attachment: MarkdownAttachmentLine) -> some View {
        Button {
            openAttachmentPreview(attachment.path)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: attachment.systemImage)
                Text((attachment.path as NSString).lastPathComponent)
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.caption2.weight(.bold))
            }
            .font(.callout)
            .foregroundStyle(MudsnoteColors.primary)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("preview-attachment-\(attachment.path)")
    }

    private func attachmentPresentationButton(
        _ mode: AttachmentPresentationMode,
        attachment: MarkdownAttachmentLine
    ) -> some View {
        Button {
            setAttachmentPresentationMode(mode, for: attachment)
        } label: {
            Label(
                attachmentPresentationLabel(mode),
                systemImage: attachmentPresentationMode(for: attachment) == mode
                    ? "checkmark"
                    : attachmentPresentationSymbol(mode)
            )
        }
        .accessibilityIdentifier("attachment-view-as-\(mode.rawValue)")
    }

    private func attachmentPresentationLabel(_ mode: AttachmentPresentationMode) -> String {
        switch mode {
        case .small: String(localized: "Small")
        case .large: String(localized: "Large")
        case .plainLink: String(localized: "Plain Link")
        }
    }

    private func attachmentPresentationSymbol(_ mode: AttachmentPresentationMode) -> String {
        switch mode {
        case .small: "rectangle.compress.vertical"
        case .large: "rectangle.expand.vertical"
        case .plainLink: "link"
        }
    }

    private func attachmentKindLabel(_ kind: MarkdownAttachmentLine.Kind) -> String {
        switch kind {
        case .image: String(localized: "Photo")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .file: String(localized: "Document")
        }
    }

    private func attachmentLabel(_ attachment: MarkdownAttachmentLine) -> some View {
        Label(attachment.path, systemImage: attachment.systemImage)
            .font(.callout)
            .foregroundStyle(MudsnoteColors.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func openAttachmentPreview(_ relativePath: String) {
        Task {
            attachmentPreview = await appModel.prepareAttachmentPreview(
                relativePath: relativePath
            )
        }
    }

    private func localImage(for relativePath: String) -> UIImage? {
        guard let url = localFileURL(for: relativePath) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func localFileURL(for relativePath: String) -> URL? {
        guard case .ready(let root) = appModel.folderStatus else { return nil }
        _ = accessRevision
        return AuthorizedLibraryPath.resolve(relativePath, within: root)
    }

    private func beginLibraryAccess() {
        guard accessedRoot == nil,
              case .ready(let root) = appModel.folderStatus else { return }
        if root.startAccessingSecurityScopedResource() {
            accessedRoot = root
        }
        accessRevision += 1
    }

    private func endLibraryAccess() {
        accessedRoot?.stopAccessingSecurityScopedResource()
        accessedRoot = nil
    }

    private func markdownText(
        _ line: String,
        location: NoteFindLocation,
        selectionFont: UIFont = .preferredFont(forTextStyle: .body),
        rendersInlineMarkdown: Bool = true
    ) -> some View {
        let renderedText = NoteFindIndex.highlightedText(
            for: line,
            query: findQuery,
            location: location,
            activeMatch: activeFindMatch,
            rendersInlineMarkdown: rendersInlineMarkdown
        )
        return Text(renderedText)
            .foregroundStyle(MudsnoteColors.text)
            .font(Font(selectionFont))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                readerTextWidths[location] = width
            }
            .simultaneousGesture(
                SpatialTapGesture(count: 2).onEnded { event in
                    let offset = ReaderInsertionPosition.offset(
                        at: event.location,
                        width: readerTextWidths[location] ?? 1,
                        text: renderedText,
                        font: selectionFont
                    )
                    beginEditingFromReader(at: ReaderInsertionPosition.sourceOffset(
                        in: renderedMarkdown,
                        location: location,
                        displayedSource: line,
                        renderedOffset: offset,
                        inlineMarkdown: rendersInlineMarkdown
                    ))
                }
            )
    }

    @MainActor
    private func finishEditingAfterPendingAutosave() async {
        while isSaving {
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
        }
        await persistDraft(finishEditing: true, announce: true)
    }

    @MainActor
    private func persistDraft(finishEditing: Bool, announce: Bool) async {
        if finishEditing { editorFocused = false }
        if finishEditing {
            migrateRemainingInlineTags()
        }
        guard !isSaving else { return }
        let requiresNewDocumentFinalization: Bool
        if case .document(let document) = source {
            requiresNewDocumentFinalization = finishEditing && document.isNew
        } else {
            requiresNewDocumentFinalization = false
        }
        guard draftMarkdown != originalMarkdown || requiresNewDocumentFinalization else {
            if finishEditing { isEditing = false }
            return
        }
        let presentsSaveActivity = finishEditing || announce
        isSaving = true
        if presentsSaveActivity {
            isSaveProgressVisible = true
            saveState = .saving
        }

        var succeeded = true
        repeat {
            let snapshot = draftMarkdown
            let saved = await save(snapshot, announce: announce)
            if saved {
                originalMarkdown = snapshot
                if presentsSaveActivity || saveState == .failed {
                    saveState = .saved
                }
            } else {
                succeeded = false
                saveState = .failed
                isSaveFailurePresented = true
                break
            }
        } while draftMarkdown != originalMarkdown

        isSaving = false
        isSaveProgressVisible = false
        if finishEditing, succeeded, draftMarkdown == originalMarkdown {
            isEditing = false
        } else if !succeeded {
            editorFocused = true
        }
    }

    private func migrateRemainingInlineTags() {
        switch source {
        case .document:
            let migration = MarkdownTagSyntax.migratingInlineTagsToFrontMatter(
                in: draftMarkdown
            )
            guard migration.occurrenceCount > 0 else { return }
            draftMarkdown = migration.body
        case .memo(var memo):
            let migration = MarkdownTagSyntax.extractingInlineTags(
                from: draftMarkdown
            )
            guard migration.occurrenceCount > 0 else { return }
            draftMarkdown = migration.body
            var seen = Set<String>()
            memo.tags = (memo.tags + migration.tags).filter {
                seen.insert(MarkdownTagSyntax.key($0)).inserted
            }
            source = .memo(memo)
        }
        tagDraft = nil
    }

    private func save(_ markdown: String, announce: Bool) async -> Bool {
        hasSaveConflict = false
        switch source {
        case .memo(let memo):
            guard let updated = await appModel.saveMemo(
                memo,
                body: markdown,
                expectedBody: originalMarkdown,
                tags: memo.tags,
                announce: announce,
                onConflict: { hasSaveConflict = true }
            ) else { return false }
            source = .memo(updated)
            return true
        case .document(let document):
            guard let updated = await appModel.saveDocument(
                document,
                markdown: markdown,
                expectedMarkdown: originalMarkdown,
                announce: announce,
                onConflict: { hasSaveConflict = true }
            ) else { return false }
            source = .document(updated)
            return true
        }
    }

    private func reloadSavedVersion() async {
        let markdown: String?
        switch source {
        case .memo(let memo):
            markdown = await appModel.reloadMemo(memo)?.body
        case .document(let document):
            if let reloaded = await appModel.reloadDocument(document) {
                source = .document(reloaded)
                markdown = reloaded.markdown
            } else {
                markdown = nil
            }
        }
        if let markdown {
            draftMarkdown = markdown
            originalMarkdown = markdown
            saveState = .saved
            hasSaveConflict = false
            editorFocused = true
        } else {
            saveState = .failed
        }
    }

    @MainActor
    private func saveConflictedDraftAsCopy() async {
        guard hasSaveConflict, !isSaving else { return }
        let snapshot = draftMarkdown
        let memoTags: [String]
        if case .memo(let memo) = source {
            memoTags = memo.tags
        } else {
            memoTags = []
        }
        func includingMemoTags(_ markdown: String) -> String {
            memoTags.reduce(markdown) { MarkdownTagSyntax.adding($1, to: $0) ?? $0 }
        }
        isSaving = true
        isSaveProgressVisible = true
        saveState = .saving
        let copy = await appModel.saveDocumentCopy(
            relativePath: currentSourceRelativePath,
            markdown: includingMemoTags(snapshot)
        )
        isSaving = false
        isSaveProgressVisible = false
        guard let copy else {
            saveState = .failed
            isSaveFailurePresented = true
            editorFocused = true
            return
        }
        source = .document(copy)
        originalMarkdown = copy.markdown
        draftMarkdown = includingMemoTags(draftMarkdown)
        noteName = copy.title
        saveState = .saved
        hasSaveConflict = false
        editorFocused = true
        // Edits entered while the copy was writing now belong to the copy as well.
        if draftMarkdown != originalMarkdown {
            await persistDraft(finishEditing: false, announce: false)
        }
    }

    private func attachPhoto(_ item: PhotosPickerItem?) async {
        defer { selectedPhotoItem = nil }
        guard case .document = source else { return }
        await persistDraft(finishEditing: false, announce: false)
        guard draftMarkdown == originalMarkdown,
              case .document(let document) = source else { return }
        saveState = .saving
        if let updated = await appModel.attachPhoto(
            item,
            to: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            editorFocused = true
        } else {
            saveState = .failed
            isSaveFailurePresented = true
        }
    }

    private func attachCameraPhoto(_ media: CapturedCameraMedia) async {
        guard case .document = source else { return }
        await persistDraft(finishEditing: false, announce: false)
        guard draftMarkdown == originalMarkdown,
              case .document(let document) = source else { return }
        saveState = .saving
        if let updated = await appModel.attachCameraPhoto(
            media,
            to: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            editorFocused = true
        } else {
            saveState = .failed
            isSaveFailurePresented = true
        }
    }

    private func attachDrawing(_ data: Data) async {
        guard case .document = source else { return }
        await persistDraft(finishEditing: false, announce: false)
        guard draftMarkdown == originalMarkdown,
              case .document(let document) = source else { return }
        saveState = .saving
        if let updated = await appModel.attachDrawing(
            data,
            to: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            editorFocused = true
        } else {
            saveState = .failed
            isSaveFailurePresented = true
        }
    }

    private func attachFile(_ url: URL) async {
        guard case .document = source else { return }
        await persistDraft(finishEditing: false, announce: false)
        guard draftMarkdown == originalMarkdown,
              case .document(let document) = source else { return }
        saveState = .saving
        if let updated = await appModel.attachFile(
            url,
            to: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            editorFocused = true
        } else {
            saveState = .failed
            isSaveFailurePresented = true
        }
    }

    private func attachScannedDocument(_ pages: [UIImage]) async {
        do {
            let data = try ScannedDocumentPDF.data(for: pages)
            let temporaryDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories: true
            )
            let temporaryURL = temporaryDirectory.appendingPathComponent(
                ScannedDocumentPDF.suggestedFileName
            )
            try data.write(to: temporaryURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
            await attachFile(temporaryURL)
        } catch {
            scanErrorMessage = error.localizedDescription
        }
    }

    private var audioButtonSystemImage: String {
        if isAudioTransitioning { return "hourglass" }
        if pendingAudioRecording != nil { return "exclamationmark.waveform" }
        return noteAudioRecorder.isRecording ? "stop.fill" : "waveform"
    }

    private var audioButtonAccessibilityLabel: String {
        if isTranscribingDocumentAudio { return String(localized: "Transcribing...") }
        if pendingAudioRecording != nil { return String(localized: "Retry audio attachment") }
        return String(localized: noteAudioRecorder.isRecording ? "Stop recording" : "Record audio")
    }

    private func toggleDocumentAudioRecording() async {
        guard case .document = source, !isAudioTransitioning else { return }
        if pendingAudioRecording != nil {
            await attachPendingAudioRecording()
            return
        }

        isAudioTransitioning = true
        defer { isAudioTransitioning = false }
        do {
            await persistDraft(finishEditing: false, announce: false)
            guard draftMarkdown == originalMarkdown else { return }

            if noteAudioRecorder.isRecording {
                guard let recording = try await noteAudioRecorder.stop() else { return }
                pendingAudioRecording = recording
                await attachPendingAudioRecording()
            } else {
                try await noteAudioRecorder.start()
                appModel.statusToast = .pending(String(localized: "Recording"))
            }
        } catch {
            noteAudioRecorder.cancel()
            appModel.statusToast = .error(error.localizedDescription)
        }
    }

    private func attachPendingAudioRecording() async {
        guard let recording = pendingAudioRecording,
              case .document(let document) = source else { return }
        saveState = .saving
        if let updated = await appModel.attachAudio(
            recording.data,
            to: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            isTranscribingDocumentAudio = true
            appModel.statusToast = .pending(String(localized: "Transcribing..."))
            defer {
                try? FileManager.default.removeItem(at: recording.temporaryURL)
                pendingAudioRecording = nil
                isTranscribingDocumentAudio = false
                editorFocused = true
            }
            do {
                let transcript = try await noteAudioRecorder.transcribe(
                    url: recording.temporaryURL
                )
                let updatedMarkdown = MarkdownAudioTranscript.appending(
                    transcript,
                    to: updated.markdown
                )
                guard updatedMarkdown != updated.markdown else {
                    appModel.statusToast = .pending(
                        String(localized: "No speech detected. Audio kept.")
                    )
                    return
                }
                draftMarkdown = updatedMarkdown
                await persistDraft(finishEditing: false, announce: false)
                if draftMarkdown == originalMarkdown {
                    appModel.statusToast = .saved(String(localized: "Audio attached and transcribed"))
                }
            } catch is CancellationError {
                appModel.statusToast = .pending(String(localized: "Audio attached"))
            } catch {
                appModel.statusToast = .error(String(
                    format: String(localized: "note.audio_transcription_failed.format"),
                    locale: .current,
                    error.localizedDescription
                ))
            }
        } else {
            saveState = .failed
            isAudioAttachmentFailurePresented = true
        }
    }

    private func retryPendingAudioRecording() async {
        guard !isAudioTransitioning else { return }
        isAudioTransitioning = true
        defer { isAudioTransitioning = false }
        await attachPendingAudioRecording()
    }

    private func discardPendingAudioRecording() {
        guard let recording = pendingAudioRecording else { return }
        try? FileManager.default.removeItem(at: recording.temporaryURL)
        pendingAudioRecording = nil
    }

    private func removeAttachment(_ attachment: MarkdownAttachmentLine) async {
        guard case .document(let document) = source else { return }
        if let updated = await appModel.removeAttachment(
            line: attachment.rawLine,
            from: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            appModel.removeAttachmentPresentationPreference(
                notePath: document.relativePath,
                attachmentPath: attachment.path
            )
        } else {
            saveState = .failed
            isSaveFailurePresented = true
        }
    }

    private func renameAttachment(_ attachment: MarkdownAttachmentLine, to name: String) async {
        guard case .document(let document) = source else { return }
        if let updated = await appModel.renameAttachment(
            line: attachment.rawLine,
            path: attachment.path,
            to: name,
            in: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            let previousPaths = attachmentPaths(in: draftMarkdown)
            let renamedPath = attachmentPaths(in: updated.markdown)
                .subtracting(previousPaths)
                .first
            if let renamedPath {
                appModel.moveAttachmentPresentationPreference(
                    notePath: document.relativePath,
                    from: attachment.path,
                    to: renamedPath
                )
            }
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
        }
    }

    private func attachmentPaths(in markdown: String) -> Set<String> {
        Set(MarkdownRenderBlock.parse(markdown).compactMap { block in
            guard case .line(let line) = block else { return nil }
            return MarkdownAttachmentLine(line)?.path
        })
    }
}

struct MarkdownDocumentSelectionOverlay: UIViewRepresentable {
    var attributedText: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.backgroundColor = .clear
        textView.isOpaque = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.tintColor = .systemBlue
        textView.clipsToBounds = false
        textView.isAccessibilityElement = false
        textView.accessibilityElementsHidden = true
        update(textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        update(textView)
    }

    private func update(_ textView: UITextView) {
        let invisibleText = NSMutableAttributedString(attributedString: attributedText)
        let range = NSRange(location: 0, length: invisibleText.length)
        invisibleText.addAttribute(.foregroundColor, value: UIColor.clear, range: range)
        textView.attributedText = invisibleText
    }
}
