import AppKit

@MainActor
final class LibraryAttachmentManagerWindowController: NSWindowController,
    NSTableViewDataSource,
    NSTableViewDelegate, NSWindowDelegate
{
    private enum Column {
        static let name = NSUserInterfaceItemIdentifier("AttachmentName")
        static let status = NSUserInterfaceItemIdentifier("AttachmentStatus")
        static let size = NSUserInterfaceItemIdentifier("AttachmentSize")
        static let references = NSUserInterfaceItemIdentifier("AttachmentReferences")
    }

    private let rootsProvider: () -> [URL]
    private let inventoryLoader: @Sendable ([URL]) throws -> LibraryAttachmentScan
    private let removeAttachment: @Sendable (URL) throws -> Void
    private let onOpenNote: (URL) -> Void
    private let quickLookController = AttachmentQuickLookController()
    private let tableView = NSTableView()
    private let filterControl = NSSegmentedControl(
        labels: ["全部", "已引用", "未引用", "缺失", "待核实"],
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
    private var scanIsComplete = true
    private var loadGeneration = 0
    private var scanTask: Task<Void, Never>?
    private enum LoadState { case loaded, loading, failed(message: String, detail: String) }
    private var loadState: LoadState = .loaded

    init(
        rootsProvider: @escaping () -> [URL],
        inventoryLoader: @escaping @Sendable ([URL]) throws -> LibraryAttachmentScan = {
            LibraryAttachmentInventory.scan(roots: $0)
        },
        removeAttachment: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        onOpenNote: @escaping (URL) -> Void
    ) {
        self.rootsProvider = rootsProvider
        self.inventoryLoader = inventoryLoader
        self.onOpenNote = onOpenNote
        self.removeAttachment = removeAttachment
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
        window.delegate = self
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
        tableView.allowsMultipleSelection = true
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

    private func refresh() { scan() }

    private func scan(removing items: [LibraryAttachmentItem] = []) {
        scanTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let selectedPath = selectedItem?.url.path
        let roots = rootsProvider(), loader = inventoryLoader, remove = removeAttachment
        loadState = .loading
        updateLoadPresentation()
        scanTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result {
                try Task.checkCancellation()
                var scan = try loader(roots)
                try Task.checkCancellation()
                if !items.isEmpty, scan.isComplete {
                    let targetPaths = Set(items.map { $0.url.standardizedFileURL.path })
                    let removable = scan.items.filter {
                        targetPaths.contains($0.url.standardizedFileURL.path) && $0.state == .unreferenced
                    }
                    var removedPaths = Set<String>()
                    for target in removable {
                        try Task.checkCancellation()
                        try remove(target.url)
                        removedPaths.insert(target.url.standardizedFileURL.path)
                    }
                    scan.items.removeAll { removedPaths.contains($0.url.standardizedFileURL.path) }
                }
                return scan
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, generation == self.loadGeneration else { return }
                self.scanTask = nil
                switch result {
                case .success(let scan):
                    self.allItems = scan.items
                    self.scanIsComplete = scan.isComplete
                    self.loadState = .loaded
                case .failure(let error):
                    self.allItems = []
                    self.loadState = .failed(message: items.isEmpty ? "扫描失败，请重试" : "删除未完成，请重试", detail: error.localizedDescription)
                }
                self.applyFilter(preserving: selectedPath)
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        loadGeneration += 1
        scanTask?.cancel()
        scanTask = nil
    }

    private func updateLoadPresentation() {
        switch loadState {
        case .loading:
            summaryLabel.stringValue = "正在扫描…"
            summaryLabel.toolTip = nil
            emptyLabel.isHidden = true
            refreshButton.isEnabled = false
        case .failed(let message, let detail):
            summaryLabel.stringValue = message
            summaryLabel.toolTip = detail
            emptyLabel.isHidden = true
            refreshButton.isEnabled = true
        case .loaded:
            let missing = allItems.filter { $0.state == .missing }.count
            let unreferenced = allItems.filter { $0.state == .unreferenced }.count
            let unknown = allItems.filter { $0.state == .unknown }.count
            summaryLabel.stringValue = "\(allItems.count) 个附件 · \(unreferenced) 个未引用 · \(missing) 个缺失"
                + (unknown > 0 ? " · \(unknown) 个待核实" : "")
                + (!scanIsComplete ? " · 引用扫描不完整" : "")
            summaryLabel.toolTip = !scanIsComplete ? "部分目录或笔记无法读取，未确认引用的附件不能删除。" : nil
            emptyLabel.isHidden = !scanIsComplete || !visibleItems.isEmpty
            refreshButton.isEnabled = true
        }
        updateSelectionActions()
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
        case 4:
            state = .unknown
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
        updateLoadPresentation()
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

    private var selectedItems: [LibraryAttachmentItem] {
        tableView.selectedRowIndexes.compactMap { row in
            visibleItems.indices.contains(row) ? visibleItems[row] : nil
        }
    }

    private var selectedItem: LibraryAttachmentItem? {
        let row = tableView.selectedRow
        return visibleItems.indices.contains(row) ? visibleItems[row] : selectedItems.first
    }

    private var removableSelectedItems: [LibraryAttachmentItem] {
        selectedItems.filter {
            $0.state == .unreferenced && FileManager.default.fileExists(atPath: $0.url.path)
        }
    }

    private func updateSelectionActions() {
        let item = selectedItem
        let exists = item.map { FileManager.default.fileExists(atPath: $0.url.path) } ?? false
        previewButton.isEnabled = exists
        revealButton.isEnabled = exists
        let referenceCount = item?.referencingNotes.count ?? 0
        openNoteButton.isEnabled = referenceCount > 0
        openNoteButton.title = referenceCount > 1 ? "打开引用笔记 (\(referenceCount))…" : "打开引用笔记"

        let removableCount = removableSelectedItems.count
        if case .loaded = loadState {
            deleteButton.isEnabled = removableCount > 0
        } else {
            deleteButton.isEnabled = false
        }
        deleteButton.title = removableCount > 1 ? "删除 \(removableCount) 个未引用附件…" : "删除未引用附件…"
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
        let existingURLs = selectedItems.map(\.url).filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(existingURLs)
    }

    @objc
    private func openNotePressed() {
        guard let references = selectedItem?.referencingNotes, !references.isEmpty else { return }
        if references.count == 1 {
            onOpenNote(references[0])
            return
        }
        let menu = NSMenu(title: "选择引用笔记")
        for noteURL in references {
            let menuItem = NSMenuItem(
                title: noteURL.deletingPathExtension().lastPathComponent,
                action: #selector(openSpecificReferencingNote(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = noteURL
            menuItem.toolTip = noteURL.path
            menu.addItem(menuItem)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: openNoteButton.bounds.height + 4), in: openNoteButton)
    }

    @objc
    private func openSpecificReferencingNote(_ sender: NSMenuItem) {
        guard let noteURL = sender.representedObject as? URL else { return }
        onOpenNote(noteURL)
    }

    @objc
    private func deletePressed() {
        let targets = removableSelectedItems
        guard !targets.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        if targets.count == 1 {
            alert.messageText = "删除未引用附件？"
            alert.informativeText = """
            \(targets[0].filename) 当前没有被资料库中的笔记引用。此操作会把文件移到废纸篓，无法通过 Mudsnote 撤销。
            """
        } else {
            alert.messageText = "批量删除 \(targets.count) 个未引用附件？"
            let sample = targets.prefix(4).map(\.filename).joined(separator: "、")
            let suffix = targets.count > 4 ? " 等 \(targets.count) 个文件" : ""
            alert.informativeText = """
            将把 \(sample)\(suffix) 移到废纸篓，无法通过 Mudsnote 撤销。
            """
        }
        alert.addButton(withTitle: "移到废纸篓")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        scan(removing: targets)
    }

    func refreshAttachmentInventoryForTesting() { refresh() }
    func waitForAttachmentInventoryForTesting() async { await scanTask?.value }
    func deleteSelectedAttachmentForTesting() {
        let targets = removableSelectedItems
        guard !targets.isEmpty else { return }
        scan(removing: targets)
    }
    var selectedAttachmentPathForTesting: String? { selectedItem?.url.path }
    var attachmentSummaryForTesting: String { summaryLabel.stringValue }
    var showsEmptyAttachmentMessageForTesting: Bool { !emptyLabel.isHidden }
    var canOpenSelectedAttachmentSourceForTesting: Bool { openNoteButton.isEnabled }

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
        scanIsComplete = true
        loadState = .loaded
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
        case .unknown:
            filterControl.selectedSegment = 4
        case nil:
            filterControl.selectedSegment = 0
        }
        applyFilter(preserving: nil)
    }
}
