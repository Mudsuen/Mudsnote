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
        var frames: [OverviewNodeID: CGRect] = [:]
        var links: [(OverviewNodeID, OverviewNodeID)] = []
        var depths: [OverviewNodeID: Int] = [:]
        var sides: [OverviewNodeID: CGFloat] = [:]
        var order: [OverviewNodeID] = []
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
            collapsed.contains(node) && node != root ? [] : tree.children[node, default: []]
        }
        var nodeSizes: [OverviewNodeID: CGSize] = [:]
        func measureNode(_ node: OverviewNodeID, depth: Int) -> CGSize {
            if let cached = nodeSizes[node] { return cached }
            let size: CGSize
            if presentation == .outline {
                let column = min(767, max(200, width - 96))
                let w = max(120, column - CGFloat(max(0, depth - 1)) * 28)
                let h: CGFloat
                if node == root { h = OverviewTypography.textHeight(label(node), width: w, size: 34, lineHeight: 54.4, weight: .semibold) }
                else if case .card(let id) = node, id == selected { h = max(280, min(420, height - 48)) }
                else { h = 6 + OverviewTypography.textHeight(label(node), width: w - 31, size: 16, lineHeight: 25.6) + OverviewTypography.detailHeight(details(node), width: w - 31) }
                size = CGSize(width: w, height: h)
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
                    w = max(360, min(600, width - 48)); h = max(280, min(420, height - 48))
                }
                size = CGSize(width: w, height: h)
            }
            nodeSizes[node] = size
            return size
        }
        if presentation == .outline {
            let leading = (width - min(767, max(200, width - 96))) / 2
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
            let raw = frames.values.reduce(CGRect.null) { $0.union($1) }
            let shift = CGPoint(x: width - raw.minX, y: height - raw.minY)
            frames = frames.mapValues { $0.offsetBy(dx: shift.x, dy: shift.y) }
        }
        let bounds = frames.values.reduce(CGRect.null) { $0.union($1) }
        let size = presentation == .mindMap
            ? CGSize(width: bounds.maxX + width, height: bounds.maxY + height)
            : CGSize(width: max(width, bounds.maxX + 24), height: max(height, bounds.maxY + 48))
        return Self(frames: frames, links: links, size: size, contentBounds: bounds, depths: depths, sides: sides, order: order, root: root)
    }
}
