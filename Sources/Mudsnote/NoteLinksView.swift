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
            font = .systemFont(ofSize: 12, weight: .medium)
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
            acceptButton.font = .systemFont(ofSize: 11, weight: .semibold)
            acceptButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            acceptButton.setAccessibilityLabel("接受建议，关联 \(item.title)")
            acceptButton.setAccessibilityHelp("在当前笔记末尾插入明确的 Markdown 链接")
            let reasonLabel = NSTextField(labelWithString: item.reason ?? "内容相关")
            reasonLabel.font = .systemFont(ofSize: 11)
            reasonLabel.textColor = .secondaryLabelColor
            reasonLabel.lineBreakMode = .byTruncatingTail
            reasonLabel.toolTip = item.reason
            reasonLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            reasonLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            super.init(frame: .zero)
            orientation = .horizontal
            alignment = .centerY
            spacing = 8
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
    var onGenerateHigherLayer: ((KnowledgeLayer) -> Void)?
    var onShowGraph: (() -> Void)?
    private(set) var knowledgeRelations = KnowledgeRelations.empty
    private var hasRenderedRelations = false
    private var synthesisTargetLayer: KnowledgeLayer?

    private var isExpanded = true
    private lazy var disclosureButton: NSButton = {
        let button = NSButton(title: "知识关系", target: self, action: #selector(toggleExpanded(_:)))
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.imagePosition = .imageLeading
        button.identifier = NSUserInterfaceItemIdentifier("LibraryRelationsDisclosure")
        return button
    }()
    private let layerLabel = NSTextField(labelWithString: "")
    private lazy var backButton = navigationButton(
        title: "‹",
        accessibilityLabel: "返回上一条知识关系",
        action: #selector(backPressed(_:))
    )
    private lazy var forwardButton = navigationButton(
        title: "›",
        accessibilityLabel: "前进到下一条知识关系",
        action: #selector(forwardPressed(_:))
    )
    private lazy var synthesisButton: NSButton = {
        let button = NSButton(title: "", target: self, action: #selector(generateHigherLayerPressed(_:)))
        button.bezelStyle = .inline
        button.controlSize = .small
        button.font = .systemFont(ofSize: 10, weight: .semibold)
        button.setAccessibilityHelp("使用当前笔记与关联笔记生成待审核草案")
        button.isHidden = true
        return button
    }()
    private lazy var graphButton: NSButton = {
        let image = NSImage(
            systemSymbolName: "point.3.connected.trianglepath.dotted",
            accessibilityDescription: "打开知识图谱"
        ) ?? NSImage()
        let button = NSButton(
            image: image,
            target: self,
            action: #selector(showGraphPressed(_:))
        )
        button.bezelStyle = .inline
        button.controlSize = .small
        button.toolTip = "查看当前笔记的可视化知识图谱"
        button.setAccessibilityLabel("打开当前笔记知识图谱")
        button.setAccessibilityHelp("在独立窗口查看已确认的知识关系")
        return button
    }()
    private let parentsContent = NSStackView()
    private let childrenContent = NSStackView()
    private let relatedContent = NSStackView()
    private let suggestedContent = NSStackView()
    private lazy var parentsRow = relationRow(
        title: "上层",
        accessibilityPrefix: "打开上层笔记",
        content: parentsContent
    )
    private lazy var childrenRow = relationRow(
        title: "下层",
        accessibilityPrefix: "打开下层笔记",
        content: childrenContent
    )
    private lazy var relatedRow = relationRow(
        title: "明确关联",
        accessibilityPrefix: "打开明确关联笔记",
        content: relatedContent
    )
    private lazy var suggestedRow = relationRow(
        title: "建议关联",
        accessibilityPrefix: "打开建议关联笔记",
        content: suggestedContent
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("LibraryNoteLinksView")
        setAccessibilityLabel("知识关系")
        wantsLayer = true
        layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
        layer?.cornerRadius = 8

        layerLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        layerLabel.textColor = .tertiaryLabelColor

        [parentsContent, childrenContent, relatedContent, suggestedContent].forEach {
            configureContentStack($0)
        }

        suggestedContent.orientation = .vertical
        suggestedContent.alignment = .leading
        suggestedContent.spacing = 6

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [
            disclosureButton,
            layerLabel,
            spacer,
            synthesisButton,
            graphButton,
            backButton,
            forwardButton
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        let stack = NSStackView(views: [
            header,
            parentsRow,
            childrenRow,
            relatedRow,
            suggestedRow
        ])
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
            parentsRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            childrenRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            relatedRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20),
            suggestedRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20)
        ])

        update(.empty)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ relations: KnowledgeRelations) {
        guard !hasRenderedRelations || knowledgeRelations != relations else { return }
        hasRenderedRelations = true
        knowledgeRelations = relations
        layerLabel.stringValue = relations.currentLayer.map {
            "当前：\($0.displayName)"
        } ?? "未分层"
        populate(parentsContent, with: relations.parents, accessibilityPrefix: "打开上层笔记")
        populate(childrenContent, with: relations.children, accessibilityPrefix: "打开下层笔记")
        populate(relatedContent, with: relations.related, accessibilityPrefix: "打开明确关联笔记")
        populateSuggestions(suggestedContent, with: relations.suggested)

        updateExpandedPresentation()
        isHidden = false
        if let targetLayer = relations.currentLayer?.nextHigher,
           targetLayer == .line || targetLayer == .plane {
            synthesisButton.title = "生成\(targetLayer.displayName)层草案"
            synthesisButton.setAccessibilityLabel("生成\(targetLayer.displayName)层草案")
            synthesisTargetLayer = targetLayer
            synthesisButton.isHidden = false
        } else {
            synthesisTargetLayer = nil
            synthesisButton.isHidden = true
        }
    }

    @objc private func toggleExpanded(_ sender: NSButton) {
        isExpanded.toggle()
        updateExpandedPresentation()
    }

    private func updateExpandedPresentation() {
        parentsRow.isHidden = !isExpanded || knowledgeRelations.parents.isEmpty
        childrenRow.isHidden = !isExpanded || knowledgeRelations.children.isEmpty
        relatedRow.isHidden = !isExpanded || knowledgeRelations.related.isEmpty
        suggestedRow.isHidden = !isExpanded || knowledgeRelations.suggested.isEmpty
        // The graph action remains available even when there are no relations.
        disclosureButton.image = NSImage(
            systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )
        disclosureButton.setAccessibilityLabel(isExpanded ? "收起知识关系" : "展开知识关系")
        disclosureButton.toolTip = isExpanded ? "收起知识关系" : "展开知识关系"
    }

    func updateNavigation(canGoBack: Bool, canGoForward: Bool) {
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
    }

    func setSynthesisInProgress(_ isInProgress: Bool) {
        synthesisButton.isEnabled = !isInProgress
        if isInProgress {
            synthesisButton.title = "正在生成…"
        } else if let targetLayer = knowledgeRelations.currentLayer?.nextHigher,
                  targetLayer == .line || targetLayer == .plane {
            synthesisButton.title = "生成\(targetLayer.displayName)层草案"
        }
    }

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
        row.alignment = .top
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
            let suggestion = SuggestionView(
                item: item,
                openTarget: self,
                openAction: #selector(relationButtonPressed(_:)),
                acceptTarget: self,
                acceptAction: #selector(acceptSuggestionPressed(_:))
            )
            stack.addArrangedSubview(suggestion)
            suggestion.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
