import AppKit
import SwiftUI
import Testing
@testable import FjordComputer

/// The bar's panel stays open while the pointer is anywhere on the bar or the panel, and closes once it leaves both.
///
/// The bar runs in its real window (off screen), driven by a pointer the test moves: the controller hears a move only the way
/// it would in the app (its system-wide monitor while it runs, the window's own events while it takes the mouse, the arming
/// window over the bar at rest), and the hovers SwiftUI would report (a section, a category cell, a row) are applied as the
/// pointer reaches them. Where things are drawn comes from the accessibility tree, which SwiftUI builds from the layout it
/// draws, so "on the panel" means where the user sees it, not what the controller believes.
extension WindowSeams {
    @MainActor
    @Suite(.hostsWindows) struct HubPointerRetention {
        static let edges: [DockEdge] = [.right, .left, .top, .bottom]

        /// An element of the hub as drawn: its label and where it is on screen.
        struct Drawn: Equatable {
            let role: String
            let label: String
            let frame: NSRect
            var centre: NSPoint { NSPoint(x: frame.midX, y: frame.midY) }
        }

        @MainActor final class Rig {
            let store: Store
            let controller: HubController
            let window: NSWindow
            let host: NSView
            var hub: HubState { controller.hub }
            var edge: DockEdge { controller.ui.edge }
            var pointer = NSPoint(x: -100_000, y: -100_000)
            /// Where the pointer was heard but the hub didn't count it as on the hub, though it was drawn there.
            var dropped: [String] = []
            var hoveredSection: HubSection?

            init(edge: DockEdge, scenario: Demo.Scenario, origin: NSPoint? = nil) async {
                _ = NSApplication.shared
                NSApp.perform(NSSelectorFromString("setAccessibilityEnhancedUserInterface:"), with: true as NSNumber)
                store = Store()
                store.persists = false
                Demo.populate(store, scenario)
                controller = HubController(store: store, demo: true, arguments: ["FjordComputer", "--edge", edge.rawValue])
                window = NSApp.windows.first { [controller] in
                    ($0.contentView as? NSHostingView<HubRoot>)?.rootView.hub === controller.hub
                }!
                host = window.contentView!
                controller.mouseButtons = { 0 }
                if let origin { window.setFrameOrigin(origin) }
                #expect(!NSScreen.screens.contains { $0.frame.intersects(window.frame) })
                controller.mouseLocation = { [unowned self] in pointer }
                await settle()
                // At rest, off the hub: nothing system-wide watches the pointer.
                await move(to: away)
            }

            func close() {
                hub.section = nil
                window.orderOut(nil)
            }

            /// Far from the bar, outside its window.
            var away: NSPoint { NSPoint(x: window.frame.midX, y: window.frame.minY - 300) }

            /// Whether the controller hears a move to `p`, as the app would.
            func heard(_ p: NSPoint) -> Bool {
                controller.watchesGlobally
                    || (!window.ignoresMouseEvents && window.frame.contains(p))
                    || controller.triggerFrame?.contains(p) == true
            }

            /// Moves the pointer; the controller hears it if it would in the app.
            func move(to p: NSPoint, expectOnHub: Bool? = nil, _ what: @autoclosure () -> String = "") async {
                pointer = p
                if heard(p) { controller.mouseMoved() }
                // The hover it starts runs on the next turn.
                await Task.yield()
                await Task.yield()
                if expectOnHub == true, window.ignoresMouseEvents {
                    dropped.append("\(edge) \(what()) at \(p): drawn on the hub, but the window let the pointer through")
                }
            }

            /// Moves the pointer there in 2pt steps, staying on what is drawn (each point is on the bar or the panel).
            func walk(to target: NSPoint, onHub: Bool = true, _ what: String) async {
                let start = pointer
                let d = hypot(target.x - start.x, target.y - start.y)
                let steps = max(1, Int((d / 2).rounded(.up)))
                for i in 1...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    await move(to: NSPoint(x: start.x + (target.x - start.x) * t, y: start.y + (target.y - start.y) * t),
                               expectOnHub: onHub, what)
                }
            }

            /// Lets SwiftUI lay out and draw what it has pending.
            func settle() async {
                await waitUntilSteady(turns: 6) { drawn().map(\.frame) }
            }

