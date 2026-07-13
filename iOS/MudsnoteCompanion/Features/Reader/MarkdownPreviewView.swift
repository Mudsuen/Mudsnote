import SwiftUI
import AVFoundation
import PhotosUI
import UIKit

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

    @EnvironmentObject private var appModel: AppModel
    @Binding private var detent: PresentationDetent
    private var source: Source
    private var metadata: String
    @State private var draftMarkdown: String
    @State private var originalMarkdown: String
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var saveState: SaveState = .idle
    @State private var isSaveFailurePresented = false
    @State private var editorFocused = false
    @State private var editingCommand: MarkdownEditingCommand?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var editorDisplayMode: EditorDisplayMode = .rich
    @State private var accessedRoot: URL?
    @State private var accessRevision = 0

    init(memo: MemoBlock, detent: Binding<PresentationDetent>) {
        _detent = detent
        source = .memo(memo)
        metadata = memo.dateText
        _draftMarkdown = State(initialValue: memo.body)
        _originalMarkdown = State(initialValue: memo.body)
    }

    init(document: MarkdownDocument, detent: Binding<PresentationDetent>) {
        _detent = detent
        source = .document(document)
        metadata = document.relativePath
        _draftMarkdown = State(initialValue: document.markdown)
        _originalMarkdown = State(initialValue: document.markdown)
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
                            displaysSource: editorDisplayMode == .source
                        )
                        .accessibilityIdentifier("markdown-editor")
                    }
                    .padding(MudsnoteSpacing.safeHorizontal)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            metadataLabel
                            markdownBody
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("rendered-markdown")
                                .contentShape(Rectangle())
                                .onTapGesture(perform: beginEditing)
                        }
                        .padding(MudsnoteSpacing.safeHorizontal)
                    }
                }
            }
            .background(MudsnoteColors.canvas)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isEditing { markdownToolbar }
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
                            Image(systemName: editorDisplayMode == .rich ? "textformat" : "chevron.left.forwardslash.chevron.right")
                        }
                        .accessibilityLabel("Editor Display")
                        .accessibilityIdentifier("markdown-display-mode")
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
                        .disabled(isSaving)
                        .accessibilityLabel("Save note")
                        .accessibilityIdentifier("save-markdown-button")
                    }
                }
            }
        }
        .interactiveDismissDisabled(isEditing && draftMarkdown != originalMarkdown)
        .onAppear(perform: beginLibraryAccess)
        .onDisappear(perform: endLibraryAccess)
        .onChange(of: selectedPhotoItem) { _, item in
            guard item != nil else { return }
            Task { await attachPhoto(item) }
        }
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
    }

    private var metadataLabel: some View {
        HStack(spacing: 8) {
            Text(metadata)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundStyle(MudsnoteColors.text)
            Spacer(minLength: 8)
            if isEditing {
                Text(saveStatusText)
                    .font(.caption)
                    .foregroundStyle(saveState == .failed ? Color.red : MudsnoteColors.muted)
                    .accessibilityIdentifier("markdown-save-status")
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
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Image(systemName: attachmentIsPreparing ? "hourglass" : "photo")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MudsnoteColors.text)
                            .frame(width: 40, height: 40)
                            .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving || appModel.isPreparingAttachment)
                    .accessibilityLabel("Add image")
                    .accessibilityIdentifier("markdown-add-image")
                }
                formatButton("textformat.size", .heading)
                formatButton("bold", .bold)
                formatButton("italic", .italic)
                formatButton("list.bullet", .bullet)
                formatButton("checklist", .checklist)
                formatButton("text.quote", .quote)
                formatButton("chevron.left.forwardslash.chevron.right", .code)
                formatButton("link", .link)
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
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(MudsnoteColors.text)
                .frame(width: 40, height: 40)
                .background(MudsnoteColors.card, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("markdown-format-\(kind.identifier)")
    }

    private func beginEditing() {
        isEditing = true
        withAnimation(.snappy(duration: 0.28)) { detent = .large }
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
        .contextMenu {
            if case .document = source {
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
            return await appModel.saveDocument(
                document,
                markdown: markdown,
                expectedMarkdown: originalMarkdown,
                announce: announce
            ) != nil
        }
    }

    private func reloadSavedVersion() async {
        let markdown: String?
        switch source {
        case .memo(let memo):
            markdown = await appModel.reloadMemo(memo)?.body
        case .document(let document):
            markdown = await appModel.reloadDocument(document)?.markdown
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
        guard case .document(let document) = source else { return }
        await persistDraft(finishEditing: false, announce: false)
        guard draftMarkdown == originalMarkdown else { return }
        saveState = .saving
        if let updated = await appModel.attachPhoto(
            item,
            to: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
            editorFocused = true
        } else {
            saveState = .failed
            isSaveFailurePresented = true
        }
    }

    private func removeAttachment(_ attachment: MarkdownAttachmentLine) async {
        guard case .document(let document) = source else { return }
        if let updated = await appModel.removeAttachment(
            line: attachment.rawLine,
            from: document,
            markdown: draftMarkdown,
            expectedMarkdown: originalMarkdown
        ) {
            draftMarkdown = updated.markdown
            originalMarkdown = updated.markdown
            saveState = .saved
        } else {
            saveState = .failed
            isSaveFailurePresented = true
        }
    }
}

struct MarkdownEditingCommand: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading
        case bold
        case italic
        case bullet
        case checklist
        case quote
        case code
        case link
        case undo
        case redo

        var identifier: String {
            switch self {
            case .heading: "heading"
            case .bold: "bold"
            case .italic: "italic"
            case .bullet: "bullet"
            case .checklist: "checklist"
            case .quote: "quote"
            case .code: "code"
            case .link: "link"
            case .undo: "undo"
            case .redo: "redo"
            }
        }
    }

    let id = UUID()
    var kind: Kind
}

