import AppKit
import MudsnoteCore

@MainActor
private final class KnowledgeGraphSegmentedControl: NSSegmentedControl {
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor.controlBackgroundColor.withAlphaComponent(0.92).setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()

        guard segmentCount > 0 else { return }
        let segmentWidth = bounds.width / CGFloat(segmentCount)
        for index in 0..<segmentCount {
            let frame = NSRect(
                x: CGFloat(index) * segmentWidth,
                y: 0,
                width: segmentWidth,
                height: bounds.height
            )
            if isSelected(forSegment: index) {
                let selection = NSBezierPath(
                    roundedRect: frame.insetBy(dx: 2, dy: 2),
                    xRadius: 6,
                    yRadius: 6
                )
                NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
                selection.fill()
            }
            let title = label(forSegment: index) ?? ""
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(
                at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                withAttributes: attributes
            )
        }
    }
}

@MainActor
private final class KnowledgeGraphToolbarButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (isHighlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.25)
            : NSColor.controlBackgroundColor.withAlphaComponent(0.92)
        ).setFill()
        outline.fill()
        NSColor.separatorColor.setStroke()
        outline.lineWidth = 1
        outline.stroke()
        guard let image else { return }
        let imageSize = NSSize(width: min(15, image.size.width), height: min(15, image.size.height))
        image.draw(
            in: NSRect(
                x: bounds.midX - imageSize.width / 2,
                y: bounds.midY - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: isEnabled ? 0.9 : 0.4
        )
    }
}

