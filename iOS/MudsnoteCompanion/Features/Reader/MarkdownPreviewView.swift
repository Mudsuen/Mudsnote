import SwiftUI
import AVFoundation
import UIKit

struct MarkdownPreviewView: View {
    @EnvironmentObject private var appModel: AppModel
    var memo: MemoBlock
    @State private var showRaw = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(memo.dateText)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(MudsnoteColors.text)

                    if showRaw {
                        Text(memo.body)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(MudsnoteColors.text)
                            .textSelection(.enabled)
                    } else {
                        markdownBody
                    }
                }
                .padding(MudsnoteSpacing.safeHorizontal)
            }
            .background(MudsnoteColors.canvas)
            .navigationTitle("Markdown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(showRaw ? "Preview" : "Raw") {
                        showRaw.toggle()
                    }
                    .foregroundStyle(MudsnoteColors.text)
                }
            }
        }
    }

    private var markdownBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(renderLines(), id: \.self) { line in
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
        return root.appendingPathComponent(relativePath)
    }

    private func markdownText(_ line: String) -> Text {
        if let attributed = try? AttributedString(markdown: line) {
            return Text(attributed)
                .foregroundStyle(MudsnoteColors.text)
        }
        return Text(line).foregroundStyle(MudsnoteColors.text)
    }

    private func renderLines() -> [String] {
        memo.body
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct AudioAttachmentPlayer: View {
    var url: URL
    var title: String
    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
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
            player?.stop()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        do {
            if player == nil {
                player = try AVAudioPlayer(contentsOf: url)
            }
            guard let player else { return }
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
        } catch {
            isPlaying = false
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