            /// Everything drawn in the hub's window, with where it is on screen. Elements in a scroll view are kept only
            /// where the scroll view shows them.
            func drawn() -> [Drawn] {
                var out: [Drawn] = []
                func visit(_ element: Any, clip: NSRect?) {
                    guard let o = element as? NSObject else { return }
                    let role = (o.value(forKey: "accessibilityRole") as? String) ?? ""
                    let label = (o.value(forKey: "accessibilityLabel") as? String) ?? ""
                    let frame = (o.value(forKey: "accessibilityFrame") as? NSRect) ?? .zero
                    var shown = frame
                    if let clip { shown = frame.intersection(clip) }
                    if !shown.isEmpty, shown.width >= 4, shown.height >= 4 { out.append(Drawn(role: role, label: label, frame: shown)) }
                    if role == "AXScrollBar" { return }
                    let inner = role == "AXScrollArea" ? (clip.map { frame.intersection($0) } ?? frame) : clip
                    for child in (o.value(forKey: "accessibilityChildren") as? [Any]) ?? [] { visit(child, clip: inner) }
                }
                visit(host, clip: nil)
                // Not the window-sized root.
                return out.filter { $0.frame.width < 600 && $0.frame.height < 900 }
            }

            var bar: NSRect { controller.barScreenFrame }

            /// What is drawn in the panel: outside the bar.
            func panelItems() -> [Drawn] {
                drawn().filter { !bar.insetBy(dx: -1, dy: -1).contains($0.centre) && $0.role != "AXScrollArea" && $0.role != "AXGroup" }
            }

            /// The bar's cell with that label.
            func cell(_ label: String) -> Drawn? {
                drawn().first { $0.label == label && bar.contains($0.centre) }
            }

            /// The pointer reached a cell of the bar: SwiftUI's hovers for it.
            func hover(_ section: HubSection, tab: InboxTab? = nil) {
                hub.enter(section)
                if let tab { FjordHub(store: store, ui: controller.ui, hub: hub).hoverTab(tab) }
            }

            /// Open `section` from its cell, as the pointer comes to rest on it.
            func open(_ section: HubSection, cell label: String, tab: InboxTab? = nil) async -> Bool {
                guard let cell = cell(label) else { Issue.record("\(edge): no bar cell \(label)"); return false }
                await walk(to: cell.centre, onHub: false, "to the \(label) cell")
                await move(to: cell.centre, expectOnHub: true, "on the \(label) cell")
                hover(section, tab: tab)
                // The dwell.
                try? await Task.sleep(for: .milliseconds(160))
                await settle()
                return hub.section == section
            }

            /// Along the bar to level with `p`, then across the seam onto it.
            func cross(to p: NSPoint, _ what: String) async {
                let b = bar.insetBy(dx: 3, dy: 3)
                let level = edge.isHorizontal
                    ? NSPoint(x: min(max(p.x, b.minX), b.maxX), y: pointer.y)
                    : NSPoint(x: pointer.x, y: min(max(p.y, b.minY), b.maxY))
                await walk(to: level, "along the bar to \(what)")
                // Straight out of the bar across the seam, then (where the panel runs past the bar's end) along the panel.
                await walk(to: edge.isHorizontal ? NSPoint(x: level.x, y: p.y) : NSPoint(x: p.x, y: level.y), "across the seam to \(what)")
                await walk(to: p, "onto \(what)")
            }

            /// From the panel back onto the bar at `p`: along the panel to level with the bar (where it runs past the bar's
            /// end), across the seam, then along the bar.
            func back(to p: NSPoint, _ what: String) async {
                let b = bar.insetBy(dx: 3, dy: 3)
                let level = edge.isHorizontal
                    ? NSPoint(x: min(max(pointer.x, b.minX), b.maxX), y: pointer.y)
                    : NSPoint(x: pointer.x, y: min(max(pointer.y, b.minY), b.maxY))
                await walk(to: level, "\(what), along the panel")
                await walk(to: edge.isHorizontal ? NSPoint(x: level.x, y: p.y) : NSPoint(x: p.x, y: level.y), "\(what), across the seam")
                await walk(to: p, what)
            }

            /// Out of the panel on its far side, away from the bar, and on out of the window.
            func leave(settling: Bool = true) async {
                let far: NSPoint = switch edge {
                case .right: NSPoint(x: window.frame.minX - 40, y: pointer.y)
                case .left: NSPoint(x: window.frame.maxX + 40, y: pointer.y)
                case .top: NSPoint(x: pointer.x, y: window.frame.minY - 40)
                case .bottom: NSPoint(x: pointer.x, y: window.frame.maxY + 40)
                }
                await walk(to: far, onHub: false, "leaving")
                // Off the hub, the window lets clicks through to what's under it at once, even before the panel closes.
                #expect(window.ignoresMouseEvents, "\(edge): off the hub, the window still takes the mouse")
                await move(to: away)
                // Past the leave grace; settling, past the closing panel's fade too.
                try? await Task.sleep(for: .milliseconds(settling ? 400 : 140))
                await move(to: away)
            }

