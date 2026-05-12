import AppKit
import Foundation
import MudsnoteCore

@MainActor
struct PreferencesSettings {
    let directory: URL
    let directories: [URL]
    let opacity: Double
    let quickCaptureHotKey: HotKeySpec
    let floatingHotKey: HotKeySpec
    let saveShortcut: HotKeySpec
    let revealSavedNoteInFinder: Bool
    let floatingNoteStaysOnTop: Bool
    let spellCheckingEnabled: Bool
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    private enum SettingsPane: String, CaseIterable {
        case general
        case editor
        case shortcuts
        case appearance

        var identifier: NSToolbarItem.Identifier { NSToolbarItem.Identifier("mudsnote.settings.\(rawValue)") }
        var label: String {
            switch self {
            case .general: return "通用"
            case .editor: return "编辑"
            case .shortcuts: return "快捷键"
            case .appearance: return "外观"
            }
        }

        var symbolName: String {
            switch self {
            case .general: return "folder"
            case .editor: return "text.cursor"
            case .shortcuts: return "keyboard"
            case .appearance: return "slider.horizontal.3"
            }
        }
    }

    private static let toolbarIdentifier = NSToolbar.Identifier("mudsnote.settings.toolbar")

    private let tabView = NSTabView()
    private let defaultDirectoryPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let addDirectoryButton = NSButton(title: "添加...", target: nil, action: nil)
    private let removeDirectoryButton = NSButton(title: "移除", target: nil, action: nil)
    private let revealDirectoryButton = NSButton(title: "在 Finder 中显示", target: nil, action: nil)
    private let revealSavedNoteButton = NSButton(checkboxWithTitle: "保存后在 Finder 中显示笔记", target: nil, action: nil)
    private let floatingNoteStaysOnTopButton = NSButton(checkboxWithTitle: "悬浮笔记保持置顶", target: nil, action: nil)
    private let spellCheckingButton = NSButton(checkboxWithTitle: "输入时检查拼写", target: nil, action: nil)
    private let opacitySlider = NSSlider(
        value: NoteStore.defaultPanelOpacity,
        minValue: NoteStore.minimumPanelOpacity,
        maxValue: NoteStore.maximumPanelOpacity,
        target: nil,
        action: nil
    )
    private let opacityValueLabel = NSTextField(labelWithString: "")
    private let resetOpacityButton = NSButton(title: "重置透明度", target: nil, action: nil)
    private let resetWindowPositionsButton = NSButton(title: "重置窗口位置", target: nil, action: nil)
    private let quickCaptureHotKeyRecorder = ShortcutRecorderButton()
    private let floatingHotKeyRecorder = ShortcutRecorderButton()
    private let saveShortcutRecorder = ShortcutRecorderButton()
    private let resetShortcutsButton = NSButton(title: "恢复默认值", target: nil, action: nil)

    private let onPreviewOpacity: (Double) -> Void
    private let onResetWindowFrames: () -> Void
    private let onSave: (PreferencesSettings) -> Void
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
        revealSavedNoteInFinder: Bool,
        floatingNoteStaysOnTop: Bool,
        spellCheckingEnabled: Bool,
        onPreviewOpacity: @escaping (Double) -> Void,
        onResetWindowFrames: @escaping () -> Void,
        onSave: @escaping (PreferencesSettings) -> Void
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

        let window = ShortcutRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.title = "\(MudsnoteBrand.appName) 设置"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .preference
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true

        super.init(window: window)
        window.delegate = self
        configureToolbar()

