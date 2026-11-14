import AppKit
import MudsnoteCore

/// Rebuilt when overview content changes, shared by navigation and layout.
/// Panning, selection and animation must not rebuild the ownership tree.
struct OverviewContentIndex {
    let tree: OverviewTree
    let areas: [UUID: NoteOverview.Area]
    let cards: [UUID: NoteOverview.Card]

    init(_ state: NoteOverview) {
        tree = OverviewTree(state)
        areas = Dictionary(state.areas.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        cards = Dictionary(state.cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func displayTitle(_ title: String?, fallback: String) -> String {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return fallback }
        return title
    }
}

struct OverviewLayoutKey: Equatable {
    var revision: Int
    var viewport: CGSize
    var selected: UUID?
    var presentation: OverviewPresentation
    var collapsed: Set<OverviewNodeID>
    var root: OverviewNodeID
    var structure: OverviewMapStructure
    var expanded: Set<UUID>
}

struct OverviewBreadcrumbKey: Equatable {
    var path: [OverviewNodeID]
    var titles: [String]
    var width: CGFloat
    var dark: Bool
}
