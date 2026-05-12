import AppKit
import Carbon.HIToolbox

@MainActor
final class ShortcutRecordingWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? ShortcutRecorderButton,
           recorder.isRecording,
           recorder.recordShortcutEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let recorder = firstResponder as? ShortcutRecorderButton,
           recorder.isRecording,
           recorder.recordShortcutEvent(event) {
            return
        }
        super.keyDown(with: event)
    }
}

@MainActor
final class ShortcutRecorderButton: NSButton {
    private(set) var shortcutSpec: HotKeySpec?
    private(set) var isRecording = false
    private var statusResetWorkItem: DispatchWorkItem?

    var shortcutString: String {
        shortcutSpec?.displayString ?? ""
    }

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setButtonType(.momentaryChange)
        bezelStyle = .rounded
        controlSize = .regular
        alignment = .center
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        focusRingType = .default
        widthAnchor.constraint(equalToConstant: 260).isActive = true
        updateTitle()
    }

    convenience init(shortcutString: String) {
        self.init(frame: .zero)
        setShortcutString(shortcutString)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setShortcutString(_ value: String) {
        shortcutSpec = HotKeySpec.parse(value)
        isRecording = false
        updateTitle()
    }

    override func mouseDown(with event: NSEvent) {
        beginRecording()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        updateTitle()
        return super.resignFirstResponder()
    }

    @discardableResult
    func recordShortcutEvent(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }

        if event.keyCode == UInt16(kVK_Escape) {
            isRecording = false
            updateTitle()
            return true
        }

        guard let spec = HotKeySpec.from(event: event) else {
            showTemporaryMessage("请按包含 ⌘ / ⌥ / ⌃ 的组合键")
            NSSound.beep()
            return true
        }

        shortcutSpec = spec
        isRecording = false
        updateTitle()
        sendAction(action, to: target)
        return true
    }

    private func beginRecording() {
        statusResetWorkItem?.cancel()
        isRecording = true
        window?.makeFirstResponder(self)
        title = "按下新的快捷键"
        toolTip = "按下一个包含 Command、Option 或 Control 的组合键，按 Esc 取消"
        needsDisplay = true
    }

    private func updateTitle() {
        statusResetWorkItem?.cancel()
        if isRecording {
            title = "按下新的快捷键"
            toolTip = "按下一个包含 Command、Option 或 Control 的组合键，按 Esc 取消"
        } else if let shortcutSpec {
            title = shortcutSpec.userVisibleString
            toolTip = "点击后重新录入快捷键"
        } else {
            title = "点击录入快捷键"
            toolTip = "点击后按下一个包含 Command、Option 或 Control 的组合键"
        }
        needsDisplay = true
    }

    private func showTemporaryMessage(_ message: String) {
        statusResetWorkItem?.cancel()
        title = message

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateTitle()
        }
        statusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: workItem)
    }
}
