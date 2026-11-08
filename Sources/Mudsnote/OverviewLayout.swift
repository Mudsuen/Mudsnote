import AppKit
import MudsnoteCore

enum OverviewPresentation: Int { case mindMap, outline }

enum OverviewNodeID: Hashable {
    case root, area(UUID), unassigned, card(UUID)

    var dragString: String {
        switch self { case .root: return "root"; case .unassigned: return "unassigned"
        case .area(let id): return "area:" + id.uuidString; case .card(let id): return "card:" + id.uuidString }
    }
    init?(dragString: String) {
        if dragString == "unassigned" { self = .unassigned; return }
        if dragString == "root" { self = .root; return }
        let parts = dragString.split(separator: ":")
        guard parts.count == 2, let id = UUID(uuidString: String(parts[1])) else { return nil }
        switch parts[0] { case "area": self = .area(id); case "card": self = .card(id); default: return nil }
    }
}

/// Both presentations use the same ownership tree. Cross-note associations are
/// separate edges, never a second parent or a second copy of a note.
struct OverviewTree {
    var children: [OverviewNodeID: [OverviewNodeID]] = [:]
    var parents: [OverviewNodeID: OverviewNodeID] = [:]

    init(_ state: NoteOverview) {
        let areaIDs = Set(state.areas.map(\.id))
        var visited = Set<UUID>()
        func append(_ area: NoteOverview.Area, to parent: OverviewNodeID) {
            guard visited.insert(area.id).inserted else { return }
            let node = OverviewNodeID.area(area.id)
            children[parent, default: []].append(node)
            parents[node] = parent
            for child in state.areas where child.parentID == area.id { append(child, to: node) }
        }
        for area in state.areas where area.parentID == nil || !areaIDs.contains(area.parentID!) || area.parentID == area.id {
            append(area, to: .root)
        }
        // Keep orphaned/cyclic imported metadata reachable without changing it.
        for area in state.areas where !visited.contains(area.id) { append(area, to: .root) }
        for card in state.cards {
            let parent = card.areaID.flatMap { areaIDs.contains($0) ? OverviewNodeID.area($0) : nil } ?? .unassigned
            if parent == .unassigned, parents[.unassigned] == nil {
                children[.root, default: []].append(.unassigned)
                parents[.unassigned] = .root
            }
            let node = OverviewNodeID.card(card.id)
            children[parent, default: []].append(node)
            parents[node] = parent
        }
    }

    func ancestors(of node: OverviewNodeID) -> [OverviewNodeID] {
        var result: [OverviewNodeID] = []
        var current = parents[node]
        while let parent = current { result.append(parent); current = parents[parent] }
        return result
    }

    func descendants(of node: OverviewNodeID) -> [OverviewNodeID] {
        children[node, default: []].flatMap { [$0] + descendants(of: $0) }
    }
}

