import Testing
@testable import FjordComputer

@MainActor
@Suite struct ShotCatalogTests {
    /// A shot is a file named after it: two with one name would overwrite each other, and the set would leave fewer files
    /// than it says.
    @Test func everyShotHasItsOwnName() {
        var seen = Set<String>()
        let repeated = PlaygroundShots.catalog.map(\.name).filter { !seen.insert($0).inserted }
        #expect(repeated.isEmpty, "Shots named more than once: \(repeated)")
    }

    @Test func aFilterKeepsTheShotsWhoseNameContainsIt() {
        #expect(PlaygroundShots.select([]).count == PlaygroundShots.catalog.count)
        #expect(PlaygroundShots.select(["right-rest"]).map(\.name).contains("right-rest"))
        #expect(PlaygroundShots.select(["RIGHT-REST"]).allSatisfy { $0.name.contains("right-rest") })
        #expect(PlaygroundShots.select(["zzz-no-such-shot"]).isEmpty)
        let two = PlaygroundShots.select(["left-rest", "bottom-rest"])
        #expect(two.allSatisfy { $0.name.contains("left-rest") || $0.name.contains("bottom-rest") } && !two.isEmpty)
    }
}
