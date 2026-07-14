import SwiftUI
import AVFoundation
import PencilKit
import PhotosUI
import QuickLook
import UIKit
import UniformTypeIdentifiers
import VisionKit

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

    private struct RenderedBlockItem: Identifiable {
        var index: Int
        var block: MarkdownRenderBlock
        var hasCollapsibleContent: Bool

        var id: Int { index }
    }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @Binding private var detent: PresentationDetent
    @State private var source: Source
    @State private var draftMarkdown: String
    @State private var originalMarkdown: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveState: SaveState = .idle
    @State private var isSaveFailurePresented = false
    @State private var editorFocused = false
    @State private var editingCommand: MarkdownEditingCommand?
    @State private var linkDraft: MarkdownLinkDraft?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isFileImporterPresented = false
    @State private var isScannerPresented = false
    @State private var isDrawingPresented = false
    @State private var scanErrorMessage: String?
    @State private var previewURL: URL?
    @State private var attachmentBeingRenamed: MarkdownAttachmentLine?
    @State private var attachmentName = ""
    @State private var editorDisplayMode: EditorDisplayMode = .rich
    @State private var accessedRoot: URL?
    @State private var accessRevision = 0
    @StateObject private var noteAudioRecorder = AudioCaptureService()
    @State private var isAudioTransitioning = false
    @State private var pendingAudioRecording: RecordedAudio?
    @State private var isAudioAttachmentFailurePresented = false
    @State private var noteName = ""
    @State private var isRenamingNote = false
    @State private var isConfirmingNoteDeletion = false
    @State private var isFindingInNote = false
    @State private var findQuery = ""
    @State private var activeFindIndex = 0
    @State private var collapsedHeadingIndices: Set<Int> = []
    @FocusState private var isFindFocused: Bool

    init(memo: MemoBlock, detent: Binding<PresentationDetent>) {
        _detent = detent
        _source = State(initialValue: .memo(memo))
        _draftMarkdown = State(initialValue: memo.body)
        _originalMarkdown = State(initialValue: memo.body)
    }

    init(document: MarkdownDocument, detent: Binding<PresentationDetent>) {
        _detent = detent
        _source = State(initialValue: .document(document))
        _draftMarkdown = State(initialValue: document.markdown)
        _originalMarkdown = State(initialValue: document.markdown)
        _isEditing = State(initialValue: document.isNew)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    VStack(alignment: .leading, spacing: 12) {
                        metadataLabel
                        MarkdownTextEditor(
                            text: $draftMarkdown,
                            isFocused: $editorFocused,
                            command: $editingCommand,
                            linkDraft: $linkDraft,
                            displaysSource: editorDisplayMode == .source
                        )
                        .accessibilityIdentifier("markdown-editor")
                    }
                    .padding(MudsnoteSpacing.safeHorizontal)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                metadataLabel
                                markdownBody
                                    .accessibilityElement(children: .contain)
                                    .accessibilityIdentifier("rendered-markdown")
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if !isFindingInNote { beginEditing() }
                                    }
                            }
                            .padding(MudsnoteSpacing.safeHorizontal)
                        }
                        .onChange(of: findQuery) { _, _ in
                            activeFindIndex = 0
                            scrollToActiveFindMatch(using: proxy)
                        }
                        .onChange(of: activeFindIndex) { _, _ in
                            scrollToActiveFindMatch(using: proxy)
                        }
                    }
                }
            }
            .background(MudsnoteColors.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEditing {
                    markdownToolbar
                } else if isFindingInNote {
                    noteFindBar
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isEditing {
                        Menu {
                            Button {
                                editorDisplayMode = .rich
                            } label: {
                                Label("Rich Text", systemImage: editorDisplayMode == .rich ? "checkmark" : "textformat")
                            }
                            Button {
                                editorDisplayMode = .source
                            } label: {
                                Label("Markdown Source", systemImage: editorDisplayMode == .source ? "checkmark" : "chevron.left.forwardslash.chevron.right")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Editor Options")
                        .accessibilityIdentifier("markdown-display-mode")
                    }

                    if !isEditing {
                        switch source {
                        case .memo:
                            ShareLink(item: draftMarkdown) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel("Share Note")
                            .accessibilityIdentifier("share-note-button")
                        case .document(let document):
                            Menu {
                                if let url = localFileURL(for: document.relativePath) {
                                    ShareLink(item: url) {
                                        Label("Share Note", systemImage: "square.and.arrow.up")
                                    }
                                }
                                Button {
                                    beginFindingInNote()
                                } label: {
                                    Label("Find in Note", systemImage: "magnifyingglass")
                                }
                                .disabled(draftMarkdown.isEmpty)
                                if let file = currentFile, canManage(document) {
                                    Divider()
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
                                                    Task {
                                                        await moveCurrentDocument(
                                                            toFolder: folder.relativePath
                                                        )
                                                    }
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
                                    Divider()
                                    Button(role: .destructive) {
                                        isConfirmingNoteDeletion = true
                                    } label: {
                                        Label("Move to Recently Deleted", systemImage: "trash")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                            .accessibilityLabel("Note Options")
                            .accessibilityIdentifier("note-options-menu")
                        }
                    }

                    Button(action: toggleDetent) {
                        Image(systemName: detent == .large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(detent == .large ? "Collapse editor" : "Expand editor")
                    .accessibilityIdentifier(detent == .large ? "collapse-markdown-editor" : "expand-markdown-editor")

                    if isEditing {
                        Button {
                            Task { await persistDraft(finishEditing: true, announce: true) }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("Done")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(
                            isSaving
                                || isAudioTransitioning
                                || noteAudioRecorder.isRecording
                                || pendingAudioRecording != nil
                        )
                        .accessibilityLabel("Save note")
                        .accessibilityIdentifier("save-markdown-button")
                    }
                }
            }
        }
        .interactiveDismissDisabled(
            (isEditing && draftMarkdown != originalMarkdown)
                || noteAudioRecorder.isRecording
                || isAudioTransitioning
                || pendingAudioRecording != nil
        )
        .onAppear {
            beginLibraryAccess()
            if isEditing {
                detent = .large
                focusEditorAfterPresentation()
            }
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
            matching: .images
        )
        .task(id: AutosaveID(markdown: draftMarkdown, isEditing: isEditing)) {
            guard isEditing, draftMarkdown != originalMarkdown else { return }
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await persistDraft(finishEditing: false, announce: false)
        }
        .alert("Couldn’t Save Note", isPresented: $isSaveFailurePresented) {
            Button("Keep Editing", role: .cancel) {
                editorFocused = true
            }
            Button("Reopen Saved Version", role: .destructive) {
                Task { await reloadSavedVersion() }
            }
        } message: {
            Text("The note may have changed elsewhere. Reopen the saved version or keep your current draft and try again.")
        }
        .alert("Couldn’t Attach Audio", isPresented: $isAudioAttachmentFailurePresented) {
            Button("Keep Editing", role: .cancel) {
                editorFocused = true
            }
            Button("Retry") {
                Task { await attachPendingAudioRecording() }
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
            "Move Note to Recently Deleted?",
            isPresented: $isConfirmingNoteDeletion,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Recently Deleted", role: .destructive) {
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
        .quickLookPreview($previewURL)
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
    }

    private func applyLinkCommand(_ kind: MarkdownEditingCommand.Kind) {
        Task { @MainActor in
            await Task.yield()
            editingCommand = MarkdownEditingCommand(kind: kind)
            editorFocused = true
        }
    }

    private func canManage(_ document: MarkdownDocument) -> Bool {
        document.relativePath != "Inbox.md"
            && !document.relativePath.hasPrefix("Daily/")
    }

    private var currentFile: RecentMarkdownFile? {
        guard case .document(let document) = source else { return nil }
        return appModel.libraryFiles.first { $0.relativePath == document.relativePath }
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
        MarkdownRenderBlock.parse(draftMarkdown)
    }

    private var findMatches: [NoteFindMatch] {
        NoteFindIndex.matches(in: renderBlocks, query: findQuery)
    }

    private var activeFindMatch: NoteFindMatch? {
        guard !findMatches.isEmpty else { return nil }
        return findMatches[min(activeFindIndex, findMatches.count - 1)]
    }

    private var findCountLabel: String {
        let total = findMatches.count
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

            Text(findCountLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(MudsnoteColors.muted)
                .frame(minWidth: 42)
                .accessibilityIdentifier("find-in-note-count")

            Button { stepFindMatch(by: -1) } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 30, height: 34)
            }
            .disabled(findMatches.isEmpty)
            .accessibilityLabel("Previous Match")
            .accessibilityIdentifier("find-in-note-previous")

            Button { stepFindMatch(by: 1) } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 30, height: 34)
            }
            .disabled(findMatches.isEmpty)
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
        withAnimation(.snappy(duration: 0.28)) { detent = .large }
        Task { @MainActor in
            await Task.yield()
            isFindFocused = true
        }
    }

    private func closeFindInNote() {
        isFindFocused = false
        findQuery = ""
        activeFindIndex = 0
        isFindingInNote = false
    }

    private func stepFindMatch(by offset: Int) {
        guard !findMatches.isEmpty else { return }
        activeFindIndex = (activeFindIndex + offset + findMatches.count) % findMatches.count
    }

    private func scrollToActiveFindMatch(using proxy: ScrollViewProxy) {
        guard let match = activeFindMatch else { return }
        let hiddenSections = MarkdownSectionProjection.collapsedHeadings(
            containing: match.location.blockIndex,
            in: renderBlocks,
            collapsed: collapsedHeadingIndices
        )
        if !hiddenSections.isEmpty {
            withAnimation(.snappy(duration: 0.22)) {
                collapsedHeadingIndices.subtract(hiddenSections)
            }
        }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.snappy(duration: 0.2)) {
                proxy.scrollTo(match.location.blockIndex, anchor: .center)
            }
        }
    }

    private var saveStatusText: LocalizedStringKey {
        switch saveState {
        case .idle: draftMarkdown == originalMarkdown ? "Saved" : "Edited"
        case .saving: "Saving…"
        case .saved: "Saved"
        case .failed: "Not Saved"
        }
    }

    private var markdownToolbar: some View {
        let attachmentIsPreparing = appModel.isPreparingAttachment
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if case .document = source {
                    Menu {
                        Button {
                            isPhotoPickerPresented = true
                        } label: {
                            Label("Add image from Photos", systemImage: "photo")
                        }
                        .accessibilityIdentifier("markdown-add-image")

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
                    } label: {
                        editorToolIcon(attachmentIsPreparing ? "hourglass" : "paperclip")
                    }
                    .disabled(isSaving || appModel.isPreparingAttachment)
                    .accessibilityLabel("Add Attachment")
                    .accessibilityIdentifier("markdown-attachment-menu")

                    Button {
                        Task { await toggleDocumentAudioRecording() }
                    } label: {
                        editorToolIcon(
                            audioButtonSystemImage,
                            foreground: noteAudioRecorder.isRecording ? .white : MudsnoteColors.text,
                            background: noteAudioRecorder.isRecording ? .red : MudsnoteColors.card
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        isSaving
                            || appModel.isPreparingAttachment
                            || isAudioTransitioning
                    )
                    .accessibilityLabel(audioButtonAccessibilityLabel)
                    .accessibilityIdentifier("markdown-record-audio")
                }

                Menu {
                    formatMenuButton("Title", systemImage: "textformat.size.larger", command: .title)
                    formatMenuButton("Heading", systemImage: "textformat.size", command: .heading)
                    formatMenuButton("Subheading", systemImage: "textformat.size.smaller", command: .subheading)
                    formatMenuButton("Body", systemImage: "textformat", command: .body)
                    Divider()
                    formatMenuButton("Bold", systemImage: "bold", command: .bold)
                    formatMenuButton("Italic", systemImage: "italic", command: .italic)
                    formatMenuButton("Underline", systemImage: "underline", command: .underline)
                    formatMenuButton("Highlight", systemImage: "highlighter", command: .highlight)
                    formatMenuButton("Strikethrough", systemImage: "strikethrough", command: .strikethrough)
                    Divider()
                    formatMenuButton("Bulleted List", systemImage: "list.bullet", command: .bullet)
                    formatMenuButton("Numbered List", systemImage: "list.number", command: .ordered)
                    formatMenuButton("Decrease Indent", systemImage: "decrease.indent", command: .outdent)
                    formatMenuButton("Increase Indent", systemImage: "increase.indent", command: .indent)
                    Divider()
                    formatMenuButton("Quote", systemImage: "text.quote", command: .quote)
                    formatMenuButton("Code", systemImage: "chevron.left.forwardslash.chevron.right", command: .code)
                    formatMenuButton("Insert Link", systemImage: "link", command: .link)
                } label: {
                    Text("Aa")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(MudsnoteColors.text)
                        .frame(width: 40, height: 40)
                        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("Formatting")
                .accessibilityIdentifier("markdown-format-menu")

                formatButton("checklist", .checklist)
                formatButton("tablecells", .table)
                formatButton("arrow.uturn.backward", .undo)
                formatButton("arrow.uturn.forward", .redo)
            }
            .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(MudsnoteColors.line).frame(height: 1) }
    }

    private func formatButton(_ systemImage: String, _ kind: MarkdownEditingCommand.Kind) -> some View {
        Button {
            editingCommand = MarkdownEditingCommand(kind: kind)
        } label: {
            editorToolIcon(systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("markdown-format-\(kind.identifier)")
    }

    private func formatMenuButton(
        _ title: LocalizedStringKey,
        systemImage: String,
        command: MarkdownEditingCommand.Kind
    ) -> some View {
        Button {
            editingCommand = MarkdownEditingCommand(kind: command)
        } label: {
            Label(title, systemImage: systemImage)
        }
        .accessibilityIdentifier("markdown-format-\(command.identifier)")
    }

    private func editorToolIcon(
        _ systemImage: String,
        foreground: Color = MudsnoteColors.text,
        background: Color = MudsnoteColors.card
    ) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 40, height: 40)
            .background(background, in: RoundedRectangle(cornerRadius: 10))
    }

    private func beginEditing() {
        isEditing = true
        withAnimation(.snappy(duration: 0.28)) { detent = .large }
        focusEditorAfterPresentation()
    }

    private func focusEditorAfterPresentation() {
        Task { @MainActor in
            await Task.yield()
            editorFocused = true
        }
    }

    private func toggleDetent() {
        withAnimation(.snappy(duration: 0.28)) {
            detent = detent == .large ? .medium : .large
        }
    }

    private var markdownBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(visibleRenderBlockItems) { item in
                Group {
                    switch item.block {
                    case .line(let line):
                        markdownLine(
                            line,
                            blockIndex: item.index,
                            hasCollapsibleContent: item.hasCollapsibleContent
                        )
                    case .table(let headers, let rows):
                        markdownTable(
                            headers: headers,
                            rows: rows,
                            blockIndex: item.index
                        )
                    }
                }
                .id(item.index)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy(duration: 0.22), value: collapsedHeadingIndices)
    }

    private var visibleRenderBlockItems: [RenderedBlockItem] {
        let blocks = renderBlocks
        return MarkdownSectionProjection.visibleIndices(
            in: blocks,
            collapsed: collapsedHeadingIndices
        ).map { index in
            RenderedBlockItem(
                index: index,
                block: blocks[index],
                hasCollapsibleContent: MarkdownSectionProjection.hasCollapsibleContent(
                    after: index,
                    in: blocks
                )
            )
        }
    }

    private var metadata: String {
        switch source {
        case .memo(let memo): memo.dateText
        case .document(let document):
            (document.modifiedAt ?? Date()).formatted(date: .abbreviated, time: .shortened)
        }
    }

    @ViewBuilder
    private func markdownLine(
        _ line: String,
        blockIndex: Int,
        hasCollapsibleContent: Bool
    ) -> some View {
        if let attachment = MarkdownAttachmentLine(line) {
            attachmentView(attachment)
        } else if MarkdownHeading(line) != nil {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if hasCollapsibleContent {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            if collapsedHeadingIndices.contains(blockIndex) {
                                collapsedHeadingIndices.remove(blockIndex)
                            } else {
                                collapsedHeadingIndices.insert(blockIndex)
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MudsnoteColors.muted)
                            .rotationEffect(
                                .degrees(collapsedHeadingIndices.contains(blockIndex) ? 0 : 90)
                            )
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("markdown-section-toggle-\(blockIndex)")
                }

                markdownText(
                    line,
                    location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
                )
            }
        } else if line.hasPrefix(">") {
            markdownText(
                line,
                location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
            )
                .font(.body.italic())
                .foregroundStyle(MudsnoteColors.muted)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle().fill(MudsnoteColors.line).frame(width: 3)
                }
        } else {
            markdownText(
                line,
                location: NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
            )
        }
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

    @ViewBuilder
    private func attachmentView(_ attachment: MarkdownAttachmentLine) -> some View {
        Group {
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
                            previewURL = localFileURL(for: attachment.path)
                        }
                        .accessibilityIdentifier("preview-attachment-\(attachment.path)")
                } else {
                    attachmentLabel(attachment)
                }
            case .audio, .file:
                if attachment.kind == .audio, let url = localFileURL(for: attachment.path) {
                    AudioAttachmentPlayer(url: url, title: attachment.path)
                } else if let url = localFileURL(for: attachment.path) {
                    Button {
                        previewURL = url
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
        .contextMenu {
            if case .document = source {
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

    private func attachmentLabel(_ attachment: MarkdownAttachmentLine) -> some View {
        Label(attachment.path, systemImage: attachment.systemImage)
            .font(.callout)
            .foregroundStyle(MudsnoteColors.muted)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 16))
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
        location: NoteFindLocation
    ) -> Text {
        Text(NoteFindIndex.highlightedText(
            for: line,
            query: findQuery,
            location: location,
            activeMatch: activeFindMatch
        ))
        .foregroundStyle(MudsnoteColors.text)
    }

    @MainActor
    private func persistDraft(finishEditing: Bool, announce: Bool) async {
        if finishEditing { editorFocused = false }
        guard !isSaving else { return }
        guard draftMarkdown != originalMarkdown else {
            if finishEditing { isEditing = false }
            return
        }
        isSaving = true
        saveState = .saving

        var succeeded = true
        repeat {
            let snapshot = draftMarkdown
            let saved = await save(snapshot, announce: announce)
            if saved {
                originalMarkdown = snapshot
                saveState = .saved
            } else {
                succeeded = false
                saveState = .failed
                isSaveFailurePresented = true
                break
            }
        } while draftMarkdown != originalMarkdown

        isSaving = false
        if finishEditing, succeeded, draftMarkdown == originalMarkdown {
            collapsedHeadingIndices.removeAll()
            isEditing = false
        } else if !succeeded {
            editorFocused = true
        }
    }

    private func save(_ markdown: String, announce: Bool) async -> Bool {
        switch source {
        case .memo(let memo):
            return await appModel.saveMemo(
                memo,
                body: markdown,
                expectedBody: originalMarkdown,
                announce: announce
            ) != nil
        case .document(let document):
            guard let updated = await appModel.saveDocument(
                document,
                markdown: markdown,
                expectedMarkdown: originalMarkdown,
                announce: announce
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
            editorFocused = true
        } else {
            saveState = .failed
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
                guard let recording = try noteAudioRecorder.stop() else { return }
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
            try? FileManager.default.removeItem(at: recording.temporaryURL)
            pendingAudioRecording = nil
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            editorFocused = true
        } else {
            saveState = .failed
            isAudioAttachmentFailurePresented = true
        }
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
            source = .document(updated)
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
        }
    }
}

private struct MarkdownLinkEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    let draft: MarkdownLinkDraft
    let onApply: (String, String) -> Void
    let onRemove: (() -> Void)?
    @State private var name: String
    @State private var destination: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case destination
    }

    init(
        draft: MarkdownLinkDraft,
        onApply: @escaping (String, String) -> Void,
        onRemove: (() -> Void)?
    ) {
        self.draft = draft
        self.onApply = onApply
        self.onRemove = onRemove
        _name = State(initialValue: draft.label)
        _destination = State(initialValue: draft.destination)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("markdown-link-name")
                    TextField("Link", text: $destination)
                        .focused($focusedField, equals: .destination)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("markdown-link-destination")
                }

                if let onRemove {
                    Section {
                        Button("Remove Link", role: .destructive) {
                            onRemove()
                        }
                        .accessibilityIdentifier("remove-markdown-link")
                    }
                }
            }
            .navigationTitle(draft.isExisting ? "Edit Link" : "Add Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(draft.isExisting ? "Done" : "Add") {
                        onApply(name, destination)
                    }
                    .fontWeight(.semibold)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                    .accessibilityIdentifier("apply-markdown-link")
                }
            }
        }
        .onAppear {
            focusedField = name.isEmpty ? .name : .destination
        }
    }
}

