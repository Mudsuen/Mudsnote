import AppKit

@MainActor
final class LibraryDocumentTabView: NSView {
    static let minimumWidth: CGFloat = 96
    static let maximumWidth: CGFloat = 168
    static let height: CGFloat = 26

    let tabID: UUID
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?

    init(tab: LibraryDocumentTab, selected: Bool) {
        tabID = tab.id
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("LibraryDocumentTab-\(tab.id)")
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(selected ? 0.075 : 0).cgColor

        let titleButton = NSButton(title: (tab.isDirty ? "• " : "") + tab.title, target: self, action: #selector(selectPressed))
        titleButton.identifier = NSUserInterfaceItemIdentifier("LibraryDocumentTabTitle")
        titleButton.isBordered = false
        titleButton.alignment = .left
        titleButton.lineBreakMode = .byTruncatingTail
        titleButton.font = .systemFont(ofSize: 12, weight: selected ? .semibold : .regular)
        titleButton.contentTintColor = selected ? .labelColor : .secondaryLabelColor
        titleButton.toolTip = tab.url?.path ?? "新标签页"
        titleButton.setAccessibilityLabel(tab.title)
        titleButton.setAccessibilityValue(selected ? "已选中" : "未选中")

        let closeButton = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭标签页")!, target: self, action: #selector(closePressed))
        closeButton.identifier = NSUserInterfaceItemIdentifier("LibraryDocumentTabClose")
        closeButton.isBordered = false
        closeButton.image = closeButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )
        closeButton.contentTintColor = selected ? .secondaryLabelColor : .tertiaryLabelColor
        closeButton.toolTip = "关闭 \(tab.title)"

        addSubview(titleButton)
        addSubview(closeButton)
        titleButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.preferredWidth(title: tab.title, isDirty: tab.isDirty)),
            heightAnchor.constraint(equalToConstant: Self.height),
            titleButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            titleButton.topAnchor.constraint(equalTo: topAnchor),
            titleButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            titleButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -3),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 18),
            closeButton.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    static func preferredWidth(title: String, isDirty: Bool) -> CGFloat {
        let displayedTitle = (isDirty ? "• " : "") + title
        let titleWidth = ceil((displayedTitle as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold)
        ]).width)
        return min(maximumWidth, max(minimumWidth, titleWidth + 48))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func selectPressed() { onSelect?() }
    @objc private func closePressed() { onClose?() }
}
