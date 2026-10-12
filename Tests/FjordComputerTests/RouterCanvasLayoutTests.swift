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
        #expect(model.layout == .list)
        model.layout = .canvas
        let folder = try #require(make(RouterPage(), done: [card("d", "s", "/code/app", kind: .done, addressed: true)]).first)
        #expect(model.canvas.folded(folder))
        model.canvas.toggleFold(folder)
        let again = RouterModel(defaults: defaults)
        #expect(again.layout == .canvas && !again.canvas.folded(folder))
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
        #expect(CanvasMetrics.columns(closed: [300, 100, 100, 50]) == [0, 1, 1, 1])
        #expect(CanvasMetrics.columns(closed: [100, 100, 100]) == [0, 1, 0])
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
}
