import SwiftUI

// How the Router's page is laid out: Now (the live sections, one scroll) and History, side by side in a wide window and one
// at a time with a switch in a narrow one; each section of Now folds to its header line, as you last left it.

/// The Router's page in a narrow window: what's live, or the history.
enum RouterPane: String {
    case now, history
}

/// How Now is drawn: the list of sections, or the canvas (each project a frame, its sessions grouped and joined to their
/// group by lines), a beta picked in the Router's top bar; the list by default. Kept across launches with the window's other
/// preferences.
enum RouterLayout: String {
    case list, canvas, lanes, brief

    static let key = "routerLayout"
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

extension RouterZone {
    /// Where the folds are kept in the window's preferences.
    static let foldsKey = "routerFoldedZones"

    /// The folds kept in `defaults`; none kept (or no preferences: shots and tests), Waiting and Working.
    static func folds(in defaults: UserDefaults?) -> Set<RouterZone> {
        guard let kept = defaults?.stringArray(forKey: foldsKey) else { return foldedAtFirst }
        return Set(kept.compactMap(RouterZone.init(rawValue:)))
    }
}
