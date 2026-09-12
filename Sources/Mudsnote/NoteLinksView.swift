import AppKit
import MudsnoteCore

final class NoteLinksView: NSView {
    private final class RelationButton: NSButton {
        let item: KnowledgeRelationItem

        init(
            item: KnowledgeRelationItem,
            accessibilityPrefix: String,
            target: AnyObject,
            action: Selector
        ) {
            self.item = item
            super.init(frame: .zero)
            title = item.title
            toolTip = [item.reason, item.url.path].compactMap { $0 }.joined(separator: "\n")
            setAccessibilityLabel("\(accessibilityPrefix) \(item.title)")
            setAccessibilityHelp("在当前资料库窗口打开")
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

    private final class SuggestionView: NSStackView {
        let item: KnowledgeRelationItem

        init(
            item: KnowledgeRelationItem,
            openTarget: AnyObject,
            openAction: Selector,
            acceptTarget: AnyObject,
            acceptAction: Selector
        ) {
            self.item = item
            let openButton = RelationButton(
                item: item,
                accessibilityPrefix: "打开建议关联笔记",
                target: openTarget,
                action: openAction
            )
            let acceptButton = NSButton(
                title: "关联",
                target: acceptTarget,
                action: acceptAction
            )
            acceptButton.bezelStyle = .inline
            acceptButton.controlSize = .small
            acceptButton.font = .systemFont(ofSize: 10, weight: .semibold)
            acceptButton.setAccessibilityLabel("接受建议，关联 \(item.title)")
            acceptButton.setAccessibilityHelp("在当前笔记末尾插入明确的 Markdown 链接")
            let reasonLabel = NSTextField(labelWithString: item.reason ?? "内容相关")
            reasonLabel.font = .systemFont(ofSize: 9)
            reasonLabel.textColor = .tertiaryLabelColor
            reasonLabel.lineBreakMode = .byTruncatingTail
            reasonLabel.toolTip = item.reason
            reasonLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            reasonLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            super.init(frame: .zero)
            orientation = .horizontal
            alignment = .centerY
            spacing = 2
            addArrangedSubview(openButton)
            addArrangedSubview(reasonLabel)
            addArrangedSubview(acceptButton)
            setContentHuggingPriority(.defaultHigh, for: .horizontal)
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    var onOpen: ((URL) -> Void)?
    var onAcceptSuggestion: ((KnowledgeRelationItem) -> Void)?
    var onGoBack: (() -> Void)?
    var onGoForward: (() -> Void)?
    // Legacy callbacks remain source-compatible while stored notes keep their original metadata.
    var onGenerateHigherLayer: ((KnowledgeLayer) -> Void)?
    var onShowGraph: (() -> Void)?
    private var synthesisTargetLayer: KnowledgeLayer?
    private(set) var knowledgeRelations = KnowledgeRelations.empty
    private(set) var isExpanded = false
    private let disclosure = NSButton()
    private let parentsContent = NSStackView()
    private let childrenContent = NSStackView()
    private let suggestedContent = NSStackView()
    private let details = NSStackView()
    private lazy var backButton = navigationButton(title: "‹", accessibilityLabel: "返回上一条笔记", action: #selector(backPressed(_:)))
    private lazy var forwardButton = navigationButton(title: "›", accessibilityLabel: "前进到下一条笔记", action: #selector(forwardPressed(_:)))
    private lazy var incomingRow = relationRow(title: "被引用", accessibilityPrefix: "引用当前笔记", content: parentsContent)
    private lazy var outgoingRow = relationRow(title: "链接到", accessibilityPrefix: "当前笔记链接", content: childrenContent)
    private lazy var suggestedRow = relationRow(title: "建议链接", accessibilityPrefix: "相关笔记", content: suggestedContent)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("LibraryNoteLinksView")
        setAccessibilityLabel("双链")
        disclosure.bezelStyle = .inline
        disclosure.font = .systemFont(ofSize: 11, weight: .medium)
        disclosure.target = self
        disclosure.action = #selector(toggleExpanded)
        disclosure.setAccessibilityLabel("展开或收起双链")
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [disclosure, spacer, backButton, forwardButton])
        header.spacing = 6
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 8
        [parentsContent, childrenContent, suggestedContent].forEach(configureContentStack)
        [incomingRow, outgoingRow, suggestedRow].forEach(details.addArrangedSubview)
        details.isHidden = true
        let stack = NSStackView(views: [header, details])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            details.widthAnchor.constraint(equalTo: stack.widthAnchor),
            incomingRow.widthAnchor.constraint(equalTo: details.widthAnchor),
            outgoingRow.widthAnchor.constraint(equalTo: details.widthAnchor),
            suggestedRow.widthAnchor.constraint(equalTo: details.widthAnchor)
        ])
        update(links: .empty, suggestions: [])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ relations: KnowledgeRelations) {
        knowledgeRelations = relations
        let items = relations.parents + relations.children + relations.related
        update(links: NoteLinkRelations(incoming: [], outgoing: items.map {
            NoteLinkItem(url: $0.url, title: $0.title)
        }), suggestions: relations.suggested)
    }

    func update(links: NoteLinkRelations, suggestions: [KnowledgeRelationItem]) {
        populate(parentsContent, with: links.incoming.map { KnowledgeRelationItem(url: $0.url, title: $0.title) }, accessibilityPrefix: "打开引用笔记")
        populate(childrenContent, with: links.outgoing.map { KnowledgeRelationItem(url: $0.url, title: $0.title) }, accessibilityPrefix: "打开链接笔记")
        populateSuggestions(suggestedContent, with: suggestions)
        incomingRow.isHidden = links.incoming.isEmpty
        outgoingRow.isHidden = links.outgoing.isEmpty
        suggestedRow.isHidden = suggestions.isEmpty
        let count = Set((links.incoming + links.outgoing).map { $0.url.standardizedFileURL }).count
        disclosure.title = "双链 · \(count)  \(isExpanded ? "⌃" : "⌄")"
        disclosure.setAccessibilityValue(isExpanded ? "已展开" : "已收起")
    }

    @objc func toggleExpanded() {
        isExpanded.toggle()
        details.isHidden = !isExpanded
        disclosure.title = disclosure.title.replacingOccurrences(of: isExpanded ? "⌄" : "⌃", with: isExpanded ? "⌃" : "⌄")
        disclosure.setAccessibilityValue(isExpanded ? "已展开" : "已收起")
    }

    func updateNavigation(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        backButton.isHidden = !canGoBack && !canGoForward
        forwardButton.isHidden = !canGoBack && !canGoForward
    }

    func setSynthesisInProgress(_ isInProgress: Bool) {}

    private func navigationButton(
        title: String,
        accessibilityLabel: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.setAccessibilityLabel(accessibilityLabel)
        button.isEnabled = false
        return button
    }

    @objc
    private func backPressed(_ sender: NSButton) {
        onGoBack?()
    }

    @objc
    private func forwardPressed(_ sender: NSButton) {
        onGoForward?()
    }

    @objc
    private func generateHigherLayerPressed(_ sender: NSButton) {
        guard let targetLayer = synthesisTargetLayer else { return }
        onGenerateHigherLayer?(targetLayer)
    }

    @objc
    private func showGraphPressed(_ sender: NSButton) {
        onShowGraph?()
    }

    private func configureContentStack(_ stack: NSStackView) {
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
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
        label.widthAnchor.constraint(equalToConstant: 76).isActive = true

        let row = NSStackView(views: [label, content])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setAccessibilityLabel(title)
        row.setAccessibilityHelp(accessibilityPrefix)
        return row
    }

    private func populate(
        _ stack: NSStackView,
        with items: [KnowledgeRelationItem],
        accessibilityPrefix: String
    ) {
        clear(stack)
        let visibleItems = items.prefix(4)
        for item in visibleItems {
            stack.addArrangedSubview(RelationButton(
                item: item,
                accessibilityPrefix: accessibilityPrefix,
                target: self,
                action: #selector(relationButtonPressed(_:))
            ))
        }
        addOverflow(
            to: stack,
            remaining: items.dropFirst(visibleItems.count),
            accessibilityPrefix: accessibilityPrefix
        )
    }

    private func populateSuggestions(
        _ stack: NSStackView,
        with items: [KnowledgeRelationItem]
    ) {
        clear(stack)
        let visibleItems = items.prefix(3)
        for item in visibleItems {
            stack.addArrangedSubview(SuggestionView(
                item: item,
                openTarget: self,
                openAction: #selector(relationButtonPressed(_:)),
                acceptTarget: self,
                acceptAction: #selector(acceptSuggestionPressed(_:))
            ))
        }
        addOverflow(
            to: stack,
            remaining: items.dropFirst(visibleItems.count),
            accessibilityPrefix: "打开建议关联笔记"
        )
    }

    private func clear(_ stack: NSStackView) {
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
    }

    private func addOverflow(
        to stack: NSStackView,
        remaining: ArraySlice<KnowledgeRelationItem>,
        accessibilityPrefix: String
    ) {
        guard !remaining.isEmpty else { return }
        let moreButton = NSPopUpButton(frame: .zero, pullsDown: true)
        moreButton.bezelStyle = .inline
        moreButton.controlSize = .small
        moreButton.font = .systemFont(ofSize: 11, weight: .medium)
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

    @objc
    private func relationButtonPressed(_ sender: RelationButton) {
        onOpen?(sender.item.url)
    }

    @objc
    private func acceptSuggestionPressed(_ sender: NSButton) {
        guard let suggestion = sender.superview as? SuggestionView else { return }
        onAcceptSuggestion?(suggestion.item)
    }

    @objc
    private func relationMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpen?(url)
    }
}
