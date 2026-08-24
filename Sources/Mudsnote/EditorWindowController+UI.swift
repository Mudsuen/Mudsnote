import AppKit
import MudsnoteCore

extension EditorWindowController {

    // MARK: - Main build

    func buildUI() {
        guard let contentView = window?.contentView else { return }

        let backdrop = GradientBackdropView(frame: contentView.bounds, panelOpacity: currentPanelOpacity)
        backdrop.chromeStyle = isQuickCaptureMode ? .minimal : .standard
        contentView.addSubview(backdrop)
        pin(backdrop, to: contentView)
        backdropView = backdrop

        let shellContent = WindowMoveBackgroundView()
        shellContent.wantsLayer = true
        shellContent.layer = CALayer()
        shellContent.layer?.masksToBounds = false
        backdrop.addSubview(shellContent)
        let shellInsets = isQuickCaptureMode
            ? NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            : NSEdgeInsets(top: 10, left: 12, bottom: 0, right: 12)
        pin(shellContent, to: backdrop, insets: shellInsets)
        shellContentView = shellContent

        editorTextView.commandDelegate = self
        editorTextView.delegate = self
        editorTextView.markdownPasteTheme = theme
        editorTextView.configureContextMenu = nil
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
            self?.makeSelectionFormattingMenu()
        }
        editorTextView.onTextInputStateChanged = { [weak self] in
            self?.refreshChrome()
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
        editorTextView.textColor = theme.textColor
        editorTextView.insertionPointColor = theme.accentColor
        editorTextView.selectedTextAttributes = [
            .backgroundColor: theme.accentColor.withAlphaComponent(0.24)
        ]
        editorTextView.drawsBackground = false
        editorTextView.isVerticallyResizable = true
        editorTextView.isHorizontallyResizable = false
        editorTextView.textContainerInset = isQuickCaptureMode ? NSSize(width: 2, height: 8) : NSSize(width: 4, height: 2)
        editorTextView.textContainer?.lineFragmentPadding = 0
        editorTextView.typingAttributes = theme.baseAttributes(for: .paragraph)

        let scrollView = EditorScrollView()
        let clipView = EditorClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = editorTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        editorTextView.postsFrameChangedNotifications = true

        let overlayScrollIndicator = ScrollIndicatorOverlay()
        overlayScrollIndicator.translatesAutoresizingMaskIntoConstraints = false
        overlayScrollIndicator.attach(to: scrollView)
        self.overlayScrollIndicator = overlayScrollIndicator

        let toolbarStack = NSStackView()
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.spacing = toolbarButtonSpacing
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false
        toolbarStack.setContentHuggingPriority(.required, for: .horizontal)
        toolbarStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        toolbarButtons.removeAll()
        toolbarButtonsByAction.removeAll()
        saveButton = nil
        cancelButton = nil
        quickCaptureDirectoryButton = nil
        quickCapturePlaceholderBodyLabel = nil
        floatingNotePlaceholderLabel = nil
        floatingNoteTitlebarView = nil
        floatingNoteBrowseButton = nil
        floatingNoteTitlebarChromeViews.removeAll()

        if isQuickCaptureMode {
            buildQuickCaptureUI(in: shellContent, backdrop: backdrop, scrollView: scrollView, overlayScrollIndicator: overlayScrollIndicator)
        } else {
            buildStandardEditorUI(in: shellContent, backdrop: backdrop, scrollView: scrollView, overlayScrollIndicator: overlayScrollIndicator, toolbarStack: toolbarStack)
        }

        refreshChrome()
        updatePanelOpacity(currentPanelOpacity)
        updateWindowFocusAppearance(isFocused: true)
        updateToolbarSelectionState()

        let suggestionView = suggestionController.view
        suggestionView.isHidden = true
        suggestionView.translatesAutoresizingMaskIntoConstraints = true
        contentView.addSubview(suggestionView, positioned: .above, relativeTo: nil)
    }

    func updateEditorPreferences(spellCheckingEnabled: Bool) {
        editorTextView.isContinuousSpellCheckingEnabled = spellCheckingEnabled
    }

    // MARK: - Standard editor UI

