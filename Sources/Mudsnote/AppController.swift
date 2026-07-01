import AppKit
import Foundation
import MudsnoteCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let noteStore = NoteStore()
    private let hotKeyManager = GlobalHotKeyManager()
    private let launchArguments = Set(CommandLine.arguments.dropFirst())
    static let explicitLaunchWindowArguments: Set<String> = [
        "--quick-capture",
        "--search",
        "--library",
        "--preferences",
        "--floating-note"
    ]

    private var statusItem: NSStatusItem?
    private var quickCaptureController: EditorWindowController?
    private var floatingNoteController: EditorWindowController?
    private var editorControllers: [String: EditorWindowController] = [:]
    private var libraryWindowController: LibraryWindowController?
    private var searchWindowController: SearchWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try noteStore.ensureNotesDirectory()
        } catch {
            presentErrorAlert(message: "无法准备笔记文件夹", details: error.localizedDescription)
        }

        setupStatusItem()
        registerHotKeysIfNeeded()

        if launchArguments.contains("--quick-capture") {
            DispatchQueue.main.async { [weak self] in
                self?.showQuickCapture()
            }
        }

        if launchArguments.contains("--search") {
            DispatchQueue.main.async { [weak self] in
                self?.showSearchWindow()
            }
        }

        if Self.shouldOpenLibraryOnLaunch(arguments: launchArguments) {
            DispatchQueue.main.async { [weak self] in
                self?.showLibraryWindow()
            }
        }

        if launchArguments.contains("--preferences") {
            DispatchQueue.main.async { [weak self] in
                self?.showPreferences()
            }
        }

        if launchArguments.contains("--floating-note") {
            DispatchQueue.main.async { [weak self] in
                self?.showFloatingNote()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLibraryWindow()
        return true
    }

    static func shouldOpenLibraryOnLaunch(arguments: Set<String>) -> Bool {
        arguments.contains("--library") || arguments.isDisjoint(with: explicitLaunchWindowArguments)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = MudsnoteBrand.statusItemImage()
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = MudsnoteBrand.appName
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let newNote = NSMenuItem(title: "快速笔记", action: #selector(showQuickCapture), keyEquivalent: "n")
        newNote.target = self
        menu.addItem(newNote)

        let floatingNote = NSMenuItem(title: "悬浮笔记", action: #selector(showFloatingNote), keyEquivalent: "r")
        floatingNote.target = self
        menu.addItem(floatingNote)

        let library = NSMenuItem(title: "笔记库", action: #selector(showLibraryWindow), keyEquivalent: "l")
        library.target = self
        menu.addItem(library)

        let searchNotes = NSMenuItem(title: "搜索笔记...", action: #selector(showSearchWindow), keyEquivalent: "f")
        searchNotes.target = self
        menu.addItem(searchNotes)

        let openFolder = NSMenuItem(title: "打开默认笔记文件夹", action: #selector(openNotesFolder), keyEquivalent: "o")
        openFolder.target = self
        menu.addItem(openFolder)

        let preferences = NSMenuItem(title: "设置...", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        menu.addItem(.separator())

        let recent = noteStore.listRecentFiles()
        if recent.isEmpty {
            let empty = NSMenuItem(title: "暂无最近笔记", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "最近笔记", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for note in recent {
                let item = NSMenuItem(title: note.title, action: #selector(openRecentNote(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = note.url.path
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 \(MudsnoteBrand.appName)", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    private func registerHotKeysIfNeeded() {
        let quickCaptureRegistered: Bool
        if let quickCaptureSpec = HotKeySpec.parse(noteStore.hotKeyString) {
            quickCaptureRegistered = hotKeyManager.register(quickCaptureSpec, id: 1) { [weak self] in
                Task { @MainActor in
                    self?.showQuickCapture()
                }
            }
        } else {
            hotKeyManager.unregister(id: 1)
            quickCaptureRegistered = false
        }

        let floatingRegistered: Bool
        if let floatingSpec = HotKeySpec.parse(noteStore.floatingNoteHotKeyString) {
            floatingRegistered = hotKeyManager.register(floatingSpec, id: 2) { [weak self] in
                Task { @MainActor in
                    self?.showFloatingNote()
                }
            }
        } else {
            hotKeyManager.unregister(id: 2)
            floatingRegistered = false
        }

        if !quickCaptureRegistered || !floatingRegistered {
            presentErrorAlert(message: "快捷键注册失败", details: "请在设置中录入其他快捷键。")
        }
    }

    @objc
    private func showQuickCapture() {
        cleanupClosedWindows()

        if let controller = quickCaptureController, !controller.isWindowClosed {
            if controller.window?.isVisible == true {
                controller.hideWindowForToggle()
            } else {
                controller.showWindowAndFocus()
            }
            return
        }

        quickCaptureController = nil
        let controller = makeEditorWindowController(fileURL: nil, remembersQuickCapturePosition: true)
        quickCaptureController = controller
        controller.window?.alphaValue = windowAlphaValue(for: noteStore.panelOpacity)
        controller.showWindowAndFocus()
    }

    @objc
    private func showFloatingNote() {
        cleanupClosedWindows()

        if let controller = floatingNoteController, !controller.isWindowClosed {
            if controller.window?.isVisible == true {
                controller.hideWindowForToggle()
            } else {
                controller.showWindowAndFocus()
            }
            return
        }

        floatingNoteController = nil
        let controller = makeFloatingNoteWindowController()
        floatingNoteController = controller
        controller.window?.alphaValue = windowAlphaValue(for: noteStore.panelOpacity)
        controller.showWindowAndFocus()
    }

    private func openEditor(for url: URL) {
        cleanupClosedWindows()
        let key = url.standardizedFileURL.path

        if let controller = editorControllers[key], controller.window?.isVisible == true {
            controller.showWindowAndFocus()
            return
        }

        let controller = makeEditorWindowController(fileURL: url)
        editorControllers[key] = controller
        controller.window?.alphaValue = windowAlphaValue(for: noteStore.panelOpacity)
        controller.showWindowAndFocus()
    }

    @objc
    private func showSearchWindow() {
        cleanupClosedWindows()

        if let controller = searchWindowController, controller.window?.isVisible == true {
            controller.showWindowAndFocus()
            return
        }

        let controller = SearchWindowController(
            noteStore: noteStore,
            onOpen: { [weak self] url in
                self?.openEditor(for: url)
            },
            onClose: { [weak self] in
                self?.cleanupClosedWindows()
            }
        )

        searchWindowController = controller
        controller.window?.alphaValue = windowAlphaValue(for: noteStore.panelOpacity)
        controller.showWindowAndFocus()
    }

    @objc
    private func showLibraryWindow() {
        cleanupClosedWindows()

        if let controller = libraryWindowController, controller.window?.isVisible == true {
            controller.showWindowAndFocus()
            return
        }

        let controller = LibraryWindowController(
            noteStore: noteStore,
            onOpenInSeparateWindow: { [weak self] url in
                self?.openEditor(for: url)
            },
            onSave: { [weak self] url in
                self?.didSaveNote(at: url)
            },
            onClose: { [weak self] in
                self?.cleanupClosedWindows()
            }
        )

        libraryWindowController = controller
        controller.showWindowAndFocus()
    }

    @objc
    private func openRecentNote(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        openEditor(for: URL(fileURLWithPath: path))
    }

    @objc
    private func openNotesFolder() {
        NSWorkspace.shared.open(noteStore.notesDirectory)
    }

    @objc
    private func showPreferences() {
        cleanupClosedWindows()

        if let controller = preferencesWindowController, controller.window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            controller.showWindow(self)
            controller.window?.makeKeyAndOrderFront(self)
            return
        }

        preferencesWindowController = nil
        let controller = PreferencesWindowController(
            currentDirectory: noteStore.notesDirectory,
            availableDirectories: noteStore.preferredDirectories,
            currentOpacity: noteStore.panelOpacity,
            currentQuickCaptureHotKey: noteStore.hotKeyString,
            currentFloatingHotKey: noteStore.floatingNoteHotKeyString,
            currentSaveShortcut: noteStore.saveShortcutString,
            revealSavedNoteInFinder: noteStore.revealSavedNoteInFinder,
            floatingNoteStaysOnTop: noteStore.floatingNoteStaysOnTop,
            spellCheckingEnabled: noteStore.spellCheckingEnabled,
            aiEnabled: noteStore.aiEnabled,
            aiOllamaBaseURL: noteStore.aiOllamaBaseURLString,
            aiOllamaModel: noteStore.aiOllamaModel,
            onPreviewOpacity: { [weak self] opacity in
                self?.updateOpenWindowOpacity(opacity)
            },
            onResetWindowFrames: { [weak self] in
                self?.noteStore.quickCaptureWindowFrame = nil
                self?.noteStore.floatingNoteWindowFrame = nil
            }
        ) { [weak self] settings in
            self?.applyPreferences(settings)
        }

        preferencesWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    private func applyPreferences(_ settings: PreferencesSettings) {
        noteStore.configurePreferredDirectories(settings.directories, defaultDirectory: settings.directory)
        noteStore.panelOpacity = settings.opacity
        noteStore.hotKeyString = settings.quickCaptureHotKey.displayString
        noteStore.floatingNoteHotKeyString = settings.floatingHotKey.displayString
        noteStore.saveShortcutString = settings.saveShortcut.displayString
        noteStore.revealSavedNoteInFinder = settings.revealSavedNoteInFinder
        noteStore.floatingNoteStaysOnTop = settings.floatingNoteStaysOnTop
        noteStore.spellCheckingEnabled = settings.spellCheckingEnabled
        noteStore.aiEnabled = settings.aiEnabled
        noteStore.aiOllamaBaseURLString = settings.aiOllamaBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        noteStore.aiOllamaModel = settings.aiOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try noteStore.ensureNotesDirectory()
        } catch {
            presentErrorAlert(message: "无法准备笔记文件夹", details: error.localizedDescription)
        }

        registerHotKeysIfNeeded()
        rebuildMenu()
        updateOpenWindowOpacity(settings.opacity)
        updateOpenEditorPreferences()
        updateFloatingNoteLevel()
    }

    private func updateOpenWindowOpacity(_ opacity: Double) {
        let alpha = windowAlphaValue(for: opacity)
        quickCaptureController?.window?.alphaValue = alpha
        quickCaptureController?.updatePanelOpacity(opacity)
        floatingNoteController?.window?.alphaValue = alpha
        floatingNoteController?.updatePanelOpacity(opacity)
        for controller in editorControllers.values {
            controller.window?.alphaValue = alpha
            controller.updatePanelOpacity(opacity)
        }
        libraryWindowController?.updatePanelOpacity(opacity)
        searchWindowController?.window?.alphaValue = alpha
        searchWindowController?.updatePanelOpacity(opacity)
        preferencesWindowController?.updatePanelOpacity(opacity)
    }

    private func didSaveNote(at url: URL) {
        rebuildMenu()
        if noteStore.revealSavedNoteInFinder {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        cleanupClosedWindows()
    }

    private func updateOpenEditorPreferences() {
        let spellCheckingEnabled = noteStore.spellCheckingEnabled
        quickCaptureController?.updateEditorPreferences(spellCheckingEnabled: spellCheckingEnabled)
        floatingNoteController?.updateEditorPreferences(spellCheckingEnabled: spellCheckingEnabled)
        editorControllers.values.forEach { $0.updateEditorPreferences(spellCheckingEnabled: spellCheckingEnabled) }
    }

    private func updateFloatingNoteLevel() {
        floatingNoteController?.window?.level = noteStore.floatingNoteStaysOnTop ? .statusBar : .normal
    }

    private func makeEditorWindowController(fileURL: URL?, remembersQuickCapturePosition: Bool = false) -> EditorWindowController {
        EditorWindowController(
            noteStore: noteStore,
            panelOpacity: noteStore.panelOpacity,
            fileURL: fileURL,
            initialWindowFrame: remembersQuickCapturePosition ? storedQuickCaptureFrame() : nil,
            draftIDOverride: remembersQuickCapturePosition ? "quick-capture" : nil,
            saveShortcut: HotKeySpec.parse(noteStore.saveShortcutString),
            showsSaveButton: true,
            remembersWindowFrame: remembersQuickCapturePosition ? { [weak self] frame in
                self?.noteStore.quickCaptureWindowFrame = StoredWindowFrame(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.size.width,
                    height: frame.size.height
                )
            } : nil,
            onSave: { [weak self] savedURL in
                self?.didSaveNote(at: savedURL)
            },
            onClose: { [weak self] in
                self?.cleanupClosedWindows()
            },
            onRequestSearch: { [weak self] in
                self?.showSearchWindow()
            },
            onRequestPreferences: { [weak self] in
                self?.showPreferences()
            }
        )
    }

    private func makeFloatingNoteWindowController() -> EditorWindowController {
        EditorWindowController(
            noteStore: noteStore,
            panelOpacity: noteStore.panelOpacity,
            fileURL: nil,
            initialWindowFrame: storedFloatingNoteFrame(),
            draftIDOverride: "floating-note",
            saveShortcut: HotKeySpec.parse(noteStore.saveShortcutString),
            showsSaveButton: false,
            windowLevel: noteStore.floatingNoteStaysOnTop ? .statusBar : .normal,
            remembersWindowFrame: { [weak self] frame in
                self?.noteStore.floatingNoteWindowFrame = StoredWindowFrame(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.size.width,
                    height: frame.size.height
                )
            },
            onSave: { [weak self] savedURL in
                self?.didSaveNote(at: savedURL)
            },
            onClose: { [weak self] in
                self?.cleanupClosedWindows()
            },
            onRequestSearch: { [weak self] in
                self?.showSearchWindow()
            },
            onRequestPreferences: { [weak self] in
                self?.showPreferences()
            }
        )
    }

    private func storedQuickCaptureFrame() -> NSRect? {
        guard let frame = noteStore.quickCaptureWindowFrame else { return nil }
        return clampedPanelFrame(
            NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
            fallbackSize: NSSize(width: 412, height: 314),
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
    }

    private func storedFloatingNoteFrame() -> NSRect? {
        guard let frame = noteStore.floatingNoteWindowFrame else { return nil }
        return clampedPanelFrame(
            NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
            fallbackSize: NSSize(width: 412, height: 314),
            visibleFrames: NSScreen.screens.map(\.visibleFrame)
        )
    }

    private func cleanupClosedWindows() {
        if let quickCaptureController {
            let hasWindow = quickCaptureController.window != nil
            if quickCaptureController.isWindowClosed || !hasWindow {
                self.quickCaptureController = nil
            }
        }

        if let floatingNoteController {
            let hasWindow = floatingNoteController.window != nil
            if floatingNoteController.isWindowClosed || !hasWindow {
                self.floatingNoteController = nil
            }
        }

        editorControllers = editorControllers.filter { $0.value.window?.isVisible == true }

        if libraryWindowController?.window?.isVisible != true {
            libraryWindowController = nil
        }

        if searchWindowController?.window?.isVisible != true {
            searchWindowController = nil
        }

        if preferencesWindowController?.window?.isVisible != true {
            preferencesWindowController = nil
        }
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }

    private func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }
}

func clampedPanelFrame(
    _ frame: NSRect,
    fallbackSize: NSSize,
    visibleFrames: [NSRect],
    padding: CGFloat = 12
) -> NSRect {
    guard let targetVisibleFrame = nearestVisibleFrame(to: frame, in: visibleFrames) else {
        return frame
    }

    let maxWidth = max(targetVisibleFrame.width - (padding * 2), 1)
    let maxHeight = max(targetVisibleFrame.height - (padding * 2), 1)
    let proposedWidth = frame.width > 0 ? frame.width : fallbackSize.width
    let proposedHeight = frame.height > 0 ? frame.height : fallbackSize.height
    let width = min(proposedWidth, maxWidth)
    let height = min(proposedHeight, maxHeight)
    let minX = targetVisibleFrame.minX + padding
    let maxX = targetVisibleFrame.maxX - padding - width
    let minY = targetVisibleFrame.minY + padding
    let maxY = targetVisibleFrame.maxY - padding - height

    return NSRect(
        x: min(max(frame.origin.x, minX), maxX),
        y: min(max(frame.origin.y, minY), maxY),
        width: width,
        height: height
    )
}

private func nearestVisibleFrame(to frame: NSRect, in visibleFrames: [NSRect]) -> NSRect? {
    guard !visibleFrames.isEmpty else { return nil }
    let center = NSPoint(x: frame.midX, y: frame.midY)
    if let containing = visibleFrames.first(where: { $0.contains(center) }) {
        return containing
    }

    return visibleFrames.min { lhs, rhs in
        squaredDistance(from: center, to: lhs) < squaredDistance(from: center, to: rhs)
    }
}

private func squaredDistance(from point: NSPoint, to rect: NSRect) -> CGFloat {
    let clampedX = min(max(point.x, rect.minX), rect.maxX)
    let clampedY = min(max(point.y, rect.minY), rect.maxY)
    let dx = point.x - clampedX
    let dy = point.y - clampedY
    return (dx * dx) + (dy * dy)
}
