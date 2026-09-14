import AppKit

/// Keeps an action's target alive without borrowing changing table selection.
@MainActor
final class LibraryContextMenuItem: NSMenuItem {
    private let handler: (NSMenuItem) -> Void

    init(original: NSMenuItem, handler: @escaping (NSMenuItem) -> Void) {
        self.handler = handler
        super.init(title: original.title, action: #selector(invoke), keyEquivalent: original.keyEquivalent)
        target = self
        image = original.image
        state = original.state
        isEnabled = original.isEnabled
        representedObject = original.representedObject
        tag = original.tag
        keyEquivalentModifierMask = original.keyEquivalentModifierMask
    }

    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler(self) }
}
