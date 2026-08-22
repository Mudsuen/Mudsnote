import AppKit
import Foundation
import MudsnoteCore
import UniformTypeIdentifiers

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private let noteStore: NoteStore
    private let hotKeyManager = GlobalHotKeyManager()
    private let launchArguments: Set<String>
    private let visualQASelectedNoteURL: URL?
    private let usesCanonicalVisualQAWindowSize: Bool
    private let prefersExternalVisualQAScreen: Bool
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
    private var fileMoveNoteMenu: NSMenu?
    private var pendingExternalMarkdownURLs: [URL] = []
    private var hasFinishedLaunching = false
    private var statusMenuRefreshTask: Task<Void, Never>?

    override init() {
        let rawLaunchArguments = Array(CommandLine.arguments.dropFirst())
        self.launchArguments = Set(rawLaunchArguments)
        self.noteStore = Self.makeNoteStore(arguments: rawLaunchArguments)
        self.visualQASelectedNoteURL = Self.visualQASelectedNoteURL(arguments: rawLaunchArguments)
        self.usesCanonicalVisualQAWindowSize = Self.usesCanonicalVisualQAWindowSize(arguments: rawLaunchArguments)
        self.prefersExternalVisualQAScreen = Self.prefersExternalVisualQAScreen(arguments: rawLaunchArguments)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let opensExternalMarkdown = !pendingExternalMarkdownURLs.isEmpty
        let opensLibrary = Self.shouldOpenLibraryOnLaunch(arguments: launchArguments) && !opensExternalMarkdown
        NSApp.setActivationPolicy(opensLibrary || opensExternalMarkdown ? .regular : .accessory)

        do {
            try noteStore.ensureNotesDirectory()
        } catch {
            presentErrorAlert(message: "无法准备笔记文件夹", details: error.localizedDescription)
        }

        setupMainMenu()
        setupStatusItem()
        registerHotKeysIfNeeded()
        synchronizeAIMemoryIfNeeded()
        hasFinishedLaunching = true

        if opensExternalMarkdown {
            let urls = pendingExternalMarkdownURLs
            pendingExternalMarkdownURLs.removeAll()
            DispatchQueue.main.async { [weak self] in
                self?.openExternalMarkdownFiles(urls)
            }
        }

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

        if opensLibrary {
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Self.terminationReply(
            editorControllers: activeEditorControllersForTermination(),
            libraryController: libraryWindowController
        )
    }

    static func terminationReply(
        editorControllers: [EditorWindowController],
        libraryController: LibraryWindowController?
    ) -> NSApplication.TerminateReply {
        for controller in editorControllers where !controller.prepareForApplicationTermination() {
            controller.window?.makeKeyAndOrderFront(nil)
            return .terminateCancel
        }
        if let libraryController,
           let window = libraryController.window,
           !libraryController.windowShouldClose(window) {
            window.makeKeyAndOrderFront(nil)
            return .terminateCancel
        }
        return .terminateNow
    }

    private func activeEditorControllersForTermination() -> [EditorWindowController] {
        var controllers: [EditorWindowController] = []
        var seen = Set<ObjectIdentifier>()
        for controller in [quickCaptureController, floatingNoteController] + Array(editorControllers.values) {
            guard let controller,
                  !controller.isWindowClosed,
                  seen.insert(ObjectIdentifier(controller)).inserted else {
                continue
            }
            controllers.append(controller)
        }
        return controllers
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLibraryWindow()
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = Self.markdownFileURLs(from: filenames)
        guard !urls.isEmpty else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        if hasFinishedLaunching {
            openExternalMarkdownFiles(urls)
        } else {
            pendingExternalMarkdownURLs.append(contentsOf: urls)
            pendingExternalMarkdownURLs = Self.deduplicatedFileURLs(pendingExternalMarkdownURLs)
        }
        sender.reply(toOpenOrPrint: urls.count == filenames.count ? .success : .failure)
    }

    static func shouldOpenLibraryOnLaunch(arguments: Set<String>) -> Bool {
        arguments.contains("--library") || arguments.isDisjoint(with: explicitLaunchWindowArguments)
    }

    static func markdownFileURLs(from filenames: [String]) -> [URL] {
        deduplicatedFileURLs(filenames.compactMap { filename in
            let url = URL(fileURLWithPath: filename).standardizedFileURL
            guard ["md", "markdown"].contains(url.pathExtension.lowercased()) else { return nil }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else {
                return nil
            }
            return url
        })
    }

    private static func deduplicatedFileURLs(_ urls: [URL]) -> [URL] {
        var paths = Set<String>()
        return urls.filter { paths.insert($0.standardizedFileURL.path).inserted }
    }

    static func makeNoteStore(
        arguments: [String] = Array(CommandLine.arguments.dropFirst())
    ) -> NoteStore {
        guard let notesDirectoryPath = value(after: "--visual-qa-notes-dir", in: arguments) else {
            return NoteStore()
        }

        let suiteName = value(after: "--visual-qa-defaults-suite", in: arguments)
            ?? "local.codex.mudsnote.visual-qa"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let appSupportDirectory = value(after: "--visual-qa-app-support-dir", in: arguments).map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }
        let noteStore = NoteStore(defaults: defaults, legacyDefaults: nil, appSupportDirectory: appSupportDirectory)
        let notesDirectory = URL(fileURLWithPath: notesDirectoryPath, isDirectory: true).standardizedFileURL
        let extraDirectories = values(after: "--visual-qa-extra-dir", in: arguments).map {
            URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
        }
        noteStore.configurePreferredDirectories([notesDirectory] + extraDirectories, defaultDirectory: notesDirectory)
        return noteStore
    }

    static func visualQASelectedNoteURL(arguments: [String]) -> URL? {
        value(after: "--visual-qa-select-note", in: arguments).map {
            URL(fileURLWithPath: $0).standardizedFileURL
        }
    }

    static func usesCanonicalVisualQAWindowSize(arguments: [String]) -> Bool {
        arguments.contains("--visual-qa-canonical-window-size")
    }

    static func prefersExternalVisualQAScreen(arguments: [String]) -> Bool {
        arguments.contains("--visual-qa-external-screen")
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        let value = arguments[valueIndex]
        return value.hasPrefix("--") ? nil : value
    }

    private static func values(after flag: String, in arguments: [String]) -> [String] {
        arguments.indices.compactMap { index in
            guard arguments[index] == flag else { return nil }
            let valueIndex = arguments.index(after: index)
            guard arguments.indices.contains(valueIndex) else { return nil }
            let value = arguments[valueIndex]
            return value.hasPrefix("--") ? nil : value
        }
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

    private func setupMainMenu() {
        let application = NSApplication.shared
        let mainMenu = makeMainMenuForApplication()
        application.mainMenu = mainMenu
        application.windowsMenu = mainMenu.items.first { $0.title == "窗口" }?.submenu
    }

    func makeMainMenuForApplication() -> NSMenu {
        let mainMenu = NSMenu(title: "Main Menu")

        let appMenuItem = NSMenuItem(title: MudsnoteBrand.appName, action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: MudsnoteBrand.appName)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let aboutItem = NSMenuItem(
            title: "关于 \(MudsnoteBrand.appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        aboutItem.target = NSApp
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "设置...", action: #selector(showPreferences), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let hideItem = NSMenuItem(title: "隐藏 \(MudsnoteBrand.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hideItem.target = NSApp
        hideItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(hideItem)

        let hideOthersItem = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.target = NSApp
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)

        let showAllItem = NSMenuItem(title: "全部显示", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAllItem.target = NSApp
        appMenu.addItem(showAllItem)
        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 \(MudsnoteBrand.appName)", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = [.command]
        appMenu.addItem(quitItem)

        let fileMenuItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let newNoteItem = NSMenuItem(title: "新建笔记", action: #selector(newNoteFromMainMenu), keyEquivalent: "n")
        newNoteItem.target = self
        newNoteItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(newNoteItem)

        let newFolderItem = NSMenuItem(title: "新建文件夹", action: #selector(newFolderFromMainMenu), keyEquivalent: "n")
        newFolderItem.target = self
        newFolderItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(newFolderItem)

        let addLibraryFolderItem = NSMenuItem(
            title: "将文件夹添加到资料库…",
            action: #selector(addLibraryFolderFromMainMenu),
            keyEquivalent: ""
        )
        addLibraryFolderItem.target = self
        fileMenu.addItem(addLibraryFolderItem)

        let manageAttachmentsItem = NSMenuItem(
            title: "管理附件…",
            action: #selector(manageAttachmentsFromMainMenu),
            keyEquivalent: ""
        )
        manageAttachmentsItem.target = self
        fileMenu.addItem(manageAttachmentsItem)
        fileMenu.addItem(.separator())

        let openItem = NSMenuItem(title: "打开...", action: #selector(openDocumentFromMainMenu), keyEquivalent: "o")
        openItem.target = self
        openItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(openItem)

        let saveItem = NSMenuItem(title: "保存", action: #selector(saveDocumentFromMainMenu), keyEquivalent: "s")
        saveItem.target = self
        saveItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(saveItem)
        fileMenu.addItem(.separator())

        let moveNoteItem = NSMenuItem(
            title: "移到文件夹",
            action: #selector(moveSelectedNotesFromMainMenu),
            keyEquivalent: ""
        )
        moveNoteItem.target = self
        let moveNoteMenu = NSMenu(title: "移到文件夹")
        moveNoteMenu.delegate = self
        moveNoteItem.submenu = moveNoteMenu
        fileMoveNoteMenu = moveNoteMenu
        fileMenu.addItem(moveNoteItem)

        let deleteNoteItem = NSMenuItem(
            title: "移到最近删除",
            action: #selector(deleteSelectedNotesFromMainMenu),
            keyEquivalent: ""
        )
        deleteNoteItem.target = self
        fileMenu.addItem(deleteNoteItem)

        let restoreNoteItem = NSMenuItem(
            title: "恢复笔记",
            action: #selector(restoreSelectedNotesFromMainMenu),
            keyEquivalent: ""
        )
        restoreNoteItem.target = self
        fileMenu.addItem(restoreNoteItem)
        fileMenu.addItem(.separator())

        let closeItem = NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.target = nil
        closeItem.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(closeItem)

        let editMenuItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        addResponderMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z", to: editMenu)
        addResponderMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z", modifiers: [.command, .shift], to: editMenu)
        editMenu.addItem(.separator())
        addResponderMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x", to: editMenu)
        addResponderMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c", to: editMenu)
        addResponderMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v", to: editMenu)
        addResponderMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a", to: editMenu)

        let viewMenuItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "显示")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        for (title, mode, keyEquivalent) in [
            ("显示为列表", LibraryNoteViewMode.list, "1"),
            ("显示为画廊", .gallery, "2")
        ] {
            let item = NSMenuItem(
                title: title,
                action: #selector(setLibraryNoteViewModeFromMainMenu(_:)),
                keyEquivalent: keyEquivalent
            )
            item.target = self
            item.tag = mode.rawValue
            item.keyEquivalentModifierMask = [.command]
            viewMenu.addItem(item)
        }
        viewMenu.addItem(.separator())

        let findItem = NSMenuItem(title: "搜索笔记", action: #selector(focusLibrarySearchFromMainMenu), keyEquivalent: "f")
        findItem.target = self
        findItem.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(findItem)

        let sidebarItem = NSMenuItem(title: "显示或隐藏资料库", action: #selector(toggleLibrarySidebarFromMainMenu), keyEquivalent: "s")
        sidebarItem.target = self
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(sidebarItem)

        let knowledgeGraphItem = NSMenuItem(
            title: "显示知识图谱",
            action: #selector(showKnowledgeGraphFromMainMenu),
            keyEquivalent: "g"
        )
        knowledgeGraphItem.target = self
        knowledgeGraphItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(knowledgeGraphItem)
        viewMenu.addItem(.separator())

        let sortItem = NSMenuItem(title: "排序方式", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: "排序方式")
        for (title, order) in [
            ("编辑日期", LibraryNoteSortOrder.dateEdited),
            ("创建日期", .dateCreated),
            ("标题", .title)
        ] {
            let item = NSMenuItem(
                title: title,
                action: #selector(sortLibraryNotesFromMainMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = order.rawValue
            sortMenu.addItem(item)
        }
        sortItem.submenu = sortMenu
        viewMenu.addItem(sortItem)

        let groupByDateItem = NSMenuItem(
            title: "按日期分组",
            action: #selector(toggleLibraryNoteGroupingFromMainMenu(_:)),
            keyEquivalent: ""
        )
        groupByDateItem.target = self
        viewMenu.addItem(groupByDateItem)

        let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        addResponderMenuItem(title: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m", to: windowMenu)
        addResponderMenuItem(title: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "", to: windowMenu)

        return mainMenu
    }

    private func addResponderMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        to menu: NSMenu
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = nil
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }

    private func rebuildMenu(recentFiles: [NoteFile]? = nil) {
        let menu = NSMenu()

        let newNote = NSMenuItem(title: "快速笔记", action: #selector(showQuickCapture), keyEquivalent: "")
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

        let recent = recentFiles ?? noteStore.listRecentFiles()
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
                showFloatingWindowWithoutRevealingOtherWindows(controller)
            }
            return
        }

        floatingNoteController = nil
        let controller = makeFloatingNoteWindowController()
        floatingNoteController = controller
        controller.window?.alphaValue = windowAlphaValue(for: noteStore.panelOpacity)
        showFloatingWindowWithoutRevealingOtherWindows(controller)
    }

    private func showFloatingWindowWithoutRevealingOtherWindows(
        _ controller: EditorWindowController
    ) {
        let wasApplicationHidden = NSApp.isHidden
        controller.showWindowAndFocus()
        guard wasApplicationHidden else { return }
        for window in NSApp.windows where window !== controller.window {
            window.orderOut(nil)
        }
    }

    private func openEditor(for url: URL) {
        cleanupClosedWindows()
        let key = url.standardizedFileURL.path

        if let controller = editorControllers[key], controller.window?.isVisible == true {
            controller.showWindowAndFocus()
            return
        }

        let controller = makeEditorWindowController(fileURL: url, usesFloatingNoteStyle: true)
        editorControllers[key] = controller
        controller.window?.alphaValue = windowAlphaValue(for: noteStore.panelOpacity)
        controller.showWindowAndFocus()
        refreshFloatingNoteBrowsers()
    }

    private func createFloatingNoteWindow() {
        do {
            let url = try noteStore.saveNewNote(
                title: "",
                body: "",
                in: noteStore.notesDirectory
            )
            openEditor(for: url)
            rebuildMenu()
        } catch {
            presentErrorAlert(message: "无法新建悬浮笔记", details: error.localizedDescription)
        }
    }

    private func activeFloatingNoteWindows() -> [FloatingNoteWindowDescriptor] {
        let controllers = ([floatingNoteController] + Array(editorControllers.values))
            .compactMap { $0 }
            .filter { $0.window?.isVisible == true && $0.isFloatingNoteMode }
        return controllers.map { controller in
            let document = controller.currentDocument()
            let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let url = controller.activeFloatingNoteURL?.standardizedFileURL
            return FloatingNoteWindowDescriptor(
                id: controller.floatingWindowID,
                url: url,
                title: title.isEmpty ? "未命名笔记" : title,
                subtitle: url.map(displayPath) ?? "尚未保存"
            )
        }.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func closeFloatingNoteWindow(id: UUID) {
        if let entry = editorControllers.first(where: { $0.value.floatingWindowID == id }) {
            editorControllers.removeValue(forKey: entry.key)
            entry.value.window?.close()
        } else if floatingNoteController?.floatingWindowID == id {
            floatingNoteController?.window?.close()
            floatingNoteController = nil
        }
        refreshFloatingNoteBrowsers()
    }

    private func activateFloatingNoteWindow(id: UUID) {
        let controller = ([floatingNoteController] + Array(editorControllers.values))
            .compactMap { $0 }
            .first { $0.floatingWindowID == id }
        controller?.showWindowAndFocus()
    }

    private func refreshFloatingNoteBrowsers() {
        floatingNoteController?.refreshFloatingNoteBrowser()
        editorControllers.values.forEach { $0.refreshFloatingNoteBrowser() }
    }

    private func openExternalMarkdownFiles(_ urls: [URL]) {
        showLibraryWindow()
        for url in Self.deduplicatedFileURLs(urls) {
            do {
                try libraryWindowController?.openMarkdownDocumentForLibrary(at: url)
            } catch {
                presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
            }
        }
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
        NSApp.setActivationPolicy(.regular)

        if let controller = libraryWindowController {
            controller.showWindowAndFocus()
            selectVisualQANoteIfNeeded(in: controller)
            return
        }

        let controller = LibraryWindowController(
            noteStore: noteStore,
            defersInitialNoteHydration: true,
            usesCanonicalWindowSize: usesCanonicalVisualQAWindowSize,
            prefersExternalScreen: prefersExternalVisualQAScreen,
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
        selectVisualQANoteIfNeeded(in: controller)
    }

    @objc
    func newNoteFromMainMenu() {
        showLibraryWindow()
        libraryWindowController?.createNewNoteForLibrary()
    }

    @objc
    func newFolderFromMainMenu() {
        showLibraryWindow()
        DispatchQueue.main.async { [weak self] in
            self?.libraryWindowController?.createNewFolderForLibrary()
        }
    }

    @objc
    func addLibraryFolderFromMainMenu() {
        showLibraryWindow()
        DispatchQueue.main.async { [weak self] in
            self?.libraryWindowController?.presentAddExistingLibraryFolderPanelForLibrary()
        }
    }

    @objc
    func manageAttachmentsFromMainMenu() {
        showLibraryWindow()
        libraryWindowController?.showAttachmentManagerForLibrary()
    }

    @objc
    func openDocumentFromMainMenu() {
        let panel = NSOpenPanel()
        panel.title = "打开 Markdown 文件"
        panel.prompt = "打开"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["md", "markdown"].compactMap {
            UTType(filenameExtension: $0, conformingTo: .text)
        }
        guard panel.runModal() == .OK else { return }
        openExternalMarkdownFiles(panel.urls)
    }

    @objc
    func saveDocumentFromMainMenu() {
        (NSApp.keyWindow?.windowController as? EditorWindowController)?.savePressed()
    }

    @objc
    func deleteSelectedNotesFromMainMenu() {
        do {
            try libraryWindowController?.deleteSelectedNotesForLibrary()
        } catch {
            presentErrorAlert(message: "删除失败", details: error.localizedDescription)
        }
    }

    @objc
    func restoreSelectedNotesFromMainMenu() {
        do {
            _ = try libraryWindowController?.restoreSelectedNoteForLibrary()
        } catch {
            presentErrorAlert(message: "恢复失败", details: error.localizedDescription)
        }
    }

    @objc
    func moveSelectedNotesFromMainMenu() {}

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === fileMoveNoteMenu else { return }
        menu.removeAllItems()
        guard let sourceMenu = libraryWindowController?.makeMoveNoteMenuForLibrary(),
              !sourceMenu.items.isEmpty else {
            let emptyItem = NSMenuItem(title: "无可用文件夹", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }
        while let item = sourceMenu.items.first {
            sourceMenu.removeItem(item)
            menu.addItem(item)
        }
    }

    @objc
    func focusLibrarySearchFromMainMenu() {
        showLibraryWindow()
        libraryWindowController?.focusSearchForLibrary()
    }

    @objc
    func toggleLibrarySidebarFromMainMenu() {
        showLibraryWindow()
        libraryWindowController?.toggleSourceListForLibrary()
    }

    @objc
    func showKnowledgeGraphFromMainMenu() {
        showLibraryWindow()
        libraryWindowController?.showKnowledgeGraphForLibrary()
    }

    @objc
    func setLibraryNoteViewModeFromMainMenu(_ sender: NSMenuItem) {
        guard let mode = LibraryNoteViewMode(rawValue: sender.tag) else { return }
        showLibraryWindow()
        libraryWindowController?.setNoteListViewModeForLibrary(mode)
    }

    @objc
    func sortLibraryNotesFromMainMenu(_ sender: NSMenuItem) {
        guard let order = LibraryNoteSortOrder(rawValue: sender.tag) else { return }
        showLibraryWindow()
        libraryWindowController?.setNoteListSortOrderForLibrary(order)
    }

    @objc
    func toggleLibraryNoteGroupingFromMainMenu(_ sender: NSMenuItem) {
        showLibraryWindow()
        guard let libraryWindowController else { return }
        libraryWindowController.setNoteListGroupingForLibrary(!libraryWindowController.groupsNoteListByDate)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(saveDocumentFromMainMenu):
            return NSApp.keyWindow?.windowController is EditorWindowController
        case #selector(moveSelectedNotesFromMainMenu):
            return libraryWindowController?.canMoveSelectedNotesFromMenuForLibrary ?? false
        case #selector(deleteSelectedNotesFromMainMenu):
            return libraryWindowController?.canDeleteSelectedNotesFromMenuForLibrary ?? false
        case #selector(restoreSelectedNotesFromMainMenu):
            return libraryWindowController?.canRestoreSelectedNotesFromMenuForLibrary ?? false
        case #selector(showKnowledgeGraphFromMainMenu):
            return libraryWindowController?.canShowKnowledgeGraphForLibrary ?? false
        case #selector(sortLibraryNotesFromMainMenu(_:)):
            let currentOrder = libraryWindowController?.noteListSortOrder
                ?? LibraryNoteSortOrder(rawValue: noteStore.libraryNoteSortOrderRawValue)
                ?? .dateEdited
            menuItem.state = menuItem.tag == currentOrder.rawValue ? .on : .off
            return true
        case #selector(toggleLibraryNoteGroupingFromMainMenu(_:)):
            let groupsByDate = libraryWindowController?.groupsNoteListByDate
                ?? noteStore.libraryGroupsNotesByDate
            menuItem.state = groupsByDate ? .on : .off
            return true
        case #selector(setLibraryNoteViewModeFromMainMenu(_:)):
            let currentMode = libraryWindowController?.noteListViewMode
                ?? LibraryNoteViewMode(rawValue: noteStore.libraryNoteViewModeRawValue)
                ?? .list
            menuItem.state = menuItem.tag == currentMode.rawValue ? .on : .off
            return true
        default:
            return true
        }
    }

    private func selectVisualQANoteIfNeeded(in controller: LibraryWindowController) {
        guard let visualQASelectedNoteURL else { return }
        controller.selectNoteForVisualQA(at: visualQASelectedNoteURL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak controller] in
            controller?.selectNoteForVisualQA(at: visualQASelectedNoteURL)
        }
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
            floatingNoteStaysOnTop: noteStore.floatingNoteStaysOnTop,
            spellCheckingEnabled: noteStore.spellCheckingEnabled,
            currentThemeColorIdentifier: noteStore.themeColorIdentifier,
            libraryIncludesSubfolderNotes: noteStore.libraryIncludesSubfolderNotes,
            searchDefaultScope: noteStore.searchDefaultScope,
            includesArchivedNotesInSearchAndKnowledge: noteStore.includesArchivedNotesInSearchAndKnowledge,
            editorContextMenuOptions: noteStore.enabledEditorContextMenuOptions,
            selectionToolbarOptions: noteStore.enabledSelectionToolbarOptions,
            aiEnabled: noteStore.aiEnabled,
            aiCodexExecutablePath: noteStore.aiCodexExecutablePath,
            aiMemoryDailySyncEnabled: noteStore.aiMemoryDailySyncEnabled,
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
        noteStore.floatingNoteStaysOnTop = settings.floatingNoteStaysOnTop
        noteStore.spellCheckingEnabled = settings.spellCheckingEnabled
        noteStore.themeColorIdentifier = settings.themeColorIdentifier
        noteStore.libraryIncludesSubfolderNotes = settings.libraryIncludesSubfolderNotes
        noteStore.searchDefaultScope = settings.searchDefaultScope
        noteStore.includesArchivedNotesInSearchAndKnowledge = settings.includesArchivedNotesInSearchAndKnowledge
        noteStore.enabledEditorContextMenuOptions = settings.editorContextMenuOptions
        noteStore.enabledSelectionToolbarOptions = settings.selectionToolbarOptions
        noteStore.aiEnabled = settings.aiEnabled
        noteStore.aiCodexExecutablePath = settings.aiCodexExecutablePath.trimmingCharacters(in: .whitespacesAndNewlines)
        noteStore.aiMemoryDailySyncEnabled = settings.aiMemoryDailySyncEnabled

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
        libraryWindowController?.refreshFolderNoteVisibilityForLibrary()
        libraryWindowController?.refreshThemeColorForLibrary()
        synchronizeAIMemoryIfNeeded()
    }

    private func synchronizeAIMemoryIfNeeded(force: Bool = false) {
        guard noteStore.aiMemoryDailySyncEnabled else { return }
        let memoryDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/memories", isDirectory: true)
        let service = AIMemorySyncService(
            memoryDirectory: memoryDirectory,
            destinationRoot: noteStore.notesDirectory
        )
        let lastSyncDate = noteStore.aiMemoryLastSyncDate
        let noteStore = noteStore
        Task.detached(priority: .utility) {
            let result = try? service.sync(
                lastSyncDate: lastSyncDate,
                force: force
            )
            guard let result else { return }
            noteStore.aiMemoryLastSyncDate = result.syncedAt
            if result.didWrite {
                noteStore.markSearchIndexDirty(at: [result.destinationURL])
            }
        }
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

    private func didSaveNote(at _: URL) {
        statusMenuRefreshTask?.cancel()
        let noteStore = noteStore
        statusMenuRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let recentFiles = await Task.detached(priority: .utility) {
                noteStore.listRecentFiles()
            }.value
            guard !Task.isCancelled, let self else { return }
            self.statusMenuRefreshTask = nil
            self.rebuildMenu(recentFiles: recentFiles)
            self.cleanupClosedWindows()
        }
    }

    private func updateOpenEditorPreferences() {
        let spellCheckingEnabled = noteStore.spellCheckingEnabled
        quickCaptureController?.updateEditorPreferences(spellCheckingEnabled: spellCheckingEnabled)
        floatingNoteController?.updateEditorPreferences(spellCheckingEnabled: spellCheckingEnabled)
        editorControllers.values.forEach { $0.updateEditorPreferences(spellCheckingEnabled: spellCheckingEnabled) }
    }

    private func updateFloatingNoteLevel() {
        let level = noteStore.floatingNoteStaysOnTop ? NSWindow.Level.statusBar : .normal
        floatingNoteController?.window?.level = level
        editorControllers.values
            .filter { $0.isFloatingNoteMode }
            .forEach { $0.window?.level = level }
    }

    private func makeEditorWindowController(
        fileURL: URL?,
        remembersQuickCapturePosition: Bool = false,
        usesFloatingNoteStyle: Bool = false
    ) -> EditorWindowController {
        let remembersFloatingNotePosition = usesFloatingNoteStyle
        let remembersWindowFrame: ((NSRect) -> Void)?
        if remembersQuickCapturePosition {
            remembersWindowFrame = { [weak self] frame in
                self?.noteStore.quickCaptureWindowFrame = StoredWindowFrame(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.size.width,
                    height: frame.size.height
                )
            }
        } else if remembersFloatingNotePosition {
            remembersWindowFrame = { [weak self] frame in
                self?.noteStore.floatingNoteWindowFrame = StoredWindowFrame(
                    x: frame.origin.x,
                    y: frame.origin.y,
                    width: frame.size.width,
                    height: frame.size.height
                )
            }
        } else {
            remembersWindowFrame = nil
        }

        weak var controllerReference: EditorWindowController?
        let controller = EditorWindowController(
            noteStore: noteStore,
            panelOpacity: noteStore.panelOpacity,
            fileURL: fileURL,
            initialWindowFrame: remembersQuickCapturePosition
                ? storedQuickCaptureFrame()
                : remembersFloatingNotePosition ? nextFloatingNoteFrame() : nil,
            draftIDOverride: remembersQuickCapturePosition
                ? "quick-capture"
                : usesFloatingNoteStyle ? "floating-note" : nil,
            saveShortcut: HotKeySpec.parse(noteStore.saveShortcutString),
            showsSaveButton: !usesFloatingNoteStyle,
            windowLevel: usesFloatingNoteStyle
                ? (noteStore.floatingNoteStaysOnTop ? .statusBar : .normal)
                : nil,
            remembersWindowFrame: remembersWindowFrame,
            onSave: { [weak self] savedURL in
                self?.didSaveNote(at: savedURL)
            },
            onClose: { [weak self] in
                self?.cleanupClosedWindows()
            },
            onRequestSearch: { [weak self] in
                self?.showSearchWindow()
            },
            floatingNoteWindows: { [weak self] in
                self?.activeFloatingNoteWindows() ?? []
            },
            onRequestOpenFloatingNote: { [weak self] url in
                self?.openFloatingNote(url, requestedBy: controllerReference)
            },
            onRequestActivateFloatingNote: { [weak self] id in
                self?.activateFloatingNoteWindow(id: id)
            },
            onRequestCloseFloatingNote: { [weak self] id in
                self?.closeFloatingNoteWindow(id: id)
            },
            onRequestCreateFloatingNote: { [weak self] in
                self?.createFloatingNoteWindow()
            },
            onRequestOpenMarkdownDocument: { [weak self] url in
                self?.openExternalMarkdownFiles([url])
            },
            onRequestPreferences: { [weak self] in
                self?.showPreferences()
            }
        )
        controllerReference = controller
        return controller
    }

    private func openFloatingNote(_ url: URL, requestedBy source: EditorWindowController?) {
        let key = url.standardizedFileURL.path
        if let source,
           source === floatingNoteController,
           source.activeFloatingNoteURL == nil,
           editorControllers[key] == nil {
            source.loadFloatingNote(at: url)
            floatingNoteController = nil
            editorControllers[key] = source
            source.showWindowAndFocus()
            refreshFloatingNoteBrowsers()
            return
        }
        openEditor(for: url)
    }

    private func makeFloatingNoteWindowController() -> EditorWindowController {
        makeEditorWindowController(fileURL: nil, usesFloatingNoteStyle: true)
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

    private func nextFloatingNoteFrame() -> NSRect? {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard let visibleFrame = NSScreen.main?.visibleFrame ?? visibleFrames.first else {
            return storedFloatingNoteFrame()
        }
        let size = NSSize(width: 412, height: 314)
        let baseFrame = storedFloatingNoteFrame() ?? NSRect(
            x: visibleFrame.midX - (size.width / 2),
            y: visibleFrame.maxY - size.height - 72,
            width: size.width,
            height: size.height
        )
        let occupiedFrames = ([floatingNoteController] + Array(editorControllers.values))
            .compactMap { controller -> NSRect? in
                guard controller?.window?.isVisible == true else { return nil }
                return controller?.window?.frame
            }
        return nonOverlappingPanelFrame(
            baseFrame,
            occupiedFrames: occupiedFrames,
            visibleFrames: visibleFrames
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
    minimumSize: NSSize = .zero,
    padding: CGFloat = 12
) -> NSRect {
    guard let targetVisibleFrame = nearestVisibleFrame(to: frame, in: visibleFrames) else {
        return frame
    }

    let maxWidth = max(targetVisibleFrame.width - (padding * 2), 1)
    let maxHeight = max(targetVisibleFrame.height - (padding * 2), 1)
    let proposedWidth = max(frame.width > 0 ? frame.width : fallbackSize.width, minimumSize.width)
    let proposedHeight = max(frame.height > 0 ? frame.height : fallbackSize.height, minimumSize.height)
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

func nonOverlappingPanelFrame(
    _ baseFrame: NSRect,
    occupiedFrames: [NSRect],
    visibleFrames: [NSRect],
    gap: CGFloat = 14
) -> NSRect {
    let base = clampedPanelFrame(baseFrame, fallbackSize: baseFrame.size, visibleFrames: visibleFrames)
    guard occupiedFrames.contains(where: { $0.intersects(base) }) else { return base }
    guard let visibleFrame = nearestVisibleFrame(to: base, in: visibleFrames) else { return base }

    let horizontalStep = base.width + gap
    let verticalStep = base.height + gap
    for ring in 1...max(occupiedFrames.count + 1, 2) {
        let candidates = [
            NSPoint(x: base.minX + CGFloat(ring) * horizontalStep, y: base.minY),
            NSPoint(x: base.minX - CGFloat(ring) * horizontalStep, y: base.minY),
            NSPoint(x: base.minX, y: base.minY - CGFloat(ring) * verticalStep),
            NSPoint(x: base.minX, y: base.minY + CGFloat(ring) * verticalStep)
        ]
        for origin in candidates {
            let candidate = NSRect(origin: origin, size: base.size)
            guard visibleFrame.contains(candidate),
                  !occupiedFrames.contains(where: { $0.intersects(candidate) }) else { continue }
            return candidate
        }
    }

    for index in 1...max(occupiedFrames.count + 1, 2) {
        let offset = CGFloat(index * 28)
        let candidate = clampedPanelFrame(
            base.offsetBy(dx: offset, dy: -offset),
            fallbackSize: base.size,
            visibleFrames: visibleFrames
        )
        if !occupiedFrames.contains(where: { $0.equalTo(candidate) }) {
            return candidate
        }
    }
    return base
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
