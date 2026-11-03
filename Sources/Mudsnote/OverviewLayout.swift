import Foundation
import MudsnoteCore

/// Viewport-sized graph tiers. No minimum canvas width and no reserved empty
/// area columns: every first card starts immediately below the area nodes.
struct OverviewLayout {
    var areas: [UUID: CGRect]
    var cards: [UUID: CGRect]
    var size: CGSize
    var columns: Int

    static func make(width: CGFloat, height: CGFloat, state: NoteOverview, selected: UUID?) -> Self {
        let width = max(1, width)
        let margin: CGFloat = 20
        let gap: CGFloat = 24
        let usable = max(1, width - margin * 2)
        let areaColumns = max(1, min(4, Int(usable / 112)))
        let areaWidth = max(1, (usable - CGFloat(areaColumns - 1) * 8) / CGFloat(areaColumns))
        var areas: [UUID: CGRect] = [:]
        for (index, area) in state.areas.enumerated() {
            areas[area.id] = CGRect(x: margin + CGFloat(index % areaColumns) * (areaWidth + 8), y: 86 + CGFloat(index / areaColumns) * 38, width: areaWidth, height: 30)
        }
        let rows = max(1, Int(ceil(Double(state.areas.count) / Double(areaColumns))))
        var y = CGFloat(86 + rows * 38 + 16)
        let columns = width >= 520 ? 2 : 1
        let cardWidth = max(1, (usable - CGFloat(columns - 1) * gap) / CGFloat(columns))
        var cards: [UUID: CGRect] = [:]
        for start in stride(from: 0, to: state.cards.count, by: columns) {
            var rowHeight: CGFloat = 132
            for offset in 0..<columns where start + offset < state.cards.count {
                let card = state.cards[start + offset]
                let cardHeight: CGFloat = card.id == selected ? max(240, min(400, height - CGFloat(86 + rows * 38 + 16) - 20)) : 132
                cards[card.id] = CGRect(x: margin + CGFloat(offset) * (cardWidth + gap), y: y, width: cardWidth, height: cardHeight)
                rowHeight = max(rowHeight, cardHeight)
            }
            y += rowHeight + gap
        }
        return Self(areas: areas, cards: cards,
                    size: CGSize(width: width, height: max(height, y)), columns: columns)
    }
}