@MainActor
enum MarkdownEditorPresentation {
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
            storage.endEditing()
            textView.typingAttributes = baseAttributes
            textView.selectedRange = clamped(selection, length: storage.length)
            return
        }

        let source = storage.string as NSString
        applyHeadings(in: source, storage: storage)
        applyDelimited(#"\*\*([^\n]+?)\*\*"#, markerLength: 2, trait: .traitBold, in: source, storage: storage)
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
            conceal(NSRange(location: match.range.location, length: markerLength), in: storage)
            conceal(NSRange(location: NSMaxRange(match.range) - markerLength, length: markerLength), in: storage)
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
}

private struct MarkdownTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    @Binding var command: MarkdownEditingCommand?
    var displaysSource: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
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

        func apply(_ kind: MarkdownEditingCommand.Kind, to textView: UITextView) {
            switch kind {
            case .heading:
                toggleLinePrefix("## ", in: textView)
            case .bold:
                wrapSelection(prefix: "**", suffix: "**", placeholder: "bold", in: textView)
            case .italic:
                wrapSelection(prefix: "_", suffix: "_", placeholder: "italic", in: textView)
            case .bullet:
                toggleLinePrefix("- ", in: textView)
            case .checklist:
                toggleLinePrefix("- [ ] ", in: textView)
            case .quote:
                toggleLinePrefix("> ", in: textView)
            case .code:
                wrapSelection(prefix: "`", suffix: "`", placeholder: "code", in: textView)
            case .link:
                let range = textView.selectedRange
                let selected = (textView.text as NSString).substring(with: range)
                let label = selected.isEmpty ? "text" : selected
                replace(range, with: "[\(label)](https://)", selecting: NSRange(location: range.location + 1, length: (label as NSString).length), in: textView)
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

        private func wrapSelection(
            prefix: String,
            suffix: String,
            placeholder: String,
            in textView: UITextView
        ) {
            let range = textView.selectedRange
            let selected = (textView.text as NSString).substring(with: range)
            let content = selected.isEmpty ? placeholder : selected
            replace(
                range,
                with: prefix + content + suffix,
                selecting: NSRange(location: range.location + (prefix as NSString).length, length: (content as NSString).length),
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

private struct MarkdownAttachmentLine {
    enum Kind {
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
