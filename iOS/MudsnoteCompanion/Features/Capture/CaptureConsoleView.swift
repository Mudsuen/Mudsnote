import PhotosUI
import SwiftUI

struct CaptureConsoleView: View {
    @EnvironmentObject private var appModel: AppModel
    @FocusState private var isBodyFocused: Bool
    @State private var selectedRoute: CaptureRoute
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented = false

    init(initialRoute: CaptureRoute) {
        _selectedRoute = State(initialValue: initialRoute)
    }

    var body: some View {
        VStack(spacing: 12) {
            editor

            if !appModel.draft.attachments.isEmpty {
                attachmentStrip
            }

            commandBar
        }
        .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(MudsnoteColors.panel)
        .onAppear {
            if selectedRoute == .image {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    isPhotoPickerPresented = true
                }
            } else {
                isBodyFocused = true
            }
        }
        .onChange(of: appModel.captureRoute) { _, route in
            selectedRoute = route
            isBodyFocused = route != .image
            if route == .image {
                isPhotoPickerPresented = true
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            selectedRoute = .image
            appModel.attachPhoto(item)
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedPhotoItem,
            matching: .images
        )
        .onDisappear {
            appModel.cancelAudioRecording()
        }
    }

    private var commandBar: some View {
        HStack(spacing: 10) {
            Button {
                selectedRoute = .image
                isPhotoPickerPresented = true
            } label: {
                Image(systemName: appModel.isPreparingAttachment ? "hourglass" : "photo")
            }
            .buttonStyle(IconCircleButtonStyle(isActive: selectedRoute == .image))
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Add image")

            Button {
                selectedRoute = .audio
                appModel.toggleAudioRecording()
            } label: {
                Image(systemName: appModel.isAudioTransitioning ? "hourglass" : (appModel.audioRecorder.isRecording ? "stop.fill" : "waveform"))
            }
            .buttonStyle(IconCircleButtonStyle(isActive: appModel.audioRecorder.isRecording || selectedRoute == .audio))
            .disabled(
                appModel.isSendingDraft
                    || appModel.isPreparingAttachment
                    || appModel.isAudioTransitioning
                    || appModel.isTranscribingAudio
            )
            .accessibilityLabel(
                Text(LocalizedStringKey(appModel.audioRecorder.isRecording ? "Stop recording" : "Record audio"))
            )

            Menu {
                Button("Tag") { appendToken(" #tag") }
                Button("Bold") { appendToken("**bold**") }
                Button("List") { appendToken("\n- ") }
                Divider()
                Button("Quote") { appendToken("\n> ") }
                Button("Checklist") { appendToken("\n- [ ] ") }
                Button("Code") { appendToken(" `code`") }
            } label: {
                Image(systemName: "textformat")
            }
            .buttonStyle(IconCircleButtonStyle())
            .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)
            .accessibilityLabel("Formatting")

            TargetMenuView()
                .disabled(appModel.isSendingDraft || appModel.isPreparingAttachment)

            Spacer()

            Button {
                isBodyFocused = false
                appModel.sendDraft(continueCapturing: false)
                selectedRoute = .text
                selectedPhotoItem = nil
            } label: {
                Image(systemName: appModel.isSendingDraft ? "hourglass" : "arrow.up")
            }
            .buttonStyle(IconCircleButtonStyle(isActive: appModel.draft.canSend))
            .disabled(
                !appModel.draft.canSend
                    || appModel.isSendingDraft
                    || appModel.isPreparingAttachment
                    || appModel.audioRecorder.isRecording
                    || appModel.isAudioTransitioning
                    || appModel.isTranscribingAudio
            )
            .accessibilityLabel("Save memo")
            .accessibilityIdentifier("save-memo-button")
        }
        .frame(minHeight: 52)
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
}
