import AppKit
import Foundation
import MudsnoteCore

private enum LibraryScope: Equatable {
    case all
    case recent
    case inbox
    case tag(String)

    var buttonTitle: String {
        switch self {
        case .all:
            return "所有笔记"
        case .recent:
            return "最近"
        case .inbox:
            return "Inbox"
        case .tag(let tag):
            return "#\(tag)"
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "folder"
        case .recent:
            return "clock"
        case .inbox:
            return "tray"
        case .tag:
            return "number"
        }
    }
}

@MainActor
final class LibraryNoteCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(labelWithString: "")
    let metaLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = panelPrimaryTextColor()

        snippetLabel.font = .systemFont(ofSize: 12)
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.textColor = panelSecondaryTextColor()

        metaLabel.font = .systemFont(ofSize: 11, weight: .medium)
        metaLabel.lineBreakMode = .byTruncatingMiddle
        metaLabel.textColor = panelTertiaryTextColor()

        let stack = NSStackView(views: [titleLabel, snippetLabel, metaLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        addSubview(stack)
        pin(stack, to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class LibraryWindowController: NSWindowController,
    NSWindowDelegate,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSSearchFieldDelegate,
    NSTextFieldDelegate,
    NSTextViewDelegate,
    MarkdownTextViewCommands,
    WindowOpacityAdjusting
{
    let noteStore: NoteStore
    let tableView = NSTableView()
    let searchField = NSSearchField(string: "")
    let titleField = NSTextField(string: "")
    let editorTextView = MarkdownTextView(frame: .zero)
    let statusLabel = NSTextField(labelWithString: "")
    let emptyLabel = NSTextField(labelWithString: "选择或新建一条笔记")

    private let onOpenInSeparateWindow: (URL) -> Void
    private let onSave: (URL) -> Void
    private let onClose: () -> Void
    private var notes: [NoteSearchResult] = []
    private var selectedURL: URL?
    private var selectedTags: [String] = []
    private var isDirty = false
    private var suppressEditorChanges = false
    private var suppressSelectionChanges = false
    private var hasCenteredWindow = false
    private var selectedScope: LibraryScope = .all
    private var sourceButtons: [NSButton] = []
    private var sourceTagNames: [String] = []

    let theme = MarkdownEditorTheme(
        textColor: panelPrimaryTextColor(),
        mutedTextColor: panelSecondaryTextColor(),
        accentColor: panelAccentColor(),
        bodyFont: .systemFont(ofSize: 15, weight: .regular),
        boldFont: .systemFont(ofSize: 15, weight: .bold),
        italicFont: NSFontManager.shared.convert(.systemFont(ofSize: 15, weight: .regular), toHaveTrait: .italicFontMask),
        codeFont: .monospacedSystemFont(ofSize: 14, weight: .medium)
    )

    init(
        noteStore: NoteStore,
        onOpenInSeparateWindow: @escaping (URL) -> Void,
        onSave: @escaping (URL) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.onOpenInSeparateWindow = onOpenInSeparateWindow
        self.onSave = onSave
        self.onClose = onClose

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(MudsnoteBrand.appName) 笔记"
        window.minSize = NSSize(width: 980, height: 560)
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        buildUI()
        reloadNotes(loadFirstIfNeeded: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndFocus() {
        showWindow(nil)
        guard let window else { return }
        if !hasCenteredWindow {
            window.center()
            hasCenteredWindow = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if selectedURL == nil {
            searchField.becomeFirstResponder()
        } else {
            editorTextView.window?.makeFirstResponder(editorTextView)
        }
    }

    func windowWillClose(_ notification: Notification) {
        try? saveCurrentNoteIfNeeded()
        onClose()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(splitView)
        pin(splitView, to: contentView)

        let sourceList = buildSourceList()
        let sidebar = buildSidebar()
        let editor = buildEditor()
        splitView.addArrangedSubview(sourceList)
        splitView.addArrangedSubview(sidebar)
        splitView.addArrangedSubview(editor)
        sourceList.widthAnchor.constraint(equalToConstant: 220).isActive = true
        sidebar.widthAnchor.constraint(equalToConstant: 320).isActive = true
    }

    private func buildSourceList() -> NSView {
        let sourceList = NSVisualEffectView()
        sourceList.material = .sidebar
        sourceList.blendingMode = .withinWindow
        sourceList.state = .active
        sourceList.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "资料库")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = panelPrimaryTextColor()

        let primaryStack = NSStackView()
        primaryStack.orientation = .vertical
        primaryStack.spacing = 4

        sourceButtons.removeAll()
        for scope in [LibraryScope.all, .recent, .inbox] {
            let button = makeScopeButton(scope, tag: sourceButtons.count)
            sourceButtons.append(button)
            primaryStack.addArrangedSubview(button)
        }

        sourceTagNames = noteStore.knownTags(limit: 12)
        let tagHeader = NSTextField(labelWithString: "标签")
        tagHeader.font = .systemFont(ofSize: 11, weight: .bold)
        tagHeader.textColor = panelTertiaryTextColor()

        let tagStack = NSStackView()
        tagStack.orientation = .vertical
        tagStack.spacing = 4
        for (index, tag) in sourceTagNames.enumerated() {
            let button = makeScopeButton(.tag(tag), tag: 100 + index)
            sourceButtons.append(button)
            tagStack.addArrangedSubview(button)
        }

        let stack = NSStackView(views: [title, primaryStack, tagHeader, tagStack, NSView()])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 14, bottom: 14, right: 12)
        sourceList.addSubview(stack)
        pin(stack, to: sourceList)
        refreshSourceSelection()

        return sourceList
    }

    private func buildSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "笔记")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = panelPrimaryTextColor()

        let newButton = makeIconButton(symbolName: "square.and.pencil", toolTip: "新建笔记", action: #selector(newNotePressed))

        let header = NSStackView(views: [title, NSView(), newButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        searchField.placeholderString = "搜索笔记"
        searchField.font = .systemFont(ofSize: 13)
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = 280
        tableView.addTableColumn(column)
        tableView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTable")
        tableView.headerView = nil
        tableView.rowHeight = 72
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
        tableView.backgroundColor = .clear
        tableView.style = .sourceList
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedInSeparateWindow)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        let stack = NSStackView(views: [header, searchField, scrollView])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 14, bottom: 14, right: 12)
        sidebar.addSubview(stack)
        pin(stack, to: sidebar)

        return sidebar
    }

    private func buildEditor() -> NSView {
        let editor = NSView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        titleField.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTitleField")
        titleField.placeholderString = "无标题"
        titleField.font = .systemFont(ofSize: 28, weight: .bold)
        titleField.textColor = panelPrimaryTextColor()
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.delegate = self

        let openButton = NSButton(title: "独立窗口打开", target: self, action: #selector(openSelectedInSeparateWindow))
        styleSecondaryButton(openButton)

        let saveButton = NSButton(title: "保存", target: self, action: #selector(savePressed))
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = [.command]
        styleAccentButton(saveButton)

        let headerActions = NSStackView(views: [openButton, saveButton])
        headerActions.orientation = .horizontal
        headerActions.spacing = 8

        let metadataRow = NSStackView(views: [statusLabel, NSView(), headerActions])
        metadataRow.orientation = .horizontal
        metadataRow.alignment = .centerY
        metadataRow.spacing = 10
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = panelSecondaryTextColor()

        configureEditorTextView()
        let scrollView = EditorScrollView()
        let clipView = EditorClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = editorTextView

        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = panelTertiaryTextColor()
        emptyLabel.alignment = .center

        let bodyContainer = NSView()
        bodyContainer.addSubview(scrollView)
        bodyContainer.addSubview(emptyLabel)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: bodyContainer.centerYAnchor)
        ])

        let stack = NSStackView(views: [titleField, metadataRow, bodyContainer])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 30, bottom: 20, right: 30)
        editor.addSubview(stack)
        pin(stack, to: editor)
        bodyContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        return editor
    }

    private func configureEditorTextView() {
        editorTextView.commandDelegate = self
        editorTextView.delegate = self
        editorTextView.isRichText = true
        editorTextView.importsGraphics = false
        editorTextView.usesFontPanel = false
        editorTextView.isAutomaticDataDetectionEnabled = false
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isAutomaticTextReplacementEnabled = false
        editorTextView.isContinuousSpellCheckingEnabled = noteStore.spellCheckingEnabled
        editorTextView.allowsUndo = true
        editorTextView.font = theme.bodyFont
        editorTextView.backgroundColor = .clear
        editorTextView.drawsBackground = false
        editorTextView.textColor = theme.textColor
        editorTextView.insertionPointColor = theme.accentColor
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainerInset = NSSize(width: 4, height: 8)
        editorTextView.textContainer?.lineFragmentPadding = 0
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
    }

    private func makeIconButton(symbolName: String, toolTip: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = toolTip
        button.bezelStyle = .texturedRounded
        button.controlSize = .large
        return button
    }

    private func makeScopeButton(_ scope: LibraryScope, tag: Int) -> NSButton {
        let button = NSButton(title: scope.buttonTitle, target: self, action: #selector(scopeButtonPressed(_:)))
        button.tag = tag
        button.image = NSImage(systemSymbolName: scope.symbolName, accessibilityDescription: scope.buttonTitle)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.alignment = .left
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.contentTintColor = panelSecondaryTextColor()
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.cornerCurve = .continuous
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return button
    }

    private func refreshSourceSelection() {
        for button in sourceButtons {
            let isSelected = scope(for: button) == selectedScope
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected ? panelAccentColor() : panelSecondaryTextColor()
        }
    }

    private func reloadNotes(selecting preferredURL: URL? = nil, loadFirstIfNeeded: Bool) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedNotes = notesForSelectedScope(limit: 240)
        notes = query.isEmpty ? scopedNotes : filteredNotes(scopedNotes, query: query)

        suppressSelectionChanges = true
        tableView.reloadData()

        let preferredPath = preferredURL?.standardizedFileURL.path
        if let preferredPath,
           let row = notes.firstIndex(where: { $0.url.standardizedFileURL.path == preferredPath }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if loadFirstIfNeeded, !notes.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }

        suppressSelectionChanges = false

        if loadFirstIfNeeded, tableView.selectedRow >= 0 {
            loadSelectedRow()
        } else if selectedURL == nil {
            updateEmptyState()
        }
        refreshSourceSelection()
    }

    private func notesForSelectedScope(limit: Int) -> [NoteSearchResult] {
        switch selectedScope {
        case .all:
            return noteStore.listNotes(limit: limit)
        case .recent:
            return noteStore.listRecentFiles(limit: min(limit, 80)).map { note in
                let loaded = try? noteStore.loadNote(at: note.url)
                return NoteSearchResult(
                    url: note.url,
                    title: note.title,
                    snippet: loaded.map { firstMeaningfulLine(from: $0.body) ?? "" } ?? "",
                    modifiedAt: note.modifiedAt,
                    tags: loaded?.tags ?? []
                )
            }
        case .inbox:
            return noteStore.listNotes(limit: limit).filter { note in
                note.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
                    || note.title.localizedCaseInsensitiveContains("Inbox")
            }
        case .tag(let tag):
            return noteStore.listNotes(limit: limit).filter { note in
                note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }
    }

    private func filteredNotes(_ notes: [NoteSearchResult], query: String) -> [NoteSearchResult] {
        notes.filter { note in
            note.title.localizedCaseInsensitiveContains(query)
                || note.snippet.localizedCaseInsensitiveContains(query)
                || displayPath(note.url).localizedCaseInsensitiveContains(query)
                || note.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private func firstMeaningfulLine(from body: String) -> String? {
        body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        notes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let note = notes[row]
        let identifier = NSUserInterfaceItemIdentifier("LibraryNoteCell")
        let cell: LibraryNoteCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? LibraryNoteCellView {
            cell = reused
        } else {
            cell = LibraryNoteCellView()
            cell.identifier = identifier
        }

        cell.titleLabel.stringValue = note.title.isEmpty ? "无标题" : note.title
        cell.snippetLabel.stringValue = note.snippet.isEmpty ? " " : note.snippet
        cell.metaLabel.stringValue = metadataText(for: note)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionChanges else { return }
        do {
            try saveCurrentNoteIfNeeded()
            loadSelectedRow()
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let object = obj.object as AnyObject? else { return }

        if object === searchField {
            reloadNotes(selecting: selectedURL, loadFirstIfNeeded: false)
            return
        }

        if object === titleField {
            markDirty()
        }
    }

    func textDidChange(_ notification: Notification) {
        markDirty()
    }

    @objc
    private func scopeButtonPressed(_ sender: NSButton) {
        do {
            try saveCurrentNoteIfNeeded()
            selectedScope = scope(for: sender)
            reloadNotes(loadFirstIfNeeded: true)
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    private func scope(for button: NSButton) -> LibraryScope {
        switch button.tag {
        case 0:
            return .all
        case 1:
            return .recent
        case 2:
            return .inbox
        case 100...:
            let index = button.tag - 100
            guard sourceTagNames.indices.contains(index) else { return .all }
            return .tag(sourceTagNames[index])
        default:
            return .all
        }
    }

    @objc
    private func newNotePressed() {
        do {
            try saveCurrentNoteIfNeeded()
            selectedURL = nil
            selectedTags = []
            suppressSelectionChanges = true
            tableView.deselectAll(nil)
            suppressSelectionChanges = false
            applyDocument(title: "", body: "", tags: [])
            isDirty = false
            statusLabel.stringValue = "新笔记"
            updateEmptyState()
            titleField.becomeFirstResponder()
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    @objc
    private func savePressed() {
        do {
            let savedURL = try saveCurrentNote(force: true)
            if let savedURL {
                reloadNotes(selecting: savedURL, loadFirstIfNeeded: false)
            }
        } catch {
            presentErrorAlert(message: "保存失败", details: error.localizedDescription)
        }
    }

    @objc
    private func openSelectedInSeparateWindow() {
        guard let selectedURL else { return }
        onOpenInSeparateWindow(selectedURL)
    }

    private func loadSelectedRow() {
        let row = tableView.selectedRow
        guard notes.indices.contains(row) else {
            updateEmptyState()
            return
        }
        load(note: notes[row])
    }

    private func load(note: NoteSearchResult) {
        do {
            let loaded = try noteStore.loadNote(at: note.url)
            selectedURL = note.url
            applyDocument(title: loaded.title, body: loaded.body, tags: loaded.tags)
            isDirty = false
            statusLabel.stringValue = statusText(for: note)
            updateEmptyState()
        } catch {
            presentErrorAlert(message: "无法打开笔记", details: error.localizedDescription)
        }
    }

    private func applyDocument(title: String, body: String, tags: [String]) {
        suppressEditorChanges = true
        titleField.stringValue = title
        selectedTags = tags
        editorTextView.textStorage?.setAttributedString(MarkdownRichTextCodec.render(markdown: body, theme: theme))
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
        editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        suppressEditorChanges = false
    }

    private func markDirty() {
        guard !suppressEditorChanges else { return }
        isDirty = true
        updateEmptyState()
        statusLabel.stringValue = selectedURL == nil ? "新笔记，未保存" : "已修改"
    }

    private func saveCurrentNoteIfNeeded() throws {
        guard isDirty else { return }
        _ = try saveCurrentNote(force: false)
    }

    @discardableResult
    private func saveCurrentNote(force: Bool) throws -> URL? {
        guard force || isDirty else { return selectedURL }

        let rawTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "无标题" : rawTitle
        guard selectedURL != nil || !title.isEmpty || !body.isEmpty else { return nil }

        let savedURL: URL
        if let selectedURL {
            savedURL = try noteStore.updateNote(at: selectedURL, title: title, body: body, tags: selectedTags)
        } else {
            savedURL = try noteStore.saveNewNote(title: title, body: body, tags: selectedTags)
        }

        selectedURL = savedURL
        isDirty = false
        statusLabel.stringValue = "已保存"
        onSave(savedURL)
        updateEmptyState()
        return savedURL
    }

    private func updateEmptyState() {
        let hasContent = selectedURL != nil
            || !titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !editorTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        emptyLabel.isHidden = hasContent
    }

    private func metadataText(for note: NoteSearchResult) -> String {
        let folder = note.url.deletingLastPathComponent().lastPathComponent
        let tags = note.tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
        if tags.isEmpty {
            return "\(relativeDateFormatter.localizedString(for: note.modifiedAt, relativeTo: Date())) · \(folder)"
        }
        return "\(relativeDateFormatter.localizedString(for: note.modifiedAt, relativeTo: Date())) · \(folder) · \(tags)"
    }

    private func statusText(for note: NoteSearchResult) -> String {
        let folder = note.url.deletingLastPathComponent().lastPathComponent
        return "\(dateFormatter.string(from: note.modifiedAt)) · \(folder)"
    }

    private func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }

    func updatePanelOpacity(_ opacity: Double) {
        window?.alphaValue = 1
    }

    func markdownTextViewInsertNewline(_ textView: MarkdownTextView) {
        textView.insertText("\n", replacementRange: textView.selectedRange())
    }

    func markdownTextView(_ textView: MarkdownTextView, shouldInterceptInsertedText text: String) -> Bool {
        false
    }

    func markdownTextViewToggleBold(_ textView: MarkdownTextView) {}
    func markdownTextViewToggleItalic(_ textView: MarkdownTextView) {}
    func markdownTextViewToggleHeading(_ textView: MarkdownTextView) {}
    func markdownTextViewToggleBulletList(_ textView: MarkdownTextView) {}
    func markdownTextViewToggleOrderedList(_ textView: MarkdownTextView) {}
    func markdownTextViewToggleChecklist(_ textView: MarkdownTextView) {}

    func markdownTextView(_ textView: MarkdownTextView, didClickCharacterAt index: Int) -> Bool {
        false
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
