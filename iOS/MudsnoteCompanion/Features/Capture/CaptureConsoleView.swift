import PhotosUI
import SwiftUI

struct CaptureConsoleView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
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

            formatToolbar

            HStack(spacing: 12) {
                routeButton(.text, icon: "text.alignleft")

                Button {
                    selectedRoute = .image
                    isPhotoPickerPresented = true
                } label: {
                    Image(systemName: "photo")
                }
                .buttonStyle(IconCircleButtonStyle(isActive: selectedRoute == .image))
                .accessibilityLabel("添加图片")

                Button {
                    selectedRoute = .audio
                    appModel.toggleAudioRecording()
                } label: {
                    Image(systemName: appModel.audioRecorder.isRecording ? "stop.fill" : "waveform")
                }
                .buttonStyle(IconCircleButtonStyle(isActive: appModel.audioRecorder.isRecording || selectedRoute == .audio))
                .accessibilityLabel(appModel.audioRecorder.isRecording ? "停止录音" : "录制语音")

                TargetMenuView()

                Spacer()

                Button {
                    appModel.sendDraft()
                    dismiss()
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(IconCircleButtonStyle(isActive: appModel.draft.canSend))
                .disabled(!appModel.draft.canSend)
                .accessibilityLabel("Save memo")
            }
        }
        .padding(.horizontal, MudsnoteSpacing.safeHorizontal)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(MudsnoteColors.panel)
        .onAppear {
            isBodyFocused = selectedRoute != .image
            if selectedRoute == .image {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isPhotoPickerPresented = true
                }
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

            if appModel.draft.body.isEmpty {
                HStack(spacing: 9) {
                    Rectangle()
                        .fill(MudsnoteColors.primary)
                        .frame(width: 3, height: 28)
                    Text(selectedRoute == .audio ? "转写内容会出现在这里..." : "现在的想法是...")
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

    private var formatToolbar: some View {
        HStack(spacing: 0) {
            formatButton("#") {
                appendToken(" #tag")
            }

            Divider().frame(height: 28).padding(.horizontal, 10)

            Button {
                selectedRoute = .image
                isPhotoPickerPresented = true
            } label: {
                Image(systemName: "photo")
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("从相册添加图片")

            Divider().frame(height: 28).padding(.horizontal, 10)

            Button {
                appendToken("**bold**")
            } label: {
                Image(systemName: "bold")
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("加粗")

            Divider().frame(height: 28).padding(.horizontal, 10)

            Button {
                appendToken("\n- ")
            } label: {
                Image(systemName: "list.bullet")
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("列表")

            Divider().frame(height: 28).padding(.horizontal, 10)

            Menu {
                Button("Quote") { appendToken("\n> ") }
                Button("Checklist") { appendToken("\n- [ ] ") }
                Button("Code") { appendToken(" `code`") }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多格式")
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(MudsnoteColors.text)
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(MudsnoteColors.line, lineWidth: 1)
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(appModel.draft.attachments.enumerated()), id: \.offset) { index, attachment in
                    Label(attachmentLabel(attachment), systemImage: attachmentIcon(attachment))
                        .font(.caption)
                        .foregroundStyle(MudsnoteColors.text)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(MudsnoteColors.card, in: Capsule())
                        .overlay { Capsule().stroke(MudsnoteColors.line, lineWidth: 1) }
                        .contextMenu {
                            Button("Remove", role: .destructive) {
                                appModel.draft.attachments.remove(at: index)
                            }
                        }
                }
            }
        }
    }

    private func routeButton(_ route: CaptureRoute, icon: String) -> some View {
        Button {
            selectedRoute = route
            isBodyFocused = true
        } label: {
            Image(systemName: icon)
        }
        .buttonStyle(IconCircleButtonStyle(isActive: selectedRoute == route))
    }

    private func attachmentLabel(_ attachment: CaptureAttachment) -> String {
        switch attachment {
        case .image:
            return "Image"
        case .audio:
            return "Audio"
        }
    }

    private func attachmentIcon(_ attachment: CaptureAttachment) -> String {
        switch attachment {
        case .image:
            return "photo"
        case .audio:
            return "waveform"
        }
    }

    private func formatButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(width: 44, height: 36)
        }
        .buttonStyle(.plain)
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
