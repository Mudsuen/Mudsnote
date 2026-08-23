import AppKit

private final class LinkEditorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LinkEditorSheetController: NSWindowController, NSTextFieldDelegate {
    static let compactContentSize = NSSize(width: 332, height: 156)

    let destinationField = NSTextField(string: "")
    let nameField = NSTextField(string: "")
    let confirmButton = NSButton(title: "确定", target: nil, action: nil)
    let cancelButton = NSButton(title: "取消", target: nil, action: nil)

    private let onSubmit: (String, String) -> Void
    private let onDismiss: () -> Void
    private var hasFinished = false

    init(
        title: String,
        destination: String,
        name: String,
        onSubmit: @escaping (String, String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss

        let window = LinkEditorWindow(
            contentRect: NSRect(origin: .zero, size: Self.compactContentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentView = makeCompactSurface()

        destinationField.stringValue = destination
        nameField.stringValue = name
        buildContent(title: title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func beginSheet(for parentWindow: NSWindow) {
        guard let window else { return }
        parentWindow.beginSheet(window)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window.makeFirstResponder(destinationField)
            destinationField.selectText(nil)
        }
    }

    func submitForTesting() {
        submit()
    }

    func cancelForTesting() {
        cancel()
    }

    func controlTextDidChange(_ obj: Notification) {
        updateConfirmState()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancel()
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)), confirmButton.isEnabled {
            submit()
            return true
        }
        return false
    }

    private func buildContent(title: String) {
        guard let contentView = window?.contentView else { return }

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.identifier = NSUserInterfaceItemIdentifier("LinkEditorTitle")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.alignment = .left

        let destinationLabel = NSTextField(labelWithString: "链接到")
        destinationLabel.font = .systemFont(ofSize: 12, weight: .regular)
        destinationLabel.textColor = .secondaryLabelColor
        destinationLabel.alignment = .right

        destinationField.identifier = NSUserInterfaceItemIdentifier("LinkEditorDestinationField")
        destinationField.placeholderString = "输入 URL"
        destinationField.delegate = self
        destinationField.setAccessibilityLabel("链接到")
        configureCompactField(destinationField)

        let nameLabel = NSTextField(labelWithString: "名称")
        nameLabel.font = .systemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.alignment = .right

        nameField.identifier = NSUserInterfaceItemIdentifier("LinkEditorNameField")
        nameField.placeholderString = "可选"
        nameField.delegate = self
        nameField.setAccessibilityLabel("名称")
        configureCompactField(nameField)

        confirmButton.identifier = NSUserInterfaceItemIdentifier("LinkEditorConfirmButton")
        confirmButton.target = self
        confirmButton.action = #selector(confirmPressed)
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelStyle = .rounded
        confirmButton.bezelColor = panelAccentColor()
        confirmButton.controlSize = .small

        cancelButton.identifier = NSUserInterfaceItemIdentifier("LinkEditorCancelButton")
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .small

        let buttonStack = NSStackView(views: [cancelButton, confirmButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        for view in [titleLabel, destinationLabel, destinationField, nameLabel, nameField, buttonStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 13),
            titleLabel.leadingAnchor.constraint(equalTo: destinationField.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: destinationField.trailingAnchor),

            destinationLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            destinationLabel.widthAnchor.constraint(equalToConstant: 42),
            destinationLabel.centerYAnchor.constraint(equalTo: destinationField.centerYAnchor),
            destinationField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 13),
            destinationField.leadingAnchor.constraint(equalTo: destinationLabel.trailingAnchor, constant: 8),
            destinationField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            destinationField.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: destinationLabel.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: destinationLabel.trailingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: nameField.centerYAnchor),
            nameField.topAnchor.constraint(equalTo: destinationField.bottomAnchor, constant: 9),
            nameField.leadingAnchor.constraint(equalTo: destinationField.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: destinationField.trailingAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 28),

            buttonStack.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(equalTo: destinationField.trailingAnchor),
            buttonStack.heightAnchor.constraint(equalToConstant: 24),
            buttonStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        window?.defaultButtonCell = confirmButton.cell as? NSButtonCell
        updateConfirmState()
    }

    private func makeCompactSurface() -> NSView {
        let surface = NSView(frame: NSRect(origin: .zero, size: Self.compactContentSize))
        surface.identifier = NSUserInterfaceItemIdentifier("LinkEditorCompactSurface")
        surface.wantsLayer = true
        surface.layer?.cornerRadius = 12
        surface.layer?.masksToBounds = true
        surface.layer?.borderWidth = 1
        surface.layer?.borderColor = panelSeparatorColor(alpha: 0.22).cgColor

        let material = NSVisualEffectView()
        material.identifier = NSUserInterfaceItemIdentifier("LinkEditorMaterial")
        material.material = .underWindowBackground
        material.blendingMode = .behindWindow
        material.state = .active
        material.alphaValue = 0.62
        surface.addSubview(material)
        pin(material, to: surface)
        return surface
    }

    private func configureCompactField(_ field: NSTextField) {
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.42)
        field.wantsLayer = true
        field.layer?.cornerRadius = 6
        field.layer?.borderWidth = 1
        field.layer?.borderColor = panelSeparatorColor(alpha: 0.30).cgColor
        field.focusRingType = .exterior
        field.cell?.wraps = false
        field.cell?.isScrollable = true
    }

    private func updateConfirmState() {
        confirmButton.isEnabled = !trimmedDestination.isEmpty
    }

    private var trimmedDestination: String {
        destinationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc
    private func confirmPressed() {
        submit()
    }

    @objc
    private func cancelPressed() {
        cancel()
    }

    private func submit() {
        guard !hasFinished else { return }
        let destination = trimmedDestination
        guard !destination.isEmpty else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        finish()
        onSubmit(destination, name)
    }

    private func cancel() {
        guard !hasFinished else { return }
        finish()
    }

    private func finish() {
        hasFinished = true
        if let window, let parent = window.sheetParent {
            parent.endSheet(window)
        }
        onDismiss()
    }
}
