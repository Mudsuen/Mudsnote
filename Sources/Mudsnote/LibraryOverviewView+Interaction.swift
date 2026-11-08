import AppKit
import MudsnoteCore

extension LibraryOverviewView: NSTextViewDelegate, NSMenuItemValidation {
    var insertionArea: UUID? {
        if case .area(let id) = activeNode ?? focusedRoot { return id }
        if case .area(let id) = focusedRoot { return id }
        return nil
    }

    @discardableResult func select(_ node: OverviewNodeID) -> Bool {
        if topicEdit?.node != node, !commitTopicEditing() { return false }
        if let selectedID, node != .card(selectedID) {
            owner?.toggleOverviewCard(selectedID)
            guard self.selectedID == nil else { return false }
        }
        owner?.cancelActiveNoteLoad()
        activeNode = node
        window?.makeFirstResponder(self)
        needsLayout = true
        return true
    }

    func topicPressed(_ node: OverviewNodeID) {
        guard select(node) else { return }
        if presentation == .outline, node != .unassigned { beginTopicEdit(node) }
    }

    @discardableResult func prepareStructureChange() -> Bool {
        guard commitTopicEditing(), owner?.commitOverviewEditor() == true else { return false }
        finishCardTransition()
        owner?.cancelActiveNoteLoad()
        if let selectedID {
            owner?.toggleOverviewCard(selectedID)
            guard self.selectedID == nil else { return false }
        }
        return true
    }

    func focus(_ node: OverviewNodeID) {
        if case .card(let id) = node { owner?.toggleOverviewCard(id); return }
        guard prepareStructureChange() else { return }
        focusedRoot = node; activeNode = node; collapsed.remove(node)
        updateBreadcrumbs(); needsLayout = true; layoutSubtreeIfNeeded(); resetViewport()
        window?.makeFirstResponder(self)
    }

