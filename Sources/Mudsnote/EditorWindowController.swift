import AppKit
import Foundation
import MudsnoteCore

// MARK: - Nested types

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate, WindowOpacityAdjusting, MarkdownTextViewCommands, NSTextViewDelegate {

    enum SlashCommand: CaseIterable {
        case heading, checklist, bulletList, orderedList, divider

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

    enum QuickCaptureAction: Int, CaseIterable {
        case tag, checklist, orderedList, bulletList

        var buttonTitle: String {
            switch self {
            case .tag: return "Tags"
            case .checklist: return "Checklist"
            case .orderedList: return "Numbered"
            case .bulletList: return "Bullets"
            }
        }

        var symbolName: String {
            switch self {
            case .tag: return "tag"
            case .checklist: return "checklist"
            case .orderedList: return "list.number"
            case .bulletList: return "list.bullet"
            }
        }

        var toolTip: String {
            switch self {
            case .tag: return "Insert tag"
            case .checklist: return "Checklist"
            case .orderedList: return "Numbered list"
            case .bulletList: return "Bulleted list"
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

    var fileURL: URL?
    var selectedDirectoryURL: URL
    var observers: [NSObjectProtocol] = []
    var autosaveTimer: Timer?
    var isDirty = false
    var suppressAutosave = false
    var suppressTextDidChange = false
    var currentPanelOpacity: Double
    var activeTags: [String] = []
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
        window.onCommandS = { [weak self] in self?.savePressed() }
        window.onCommandF = { [weak self] in self?.searchPressed() }
        window.onEscape = { [weak self] in self?.cancelPressed() }
        window.onLeftMouseDownPreflight = { [weak self] event in self?.preflightQuickCaptureTitleClick(with: event) }
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
        if let draftIDOverride { return draftIDOverride }
        if let fileURL { return "edit-" + sha256Hex(fileURL.path) }
        return "quick-capture"
    }

    var isQuickCaptureMode: Bool {
        draftIDOverride == "quick-capture" && fileURL == nil
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