struct MarkdownEditingCommand: Identifiable, Equatable {
    enum Kind: Equatable {
        case title
        case heading
        case subheading
        case body
        case bold
        case italic
        case underline
        case highlight
        case strikethrough
        case bullet
        case ordered
        case checklist
        case outdent
        case indent
        case quote
        case code
        case link
        case applyLink(draft: MarkdownLinkDraft, label: String, destination: String)
        case removeLink(draft: MarkdownLinkDraft)
        case table
        case undo
        case redo

        var identifier: String {
            switch self {
            case .title: "title"
            case .heading: "heading"
            case .subheading: "subheading"
            case .body: "body"
            case .bold: "bold"
            case .italic: "italic"
            case .underline: "underline"
            case .highlight: "highlight"
            case .strikethrough: "strikethrough"
            case .bullet: "bullet"
            case .ordered: "ordered"
            case .checklist: "checklist"
            case .outdent: "outdent"
            case .indent: "indent"
            case .quote: "quote"
            case .code: "code"
            case .link: "link"
            case .applyLink: "apply-link"
            case .removeLink: "remove-link"
            case .table: "table"
            case .undo: "undo"
            case .redo: "redo"
            }
        }
    }

    let id = UUID()
    var kind: Kind
}

struct MarkdownLinkDraft: Identifiable, Equatable {
    let id = UUID()
    var range: NSRange
    var label: String
    var destination: String
    var isExisting: Bool
}

