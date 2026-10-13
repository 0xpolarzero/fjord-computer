import Foundation
import SwiftUI
import Testing
@testable import FjordComputer

/// The Router's canvas as data and geometry: which frames, groups and items it draws, in what order, where, and the camera.
@MainActor
@Suite struct RouterCanvasLayoutTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func card(_ id: String, _ session: String, _ folder: String?, kind: RouterCard.Kind = .question, minutes: Double = 1,
                      addressed: Bool = false) -> RouterCard {
        let at = now.addingTimeInterval(-minutes * 60)
        return RouterCard(id: id, sessionID: session, kind: kind, title: id, folder: folder, text: "", createdAt: at,
                          addressedAt: addressed ? at : nil, addressedBy: addressed ? .you : nil)
    }

    private func row(_ session: String, _ folder: String?) -> AgentRow {
        AgentRow(session: ClaudeSession(id: session, title: session, folder: folder, lastActivity: now, running: true),
                 entry: AgentEntry(id: session), label: session)
    }

    private func make(_ page: RouterPage, done: [RouterCard] = [], muted: Set<String> = [], filter: Set<CanvasGroup> = [],
                      picked: Set<String> = [], expanded: Set<String> = [], showsAll: Bool = false) -> [CanvasFolder] {
        RouterCanvasModel.make(page: page, done: done, muted: muted, name: { $0.isEmpty ? "Scratch" : URL(fileURLWithPath: $0).lastPathComponent },
                               color: { _ in .blue }, filter: filter, picked: picked, expanded: expanded, showsAll: showsAll)
    }

    @Test func theLayoutAndTheFramesFoldsAreKeptInTheWindowsPreferences() throws {
        let defaults = try #require(UserDefaults(suiteName: "RouterCanvasLayoutTests-\(UUID().uuidString)"))
        let model = RouterModel(defaults: defaults)
        // The list by default.
        #expect(model.layout == .list)
        model.layout = .canvas
        let folder = try #require(make(RouterPage(), done: [card("d", "s", "/code/app", kind: .done, addressed: true)]).first)
        #expect(model.canvas.folded(folder))
        model.canvas.toggleFold(folder)
        // The pick and the folds kept.
        let again = RouterModel(defaults: defaults)
        #expect(again.layout == .canvas && !again.canvas.folded(folder))
        again.layout = .list
        #expect(RouterModel(defaults: defaults).layout == .list)
        // Shots and tests keep nothing.
        #expect(RouterModel().layout == .list)
    }

    @Test func itemsGoToTheirFolderAndGroupScratchTooAndMutedFoldersAreLeftOut() throws {
        var page = RouterPage()
        page.needs = [card("q", "a", "/code/app")]
        page.notes = [card("n", "b", nil, kind: .done)]
        page.working = [row("w", "/code/app"), row("m", "/code/muted")]
        let folders = make(page, muted: ["/code/muted"])
        #expect(folders.map(\.key) == ["/code/app", ""])
        let app = try #require(folders.first)
        #expect(app.groups.map(\.group) == [.needs, .working])
        #expect(folders[1].name == "Scratch" && folders[1].color == nil)
    }

    @Test func aSessionInNeedsYouAndWorkingHasBothNodesKeyedAsTheListKeysThem() throws {
        var page = RouterPage()
        page.needs = [card("q", "s", "/code/app")]
        page.working = [row("s", "/code/app")]
        page.waiting = [card("wait", "t", "/code/app", kind: .waiting)]
        let ids = RouterCanvasModel.order(make(page))
        #expect(ids == ["q", RouterModel.workingID("t"), RouterModel.workingID("s")])
    }

    @Test func doneIsEachSessionsNewestAddressedCardLessSessionsShownElsewhere() {
        let history: [RouterPage.Entry] = [
            .card(card("old", "s", "/code/app", kind: .done, minutes: 9, addressed: true)),
            .card(card("other", "t", "/code/app", kind: .done, minutes: 7, addressed: true)),
            .card(card("new", "s", "/code/app", kind: .done, minutes: 5, addressed: true)),
            .card(card("live", "u", "/code/app", kind: .done, minutes: 1, addressed: true)),
        ]
        let done = RouterCanvasModel.done(history: history)
        #expect(done.map(\.id) == ["live", "new", "other"])
        var page = RouterPage()
        page.working = [row("u", "/code/app")]
        #expect(RouterCanvasModel.order(make(page, done: done)) == [RouterModel.workingID("u"), "new", "other"])
    }

    @Test func worthALookAndDoneDrawThreeThenMoreWidenedForAPickOrWhenOpened() throws {
        var page = RouterPage()
        page.notes = (1...6).map { card("n\($0)", "s\($0)", "/code/app", kind: .done) }
        let folded = try #require(make(page).first?.groups.first)
        #expect(folded.items.count == 3 && folded.more == 3)
        #expect(make(page, picked: ["n5"]).first?.groups.first?.items.count == 6)
        #expect(make(page, expanded: ["/code/app#notes"]).first?.groups.first?.more == 0)
        #expect(make(page, showsAll: true).first?.groups.first?.more == 0)
        // One past the three is drawn rather than said.
        page.notes = Array(page.notes.prefix(4))
        #expect(make(page).first?.groups.first?.items.count == 4)
    }

    @Test func busiestFoldersFirstThenByName() {
        var page = RouterPage()
        page.working = [row("a", "/code/zeta"), row("b", "/code/zeta"), row("c", "/code/alpha")]
        page.notes = [card("n", "d", "/code/beta", kind: .done)]
        page.needs = [card("q", "e", "/code/gamma")]
        #expect(make(page).map(\.name) == ["gamma", "beta", "zeta", "alpha"])
        // A frame of finished sessions only, however many, under every frame with something live.
        let done = (0..<5).map { card("d\($0)", "s\($0)", "/code/aaa", kind: .done, addressed: true) }
        #expect(make(page, done: done).map(\.name) == ["gamma", "beta", "zeta", "alpha", "aaa"])
    }

    @Test func theChipsMoreAndAPickNeverMoveAFrameToAnotherColumn() {
        var page = RouterPage()
        page.needs = [card("q", "a", "/code/a")]
        page.notes = (0..<6).map { card("n\($0)", "n\($0)", "/code/a", kind: .done) }
        page.working = [row("w", "/code/b"), row("v", "/code/c")]
        func columns(_ folders: [CanvasFolder]) -> [String: Int] {
            let c = CanvasMetrics.columns(closed: folders.map { CanvasMetrics.closedHeight($0, folded: false) }, count: 2)
            return Dictionary(uniqueKeysWithValues: zip(folders.map(\.key), c))
        }
        let base = columns(make(page))
        #expect(columns(make(page, filter: [.working])) == base)
        #expect(columns(make(page, expanded: ["/code/a#notes"])) == base)
        #expect(columns(make(page, picked: ["n5"])) == base)
    }

    @Test func theColumnsComeFromTheFramesForASixteenByTenShapeNeverFromTheWindow() {
        #expect(CanvasMetrics.columnCount(closed: []) == 1)
        #expect(CanvasMetrics.columnCount(closed: [200]) == 1)
        // Four frames of a screen's height each: side by side would be too wide, stacked too tall.
        #expect(CanvasMetrics.columnCount(closed: [300, 300, 300, 300]) == 2)
        // Many short frames spread over more columns.
        let many = CanvasMetrics.columnCount(closed: Array(repeating: 120, count: 20))
        #expect(many == 3)
        // Two tall frames side by side, two short ones one under the other.
        #expect(CanvasMetrics.columnCount(closed: [1200, 1200]) == 2)
        #expect(CanvasMetrics.columnCount(closed: [200, 200]) == 1)
    }

    @Test func framesArePackedAsMasonryAndOneYouPlacedStaysWhereYouPutItTheNewOnesUnderIt() {
        let frames: [(key: String, closed: CGFloat)] = [("a", 600), ("b", 300), ("c", 300)]
        let packed = CanvasMetrics.preferred(frames, placed: [:])
        let step = CanvasMetrics.frameWidth + CanvasMetrics.colGap
        #expect(packed["a"] == CGPoint(x: 0, y: 0))
        #expect(packed["b"] == CGPoint(x: step, y: 0))
        #expect(packed["c"] == CGPoint(x: step, y: 300 + CanvasMetrics.rowGap))
        // A frame you placed, and the others kept where they were: a new one lands under all of them.
        var placed = packed
        placed["a"] = CGPoint(x: -400, y: 800)
        let next = CanvasMetrics.preferred(frames + [("d", 50)], placed: placed)
        #expect(next["a"] == CGPoint(x: -400, y: 800) && next["b"] == packed["b"] && next["c"] == packed["c"])
        #expect(next["d"] == CGPoint(x: -400, y: 800 + 600 + CanvasMetrics.rowGap))
    }

    @Test func aFrameYouPlacedIsNeverMovedOverlapsAllowedAndOnlyPackedFramesArePushedDown() {
        let size = CGSize(width: CanvasMetrics.frameWidth, height: 200)
        let step = CanvasMetrics.frameWidth + CanvasMetrics.colGap
        // Packed, side by side and well apart: nothing moves.
        let apart = [CGPoint(x: 0, y: 0), CGPoint(x: step, y: 0), CGPoint(x: 0, y: 400)]
        #expect(CanvasMetrics.resolve(apart.map { ($0, size, false) }) == apart)
        // A card opened in a packed frame makes it taller: the packed frame under it goes down, the gap kept.
        let tall = CanvasMetrics.resolve([(CGPoint(x: 0, y: 0), CGSize(width: size.width, height: 500), false),
                                          (CGPoint(x: step, y: 0), size, false), (CGPoint(x: 0, y: 400), size, false)])
        #expect(tall == [CGPoint(x: 0, y: 0), CGPoint(x: step, y: 0), CGPoint(x: 0, y: 500 + CanvasMetrics.rowGap)])
        // Placed frames stay exactly where they are, overlapping or not, however tall they grow, wherever they are.
        let placed = [CGPoint(x: 0, y: 0), CGPoint(x: 100.5, y: 50.25), CGPoint(x: -3000, y: -2000)]
        let grown = CanvasMetrics.resolve([(placed[0], CGSize(width: size.width, height: 900), true),
                                           (placed[1], size, true), (placed[2], size, true)])
        #expect(grown == placed)
        // A packed frame never lands on a placed one: it goes under it.
        let mixed = CanvasMetrics.resolve([(CGPoint(x: 0, y: 0), size, true), (CGPoint(x: 0, y: 100), size, false)])
        #expect(mixed == [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 200 + CanvasMetrics.rowGap)])
    }

    @Test func aMeasureThatWaversByAFractionGivesTheSameSizeSoNothingMoves() {
        let a = CanvasMetrics.whole(CGSize(width: 560, height: 212.3))
        let b = CanvasMetrics.whole(CGSize(width: 560.004, height: 212.9))
        #expect(a == b && a == CGSize(width: 560, height: 213))
        let size = CGSize(width: CanvasMetrics.frameWidth, height: 200)
        let one = CanvasMetrics.resolve([(.zero, CanvasMetrics.whole(CGSize(width: 560, height: 200.2)), false), (CGPoint(x: 0, y: 260), size, false)])
        let two = CanvasMetrics.resolve([(.zero, CanvasMetrics.whole(CGSize(width: 560, height: 200.7)), false), (CGPoint(x: 0, y: 260), size, false)])
        #expect(one == two)
    }

    @Test func aFrameDroppedStaysExactlyWhereItWasLetGoOnTopAndIsKeptAcrossLaunchesUntilReset() throws {
        let defaults = try #require(UserDefaults(suiteName: "RouterCanvasLayoutTests-\(UUID().uuidString)"))
        let canvas = RouterCanvasState(defaults: defaults)
        #expect(canvas.positions.isEmpty)
        canvas.preferred = ["/code/a": CGPoint(x: 0, y: 0), "/code/b": CGPoint(x: 608, y: 0)]
        canvas.frameRects = ["/code/a": CGRect(x: 0, y: 0, width: 560, height: 300),
                             "/code/b": CGRect(x: 608, y: 120, width: 560, height: 300)]
        canvas.drag.key = "/code/a"
        canvas.drop("/code/a", offset: CGSize(width: 650.5, height: 101.25))
        // No grid, no nudge: right over b, which keeps where it was drawn.
        #expect(canvas.positions == ["/code/a": CGPoint(x: 650.5, y: 101.25), "/code/b": CGPoint(x: 608, y: 120)])
        #expect(canvas.stack == ["/code/a"] && canvas.drag.key == nil)
        // Far off, up and left.
        canvas.drop("/code/b", offset: CGSize(width: -5000, height: -4000))
        #expect(canvas.positions["/code/b"] == CGPoint(x: -4392, y: -3880) && canvas.stack == ["/code/a", "/code/b"])
        #expect(RouterCanvasState(defaults: defaults).positions == canvas.positions)
        canvas.resetLayout(reduce: true)
        #expect(canvas.positions.isEmpty && RouterCanvasState(defaults: defaults).positions.isEmpty)
    }

    @Test func aFrameResizedKeepsItsSizeAcrossLaunchesItsCardsTakeItsWidthAndResetClearsIt() throws {
        let defaults = try #require(UserDefaults(suiteName: "RouterCanvasLayoutTests-\(UUID().uuidString)"))
        let canvas = RouterCanvasState(defaults: defaults)
        #expect(canvas.width("/code/a") == CanvasMetrics.frameWidth)
        // The cards: the frame less the labels' gutter, so a wider frame shows more of them.
        #expect(CanvasMetrics.cardWidth(frame: CanvasMetrics.frameWidth) == CanvasMetrics.cardW)
        #expect(CanvasMetrics.cardWidth(frame: 900) == 900 - CanvasMetrics.cardX - CanvasMetrics.pad)
        // Never under the minimum.
        let small = CanvasMetrics.resized(CGSize(width: 560, height: 300), by: CGSize(width: -900, height: -900), width: true, height: true)
        #expect(small == CGSize(width: CanvasMetrics.minFrameWidth, height: CanvasMetrics.minFrameHeight))
        #expect(CanvasMetrics.resized(CGSize(width: 560, height: 0), by: CGSize(width: 40, height: 99), width: true, height: false)
                == CGSize(width: 600, height: 0))
        canvas.preferred = ["/code/a": CGPoint(x: 0, y: 0), "/code/b": CGPoint(x: 608, y: 0)]
        canvas.resize("/code/a", to: CGSize(width: 900, height: 0))
        #expect(canvas.width("/code/a") == 900)
        canvas.endResize("/code/a")
        // Its size kept, nothing moved: the frames keep the places they had.
        #expect(canvas.sizes["/code/a"] == CGSize(width: 900, height: 0) && canvas.drag.resizing == nil)
        #expect(canvas.positions == ["/code/a": .zero, "/code/b": CGPoint(x: 608, y: 0)])
        #expect(RouterCanvasState(defaults: defaults).sizes == canvas.sizes)
        canvas.resetLayout(reduce: true)
        #expect(canvas.sizes.isEmpty && RouterCanvasState(defaults: defaults).sizes.isEmpty)
    }

    @Test func theCameraMovesOnlyWhenYouMoveItAndIsKeptAcrossLaunches() async throws {
        let defaults = try #require(UserDefaults(suiteName: "RouterCanvasLayoutTests-\(UUID().uuidString)"))
        let canvas = RouterCanvasState(defaults: defaults)
        canvas.free = CGRect(x: 16, y: 56, width: 1000, height: 600)
        canvas.camera.transform = CanvasTransform(origin: CGPoint(x: 40, y: 30), scale: 0.5)
        canvas.camera.moved = true
        let before = canvas.camera.transform
        // A node picked or written to far off the view: a marker points to it, the camera stays.
        let far = CGRect(x: 5000, y: 100, width: 420, height: 52)
        canvas.nodeRects["far"] = far
        canvas.point(to: "far", label: "Far card")
        try await Task.sleep(for: .milliseconds(80))
        #expect(canvas.camera.transform == before && canvas.marker?.node == "far")
        // One on the view: no marker.
        canvas.nodeRects["near"] = CGRect(x: 100, y: 100, width: 420, height: 52)
        canvas.point(to: "near", label: "Near")
        try await Task.sleep(for: .milliseconds(80))
        #expect(canvas.marker?.node == "far")
        // The first look isn't taken again, whatever settles.
        canvas.frameRects = ["/code/a": CGRect(x: 0, y: 0, width: 560, height: 300)]
        canvas.fitFirst()
        #expect(canvas.camera.transform == before)
        // Kept across launches; the marker clicked moves it, as you asked.
        #expect(RouterCanvasState(defaults: defaults).camera.transform == before)
        #expect(RouterCanvasState(defaults: defaults).camera.moved)
        canvas.goToMarker(reduce: true)
        #expect(canvas.camera.transform != before && canvas.marker == nil)
        // The edge's point towards a node: on the room's edge, on the line from its centre.
        let room = CGRect(x: 0, y: 0, width: 200, height: 100)
        #expect(CanvasMetrics.edgePoint(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 1000, y: 50), in: room) == CGPoint(x: 200, y: 50))
        #expect(CanvasMetrics.edgePoint(from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: -500), in: room) == CGPoint(x: 100, y: 0))
    }


    @Test func filteredGroupsAreHiddenInPlaceAndTheOrderSkipsThem() throws {
        var page = RouterPage()
        page.needs = [card("q", "a", "/code/app")]
        page.working = [row("w", "/code/app")]
        let folder = try #require(make(page, filter: [.working]).first)
        #expect(folder.groups.map(\.hidden) == [true, false])
        #expect(RouterCanvasModel.order([folder]) == [RouterModel.workingID("w")])
        #expect(RouterCanvasModel.order([folder], folded: { _ in true }).isEmpty)
    }

    @Test func aFrameOfFinishedSessionsOnlyIsDoneOnlyAndFoldsToItsHeader() throws {
        let done = [card("d", "s", "/code/app", kind: .done, addressed: true)]
        let folder = try #require(make(RouterPage(), done: done).first)
        #expect(folder.doneOnly)
        #expect(CanvasMetrics.closedHeight(folder, folded: true) == CanvasMetrics.header)
        #expect(CanvasMetrics.closedHeight(folder, folded: false)
                == CanvasMetrics.header + CanvasMetrics.pad + CanvasMetrics.lineH)
    }

    @Test func framesGoUnderTheShortestColumnByClosedHeights() {
        #expect(CanvasMetrics.columns(closed: [300, 100, 100, 50], count: 2) == [0, 1, 1, 1])
        #expect(CanvasMetrics.columns(closed: [100, 100, 100], count: 2) == [0, 1, 0])
    }

    @Test func nodesStackGapApartAndGroupGapBetweenGroupsLabelsCentredOnTheirHeaders() {
        let placed = CanvasMetrics.folderPlacement(rows: [(.needs, 50, 20), (.needs, 30, 10), (.working, 40, 20)])
        #expect(placed.tops == [0, 56, 102])
        #expect(placed.labels[.needs] == CGFloat(43))
        #expect(placed.labels[.working] == CGFloat(122))
    }

    @Test func aConnectorLeavesTheLabelLevelAndMeetsTheHeadersMiddle() {
        let line = CanvasMetrics.connector(label: CGRect(x: 16, y: 40, width: 60, height: 22),
                                           header: CGRect(x: 124, y: 80, width: 420, height: 20))
        #expect(line.from == CGPoint(x: 82, y: 51))
        #expect(line.to == CGPoint(x: 124, y: 90))
        #expect(line.c1 == CGPoint(x: 103, y: 51) && line.c2 == CGPoint(x: 103, y: 90))
    }

    @Test func theCameraZoomsAboutThePointerFitsNeverAboveOneAndMovesTheLeastToShowARect() throws {
        let t = CanvasTransform(origin: CGPoint(x: 10, y: 20), scale: 0.5)
        let z = t.zoomed(by: 2, at: CGPoint(x: 110, y: 120))
        #expect(z.scale == 1)
        // The content point under the pointer (200, 200) stays under it.
        #expect(z.origin.x + 200 * z.scale == 110 && z.origin.y + 200 * z.scale == 120)
        #expect(t.zoomed(by: 0.1, at: .zero).scale == CanvasTransform.range.lowerBound)

        let free = CGRect(x: 16, y: 16, width: 600, height: 400)
        #expect(CanvasTransform.fit(CGRect(x: 0, y: 0, width: 100, height: 100), in: free).scale == 1)
        let all = CanvasTransform.fit(CGRect(x: 0, y: 0, width: 1200, height: 400), in: free)
        #expect(all.scale == 0.5 && all.origin == CGPoint(x: 16, y: 116))

        let at = CanvasTransform(origin: .zero, scale: 1)
        #expect(at.origin(toShow: CGRect(x: 20, y: 20, width: 100, height: 100), in: free) == nil)
        #expect(at.origin(toShow: CGRect(x: 20, y: 400, width: 100, height: 100), in: free) == CGPoint(x: 0, y: -84))
        // Taller than the room: its top at the room's top.
        #expect(at.origin(toShow: CGRect(x: 20, y: 300, width: 100, height: 900), in: free) == CGPoint(x: 0, y: -284))
    }

    @Test func aRevealGoesToTheItemDrawnOrToTheFirstOfItsGroupAndNowhereForWhatIsntDrawn() {
        var page = RouterPage()
        page.notes = [card("n", "b", "/code/b", kind: .done)]
        page.working = [row("w", "/code/a"), row("v", "/code/b")]
        let folders = make(page, done: [card("d", "z", "/code/z", kind: .done, addressed: true)])
        #expect(RouterCanvasModel.target(forReveal: "n", in: folders) == "n")
        #expect(RouterCanvasModel.target(forReveal: RouterModel.workingID("v"), in: folders) == RouterModel.workingID("v"))
        // A section of Now: its group's first item, frame by frame (busiest first: b has a note).
        #expect(RouterCanvasModel.target(forReveal: RouterZone.working.rawValue, in: folders) == RouterModel.workingID("v"))
        // The history's end, a section's fold, a frame folded away.
        #expect(RouterCanvasModel.target(forReveal: RouterModel.endID, in: folders) == nil)
        #expect(RouterCanvasModel.target(forReveal: RouterZone.foldPrefix + "working", in: folders) == nil)
        #expect(RouterCanvasModel.target(forReveal: "d", in: folders, folded: { $0.doneOnly }) == nil)
        #expect(RouterCanvasModel.target(forReveal: "d", in: folders) == "d")
    }
}
