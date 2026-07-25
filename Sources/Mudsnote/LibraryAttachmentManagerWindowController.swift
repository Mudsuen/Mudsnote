import AppKit

@MainActor
final class LibraryAttachmentManagerWindowController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate
{
    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("AttachmentName")
        static let status = NSUserInterfaceItemIdentifier("AttachmentStatus")
        static let size = NSUserInterfaceItemIdentifier("AttachmentSize")
        static let references = NSUserInterfaceItemIdentifier("AttachmentReferences")
    }

    private let rootsProvider: () -> [URL]
    private let inventoryLoader: @Sendable ([URL]) -> [LibraryAttachmentItem]
    private let onOpenNote: (URL) -> Void
    private let quickLookController = AttachmentQuickLookController()
    private let tableView = NSTableView()
    private let filterControl = NSSegmentedControl(
        labels: ["全部", "已引用", "未引用", "缺失"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let summaryLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "没有符合条件的附件")
    private let refreshButton = NSButton(title: "刷新", target: nil, action: nil)
    private let previewButton = NSButton(title: "快速查看", target: nil, action: nil)
    private let revealButton = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
    private let openNoteButton = NSButton(title: "打开引用笔记", target: nil, action: nil)
    private let deleteButton = NSButton(title: "删除未引用附件…", target: nil, action: nil)
    private var allItems: [LibraryAttachmentItem] = []
    private var visibleItems: [LibraryAttachmentItem] = []
    private var loadGeneration = 0

    init(
        rootsProvider: @escaping () -> [URL],
        inventoryLoader: @escaping @Sendable ([URL]) -> [LibraryAttachmentItem] = {
            LibraryAttachmentInventory.build(roots: $0)
        },
        onOpenNote: @escaping (URL) -> Void
    ) {
        self.rootsProvider = rootsProvider
        self.inventoryLoader = inventoryLoader
        self.onOpenNote = onOpenNote
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "附件管理"
        window.minSize = NSSize(width: 620, height: 340)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showAndRefresh() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        filterControl.selectedSegment = 0
        filterControl.target = self
        filterControl.action = #selector(filterChanged)
        filterControl.setAccessibilityLabel("附件筛选")

        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .secondaryLabelColor
        summaryLabel.setAccessibilityLabel("附件统计")

        for (identifier, title, width) in [
            (Column.name, "名称", 220.0),
            (Column.status, "状态", 88.0),
            (Column.size, "大小", 80.0),
            (Column.references, "引用", 250.0)
        ] {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.minWidth = identifier == Column.name ? 150 : 70
            tableView.addTableColumn(column)
        }
        tableView.identifier = NSUserInterfaceItemIdentifier("LibraryAttachmentManagerTable")
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = false
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 28
        tableView.doubleAction = #selector(previewPressed)
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.isHidden = true

        refreshButton.target = self
        refreshButton.action = #selector(refreshPressed)
        previewButton.target = self
        previewButton.action = #selector(previewPressed)
        revealButton.target = self
        revealButton.action = #selector(revealPressed)
        openNoteButton.target = self
        openNoteButton.action = #selector(openNotePressed)
        deleteButton.target = self
        deleteButton.action = #selector(deletePressed)
        deleteButton.contentTintColor = .systemRed

        let header = NSStackView(views: [filterControl, summaryLabel, refreshButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        summaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actions = NSStackView(views: [
            previewButton,
            revealButton,
            openNoteButton,
            NSView(),
            deleteButton
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        for view in [header, scrollView, emptyLabel, actions] {
            contentView.addSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scrollView.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -12),
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            actions.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            actions.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            actions.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
        updateSelectionActions()
    }

    private func refresh() {
        loadGeneration += 1
        let generation = loadGeneration
        let roots = rootsProvider()
        refreshButton.isEnabled = false
        summaryLabel.stringValue = "正在扫描…"
        let loader = inventoryLoader
        Task.detached(priority: .userInitiated) { [weak self] in
            let items = loader(roots)
            await MainActor.run {
                guard let self, generation == self.loadGeneration else { return }
                self.refreshButton.isEnabled = true
                self.allItems = items
                self.applyFilter(preserving: nil)
            }
        }
    }

    private func applyFilter(preserving selectedPath: String?) {
        let state: LibraryAttachmentState?
        switch filterControl.selectedSegment {
        case 1:
            state = .referenced
        case 2:
            state = .unreferenced
        case 3:
            state = .missing
        default:
            state = nil
        }
        visibleItems = state.map { selectedState in
            allItems.filter { $0.state == selectedState }
        } ?? allItems
        tableView.reloadData()
        if let selectedPath,
           let row = visibleItems.firstIndex(where: { $0.url.path == selectedPath }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        let missing = allItems.filter { $0.state == .missing }.count
        let unreferenced = allItems.filter { $0.state == .unreferenced }.count
        summaryLabel.stringValue = "\(allItems.count) 个附件 · \(unreferenced) 个未引用 · \(missing) 个缺失"
        emptyLabel.isHidden = !visibleItems.isEmpty
        updateSelectionActions()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard visibleItems.indices.contains(row), let tableColumn else { return nil }
        let item = visibleItems[row]
        let identifier = tableColumn.identifier
        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView)
            ?? NSTableCellView()
        cell.identifier = identifier
        let label = cell.textField ?? NSTextField(labelWithString: "")
        if label.superview == nil {
            cell.textField = label
            cell.addSubview(label)
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = item.url.path
        switch identifier {
        case Column.name:
            label.stringValue = item.filename
        case Column.status:
            label.stringValue = item.state.title
            label.textColor = item.state == .missing
                ? .systemRed
                : (item.state == .unreferenced ? .systemOrange : .labelColor)
        case Column.size:
            label.stringValue = item.byteCount.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            } ?? "—"
        case Column.references:
            label.stringValue = item.referenceSummary
        default:
            label.stringValue = ""
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionActions()
    }

    private var selectedItem: LibraryAttachmentItem? {
        let row = tableView.selectedRow
        return visibleItems.indices.contains(row) ? visibleItems[row] : nil
    }

    private func updateSelectionActions() {
        let item = selectedItem
        let exists = item.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false
        previewButton.isEnabled = exists
        revealButton.isEnabled = exists
        openNoteButton.isEnabled = !(item?.referencingNotes.isEmpty ?? true)
        deleteButton.isEnabled = item?.state == .unreferenced && exists
    }

    @objc
    private func filterChanged() {
        applyFilter(preserving: selectedItem?.url.path)
    }

    @objc
    private func refreshPressed() {
        refresh()
    }

    @objc
    private func previewPressed() {
        guard let item = selectedItem,
              FileManager.default.fileExists(atPath: item.url.path) else {
            return
        }
        quickLookController.preview(item.url)
    }

    @objc
    private func revealPressed() {
        guard let item = selectedItem,
              FileManager.default.fileExists(atPath: item.url.path) else {
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    @objc
    private func openNotePressed() {
        guard let noteURL = selectedItem?.referencingNotes.first else { return }
        onOpenNote(noteURL)
    }

    @objc
    private func deletePressed() {
        guard let item = selectedItem, item.state == .unreferenced else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除未引用附件？"
        alert.informativeText = """
        \(item.filename) 当前没有被资料库中的笔记引用。此操作会把文件移到废纸篓，无法通过 Mudsnote 撤销。
        """
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            refresh()
        } catch {
            let errorAlert = NSAlert(error: error)
            errorAlert.messageText = "无法删除附件"
            errorAlert.runModal()
        }
    }

    var attachmentItemsForTesting: [LibraryAttachmentItem] {
        visibleItems
    }

    func selectAttachmentForTesting(at row: Int) {
        guard visibleItems.indices.contains(row) else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    var canDeleteSelectedAttachmentForTesting: Bool {
        deleteButton.isEnabled
    }

    func loadAttachmentItemsForTesting(_ items: [LibraryAttachmentItem]) {
        allItems = items
        filterControl.selectedSegment = 0
        applyFilter(preserving: nil)
    }

    func setAttachmentFilterForTesting(_ state: LibraryAttachmentState?) {
        switch state {
        case .referenced:
            filterControl.selectedSegment = 1
        case .unreferenced:
            filterControl.selectedSegment = 2
        case .missing:
            filterControl.selectedSegment = 3
        case nil:
            filterControl.selectedSegment = 0
        }
        applyFilter(preserving: nil)
    }
}