enum MarkdownLinkEditing {
    static func draft(in markdown: String, selection: NSRange) -> MarkdownLinkDraft? {
        let source = markdown as NSString
        guard selection.location >= 0, NSMaxRange(selection) <= source.length else { return nil }

        let expression = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\n]+)\)"#)
        let matches = expression?.matches(
            in: markdown,
            range: NSRange(location: 0, length: source.length)
        ) ?? []
        if let match = matches.first(where: { contains(selection, in: $0.range) }) {
            return MarkdownLinkDraft(
                range: match.range,
                label: source.substring(with: match.range(at: 1)),
                destination: source.substring(with: match.range(at: 2)),
                isExisting: true
            )
        }

        return MarkdownLinkDraft(
            range: selection,
            label: source.substring(with: selection),
            destination: "",
            isExisting: false
        )
    }

    static func insertionEdit(
        for draft: MarkdownLinkDraft,
        label: String,
        destination: String
    ) -> MarkdownListEdit? {
        let cleanedLabel = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "[", with: "(")
            .replacingOccurrences(of: "]", with: ")")
        guard !cleanedLabel.isEmpty,
              let normalizedDestination = normalizedDestination(destination) else { return nil }
        return MarkdownListEdit(
            range: draft.range,
            replacement: "[\(cleanedLabel)](\(normalizedDestination))",
            selection: NSRange(
                location: draft.range.location + 1,
                length: (cleanedLabel as NSString).length
            )
        )
    }

    static func removalEdit(for draft: MarkdownLinkDraft) -> MarkdownListEdit? {
        guard draft.isExisting else { return nil }
        return MarkdownListEdit(
            range: draft.range,
            replacement: draft.label,
            selection: NSRange(
                location: draft.range.location,
                length: (draft.label as NSString).length
            )
        )
    }

    static func normalizedDestination(_ value: String) -> String? {
        var destination = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else { return nil }
        destination = destination
            .replacingOccurrences(of: " ", with: "%20")
            .replacingOccurrences(of: "(", with: "%28")
            .replacingOccurrences(of: ")", with: "%29")
        let hasScheme = destination.range(
            of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
            options: .regularExpression
        ) != nil
        if !hasScheme,
           !destination.hasPrefix("#"),
           !destination.hasPrefix("/"),
           !destination.hasPrefix("./"),
           !destination.hasPrefix("../") {
            destination = destination.contains("@")
                ? "mailto:\(destination)"
                : "https://\(destination)"
        }
        return destination
    }

    private static func contains(_ selection: NSRange, in range: NSRange) -> Bool {
        if selection.length == 0 {
            return selection.location >= range.location && selection.location <= NSMaxRange(range)
        }
        return selection.location >= range.location && NSMaxRange(selection) <= NSMaxRange(range)
    }
}