            /// Every item of the open panel, top to bottom, each in turn: crossing from the bar to the first, then from one
            /// to the next; the row under the pointer is picked (its actions show) as SwiftUI's hover would.
            func hoverEachItem(_ what: String) async {
                let items = panelItems()
                #expect(!items.isEmpty, "\(edge) \(what): nothing drawn in the panel")
                var first = true
                for item in items {
                    // Each may have moved (a row's actions showing): read again.
                    guard let now = panelItems().first(where: { $0.label == item.label && $0.role == item.role }) else { continue }
                    if first { await cross(to: now.centre, "\(what): \(now.label)") } else { await walk(to: now.centre, "\(what): \(now.label)") }
                    first = false
                    if let id = rowID(now.label) { hub.selection = "i:" + id }
                    await settle()
                    // A small move on it, after anything the hover changed.
                    await move(to: NSPoint(x: pointer.x + 1, y: pointer.y + 1), expectOnHub: true, "\(what): on \(now.label)")
                }
            }

            /// The inbox row a label names.
            func rowID(_ label: String) -> String? {
                store.entries(in: store.hubTab(hub)).first { label.hasPrefix($0.thing.title + ",") }?.id
            }

            /// Waits out the leave grace: what's open then stays open.
            func graceElapsed() async {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        // MARK: The inbox, each tab from its own cell

        @Test(arguments: edges) func theInboxPanelStaysOpenOverEveryRowOfEveryTabOpenedFromItsCell(_ edge: DockEdge) async {
            let rig = await Rig(edge: edge, scenario: .agents)
            defer { rig.close() }
            for category in rig.store.shownCategories {
                let opened = await rig.open(.inbox, cell: category.title, tab: .category(category.id))
                #expect(opened, "\(edge) \(category.name): no panel")
                await rig.hoverEachItem(category.name)
                await rig.graceElapsed()
                #expect(rig.hub.section == .inbox, "\(edge) \(category.name): the panel closed under the pointer")
                await rig.leave()
                #expect(rig.hub.section == nil, "\(edge) \(category.name): still open after the pointer left")
                #expect(rig.window.ignoresMouseEvents && !rig.controller.watchesGlobally,
                        "\(edge) \(category.name): the bar still takes the mouse or watches it system-wide at rest")
            }
            #expect(rig.dropped.isEmpty, "\(rig.dropped.prefix(5))")
        }

        // MARK: Back on the bar as the last panel fades

        @Test(arguments: edges) func aPanelReopenedWhileTheLastOneFadesStaysOpenOverItsRows(_ edge: DockEdge) async {
            let rig = await Rig(edge: edge, scenario: .agents)
            defer { rig.close() }
            for category in rig.store.shownCategories + rig.store.shownCategories.prefix(1) {
                let opened = await rig.open(.inbox, cell: category.title, tab: .category(category.id))
                #expect(opened, "\(edge) \(category.name): no panel")
                await rig.hoverEachItem(category.name)
                await rig.graceElapsed()
                #expect(rig.hub.section == .inbox, "\(edge) \(category.name): the panel closed under the pointer")
                // Off it, and straight back: the closing panel is still fading out as the next opens.
                await rig.leave(settling: false)
                #expect(rig.hub.section == nil)
            }
            #expect(rig.dropped.isEmpty, "\(rig.dropped.prefix(5))")
        }

        // MARK: Switching tabs from the bar with the panel open

        @Test(arguments: edges) func theInboxPanelStaysOpenOverTheRowsOfATabPickedFromTheBarWhileOpen(_ edge: DockEdge) async {
            let rig = await Rig(edge: edge, scenario: .agents)
            defer { rig.close() }
            let categories = rig.store.shownCategories
            guard let first = categories.first else { Issue.record("no categories"); return }
            #expect(await rig.open(.inbox, cell: first.title, tab: .category(first.id)))
            for category in categories.reversed() {
                // Back onto the bar, to another category's cell: its list replaces the panel's.
                guard let cell = rig.cell(category.title) else { Issue.record("\(edge): no cell \(category.title)"); continue }
                await rig.back(to: cell.centre, "back to the \(category.title) cell")
                rig.hover(.inbox, tab: .category(category.id))
                await rig.settle()
                await rig.hoverEachItem("\(category.name), switched")
                #expect(rig.hub.section == .inbox)
            }
            await rig.graceElapsed()
            #expect(rig.hub.section == .inbox, "\(edge): the panel closed under the pointer")
            await rig.leave()
            #expect(rig.hub.section == nil)
            #expect(rig.dropped.isEmpty, "\(rig.dropped.prefix(5))")
        }