@MainActor
final class KnowledgeGraphWindowController: NSWindowController, NSWindowDelegate {
    private let noteStore: NoteStore
    private let rootsProvider: () -> [URL]
    private let canvasView = KnowledgeGraphCanvasView(frame: .zero)
    private let scopeControl = KnowledgeGraphSegmentedControl(
        labels: ["当前", "全局"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let depthControl = KnowledgeGraphSegmentedControl(
        labels: ["1 跳", "2 跳", "3 跳"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let layerControl = KnowledgeGraphSegmentedControl(
        labels: ["点", "线", "面", "体", "未分层"],
        trackingMode: .selectAny,
        target: nil,
        action: nil
    )
    private let searchField = NSSearchField(string: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let loadingIndicator = NSProgressIndicator()
    private var rootURL: URL?
    private var snapshot = KnowledgeGraphSnapshot.empty
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration = 0

    var onOpenNode: ((URL) -> Void)?
    var onClose: (() -> Void)?

    init(noteStore: NoteStore, rootsProvider: @escaping () -> [URL]) {
        self.noteStore = noteStore
        self.rootsProvider = rootsProvider
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 920, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 820, height: 460)
        window.title = "知识图谱"
        window.setFrameAutosaveName("MudsnoteKnowledgeGraphWindow")
        super.init(window: window)
        window.delegate = self
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(rootURL: URL?) {
        setRoot(rootURL, reload: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setRoot(_ url: URL?, reload: Bool) {
        let next = url?.standardizedFileURL
        guard rootURL != next || reload else { return }
        rootURL = next
        updateWindowTitle()
        if reload, scopeControl.selectedSegment != 1 {
            refresh()
        }
    }

    func reload() {
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        refreshTask?.cancel()
        refreshTask = nil
        refreshGeneration += 1
        onClose?()
    }

    private func configureUI() {
        guard let window else { return }
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = content

        scopeControl.identifier = NSUserInterfaceItemIdentifier("KnowledgeGraphScopeControl")
        scopeControl.selectedSegment = 0
        scopeControl.segmentStyle = .rounded
        scopeControl.controlSize = .small
        scopeControl.target = self
        scopeControl.action = #selector(scopeChanged(_:))
        scopeControl.setAccessibilityLabel("图谱范围")
        scopeControl.toolTip = "切换当前笔记局部图或全部已确认关系"

        depthControl.identifier = NSUserInterfaceItemIdentifier("KnowledgeGraphDepthControl")
        depthControl.selectedSegment = 0
        depthControl.segmentStyle = .rounded
        depthControl.controlSize = .small
        depthControl.target = self
        depthControl.action = #selector(depthChanged(_:))
        depthControl.setAccessibilityLabel("局部图深度")

        layerControl.identifier = NSUserInterfaceItemIdentifier("KnowledgeGraphLayerControl")
        layerControl.target = self
        layerControl.action = #selector(layerFilterChanged(_:))
        layerControl.segmentStyle = .rounded
        layerControl.controlSize = .small
        layerControl.setAccessibilityLabel("层级筛选")
        for index in 0..<layerControl.segmentCount {
            layerControl.setSelected(true, forSegment: index)
        }

        searchField.identifier = NSUserInterfaceItemIdentifier("KnowledgeGraphSearchField")
        searchField.placeholderString = "查找节点"
        searchField.bezelStyle = .roundedBezel
        searchField.drawsBackground = true
        searchField.backgroundColor = .controlBackgroundColor
        searchField.textColor = .labelColor
        searchField.setAccessibilityLabel("查找图谱节点")
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let searchCaption = NSTextField(labelWithString: "搜索")
        searchCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        searchCaption.textColor = .secondaryLabelColor

        let zoomOut = graphButton(
            symbolName: "minus.magnifyingglass",
            label: "缩小图谱",
            action: #selector(zoomOutPressed(_:))
        )
        let fit = graphButton(
            symbolName: "arrow.up.left.and.arrow.down.right",
            label: "适合窗口",
            action: #selector(fitPressed(_:))
        )
        let zoomIn = graphButton(
            symbolName: "plus.magnifyingglass",
            label: "放大图谱",
            action: #selector(zoomInPressed(_:))
        )

        countLabel.font = .systemFont(ofSize: 11, weight: .medium)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentHuggingPriority(.required, for: .horizontal)

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isDisplayedWhenStopped = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbar = NSStackView(views: [
            scopeControl,
            depthControl,
            layerControl,
            searchCaption,
            searchField,
            spacer,
            countLabel,
            loadingIndicator,
            zoomOut,
            fit,
            zoomIn
        ])
        toolbar.identifier = NSUserInterfaceItemIdentifier("KnowledgeGraphToolbar")
        toolbar.wantsLayer = true
        toolbar.layer?.zPosition = 10
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        toolbar.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        toolbar.layer?.borderWidth = 0.5
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)

        canvasView.identifier = NSUserInterfaceItemIdentifier("KnowledgeGraphCanvas")
        canvasView.layer?.zPosition = 0
        canvasView.onOpenNode = { [weak self] url in
            self?.onOpenNode?(url)
        }
        canvasView.onFocusNode = { [weak self] url in
            guard let self else { return }
            scopeControl.selectedSegment = 0
            depthControl.isHidden = false
            setRoot(url, reload: true)
        }

        let stack = NSStackView(views: [toolbar, canvasView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.distribution = .fill
        content.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            canvasView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            canvasView.heightAnchor.constraint(greaterThanOrEqualToConstant: 360)
        ])
    }

    private func graphButton(symbolName: String, label: String, action: Selector) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) ?? NSImage()
        let button = KnowledgeGraphToolbarButton(image: image, target: self, action: action)
        button.bezelStyle = .inline
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        button.toolTip = label
        button.setAccessibilityLabel(label)
        return button
    }

    @objc
    private func scopeChanged(_ sender: NSSegmentedControl) {
        depthControl.isHidden = sender.selectedSegment == 1
        refresh()
    }

    @objc
    private func depthChanged(_ sender: NSSegmentedControl) {
        refresh()
    }

    @objc
    private func layerFilterChanged(_ sender: NSSegmentedControl) {
        applyFilters()
    }

    @objc
    private func searchChanged(_ sender: NSSearchField) {
        applyFilters()
    }

    @objc
    private func zoomOutPressed(_ sender: NSButton) {
        canvasView.zoom(by: 0.82)
    }

    @objc
    private func zoomInPressed(_ sender: NSButton) {
        canvasView.zoom(by: 1.22)
    }

    @objc
    private func fitPressed(_ sender: NSButton) {
        canvasView.fitGraph()
    }

    private func refresh() {
        guard scopeControl.selectedSegment == 1 || rootURL != nil else {
            refreshTask?.cancel()
            refreshTask = nil
            refreshGeneration += 1
            loadingIndicator.stopAnimation(nil)
            canvasView.setLoading(false)
            snapshot = .empty
            applyFilters()
            return
        }
        refreshTask?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        let root = rootURL
        let scope: KnowledgeGraphScope
        if scopeControl.selectedSegment == 1 {
            scope = .global
        } else if let root {
            scope = .local(focus: root, depth: depthControl.selectedSegment + 1)
        } else {
            scope = .global
        }
        let roots = rootsProvider()
        let noteStore = noteStore
        loadingIndicator.startAnimation(nil)
        countLabel.stringValue = "正在构建…"
        canvasView.setLoading(true)
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            let result = noteStore.knowledgeGraphSnapshot(
                scope: scope,
                roots: roots,
                cancellationCheck: { Task.isCancelled }
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self,
                      generation == self.refreshGeneration,
                      self.rootURL == root else {
                    return
                }
                self.refreshTask = nil
                self.loadingIndicator.stopAnimation(nil)
                self.canvasView.setLoading(false)
                self.snapshot = result
                self.applyFilters()
            }
        }
        refreshTask = task
    }

    private func applyFilters() {
        let allowedLayerKeys = Set((0..<layerControl.segmentCount).compactMap { index -> String? in
            guard layerControl.isSelected(forSegment: index) else { return nil }
            switch index {
            case 0: return KnowledgeLayer.point.rawValue
            case 1: return KnowledgeLayer.line.rawValue
            case 2: return KnowledgeLayer.plane.rawValue
            case 3: return KnowledgeLayer.body.rawValue
            default: return "unknown"
            }
        })
        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleNodes = snapshot.nodes.filter { node in
            allowedLayerKeys.contains(node.layer?.rawValue ?? "unknown")
                && (query.isEmpty || node.title.localizedCaseInsensitiveContains(query))
        }
        let visiblePaths = Set(visibleNodes.map { $0.url.standardizedFileURL.path })
        let visibleEdges = snapshot.edges.filter {
            visiblePaths.contains($0.sourceURL.standardizedFileURL.path)
                && visiblePaths.contains($0.targetURL.standardizedFileURL.path)
        }
        let filtered = KnowledgeGraphSnapshot(
            nodes: visibleNodes,
            edges: visibleEdges,
            focusedURL: snapshot.focusedURL,
            sourceRevision: snapshot.sourceRevision
        )
        canvasView.update(filtered)
        countLabel.stringValue = "\(visibleNodes.count) 个节点 · \(visibleEdges.count) 条关系"
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        let rootTitle = rootURL?.deletingPathExtension().lastPathComponent
        if scopeControl.selectedSegment == 1 {
            window?.title = "知识图谱 — 全局"
        } else if let rootTitle {
            window?.title = "知识图谱 — \(rootTitle)"
        } else {
            window?.title = "知识图谱"
        }
    }
}

private final class KnowledgeGraphNodeAccessibilityElement: NSAccessibilityElement {
    nonisolated(unsafe) var pressHandler: (() -> Void)?

    override func accessibilityPerformPress() -> Bool {
        pressHandler?()
        return pressHandler != nil
    }
}

@MainActor
final class KnowledgeGraphCanvasView: NSView {
    private struct NodePresentation {
        let node: KnowledgeGraphNode
        let frame: NSRect
    }

    var onOpenNode: ((URL) -> Void)?
    var onFocusNode: ((URL) -> Void)?

    private var snapshot = KnowledgeGraphSnapshot.empty
    private var presentations: [NodePresentation] = []
    private var selectedURL: URL?
    private var hoveredURL: URL?
    private var scale: CGFloat = 1
    private var panOffset = CGPoint.zero
    private var dragOrigin: CGPoint?
    private var panOrigin = CGPoint.zero
    private var trackingAreaReference: NSTrackingArea?
    private var isLoading = false
    private var accessibilityElementsByPath: [String: KnowledgeGraphNodeAccessibilityElement] = [:]

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityRole(.group)
        setAccessibilityLabel("知识图谱")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaReference = area
        super.updateTrackingAreas()
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
        needsDisplay = true
    }

    func update(_ snapshot: KnowledgeGraphSnapshot) {
        self.snapshot = snapshot
        layoutNodes()
        selectedURL = snapshot.focusedURL ?? presentations.first?.node.url
        synchronizeAccessibilityElements()
        fitGraph()
        setAccessibilityLabel(
            "知识图谱，\(snapshot.nodes.count) 个节点，\(snapshot.edges.count) 条关系"
        )
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    func zoom(by factor: CGFloat) {
        scale = min(max(scale * factor, 0.45), 2.2)
        notifyAccessibilityLayoutChanged()
        needsDisplay = true
    }

    func fitGraph() {
        guard !presentations.isEmpty, bounds.width > 0, bounds.height > 0 else {
            scale = 1
            panOffset = .zero
            needsDisplay = true
            return
        }
        let graphBounds = presentations.reduce(NSRect.null) { $0.union($1.frame) }
        let availableWidth = max(bounds.width - 64, 1)
        let availableHeight = max(bounds.height - 64, 1)
        scale = min(max(min(
            availableWidth / max(graphBounds.width, 1),
            availableHeight / max(graphBounds.height, 1)
        ), 0.04), 1.35)
        panOffset = CGPoint(
            x: (bounds.width - graphBounds.width * scale) / 2 - graphBounds.minX * scale,
            y: (bounds.height - graphBounds.height * scale) / 2 - graphBounds.minY * scale
        )
        notifyAccessibilityLayoutChanged()
        needsDisplay = true
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        panOffset.x -= event.scrollingDeltaX
        panOffset.y -= event.scrollingDeltaY
        notifyAccessibilityLayoutChanged()
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if let hit = node(at: point) {
            selectedURL = hit.node.url
            updateAccessibilitySelection()
            if event.clickCount >= 2 {
                onOpenNode?(hit.node.url)
            }
            needsDisplay = true
            return
        }
        selectedURL = nil
        updateAccessibilitySelection()
        dragOrigin = point
        panOrigin = panOffset
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOrigin else { return }
        let point = convert(event.locationInWindow, from: nil)
        panOffset = CGPoint(
            x: panOrigin.x + point.x - dragOrigin.x,
            y: panOrigin.y + point.y - dragOrigin.y
        )
        notifyAccessibilityLayoutChanged()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragOrigin = nil
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nextURL = node(at: point)?.node.url
        if hoveredURL != nextURL {
            hoveredURL = nextURL
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            if let selectedURL {
                onOpenNode?(selectedURL)
            }
        case 49:
            if let selectedURL {
                onFocusNode?(selectedURL)
            }
        case 24:
            zoom(by: 1.22)
        case 27:
            zoom(by: 0.82)
        case 29:
            fitGraph()
        case 123:
            selectNode(in: CGVector(dx: -1, dy: 0))
        case 124:
            selectNode(in: CGVector(dx: 1, dy: 0))
        case 125:
            selectNode(in: CGVector(dx: 0, dy: 1))
        case 126:
            selectNode(in: CGVector(dx: 0, dy: -1))
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityChildren() -> [Any]? {
        updateAccessibilityElementFrames()
        return presentations.compactMap {
            accessibilityElementsByPath[$0.node.url.standardizedFileURL.path]
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        guard !presentations.isEmpty else {
            let text = isLoading ? "正在构建知识图谱…" : "当前范围内没有已确认的知识关系"
            drawCenteredText(text, color: .secondaryLabelColor)
            return
        }

        let framesByPath = Dictionary(uniqueKeysWithValues: presentations.map {
            ($0.node.url.standardizedFileURL.path, transformed($0.frame))
        })
        for edge in snapshot.edges {
            guard let sourceFrame = framesByPath[edge.sourceURL.standardizedFileURL.path],
                  let targetFrame = framesByPath[edge.targetURL.standardizedFileURL.path],
                  dirtyRect.intersects(sourceFrame.union(targetFrame)) else {
                continue
            }
            drawEdge(edge, from: sourceFrame, to: targetFrame)
        }
        for presentation in presentations {
            let frame = transformed(presentation.frame)
            if dirtyRect.intersects(frame) {
                drawNode(presentation.node, in: frame)
            }
        }
    }

    private func layoutNodes() {
        let laneOrder: [KnowledgeLayer?] = [.body, .plane, .line, .point, nil]
        let grouped = Dictionary(grouping: snapshot.nodes, by: \.layer)
        var result: [NodePresentation] = []
        let nodeWidth: CGFloat = 148
        let nodeHeight: CGFloat = 48
        let horizontalGap: CGFloat = 32
        let verticalGap: CGFloat = 92
        let horizontalInset: CGFloat = 50
        let verticalInset: CGFloat = 48

        for (laneIndex, layer) in laneOrder.enumerated() {
            let nodes = (grouped[layer] ?? []).sorted {
                if $0.linkCount == $1.linkCount {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.linkCount > $1.linkCount
            }
            for (index, node) in nodes.enumerated() {
                result.append(NodePresentation(
                    node: node,
                    frame: NSRect(
                        x: horizontalInset + CGFloat(index) * (nodeWidth + horizontalGap),
                        y: verticalInset + CGFloat(laneIndex) * (nodeHeight + verticalGap),
                        width: nodeWidth,
                        height: nodeHeight
                    )
                ))
            }
        }
        presentations = result
    }

    private func transformed(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.origin.x * scale + panOffset.x,
            y: rect.origin.y * scale + panOffset.y,
            width: rect.width * scale,
            height: rect.height * scale
        )
    }

    private func node(at point: CGPoint) -> NodePresentation? {
        presentations.last { transformed($0.frame).contains(point) }
    }

    private func selectNode(in direction: CGVector) {
        guard !presentations.isEmpty else { return }
        guard let selectedURL,
              let current = presentations.first(where: {
                  $0.node.url.standardizedFileURL == selectedURL.standardizedFileURL
              }) else {
            self.selectedURL = presentations.first?.node.url
            needsDisplay = true
            return
        }
        let origin = CGPoint(x: current.frame.midX, y: current.frame.midY)
        let candidates = presentations.compactMap { presentation -> (NodePresentation, CGFloat)? in
            guard presentation.node.url.standardizedFileURL != selectedURL.standardizedFileURL else {
                return nil
            }
            let dx = presentation.frame.midX - origin.x
            let dy = presentation.frame.midY - origin.y
            let forward = dx * direction.dx + dy * direction.dy
            guard forward > 0 else { return nil }
            let cross = abs(dx * direction.dy - dy * direction.dx)
            return (presentation, forward + cross * 2.2)
        }
        guard let next = candidates.min(by: { $0.1 < $1.1 })?.0 else { return }
        self.selectedURL = next.node.url
        needsDisplay = true
        let path = next.node.url.standardizedFileURL.path
        updateAccessibilitySelection()
        if let element = accessibilityElementsByPath[path] {
            NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
        }
    }

    private func synchronizeAccessibilityElements() {
        var updated: [String: KnowledgeGraphNodeAccessibilityElement] = [:]
        for presentation in presentations {
            let node = presentation.node
            let path = node.url.standardizedFileURL.path
            let element = accessibilityElementsByPath[path]
                ?? KnowledgeGraphNodeAccessibilityElement()
            let layerName = node.layer?.displayName ?? "未分层"
            element.setAccessibilityRole(.button)
            element.setAccessibilityParent(self)
            element.setAccessibilityLabel(
                "\(node.title)，\(layerName)层，\(node.linkCount) 条关系"
            )
            element.setAccessibilityHelp("按下可在资料库中打开，并将它设为图谱中心")
            element.setAccessibilityIdentifier("KnowledgeGraphNode-\(path)")
            element.pressHandler = { [weak self] in
                self?.selectedURL = node.url
                self?.updateAccessibilitySelection()
                self?.needsDisplay = true
                self?.onOpenNode?(node.url)
            }
            updated[path] = element
        }
        accessibilityElementsByPath = updated
        updateAccessibilitySelection()
        updateAccessibilityElementFrames()
    }

    private func updateAccessibilitySelection() {
        let selectedPath = selectedURL?.standardizedFileURL.path
        for (path, element) in accessibilityElementsByPath {
            element.setAccessibilityFocused(path == selectedPath)
        }
    }

    private func updateAccessibilityElementFrames() {
        guard let window else { return }
        for presentation in presentations {
            let path = presentation.node.url.standardizedFileURL.path
            let windowFrame = convert(transformed(presentation.frame), to: nil)
            accessibilityElementsByPath[path]?.setAccessibilityFrame(
                window.convertToScreen(windowFrame)
            )
        }
    }

    private func notifyAccessibilityLayoutChanged() {
        updateAccessibilityElementFrames()
        NSAccessibility.post(element: self, notification: .layoutChanged)
    }

    private func drawEdge(_ edge: KnowledgeGraphEdge, from source: NSRect, to target: NSRect) {
        let path = NSBezierPath()
        let sourceCenter = CGPoint(x: source.midX, y: source.midY)
        let targetCenter = CGPoint(x: target.midX, y: target.midY)
        let dx = targetCenter.x - sourceCenter.x
        let dy = targetCenter.y - sourceCenter.y
        let isVertical = abs(dy) >= abs(dx)
        let start: CGPoint
        let end: CGPoint
        let controlPoint1: CGPoint
        let controlPoint2: CGPoint
        if isVertical {
            let direction: CGFloat = dy >= 0 ? 1 : -1
            start = CGPoint(
                x: source.midX,
                y: direction > 0 ? source.maxY : source.minY
            )
            end = CGPoint(
                x: target.midX,
                y: direction > 0 ? target.minY : target.maxY
            )
            let offset = max(abs(end.y - start.y) * 0.34, 28)
            controlPoint1 = CGPoint(x: start.x, y: start.y + direction * offset)
            controlPoint2 = CGPoint(x: end.x, y: end.y - direction * offset)
        } else {
            let direction: CGFloat = dx >= 0 ? 1 : -1
            start = CGPoint(
                x: direction > 0 ? source.maxX : source.minX,
                y: source.midY
            )
            end = CGPoint(
                x: direction > 0 ? target.minX : target.maxX,
                y: target.midY
            )
            let offset = max(abs(end.x - start.x) * 0.34, 28)
            controlPoint1 = CGPoint(x: start.x + direction * offset, y: start.y)
            controlPoint2 = CGPoint(x: end.x - direction * offset, y: end.y)
        }
        path.move(to: start)
        path.curve(
            to: end,
            controlPoint1: controlPoint1,
            controlPoint2: controlPoint2
        )
        path.lineWidth = edge.kind == .hierarchy ? 1.6 : 1
        if edge.kind == .related {
            path.setLineDash([5, 4], count: 2, phase: 0)
            NSColor.tertiaryLabelColor.withAlphaComponent(0.45).setStroke()
        } else {
            NSColor.controlAccentColor.withAlphaComponent(0.46).setStroke()
        }
        path.stroke()

        guard edge.kind == .hierarchy else { return }
        let arrowLength = max(6, 8 * scale)
        let arrowAngle = atan2(end.y - controlPoint2.y, end.x - controlPoint2.x)
        let arrow = NSBezierPath()
        arrow.move(to: end)
        arrow.line(
            to: CGPoint(
                x: end.x - arrowLength * cos(arrowAngle - 0.48),
                y: end.y - arrowLength * sin(arrowAngle - 0.48)
            )
        )
        arrow.move(to: end)
        arrow.line(
            to: CGPoint(
                x: end.x - arrowLength * cos(arrowAngle + 0.48),
                y: end.y - arrowLength * sin(arrowAngle + 0.48)
            )
        )
        arrow.lineWidth = path.lineWidth
        NSColor.controlAccentColor.withAlphaComponent(0.62).setStroke()
        arrow.stroke()
    }

    private func drawNode(_ node: KnowledgeGraphNode, in frame: NSRect) {
        let isSelected = selectedURL?.standardizedFileURL == node.url.standardizedFileURL
        let isHovered = hoveredURL?.standardizedFileURL == node.url.standardizedFileURL
        let isFocused = snapshot.focusedURL?.standardizedFileURL == node.url.standardizedFileURL
        let color = color(for: node.layer)
        let path = nodePath(for: node.layer, frame: frame)
        color.withAlphaComponent(isHovered ? 0.25 : 0.16).setFill()
        path.fill()
        (isSelected || isFocused ? color : color.withAlphaComponent(0.72)).setStroke()
        path.lineWidth = isSelected ? 3 : (isFocused ? 2.4 : 1.3)
        path.stroke()

        let layerName = node.layer?.displayName ?? "未分层"
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(9, 11 * scale), weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let detailAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(8, 9 * scale), weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let titleRect = frame.insetBy(dx: 10 * scale, dy: 7 * scale)
        (node.title as NSString).draw(
            in: NSRect(
                x: titleRect.minX,
                y: titleRect.minY,
                width: titleRect.width,
                height: 17 * scale
            ),
            withAttributes: titleAttributes
        )
        ("\(layerName) · \(node.linkCount) 条关系" as NSString).draw(
            in: NSRect(
                x: titleRect.minX,
                y: titleRect.minY + 19 * scale,
                width: titleRect.width,
                height: 14 * scale
            ),
            withAttributes: detailAttributes
        )
    }

    private func nodePath(for layer: KnowledgeLayer?, frame: NSRect) -> NSBezierPath {
        switch layer {
        case .body:
            let path = NSBezierPath()
            path.move(to: CGPoint(x: frame.midX, y: frame.minY))
            path.line(to: CGPoint(x: frame.maxX, y: frame.midY))
            path.line(to: CGPoint(x: frame.midX, y: frame.maxY))
            path.line(to: CGPoint(x: frame.minX, y: frame.midY))
            path.close()
            return path
        case .point:
            return NSBezierPath(ovalIn: frame)
        case .line:
            return NSBezierPath(roundedRect: frame, xRadius: 18 * scale, yRadius: 18 * scale)
        case .plane:
            return NSBezierPath(roundedRect: frame, xRadius: 7 * scale, yRadius: 7 * scale)
        case nil:
            return NSBezierPath(roundedRect: frame, xRadius: 10 * scale, yRadius: 10 * scale)
        }
    }

    private func color(for layer: KnowledgeLayer?) -> NSColor {
        switch layer {
        case .point: return .systemBlue
        case .line: return .systemOrange
        case .plane: return .systemGreen
        case .body: return .systemPurple
        case nil: return .systemGray
        }
    }

    private func drawCenteredText(_ value: String, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color
        ]
        let size = (value as NSString).size(withAttributes: attributes)
        (value as NSString).draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
