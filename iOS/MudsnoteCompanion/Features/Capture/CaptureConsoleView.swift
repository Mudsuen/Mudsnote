import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

struct QuickCaptureLaunchPlan: Equatable {
    var focusesEditor: Bool
    var presentsPhotoPicker: Bool
    var startsAudioRecording: Bool

    static func make(for route: CaptureRoute) -> QuickCaptureLaunchPlan {
        switch route {
        case .text:
            QuickCaptureLaunchPlan(
                focusesEditor: true,
                presentsPhotoPicker: false,
                startsAudioRecording: false
            )
        case .image:
            QuickCaptureLaunchPlan(
                focusesEditor: false,
                presentsPhotoPicker: true,
                startsAudioRecording: false
            )
        case .audio:
            QuickCaptureLaunchPlan(
                focusesEditor: false,
                presentsPhotoPicker: false,
                startsAudioRecording: true
            )
        }
    }
}

struct CaptureConsoleView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isBodyFocused = false
    @State private var selectedRoute: CaptureRoute
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false
    @State private var isScannerPresented = false
    @State private var refocusAfterCamera = false
    @State private var refocusAfterScanner = false
    @State private var didStartInitialAudioRoute = false
    @State private var attachmentPreview: PreparedAttachmentPreview?
    @State private var isContextPresented = false
    @State private var editingCommand: MarkdownEditingCommand?
    @State private var tagDraft: MarkdownInlineTagDraft?
    @State private var noteMentionDraft: MarkdownNoteMentionDraft?

    init(initialRoute: CaptureRoute) {
        _selectedRoute = State(initialValue: initialRoute)
    }

    var body: some View {
        VStack(spacing: 12) {
            editor

            audioStatus

            if !appModel.draft.attachments.isEmpty {
                attachmentStrip
            }

            if let issue = appModel.captureSubmissionIssue {
                submissionRecovery(issue)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            commandBar
        }
        .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(MudsnoteColors.panel)
        .animation(.snappy(duration: 0.24), value: appModel.captureSubmissionIssue != nil)
        .onAppear {
            migrateCaptureInlineTags()
            activateInitialRoute(selectedRoute)
        }
        .onChange(of: appModel.captureRoute) { _, route in
            selectedRoute = route
            activateInitialRoute(route)
        }
        .onChange(of: selectedPhotoItem) { _, item in
            selectedRoute = .image
            appModel.attachPhoto(item)
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .any(of: [.images, .videos])
        )
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    _ = await appModel.attachFile(url)
                    isBodyFocused = appModel.captureAttachmentIssue == nil
                }
            case .failure(let error):
                if (error as? CocoaError)?.code == .userCancelled {
                    isBodyFocused = true
                } else {
                    appModel.reportCaptureAttachmentFailure(error.localizedDescription)
                }
            }
        }
        .fullScreenCover(
            isPresented: $isCameraPresented,
            onDismiss: refocusCaptureAfterCameraIfNeeded
        ) {
            CameraPhotoCaptureView(
                onComplete: { result in
                    switch result {
                    case .success(let media):
                        selectedRoute = .image
                        appModel.attachCameraPhoto(media)
                        refocusAfterCamera = appModel.captureAttachmentIssue == nil
                    case .failure(let error):
                        appModel.reportCaptureAttachmentFailure(error.localizedDescription)
                    }
                    isCameraPresented = false
                },
                onCancel: {
                    refocusAfterCamera = true
                    isCameraPresented = false
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(
            isPresented: $isScannerPresented,
            onDismiss: refocusCaptureAfterScannerIfNeeded
        ) {
            DocumentScannerView(
                onComplete: { result in
                    switch result {
                    case .success(let pages):
                        Task {
                            _ = await appModel.attachScannedDocument(pages)
                            refocusAfterScanner = appModel.captureAttachmentIssue == nil
                            isScannerPresented = false
                        }
                    case .failure(let error):
                        appModel.reportCaptureAttachmentFailure(error.localizedDescription)
                        isScannerPresented = false
                    }
                },
                onCancel: {
                    refocusAfterScanner = true
                    isScannerPresented = false
                }
            )
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $attachmentPreview) { preview in
            AttachmentQuickLookPreview(
                preview: preview,
                onDismiss: {
                    attachmentPreview = nil
                    isBodyFocused = true
                },
                onSave: { _ in }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $isContextPresented) {
            CaptureContextSheet(
                capturedAt: appModel.draft.createdAt,
                location: Binding(
                    get: { appModel.draft.locationStamp },
                    set: { appModel.draft.locationStamp = $0 }
                ),
                weather: Binding(
                    get: { appModel.draft.weatherStamp },
                    set: { appModel.draft.weatherStamp = $0 }
                )
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .alert("Couldn’t Add Attachment", isPresented: Binding(
            get: { appModel.captureAttachmentIssue != nil },
            set: { if !$0 { appModel.dismissCaptureAttachmentIssue() } }
        )) {
            Button("OK", role: .cancel) {
                appModel.dismissCaptureAttachmentIssue()
                isBodyFocused = true
            }
        } message: {
            Text(appModel.captureAttachmentIssue ?? "Try adding the attachment again.")
        }
        .onChange(of: appModel.captureSubmissionIssue) { _, issue in
            if issue != nil { isBodyFocused = true }
        }
        .onDisappear {
            appModel.endCaptureSession()
        }
    }

    @ViewBuilder
    private var audioStatus: some View {
        switch appModel.audioCapturePhase {
        case .idle:
            EmptyView()
        case .requestingPermission:
            audioStatusRow(
                systemImage: "mic.badge.plus",
                title: String(localized: "Preparing microphone…"),
                showsProgress: true
            )
        case .recording:
            audioStatusRow(
                systemImage: "record.circle.fill",
                title: String(localized: "Recording"),
                tint: .red,
                actionTitle: String(localized: "Cancel"),
                action: appModel.cancelAudioRecording
            )
        case .stopping:
            audioStatusRow(
                systemImage: "waveform",
                title: String(localized: "Saving audio…"),
                showsProgress: true
            )
        case .transcribing:
            audioStatusRow(
                systemImage: "waveform.badge.magnifyingglass",
                title: String(localized: "Audio saved · Transcribing…"),
                actionTitle: String(localized: "Skip"),
                action: appModel.skipAudioTranscription
            )
        case .failed(let message):
            audioStatusRow(
                systemImage: "exclamationmark.circle.fill",
                title: message,
                tint: .red
            )
        }
    }

    private func audioStatusRow(
        systemImage: String,
        title: String,
        tint: Color = MudsnoteColors.primary,
        showsProgress: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 9) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }

            Text(verbatim: title)
                .font(.footnote.weight(.medium))
                .foregroundStyle(MudsnoteColors.text)
                .lineLimit(2)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.clear, in: Capsule())
        .overlay {
            Capsule().stroke(MudsnoteColors.line, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture-audio-status")
    }

    private var commandBar: some View {
        HStack(spacing: 3) {
            Menu {
                Button {
                    selectedRoute = .image
                    isPhotoPickerPresented = true
                } label: {
                    Label("Choose Photo or Video", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityIdentifier("capture-add-image")

                Button {
                    isBodyFocused = false
                    isCameraPresented = true
                } label: {
                    Label("Take Photo or Video", systemImage: "camera")
                }
                .disabled(!CameraPhotoCapture.isAvailable)
                .accessibilityIdentifier("capture-take-photo")

                Button {
                    isBodyFocused = false
                    isFileImporterPresented = true
                } label: {
                    Label("Add File", systemImage: "doc")
                }
                .accessibilityIdentifier("capture-add-file")

                Button {
                    isBodyFocused = false
                    isScannerPresented = true
                } label: {
                    Label("Scan Document", systemImage: "doc.viewfinder")
                }
                .disabled(!VNDocumentCameraViewController.isSupported)
                .accessibilityIdentifier("capture-scan-document")

                Button {
                    isBodyFocused = true
                    DispatchQueue.main.async {
                        _ = CameraTextCapture.start()
                    }
                } label: {
                    Label("Scan Text", systemImage: "text.viewfinder")
                }
                .disabled(!CameraTextCapture.isAvailable)
                .accessibilityIdentifier("capture-scan-text")

                Divider()
                Button {
                    isBodyFocused = false
                    isContextPresented = true
                } label: {
                    Label("Note Context", systemImage: "mappin.and.ellipse")
                }
                .accessibilityIdentifier("capture-note-context")
            } label: {
                Image(systemName: appModel.isPreparingAttachment ? "hourglass" : "paperclip")
            }
            .buttonStyle(CompactCaptureButtonStyle(isActive: selectedRoute == .image))
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Add Attachment")
            .accessibilityIdentifier("capture-attachment-menu")

            Button("#") {
                editingCommand = MarkdownEditingCommand(kind: .insertText("#"))
            }
                .buttonStyle(CompactCaptureButtonStyle())
                .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
                .accessibilityLabel("Tag")
                .accessibilityIdentifier("capture-insert-tag")

            Button("@") {
                editingCommand = MarkdownEditingCommand(kind: .insertText("@"))
            }
            .buttonStyle(CompactCaptureButtonStyle())
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Link to note")
            .accessibilityIdentifier("capture-insert-mention")

            Button {
                editingCommand = MarkdownEditingCommand(kind: .insertText("\n- [ ] "))
            } label: {
                Image(systemName: "checklist")
            }
            .buttonStyle(CompactCaptureButtonStyle())
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Checklist")
            .accessibilityIdentifier("capture-insert-checklist")

            TargetMenuView()
                .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)

            Spacer(minLength: 0)

            Button {
                selectedRoute = .audio
                appModel.toggleAudioRecording()
            } label: {
                Image(systemName: appModel.isAudioTransitioning ? "hourglass" : (appModel.audioRecorder.isRecording ? "stop.fill" : "waveform"))
            }
            .buttonStyle(
                CompactCaptureButtonStyle(
                    isActive: appModel.audioRecorder.isRecording,
                    fillsActiveBackground: false
                )
            )
            .disabled(
                appModel.isSendingDraft
                    || appModel.isPreparingAttachment
                    || appModel.isAudioTransitioning
                    || appModel.isTranscribingAudio
            )
            .accessibilityLabel(
                Text(LocalizedStringKey(appModel.audioRecorder.isRecording ? "Stop recording" : "Record audio"))
            )
            .accessibilityValue(Text(verbatim: audioAccessibilityValue))
            .accessibilityIdentifier("capture-record-audio")

            Button {
                isBodyFocused = false
                migrateCaptureInlineTags()
                appModel.sendDraft(continueCapturing: false)
                selectedRoute = .text
                selectedPhotoItem = nil
            } label: {
                Image(systemName: appModel.isSendingDraft ? "hourglass" : "arrow.up")
            }
            .buttonStyle(CaptureSaveButtonStyle(isActive: appModel.draft.canSend))
            .disabled(
                !appModel.draft.canSend
                    || appModel.isSendingDraft
                    || appModel.isPreparingAttachment
                    || appModel.audioRecorder.isRecording
                    || appModel.isAudioTransitioning
            )
            .accessibilityLabel("Save memo")
            .accessibilityIdentifier("save-memo-button")
        }
        .frame(minHeight: 44)
    }

    private func submissionRecovery(_ issue: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 3) {
                Text("Couldn’t Save Quick Note")
                    .font(.subheadline.weight(.semibold))
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            Button("Try Again") {
                isBodyFocused = false
                appModel.retryCaptureSubmission()
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(appModel.isSendingDraft)
            .accessibilityIdentifier("retry-capture-save")
        }
        .foregroundStyle(MudsnoteColors.text)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.red.opacity(0.45), lineWidth: 1)
        }
    }

    private func refocusCaptureAfterCameraIfNeeded() {
        guard refocusAfterCamera else { return }
        refocusAfterCamera = false
        isBodyFocused = true
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !captureTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Label("Tags", systemImage: "number")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MudsnoteColors.muted)
                        ForEach(captureTags, id: \.self) { tag in
                            Button {
                                removeCaptureTag(tag)
                            } label: {
                                HStack(spacing: 5) {
                                    Text(tag)
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
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
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(tag)")
                        }
                    }
                }
                .frame(height: 34)
                .accessibilityIdentifier("capture-tag-bar")
            }

            ZStack(alignment: .topLeading) {
                CaptureTextEditor(
                    text: $appModel.draft.body,
                    isFocused: $isBodyFocused,
                    command: $editingCommand,
                    tagDraft: $tagDraft,
                    noteMentionDraft: $noteMentionDraft,
                    onCommitTag: addCaptureTag
                )
                .disabled(appModel.isSendingDraft)
                .accessibilityIdentifier("capture-body-editor")

                if appModel.draft.body.isEmpty {
                    HStack(spacing: 9) {
                        Rectangle()
                            .fill(MudsnoteColors.primary)
                            .frame(width: 3, height: 28)
                        Text(LocalizedStringKey(
                            appModel.isTranscribingAudio
                                ? "Transcribing..."
                                : selectedRoute == .audio
                                ? "Transcription appears here..."
                                : "What's on your mind?"
                        ))
                            .font(.body)
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                    .padding(.top, 10)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
                }

                VStack {
                    Spacer()
                    if let tagDraft,
                       !captureTagSuggestions(for: tagDraft.query).isEmpty {
                        MarkdownTagSuggestions(
                            tags: Array(captureTagSuggestions(for: tagDraft.query).prefix(5)),
                            knownTags: Set(
                                appModel.tagSummaries.map(\.name).map(MarkdownTagSyntax.key)
                            ),
                            select: acceptCaptureTag
                        )
                    } else if let noteMentionDraft,
                              !captureMentionSuggestions(for: noteMentionDraft.query).isEmpty {
                        MarkdownNoteMentionSuggestions(
                            notes: Array(
                                captureMentionSuggestions(for: noteMentionDraft.query).prefix(5)
                            ),
                            select: acceptCaptureMention
                        )
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .frame(minHeight: 156)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(appModel.draft.attachments.enumerated()), id: \.offset) { index, attachment in
                    HStack(spacing: 6) {
                        Button {
                            Task {
                                attachmentPreview = await appModel.prepareAttachmentPreview(
                                    for: attachment,
                                    index: index
                                )
                            }
                        } label: {
                            Label(
                                attachmentLabel(attachment),
                                systemImage: attachmentIcon(attachment)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview attachment")
                        .accessibilityIdentifier("preview-capture-attachment-\(index)")
                        Button {
                            appModel.draft.attachments.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .accessibilityLabel("Remove attachment")
                        .disabled(appModel.isSendingDraft)
                    }
                    .font(.caption)
                    .foregroundStyle(MudsnoteColors.text)
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .frame(height: 44)
                    .background(MudsnoteColors.card, in: Capsule())
                    .overlay { Capsule().stroke(MudsnoteColors.line, lineWidth: 1) }
                }
            }
        }
    }

    private func attachmentLabel(_ attachment: CaptureAttachment) -> String {
        switch attachment {
        case .image:
            return String(localized: "Image")
        case .video:
            return String(localized: "Video")
        case .audio:
            return String(localized: "Audio")
        case .file(_, _, let preferredBaseName):
            return preferredBaseName
        }
    }

    private func attachmentIcon(_ attachment: CaptureAttachment) -> String {
        switch attachment {
        case .image:
            return "photo"
        case .video:
            return "video"
        case .audio:
            return "waveform"
        case .file:
            return "doc"
        }
    }

    private var captureTags: [String] {
        var seen = Set<String>()
        return appModel.draft.tags
            .split(whereSeparator: \.isWhitespace)
            .compactMap { MarkdownTagSyntax.normalizedTag(String($0)) }
            .filter { seen.insert(MarkdownTagSyntax.key($0)).inserted }
    }

    private func captureTagSuggestions(for query: String) -> [String] {
        MarkdownTagSyntax.rankedInlineSuggestions(
            query: query,
            knownTags: appModel.tagSummaries.map(\.name)
                + appModel.libraryFiles.flatMap(\.tags),
            activeTags: captureTags
        )
    }

    private func captureMentionSuggestions(for query: String) -> [RecentMarkdownFile] {
        NoteMentionRanker.rank(appModel.libraryFiles, query: query)
    }

    private func addCaptureTag(_ input: String) {
        guard let tag = MarkdownTagSyntax.normalizedTag(input),
              !captureTags.contains(where: {
                  MarkdownTagSyntax.key($0) == MarkdownTagSyntax.key(tag)
              })
        else { return }
        appModel.draft.tags = (captureTags + [tag]).joined(separator: " ")
    }

    private func migrateCaptureInlineTags() {
        let migration = MarkdownTagSyntax.extractingInlineTags(
            from: appModel.draft.body
        )
        guard migration.occurrenceCount > 0 else { return }
        appModel.draft.body = migration.body
        var seen = Set<String>()
        appModel.draft.tags = (captureTags + migration.tags)
            .filter { seen.insert(MarkdownTagSyntax.key($0)).inserted }
            .joined(separator: " ")
    }

    private func removeCaptureTag(_ tag: String) {
        appModel.draft.tags = captureTags.filter {
            MarkdownTagSyntax.key($0) != MarkdownTagSyntax.key(tag)
        }
        .joined(separator: " ")
    }

    private func acceptCaptureTag(_ tag: String) {
        guard let tagDraft else { return }
        self.tagDraft = nil
        editingCommand = MarkdownEditingCommand(
            kind: .applyTag(range: tagDraft.replacementRange, tag: tag)
        )
        isBodyFocused = true
    }

    private func acceptCaptureMention(_ note: RecentMarkdownFile) {
        guard let noteMentionDraft else { return }
        let sourcePath = appModel.draft.target.relativeFolderPath.map {
            "\($0)/Untitled.md"
        } ?? "Untitled.md"
        guard let destination = MarkdownNoteLink.relativeDestination(
            from: sourcePath,
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
        isBodyFocused = true
    }

    private func refocusCaptureAfterScannerIfNeeded() {
        guard refocusAfterScanner else { return }
        refocusAfterScanner = false
        Task { @MainActor in
            await Task.yield()
            isBodyFocused = true
        }
    }

    private var audioAccessibilityValue: String {
        switch appModel.audioCapturePhase {
        case .idle:
            String(localized: "Not recording")
        case .requestingPermission:
            String(localized: "Preparing microphone…")
        case .recording:
            String(localized: "Recording")
        case .stopping:
            String(localized: "Saving audio…")
        case .transcribing:
            String(localized: "Audio saved · Transcribing…")
        case .failed(let message):
            message
        }
    }

    private func activateInitialRoute(_ route: CaptureRoute) {
        let plan = QuickCaptureLaunchPlan.make(for: route)
        isBodyFocused = plan.focusesEditor

        if plan.presentsPhotoPicker {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard selectedRoute == route else { return }
                isPhotoPickerPresented = true
            }
        }

        if plan.startsAudioRecording {
            guard !didStartInitialAudioRoute else { return }
            didStartInitialAudioRoute = true
            appModel.startAudioRecording()
        }
    }
}

private struct CaptureTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var command: MarkdownEditingCommand?
    @Binding var tagDraft: MarkdownInlineTagDraft?
    @Binding var noteMentionDraft: MarkdownNoteMentionDraft?
    var onCommitTag: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(MudsnoteColors.text)
        view.tintColor = UIColor(MudsnoteColors.primary)
        view.font = .preferredFont(forTextStyle: .body)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 2, bottom: 8, right: 2)
        view.textContainer.lineFragmentPadding = 0
        view.keyboardDismissMode = .interactive
        view.autocorrectionType = .yes
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.text = text
        view.accessibilityIdentifier = "capture-body-editor"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.markedTextRange == nil, view.text != text {
            let selection = view.selectedRange
            view.text = text
            view.selectedRange = NSRange(
                location: min(selection.location, (text as NSString).length),
                length: 0
            )
        }
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
        var parent: CaptureTextEditor
        var lastCommandID: UUID?

        init(parent: CaptureTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
            parent.tagDraft = nil
            parent.noteMentionDraft = nil
        }

        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            publish(textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            updateDrafts(in: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            if (replacement == " " || replacement == "\n" || replacement == "\t"),
               let draft = MarkdownTagSyntax.inlineDraft(
                   in: textView.text,
                   selection: range
               ),
               let tag = MarkdownTagSyntax.normalizedTag(draft.query) {
                replace(
                    draft.replacementRange,
                    with: replacement == "\n" ? "\n" : "",
                    in: textView
                )
                parent.tagDraft = nil
                parent.onCommitTag(tag)
                return false
            }
            return true
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard range.length > 0 else {
                return UIMenu(children: suggestedActions)
            }
            let bold = UIAction(
                title: String(localized: "Bold"),
                image: UIImage(systemName: "bold")
            ) { [weak self, weak textView] _ in
                guard let self, let textView else { return }
                self.apply(.bold, to: textView)
            }
            return UIMenu(
                children: suggestedActions + [
                    UIMenu(options: .displayInline, children: [bold])
                ]
            )
        }

        func apply(_ command: MarkdownEditingCommand.Kind, to textView: UITextView) {
            switch command {
            case .insertText(let text):
                replace(
                    textView.selectedRange,
                    with: triggerAwareInsertion(text, in: textView),
                    in: textView
                )
            case .applyTag(let range, let tag):
                replace(range, with: "", in: textView)
                parent.tagDraft = nil
                parent.onCommitTag(tag)
            case .applyNoteMention(let range, let label, let destination):
                replace(range, with: "[\(label)](\(destination))", in: textView)
                parent.noteMentionDraft = nil
            case .bold:
                guard let edit = MarkdownInlineEditing.toggleEdit(
                    in: textView.text,
                    selection: textView.selectedRange,
                    prefix: "**",
                    suffix: "**",
                    placeholder: "bold"
                ) else { return }
                replace(edit.range, with: edit.replacement, selection: edit.selection, in: textView)
            default:
                return
            }
        }

        private func triggerAwareInsertion(
            _ text: String,
            in textView: UITextView
        ) -> String {
            guard text == "#" || text == "@",
                  textView.selectedRange.length == 0,
                  textView.selectedRange.location > 0
            else { return text }
            let source = textView.text as NSString
            let previous = source.substring(
                with: NSRange(location: textView.selectedRange.location - 1, length: 1)
            )
            return previous.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
                ? " \(text)"
                : text
        }

        private func replace(
            _ range: NSRange,
            with replacement: String,
            selection: NSRange? = nil,
            in textView: UITextView
        ) {
            guard range.location >= 0,
                  NSMaxRange(range) <= (textView.text as NSString).length
            else { return }
            let updated = NSMutableString(string: textView.text)
            updated.replaceCharacters(in: range, with: replacement)
            textView.text = updated as String
            textView.selectedRange = selection ?? NSRange(
                location: range.location + replacement.utf16.count,
                length: 0
            )
            publish(textView)
        }

        private func publish(_ textView: UITextView) {
            parent.text = textView.text
            updateDrafts(in: textView)
        }

        private func updateDrafts(in textView: UITextView) {
            parent.tagDraft = MarkdownTagSyntax.inlineDraft(
                in: textView.text,
                selection: textView.selectedRange
            )
            parent.noteMentionDraft = noteMentionDraft(in: textView)
        }

        private func noteMentionDraft(in textView: UITextView) -> MarkdownNoteMentionDraft? {
            let selection = textView.selectedRange
            guard selection.length == 0 else { return nil }
            let source = textView.text as NSString
            let caret = min(selection.location, source.length)
            let paragraphRange = source.paragraphRange(
                for: NSRange(location: caret, length: 0)
            )
            let prefixRange = NSRange(
                location: paragraphRange.location,
                length: max(caret - paragraphRange.location, 0)
            )
            let prefix = source.substring(with: prefixRange)
            guard let match = prefix.range(
                of: #"(^|\s)@([^@\n]*)$"#,
                options: .regularExpression
            ) else { return nil }
            let matched = String(prefix[match])
            guard let markerIndex = matched.firstIndex(of: "@") else { return nil }
            let token = String(matched[markerIndex...])
            let matchRange = NSRange(match, in: prefix)
            return MarkdownNoteMentionDraft(
                query: String(token.dropFirst()),
                replacementRange: NSRange(
                    location: prefixRange.location
                        + matchRange.location
                        + matched[..<markerIndex].utf16.count,
                    length: token.utf16.count
                )
            )
        }
    }
}

private struct CaptureContextSheet: View {
    @Environment(\.dismiss) private var dismiss
    var capturedAt: Date
    @Binding var location: String
    @Binding var weather: String

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Captured") {
                        Text(capturedAt, format: .dateTime.year().month().day().hour().minute())
                            .foregroundStyle(MudsnoteColors.muted)
                    }
                    TextField("Location or address", text: $location)
                        .textContentType(.fullStreetAddress)
                        .accessibilityIdentifier("capture-context-location")
                    TextField("Weather", text: $weather)
                        .accessibilityIdentifier("capture-context-weather")
                } footer: {
                    Text("Context is saved as metadata and stays hidden in the reading card by default.")
                }
            }
            .navigationTitle("Note Context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
