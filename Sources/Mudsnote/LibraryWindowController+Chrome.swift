import AppKit
import Carbon.HIToolbox
import Foundation
import ImageIO
import MudsnoteCore
import UniformTypeIdentifiers

extension LibraryWindowController {
    func buildUI() {
        let sourceList = buildSourceList()
        let sidebar = buildSidebar()
        let navigation = buildNavigationSidebar(tree: sourceList, list: sidebar)
        let editor = buildEditor()

        let sourceController = NSViewController()
        sourceController.view = navigation
        let editorController = NSViewController()
        editorController.view = editor

        let sourceItem = NSSplitViewItem(sidebarWithViewController: sourceController)
        sourceItem.minimumThickness = LibraryNotesLayout.sourceColumnMinimumWidth
        sourceItem.maximumThickness = LibraryNotesLayout.sourceColumnMaximumWidth
        sourceItem.canCollapse = true
        sourceItem.allowsFullHeightLayout = true
        sourceItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        sourceItem.isCollapsed = !noteStore.librarySourceListVisible

        let editorItem = NSSplitViewItem(viewController: editorController)
        editorItem.minimumThickness = LibraryNotesLayout.editorColumnMinimumWidth

        let splitController = NSSplitViewController()
        splitController.addSplitViewItem(sourceItem)
        splitController.addSplitViewItem(editorItem)
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        splitController.view.wantsLayer = true
        splitController.view.layer?.backgroundColor = LibraryNotesPalette.windowBackground.cgColor

        librarySplitViewController = splitController
        sourceSplitViewItem = sourceItem
        noteListSplitViewItem = nil
        librarySplitView = splitController.splitView
        window?.contentViewController = splitController
        hostEditorSuggestionView(in: splitController.view)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(librarySplitViewDidResize(_:)),
            name: NSSplitView.didResizeSubviewsNotification,
            object: splitController.splitView
        )

