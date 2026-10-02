import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func configureToolbar() {
        searchField.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarSearchField")
        searchField.placeholderString = LibraryCopy.search
        searchField.toolTip = LibraryCopy.searchNotes
        searchField.setAccessibilityLabel(LibraryCopy.searchNotes)
        searchField.font = .systemFont(ofSize: 14)
        searchField.delegate = self
        searchField.isBordered = true
        searchField.bezelStyle = .roundedBezel
        searchField.focusRingType = .default
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.frame = NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarSearchWidth,
            height: LibraryNotesLayout.toolbarSearchHeight
        )
        searchField.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarSearchWidth).isActive = true
        searchField.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarSearchHeight).isActive = true

        let toolbar = NSToolbar(identifier: Self.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window?.toolbar = toolbar
        applySidebarPresentationChrome()
        applyNoteListViewModeToolbarChrome()
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
            .flexibleSpace,
            Self.newNoteToolbarItemIdentifier,
            Self.toggleSidebarToolbarItemIdentifier,
            Self.sourceTrackingSeparatorToolbarItemIdentifier,
            Self.sidebarPresentationToolbarItemIdentifier,
            Self.documentTabsToolbarItemIdentifier,
            .flexibleSpace,
            Self.searchToolbarItemIdentifier
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [
            Self.navigationBackToolbarItemIdentifier,
            Self.navigationForwardToolbarItemIdentifier,
            Self.editorToolsToolbarItemIdentifier,
            Self.sourceTrackingSeparatorToolbarItemIdentifier,
            Self.documentTabsToolbarItemIdentifier,
            Self.noteTrackingSeparatorToolbarItemIdentifier,
            Self.openSeparateToolbarItemIdentifier,
            Self.moveToolbarItemIdentifier,
            Self.saveToolbarItemIdentifier,
            Self.deleteToolbarItemIdentifier,
            Self.restoreToolbarItemIdentifier,
            Self.formatToolbarItemIdentifier,
            Self.checklistToolbarItemIdentifier,
            Self.linkToolbarItemIdentifier,
            Self.sourceModeToolbarItemIdentifier
        ]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.sourceTrackingSeparatorToolbarItemIdentifier:
            return toolbarTrackingSeparatorItem(identifier: itemIdentifier, dividerIndex: 0)
        case Self.noteTrackingSeparatorToolbarItemIdentifier:
            return toolbarTrackingSeparatorItem(identifier: itemIdentifier, dividerIndex: 1)
        case Self.noteListTitleToolbarItemIdentifier:
            return toolbarNoteListTitleItem(identifier: itemIdentifier)
        case Self.sidebarPresentationToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "文件树 / 列表"
            item.visibilityPriority = .high
            item.isBordered = false
            let button = NSButton()
            button.identifier = NSUserInterfaceItemIdentifier("LibrarySidebarPresentationButton")
            configureSidebarPresentationButton(button)
            sidebarPresentationButtons.append(button)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
            item.view = button
            return item
        case Self.documentTabsToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "标签页"
            item.paletteLabel = "标签页"
            item.visibilityPriority = .high
            item.isBordered = false
            item.view = buildDocumentTabHeader()
            return item
        case Self.toggleSidebarToolbarItemIdentifier:
            return toolbarNewNoteButtonItem(
                identifier: itemIdentifier,
                label: "隐藏资料库",
                symbolName: "sidebar.left",
                action: #selector(toggleSourceListPressed),
                wrapperWidth: LibraryNotesLayout.toolbarCollapsedSidebarWrapperWidth,
                wrapperIdentifier: "LibraryToolbarSidebarWrapper"
            )
        case Self.navigationBackToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "后退",
                symbolName: "chevron.left",
                action: #selector(goBackInKnowledgeRelations)
            )
        case Self.navigationForwardToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "前进",
                symbolName: "chevron.right",
                action: #selector(goForwardInKnowledgeRelations)
            )
        case Self.newNoteToolbarItemIdentifier:
            return toolbarNewNoteButtonItem(
                identifier: itemIdentifier,
                label: "新建笔记",
                symbolName: "square.and.pencil",
                action: #selector(newNotePressed)
            )
        case Self.openSeparateToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "独立窗口打开",
                symbolName: "rectangle.on.rectangle",
                action: #selector(openSelectedInSeparateWindow),
                visibilityPriority: .low
            )
        case Self.editorToolsToolbarItemIdentifier:
            return toolbarEditorToolsItem(identifier: itemIdentifier)
        case Self.formatToolbarItemIdentifier:
            let item = toolbarImageItem(
                identifier: itemIdentifier,
                label: "格式",
                image: makeFormatToolbarImage(),
                action: #selector(formatPressed(_:))
            )
            return item
        case Self.checklistToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "待办列表",
                symbolName: "checklist",
                action: #selector(checklistPressed)
            )
        case Self.revealToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "打开文件位置",
                symbolName: "folder",
                action: #selector(revealSelectedNoteInFinderPressed)
            )
        case Self.linkToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "插入链接",
                symbolName: "link",
                action: #selector(linkPressed)
            )
        case Self.sourceModeToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "显示 Markdown 源码",
                symbolName: "chevron.left.forwardslash.chevron.right",
                action: #selector(toggleEditorSourceModePressed)
            )
        case Self.moveToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "移动到文件夹",
                symbolName: "folder",
                action: #selector(moveSelectedNotePressed(_:)),
                visibilityPriority: .low
            )
        case Self.saveToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "保存",
                symbolName: "checkmark.circle",
                action: #selector(savePressed),
                visibilityPriority: .low
            )
        case Self.deleteToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "删除",
                symbolName: "trash",
                action: #selector(deleteSelectedNotePressed),
                visibilityPriority: .low
            )
        case Self.restoreToolbarItemIdentifier:
            return toolbarButtonItem(
                identifier: itemIdentifier,
                label: "恢复",
                symbolName: "arrow.uturn.backward",
                action: #selector(restoreSelectedNotePressed),
                visibilityPriority: .low
            )
        case Self.searchToolbarItemIdentifier:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = LibraryCopy.search
            item.paletteLabel = LibraryCopy.search
            item.toolTip = LibraryCopy.searchNotes
            item.visibilityPriority = .high
            let wrapper = NSView(frame: NSRect(
                x: 0,
                y: 0,
                width: LibraryNotesLayout.toolbarSearchWrapperWidth,
                height: LibraryNotesLayout.toolbarSearchWrapperHeight
            ))
            wrapper.translatesAutoresizingMaskIntoConstraints = false
            wrapper.addSubview(searchField)
            NSLayoutConstraint.activate([
                wrapper.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarSearchWrapperWidth),
                wrapper.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarSearchWrapperHeight),
                searchField.centerXAnchor.constraint(equalTo: wrapper.centerXAnchor),
                searchField.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
            ])
            item.view = wrapper
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

    func toolbarNoteListTitleItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "笔记列表标题"
        item.paletteLabel = "笔记列表标题"
        item.visibilityPriority = .high
        item.isBordered = false

        let titleStack = NSStackView(views: [noteListTitleLabel, noteListCountLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 0
        titleStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerStack = NSStackView(views: [titleStack, searchScopeControl])
        headerStack.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarNoteListHeaderStack")
        headerStack.orientation = .horizontal
        headerStack.alignment = .centerY
        headerStack.spacing = 8
        searchScopeControl.setContentHuggingPriority(.required, for: .horizontal)
        searchScopeControl.setContentCompressionResistancePriority(.required, for: .horizontal)

        let wrapper = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarNoteListTitleWidth,
            height: LibraryNotesLayout.toolbarNoteListTitleHeight
        ))
        wrapper.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarNoteListTitle")
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(headerStack)
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        let titleLeadingConstraint = headerStack.leadingAnchor.constraint(
            equalTo: wrapper.leadingAnchor,
            constant: LibraryNotesLayout.toolbarExpandedTitleLeadingOffset
        )
        noteListToolbarTitleLeadingConstraint = titleLeadingConstraint
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarNoteListTitleWidth),
            wrapper.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarNoteListTitleHeight),
            titleLeadingConstraint,
            headerStack.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor, constant: -6),
            headerStack.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])

        item.view = wrapper
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case Self.navigationBackToolbarItemIdentifier:
            return !knowledgeBackStack.isEmpty
        case Self.navigationForwardToolbarItemIdentifier:
            return !knowledgeForwardStack.isEmpty
        case Self.moreToolbarItemIdentifier:
            return canShowMoreActions
        case Self.openSeparateToolbarItemIdentifier:
            return canUseSingleSelectedNote
        case Self.editorToolsToolbarItemIdentifier:
            return canEditCurrentDocument || canUseSelectedNote
        case Self.formatToolbarItemIdentifier,
             Self.checklistToolbarItemIdentifier,
             Self.linkToolbarItemIdentifier,
             Self.sourceModeToolbarItemIdentifier:
            return canEditCurrentDocument
        case Self.revealToolbarItemIdentifier:
            return canUseSelectedNote
        case Self.moveToolbarItemIdentifier:
            return canMoveSelectedNote
        case Self.saveToolbarItemIdentifier:
            return canEditCurrentDocument
        case Self.exportToolbarItemIdentifier:
            return canExportSelectedNote
        case Self.deleteToolbarItemIdentifier:
            return canUseSelectedNote
        case Self.restoreToolbarItemIdentifier:
            return canRestoreSelectedNote
        default:
            return true
        }
    }

    func toolbarButtonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .standard,
        symbolPointSize: CGFloat = LibraryNotesLayout.toolbarSymbolPointSize
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = toolbarSymbolImage(
            symbolName: symbolName,
            label: label,
            pointSize: symbolPointSize
        )
        item.target = self
        item.action = action
        item.visibilityPriority = visibilityPriority
        item.isBordered = false
        return item
    }

    func toolbarEditorToolsItem(identifier: NSToolbarItem.Identifier) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = "编辑工具"
        item.paletteLabel = "编辑工具"
        item.toolTip = "编辑工具"
        item.visibilityPriority = .high
        item.isBordered = false

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let capsule = toolbarGlassSurface(
            identifier: "LibraryToolbarEditorTools",
            content: stack,
            size: NSSize(
                width: LibraryNotesLayout.toolbarEditorToolsWidth,
                height: LibraryNotesLayout.toolbarEditorToolsHeight
            ),
            cornerRadius: LibraryNotesLayout.toolbarEditorToolsHeight / 2
        )
        let buttons = [
            toolbarEditorFormatButton(
                identifier: Self.formatToolbarItemIdentifier,
                label: "格式",
                action: #selector(formatPressed(_:))
            ),
            toolbarEditorToolButton(
                identifier: Self.checklistToolbarItemIdentifier,
                label: "待办列表",
                symbolName: "checklist",
                action: #selector(checklistPressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.linkToolbarItemIdentifier,
                label: "插入链接",
                symbolName: "link",
                action: #selector(linkPressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.sourceModeToolbarItemIdentifier,
                label: "显示 Markdown 源码",
                symbolName: "chevron.left.forwardslash.chevron.right",
                action: #selector(toggleEditorSourceModePressed)
            ),
            toolbarEditorToolButton(
                identifier: Self.revealToolbarItemIdentifier,
                label: "打开文件位置",
                symbolName: "folder",
                action: #selector(revealSelectedNoteInFinderPressed)
            )
        ]
        buttons.forEach { stack.addArrangedSubview($0) }

        NSLayoutConstraint.activate([
            stack.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolButtonHeight)
        ])

        let slot = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: LibraryNotesLayout.toolbarEditorToolsSlotWidth,
            height: LibraryNotesLayout.toolbarEditorToolsHeight
        ))
        slot.identifier = NSUserInterfaceItemIdentifier("LibraryToolbarEditorToolsSlot")
        slot.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(capsule)
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolsSlotWidth),
            slot.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolsHeight),
            capsule.trailingAnchor.constraint(equalTo: slot.trailingAnchor),
            capsule.centerYAnchor.constraint(equalTo: slot.centerYAnchor)
        ])

        item.view = slot
        updateEditorToolsToolbarGroupState(in: item)
        return item
    }

    func toolbarEditorFormatButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        action: Selector
    ) -> NSButton {
        let button = NSButton(title: "Aa", target: self, action: action)
        button.font = .systemFont(ofSize: LibraryNotesLayout.toolbarEditorFormatFontSize, weight: .regular)
        return configureToolbarEditorToolButton(button, identifier: identifier, label: label)
    }

    func toolbarEditorToolButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector
    ) -> NSButton {
        let image = toolbarEditorToolSymbolImage(symbolName: symbolName, label: label)
        image?.isTemplate = true
        return toolbarEditorToolButton(identifier: identifier, label: label, image: image, action: action)
    }

    func toolbarEditorToolButton(
        identifier: NSToolbarItem.Identifier,
        label: String,
        image: NSImage?,
        action: Selector
    ) -> NSButton {
        let button = NSButton(image: image ?? NSImage(), target: self, action: action)
        return configureToolbarEditorToolButton(button, identifier: identifier, label: label)
    }

    func configureToolbarEditorToolButton(
        _ button: NSButton,
        identifier: NSToolbarItem.Identifier,
        label: String
    ) -> NSButton {
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .toolbar
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = true
        button.focusRingType = .none
        button.imagePosition = button.image == nil ? .noImage : .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolButtonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarEditorToolButtonHeight).isActive = true
        return button
    }

    func toolbarImageItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        image: NSImage,
        action: Selector,
        visibilityPriority: NSToolbarItem.VisibilityPriority = .standard
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.image = image
        item.target = self
        item.action = action
        item.visibilityPriority = visibilityPriority
        return item
    }

    func toolbarNewNoteButtonItem(
        identifier: NSToolbarItem.Identifier,
        label: String,
        symbolName: String,
        action: Selector,
        wrapperWidth: CGFloat = LibraryNotesLayout.toolbarNewNoteWrapperWidth,
        wrapperIdentifier: String = "LibraryToolbarNewNoteWrapper"
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.target = self
        item.action = action
        item.isBordered = false

        let symbol = toolbarCompactGlassSymbolImage(
            symbolName: symbolName,
            label: label,
            pointSize: LibraryNotesLayout.toolbarNewNoteSymbolPointSize
        )
        // AppKit applies a different symbol scale inside the sidebar toolbar.
        // Render a template with fixed intrinsic dimensions so both regions
        // draw exactly the same glyph when the tracking separator moves.
        let configuredImage = symbol.map { symbol in
            let canvasSize = NSSize(width: 24, height: 22)
            let scale = 18 / max(symbol.size.width, symbol.size.height)
            let glyphSize = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            let image = NSImage(size: canvasSize)
            image.lockFocus()
            symbol.draw(in: NSRect(
                x: (canvasSize.width - glyphSize.width) / 2,
                y: (canvasSize.height - glyphSize.height) / 2,
                width: glyphSize.width,
                height: glyphSize.height
            ))
            image.unlockFocus()
            image.isTemplate = true
            image.accessibilityDescription = label
            return image
        }

        let button = NSButton(image: configuredImage ?? NSImage(), target: self, action: action)
        button.identifier = NSUserInterfaceItemIdentifier(identifier.rawValue)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.focusRingType = .none
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.contentTintColor = toolbarIconTintColor(isEnabled: true)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.widthAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize).isActive = true

        let wrapper = NSView(frame: NSRect(
            x: 0,
            y: 0,
            width: wrapperWidth,
            height: LibraryNotesLayout.toolbarCircularButtonSize
        ))
        wrapper.identifier = NSUserInterfaceItemIdentifier(wrapperIdentifier)
        wrapper.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(button)
        NSLayoutConstraint.activate([
            wrapper.widthAnchor.constraint(equalToConstant: wrapperWidth),
            wrapper.heightAnchor.constraint(equalToConstant: LibraryNotesLayout.toolbarCircularButtonSize),
            button.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            button.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor)
        ])

        item.image = configuredImage
        item.view = wrapper
        return item
    }

    func toolbarSymbolImage(
        symbolName: String,
        label: String,
        pointSize: CGFloat = LibraryNotesLayout.toolbarSymbolPointSize
    ) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular
        )) ?? image
    }

    func toolbarCompactGlassSymbolImage(
        symbolName: String,
        label: String,
        pointSize: CGFloat = LibraryNotesLayout.toolbarCircularButtonSymbolPointSize
    ) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular
        )) ?? image
    }

    func toolbarEditorToolSymbolImage(symbolName: String, label: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        return image?.withSymbolConfiguration(NSImage.SymbolConfiguration(
            pointSize: LibraryNotesLayout.toolbarEditorToolSymbolPointSize,
            weight: .regular
        )) ?? image
    }

    func toolbarIconTintColor(isEnabled: Bool) -> NSColor {
        panelPrimaryTextColor().withAlphaComponent(isEnabled
            ? LibraryNotesLayout.toolbarIconEnabledAlpha
            : LibraryNotesLayout.toolbarIconDisabledAlpha
        )
    }

    func toolbarEditorToolIconTintColor(isEnabled: Bool) -> NSColor {
        panelPrimaryTextColor().withAlphaComponent(isEnabled
            ? LibraryNotesLayout.toolbarIconEnabledAlpha
            : LibraryNotesLayout.toolbarEditorToolIconDisabledAlpha
        )
    }

    func toolbarGlassSurface(
        identifier: String,
        content: NSView,
        size: NSSize,
        cornerRadius: CGFloat
    ) -> NSGlassEffectView {
        let glass = NSGlassEffectView(frame: NSRect(origin: .zero, size: size))
        glass.identifier = NSUserInterfaceItemIdentifier(identifier)
        glass.style = .regular
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        glass.translatesAutoresizingMaskIntoConstraints = false
        glass.setContentHuggingPriority(.required, for: .horizontal)
        glass.setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            glass.widthAnchor.constraint(equalToConstant: size.width),
            glass.heightAnchor.constraint(equalToConstant: size.height)
        ])
        return glass
    }

    func makeFormatToolbarImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 21, height: 16))
        image.lockFocus()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        ("Aa" as NSString).draw(at: NSPoint(x: 1, y: 0), withAttributes: attributes)
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "格式"
        return image
    }

    func updateToolbarActionState() {
        let isTrashScope = selectedScope == .trash
        let selectionCount = selectedMarkdownFileURLsForLibrary().count
        applySourceVisibilityChrome(isSourceListVisibleForLibrary)
        applyNoteListViewModeToolbarChrome()
        for item in window?.toolbar?.items ?? [] {
            switch item.itemIdentifier {
            case Self.deleteToolbarItemIdentifier:
                let label = isTrashScope
                    ? noteActionTitle(single: "永久删除", multiple: "永久删除 %d 条笔记", count: selectionCount)
                    : noteActionTitle(single: "删除", multiple: "删除 %d 条笔记", count: selectionCount)
                updateToolbarItemPresentation(
                    item,
                    label: label,
                    symbolName: isTrashScope ? "trash.slash" : "trash"
                )
            case Self.restoreToolbarItemIdentifier:
                let label = noteActionTitle(single: "恢复", multiple: "恢复 %d 条笔记", count: selectionCount)
                updateToolbarItemPresentation(item, label: label, symbolName: "arrow.uturn.backward")
            case Self.editorToolsToolbarItemIdentifier:
                updateEditorToolsToolbarGroupState(in: item)
                updateSourceModeToolbarButton(in: item)
            default:
                continue
            }
        }
        window?.toolbar?.validateVisibleItems()
        updateVisibleEditorToolsToolbarGroupEnabled()
    }

    func updateToolbarItemPresentation(
        _ item: NSToolbarItem,
        label: String,
        symbolName: String,
        symbolPointSize: CGFloat = LibraryNotesLayout.toolbarSymbolPointSize
    ) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        let image = toolbarSymbolImage(
            symbolName: symbolName,
            label: label,
            pointSize: symbolPointSize
        )
        image?.isTemplate = true
        item.image = image
        guard let button = item.view as? NSButton else { return }
        button.image = image
        button.toolTip = label
        button.setAccessibilityLabel(label)
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

    func updateVisibleEditorToolsToolbarGroupEnabled() {
        for item in window?.toolbar?.items ?? [] where item.itemIdentifier == Self.editorToolsToolbarItemIdentifier {
            updateEditorToolsToolbarGroupState(in: item)
        }
    }

    func updateEditorToolsToolbarGroupState(in item: NSToolbarItem) {
        let hasEnabledAction = canEditCurrentDocument || canUseSelectedNote
        item.isEnabled = hasEnabledAction
        guard let view = item.view else { return }
        view.alphaValue = hasEnabledAction
            ? LibraryNotesLayout.toolbarEditorToolsEnabledAlpha
            : LibraryNotesLayout.toolbarEditorToolsDisabledAlpha
        for button in editorToolButtons(in: view) {
            let identifier = button.identifier?.rawValue
            let isEnabled: Bool
            if identifier == Self.revealToolbarItemIdentifier.rawValue {
                isEnabled = canUseSelectedNote
            } else if identifier == Self.sourceModeToolbarItemIdentifier.rawValue {
                isEnabled = canEditCurrentDocument
            } else {
                isEnabled = canEditCurrentDocument && !isEditorShowingMarkdownSource
            }
            button.isEnabled = isEnabled
            button.alphaValue = 1
            button.contentTintColor = toolbarEditorToolIconTintColor(isEnabled: isEnabled)
            updateToolbarEditorTextButtonAppearance(
                button,
                isEnabled: isEnabled,
                isWindowFocused: window?.isKeyWindow == true
            )
        }
    }

    func updateSourceModeToolbarButton(in item: NSToolbarItem) {
        guard let view = item.view,
              let button = editorToolButtons(in: view).first(where: {
                  $0.identifier?.rawValue == Self.sourceModeToolbarItemIdentifier.rawValue
              }) else { return }
        let label = isEditorShowingMarkdownSource ? "显示渲染模式" : "显示 Markdown 源码"
        let symbol = isEditorShowingMarkdownSource ? "doc.richtext" : "chevron.left.forwardslash.chevron.right"
        button.image = toolbarEditorToolSymbolImage(symbolName: symbol, label: label)
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    func editorToolButtons(in view: NSView) -> [NSButton] {
        var buttons = view.subviews.compactMap { $0 as? NSButton }
        for subview in view.subviews {
            buttons.append(contentsOf: editorToolButtons(in: subview))
        }
        return buttons
    }

    func updateToolbarEditorTextButtonAppearance(
        _ button: NSButton,
        isEnabled: Bool,
        isWindowFocused: Bool
    ) {
        guard button.identifier?.rawValue == Self.formatToolbarItemIdentifier.rawValue else { return }
        let titleAlpha = isEnabled && isWindowFocused
            ? LibraryNotesLayout.toolbarIconEnabledAlpha
            : LibraryNotesLayout.toolbarIconDisabledAlpha
        button.attributedTitle = NSAttributedString(string: "Aa", attributes: [
            .font: NSFont.systemFont(
                ofSize: LibraryNotesLayout.toolbarEditorFormatFontSize,
                weight: .regular
            ),
            .foregroundColor: panelPrimaryTextColor().withAlphaComponent(titleAlpha)
        ])
    }

    func refreshToolbarEditorTextButtonFocus(isWindowFocused: Bool) {
        for item in window?.toolbar?.items ?? [] where item.itemIdentifier == Self.editorToolsToolbarItemIdentifier {
            guard let view = item.view else { continue }
            for button in editorToolButtons(in: view) {
                updateToolbarEditorTextButtonAppearance(
                    button,
                    isEnabled: button.isEnabled,
                    isWindowFocused: isWindowFocused
                )
            }
        }
    }
}
