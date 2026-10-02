import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard outlineView === sourceOutlineView else { return 0 }
        if let item = item as? LibrarySourceOutlineItem {
            return item.children.count
        }
        return sourceOutlineRootItems.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let item = item as? LibrarySourceOutlineItem {
            return item.children[index]
        }
        return sourceOutlineRootItems[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return false }
        return !item.children.isEmpty
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return nil }

        switch item.kind {
        case .group(let title, let section):
            // The folder group's heading lives in the fixed shared header.
            if section == .folders { return NSView() }
            let identifier: NSUserInterfaceItemIdentifier
            if section == .tags {
                identifier = NSUserInterfaceItemIdentifier("LibrarySourceGroup-Tags")
            } else if section == .folders {
                identifier = NSUserInterfaceItemIdentifier("LibrarySourceGroup-Files")
            } else {
                identifier = NSUserInterfaceItemIdentifier("LibrarySourceGroup-Mudsnote")
            }
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
                ?? NSTableCellView()
            cell.identifier = identifier
            let label = cell.textField ?? NSTextField(labelWithString: "")
            if label.superview == nil {
                cell.textField = label
                cell.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                let leading = label.leadingAnchor.constraint(
                    equalTo: cell.leadingAnchor,
                    constant: LibraryNotesLayout.sourceGroupContentLeadingInset
                        + (section == .tags ? 0 : 4)
                )
                NSLayoutConstraint.activate([
                    leading,
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: section == .tags ? -56 : -6),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            if section == .tags, !cell.subviews.contains(where: { $0.identifier?.rawValue == "CreateLibraryTagButton" }) {
                let add = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "添加标签")!,
                                   target: self, action: #selector(addSelectedNoteTagPressed))
                add.identifier = NSUserInterfaceItemIdentifier("CreateLibraryTagButton")
                add.isBordered = false
                add.toolTip = "为当前笔记添加标签"
                add.setAccessibilityLabel("添加标签")
                add.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(add)
                let manage = NSButton(image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "管理标签")!,
                                      target: self, action: #selector(manageLibraryTagsPressed(_:)))
                manage.isBordered = false
                manage.identifier = NSUserInterfaceItemIdentifier("ManageLibraryTagsButton")
                manage.toolTip = "管理标签"
                manage.setAccessibilityLabel("管理标签")
                manage.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(manage)
                NSLayoutConstraint.activate([
                    manage.trailingAnchor.constraint(equalTo: add.leadingAnchor, constant: -4),
                    manage.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    manage.widthAnchor.constraint(equalToConstant: 20),
                    manage.heightAnchor.constraint(equalToConstant: 20)
                ])
                NSLayoutConstraint.activate([
                    add.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    add.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    add.widthAnchor.constraint(equalToConstant: 20),
                    add.heightAnchor.constraint(equalToConstant: 20)
                ])
            }
            label.stringValue = title
            label.identifier = identifier
            label.font = .systemFont(ofSize: LibraryNotesLayout.sourceGroupFontSize, weight: .medium)
            label.textColor = panelTertiaryTextColor()
            return cell
        case .status(let message):
            let identifier = NSUserInterfaceItemIdentifier("LibrarySourceStatusCell")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
                ?? NSTableCellView()
            cell.identifier = identifier
            let label = cell.textField ?? NSTextField(labelWithString: "")
            if label.superview == nil {
                cell.textField = label
                cell.addSubview(label)
                label.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 18),
                    label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                    label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            label.identifier = NSUserInterfaceItemIdentifier(
                item.identifier.contains("folders") ? "LibrarySourceFolderStatus" : "LibrarySourceTagStatus"
            )
            label.stringValue = message
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = panelTertiaryTextColor().withAlphaComponent(0.82)
            return cell
        case .inlineFolderEdit(let operation):
            return makeSourceOutlineInlineEditCell(for: operation, item: item)
        case .scope:
            let identifier = NSUserInterfaceItemIdentifier("LibrarySourceOutlineCell")
            let cell: LibrarySourceOutlineCellView
            if let reused = outlineView.makeView(withIdentifier: identifier, owner: nil)
                as? LibrarySourceOutlineCellView {
                cell = reused
            } else {
                cell = LibrarySourceOutlineCellView()
                cell.identifier = identifier
            }
            configureSourceOutlineCell(cell, for: item)
            return cell
        case .note(let note):
            return makeSourceOutlineNoteCell(for: note, item: item)
        }
    }

    func makeSourceOutlineNoteCell(
        for note: NoteSearchResult,
        item: LibrarySourceOutlineItem
    ) -> NSView {
        let identifier = NSUserInterfaceItemIdentifier("LibrarySourceNoteCell")
        let cell = (sourceOutlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView)
            ?? NSTableCellView()
        cell.identifier = identifier
        let icon = cell.imageView ?? NSImageView()
        let label = cell.textField ?? NSTextField(labelWithString: "")
        if label.superview == nil {
            cell.imageView = icon
            cell.textField = label
            cell.addSubview(icon)
            cell.addSubview(label)
            icon.translatesAutoresizingMaskIntoConstraints = false
            label.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 18),
                icon.heightAnchor.constraint(equalToConstant: 18),
                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 5),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        label.stringValue = note.title.isEmpty
            ? note.url.deletingPathExtension().lastPathComponent
            : note.title
        label.font = .systemFont(ofSize: LibraryNotesLayout.sourceButtonFontSize, weight: .regular)
        label.textColor = LibrarySourceSelectionPalette.unselectedForegroundColor
        label.lineBreakMode = .byTruncatingMiddle
        let isSelected = sourceOutlineView.row(forItem: item) == sourceOutlineView.selectedRow
        let foregroundColor = isSelected
            ? selectedThemeColor.foregroundColor
            : LibrarySourceSelectionPalette.unselectedForegroundColor
        let configuration = NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.sourceSymbolPointSize,
            weight: LibraryNotesLayout.sourceSymbolWeight
        ).applying(NSImage.SymbolConfiguration(paletteColors: [foregroundColor]))
        let noteImage = NSImage(
            systemSymbolName: "doc.text",
            accessibilityDescription: "笔记"
        )?.withSymbolConfiguration(configuration)
        noteImage?.isTemplate = false
        icon.identifier = NSUserInterfaceItemIdentifier("LibrarySourceNoteIcon")
        icon.image = noteImage
        icon.contentTintColor = nil
        cell.setAccessibilityLabel(label.stringValue)
        cell.setAccessibilityValue("笔记")
        return cell
    }

    func configureSourceOutlineCell(
        _ cell: LibrarySourceOutlineCellView,
        for item: LibrarySourceOutlineItem
    ) {
        guard let scope = item.scope else { return }
        let themeColor = selectedThemeColor
        let title = sourceTitle(for: scope)
        let row = sourceOutlineView.row(forItem: item)
        let isSelected = isSourceOutlineItemVisuallySelected(item)
        let legacyTag = sourceLegacyTag(for: scope)
        cell.identifier = NSUserInterfaceItemIdentifier("LibrarySourceRow-\(legacyTag)")
        cell.textField?.identifier = NSUserInterfaceItemIdentifier("LibrarySourceLabel-\(legacyTag)")
        cell.countLabel.identifier = NSUserInterfaceItemIdentifier("LibrarySourceCount-\(legacyTag)")
        cell.textField?.stringValue = title
        cell.textField?.font = .systemFont(
            ofSize: LibraryNotesLayout.sourceButtonFontSize,
            weight: isSelected
                ? LibraryNotesLayout.sourceSelectedButtonFontWeight
                : LibraryNotesLayout.sourceUnselectedButtonFontWeight
        )
        cell.textField?.textColor = isSelected
            ? themeColor.foregroundColor
            : LibrarySourceSelectionPalette.unselectedForegroundColor
        let foregroundColor = isSelected
            ? themeColor.foregroundColor
            : LibrarySourceSelectionPalette.unselectedForegroundColor
        let sourceImageConfiguration = NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.sourceSymbolPointSize,
            weight: LibraryNotesLayout.sourceSymbolWeight
        ).applying(NSImage.SymbolConfiguration(paletteColors: [foregroundColor]))
        let sourceImage = NSImage(
            systemSymbolName: sourceSymbolName(for: scope),
            accessibilityDescription: title
        )?.withSymbolConfiguration(sourceImageConfiguration)
        sourceImage?.isTemplate = false
        cell.imageView?.image = sourceImage
        cell.imageView?.contentTintColor = nil
        cell.imageView?.needsDisplay = true
        cell.needsDisplay = true
        cell.countLabel.stringValue = sourceCountText(item.count, for: scope)
        cell.countLabel.textColor = isSelected
            ? LibrarySourceSelectionPalette.selectedCountColor
            : panelTertiaryTextColor()
        (sourceOutlineView.rowView(
            atRow: row,
            makeIfNecessary: false
        ) as? LibrarySourceOutlineRowView)?.setVisuallySelected(isSelected)
        cell.accessibilityPressHandler = { [weak self] in
            self?.activateSourceScope(scope) ?? false
        }
        cell.setAccessibilityLabel(title)
        cell.setAccessibilityValue(
            item.count.map { "\($0) 条笔记" } ?? "正在载入笔记数量"
        )
    }

    func isSourceOutlineItemVisuallySelected(_ item: LibrarySourceOutlineItem) -> Bool {
        guard let scope = item.scope else { return false }
        if sourceOutlineView.isDeferringPrimaryMouseSelectionCommit {
            return selectedScope == scope
        }
        let row = sourceOutlineView.row(forItem: item)
        let visualSelectionRow = sourceOutlineView.primaryMouseVisualSelectionRow
            ?? sourceOutlineView.selectedRow
        return row >= 0 ? row == visualSelectionRow : selectedScope == scope
    }

    var selectedThemeColor: MudsnoteThemeColor {
        MudsnoteThemeColor(identifier: noteStore.themeColorIdentifier)
    }

    func sourceSymbolName(for scope: LibraryScope) -> String {
        guard case .folder(let folderURL) = scope,
              sourceFolderTreeRows.first(where: {
                  $0.url.standardizedFileURL.path == folderURL.standardizedFileURL.path
              })?.depth == 0 else {
            return scope.symbolName
        }
        return noteStore.libraryFolderIconName(for: folderURL) ?? "folder.fill"
    }

    func sourceLegacyTag(for scope: LibraryScope) -> Int {
        switch scope {
        case .all:
            return 0
        case .recent:
            return 1
        case .favorites:
            return 4
        case .inbox:
            return 2
        case .trash:
            return 3
        case .folder(let folderURL):
            let folderPath = folderURL.standardizedFileURL.path
            return 10 + (sourceFolderTreeRows.firstIndex {
                $0.url.standardizedFileURL.path == folderPath
            } ?? 0)
        case .tag(let tag):
            return 100 + (sourceTagNames.firstIndex {
                $0.localizedCaseInsensitiveCompare(tag) == .orderedSame
            } ?? 0)
        }
    }

    func makeSourceOutlineInlineEditCell(
        for operation: InlineFolderEditOperation,
        item: LibrarySourceOutlineItem
    ) -> NSView {
        let cell = NSTableCellView()
        cell.identifier = NSUserInterfaceItemIdentifier("LibraryInlineFolderEditRow")

        let icon = NSImageView(image: NSImage(
            systemSymbolName: "folder",
            accessibilityDescription: "文件夹"
        ) ?? NSImage())
        icon.contentTintColor = LibrarySourceSelectionPalette.unselectedForegroundColor
        icon.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.sourceSymbolPointSize,
            weight: LibraryNotesLayout.sourceSymbolWeight
        )
        icon.translatesAutoresizingMaskIntoConstraints = false

        let field = NSTextField(string: operation.initialName)
        field.identifier = NSUserInterfaceItemIdentifier("LibraryInlineFolderEditField")
        field.delegate = self
        field.font = .systemFont(
            ofSize: LibraryNotesLayout.sourceButtonFontSize,
            weight: LibraryNotesLayout.sourceUnselectedButtonFontWeight
        )
        field.textColor = LibrarySourceSelectionPalette.unselectedForegroundColor
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBezeled = false
        field.isBordered = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(icon)
        cell.addSubview(field)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(
                equalTo: cell.leadingAnchor,
                constant: LibraryNotesLayout.sourceCellContentLeadingInset
            ),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceIconWidth),
            icon.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.sourceIconHeight),
            field.leadingAnchor.constraint(
                equalTo: icon.trailingAnchor,
                constant: LibraryNotesLayout.sourceIconTitleSpacing
            ),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 20)
        ])
        inlineFolderEditField = field
        return cell
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let item = item as? LibrarySourceOutlineItem else { return false }
        if case .group = item.kind { return true }
        return false
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return false }
        switch item.kind {
        case .group:
            return false
        case .scope, .note:
            return true
        case .status, .inlineFolderEdit:
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let item = item as? LibrarySourceOutlineItem else {
            return LibraryNotesLayout.sourceRowHeight
        }
        switch item.kind {
        case .group(_, let section):
            if section == .folders { return 1 }
            return LibraryNotesLayout.sourceSectionHeaderHeight
        case .status:
            return LibraryNotesLayout.sourceStatusRowHeight
        case .scope, .note, .inlineFolderEdit:
            return LibraryNotesLayout.sourceRowHeight
        }
    }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        guard let item = item as? LibrarySourceOutlineItem else { return nil }
        switch item.kind {
        case .scope, .note:
            let row = LibrarySourceOutlineRowView()
            let itemRow = sourceOutlineView.row(forItem: item)
            row.setVisuallySelected(
                item.note != nil
                    ? itemRow == sourceOutlineView.selectedRow
                    : isSourceOutlineItemVisuallySelected(item)
            )
            return row
        case .group, .status, .inlineFolderEdit:
            let row = NSTableRowView()
            row.selectionHighlightStyle = .none
            return row
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSOutlineView === sourceOutlineView,
              !isSynchronizingSourceOutlineSelection else { return }
        if sourceOutlineView.isDeferringPrimaryMouseSelectionCommit {
            refreshVisibleSourceOutlinePresentation()
            sourceOutlineView.window?.displayIfNeeded()
            return
        }
        commitCurrentSourceOutlineSelection()
    }

    func commitCurrentSourceOutlineSelection() {
        guard sourceOutlineView.selectedRow >= 0,
              let item = sourceOutlineView.item(atRow: sourceOutlineView.selectedRow)
                as? LibrarySourceOutlineItem else { return }
        refreshVisibleSourceOutlinePresentation()
        if let note = item.note {
            selectedTreeNoteURL = note.url
            do {
                try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
                load(note: note)
            } catch {
                presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            }
            return
        }
        guard let scope = item.scope else { return }
        selectedTreeNoteURL = nil
        if scope == .recent || scope == .favorites {
            if !activateSourceScope(scope) {
                refreshSourceSelection()
            }
            return
        }
        if sidebarPresentation == .tree {
            selectedScope = scope
            lastTreeScope = scope
            if scope == .all {
                rebuildSourceRows(includeTags: sourceTagsLoaded)
            }
            reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
            refreshVisibleSourceOutlinePresentation()
        } else if !activateSourceScope(scope) {
            refreshSourceSelection()
        }
    }

    @discardableResult
    func activateSourceScope(_ scope: LibraryScope) -> Bool {
        do {
            try saveCurrentNoteIfNeeded(allowBackgroundHandoff: true)
            selectedScope = scope
            lastTreeScope = scope
            lastListScope = scope
            if scope == .recent || scope == .favorites || scope == .all {
                // List navigation does not need to recreate the hidden folder tree.
                sourceTreeNeedsScopeRebuild = true
                if scope == .all, isShowingSidebarTree {
                    rebuildSourceRows(includeTags: sourceTagsLoaded)
                }
            }
            reloadNotesForNavigation(loadFirstIfNeeded: true)
            if (scope == .recent || scope == .favorites), sidebarPresentation != .list {
                sidebarPresentation = .list
                noteStore.librarySidebarPresentationRawValue = LibrarySidebarPresentation.list.rawValue
                applySidebarPresentation(
                    animated: window?.isVisible == true
                        && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                )
            }
            refreshVisibleSourceOutlinePresentation()
            return true
        } catch {
            presentErrorAlert(message: "无法保存当前笔记", details: error.localizedDescription)
            return false
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        updateSourceFolderExpansion(from: notification, isExpanded: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        updateSourceFolderExpansion(from: notification, isExpanded: false)
    }

    func updateSourceFolderExpansion(from notification: Notification, isExpanded: Bool) {
        guard !isRestoringSourceOutlineExpansion,
              notification.object as? NSOutlineView === sourceOutlineView,
              let item = notification.userInfo?["NSObject"]
                as? LibrarySourceOutlineItem else { return }

        if case .group(_, let section) = item.kind,
           let section,
           !item.children.isEmpty {
            DispatchQueue.main.async { [weak self, weak item] in
                guard let self,
                      let item,
                      self.sourceOutlineItemsByIdentifier[item.identifier] === item,
                      self.sourceOutlineView.isItemExpanded(item) == isExpanded else { return }
                self.setSourceSection(section, collapsed: !isExpanded)
                if isExpanded {
                    self.refreshSourceSelection()
                }
            }
            return
        }

        let folderURL: URL
        switch item.kind {
        case .scope(.folder(let url)):
            folderURL = url
        case .inlineFolderEdit(.rename(let url)):
            folderURL = url
        case .note:
            return
        default:
            return
        }
        guard let folderRow = sourceFolderTreeRows.first(where: {
            $0.url.standardizedFileURL.path == folderURL.standardizedFileURL.path
        }) else { return }

        let folderPath = folderURL.standardizedFileURL.path
        if folderRow.depth == 0 {
            if isExpanded {
                collapsedFolderPaths.remove(folderPath)
            } else {
                collapsedFolderPaths.insert(folderPath)
            }
        } else if isExpanded {
            expandedFolderPaths.insert(folderPath)
        } else {
            expandedFolderPaths.remove(folderPath)
        }
        if !isExpanded {
            expandedFolderPaths = expandedFolderPaths.filter { !$0.hasPrefix(folderPath + "/") }
            if case .folder(let selectedFolderURL) = selectedScope,
               selectedFolderURL.standardizedFileURL.path.hasPrefix(folderPath + "/") {
                selectedScope = .folder(folderURL)
                refreshSourceSelection()
                reloadNotesForNavigation(loadFirstIfNeeded: true)
            }
        }
        sourceFolderRows = Self.visibleFolderRowsForSourceList(
            from: sourceFolderTreeRows,
            collapsedFolderPaths: collapsedFolderPaths,
            expandedFolderPaths: expandedFolderPaths
        )
        persistSourceDisclosureState()
        refreshSourceCounts(using: sourceCountSnapshot)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        validateDrop info: NSDraggingInfo,
        proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return [] }
        let urls = sourceOutlineDraggedFileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return [] }

        let directories = urls.filter { sourceOutlineURLIsDirectory($0) }
        if directories.isEmpty {
            guard urls.allSatisfy(isMarkdownFileForLibrary),
                  case .folder(let targetDirectory)? = item.scope else { return [] }
            outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return urls.allSatisfy(isInsideConfiguredLibraryRoot)
                ? (canMoveDraggedNotesForLibrary(at: urls, to: targetDirectory) ? .move : [])
                : .copy
        }

        guard directories.count == 1, urls.count == 1 else { return [] }
        let source = directories[0]
        if isManagedLibraryFolder(source) {
            return canMoveOrReorderFolderForLibrary(source, under: item, childIndex: index) ? .move : []
        }
        if case .folder = item.scope {
            outlineView.setDropItem(item, dropChildIndex: NSOutlineViewDropOnItemIndex)
            return .copy
        }
        if case .group(_, .folders) = item.kind {
            return .copy
        }
        return []
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        acceptDrop info: NSDraggingInfo,
        item: Any?,
        childIndex index: Int
    ) -> Bool {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem else { return false }
        let urls = sourceOutlineDraggedFileURLs(from: info.draggingPasteboard)
        guard !urls.isEmpty else { return false }

        do {
            if urls.count == 1, sourceOutlineURLIsDirectory(urls[0]) {
                let source = urls[0]
                if isManagedLibraryFolder(source) {
                    return try moveOrReorderFolderForLibrary(source, under: item, childIndex: index)
                }
                if case .group(_, .folders) = item.kind {
                    try addExistingLibraryFolderForLibrary(at: source)
                    return true
                }
                guard case .folder(let targetDirectory)? = item.scope else { return false }
                _ = try importExternalLibraryItem(source, to: targetDirectory)
                return true
            }

            guard urls.allSatisfy(isMarkdownFileForLibrary),
                  case .folder(let targetDirectory)? = item.scope else { return false }
            if urls.allSatisfy(isInsideConfiguredLibraryRoot) {
                return !(try moveDraggedNotesForLibrary(at: urls, to: targetDirectory)).isEmpty
            }
            for url in urls {
                _ = try importExternalLibraryItem(url, to: targetDirectory)
            }
            return true
        } catch {
            presentErrorAlert(message: "拖拽失败", details: error.localizedDescription)
            return false
        }
    }

    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard outlineView === sourceOutlineView,
              let item = item as? LibrarySourceOutlineItem,
              case .folder(let folderURL)? = item.scope else { return nil }
        return folderURL as NSURL
    }

    func sourceOutlineURLIsDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    func isMarkdownFileForLibrary(_ url: URL) -> Bool {
        ["md", "markdown"].contains(url.pathExtension.lowercased())
    }

    func isManagedLibraryFolder(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return noteStore.preferredDirectories.contains { root in
            let rootPath = root.standardizedFileURL.path
            return path == rootPath || path.hasPrefix(rootPath + "/")
        }
    }

    func canMoveOrReorderFolderForLibrary(
        _ sourceURL: URL,
        under item: LibrarySourceOutlineItem,
        childIndex: Int
    ) -> Bool {
        let source = sourceURL.standardizedFileURL
        guard sourceFolderTreeRows.contains(where: { $0.url.standardizedFileURL.path == source.path }) else {
            return false
        }
        if case .group(_, .folders) = item.kind {
            return sourceFolderTreeRows.first(where: { $0.url.standardizedFileURL.path == source.path })?.depth == 0
        }
        guard case .folder(let target)? = item.scope else { return false }
        let targetURL = target.standardizedFileURL
        return source.path != noteStore.notesDirectory.standardizedFileURL.path
            && targetURL.path != source.path
            && !targetURL.path.hasPrefix(source.path + "/")
    }

    @discardableResult
    func moveOrReorderFolderForLibrary(
        _ sourceURL: URL,
        under item: LibrarySourceOutlineItem,
        childIndex: Int
    ) throws -> Bool {
        let source = sourceURL.standardizedFileURL
        guard canMoveOrReorderFolderForLibrary(source, under: item, childIndex: childIndex) else { return false }

        if case .group(_, .folders) = item.kind {
            persistFolderOrder(moving: source, among: item.children, insertionIndex: childIndex)
            reloadSourceFolderRowsForCurrentState()
            return true
        }

        guard case .folder(let targetParent)? = item.scope else { return false }
        let parent = targetParent.standardizedFileURL
        let destination: URL
        if source.deletingLastPathComponent().standardizedFileURL == parent {
            destination = source
        } else {
            destination = try moveFolderForLibrary(at: source, to: parent)
        }
        persistFolderOrder(moving: destination, among: item.children, insertionIndex: childIndex)
        reloadSourceFolderRowsForCurrentState()
        return true
    }

    @discardableResult
    func moveFolderForLibrary(at sourceURL: URL, to parentDirectory: URL) throws -> URL {
        let source = sourceURL.standardizedFileURL
        let parent = parentDirectory.standardizedFileURL
        try saveCurrentNoteIfNeeded()
        let destination = try noteStore.moveFolder(at: source, to: parent)
        guard destination != source else { return source }

        recordInternalFileSystemChanges(for: [source, destination])
        remapSourceSnapshotFolder(from: source, to: destination)
        setSelectedURLForLibrary(remappedLibraryURL(
            selectedURL,
            from: source,
            to: destination
        ))
        if case .folder(let selectedFolder) = selectedScope,
           let remappedFolder = remappedLibraryURL(selectedFolder, from: source, to: destination) {
            selectedScope = .folder(remappedFolder)
        }
        activeSearchSession = nil
        reloadPersistedSourceDisclosureState()
        reloadSourceFolderRowsForCurrentState()
        reloadNotesForNavigation(selecting: selectedURL, loadFirstIfNeeded: false)
        return destination
    }

    func remappedLibraryURL(_ url: URL?, from source: URL, to destination: URL) -> URL? {
        guard let url else { return nil }
        let path = url.standardizedFileURL.path
        guard path == source.path || path.hasPrefix(source.path + "/") else { return url }
        return URL(
            fileURLWithPath: destination.path + String(path.dropFirst(source.path.count)),
            isDirectory: path == source.path
        )
    }

    func persistFolderOrder(
        moving folderURL: URL,
        among children: [LibrarySourceOutlineItem],
        insertionIndex: Int
    ) {
        let folderPath = folderURL.standardizedFileURL.path
        var siblingPaths = children.compactMap { child -> String? in
            guard case .folder(let url)? = child.scope else { return nil }
            let path = url.standardizedFileURL.path
            return path == folderPath ? nil : path
        }
        let targetIndex = insertionIndex == NSOutlineViewDropOnItemIndex
            ? siblingPaths.count
            : min(max(insertionIndex, 0), siblingPaths.count)
        siblingPaths.insert(folderPath, at: targetIndex)
        let siblingSet = Set(siblingPaths)
        noteStore.libraryFolderOrderPaths = noteStore.libraryFolderOrderPaths.filter {
            !siblingSet.contains($0) && $0 != folderPath
        } + siblingPaths
    }

    @discardableResult
    func importExternalLibraryItem(_ sourceURL: URL, to targetDirectory: URL) throws -> URL {
        let source = sourceURL.standardizedFileURL
        let target = targetDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var destination = target.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: sourceOutlineURLIsDirectory(source)
        )
        var suffix = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            let stem = source.deletingPathExtension().lastPathComponent
            let filename = source.pathExtension.isEmpty
                ? "\(stem) \(suffix)"
                : "\(stem) \(suffix).\(source.pathExtension)"
            destination = target.appendingPathComponent(filename, isDirectory: sourceOutlineURLIsDirectory(source))
            suffix += 1
        }
        try FileManager.default.copyItem(at: source, to: destination)
        recordInternalFileSystemChanges(for: [destination])
        activeSearchSession = nil
        reloadSourceFolderRowsForCurrentState()
        forceFullLibrarySnapshotReload()
        selectedScope = sourceOutlineURLIsDirectory(destination) ? .folder(destination) : .folder(target)
        refreshSourceSelection()
        return destination
    }

    func sourceOutlineDraggedFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let objects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []
        var seenPaths = Set<String>()
        return objects.compactMap { object in
            let url = (object as? URL) ?? ((object as? NSURL).map { $0 as URL })
            guard let url else { return nil }
            let standardized = url.standardizedFileURL
            guard standardized.isFileURL,
                  seenPaths.insert(standardized.path).inserted else { return nil }
            return standardized
        }
    }
}
