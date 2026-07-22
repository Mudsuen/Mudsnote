import AppKit
import MudsnoteCore

struct FloatingNoteWindowDescriptor {
    let id: UUID
    let url: URL?
    let title: String
    let subtitle: String
}

@MainActor
final class FloatingNoteBrowserResultCellView: NSTableCellView {
    let marker = NSView()
    let titleLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(labelWithString: "")
    let actionButton = NSButton()
    private var onAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true

        marker.translatesAutoresizingMaskIntoConstraints = false
        marker.wantsLayer = true
        marker.layer?.cornerRadius = 4
        marker.layer?.backgroundColor = panelTertiaryTextColor().cgColor

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.lineBreakMode = .byTruncatingTail

        snippetLabel.font = .systemFont(ofSize: 12, weight: .regular)
        snippetLabel.textColor = panelSecondaryTextColor()
        snippetLabel.lineBreakMode = .byTruncatingTail

        let labels = NSStackView(views: [titleLabel, snippetLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false

        actionButton.isBordered = false
        actionButton.bezelStyle = .regularSquare
        actionButton.imagePosition = .imageOnly
        actionButton.target = self
        actionButton.action = #selector(actionPressed)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(marker)
        addSubview(labels)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            marker.centerYAnchor.constraint(equalTo: centerYAnchor),
            marker.widthAnchor.constraint(equalToConstant: 8),
            marker.heightAnchor.constraint(equalToConstant: 8),

            labels.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 28),
            actionButton.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        subtitle: String,
        isCurrent: Bool,
        isOpen: Bool,
        onAction: @escaping () -> Void
    ) {
        titleLabel.stringValue = title
        snippetLabel.stringValue = subtitle
        marker.layer?.backgroundColor = (isCurrent ? NSColor.systemRed : panelTertiaryTextColor()).cgColor
        let symbolName = isOpen ? "xmark" : "plus"
        actionButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        actionButton.contentTintColor = isOpen ? .systemRed : panelPrimaryTextColor()
        let label = isOpen ? "关闭 \(titleLabel.stringValue)" : "添加 \(titleLabel.stringValue)"
        actionButton.toolTip = label
        actionButton.setAccessibilityLabel(label)
        self.onAction = onAction
    }

    @objc private func actionPressed() {
        onAction?()
    }
}

@MainActor
final class FloatingNoteBrowserPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class FloatingNoteBrowserController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private struct Item {
        let url: URL?
        let title: String
        let subtitle: String
        let openWindowID: UUID?

