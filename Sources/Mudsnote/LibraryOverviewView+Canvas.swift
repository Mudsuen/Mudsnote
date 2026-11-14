import AppKit
import MudsnoteCore

extension LibraryOverviewView {
    func updateCardDisplayChrome() {
        let visible = Set(plan?.cards.keys.map { $0 } ?? [])
        let allExpanded = !visible.isEmpty && visible.isSubset(of: expandedCardIDs)
        let label = presentation == .outline ? (allExpanded ? "收起全部正文" : "展开全部正文")
            : (allExpanded ? "收起全部卡片" : "展开全部卡片")
        cardDisplayButton.isEnabled = !visible.isEmpty
        cardDisplayButton.toolTip = label
        cardDisplayButton.setAccessibilityLabel(label)
        let symbol = presentation == .outline ? (allExpanded ? "chevron.up" : "chevron.down")
            : (allExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
        cardDisplayButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    }

    func toggleCardPreview(_ id: UUID) {
        guard cards[id] != nil else { return }
        transitionCardPreviews(anchoring: .card(id)) { ids in
            if !ids.insert(id).inserted { ids.remove(id) }
        }
    }

    func toggleAllCardPreviews() {
        let visible = Set(plan?.cards.keys.map { $0 } ?? [])
        guard !visible.isEmpty else { return }
        let shouldCollapse = visible.isSubset(of: expandedCardIDs)
        let anchor = activeNode.flatMap { plan?.frames[$0] != nil ? $0 : nil } ?? focusedRoot
        transitionCardPreviews(anchoring: anchor) { ids in
            if shouldCollapse { ids.subtract(visible) } else { ids.formUnion(visible) }
        }
    }

    func finishCardTransition() {
        cardTransitionTask?.cancel(); cardTransitionTask = nil
        cardTransition = nil
        needsLayout = true
    }

    /// Keep the clicked title at the same viewport position while the ownership
    /// tree makes room. Frames and connectors share the same interpolation.
    func transitionCardPreviews(anchoring anchor: OverviewNodeID, change: (inout Set<UUID>) -> Void) {
        guard commitTopicEditing(), owner?.commitOverviewEditor() == true else { return }
        layoutSubtreeIfNeeded()
        guard var source = plan else { return }
        let oldOrigin = scroll.contentView.bounds.origin
        let sourceAlphas = cards.mapValues { $0.preview.alphaValue }
        let sourcePreviews = Set(cards.compactMap { !$0.value.isCompact || $0.value.editor != nil ? $0.key : nil })
        finishCardTransition()
        if let selectedID {
            owner?.toggleOverviewCard(selectedID)
            guard self.selectedID == nil else { return }
        }
        owner?.cancelActiveNoteLoad()
        change(&expandedCardIDs)
        for card in state.cards where expandedCardIDs.contains(card.id) {
            loadCardPreview(card)
        }
        activeNode = anchor
        window?.makeFirstResponder(self)
        needsLayout = true; layoutSubtreeIfNeeded()
        if let old = source.frames[anchor], let target = plan?.frames[anchor] {
            let requested = CGPoint(x: oldOrigin.x + target.minX - old.minX,
                                    y: oldOrigin.y + target.minY - old.minY)
            if presentation == .mindMap { panViewport(to: requested) }
            else {
                var bounds = scroll.contentView.bounds; bounds.origin = requested; bounds.origin.x = 0
                scroll.contentView.scroll(to: scroll.contentView.constrainBoundsRect(bounds).origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }
        guard let target = plan else { return }
        let origin = scroll.contentView.bounds.origin
        source.frames = source.frames.mapValues { $0.offsetBy(dx: origin.x - oldOrigin.x, dy: origin.y - oldOrigin.y) }
        source.worldOffset = target.worldOffset
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        cardTransition = (source, 0, sourcePreviews.union(expandedCardIDs), sourceAlphas)
        needsLayout = true; layoutSubtreeIfNeeded()
        let started = ProcessInfo.processInfo.systemUptime
        cardTransitionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, var transition = self.cardTransition else { return }
                let fraction = min(1, (ProcessInfo.processInfo.systemUptime - started) / 0.22)
                let value = CGFloat(fraction)
                transition.progress = value * value * (3 - 2 * value)
                self.cardTransition = transition
                if fraction >= 1 { self.cardTransition = nil; self.cardTransitionTask = nil }
                self.needsLayout = true; self.layoutSubtreeIfNeeded()
                if fraction >= 1 { return }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    /// Rebase a small scroll window instead of growing a gigantic backing view.
    /// All persisted positions remain in world coordinates relative to this root.
    func panViewport(to requested: CGPoint) {
        guard presentation == .mindMap, !updatingViewport else { return }
        updatingViewport = true
        defer { updatingViewport = false }
        let clip = scroll.contentView
        let visible = clip.bounds.size
        var delta = CGPoint.zero
        if requested.x < visible.width * 0.5 || requested.x > canvas.bounds.width - visible.width * 1.5 {
            delta.x = (canvas.bounds.width - visible.width) / 2 - requested.x
        }
        if requested.y < visible.height * 0.5 || requested.y > canvas.bounds.height - visible.height * 1.5 {
            delta.y = (canvas.bounds.height - visible.height) / 2 - requested.y
        }
        if delta != .zero {
            canvasTranslation.x += delta.x; canvasTranslation.y += delta.y
            needsLayout = true; layoutSubtreeIfNeeded()
        }
        clip.scroll(to: CGPoint(x: requested.x + delta.x, y: requested.y + delta.y))
        scroll.reflectScrolledClipView(clip)
    }

    @objc func canvasViewportChanged() {
        viewportControls.sync(overview: self)
        guard presentation == .mindMap, !updatingViewport, let plan else { return }
        let clip = scroll.contentView
        let size = clip.bounds.size
        if abs(plan.size.width - size.width * 3) > 0.5 || abs(plan.size.height - size.height * 3) > 0.5 {
            guard !viewportLayoutQueued else { return }
            viewportLayoutQueued = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.viewportLayoutQueued = false
                self.needsLayout = true; self.layoutSubtreeIfNeeded()
            }
        } else {
            panViewport(to: clip.bounds.origin)
        }
    }

    func centerWorldPoint(_ point: CGPoint) {
        guard presentation == .mindMap else { return }
        updatingViewport = true
        defer { updatingViewport = false }
        let visible = scroll.contentView.bounds.size
        canvasTranslation = CGPoint(x: visible.width * 0.5 - point.x, y: visible.height * 0.5 - point.y)
        needsLayout = true; layoutSubtreeIfNeeded()
        scroll.contentView.scroll(to: CGPoint(x: visible.width, y: visible.height))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func mapPosition(at point: CGPoint) -> NoteOverview.MapPosition {
        let offset = plan?.worldOffset ?? .zero
        return .init(x: point.x - offset.x, y: point.y - offset.y, scope: focusedRoot.dragString)
    }

    @discardableResult func moveToCanvas(_ node: OverviewNodeID, at point: CGPoint) -> Bool {
        guard presentation == .mindMap, canMove(node, to: focusedRoot), prepareStructureChange() else { return false }
        let position = mapPosition(at: point)
        let area: UUID? = { if case .area(let id) = focusedRoot { return id }; return nil }()
        let changed = owner?.changeOverview { state in
            switch node {
            case .area(let id):
                guard let index = state.areas.firstIndex(where: { $0.id == id }) else { return }
                state.areas[index].parentID = area; state.areas[index].mapPosition = position
            case .card(let id):
                guard let index = state.cards.firstIndex(where: { $0.id == id }) else { return }
                state.cards[index].areaID = area; state.cards[index].mapPosition = position
            default: break
            }
        } == true
        if changed {
            collapsed.remove(focusedRoot); collapsed.remove(.unassigned)
            activeNode = node; needsLayout = true; layoutSubtreeIfNeeded()
        }
        return changed
    }

    func showCanvasMenu(at point: CGPoint, event: NSEvent? = nil) {
        guard presentation == .mindMap, commitTopicEditing() else { return }
        if let hit = plan?.order.first(where: { plan?.frames[$0]?.contains(point) == true }) {
            showTopicMenu(hit); return
        }
        let position = mapPosition(at: point)
        let parent = focusedRoot
        let area: UUID? = { if case .area(let id) = parent { return id }; return nil }()
        let menu = NSMenu()
        menu.addItem(OverviewMenuItem("新建笔记") { [weak owner] in owner?.createNoteInOverview(area: area, position: position) })
        if parent != .unassigned {
            menu.addItem(OverviewMenuItem("新建主题") { [weak self] in self?.createTopic(parent: parent, position: position) })
        }
        menu.addItem(OverviewMenuItem("关联已有笔记…") { [weak owner] in owner?.pickOverviewNote(area: area, connecting: nil, position: position) })
        menu.addItem(.separator())
        menu.addItem(OverviewMenuItem("回到中心主题") { [weak self] in self?.centerRoot() })
        menu.addItem(OverviewMenuItem("适应全部内容") { [weak self] in self?.fitToWindow() })
        if let event { NSMenu.popUpContextMenu(menu, with: event, for: canvas) }
        else { menu.popUp(positioning: nil, at: point, in: canvas) }
    }
}
