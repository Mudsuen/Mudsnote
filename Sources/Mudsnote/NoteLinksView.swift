import AppKit
import MudsnoteCore

final class NoteLinksView: NSView {
    private final class LinkButton: NSButton {
        let url: URL

        init(item: NoteLinkItem, target: AnyObject, action: Selector) {
            self.url = item.url
            super.init(frame: .zero)
            title = item.title
            toolTip = item.url.path
            setAccessibilityLabel("打开关联笔记 \(item.title)")
            bezelStyle = .inline
            controlSize = .small
            font = .systemFont(ofSize: 11, weight: .medium)
            lineBreakMode = .byTruncatingTail
            contentTintColor = .controlAccentColor
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

    private let incomingContent = NSStackView()
    private let outgoingContent = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("LibraryNoteLinksView")
        setAccessibilityLabel("双链关系")
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
        layer?.cornerRadius = 8

        let titleLabel = NSTextField(labelWithString: "双链关系")
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor

        configureContentStack(incomingContent)
        configureContentStack(outgoingContent)

        let incomingRow = relationRow(title: "链接到此笔记", content: incomingContent)
        let outgoingRow = relationRow(title: "此笔记链接", content: outgoingContent)
        let stack = NSStackView(views: [titleLabel, incomingRow, outgoingRow])
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
            incomingRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            outgoingRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20)
        ])

        update(.empty)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ relations: NoteLinkRelations) {
        populate(incomingContent, with: relations.incoming)
        populate(outgoingContent, with: relations.outgoing)
        let isEmpty = relations.incoming.isEmpty && relations.outgoing.isEmpty
        isHidden = isEmpty
        incomingContent.superview?.isHidden = relations.incoming.isEmpty
        outgoingContent.superview?.isHidden = relations.outgoing.isEmpty
    }

    private func configureContentStack(_ stack: NSStackView) {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
    }

    private func relationRow(title: String, content: NSStackView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let row = NSStackView(views: [label, content])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    private func populate(_ stack: NSStackView, with items: [NoteLinkItem]) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        let visibleItems = items.prefix(4)
        for item in visibleItems {
            stack.addArrangedSubview(LinkButton(
                item: item,
                target: self,
                action: #selector(linkButtonPressed(_:))
            ))
        }

        guard items.count > visibleItems.count else { return }
        let remaining = items.dropFirst(visibleItems.count)
        let moreButton = NSPopUpButton(frame: .zero, pullsDown: true)
        moreButton.bezelStyle = .inline
        moreButton.controlSize = .small
        moreButton.font = .systemFont(ofSize: 11, weight: .medium)
        let menu = moreButton.menu ?? NSMenu()
        menu.removeAllItems()
        menu.addItem(NSMenuItem(title: "+\(remaining.count)", action: nil, keyEquivalent: ""))
        for item in remaining {
            let menuItem = NSMenuItem(
                title: item.title,
                action: #selector(linkMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = item.url
            menu.addItem(menuItem)
        }
        moreButton.menu = menu
        stack.addArrangedSubview(moreButton)
    }

    @objc
    private func linkButtonPressed(_ sender: LinkButton) {
        onOpen?(sender.url)
    }

    @objc
    private func linkMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpen?(url)
    }
}
