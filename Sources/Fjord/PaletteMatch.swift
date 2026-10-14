import Foundation

// The palette's matcher and ranking (docs/design/palette/DESIGN.md, Ranking). STUB: a plain folded substring match, to be
// replaced by the tiered matcher; the signatures are the contract the model relies on.

/// Text folded for matching: lowercased, accents dropped, œ/æ spelled out.
enum PaletteText {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

/// One ranked row: the item, and the ranges of its title the query matched (for the highlight).
struct PaletteHit: Identifiable {
    let item: PaletteItem
    let ranges: [Range<String.Index>]
    var id: String { item.id }
}

/// The items of one open palette, prepared once (folded text) so each keystroke only scores.
struct PaletteIndex {
    let items: [PaletteItem]
    init(_ items: [PaletteItem]) { self.items = items }
}

@MainActor
enum PaletteRanker {
    /// The items matching `query`, best first, at most `limit`. An empty query matches nothing (the empty palette shows
    /// its groups instead).
    static func rank(_ query: String, in index: PaletteIndex, usage: PaletteUsage?, now: Date = Date(), limit: Int = 50)
        -> [PaletteHit] {
        let q = PaletteText.fold(query).trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return index.items.filter { PaletteText.fold(([$0.title] + $0.keywords).joined(separator: " ")).contains(q) }
            .prefix(limit).map { PaletteHit(item: $0, ranges: []) }
    }
}

/// What was picked, when, and after typing what: the palette's memory, kept in the user's defaults.
@MainActor
final class PaletteUsage {
    private let defaults: UserDefaults?
    private var picks: [String] = []

    /// `defaults`: nil keeps nothing (demo, shots, tests).
    init(defaults: UserDefaults?) { self.defaults = defaults }

    /// Remembers a pick of `itemID` after typing `query` (empty: picked from the empty palette).
    func record(_ itemID: String, query: String, now: Date = Date()) {
        picks.removeAll { $0 == itemID }
        picks.insert(itemID, at: 0)
    }

    /// The ids picked last, newest first.
    func recent(_ count: Int) -> [String] { Array(picks.prefix(count)) }
}
