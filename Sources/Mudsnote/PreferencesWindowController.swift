import AppKit
import Foundation
import MudsnoteCore

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let defaultDirectoryPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let addDirectoryButton = NSButton(title: "Add...", target: nil, action: nil)
    private let removeDirectoryButton = NSButton(title: "Remove", target: nil, action: nil)
    private let revealDirectoryButton = NSButton(title: "Reveal in Finder", target: nil, action: nil)
    private let opacitySlider = NSSlider(
        value: NoteStore.defaultPanelOpacity,
        minValue: NoteStore.minimumPanelOpacity,
        maxValue: NoteStore.maximumPanelOpacity,
        target: nil,
        action: nil
    )
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private let resetOpacityButton = NSButton(title: "Reset Opacity", target: nil, action: nil)
    private let resetWindowPositionsButton = NSButton(title: "Reset Window Positions", target: nil, action: nil)
    private let quickCaptureHotKeyField = NSTextField(string: "")
    private let floatingHotKeyField = NSTextField(string: "")
    private let saveShortcutField = NSTextField(string: "")
    private let resetShortcutsButton = NSButton(title: "Restore Defaults", target: nil, action: nil)

    private let onPreviewOpacity: (Double) -> Void
    private let onResetWindowFrames: () -> Void
    private let onSave: (URL, [URL], Double, HotKeySpec, HotKeySpec, HotKeySpec) -> Void
    private let initialOpacity: Double

    private var selectedDirectory: URL
    private var managedDirectories: [URL]
    private var didSavePreferences = false

    init(
        currentDirectory: URL,
        availableDirectories: [URL],
        currentOpacity: Double,
        currentQuickCaptureHotKey: String,
        currentFloatingHotKey: String,
        currentSaveShortcut: String,
        onPreviewOpacity: @escaping (Double) -> Void,
        onResetWindowFrames: @escaping () -> Void,
        onSave: @escaping (URL, [URL], Double, HotKeySpec, HotKeySpec, HotKeySpec) -> Void
    ) {
        let normalizedCurrentDirectory = currentDirectory.standardizedFileURL
        var normalizedDirectories = Array(Set(availableDirectories.map(\.standardizedFileURL))).sorted {
            $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
        }
        if !normalizedDirectories.contains(where: { $0.path == normalizedCurrentDirectory.path }) {
            normalizedDirectories.insert(normalizedCurrentDirectory, at: 0)
        }

        self.selectedDirectory = normalizedCurrentDirectory
        self.managedDirectories = normalizedDirectories
        self.initialOpacity = currentOpacity
        self.onPreviewOpacity = onPreviewOpacity
        self.onResetWindowFrames = onResetWindowFrames
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.title = "\(MudsnoteBrand.appName) Settings"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true

        super.init(window: window)
        window.delegate = self

        buildUI(
            currentOpacity: currentOpacity,
            currentQuickCaptureHotKey: currentQuickCaptureHotKey,
            currentFloatingHotKey: currentFloatingHotKey,
            currentSaveShortcut: currentSaveShortcut
        )
        refreshDirectoryControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI(
        currentOpacity: Double,
        currentQuickCaptureHotKey: String,
        currentFloatingHotKey: String,
        currentSaveShortcut: String
    ) {
        guard let contentView = window?.contentView else { return }

        defaultDirectoryPopUp.target = self
        defaultDirectoryPopUp.action = #selector(defaultDirectoryChanged(_:))
        defaultDirectoryPopUp.controlSize = .regular
        defaultDirectoryPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        addDirectoryButton.target = self
        addDirectoryButton.action = #selector(addFolderPressed)
        removeDirectoryButton.target = self
        removeDirectoryButton.action = #selector(removeFolderPressed)
        revealDirectoryButton.target = self
        revealDirectoryButton.action = #selector(revealFolderPressed)

        opacitySlider.doubleValue = clampedOpacity(currentOpacity)
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))
        opacityValueLabel.alignment = .right
        opacityValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        opacityValueLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        resetOpacityButton.target = self
        resetOpacityButton.action = #selector(resetOpacityPressed)
        resetWindowPositionsButton.target = self
        resetWindowPositionsButton.action = #selector(resetWindowPositionsPressed)
        refreshOpacityLabel()

        configureShortcutField(quickCaptureHotKeyField, value: currentQuickCaptureHotKey, placeholder: "option+shift+n")
        configureShortcutField(floatingHotKeyField, value: currentFloatingHotKey, placeholder: "option+r")
        configureShortcutField(saveShortcutField, value: currentSaveShortcut, placeholder: "command+return")
        resetShortcutsButton.target = self
        resetShortcutsButton.action = #selector(resetShortcutsPressed)

        let tabView = NSTabView()
        tabView.tabViewType = .topTabsBezelBorder
        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.addTabViewItem(tabItem(label: "General", view: makeGeneralPane()))
        tabView.addTabViewItem(tabItem(label: "Shortcuts", view: makeShortcutsPane()))
        tabView.addTabViewItem(tabItem(label: "Appearance", view: makeAppearancePane()))

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: "Save", target: self, action: #selector(savePressed))
        saveButton.keyEquivalent = "\r"

        let footer = NSStackView(views: [NSView(), cancelButton, saveButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(tabView)
        contentView.addSubview(footer)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            tabView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -14),

            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])
    }

    private func makeGeneralPane() -> NSView {
        let actions = NSStackView(views: [addDirectoryButton, removeDirectoryButton, revealDirectoryButton, NSView()])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        return contentPane(views: [
            sectionTitle("Notes"),
            preferenceRow(
                label: "Default folder:",
                control: defaultDirectoryPopUp,
                help: "New notes save here by default. Additional managed folders stay available from quick capture."
            ),
            preferenceRow(label: "Managed folders:", control: actions),
            sectionDivider(),
            sectionTitle("Planned settings area"),
            bodyText("Keep folder selection, capture behavior, shortcuts, and window appearance separate so future options can be added without crowding one long panel.")
        ])
    }

    private func makeShortcutsPane() -> NSView {
        return contentPane(views: [
            sectionTitle("Keyboard Shortcuts"),
            preferenceRow(
                label: "Quick capture:",
                control: quickCaptureHotKeyField,
                help: "Opens the quick note window from anywhere."
            ),
            preferenceRow(
                label: "Floating note:",
                control: floatingHotKeyField,
                help: "Shows or raises the persistent floating note window."
            ),
            preferenceRow(
                label: "Save note:",
                control: saveShortcutField,
                help: "Saves the current note while editing."
            ),
            preferenceRow(label: "", control: resetShortcutsButton)
        ])
    }

    private func makeAppearancePane() -> NSView {
        let opacityControl = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityControl.orientation = .horizontal
        opacityControl.alignment = .centerY
        opacityControl.spacing = 10
        opacitySlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 300).isActive = true

        return contentPane(views: [
            sectionTitle("Windows"),
            preferenceRow(
                label: "Panel opacity:",
                control: opacityControl,
                help: "Applies to the quick capture and floating note panels while leaving Settings fully opaque."
            ),
            preferenceRow(label: "", control: resetOpacityButton),
            preferenceRow(
                label: "Window memory:",
                control: resetWindowPositionsButton,
                help: "Use this when a quick capture or floating note window reopens in an awkward or off-screen position."
            )
        ])
    }

    private func tabItem(label: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: label)
        item.label = label
        item.view = view
        return item
    }

    private func contentPane(views: [NSView]) -> NSView {
        let pane = NSView()
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        pane.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -28),
            stack.topAnchor.constraint(equalTo: pane.topAnchor, constant: 26),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: pane.bottomAnchor, constant: -26)
        ])
        return pane
    }

    private func sectionTitle(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func bodyText(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 3
        return label
    }

    private func sectionDivider() -> NSBox {
        let divider = NSBox()
        divider.boxType = .separator
        divider.widthAnchor.constraint(equalToConstant: 600).isActive = true
        return divider
    }

    private func preferenceRow(label title: String, control: NSView, help: String? = nil) -> NSView {
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.alignment = .right
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.textColor = .labelColor
        titleLabel.widthAnchor.constraint(equalToConstant: 140).isActive = true

        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.widthAnchor.constraint(equalToConstant: 600).isActive = true
        container.addArrangedSubview(row)

        if let help {
            let spacer = NSView()
            spacer.widthAnchor.constraint(equalToConstant: 150).isActive = true
            let helpLabel = bodyText(help)
            helpLabel.widthAnchor.constraint(equalToConstant: 450).isActive = true

            let helpRow = NSStackView(views: [spacer, helpLabel])
            helpRow.orientation = .horizontal
            helpRow.alignment = .top
            helpRow.spacing = 0
            container.addArrangedSubview(helpRow)
        }

        return container
    }

    private func configureShortcutField(_ field: NSTextField, value: String, placeholder: String) {
        field.stringValue = value
        field.placeholderString = placeholder
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.controlSize = .regular
        field.widthAnchor.constraint(equalToConstant: 260).isActive = true
    }

    private func refreshDirectoryControls() {
        defaultDirectoryPopUp.removeAllItems()
        defaultDirectoryPopUp.addItems(withTitles: managedDirectories.map(directoryLabel(for:)))

        if let selectedIndex = managedDirectories.firstIndex(where: { $0.path == selectedDirectory.path }) {
            defaultDirectoryPopUp.selectItem(at: selectedIndex)
        }

        removeDirectoryButton.isEnabled = managedDirectories.count > 1
        revealDirectoryButton.isEnabled = true

        for (index, url) in managedDirectories.enumerated() {
            defaultDirectoryPopUp.item(at: index)?.toolTip = displayPath(url)
        }
    }

    private func refreshOpacityLabel() {
        opacityValueLabel.stringValue = "\(Int((opacitySlider.doubleValue * 100).rounded()))%"
    }

    private func directoryLabel(for url: URL) -> String {
        let folder = url.lastPathComponent.isEmpty ? "Folder" : url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty ? folder : "\(folder) - \(parent)"
    }

    @objc
    private func defaultDirectoryChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard managedDirectories.indices.contains(index) else { return }
        selectedDirectory = managedDirectories[index]
        refreshDirectoryControls()
    }

    @objc
    private func addFolderPressed() {
        guard let url = chooseDirectory(startingAt: selectedDirectory)?.standardizedFileURL else { return }
        if !managedDirectories.contains(where: { $0.path == url.path }) {
            managedDirectories.append(url)
            managedDirectories.sort { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        }
        selectedDirectory = url
        refreshDirectoryControls()
    }

    @objc
    private func removeFolderPressed() {
        guard managedDirectories.count > 1 else { return }
        managedDirectories.removeAll { $0.path == selectedDirectory.path }
        if let first = managedDirectories.first {
            selectedDirectory = first
        }
        refreshDirectoryControls()
    }

    @objc
    private func revealFolderPressed() {
        NSWorkspace.shared.activateFileViewerSelecting([selectedDirectory])
    }

    @objc
    private func resetOpacityPressed() {
        opacitySlider.doubleValue = NoteStore.defaultPanelOpacity
        refreshOpacityLabel()
        onPreviewOpacity(opacitySlider.doubleValue)
    }

    @objc
    private func resetWindowPositionsPressed() {
        onResetWindowFrames()
        resetWindowPositionsButton.title = "Window Positions Reset"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.resetWindowPositionsButton.title = "Reset Window Positions"
        }
    }

    @objc
    private func resetShortcutsPressed() {
        quickCaptureHotKeyField.stringValue = "option+shift+n"
        floatingHotKeyField.stringValue = "option+r"
        saveShortcutField.stringValue = "command+return"
    }

    @objc
    private func cancelPressed() {
        window?.close()
    }

    @objc
    private func opacityChanged(_ sender: NSSlider) {
        sender.doubleValue = clampedOpacity(sender.doubleValue)
        refreshOpacityLabel()
        onPreviewOpacity(sender.doubleValue)
    }

    @objc
    private func savePressed() {
        let quickCaptureHotKeyRaw = quickCaptureHotKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let floatingHotKeyRaw = floatingHotKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveShortcutRaw = saveShortcutField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let quickCaptureSpec = HotKeySpec.parse(quickCaptureHotKeyRaw),
              let floatingSpec = HotKeySpec.parse(floatingHotKeyRaw),
              let saveShortcutSpec = HotKeySpec.parse(saveShortcutRaw) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Invalid shortcut"
            alert.informativeText = "Use formats like option+shift+n, option+r, or command+return."
            alert.runModal()
            return
        }

        didSavePreferences = true
        onSave(selectedDirectory, managedDirectories, opacitySlider.doubleValue, quickCaptureSpec, floatingSpec, saveShortcutSpec)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if !didSavePreferences {
            onPreviewOpacity(initialOpacity)
        }
    }

    func updatePanelOpacity(_ opacity: Double) {
        opacitySlider.doubleValue = clampedOpacity(opacity)
        refreshOpacityLabel()
    }

    private func clampedOpacity(_ opacity: Double) -> Double {
        min(max(opacity, NoteStore.minimumPanelOpacity), NoteStore.maximumPanelOpacity)
    }
}
