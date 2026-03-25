import AppKit
import Foundation
import QuickMarkdownCore

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let defaultDirectoryPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let addDirectoryButton = NSButton(title: "Add Folder", target: nil, action: nil)
    private let removeDirectoryButton = NSButton(title: "Remove", target: nil, action: nil)
    private let opacitySlider = NSSlider(
        value: NoteStore.defaultPanelOpacity,
        minValue: NoteStore.minimumPanelOpacity,
        maxValue: NoteStore.maximumPanelOpacity,
        target: nil,
        action: nil
    )
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private let hotKeyField = NSTextField(string: "")
    private let onSave: (URL, [URL], Double, HotKeySpec) -> Void
    private let onPreviewOpacity: (Double) -> Void
    private let initialOpacity: Double

    private var selectedDirectory: URL
    private var managedDirectories: [URL]
    private var didSavePreferences = false
    private var currentPanelOpacity: Double
    private weak var backdropView: GradientBackdropView?
    private weak var directorySurfaceView: NSView?
    private weak var opacitySurfaceView: NSView?
    private weak var hotKeySurfaceView: NSView?

    init(
        currentDirectory: URL,
        availableDirectories: [URL],
        currentOpacity: Double,
        currentHotKey: String,
        onPreviewOpacity: @escaping (Double) -> Void,
        onSave: @escaping (URL, [URL], Double, HotKeySpec) -> Void
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
        self.currentPanelOpacity = currentOpacity
        self.onPreviewOpacity = onPreviewOpacity
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false

        super.init(window: window)
        window.delegate = self
        buildUI(currentOpacity: currentOpacity, currentHotKey: currentHotKey)
        refreshDirectoryControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI(currentOpacity: Double, currentHotKey: String) {
        guard let contentView = window?.contentView else { return }

        let backdrop = GradientBackdropView(frame: contentView.bounds, panelOpacity: currentOpacity)
        contentView.addSubview(backdrop)
        pin(backdrop, to: contentView)
        backdropView = backdrop

        let shellContent = NSView()
        backdrop.addSubview(shellContent)
        pin(shellContent, to: backdrop, insets: .init(top: 14, left: 14, bottom: 14, right: 14))

        let badge = NSTextField(labelWithString: "PREFERENCES")
        badge.font = .systemFont(ofSize: 11, weight: .bold)
        badge.textColor = NSColor.white.withAlphaComponent(0.72)

        let title = NSTextField(labelWithString: "QuickMarkdown Setup")
        title.font = .systemFont(ofSize: 24, weight: .bold)
        title.textColor = .white

        let folderLabel = NSTextField(labelWithString: "Managed folders")
        folderLabel.font = .systemFont(ofSize: 12, weight: .medium)
        folderLabel.textColor = NSColor.white.withAlphaComponent(0.58)

        defaultDirectoryPopUp.target = self
        defaultDirectoryPopUp.action = #selector(defaultDirectoryChanged(_:))
        defaultDirectoryPopUp.controlSize = .regular

        let directorySurface = makeModernSurface(
            content: insetted(defaultDirectoryPopUp, padding: .init(top: 8, left: 8, bottom: 8, right: 8)),
            cornerRadius: 16,
            tintColor: NSColor.white.withAlphaComponent(0.03),
            alpha: secondarySurfaceAlpha(for: currentOpacity),
            material: .menu
        )
        directorySurfaceView = directorySurface

        addDirectoryButton.target = self
        addDirectoryButton.action = #selector(addFolderPressed)
        styleSecondaryButton(addDirectoryButton)
        addDirectoryButton.controlSize = .regular

        removeDirectoryButton.target = self
        removeDirectoryButton.action = #selector(removeFolderPressed)
        styleSecondaryButton(removeDirectoryButton)
        removeDirectoryButton.controlSize = .regular

        let directoryActions = NSStackView(views: [addDirectoryButton, removeDirectoryButton, NSView()])
        directoryActions.orientation = .horizontal
        directoryActions.spacing = 8

        let folderHelp = NSTextField(
            wrappingLabelWithString: "Add folders here and they will appear in the quick capture dropdown. The selected folder here is the default save location."
        )
        folderHelp.font = .systemFont(ofSize: 12)
        folderHelp.textColor = NSColor.white.withAlphaComponent(0.56)

        let opacityLabel = NSTextField(labelWithString: "Window opacity")
        opacityLabel.font = .systemFont(ofSize: 12, weight: .medium)
        opacityLabel.textColor = NSColor.white.withAlphaComponent(0.58)

        opacitySlider.doubleValue = currentOpacity
        opacitySlider.target = self
        opacitySlider.action = #selector(opacityChanged(_:))

        opacityValueLabel.font = .systemFont(ofSize: 12, weight: .medium)
        opacityValueLabel.textColor = NSColor.white.withAlphaComponent(0.70)
        refreshOpacityLabel()

        let opacityRow = NSStackView(views: [opacitySlider, opacityValueLabel])
        opacityRow.orientation = .horizontal
        opacityRow.spacing = 12
        opacityValueLabel.setContentHuggingPriority(.required, for: .horizontal)

        let opacitySurface = makeModernSurface(
            content: insetted(opacityRow, padding: .init(top: 8, left: 10, bottom: 8, right: 10)),
            cornerRadius: 16,
            tintColor: NSColor.white.withAlphaComponent(0.03),
            alpha: secondarySurfaceAlpha(for: currentOpacity),
            material: .menu
        )
        opacitySurfaceView = opacitySurface

        let hotKeyLabel = NSTextField(labelWithString: "Global shortcut")
        hotKeyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        hotKeyLabel.textColor = NSColor.white.withAlphaComponent(0.58)

        hotKeyField.stringValue = currentHotKey
        hotKeyField.placeholderString = "option+shift+n"
        hotKeyField.font = .systemFont(ofSize: 18, weight: .semibold)
        hotKeyField.isBordered = false
        hotKeyField.drawsBackground = false
        hotKeyField.textColor = .white

        let hotKeySurface = makeModernSurface(
            content: insetted(hotKeyField, padding: .init(top: 10, left: 12, bottom: 10, right: 12)),
            cornerRadius: 16,
            tintColor: NSColor.systemBlue.withAlphaComponent(0.14),
            alpha: primarySurfaceAlpha(for: currentOpacity),
            material: .menu
        )
        hotKeySurfaceView = hotKeySurface

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        styleSecondaryButton(cancelButton)

        let saveButton = NSButton(title: "Save Preferences", target: self, action: #selector(savePressed))
        saveButton.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        saveButton.imagePosition = .imageLeading
        styleAccentButton(saveButton)

        let footer = NSStackView(views: [NSView(), cancelButton, saveButton])
        footer.orientation = .horizontal
        footer.spacing = 10

        for view in [badge, title, folderLabel, directorySurface, directoryActions, folderHelp, opacityLabel, opacitySurface, hotKeyLabel, hotKeySurface, footer] {
            view.translatesAutoresizingMaskIntoConstraints = false
            shellContent.addSubview(view)
        }

        NSLayoutConstraint.activate([
            badge.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            badge.topAnchor.constraint(equalTo: shellContent.topAnchor, constant: 18),

            title.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            title.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 6),

            folderLabel.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            folderLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),

            directorySurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            directorySurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            directorySurface.topAnchor.constraint(equalTo: folderLabel.bottomAnchor, constant: 8),

            directoryActions.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            directoryActions.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            directoryActions.topAnchor.constraint(equalTo: directorySurface.bottomAnchor, constant: 8),

            folderHelp.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            folderHelp.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            folderHelp.topAnchor.constraint(equalTo: directoryActions.bottomAnchor, constant: 10),

            opacityLabel.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            opacityLabel.topAnchor.constraint(equalTo: folderHelp.bottomAnchor, constant: 14),

            opacitySurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            opacitySurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            opacitySurface.topAnchor.constraint(equalTo: opacityLabel.bottomAnchor, constant: 8),

            hotKeyLabel.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            hotKeyLabel.topAnchor.constraint(equalTo: opacitySurface.bottomAnchor, constant: 14),

            hotKeySurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            hotKeySurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            hotKeySurface.topAnchor.constraint(equalTo: hotKeyLabel.bottomAnchor, constant: 8),

            footer.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            footer.topAnchor.constraint(greaterThanOrEqualTo: hotKeySurface.bottomAnchor, constant: 18),
            footer.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor, constant: -18)
        ])

        updatePanelOpacity(currentOpacity)
    }

    private func refreshDirectoryControls() {
        defaultDirectoryPopUp.removeAllItems()
        defaultDirectoryPopUp.addItems(withTitles: managedDirectories.map(directoryLabel(for:)))

        if let selectedIndex = managedDirectories.firstIndex(where: { $0.path == selectedDirectory.path }) {
            defaultDirectoryPopUp.selectItem(at: selectedIndex)
        }

        removeDirectoryButton.isEnabled = managedDirectories.count > 1
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
        return parent.isEmpty ? folder : "\(folder) · \(parent)"
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
    private func cancelPressed() {
        window?.close()
    }

    @objc
    private func opacityChanged(_ sender: NSSlider) {
        refreshOpacityLabel()
        updatePanelOpacity(sender.doubleValue)
        onPreviewOpacity(sender.doubleValue)
    }

    @objc
    private func savePressed() {
        let hotKeyRaw = hotKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let spec = HotKeySpec.parse(hotKeyRaw) else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Invalid hotkey"
            alert.informativeText = "Use a format like option+shift+n."
            alert.runModal()
            return
        }

        didSavePreferences = true
        onSave(selectedDirectory, managedDirectories, opacitySlider.doubleValue, spec)
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        if !didSavePreferences {
            onPreviewOpacity(initialOpacity)
        }
    }

    func updatePanelOpacity(_ opacity: Double) {
        currentPanelOpacity = opacity
        window?.alphaValue = windowAlphaValue(for: opacity)
        backdropView?.updatePanelOpacity(opacity)
        directorySurfaceView?.alphaValue = secondarySurfaceAlpha(for: opacity)
        opacitySurfaceView?.alphaValue = secondarySurfaceAlpha(for: opacity)
        hotKeySurfaceView?.alphaValue = primarySurfaceAlpha(for: opacity)
    }
}
