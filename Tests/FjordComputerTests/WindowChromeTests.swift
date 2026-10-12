import AppKit
import SwiftUI
import Testing
@testable import FjordComputer

/// The window's macOS 26 chrome (docs/design/fjord/glass-plan.md §5.2): an inset sidebar, the page beside it laid out once
/// at the fold's end and drawn by an offset that starts at the whole distance and lands with the sidebar's edge.
@MainActor
@Suite struct WindowChromeTests {
    @Test func thePageStartsWhereTheInsetPanelEnds() {
        #expect(WindowChrome.pageLeading(collapsed: false) == WindowChrome.inset + AppRootView.sidebarWidth)
        #expect(WindowChrome.pageLeading(collapsed: true) == WindowChrome.inset + AppSidebar.railWidth)
    }

    /// The capsule sits at the same place in the page either way: clear of the window's three buttons over a rail, beside
    /// the sidebar (never on it) when it is out.
    @Test func theNavCapsuleClearsTheWindowsButtonsAndTheSidebar() {
        #expect(WindowChrome.pageLeading(collapsed: true) + WindowChrome.navGap >= AppNavButtons.leading)
        #expect(WindowChrome.navGap >= WindowChrome.inset)
        #expect(WindowChrome.headerInset > WindowChrome.navGap)
    }

    @Test func aShapeInsetInTheWindowKeepsTheFloorInFullScreen() {
        #expect(Theme.Radius.concentric(0, inset: WindowChrome.inset, minimum: WindowChrome.minimumRadius) == 6)
        #expect(Theme.Radius.concentric(26, inset: WindowChrome.inset, minimum: WindowChrome.minimumRadius) == 18)
    }
}

/// The window's root in a window: the page where the panel ends and under its header, the same geometry with glass and with
/// the opaque fills, and a fold the page follows.
@MainActor
@Suite(.hostsWindows) struct WindowChromeHostedTests {
    private func scrolls(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrolls) }

    @Test(arguments: [Chrome.Mode.glass, .opaque])
    func thePageSitsBesideTheSidebarAndFollowsItsFold(mode: Chrome.Mode) async throws {
        guard #available(macOS 26, *) else { return }
        let store = Store()
        Demo.populate(store)
        let category = try #require(store.shownCategories.max { store.count($0.id) < store.count($1.id) })
        let sidebar = SidebarState(defaults: nil, collapsed: false)
        let root = AppRootView(store: store, navigator: AppNavigator(start: .category(category.id), defaults: nil),
                               routerModel: RouterModel(), hub: HubState(), checksClaudeCode: false, sidebar: sidebar,
                               chrome: Chrome(mode: mode))
        let size = NSSize(width: 1200, height: 800)
        let hosting = NSHostingView(rootView: root.frame(width: size.width, height: size.height))
        let window = AwayWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
                                defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.orderOut(nil) }

        /// The inbox list: the widest scroll (the sidebar's is narrower).
        func list() -> NSRect? {
            hosting.layoutSubtreeIfNeeded()
            return scrolls(hosting).map { $0.convert($0.bounds, to: nil) }.max { $0.width < $1.width }
        }
        await waitUntil { (list()?.width ?? 0) > 600 }
        await waitUntilSteady(turns: 8) { list().map { [Int($0.minX), Int($0.width)] } }
        let out = try #require(list())
        #expect(Int(out.minX) == Int(WindowChrome.pageLeading(collapsed: false)), "\(out)")
        // The list runs under the page's header (its top bar), not from under it.
        #expect(out.maxY > size.height - CDS.TitleBar.header, "\(out)")

        // Folded: the page lands beside the rail.
        sidebar.set(collapsed: true)
        await waitUntilSteady(turns: 8, quiet: 0.5) { list().map { [Int($0.minX), Int($0.width)] } }
        let rail = try #require(list())
        #expect(Int(rail.minX) == Int(WindowChrome.pageLeading(collapsed: true)), "\(rail)")
    }
}
