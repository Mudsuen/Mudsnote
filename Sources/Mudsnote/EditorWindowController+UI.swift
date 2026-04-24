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
        editorTextView.isContinuousSpellCheckingEnabled = true
        editorTextView.allowsUndo = true
        editorTextView.font = theme.bodyFont
        editorTextView.backgroundColor = .clear
        editorTextView.textColor = theme.textColor
        editorTextView.insertionPointColor = theme.accentColor
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
        quickCaptureButtonsByAction.removeAll()
        saveButton = nil
        cancelButton = nil
        quickCaptureDirectoryButton = nil
        quickCaptureTitleHost = nil
        quickCaptureTitleTextView = nil
        quickCaptureTitlePlaceholderLabel = nil
        quickCapturePlaceholderBodyLabel = nil
        quickCaptureTagButton = nil

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
        shellContent.addSubview(suggestionView)
    }

    // MARK: - Standard editor UI

    func buildStandardEditorUI(
        in shellContent: NSView,
        backdrop: GradientBackdropView,
        scrollView: NSScrollView,
        overlayScrollIndicator: ScrollIndicatorOverlay,
        toolbarStack: NSStackView
    ) {
        let topDragBar = DragHandleView()
        topDragBar.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.alphaValue = 0.78

        let topDivider = NSBox()
        topDivider.boxType = .separator
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        topDivider.alphaValue = 0.72

        ToolbarAction.allCases.forEach { action in
            let button = makeToolbarButton(for: action)
            toolbarButtons.append(button)
            toolbarButtonsByAction[action] = button
            toolbarStack.addArrangedSubview(button)
        }

        let toolbarWidth = (CGFloat(ToolbarAction.allCases.count) * toolbarButtonWidth)
            + (CGFloat(max(ToolbarAction.allCases.count - 1, 0)) * toolbarButtonSpacing)
        toolbarStack.widthAnchor.constraint(equalToConstant: toolbarWidth).isActive = true

        let footerBar = NSView()
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        shellContent.addSubview(footerBar)

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
                saveButton.leadingAnchor.constraint(greaterThanOrEqualTo: toolbarStack.trailingAnchor, constant: footerGapToSave)
            ])
        } else {
            footerBar.addSubview(toolbarStack)
            NSLayoutConstraint.activate([
                toolbarStack.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: footerEdgeInset),
                toolbarStack.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
                toolbarStack.trailingAnchor.constraint(lessThanOrEqualTo: footerBar.trailingAnchor, constant: -footerEdgeInset)
            ])
        }

        shellContent.addSubview(topDragBar)
        shellContent.addSubview(topDivider)
        shellContent.addSubview(scrollView)
        backdrop.addSubview(overlayScrollIndicator)
        shellContent.addSubview(divider)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),
            scrollView.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: showsSaveButton ? -4 : -2),

            overlayScrollIndicator.trailingAnchor.constraint(equalTo: backdrop.trailingAnchor, constant: -2),
            overlayScrollIndicator.topAnchor.constraint(equalTo: scrollView.topAnchor),
            overlayScrollIndicator.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            overlayScrollIndicator.widthAnchor.constraint(equalToConstant: 8),
            scrollView.trailingAnchor.constraint(equalTo: overlayScrollIndicator.leadingAnchor, constant: -4),

            topDragBar.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 2),
            topDragBar.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -8),
            topDragBar.topAnchor.constraint(equalTo: shellContent.topAnchor),
            topDragBar.heightAnchor.constraint(equalToConstant: 15),

            topDivider.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor, constant: 2),
            topDivider.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor, constant: -2),
            topDivider.topAnchor.constraint(equalTo: topDragBar.bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor),
            footerBar.heightAnchor.constraint(equalToConstant: toolbarButtonHeight),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: showsSaveButton ? 214 : 216)
        ])
    }

    // MARK: - Quick capture UI

    func buildQuickCaptureUI(
        in shellContent: NSView,
        backdrop: GradientBackdropView,
        scrollView: NSScrollView,
        overlayScrollIndicator: ScrollIndicatorOverlay
    ) {
        let titleBodyGap: CGFloat = 6

        let bodyContainer = SubviewPassthroughView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false
        shellContent.addSubview(bodyContainer)

        let dragHandle = DragHandleView()
        dragHandle.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(dragHandle)

        let titleHost = TitleEditorProxyView()
        titleHost.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(titleHost)
        quickCaptureTitleHost = titleHost

        let titleTextContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        titleTextContainer.widthTracksTextView = true
        titleTextContainer.heightTracksTextView = true
        titleTextContainer.maximumNumberOfLines = 1
        titleTextContainer.lineBreakMode = NSLineBreakMode.byClipping

        let titleLayoutManager = NSLayoutManager()
        titleLayoutManager.addTextContainer(titleTextContainer)

        let titleStorage = NSTextStorage()
        titleStorage.addLayoutManager(titleLayoutManager)

        let titleTextView = FocusableTitleTextView(frame: .zero, textContainer: titleTextContainer)
        titleTextView.translatesAutoresizingMaskIntoConstraints = false
        titleTextView.delegate = self
        titleTextView.drawsBackground = false
        titleTextView.isRichText = false
        titleTextView.importsGraphics = false
        titleTextView.usesFontPanel = false
        titleTextView.isAutomaticDataDetectionEnabled = false
        titleTextView.isAutomaticQuoteSubstitutionEnabled = false
        titleTextView.isAutomaticDashSubstitutionEnabled = false
        titleTextView.isAutomaticTextReplacementEnabled = false
        titleTextView.isContinuousSpellCheckingEnabled = false
        titleTextView.allowsUndo = true
        titleTextView.isEditable = true
        titleTextView.isSelectable = true
        titleTextView.isHorizontallyResizable = false
        titleTextView.isVerticallyResizable = true
        titleTextView.minSize = NSSize(width: 0, height: 28)
        titleTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        titleTextView.textColor = panelPrimaryTextColor()
        titleTextView.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        titleTextView.insertionPointColor = theme.accentColor
        titleTextView.textContainerInset = NSSize(width: 0, height: 4)
        titleTextView.textContainer?.lineFragmentPadding = 0
        titleTextView.typingAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            NSAttributedString.Key.foregroundColor: panelPrimaryTextColor()
        ]
        titleHost.addSubview(titleTextView)
        quickCaptureTitleTextView = titleTextView
        titleTextView.onTextInputStateChanged = { [weak self] in
            self?.refreshChrome()
        }
        titleTextView.nextKeyView = editorTextView
        editorTextView.nextKeyView = titleTextView

        let titlePlaceholderOverlay = PassthroughOverlayView()
        titlePlaceholderOverlay.translatesAutoresizingMaskIntoConstraints = false
        titleHost.addSubview(titlePlaceholderOverlay)

        let titlePlaceholderLabel = NSTextField(labelWithString: "New Note")
        titlePlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false
        titlePlaceholderLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titlePlaceholderLabel.textColor = panelTertiaryTextColor()
        titlePlaceholderOverlay.addSubview(titlePlaceholderLabel)
        quickCaptureTitlePlaceholderLabel = titlePlaceholderLabel

        let bodyPlaceholderOverlay = PassthroughOverlayView()
        bodyPlaceholderOverlay.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(bodyPlaceholderOverlay)

        let bodyLabel = NSTextField(labelWithString: "Notes")
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 15, weight: .regular)
        bodyLabel.textColor = panelTertiaryTextColor()
        bodyPlaceholderOverlay.addSubview(bodyLabel)
        quickCapturePlaceholderBodyLabel = bodyLabel

        let actionStack = NSStackView()
        actionStack.orientation = .horizontal
        actionStack.alignment = .centerY
        actionStack.spacing = 10
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(actionStack)

        QuickCaptureAction.allCases.forEach { action in
            let button = makeQuickCaptureActionButton(for: action)
            toolbarButtons.append(button)
            if action == .tag { quickCaptureTagButton = button }
            if let linkedAction = action.linkedToolbarAction {
                quickCaptureButtonsByAction[linkedAction] = button
            }
            actionStack.addArrangedSubview(button)
        }

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
        (directoryButton.cell as? NSButtonCell)?.lineBreakMode = .byTruncatingTail
        footerShelf.addSubview(directoryButton)
        quickCaptureDirectoryButton = directoryButton

        let cancelButton = FocusAwareSecondaryButton(frame: .zero)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.title = "Cancel"
        cancelButton.target = self
        cancelButton.action = #selector(cancelPressed)
        cancelButton.font = .systemFont(ofSize: 13, weight: .semibold)
        cancelButton.controlSize = .regular
        cancelButton.widthAnchor.constraint(equalToConstant: 70).isActive = true
        cancelButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        footerShelf.addSubview(cancelButton)
        self.cancelButton = cancelButton

        let saveButton = makePrimarySaveButton()
        saveButton.image = nil
        saveButton.imagePosition = .noImage
        saveButton.font = .systemFont(ofSize: 13, weight: .semibold)
        saveButton.widthAnchor.constraint(equalToConstant: 70).isActive = true
        saveButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        footerShelf.addSubview(saveButton)
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

            titleHost.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 18),
            titleHost.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -20),
            titleHost.topAnchor.constraint(equalTo: dragHandle.bottomAnchor, constant: 8),
            titleHost.heightAnchor.constraint(equalToConstant: 32),

            titleTextView.leadingAnchor.constraint(equalTo: titleHost.leadingAnchor),
            titleTextView.trailingAnchor.constraint(equalTo: titleHost.trailingAnchor),
            titleTextView.topAnchor.constraint(equalTo: titleHost.topAnchor),
            titleTextView.bottomAnchor.constraint(equalTo: titleHost.bottomAnchor),

            titlePlaceholderOverlay.leadingAnchor.constraint(equalTo: titleHost.leadingAnchor),
            titlePlaceholderOverlay.trailingAnchor.constraint(equalTo: titleHost.trailingAnchor),
            titlePlaceholderOverlay.topAnchor.constraint(equalTo: titleHost.topAnchor),
            titlePlaceholderOverlay.bottomAnchor.constraint(equalTo: titleHost.bottomAnchor),

            titlePlaceholderLabel.leadingAnchor.constraint(equalTo: titlePlaceholderOverlay.leadingAnchor),
            titlePlaceholderLabel.centerYAnchor.constraint(equalTo: titlePlaceholderOverlay.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor, constant: 18),
            scrollView.topAnchor.constraint(equalTo: titleHost.bottomAnchor, constant: titleBodyGap),
            scrollView.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -12),

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
            bodyLabel.topAnchor.constraint(equalTo: bodyPlaceholderOverlay.topAnchor, constant: titleBodyGap),

            actionStack.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor, constant: -16),
            actionStack.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor, constant: -11),
            actionStack.heightAnchor.constraint(equalToConstant: 28),

            footerShelf.leadingAnchor.constraint(equalTo: shellContent.leadingAnchor),
            footerShelf.trailingAnchor.constraint(equalTo: shellContent.trailingAnchor),
            footerShelf.bottomAnchor.constraint(equalTo: shellContent.bottomAnchor),
            footerShelf.heightAnchor.constraint(equalToConstant: 42),

            footerDivider.leadingAnchor.constraint(equalTo: footerShelf.leadingAnchor),
            footerDivider.trailingAnchor.constraint(equalTo: footerShelf.trailingAnchor),
            footerDivider.topAnchor.constraint(equalTo: footerShelf.topAnchor),

            directoryButton.leadingAnchor.constraint(equalTo: footerShelf.leadingAnchor, constant: 12),
            directoryButton.centerYAnchor.constraint(equalTo: footerShelf.centerYAnchor),
            directoryButton.heightAnchor.constraint(equalToConstant: 22),
            directoryButton.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -10),

            saveButton.trailingAnchor.constraint(equalTo: footerShelf.trailingAnchor, constant: -12),
            saveButton.centerYAnchor.constraint(equalTo: footerShelf.centerYAnchor),

            cancelButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -6),
            cancelButton.centerYAnchor.constraint(equalTo: footerShelf.centerYAnchor),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 176)
        ])
    }

    // MARK: - Button factories

    func makePrimarySaveButton() -> FocusAwareAccentButton {
        let saveButton = FocusAwareAccentButton(frame: .zero)
        saveButton.title = "Save"
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

    func makeToolbarButton(for action: ToolbarAction) -> HoverToolbarButton {
        let button = HoverToolbarButton(frame: .zero)
        button.title = action.title ?? ""
        button.target = self
        button.action = #selector(toolbarButtonPressed(_:))
        button.tag = action.rawValue
        button.toolTip = action.toolTip
        button.controlSize = .small
        button.font = .systemFont(ofSize: 12, weight: .semibold)
        button.preferredSize = NSSize(width: toolbarButtonWidth, height: toolbarButtonHeight)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: toolbarButtonWidth).isActive = true
        button.heightAnchor.constraint(equalToConstant: toolbarButtonHeight).isActive = true

        if let symbolName = action.symbolName {
            button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: action.toolTip)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
            button.imagePosition = .imageOnly
        }
        return button
    }

    func makeQuickCaptureActionButton(for action: QuickCaptureAction) -> HoverToolbarButton {
        let button = HoverToolbarButton(frame: .zero)
        button.target = self
        button.action = #selector(quickCaptureActionPressed(_:))
        button.tag = action.rawValue
        button.toolTip = action.toolTip
        button.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: action.toolTip)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        button.imagePosition = .imageOnly
        button.title = ""
        button.preferredSize = NSSize(width: 28, height: 28)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        button.imageOffsetY = -1
        return button
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
        if let titleTextView = quickCaptureTitleTextView {
            observers.append(
                center.addObserver(forName: NSText.didChangeNotification, object: titleTextView, queue: nil) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.refreshChrome()
                        self?.markDocumentDirty()
                    }
                }
            )
        }
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
                let note = try noteStore.loadNote(at: fileURL)
                title = note.title
                body = note.body
                isDirty = false
            } catch {
                presentErrorAlert(message: "Failed to load note", details: error.localizedDescription)
            }
        }

        applyInitialContent(title: title, body: body)

        if let draft = noteStore.loadDraft(id: currentDraftID) {
            applyInitialContent(title: draft.title, body: draft.body)
            selectedDirectoryURL = URL(fileURLWithPath: draft.selectedDirectoryPath, isDirectory: true)
            isDirty = true
            statusLabel.stringValue = "Restored"
        } else {
            statusLabel.stringValue = fileURL == nil ? "Markdown" : "Editing"
        }

        refreshChrome()
        overlayScrollIndicator?.updateIndicator()
        updateTypingAttributesFromInsertionPoint()
        updateToolbarSelectionState()
        updateInlineSuggestions()
    }

    func applyInitialContent(title: String, body: String) {
        if isQuickCaptureMode {
            quickCaptureTitleTextView?.string = title
            applyBodyMarkdown(body)
            return
        }
        applyBodyMarkdown(MarkdownEditorDocument(title: title, body: body).editorText)
    }

    func applyBodyMarkdown(_ markdown: String) {
        suppressTextDidChange = true
        let rendered = MarkdownRichTextCodec.render(markdown: markdown, theme: theme)
        editorTextView.textStorage?.setAttributedString(rendered)
        suppressTextDidChange = false
    }

    // MARK: - Chrome refresh

    func refreshChrome() {
        refreshTrackedTags()
        refreshQuickCaptureChrome()
    }

    func refreshQuickCaptureChrome() {
        guard isQuickCaptureMode else { return }

        let state = QuickCaptureDocumentState(
            title: currentQuickCaptureTitleValue(),
            bodyMarkdown: serializedBodyMarkdown()
        )
        let titleHasMarkedText = quickCaptureTitleTextView?.hasMarkedText() == true
        let bodyHasMarkedText = editorTextView.hasMarkedText()

        quickCaptureTitlePlaceholderLabel?.isHidden = !state.normalizedTitle.isEmpty || titleHasMarkedText
        quickCapturePlaceholderBodyLabel?.isHidden = !state.normalizedBody.isEmpty || bodyHasMarkedText

        if let tagButton = quickCaptureTagButton {
            tagButton.isActive = !state.tags.isEmpty
            tagButton.toolTip = state.tags.isEmpty
                ? "Choose known tags or insert # into the note"
                : state.tags.map { "#\($0)" }.joined(separator: ", ")
        }

        let destinationTitle = quickCaptureDestinationTitle()
        quickCaptureDirectoryButton?.title = destinationTitle
        quickCaptureDirectoryButton?.toolTip = displayPath(selectedDirectoryURL)
        (quickCaptureDirectoryButton as? FocusAwareGhostButton)?.updateAppearance()
    }

    func quickCaptureDestinationTitle() -> String {
        let standardizedSelected = selectedDirectoryURL.standardizedFileURL
        let standardizedRoot = noteStore.notesDirectory.standardizedFileURL
        if standardizedSelected == standardizedRoot { return "Inbox" }
        return standardizedSelected.lastPathComponent
    }

    func updateWindowFocusAppearance(isFocused: Bool) {
        toolbarButtons.forEach { $0.isWindowFocused = isFocused }
        saveButton?.isWindowFocused = isFocused
        cancelButton?.isWindowFocused = isFocused
        (quickCaptureDirectoryButton as? FocusAwareGhostButton)?.isWindowFocused = isFocused
        statusLabel.textColor = isFocused ? panelSecondaryTextColor() : panelTertiaryTextColor()
    }
}
