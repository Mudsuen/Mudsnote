import AppKit
import Foundation
import MudsnoteCore

// MARK: - Nested types

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, WindowOpacityAdjusting, MarkdownTextViewCommands, NSTextViewDelegate {

    enum SlashCommand: CaseIterable {
        case heading1, heading2, heading3, checklist, bulletList, orderedList, divider
        case aiSummarize, aiFix, aiTodos

        var title: String {
            switch self {
            case .heading1: return "一级标题"
            case .heading2: return "二级标题"
            case .heading3: return "三级标题"
            case .checklist: return "待办列表"
            case .bulletList: return "项目符号列表"
            case .orderedList: return "编号列表"
            case .divider: return "分割线"
            case .aiSummarize: return "AI 总结"
            case .aiFix: return "AI 修正"
            case .aiTodos: return "AI 提取待办"
            }
        }

        var subtitle: String {
            switch self {
            case .heading1, .heading2, .heading3: return "将当前行改为标题"
            case .checklist: return "开始一个待办项"
            case .bulletList: return "开始一个项目符号项"
            case .orderedList: return "开始一个编号项"
            case .divider: return "插入分割线"
            case .aiSummarize: return "总结选中内容或当前笔记"
            case .aiFix: return "修正选中内容或当前段落"
            case .aiTodos: return "提取 Markdown 待办项"
            }
        }

        var searchAliases: [String] {
            switch self {
            case .heading1: return ["heading 1", "h1", "一级标题"]
            case .heading2: return ["heading 2", "h2", "二级标题"]
            case .heading3: return ["heading 3", "h3", "三级标题"]
            case .checklist: return ["todo", "to-do", "checklist", "待办", "清单"]
            case .bulletList: return ["bullet", "bulleted", "list", "项目符号"]
            case .orderedList: return ["numbered", "ordered", "number", "编号"]
            case .divider: return ["divider", "line", "分割线"]
            case .aiSummarize: return ["summarize", "summary", "sum", "tldr", "总结", "摘要"]
            case .aiFix: return ["fix", "proofread", "grammar", "ai fix", "修正", "润色"]
            case .aiTodos: return ["todos", "actions", "tasks", "待办", "行动项"]
            }
        }

        var symbolName: String {
            switch self {
            case .heading1, .heading2, .heading3: return "textformat.size"
            case .checklist: return "checklist"
            case .bulletList: return "list.bullet"
            case .orderedList: return "list.number"
            case .divider: return "minus"
            case .aiSummarize, .aiFix, .aiTodos: return "sparkles"
            }
        }

        var aiActionID: AIActionID? {
            switch self {
            case .aiSummarize: return .summarize
            case .aiFix: return .fix
            case .aiTodos: return .todos
            default: return nil
            }
        }
    }

    enum InlineSuggestionContext {
        case tags(query: String, replacementRange: NSRange, items: [String])
        case slash(query: String, replacementRange: NSRange, items: [SlashCommand])
    }

    enum ToolbarAction: Int, CaseIterable {
        case heading, bold, italic, strikethrough, underline, checklist, orderedList, bulletList

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
            case .checklist: return "待办列表"
            case .orderedList: return "编号列表"
            case .bulletList: return "项目符号列表"
            }
        }

        var keyEquivalent: String { "" }
        var keyModifiers: NSEvent.ModifierFlags { [] }
    }

    enum QuickCaptureAction: Int, CaseIterable {
        case tag, checklist, orderedList, bulletList

        var buttonTitle: String {
            switch self {
            case .tag: return "标签"
            case .checklist: return "待办"
            case .orderedList: return "编号"
            case .bulletList: return "项目符号"
            }
        }

        var symbolName: String {
            switch self {
            case .tag: return "tag"
            case .checklist: return "checkmark.square"
            case .orderedList: return "list.number"
            case .bulletList: return "list.bullet"
            }
        }

        var toolTip: String {
            switch self {
            case .tag: return "插入标签"
            case .checklist: return "待办列表"
            case .orderedList: return "编号列表"
            case .bulletList: return "项目符号列表"
            }
        }

        var linkedToolbarAction: ToolbarAction? {
            switch self {
            case .tag: return nil
            case .checklist: return .checklist
            case .orderedList: return .orderedList
            case .bulletList: return .bulletList
            }
        }
    }

    // MARK: - Stored properties

    let noteStore: NoteStore
    let onSave: (URL) -> Void
    let onClose: () -> Void
    let onRequestSearch: () -> Void

    let toolbarButtonWidth: CGFloat = 30
    let toolbarButtonHeight: CGFloat = 26
    let toolbarButtonSpacing: CGFloat = 0
    let footerGapToSave: CGFloat = 1
    let footerEdgeInset: CGFloat = 2

    let editorTextView = MarkdownTextView(frame: .zero)
    let statusLabel = NSTextField(labelWithString: "")
    var toolbarButtons: [HoverToolbarButton] = []
    var toolbarButtonsByAction: [ToolbarAction: HoverToolbarButton] = [:]
    var quickCaptureButtonsByAction: [ToolbarAction: HoverToolbarButton] = [:]
    weak var saveButton: FocusAwareAccentButton?
    weak var cancelButton: FocusAwareSecondaryButton?
    weak var quickCaptureDirectoryButton: NSButton?
    weak var quickCaptureTitleHost: NSView?
    weak var quickCaptureTitleTextView: FocusableTitleTextView?
    weak var quickCaptureTitlePlaceholderLabel: NSTextField?
    weak var quickCapturePlaceholderBodyLabel: NSTextField?
    weak var quickCaptureTagButton: HoverToolbarButton?
    weak var floatingNotePlaceholderLabel: NSTextField?
    weak var floatingNoteTitlebarView: NSView?
    weak var floatingNoteBrowseButton: HoverToolbarButton?
    var floatingNoteTitlebarChromeViews: [NSView] = []
    var activeFloatingNoteURL: URL?
    var floatingNoteBrowserController: FloatingNoteBrowserController?

    var fileURL: URL?
    var selectedDirectoryURL: URL
    var observers: [NSObjectProtocol] = []
    var autosaveTimer: Timer?
    var isDirty = false
    var suppressAutosave = false
    var suppressTextDidChange = false
    var currentPanelOpacity: Double
    var activeTags: [String] = []
    var lastEditorSelectionForToolbarAction: NSRange?
    var activeToolbarActionSelection: NSRange?
    let suggestionController = SuggestionPopoverController()
    var inlineSuggestionContext: InlineSuggestionContext?
    weak var backdropView: GradientBackdropView?
    weak var shellContentView: NSView?
    weak var overlayScrollIndicator: ScrollIndicatorOverlay?
    let initialWindowFrame: NSRect?
    let draftIDOverride: String?
    let saveShortcut: HotKeySpec?
    let showsSaveButton: Bool
    let remembersWindowFrame: ((NSRect) -> Void)?
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
        onRequestPreferences: @escaping () -> Void
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
        window.onLeftMouseDownPreflight = { [weak self] event in
            self?.rememberEditorSelectionForToolbarActions()
            self?.preflightQuickCaptureTitleClick(with: event)
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

        if isQuickCaptureMode, quickCaptureTitleTextView != nil {
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, window.isVisible else { return }
                self.focusQuickCaptureTitle(placingCaretAtEnd: true)
            }
        } else {
            window.makeFirstResponder(editorTextView)
            editorTextView.setSelectedRange(NSRange(location: editorTextView.string.utf16.count, length: 0))
        }
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
        draftIDOverride == "floating-note" && fileURL == nil
    }

    // MARK: - Window delegate

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

    func markdownTextViewToggleBold(_ textView: MarkdownTextView) { toggleInlineFontTrait(.boldFontMask) }
    func markdownTextViewToggleItalic(_ textView: MarkdownTextView) { toggleInlineFontTrait(.italicFontMask) }
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

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachment attachment: MarkdownAttachmentReference) -> Bool {
        configureAttachmentContextMenu(menu, forAttachmentPath: attachment.path, markdown: attachment.markdown)
    }

    @discardableResult
    func configureAttachmentContextMenu(_ menu: NSMenu, forAttachmentPath path: String, markdown: String? = nil) -> Bool {
        guard FileManager.default.fileExists(atPath: path) else { return false }

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
        for item in [copyPathItem, copyMarkdownItem, revealItem, openItem] {
            menu.insertItem(item, at: 0)
        }
        return true
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

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if textView === quickCaptureTitleTextView {
            switch commandSelector {
            case #selector(insertNewline(_:)), #selector(insertTab(_:)):
                focusQuickCaptureBody()
                return true
            case #selector(cancelOperation(_:)):
                cancelPressed()
                return true
            default:
                return false
            }
        }

        if textView === editorTextView {
            switch commandSelector {
            case #selector(insertBacktab(_:)):
                focusQuickCaptureTitle(placingCaretAtEnd: true)
                return true
            default:
                return false
            }
        }

        return false
    }

    func focusQuickCaptureTitle(placingCaretAtEnd: Bool, clickEvent: NSEvent? = nil) {
        guard let window, let titleTextView = quickCaptureTitleTextView else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !window.isKeyWindow {
            window.makeKeyAndOrderFront(nil)
        }
        guard titleTextView.activateEditing(placingCaretAtEnd: placingCaretAtEnd) else { return }
        if let clickEvent {
            placeQuickCaptureTitleCaret(using: clickEvent, in: titleTextView)
        }
    }

    func focusQuickCaptureBody() {
        guard let window else { return }
        _ = window.makeFirstResponder(nil)
        window.makeFirstResponder(editorTextView)
        editorTextView.scrollRangeToVisible(editorTextView.selectedRange())
    }

    func preflightQuickCaptureTitleClick(with event: NSEvent) {
        guard
            isQuickCaptureMode,
            let window,
            let titleHost = quickCaptureTitleHost,
            let titleTextView = quickCaptureTitleTextView,
            window.firstResponder !== titleTextView
        else {
            return
        }

        let titleFrameInWindow = titleHost.convert(titleHost.bounds, to: nil)
        guard titleFrameInWindow.contains(event.locationInWindow) else { return }
        guard titleTextView.activateEditing(placingCaretAtEnd: false) else { return }
        placeQuickCaptureTitleCaret(using: event, in: titleTextView)
    }

    private func placeQuickCaptureTitleCaret(using event: NSEvent, in textView: NSTextView) {
        guard
            let layoutManager = textView.layoutManager,
            let textContainer = textView.textContainer
        else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let point = textView.convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: max(point.x - textView.textContainerInset.width, 0),
            y: max(point.y - textView.textContainerInset.height, 0)
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let characterIndex = min(
            layoutManager.characterIndexForGlyph(at: glyphIndex),
            textView.string.utf16.count
        )
        textView.setSelectedRange(NSRange(location: characterIndex, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
    }
}
