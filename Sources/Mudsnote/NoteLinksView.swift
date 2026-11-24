import AppKit
import MudsnoteCore

final class NoteLinksView: NSView {
    var isSuppressed = false {
        didSet { updateVisibility() }
    }

    private func updateVisibility() {
        isHidden = isSuppressed || (linkRelations.outgoing.isEmpty && linkRelations.incoming.isEmpty)
    }

    private final class RelationButton: NSButton {
        let item: NoteLinkItem

        init(
            item: NoteLinkItem,
            accessibilityPrefix: String,
            target: AnyObject,
            action: Selector
        ) {
            self.item = item
            super.init(frame: .zero)
            title = item.title
            toolTip = item.url.path
            setAccessibilityLabel("\(accessibilityPrefix) \(item.title)")
            setAccessibilityHelp("在当前资料库窗口打开")
            bezelStyle = .shadowlessSquare
            isBordered = false
            controlSize = .small
            font = .systemFont(ofSize: 12, weight: .regular)
            attributedTitle = NSAttributedString(string: item.title, attributes: [
                .font: font!, .foregroundColor: NSColor.labelColor
            ])
            lineBreakMode = .byTruncatingTail
            alignment = .left
            contentTintColor = .labelColor
            self.target = target
            self.action = action
            setContentHuggingPriority(.defaultHigh, for: .horizontal)
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    var onOpen: ((URL) -> Void)?
    var onPinChanged: ((Bool) -> Void)?
    var onLayoutChanged: (() -> Void)?
    private(set) var isPinned = false
    private(set) var linkRelations = NoteLinkRelations.empty
    private var hasRenderedRelations = false
    private var isExpanded = true

    private lazy var pinButton: NSButton = {
        let button = NSButton(image: NSImage(systemSymbolName: "pin", accessibilityDescription: "固定双向链接")!, target: self, action: #selector(togglePin))
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.identifier = NSUserInterfaceItemIdentifier("LibraryRelationsPin")
        button.toolTip = "固定在底部"
        button.setAccessibilityLabel("固定双向链接到底部")
        return button
    }()

    private lazy var disclosureButton: NSButton = {
        let button = NSButton(title: "双向链接", target: self, action: #selector(toggleExpanded(_:)))
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.font = .systemFont(ofSize: 11, weight: .regular)
        button.imagePosition = .imageLeading
        button.identifier = NSUserInterfaceItemIdentifier("LibraryRelationsDisclosure")
        return button
    }()

    private let outgoingContent = NSStackView()
    private let incomingContent = NSStackView()
    private lazy var outgoingRow = relationRow(
        title: "引用",
        accessibilityPrefix: "打开引用笔记",
        content: outgoingContent
    )
    private lazy var incomingRow = relationRow(
        title: "被引用",
        accessibilityPrefix: "打开反向引用笔记",
        content: incomingContent
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("LibraryNoteLinksView")
        setAccessibilityLabel("双向链接")
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        [outgoingContent, incomingContent].forEach {
            $0.orientation = .vertical
            $0.alignment = .leading
            $0.spacing = 5
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [disclosureButton, spacer, pinButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let stack = NSStackView(views: [header, outgoingRow, incomingRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            outgoingRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            incomingRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20)
        ])

        update(.empty)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ relations: NoteLinkRelations) {
        guard !hasRenderedRelations || linkRelations != relations else { return }
        hasRenderedRelations = true
        linkRelations = relations
        populate(outgoingContent, with: relations.outgoing, accessibilityPrefix: "打开引用笔记")
        populate(incomingContent, with: relations.incoming, accessibilityPrefix: "打开反向引用笔记")
        updateVisibility()
        updateExpandedPresentation()
    }

    @objc private func togglePin() {
        isPinned.toggle()
        pinButton.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: nil)
        pinButton.toolTip = isPinned ? "取消固定，跟随正文滚动" : "固定在底部"
        pinButton.setAccessibilityLabel(isPinned ? "取消固定双向链接" : "固定双向链接到底部")
        pinButton.contentTintColor = isPinned ? .labelColor : .secondaryLabelColor
        onPinChanged?(isPinned)
    }

    @objc private func toggleExpanded(_ sender: NSButton) {
        isExpanded.toggle()
        updateExpandedPresentation()
    }

    private func updateExpandedPresentation() {
        outgoingRow.isHidden = !isExpanded || linkRelations.outgoing.isEmpty
        incomingRow.isHidden = !isExpanded || linkRelations.incoming.isEmpty
        disclosureButton.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        disclosureButton.setAccessibilityLabel(isExpanded ? "收起双向链接" : "展开双向链接")
        disclosureButton.toolTip = isExpanded ? "收起双向链接" : "展开双向链接"
        onLayoutChanged?()
    }

    private func relationRow(
        title: String,
        accessibilityPrefix: String,
        content: NSStackView
    ) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let row = NSStackView(views: [label, content])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .top
        row.spacing = 8
        content.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true
        row.setAccessibilityLabel(title)
        row.setAccessibilityHelp(accessibilityPrefix)
        return row
    }

    private func populate(
        _ stack: NSStackView,
        with items: [NoteLinkItem],
        accessibilityPrefix: String
    ) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let visibleItems = items.prefix(4)
        for item in visibleItems {
            stack.addArrangedSubview(RelationButton(
                item: item,
                accessibilityPrefix: accessibilityPrefix,
                target: self,
                action: #selector(relationButtonPressed(_:))
            ))
        }
        let remaining = items.dropFirst(visibleItems.count)
        guard !remaining.isEmpty else { return }
        let moreButton = NSPopUpButton(frame: .zero, pullsDown: true)
        moreButton.bezelStyle = .inline
        moreButton.controlSize = .small
        moreButton.font = .systemFont(ofSize: 12, weight: .medium)
        moreButton.setAccessibilityLabel("更多\(accessibilityPrefix)")
        let menu = moreButton.menu ?? NSMenu()
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "+\(remaining.count)", action: nil, keyEquivalent: ""))
        for item in remaining {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(relationMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.url
            menu.addItem(menuItem)
        }
        moreButton.menu = menu
        stack.addArrangedSubview(moreButton)
    }

    @objc private func relationButtonPressed(_ sender: RelationButton) {
        onOpen?(sender.item.url)
    }

    @objc private func relationMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpen?(url)
    }
}
