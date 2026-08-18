import AppKit
import Foundation
import MudsnoteCore

@MainActor
final class SearchResultCellView: NSTableCellView {
    let titleLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(wrappingLabelWithString: "")
    let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = panelPrimaryTextColor()

        snippetLabel.font = .systemFont(ofSize: 12)
        snippetLabel.textColor = panelSecondaryTextColor()
        snippetLabel.maximumNumberOfLines = 2

        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = panelTertiaryTextColor()

        let stack = NSStackView(views: [titleLabel, snippetLabel, pathLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)

        addSubview(stack)
        pin(stack, to: self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class SearchWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, WindowOpacityAdjusting {
    private let noteStore: NoteStore
    private let onOpen: (URL) -> Void
    private let onClose: () -> Void

    let searchField = NSSearchField(string: "")
    let scopePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    let filterPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let infoLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private var results: [NoteSearchResult] = []
    private lazy var searchController = DebouncedNoteSearchController(noteStore: noteStore, limit: 60)
    private var currentPanelOpacity: Double
    private weak var backdropView: GradientBackdropView?
    private weak var searchSurfaceView: NSView?
    private weak var resultSurfaceView: NSView?

    var resultTitlesForTesting: [String] { results.map(\.title) }
    var searchInfoForTesting: String { infoLabel.stringValue }

    init(noteStore: NoteStore, onOpen: @escaping (URL) -> Void, onClose: @escaping () -> Void) {
        self.noteStore = noteStore
        self.onOpen = onOpen
        self.onClose = onClose
        self.currentPanelOpacity = noteStore.panelOpacity

        let window = QuickEntryPanel(size: NSSize(width: 860, height: 480))
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.onEscape = { [weak self] in
            self?.closePressed()
        }
        buildUI()
        scheduleSearch(delay: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showWindowAndFocus() {
        showWindow(nil)
        guard let window else { return }
        positionPanelNearTopCenter(window, topMargin: 96)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        searchField.selectText(nil)
    }

    func windowWillClose(_ notification: Notification) {
        searchController.cancel(invalidateSession: true)
        onClose()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let backdrop = GradientBackdropView(frame: contentView.bounds, panelOpacity: currentPanelOpacity)
        contentView.addSubview(backdrop)
        pin(backdrop, to: contentView)
        backdropView = backdrop

        let shellContent = NSView()
        backdrop.addSubview(shellContent)
        pin(shellContent, to: backdrop, insets: .init(top: 20, left: 22, bottom: 20, right: 22))

        let badge = NSTextField(labelWithString: "搜索")
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = panelSecondaryTextColor()

        let title = NSTextField(labelWithString: "搜索 Markdown 笔记")
        title.font = .systemFont(ofSize: 26, weight: .bold)
        title.textColor = panelPrimaryTextColor()

        searchField.placeholderString = "搜索标题或正文"
        searchField.font = .systemFont(ofSize: 18)
        searchField.focusRingType = .none
        searchField.target = self
        searchField.action = #selector(openSelectedResult)
        searchField.delegate = self

        let searchSurface = makeModernSurface(
            content: insetted(searchField, padding: .init(top: 12, left: 14, bottom: 12, right: 14)),
            cornerRadius: 22,
            tintColor: panelAccentColor().withAlphaComponent(0.18),
            alpha: primarySurfaceAlpha(for: currentPanelOpacity)
        )
        searchSurfaceView = searchSurface

        configureSearchOptions()
        let optionsRow = NSStackView(views: [
            NSTextField(labelWithString: "文件夹"),
            scopePopUp,
            NSTextField(labelWithString: "筛选"),
            filterPopUp,
            NSView()
        ])
        optionsRow.orientation = .horizontal
        optionsRow.alignment = .centerY
        optionsRow.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.width = 760
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 74
        tableView.intercellSpacing = NSSize(width: 0, height: 6)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedResult)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        let resultSurface = makeModernSurface(
            content: insetted(scrollView, padding: .init(top: 10, left: 10, bottom: 10, right: 10)),
            cornerRadius: 24,
            tintColor: panelSeparatorColor(alpha: 0.46),
            alpha: secondarySurfaceAlpha(for: currentPanelOpacity)
        )
        resultSurfaceView = resultSurface

        let closeButton = NSButton(title: "关闭", target: self, action: #selector(closePressed))
        closeButton.keyEquivalent = "\u{1b}"
        styleSecondaryButton(closeButton)

        infoLabel.font = .systemFont(ofSize: 12, weight: .medium)
        infoLabel.textColor = panelSecondaryTextColor()

        let footer = NSStackView(views: [infoLabel, NSView(), closeButton])
        footer.orientation = .horizontal
        footer.spacing = 10
        badge.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        searchSurface.translatesAutoresizingMaskIntoConstraints = false
        optionsRow.translatesAutoresizingMaskIntoConstraints = false
        resultSurface.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false

        shellContent.addSubview(badge)
        shellContent.addSubview(title)
        shellContent.addSubview(searchSurface)
        shellContent.addSubview(optionsRow)
        shellContent.addSubview(resultSurface)
        shellContent.addSubview(footer)

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            badge.topAnchor.constraint(equalTo: shellContent.topAnchor, constant: 18),

            title.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            title.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 6),

            searchSurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            searchSurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            searchSurface.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),

            resultSurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            resultSurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            optionsRow.leadingAnchor.constraint(equalTo: searchSurface.leadingAnchor, constant: 4),
            optionsRow.trailingAnchor.constraint(equalTo: searchSurface.trailingAnchor, constant: -4),
            optionsRow.topAnchor.constraint(equalTo: searchSurface.bottomAnchor, constant: 10),

            resultSurface.topAnchor.constraint(equalTo: optionsRow.bottomAnchor, constant: 10),

            footer.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            footer.topAnchor.constraint(equalTo: resultSurface.bottomAnchor, constant: 14),
            footer.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor, constant: -18)
        ])

        updatePanelOpacity(currentPanelOpacity)
    }