enum MarkdownInlineEditing {
    static func toggleEdit(
        in markdown: String,
        selection: NSRange,
        prefix: String,
        suffix: String,
        placeholder: String
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length,
              !prefix.isEmpty,
              !suffix.isEmpty else { return nil }

        let prefixLength = (prefix as NSString).length
        let suffixLength = (suffix as NSString).length
        let selected = source.substring(with: selection)

        if selection.length >= prefixLength + suffixLength,
           selected.hasPrefix(prefix),
           selected.hasSuffix(suffix) {
            let contentRange = NSRange(
                location: prefixLength,
                length: selection.length - prefixLength - suffixLength
            )
            let content = (selected as NSString).substring(with: contentRange)
            return MarkdownListEdit(
                range: selection,
                replacement: content,
                selection: NSRange(location: selection.location, length: contentRange.length)
            )
        }

        if selection.location >= prefixLength,
           NSMaxRange(selection) + suffixLength <= source.length {
            let before = source.substring(with: NSRange(
                location: selection.location - prefixLength,
                length: prefixLength
            ))
            let after = source.substring(with: NSRange(
                location: NSMaxRange(selection),
                length: suffixLength
            ))
            if before == prefix, after == suffix {
                return MarkdownListEdit(
                    range: NSRange(
                        location: selection.location - prefixLength,
                        length: prefixLength + selection.length + suffixLength
                    ),
                    replacement: selected,
                    selection: NSRange(
                        location: selection.location - prefixLength,
                        length: selection.length
                    )
                )
            }
        }

        let content = selected.isEmpty ? placeholder : selected
        let replacement = prefix + content + suffix
        return MarkdownListEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(
                location: selection.location + prefixLength,
                length: (content as NSString).length
            )
        )
    }
}

enum MarkdownRenderBlock: Equatable {
    case line(String)
    case table(headers: [String], rows: [[String]])

    static func parse(_ markdown: String) -> [MarkdownRenderBlock] {
        let lines = markdown.components(separatedBy: .newlines)
        var blocks: [MarkdownRenderBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                index += 1
                continue
            }

            if index + 1 < lines.count,
               let headers = cells(in: line),
               isSeparator(lines[index + 1], columnCount: headers.count) {
                var rows: [[String]] = []
                index += 2
                while index < lines.count, let row = cells(in: lines[index]), row.count == headers.count {
                    rows.append(row)
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            blocks.append(.line(line))
            index += 1
        }
        return blocks
    }

    private static func cells(in line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("|") else { return nil }
        let content = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        let cells = content
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return cells.count >= 2 ? cells : nil
    }

    private static func isSeparator(_ line: String, columnCount: Int) -> Bool {
        guard let cells = cells(in: line), cells.count == columnCount else { return false }
        return cells.allSatisfy { cell in
            cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
        }
    }
}

struct MarkdownHeading: Equatable {
    var level: Int
    var title: String

    init(level: Int, title: String) {
        self.level = level
        self.title = title
    }

    init?(_ line: String) {
        let markerCount = line.prefix { $0 == "#" }.count
        guard (1...6).contains(markerCount),
              line.count > markerCount,
              line[line.index(line.startIndex, offsetBy: markerCount)] == " " else {
            return nil
        }
        let title = String(line.dropFirst(markerCount + 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        self.level = markerCount
        self.title = title
    }
}

enum MarkdownSectionProjection {
    static func visibleIndices(
        in blocks: [MarkdownRenderBlock],
        collapsed: Set<Int>
    ) -> [Int] {
        var result: [Int] = []
        var hiddenUntilHeadingLevel: Int?

        for (index, block) in blocks.enumerated() {
            let heading = parsedHeading(in: block)
            if let hiddenLevel = hiddenUntilHeadingLevel {
                guard let heading, heading.level <= hiddenLevel else { continue }
                hiddenUntilHeadingLevel = nil
            }

            result.append(index)
            if let heading, collapsed.contains(index) {
                hiddenUntilHeadingLevel = heading.level
            }
        }
        return result
    }

    static func hasCollapsibleContent(
        after headingIndex: Int,
        in blocks: [MarkdownRenderBlock]
    ) -> Bool {
        guard blocks.indices.contains(headingIndex),
              let currentHeading = parsedHeading(in: blocks[headingIndex]),
              blocks.indices.contains(headingIndex + 1) else { return false }
        if let nextHeading = parsedHeading(in: blocks[headingIndex + 1]) {
            return nextHeading.level > currentHeading.level
        }
        return true
    }

    static func collapsedHeadings(
        containing blockIndex: Int,
        in blocks: [MarkdownRenderBlock],
        collapsed: Set<Int>
    ) -> Set<Int> {
        guard blocks.indices.contains(blockIndex) else { return [] }
        return Set(collapsed.filter { headingIndex in
            guard headingIndex < blockIndex,
                  blocks.indices.contains(headingIndex),
                  let currentHeading = parsedHeading(in: blocks[headingIndex]) else { return false }
            let end = blocks.indices.dropFirst(headingIndex + 1).first { candidate in
                guard let candidateHeading = parsedHeading(in: blocks[candidate]) else { return false }
                return candidateHeading.level <= currentHeading.level
            } ?? blocks.endIndex
            return blockIndex < end
        })
    }

    private static func parsedHeading(in block: MarkdownRenderBlock) -> MarkdownHeading? {
        guard case .line(let line) = block else { return nil }
        return MarkdownHeading(line)
    }
}

struct NoteFindLocation: Hashable {
    var blockIndex: Int
    var cellIndex: Int?
}

struct NoteFindMatch: Identifiable, Equatable {
    var location: NoteFindLocation
    var occurrence: Int

    var id: String {
        "\(location.blockIndex):\(location.cellIndex ?? -1):\(occurrence)"
    }
}

enum NoteFindIndex {
    static func matches(
        in blocks: [MarkdownRenderBlock],
        query: String
    ) -> [NoteFindMatch] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        var results: [NoteFindMatch] = []
        for (blockIndex, block) in blocks.enumerated() {
            switch block {
            case .line(let line):
                guard MarkdownAttachmentLine(line) == nil else { continue }
                let location = NoteFindLocation(blockIndex: blockIndex, cellIndex: nil)
                results.append(contentsOf: matches(
                    in: visibleText(for: line),
                    term: term,
                    location: location
                ))
            case .table(let headers, let rows):
                let cells = headers + rows.flatMap { $0 }
                for (cellIndex, cell) in cells.enumerated() {
                    let location = NoteFindLocation(
                        blockIndex: blockIndex,
                        cellIndex: cellIndex
                    )
                    results.append(contentsOf: matches(
                        in: visibleText(for: cell),
                        term: term,
                        location: location
                    ))
                }
            }
        }
        return results
    }

    static func visibleText(for markdown: String) -> String {
        let source: String
        if markdown.hasPrefix(">") {
            source = markdown.trimmingCharacters(in: CharacterSet(charactersIn: "> "))
        } else {
            source = markdown
        }
        return String(MarkdownInlineRendering.attributedText(for: source).characters)
    }

    static func highlightedText(
        for markdown: String,
        query: String,
        location: NoteFindLocation,
        activeMatch: NoteFindMatch?
    ) -> AttributedString {
        let source = markdown.hasPrefix(">")
            ? markdown.trimmingCharacters(in: CharacterSet(charactersIn: "> "))
            : markdown
        let rendered = MarkdownInlineRendering.attributedText(for: source)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return rendered }

        let attributed = NSMutableAttributedString(
            attributedString: NSAttributedString(rendered)
        )
        for (occurrence, range) in ranges(in: attributed.string, term: term).enumerated() {
            let isActive = activeMatch?.location == location
                && activeMatch?.occurrence == occurrence
            attributed.addAttribute(
                .backgroundColor,
                value: isActive
                    ? UIColor.systemOrange
                    : UIColor.systemYellow.withAlphaComponent(0.55),
                range: range
            )
            if isActive {
                attributed.addAttribute(.foregroundColor, value: UIColor.black, range: range)
            }
        }
        return AttributedString(attributed)
    }

    private static func matches(
        in text: String,
        term: String,
        location: NoteFindLocation
    ) -> [NoteFindMatch] {
        ranges(in: text, term: term).indices.map {
            NoteFindMatch(location: location, occurrence: $0)
        }
    }

    private static func ranges(in text: String, term: String) -> [NSRange] {
        let source = text as NSString
        guard source.length > 0 else { return [] }
        var results: [NSRange] = []
        var searchRange = NSRange(location: 0, length: source.length)
        while searchRange.length > 0 {
            let match = source.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                range: searchRange
            )
            guard match.location != NSNotFound else { break }
            results.append(match)
            let nextLocation = NSMaxRange(match)
            guard nextLocation < source.length else { break }
            searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
        }
        return results
    }
}