        buildUI(
            currentOpacity: currentOpacity,
            currentQuickCaptureHotKey: currentQuickCaptureHotKey,
            currentFloatingHotKey: currentFloatingHotKey,
            currentSaveShortcut: currentSaveShortcut,
            revealSavedNoteInFinder: revealSavedNoteInFinder,
            floatingNoteStaysOnTop: floatingNoteStaysOnTop,
            spellCheckingEnabled: spellCheckingEnabled
        )
        refreshDirectoryControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureToolbar() {
        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.selectedItemIdentifier = SettingsPane.general.identifier
        window?.toolbar = toolbar
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.identifier)
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.identifier)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        SettingsPane.allCases.map(\.identifier)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let pane = SettingsPane.allCases.first(where: { $0.identifier == itemIdentifier }) else {
            return nil
        }

        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = pane.label
        item.paletteLabel = pane.label
        item.toolTip = pane.label
        item.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.label)
        item.target = self
        item.action = #selector(toolbarPaneSelected(_:))
        return item
    }

    @objc
    private func toolbarPaneSelected(_ sender: NSToolbarItem) {
        guard let pane = SettingsPane.allCases.first(where: { $0.identifier == sender.itemIdentifier }) else {
            return
        }

        tabView.selectTabViewItem(withIdentifier: pane.rawValue)
        window?.toolbar?.selectedItemIdentifier = pane.identifier
    }

    private func buildUI(
        currentOpacity: Double,
        currentQuickCaptureHotKey: String,
        currentFloatingHotKey: String,
        currentSaveShortcut: String,
        revealSavedNoteInFinder: Bool,
        floatingNoteStaysOnTop: Bool,
        spellCheckingEnabled: Bool
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
        revealSavedNoteButton.state = revealSavedNoteInFinder ? .on : .off
        floatingNoteStaysOnTopButton.state = floatingNoteStaysOnTop ? .on : .off
        spellCheckingButton.state = spellCheckingEnabled ? .on : .off

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

        configureShortcutRecorder(quickCaptureHotKeyRecorder, value: currentQuickCaptureHotKey)
        configureShortcutRecorder(floatingHotKeyRecorder, value: currentFloatingHotKey)
        configureShortcutRecorder(saveShortcutRecorder, value: currentSaveShortcut)
        resetShortcutsButton.target = self
        resetShortcutsButton.action = #selector(resetShortcutsPressed)

        tabView.translatesAutoresizingMaskIntoConstraints = false
        tabView.tabViewType = .noTabsNoBorder
        tabView.addTabViewItem(tabItem(pane: .general, view: makeGeneralPane()))
        tabView.addTabViewItem(tabItem(pane: .editor, view: makeEditorPane()))
        tabView.addTabViewItem(tabItem(pane: .shortcuts, view: makeShortcutsPane()))
        tabView.addTabViewItem(tabItem(pane: .appearance, view: makeAppearancePane()))
        tabView.selectTabViewItem(withIdentifier: SettingsPane.general.rawValue)

        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancelPressed))
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: "保存", target: self, action: #selector(savePressed))
        saveButton.keyEquivalent = "\r"

        let footer = NSStackView(views: [NSView(), cancelButton, saveButton])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        footer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(tabView)
        contentView.addSubview(footer)

        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor),
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
            sectionTitle("笔记"),
            preferenceRow(
                label: "默认文件夹:",
                control: defaultDirectoryPopUp,
                help: "新笔记默认保存到这里。其他托管文件夹仍可在快速笔记中选择。"
            ),
            preferenceRow(label: "托管文件夹:", control: actions),
            sectionDivider(),
            sectionTitle("保存行为"),
            preferenceRow(
                label: "",
                control: revealSavedNoteButton,
                help: "开启后，手动保存成功时会在 Finder 中选中新笔记。"
            )
        ])
    }

    private func makeEditorPane() -> NSView {
        return contentPane(views: [
            sectionTitle("编辑"),
            preferenceRow(
                label: "",
                control: spellCheckingButton,
                help: "作用于快速笔记、悬浮笔记和普通笔记窗口的正文编辑器。"
            )
        ])
    }

    private func makeShortcutsPane() -> NSView {
        return contentPane(views: [
            sectionTitle("键盘快捷键"),
            preferenceRow(
                label: "快速笔记:",
                control: quickCaptureHotKeyRecorder,
                help: "点击后按下组合键，用于从任意位置打开快速笔记窗口。"
            ),
            preferenceRow(
                label: "悬浮笔记:",
                control: floatingHotKeyRecorder,
                help: "点击后按下组合键，用于显示或唤起常驻悬浮笔记窗口。"
            ),
            preferenceRow(
                label: "保存笔记:",
                control: saveShortcutRecorder,
                help: "点击后按下组合键，用于编辑时保存当前笔记。"
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
            sectionTitle("窗口"),
            preferenceRow(
                label: "面板透明度:",
                control: opacityControl,
                help: "作用于快速笔记和悬浮笔记面板，设置窗口始终保持不透明。"
            ),
            preferenceRow(label: "", control: resetOpacityButton),
            preferenceRow(
                label: "",
                control: floatingNoteStaysOnTopButton,
                help: "关闭后，悬浮笔记会像普通窗口一样，不再覆盖其他应用。"
            ),
            preferenceRow(
                label: "窗口位置:",
                control: resetWindowPositionsButton,
                help: "当快速笔记或悬浮笔记重新打开到异常位置或屏幕外时使用。"
            )
        ])
    }

    private func tabItem(pane: SettingsPane, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem(identifier: pane.rawValue)
        item.label = pane.label
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

    private func configureShortcutRecorder(_ recorder: ShortcutRecorderButton, value: String) {
        recorder.setShortcutString(value)
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
        let folder = url.lastPathComponent.isEmpty ? "文件夹" : url.lastPathComponent
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
        resetWindowPositionsButton.title = "窗口位置已重置"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.resetWindowPositionsButton.title = "重置窗口位置"
        }
    }

    @objc
    private func resetShortcutsPressed() {
        quickCaptureHotKeyRecorder.setShortcutString("option+shift+n")
        floatingHotKeyRecorder.setShortcutString("option+r")
        saveShortcutRecorder.setShortcutString("command+return")
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
        guard let quickCaptureSpec = quickCaptureHotKeyRecorder.shortcutSpec,
              let floatingSpec = floatingHotKeyRecorder.shortcutSpec,
              let saveShortcutSpec = saveShortcutRecorder.shortcutSpec else {
            presentValidationAlert(
                message: "快捷键无效",
                details: "请点击快捷键控件，然后按下包含 Command、Option 或 Control 的组合键。"
            )
            return
        }

        if let duplicateMessage = duplicateShortcutMessage([
            ("快速笔记", quickCaptureSpec),
            ("悬浮笔记", floatingSpec),
            ("保存笔记", saveShortcutSpec)
        ]) {
            presentValidationAlert(message: "快捷键重复", details: duplicateMessage)
            return
        }

        didSavePreferences = true
        onSave(PreferencesSettings(
            directory: selectedDirectory,
            directories: managedDirectories,
            opacity: opacitySlider.doubleValue,
            quickCaptureHotKey: quickCaptureSpec,
            floatingHotKey: floatingSpec,
            saveShortcut: saveShortcutSpec,
            revealSavedNoteInFinder: revealSavedNoteButton.state == .on,
            floatingNoteStaysOnTop: floatingNoteStaysOnTopButton.state == .on,
            spellCheckingEnabled: spellCheckingButton.state == .on
        ))
        window?.close()
    }

    private func duplicateShortcutMessage(_ shortcuts: [(label: String, spec: HotKeySpec)]) -> String? {
        for lhsIndex in shortcuts.indices {
            for rhsIndex in shortcuts.index(after: lhsIndex)..<shortcuts.endIndex where shortcuts[lhsIndex].spec == shortcuts[rhsIndex].spec {
                return "\(shortcuts[lhsIndex].label) 和 \(shortcuts[rhsIndex].label) 使用了同一个快捷键。请为它们录入不同的组合键。"
            }
        }
        return nil
    }

    private func presentValidationAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
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
