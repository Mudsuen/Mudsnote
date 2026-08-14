import AppKit
import Carbon.HIToolbox
import Foundation
import MudsnoteCore

// MARK: - Nested types

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, WindowOpacityAdjusting, MarkdownTextViewCommands, NSTextViewDelegate {

    enum InlineSuggestionContext {
        case tags(query: String, replacementRange: NSRange, items: [String])
        case slash(query: String, replacementRange: NSRange, items: [SlashCommand])
    }

    enum ToolbarAction: Int, CaseIterable {
        case heading, bold, italic, strikethrough, underline, highlight, checklist, orderedList, bulletList

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
            case .checklist: return "checkmark.square"
            case .orderedList: return "list.number"
            case .bulletList: return "list.bullet"
            case .highlight: return "highlighter"
            default: return nil
            }
        }

        var toolTip: String {
            switch self {
            case .heading: return "一级标题"
            case .bold: return "加粗"
            case .italic: return "斜体"
            case .strikethrough: return "删除线"
            case .underline: return "下划线"
            case .highlight: return "高亮"
            case .checklist: return "待办列表"
            case .orderedList: return "编号列表"
            case .bulletList: return "项目符号列表"
            }
        }

        var keyEquivalent: String { "" }
        var keyModifiers: NSEvent.ModifierFlags { [] }
    }

    // MARK: - Stored properties

    let noteStore: NoteStore
    let floatingWindowID = UUID()
    let onSave: (URL) -> Void
    let onClose: () -> Void
    let onRequestSearch: () -> Void
    let floatingNoteWindows: () -> [FloatingNoteWindowDescriptor]
    let onRequestOpenFloatingNote: (URL) -> Void
    let onRequestActivateFloatingNote: (UUID) -> Void
    let onRequestCloseFloatingNote: (UUID) -> Void
    let onRequestCreateFloatingNote: () -> Void
    let saveDraftSnapshot: @Sendable (DraftSnapshot) throws -> Void
    let deleteDraftSnapshot: @Sendable (String) -> Void
    let draftPersistenceErrorHandler: ((Error) -> Void)?
    lazy var draftPersistenceCoordinator = DraftPersistenceCoordinator(
        save: saveDraftSnapshot,
        delete: deleteDraftSnapshot
    )

    let toolbarButtonWidth: CGFloat = 30
    let toolbarButtonHeight: CGFloat = 26
    let toolbarButtonVisualHeight: CGFloat = 24
    let toolbarButtonSpacing: CGFloat = 0
    let footerGapToSave: CGFloat = 1
    let footerEdgeInset: CGFloat = 2

    let editorTextView = MarkdownTextView(frame: .zero)
    let attachmentQuickLookController = AttachmentQuickLookController()
    let statusLabel = NSTextField(labelWithString: "")
    var toolbarButtons: [HoverToolbarButton] = []
    var toolbarButtonsByAction: [ToolbarAction: HoverToolbarButton] = [:]
    weak var saveButton: NSButton?
    weak var cancelButton: NSButton?
    weak var quickCaptureDirectoryButton: NSButton?
    weak var quickCapturePlaceholderBodyLabel: NSTextField?
    weak var floatingNotePlaceholderLabel: NSTextField?
    weak var floatingNoteTitlebarView: NSView?
    weak var floatingNoteBrowseButton: NSButton?
    var floatingNoteTitlebarChromeViews: [NSView] = []
    var activeFloatingNoteURL: URL?
    var floatingNoteBrowserController: FloatingNoteBrowserController?

    var fileURL: URL?
    var sourceContentsAtLoad: String?
    var selectedDirectoryURL: URL
    var observers: [NSObjectProtocol] = []
    var autosaveTimer: Timer?
    var isDirty = false
    var draftContentRevision = 0
    var draftPersistenceGeneration = 0
    var suppressAutosave = false
    var suppressTextDidChange = false
    var currentPanelOpacity: Double
    var activeTags: [String] = []
    var lastEditorSelectionForToolbarAction: NSRange?
    var activeToolbarActionSelection: NSRange?
    let suggestionController = SuggestionPopoverController()
    var slashCommandInputSourceSession: any SlashCommandInputSourceSessioning = SlashCommandInputSourceSession()
    var inlineSuggestionContext: InlineSuggestionContext?
    var knownTagsForSuggestions: [String]?
    var tagSuggestionTask: Task<Void, Never>?
    var linkEditorSheetController: LinkEditorSheetController?
    weak var backdropView: GradientBackdropView?
    weak var shellContentView: NSView?
    weak var overlayScrollIndicator: ScrollIndicatorOverlay?
    let initialWindowFrame: NSRect?
    let draftIDOverride: String?
    let saveShortcut: HotKeySpec?
    let showsSaveButton: Bool
    let remembersWindowFrame: ((NSRect) -> Void)?
    let onRequestOpenMarkdownDocument: (URL) -> Void
    let onRequestPreferences: () -> Void
    var hasPresentedWindow = false
    var didCloseWindow = false

    lazy var theme = MarkdownEditorTheme(
        textColor: panelPrimaryTextColor(),
        mutedTextColor: panelSecondaryTextColor(),
        accentColor: panelAccentColor(),
        bodyFont: NSFont.systemFont(ofSize: 14, weight: .regular),
        boldFont: NSFont.systemFont(ofSize: 14, weight: .bold),
        italicFont: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 14, weight: .regular), toHaveTrait: .italicFontMask),
        codeFont: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
    )

    // MARK: - Init

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
        onRequestSearch: @escaping () -> Void,
        floatingNoteWindows: @escaping () -> [FloatingNoteWindowDescriptor] = { [] },
        onRequestOpenFloatingNote: @escaping (URL) -> Void = { _ in },
        onRequestActivateFloatingNote: @escaping (UUID) -> Void = { _ in },
        onRequestCloseFloatingNote: @escaping (UUID) -> Void = { _ in },
        onRequestCreateFloatingNote: @escaping () -> Void = {},
        onRequestOpenMarkdownDocument: @escaping (URL) -> Void = { _ in },
        saveDraftSnapshot: (@Sendable (DraftSnapshot) throws -> Void)? = nil,
        deleteDraftSnapshot: (@Sendable (String) -> Void)? = nil,
        draftPersistenceErrorHandler: ((Error) -> Void)? = nil,
        onRequestPreferences: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.currentPanelOpacity = panelOpacity
        self.fileURL = fileURL
        if draftIDOverride == "floating-note" {
            self.activeFloatingNoteURL = fileURL
        }
        self.initialWindowFrame = initialWindowFrame
        self.draftIDOverride = draftIDOverride
        self.saveShortcut = saveShortcut
        self.showsSaveButton = showsSaveButton
        self.remembersWindowFrame = remembersWindowFrame
        self.selectedDirectoryURL = fileURL?.deletingLastPathComponent()
            ?? ((draftIDOverride == "floating-note" || draftIDOverride == "quick-capture")
                ? noteStore.preferredInboxDirectory
                : noteStore.notesDirectory)
        self.onSave = onSave
        self.onClose = onClose
        self.onRequestSearch = onRequestSearch
        self.floatingNoteWindows = floatingNoteWindows
        self.onRequestOpenFloatingNote = onRequestOpenFloatingNote
        self.onRequestActivateFloatingNote = onRequestActivateFloatingNote
        self.onRequestCloseFloatingNote = onRequestCloseFloatingNote
        self.onRequestCreateFloatingNote = onRequestCreateFloatingNote
        self.onRequestOpenMarkdownDocument = onRequestOpenMarkdownDocument
        self.saveDraftSnapshot = saveDraftSnapshot ?? { @Sendable in try noteStore.saveDraft($0) }
        self.deleteDraftSnapshot = deleteDraftSnapshot ?? { @Sendable in noteStore.deleteDraft(id: $0) }
        self.draftPersistenceErrorHandler = draftPersistenceErrorHandler
        self.onRequestPreferences = onRequestPreferences

        let window = QuickEntryPanel(size: NSSize(width: 412, height: 314))
        window.isReleasedWhenClosed = false
        if let windowLevel {
            window.level = windowLevel
        }

        super.init(window: window)
        window.delegate = self
        window.onCommandF = { [weak self] in self?.searchPressed() }
        window.onCommandComma = { [weak self] in self?.onRequestPreferences() }
        window.onEscape = { [weak self] in self?.cancelPressed() }
        window.onLeftMouseDownPreflight = { [weak self] _ in
            self?.rememberEditorSelectionForToolbarActions()
        }
        window.onStandardEditCommand = { [weak self] selector in self?.performStandardEditCommand(selector) ?? false }
        window.onEditorCommand = { [weak self] event in self?.handleShortcutEvent(event) ?? false }

        configureSuggestionPopover()
        buildUI()
        configureObservers()
        loadInitialContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public interface

    func showWindowAndFocus() {
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

        let targetFrame = window.frame
        let targetAlpha = windowAlphaValue(for: currentPanelOpacity)
        let shouldAnimateReveal = !window.isVisible && draftIDOverride == "quick-capture"

        if shouldAnimateReveal {
            prepareRevealAnimation(window: window)
        } else {
            window.alphaValue = targetAlpha
        }

        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        if shouldAnimateReveal {
            performRevealAnimation(window: window, targetFrame: targetFrame, targetAlpha: targetAlpha)
        }

        window.makeFirstResponder(editorTextView)
        editorTextView.setSelectedRange(NSRange(location: editorTextView.string.utf16.count, length: 0))
    }

    func hasMeaningfulUnsavedContent() -> Bool {
        let document = currentDocument()
        return !document.title.isEmpty || !document.body.isEmpty || !document.tags.isEmpty
    }

    var isWindowClosed: Bool { didCloseWindow }

    func rememberCurrentWindowFrame() {
        guard let frame = window?.frame else { return }
        remembersWindowFrame?(frame)
    }

    func hideWindowForToggle() {
        rememberCurrentWindowFrame()
        window?.orderOut(nil)
    }

    func updatePanelOpacity(_ opacity: Double) {
        currentPanelOpacity = opacity
        window?.alphaValue = windowAlphaValue(for: opacity)
        backdropView?.updatePanelOpacity(opacity)
    }

    // MARK: - Computed

    var currentDraftID: String {
        if isFloatingNoteMode, let activeFloatingNoteURL {
            return "floating-edit-" + sha256Hex(activeFloatingNoteURL.path)
        }
        if let draftIDOverride { return draftIDOverride }
        if let fileURL { return "edit-" + sha256Hex(fileURL.path) }
        return "quick-capture"
    }

    var isQuickCaptureMode: Bool {
        draftIDOverride == "quick-capture" && fileURL == nil
    }

    var isFloatingNoteMode: Bool {
        draftIDOverride == "floating-note"
    }

    // MARK: - Window delegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        prepareForApplicationTermination()
    }

    func windowWillClose(_ notification: Notification) {
        didCloseWindow = true
        tagSuggestionTask?.cancel()
        tagSuggestionTask = nil
        attachmentQuickLookController.dismiss()
        rememberCurrentWindowFrame()
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

    func windowDidMove(_ notification: Notification) { rememberCurrentWindowFrame() }
    func windowDidResize(_ notification: Notification) { rememberCurrentWindowFrame() }

    // MARK: - MarkdownTextViewCommands

    func markdownTextViewInsertNewline(_ textView: MarkdownTextView) {
        if commitPendingTagIfNeeded(insertingTrailingText: "\n") { return }
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

    func markdownTextView(_ textView: MarkdownTextView, handleKeyDown event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard event.keyCode == UInt16(kVK_Space),
              modifiers.isEmpty,
              let attachment = textView.fileAttachmentReferenceNearSelection() else {
            return false
        }
        return previewAttachment(atPath: attachment.path)
    }

    func markdownTextViewToggleBold(_ textView: MarkdownTextView) { toggleInlineFontTrait(.boldFontMask) }
    func markdownTextViewToggleItalic(_ textView: MarkdownTextView) { toggleInlineFontTrait(.italicFontMask) }
    func markdownTextViewToggleUnderline(_ textView: MarkdownTextView) { applyUnderline() }
    func markdownTextViewToggleStrikethrough(_ textView: MarkdownTextView) { applyStrikethrough() }
    func markdownTextViewToggleHeading(_ textView: MarkdownTextView) { toggleParagraphKind(.heading(level: 1)) }
    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView) { toggleParagraphKind(.bullet) }
    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView) { toggleParagraphKind(.ordered(index: 1)) }
    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView) { toggleParagraphKind(.checklist(checked: false)) }

    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool {
        toggleChecklistIfNeeded(atCharacterIndex: index)
    }

    func markdownTextView(_ textView: MarkdownTextView, didDoubleClickAttachmentAt index: Int) -> Bool {
        guard
            let storage = textView.textStorage,
            index >= 0,
            index < storage.length,
            let path = storage.attribute(.qmAttachmentFilePath, at: index, effectiveRange: nil) as? String
        else { return false }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        return true
    }

    func markdownTextView(_ textView: MarkdownTextView, didCommandClickLinkAt index: Int) -> Bool {
        guard let link = textView.linkReference(atCharacterIndex: index) else { return false }
        return openMarkdownLink(link)
    }

    @discardableResult
    func configureLinkContextMenu(_ menu: NSMenu, for link: MarkdownLinkReference) -> Bool {
        let openItem = NSMenuItem(title: "打开链接", action: #selector(openLinkMenuItemPressed(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = link
        openItem.isEnabled = markdownLinkDestination(link.url, relativeTo: currentMarkdownDocumentURL) != nil

        let editItem = NSMenuItem(title: "编辑链接...", action: #selector(editLinkMenuItemPressed(_:)), keyEquivalent: "")
        editItem.target = self
        editItem.representedObject = link

        let copyItem = NSMenuItem(title: "复制链接", action: #selector(copyLinkMenuItemPressed(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = link

        let removeItem = NSMenuItem(title: "移除链接", action: #selector(removeLinkMenuItemPressed(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = link

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [openItem, editItem, copyItem, removeItem].reversed() {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    private func openLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        _ = openMarkdownLink(link)
    }

    @objc
    private func editLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        presentLinkEditor(
            title: "编辑链接",
            destination: link.url,
            name: link.label
        ) { [weak self] destination, name in
            self?.applyLinkURL(
                destination,
                label: name.isEmpty ? destination : name,
                to: link
            )
        }
    }

    @objc
    private func copyLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url, forType: .string)
    }

    @objc
    private func removeLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        applyLinkURL(nil, to: link)
    }

    @discardableResult
    private func openMarkdownLink(_ link: MarkdownLinkReference) -> Bool {
        guard let destination = markdownLinkDestination(
            link.url,
            relativeTo: currentMarkdownDocumentURL
        ) else {
            return false
        }
        switch destination {
        case .localMarkdown(let url):
            onRequestOpenMarkdownDocument(url)
        case .external(let url):
            NSWorkspace.shared.open(url)
        }
        return true
    }

    private var currentMarkdownDocumentURL: URL {
        fileURL ?? selectedDirectoryURL.appendingPathComponent(".mudsnote-unsaved.md")
    }

    private func presentLinkEditor(
        title: String,
        destination: String,
        name: String,
        onSubmit: @escaping (String, String) -> Void
    ) {
        guard linkEditorSheetController == nil, let window else { return }
        let controller = LinkEditorSheetController(
            title: title,
            destination: destination,
            name: name,
            onSubmit: onSubmit,
            onDismiss: { [weak self] in
                self?.linkEditorSheetController = nil
                self?.window?.makeFirstResponder(self?.editorTextView)
            }
        )
        linkEditorSheetController = controller
        controller.beginSheet(for: window)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachment attachment: MarkdownAttachmentReference) -> Bool {
        configureAttachmentContextMenu(menu, forAttachmentPath: attachment.path, markdown: attachment.markdown)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachmentPath path: String, markdown: String? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }

        let previewItem = NSMenuItem(title: "快速查看", action: #selector(previewAttachmentMenuItemPressed(_:)), keyEquivalent: " ")
        previewItem.keyEquivalentModifierMask = []
        previewItem.target = self
        previewItem.representedObject = path

        let openItem = NSMenuItem(title: "打开附件", action: #selector(openAttachmentMenuItemPressed(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = path

        let revealItem = NSMenuItem(title: "在 Finder 中显示", action: #selector(revealAttachmentMenuItemPressed(_:)), keyEquivalent: "")
        revealItem.target = self
        revealItem.representedObject = path

        let copyPathItem = NSMenuItem(title: "复制附件路径", action: #selector(copyAttachmentPathMenuItemPressed(_:)), keyEquivalent: "")
        copyPathItem.target = self
        copyPathItem.representedObject = path

        let copyMarkdownItem = NSMenuItem(title: "复制 Markdown 链接", action: #selector(copyAttachmentMarkdownMenuItemPressed(_:)), keyEquivalent: "")
        copyMarkdownItem.target = self
        copyMarkdownItem.representedObject = markdown
        copyMarkdownItem.isEnabled = !(markdown?.isEmpty ?? true)

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [copyPathItem, copyMarkdownItem, revealItem, openItem, previewItem] {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    private func previewAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        attachmentQuickLookController.preview(url)
    }

    @discardableResult
    func previewAttachment(atPath path: String) -> Bool {
        attachmentQuickLookController.preview(URL(fileURLWithPath: path))
    }

    @objc
    private func openAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc
    private func revealAttachmentMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = attachmentURL(from: sender) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc
    private func copyAttachmentPathMenuItemPressed(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc
    private func copyAttachmentMarkdownMenuItemPressed(_ sender: NSMenuItem) {
        guard let markdown = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    private func attachmentURL(from sender: NSMenuItem) -> URL? {
        guard let path = sender.representedObject as? String else { return nil }
        return URL(fileURLWithPath: path)
    }

}