struct OverviewLayout {
    var frames: [OverviewNodeID: CGRect]
    var links: [(OverviewNodeID, OverviewNodeID)]
    var size: CGSize
    var contentBounds: CGRect
    var depths: [OverviewNodeID: Int]
    var sides: [OverviewNodeID: CGFloat]
    var order: [OverviewNodeID]
    var root: OverviewNodeID
    var presentation: OverviewPresentation
    var worldOffset: CGPoint
    var areas: [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: frames.compactMap { key, value in
            if case .area(let id) = key { return (id, value) }; return nil
        })
    }
    var cards: [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: frames.compactMap { key, value in
            if case .card(let id) = key { return (id, value) }; return nil
        })
    }

    @MainActor static func make(width: CGFloat, height: CGFloat, state: NoteOverview, selected: UUID?,
                     presentation: OverviewPresentation = .mindMap, collapsed: Set<OverviewNodeID> = [],
                     titles: [UUID: String] = [:], root requestedRoot: OverviewNodeID = .root,
                     structure: OverviewMapStructure = .right) -> Self {
        let tree = OverviewTree(state)
        let root = requestedRoot == .root || tree.parents[requestedRoot] != nil ? requestedRoot : .root
        let width = max(1, width), height = max(1, height)
        let editorSize = CGSize(width: min(360, max(280, width * 0.38)),
                                height: min(240, max(160, height * 0.36)))
        let outlineAvailable = max(120, width - 11.5)
        let outlineWrapper = min(872, outlineAvailable)
        let outlineColumn = max(120, outlineWrapper - 105)
        let outlineLeading = max(0, (outlineAvailable - outlineWrapper) / 2) + 52.5
        var frames: [OverviewNodeID: CGRect] = [:]
        var links: [(OverviewNodeID, OverviewNodeID)] = []
        var depths: [OverviewNodeID: Int] = [:]
        var sides: [OverviewNodeID: CGFloat] = [:]
        var order: [OverviewNodeID] = []
        var worldOffset = CGPoint.zero
        let floating = Dictionary(uniqueKeysWithValues: tree.descendants(of: root).compactMap { node -> (OverviewNodeID, NoteOverview.MapPosition)? in
            let position: NoteOverview.MapPosition?
            switch node {
            case .area(let id): position = state.areas.first { $0.id == id }?.mapPosition
            case .card(let id): position = state.cards.first { $0.id == id }?.mapPosition
            default: position = nil
            }
            guard let position, position.scope == root.dragString,
                  position.x.isFinite, position.y.isFinite, abs(position.x) < 1e12, abs(position.y) < 1e12 else { return nil }
            return (node, position)
        })
        func label(_ node: OverviewNodeID) -> String {
            switch node {
            case .root: return state.title ?? "我的生活"
            case .area(let id): return state.areas.first { $0.id == id }?.title ?? ""
            case .unassigned: return "未归属"
            case .card(let id): return titles[id] ?? state.cards.first { $0.id == id }?.url.deletingPathExtension().lastPathComponent ?? ""
            }
        }
        func details(_ node: OverviewNodeID) -> String {
            switch node {
            case .root: return state.principles
            case .area(let id): return state.areas.first { $0.id == id }?.details ?? ""
            default: return ""
            }
        }
        func children(_ node: OverviewNodeID) -> [OverviewNodeID] {
            guard !collapsed.contains(node) || node == root else { return [] }
            return tree.children[node, default: []].filter { child in
                guard presentation == .mindMap else { return true }
                if floating[child] != nil { return false }
                if child == .unassigned { return tree.children[child, default: []].contains { floating[$0] == nil } }
                return true
            }
        }
        var nodeSizes: [OverviewNodeID: CGSize] = [:]
        func measureNode(_ node: OverviewNodeID, depth: Int) -> CGSize {
            if let cached = nodeSizes[node] { return cached }
            let size: CGSize
            if presentation == .outline {
                let w = max(120, outlineColumn - CGFloat(max(0, depth - 1)) * 28)
                let h: CGFloat
                if node == root { h = OverviewTypography.textHeight(label(node), width: w, size: 34, lineHeight: 54.4, weight: .semibold) }
                else if case .card(let id) = node, id == selected { h = editorSize.height }
                else { h = 6 + OverviewTypography.textHeight(label(node), width: w - 31, size: 16, lineHeight: 25.6) + OverviewTypography.detailHeight(details(node), width: w - 31) }
                let selectedCard: Bool = { if case .card(let id) = node { return id == selected }; return false }()
                size = CGSize(width: selectedCard ? min(w, editorSize.width) : w, height: h)
            } else {
                let fontSize: CGFloat = depth == 0 ? 24 : depth == 1 ? 16 : 14
                let padding: CGFloat = depth == 0 ? 48 : depth == 1 ? 32 : 64
                let textWidth = OverviewTypography.width(label(node), size: fontSize, weight: depth == 0 ? .medium : .regular, map: true)
                var w = max(48, min(500, textWidth) + padding)
                let detailPadding: CGFloat = depth == 0 ? 32 : depth == 1 ? 42 : 74
                if !details(node).isEmpty {
                    w = max(w, min(420, OverviewTypography.width(details(node), size: 14, map: true) + detailPadding))
                }
                let lineHeight: CGFloat = depth == 0 ? 38 : depth == 1 ? 26 : 22
                var h = OverviewTypography.textHeight(label(node), width: w - padding, size: fontSize, lineHeight: lineHeight, weight: depth == 0 ? .medium : .regular, map: true) + (depth < 2 ? 24 : 22)
                h += OverviewTypography.detailHeight(details(node), width: w - detailPadding)
                if case .card(let id) = node, id == selected {
                    w = editorSize.width; h = editorSize.height
                }
                size = CGSize(width: w, height: h)
            }
            nodeSizes[node] = size
            return size
        }
        if presentation == .outline {
            let leading = outlineLeading
            var y: CGFloat = 48
            func place(_ node: OverviewNodeID, depth: Int) {
                let size = measureNode(node, depth: depth)
                depths[node] = depth; sides[node] = 1; order.append(node)
                frames[node] = CGRect(x: leading + CGFloat(max(0, depth - 1)) * 28, y: y, width: size.width, height: size.height)
                y += size.height
                if node == root { y += 18 + OverviewTypography.detailHeight(details(root), width: size.width) }
                for child in children(node) {
                    links.append((node, child)); place(child, depth: depth + 1)
                }
            }
            place(root, depth: 0)
        } else {
            struct Metrics { var span: CGFloat; var anchor: CGFloat; var children: [(OverviewNodeID, CGFloat)] }
            var metrics: [OverviewNodeID: Metrics] = [:]
            func anchorOffset(_ node: OverviewNodeID, depth: Int) -> CGFloat {
                let h = measureNode(node, depth: depth).height
                return depth < 2 ? h / 2 : h
            }
            @discardableResult func measure(_ node: OverviewNodeID, depth: Int) -> Metrics {
                depths[node] = depth
                let h = measureNode(node, depth: depth).height
                let visible = children(node)
                guard !visible.isEmpty else {
                    let m = Metrics(span: h, anchor: anchorOffset(node, depth: depth), children: [])
                    metrics[node] = m; return m
                }
                var offsets: [(OverviewNodeID, CGFloat)] = []
                var y: CGFloat = 0
                for child in visible {
                    let m = measure(child, depth: depth + 1)
                    offsets.append((child, y)); y += m.span
                }
                let first = offsets.first!, last = offsets.last!
                let anchor = (first.1 + metrics[first.0]!.anchor + last.1 + metrics[last.0]!.anchor) / 2
                let top = min(0, anchor - anchorOffset(node, depth: depth))
                let bottom = max(y, anchor - anchorOffset(node, depth: depth) + h)
                let m = Metrics(span: bottom - top, anchor: anchor - top, children: offsets.map { ($0.0, $0.1 - top) })
                metrics[node] = m; return m
            }
            func place(_ node: OverviewNodeID, x: CGFloat, top: CGFloat, depth: Int, side: CGFloat) {
                let size = measureNode(node, depth: depth), m = metrics[node]!
                frames[node] = CGRect(x: x, y: top + m.anchor - anchorOffset(node, depth: depth), width: size.width, height: size.height)
                sides[node] = side; order.append(node)
                let gap: CGFloat = depth == 0 ? 80 : depth == 1 ? 26 : 0
                for (child, offset) in m.children {
                    links.append((node, child))
                    let childSize = measureNode(child, depth: depth + 1)
                    let childX = side > 0 ? x + size.width + gap : x - gap - childSize.width
                    place(child, x: childX, top: top + offset, depth: depth + 1, side: side)
                }
            }
            let rootSize = measureNode(root, depth: 0)
            depths[root] = 0; sides[root] = 1; order.append(root)
            frames[root] = CGRect(x: 0, y: -rootSize.height / 2, width: rootSize.width, height: rootSize.height)
            let visible = children(root)
            let rightCount = structure == .balanced ? (visible.count + 1) / 2 : visible.count
            for (side, nodes) in [(CGFloat(1), Array(visible.prefix(rightCount))), (CGFloat(-1), Array(visible.dropFirst(rightCount)))] {
                guard !nodes.isEmpty else { continue }
                var offsets: [(OverviewNodeID, CGFloat)] = []; var y: CGFloat = 0
                for child in nodes {
                    let m = measure(child, depth: 1); offsets.append((child, y)); y += m.span
                }
                let first = offsets.first!, last = offsets.last!
                let center = (first.1 + metrics[first.0]!.anchor + last.1 + metrics[last.0]!.anchor) / 2
                for (child, offset) in offsets {
                    links.append((root, child))
                    let childSize = measureNode(child, depth: 1)
                    place(child, x: side > 0 ? rootSize.width + 80 : -80 - childSize.width,
                          top: offset - center, depth: 1, side: side)
                }
            }
            for node in tree.descendants(of: root) {
                guard let position = floating[node], !tree.ancestors(of: node).contains(where: { $0 != root && collapsed.contains($0) }) else { continue }
                let depth = (tree.ancestors(of: node).firstIndex(of: root) ?? 0) + 1
                let m = measure(node, depth: depth)
                let side: CGFloat = position.x >= rootSize.width / 2 ? 1 : -1
                place(node, x: position.x, top: position.y - m.anchor + anchorOffset(node, depth: depth), depth: depth, side: side)
            }
            let shift = CGPoint(x: width, y: height)
            worldOffset = shift
            frames = frames.mapValues { $0.offsetBy(dx: shift.x, dy: shift.y) }
        }
        let bounds = frames.values.reduce(CGRect.null) { $0.union($1) }
        let size = presentation == .mindMap
            ? CGSize(width: width * 3, height: height * 3)
            : CGSize(width: max(width, bounds.maxX + 24), height: max(height, bounds.maxY + 48))
        return Self(frames: frames, links: links, size: size, contentBounds: bounds, depths: depths, sides: sides, order: order, root: root, presentation: presentation, worldOffset: worldOffset)
    }
}
