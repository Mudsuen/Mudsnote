import AppKit
import Foundation
import MudsnoteCore

private enum LibraryScope: Equatable {
    case all
    case recent
    case inbox
    case folder(URL)
    case tag(String)
    case trash

    var buttonTitle: String {
        switch self {
        case .all:
            return "所有笔记"
        case .recent:
            return "最近"
        case .inbox:
            return "Inbox"
        case .folder(let url):
            return url.lastPathComponent.isEmpty ? "Notes" : url.lastPathComponent
        case .tag(let tag):
            return "#\(tag)"
        case .trash:
            return "最近删除"
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
        case .folder:
            return "folder"
        case .tag:
            return "number"
        case .trash:
            return "trash"
        }
    }
}

private enum LibraryNoteListRow {
    case group(title: String)
    case note(NoteSearchResult)

    var note: NoteSearchResult? {
        guard case .note(let note) = self else { return nil }
        return note
    }
}

private enum LibraryActionError: LocalizedError {
    case noFolderSelected
    case noNoteSelected

    var errorDescription: String? {
        switch self {
        case .noFolderSelected:
            return "没有选中文件夹"
        case .noNoteSelected:
            return "没有选中笔记"
        }
    }
}

@MainActor
final class LibraryGroupHeaderCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        titleLabel.alignment = .left
        titleLabel.textColor = panelPrimaryTextColor()

        snippetLabel.font = .systemFont(ofSize: 12)
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.alignment = .left
        snippetLabel.textColor = panelSecondaryTextColor()

        metaLabel.font = .systemFont(ofSize: 11, weight: .medium)
        metaLabel.lineBreakMode = .byTruncatingMiddle
        metaLabel.alignment = .left
        metaLabel.textColor = panelTertiaryTextColor()

        let stack = NSStackView(views: [titleLabel, snippetLabel, metaLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        addSubview(stack)
        pin(stack, to: self)
        for label in [titleLabel, snippetLabel, metaLabel] {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class LibraryNoteRowView: NSTableRowView {
    var isGroupRow = false

    override func drawSelection(in dirtyRect: NSRect) {
        guard !isGroupRow else { return }
        let selectionRect = bounds.insetBy(dx: 7, dy: 2)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedRed: 0.55, green: 0.43, blue: 0.08, alpha: 0.95).setFill()
        path.fill()
    }
}

@MainActor
final class LibraryWindowController: NSWindowController,
    NSWindowDelegate,
    NSToolbarDelegate,
    NSToolbarItemValidation,
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

    private static let toolbarIdentifier = NSToolbar.Identifier("mudsnote.library.toolbar")
    private static let addFolderToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.add-folder")
    private static let toggleSidebarToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.toggle-sidebar")
    private static let newNoteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.new-note")
    private static let openSeparateToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.open-separate")
    private static let moveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.move")
    private static let saveToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.save")
    private static let deleteToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.delete")
    private static let restoreToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.restore")
    private static let searchToolbarItemIdentifier = NSToolbarItem.Identifier("mudsnote.library.toolbar.search")

    private let onOpenInSeparateWindow: (URL) -> Void
    private let onSave: (URL) -> Void
    private let onClose: () -> Void
    private var notes: [NoteSearchResult] = []
    private var listRows: [LibraryNoteListRow] = []
    private var selectedURL: URL?
    private var selectedTags: [String] = []
    private var isDirty = false
    private var suppressEditorChanges = false
    private var suppressSelectionChanges = false
    private var hasCenteredWindow = false
    private var selectedScope: LibraryScope = .all
    private var sourceButtons: [NSButton] = []
    private var sourceCountLabels: [Int: NSTextField] = [:]
    private var sourceFolderURLs: [URL] = []
    private var sourceTagNames: [String] = []
    private weak var sourceListView: NSView?
    private let sourcePrimaryStack = NSStackView()
    private let sourceFolderStack = NSStackView()
    private let sourceTagStack = NSStackView()

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
        configureToolbar()
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
        sourceListView = sourceList

        let title = NSTextField(labelWithString: "资料库")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = panelPrimaryTextColor()
        title.alignment = .left

        configureSourceStack(sourcePrimaryStack)
        configureSourceStack(sourceFolderStack)
        configureSourceStack(sourceTagStack)

        let folderHeader = NSTextField(labelWithString: "文件夹")
        folderHeader.font = .systemFont(ofSize: 11, weight: .bold)
        folderHeader.textColor = panelTertiaryTextColor()
        folderHeader.alignment = .left

        let tagHeader = NSTextField(labelWithString: "标签")
        tagHeader.font = .systemFont(ofSize: 11, weight: .bold)
        tagHeader.textColor = panelTertiaryTextColor()
        tagHeader.alignment = .left

        rebuildSourceRows(includeTags: false)

        let stack = NSStackView(views: [title, sourcePrimaryStack, folderHeader, sourceFolderStack, tagHeader, sourceTagStack, NSView()])
        stack.orientation = .vertical
        stack.alignment = .leading
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

        let header = NSStackView(views: [title, NSView()])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = 280
        tableView.addTableColumn(column)
        tableView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTable")
        tableView.headerView = nil
        tableView.rowHeight = 72
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.style = .sourceList
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedInSeparateWindow)
        tableView.menu = makeNoteContextMenu()

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        let stack = NSStackView(views: [header, scrollView])
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

        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textColor = panelSecondaryTextColor()
        statusLabel.alignment = .center

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

        let stack = NSStackView(views: [statusLabel, titleField, bodyContainer])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 30, bottom: 20, right: 30)
        editor.addSubview(stack)
        pin(stack, to: editor)
        bodyContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        return editor
    }

    private func configureToolbar() {
        searchField.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarSearchField")
        searchField.placeholderString = "搜索"
        searchField.font = .systemFont(ofSize: 13)
        searchField.delegate = self
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.frame = NSRect(x: 0, y: 0, width: 250, height: 30)
        searchField.widthAnchor.constraint(equalToConstant: 250).isActive = true
        searchField.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.addFolderToolbarItemIdentifier,
            Self.toggleSidebarToolbarItemIdentifier,
            .space,
            Self.newNoteToolbarItemIdentifier,
            .flexibleSpace,
            Self.openSeparateToolbarItemIdentifier,
            Self.moveToolbarItemIdentifier,
            Self.saveToolbarItemIdentifier,
            Self.deleteToolbarItemIdentifier,
            Self.restoreToolbarItemIdentifier,
            Self.searchToolbarItemIdentifier
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.addFolderToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "添加文件夹",
                symbolName: "folder.badge.plus",
                action: #selector(addFolderPressed)
            )
        case Self.toggleSidebarToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "显示或隐藏资料库",
                symbolName: "sidebar.left",
                action: #selector(toggleSourceListPressed)
            )
        case Self.newNoteToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "新建笔记",
                symbolName: "square.and.pencil",
                action: #selector(newNotePressed)
            )
        case Self.openSeparateToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "独立窗口打开",
                symbolName: "rectangle.on.rectangle",
                action: #selector(openSelectedInSeparateWindow)
            )
        case Self.moveToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "移动到文件夹",
                symbolName: "folder",
                action: #selector(moveSelectedNotePressed(_:))
            )
        case Self.saveToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "保存",
                symbolName: "checkmark.circle",
                action: #selector(savePressed)
            )
        case Self.deleteToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "删除",
                symbolName: "trash",
                action: #selector(deleteSelectedNotePressed)
            )
        case Self.restoreToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "恢复",
                symbolName: "arrow.uturn.backward",
                action: #selector(restoreSelectedNotePressed)
            )
        case Self.searchToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "搜索"
            item.paletteLabel = "搜索"
            item.toolTip = "搜索笔记"
            let wrapper = NSView(frame: NSRect(x: 0, y: 0, width: 270, height: 32))
            wrapper.addSubview(searchField)
            NSLayoutConstraint.activate([
                searchField.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 10),
                searchField.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -10),
                searchField.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
            ])
            item.view = wrapper
            return item
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.openSeparateToolbarItemIdentifier:
            return selectedURL != nil
        case Self.moveToolbarItemIdentifier:
            return selectedURL != nil && selectedScope != .trash && !sourceFolderURLs.isEmpty
        case Self.saveToolbarItemIdentifier:
            return selectedScope != .trash
        case Self.deleteToolbarItemIdentifier:
            return selectedURL != nil
        case Self.restoreToolbarItemIdentifier:
            return selectedScope == .trash && selectedURL != nil
        default:
            return true
        }
    }

    private func toolbarButtonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        item.target = self
        item.action = action
        return item
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

    private func configureSourceStack(_ stack: NSStackView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
    }

    private func rebuildSourceRows(includeTags: Bool) {
        sourceButtons.removeAll()
        sourceCountLabels.removeAll()
        removeArrangedSubviews(from: sourcePrimaryStack)
        removeArrangedSubviews(from: sourceFolderStack)
        removeArrangedSubviews(from: sourceTagStack)

        for scope in [LibraryScope.all, .recent, .inbox, .trash] {
            sourcePrimaryStack.addArrangedSubview(makeScopeRow(scope, tag: sourceButtons.count))
        }

        sourceFolderURLs = noteStore.preferredDirectories
        for (index, folderURL) in sourceFolderURLs.enumerated() {
            sourceFolderStack.addArrangedSubview(makeScopeRow(.folder(folderURL), tag: 10 + index))
        }

        sourceTagNames = includeTags ? noteStore.knownTags(limit: 12) : []
        for (index, tag) in sourceTagNames.enumerated() {
            sourceTagStack.addArrangedSubview(makeScopeRow(.tag(tag), tag: 100 + index))
        }
        tableView.menu = makeNoteContextMenu()
    }

    private func removeArrangedSubviews(from stack: NSStackView) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func makeScopeRow(_ scope: LibraryScope, tag: Int) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        row.widthAnchor.constraint(equalToConstant: 194).isActive = true

        let button = makeScopeButton(scope, tag: tag)
        if case .folder(let folderURL) = scope {
            let menu = makeFolderContextMenu(for: folderURL)
            row.menu = menu
            button.menu = menu
        }
        let overlay = PassthroughOverlayView()
        let countLabel = NSTextField(labelWithString: "")
        countLabel.identifier = NSUserInterfaceItemIdentifier("LibrarySourceCount-\(tag)")
        countLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.textColor = panelTertiaryTextColor()
        countLabel.alignment = .right

        row.addSubview(button)
        row.addSubview(overlay)
        overlay.addSubview(countLabel)

        button.translatesAutoresizingMaskIntoConstraints = false
        overlay.translatesAutoresizingMaskIntoConstraints = false
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            overlay.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: row.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            countLabel.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 44)
        ])

        sourceButtons.append(button)
        sourceCountLabels[tag] = countLabel
        return row
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
        return button
    }

    private func refreshSourceSelection() {
        for button in sourceButtons {
            let isSelected = scope(for: button) == selectedScope
            button.layer?.backgroundColor = isSelected
                ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
                : NSColor.clear.cgColor
            button.contentTintColor = isSelected ? panelAccentColor() : panelSecondaryTextColor()
            sourceCountLabels[button.tag]?.textColor = isSelected ? panelAccentColor() : panelTertiaryTextColor()
        }
    }

    private func refreshSourceCounts() {
        let recentNotes = recentNoteResults(limit: 10_000)
        let recentCount = noteStore.listRecentFiles(limit: 80).count

        for button in sourceButtons {
            let count: Int
            switch scope(for: button) {
            case .all:
                count = recentNotes.count
            case .recent:
                count = recentCount
            case .inbox:
                count = recentNotes.filter { note in
                    note.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
                        || note.title.localizedCaseInsensitiveContains("Inbox")
                }.count
            case .trash:
                count = noteStore.listTrashedNotes(limit: 10_000).count
            case .folder(let url):
                let folderPath = url.standardizedFileURL.path
                count = recentNotes.filter { note in
                    note.url.deletingLastPathComponent().standardizedFileURL.path == folderPath
                }.count
            case .tag(let tag):
                count = recentNotes.filter { note in
                    note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
                }.count
            }
            sourceCountLabels[button.tag]?.stringValue = count > 0 ? String(count) : ""
        }
    }

    private func reloadNotes(selecting preferredURL: URL? = nil, loadFirstIfNeeded: Bool) {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let scopedNotes = notesForSelectedScope(limit: 240)
        notes = query.isEmpty ? scopedNotes : filteredNotes(scopedNotes, query: query)
        listRows = buildGroupedRows(for: notes)

        suppressSelectionChanges = true
        tableView.reloadData()

        let preferredPath = preferredURL?.standardizedFileURL.path
        if let preferredPath,
           let row = rowIndex(for: preferredPath) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else if loadFirstIfNeeded,
                  let firstNoteRow = listRows.firstIndex(where: { $0.note != nil }) {
            tableView.selectRowIndexes(IndexSet(integer: firstNoteRow), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }

        suppressSelectionChanges = false

        if loadFirstIfNeeded, tableView.selectedRow >= 0 {
            loadSelectedRow()
        } else if selectedURL == nil {
            updateEmptyState()
        }
        refreshSourceCounts()
        refreshSourceSelection()
        updateToolbarActionState()
    }

    private func notesForSelectedScope(limit: Int) -> [NoteSearchResult] {
        switch selectedScope {
        case .all:
            return recentNoteResults(limit: limit)
        case .recent:
            return recentNoteResults(limit: min(limit, 80))
        case .inbox:
            return recentNoteResults(limit: limit).filter { note in
                note.url.lastPathComponent.localizedCaseInsensitiveCompare("Inbox.md") == .orderedSame
                    || note.title.localizedCaseInsensitiveContains("Inbox")
            }
        case .trash:
            return noteStore.listTrashedNotes(limit: limit)
        case .folder(let url):
            return noteStore.listNotes(limit: limit, roots: [url])
        case .tag(let tag):
            return noteStore.listNotes(limit: limit).filter { note in
                note.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }
            }
        }
    }

    private func recentNoteResults(limit: Int) -> [NoteSearchResult] {
        noteStore.listRecentFiles(limit: limit).map { note in
            NoteSearchResult(
                url: note.url,
                title: note.title,
                snippet: "",
                modifiedAt: note.modifiedAt,
                tags: []
            )
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

    private func buildGroupedRows(for notes: [NoteSearchResult], now: Date = Date()) -> [LibraryNoteListRow] {
        var rows: [LibraryNoteListRow] = []
        var currentGroup: String?
        for note in notes {
            let group = groupTitle(for: note.modifiedAt, now: now)
            if group != currentGroup {
                rows.append(.group(title: group))
                currentGroup = group
            }
            rows.append(.note(note))
        }
        return rows
    }

    private func rowIndex(for standardizedPath: String) -> Int? {
        listRows.firstIndex { row in
            row.note?.url.standardizedFileURL.path == standardizedPath
        }
    }

    private func note(at row: Int) -> NoteSearchResult? {
        guard listRows.indices.contains(row) else { return nil }
        return listRows[row].note
    }

    private func groupTitle(for date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天"
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfToday).day ?? 0
        if (2...7).contains(daysAgo) {
            return "过去 7 天"
        }
        if (8...30).contains(daysAgo) {
            return "过去 30 天"
        }
        return String(calendar.component(.year, from: date))
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        listRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch listRows[row] {
        case .group(let title):
            let identifier = NSUserInterfaceItemIdentifier("LibraryGroupHeaderCell")
            let cell: LibraryGroupHeaderCellView
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? LibraryGroupHeaderCellView {
                cell = reused
            } else {
                cell = LibraryGroupHeaderCellView()
                cell.identifier = identifier
            }
            cell.titleLabel.stringValue = title
            return cell
        case .note(let note):
            return noteCell(for: note, tableView: tableView)
        }
    }

    private func noteCell(for note: NoteSearchResult, tableView: NSTableView) -> NSView {
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

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard listRows.indices.contains(row) else { return false }
        if case .group = listRows[row] {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        note(at: row) != nil
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if note(at: row) == nil {
            return 54
        }
        return 72
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LibraryNoteRowView()
        rowView.isGroupRow = note(at: row) == nil
        return rowView
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
        case 3:
            return .trash
        case 10..<100:
            let index = button.tag - 10
            guard sourceFolderURLs.indices.contains(index) else { return .all }
            return .folder(sourceFolderURLs[index])
        case 100...:
            let index = button.tag - 100
            guard sourceTagNames.indices.contains(index) else { return .all }
            return .tag(sourceTagNames[index])
        default:
            return .all
        }
    }

    @objc
    private func addFolderPressed() {
        guard let folderName = promptForText(
            title: "新建文件夹",
            message: "输入文件夹名称。",
            placeholder: "新建文件夹",
            defaultValue: "新建文件夹"
        ) else { return }

        do {
            _ = try createLibraryFolder(named: folderName)
        } catch {
            presentErrorAlert(message: "无法新建文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func toggleSourceListPressed() {
        guard let sourceListView else { return }
        sourceListView.isHidden.toggle()
    }

    @objc
    private func newNotePressed() {
        do {
            try saveCurrentNoteIfNeeded()
            if selectedScope == .trash {
                selectedScope = .all
            }
            selectedURL = nil
            selectedTags = []
            suppressSelectionChanges = true
            tableView.deselectAll(nil)
            suppressSelectionChanges = false
            setEditorEditable(true)
            applyDocument(title: "", body: "", tags: [])
            isDirty = false
            statusLabel.stringValue = "新笔记"
            updateEmptyState()
            refreshSourceSelection()
            updateToolbarActionState()
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

    @objc
    private func moveSelectedNotePressed(_ sender: Any?) {
        let menu = makeMoveNoteMenu()
        guard !menu.items.isEmpty else { return }

        if let item = sender as? NSToolbarItem,
           let view = item.view {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.minY - 4), in: view)
        } else if let contentView = window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 40), in: contentView)
        }
    }

    @objc
    private func moveNoteMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL else { return }
        do {
            _ = try moveSelectedNoteForLibrary(to: directory)
        } catch {
            presentErrorAlert(message: "移动失败", details: error.localizedDescription)
        }
    }

    @objc
    private func deleteSelectedNotePressed() {
        guard let url = selectedURL else { return }
        do {
            if selectedScope == .trash {
                try noteStore.permanentlyDeleteTrashedNote(at: url)
            } else {
                try saveCurrentNoteIfNeeded()
                _ = try noteStore.trashNote(at: selectedURL ?? url)
            }
            clearCurrentDocumentAfterRemoval()
            rebuildSourceRows(includeTags: false)
            reloadNotes(loadFirstIfNeeded: true)
        } catch {
            presentErrorAlert(message: "删除失败", details: error.localizedDescription)
        }
    }

    @objc
    private func renameFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL,
              let folderName = promptForText(
                title: "重命名文件夹",
                message: "输入新的文件夹名称。",
                placeholder: "文件夹名称",
                defaultValue: directory.lastPathComponent
              ) else { return }

        do {
            selectedScope = .folder(directory)
            _ = try renameSelectedFolderForLibrary(to: folderName)
        } catch {
            presentErrorAlert(message: "无法重命名文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func deleteFolderMenuItemPressed(_ sender: NSMenuItem) {
        guard let directory = sender.representedObject as? URL,
              confirmDestructiveAction(
                title: "删除文件夹？",
                message: "文件夹中的 Markdown 笔记会移动到最近删除。"
              ) else { return }

        do {
            selectedScope = .folder(directory)
            try deleteSelectedFolderForLibrary()
        } catch {
            presentErrorAlert(message: "无法删除文件夹", details: error.localizedDescription)
        }
    }

    @objc
    private func restoreSelectedNotePressed() {
        guard selectedScope == .trash, let url = selectedURL else { return }
        do {
            let restoredURL = try noteStore.restoreTrashedNote(at: url)
            selectedScope = .all
            clearCurrentDocumentAfterRemoval()
            rebuildSourceRows(includeTags: false)
            reloadNotes(selecting: restoredURL, loadFirstIfNeeded: true)
        } catch {
            presentErrorAlert(message: "恢复失败", details: error.localizedDescription)
        }
    }

    private func loadSelectedRow() {
        let row = tableView.selectedRow
        guard let note = note(at: row) else {
            updateEmptyState()
            return
        }
        load(note: note)
    }

    private func load(note: NoteSearchResult) {
        do {
            let loaded = try noteStore.loadNote(at: note.url)
            selectedURL = note.url
            setEditorEditable(selectedScope != .trash)
            applyDocument(title: loaded.title, body: loaded.body, tags: loaded.tags)
            isDirty = false
            statusLabel.stringValue = statusText(for: note)
            updateEmptyState()
            updateToolbarActionState()
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
        guard !suppressEditorChanges, selectedScope != .trash else { return }
        isDirty = true
        updateEmptyState()
        statusLabel.stringValue = selectedURL == nil ? "新笔记，未保存" : "已修改"
        updateToolbarActionState()
    }

    private func saveCurrentNoteIfNeeded() throws {
        guard isDirty else { return }
        _ = try saveCurrentNote(force: false)
    }

    @discardableResult
    private func saveCurrentNote(force: Bool) throws -> URL? {
        guard force || isDirty else { return selectedURL }
        guard selectedScope != .trash else { return selectedURL }

        let rawTitle = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = MarkdownRichTextCodec.serialize(editorTextView.attributedString(), theme: theme)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "无标题" : rawTitle
        guard selectedURL != nil || !title.isEmpty || !body.isEmpty else { return nil }

        let savedURL: URL
        if let selectedURL {
            savedURL = try noteStore.updateNote(at: selectedURL, title: title, body: body, tags: selectedTags)
        } else {
            savedURL = try noteStore.saveNewNote(
                title: title,
                body: body,
                tags: selectedTags,
                in: targetDirectoryForNewNote()
            )
        }

        selectedURL = savedURL
        isDirty = false
        statusLabel.stringValue = "已保存"
        onSave(savedURL)
        updateEmptyState()
        updateToolbarActionState()
        return savedURL
    }

    @discardableResult
    func createLibraryFolder(named name: String) throws -> URL {
        let folderURL = try noteStore.createFolder(named: name, in: targetDirectoryForNewFolder())
        selectedScope = .folder(folderURL)
        rebuildSourceRows(includeTags: false)
        reloadNotes(loadFirstIfNeeded: true)
        return folderURL
    }

    @discardableResult
    func renameSelectedFolderForLibrary(to name: String) throws -> URL {
        guard case .folder(let folderURL) = selectedScope else {
            throw LibraryActionError.noFolderSelected
        }

        let renamedURL = try noteStore.renamePreferredDirectory(folderURL, to: name)
        selectedScope = .folder(renamedURL)
        rebuildSourceRows(includeTags: false)
        reloadNotes(loadFirstIfNeeded: true)
        return renamedURL
    }

    func deleteSelectedFolderForLibrary() throws {
        guard case .folder(let folderURL) = selectedScope else {
            throw LibraryActionError.noFolderSelected
        }

        _ = try noteStore.trashFolder(at: folderURL)
        selectedScope = .all
        clearCurrentDocumentAfterRemoval()
        rebuildSourceRows(includeTags: false)
        reloadNotes(loadFirstIfNeeded: true)
    }

    @discardableResult
    func moveSelectedNoteForLibrary(to directory: URL) throws -> URL {
        try saveCurrentNoteIfNeeded()
        guard selectedScope != .trash else {
            throw LibraryActionError.noNoteSelected
        }
        guard let selectedURL else {
            throw LibraryActionError.noNoteSelected
        }

        let targetDirectory = directory.standardizedFileURL
        let movedURL = try noteStore.moveNote(at: selectedURL, to: targetDirectory)
        self.selectedURL = movedURL
        selectedScope = .folder(targetDirectory)
        rebuildSourceRows(includeTags: false)
        reloadNotes(selecting: movedURL, loadFirstIfNeeded: true)
        return movedURL
    }

    private func clearCurrentDocumentAfterRemoval() {
        selectedURL = nil
        selectedTags = []
        isDirty = false
        setEditorEditable(selectedScope != .trash)
        applyDocument(title: "", body: "", tags: [])
        updateEmptyState()
    }

    private func setEditorEditable(_ isEditable: Bool) {
        titleField.isEditable = isEditable
        editorTextView.isEditable = isEditable
    }

    private func targetDirectoryForNewNote() -> URL {
        if case .folder(let folderURL) = selectedScope {
            return folderURL
        }
        return noteStore.notesDirectory
    }

    private func targetDirectoryForNewFolder() -> URL {
        if case .folder(let folderURL) = selectedScope {
            return folderURL
        }
        return noteStore.notesDirectory
    }

    private func updateEmptyState() {
        let hasContent = selectedURL != nil
            || !titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !editorTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        emptyLabel.isHidden = hasContent
    }

    private func metadataText(for note: NoteSearchResult) -> String {
        let folder = isTrashURL(note.url) ? "最近删除" : note.url.deletingLastPathComponent().lastPathComponent
        let tags = note.tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
        if tags.isEmpty {
            return "\(relativeDateText(for: note.modifiedAt)) · \(folder)"
        }
        return "\(relativeDateText(for: note.modifiedAt)) · \(folder) · \(tags)"
    }

    private func relativeDateText(for date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 {
            return "刚刚"
        }
        return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func statusText(for note: NoteSearchResult) -> String {
        let folder = isTrashURL(note.url) ? "最近删除" : note.url.deletingLastPathComponent().lastPathComponent
        return "\(dateFormatter.string(from: note.modifiedAt)) · \(folder)"
    }

    private func isTrashURL(_ url: URL) -> Bool {
        let trashPath = noteStore.trashDirectory().standardizedFileURL.path
        let path = url.standardizedFileURL.path
        return path == trashPath || path.hasPrefix(trashPath + "/")
    }

    private func updateToolbarActionState() {
        let isTrashScope = selectedScope == .trash
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.deleteToolbarItemIdentifier:
                item.label = isTrashScope ? "永久删除" : "删除"
                item.paletteLabel = item.label
                item.toolTip = item.label
                item.image = NSImage(
                    systemSymbolName: isTrashScope ? "trash.slash" : "trash",
                    accessibilityDescription: item.label
                )
            case Self.restoreToolbarItemIdentifier:
                item.label = "恢复"
                item.paletteLabel = "恢复"
                item.toolTip = "恢复笔记"
            default:
                continue
            }
        }
        window?.toolbar?.validateVisibleItems()
    }

    private func makeFolderContextMenu(for folderURL: URL) -> NSMenu {
        let menu = NSMenu()

        let renameItem = NSMenuItem(title: "重命名文件夹", action: #selector(renameFolderMenuItemPressed(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = folderURL
        menu.addItem(renameItem)

        let deleteItem = NSMenuItem(title: "删除文件夹", action: #selector(deleteFolderMenuItemPressed(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = folderURL
        deleteItem.isEnabled = folderURL.standardizedFileURL.path != noteStore.notesDirectory.standardizedFileURL.path
        menu.addItem(deleteItem)

        return menu
    }

    private func makeNoteContextMenu() -> NSMenu {
        let menu = NSMenu()

        let moveItem = NSMenuItem(title: "移到文件夹", action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveNoteMenu()
        menu.addItem(moveItem)
        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: "删除", action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    private func makeMoveNoteMenu() -> NSMenu {
        let menu = NSMenu()
        for folderURL in sourceFolderURLs {
            let item = NSMenuItem(title: folderURL.lastPathComponent, action: #selector(moveNoteMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = folderURL
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    private func promptForText(title: String, message: String, placeholder: String, defaultValue: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "确定")
        alert.addButton(withTitle: "取消")

        let field = NSTextField(string: defaultValue)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 28)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func confirmDestructiveAction(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
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
