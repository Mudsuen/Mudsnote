import SwiftUI
import AVFoundation
import AVKit
import PencilKit
import PhotosUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

struct VideoAttachmentPlayer: View {
    var url: URL
    var title: String
    @State private var player: AVPlayer

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VideoPlayer(player: player)
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(MudsnoteColors.line, lineWidth: 1)
                }
            Text((title as NSString).lastPathComponent)
                .font(.caption)
                .foregroundStyle(MudsnoteColors.muted)
                .lineLimit(1)
        }
        .onDisappear { player.pause() }
    }
}

struct AudioAttachmentPlayer: View {
    var url: URL
    var title: String
    @StateObject private var playback = AudioPlaybackController()
    @State private var saveMessage: String?
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                .accessibilityLabel(playback.isPlaying ? "Pause audio" : "Play audio")
                .accessibilityIdentifier("audio-attachment-playback")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio")
                        .font(.headline)
                        .foregroundStyle(MudsnoteColors.text)
                    Text((title as NSString).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(MudsnoteColors.muted)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    saveLocally()
                } label: {
                    Label("Save Locally", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save audio locally")
                .accessibilityIdentifier("audio-attachment-save-local")
            }

            if let message = playback.errorMessage ?? saveMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(playback.errorMessage == nil ? MudsnoteColors.muted : .red)
                    .accessibilityIdentifier(
                        playback.errorMessage == nil
                            ? "audio-save-success"
                            : "audio-playback-error"
                    )
            }
        }
        .padding(12)
        .mudsnoteGlassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onDisappear {
            playback.stop()
        }
        .alert("Could Not Save Audio", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "")
        }
    }

    private func togglePlayback() {
        playback.toggle(url: url)
    }

    private func saveLocally() {
        do {
            let savedURL = try LocalAudioSaveService().save(
                sourceURL: url,
                to: LocalAudioSaveService.defaultDirectory
            )
            saveError = nil
            saveMessage = String(
                format: String(localized: "Saved as %@ in Files > On My iPhone > Mudsnote > Saved Audio"),
                locale: .current,
                savedURL.lastPathComponent
            )
        } catch {
            saveMessage = nil
            saveError = error.localizedDescription
        }
    }
}

@MainActor
final class AudioPlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        do {
            errorMessage = nil
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
                guard player.play() else {
                    errorMessage = String(localized: "Could not play this audio file.")
                    return
                }
                isPlaying = true
            }
        } catch {
            stop()
            errorMessage = String(localized: "Could not play this audio file.")
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
            self?.errorMessage = String(localized: "Could not play this audio file.")
        }
    }
}

struct LocalAudioSaveService {
    static var defaultDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Saved Audio", isDirectory: true)
    }

    var fileManager = FileManager.default

    func save(sourceURL: URL, to directory: URL) throws -> URL {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }
        guard fileManager.fileExists(atPath: sourceURL.path),
              (try sourceURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw CocoaError(.fileNoSuchFile)
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let sanitizedStem = sanitizedFilenameStem(sourceName)
        let fileExtension = sourceURL.pathExtension.isEmpty
            ? "m4a"
            : sourceURL.pathExtension.lowercased()
        var destination = directory.appendingPathComponent("\(sanitizedStem).\(fileExtension)")
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(
                "\(sanitizedStem) \(suffix).\(fileExtension)"
            )
            suffix += 1
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private func sanitizedFilenameStem(_ value: String) -> String {
        let sanitized = value
            .replacingOccurrences(
                of: #"[/\\:?*|\"<>\u{0000}-\u{001F}]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Audio" : String(sanitized.prefix(80))
    }
}

struct MarkdownAttachmentLine {
    enum Kind: Equatable {
        case image
        case video
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
            let candidate = line
                .replacingOccurrences(of: "![[", with: "")
                .replacingOccurrences(of: "]]", with: "")
            guard Self.isAttachmentPath(candidate) else { return nil }
            path = candidate
            systemImage = "paperclip"
            kind = .file
            return
        }

        if let match = Self.match(line, pattern: #"^!\[[^\]]*\]\(([^)]+)\)$"#) {
            guard Self.isAttachmentPath(match) else { return nil }
            path = match
            systemImage = "photo"
            kind = .image
            return
        }

        if let match = Self.match(line, pattern: #"^\[[^\]]+\]\(([^)]+)\)$"#) {
            guard Self.isAttachmentPath(match) else { return nil }
            path = match
            let libraryKind = LibraryAttachment.Kind(
                fileExtension: (match as NSString).pathExtension
            )
            if libraryKind == .video {
                systemImage = "video"
                kind = .video
            } else if libraryKind == .audio {
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

    private static func isAttachmentPath(_ value: String) -> Bool {
        let decoded = value.removingPercentEncoding ?? value
        return decoded.hasPrefix("Attachments/")
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
final class MarkdownDrawingController: NSObject, ObservableObject, PKCanvasViewDelegate {
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

struct MarkdownDrawingCanvas: UIViewRepresentable {
    @ObservedObject var controller: MarkdownDrawingController

    func makeUIView(context: Context) -> PKCanvasView {
        controller.configureIfNeeded()
        return controller.canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        controller.configureIfNeeded()
    }
}

struct MarkdownDrawingEditor: View {
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