    func buildStandardEditorUI(
        in shellContent: NSView,
        backdrop: GradientBackdropView,
        scrollView: NSScrollView,
        overlayScrollIndicator: ScrollIndicatorOverlay,
        toolbarStack: NSStackView
    ) {
        let topDragBar: WindowMoveBackgroundView = isFloatingNoteMode ? HoverRevealTitlebarView() : DragHandleView()
        topDragBar.translatesAutoresizingMaskIntoConstraints = false
        floatingNoteTitlebarView = isFloatingNoteMode ? topDragBar : nil

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.alphaValue = 0.78

        let topDivider = NSBox()
        topDivider.boxType = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        topDivider.alphaValue = 0.72

        if !isFloatingNoteMode {
            ToolbarAction.allCases.forEach { action in
                let button = makeToolbarButton(for: action)
                toolbarButtons.append(button)
                toolbarButtonsByAction[action] = button
                toolbarStack.addArrangedSubview(button)
            }
        }

        let toolbarWidth = (CGFloat(ToolbarAction.allCases.count) * toolbarButtonWidth)
            + (CGFloat(max(ToolbarAction.allCases.count - 1, 0)) * toolbarButtonSpacing)
        toolbarStack.widthAnchor.constraint(equalToConstant: toolbarWidth).isActive = true

        let footerBar: NSView?
        if isFloatingNoteMode {
            footerBar = nil
        } else {
            let view = NSView()
            view.translatesAutoresizingMaskIntoConstraints = false
            shellContent.addSubview(view)
            footerBar = view
        }

        if isFloatingNoteMode {
            let browseButton = makeFloatingHeaderButton(
                symbolName: "rectangle.stack",
                toolTip: "管理悬浮笔记",
                action: #selector(floatingBrowseNotesPressed(_:))
            )
            floatingNoteBrowseButton = browseButton
            let buttonHost = window?.contentView ?? backdrop
            buttonHost.addSubview(browseButton, positioned: .above, relativeTo: nil)
            NSLayoutConstraint.activate([
                browseButton.trailingAnchor.constraint(equalTo: buttonHost.trailingAnchor, constant: -20),
                browseButton.topAnchor.constraint(equalTo: buttonHost.topAnchor, constant: 8)
            ])
            floatingNoteTitlebarChromeViews.append(browseButton)
            setFloatingNoteTitlebarChromeVisible(true)
        }

        if let footerBar {
            wordCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            wordCountLabel.textColor = panelTertiaryTextColor()
            wordCountLabel.alignment = .right
            wordCountLabel.setAccessibilityLabel("字数")
            wordCountLabel.translatesAutoresizingMaskIntoConstraints = false
            footerBar.addSubview(wordCountLabel)
            wordCountLabel.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor).isActive = true
            wordCountLabel.widthAnchor.constraint(equalToConstant: 54).isActive = true
            if showsSaveButton {
                let saveButton = makePrimarySaveButton()
                let saveButtonWidth = ceil(saveButton.intrinsicContentSize.width) + 6
                saveButton.widthAnchor.constraint(equalToConstant: saveButtonWidth).isActive = true
                saveButton.heightAnchor.constraint(equalToConstant: toolbarButtonHeight).isActive = true
                self.saveButton = saveButton
                footerBar.addSubview(toolbarStack)
                footerBar.addSubview(saveButton)
                NSLayoutConstraint.activate([
                    toolbarStack.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: footerEdgeInset),
                    toolbarStack.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
                    saveButton.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -footerEdgeInset),
                    saveButton.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
                    wordCountLabel.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),
                    wordCountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarStack.trailingAnchor, constant: 8)
                ])
            } else {
                footerBar.addSubview(toolbarStack)
                NSLayoutConstraint.activate([
                    toolbarStack.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: footerEdgeInset),
                    toolbarStack.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
                    wordCountLabel.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -footerEdgeInset),
                    wordCountLabel.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarStack.trailingAnchor, constant: 8)
                ])
            }
        }

        let floatingPlaceholderOverlay = PassthroughOverlayView()
        floatingPlaceholderOverlay.translatesAutoresizingMaskIntoConstraints = false

        let floatingPlaceholderLabel = NSTextField(labelWithString: "写点什么")
        floatingPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        floatingPlaceholderLabel.font = .systemFont(ofSize: 14, weight: .regular)
        floatingPlaceholderLabel.textColor = panelTertiaryTextColor()
        floatingPlaceholderOverlay.addSubview(floatingPlaceholderLabel)
        floatingNotePlaceholderLabel = floatingPlaceholderLabel

        shellContent.addSubview(topDragBar)
        if !isFloatingNoteMode {
            shellContent.addSubview(topDivider)
        }
        shellContent.addSubview(scrollView)
        if isFloatingNoteMode {
            shellContent.addSubview(floatingPlaceholderOverlay)
        }
        backdrop.addSubview(overlayScrollIndicator)
        if footerBar != nil {
            shellContent.addSubview(divider)
        }

        var constraints: [NSLayoutConstraint] = [
            scrollView.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),

            overlayScrollIndicator.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -2),
            overlayScrollIndicator.topAnchor.constraint(equalTo: scrollView.topAnchor),
            overlayScrollIndicator.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            overlayScrollIndicator.widthAnchor.constraint(equalToConstant: 8),
            scrollView.trailingAnchor.constraint(equalTo: overlayScrollIndicator.leadingAnchor, constant: -4),

            topDragBar.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 2),
            topDragBar.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -8),
            topDragBar.topAnchor.constraint(equalTo: shellContent.topAnchor),
            topDragBar.heightAnchor.constraint(equalToConstant: isFloatingNoteMode ? 22 : 15),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: showsSaveButton ? 214 : 216)
        ]

        if let footerBar {
            constraints.append(contentsOf: [
                scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: showsSaveButton ? -4 : -2),
                divider.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor),
                divider.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor),
                divider.bottomAnchor.constraint(equalTo: footerBar.topAnchor),
                footerBar.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),
                footerBar.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor),
                footerBar.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor),
                footerBar.heightAnchor.constraint(equalToConstant: toolbarButtonHeight)
            ])
        } else {
            constraints.append(
                scrollView.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor)
            )
        }

        if isFloatingNoteMode {
            constraints.append(contentsOf: [
                scrollView.topAnchor.constraint(equalTo: topDragBar.bottomAnchor),

                floatingPlaceholderOverlay.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
                floatingPlaceholderOverlay.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
                floatingPlaceholderOverlay.topAnchor.constraint(equalTo: scrollView.topAnchor),
                floatingPlaceholderOverlay.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

                floatingPlaceholderLabel.leadingAnchor.constraint(equalTo: floatingPlaceholderOverlay.leadingAnchor, constant: 4),
                floatingPlaceholderLabel.topAnchor.constraint(equalTo: floatingPlaceholderOverlay.topAnchor, constant: 8)
            ])
        } else {
            constraints.append(contentsOf: [
                scrollView.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 4),

                topDivider.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 2),
                topDivider.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -2),
                topDivider.topAnchor.constraint(equalTo: topDragBar.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate(constraints)
    }

    // MARK: - Quick capture UI

    func buildQuickCaptureUI(
        in shellContent: NSView,
        backdrop: GradientBackdropView,
        scrollView: NSScrollView,
        overlayScrollIndicator: ScrollIndicatorOverlay
    ) {
        let bodyContainer = SubviewPassthroughView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        shellContent.addSubview(bodyContainer)

        let dragHandle = DragHandleView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(dragHandle)

        let bodyPlaceholderOverlay = PassthroughOverlayView()
        bodyPlaceholderOverlay.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(bodyPlaceholderOverlay)

        let bodyLabel = NSTextField(labelWithString: "开始输入笔记…")
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = panelTertiaryTextColor()
        bodyPlaceholderOverlay.addSubview(bodyLabel)
        quickCapturePlaceholderBodyLabel = bodyLabel

        let footerShelf = NSVisualEffectView()
        footerShelf.translatesAutoresizingMaskIntoConstraints = false
        footerShelf.material = .headerView
        footerShelf.state = .active
        footerShelf.blendingMode = .withinWindow
        footerShelf.wantsLayer = true
        footerShelf.layer?.masksToBounds = true
        footerShelf.layer?.cornerRadius = 0
        shellContent.addSubview(footerShelf)

        let footerDivider = NSBox()
        footerDivider.boxType = .separator
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footerShelf.addSubview(footerDivider)

        let directoryButton = FocusAwareGhostButton(frame: .zero)
        directoryButton.translatesAutoresizingMaskIntoConstraints = false
        directoryButton.title = ""
        directoryButton.target = self
        directoryButton.action = #selector(quickCaptureDirectoryPressed)
        directoryButton.setButtonType(.momentaryChange)
        directoryButton.font = .systemFont(ofSize: 13, weight: .semibold)
        directoryButton.image = NSImage(systemSymbolName: "tray.full", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        directoryButton.imagePosition = .imageLeading
        directoryButton.imageHugsTitle = true
        directoryButton.controlSize = .regular
        directoryButton.usesSubtlePressFeedback = true
        directoryButton.setAccessibilityIdentifier("QuickCaptureDestinationButton")
        (directoryButton.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        footerShelf.addSubview(directoryButton)
        quickCaptureDirectoryButton = directoryButton

        let cancelButton = makeQuickCaptureFooterButton(
            symbolName: "xmark",
            toolTip: "取消",
            action: #selector(cancelPressed),
            symbolWeight: .medium
        )
        footerShelf.addSubview(cancelButton)
        toolbarButtons.append(cancelButton)
        self.cancelButton = cancelButton

        let saveButton = makeQuickCaptureFooterButton(
            symbolName: "checkmark",
            toolTip: "保存",
            action: #selector(savePressed),
            symbolWeight: .semibold
        )
        footerShelf.addSubview(saveButton)
        toolbarButtons.append(saveButton)
        self.saveButton = saveButton

        bodyContainer.addSubview(scrollView, positioned: .below, relativeTo: nil)
        backdrop.addSubview(overlayScrollIndicator)

        NSLayoutConstraint.activate([
            bodyContainer.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor),
            bodyContainer.topAnchor.constraint(equalTo: shellContent.topAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: footerShelf.topAnchor),

            dragHandle.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 18),
            dragHandle.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -18),
            dragHandle.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: 6),
            dragHandle.heightAnchor.constraint(equalToConstant: 16),

            scrollView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 18),
            scrollView.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -12),

            overlayScrollIndicator.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -10),
            overlayScrollIndicator.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 6),
            overlayScrollIndicator.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -6),
            overlayScrollIndicator.widthAnchor.constraint(equalToConstant: 8),
            scrollView.trailingAnchor.constraint(equalTo: overlayScrollIndicator.leadingAnchor, constant: -8),

            bodyPlaceholderOverlay.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            bodyPlaceholderOverlay.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            bodyPlaceholderOverlay.topAnchor.constraint(equalTo: scrollView.topAnchor),
            bodyPlaceholderOverlay.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),

            bodyLabel.leadingAnchor.constraint(equalTo: bodyPlaceholderOverlay.leadingAnchor, constant: 20),
            bodyLabel.topAnchor.constraint(equalTo: bodyPlaceholderOverlay.topAnchor, constant: 8),

            footerShelf.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),
            footerShelf.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor),
            footerShelf.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor),
            footerShelf.heightAnchor.constraint(equalToConstant: 36),

            footerDivider.leadingAnchor.constraint(equalTo: footerShelf.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: footerShelf.trailingAnchor),
            footerDivider.topAnchor.constraint(equalTo: footerShelf.topAnchor),

            directoryButton.leadingAnchor.constraint(equalTo: footerShelf.leadingAnchor, constant: 10),
            directoryButton.centerYAnchor.constraint(equalTo: footerShelf.centerYAnchor),
            directoryButton.heightAnchor.constraint(equalToConstant: 28),

            saveButton.trailingAnchor.constraint(equalTo: footerShelf.trailingAnchor, constant: -10),
            saveButton.centerYAnchor.constraint(equalTo: footerShelf.centerYAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -2),
            cancelButton.centerYAnchor.constraint(equalTo: footerShelf.centerYAnchor),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 176)
        ])
    }

    // MARK: - Button factories

    func makePrimarySaveButton() -> FocusAwareAccentButton {
        let saveButton = FocusAwareAccentButton(frame: .zero)
        saveButton.title = "保存"
        saveButton.target = self
        saveButton.action = #selector(savePressed)
        saveButton.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        saveButton.image?.isTemplate = true
        saveButton.imagePosition = .imageLeading
        saveButton.imageHugsTitle = true
        saveButton.controlSize = .small
        saveButton.font = .systemFont(ofSize: 11, weight: .semibold)
        saveButton.controlSize = .small
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.setContentHuggingPriority(.required, for: .horizontal)
        return saveButton
    }

    func makeQuickCaptureFooterButton(
        symbolName: String,
        toolTip: String,
        action: Selector,
        symbolWeight: NSFont.Weight
    ) -> HoverToolbarButton {
        let button = HoverToolbarButton(frame: .zero)
        button.title = ""
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 12, weight: symbolWeight))
        button.imagePosition = .imageOnly
        button.preferredSize = NSSize(width: 28, height: 28)
        button.usesSubtlePressFeedback = true
        button.setAccessibilityIdentifier("QuickCapture\(toolTip)Button")
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    func makeToolbarButton(for action: ToolbarAction) -> HoverToolbarButton {
        let button = HoverToolbarButton(frame: .zero)
        button.title = action.title ?? ""
        button.target = self
        button.action = #selector(toolbarButtonPressed(_:))
        button.onMouseDown = { [weak self] in
            self?.focusEditorForToolbarAction()
        }
        button.performsActionOnMouseDown = true
        button.tag = action.rawValue
        button.toolTip = action.toolTip
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.preferredSize = NSSize(width: toolbarButtonWidth, height: toolbarButtonVisualHeight)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: toolbarButtonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: toolbarButtonVisualHeight).isActive = true

        if let symbolName = action.symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: action.toolTip)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
            button.imagePosition = .imageOnly
        }
        return button
    }

    func makeFloatingHeaderButton(
        symbolName: String,
        toolTip: String,
        action: Selector
    ) -> HoverToolbarButton {
        let button = HoverToolbarButton(frame: .zero)
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: toolTip)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .semibold))
        button.imagePosition = .imageOnly
        button.title = ""
        button.setAccessibilityIdentifier("FloatingNoteManagerButton")
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.focusRingType = .none
        button.contentTintColor = NSColor.white.withAlphaComponent(0.74)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    @objc func floatingPreferencesPressed(_ sender: Any?) {
        onRequestPreferences()
    }

    @objc func floatingBrowseNotesPressed(_ sender: Any?) {
        showFloatingNoteBrowser(relativeTo: (sender as? NSView) ?? floatingNoteBrowseButton)
    }

    func setFloatingNoteTitlebarChromeVisible(_ isVisible: Bool) {
        floatingNoteTitlebarChromeViews.forEach { view in
            view.alphaValue = isVisible ? 1 : 0
        }
    }

    // MARK: - Observer and content setup

    func configureSuggestionPopover() {
        suggestionController.onSelect = { [weak self] index in
            self?.acceptInlineSuggestion(at: index)
        }
    }

    func configureObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: NSText.didChangeNotification, object: editorTextView, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.userDidEdit() }
            }
        )
        if let contentView = editorTextView.enclosingScrollView?.contentView {
            observers.append(
                center.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: nil) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.overlayScrollIndicator?.updateIndicator() }
                }
            )
        }
        observers.append(
            center.addObserver(forName: NSView.frameDidChangeNotification, object: editorTextView, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in self?.overlayScrollIndicator?.updateIndicator() }
            }
        )
        observers.append(
            center.addObserver(forName: NSTextView.didChangeSelectionNotification, object: editorTextView, queue: nil) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.rememberEditorSelectionForToolbarActions()
                    self?.updateTypingAttributesFromInsertionPoint()
                    self?.updateToolbarSelectionState()
                    self?.updateInlineSuggestions()
                }
            }
        )
    }

    func loadInitialContent() {
        suppressAutosave = true
        defer { suppressAutosave = false }

        var title = ""
        var body = ""
        if let fileURL {
            do {
                let note = try noteStore.loadNoteDocument(at: fileURL)
                title = note.title
                let migration = MarkdownEditorDocument.extractingInlineTags(from: note.body)
                body = migration.body
                activeTags = MarkdownEditorDocument.normalizedTags(
                    note.tags + migration.tags
                )
                sourceContentsAtLoad = note.sourceContents
                isDirty = migration.occurrenceCount > 0
            } catch {
                presentErrorAlert(message: "无法加载笔记", details: error.localizedDescription)
            }
        }

        applyInitialContent(title: title, body: body)

        if let draft = noteStore.loadDraft(id: currentDraftID) {
            let migration = MarkdownEditorDocument.extractingInlineTags(from: draft.body)
            activeTags = MarkdownEditorDocument.normalizedTags(
                draft.tags + migration.tags
            )
            applyInitialContent(title: draft.title, body: migration.body)
            selectedDirectoryURL = URL(fileURLWithPath: draft.selectedDirectoryPath, isDirectory: true)
            isDirty = true
            statusLabel.stringValue = "已恢复"
        } else {
            statusLabel.stringValue = fileURL == nil ? "Markdown" : "编辑中"
        }

        refreshChrome()
        updateWordCount()
        overlayScrollIndicator?.updateIndicator()
        updateTypingAttributesFromInsertionPoint()
        updateToolbarSelectionState()
        updateInlineSuggestions()
    }

    func applyInitialContent(title: String, body: String) {
        if isQuickCaptureMode {
            hasAutomaticTitleFormatting = false
            applyBodyMarkdown(QuickCaptureDocumentState.unifiedMarkdown(
                legacyTitle: title,
                bodyMarkdown: body
            ))
            return
        }
        guard isFloatingNoteMode else {
            hasAutomaticTitleFormatting = false
            applyBodyMarkdown(MarkdownEditorDocument.composeEditorText(
                title: title,
                body: body,
                hasMetadataTags: !activeTags.isEmpty
            ))
            return
        }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        hasAutomaticTitleFormatting = !trimmedTitle.isEmpty && trimmedBody.isEmpty
        if hasAutomaticTitleFormatting {
            applyBodyMarkdown("# \(trimmedTitle)")
        } else {
            let separator = activeTags.isEmpty ? "\n\n" : "\n"
            applyBodyMarkdown(
                [trimmedTitle, trimmedBody]
                    .filter { !$0.isEmpty }
                    .joined(separator: separator)
            )
        }
    }

    func applyBodyMarkdown(_ markdown: String) {
        suppressTextDidChange = true
        let rendered = MarkdownRichTextCodec.render(
            markdown: markdown,
            theme: theme,
            baseURL: activeFloatingNoteURL ?? fileURL,
            imageDisplayWidthProvider: noteStore.libraryImageDisplayWidth(for:)
        )
        editorTextView.textStorage?.setAttributedString(rendered)
        suppressTextDidChange = false
    }

    // MARK: - Chrome refresh

    func refreshChrome() {
        refreshTrackedTags()
        refreshFloatingNoteChrome()
        refreshQuickCaptureChrome()
    }

    func refreshFloatingNoteChrome() {
        guard isFloatingNoteMode else { return }

        let document = currentDocument()
        floatingNotePlaceholderLabel?.isHidden = !document.title.isEmpty || !document.body.isEmpty || editorTextView.hasMarkedText()
    }

    func refreshQuickCaptureChrome() {
        guard isQuickCaptureMode else { return }

        let state = QuickCaptureDocumentState(
            title: "",
            bodyMarkdown: serializedBodyMarkdown()
        )
        let bodyHasMarkedText = editorTextView.hasMarkedText()

        quickCapturePlaceholderBodyLabel?.isHidden = !state.normalizedBody.isEmpty || bodyHasMarkedText

        let destinationTitle = quickCaptureDestinationTitle()
        quickCaptureDirectoryButton?.title = destinationTitle
        quickCaptureDirectoryButton?.toolTip = displayPath(selectedDirectoryURL)
        (quickCaptureDirectoryButton as? FocusAwareGhostButton)?.updateAppearance()
    }

    func quickCaptureDestinationTitle() -> String {
        quickCaptureFolderDisplayName(for: selectedDirectoryURL)
    }

    func quickCaptureFolderDisplayName(for directory: URL) -> String {
        let name = directory.standardizedFileURL.lastPathComponent
        let withoutPrefix = name.replacingOccurrences(of: #"^\d+[_-]+"#, with: "", options: .regularExpression)
        return withoutPrefix.isEmpty ? displayPath(directory) : withoutPrefix
    }

    func updateWindowFocusAppearance(isFocused: Bool) {
        toolbarButtons.forEach { $0.isWindowFocused = isFocused }
        (saveButton as? ModernPillButton)?.isWindowFocused = isFocused
        (cancelButton as? ModernPillButton)?.isWindowFocused = isFocused
        (quickCaptureDirectoryButton as? FocusAwareGhostButton)?.isWindowFocused = isFocused
        statusLabel.textColor = isFocused ? panelSecondaryTextColor() : panelTertiaryTextColor()
    }
}
