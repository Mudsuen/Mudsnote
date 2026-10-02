import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func sourceContextMenuForLibrary(row: Int) -> NSMenu? {
        guard let item = sourceOutlineView.item(atRow: row) as? LibrarySourceOutlineItem else { return nil }
        if let note = item.note {
            let menu = NSMenu()
            let openItem = NSMenuItem(title: "打开", action: #selector(openTreeNoteMenuItemPressed(_:)), keyEquivalent: "")
            openItem.target = self
            openItem.representedObject = note.url
            menu.addItem(openItem)

            let separateItem = NSMenuItem(
                title: "在独立窗口中打开",
                action: #selector(openTreeNoteSeparatelyMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            separateItem.target = self
            separateItem.representedObject = note.url
            menu.addItem(separateItem)

            let listItem = NSMenuItem(
                title: "在列表中显示",
                action: #selector(showTreeNoteInListMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            listItem.target = self
            listItem.representedObject = note.url
            menu.addItem(listItem)
            menu.addItem(.separator())

            if sourceOutlineView.selectedRow != row {
                sourceOutlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            let actions = makeNoteContextMenu()
            for action in actions.items {
                actions.removeItem(action)
                menu.addItem(action)
            }
            return menu
        }
        if case .group(title: _, section: .folders) = item.kind {
            let menu = NSMenu()
            let addItem = NSMenuItem(
                title: "将文件夹添加到资料库…",
                action: #selector(addExistingLibraryFolderMenuItemPressed),
                keyEquivalent: ""
            )
            addItem.target = self
            menu.addItem(addItem)
            return menu
        }
        if case .tag(let tag)? = item.scope { return makeLibraryTagMenu(tag) }
        guard case .folder(let folderURL)? = item.scope else { return nil }
        return makeFolderContextMenu(for: folderURL)
    }

    func makeLibraryTagMenu(_ tag: String) -> NSMenu {
        let menu = NSMenu()
        let add = NSMenuItem(title: "添加到当前笔记", action: #selector(addLibraryTagToNote(_:)), keyEquivalent: "")
        add.target = self
        add.representedObject = tag
        add.isEnabled = canEditCurrentDocument
        menu.addItem(add)
        if selectedTags.contains(where: { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame }) {
            let remove = NSMenuItem(title: "从当前笔记移除", action: #selector(removeLibraryTagFromNote(_:)), keyEquivalent: "")
            remove.target = self
            remove.representedObject = tag
            menu.addItem(remove)
        }
        menu.addItem(.separator())
        let rename = NSMenuItem(title: "重命名标签…", action: #selector(renameLibraryTagPressed(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = tag
        menu.addItem(rename)
        let deleteItem = NSMenuItem(
            title: "从所有笔记删除标签…",
            action: #selector(deleteLibraryTagMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.representedObject = tag
        menu.addItem(deleteItem)
        return menu
    }

    @objc func manageLibraryTagsPressed(_ sender: NSButton) {
        let menu = NSMenu()
        let add = NSMenuItem(title: "添加标签…", action: #selector(addSelectedNoteTagPressed), keyEquivalent: "")
        add.target = self
        menu.addItem(add)
        if !sourceTagNames.isEmpty { menu.addItem(.separator()) }
        for tag in sourceTagNames {
            let item = NSMenuItem(title: libraryDisplayTag(tag), action: nil, keyEquivalent: "")
            item.submenu = makeLibraryTagMenu(tag)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 4), in: sender)
    }

    @objc
    func openTreeNoteMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL,
              let note = sourceCountSnapshot.first(where: {
                  $0.url.standardizedFileURL.path == url.standardizedFileURL.path
              }) else { return }
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            selectedTreeNoteURL = note.url
            load(note: note)
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
        }
    }

    @objc
    func openTreeNoteSeparatelyMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        onOpenInSeparateWindow(url)
    }

    @objc
    func showTreeNoteInListMenuItemPressed(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        selectedScope = .folder(url.deletingLastPathComponent())
        lastListScope = selectedScope
        setSidebarPresentation(.list, animated: true)
        reloadNotesForNavigation(selecting: url, loadFirstIfNeeded: false)
    }

    @objc
    func deleteLibraryTagMenuItemPressed(_ sender: NSMenuItem) {
        guard !tagMutationInProgress else { return }
        guard let tag = sender.representedObject as? String else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除 \(libraryDisplayTag(tag))？"
        alert.informativeText = "该标签会从所有笔记中移除，此操作无法撤销。"
        alert.addButton(withTitle: "删除标签")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do { drainBackgroundAutosaves(); try saveCurrentNoteIfNeeded() }
        catch { presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription); return }
        let noteStore = self.noteStore
        let roots = noteStore.preferredDirectories
        let extraURLs = externallyOpenedDocumentsByPath.keys.map { URL(fileURLWithPath: $0) }
        tagMutationInProgress = true
        updateEditorStatus("正在删除标签…")
        Task { [weak self] in
            defer { self?.tagMutationInProgress = false; self?.updateEditorStatus("") }
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try noteStore.deleteTag(tag, roots: roots, additionalNoteURLs: extraURLs)
                }.value
                guard let self else { return }
                removeSelectedMetadataTag(tag)
                if case .tag(let selectedTag) = selectedScope,
                   selectedTag.localizedCaseInsensitiveCompare(tag) == .orderedSame {
                    selectedScope = .all
                }
                invalidateSourceTagsForLibrary()
                forceFullLibrarySnapshotReload()
                scheduleDeferredSourceTagLoad()
            } catch {
                self?.presentErrorAlert(
                    message: "无法删除标签",
                    details: error.localizedDescription
                )
            }
        }
    }

    func makeFolderContextMenu(for folderURL: URL) -> NSMenu {
        let menu = NSMenu()

        let standardizedFolder = folderURL.standardizedFileURL
        let rootPaths = Set(Self.rootPreferredDirectories(from: noteStore.preferredDirectories).map(\.path))
        let isRoot = rootPaths.contains(standardizedFolder.path)
        let isDefaultRoot = standardizedFolder.path == noteStore.notesDirectory.standardizedFileURL.path
        let isExternalPreviewFolder = externalPreviewFolderURLs().contains {
            $0.standardizedFileURL.path == standardizedFolder.path
        }

        let listItem = NSMenuItem(
            title: "以列表显示",
            action: #selector(showFolderInListMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        listItem.target = self
        listItem.representedObject = standardizedFolder
        menu.addItem(listItem)
        menu.addItem(.separator())

        let revealItem = NSMenuItem(
            title: "在 Finder 中显示",
            action: #selector(revealLibraryFolderMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        revealItem.target = self
        revealItem.representedObject = standardizedFolder
        menu.addItem(revealItem)

        if isRoot {
            menu.addItem(.separator())
            let iconItem = NSMenuItem(title: "更改图标", action: nil, keyEquivalent: "")
            iconItem.submenu = makeFolderIconMenu(for: standardizedFolder)
            menu.addItem(iconItem)

            if !isDefaultRoot {
                menu.addItem(.separator())
                let removeItem = NSMenuItem(
                    title: "从资料库移除",
                    action: #selector(removeLibraryFolderMenuItemPressed(_:)),
                    keyEquivalent: ""
                )
                removeItem.target = self
                removeItem.representedObject = standardizedFolder
                menu.addItem(removeItem)
            }
            return menu
        }

        if isExternalPreviewFolder {
            return menu
        }

        menu.addItem(.separator())

        let renameItem = NSMenuItem(title: "重命名文件夹", action: #selector(renameFolderMenuItemPressed(_:)), keyEquivalent: "")
        renameItem.target = self
        renameItem.representedObject = folderURL
        menu.addItem(renameItem)

        let moveItem = NSMenuItem(title: "移动到文件夹", action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveFolderMenu(for: standardizedFolder)
        moveItem.isEnabled = moveItem.submenu?.items.contains(where: \.isEnabled) == true
        menu.addItem(moveItem)

        let deleteItem = NSMenuItem(title: "删除文件夹", action: #selector(deleteFolderMenuItemPressed(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = folderURL
        menu.addItem(deleteItem)

        return menu
    }

    @objc
    func showFolderInListMenuItemPressed(_ sender: NSMenuItem) {
        guard let folderURL = sender.representedObject as? URL else { return }
        lastListScope = .folder(folderURL.standardizedFileURL)
        setSidebarPresentation(.list, animated: true)
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
    }

    func makeFolderIconMenu(for folderURL: URL) -> NSMenu {
        let menu = NSMenu()
        let currentSymbolName = noteStore.libraryFolderIconName(for: folderURL)
        let defaultItem = NSMenuItem(
            title: "默认",
            action: #selector(changeFolderIconMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        defaultItem.target = self
        defaultItem.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: "默认图标")
        defaultItem.state = currentSymbolName == nil ? .on : .off
        defaultItem.representedObject = LibraryFolderIconRequest(folderURL: folderURL, symbolName: nil)
        menu.addItem(defaultItem)
        menu.addItem(.separator())

        for choice in LibraryFolderIconChoice.all {
            let item = NSMenuItem(
                title: choice.title,
                action: #selector(changeFolderIconMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.image = NSImage(systemSymbolName: choice.symbolName, accessibilityDescription: choice.title)
            item.state = currentSymbolName == choice.symbolName ? .on : .off
            item.representedObject = LibraryFolderIconRequest(
                folderURL: folderURL,
                symbolName: choice.symbolName
            )
            menu.addItem(item)
        }
        return menu
    }

    func makeMoveFolderMenuForLibrary(at folderURL: URL) -> NSMenu {
        makeMoveFolderMenu(for: folderURL.standardizedFileURL)
    }

    func makeMoveFolderMenu(for sourceFolder: URL) -> NSMenu {
        let menu = NSMenu()
        let source = sourceFolder.standardizedFileURL
        let currentParentPath = source.deletingLastPathComponent().standardizedFileURL.path

        for folderRow in sourceFolderTreeRows {
            let destination = folderRow.url.standardizedFileURL
            guard destination.path != source.path,
                  !destination.path.hasPrefix(source.path + "/") else {
                continue
            }
            let title = String(repeating: "  ", count: folderRow.depth) + folderTitle(for: destination)
            let item = NSMenuItem(
                title: title,
                action: #selector(moveFolderMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = LibraryFolderMoveRequest(
                source: source,
                destinationParent: destination
            )
            item.isEnabled = destination.path != currentParentPath
            menu.addItem(item)
        }
        return menu
    }

    func noteContextMenuForLibrary(row: Int) -> NSMenu? {
        guard let clickedNote = note(at: row) else { return nil }

        if !tableView.selectedRowIndexes.contains(row) {
            do {
                try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
                suppressSelectionChanges = true
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                suppressSelectionChanges = false
                load(note: clickedNote)
            } catch {
                suppressSelectionChanges = false
                presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
                return nil
            }
        }

        return makeNoteContextMenu()
    }

    func makeNoteContextMenu() -> NSMenu {
        let menu = NSMenu()
        let isTrashScope = selectedScope == .trash
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        if isTrashScope {
            addTrashNoteLifecycleItems(to: menu, selectionCount: selectionCount)
            menu.addItem(.separator())

            let revealItem = NSMenuItem(title: noteActionTitle(single: "在 Finder 中显示", multiple: "在 Finder 中显示 %d 个文件", count: selectionCount), action: #selector(revealSelectedNoteInFinderPressed), keyEquivalent: "")
            revealItem.target = self
            revealItem.isEnabled = canUseSelectedNote
            menu.addItem(revealItem)


            return menu
        }

        addPinNoteItem(to: menu, selectionCount: selectionCount)
        menu.addItem(.separator())

        let moveItem = NSMenuItem(title: noteActionTitle(single: "移到文件夹", multiple: "移动 %d 条笔记到文件夹", count: selectionCount), action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveNoteMenu()
        moveItem.isEnabled = canMoveSelectedNote
        menu.addItem(moveItem)
        menu.addItem(.separator())

        let revealItem = NSMenuItem(title: noteActionTitle(single: "在 Finder 中显示", multiple: "在 Finder 中显示 %d 个文件", count: selectionCount), action: #selector(revealSelectedNoteInFinderPressed), keyEquivalent: "")
        revealItem.target = self
        revealItem.isEnabled = canUseSelectedNote
        menu.addItem(revealItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(title: noteActionTitle(single: "删除", multiple: "删除 %d 条笔记", count: selectionCount), action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.isEnabled = canUseSelectedNote
        menu.addItem(deleteItem)

        return menu
    }

    func addTrashNoteLifecycleItems(to menu: NSMenu, selectionCount: Int) {
        let restoreItem = NSMenuItem(title: noteActionTitle(single: "恢复", multiple: "恢复 %d 条笔记", count: selectionCount), action: #selector(restoreSelectedNotePressed), keyEquivalent: "")
        restoreItem.target = self
        restoreItem.isEnabled = canRestoreSelectedNote
        menu.addItem(restoreItem)

        let permanentlyDeleteItem = NSMenuItem(title: noteActionTitle(single: "永久删除", multiple: "永久删除 %d 条笔记", count: selectionCount), action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
        permanentlyDeleteItem.target = self
        permanentlyDeleteItem.isEnabled = canUseSelectedNote
        menu.addItem(permanentlyDeleteItem)
    }

    func addPinNoteItem(to menu: NSMenu, selectionCount: Int) {
        let urls = selectedMarkdownFileURLsForLibrary()
        let allPinned = !urls.isEmpty && urls.allSatisfy { noteStore.isLibraryNotePinned(at: $0) }
        let title = allPinned
            ? noteActionTitle(single: "取消置顶", multiple: "取消置顶 %d 条笔记", count: selectionCount)
            : noteActionTitle(single: "置顶笔记", multiple: "置顶 %d 条笔记", count: selectionCount)
        let item = NSMenuItem(title: title, action: #selector(togglePinnedNotesPressed), keyEquivalent: "")
        item.target = self
        item.isEnabled = canUseSelectedNote && selectedScope != .trash
        menu.addItem(item)
    }

    func makeExportMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        let copyContentItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 内容", multiple: "复制 %d 条 Markdown 内容", count: selectionCount), action: #selector(copySelectedMarkdownContentPressed), keyEquivalent: "")
        copyContentItem.target = self
        copyContentItem.isEnabled = canExportSelectedNote
        menu.addItem(copyContentItem)

        let exportItem = NSMenuItem(title: noteActionTitle(single: "导出 Markdown...", multiple: "导出 %d 个 Markdown 文件...", count: selectionCount), action: #selector(exportSelectedMarkdownPressed), keyEquivalent: "")
        exportItem.target = self
        exportItem.isEnabled = canExportSelectedNote
        menu.addItem(exportItem)

        return menu
    }

    func makeNoteListActionsMenuForLibrary() -> NSMenu {
        let menu = NSMenu()

        let sortItem = NSMenuItem(title: "排序方式", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu()
        for (title, order) in [
            ("编辑日期", LibraryNoteSortOrder.dateEdited),
            ("创建日期", .dateCreated),
            ("标题", .title)
        ] {
            let item = NSMenuItem(
                title: title,
                action: #selector(noteListSortMenuItemPressed(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = order.rawValue
            item.state = noteListSortOrder == order ? .on : .off
            sortMenu.addItem(item)
        }
        sortItem.submenu = sortMenu
        menu.addItem(sortItem)

        let groupingItem = NSMenuItem(
            title: "按日期分组",
            action: #selector(noteListGroupingMenuItemPressed(_:)),
            keyEquivalent: ""
        )
        groupingItem.target = self
        groupingItem.state = groupsNoteListByDate ? .on : .off
        menu.addItem(groupingItem)

        return menu
    }

    @objc
    func noteListGroupingMenuItemPressed(_ sender: NSMenuItem) {
        setNoteListGroupingForLibrary(!groupsNoteListByDate)
    }

    func setNoteListGroupingForLibrary(_ groupsByDate: Bool) {
        guard groupsNoteListByDate != groupsByDate else { return }
        groupsNoteListByDate = groupsByDate
        noteStore.libraryGroupsNotesByDate = groupsNoteListByDate
        rebuildNoteListRowsForDisplayOptions()
    }

    @objc
    func noteListSortMenuItemPressed(_ sender: NSMenuItem) {
        guard let order = LibraryNoteSortOrder(rawValue: sender.tag) else { return }
        setNoteListSortOrderForLibrary(order)
    }

    func setNoteListSortOrderForLibrary(_ order: LibraryNoteSortOrder) {
        guard order != noteListSortOrder else { return }
        noteListSortOrder = order
        noteStore.libraryNoteSortOrderRawValue = order.rawValue
        rebuildNoteListRowsForDisplayOptions()
    }

    func makeMoreActionsMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let isTrashScope = selectedScope == .trash
        let selectionCount = selectedMarkdownFileURLsForLibrary().count

        let openItem = NSMenuItem(title: "独立窗口打开", action: #selector(openSelectedInSeparateWindow), keyEquivalent: "")
        openItem.target = self
        openItem.isEnabled = canUseSingleSelectedNote
        menu.addItem(openItem)

        if !isTrashScope {
            addPinNoteItem(to: menu, selectionCount: selectionCount)
        }

        let moveItem = NSMenuItem(title: noteActionTitle(single: "移到文件夹", multiple: "移动 %d 条笔记到文件夹", count: selectionCount), action: nil, keyEquivalent: "")
        moveItem.submenu = makeMoveNoteMenu()
        moveItem.isEnabled = canMoveSelectedNote
        menu.addItem(moveItem)

        let saveItem = NSMenuItem(title: "保存", action: #selector(savePressed), keyEquivalent: "s")
        saveItem.target = self
        saveItem.keyEquivalentModifierMask = [.command]
        saveItem.isEnabled = canEditCurrentDocument
        menu.addItem(saveItem)

        menu.addItem(.separator())

        let revealItem = NSMenuItem(title: noteActionTitle(single: "在 Finder 中显示", multiple: "在 Finder 中显示 %d 个文件", count: selectionCount), action: #selector(revealSelectedNoteInFinderPressed), keyEquivalent: "")
        revealItem.target = self
        revealItem.isEnabled = canUseSelectedNote
        menu.addItem(revealItem)

        let copyPathItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 路径", multiple: "复制 %d 个 Markdown 路径", count: selectionCount), action: #selector(copySelectedMarkdownPathPressed), keyEquivalent: "")
        copyPathItem.target = self
        copyPathItem.isEnabled = canUseSelectedNote
        menu.addItem(copyPathItem)

        let copyContentItem = NSMenuItem(title: noteActionTitle(single: "复制 Markdown 内容", multiple: "复制 %d 条 Markdown 内容", count: selectionCount), action: #selector(copySelectedMarkdownContentPressed), keyEquivalent: "")
        copyContentItem.target = self
        copyContentItem.isEnabled = canExportSelectedNote
        menu.addItem(copyContentItem)

        let exportItem = NSMenuItem(title: noteActionTitle(single: "导出 Markdown...", multiple: "导出 %d 个 Markdown 文件...", count: selectionCount), action: #selector(exportSelectedMarkdownPressed), keyEquivalent: "")
        exportItem.target = self
        exportItem.isEnabled = canExportSelectedNote
        menu.addItem(exportItem)

        menu.addItem(.separator())

        let manageAttachmentsItem = NSMenuItem(
            title: "管理附件…",
            action: #selector(manageAttachmentsPressed),
            keyEquivalent: ""
        )
        manageAttachmentsItem.target = self
        menu.addItem(manageAttachmentsItem)

        menu.addItem(.separator())

        if isTrashScope {
            addTrashNoteLifecycleItems(to: menu, selectionCount: selectionCount)
        } else {
            let deleteItem = NSMenuItem(title: noteActionTitle(single: "删除", multiple: "删除 %d 条笔记", count: selectionCount), action: #selector(deleteSelectedNotePressed), keyEquivalent: "")
            deleteItem.target = self
            deleteItem.isEnabled = canUseSelectedNote
            menu.addItem(deleteItem)
        }

        return menu
    }

    func noteActionTitle(single: String, multiple: String, count: Int) -> String {
        count > 1 ? String(format: multiple, count) : single
    }

    func makeFormatMenuForLibrary() -> NSMenu {
        let menu = NSMenu()
        let groups: [[(String, LibraryFormatCommand, String, NSEvent.ModifierFlags)]] = [
            [
                ("标题", .heading1, "1", [.command, .option]),
                ("副标题", .heading2, "2", [.command, .option]),
                ("小标题", .heading3, "3", [.command, .option]),
                ("正文", .paragraph, "0", [.command, .option])
            ],
            [
                ("加粗", .bold, "b", [.command]),
                ("斜体", .italic, "i", [.command]),
                ("下划线", .underline, "u", [.command]),
                ("删除线", .strikethrough, "x", [.command, .shift])
            ],
            [
                ("待办列表", .checklist, "9", [.command, .shift]),
                ("项目符号列表", .bullet, "8", [.command, .shift]),
                ("编号列表", .ordered, "7", [.command, .shift])
            ]
        ]

        for (groupIndex, items) in groups.enumerated() {
            if groupIndex > 0 {
                menu.addItem(.separator())
            }
            for (title, command, keyEquivalent, modifiers) in items {
                let item = NSMenuItem(title: title, action: #selector(formatMenuItemPressed(_:)), keyEquivalent: keyEquivalent)
                item.target = self
                item.tag = command.rawValue
                item.keyEquivalentModifierMask = modifiers
                item.state = isFormatCommandActive(command) ? .on : .off
                menu.addItem(item)
            }
        }

        return menu
    }

    func makeSelectionFormattingMenuForLibrary() -> NSMenu? {
        guard canEditCurrentDocument,
              !isEditorShowingMarkdownSource,
              editorTextView.selectedRange().length > 0 else { return nil }

        let menu = NSMenu(title: "快捷格式")
        let enabled = noteStore.enabledSelectionToolbarOptions
        let inlineCommands: [(SelectionToolbarOption, String, String, LibraryFormatCommand)] = [
            (.bold, "加粗", "bold", .bold),
            (.italic, "斜体", "italic", .italic)
        ]
        for (option, title, symbolName, command) in inlineCommands where enabled.contains(option) {
            let item = NSMenuItem(title: title, action: #selector(formatMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.tag = command.rawValue
            item.state = isFormatCommandActive(command) ? .on : .off
            item.image = selectionMenuImage(symbolName: symbolName, title: title)
            menu.addItem(item)
        }

        if enabled.contains(.highlight) {
            let isHighlighted = isFormatCommandActive(.highlight)
            let highlightItem = NSMenuItem(title: "高亮", action: #selector(formatMenuItemPressed(_:)), keyEquivalent: "")
            highlightItem.target = self
            highlightItem.tag = (isHighlighted ? LibraryFormatCommand.removeHighlight : .highlight).rawValue
            highlightItem.state = isHighlighted ? .on : .off
            highlightItem.image = selectionMenuImage(symbolName: "highlighter", title: "高亮")
            menu.addItem(highlightItem)
        }

        if enabled.contains(.link) {
            let linkItem = NSMenuItem(title: "添加链接", action: #selector(linkPressed), keyEquivalent: "")
            linkItem.target = self
            linkItem.image = selectionMenuImage(symbolName: "link", title: "添加链接")
            menu.addItem(linkItem)
        }

        let conversionOptions: Set<SelectionToolbarOption> = [.conversion, .checklist, .bulletList, .orderedList]
        if !enabled.isDisjoint(with: conversionOptions) {
            let conversionItem = NSMenuItem(title: "转换为", action: nil, keyEquivalent: "")
            conversionItem.image = selectionMenuTextImage("Aa", title: "转换为")
            let conversionMenu = NSMenu(title: "转换为")
            let conversionCommands: [(SelectionToolbarOption, String, String, LibraryFormatCommand)] = [
                (.conversion, "正文", "textformat", .paragraph),
                (.conversion, "标题", "textformat.size.larger", .heading1),
                (.conversion, "副标题", "textformat.size", .heading2),
                (.conversion, "小标题", "textformat.size.smaller", .heading3),
                (.bulletList, "项目符号列表", "list.bullet", .bullet),
                (.orderedList, "编号列表", "list.number", .ordered),
                (.checklist, "待办列表", "checkmark.square", .checklist)
            ]
            for (option, title, symbolName, command) in conversionCommands where enabled.contains(option) {
                let item = NSMenuItem(title: title, action: #selector(formatMenuItemPressed(_:)), keyEquivalent: "")
                item.target = self
                item.tag = command.rawValue
                item.state = isFormatCommandActive(command) ? .on : .off
                item.image = selectionMenuImage(symbolName: symbolName, title: title)
                conversionMenu.addItem(item)
            }
            conversionItem.submenu = conversionMenu
            menu.insertItem(conversionItem, at: 0)
        }
        return menu
    }

    func configureEditorInsertContextMenu(_ menu: NSMenu) {
        let enabled = noteStore.enabledEditorContextMenuOptions
        let commands: [(EditorContextMenuOption, String, String, Selector)] = [
            (.insertTable, "表格", "tablecells", #selector(tablePressed)),
            (.insertLink, "链接…", "link", #selector(linkPressed)),
            (.insertAttachment, "附件…", "paperclip", #selector(attachmentPressed))
        ]
        let visibleCommands = commands.filter { enabled.contains($0.0) }
        guard !visibleCommands.isEmpty else { return }
        let insertItem = NSMenuItem(title: "插入", action: nil, keyEquivalent: "")
        insertItem.image = selectionMenuImage(symbolName: "plus", title: "插入")
        insertItem.isEnabled = canEditCurrentDocument && !isEditorShowingMarkdownSource
        let insertMenu = NSMenu(title: "插入")
        for (_, title, symbolName, action) in visibleCommands {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = selectionMenuImage(symbolName: symbolName, title: title)
            item.isEnabled = insertItem.isEnabled
            insertMenu.addItem(item)
        }
        insertItem.submenu = insertMenu
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        menu.insertItem(insertItem, at: 0)
    }

    func selectionMenuImage(symbolName: String, title: String) -> NSImage? {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
    }

    func selectionMenuTextImage(_ text: String, title: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 16))
        image.lockFocus()
        (text as NSString).draw(at: NSPoint(x: 0, y: 0), withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ])
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = title
        return image
    }

    func isFormatCommandActive(_ command: LibraryFormatCommand) -> Bool {
        if let targetKind = command.paragraphKind,
           let storage = editorTextView.textStorage {
            let kinds = selectedLineRanges().map {
                MarkdownRichTextCodec.paragraphKind(at: $0, in: storage)
            }
            return !kinds.isEmpty && kinds.allSatisfy { sameParagraphCategory($0, targetKind) }
        }

        let attributes: [NSAttributedString.Key: Any]
        if let storage = editorTextView.textStorage, storage.length > 0 {
            let location = min(editorTextView.selectedRange().location, storage.length - 1)
            attributes = storage.attributes(at: location, effectiveRange: nil)
        } else {
            attributes = editorTextView.typingAttributes
        }
        switch command {
        case .bold:
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            return NSFontManager.shared.traits(of: font).contains(.boldFontMask)
        case .italic:
            let font = (attributes[.font] as? NSFont) ?? theme.bodyFont
            return isItalicActive(font: font, obliqueness: attributes[.obliqueness])
        case .underline:
            return (attributes[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue
        case .strikethrough:
            return (attributes[.strikethroughStyle] as? Int) == NSUnderlineStyle.single.rawValue
        case .highlight:
            return (attributes[.qmHighlight] as? Bool) == true
        case .removeHighlight:
            return (attributes[.qmHighlight] as? Bool) != true
        default:
            return false
        }
    }

    func makeMoveNoteMenu() -> NSMenu {
        let menu = NSMenu()
        for folderRow in sourceFolderRows {
            let folderURL = folderRow.url
            let title = String(repeating: "  ", count: folderRow.depth) + folderTitle(for: folderURL)
            let item = NSMenuItem(title: title, action: #selector(moveNoteMenuItemPressed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = folderURL
            item.isEnabled = true
            menu.addItem(item)
        }
        return menu
    }

    @discardableResult
    func configureLinkContextMenuForLibrary(_ menu: NSMenu, for link: MarkdownLinkReference) -> Bool {
        let openItem = NSMenuItem(title: "打开链接", action: #selector(openLinkMenuItemPressed(_:)), keyEquivalent: "")
        openItem.target = self
        openItem.representedObject = link
        openItem.isEnabled = markdownLinkDestination(link.url, relativeTo: selectedURL) != nil

        let editItem = NSMenuItem(title: "编辑链接...", action: #selector(editLinkMenuItemPressed(_:)), keyEquivalent: "")
        editItem.target = self
        editItem.representedObject = link
        editItem.isEnabled = canEditCurrentDocument

        let copyItem = NSMenuItem(title: "复制链接", action: #selector(copyLinkMenuItemPressed(_:)), keyEquivalent: "")
        copyItem.target = self
        copyItem.representedObject = link

        let removeItem = NSMenuItem(title: "移除链接", action: #selector(removeLinkMenuItemPressed(_:)), keyEquivalent: "")
        removeItem.target = self
        removeItem.representedObject = link
        removeItem.isEnabled = canEditCurrentDocument

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [openItem, editItem, copyItem, removeItem].reversed() {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    func openLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        _ = openMarkdownLinkForLibrary(link)
    }

    @objc
    func editLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        presentLinkEditorForLibrary(
            title: "编辑链接",
            destination: link.url,
            name: link.label
        ) { [weak self] destination, name in
            self?.updateLinkForLibrary(
                link,
                label: name.isEmpty ? destination : name,
                url: destination
            )
        }
    }

    @objc
    func copyLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url, forType: .string)
    }

    @objc
    func removeLinkMenuItemPressed(_ sender: NSMenuItem) {
        guard let link = sender.representedObject as? MarkdownLinkReference else { return }
        updateLinkForLibrary(link, url: nil)
    }

    @discardableResult
    func openMarkdownLinkForLibrary(_ link: MarkdownLinkReference) -> Bool {
        guard let destination = markdownLinkDestination(link.url, relativeTo: selectedURL) else {
            return false
        }
        switch destination {
        case .localMarkdown(let url):
            do {
                try openMarkdownDocumentForLibrary(at: url)
            } catch {
                presentErrorAlert(message: "无法打开 Markdown 文件", details: error.localizedDescription)
                return false
            }
        case .external(let url):
            NSWorkspace.shared.open(url)
        }
        return true
    }

    func updateLinkForLibrary(_ link: MarkdownLinkReference, label: String? = nil, url: String?) {
        guard canEditCurrentDocument,
              let storage = editorTextView.textStorage,
              link.range.location >= 0,
              NSMaxRange(link.range) <= storage.length,
              storage.attribute(.qmLinkURL, at: link.range.location, effectiveRange: nil) != nil else {
            return
        }

        suppressEditorChanges = true
        storage.beginEditing()
        if let url {
            if let label {
                storage.replaceCharacters(in: link.range, with: label)
            }
            let updatedRange = NSRange(location: link.range.location, length: (label ?? link.label).utf16.count)
            storage.removeAttribute(.qmAutomaticLink, range: updatedRange)
            storage.addAttribute(.qmLinkURL, value: url, range: updatedRange)
            storage.addAttribute(.foregroundColor, value: theme.accentColor, range: updatedRange)
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: updatedRange)
        } else {
            storage.removeAttribute(.qmAutomaticLink, range: link.range)
            storage.removeAttribute(.qmLinkURL, range: link.range)
            storage.removeAttribute(.underlineStyle, range: link.range)
            storage.addAttribute(.foregroundColor, value: theme.textColor, range: link.range)
        }
        storage.endEditing()
        suppressEditorChanges = false

        let selectedLength = url == nil ? link.range.length : (label ?? link.label).utf16.count
        editorTextView.setSelectedRange(NSRange(location: link.range.location, length: selectedLength))
        updateTypingAttributesFromInsertionPoint()
        markDirty()
    }

    func presentLinkEditorForLibrary(
        title: String,
        destination: String,
        name: String,
        onSubmit: @escaping (String, String) -> Void
    ) {
        guard linkEditorSheetController == nil, let window else { return }
        editorTextView.dismissSelectionFormattingPanel()
        let controller = LinkEditorSheetController(
            title: title,
            destination: destination,
            name: name,
            onSubmit: onSubmit,
            onDismiss: { [weak self] in
                self?.linkEditorSheetController = nil
                self?.focusEditorForLibraryAction()
            }
        )
        linkEditorSheetController = controller
        controller.beginSheet(for: window)
    }

    @discardableResult
    func configureMarkdownTableContextMenuForLibrary(_ menu: NSMenu, atCharacterIndex characterIndex: Int) -> Bool {
        guard canEditCurrentDocument else {
            return false
        }

        guard let string = editorTextView.textStorage?.mutableString else {
            return false
        }
        let richLocation = richMarkdownTableLocation(atCharacterIndex: characterIndex)
        let plainLocation = markdownTableLocation(atCharacterIndex: characterIndex, in: string)
        guard richLocation != nil || plainLocation != nil else {
            return false
        }
        let columnCount = richLocation?.snapshot.columnCount ?? plainLocation?.columnCount ?? 0
        let isDataRow = richLocation.map { $0.row > 0 } ?? isMarkdownTableDataRow(atCharacterIndex: characterIndex)

        let insertRowItem = NSMenuItem(title: "插入表格行", action: #selector(insertMarkdownTableRowMenuItemPressed(_:)), keyEquivalent: "")
        insertRowItem.target = self
        insertRowItem.representedObject = characterIndex

        let insertColumnItem = NSMenuItem(title: "插入右侧列", action: #selector(insertMarkdownTableColumnMenuItemPressed(_:)), keyEquivalent: "")
        insertColumnItem.target = self
        insertColumnItem.representedObject = characterIndex

        let deleteRowItem = NSMenuItem(title: "删除表格行", action: #selector(deleteMarkdownTableRowMenuItemPressed(_:)), keyEquivalent: "")
        deleteRowItem.target = self
        deleteRowItem.representedObject = characterIndex
        deleteRowItem.keyEquivalent = "\u{7F}"
        deleteRowItem.keyEquivalentModifierMask = [.command]
        deleteRowItem.isEnabled = isDataRow

        let deleteColumnItem = NSMenuItem(title: "删除表格列", action: #selector(deleteMarkdownTableColumnMenuItemPressed(_:)), keyEquivalent: "")
        deleteColumnItem.target = self
        deleteColumnItem.representedObject = characterIndex
        deleteColumnItem.isEnabled = columnCount > 2

        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in [insertRowItem, insertColumnItem, deleteRowItem, deleteColumnItem].reversed() {
            menu.insertItem(item, at: 0)
        }
        return true
    }

    @objc
    func insertMarkdownTableRowMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        moveEditorSelection(to: characterIndex)
        insertTableForLibrary()
    }

    @objc
    func deleteMarkdownTableRowMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        moveEditorSelection(to: characterIndex)
        deleteCurrentMarkdownTableRowForLibrary()
    }

    @objc
    func insertMarkdownTableColumnMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        insertMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex)
    }

    @objc
    func deleteMarkdownTableColumnMenuItemPressed(_ sender: NSMenuItem) {
        guard let characterIndex = sender.representedObject as? Int else { return }
        deleteMarkdownTableColumnForLibrary(atCharacterIndex: characterIndex)
    }

    func confirmDestructiveAction(title: String, message: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func presentErrorAlert(message: String, details: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = details
        alert.runModal()
    }

    func updatePanelOpacity(_ opacity: Double) {
        window?.alphaValue = 1
    }
}
