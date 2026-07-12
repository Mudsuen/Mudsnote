import AppKit

@MainActor
final class LinkEditorSheetController: NSWindowController, NSTextFieldDelegate {
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        super.init(window: window)

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
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.alignment = .center

        let destinationLabel = NSTextField(labelWithString: "链接到")
        destinationLabel.font = .systemFont(ofSize: 12, weight: .regular)
        destinationLabel.textColor = .secondaryLabelColor

        destinationField.identifier = NSUserInterfaceItemIdentifier("LinkEditorDestinationField")
        destinationField.placeholderString = "输入 URL"
        destinationField.delegate = self
        destinationField.setAccessibilityLabel("链接到")
        destinationField.cell?.wraps = true
        destinationField.cell?.isScrollable = false

        let nameLabel = NSTextField(labelWithString: "名称")
        nameLabel.font = .systemFont(ofSize: 12, weight: .regular)
        nameLabel.textColor = .secondaryLabelColor

        nameField.identifier = NSUserInterfaceItemIdentifier("LinkEditorNameField")
        nameField.placeholderString = "可选"
        nameField.delegate = self
        nameField.setAccessibilityLabel("名称")

        confirmButton.identifier = NSUserInterfaceItemIdentifier("LinkEditorConfirmButton")
        confirmButton.target = self
        confirmButton.action = #selector(confirmPressed)
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelStyle = .rounded
        confirmButton.bezelColor = panelAccentColor()

        cancelButton.identifier = NSUserInterfaceItemIdentifier("LinkEditorCancelButton")
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let buttonStack = NSStackView(views: [cancelButton, confirmButton])
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8

        for view in [titleLabel, destinationLabel, destinationField, nameLabel, nameField, buttonStack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            destinationLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            destinationLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            destinationField.topAnchor.constraint(equalTo: destinationLabel.bottomAnchor, constant: 5),
            destinationField.leadingAnchor.constraint(equalTo: destinationLabel.leadingAnchor),
            destinationField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            destinationField.heightAnchor.constraint(equalToConstant: 62),

            nameLabel.topAnchor.constraint(equalTo: destinationField.bottomAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 5),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: destinationField.trailingAnchor),
            nameField.heightAnchor.constraint(equalToConstant: 28),

            buttonStack.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 14),
            buttonStack.trailingAnchor.constraint(equalTo: destinationField.trailingAnchor),
            buttonStack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -14)
        ])

        window?.defaultButtonCell = confirmButton.cell as? NSButtonCell
        updateConfirmState()
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
