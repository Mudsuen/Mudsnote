import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

struct CaptureConsoleView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isBodyFocused: Bool
    @State private var selectedRoute: CaptureRoute
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false
    @State private var isCameraPresented = false
    @State private var isFileImporterPresented = false
    @State private var isScannerPresented = false
    @State private var refocusAfterCamera = false
    @State private var refocusAfterScanner = false
    @State private var didStartInitialAudioRoute = false

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
        .background(MudsnoteColors.card, in: Capsule())
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
            } label: {
                Image(systemName: appModel.isPreparingAttachment ? "hourglass" : "paperclip")
            }
            .buttonStyle(CompactCaptureButtonStyle(isActive: selectedRoute == .image))
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Add Attachment")
            .accessibilityIdentifier("capture-attachment-menu")

            Button {
                selectedRoute = .audio
                appModel.toggleAudioRecording()
            } label: {
                Image(systemName: appModel.isAudioTransitioning ? "hourglass" : (appModel.audioRecorder.isRecording ? "stop.fill" : "waveform"))
            }
            .buttonStyle(CompactCaptureButtonStyle(isActive: appModel.audioRecorder.isRecording || selectedRoute == .audio))
            .disabled(
                appModel.isSendingDraft
                    || appModel.isPreparingAttachment
                    || appModel.isAudioTransitioning
                    || appModel.isTranscribingAudio
            )
            .accessibilityLabel(
                Text(LocalizedStringKey(appModel.audioRecorder.isRecording ? "Stop recording" : "Record audio"))
            )
            .accessibilityIdentifier("capture-record-audio")

            Button("#") { appendToken(" #tag") }
                .buttonStyle(CompactCaptureButtonStyle())
                .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
                .accessibilityLabel("Tag")
                .accessibilityIdentifier("capture-insert-tag")

            Button {
                appendToken("**bold**")
            } label: {
                Image(systemName: "bold")
            }
            .buttonStyle(CompactCaptureButtonStyle())
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Bold")
            .accessibilityIdentifier("capture-insert-bold")

            Button {
                appendToken("\n- [ ] ")
            } label: {
                Image(systemName: "checklist")
            }
            .buttonStyle(CompactCaptureButtonStyle())
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Checklist")
            .accessibilityIdentifier("capture-insert-checklist")

            Menu {
                Button("List") { appendToken("\n- ") }
                Button("Quote") { appendToken("\n> ") }
                Button("Code") { appendToken(" `code`") }
            } label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(CompactCaptureButtonStyle())
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("More Formatting")
            .accessibilityIdentifier("capture-more-formatting")

            TargetMenuView()
                .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)

            Spacer(minLength: 0)

            Button {
                isBodyFocused = false
                appModel.sendDraft(continueCapturing: false)
                selectedRoute = .text
                selectedPhotoItem = nil
            } label: {
                Image(systemName: appModel.isSendingDraft ? "hourglass" : "arrow.up")
            }
            .buttonStyle(CompactCaptureButtonStyle(isActive: appModel.draft.canSend))
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
        ZStack(alignment: .topLeading) {
            TextEditor(text: $appModel.draft.body)
                .focused($isBodyFocused)
                .scrollContentBackground(.hidden)
                .foregroundStyle(MudsnoteColors.text)
                .font(.body)
                .lineSpacing(2)
                .padding(.horizontal, 2)
                .padding(.vertical, 4)
                .background(MudsnoteColors.panel)
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
        }
        .frame(minHeight: 156)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(appModel.draft.attachments.enumerated()), id: \.offset) { index, attachment in
                    HStack(spacing: 6) {
                        Label(attachmentLabel(attachment), systemImage: attachmentIcon(attachment))
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

    private func appendToken(_ token: String) {
        if appModel.draft.body.isEmpty || token.hasPrefix("\n") {
            appModel.draft.body += token.trimmingCharacters(in: .whitespaces)
        } else {
            appModel.draft.body += token
        }
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

    private func activateInitialRoute(_ route: CaptureRoute) {
        switch route {
        case .text:
            isBodyFocused = true
        case .image:
            isBodyFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard selectedRoute == .image else { return }
                isPhotoPickerPresented = true
            }
        case .audio:
            isBodyFocused = false
            guard !didStartInitialAudioRoute else { return }
            didStartInitialAudioRoute = true
            appModel.startAudioRecording()
        }
    }
}
