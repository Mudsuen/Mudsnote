import AppKit
import MudsnoteCore

@MainActor
final class FloatingNoteBrowserResultCellView: NSTableCellView {
    let marker = NSView()
    let titleLabel = NSTextField(labelWithString: "")
    let snippetLabel = NSTextField(labelWithString: "")

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
        labels.spacing = 4
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(marker)
        addSubview(labels)

        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            marker.centerYAnchor.constraint(equalTo: centerYAnchor),
            marker.widthAnchor.constraint(equalToConstant: 8),
            marker.heightAnchor.constraint(equalToConstant: 8),

            labels.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 10),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with result: NoteSearchResult, isCurrent: Bool) {
        titleLabel.stringValue = result.title.isEmpty ? result.url.deletingPathExtension().lastPathComponent : result.title
        snippetLabel.stringValue = result.snippet.isEmpty ? displayPath(result.url) : result.snippet
        marker.layer?.backgroundColor = (isCurrent ? NSColor.systemRed : panelTertiaryTextColor()).cgColor
    }
}

@MainActor
final class FloatingNoteBrowserPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class FloatingNoteBrowserController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let noteStore: NoteStore
    private let onSelect: (URL) -> Void
    private let searchField = NSSearchField(string: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private var results: [NoteSearchResult] = []

    var selectedURL: URL? {
        didSet { tableView.reloadData() }
    }

    init(noteStore: NoteStore, selectedURL: URL?, onSelect: @escaping (URL) -> Void) {
        self.noteStore = noteStore
        self.selectedURL = selectedURL
        self.onSelect = onSelect

        let panel = FloatingNoteBrowserPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 294),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = true

        super.init(window: panel)
        panel.delegate = self
        buildUI()
        reloadResults()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(relativeTo anchorView: NSView?, parentWindow: NSWindow?) {
        reloadResults()

        guard let window else { return }
        if let parentWindow {
            window.level = parentWindow.level
        }

        if let anchorView, let parentWindow {
            let anchorRect = anchorView.convert(anchorView.bounds, to: nil)
            let origin = parentWindow.convertPoint(toScreen: NSPoint(x: anchorRect.maxX - window.frame.width, y: anchorRect.minY - window.frame.height - 8))
            window.setFrameOrigin(origin)
            if window.parent !== parentWindow {
                parentWindow.addChildWindow(window, ordered: .above)
            }
        } else if let parentWindow {
            let parentFrame = parentWindow.frame
            window.setFrameOrigin(NSPoint(x: parentFrame.maxX - window.frame.width - 12, y: parentFrame.maxY - window.frame.height - 30))
            if window.parent !== parentWindow {
                parentWindow.addChildWindow(window, ordered: .above)
            }
        }

        window.orderFrontRegardless()
        window.makeKey()
        searchField.selectText(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window else { return }
        window.parent?.removeChildWindow(window)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let surface = NSVisualEffectView()
        surface.translatesAutoresizingMaskIntoConstraints = false
        surface.material = .hudWindow
        surface.state = .active
        surface.blendingMode = .behindWindow
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 20
        surface.layer?.masksToBounds = true
        contentView.addSubview(surface)
        pin(surface, to: contentView)

        searchField.placeholderString = "Search for notes..."
        searchField.font = .systemFont(ofSize: 18, weight: .semibold)
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(openSelectedResult)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(searchField)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(divider)

        let titleLabel = NSTextField(labelWithString: "Notes")
        titleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        titleLabel.textColor = panelSecondaryTextColor()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(titleLabel)

        countLabel.font = .systemFont(ofSize: 14, weight: .bold)
        countLabel.textColor = panelSecondaryTextColor()
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(countLabel)

        let infoIcon = NSImageView()
        infoIcon.translatesAutoresizingMaskIntoConstraints = false
        infoIcon.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        infoIcon.contentTintColor = panelSecondaryTextColor()
        surface.addSubview(infoIcon)

        tableView.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note")))
        tableView.headerView = nil
        tableView.rowHeight = 56
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
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
        scrollView.hasVerticalScroller = false
        scrollView.documentView = tableView
        surface.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            searchField.topAnchor.constraint(equalTo: surface.topAnchor, constant: 16),
            searchField.heightAnchor.constraint(equalToConstant: 34),

            divider.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),

            titleLabel.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 20),
            titleLabel.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 16),

            infoIcon.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -20),
            infoIcon.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            infoIcon.widthAnchor.constraint(equalToConstant: 17),
            infoIcon.heightAnchor.constraint(equalToConstant: 17),

            countLabel.trailingAnchor.constraint(equalTo: infoIcon.leadingAnchor, constant: -10),
            countLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),

            scrollView.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -16)
        ])
    }

    func controlTextDidChange(_ obj: Notification) {
        reloadResults()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let result = results[row]
        let identifier = NSUserInterfaceItemIdentifier("FloatingNoteBrowserResultCell")
        let cell: FloatingNoteBrowserResultCellView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? FloatingNoteBrowserResultCellView {
            cell = reused
        } else {
            cell = FloatingNoteBrowserResultCellView()
            cell.identifier = identifier
        }
        cell.configure(
            with: result,
            isCurrent: selectedURL.map { result.url.standardizedFileURL == $0.standardizedFileURL } ?? false
        )
        return cell
    }

    @objc private func openSelectedResult() {
        let row = tableView.selectedRow >= 0 ? tableView.selectedRow : 0
        guard results.indices.contains(row) else { return }
        let url = results[row].url
        window?.close()
        onSelect(url)
    }

    private func reloadResults() {
        results = noteStore.searchNotes(query: searchField.stringValue, limit: 5)
        tableView.reloadData()
        if !results.isEmpty {
            let selectedIndex = selectedURL.flatMap { selected in
                results.firstIndex { $0.url.standardizedFileURL == selected.standardizedFileURL }
            } ?? 0
            tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
        }
        countLabel.stringValue = "\(results.count)/5 Notes"
    }
}
