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
    let titleLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(labelWithString: "")
    let actionButton = NSButton()
    private var onAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.masksToBounds = true
        layer?.backgroundColor = panelPrimaryTextColor().withAlphaComponent(0.08).cgColor

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.lineBreakMode = .byTruncatingTail

        snippetLabel.font = .systemFont(ofSize: 11, weight: .regular)
        snippetLabel.textColor = panelSecondaryTextColor()
        snippetLabel.lineBreakMode = .byTruncatingTail

        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        snippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labels = NSStackView(views: [titleLabel, snippetLabel])
        labels.orientation = .horizontal
        labels.alignment = .centerY
        labels.spacing = 7
        labels.translatesAutoresizingMaskIntoConstraints = false

        actionButton.isBordered = false
        actionButton.bezelStyle = .regularSquare
        actionButton.imagePosition = .imageOnly
        actionButton.target = self
        actionButton.action = #selector(actionPressed)
        actionButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(labels)
        addSubview(actionButton)

        NSLayoutConstraint.activate([
            labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -6),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 24),
            actionButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        title: String,
        subtitle: String,
        isOpen: Bool,
        onAction: @escaping () -> Void
    ) {
        titleLabel.stringValue = title
        snippetLabel.stringValue = subtitle
        let symbolName = isOpen ? "xmark" : "plus"
        actionButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        actionButton.contentTintColor = panelSecondaryTextColor()
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
    static let compactPanelWidth: CGFloat = 300
    static let compactRowHeight: CGFloat = 36
    static let compactRowStride: CGFloat = 40
    static let compactChromeHeight: CGFloat = 76

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
    private let onCreate: () -> Void
    private let searchField = NSSearchField(string: "")
    let newWindowButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "搜索笔记并添加悬浮窗口")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var items: [Item] = []
    private(set) var presentationCount = 0
    private weak var presentationAnchorView: NSView?
    private var outsideClickMonitor: Any?

    var displayedURLs: [URL] { items.compactMap(\.url) }
    var displayedOpenStates: [Bool] { items.map(\.isOpen) }

    func rowActionButton(at row: Int) -> NSButton? {
        guard items.indices.contains(row) else { return nil }
        return (tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FloatingNoteBrowserResultCellView)?.actionButton
    }

    func resultCell(at row: Int) -> FloatingNoteBrowserResultCellView? {
        guard items.indices.contains(row) else { return nil }
        return tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FloatingNoteBrowserResultCellView
    }

    var resultRowHeight: CGFloat { tableView.rowHeight }
    var usesVerticalScroller: Bool { scrollView.hasVerticalScroller }
    var verticalScrollElasticity: NSScrollView.Elasticity { scrollView.verticalScrollElasticity }
    var verticalScrollOffset: CGFloat { scrollView.contentView.bounds.minY }

    init(
        noteStore: NoteStore,
        openWindows: @escaping () -> [FloatingNoteWindowDescriptor],
        onOpen: @escaping (URL) -> Void,
        onActivate: @escaping (UUID) -> Void,
        onClose: @escaping (UUID) -> Void,
        onCreate: @escaping () -> Void
    ) {
        self.noteStore = noteStore
        self.openWindows = openWindows
        self.onOpen = onOpen
        self.onActivate = onActivate
        self.onClose = onClose
        self.onCreate = onCreate

        let panel = FloatingNoteBrowserPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.compactPanelWidth, height: 116),
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
        presentationAnchorView = anchorView
        installOutsideClickMonitor()
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
            window.setFrameOrigin(containedOrigin(for: window.frame.size, proposed: proposedOrigin, parentWindow: parentWindow))
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

    func containedOrigin(for windowSize: NSSize, proposed: NSPoint, parentWindow: NSWindow?) -> NSPoint {
        if let parentWindow {
            let parentFrame = parentWindow.frame
            let maximumX = max(parentFrame.minX, parentFrame.maxX - windowSize.width)
            let maximumY = max(parentFrame.minY, parentFrame.maxY - windowSize.height)
            return NSPoint(
                x: min(max(proposed.x, parentFrame.minX), maximumX),
                y: min(max(proposed.y, parentFrame.minY), maximumY)
            )
        }
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
        removeOutsideClickMonitor()
        window.parent?.removeChildWindow(window)
    }

    func windowDidResignKey(_ notification: Notification) {
        if let event = NSApp.currentEvent, eventTargetsPresentationAnchor(event) {
            return
        }
        window?.close()
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self else { return event }
            if event.window !== self.window,
               !self.eventTargetsPresentationAnchor(event) {
                self.window?.close()
            }
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        guard let outsideClickMonitor else { return }
        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func eventTargetsPresentationAnchor(_ event: NSEvent) -> Bool {
        guard let anchor = presentationAnchorView,
              event.window === anchor.window else { return false }
        return anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil))
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

    @objc private func createWindowPressed() {
        window?.close()
        onCreate()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let surface = NSVisualEffectView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.material = .hudWindow
        surface.state = .active
        surface.blendingMode = .behindWindow
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 14
        surface.layer?.masksToBounds = true
        contentView.addSubview(surface)
        pin(surface, to: contentView)

        let titleLabel = NSTextField(labelWithString: "悬浮窗口")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = panelSecondaryTextColor()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(titleLabel)

        newWindowButton.isBordered = false
        newWindowButton.bezelStyle = .regularSquare
        newWindowButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "新建悬浮窗口")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        newWindowButton.imagePosition = .imageOnly
        newWindowButton.contentTintColor = panelPrimaryTextColor()
        newWindowButton.toolTip = "新建悬浮窗口"
        newWindowButton.setAccessibilityLabel("新建悬浮窗口")
        newWindowButton.target = self
        newWindowButton.action = #selector(createWindowPressed)
        newWindowButton.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(newWindowButton)

        searchField.placeholderString = "搜索并添加笔记"
        searchField.font = .systemFont(ofSize: 13, weight: .regular)
        searchField.controlSize = .small
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(searchField)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(divider)

        let noteColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        noteColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(noteColumn)
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.style = .plain
        tableView.headerView = nil
        tableView.rowHeight = Self.compactRowHeight
        tableView.intercellSpacing = NSSize(width: 0, height: Self.compactRowStride - Self.compactRowHeight)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedResult)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = tableView
        surface.addSubview(scrollView)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = panelSecondaryTextColor()
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 12),
            titleLabel.topAnchor.constraint(equalTo: surface.topAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: newWindowButton.leadingAnchor, constant: -8),

            newWindowButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8),
            newWindowButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            newWindowButton.widthAnchor.constraint(equalToConstant: 24),
            newWindowButton.heightAnchor.constraint(equalToConstant: 24),

            searchField.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -10),
            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            searchField.heightAnchor.constraint(equalToConstant: 26),

            divider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 7),

            scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -8),
            scrollView.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 6),
            scrollView.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -8),

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
        let needsScrolling = items.count > 5
        scrollView.hasVerticalScroller = needsScrolling
        scrollView.verticalScrollElasticity = needsScrolling ? .automatic : .none
        if !needsScrolling {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        emptyLabel.isHidden = !items.isEmpty
        resizeForContent()
    }

    private func resizeForContent() {
        guard let window else { return }
        let visibleRows = min(max(items.count, 1), 5)
        let height = Self.compactChromeHeight + CGFloat(visibleRows) * Self.compactRowStride
        let topEdge = window.frame.maxY
        window.setContentSize(NSSize(width: Self.compactPanelWidth, height: height))
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: topEdge - window.frame.height))
    }
}
