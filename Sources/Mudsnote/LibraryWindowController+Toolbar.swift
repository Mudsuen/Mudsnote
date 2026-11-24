import AppKit
import Foundation
import MudsnoteCore

extension LibraryWindowController {
    func configureToolbar() {
        searchField.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarSearchField")
        searchField.placeholderString = LibraryCopy.search
        searchField.toolTip = LibraryCopy.searchNotes
        searchField.setAccessibilityLabel(LibraryCopy.searchNotes)
        searchField.font = .systemFont(ofSize: 14)
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        searchField.isBordered = false
        searchField.isBezeled = true
        searchField.drawsBackground = false
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .exterior
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.frame = NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarSearchWidth,
            height: LibraryNotesLayout.toolbarSearchHeight
        )
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarSearchHeight).isActive = true

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbar = toolbar
    }

    func configureSearchScopeControl() {
        searchScopeControl.identifier = NSUserInterfaceItemIdentifier("LibrarySearchScopeControl")
        searchScopeControl.setAccessibilityLabel("搜索范围")
        searchScopeControl.target = self
        searchScopeControl.action = #selector(searchScopeChanged(_:))
        searchScopeControl.selectedSegment = 0
        searchScopeControl.segmentStyle = .capsule
        searchScopeControl.controlSize = .small
        searchScopeControl.font = .systemFont(ofSize: 11, weight: .medium)
        searchScopeControl.setWidth(44, forSegment: 0)
        searchScopeControl.setWidth(44, forSegment: 1)
        searchScopeControl.toolTip = "切换搜索范围"
        searchScopeControl.isHidden = true
    }

    func configureNoteListHeaderLabels() {
        noteListTitleLabel.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListTitle")
        noteListTitleLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteListHeaderTitleFontSize, weight: .medium)
        noteListTitleLabel.textColor = panelPrimaryTextColor()
        noteListTitleLabel.lineBreakMode = .byTruncatingTail

        noteListCountLabel.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListCount")
        noteListCountLabel.font = .systemFont(ofSize: LibraryNotesLayout.noteListHeaderCountFontSize, weight: .regular)
        noteListCountLabel.textColor = panelTertiaryTextColor()
        noteListCountLabel.lineBreakMode = .byTruncatingTail
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.navigationGroupToolbarItemIdentifier,
            Self.sourceTrackingSeparatorToolbarItemIdentifier,
            Self.pageTitleToolbarItemIdentifier,
            Self.documentTabsToolbarItemIdentifier,
            .flexibleSpace
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.navigationGroupToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.isBordered = false
            let back = OverviewActionButton("", symbol: "arrow.left") { [weak self] in self?.navigateLibraryBack() }
            let forward = OverviewActionButton("", symbol: "arrow.right") { [weak self] in self?.navigateLibraryForward() }
            let sidebar = OverviewActionButton("", symbol: "sidebar.left") { [weak self] in _ = self?.toggleSourceListForLibrary() }
            for (button, label) in [(back, "后退"), (forward, "前进"), (sidebar, "展开或收起笔记列表")] {
                button.isBordered = false
                button.toolTip = label
                button.setAccessibilityLabel(label)
                button.image = button.image?.withSymbolConfiguration(.init(pointSize: 16, weight: .light))
                button.widthAnchor.constraint(equalToConstant: 34).isActive = true
                button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            }
            pageBackButton = back
            pageForwardButton = forward
            sidebarToggleButton = sidebar
            back.isEnabled = !pageBackStack.isEmpty
            forward.isEnabled = !pageForwardStack.isEmpty
            let group = NSStackView(views: [back, forward, sidebar])
            group.orientation = .horizontal
            group.spacing = 0
            item.view = group
            item.visibilityPriority = .high
            return item
        case Self.pageTitleToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.isBordered = false
            item.autovalidates = false
            item.isEnabled = true
            toolbarPageTitle.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                toolbarPageTitle.widthAnchor.constraint(equalToConstant: 160),
                toolbarPageTitle.heightAnchor.constraint(equalToConstant: 28)
            ])
            item.view = toolbarPageTitle
            item.visibilityPriority = .high
            return item
        case Self.sourceTrackingSeparatorToolbarItemIdentifier:
            return toolbarTrackingSeparatorItem(identifier: itemIdentifier, dividerIndex: 0)
        case Self.documentTabsToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "标签页"
            item.paletteLabel = "标签页"
            item.visibilityPriority = .high
            item.isBordered = false
            item.view = buildDocumentTabHeader()
            return item
        default:
            return nil
        }
    }

    func toolbarTrackingSeparatorItem(
        identifier: NSToolbarItem.Identifier,
        dividerIndex: Int
    ) -> NSToolbarItem {
        guard let librarySplitView else {
            return NSToolbarItem(itemIdentifier: identifier)
        }
        return NSTrackingSeparatorToolbarItem(
            identifier: identifier,
            splitView: librarySplitView,
            dividerIndex: dividerIndex
        )
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        true
    }

    func updateToolbarActionState() {
        pageBackButton?.isEnabled = !pageBackStack.isEmpty
        pageForwardButton?.isEnabled = !pageForwardStack.isEmpty
        applySourceVisibilityChrome(isSourceListVisibleForLibrary)
        window?.toolbar?.validateVisibleItems()
    }

    func popToolbarMenu(_ menu: NSMenu, from sender: Any?) {
        menu.autoenablesItems = false
        if let view = (sender as? NSView) ?? (sender as? NSToolbarItem)?.view {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: view.bounds.midX, y: view.bounds.minY - 4),
                in: view
            )
        } else if let contentView = window?.contentView {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: contentView.bounds.midX, y: contentView.bounds.maxY - 44),
                in: contentView
            )
        }
    }
}
