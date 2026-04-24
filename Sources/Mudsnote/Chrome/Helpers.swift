import AppKit
import CryptoKit

@MainActor
func displayPath(_ url: URL) -> String {
    (url.path as NSString).abbreviatingWithTildeInPath
}

func sha256Hex(_ value: String) -> String {
    let digest = SHA256.hash(data: Data(value.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

@MainActor
func chooseDirectory(startingAt directory: URL?) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.prompt = "Choose"
    panel.directoryURL = directory

    guard panel.runModal() == .OK else { return nil }
    return panel.url
}

@MainActor
func pin(_ child: NSView, to parent: NSView, insets: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0)) {
    child.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
        child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: insets.left),
        child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -insets.right),
        child.topAnchor.constraint(equalTo: parent.topAnchor, constant: insets.top),
        child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -insets.bottom)
    ])
}

@MainActor
func insetted(_ content: NSView, padding: NSEdgeInsets) -> NSView {
    let wrapper = NSView()
    wrapper.addSubview(content)
    pin(content, to: wrapper, insets: padding)
    return wrapper
}

@MainActor
func positionPanelNearTopCenter(_ window: NSWindow, topMargin: CGFloat = 72) {
    let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }

    let frame = screen.visibleFrame
    let origin = NSPoint(
        x: frame.midX - (window.frame.width / 2),
        y: frame.maxY - window.frame.height - topMargin
    )
    window.setFrameOrigin(origin)
}