        var isOpen: Bool { openWindowID != nil }
    }

    private let noteStore: NoteStore
    private let openWindows: () -> [FloatingNoteWindowDescriptor]
    private let onOpen: (URL) -> Void
    private let onActivate: (UUID) -> Void
    private let onClose: (UUID) -> Void
    private let searchField = NSSearchField(string: "")
    private let emptyLabel = NSTextField(labelWithString: "搜索笔记并添加悬浮窗口")
    private let tableView = NSTableView()
    private var items: [Item] = []
    private(set) var presentationCount = 0

    var displayedURLs: [URL] { items.compactMap(\.url) }
    var displayedOpenStates: [Bool] { items.map(\.isOpen) }

    func rowActionButton(at row: Int) -> NSButton? {
        guard items.indices.contains(row) else { return nil }
        return (tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FloatingNoteBrowserResultCellView)?.actionButton
    }

    var selectedWindowID: UUID? {
        didSet { tableView.reloadData() }
    }

    init(
        noteStore: NoteStore,
        selectedWindowID: UUID,
        openWindows: @escaping () -> [FloatingNoteWindowDescriptor],
        onOpen: @escaping (URL) -> Void,
        onActivate: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void
    ) {
        self.noteStore = noteStore
        self.selectedWindowID = selectedWindowID
        self.openWindows = openWindows
        self.onOpen = onOpen
        self.onActivate = onActivate
        self.onClose = onClose

        let panel = FloatingNoteBrowserPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 220),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        super.init(window: panel)
        panel.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(relativeTo anchorView: NSView?, parentWindow: NSWindow?) {
        guard let window else { return }
        presentationCount += 1
        reloadResults()
        if let parentWindow {
            window.level = parentWindow.level
        }

        var proposedOrigin: NSPoint?
        if let anchorView, let parentWindow {
            let anchorRect = anchorView.convert(anchorView.bounds, to: nil)
            let screenRect = parentWindow.convertToScreen(anchorRect)
            proposedOrigin = NSPoint(
                x: screenRect.maxX - window.frame.width,
                y: screenRect.minY - window.frame.height - 8
            )
        } else if let parentWindow {
            proposedOrigin = NSPoint(
                x: parentWindow.frame.maxX - window.frame.width - 12,
                y: parentWindow.frame.maxY - window.frame.height - 30
            )
        }

        if let proposedOrigin {
            window.setFrameOrigin(visibleOrigin(for: window.frame.size, proposed: proposedOrigin, parentWindow: parentWindow))
        }
        if let parentWindow, window.parent !== parentWindow {
            parentWindow.addChildWindow(window, ordered: .above)
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        searchField.selectText(nil)
        DispatchQueue.main.async { [weak self, weak window] in
            window?.makeKeyAndOrderFront(nil)
            self?.searchField.selectText(nil)
            self?.reloadResults()
        }
    }

    func refresh() {
        guard window?.isVisible == true else { return }
        reloadResults()
    }

    func visibleOrigin(for windowSize: NSSize, proposed: NSPoint, parentWindow: NSWindow?) -> NSPoint {
        guard let visibleFrame = parentWindow?.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else {
            return proposed
        }
        let maximumX = max(visibleFrame.minX, visibleFrame.maxX - windowSize.width)
        let maximumY = max(visibleFrame.minY, visibleFrame.maxY - windowSize.height)
        return NSPoint(
            x: min(max(proposed.x, visibleFrame.minX), maximumX),
            y: min(max(proposed.y, visibleFrame.minY), maximumY)
        )
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        window.parent?.removeChildWindow(window)
    }

    func windowDidResignKey(_ notification: Notification) {
        window?.close()
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadResults()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row]
        let identifier = NSUserInterfaceItemIdentifier("FloatingNoteBrowserResultCell")
        let cell: FloatingNoteBrowserResultCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? FloatingNoteBrowserResultCellView {
            cell = reused
        } else {
            cell = FloatingNoteBrowserResultCellView()
            cell.identifier = identifier
        }
        cell.configure(
            title: item.title,
            subtitle: item.subtitle,
            isCurrent: item.openWindowID == selectedWindowID,
            isOpen: item.isOpen,
            onAction: { [weak self] in self?.performAction(for: item) }
        )
        return cell
    }

    @objc private func openSelectedResult() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard items.indices.contains(row) else { return }
        window?.close()
        let item = items[row]
        if let id = item.openWindowID {
            onActivate(id)
        } else if let url = item.url {
            onOpen(url)
        }
    }

    private func performAction(for item: Item) {
        if let id = item.openWindowID {
            onClose(id)
        } else if let url = item.url {
            onOpen(url)
        }
        reloadResults()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let surface = NSVisualEffectView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.material = .hudWindow
        surface.state = .active
        surface.blendingMode = .behindWindow
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 18
        surface.layer?.masksToBounds = true
        contentView.addSubview(surface)
        pin(surface, to: contentView)

        let titleLabel = NSTextField(labelWithString: "悬浮窗口")
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = panelSecondaryTextColor()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(titleLabel)

        searchField.placeholderString = "搜索并添加笔记"
        searchField.font = .systemFont(ofSize: 15, weight: .semibold)
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(searchField)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(divider)

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")))
        tableView.headerView = nil
        tableView.rowHeight = 52
        tableView.intercellSpacing = NSSize(width: 0, height: 3)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedResult)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = tableView
        surface.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = panelSecondaryTextColor()
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            titleLabel.topAnchor.constraint(equalTo: surface.topAnchor, constant: 14),

            searchField.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            searchField.heightAnchor.constraint(equalToConstant: 30),

            divider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),

            scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -10),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -10),

            emptyLabel.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -16),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor)
        ])
    }

    private func reloadResults() {
        let windows = openWindows()
        let openPaths = Set(windows.compactMap { $0.url?.standardizedFileURL.path })
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = query.isEmpty
            ? []
            : noteStore.searchNotes(query: query, limit: .max).filter { !openPaths.contains($0.url.standardizedFileURL.path) }

        items = windows.map {
            Item(url: $0.url, title: $0.title, subtitle: $0.subtitle, openWindowID: $0.id)
        } + candidates.map {
            Item(
                url: $0.url,
                title: $0.title.isEmpty ? $0.url.deletingPathExtension().lastPathComponent : $0.title,
                subtitle: $0.snippet.isEmpty ? displayPath($0.url) : $0.snippet,
                openWindowID: nil
            )
        }
        tableView.reloadData()
        emptyLabel.isHidden = !items.isEmpty
        resizeForContent()
    }

    private func resizeForContent() {
        guard let window else { return }
        let visibleRows = min(max(items.count, 1), 5)
        let height = 116 + CGFloat(visibleRows * 55)
        let topEdge = window.frame.maxY
        window.setContentSize(NSSize(width: 340, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: topEdge - window.frame.height))
    }
}