        splitController.view.layoutSubtreeIfNeeded()
        applyStoredLibrarySplitLayoutForLibrary()
        applySidebarPresentation(animated: false)
        applyNoteListViewModeChrome(animated: false)
    }

    func buildNavigationSidebar(tree: NSView, list: NSView) -> NSView {
        let container = NSView()
        container.identifier = NSUserInterfaceItemIdentifier("LibraryNavigationSidebar")
        container.setAccessibilityLabel("笔记导航")
        container.translatesAutoresizingMaskIntoConstraints = false
        sourceListView = container
        sidebarTreeView = tree
        sidebarNoteListView = list

        let surface = NSVisualEffectView()
        surface.material = .underWindowBackground
        surface.blendingMode = .withinWindow
        surface.state = .active
        // The native sidebar host already supplies the rounded outer boundary.
        surface.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(surface)

        let tint = LibraryPassthroughTintView()
        tint.identifier = NSUserInterfaceItemIdentifier("LibraryNavigationSidebarTint")
        tint.wantsLayer = true
        tint.layer?.backgroundColor = LibraryNotesPalette.sidebarMaterialTint.cgColor
        let modeContainer = NSView()
        modeContainer.identifier = NSUserInterfaceItemIdentifier("LibrarySidebarModeContent")

        tint.translatesAutoresizingMaskIntoConstraints = false
        modeContainer.translatesAutoresizingMaskIntoConstraints = false
        tree.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        surface.addSubview(tint)
        container.addSubview(sidebarHeaderView)
        sidebarHeaderView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(modeContainer)
        modeContainer.addSubview(tree)
        modeContainer.addSubview(list)


        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            surface.topAnchor.constraint(equalTo: container.topAnchor),
            surface.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tint.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            tint.topAnchor.constraint(equalTo: surface.topAnchor),
            tint.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            modeContainer.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            modeContainer.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sidebarHeaderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sidebarHeaderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sidebarHeaderView.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 6),
            modeContainer.topAnchor.constraint(equalTo: sidebarHeaderView.bottomAnchor),
            modeContainer.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tree.leadingAnchor.constraint(equalTo: modeContainer.leadingAnchor),
            tree.trailingAnchor.constraint(equalTo: modeContainer.trailingAnchor),
            tree.topAnchor.constraint(equalTo: modeContainer.topAnchor),
            tree.bottomAnchor.constraint(equalTo: modeContainer.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: modeContainer.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: modeContainer.trailingAnchor),
            list.topAnchor.constraint(equalTo: modeContainer.topAnchor),
            list.bottomAnchor.constraint(equalTo: modeContainer.bottomAnchor)
        ])
        return container
    }

    func setSidebarPresentation(_ presentation: LibrarySidebarPresentation, animated: Bool) {
        guard presentation != sidebarPresentation else { return }
        sidebarPresentation = presentation
        noteStore.librarySidebarPresentationRawValue = presentation.rawValue
        applySidebarPresentation(animated: animated)
    }

    var isShowingSidebarTree: Bool {
        sidebarPresentation == .tree
            && searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func applySidebarPresentation(animated: Bool) {
        guard let tree = sidebarTreeView, let list = sidebarNoteListView else { return }
        let showsTree = isShowingSidebarTree
        let incoming = showsTree ? tree : list
        let changed = incoming.isHidden
        // Keep the shared header and editor stationary; only reveal the new content.
        tree.layer?.removeAllAnimations()
        list.layer?.removeAllAnimations()
        tree.isHidden = !showsTree
        list.isHidden = showsTree
        tree.alphaValue = 1
        list.alphaValue = 1
        if showsTree {
            if sourceTreeNeedsScopeRebuild {
                rebuildSourceRows(includeTags: sourceTagsLoaded)
            }
            refreshSourceSelection()
        }
        applySidebarPresentationChrome()
        updateSidebarScopeButton()
        if changed, animated, window?.isVisible == true,
           !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            incoming.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                incoming.animator().alphaValue = 1
            }
        }
    }

    func buildSourceList() -> NSView {
        let sourceList = NSView()
        sourceList.translatesAutoresizingMaskIntoConstraints = false
        sourceList.identifier = NSUserInterfaceItemIdentifier("LibrarySourceSurface")
        sourceList.setAccessibilityLabel("资料库")
        sourceFolderTreeRows = rootFolderRowsForSourceList()
        sourceFolderRows = sourceFolderTreeRows

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("LibrarySourceColumn"))
        column.resizingMask = .autoresizingMask
        sourceOutlineView.addTableColumn(column)
        sourceOutlineView.outlineTableColumn = column
        sourceOutlineView.identifier = NSUserInterfaceItemIdentifier("LibrarySourceOutline")
        sourceOutlineView.setAccessibilityLabel("资料库")
        sourceOutlineView.headerView = nil
        sourceOutlineView.backgroundColor = .clear
        sourceOutlineView.style = .sourceList
        sourceOutlineView.selectionHighlightStyle = .regular
        sourceOutlineView.allowsEmptySelection = true
        sourceOutlineView.allowsMultipleSelection = false
        sourceOutlineView.indentationPerLevel = LibraryNotesLayout.sourceFolderIndentStep
        sourceOutlineView.rowSizeStyle = .custom
        sourceOutlineView.intercellSpacing = .zero
        sourceOutlineView.floatsGroupRows = false
        sourceOutlineView.delegate = self
        sourceOutlineView.dataSource = self
        sourceOutlineView.registerForDraggedTypes([.fileURL])
        sourceOutlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        sourceOutlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        sourceOutlineView.onNoteKeyCommand = { [weak self] command in
            self?.handleNoteListKeyCommand(command) ?? false
        }
        sourceOutlineView.contextMenuProvider = { [weak self] row in
            self?.sourceContextMenuForLibrary(row: row)
        }
        sourceOutlineView.onPrimaryMouseSelectionCommitted = { [weak self] in
            self?.commitCurrentSourceOutlineSelection()
        }
        sourceOutlineView.onPrimaryMouseSelectionPreviewChanged = { [weak self] in
            guard let self else { return }
            self.refreshVisibleSourceOutlinePresentation()
            self.sourceOutlineView.window?.displayIfNeeded()
        }

        let scrollView = LibrarySourceScrollView()
        scrollView.identifier = NSUserInterfaceItemIdentifier("LibrarySourceScroll")
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.autohidesScrollers = true
        scrollView.documentView = sourceOutlineView
        scrollView.contentInsets = NSEdgeInsets(
            top: LibraryNotesLayout.sourceListTopInset,
            left: LibraryNotesLayout.sourceListLeadingInset,
            bottom: LibraryNotesLayout.sourceListBottomInset,
            right: LibraryNotesLayout.sourceListTrailingInset
        )
        scrollView.scrollerInsets = NSEdgeInsets()
        sourceList.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: sourceList.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: sourceList.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: sourceList.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sourceList.bottomAnchor)
        ])
        rebuildSourceRows(includeTags: sourceTagsLoaded)

        return sourceList
    }

    func buildSidebar() -> NSView {
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false

        configureNoteListHeaderLabels()
        configureSearchScopeControl()

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("library-note"))
        column.width = LibraryNotesLayout.noteTableInitialWidth
        column.minWidth = LibraryNotesLayout.noteTableMinimumWidth
        column.resizingMask = .userResizingMask
        tableView.addTableColumn(column)
        tableView.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTable")
        tableView.setAccessibilityLabel("笔记列表")
        tableView.headerView = nil
        tableView.rowHeight = 68
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.floatsGroupRows = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.selectionHighlightStyle = .regular
        tableView.allowsMultipleSelection = true
        tableView.delegate = self
        tableView.dataSource = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedInSeparateWindow)
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.onKeyCommand = { [weak self] command in
            self?.handleNoteListKeyCommand(command) ?? false
        }
        tableView.onContextMenu = { [weak self] row in
            self?.noteContextMenuForLibrary(row: row)
        }

        let scrollView = LibraryNoteScrollView()
        let clipView = LibraryNoteClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        clipView.drawsBackground = false
        clipView.backgroundColor = .clear
        scrollView.contentView = clipView
        scrollView.documentView = tableView

        noteListEmptyLabel.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListEmptyLabel")
        noteListEmptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        noteListEmptyLabel.textColor = panelTertiaryTextColor()
        noteListEmptyLabel.alignment = .center
        noteListEmptyLabel.lineBreakMode = .byWordWrapping
        noteListEmptyLabel.maximumNumberOfLines = 2
        noteListEmptyLabel.isHidden = true

        let listContainer = NSView()
        listContainer.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListContainer")
        listContainer.addSubview(scrollView)
        listContainer.addSubview(noteListEmptyLabel)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        noteListEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
            noteListEmptyLabel.leadingAnchor.constraint(
                equalTo: listContainer.leadingAnchor,
                constant: LibraryNotesLayout.noteListLeadingInset
            ),
            noteListEmptyLabel.trailingAnchor.constraint(
                equalTo: listContainer.trailingAnchor,
                constant: -LibraryNotesLayout.noteListLeadingInset
            ),
            noteListEmptyLabel.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor, constant: -20)
        ])

        let listHeaderSpacer = NSView()
        listHeaderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        sidebarListHeaderContent.orientation = .horizontal
        sidebarListHeaderContent.spacing = 6
        [noteListTitleLabel, noteListCountLabel, searchScopeControl].forEach {
            sidebarListHeaderContent.addArrangedSubview($0)
        }
        sidebarAllNotesButton.title = "全部笔记"
        sidebarAllNotesButton.font = .systemFont(ofSize: 12, weight: .medium)
        sidebarAllNotesButton.isBordered = false
        sidebarAllNotesButton.contentTintColor = .secondaryLabelColor
        sidebarAllNotesButton.target = self
        sidebarAllNotesButton.action = #selector(showAllNotesPressed)
        sidebarAllNotesButton.identifier = NSUserInterfaceItemIdentifier("LibraryReturnToAllNotes")
        sidebarAllNotesButton.toolTip = "显示全部笔记"
        sidebarAllNotesButton.setAccessibilityLabel("显示全部笔记")
        sidebarAllNotesButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
        sidebarAllNotesButton.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let listHeader = NSStackView(views: [
            sidebarAllNotesButton, sidebarListHeaderContent, listHeaderSpacer
        ])
        sidebarHeaderView = listHeader
        listHeader.identifier = NSUserInterfaceItemIdentifier("LibrarySidebarListHeader")
        listHeader.orientation = .horizontal
        listHeader.alignment = .centerY
        listHeader.spacing = 6
        listHeader.edgeInsets = NSEdgeInsets(top: 0, left: 16, bottom: 0, right: 10)
        noteListTitleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        noteListCountLabel.setContentHuggingPriority(.required, for: .horizontal)
        searchScopeControl.setContentHuggingPriority(.required, for: .horizontal)
        listHeader.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let stack = NSStackView(views: [listContainer])
        stack.identifier = NSUserInterfaceItemIdentifier("LibraryNoteListStack")
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(
            top: LibraryNotesLayout.noteListTopInset,
            left: LibraryNotesLayout.noteListLeadingInset,
            bottom: LibraryNotesLayout.noteListBottomInset,
            right: LibraryNotesLayout.noteListTrailingInset
        )
        sidebar.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            stack.topAnchor.constraint(
                equalTo: sidebar.safeAreaLayoutGuide.topAnchor,
                constant: LibraryNotesLayout.noteListStackTopOffset
            ),
            stack.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor)
        ])
        let stackHorizontalInsets = stack.edgeInsets.left + stack.edgeInsets.right
        [listContainer].forEach {
            $0.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -stackHorizontalInsets
            ).isActive = true
        }
        return sidebar
    }

    @objc func showAllNotesPressed() {
        _ = activateSourceScope(.all)
    }

    func updateSidebarScopeButton() {
        sidebarAllNotesButton.isHidden = selectedScope == .all
    }

    func configureGalleryCollectionView() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(
            width: LibraryNotesLayout.galleryItemWidth,
            height: LibraryNotesLayout.galleryItemHeight
        )
        layout.minimumInteritemSpacing = LibraryNotesLayout.galleryInteritemSpacing
        layout.minimumLineSpacing = LibraryNotesLayout.galleryLineSpacing
        layout.sectionInset = NSEdgeInsets(
            top: LibraryNotesLayout.galleryVerticalInset,
            left: LibraryNotesLayout.galleryHorizontalInset,
            bottom: LibraryNotesLayout.galleryVerticalInset,
            right: LibraryNotesLayout.galleryHorizontalInset
        )

        galleryCollectionView.identifier = NSUserInterfaceItemIdentifier("LibraryGalleryCollection")
        galleryCollectionView.setAccessibilityLabel("笔记画廊")
        galleryCollectionView.collectionViewLayout = layout
        galleryCollectionView.backgroundColors = [.clear]
        galleryCollectionView.isSelectable = true
        galleryCollectionView.allowsMultipleSelection = true
        galleryCollectionView.dataSource = self
        galleryCollectionView.delegate = self
        galleryCollectionView.register(
            LibraryGalleryItem.self,
            forItemWithIdentifier: LibraryGalleryItem.identifier
        )
        galleryCollectionView.register(
            LibraryGallerySectionHeaderView.self,
            forSupplementaryViewOfKind: NSCollectionView.elementKindSectionHeader,
            withIdentifier: LibraryGallerySectionHeaderView.identifier
        )
        galleryCollectionView.onKeyCommand = { [weak self] command in
            self?.handleGalleryKeyCommand(command) ?? false
        }
        galleryCollectionView.onContextMenu = { [weak self] indexPath in
            self?.galleryContextMenuForLibrary(at: indexPath)
        }
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(galleryDoubleClicked(_:)))
        doubleClick.numberOfClicksRequired = 2
        galleryCollectionView.addGestureRecognizer(doubleClick)
    }

    func buildEditor() -> NSView {
        let editor = NSView()
        editor.translatesAutoresizingMaskIntoConstraints = false
        editor.wantsLayer = true
        editor.layer?.backgroundColor = LibraryNotesPalette.editorBackground.cgColor

        titleField.identifier = NSUserInterfaceItemIdentifier("LibraryNoteTitleField")
        titleField.setAccessibilityLabel("笔记标题")
        titleField.placeholderString = ""
        titleField.font = .systemFont(ofSize: LibraryNotesLayout.editorTitleFontSize, weight: .bold)
        titleField.textColor = panelPrimaryTextColor()
        titleField.alignment = .left
        titleField.lineBreakMode = .byTruncatingTail
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.focusRingType = .none
        titleField.delegate = self
        titleField.isHidden = true
        titleField.setAccessibilityElement(false)

        statusLabel.identifier = NSUserInterfaceItemIdentifier("LibraryEditorStatusLabel")
        statusLabel.setAccessibilityLabel("编辑时间或保存状态")
        statusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = panelTertiaryTextColor()
        statusLabel.alignment = .right
        statusLabel.lineBreakMode = .byTruncatingTail
        wordCountLabel.setAccessibilityLabel("字数")
        wordCountLabel.font = .monospacedDigitSystemFont(
            ofSize: LibraryNotesLayout.editorStatusFontSize,
            weight: .medium
        )
        wordCountLabel.textColor = panelTertiaryTextColor()
        wordCountLabel.alignment = .right

        configureEditorTextView()
        createdDateLabel.identifier = NSUserInterfaceItemIdentifier("LibraryEditorCreatedDateLabel")
        createdDateLabel.setAccessibilityLabel("创建时间")
        createdDateLabel.font = .systemFont(ofSize: 11, weight: .regular)
        createdDateLabel.textColor = panelTertiaryTextColor()
        createdDateLabel.alignment = .right
        createdDateLabel.lineBreakMode = .byTruncatingTail
        let scrollView = LibraryEditorScrollView()
        let clipView = EditorClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .small
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        clipView.drawsBackground = true
        clipView.backgroundColor = LibraryNotesPalette.editorBackground
        scrollView.contentView = clipView
        scrollView.documentView = editorTextView
        scrollView.contentInsets = NSEdgeInsets(
            top: 0,
            left: 0,
            bottom: 0,
            right: LibraryNotesLayout.editorHorizontalInset
        )
        scrollView.scrollerInsets = NSEdgeInsets()

        let bodyContainer = NSView()
        bodyContainer.identifier = NSUserInterfaceItemIdentifier("LibraryEditorBodyContainer")
        bodyContainer.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -44)
        ])

        let dates = NSStackView(views: [createdDateLabel, statusLabel])
        dates.orientation = .vertical
        dates.alignment = .trailing
        dates.spacing = 2
        bodyContainer.addSubview(dates)
        bodyContainer.addSubview(wordCountLabel)
        dates.translatesAutoresizingMaskIntoConstraints = false
        wordCountLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dates.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -20),
            dates.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -8),
            dates.leadingAnchor.constraint(greaterThanOrEqualTo: wordCountLabel.trailingAnchor, constant: 12),
            wordCountLabel.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 20),
            wordCountLabel.bottomAnchor.constraint(equalTo: dates.bottomAnchor)
        ])

        noteLinksView.onOpen = { [weak self] url in
            self?.openKnowledgeRelation(at: url)
        }
        noteLinksView.onAcceptSuggestion = { [weak self] item in
            self?.acceptKnowledgeSuggestion(item)
        }
        noteLinksView.onGoBack = { [weak self] in
            self?.goBackInKnowledgeRelations()
        }
        noteLinksView.onGoForward = { [weak self] in
            self?.goForwardInKnowledgeRelations()
        }
        noteLinksView.onGenerateHigherLayer = { [weak self] layer in
            self?.generateHigherLayerDraft(targetLayer: layer)
        }
        noteLinksView.onShowGraph = { [weak self] in
            self?.showKnowledgeGraphForLibrary()
        }

        let stack = NSStackView(views: [bodyContainer])
        stack.identifier = NSUserInterfaceItemIdentifier("LibraryEditorStack")
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 0
        stack.setCustomSpacing(8, after: bodyContainer)
        stack.edgeInsets = NSEdgeInsets(
            top: 0,
            left: LibraryNotesLayout.editorHorizontalInset,
            bottom: LibraryNotesLayout.editorBottomInset,
            right: LibraryNotesLayout.editorHorizontalInset
        )

        configureGalleryCollectionView()
        let galleryScrollView = NSScrollView()
        galleryScrollView.identifier = NSUserInterfaceItemIdentifier("LibraryGalleryScroll")
        galleryScrollView.drawsBackground = false
        galleryScrollView.borderType = .noBorder
        galleryScrollView.hasVerticalScroller = true
        galleryScrollView.hasHorizontalScroller = false
        galleryScrollView.autohidesScrollers = true
        galleryScrollView.contentView.drawsBackground = false
        galleryScrollView.documentView = galleryCollectionView

        galleryEmptyLabel.identifier = NSUserInterfaceItemIdentifier("LibraryGalleryEmptyLabel")
        galleryEmptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        galleryEmptyLabel.textColor = panelTertiaryTextColor()
        galleryEmptyLabel.alignment = .center
        galleryEmptyLabel.lineBreakMode = .byWordWrapping
        galleryEmptyLabel.maximumNumberOfLines = 2
        galleryEmptyLabel.isHidden = true

        editor.addSubview(stack)
        editor.addSubview(galleryScrollView)
        editor.addSubview(galleryEmptyLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        galleryScrollView.translatesAutoresizingMaskIntoConstraints = false
        galleryEmptyLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            stack.topAnchor.constraint(equalTo: editor.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            galleryScrollView.leadingAnchor.constraint(equalTo: editor.leadingAnchor),
            galleryScrollView.trailingAnchor.constraint(equalTo: editor.trailingAnchor),
            galleryScrollView.topAnchor.constraint(equalTo: editor.safeAreaLayoutGuide.topAnchor),
            galleryScrollView.bottomAnchor.constraint(equalTo: editor.bottomAnchor),
            galleryEmptyLabel.centerXAnchor.constraint(equalTo: editor.centerXAnchor),
            galleryEmptyLabel.centerYAnchor.constraint(equalTo: editor.centerYAnchor, constant: -20),
            galleryEmptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: editor.leadingAnchor, constant: 24),
            galleryEmptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: editor.trailingAnchor, constant: -24)
        ])
        NSLayoutConstraint.activate([
            bodyContainer.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -LibraryNotesLayout.editorHorizontalInset
            )
        ])
        bodyContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 320).isActive = true

        editorStackView = stack
        pinnedRelationsWidthConstraint = noteLinksView.widthAnchor.constraint(
            equalTo: stack.widthAnchor, constant: -(LibraryNotesLayout.editorHorizontalInset * 2)
        )
        editorTextView.addSubview(noteLinksView)
        noteLinksView.onPinChanged = { [weak self] pinned in
            guard let self, let stack = self.editorStackView else { return }
            self.pinnedRelationsWidthConstraint?.isActive = false
            if stack.arrangedSubviews.contains(self.noteLinksView) {
                stack.removeArrangedSubview(self.noteLinksView)
            }
            self.noteLinksView.removeFromSuperview()
            if pinned {
                self.noteLinksView.translatesAutoresizingMaskIntoConstraints = false
                stack.addArrangedSubview(self.noteLinksView)
                self.pinnedRelationsWidthConstraint?.isActive = true
            } else {
                self.noteLinksView.translatesAutoresizingMaskIntoConstraints = true
                self.editorTextView.addSubview(self.noteLinksView)
            }
            self.layoutEditorStatusLabel()
        }
        noteLinksView.onLayoutChanged = { [weak self] in self?.layoutEditorStatusLabel() }
        self.galleryScrollView = galleryScrollView
        stack.isHidden = noteListViewMode == .gallery
        galleryScrollView.isHidden = noteListViewMode != .gallery

        return editor
    }

    func buildDocumentTabHeader() -> NSView {
        documentTabsStack.orientation = .horizontal
        documentTabsStack.alignment = .centerY
        documentTabsStack.spacing = 1

        let scrollView = NSScrollView()
        scrollView.identifier = NSUserInterfaceItemIdentifier("LibraryDocumentTabs")
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = documentTabsStack
        documentTabsStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            documentTabsStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentTabsStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentTabsStack.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
        let preferredWidth = scrollView.widthAnchor.constraint(equalToConstant: 96)
        preferredWidth.priority = .defaultHigh
        preferredWidth.isActive = true
        documentTabsWidthConstraint = preferredWidth

        let addButton = NSButton(
            image: NSImage(systemSymbolName: "plus", accessibilityDescription: "新标签页")!,
            target: self,
            action: #selector(newDocumentTabPressed)
        )
        addButton.identifier = NSUserInterfaceItemIdentifier("LibraryNewDocumentTab")
        addButton.isBordered = false
        addButton.contentTintColor = .secondaryLabelColor
        addButton.image = addButton.image?.withSymbolConfiguration(.init(pointSize: 12, weight: .regular))
        addButton.toolTip = "新标签页"
        addButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            addButton.widthAnchor.constraint(equalToConstant: 28),
            addButton.heightAnchor.constraint(equalToConstant: 28)
        ])

        let header = NSStackView(views: [scrollView, addButton])
        header.identifier = NSUserInterfaceItemIdentifier("LibraryDocumentTabHeader")
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 2
        NSLayoutConstraint.activate([
            header.heightAnchor.constraint(equalToConstant: 30)
        ])
        updateDocumentTabBar()
        return header
    }

    func updateDocumentTabBar() {
        guard !documentTabs.isEmpty else { return }
        let activeID = activeDocumentTab.id
        let signature = documentTabs.map {
            "\($0.id):\($0.url?.path ?? ""):\($0.title):\($0.isDirty):\($0.id == activeID)"
        }.joined(separator: "|")
        guard signature != documentTabBarSignature else { return }
        documentTabBarSignature = signature
        let tabWidths = documentTabs.map {
            LibraryDocumentTabView.preferredWidth(title: $0.title, isDirty: $0.isDirty)
        }
        documentTabsWidthConstraint?.constant = min(
            tabWidths.reduce(0, +) + CGFloat(max(0, documentTabs.count - 1)) * documentTabsStack.spacing,
            480
        )
        documentTabsStack.arrangedSubviews.forEach {
            documentTabsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for tab in documentTabs {
            let tabView = LibraryDocumentTabView(tab: tab, selected: tab.id == activeID)
            tabView.onSelect = { [weak self] in self?.activateDocumentTab(tab.id) }
            tabView.onClose = { [weak self] in self?.closeDocumentTab(tab.id) }
            documentTabsStack.addArrangedSubview(tabView)
        }
        documentTabsStack.layoutSubtreeIfNeeded()
        if let selectedView = documentTabsStack.arrangedSubviews.first(where: {
            ($0 as? LibraryDocumentTabView)?.tabID == activeID
        }) {
            selectedView.scrollToVisible(selectedView.bounds)
        }
    }

    @objc func newDocumentTabPressed() {
        do {
            drainBackgroundAutosaves()
            try saveCurrentNoteIfNeeded()
            activeDocumentTab.url = selectedURL
            activeDocumentTab.isDirty = false
            let tab = LibraryDocumentTab()
            documentTabs.append(tab)
            activateDocumentTab(tab.id)
        } catch {
            presentErrorAlert(message: "无法新建标签页", details: error.localizedDescription)
        }
    }

    func activateDocumentTab(_ id: UUID, capturesCurrentDocument: Bool = true) {
        guard let tab = documentTabs.first(where: { $0.id == id }),
              activeDocumentTabID != tab.id else { return }
        if capturesCurrentDocument {
            do {
                drainBackgroundAutosaves()
                try saveCurrentNoteIfNeeded()
            } catch {
                presentErrorAlert(message: "无法切换标签页", details: error.localizedDescription)
                return
            }
            activeDocumentTab.url = selectedURL
            activeDocumentTab.isDirty = false
        }
        activeDocumentTabID = tab.id
        cancelActiveNoteLoad()
        if let url = tab.url {
            let note = sourceCountSnapshot.first {
                $0.url.standardizedFileURL == url.standardizedFileURL
            } ?? NoteSearchResult(
                url: url,
                title: tab.title,
                snippet: "",
                modifiedAt: Date()
            )
            isActivatingDocumentTab = true
            load(note: note)
            isActivatingDocumentTab = false
        } else {
            isCreatingNewNote = true
            setSelectedURLForLibrary(nil)
            selectedSourceContents = nil
            selectedTags = []
            noteLinksView.update(.empty)
            setEditorEditable(true)
            applyDocument(title: "", body: "", tags: [])
            isDirty = false
            updateEditorStatus("")
        }
        updateDocumentTabBar()
        window?.makeFirstResponder(editorTextView)
    }

    func prepareDocumentTab(for note: NoteSearchResult) -> Bool {
        guard !isActivatingDocumentTab else { return false }
        if let existing = documentTabs.first(where: {
            $0.url?.standardizedFileURL == note.url.standardizedFileURL
        }), existing.id != activeDocumentTab.id {
            activateDocumentTab(existing.id)
            return true
        }
        // Commit tab identity together with the successfully loaded document.
        return false
    }

    func closeDocumentTab(_ id: UUID) {
        guard let index = documentTabs.firstIndex(where: { $0.id == id }) else { return }
        if documentTabs[index].id == activeDocumentTab.id {
            do {
                drainBackgroundAutosaves()
                try saveCurrentNoteIfNeeded()
            } catch {
                presentErrorAlert(message: "无法关闭标签页", details: error.localizedDescription)
                return
            }
        }
        let wasActive = documentTabs[index].id == activeDocumentTab.id
        if documentTabs.count == 1 {
            documentTabs.append(LibraryDocumentTab())
        }
        let nextID = wasActive
            ? documentTabs[index + 1 < documentTabs.count ? index + 1 : index - 1].id
            : nil
        documentTabs.remove(at: index)
        if let nextID {
            activateDocumentTab(nextID, capturesCurrentDocument: false)
        } else {
            updateDocumentTabBar()
        }
    }

    func configureEditorTextView() {
        editorTextView.setAccessibilityLabel("笔记内容")
        editorTextView.onAddMetadataTag = { [weak self] in self?.addSelectedNoteTagPressed() }
        editorTextView.commandDelegate = self
        editorTextView.delegate = self
        editorTextView.markdownPasteTheme = theme
        editorTextView.configureContextMenu = { [weak self] menu, _ in
            self?.configureEditorInsertContextMenu(menu)
        }
        editorTextView.contextMenuOptionsProvider = { [weak self] in
            self?.noteStore.enabledEditorContextMenuOptions ?? Set(EditorContextMenuOption.allCases)
        }
        editorTextView.onImageDisplayWidthChanged = { [weak self] fileURL, width in
            self?.noteStore.setLibraryImageDisplayWidth(width, for: fileURL)
        }
        editorTextView.imageDisplayWidthProvider = { [weak self] fileURL in
            self?.noteStore.libraryImageDisplayWidth(for: fileURL)
        }
        editorTextView.selectionMenuProvider = { [weak self] in
            self?.makeSelectionFormattingMenuForLibrary()
        }
        editorTextView.onTextInputStateChanged = { [weak self] in
            self?.updateEditorSlashSuggestions()
        }
        editorTextView.isRichText = true
        editorTextView.importsGraphics = false
        editorTextView.usesFontPanel = false
        editorTextView.isAutomaticDataDetectionEnabled = false
        editorTextView.isAutomaticQuoteSubstitutionEnabled = false
        editorTextView.isAutomaticDashSubstitutionEnabled = false
        editorTextView.isAutomaticTextReplacementEnabled = false
        editorTextView.isContinuousSpellCheckingEnabled = noteStore.spellCheckingEnabled
        editorTextView.allowsUndo = true
        editorTextView.font = theme.bodyFont
        editorTextView.backgroundColor = .clear
        editorTextView.drawsBackground = false
        editorTextView.textColor = theme.textColor
        editorTextView.insertionPointColor = theme.accentColor
        editorTextView.selectedTextAttributes = [
            .backgroundColor: theme.accentColor.withAlphaComponent(0.24)
        ]
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainerInset = NSSize(
            width: LibraryNotesLayout.editorTextContainerHorizontalInset,
            height: 14
        )
        editorTextView.textContainer?.lineFragmentPadding = 0
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)
        editorSuggestionController.view.identifier = NSUserInterfaceItemIdentifier(
            "LibraryEditorSlashSuggestionPopover"
        )
        editorSuggestionController.view.isHidden = true
        editorSuggestionController.view.translatesAutoresizingMaskIntoConstraints = true
        editorSuggestionController.onSelect = { [weak self] index in
            self?.acceptEditorSlashSuggestion(at: index)
        }
    }

    func hostEditorSuggestionView(in host: NSView) {
        let suggestionView = editorSuggestionController.view
        guard suggestionView.superview !== host else { return }
        suggestionView.removeFromSuperview()
        host.addSubview(suggestionView, positioned: .above, relativeTo: nil)
    }
}
