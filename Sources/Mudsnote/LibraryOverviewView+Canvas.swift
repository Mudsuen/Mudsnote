import AppKit
import MudsnoteCore

extension LibraryOverviewView {
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
