import AppKit

struct SuggestionItem: Equatable {
    let title: String
    let subtitle: String?
    let symbolName: String?
}

@MainActor
final class SuggestionRowView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 6

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = panelPrimaryTextColor()
        addSubview(titleLabel)
        pin(titleLabel, to: self, insets: .init(top: 7, left: 10, bottom: 7, right: 10))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: SuggestionItem, selected: Bool) {
        titleLabel.stringValue = item.title

        layer?.backgroundColor = selected
            ? panelAccentColor().withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        layer?.borderWidth = selected ? 1 : 0
        layer?.borderColor = panelSeparatorColor(alpha: 0.42).cgColor
    }
}

@MainActor
final class SuggestionPopoverController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    var onSelect: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var items: [SuggestionItem] = []
    private(set) var selectedIndex = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 180, height: 180))
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        view.layer?.borderWidth = 1
        view.layer?.borderColor = panelSeparatorColor(alpha: 0.64).cgColor

        let column = NSTableColumn(identifier: .init("suggestion"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 36
        tableView.intercellSpacing = .zero
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.focusRingType = .none
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.scrollerStyle = .legacy
        scrollView.verticalScroller = SlimScroller()
        scrollView.documentView = tableView

        view.addSubview(scrollView)
        pin(scrollView, to: view, insets: .init(top: 4, left: 4, bottom: 4, right: 4))
    }

    func updateItems(_ items: [SuggestionItem]) {
        self.items = items
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
        tableView.reloadData()
        selectRow(at: selectedIndex)
        preferredContentSize = NSSize(width: 180, height: min(CGFloat(max(items.count, 1)) * 36 + 8, 188))
    }

    func moveSelection(delta: Int) {
        guard !items.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), items.count - 1)
        selectRow(at: selectedIndex)
    }

    func acceptSelection() {
        guard items.indices.contains(selectedIndex) else { return }
        onSelect?(selectedIndex)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("SuggestionRow")
        let rowView = (tableView.makeView(withIdentifier: identifier, owner: nil) as? SuggestionRowView) ?? {
            let view = SuggestionRowView()
            view.identifier = identifier
            return view
        }()
        rowView.configure(item: items[row], selected: row == selectedIndex)
        return rowView
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        selectedIndex = max(tableView.selectedRow, 0)
        tableView.reloadData()
    }

    @objc
    private func doubleClicked() {
        acceptSelection()
    }

    private func selectRow(at index: Int) {
        guard items.indices.contains(index) else { return }
        tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        tableView.scrollRowToVisible(index)
        tableView.reloadData()
    }
}

@MainActor
func caretRectInWindow(for textView: NSTextView) -> NSRect {
    guard let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else {
        return textView.bounds
    }

    let selectedRange = textView.selectedRange()
    let glyphIndex = layoutManager.glyphIndexForCharacter(at: max(selectedRange.location, 0))
    var rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 0), in: textContainer)
    rect.origin.x += textView.textContainerInset.width
    rect.origin.y += textView.textContainerInset.height
    return rect.insetBy(dx: -4, dy: -4)
}
