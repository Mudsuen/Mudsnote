import AppKit
import Foundation
import QuickMarkdownCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let noteStore = NoteStore()
    private let hotKeyManager = GlobalHotKeyManager()
    private let launchArguments = Set(CommandLine.arguments.dropFirst())

    private var statusItem: NSStatusItem?
    private var quickCaptureController: EditorWindowController?
    private var editorControllers: [String: EditorWindowController] = [:]
    private var searchWindowController: SearchWindowController?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            try noteStore.ensureNotesDirectory()
        } catch {
            presentErrorAlert(message: "Failed to prepare notes directory", details: error.localizedDescription)
        }

        setupStatusItem()
        registerHotKeyIfNeeded()

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

        if launchArguments.contains("--preferences") {
            DispatchQueue.main.async { [weak self] in
                self?.showPreferences()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "note.text.badge.plus", accessibilityDescription: "QuickMarkdown")
            button.toolTip = "QuickMarkdown"
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let newNote = NSMenuItem(title: "Quick Capture", action: #selector(showQuickCapture), keyEquivalent: "n")
        newNote.target = self
        menu.addItem(newNote)

        let searchNotes = NSMenuItem(title: "Search Notes...", action: #selector(showSearchWindow), keyEquivalent: "f")
        searchNotes.target = self
        menu.addItem(searchNotes)

        let openFolder = NSMenuItem(title: "Open Default Notes Folder", action: #selector(openNotesFolder), keyEquivalent: "o")
        openFolder.target = self
        menu.addItem(openFolder)

        let preferences = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)

        menu.addItem(.separator())

        let recent = noteStore.listRecentFiles()
        if recent.isEmpty {
            let empty = NSMenuItem(title: "No recent notes yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            let header = NSMenuItem(title: "Recent Notes", action: nil, keyEquivalent: "")
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

        let quit = NSMenuItem(title: "Quit QuickMarkdown", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
    }

    private func registerHotKeyIfNeeded() {
        guard let spec = HotKeySpec.parse(noteStore.hotKeyString) else { return }
        let registered = hotKeyManager.register(spec) { [weak self] in
            Task { @MainActor in
                self?.showQuickCapture()
            }
        }

        if !registered {
            presentErrorAlert(message: "Hotkey registration failed", details: "Try a different shortcut in Preferences.")
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
        let controller = PreferencesWindowController(
            currentDirectory: noteStore.notesDirectory,
            availableDirectories: noteStore.preferredDirectories,
            currentOpacity: noteStore.panelOpacity,
            currentHotKey: noteStore.hotKeyString,
            onPreviewOpacity: { [weak self] opacity in
                self?.updateOpenWindowOpacity(opacity)
            }
        ) { [weak self] directory, directories, opacity, hotKey in
            self?.applyPreferences(directory: directory, directories: directories, opacity: opacity, hotKey: hotKey)
        }

        preferencesWindowController = controller
        controller.window?.alphaValue = windowAlphaValue(for: noteStore.panelOpacity)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(self)
        controller.window?.makeKeyAndOrderFront(self)
    }

    private func applyPreferences(directory: URL, directories: [URL], opacity: Double, hotKey: HotKeySpec) {
        noteStore.configurePreferredDirectories(directories, defaultDirectory: directory)
        noteStore.panelOpacity = opacity
        noteStore.hotKeyString = hotKey.displayString

        do {
            try noteStore.ensureNotesDirectory()
        } catch {
            presentErrorAlert(message: "Failed to prepare notes directory", details: error.localizedDescription)
        }

        registerHotKeyIfNeeded()
        rebuildMenu()
        updateOpenWindowOpacity(opacity)
    }

    private func updateOpenWindowOpacity(_ opacity: Double) {
        let alpha = windowAlphaValue(for: opacity)
        quickCaptureController?.window?.alphaValue = alpha
        quickCaptureController?.updatePanelOpacity(opacity)
        for controller in editorControllers.values {
            controller.window?.alphaValue = alpha
            controller.updatePanelOpacity(opacity)
        }
        searchWindowController?.window?.alphaValue = alpha
        searchWindowController?.updatePanelOpacity(opacity)
        preferencesWindowController?.window?.alphaValue = alpha
        preferencesWindowController?.updatePanelOpacity(opacity)
    }

    private func didSaveNote(at url: URL) {
        rebuildMenu()
        NSWorkspace.shared.activateFileViewerSelecting([url])
        cleanupClosedWindows()
    }

    private func makeEditorWindowController(fileURL: URL?, remembersQuickCapturePosition: Bool = false) -> EditorWindowController {
        EditorWindowController(
            noteStore: noteStore,
            panelOpacity: noteStore.panelOpacity,
            fileURL: fileURL,
            initialWindowFrame: remembersQuickCapturePosition ? storedQuickCaptureFrame() : nil,
            remembersPosition: remembersQuickCapturePosition,
            onSave: { [weak self] savedURL in
                self?.didSaveNote(at: savedURL)
            },
            onClose: { [weak self] in
                self?.cleanupClosedWindows()
            },
            onRequestSearch: { [weak self] in
                self?.showSearchWindow()
            }
        )
    }

    private func storedQuickCaptureFrame() -> NSRect? {
        guard let frame = noteStore.quickCaptureWindowFrame else { return nil }
        return NSRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private func cleanupClosedWindows() {
        if let quickCaptureController {
            let hasWindow = quickCaptureController.window != nil
            if quickCaptureController.isWindowClosed || !hasWindow {
                self.quickCaptureController = nil
            }
        }

        editorControllers = editorControllers.filter { $0.value.window?.isVisible == true }

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
