import SwiftUI

// How the Router's page is laid out: Now (the live sections, one scroll) and History, side by side in a wide window and one
// at a time with a switch in a narrow one; each section of Now folds to its header line, as you last left it.

/// The Router's page in a narrow window: what's live, or the history.
enum RouterPane: String {
    case now, history
}

/// A section of Now, top to bottom by whose move is next.
enum RouterZone: String, CaseIterable, Identifiable {
    case needs, notes, waiting, working

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needs: "Needs you"
        case .notes: "Worth a look"
        case .waiting: "Waiting"
        case .working: "Working"
        }
    }

    var symbol: String {
        switch self {
        case .needs: "exclamationmark.circle"
        case .notes: "eye"
        case .waiting: "hourglass"
        case .working: "circle.dotted"
        }
    }

    /// Waiting and Working run on their own: folded to a line until you open them.
    static let foldedAtFirst: Set<RouterZone> = [.waiting, .working]

    /// What the page scrolls to for the section, its header at the top.
    var anchorID: String { "zone#" + rawValue }

    /// Whether the page is wide enough for Now and History side by side.
    static func sideBySide(width: CGFloat) -> Bool { width >= 1040 }
}

extension Store {
    /// The sections of Now folded, as you last left them.
    var routerFolded: Set<RouterZone> {
        router.foldedZones.map { Set($0.compactMap(RouterZone.init(rawValue:))) } ?? RouterZone.foldedAtFirst
    }

    /// Folds a section of Now, or opens it, kept across launches.
    func setRouterZone(_ zone: RouterZone, folded: Bool) {
        var set = routerFolded
        if folded { set.insert(zone) } else { set.remove(zone) }
        guard router.foldedZones.map(Set.init) != Set(set.map(\.rawValue)) else { return }
        var state = router
        state.foldedZones = RouterZone.allCases.filter(set.contains).map(\.rawValue)
        router = state
    }
}
