import AppKit

struct SuggestionItem: Equatable {
    let title: String
    let subtitle: String?
    let symbolName: String?
}

@MainActor
final class SuggestionRowView: NSTableCellView {
    private let selectionView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var titleIconLeadingConstraint: NSLayoutConstraint?
    private var titleDirectLeadingConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 5
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionView)

        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        iconView.contentTintColor = panelSecondaryTextColor()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = panelPrimaryTextColor()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        titleIconLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 5)
        titleDirectLeadingConstraint = titleLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 4)

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            selectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            selectionView.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            selectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            iconView.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor, constant: -1),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            titleLabel.trailingAnchor.constraint(equalTo: selectionView.trailingAnchor, constant: -6),
            titleLabel.centerYAnchor.constraint(equalTo: selectionView.centerYAnchor, constant: -1)
        ])
        titleDirectLeadingConstraint?.isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: SuggestionItem, selected: Bool) {
        titleLabel.stringValue = item.title
        iconView.image = item.symbolName.flatMap {
            NSImage(systemSymbolName: $0, accessibilityDescription: item.title)
        }
        iconView.isHidden = item.symbolName == nil
        titleIconLeadingConstraint?.isActive = item.symbolName != nil
        titleDirectLeadingConstraint?.isActive = item.symbolName == nil

        selectionView.layer?.backgroundColor = selected
            ? NSColor(calibratedWhite: 0.18, alpha: 1).cgColor
            : NSColor.clear.cgColor
        selectionView.layer?.borderWidth = selected ? 1 : 0
        selectionView.layer?.borderColor = NSColor(calibratedWhite: 0.28, alpha: 1).cgColor
        iconView.contentTintColor = selected ? panelPrimaryTextColor() : panelSecondaryTextColor()
    }
}

@MainActor
final class SuggestionPopoverController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {
    private enum Metrics {
        static let rowHeight: CGFloat = 24
        static let outerInset: CGFloat = 0
        static let maxHeight: CGFloat = 120
        static let selectionInset: CGFloat = 1
        static let iconLeading: CGFloat = 4
        static let iconWidth: CGFloat = 15
        static let iconTitleGap: CGFloat = 5
        static let titleLeading: CGFloat = 4
        static let titleTrailing: CGFloat = 6
        static let fallbackWidth: CGFloat = 64
        static let maxWidth: CGFloat = 180
        static let scrollerGutter: CGFloat = 10
        static func titleFont() -> NSFont { .systemFont(ofSize: 12, weight: .semibold) }
    }

    var onSelect: ((Int) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let suggestionColumn = NSTableColumn(identifier: .init("suggestion"))
    private var items: [SuggestionItem] = []
    private(set) var selectedIndex = 0

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: Metrics.fallbackWidth, height: Metrics.maxHeight))
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.backgroundColor = NSColor(calibratedWhite: 0.08, alpha: 1).cgColor
        view.layer?.borderWidth = 0
        view.layer?.borderColor = NSColor.clear.cgColor

        tableView.addTableColumn(suggestionColumn)
        tableView.headerView = nil
        tableView.rowHeight = Metrics.rowHeight
        tableView.intercellSpacing = .zero
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
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
        let contentWidth = preferredContentWidth(for: items)
        let needsScroller = CGFloat(items.count) * Metrics.rowHeight > Metrics.maxHeight
        let width = contentWidth + (needsScroller ? Metrics.scrollerGutter : 0)
        suggestionColumn.width = contentWidth
        tableView.frame.size = NSSize(
            width: contentWidth,
            height: CGFloat(items.count) * Metrics.rowHeight
        )
        preferredContentSize = NSSize(
            width: width,
            height: min(
                CGFloat(max(items.count, 1)) * Metrics.rowHeight + (Metrics.outerInset * 2),
                Metrics.maxHeight
            )
        )
    }

    private func preferredContentWidth(for items: [SuggestionItem]) -> CGFloat {
        let maxTitleWidth = items
            .map { ceil(($0.title as NSString).size(withAttributes: [.font: Metrics.titleFont()]).width) }
            .max() ?? 0
        let leadingSpace = items.contains { $0.symbolName != nil }
            ? Metrics.iconLeading + Metrics.iconWidth + Metrics.iconTitleGap
            : Metrics.titleLeading
        let horizontalPadding = (Metrics.selectionInset * 2) + leadingSpace + Metrics.titleTrailing
        let contentWidth = maxTitleWidth + horizontalPadding
        return min(max(ceil(contentWidth), Metrics.fallbackWidth), Metrics.maxWidth)
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
