import AppKit

/// Empty space in the scrollable icon strip remains a native window drag region.
@MainActor
final class LibraryWindowDragHandle: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// Icon-only navigation keeps the full folder name available to hover and VoiceOver.
@MainActor
final class LibraryFolderShortcutButton: NSButton {
    let folderURL: URL?

    init(folderURL: URL?, symbol: String, label: String, target: AnyObject, action: Selector) {
        self.folderURL = folderURL
        super.init(frame: .zero)
        title = ""
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        imagePosition = .imageOnly
        bezelStyle = .recessed
        setButtonType(.pushOnPushOff)
        isBordered = true
        showsBorderOnlyWhileMouseInside = true
        self.target = target
        self.action = action
        toolTip = label
        setAccessibilityLabel(label)
        identifier = NSUserInterfaceItemIdentifier("LibraryFolderShortcut:\(folderURL?.standardizedFileURL.path ?? "home")")
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds) }
        return accepted
    }
}
