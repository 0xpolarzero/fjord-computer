import Foundation

// The palette's source for Triage: inbox items (archive included), PR/issue numbers and URLs, categories, Triage runs, the item-session link (docs/design/palette/DESIGN.md, Sources). STUB: returns nothing yet.

@MainActor
enum PaletteTriageSource {
    static func make(_ context: PaletteContext) -> PaletteSourceOutput { PaletteSourceOutput() }
}