enum MarkdownTableEditing {
    static func insertionEdit(in markdown: String, selection: NSRange) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }

        let needsLeadingNewline = selection.location > 0
            && source.character(at: selection.location - 1) != 10
        let needsTrailingNewline = NSMaxRange(selection) < source.length
            && source.character(at: NSMaxRange(selection)) != 10
        let leading = needsLeadingNewline ? "\n" : ""
        let trailing = needsTrailingNewline ? "\n" : ""
        let table = "| Column 1 | Column 2 |\n| --- | --- |\n|  |  |"
        let replacement = leading + table + trailing
        let firstCellOffset = (leading + "| Column 1 | Column 2 |\n| --- | --- |\n| ") as NSString
        return MarkdownListEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(location: selection.location + firstCellOffset.length, length: 0)
        )
    }
}

struct MarkdownListEdit: Equatable {
    var range: NSRange
    var replacement: String
    var selection: NSRange
}

enum MarkdownParagraphEditing {
    enum Style {
        case title
        case heading
        case subheading
        case body

        var prefix: String? {
            switch self {
            case .title: "# "
            case .heading: "## "
            case .subheading: "### "
            case .body: nil
            }
        }
    }

    static func styleEdit(
        in markdown: String,
        selection: NSRange,
        style: Style
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }

        let lineRange = source.lineRange(for: selection)
        let block = source.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }

        let headingExpression = try? NSRegularExpression(
            pattern: #"^([ \t]*)#{1,6}[ \t]+"#
        )
        let indentationExpression = try? NSRegularExpression(pattern: #"^[ \t]*"#)
        lines = lines.map { line in
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return line
            }

            let fullRange = NSRange(location: 0, length: (line as NSString).length)
            let body = headingExpression?.stringByReplacingMatches(
                in: line,
                range: fullRange,
                withTemplate: "$1"
            ) ?? line
            guard let prefix = style.prefix else { return body }

            let bodyRange = NSRange(location: 0, length: (body as NSString).length)
            let indentationRange = indentationExpression?.firstMatch(
                in: body,
                range: bodyRange
            )?.range ?? NSRange(location: 0, length: 0)
            let bodySource = body as NSString
            let indentation = bodySource.substring(with: indentationRange)
            let content = bodySource.substring(from: NSMaxRange(indentationRange))
            return indentation + prefix + content
        }

        var replacement = lines.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        return MarkdownListEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }
}

enum MarkdownInlineRendering {
    private static let underlineStart = "\u{E000}"
    private static let underlineEnd = "\u{E001}"
    private static let highlightStart = "\u{E002}"
    private static let highlightEnd = "\u{E003}"

    static func attributedText(for markdown: String) -> AttributedString {
        let prepared = markdown
            .replacingOccurrences(of: "<u>", with: underlineStart)
            .replacingOccurrences(of: "</u>", with: underlineEnd)
            .replacingOccurrences(of: "<mark>", with: highlightStart)
            .replacingOccurrences(of: "</mark>", with: highlightEnd)
        let parsed = (try? AttributedString(markdown: prepared))
            ?? AttributedString(prepared)
        let attributed = NSMutableAttributedString(
            attributedString: NSAttributedString(parsed)
        )
        applyDelimitedStyle(
            in: attributed,
            start: underlineStart,
            end: underlineEnd,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]
        )
        applyDelimitedStyle(
            in: attributed,
            start: highlightStart,
            end: highlightEnd,
            attributes: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.48)]
        )
        return AttributedString(attributed)
    }

    private static func applyDelimitedStyle(
        in attributed: NSMutableAttributedString,
        start: String,
        end: String,
        attributes: [NSAttributedString.Key: Any]
    ) {
        while true {
            let source = attributed.string as NSString
            let opening = source.range(of: start)
            guard opening.location != NSNotFound else { break }
            let trailingRange = NSRange(
                location: NSMaxRange(opening),
                length: source.length - NSMaxRange(opening)
            )
            let closing = source.range(of: end, range: trailingRange)
            guard closing.location != NSNotFound else {
                attributed.deleteCharacters(in: opening)
                continue
            }
            let contentLength = closing.location - NSMaxRange(opening)
            attributed.deleteCharacters(in: closing)
            attributed.deleteCharacters(in: opening)
            if contentLength > 0 {
                attributed.addAttributes(
                    attributes,
                    range: NSRange(location: opening.location, length: contentLength)
                )
            }
        }
        attributed.mutableString.replaceOccurrences(
            of: end,
            with: "",
            range: NSRange(location: 0, length: attributed.length)
        )
    }
}

enum MarkdownListEditing {
    enum IndentationDirection {
        case increase
        case decrease
    }

    private enum Kind {
        case bullet(marker: String)
        case ordered(indent: String, number: Int, delimiter: String)
        case checklist(indent: String)
    }

    private struct Item {
        var prefix: String
        var body: String
        var kind: Kind
    }

