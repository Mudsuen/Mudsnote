import AppKit
import Foundation
import QuickMarkdownCore

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, WindowOpacityAdjusting, MarkdownTextViewCommands {
    private enum SlashCommand: CaseIterable {
        case heading
        case checklist
        case bulletList
        case orderedList
        case divider

        var title: String {
            switch self {
            case .heading: return "Heading 1"
            case .checklist: return "To-do List"
            case .bulletList: return "Bulleted List"
            case .orderedList: return "Numbered List"
            case .divider: return "Divider"
            }
        }

        var subtitle: String {
            switch self {
            case .heading: return "Turn this line into a heading"
            case .checklist: return "Start a checklist item"
            case .bulletList: return "Start a bullet item"
            case .orderedList: return "Start a numbered item"
            case .divider: return "Insert a divider marker"
            }
        }

        var symbolName: String {
            switch self {
            case .heading: return "textformat.size"
            case .checklist: return "checklist"
            case .bulletList: return "list.bullet"
            case .orderedList: return "list.number"
            case .divider: return "minus"
            }
        }
    }

    private enum InlineSuggestionContext {
        case tags(query: String, replacementRange: NSRange, items: [String])
        case slash(query: String, replacementRange: NSRange, items: [SlashCommand])
    }

    private enum ToolbarAction: Int, CaseIterable {
        case heading
        case bold
        case italic
        case strikethrough
        case underline
        case checklist
        case orderedList
        case bulletList

        var title: String? {
            switch self {
            case .heading: return "H"
            case .bold: return "B"
            case .italic: return "I"
            case .strikethrough: return "S"
            case .underline: return "U"
            default: return nil
            }
        }

        var symbolName: String? {
            switch self {
            case .checklist: return "checklist"
            case .orderedList: return "list.number"
            case .bulletList: return "list.bullet"
            default: return nil
            }
        }

        var toolTip: String {
            switch self {
            case .heading: return "Heading"
            case .bold: return "Bold"
            case .italic: return "Italic"
            case .strikethrough: return "Strikethrough"
            case .underline: return "Underline"
            case .checklist: return "Checklist"
            case .orderedList: return "Numbered list"
            case .bulletList: return "Bulleted list"
            }
        }

        var keyEquivalent: String { "" }

        var keyModifiers: NSEvent.ModifierFlags { [] }
    }

    private let noteStore: NoteStore
    private let onSave: (URL) -> Void
    private let onClose: () -> Void
    private let onRequestSearch: () -> Void

    private let editorTextView = MarkdownTextView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "")
    private var toolbarButtons: [HoverToolbarButton] = []
    private var toolbarButtonsByAction: [ToolbarAction: HoverToolbarButton] = [:]
    private weak var saveButton: HoverToolbarButton?

    private var fileURL: URL?
    private var selectedDirectoryURL: URL
    private var observers: [NSObjectProtocol] = []
    private var autosaveTimer: Timer?
    private var isDirty = false
    private var suppressAutosave = false
    private var suppressTextDidChange = false
    private var currentPanelOpacity: Double
    private var activeTags: [String] = []
    private let suggestionController = SuggestionPopoverController()
    private var inlineSuggestionContext: InlineSuggestionContext?
    private weak var backdropView: GradientBackdropView?
    private weak var shellContentView: NSView?
    private let initialWindowFrame: NSRect?
    private let draftIDOverride: String?
    private let saveShortcut: HotKeySpec?
    private let showsSaveButton: Bool
    private let remembersWindowFrame: ((NSRect) -> Void)?
    private var hasPresentedWindow = false
    private var didCloseWindow = false

    private lazy var theme = MarkdownEditorTheme(
        textColor: NSColor.white.withAlphaComponent(0.96),
        mutedTextColor: NSColor.white.withAlphaComponent(0.72),
        accentColor: NSColor.white.withAlphaComponent(0.92),
        bodyFont: NSFont.systemFont(ofSize: 14, weight: .regular),
        boldFont: NSFont.systemFont(ofSize: 14, weight: .bold),
        italicFont: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask),
        codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    )

    init(
        noteStore: NoteStore,
        panelOpacity: Double,
        fileURL: URL?,
        initialWindowFrame: NSRect? = nil,
        draftIDOverride: String? = nil,
        saveShortcut: HotKeySpec? = nil,
        showsSaveButton: Bool = true,
        windowLevel: NSWindow.Level? = nil,
        remembersWindowFrame: ((NSRect) -> Void)? = nil,
        onSave: @escaping (URL) -> Void,
        onClose: @escaping () -> Void,
        onRequestSearch: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.currentPanelOpacity = panelOpacity
        self.fileURL = fileURL
        self.initialWindowFrame = initialWindowFrame
        self.draftIDOverride = draftIDOverride
        self.saveShortcut = saveShortcut
        self.showsSaveButton = showsSaveButton
        self.remembersWindowFrame = remembersWindowFrame
        self.selectedDirectoryURL = fileURL?.deletingLastPathComponent() ?? noteStore.notesDirectory
        self.onSave = onSave
        self.onClose = onClose
        self.onRequestSearch = onRequestSearch

        let window = QuickEntryPanel(size: NSSize(width: 412, height: 314))
        window.isReleasedWhenClosed = false
        if let windowLevel {
            window.level = windowLevel
        }

        super.init(window: window)
        window.delegate = self
        window.onCommandS = { [weak self] in
            self?.savePressed()
        }
        window.onCommandF = { [weak self] in
            self?.searchPressed()
        }
        window.onEscape = { [weak self] in
            self?.cancelPressed()
        }
        window.onStandardEditCommand = { [weak self] selector in
            self?.performStandardEditCommand(selector) ?? false
        }
        window.onEditorCommand = { [weak self] event in
            self?.handleShortcutEvent(event) ?? false
        }

        configureSuggestionPopover()
        buildUI()
        configureObservers()
        loadInitialContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndFocus() {
        showWindow(nil)
        guard let window else { return }
        didCloseWindow = false
        if !hasPresentedWindow {
            if let initialWindowFrame {
                window.setFrame(initialWindowFrame, display: false)
            } else {
                positionPanelNearTopCenter(window)
            }
            hasPresentedWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: editorTextView.string.utf16.count, length: 0))
    }

    func hasMeaningfulUnsavedContent() -> Bool {
        let markdown = serializedMarkdown()
        let document = MarkdownEditorDocument.parse(editorText: markdown, tags: mergedDocumentTags(from: markdown))
        return !document.title.isEmpty || !document.body.isEmpty || !document.tags.isEmpty
    }

    var isWindowClosed: Bool {
        didCloseWindow
    }

    func rememberCurrentWindowFrame() {
        guard let frame = window?.frame else { return }
        remembersWindowFrame?(frame)
    }

    func hideWindowForToggle() {
        rememberCurrentWindowFrame()
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        didCloseWindow = true
        rememberCurrentWindowFrame()
        persistDraft(force: true)
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        autosaveTimer?.invalidate()
        onClose()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateWindowFocusAppearance(isFocused: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        updateWindowFocusAppearance(isFocused: false)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        backdropView?.setLiveResizing(true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        backdropView?.setLiveResizing(false)
        rememberCurrentWindowFrame()
    }

    func windowDidMove(_ notification: Notification) {
        rememberCurrentWindowFrame()
    }

    func windowDidResize(_ notification: Notification) {
        rememberCurrentWindowFrame()
    }

    func updatePanelOpacity(_ opacity: Double) {
        currentPanelOpacity = opacity
        window?.alphaValue = windowAlphaValue(for: opacity)
        backdropView?.updatePanelOpacity(opacity)
    }

    func markdownTextViewInsertNewline(_ textView: MarkdownTextView) {
        if commitPendingTagIfNeeded(insertingTrailingText: "\n") {
            return
        }
        guard handleStructuredNewline() else {
            textView.insertNewlineIgnoringFieldEditor(self)
            updateTypingAttributesFromInsertionPoint()
            return
        }
    }

    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool {
        guard text == " " || text == "\t" else { return false }
        return commitPendingTagIfNeeded(insertingTrailingText: text)
    }

    func markdownTextViewToggleBold(_ textView: MarkdownTextView) {
        toggleInlineFontTrait(.boldFontMask)
    }

    func markdownTextViewToggleItalic(_ textView: MarkdownTextView) {
        toggleInlineFontTrait(.italicFontMask)
    }

    func markdownTextViewToggleHeading(_ textView: MarkdownTextView) {
        toggleParagraphKind(.heading(level: 1))
    }

    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView) {
        toggleParagraphKind(.bullet)
    }

    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView) {
        toggleParagraphKind(.ordered(index: 1))
    }

    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView) {
        toggleParagraphKind(.checklist(checked: false))
    }

    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool {
        toggleChecklistIfNeeded(atCharacterIndex: index)
    }

    private var currentDraftID: String {
        if let draftIDOverride {
            return draftIDOverride
        }
        if let fileURL {
            return "edit-" + sha256Hex(fileURL.path)
        }
        return "quick-capture"
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let backdrop = GradientBackdropView(frame: contentView.bounds, panelOpacity: currentPanelOpacity)
        contentView.addSubview(backdrop)
        pin(backdrop, to: contentView)
        backdropView = backdrop

        let shellContent = NSView()
        backdrop.addSubview(shellContent)
        pin(shellContent, to: backdrop, insets: .init(top: 10, left: 12, bottom: 0, right: 0))
        shellContentView = shellContent

        let topDragBar = NSView()
        topDragBar.translatesAutoresizingMaskIntoConstraints = false

        editorTextView.commandDelegate = self
        editorTextView.isRichText = true
        editorTextView.importsGraphics = false
        editorTextView.usesFontPanel = false
        editorTextView.isAutomaticDataDetectionEnabled = false
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isAutomaticTextReplacementEnabled = false
        editorTextView.isContinuousSpellCheckingEnabled = true
        editorTextView.allowsUndo = true
        editorTextView.font = theme.bodyFont
        editorTextView.backgroundColor = .clear
        editorTextView.textColor = theme.textColor
        editorTextView.insertionPointColor = .white
        editorTextView.drawsBackground = false
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainerInset = NSSize(width: 0, height: 2)
        editorTextView.textContainer?.lineFragmentPadding = 0
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.documentView = editorTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        let slimScroller = SlimScroller()
        slimScroller.scrollerStyle = .legacy
        slimScroller.controlSize = .small
        slimScroller.knobStyle = .light
        scrollView.verticalScroller = slimScroller

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        let topDivider = NSBox()
        topDivider.boxType = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 10, weight: .medium)
        statusLabel.textColor = NSColor.white.withAlphaComponent(0.50)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let toolbarStack = NSStackView()
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.spacing = 1

        toolbarButtons.removeAll()
        toolbarButtonsByAction.removeAll()
        ToolbarAction.allCases.forEach { action in
            let button = makeToolbarButton(for: action)
            toolbarButtons.append(button)
            toolbarButtonsByAction[action] = button
            toolbarStack.addArrangedSubview(button)
        }

        let footerViews: [NSView]
        if showsSaveButton {
            let saveButton = HoverToolbarButton(frame: .zero)
            saveButton.title = "Save"
            saveButton.target = self
            saveButton.action = #selector(savePressed)
            saveButton.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
            saveButton.image?.isTemplate = true
            saveButton.imagePosition = .imageLeading
            saveButton.imageHugsTitle = true
            saveButton.controlSize = .small
            saveButton.font = .systemFont(ofSize: 11, weight: .semibold)
            saveButton.setContentHuggingPriority(.required, for: .horizontal)
            saveButton.widthAnchor.constraint(equalToConstant: 45).isActive = true
            saveButton.heightAnchor.constraint(equalToConstant: 24).isActive = true
            self.saveButton = saveButton
            footerViews = [toolbarStack, NSView(), saveButton]
        } else {
            self.saveButton = nil
            footerViews = [toolbarStack]
        }

        let footerBar = NSStackView(views: footerViews)
        footerBar.orientation = .horizontal
        footerBar.alignment = .centerY
        footerBar.spacing = 2
        footerBar.translatesAutoresizingMaskIntoConstraints = false

        shellContent.addSubview(topDragBar)
        shellContent.addSubview(topDivider)
        shellContent.addSubview(scrollView)
        shellContent.addSubview(divider)
        shellContent.addSubview(footerBar)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: showsSaveButton ? -8 : -4),

            topDragBar.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 2),
            topDragBar.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -8),
            topDragBar.topAnchor.constraint(equalTo: shellContent.topAnchor),
            topDragBar.heightAnchor.constraint(equalToConstant: 15),

            topDivider.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 2),
            topDivider.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -2),
            topDivider.topAnchor.constraint(equalTo: topDragBar.bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 2),
            divider.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -2),
            divider.bottomAnchor.constraint(equalTo: footerBar.topAnchor, constant: -1),

            footerBar.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 10),
            footerBar.trailingAnchor.constraint(lessThanOrEqualTo: shellContent.trailingAnchor, constant: -8),
            footerBar.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor, constant: -1),
            footerBar.heightAnchor.constraint(equalToConstant: showsSaveButton ? 24 : 20),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: showsSaveButton ? 214 : 220)
        ])

        refreshChrome()
        updatePanelOpacity(currentPanelOpacity)
        updateWindowFocusAppearance(isFocused: true)
        updateToolbarSelectionState()

        let suggestionView = suggestionController.view
        suggestionView.isHidden = true
        suggestionView.translatesAutoresizingMaskIntoConstraints = true
        shellContent.addSubview(suggestionView)
    }

    private func configureSuggestionPopover() {
        suggestionController.onSelect = { [weak self] index in
            self?.acceptInlineSuggestion(at: index)
        }
    }

    private func configureObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: NSText.didChangeNotification,
                object: editorTextView,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.userDidEdit()
                }
            }
        )
        observers.append(
            center.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: editorTextView,
                queue: nil
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.updateTypingAttributesFromInsertionPoint()
                    self?.updateToolbarSelectionState()
                    self?.updateInlineSuggestions()
                }
            }
        )
    }

    private func loadInitialContent() {
        suppressAutosave = true
        defer { suppressAutosave = false }

        let markdown: String
        if let fileURL {
            do {
                let note = try noteStore.loadNote(at: fileURL)
                markdown = MarkdownEditorDocument(title: note.title, body: note.body, tags: note.tags).editorText
                activeTags = note.tags
                isDirty = false
            } catch {
                presentErrorAlert(message: "Failed to load note", details: error.localizedDescription)
                markdown = ""
            }
        } else {
            markdown = ""
        }

        applyMarkdown(markdown)

        if let draft = noteStore.loadDraft(id: currentDraftID) {
            let draftMarkdown = MarkdownEditorDocument(title: draft.title, body: draft.body, tags: draft.tags).editorText
            applyMarkdown(draftMarkdown)
            selectedDirectoryURL = URL(fileURLWithPath: draft.selectedDirectoryPath, isDirectory: true)
            activeTags = draft.tags
            isDirty = true
            statusLabel.stringValue = "Restored"
        } else {
            statusLabel.stringValue = fileURL == nil ? "Markdown" : "Editing"
        }

        refreshChrome()
        updateTypingAttributesFromInsertionPoint()
        updateToolbarSelectionState()
        updateInlineSuggestions()
    }

    private func applyMarkdown(_ markdown: String) {
        suppressTextDidChange = true
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        editorTextView.textStorage?.setAttributedString(rendered)
        suppressTextDidChange = false
    }

    private func userDidEdit() {
        guard !suppressTextDidChange else { return }
        interpretTypedMarkdownIfNeeded()
        updateTypingAttributesFromInsertionPoint()
        updateToolbarSelectionState()
        updateInlineSuggestions()
        guard !suppressAutosave else { return }
        isDirty = true
        statusLabel.stringValue = "Autosaving"
        autosaveTimer?.invalidate()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.persistDraft(force: false)
            }
        }
    }

    private func refreshChrome() {
        refreshTrackedTags()
    }

    private func persistDraft(force: Bool) {
        autosaveTimer?.invalidate()
        autosaveTimer = nil

        guard isDirty || force else { return }

        let markdown = serializedMarkdown()
        let document = MarkdownEditorDocument.parse(editorText: markdown, tags: mergedDocumentTags(from: markdown))

        if document.title.isEmpty && document.body.isEmpty {
            noteStore.deleteDraft(id: currentDraftID)
            statusLabel.stringValue = fileURL == nil ? "Markdown" : "Editing"
            return
        }

        let snapshot = DraftSnapshot(
            id: currentDraftID,
            sourcePath: fileURL?.path,
            selectedDirectoryPath: selectedDirectoryURL.path,
            title: document.title,
            body: document.body,
            tags: document.tags,
            updatedAt: Date()
        )

        do {
            try noteStore.saveDraft(snapshot)
            statusLabel.stringValue = "Saved"
        } catch {
            statusLabel.stringValue = "Failed"
        }
    }

    private func serializedMarkdown() -> String {
        guard let storage = editorTextView.textStorage else { return "" }
        return MarkdownRichTextCodec.serialize(storage, theme: theme)
            .trimmingCharacters(in: CharacterSet.newlines)
    }

    private func interpretTypedMarkdownIfNeeded() {
        guard let storage = editorTextView.textStorage else { return }

        let currentLineRange = visibleLineRangeForSelection()
        let currentText = (storage.string as NSString).substring(with: currentLineRange)
        guard MarkdownRichTextCodec.shouldInterpretMarkdown(in: currentText) else { return }

        let selection = editorTextView.selectedRange()
        let selectionStartOffset = max(selection.location - currentLineRange.location, 0)
        let selectionEndOffset = max(NSMaxRange(selection) - currentLineRange.location, 0)
        let rendered = MarkdownRichTextCodec.renderLine(currentText, theme: theme)
        let clampedStart = min(selectionStartOffset, rendered.length)
        let clampedEnd = min(selectionEndOffset, rendered.length)
        let newSelection = NSRange(
            location: currentLineRange.location + clampedStart,
            length: max(clampedEnd - clampedStart, 0)
        )

        suppressTextDidChange = true
        storage.replaceCharacters(in: currentLineRange, with: rendered)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(newSelection)
    }

    private func updateTypingAttributesFromInsertionPoint() {
        guard let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        let location = max(min(selection.location, storage.length), 0)

        if storage.length == 0 || location == 0 {
            editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
            return
        }

        let lineRange = visibleLineRangeForSelection()
        let paragraphKind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: paragraphKind)

        if location <= contentRange.location {
            editorTextView.typingAttributes = theme.baseAttributes(for: paragraphKind)
            return
        }

        let probeLocation = max(min(location - 1, storage.length - 1), contentRange.location)
        let attrs = storage.attributes(at: probeLocation, effectiveRange: nil)
        editorTextView.typingAttributes = attrs
    }

    private func visibleLineRangeForSelection() -> NSRange {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let paragraphRange = string.paragraphRange(for: NSRange(location: min(selection.location, string.length), length: 0))
        return NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (string.substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0), 0))
    }

    private func selectedLineRanges() -> [NSRange] {
        let string = editorTextView.string as NSString
        let selection = editorTextView.selectedRange()
        let fullRange = string.lineRange(for: selection)
        var ranges: [NSRange] = []
        var location = fullRange.location

        while location < NSMaxRange(fullRange) {
            let paragraphRange = string.paragraphRange(for: NSRange(location: location, length: 0))
            let hasTrailingNewline = string.substring(with: paragraphRange).hasSuffix("\n")
            let visibleRange = NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (hasTrailingNewline ? 1 : 0), 0))
            ranges.append(visibleRange)
            location = NSMaxRange(paragraphRange)
        }

        if ranges.isEmpty {
            ranges.append(.init(location: 0, length: 0))
        }

        return ranges
    }

    private func handleStructuredNewline() -> Bool {
        guard let storage = editorTextView.textStorage else { return false }

        let lineRange = visibleLineRangeForSelection()
        let kind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: kind)
        let content = (storage.string as NSString).substring(with: contentRange).trimmingCharacters(in: .whitespacesAndNewlines)

        switch kind {
        case .paragraph:
            return false
        case .heading:
            insertStructuredLine(kind: .paragraph, inlineMarkdown: "")
            return true
        case .bullet, .ordered, .checklist:
            if content.isEmpty {
                convertCurrentLineToParagraph()
            } else {
                let nextKind: MarkdownParagraphKind
                switch kind {
                case .ordered(let index):
                    nextKind = .ordered(index: index + 1)
                case .checklist:
                    nextKind = .checklist(checked: false)
                default:
                    nextKind = kind
                }
                insertStructuredLine(kind: nextKind, inlineMarkdown: "")
            }
            return true
        }
    }

    private func handleEditorShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        switch (modifiers, keyCode) {
        case ([.command], 11): // b
            toggleInlineFontTrait(.boldFontMask)
            return true
        case ([.command], 34): // i
            toggleInlineFontTrait(.italicFontMask)
            return true
        case ([.command, .option], 18): // 1
            toggleParagraphKind(.heading(level: 1))
            return true
        case ([.command, .shift], 26): // 7
            toggleParagraphKind(.ordered(index: 1))
            return true
        case ([.command, .shift], 28): // 8
            toggleParagraphKind(.bullet)
            return true
        case ([.command, .shift], 25): // 9
            toggleParagraphKind(.checklist(checked: false))
            return true
        default:
            return false
        }
    }

    private func handleShortcutEvent(_ event: NSEvent) -> Bool {
        if let saveShortcut, saveShortcut.matches(event) {
            savePressed()
            return true
        }

        if isSuggestionVisible {
            switch event.keyCode {
            case 125:
                suggestionController.moveSelection(delta: 1)
                return true
            case 126:
                suggestionController.moveSelection(delta: -1)
                return true
            case 36, 76:
                if commitPendingTagIfNeeded(insertingTrailingText: "\n") {
                    dismissInlineSuggestions()
                    return true
                }
                suggestionController.acceptSelection()
                return true
            case 53:
                dismissInlineSuggestions()
                return true
            default:
                break
            }
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if handleEditorShortcut(keyCode: event.keyCode, modifiers: modifiers) {
            return true
        }

        if modifiers.contains(.command) {
            return true
        }

        return false
    }

    private func performStandardEditCommand(_ selector: Selector) -> Bool {
        guard let textResponder = window?.firstResponder as? NSText else { return false }

        switch selector {
        case #selector(NSText.copy(_:)):
            textResponder.copy(self)
            return true
        case #selector(NSText.cut(_:)):
            textResponder.cut(self)
            return true
        case #selector(NSText.paste(_:)):
            textResponder.paste(self)
            return true
        case #selector(NSResponder.selectAll(_:)):
            textResponder.selectAll(self)
            return true
        case Selector(("undo:")):
            textResponder.undoManager?.undo()
            return true
        case Selector(("redo:")):
            textResponder.undoManager?.redo()
            return true
        default:
            break
        }

        return false
    }

    private func convertCurrentLineToParagraph() {
        guard let storage = editorTextView.textStorage else { return }
        let lineRange = visibleLineRangeForSelection()
        let replacement = MarkdownRichTextCodec.renderLine("", theme: theme)

        suppressTextDidChange = true
        storage.replaceCharacters(in: lineRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: lineRange.location, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        userDidEdit()
    }

    private func insertStructuredLine(kind: MarkdownParagraphKind, inlineMarkdown: String) {
        guard let storage = editorTextView.textStorage else { return }
        let selection = editorTextView.selectedRange()
        let markdownLine = MarkdownRichTextCodec.markdownLine(for: kind, inlineContent: inlineMarkdown)
        let renderedLine = MarkdownRichTextCodec.renderLine(markdownLine, theme: theme)
        let replacement = NSMutableAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph))
        replacement.append(renderedLine)

        suppressTextDidChange = true
        storage.replaceCharacters(in: selection, with: replacement)
        suppressTextDidChange = false

        let cursorLocation = selection.location + 1 + kind.prefixLength
        editorTextView.setSelectedRange(NSRange(location: cursorLocation, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        userDidEdit()
    }

    private func toggleParagraphKind(_ target: MarkdownParagraphKind) {
        guard let storage = editorTextView.textStorage else { return }

        let ranges = selectedLineRanges()
        var renderedLines: [NSAttributedString] = []
        let currentKinds = ranges.map { MarkdownRichTextCodec.paragraphKind(at: $0, in: storage) }
        let shouldResetToParagraph = currentKinds.allSatisfy { sameParagraphCategory($0, target) }

        for (index, lineRange) in ranges.enumerated() {
            let currentKind = currentKinds[index]
            let contentRange = MarkdownRichTextCodec.visibleContentRange(for: lineRange, in: storage, kind: currentKind)
            let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(
                range: contentRange,
                in: storage,
                paragraphKind: currentKind,
                theme: theme
            )
            let nextKind: MarkdownParagraphKind

            if shouldResetToParagraph {
                nextKind = .paragraph
            } else {
                switch target {
                case .ordered:
                    nextKind = .ordered(index: index + 1)
                default:
                    nextKind = target
                }
            }

            let lineMarkdown = MarkdownRichTextCodec.markdownLine(for: nextKind, inlineContent: inlineMarkdown)
            renderedLines.append(MarkdownRichTextCodec.renderLine(lineMarkdown, theme: theme))
        }

        let replacement = joinRenderedLines(renderedLines)
        let fullRange = combinedRange(of: ranges)
        let selectionLocation = fullRange.location + replacement.length

        suppressTextDidChange = true
        storage.replaceCharacters(in: fullRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: selectionLocation, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
        userDidEdit()
    }

    private func sameParagraphCategory(_ lhs: MarkdownParagraphKind, _ rhs: MarkdownParagraphKind) -> Bool {
        switch (lhs, rhs) {
        case (.heading, .heading), (.bullet, .bullet), (.ordered, .ordered), (.checklist, .checklist), (.paragraph, .paragraph):
            return true
        default:
            return false
        }
    }

    private func joinRenderedLines(_ lines: [NSAttributedString]) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: theme.baseAttributes(for: .paragraph)))
            }
            result.append(line)
        }
        return result
    }

    private func combinedRange(of ranges: [NSRange]) -> NSRange {
        guard let first = ranges.first, let last = ranges.last else { return NSRange(location: 0, length: 0) }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }

    private func toggleInlineFontTrait(_ trait: NSFontTraitMask) {
        let selection = editorTextView.selectedRange()

        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let currentFont = (typing[.font] as? NSFont) ?? theme.bodyFont
            typing[.font] = toggledFont(from: currentFont, trait: trait)
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        suppressTextDidChange = true
        storage.beginEditing()
        var location = selection.location

        while location < NSMaxRange(selection) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let font = (storage.attribute(.font, at: location, effectiveRange: &effectiveRange) as? NSFont) ?? theme.bodyFont
            let clippedRange = NSIntersectionRange(selection, effectiveRange)
            storage.addAttribute(.font, value: toggledFont(from: font, trait: trait), range: clippedRange)
            location = NSMaxRange(clippedRange)
        }

        storage.endEditing()
        suppressTextDidChange = false
        userDidEdit()
    }

    private func toggledFont(from font: NSFont, trait: NSFontTraitMask) -> NSFont {
        let traits = NSFontManager.shared.traits(of: font)
        if traits.contains(trait) {
            return NSFontManager.shared.convert(font, toNotHaveTrait: trait)
        }
        return NSFontManager.shared.convert(font, toHaveTrait: trait)
    }

    private func applyAttribute(_ attributes: [NSAttributedString.Key: Any], removing keys: [NSAttributedString.Key] = []) {
        let selection = editorTextView.selectedRange()
        guard selection.length > 0, let storage = editorTextView.textStorage else { return }
        suppressTextDidChange = true
        storage.beginEditing()
        keys.forEach { storage.removeAttribute($0, range: selection) }
        storage.addAttributes(attributes, range: selection)
        storage.endEditing()
        suppressTextDidChange = false
        userDidEdit()
    }

    private func applyStrikethrough() {
        toggleIntAttribute(.strikethroughStyle, enabledValue: NSUnderlineStyle.single.rawValue)
    }

    private func applyUnderline() {
        toggleIntAttribute(.underlineStyle, enabledValue: NSUnderlineStyle.single.rawValue)
    }

    private func toggleIntAttribute(_ key: NSAttributedString.Key, enabledValue: Int) {
        let selection = editorTextView.selectedRange()

        if selection.length == 0 {
            var typing = editorTextView.typingAttributes
            let enabled = (typing[key] as? Int) == enabledValue
            if enabled {
                typing.removeValue(forKey: key)
            } else {
                typing[key] = enabledValue
            }
            editorTextView.typingAttributes = typing
            return
        }

        guard let storage = editorTextView.textStorage else { return }
        let enabled = (storage.attribute(key, at: selection.location, effectiveRange: nil) as? Int) == enabledValue

        if enabled {
            applyAttribute([:], removing: [key])
        } else {
            applyAttribute([key: enabledValue])
        }
    }

    private func updateToolbarSelectionState() {
        guard let storage = editorTextView.textStorage else { return }

        let selection = editorTextView.selectedRange()
        let probeLocation = max(min(selection.location == storage.length ? max(storage.length - 1, 0) : selection.location, storage.length == 0 ? 0 : storage.length - 1), 0)

        let paragraphKind: MarkdownParagraphKind = {
            if storage.length == 0 {
                return .paragraph
            }
            let lineRange = visibleLineRangeForSelection()
            return MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        }()

        let attributes: [NSAttributedString.Key: Any] = {
            if selection.length == 0 {
                return editorTextView.typingAttributes
            }
            guard storage.length > 0 else { return editorTextView.typingAttributes }
            return storage.attributes(at: probeLocation, effectiveRange: nil)
        }()

        let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
        let traits = NSFontManager.shared.traits(of: font)
        let isBold = traits.contains(.boldFontMask)
        let isItalic = traits.contains(.italicFontMask)
        let isUnderlined = ((attributes[.underlineStyle] as? Int) ?? 0) != 0
        let isStruck = ((attributes[.strikethroughStyle] as? Int) ?? 0) != 0

        toolbarButtonsByAction[.heading]?.isActive = {
            if case .heading = paragraphKind { return true }
            return false
        }()
        toolbarButtonsByAction[.bold]?.isActive = isBold
        toolbarButtonsByAction[.italic]?.isActive = isItalic
        toolbarButtonsByAction[.underline]?.isActive = isUnderlined
        toolbarButtonsByAction[.strikethrough]?.isActive = isStruck
        toolbarButtonsByAction[.bulletList]?.isActive = {
            if case .bullet = paragraphKind { return true }
            return false
        }()
        toolbarButtonsByAction[.orderedList]?.isActive = {
            if case .ordered = paragraphKind { return true }
            return false
        }()
        toolbarButtonsByAction[.checklist]?.isActive = {
            if case .checklist = paragraphKind { return true }
            return false
        }()
    }

    private func refreshTrackedTags() {
        activeTags = MarkdownEditorDocument.normalizedTags(extractInlineTags(from: editorTextView.string))
    }

    private func mergedDocumentTags(from markdown: String) -> [String] {
        MarkdownEditorDocument.normalizedTags(extractInlineTags(from: markdown))
    }

    private func extractInlineTags(from text: String) -> [String] {
        let characters = Array(text)
        var tags: [String] = []
        var index = 0

        while index < characters.count {
            if characters[index] == "#",
               (index == 0 || characters[index - 1].isWhitespace) {
                var end = index + 1
                while end < characters.count, characters[end].isTagCharacter {
                    end += 1
                }
                if end > index + 1 {
                    tags.append(String(characters[(index + 1)..<end]))
                    index = end
                    continue
                }
            }
            index += 1
        }

        return tags
    }

    private func currentTagToken() -> (query: String, replacementRange: NSRange)? {
        let selection = editorTextView.selectedRange()
        guard selection.length == 0 else { return nil }

        let string = editorTextView.string as NSString
        let caret = min(selection.location, string.length)
        let paragraphRange = string.paragraphRange(for: NSRange(location: caret, length: 0))
        let linePrefix = string.substring(with: NSRange(location: paragraphRange.location, length: max(caret - paragraphRange.location, 0)))

        guard let match = linePrefix.range(of: #"(^|\s)#([^\s#]*)$"#, options: .regularExpression) else {
            return nil
        }

        let token = String(linePrefix[match])
        let query = String(token.trimmingCharacters(in: .whitespaces).dropFirst())
        let replacementRange = NSRange(
            location: paragraphRange.location + linePrefix.distance(from: linePrefix.startIndex, to: match.lowerBound) + (token.hasPrefix(" ") ? 1 : 0),
            length: token.trimmingCharacters(in: .whitespaces).utf16.count
        )
        return (query, replacementRange)
    }

    private func rankedMatchingTags(for query: String) -> [String] {
        let known = noteStore.knownTags()
            .filter { candidate in
                !activeTags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            }

        guard !query.isEmpty else { return known }

        let loweredQuery = query.lowercased()
        return known
            .compactMap { tag -> (tag: String, score: Int)? in
                let loweredTag = tag.lowercased()
                if loweredTag == loweredQuery {
                    return (tag, 1000)
                }
                if loweredTag.hasPrefix(loweredQuery) {
                    return (tag, 850 - max(loweredTag.count - loweredQuery.count, 0))
                }
                if let range = loweredTag.range(of: loweredQuery) {
                    let offset = loweredTag.distance(from: loweredTag.startIndex, to: range.lowerBound)
                    return (tag, 650 - offset)
                }
                if isSubsequence(loweredQuery, of: loweredTag) {
                    return (tag, 420 - max(loweredTag.count - loweredQuery.count, 0))
                }
                if let distance = levenshteinDistance(between: loweredQuery, and: loweredTag), distance <= 2 {
                    return (tag, 240 - (distance * 40))
                }
                return nil
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.tag.localizedCaseInsensitiveCompare(rhs.tag) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .map(\.tag)
    }

    private func updateInlineSuggestions() {
        guard editorTextView.window != nil else { return }
        guard let context = currentInlineSuggestionContext() else {
            dismissInlineSuggestions()
            return
        }

        inlineSuggestionContext = context
        let items: [SuggestionItem]
        switch context {
        case .tags(_, _, let tags):
            items = tags.map { tag in
                SuggestionItem(
                    title: "#\(tag)",
                    subtitle: nil,
                    symbolName: nil
                )
            }
        case .slash(_, _, let commands):
            items = commands.map {
                SuggestionItem(title: $0.title, subtitle: nil, symbolName: nil)
            }
        }

        guard !items.isEmpty else {
            dismissInlineSuggestions()
            return
        }

        suggestionController.updateItems(items)
        positionSuggestionView(for: context)
    }

    private func currentInlineSuggestionContext() -> InlineSuggestionContext? {
        let selection = editorTextView.selectedRange()
        guard selection.length == 0 else { return nil }

        if let tagToken = currentTagToken() {
            let items = rankedMatchingTags(for: tagToken.query)
            if !items.isEmpty {
                return .tags(query: tagToken.query, replacementRange: tagToken.replacementRange, items: items)
            }
        }

        let string = editorTextView.string as NSString
        let caret = min(selection.location, string.length)
        let paragraphRange = string.paragraphRange(for: NSRange(location: caret, length: 0))
        let linePrefix = string.substring(with: NSRange(location: paragraphRange.location, length: max(caret - paragraphRange.location, 0)))

        if let match = linePrefix.range(of: #"(^|\s)/([^\s/]*)$"#, options: .regularExpression) {
            let token = String(linePrefix[match])
            let query = token.trimmingCharacters(in: .whitespaces).dropFirst().lowercased()
            let replacementRange = NSRange(location: paragraphRange.location + linePrefix.distance(from: linePrefix.startIndex, to: match.lowerBound) + (token.hasPrefix(" ") ? 1 : 0),
                                           length: token.trimmingCharacters(in: .whitespaces).utf16.count)
            let commands = SlashCommand.allCases.filter {
                query.isEmpty
                || $0.title.lowercased().contains(query)
                || $0.subtitle.lowercased().contains(query)
            }
            return commands.isEmpty ? nil : .slash(query: query, replacementRange: replacementRange, items: commands)
        }

        return nil
    }

    private func acceptInlineSuggestion(at index: Int) {
        guard let context = inlineSuggestionContext else { return }

        switch context {
        case .tags(_, let replacementRange, let items):
            guard items.indices.contains(index) else { return }
            applyTag(items[index], replacementRange: replacementRange)
        case .slash(_, let replacementRange, let items):
            guard items.indices.contains(index) else { return }
            applySlashCommand(items[index], replacementRange: replacementRange)
        }
        dismissInlineSuggestions()
    }

    private func dismissInlineSuggestions() {
        inlineSuggestionContext = nil
        suggestionController.view.isHidden = true
    }

    private func applyTag(_ tag: String, replacementRange: NSRange) {
        replaceText(in: replacementRange, with: "#\(tag)")
        refreshChrome()
        userDidEdit()
    }

    private func applySlashCommand(_ command: SlashCommand, replacementRange: NSRange) {
        replaceText(in: replacementRange, with: "")

        switch command {
        case .heading:
            toggleParagraphKind(.heading(level: 1))
        case .checklist:
            toggleParagraphKind(.checklist(checked: false))
        case .bulletList:
            toggleParagraphKind(.bullet)
        case .orderedList:
            toggleParagraphKind(.ordered(index: 1))
        case .divider:
            insertTextAtSelection("---")
            userDidEdit()
        }
    }

    private func replaceText(in range: NSRange, with replacement: String, attributes: [NSAttributedString.Key: Any]? = nil) {
        guard let storage = editorTextView.textStorage else { return }
        suppressTextDidChange = true
        storage.replaceCharacters(
            in: range,
            with: NSAttributedString(string: replacement, attributes: attributes ?? editorTextView.typingAttributes)
        )
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: range.location + replacement.utf16.count, length: 0))
        scrollSelectionToVisible()
        updateTypingAttributesFromInsertionPoint()
    }

    private func insertTextAtSelection(_ text: String, attributes: [NSAttributedString.Key: Any]? = nil) {
        replaceText(in: editorTextView.selectedRange(), with: text, attributes: attributes)
    }

    private func commitPendingTagIfNeeded(insertingTrailingText trailingText: String? = nil) -> Bool {
        guard let token = currentTagToken() else { return false }
        let normalized = token.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        applyTag(normalized, replacementRange: token.replacementRange)
        if let trailingText {
            let neutralAttributes = neutralTypingAttributesForCurrentLine()
            insertTextAtSelection(trailingText, attributes: neutralAttributes)
            editorTextView.typingAttributes = neutralAttributes
        }
        return true
    }

    private var isSuggestionVisible: Bool {
        !suggestionController.view.isHidden
    }

    private func positionSuggestionView(for context: InlineSuggestionContext) {
        guard let host = shellContentView else { return }

        let anchorRect = editorTextView.convert(caretRectInWindow(for: editorTextView), to: host)
        let size = suggestionController.preferredContentSize
        var origin = NSPoint(x: anchorRect.maxX + 4, y: anchorRect.maxY - size.height + 14)

        switch context {
        case .tags:
            origin.x = anchorRect.maxX + 4
            origin.y = anchorRect.maxY - size.height + 12
        case .slash:
            origin.x = anchorRect.minX
            origin.y = anchorRect.minY - size.height - 6
        }

        origin.x = min(max(origin.x, 4), max(host.bounds.width - size.width - 4, 4))
        origin.y = min(max(origin.y, 4), max(host.bounds.height - size.height - 4, 4))

        suggestionController.view.frame = NSRect(origin: origin, size: size)
        suggestionController.view.isHidden = false
    }

    private func neutralTypingAttributesForCurrentLine() -> [NSAttributedString.Key: Any] {
        guard let storage = editorTextView.textStorage, storage.length > 0 else {
            return theme.baseAttributes(for: .paragraph)
        }

        let lineRange = visibleLineRangeForSelection()
        let kind = MarkdownRichTextCodec.paragraphKind(at: lineRange, in: storage)
        var attributes = theme.baseAttributes(for: kind)
        attributes.removeValue(forKey: .qmTag)
        return attributes
    }

    private func scrollSelectionToVisible() {
        guard let layoutManager = editorTextView.layoutManager,
              let textContainer = editorTextView.textContainer else {
            editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
    }

    private func toggleChecklistIfNeeded(atCharacterIndex index: Int) -> Bool {
        guard let storage = editorTextView.textStorage,
              storage.length > 0 else { return false }

        let safeIndex = min(max(index, 0), max(storage.length - 1, 0))
        let string = storage.string as NSString
        let paragraphRange = string.paragraphRange(for: NSRange(location: safeIndex, length: 0))
        let visibleRange = NSRange(location: paragraphRange.location, length: max(paragraphRange.length - (string.substring(with: paragraphRange).hasSuffix("\n") ? 1 : 0), 0))
        let kind = MarkdownRichTextCodec.paragraphKind(at: visibleRange, in: storage)

        guard case .checklist(let checked) = kind else { return false }
        let prefixRange = NSRange(location: visibleRange.location, length: min(kind.prefixLength, visibleRange.length))
        guard NSLocationInRange(safeIndex, prefixRange) else { return false }

        let contentRange = MarkdownRichTextCodec.visibleContentRange(for: visibleRange, in: storage, kind: kind)
        let inlineMarkdown = MarkdownRichTextCodec.serializeVisibleContent(range: contentRange, in: storage, paragraphKind: kind, theme: theme)
        let replacement = MarkdownRichTextCodec.renderLine(
            MarkdownRichTextCodec.markdownLine(for: .checklist(checked: !checked), inlineContent: inlineMarkdown),
            theme: theme
        )

        suppressTextDidChange = true
        storage.replaceCharacters(in: visibleRange, with: replacement)
        suppressTextDidChange = false
        editorTextView.setSelectedRange(NSRange(location: min(visibleRange.location + replacement.length, storage.length), length: 0))
        userDidEdit()
        return true
    }

    private func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        guard !needle.isEmpty else { return true }
        var needleIndex = needle.startIndex

        for character in haystack where needleIndex < needle.endIndex {
            if character == needle[needleIndex] {
                needle.formIndex(after: &needleIndex)
            }
        }

        return needleIndex == needle.endIndex
    }

    private func levenshteinDistance(between lhs: String, and rhs: String) -> Int? {
        guard !lhs.isEmpty, !rhs.isEmpty else { return nil }
        let left = Array(lhs)
        let right = Array(rhs)
        var previous = Array(0...right.count)

        for (leftIndex, leftChar) in left.enumerated() {
            var current = [leftIndex + 1]
            current.reserveCapacity(right.count + 1)

            for (rightIndex, rightChar) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftChar == rightChar ? 0 : 1)
                current.append(min(insertion, deletion, substitution))
            }

            previous = current
        }

        return previous.last
    }

    private func makeToolbarButton(for action: ToolbarAction) -> HoverToolbarButton {
        let button = HoverToolbarButton(frame: .zero)
        button.title = action.title ?? ""
        button.target = self
        button.action = #selector(toolbarButtonPressed(_:))
        button.tag = action.rawValue
        button.toolTip = action.toolTip
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 30).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true

        if let symbolName = action.symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: action.toolTip)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
            button.imagePosition = .imageOnly
        }

        return button
    }

    @objc
    private func toolbarButtonPressed(_ sender: NSButton) {
        guard let action = ToolbarAction(rawValue: sender.tag) else { return }

        switch action {
        case .heading:
            toggleParagraphKind(.heading(level: 1))
        case .bold:
            toggleInlineFontTrait(.boldFontMask)
        case .italic:
            toggleInlineFontTrait(.italicFontMask)
        case .strikethrough:
            applyStrikethrough()
        case .underline:
            applyUnderline()
        case .checklist:
            toggleParagraphKind(.checklist(checked: false))
        case .orderedList:
            toggleParagraphKind(.ordered(index: 1))
        case .bulletList:
            toggleParagraphKind(.bullet)
        }
    }

    @objc
    private func removeTagPressed(_ sender: NSButton) {
        guard let rawTag = sender.identifier?.rawValue else { return }
        activeTags.removeAll { $0.caseInsensitiveCompare(rawTag) == .orderedSame }
        refreshChrome()
        userDidEdit()
    }

    @objc
    private func searchPressed() {
        onRequestSearch()
    }

    private func updateWindowFocusAppearance(isFocused: Bool) {
        toolbarButtons.forEach { $0.isWindowFocused = isFocused }
        saveButton?.isWindowFocused = isFocused
        statusLabel.textColor = NSColor.white.withAlphaComponent(isFocused ? 0.50 : 0.28)
    }

    @objc
    private func cancelPressed() {
        window?.close()
    }

    @objc
    private func savePressed() {
        let markdown = serializedMarkdown()
        let document = MarkdownEditorDocument.parse(editorText: markdown, tags: mergedDocumentTags(from: markdown))

        if document.title.isEmpty && document.body.isEmpty {
            noteStore.deleteDraft(id: currentDraftID)
            window?.close()
            return
        }

        do {
            let previousDraftID = currentDraftID
            let savedURL: URL

            if let fileURL {
                savedURL = try noteStore.updateNote(
                    at: fileURL,
                    title: document.title,
                    body: document.body,
                    tags: document.tags,
                    in: selectedDirectoryURL
                )
            } else {
                savedURL = try noteStore.saveNewNote(
                    title: document.title,
                    body: document.body,
                    tags: document.tags,
                    in: selectedDirectoryURL
                )
            }

            fileURL = savedURL
            selectedDirectoryURL = savedURL.deletingLastPathComponent()
            noteStore.deleteDraft(id: previousDraftID)
            noteStore.deleteDraft(id: currentDraftID)
            isDirty = false
            onSave(savedURL)
            window?.close()
        } catch {
            presentErrorAlert(message: "Failed to save note", details: error.localizedDescription)
        }
    }

    private func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}
