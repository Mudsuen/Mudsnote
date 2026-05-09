import AppKit

struct SuggestionItem: Equatable {
    let title: String
    let subtitle: String?
    let symbolName: String?
}

@MainActor
final class SuggestionRowView: NSTableCellView {
    private let selectionView = NSView()
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 5
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            selectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            selectionView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            selectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            titleLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 8),
            titleLabel.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -8),
            titleLabel.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor, constant: -1)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: SuggestionItem, selected: Bool) {
        titleLabel.stringValue = item.title

        selectionView.layer?.backgroundColor = selected
            ? panelAccentColor().withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        selectionView.layer?.borderWidth = selected ? 1 : 0
        selectionView.layer?.borderColor = panelSeparatorColor(alpha: 0.42).cgColor
    }
}

@MainActor
final class SuggestionPopoverController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    private enum Metrics {
        static let width: CGFloat = 156
        static let rowHeight: CGFloat = 24
        static let outerInset: CGFloat = 2
        static let maxHeight: CGFloat = 124
    }

    var onSelect: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private var items: [SuggestionItem] = []
    private(set) var selectedIndex = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.maxHeight))
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        view.layer?.borderWidth = 0
        view.layer?.borderColor = NSColor.clear.cgColor

        let column = NSTableColumn(identifier: .init("suggestion"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
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
        pin(scrollView, to: view, insets: .init(
            top: Metrics.outerInset,
            left: Metrics.outerInset,
            bottom: Metrics.outerInset,
            right: Metrics.outerInset
        ))
    }

    func updateItems(_ items: [SuggestionItem]) {
        self.items = items
        selectedIndex = min(selectedIndex, max(items.count - 1, 0))
        tableView.reloadData()
        selectRow(at: selectedIndex)
        preferredContentSize = NSSize(
            width: Metrics.width,
            height: min(
                CGFloat(max(items.count, 1)) * Metrics.rowHeight + (Metrics.outerInset * 2),
                Metrics.maxHeight
            )
        )
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