    static func returnEdit(in markdown: String, selection: NSRange) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }
        let lineRange = source.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let item = item(in: line) else { return nil }

        if item.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let prefixLength = (item.prefix as NSString).length
            return MarkdownListEdit(
                range: NSRange(location: lineRange.location, length: prefixLength),
                replacement: "",
                selection: NSRange(location: lineRange.location, length: 0)
            )
        }

        let continuation: String
        switch item.kind {
        case .bullet(let marker):
            continuation = marker
        case .ordered(let indent, let number, let delimiter):
            continuation = "\(indent)\(number + 1)\(delimiter) "
        case .checklist(let indent):
            continuation = "\(indent)- [ ] "
        }
        let replacement = "\n" + continuation
        return MarkdownListEdit(
            range: selection,
            replacement: replacement,
            selection: NSRange(
                location: selection.location + (replacement as NSString).length,
                length: 0
            )
        )
    }

    static func backspaceEdit(in markdown: String, deletionRange: NSRange) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard deletionRange.length == 1,
              deletionRange.location >= 0,
              NSMaxRange(deletionRange) <= source.length else { return nil }
        let caret = NSMaxRange(deletionRange)
        let lineRange = source.lineRange(for: NSRange(location: caret, length: 0))
        let line = source.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let item = item(in: line) else { return nil }
        let prefixLength = (item.prefix as NSString).length
        guard caret == lineRange.location + prefixLength else { return nil }
        return MarkdownListEdit(
            range: NSRange(location: lineRange.location, length: prefixLength),
            replacement: "",
            selection: NSRange(location: lineRange.location, length: 0)
        )
    }

    static func indentationEdit(
        in markdown: String,
        selection: NSRange,
        direction: IndentationDirection
    ) -> MarkdownListEdit? {
        let source = markdown as NSString
        guard selection.location >= 0,
              NSMaxRange(selection) <= source.length else { return nil }
        let lastSelectedCharacter = NSMaxRange(selection) - 1
        let selectionEndsWithNewline = selection.length > 0
            && source.character(at: lastSelectedCharacter) == 10
        let effectiveLength = selectionEndsWithNewline ? selection.length - 1 : selection.length
        let lineRange = source.lineRange(
            for: NSRange(location: selection.location, length: effectiveLength)
        )
        let block = source.substring(with: lineRange)
        let endsWithNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if endsWithNewline { lines.removeLast() }
        var changed = false
        lines = lines.map { line in
            guard isListItem(line) else { return line }
            switch direction {
            case .increase:
                changed = true
                return "  " + line
            case .decrease:
                if line.hasPrefix("  ") {
                    changed = true
                    return String(line.dropFirst(2))
                }
                if line.hasPrefix("\t") || line.hasPrefix(" ") {
                    changed = true
                    return String(line.dropFirst())
                }
                return line
            }
        }
        guard changed else { return nil }
        var replacement = lines.joined(separator: "\n")
        if endsWithNewline { replacement += "\n" }
        return MarkdownListEdit(
            range: lineRange,
            replacement: replacement,
            selection: NSRange(
                location: lineRange.location,
                length: (replacement as NSString).length
            )
        )
    }

    private static func item(in line: String) -> Item? {
        if let groups = groups(for: #"^([ \t]*)(- \[[ xX]\] )(.*)$"#, in: line) {
            return Item(prefix: groups[0] + groups[1], body: groups[2], kind: .checklist(indent: groups[0]))
        }
        if let groups = groups(for: #"^([ \t]*)([-*+] )(.*)$"#, in: line) {
            return Item(prefix: groups[0] + groups[1], body: groups[2], kind: .bullet(marker: groups[0] + groups[1]))
        }
        if let groups = groups(for: #"^([ \t]*)([0-9]+)([.)]) (.*)$"#, in: line),
           let number = Int(groups[1]) {
            let prefix = groups[0] + groups[1] + groups[2] + " "
            return Item(prefix: prefix, body: groups[3], kind: .ordered(indent: groups[0], number: number, delimiter: groups[2]))
        }
        return nil
    }

    private static func groups(for pattern: String, in value: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let source = value as NSString
        guard let match = expression.firstMatch(
            in: value,
            range: NSRange(location: 0, length: source.length)
        ) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
    }

    private static func isListItem(_ line: String) -> Bool {
        groups(for: #"^[ \t]*(?:[-*+] |[0-9]+[.)] )"#, in: line) != nil
    }
}

@MainActor
final class MarkdownRichTextView: UITextView {
    var checklistMarkers: [MarkdownEditorPresentation.ChecklistMarker] = [] {
        didSet { setNeedsDisplay() }
    }
    var bulletMarkers: [MarkdownEditorPresentation.BulletMarker] = [] {
        didSet { setNeedsDisplay() }
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        for marker in checklistMarkers {
            let markerRect = renderedRect(for: marker.range)
            let symbolRect = CGRect(
                x: markerRect.minX + 1,
                y: markerRect.midY - 10,
                width: 20,
                height: 20
            )
            let configuration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            let name = marker.checked ? "checkmark.circle.fill" : "circle"
            UIColor(MudsnoteColors.primary).set()
            UIImage(systemName: name, withConfiguration: configuration)?
                .withTintColor(UIColor(MudsnoteColors.primary), renderingMode: .alwaysOriginal)
                .draw(in: symbolRect)
        }
        UIColor(MudsnoteColors.text).setFill()
        for marker in bulletMarkers {
            let markerRect = renderedRect(for: marker.range)
            let diameter: CGFloat = 6
            let bulletRect = CGRect(
                x: markerRect.minX + 7,
                y: markerRect.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            UIBezierPath(ovalIn: bulletRect).fill()
        }
    }

    func checklistMarker(at point: CGPoint) -> MarkdownEditorPresentation.ChecklistMarker? {
        checklistMarkers.first { marker in
            renderedRect(for: marker.range).insetBy(dx: -8, dy: -8).contains(point)
        }
    }

    private func renderedRect(for range: NSRange) -> CGRect {
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: range,
            actualCharacterRange: nil
        )
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.left
        rect.origin.y += textContainerInset.top
        return rect
    }
}

@MainActor
enum MarkdownEditorPresentation {
    struct ChecklistMarker: Equatable {
        var range: NSRange
        var checked: Bool
    }

    struct BulletMarker: Equatable {
        var range: NSRange
    }

    static func apply(to textView: UITextView, displaysSource: Bool) {
        let storage = textView.textStorage
        let fullRange = NSRange(location: 0, length: storage.length)
        let selection = textView.selectedRange
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 3
        let bodyFont: UIFont = displaysSource
            ? .monospacedSystemFont(ofSize: 17, weight: .regular)
            : .preferredFont(forTextStyle: .body)
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: bodyFont,
            .foregroundColor: UIColor(MudsnoteColors.text),
            .paragraphStyle: paragraph,
        ]

        storage.beginEditing()
        if fullRange.length > 0 {
            storage.setAttributes(baseAttributes, range: fullRange)
        }
        guard !displaysSource, storage.length <= 512 * 1_024 else {
            (textView as? MarkdownRichTextView)?.checklistMarkers = []
            (textView as? MarkdownRichTextView)?.bulletMarkers = []
            storage.endEditing()
            textView.typingAttributes = baseAttributes
            textView.selectedRange = clamped(selection, length: storage.length)
            return
        }

        let source = storage.string as NSString
        let checklistMarkers = checklists(in: source as String)
        for marker in checklistMarkers {
            storage.addAttributes([
                .foregroundColor: UIColor.clear,
                .font: UIFont.preferredFont(forTextStyle: .body),
            ], range: marker.range)
        }
        (textView as? MarkdownRichTextView)?.checklistMarkers = checklistMarkers
        let bulletMarkers = bullets(in: source as String)
        for marker in bulletMarkers {
            storage.addAttributes([
                .foregroundColor: UIColor.clear,
                .font: UIFont.preferredFont(forTextStyle: .body),
            ], range: marker.range)
        }
        (textView as? MarkdownRichTextView)?.bulletMarkers = bulletMarkers
        applyHeadings(in: source, storage: storage)
        applyDelimited(#"\*\*([^\n]+?)\*\*"#, markerLength: 2, trait: .traitBold, in: source, storage: storage)
        applyDelimited(#"<u>([^\n]+?)</u>"#, markerLength: 3, suffixMarkerLength: 4, trait: nil, in: source, storage: storage, extra: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        applyDelimited(#"<mark>([^\n]+?)</mark>"#, markerLength: 6, suffixMarkerLength: 7, trait: nil, in: source, storage: storage, extra: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.48)])
        applyDelimited(#"~~([^\n]+?)~~"#, markerLength: 2, trait: nil, in: source, storage: storage, extra: [.strikethroughStyle: NSUnderlineStyle.single.rawValue])
        applyDelimited(#"(?<!\*)\*([^*\n]+?)\*(?!\*)"#, markerLength: 1, trait: .traitItalic, in: source, storage: storage)
        applyDelimited(#"_([^_\n]+?)_"#, markerLength: 1, trait: .traitItalic, in: source, storage: storage)
        applyCode(in: source, storage: storage)
        applyLinks(in: source, storage: storage)
        storage.endEditing()
        textView.typingAttributes = baseAttributes
        textView.selectedRange = clamped(selection, length: storage.length)
    }

    private static func applyHeadings(in source: NSString, storage: NSTextStorage) {
        matches(#"(?m)^(#{1,6})[ \t]+([^\n]*)"#, in: source).forEach { match in
            let marker = match.range(at: 1)
            let level = marker.length
            let size: CGFloat = switch level {
            case 1: 28
            case 2: 24
            case 3: 21
            default: 18
            }
            storage.addAttribute(
                .font,
                value: UIFont.systemFont(ofSize: size, weight: .bold),
                range: match.range
            )
            conceal(NSRange(location: marker.location, length: marker.length + 1), in: storage)
        }
    }

    private static func applyDelimited(
        _ pattern: String,
        markerLength: Int,
        suffixMarkerLength: Int? = nil,
        trait: UIFontDescriptor.SymbolicTraits?,
        in source: NSString,
        storage: NSTextStorage,
        extra: [NSAttributedString.Key: Any] = [:]
    ) {
        matches(pattern, in: source).forEach { match in
            let content = match.range(at: 1)
            if let trait, content.length > 0 {
                let current = storage.attribute(.font, at: content.location, effectiveRange: nil) as? UIFont
                    ?? .preferredFont(forTextStyle: .body)
                if let descriptor = current.fontDescriptor.withSymbolicTraits(
                    current.fontDescriptor.symbolicTraits.union(trait)
                ) {
                    storage.addAttribute(.font, value: UIFont(descriptor: descriptor, size: current.pointSize), range: content)
                }
            }
            if !extra.isEmpty { storage.addAttributes(extra, range: content) }
            let trailingMarkerLength = suffixMarkerLength ?? markerLength
            conceal(NSRange(location: match.range.location, length: markerLength), in: storage)
            conceal(
                NSRange(
                    location: NSMaxRange(match.range) - trailingMarkerLength,
                    length: trailingMarkerLength
                ),
                in: storage
            )
        }
    }

    private static func applyCode(in source: NSString, storage: NSTextStorage) {
        matches(#"`([^`\n]+?)`"#, in: source).forEach { match in
            let content = match.range(at: 1)
            storage.addAttributes([
                .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .regular),
                .backgroundColor: UIColor.secondarySystemFill,
            ], range: content)
            conceal(NSRange(location: match.range.location, length: 1), in: storage)
            conceal(NSRange(location: NSMaxRange(match.range) - 1, length: 1), in: storage)
        }
    }

    private static func applyLinks(in source: NSString, storage: NSTextStorage) {
        matches(#"\[([^\]\n]+)\]\(([^)\n]+)\)"#, in: source).forEach { match in
            let label = match.range(at: 1)
            storage.addAttributes([
                .foregroundColor: UIColor(MudsnoteColors.primary),
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: label)
            conceal(NSRange(location: match.range.location, length: 1), in: storage)
            conceal(NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), in: storage)
        }
    }

    private static func conceal(_ range: NSRange, in storage: NSTextStorage) {
        guard range.location >= 0, NSMaxRange(range) <= storage.length else { return }
        storage.addAttributes([
            .foregroundColor: UIColor.clear,
            .font: UIFont.systemFont(ofSize: 1),
        ], range: range)
    }

    private static func matches(_ pattern: String, in source: NSString) -> [NSTextCheckingResult] {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: source as String, range: NSRange(location: 0, length: source.length))
    }

    private static func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(max(range.location, 0), length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    static func checklists(in markdown: String) -> [ChecklistMarker] {
        let source = markdown as NSString
        return matches(#"(?m)^[ \t]*(- \[([ xX])\] )"#, in: source).map { match in
            let markerRange = match.range(at: 1)
            let stateRange = match.range(at: 2)
            let state = stateRange.location < source.length
                ? source.substring(with: stateRange).lowercased()
                : " "
            return ChecklistMarker(range: markerRange, checked: state == "x")
        }
    }

    static func bullets(in markdown: String) -> [BulletMarker] {
        let source = markdown as NSString
        return matches(#"(?m)^[ \t]*([-*+] )(?!\[[ xX]\] )"#, in: source).map { match in
            BulletMarker(range: match.range(at: 1))
        }
    }

    static func togglingChecklist(in markdown: String, marker: ChecklistMarker) -> String? {
        let source = NSMutableString(string: markdown)
        let stateLocation = marker.range.location + 3
        guard marker.range.length >= 5, stateLocation < source.length else { return nil }
        source.replaceCharacters(
            in: NSRange(location: stateLocation, length: 1),
            with: marker.checked ? " " : "x"
        )
        return source as String
    }
}

private struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var command: MarkdownEditingCommand?
    @Binding var linkDraft: MarkdownLinkDraft?
    var displaysSource: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = MarkdownRichTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(MudsnoteColors.text)
        view.tintColor = UIColor(MudsnoteColors.primary)
        view.font = .monospacedSystemFont(ofSize: 17, weight: .regular)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .yes
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.text = text
        let checklistTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleChecklistTap(_:))
        )
        checklistTap.cancelsTouchesInView = false
        view.addGestureRecognizer(checklistTap)
        MarkdownEditorPresentation.apply(to: view, displaysSource: displaysSource)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
        }
        MarkdownEditorPresentation.apply(to: view, displaysSource: displaysSource)
        if isFocused, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !isFocused, view.isFirstResponder {
            view.resignFirstResponder()
        }
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            context.coordinator.apply(command.kind, to: view)
            DispatchQueue.main.async { self.command = nil }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MarkdownTextEditor
        var lastCommandID: UUID?

        init(parent: MarkdownTextEditor) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            MarkdownEditorPresentation.apply(
                to: textView,
                displaysSource: parent.displaysSource
            )
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard !parent.displaysSource else { return true }
            let edit: MarkdownListEdit?
            if text == "\n" {
                edit = MarkdownListEditing.returnEdit(in: textView.text, selection: range)
            } else if text.isEmpty {
                edit = MarkdownListEditing.backspaceEdit(in: textView.text, deletionRange: range)
            } else {
                edit = nil
            }
            guard let edit else { return true }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
            return false
        }

        @objc func handleChecklistTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  !parent.displaysSource,
                  let view = recognizer.view as? MarkdownRichTextView,
                  let marker = view.checklistMarker(at: recognizer.location(in: view)),
                  let updated = MarkdownEditorPresentation.togglingChecklist(
                    in: view.text,
                    marker: marker
                  ) else { return }
            let selection = view.selectedRange
            view.text = updated
            view.selectedRange = selection
            parent.text = updated
            MarkdownEditorPresentation.apply(to: view, displaysSource: false)
        }

        func apply(_ kind: MarkdownEditingCommand.Kind, to textView: UITextView) {
            switch kind {
            case .title:
                applyParagraphStyle(.title, in: textView)
            case .heading:
                applyParagraphStyle(.heading, in: textView)
            case .subheading:
                applyParagraphStyle(.subheading, in: textView)
            case .body:
                applyParagraphStyle(.body, in: textView)
            case .bold:
                toggleInlineStyle(prefix: "**", suffix: "**", placeholder: "bold", in: textView)
            case .italic:
                toggleInlineStyle(prefix: "_", suffix: "_", placeholder: "italic", in: textView)
            case .underline:
                toggleInlineStyle(prefix: "<u>", suffix: "</u>", placeholder: "underline", in: textView)
            case .highlight:
                toggleInlineStyle(prefix: "<mark>", suffix: "</mark>", placeholder: "highlight", in: textView)
            case .strikethrough:
                toggleInlineStyle(prefix: "~~", suffix: "~~", placeholder: "strikethrough", in: textView)
            case .bullet:
                toggleLinePrefix("- ", in: textView)
            case .ordered:
                toggleOrderedList(in: textView)
            case .checklist:
                toggleLinePrefix("- [ ] ", in: textView)
            case .outdent:
                changeListIndentation(.decrease, in: textView)
            case .indent:
                changeListIndentation(.increase, in: textView)
            case .quote:
                toggleLinePrefix("> ", in: textView)
            case .code:
                toggleInlineStyle(prefix: "`", suffix: "`", placeholder: "code", in: textView)
            case .link:
                let draft = MarkdownLinkEditing.draft(
                    in: textView.text,
                    selection: textView.selectedRange
                )
                DispatchQueue.main.async { self.parent.linkDraft = draft }
            case .applyLink(let draft, let label, let destination):
                if let edit = MarkdownLinkEditing.insertionEdit(
                    for: draft,
                    label: label,
                    destination: destination
                ) {
                    replace(edit.range, with: edit.replacement, selecting: edit.selection, in: textView)
                }
            case .removeLink(let draft):
                if let edit = MarkdownLinkEditing.removalEdit(for: draft) {
                    replace(edit.range, with: edit.replacement, selecting: edit.selection, in: textView)
                }
            case .table:
                if let edit = MarkdownTableEditing.insertionEdit(
                    in: textView.text,
                    selection: textView.selectedRange
                ) {
                    replace(edit.range, with: edit.replacement, selecting: edit.selection, in: textView)
                }
            case .undo:
                textView.undoManager?.undo()
            case .redo:
                textView.undoManager?.redo()
            }
            parent.text = textView.text
            MarkdownEditorPresentation.apply(
                to: textView,
                displaysSource: parent.displaysSource
            )
        }

        private func toggleInlineStyle(
            prefix: String,
            suffix: String,
            placeholder: String,
            in textView: UITextView
        ) {
            guard let edit = MarkdownInlineEditing.toggleEdit(
                in: textView.text,
                selection: textView.selectedRange,
                prefix: prefix,
                suffix: suffix,
                placeholder: placeholder
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func applyParagraphStyle(
            _ style: MarkdownParagraphEditing.Style,
            in textView: UITextView
        ) {
            guard let edit = MarkdownParagraphEditing.styleEdit(
                in: textView.text,
                selection: textView.selectedRange,
                style: style
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func toggleLinePrefix(_ prefix: String, in textView: UITextView) {
            let source = textView.text as NSString
            let lineRange = source.lineRange(for: textView.selectedRange)
            let block = source.substring(with: lineRange)
            let endsWithNewline = block.hasSuffix("\n")
            var lines = block.components(separatedBy: "\n")
            if endsWithNewline { lines.removeLast() }
            let contentLines = lines.filter { !$0.isEmpty }
            let shouldRemove = !contentLines.isEmpty && contentLines.allSatisfy { $0.hasPrefix(prefix) }
            lines = lines.map { line in
                guard !line.isEmpty else { return line }
                return shouldRemove ? String(line.dropFirst(prefix.count)) : prefix + line
            }
            var replacement = lines.joined(separator: "\n")
            if endsWithNewline { replacement += "\n" }
            replace(
                lineRange,
                with: replacement,
                selecting: NSRange(location: lineRange.location, length: (replacement as NSString).length),
                in: textView
            )
        }

        private func toggleOrderedList(in textView: UITextView) {
            let source = textView.text as NSString
            let lineRange = source.lineRange(for: textView.selectedRange)
            let block = source.substring(with: lineRange)
            let endsWithNewline = block.hasSuffix("\n")
            var lines = block.components(separatedBy: "\n")
            if endsWithNewline { lines.removeLast() }
            let expression = try? NSRegularExpression(pattern: #"^([ \t]*)[0-9]+[.)] "#)
            let contentLines = lines.filter { !$0.isEmpty }
            let shouldRemove = !contentLines.isEmpty && contentLines.allSatisfy { line in
                let value = line as NSString
                return expression?.firstMatch(
                    in: line,
                    range: NSRange(location: 0, length: value.length)
                ) != nil
            }
            var nextNumber = 1
            lines = lines.map { line in
                guard !line.isEmpty else { return line }
                let value = line as NSString
                if shouldRemove,
                   let match = expression?.firstMatch(
                    in: line,
                    range: NSRange(location: 0, length: value.length)
                   ) {
                    let prefix = value.substring(with: match.range)
                    let indentation = prefix.prefix { $0 == " " || $0 == "\t" }
                    return String(indentation) + value.substring(from: NSMaxRange(match.range))
                }
                let indentation = line.prefix { $0 == " " || $0 == "\t" }
                let body = line.dropFirst(indentation.count)
                defer { nextNumber += 1 }
                return "\(indentation)\(nextNumber). \(body)"
            }
            var replacement = lines.joined(separator: "\n")
            if endsWithNewline { replacement += "\n" }
            replace(
                lineRange,
                with: replacement,
                selecting: NSRange(location: lineRange.location, length: (replacement as NSString).length),
                in: textView
            )
        }

        private func changeListIndentation(
            _ direction: MarkdownListEditing.IndentationDirection,
            in textView: UITextView
        ) {
            guard let edit = MarkdownListEditing.indentationEdit(
                in: textView.text,
                selection: textView.selectedRange,
                direction: direction
            ) else { return }
            replace(
                edit.range,
                with: edit.replacement,
                selecting: edit.selection,
                in: textView
            )
        }

        private func replace(
            _ range: NSRange,
            with replacement: String,
            selecting selection: NSRange,
            in textView: UITextView
        ) {
            guard let textRange = textView.textRange(from: range) else { return }
            textView.replace(textRange, withText: replacement)
            textView.selectedRange = selection
            textViewDidChange(textView)
        }
    }
}

private extension UITextView {
    func textRange(from range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length) else { return nil }
        return textRange(from: start, to: end)
    }
}

private struct AudioAttachmentPlayer: View {
    var url: URL
    var title: String
    @StateObject private var playback = AudioPlaybackController()

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(MudsnoteColors.primary, in: Circle())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text("Audio")
                    .font(.headline)
                    .foregroundStyle(MudsnoteColors.text)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 16))
        .onDisappear {
            playback.stop()
        }
    }

    private func togglePlayback() {
        playback.toggle(url: url)
    }
}