        // MARK: A list longer than the panel, scrolled

        @Test(arguments: edges) func aScrolledInboxListKeepsThePanelOpenOverItsRows(_ edge: DockEdge) async {
            let rig = await Rig(edge: edge, scenario: .inboxMany)
            defer { rig.close() }
            guard let category = rig.store.shownCategories.max(by: { rig.store.entries(in: $0.id).count < rig.store.entries(in: $1.id).count })
            else { Issue.record("no categories"); return }
            #expect(await rig.open(.inbox, cell: category.title, tab: .category(category.id)))
            await rig.hoverEachItem("\(category.name), top")
            if let last = rig.store.entries(in: category.id).last { rig.hub.requestScroll("i:" + last.id) }
            try? await Task.sleep(for: .milliseconds(400))
            await rig.settle()
            await rig.hoverEachItem("\(category.name), scrolled to the end")
            await rig.graceElapsed()
            #expect(rig.hub.section == .inbox, "\(edge): the panel closed under the pointer")
            await rig.leave()
            #expect(rig.hub.section == nil)
            #expect(rig.dropped.isEmpty, "\(rig.dropped.prefix(5))")
        }

        // MARK: The Router and the controls

        @Test(arguments: edges) func theRouterAndControlsPanelsStayOpenOverTheirItems(_ edge: DockEdge) async {
            let rig = await Rig(edge: edge, scenario: .router)
            defer { rig.close() }
            for (section, cell) in [(HubSection.router, "Router"), (.controls, "Controls")] {
                #expect(await rig.open(section, cell: cell), "\(edge) \(cell): no panel")
                await rig.hoverEachItem(cell)
                await rig.graceElapsed()
                #expect(rig.hub.section == section, "\(edge) \(cell): the panel closed under the pointer")
                await rig.leave()
                #expect(rig.hub.section == nil, "\(edge) \(cell): still open after the pointer left")
            }
            #expect(rig.dropped.isEmpty, "\(rig.dropped.prefix(5))")
        }

        // MARK: Slipping off and back

        @Test(arguments: edges) func slippingOffThePanelForAMomentAndBackOntoItKeepsItOpen(_ edge: DockEdge) async {
            let rig = await Rig(edge: edge, scenario: .agents)
            defer { rig.close() }
            guard let category = rig.store.shownCategories.first else { return }
            #expect(await rig.open(.inbox, cell: category.title, tab: .category(category.id)))
            guard let row = rig.panelItems().last else { Issue.record("\(edge): nothing in the panel"); return }
            await rig.cross(to: row.centre, "the last row")
            // Off the panel's far side, briefly, and back onto the same row.
            let back = rig.pointer
            let off: NSPoint = switch edge {
            case .right: NSPoint(x: row.frame.minX - 30, y: back.y)
            case .left: NSPoint(x: row.frame.maxX + 30, y: back.y)
            case .top: NSPoint(x: back.x, y: rig.panelItems().map(\.frame.minY).min()! - 30)
            case .bottom: NSPoint(x: back.x, y: rig.panelItems().map(\.frame.maxY).max()! + 30)
            }
            await rig.move(to: off)
            try? await Task.sleep(for: .milliseconds(40))
            await rig.move(to: back)
            await rig.graceElapsed()
            #expect(rig.hub.section == .inbox, "\(edge): a moment off the panel closed it though the pointer came back")
            #expect(!rig.window.ignoresMouseEvents, "\(edge): back on the panel, the window lets the pointer through")
            await rig.leave()
            #expect(rig.hub.section == nil)
        }

        // MARK: Anywhere on screen

        @Test func theWindowsPlaceOnScreenDoesNotMatter() async {
            // A screen far from the origin, at a fractional place (a second display left of and below the main one).
            for (edge, origin) in [(DockEdge.right, NSPoint(x: -12_345.5, y: -6_789.25)), (.bottom, NSPoint(x: -20_011.5, y: -9_001.5))] {
                let rig = await Rig(edge: edge, scenario: .agents, origin: origin)
                defer { rig.close() }
                for category in rig.store.shownCategories.prefix(2) {
                    #expect(await rig.open(.inbox, cell: category.title, tab: .category(category.id)))
                    await rig.hoverEachItem(category.name)
                    await rig.graceElapsed()
                    #expect(rig.hub.section == .inbox, "\(edge) at \(origin): the panel closed under the pointer")
                    await rig.leave()
                    #expect(rig.hub.section == nil)
                }
                #expect(rig.dropped.isEmpty, "\(rig.dropped.prefix(5))")
            }
        }
    }
}