    func updateBreadcrumbs() {
        breadcrumb.subviews.forEach { $0.removeFromSuperview() }
        let tree = OverviewTree(state)
        let path = focusedRoot == .root ? [OverviewNodeID.root] : tree.ancestors(of: focusedRoot).reversed() + [focusedRoot]
        let available = max(100, breadcrumbScroll.bounds.width)
        var x: CGFloat = 0
        func append(_ label: String, current: Bool, action: @escaping () -> Void) {
            let button = OverviewActionButton(label, action: action)
            button.font = .systemFont(ofSize: 14)
            button.alignment = .left; button.lineBreakMode = .byTruncatingTail
            button.cell?.usesSingleLineMode = true; button.cell?.wraps = false
            button.attributedTitle = NSAttributedString(string: label, attributes: [.font: button.font!, .foregroundColor: current ? colors.text : colors.detail])
            let natural = ceil((label as NSString).size(withAttributes: [.font: button.font!]).width) + 8
            button.frame = NSRect(x: x, y: 0, width: min(natural, max(90, available * 0.62)), height: 18)
            button.setAccessibilityLabel(current ? label : "返回 " + label)
            button.toolTip = label
            breadcrumb.addSubview(button); x += button.frame.width
        }
        append("总览", current: false) { [weak self] in self?.focus(.root) }
        for node in path {
            let arrow = NSImageView(image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)!)
            arrow.contentTintColor = colors.detail; arrow.setAccessibilityElement(false)
            arrow.frame = NSRect(x: x + 5, y: 4, width: 8, height: 10)
            breadcrumb.addSubview(arrow); x += 20
            append(nodeTitle(node), current: node == focusedRoot) { [weak self] in self?.focus(node) }
        }
        breadcrumb.frame = NSRect(x: 0, y: 0, width: max(1, x), height: 18)
        breadcrumbScroll.contentView.scroll(to: NSPoint(x: max(0, x - available), y: 0))
    }

    func createTopic(parent: OverviewNodeID, after sibling: OverviewNodeID? = nil, position: NoteOverview.MapPosition? = nil) {
        guard parent != .unassigned, !isCard(parent), prepareStructureChange() else { return }
        let parentID: UUID? = { if case .area(let id) = parent { return id }; return nil }()
        var area = NoteOverview.Area(title: "", parentID: parentID)
        area.mapPosition = position
        guard owner?.changeOverview({ state in
            if case .area(let id) = sibling, let index = state.areas.firstIndex(where: { $0.id == id }) {
                state.areas.insert(area, at: index + 1)
            } else { state.areas.append(area) }
        }) == true else { return }
        collapsed.remove(parent)
        activeNode = .area(area.id)
        beginTopicEdit(.area(area.id))
    }

    func createSibling(of node: OverviewNodeID) {
        if case .card(let id) = node {
            owner?.createNoteInOverview(area: state.cards.first { $0.id == id }?.areaID)
            return
        }
        let parent = node == focusedRoot ? focusedRoot : OverviewTree(state).parents[node] ?? .root
        createTopic(parent: parent == .unassigned ? .root : parent, after: node)
    }

    @discardableResult func changeIndent(_ node: OverviewNodeID, outward: Bool) -> Bool {
        let tree = OverviewTree(state)
        guard node != focusedRoot, let parent = tree.parents[node] else { return false }
        let destination: OverviewNodeID
        if outward {
            guard parent != .root && parent != .unassigned else { return false }
            destination = tree.parents[parent] ?? .root
        } else {
            let siblings = tree.children[parent, default: []]
            guard let index = siblings.firstIndex(of: node), let previous = siblings[..<index].last(where: {
                if case .area = $0 { return true }; return false
            }) else { return false }
            destination = previous
        }
        return move(node, to: destination, relativeTo: outward ? parent : nil, after: outward)
    }

    func canMove(_ node: OverviewNodeID, to parent: OverviewNodeID, relativeTo target: OverviewNodeID? = nil) -> Bool {
        let tree = OverviewTree(state)
        guard tree.parents[node] != nil, node != parent, node != target, !isCard(parent),
              parent == .root || tree.parents[parent] != nil else { return false }
        if case .area = node {
            return parent != .unassigned && !tree.ancestors(of: parent).contains(node)
        }
        return isCard(node)
    }

    @discardableResult func move(_ node: OverviewNodeID, to parent: OverviewNodeID,
                                relativeTo target: OverviewNodeID? = nil, after: Bool = false) -> Bool {
        guard canMove(node, to: parent, relativeTo: target), prepareStructureChange() else { return false }
        let parentID: UUID? = { if case .area(let id) = parent { return id }; return nil }()
        let success = owner?.changeOverview { state in
            switch node {
            case .area(let id):
                guard let index = state.areas.firstIndex(where: { $0.id == id }) else { return }
                var area = state.areas.remove(at: index); area.parentID = parentID; area.mapPosition = nil
                if case .area(let targetID) = target, let at = state.areas.firstIndex(where: { $0.id == targetID }) {
                    state.areas.insert(area, at: at + (after ? 1 : 0))
                } else { state.areas.append(area) }
            case .card(let id):
                guard let index = state.cards.firstIndex(where: { $0.id == id }) else { return }
                var card = state.cards.remove(at: index); card.areaID = parentID; card.mapPosition = nil
                if case .card(let targetID) = target, let at = state.cards.firstIndex(where: { $0.id == targetID }) {
                    state.cards.insert(card, at: at + (after ? 1 : 0))
                } else { state.cards.append(card) }
            default: break
            }
        } == true
        if success {
            collapsed.remove(parent); activeNode = node
            needsLayout = true; layoutSubtreeIfNeeded(); hosts[node]?.scrollToVisible(hosts[node]?.bounds ?? .zero)
        }
        return success
    }

    func removeTopic(_ node: OverviewNodeID) {
        guard node != .root, node != .unassigned, prepareStructureChange() else { return }
        let tree = OverviewTree(state)
        let removed = Set([node] + tree.descendants(of: node))
        let cardIDs = Set(removed.compactMap { if case .card(let id) = $0 { return id }; return nil })
        _ = owner?.changeOverview { state in
            state.areas.removeAll { removed.contains(.area($0.id)) }
            state.cards.removeAll { cardIDs.contains($0.id) }
            state.connections.removeAll { cardIDs.contains($0.from) || cardIDs.contains($0.to) }
        }
        activeNode = tree.parents[node] ?? .root
    }

    func recordChange(from previous: NoteOverview) {
        guard !replayingHistory else { return }
        let grouping = structuralUndo.groupingLevel == 0
        if grouping { structuralUndo.beginUndoGrouping() }
        structuralUndo.registerUndo(withTarget: self) { $0.restoreOverview(previous) }
        structuralUndo.setActionName("编辑总览")
        if grouping { structuralUndo.endUndoGrouping() }
    }
    func restoreOverview(_ snapshot: NoteOverview) {
        guard prepareStructureChange(), let previous = owner?.overviewState else { return }
        replayingHistory = true
        defer { replayingHistory = false }
        if owner?.changeOverview({ $0 = snapshot }) == true {
            structuralUndo.registerUndo(withTarget: self) { $0.restoreOverview(previous) }
            structuralUndo.setActionName("编辑总览")
        }
    }
    @objc func undo(_ sender: Any?) { structuralUndo.undo() }
    @objc func redo(_ sender: Any?) { structuralUndo.redo() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undo(_:)) { return structuralUndo.canUndo }
        if menuItem.action == #selector(redo(_:)) { return structuralUndo.canRedo }
        return true
    }

    func beginTopicEdit(_ node: OverviewNodeID, details: Bool = false) {
        guard !isCard(node), node != .unassigned else { return }
        if topicEdit?.node == node && topicEdit?.details == details { return }
        guard prepareStructureChange() else { return }
        activeNode = node
        topicEdit = (node, details)
        let value = details ? nodeDetails(node) : nodeTitle(node)
        topicEditor.string = ""
        topicEditor.isHidden = false
        needsLayout = true; layoutSubtreeIfNeeded(); layoutTopicEditor()
        topicEditor.string = value
        topicEditor.setSelectedRange(NSRange(location: (topicEditor.string as NSString).length, length: 0))
        window?.makeFirstResponder(topicEditor)
        topicEditor.scrollToVisible(topicEditor.bounds)
    }
    func layoutTopicEditor() {
        title.isHidden = false
        for host in hosts.values { host.content.isHidden = false }
        guard let topicEdit, let plan else { topicEditor.isHidden = true; return }
        let host = topicEdit.node == plan.root ? rootHost! : hosts[topicEdit.node]
        guard let host, !host.isHidden else { return }
        let depth = plan.depths[topicEdit.node] ?? 0
        let rect: NSRect
        if topicEdit.details && topicEdit.node == plan.root {
            rect = canvas.convert(principles.frame, from: rootHost)
            principles.isHidden = true
        } else {
            rect = canvas.convert(topicEdit.details ? host.detailRect : host.textRect, from: host)
            if topicEdit.details { host.detail.isHidden = true } else { host.content.isHidden = true }
        }
        topicEditor.frame = NSRect(x: rect.minX, y: rect.minY, width: max(80, rect.width), height: max(24, rect.height))
        let size: CGFloat = topicEdit.details ? 14 : presentation == .outline ? (depth == 0 ? 34 : 16) : (depth == 0 ? 24 : depth == 1 ? 16 : 14)
        let nextFont = OverviewTypography.font(size, weight: depth == 0 && !topicEdit.details ? (presentation == .outline ? .semibold : .medium) : .regular, map: presentation == .mindMap)
        if topicEditor.font?.fontName != nextFont.fontName || topicEditor.font?.pointSize != nextFont.pointSize { topicEditor.font = nextFont }
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = topicEdit.details ? 24 : presentation == .outline ? (depth == 0 ? 54.4 : 25.6) : (depth == 0 ? 38 : depth == 1 ? 26 : 22)
        paragraph.maximumLineHeight = paragraph.minimumLineHeight
        paragraph.lineBreakMode = .byWordWrapping
        if !topicEditor.hasMarkedText() {
            topicEditor.defaultParagraphStyle = paragraph
            topicEditor.typingAttributes[.paragraphStyle] = paragraph
        }
        let nextColor = topicEdit.details ? (presentation == .outline ? colors.detail : colors.mapDetail)
            : presentation == .outline ? (depth == 0 ? colors.title : colors.text) : (depth == 0 ? colors.mapRootText : colors.mapText)
        if topicEditor.textColor != nextColor { topicEditor.textColor = nextColor }
        topicEditor.insertionPointColor = topicEditor.textColor ?? .labelColor
        topicEditor.textContainer?.containerSize = NSSize(width: topicEditor.bounds.width, height: .greatestFiniteMagnitude)
        canvas.addSubview(topicEditor, positioned: .above, relativeTo: nil)
    }
    func saveTopicText() -> Bool {
        guard let edit = topicEdit, !topicEditor.hasMarkedText() else { return topicEdit == nil }
        let value = topicEditor.string
        guard value != (edit.details ? nodeDetails(edit.node) : nodeTitle(edit.node)) else { return true }
        return owner?.changeOverview { state in
            switch edit.node {
            case .root:
                if edit.details { state.principles = value } else { state.title = value }
            case .area(let id):
                guard let index = state.areas.firstIndex(where: { $0.id == id }) else { return }
                if edit.details { state.areas[index].details = value } else { state.areas[index].title = value }
            default: break
            }
        } == true
    }
    @discardableResult func commitTopicEditing() -> Bool {
        topicSaveWork?.cancel(); topicSaveWork = nil
        guard topicEdit != nil else { return true }
        guard !endingTopicEdit else { return true }
        endingTopicEdit = true
        defer { endingTopicEdit = false }
        topicEditor.unmarkText()
        guard saveTopicText() else { return false }
        topicEdit = nil; topicEditor.isHidden = true
        if window?.firstResponder === topicEditor { window?.makeFirstResponder(self) }
        needsLayout = true
        return true
    }
    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === topicEditor, !topicEditor.hasMarkedText() else { return }
        topicSaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in _ = self?.saveTopicText() }
        topicSaveWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: work)
    }
    func textDidEndEditing(_ notification: Notification) {
        if notification.object as AnyObject? === topicEditor { _ = commitTopicEditing() }
    }
    func textView(_ textView: NSTextView, doCommandBy command: Selector) -> Bool {
        guard textView === topicEditor, let edit = topicEdit else { return false }
        if command == #selector(NSResponder.cancelOperation(_:)) {
            _ = commitTopicEditing(); window?.makeFirstResponder(self); return true
        }
        if command == #selector(NSResponder.insertNewline(_:)), !edit.details {
            guard commitTopicEditing() else { return true }
            createSibling(of: edit.node); return true
        }
        if command == #selector(NSResponder.insertTab(_:)) || command == #selector(NSResponder.insertBacktab(_:)) {
            guard commitTopicEditing() else { return true }
            if presentation == .mindMap && command == #selector(NSResponder.insertTab(_:)) { createTopic(parent: edit.node) }
            else {
                _ = changeIndent(edit.node, outward: command == #selector(NSResponder.insertBacktab(_:)))
                beginTopicEdit(edit.node, details: edit.details)
            }
            return true
        }
        return false
    }

    func handleKey(_ event: NSEvent) -> Bool {
        let text = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if event.modifierFlags.contains(.command) {
            if text == "z" { event.modifierFlags.contains(.shift) ? structuralUndo.redo() : structuralUndo.undo(); return true }
            if presentation == .mindMap && ["+", "=", "-", "0"].contains(text) {
                if text == "0" { centerRoot() } else { changeZoom(by: text == "-" ? -0.1 : 0.1) }; return true
            }
            return false
        }
        if !event.modifierFlags.intersection([.option, .control]).isEmpty { return false }
        let node = activeNode ?? focusedRoot
        switch event.keyCode {
        case 49:
            if case .card(let id) = node { toggleCardPreview(id); return true }
            return false
        case 36, 76: createSibling(of: node); return true
        case 48:
            if event.modifierFlags.contains(.shift) { _ = changeIndent(node, outward: true) }
            else if presentation == .outline { _ = changeIndent(node, outward: false) }
            else if case .card(let id) = node { owner?.toggleOverviewCard(id) }
            else { createTopic(parent: node) }
            return true
        case 51, 117: removeTopic(node); return true
        case 53: if focusedRoot != .root { focus(.root) }; return true
        case 123, 124:
            let forward = event.keyCode == 124
            let tree = OverviewTree(state)
            if forward {
                if collapsed.contains(node) { toggleBranch(node) }
                else if let child = tree.children[node]?.first { _ = select(child) }
            } else {
                if !collapsed.contains(node), tree.children[node]?.isEmpty == false { toggleBranch(node) }
                else if let parent = tree.parents[node] { _ = select(parent) }
            }
            revealActiveNode(); return true
        case 125, 126:
            guard let order = plan?.order, let index = order.firstIndex(of: node) else { return true }
            let next = index + (event.keyCode == 125 ? 1 : -1)
            if order.indices.contains(next) { _ = select(order[next]); revealActiveNode() }
            return true
        default:
            if !text.isEmpty && !event.modifierFlags.intersection([.control, .option]).isEmpty { return false }
            if !text.isEmpty, !isCard(node), node != .unassigned {
                beginTopicEdit(node)
                topicEditor.setSelectedRange(NSRange(location: 0, length: (topicEditor.string as NSString).length))
                topicEditor.insertText(event.characters ?? "", replacementRange: topicEditor.selectedRange())
                return true
            }
            return false
        }
    }
    func revealActiveNode() {
        guard let node = activeNode, let frame = plan?.frames[node] else { return }
        if presentation == .mindMap, let plan { centerWorldPoint(CGPoint(x: frame.midX - plan.worldOffset.x, y: frame.midY - plan.worldOffset.y)) }
        else { canvas.scrollToVisible(frame.insetBy(dx: -40, dy: -20)) }
    }

    func startDrag(_ node: OverviewNodeID, event: NSEvent, origin: NSEvent) {
        guard prepareStructureChange(), let window, let host = hosts[node],
              let frame = plan?.frames[node] else { return }
        let start = canvas.convert(origin.locationInWindow, from: nil)
        dragOffset = CGPoint(x: start.x - frame.minX, y: start.y - frame.minY)
        host.alphaValue = 0.45
        NSCursor.closedHand.push()
        defer {
            host.alphaValue = 1
            canvas.dropRect = nil; canvas.needsDisplay = true
            NSCursor.pop()
        }
        _ = handleDrop(node, point: canvas.convert(event.locationInWindow, from: nil), perform: false)
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) {
            if next.type == .keyDown {
                if next.keyCode == 53 { return }
                continue
            }
            let point = canvas.convert(next.locationInWindow, from: nil)
            _ = handleDrop(node, point: point, perform: next.type == .leftMouseUp)
            if next.type == .leftMouseUp { return }
        }
    }
    func handleDrop(_ node: OverviewNodeID, point: NSPoint, perform: Bool) -> Bool {
        guard let plan else { return false }
        let tree = OverviewTree(state)
        let hit = plan.order.first { plan.frames[$0]?.contains(point) == true }
        if presentation == .mindMap, hit == nil {
            let origin = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
            canvas.dropRect = CGRect(origin: origin, size: plan.frames[node]?.size ?? CGSize(width: 120, height: 44))
            canvas.needsDisplay = true
            return perform ? moveToCanvas(node, at: origin) : node != focusedRoot && node != .unassigned
        }
        var parent = focusedRoot
        var target: OverviewNodeID?
        var after = false
        var indicator = plan.frames[focusedRoot] ?? .zero
        if let hit, let rect = plan.frames[hit] {
            if presentation == .outline && hit != focusedRoot && (point.y < rect.minY + 8 || point.y > rect.maxY - 8) || isCard(hit) {
                parent = tree.parents[hit] ?? .root; target = hit; after = point.y >= rect.midY
                indicator = NSRect(x: rect.minX, y: after ? rect.maxY : rect.minY, width: rect.width, height: 1)
            } else { parent = hit; indicator = rect }
        }
        guard canMove(node, to: parent, relativeTo: target) else { canvas.dropRect = nil; canvas.needsDisplay = true; return false }
        canvas.dropRect = indicator; canvas.needsDisplay = true
        return perform ? move(node, to: parent, relativeTo: target, after: after) : true
    }
}