    private func configureSearchOptions() {
        scopePopUp.removeAllItems()
        scopePopUp.addItem(withTitle: "所有资料库")
        scopePopUp.lastItem?.representedObject = ""
        for directory in noteStore.preferredDirectories {
            scopePopUp.addItem(withTitle: directory.lastPathComponent)
            scopePopUp.lastItem?.representedObject = directory.standardizedFileURL.path
            scopePopUp.lastItem?.toolTip = directory.path
        }
        if noteStore.searchDefaultScope == .defaultDirectory,
           let index = scopePopUp.itemArray.firstIndex(where: {
               ($0.representedObject as? String) == noteStore.notesDirectory.standardizedFileURL.path
           }) {
            scopePopUp.selectItem(at: index)
        } else {
            scopePopUp.selectItem(at: 0)
        }
        scopePopUp.target = self
        scopePopUp.action = #selector(searchOptionsChanged(_:))

        let filters: [(String, NoteSearchFilter)] = [
            ("全部", .all),
            ("标题", .title),
            ("正文", .body),
            ("标签", .tags),
            ("含附件", .attachments)
        ]
        filterPopUp.removeAllItems()
        for (title, filter) in filters {
            filterPopUp.addItem(withTitle: title)
            filterPopUp.lastItem?.representedObject = filter.rawValue
        }
        filterPopUp.selectItem(at: 0)
        filterPopUp.target = self
        filterPopUp.action = #selector(searchOptionsChanged(_:))
    }

    @objc
    private func searchOptionsChanged(_ sender: Any?) {
        searchController.cancel(invalidateSession: true)
        scheduleSearch(delay: .zero)
    }

    private var selectedSearchRoots: [URL] {
        guard let path = scopePopUp.selectedItem?.representedObject as? String,
              !path.isEmpty else {
            return noteStore.knownSearchRoots()
        }
        return [URL(fileURLWithPath: path, isDirectory: true)]
    }

    private var selectedSearchFilter: NoteSearchFilter {
        guard let rawValue = filterPopUp.selectedItem?.representedObject as? String else {
            return .all
        }
        return NoteSearchFilter(rawValue: rawValue) ?? .all
    }

    func controlTextDidChange(_ obj: Notification) {
        scheduleSearch()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let result = results[row]
        let identifier = NSUserInterfaceItemIdentifier("SearchResultCell")

        let cell: SearchResultCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? SearchResultCellView {
            cell = reused
        } else {
            cell = SearchResultCellView()
            cell.identifier = identifier
        }

        cell.titleLabel.stringValue = result.title
        cell.snippetLabel.stringValue = result.snippet
        cell.pathLabel.stringValue = displayPath(result.url)
        return cell
    }

    @objc
    private func openSelectedResult() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard results.indices.contains(row) else { return }
        onOpen(results[row].url)
        window?.close()
    }

    @objc
    private func closePressed() {
        window?.close()
    }

    private func scheduleSearch(delay: Duration = DebouncedNoteSearchController.defaultDelay) {
        let query = searchField.stringValue
        searchController.submit(
            query: query,
            roots: selectedSearchRoots,
            filter: selectedSearchFilter,
            delay: delay,
            onStart: { [weak self] in
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self?.infoLabel.stringValue = "正在搜索…"
            },
            completion: { [weak self] payload in
                guard let self, self.searchField.stringValue == payload.query else { return }
                self.applySearchResults(payload)
            }
        )
    }

    private func applySearchResults(_ payload: DebouncedNoteSearchResults) {
        let selectedPath = results.indices.contains(tableView.selectedRow)
            ? results[tableView.selectedRow].url.standardizedFileURL.path
            : nil
        results = payload.results
        tableView.reloadData()

        if let selectedPath,
           let selectedRow = results.firstIndex(where: {
               $0.url.standardizedFileURL.path == selectedPath
           }) {
            tableView.selectRowIndexes(IndexSet(integer: selectedRow), byExtendingSelection: false)
        } else if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }

        if payload.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            infoLabel.stringValue = results.isEmpty ? "暂无最近笔记" : "\(results.count) 条最近笔记"
        } else {
            infoLabel.stringValue = results.isEmpty
                ? "\(payload.searchRootCount) 个文件夹中无匹配"
                : "\(results.count) 条匹配，来自 \(payload.searchRootCount) 个文件夹"
        }
    }

    func waitForSearchForTesting() async {
        await searchController.waitForCurrentSearchForTesting()
    }

    func updatePanelOpacity(_ opacity: Double) {
        currentPanelOpacity = opacity
        window?.alphaValue = windowAlphaValue(for: opacity)
        backdropView?.updatePanelOpacity(opacity)
        searchSurfaceView?.alphaValue = primarySurfaceAlpha(for: opacity)
        resultSurfaceView?.alphaValue = secondarySurfaceAlpha(for: opacity)
    }
}
