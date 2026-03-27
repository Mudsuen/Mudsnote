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
    private let quickCaptureHotKeyField = NSTextField(string: "")
    private let floatingHotKeyField = NSTextField(string: "")
    private let saveShortcutField = NSTextField(string: "")
    private let onSave: (URL, [URL], Double, HotKeySpec, HotKeySpec, HotKeySpec) -> Void
    private let onPreviewOpacity: (Double) -> Void
    private let initialOpacity: Double

    private var selectedDirectory: URL
    private var managedDirectories: [URL]
    private var didSavePreferences = false
    private var currentPanelOpacity: Double
    private weak var backdropView: GradientBackdropView?
    private weak var directorySurfaceView: NSView?
    private weak var opacitySurfaceView: NSView?
    private weak var quickCaptureHotKeySurfaceView: NSView?
    private weak var floatingHotKeySurfaceView: NSView?
    private weak var saveShortcutSurfaceView: NSView?

    init(
        currentDirectory: URL,
        availableDirectories: [URL],
        currentOpacity: Double,
        currentQuickCaptureHotKey: String,
        currentFloatingHotKey: String,
        currentSaveShortcut: String,
        onPreviewOpacity: @escaping (Double) -> Void,
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
        self.currentPanelOpacity = currentOpacity
        self.onPreviewOpacity = onPreviewOpacity
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 460),
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

        let quickCaptureHotKeyLabel = NSTextField(labelWithString: "Quick capture shortcut")
        quickCaptureHotKeyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        quickCaptureHotKeyLabel.textColor = NSColor.white.withAlphaComponent(0.58)

        quickCaptureHotKeyField.stringValue = currentQuickCaptureHotKey
        quickCaptureHotKeyField.placeholderString = "option+shift+n"
        quickCaptureHotKeyField.font = .systemFont(ofSize: 16, weight: .semibold)
        quickCaptureHotKeyField.isBordered = false
        quickCaptureHotKeyField.drawsBackground = false
        quickCaptureHotKeyField.textColor = .white

        let quickCaptureHotKeySurface = makeModernSurface(
            content: insetted(quickCaptureHotKeyField, padding: .init(top: 8, left: 12, bottom: 8, right: 12)),
            cornerRadius: 16,
            tintColor: NSColor.systemBlue.withAlphaComponent(0.14),
            alpha: primarySurfaceAlpha(for: currentOpacity),
            material: .menu
        )
        quickCaptureHotKeySurfaceView = quickCaptureHotKeySurface

        let floatingHotKeyLabel = NSTextField(labelWithString: "Floating note shortcut")
        floatingHotKeyLabel.font = .systemFont(ofSize: 12, weight: .medium)
        floatingHotKeyLabel.textColor = NSColor.white.withAlphaComponent(0.58)

        floatingHotKeyField.stringValue = currentFloatingHotKey
        floatingHotKeyField.placeholderString = "option+r"
        floatingHotKeyField.font = .systemFont(ofSize: 16, weight: .semibold)
        floatingHotKeyField.isBordered = false
        floatingHotKeyField.drawsBackground = false
        floatingHotKeyField.textColor = .white

        let floatingHotKeySurface = makeModernSurface(
            content: insetted(floatingHotKeyField, padding: .init(top: 8, left: 12, bottom: 8, right: 12)),
            cornerRadius: 16,
            tintColor: NSColor.systemBlue.withAlphaComponent(0.14),
            alpha: primarySurfaceAlpha(for: currentOpacity),
            material: .menu
        )
        floatingHotKeySurfaceView = floatingHotKeySurface

        let saveShortcutLabel = NSTextField(labelWithString: "Save shortcut")
        saveShortcutLabel.font = .systemFont(ofSize: 12, weight: .medium)
        saveShortcutLabel.textColor = NSColor.white.withAlphaComponent(0.58)

        saveShortcutField.stringValue = currentSaveShortcut
        saveShortcutField.placeholderString = "command+return"
        saveShortcutField.font = .systemFont(ofSize: 16, weight: .semibold)
        saveShortcutField.isBordered = false
        saveShortcutField.drawsBackground = false
        saveShortcutField.textColor = .white

        let saveShortcutSurface = makeModernSurface(
            content: insetted(saveShortcutField, padding: .init(top: 8, left: 12, bottom: 8, right: 12)),
            cornerRadius: 16,
            tintColor: NSColor.systemBlue.withAlphaComponent(0.14),
            alpha: primarySurfaceAlpha(for: currentOpacity),
            material: .menu
        )
        saveShortcutSurfaceView = saveShortcutSurface

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelPressed))
        styleSecondaryButton(cancelButton)

        let saveButton = NSButton(title: "Save Preferences", target: self, action: #selector(savePressed))
        saveButton.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        saveButton.imagePosition = .imageLeading
        styleAccentButton(saveButton)

        let footer = NSStackView(views: [NSView(), cancelButton, saveButton])
        footer.orientation = .horizontal
        footer.spacing = 10

        for view in [
            badge, title, folderLabel, directorySurface, directoryActions, folderHelp,
            opacityLabel, opacitySurface,
            quickCaptureHotKeyLabel, quickCaptureHotKeySurface,
            floatingHotKeyLabel, floatingHotKeySurface,
            saveShortcutLabel, saveShortcutSurface,
            footer
        ] {
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

            quickCaptureHotKeyLabel.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            quickCaptureHotKeyLabel.topAnchor.constraint(equalTo: opacitySurface.bottomAnchor, constant: 14),

            quickCaptureHotKeySurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            quickCaptureHotKeySurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            quickCaptureHotKeySurface.topAnchor.constraint(equalTo: quickCaptureHotKeyLabel.bottomAnchor, constant: 8),

            floatingHotKeyLabel.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            floatingHotKeyLabel.topAnchor.constraint(equalTo: quickCaptureHotKeySurface.bottomAnchor, constant: 12),

            floatingHotKeySurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            floatingHotKeySurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            floatingHotKeySurface.topAnchor.constraint(equalTo: floatingHotKeyLabel.bottomAnchor, constant: 8),

            saveShortcutLabel.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            saveShortcutLabel.topAnchor.constraint(equalTo: floatingHotKeySurface.bottomAnchor, constant: 12),

            saveShortcutSurface.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            saveShortcutSurface.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            saveShortcutSurface.topAnchor.constraint(equalTo: saveShortcutLabel.bottomAnchor, constant: 8),

            footer.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -18),
            footer.topAnchor.constraint(greaterThanOrEqualTo: saveShortcutSurface.bottomAnchor, constant: 18),
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
        currentPanelOpacity = opacity
        window?.alphaValue = windowAlphaValue(for: opacity)
        backdropView?.updatePanelOpacity(opacity)
        directorySurfaceView?.alphaValue = secondarySurfaceAlpha(for: opacity)
        opacitySurfaceView?.alphaValue = secondarySurfaceAlpha(for: opacity)
        quickCaptureHotKeySurfaceView?.alphaValue = primarySurfaceAlpha(for: opacity)
        floatingHotKeySurfaceView?.alphaValue = primarySurfaceAlpha(for: opacity)
        saveShortcutSurfaceView?.alphaValue = primarySurfaceAlpha(for: opacity)
    }
}