@MainActor
private final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        do {
            if player == nil {
                let player = try AVAudioPlayer(contentsOf: url)
                player.delegate = self
                self.player = player
            }
            guard let player else { return }
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                isPlaying = player.play()
            }
        } catch {
            stop()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.isPlaying = false
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }
}

struct MarkdownAttachmentLine {
    enum Kind: Equatable {
        case image
        case audio
        case file
    }

    var path: String
    var rawLine: String
    var systemImage: String
    var kind: Kind

    init?(_ line: String) {
        rawLine = line
        if line.hasPrefix("![[") {
            path = line
                .replacingOccurrences(of: "![[", with: "")
                .replacingOccurrences(of: "]]", with: "")
            systemImage = "paperclip"
            kind = .file
            return
        }

        if let match = Self.match(line, pattern: #"^!\[[^\]]*\]\(([^)]+)\)$"#) {
            path = match
            systemImage = "photo"
            kind = .image
            return
        }

        if let match = Self.match(line, pattern: #"^\[[^\]]+\]\(([^)]+)\)$"#) {
            path = match
            if LibraryAttachment.Kind(fileExtension: (match as NSString).pathExtension) == .audio {
                systemImage = "waveform"
                kind = .audio
            } else {
                systemImage = "doc"
                kind = .file
            }
            return
        }

        return nil
    }

