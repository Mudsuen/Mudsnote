import AppKit
import MudsnoteCore

extension LibraryOverviewView {
    func measuredLayout(viewport: CGSize) -> OverviewLayout {
        let key = OverviewLayoutKey(revision: layoutRevision, viewport: viewport, selected: selectedID,
            presentation: presentation, collapsed: collapsed, root: focusedRoot,
            structure: mapStructure, expanded: expandedCardIDs)
        if let cachedLayout, cachedLayout.key == key { return cachedLayout.value }
        let result = OverviewLayout.make(width: viewport.width, height: viewport.height, state: state,
            selected: selectedID, presentation: presentation, collapsed: collapsed,
            titles: cards.mapValues { $0.heading.stringValue }, root: focusedRoot, structure: mapStructure,
            expandedCards: expandedCardIDs, previews: cards.mapValues { $0.preview.stringValue }, index: contentIndex)
        layoutBuildCount += 1
        cachedLayout = (key, result)
        return result
    }

    func layoutOverview() {
        let wasUpdatingViewport = updatingViewport
        updatingViewport = true
        defer { updatingViewport = wasUpdatingViewport }
        let width = max(1, bounds.width)
        breadcrumbScroll.frame = NSRect(x: 36, y: 16, width: max(1, width - 315), height: 18)
        updateBreadcrumbs()
        cardDisplayButton.frame = NSRect(x: width - 242, y: 10, width: 28, height: 28)
        presentationButton.frame = NSRect(x: width - 204, y: 10, width: 28, height: 28)
        graphButton.frame = NSRect(x: width - 280, y: 10, width: 28, height: 28)
        addArea.frame = NSRect(x: width - 166, y: 10, width: 28, height: 28)
        add.frame = NSRect(x: width - 128, y: 10, width: 28, height: 28)
        newNote.frame = NSRect(x: width - 90, y: 10, width: 28, height: 28)
        appearanceButton.frame = NSRect(x: width - 52, y: 10, width: 28, height: 28)
        for button in [presentationButton, cardDisplayButton, graphButton, addArea, add, newNote, appearanceButton] { button.contentTintColor = colors.detail }
        scroll.frame = NSRect(x: 0, y: 48, width: width, height: max(1, bounds.height - 48))
        scroll.wantsLayer = true; scroll.layer?.backgroundColor = (presentation == .outline ? colors.outlineBackground : colors.mapBackground).cgColor
        let viewport = scroll.contentView.frame.size
        viewportControls.frame = NSRect(x: max(8, width - 188), y: max(48, bounds.height - 50), width: 172, height: 34)
        viewportControls.sync(overview: self)
        var next = measuredLayout(viewport: viewport)
        var preserveOrigin: CGPoint?
        if presentation == .mindMap {
            let visible = scroll.contentView.bounds.size
            let offset = CGPoint(x: visible.width + canvasTranslation.x, y: visible.height + canvasTranslation.y)
            let delta = CGPoint(x: offset.x - next.worldOffset.x, y: offset.y - next.worldOffset.y)
            next.frames = next.frames.mapValues { $0.offsetBy(dx: delta.x, dy: delta.y) }
            next.contentBounds = next.contentBounds.offsetBy(dx: delta.x, dy: delta.y)
            next.worldOffset = offset
            next.size = CGSize(width: max(1, visible.width * 3), height: max(1, visible.height * 3))
            if let old = plan, old.presentation == .mindMap, old.root == next.root {
                preserveOrigin = CGPoint(x: scroll.contentView.bounds.minX + offset.x - old.worldOffset.x,
                                         y: scroll.contentView.bounds.minY + offset.y - old.worldOffset.y)
            }
        }
        if let transition = cardTransition { next = next.interpolatingFrames(from: transition.source, progress: transition.progress) }
        plan = next
        updateCardDisplayChrome()
        let tree = contentIndex.tree
        rootHost.configure(nodeFrame: next.frames[next.root] ?? .zero, presentation: presentation, depth: 0, side: 1,
            colors: colors, active: activeNode == next.root, folded: false, children: tree.children[next.root, default: []].count,
            details: nodeDetails(next.root), allowsChild: next.root != .unassigned)
        title.stringValue = nodeTitle(next.root); title.isMap = presentation == .mindMap
        title.alignment = title.isMap ? .center : .left
        title.font = OverviewTypography.font(title.isMap ? 24 : 34, weight: title.isMap ? .medium : .semibold, map: title.isMap)
        title.textColor = title.isMap ? colors.mapRootText : colors.title
        title.textFrame = rootHost.textRect.offsetBy(dx: -rootHost.contentRect.minX, dy: -rootHost.contentRect.minY)
        title.needsDisplay = true
        principles.stringValue = nodeDetails(next.root)
        principles.font = OverviewTypography.font(14)
        principles.isHidden = principles.stringValue.isEmpty
        let rootRect = rootHost.contentRect
        let detailHeight = OverviewTypography.detailHeight(principles.stringValue, width: rootRect.width - (presentation == .outline ? 0 : 32))
        principles.frame = presentation == .outline
            ? NSRect(x: rootRect.minX, y: rootRect.maxY + 6, width: rootRect.width, height: detailHeight)
            : NSRect(x: rootRect.minX + 16, y: rootHost.textRect.maxY, width: rootRect.width - 32, height: detailHeight)
        if presentation == .outline, !principles.stringValue.isEmpty { rootHost.frame.size.height += detailHeight + 6 }
        let detailParagraph = NSMutableParagraphStyle(); detailParagraph.minimumLineHeight = 24; detailParagraph.maximumLineHeight = 24; detailParagraph.lineBreakMode = .byWordWrapping
        principles.attributedStringValue = NSAttributedString(string: principles.stringValue,
            attributes: [.font: principles.font!, .paragraphStyle: detailParagraph, .foregroundColor: presentation == .outline ? colors.detail : colors.mapRootText.withAlphaComponent(0.7)])
        for (node, host) in hosts {
            guard node != next.root, let rect = next.frames[node] else { host.isHidden = true; continue }
            host.isHidden = false
            let depth = next.depths[node] ?? 1
            host.configure(nodeFrame: rect, presentation: presentation, depth: depth, side: next.sides[node] ?? 1,
                colors: colors, active: activeNode == node, folded: collapsed.contains(node),
                children: tree.children[node, default: []].count, details: nodeDetails(node), allowsChild: node != .unassigned && !isCard(node))
            if let button = host.content as? OverviewActionButton {
                button.alignment = .left; button.font = OverviewTypography.font(presentation == .outline || depth == 1 ? 16 : 14, map: presentation == .mindMap)
                button.cell?.wraps = true; button.cell?.usesSingleLineMode = false; button.lineBreakMode = .byWordWrapping
                let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = presentation == .outline ? 25.6 : depth == 1 ? 26 : 22; paragraph.maximumLineHeight = paragraph.minimumLineHeight; paragraph.lineBreakMode = .byWordWrapping
                button.attributedTitle = NSAttributedString(string: button.title, attributes: [.font: button.font!, .paragraphStyle: paragraph, .foregroundColor: presentation == .outline ? colors.text : colors.mapText])
                button.setAccessibilityLabel(button.title.isEmpty ? "未命名主题" : button.title)
            }
            if case .card(let id) = node, let card = cards[id] {
                card.isHidden = false; card.isOutline = presentation == .outline; card.mapDepth = depth; card.colors = colors
                card.isCompact = !expandedCardIDs.contains(id) && !(cardTransition?.visiblePreviews.contains(id) ?? false)
                let targetAlpha: CGFloat = expandedCardIDs.contains(id) ? 1 : 0
                if let transition = cardTransition {
                    let sourceAlpha = transition.alphas[id] ?? targetAlpha
                    card.preview.alphaValue = sourceAlpha + (targetAlpha - sourceAlpha) * transition.progress
                } else { card.preview.alphaValue = targetAlpha }
                card.setAccessibilityValue(expandedCardIDs.contains(id) ? (presentation == .outline ? "正文已展开" : "内容卡片") : "标题")
                card.setAccessibilityHelp("单击展开或收起，双击标题编辑；右键查看关联与归属")
                card.nodeActive = activeNode == node; card.needsLayout = true; card.needsDisplay = true
                host.bullet.setAccessibilityLabel("打开笔记")
            } else { host.bullet.setAccessibilityLabel("进入主题 " + nodeTitle(node)) }
        }
        canvas.lines = []; canvas.isOutline = presentation == .outline
        canvas.strokeColor = presentation == .outline ? colors.guide : colors.mapLine
        if presentation == .mindMap {
            func connectionY(_ node: OverviewNodeID, _ frame: CGRect) -> CGFloat {
                if (next.depths[node] ?? 0) < 2 { return frame.midY }
                if case .card(let id) = node {
                    let amount: CGFloat = selectedID == id ? 1 : (cards[id]?.preview.alphaValue ?? 0)
                    return frame.maxY + (frame.midY - frame.maxY) * amount
                }
                return frame.maxY
            }
            for (parent, child) in next.links {
                guard let a = next.frames[parent], let b = next.frames[child] else { continue }
                let side = next.sides[child] ?? 1
                let startY = connectionY(parent, a)
                let endY = connectionY(child, b)
                let start = NSPoint(x: side > 0 ? a.maxX : a.minX, y: startY)
                let end = NSPoint(x: side > 0 ? b.minX : b.maxX, y: endY)
                let bend = (start.x + end.x) / 2
                canvas.lines.append(([start, NSPoint(x: bend, y: start.y), NSPoint(x: bend, y: end.y), end], true))
            }
        } else {
            // One bottom-up pass replaces a descendant walk for every row.
            var subtreeBottoms = next.frames.mapValues(\.maxY)
            for node in next.order.reversed() {
                if let parent = tree.parents[node], let bottom = subtreeBottoms[node] {
                    subtreeBottoms[parent] = max(subtreeBottoms[parent] ?? bottom, bottom)
                }
            }
            for (node, rect) in next.frames where node != next.root && !collapsed.contains(node) {
                let bottom = subtreeBottoms[node] ?? rect.maxY
                if bottom > rect.maxY {
                    let x = rect.minX + 12
                    canvas.lines.append(([NSPoint(x: x, y: rect.maxY), NSPoint(x: x, y: bottom)], true))
                }
            }
        }
        if presentation == .mindMap, case .card(let id) = activeNode {
            for edge in state.connections where edge.from == id || edge.to == id {
                guard let a = next.frames[.card(edge.from)], let b = next.frames[.card(edge.to)] else { continue }
                let gutter = next.contentBounds.maxX + 24
                canvas.lines.append(([NSPoint(x: a.maxX, y: a.midY), NSPoint(x: gutter, y: a.midY),
                                      NSPoint(x: gutter, y: b.midY), NSPoint(x: b.maxX, y: b.midY)], false))
            }
        }
        canvas.setFrameSize(next.size); canvas.needsDisplay = true
        if let preserveOrigin {
            let wasUpdating = updatingViewport; updatingViewport = true
            scroll.contentView.scroll(to: preserveOrigin); scroll.reflectScrolledClipView(scroll.contentView)
            updatingViewport = wasUpdating
        }
        layoutTopicEditor()
        if initialViewport, bounds.width > 0, bounds.height > 48 {
            initialViewport = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.activeNode == nil else { return }
                self.resetViewport()
            }
        }
    }
}
