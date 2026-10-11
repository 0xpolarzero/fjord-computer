import AppKit
import SwiftUI
import Testing
@testable import Lookout

@MainActor
@Suite(.hostsWindows) struct BarLatency {
    private func controller() -> (HubController, NSHostingView<HubRoot>, NSWindow) {
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let controller = HubController(store: store, demo: true)
        let panel = NSApp.windows.first { ($0.contentView as? NSHostingView<HubRoot>)?.rootView.hub === controller.hub }!
        let host = panel.contentView as! NSHostingView<HubRoot>
        #expect(!NSScreen.screens.contains { $0.frame.intersects(panel.frame) })
        return (controller, host, panel)
    }

    @Test(arguments: [false, true]) func openingCapturesThePeekBeforeTheBarHides(_ updates: Bool) async {
        let enabled = AppTransition.enabled
        AppTransition.enabled = true
        defer { AppTransition.enabled = enabled }
        let (controller, host, panel) = controller()
        let hub = controller.hub
        hub.section = .inbox
        hub.hovering = true
        hub.selection = "i:a"
        var captured = false
        func open() {
            // The app window's bar callback takes its picture here, before hiding the bar.
            captured = true
            #expect(hub.section == .inbox && hub.hovering && hub.selection == "i:a")
            controller.setWindowOpen(true)
        }
        controller.openApp = { _ in open() }
        controller.openUpdates = { open() }
        if updates { host.rootView.openUpdates() } else { host.rootView.openApp(.settings) }
        #expect(captured && hub.barHidden && hub.section == .inbox && panel.isVisible)
        await waitUntil { !panel.isVisible }
        #expect(hub.section == nil && !hub.hovering && hub.selection == nil)
    }

    @Test func returningDuringFadeOutClearsThePeekAndKeepsTheBarVisible() async {
        let enabled = AppTransition.enabled
        AppTransition.enabled = true
        defer { AppTransition.enabled = enabled }
        let (controller, _, panel) = controller()
        let hub = controller.hub
        hub.section = .inbox
        hub.hovering = true
        hub.selection = "i:a"
        controller.setWindowOpen(true)
        #expect(hub.section == .inbox)
        controller.setWindowOpen(false)
        #expect(!hub.barHidden && hub.quiet && hub.section == nil && !hub.hovering && hub.selection == nil)
        await waitUntilSteady(turns: 12) { panel.isVisible && panel.alphaValue == 1 }
        // The old fade-out completion must leave a bar that has returned on its edge.
        #expect(panel.isVisible && !hub.barHidden)
        controller.setWindowOpen(true)
        await waitUntil { !panel.isVisible }
    }

    @Test func anOlderFadeCannotHideANewerDeparture() {
        let enabled = AppTransition.enabled
        AppTransition.enabled = true
        defer { AppTransition.enabled = enabled }
        let (controller, _, panel) = controller()
        controller.setWindowOpen(true)
        let older = controller.barGeneration
        controller.setWindowOpen(false)
        controller.setWindowOpen(true)
        let hub = controller.hub
        hub.section = .router
        hub.hovering = true
        hub.selection = "i:b"
        // Deliver the old completion after the bar has started leaving for the second time.
        controller.finishFadeOut(older)
        #expect(panel.isVisible && hub.section == .router && hub.hovering && hub.selection == "i:b")
        controller.finishFadeOut(controller.barGeneration)
        #expect(!panel.isVisible && hub.section == nil && !hub.hovering && hub.selection == nil)
    }

    @Test func hidingWithoutAnimationClearsOnlyAfterOrderingTheBarOut() {
        let enabled = AppTransition.enabled
        AppTransition.enabled = false
        defer { AppTransition.enabled = enabled }
        let (controller, _, panel) = controller()
        let hub = controller.hub
        hub.section = .inbox
        hub.hovering = true
        hub.selection = "i:a"
        controller.setWindowOpen(true)
        #expect(!panel.isVisible && hub.barHidden && hub.section == nil && !hub.hovering && hub.selection == nil)
        controller.setWindowOpen(false)
        #expect(panel.isVisible && panel.alphaValue == 1 && hub.quiet && !hub.barHidden)
        controller.setWindowOpen(true)
    }
}
