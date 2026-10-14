import Foundation

// The palette's source for Router: the cards waiting on you, sessions, their actions, and the send-to-the-Router row (docs/design/palette/DESIGN.md, Sources). STUB: returns nothing yet.

@MainActor
enum PaletteRouterSource {
    static func make(_ context: PaletteContext) -> PaletteSourceOutput { PaletteSourceOutput() }
}

extension PaletteRouterSource {
    /// The last row while typing: send what is typed to the Router, which picks the session. Nil when the Router can't
    /// send (off, Claude Code not found) or the query is blank.
    static func send(_ query: String, _ context: PaletteContext) -> PaletteItem? { nil }
}
