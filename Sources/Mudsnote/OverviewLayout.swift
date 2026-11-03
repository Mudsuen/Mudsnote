import AppKit
import MudsnoteCore

enum OverviewPresentation: Int { case mindMap, outline }

enum OverviewNodeID: Hashable {
    case root, area(UUID), unassigned, card(UUID)
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
}

struct OverviewLayout {
    var frames: [OverviewNodeID: CGRect]
    var links: [(OverviewNodeID, OverviewNodeID)]
    var size: CGSize
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
                     presentation: OverviewPresentation = .mindMap, collapsed: Set<OverviewNodeID> = [], titles: [UUID: String] = [:]) -> Self {
        let tree = OverviewTree(state)
        let width = max(1, width), height = max(1, height)
        var frames: [OverviewNodeID: CGRect] = [:]
        var links: [(OverviewNodeID, OverviewNodeID)] = []
        let margin: CGFloat = 24
        func nodeHeight(_ node: OverviewNodeID) -> CGFloat {
            if case .card(let id) = node { return id == selected ? max(260, min(420, height - 48)) : 32 }
            return node == .root ? 50 : 36
        }
        func visibleChildren(_ node: OverviewNodeID) -> [OverviewNodeID] {
            collapsed.contains(node) ? [] : tree.children[node, default: []]
        }
        switch presentation {
        case .mindMap:
            let gap: CGFloat = 20
            var heights: [OverviewNodeID: CGFloat] = [:]
            func measure(_ node: OverviewNodeID) -> CGFloat {
                let children = visibleChildren(node)
                let span = children.reduce(CGFloat.zero) { $0 + measure($1) } + CGFloat(max(0, children.count - 1)) * gap
                let value = max(nodeHeight(node), span)
                heights[node] = value
                return value
            }
            let totalHeight = measure(.root)
            func place(_ node: OverviewNodeID, x: CGFloat, y: CGFloat) {
                let nodeWidth: CGFloat
                switch node {
                case .root: nodeWidth = 144
                case .area(let id):
                    let text = state.areas.first { $0.id == id }?.title ?? ""
                    nodeWidth = max(72, min(220, (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15)]).width + 28))
                case .unassigned: nodeWidth = 82
                case .card(let id):
                    let text = titles[id] ?? state.cards.first { $0.id == id }?.url.deletingPathExtension().lastPathComponent ?? ""
                    nodeWidth = id == selected ? max(360, min(600, width - 48)) : max(100, min(280, (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15)]).width + 24))
                }
                let frame = CGRect(x: x, y: y + ((heights[node] ?? 0) - nodeHeight(node)) / 2,
                                   width: nodeWidth, height: nodeHeight(node))
                frames[node] = frame
                var nextY = y
                for child in visibleChildren(node) {
                    links.append((node, child))
                    place(child, x: frame.maxX + 56, y: nextY)
                    nextY += (heights[child] ?? 0) + gap
                }
            }
            place(.root, x: margin, y: margin + max(0, (height - margin * 2 - totalHeight) / 2))
        case .outline:
            let columnWidth = min(680, max(240, width - 96))
            let leading = (width - columnWidth) / 2
            var y: CGFloat = 64
            func place(_ node: OverviewNodeID, depth: Int) {
                let indent = CGFloat(max(0, depth - 1)) * 24
                let x = leading + indent
                frames[node] = CGRect(x: x, y: y, width: max(120, columnWidth - indent), height: nodeHeight(node))
                y += nodeHeight(node) + (node == .root ? 60 : 2)
                for child in visibleChildren(node) {
                    links.append((node, child))
                    place(child, depth: depth + 1)
                }
            }
            place(.root, depth: 0)
        }
        return Self(frames: frames, links: links,
                    size: CGSize(width: max(width, (frames.values.map(\.maxX).max() ?? 0) + margin),
                                 height: max(height, (frames.values.map(\.maxY).max() ?? 0) + margin)))
    }
}
