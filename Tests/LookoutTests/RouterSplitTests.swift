import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lookout

/// How the Router's page is shared between the history and the zones.
@MainActor
@Suite(.hostsWindows) struct RouterSplitTests {
    @Test func theSnapPointsGiveEachSideThreeQuartersWithinTheFloors() {
        let page: CGFloat = 1000
        #expect(RouterSplit.room(page: page, share: RouterSplit.historyBig) == 250)
        // The history keeps its floor (28% of a tall page): the zones' three quarters stop short of it.
        #expect(RouterSplit.historyFloor(page: page) == 280)
        #expect(RouterSplit.room(page: page, share: RouterSplit.zonesBig) == 720)
        // Dragged past either floor, the line stops there.
        #expect(RouterSplit.room(page: page, share: 0) == RouterSplit.zonesFloor)
        #expect(RouterSplit.room(page: page, share: 1) == 720)
        #expect(RouterSplit.dragged(from: 500, by: 900, page: page) == RouterSplit.zonesFloor / page)
        #expect(RouterSplit.dragged(from: 500, by: -900, page: page) == 0.72)
        // A page too short for both floors: the history's wins.
        #expect(RouterSplit.room(page: 200, share: 0.5) == 100)
    }

    @Test func zonesThatNeedLessThanTheirShareTakeOnlyThat() {
        #expect(RouterSplit.zones(natural: 180, page: 1000, share: RouterSplit.zonesBig) == 180)
        #expect(RouterSplit.zones(natural: 900, page: 1000, share: RouterSplit.zonesBig) == 720)
        #expect(RouterSplit.zones(natural: 900, page: 1000, share: RouterSplit.historyBig) == 250)
    }

    @Test func dragAndKeysMoveTheLineFromWhereItShows() {
        // The zones show 300 of their 720: dragging up 100 asks for 400, down 100 for 200.
        #expect(RouterSplit.dragged(from: 300, by: -100, page: 1000) == 0.4)
        #expect(RouterSplit.dragged(from: 300, by: 100, page: 1000) == 0.2)
        #expect(RouterSplit.adjusted(shown: 300, page: 1000, up: true) == 0.4)
        #expect(abs(RouterSplit.adjusted(shown: 300, page: 1000, up: false) - 0.2) < 0.0001)
    }

    @Test func theChevronSwitchesToTheOtherSnapPoint() {
        // Zones taking more than the history-big split gives them: down, to give the history the room.
        #expect(RouterSplit.zonesAreBig(shown: 600, page: 1000))
        #expect(RouterSplit.toggled(shown: 600, page: 1000) == RouterSplit.historyBig)
        // At the history-big split (or smaller): up.
        #expect(!RouterSplit.zonesAreBig(shown: 250, page: 1000))
        #expect(RouterSplit.toggled(shown: 250, page: 1000) == RouterSplit.zonesBig)
    }

    @Test func theWorkingCardTakesAPartOfTheRoomUnlessNothingWaits() {
        #expect(RouterSplit.workingCap(room: 700, needsEmpty: false) == 280)
        #expect(RouterSplit.workingCap(room: 700, needsEmpty: true) == 630)
        #expect(RouterSplit.workingCap(room: 100, needsEmpty: false) == 56)
    }

    @Test func theSplitIsKeptAcrossLaunches() throws {
        let store = Store()
        store.persists = false
        #expect(store.router.zonesShare == nil)
        store.setZonesShare(RouterSplit.historyBig)
        let back = try JSONDecoder().decode(RouterState.self, from: JSONEncoder().encode(store.router))
        #expect(back.zonesShare == Double(RouterSplit.historyBig))
        let old = try JSONDecoder().decode(RouterState.self, from: Data(#"{"enabled":true}"#.utf8))
        #expect(old.zonesShare == nil)
    }

    /// The history's height on the demo page, its zones holding `needs` copies of each open card, at a share.
    private func historyHeight(share: CGFloat?, copies: Int, working: Bool = true) async -> CGFloat {
        let store = Store()
        Demo.populate(store, .router)
        store.interceptOpen = { _ in }
        let open = store.router.cards.filter(\.isOpen)
        if copies == 0 {
            store.router.cards = store.router.cards.map { var c = $0; c.addressedAt = Date(); c.addressedBy = .you; return c }
        } else {
            store.router.cards += (1..<copies).flatMap { n in open.map { var c = $0; c.id += "#copy\(n)"; return c } }
        }
        if !working { for id in store.routerWorkingRows.map(\.id) { store.claudeSessions[id]?.running = false; store.claudeTasks[id] = nil } }
        if let share { store.setZonesShare(share) }
        let hosting = NSHostingView(rootView: RouterCodeView(store: store, model: RouterModel(), checksClaudeCode: false)
            .frame(width: 1100, height: 900))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900), styleMask: .borderless, backing: .buffered,
                              defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }
        func scrolls(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrolls) }
        func history() -> CGFloat {
            hosting.layoutSubtreeIfNeeded()
            return scrolls(hosting).filter { $0.frame.height > 0 }.map { $0.convert($0.bounds, to: nil) }.max { $0.maxY < $1.maxY }?.height ?? 0
        }
        await waitUntil { history() > 0 }
        await waitUntilSteady(turns: 8) { Int(history()) }
        return history()
    }

    @Test func eachSnapPointGivesItsSideTheRoomOnAFullPage() async {
        let historyBig = await historyHeight(share: RouterSplit.historyBig, copies: 6)
        let zonesBig = await historyHeight(share: RouterSplit.zonesBig, copies: 6)
        #expect(historyBig > zonesBig + 200, "history big \(historyBig), zones big \(zonesBig)")
        #expect(zonesBig >= 140, "the history keeps its floor: \(zonesBig)")
        // Nothing needs you and nothing works: the zones take only their line, whatever their share.
        let empty = await historyHeight(share: RouterSplit.zonesBig, copies: 0, working: false)
        #expect(empty > historyBig, "content wins: \(empty)")
    }
}
