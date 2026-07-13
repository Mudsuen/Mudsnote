import SwiftUI
import AVFoundation
import UIKit

struct MarkdownPreviewView: View {
    private enum Source {
        case memo(MemoBlock)
        case document(MarkdownDocument)
    }

    @EnvironmentObject private var appModel: AppModel
    @FocusState private var editorFocused: Bool
    private var source: Source
    private var title: String
    private var metadata: String
    @State private var draftMarkdown: String
    @State private var originalMarkdown: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var accessedRoot: URL?
    @State private var accessRevision = 0

    init(memo: MemoBlock) {
        source = .memo(memo)
        title = String(localized: "Markdown")
        metadata = memo.dateText
        _draftMarkdown = State(initialValue: memo.body)
        _originalMarkdown = State(initialValue: memo.body)
    }

    init(document: MarkdownDocument) {
        source = .document(document)
        title = document.title
        metadata = document.relativePath
        _draftMarkdown = State(initialValue: document.markdown)
        _originalMarkdown = State(initialValue: document.markdown)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(metadata)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(MudsnoteColors.text)

                    if isEditing {
                        TextEditor(text: $draftMarkdown)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(MudsnoteColors.text)
                            .scrollContentBackground(.hidden)
                            .focused($editorFocused)
                            .frame(minHeight: 420)
                            .accessibilityIdentifier("markdown-editor")
                    } else {
                        markdownBody
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("rendered-markdown")
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isEditing = true
                                editorFocused = true
                            }
                    }
                }
                .padding(MudsnoteSpacing.safeHorizontal)
            }
            .background(MudsnoteColors.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await saveAndFinishEditing() }
                        } label: {
                            if isSaving {
                                ProgressView()
                            } else {
                                Image(systemName: "checkmark")
                            }
                        }
                        .disabled(isSaving)
                        .accessibilityLabel("Save note")
                    }
                }
            }
        }
        .interactiveDismissDisabled(isEditing && draftMarkdown != originalMarkdown)
        .onAppear(perform: beginLibraryAccess)
        .onDisappear(perform: endLibraryAccess)
    }

    private var markdownBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(renderLines().enumerated()), id: \.offset) { _, line in
                if let attachment = MarkdownAttachmentLine(line) {
                    attachmentView(attachment)
                } else if line.hasPrefix(">") {
                    Text(line.trimmingCharacters(in: CharacterSet(charactersIn: "> ")))
                        .font(.body.italic())
                        .foregroundStyle(MudsnoteColors.muted)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(MudsnoteColors.line).frame(width: 3)
                        }
                } else {
                    markdownText(line)
                }
            }
        }
    }

    @ViewBuilder
    private func attachmentView(_ attachment: MarkdownAttachmentLine) -> some View {
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
            } else {
                attachmentLabel(attachment)
            }
        case .audio, .file:
            if attachment.kind == .audio, let url = localFileURL(for: attachment.path) {
                AudioAttachmentPlayer(url: url, title: attachment.path)
            } else if let url = localFileURL(for: attachment.path) {
                Link(destination: url) { attachmentLabel(attachment) }
            } else {
                attachmentLabel(attachment)
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

    private func markdownText(_ line: String) -> Text {
        if let attributed = try? AttributedString(markdown: line) {
            return Text(attributed)
                .foregroundStyle(MudsnoteColors.text)
        }
        return Text(line).foregroundStyle(MudsnoteColors.text)
    }

    private func renderLines() -> [String] {
        draftMarkdown
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    @MainActor
    private func saveAndFinishEditing() async {
        editorFocused = false
        guard draftMarkdown != originalMarkdown else {
            isEditing = false
            return
        }
        isSaving = true
        defer { isSaving = false }

        let saved: Bool
        switch source {
        case .memo(let memo):
            saved = await appModel.saveMemo(
                memo,
                body: draftMarkdown,
                expectedBody: originalMarkdown
            ) != nil
        case .document(let document):
            saved = await appModel.saveDocument(
                document,
                markdown: draftMarkdown,
                expectedMarkdown: originalMarkdown
            ) != nil
        }
        if saved {
            originalMarkdown = draftMarkdown
            isEditing = false
        } else {
            editorFocused = true
        }
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

private struct MarkdownAttachmentLine {
    enum Kind {
        case image
        case audio
        case file
    }

    var path: String
    var systemImage: String
    var kind: Kind

    init?(_ line: String) {
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
            systemImage = "waveform"
            kind = .audio
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
