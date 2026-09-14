import AppKit

@MainActor
final class LibraryDocumentTabView: NSView {
    let tabID: UUID
    private let selected: Bool
    private let selectButton = NSButton()
    private let closeButton = NSButton()
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onCloseOthers: (() -> Void)?

    init(tab: LibraryDocumentTab, selected: Bool) {
        tabID = tab.id
        self.selected = selected
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("LibraryTab:\(tab.id)")
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(selected ? 0.075 : 0).cgColor
        selectButton.title = (tab.saveFailed ? "! " : (tab.isDirty ? "• " : "")) + tab.title
        selectButton.contentTintColor = tab.saveFailed ? .systemRed : .labelColor
        selectButton.toolTip = tab.url?.path ?? "新标签页"
        selectButton.setAccessibilityLabel(tab.title)
        selectButton.setAccessibilityValue(selected ? "已选中" : "未选中")
        selectButton.font = .systemFont(ofSize: 12, weight: selected ? .medium : .regular)
        selectButton.isBordered = false
        selectButton.alignment = .left
        selectButton.lineBreakMode = .byTruncatingTail
        selectButton.target = self
        selectButton.action = #selector(selectPressed)
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签页")
        closeButton.image?.size = NSSize(width: 9, height: 9)
        closeButton.isBordered = false
        closeButton.toolTip = "关闭 \(tab.title)"
        closeButton.setAccessibilityLabel("关闭 \(tab.title)")
        closeButton.target = self
        closeButton.action = #selector(closePressed)
        for view in [selectButton, closeButton] { addSubview(view); view.translatesAutoresizingMaskIntoConstraints = false }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 170), heightAnchor.constraint(equalToConstant: 30),
            selectButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            selectButton.topAnchor.constraint(equalTo: topAnchor), selectButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            selectButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
            closeButton.widthAnchor.constraint(equalToConstant: 20), closeButton.heightAnchor.constraint(equalToConstant: 24),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(selected ? 0.075 : 0).cgColor
    }
    @objc private func selectPressed() { onSelect?() }
    @objc private func closePressed() { onClose?() }
    @objc private func closeOthersPressed() { onCloseOthers?() }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        for (title, action) in [("关闭标签页", #selector(closePressed)), ("关闭其他标签页", #selector(closeOthersPressed))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        return menu
    }
}
