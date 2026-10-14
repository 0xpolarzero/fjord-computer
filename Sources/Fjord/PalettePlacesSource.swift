import Foundation

// The palette's source for places: pages, settings rows, commands, computers, snippets, projects (docs/design/palette/DESIGN.md, Sources). STUB: returns nothing yet.

@MainActor
enum PalettePlacesSource {
    static func make(_ context: PaletteContext) -> PaletteSourceOutput { PaletteSourceOutput() }
}