    private static func match(_ value: String, pattern: String) -> String? {
        guard let range = value.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let matched = String(value[range])
        guard let open = matched.lastIndex(of: "("), let close = matched.lastIndex(of: ")"), open < close else {
            return nil
        }
        return String(matched[matched.index(after: open)..<close])
    }
}

@MainActor
enum MarkdownDrawingExport {
    static let padding: CGFloat = 24
    static let maximumPixelDimension: CGFloat = 4_096

    static func pngData(for drawing: PKDrawing, screenScale: CGFloat = 3) throws -> Data {
        guard drawing.strokes.isEmpty == false else { throw CaptureAttachmentError.empty }
        let bounds = drawing.bounds
            .insetBy(dx: -padding, dy: -padding)
            .integral
        guard bounds.width > 0, bounds.height > 0 else { throw CaptureAttachmentError.empty }

        let largestDimension = max(bounds.width, bounds.height)
        let scale = max(0.1, min(screenScale, maximumPixelDimension / largestDimension))
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = scale
        var renderedDrawing: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            renderedDrawing = drawing.image(from: bounds, scale: scale)
        }
        guard let renderedDrawing else { throw CaptureAttachmentError.empty }
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: bounds.size))
            renderedDrawing.draw(in: CGRect(origin: .zero, size: bounds.size))
        }
        guard let data = image.pngData() else { throw CaptureAttachmentError.empty }
        return data
    }
}

@MainActor
private final class MarkdownDrawingController: NSObject, ObservableObject, PKCanvasViewDelegate {
    let canvasView = PKCanvasView()
    private let toolPicker = PKToolPicker()
    @Published private(set) var drawing = PKDrawing()
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var isConfigured = false

    func configureIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true
        canvasView.delegate = self
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = PKInkingTool(.pen, color: .black, width: 5)
        canvasView.backgroundColor = .white
        canvasView.isOpaque = true
        canvasView.overrideUserInterfaceStyle = .light
        canvasView.alwaysBounceVertical = false
        canvasView.alwaysBounceHorizontal = false
        canvasView.accessibilityIdentifier = "markdown-drawing-canvas"
        toolPicker.addObserver(canvasView)
        toolPicker.setVisible(true, forFirstResponder: canvasView)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            canvasView.becomeFirstResponder()
            canvasView.tool = PKInkingTool(.pen, color: .black, width: 5)
        }
    }

    func undo() {
        canvasView.undoManager?.undo()
        publishDrawingState()
    }

    func redo() {
        canvasView.undoManager?.redo()
        publishDrawingState()
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        publishDrawingState()
    }

    private func publishDrawingState() {
        drawing = canvasView.drawing
        canUndo = canvasView.undoManager?.canUndo == true
        canRedo = canvasView.undoManager?.canRedo == true
    }
}

private struct MarkdownDrawingCanvas: UIViewRepresentable {
    @ObservedObject var controller: MarkdownDrawingController

    func makeUIView(context: Context) -> PKCanvasView {
        controller.configureIfNeeded()
        return controller.canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        controller.configureIfNeeded()
    }
}

private struct MarkdownDrawingEditor: View {
    @StateObject private var controller = MarkdownDrawingController()
    @State private var isConfirmingDiscard = false
    @State private var exportErrorMessage: String?
    var onCancel: () -> Void
    var onSave: (Data) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                MarkdownDrawingCanvas(controller: controller)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.black.opacity(0.08), lineWidth: 1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                if controller.drawing.strokes.isEmpty {
                    Text("Draw with your finger")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .navigationTitle("Drawing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        if controller.drawing.strokes.isEmpty {
                            onCancel()
                        } else {
                            isConfirmingDiscard = true
                        }
                    }
                    .accessibilityIdentifier("cancel-markdown-drawing")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        controller.undo()
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!controller.canUndo)
                    .accessibilityLabel("Undo Drawing")
                    .accessibilityIdentifier("undo-markdown-drawing")

                    Button {
                        controller.redo()
                    } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!controller.canRedo)
                    .accessibilityLabel("Redo Drawing")
                    .accessibilityIdentifier("redo-markdown-drawing")

                    Button("Add") {
                        saveDrawing()
                    }
                    .fontWeight(.semibold)
                    .disabled(controller.drawing.strokes.isEmpty)
                    .accessibilityIdentifier("save-markdown-drawing")
                }
            }
            .confirmationDialog(
                "Discard Drawing?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Drawing", role: .destructive, action: onCancel)
                Button("Keep Drawing", role: .cancel) {}
            }
            .alert("Couldn’t Add Drawing", isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { exportErrorMessage = nil }
            } message: {
                Text(exportErrorMessage ?? "Try saving the drawing again.")
            }
        }
    }

    private func saveDrawing() {
        do {
            onSave(try MarkdownDrawingExport.pngData(for: controller.drawing))
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}
