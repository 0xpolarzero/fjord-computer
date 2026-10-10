import AppKit
import Foundation
import SwiftUI
import Testing
@testable import Lookout

/// The app window as the bar's other mode: it opens on a place, and closing it tells the bar to come back.
@MainActor
@Suite(.hostsWindows) struct AppWindowTests {
    private func controller() -> (AppWindowController, Store) {
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        return (AppWindowController(store: store, remembers: false, checksClaudeCode: false), store)
    }

    /// The window off every screen, and closed again when the test is done.
    private func away(_ controller: AppWindowController) {
        controller.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    }

    @Test func showingOpensTheWindowOnThePlaceAndClosingTellsTheBar() async {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        #expect(!window.isOpen)
        window.show(.settings)
        away(window)
        #expect(window.isOpen && window.navigator.selection == .settings)
        // A regular app while the window is open: a Dock icon and ⌘-Tab.
        // (Wanted only: a test run never applies it, or its helper would land in the Dock.)
        #expect(AppPolicy.current == .regular)
        #expect(NSApp.activationPolicy() != .regular)
        window.close()
        await waitUntil { closed == 1 }
        #expect(!window.isOpen && closed == 1)
        // The bar only again: no Dock icon.
        #expect(AppPolicy.current == .accessory)
    }

    @Test func showingWithoutAPlaceOpensWhereItWasLeft() async {
        let (window, _) = controller()
        window.show(.done)
        away(window)
        window.close()
        await waitUntil { !window.isOpen }
        window.show()
        away(window)
        #expect(window.navigator.selection == .done)
        window.close()
        await waitUntil { !window.isOpen }
    }

    /// Opened again after a close, the window has its size back (its content leaves it on close, and coming back must not
    /// size it to the content's minimum: a window too small to see).
    @Test func openingAgainKeepsTheWindowsSize() async {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.settings)
        window.window?.setContentSize(NSSize(width: 1100, height: 700))
        let size = window.window?.frame.size
        window.close()
        await waitUntil { closed == 1 }
        window.show(.settings)
        #expect(window.window?.frame.size == size)
        away(window)
        window.close()
        await waitUntil { closed == 2 }
    }

    /// The window made smaller while closed (opening on a smaller screen fits it to that one) keeps that size when its kept
    /// content, still at the old size, goes back in.
    @Test func keptContentTakesTheSizeTheWindowHasNow() async {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.settings)
        window.window?.setContentSize(NSSize(width: 1300, height: 800))
        window.close()
        await waitUntil { closed == 1 }
        let smaller = NSRect(x: -5000, y: -5000, width: 1050, height: 650)
        window.window?.setFrame(smaller, display: false)
        window.show(.settings)
        #expect(window.window?.frame.size == smaller.size)
        window.close()
        await waitUntil { closed == 2 }
    }

    /// Closed, the window lets go of its content, which stands still out of it, and keeps it for the next open: the same
    /// content comes back, as it was left, without being made again.
    @Test func closingKeepsTheContentOutOfTheWindowForTheNextOpen() async throws {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.router)
        away(window)
        let content = try #require(window.window?.contentViewController)
        window.close()
        await waitUntil { closed == 1 }
        #expect(window.window?.contentViewController == nil && content.view.window == nil)
        window.show(.router)
        away(window)
        #expect(window.window?.contentViewController === content)
        window.close()
        await waitUntil { closed == 2 }
    }

    /// The categories page kept from a close has an undo history of what was done before it: a change the Router made while
    /// the window was closed is newer, so ⌘Z after opening again must not take the page back to before it.
    @Test func aRouterChangeWhileClosedIsNotUndoneByTheKeptCategoriesPage() async throws {
        let (window, store) = controller()
        // The page asks GitHub for repos to suggest when it has none.
        store.suggestions = ["octo/repo"]
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.categories)
        away(window)
        await waitUntil { store.categoryHistory != nil }
        // A step of the page's own, so it has something to undo.
        var renamed = try #require(store.categories.first)
        renamed.name += " (edited)"
        store.categories[0] = renamed
        await waitUntil { store.categoryHistory?.canUndo == true }
        #expect(store.categoryHistory?.canUndo == true)
        window.close()
        await waitUntil { closed == 1 }
        #expect(store.categoryHistory == nil)
        var made = CategoriesView.newDraft(after: store.categories)
        made.name = "From the Router"
        store.categories.append(made)
        store.categoriesChangedByRouter()
        window.show(.categories)
        away(window)
        await waitUntil { store.categoryHistory != nil }
        await waitUntilSteady { store.categoryHistory?.canUndo }
        store.categoryHistory?.undo(store)
        #expect(store.categories.contains { $0.id == made.id })
        window.close()
        await waitUntil { closed == 2 }
    }

    /// The composer kept from a close, given the keyboard again when the window opens, says so: Return sends again rather
    /// than starting a new line.
    @Test func theKeptComposerSaysItHasTheKeyboardAgainAfterReopening() async throws {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        func fields(_ view: NSView) -> [MentionTextView] { (view as? MentionTextView).map { [$0] } ?? [] + view.subviews.flatMap(fields) }
        func focus() async throws {
            let host = try #require(window.window?.contentView)
            await waitUntil { !fields(host).isEmpty }
            await drainMainQueue()
            let field = fields(host).first
            await waitUntil {
                if window.window?.firstResponder !== field, let field { window.window?.makeFirstResponder(field) }
                return window.window?.firstResponder === field
            }
        }
        window.show(.router)
        away(window)
        try await focus()
        await waitUntil { window.routerModel.composerFocused }
        #expect(window.routerModel.composerFocused)
        window.close()
        await waitUntil { closed == 1 }
        #expect(!window.routerModel.composerFocused)
        window.show(.router)
        away(window)
        try await focus()
        await waitUntil { window.routerModel.composerFocused }
        #expect(window.routerModel.composerFocused)
        window.close()
        await waitUntil { closed == 2 }
    }

    /// Short of memory, a closed window lets go of the content it kept, and the next open makes it again; an open one keeps it.
    @Test func memoryPressureReleasesTheContentKeptWhileClosed() async throws {
        let (window, _) = controller()
        var closed = 0
        window.onClose = { closed += 1 }
        window.show(.settings)
        away(window)
        let content = try #require(window.content)
        window.releaseKept()
        #expect(window.content === content && window.window?.contentViewController === content)
        window.close()
        await waitUntil { closed == 1 }
        window.releaseKept()
        #expect(window.content == nil)
        window.show(.settings)
        away(window)
        #expect(window.window?.contentViewController != nil && window.window?.contentViewController !== content)
        window.close()
        await waitUntil { closed == 2 }
    }

    /// Prepared at idle after launch, the window and its content are made out of sight: nothing is ordered in, the window is
    /// not open or in front, the app stays an accessory; the first open then brings in that content rather than making it.
    @Test func aPreparedContentIsMadeOutOfSightAndTheFirstOpenUsesIt() async throws {
        let (window, _) = controller()
        var fronts = 0, closed = 0
        window.onFront = { _ in fronts += 1 }
        window.onClose = { closed += 1 }
        let policy = AppPolicy.current
        window.prepare()
        let content = try #require(window.content)
        #expect(window.window?.isVisible == false && !window.isOpen && !window.isFront && fronts == 0)
        #expect(window.window?.contentViewController == nil && content.view.window == nil)
        #expect(AppPolicy.current == policy)
        #expect(!NSApp.windows.contains { $0.isVisible && $0 === window.window })
        // Twice is once.
        window.prepare()
        #expect(window.content === content)
        // Nothing a close leaves for later comes of it: the bar is not told the window closed.
        await drainMainQueue()
        #expect(closed == 0)
        window.show(.router)
        away(window)
        #expect(window.isOpen && window.window?.contentViewController === content)
        window.close()
        await waitUntil { closed == 1 }
    }

    /// Prepared on the categories page, the page out of sight leaves no undo history to take ⌘Z, and opening on it has a
    /// fresh one.
    @Test func aPreparedCategoriesPageRegistersItsHistoryOnlyOnceOpen() async throws {
        let (window, store) = controller()
        store.suggestions = ["octo/repo"]
        var closed = 0
        window.onClose = { closed += 1 }
        window.navigator.go(.categories)
        window.prepare()
        await drainMainQueue()
        #expect(store.categoryHistory == nil)
        window.show(.categories)
        away(window)
        await waitUntil { store.categoryHistory != nil }
        #expect(store.categoryHistory?.canUndo == false)
        window.close()
        await waitUntil { closed == 1 }
    }

    /// Why `prepare` builds the content in the window and takes it out again: once it has been in a window, a hosting
    /// controller out of one stands still (no body runs as the store behind it changes).
    @Test func contentTakenOutOfTheWindowStandsStill() async {
        let model = ProbeModel(), count = ProbeCount()
        let window = AwayWindow(contentRect: NSRect(x: -5000, y: -5000, width: 400, height: 300), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let content = NSHostingController(rootView: ProbeView(model: model, count: count))
        content.sizingOptions = []
        content.view.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        window.contentViewController = content
        content.view.layoutSubtreeIfNeeded()
        window.contentViewController = nil
        #expect(count.bodies >= 1 && !window.isVisible)
        let built = count.bodies
        for _ in 0..<10 {
            model.n += 1
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(count.bodies == built)
        withExtendedLifetime((content, window)) {}
    }

    @Test func aPlaceThatIsGoneOpensOnTheFirstCategory() async {
        let (window, store) = controller()
        window.show(.category(UUID()))
        away(window)
        #expect(window.navigator.selection == .category(store.shownCategories[0].id))
        window.close()
        await waitUntil { !window.isOpen }
    }

    @Test func aCardOpensOnTheRouter() async throws {
        let (window, store) = controller()
        window.show(.settings)
        away(window)
        let card = try #require(store.openRouterCards.first)
        window.show(card: card.id)
        #expect(window.navigator.selection == .router && window.routerModel.selection == card.id)
        window.close()
        await waitUntil { !window.isOpen }
    }

    @Test func anEntryOpensOnItsCategoryPickedAndAskedFor() async throws {
        let (window, store) = controller()
        let entry = try #require(store.entries.first { !$0.isDone })
        window.show(entry: entry)
        away(window)
        #expect(window.navigator.selection == .category(entry.categoryID))
        #expect(window.hub.selection == "i:" + entry.id && window.hub.keyboardSelection?.id == "i:" + entry.id)
        window.close()
        await waitUntil { !window.isOpen }
    }

    /// Check for Updates (the bar's menu) asks the window's own Settings for Updates, which takes the request: from another
    /// place, and again while Settings is open already.
    @Test func checkForUpdatesScrollsTheWindowsSettingsToUpdates() async {
        let (window, _) = controller()
        window.show(.done)
        away(window)
        window.showUpdates()
        #expect(window.isOpen && window.navigator.selection == .settings)
        #expect(window.hub.settingsScroll?.id == SettingsView.updatesID)
        await waitUntil { window.hub.settingsScroll == nil }
        #expect(window.hub.settingsScroll == nil)
        window.showUpdates()
        #expect(window.hub.settingsScroll?.id == SettingsView.updatesID)
        await waitUntil { window.hub.settingsScroll == nil }
        #expect(window.hub.settingsScroll == nil)
        // Closed on Settings and opened again by the menu: the page kept from the close takes it as it comes back.
        var closed = false
        window.onClose = { closed = true }
        window.close()
        await waitUntil { closed }
        window.showUpdates()
        away(window)
        #expect(window.hub.settingsScroll?.id == SettingsView.updatesID)
        await waitUntil { window.hub.settingsScroll == nil }
        #expect(window.hub.settingsScroll == nil)
        window.close()
        await waitUntil { !window.isOpen }
    }
}

@MainActor
@Suite struct BarState {
    /// The rows' avatars are warmed at the URL a row asks for: the latest actor's, at a row's size; and the account's at
    /// Settings' size.
    @Test func theAvatarsWarmedAreTheOnesTheRowsShow() {
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let warmed = store.avatarsToWarm()
        let shown = Set(store.shownCategories.flatMap { store.entries(in: .category($0.id)) }
            .filter { $0.thing.kind != .workflow }
            .compactMap { Avatar.sizedURL($0.thing.latestActor?.avatar, size: EntryRow.avatar) })
        let account = Avatar.sizedURL(store.me?.avatarUrl, size: SettingsView.accountAvatar)
        #expect(!warmed.isEmpty && warmed.count <= 61 && Set(warmed).count == warmed.count)
        #expect(warmed.contains { shown.contains($0) })
        #expect(warmed.allSatisfy { shown.contains($0) || $0 == account })
        // The tab the inbox opens on comes first.
        let first = store.entries(in: store.tabNeedingYou).filter { $0.thing.kind != .workflow }
            .compactMap { Avatar.sizedURL($0.thing.latestActor?.avatar, size: EntryRow.avatar) }
        if let lead = first.first { #expect(warmed.first == lead) }
        #expect(store.avatarsToWarm(limit: 1).filter { $0 != account }.count <= 1)
    }

    @Test func aPeekWaitsForThePointerToSettleThenSwitchesAtOnce() async {
        let hub = HubState()
        hub.enter(.inbox)
        #expect(hub.section == nil)
        await waitUntil { hub.section == .inbox }
        #expect(hub.section == .inbox)
        hub.enter(.router)
        #expect(hub.section == .router)
        hub.cancelDwell()
    }

    @Test func aPeekIsNotShownWhileTheBarIsQuiet() {
        let hub = HubState()
        hub.section = .inbox
        hub.panelFrame = CGRect(x: 0, y: 0, width: 10, height: 10)
        #expect(hub.openPanelFrame != nil)
        hub.quiet = true
        #expect(hub.openPanelFrame == nil)
    }

    @Test func changingThePeekedTabDropsTheRowPickedInTheOther() {
        let hub = HubState()
        hub.selection = "i:a"
        hub.tab = .done
        #expect(hub.selection == nil)
    }
}

/// The bar and the window: the bar is away only while the window is open and in front, and the morph is a no-op under test.
@MainActor
@Suite(.hostsWindows) struct BarComesBack {
    @Test func theBarIsAwayOnlyWhileTheOpenWindowIsInFront() {
        var presence = BarPresence()
        #expect(!presence.barAway)
        presence.opened(true)
        #expect(presence.barAway)
        // Another app in front: the bar is back, the window stays open behind.
        presence.front(false)
        #expect(!presence.barAway && presence.windowOpen)
        // The window returns (a click on the bar's item, the Dock icon).
        presence.front(true)
        #expect(presence.barAway)
        presence.opened(false)
        #expect(!presence.barAway)
        // A window that is not open is never in front.
        presence.front(true)
        #expect(!presence.barAway)
    }

    @Test func resigningActiveReportsOutOfSightAndBecomingActiveReportsFront() async {
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let controller = AppWindowController(store: store, remembers: false, checksClaudeCode: false)
        var reports: [Bool] = []
        controller.onFront = { reports.append($0) }
        controller.show(.settings)
        controller.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        // The window is on screen; whether the app counts as active depends on the runner, so say it.
        controller.reportFront(active: true)
        #expect(reports.last == true || controller.window?.occlusionState.contains(.visible) == false)
        let seen = reports.count
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        await waitUntil { reports.count > seen || reports.last == false }
        #expect(reports.last == false)
        controller.close()
        await waitUntil { !controller.isOpen }
        #expect(!controller.isOpen)
    }

    @Test func theMorphIsSkippedUnderTestSoTheWindowOpensAndClosesAtOnce() async {
        #expect(!AppTransition.enabled)
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let controller = AppWindowController(store: store, remembers: false, checksClaudeCode: false)
        var asked = 0
        controller.bar = { asked += 1; return BarMorph(frame: NSRect(x: 0, y: 0, width: 50, height: 200)) }
        var closing = 0
        var closed = 0
        controller.onClosing = { closing += 1 }
        controller.onClose = { closed += 1 }
        controller.show(.settings)
        controller.window?.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        #expect(controller.window?.alphaValue == 1 && controller.isOpen)
        controller.close()
        await waitUntil { closed == 1 }
        #expect(closed == 1 && closing == 0 && asked == 0 && !controller.isOpen)
    }

    private final class Ticks {
        var blocks: [@MainActor () -> Void] = []
        var turns: [@MainActor () -> Void] = []
    }

    /// A morph with the frame ticks in the test's hands. Synchronous: nothing else sees the morph switched on. A window under
    /// test never has the keyboard (the test runner is not the active app): `AppTransition.isKey` may say otherwise.
    private func morphing(_ body: (AppWindowController, Ticks) throws -> Void) rethrows {
        let saved = (AppTransition.enabled, AppTransition.nextFrame, AppTransition.nextTurn, AppTransition.isKey,
                     AppTransition.isMiniaturized)
        let ticks = Ticks()
        AppTransition.enabled = true
        AppTransition.nextFrame = { _, block in ticks.blocks.append(block) }
        AppTransition.nextTurn = { block in ticks.turns.append(block) }
        defer {
            AppTransition.enabled = saved.0
            AppTransition.nextFrame = saved.1
            AppTransition.nextTurn = saved.2
            AppTransition.isKey = saved.3
            AppTransition.isMiniaturized = saved.4
        }
        _ = NSApplication.shared
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        let window = AppWindowController(store: store, remembers: false, checksClaudeCode: false)
        window.bar = { BarMorph(frame: NSRect(x: 1400, y: 300, width: 46, height: 300)) }
        try body(window, ticks)
        window.run?.end()
        window.close()
    }

    @Test func theRealWindowIsShownBeforeTheOverlayGoes() {
        morphing { controller, ticks in
            controller.show(.settings)
            guard let run = controller.run, let window = controller.window else { return #expect(Bool(false), "no morph") }
            // Waiting at its frame, invisible, while the overlay grows out of the bar.
            #expect(controller.phase == .opening && window.alphaValue == 0 && run.overlay.isVisible)
            run.complete()
            // At the end: the real window is in under the overlay at once, and the overlay stays until two refreshes later.
            #expect(window.alphaValue == 1 && run.overlay.isVisible && !run.ended)
            #expect(ticks.blocks.count == 1)
            ticks.blocks.removeFirst()()
            #expect(window.alphaValue == 1 && run.overlay.isVisible && ticks.blocks.count == 1)
            ticks.blocks.removeFirst()()
            #expect(window.alphaValue == 1 && !run.ended)
        }
    }

    @Test func theMorphMovesBeforeTheWindowIsBuilt() {
        morphing { controller, ticks in
            controller.show(.settings)
            guard let run = controller.run, let window = controller.window else { return #expect(Bool(false), "no morph") }
            // The overlay is on screen at once, on the window's bare surface; the window and its content come a turn later,
            // and it counts as open meanwhile (a toggle closes it).
            #expect(run.overlay.isVisible && run.image == nil && controller.isOpen)
            #expect(!window.isVisible && window.contentViewController == nil)
            #expect(ticks.turns.count == 1)
            ticks.turns.removeFirst()()
            #expect(window.isVisible && window.alphaValue == 0 && window.contentViewController != nil)
            // The picture is there before the real window takes over.
            run.complete()
            #expect(run.image != nil && window.alphaValue == 1 && run.overlay.isVisible)
        }
    }

    /// What a close leaves for the next turn (the content out of the window, the bar told) is called off when the window is
    /// opened again first: the bar must not be told the window closed while it is on its way in.
    @Test func openingAgainBeforeTheCloseIsTidiedKeepsTheWindowOpen() {
        morphing { controller, ticks in
            var closed = 0
            controller.onClose = { closed += 1 }
            controller.show(.settings)
            controller.close()
            controller.run?.complete()
            #expect(controller.phase == .idle && controller.window?.isVisible == false)
            controller.show(.settings)
            #expect(controller.phase == .opening && controller.isOpen)
            // Every turn queued but the new opening's own bringing in: the close's tidying among them.
            let turns = ticks.turns
            ticks.turns = []
            turns.dropLast().forEach { $0() }
            #expect(closed == 0 && controller.isOpen && AppPolicy.current == .regular)
            #expect(controller.window?.contentViewController != nil)
            turns.last?()
            #expect(closed == 0 && controller.window?.isVisible == true)
        }
    }

    /// Once the overlay has let go of its picture (the real window's live pixels show, the overlay's shadow still fading),
    /// a close is a close of the window as it is: a fresh picture, shown before the real window goes, which then shrinks
    /// into the bar, rather than the opening's overlay turned round from nothing to see.
    @Test func closingAsTheOverlayLetsGoMorphsFromAFreshPicture() {
        morphing { controller, ticks in
            controller.show(.settings)
            guard let opened = controller.run, let window = controller.window else { return #expect(Bool(false), "no morph") }
            ticks.turns.removeFirst()()
            opened.complete()
            ticks.blocks.removeFirst()()
            ticks.blocks.removeFirst()()
            #expect(opened.handedOver && controller.phase == .opening && window.isVisible)
            controller.close()
            guard let closing = controller.run else { return #expect(Bool(false), "no close morph") }
            #expect(controller.phase == .closing && closing !== opened && closing.image != nil)
            // The overlay shows the window before the real one goes.
            #expect(window.isVisible && closing.overlay.isVisible && ticks.blocks.count == 1)
            ticks.blocks.removeFirst()()
            #expect(!window.isVisible && closing.startPose?.container == 1 && closing.startPose?.window == 1)
        }
    }

    /// Opened, then closed with the keyboard (the picture it closes on is kept), and its close under way.
    private func openAndStartClosing(_ controller: AppWindowController, _ ticks: Ticks, on place: AppDestination) {
        AppTransition.isKey = { _ in true }
        controller.show(place)
        ticks.turns.forEach { $0() }
        ticks.turns = []
        controller.run?.complete()
        ticks.blocks.removeFirst()()
        ticks.blocks.removeFirst()()
        controller.close()
        ticks.blocks.removeFirst()()
    }

    /// A close turned round by a banner's click on another card of the same place shows that card, not the picture of the
    /// one it closed on.
    @Test func aCloseTurnedRoundOnAnotherCardRefreshesThePicture() throws {
        try morphing { controller, ticks in
            let cards = controller.store.openRouterCards
            try #require(cards.count >= 2)
            controller.routerModel.select(cards[0].id, store: controller.store)
            openAndStartClosing(controller, ticks, on: .router)
            guard let run = controller.run, let shown = run.image else { return #expect(Bool(false), "no close morph") }
            controller.show(card: cards[1].id)
            #expect(controller.phase == .opening && controller.run === run && controller.navigator.selection == .router)
            ticks.turns.forEach { $0() }
            #expect(run.image != nil && run.image !== shown)
        }
    }

    /// Closed before its fresh picture came, an opening to another place keeps the picture it started on as that of the
    /// place it shows: turned round, it still owes the fresh one.
    @Test func aCloseCutShortBeforeItsFreshPictureStillOwesItWhenTurnedRound() {
        morphing { controller, ticks in
            openAndStartClosing(controller, ticks, on: .router)
            controller.run?.complete()
            ticks.turns.forEach { $0() }
            ticks.turns = []
            #expect(controller.phase == .idle && controller.window?.isVisible == false)
            // Settings starts on the Router's picture; the window does not get the keyboard before the toggle.
            AppTransition.isKey = { _ in false }
            controller.show(.settings)
            guard let run = controller.run, let started = run.image else { return #expect(Bool(false), "no kept picture") }
            controller.close()
            #expect(controller.phase == .closing && controller.run === run)
            controller.show(.settings)
            #expect(controller.phase == .opening && controller.run === run && run.image === started)
            run.complete()
            #expect(run.image != nil && run.image !== started)
        }
    }

    /// The place changed by the Go menu (the navigator itself, not `show`) while the window is on its way in, its fresh
    /// picture taken already: the overlay takes another, of where it now goes.
    @Test func goingElsewhereOnTheWayInRefreshesThePicture() {
        morphing { controller, ticks in
            AppTransition.isKey = { _ in true }
            controller.show(.settings)
            ticks.turns.forEach { $0() }
            ticks.turns = []
            guard let run = controller.run, let taken = run.image else { return #expect(Bool(false), "no picture") }
            controller.navigator.go(.done)
            ticks.turns.forEach { $0() }
            #expect(run.image != nil && run.image !== taken && run.shows == .done)
        }
    }

    /// A card or a message of the Router asked for from the bar while the window is on its way in to the Router: the place
    /// is the same, what it shows is not.
    @Test func aRouterPickOnTheWayInRefreshesThePicture() throws {
        try morphing { controller, ticks in
            let cards = controller.store.openRouterCards
            try #require(cards.count >= 2)
            AppTransition.isKey = { _ in true }
            controller.routerModel.select(cards[0].id, store: controller.store)
            controller.show(.router)
            ticks.turns.forEach { $0() }
            ticks.turns = []
            guard let run = controller.run, let taken = run.image else { return #expect(Bool(false), "no picture") }
            controller.pick(card: cards[1].id)
            controller.show(.router)
            ticks.turns.forEach { $0() }
            ticks.turns = []
            guard let card = run.image else { return #expect(Bool(false), "no picture") }
            #expect(card !== taken && controller.routerModel.selection == cards[1].id)
            controller.pick(message: UUID())
            ticks.turns.forEach { $0() }
            #expect(run.image != nil && run.image !== card)
        }
    }

    /// Any close turned round takes a fresh picture: what the window shows may have changed meanwhile (the store, a message
    /// asked for) with nothing to say so.
    @Test func everyCloseTurnedRoundRefreshesThePicture() {
        morphing { controller, ticks in
            openAndStartClosing(controller, ticks, on: .settings)
            guard let run = controller.run, let shown = run.image else { return #expect(Bool(false), "no close morph") }
            controller.show(.settings)
            #expect(controller.phase == .opening && controller.run === run)
            ticks.turns.forEach { $0() }
            #expect(run.image != nil && run.image !== shown)
        }
    }

    /// Minimized on its way in, then closed by a toggle, the window turned round by another toggle opens again: the close's
    /// end does not close it after all.
    @Test func aCloseOfAWindowMinimizedOnItsWayInTurnsRound() {
        morphing { controller, ticks in
            controller.show(.settings)
            ticks.turns.forEach { $0() }
            ticks.turns = []
            guard let window = controller.window else { return #expect(Bool(false), "no window") }
            // ⌘M: a window under test does not minimize at once.
            AppTransition.isMiniaturized = { $0 === window }
            controller.close()
            guard let closing = controller.run else { return #expect(Bool(false), "no close morph") }
            #expect(controller.phase == .closing)
            controller.show(.settings)
            #expect(controller.phase == .opening && controller.isOpen)
            closing.complete()
            ticks.turns.forEach { $0() }
            #expect(controller.phase != .closing && controller.isOpen)
        }
    }

    @Test func closingWhileOpeningPicksUpFromWhereTheOverlayIs() {
        morphing { controller, ticks in
            controller.show(.settings)
            guard let run = controller.run, let window = controller.window else { return #expect(Bool(false), "no morph") }
            let before = run.pose
            controller.close()
            // On its way out it counts as closed: a toggle opens it again.
            #expect(controller.phase == .closing && controller.run === run && !controller.isOpen)
            #expect(run.startPose?.rect == before.rect && run.startPose?.radius == before.radius)
            // The real window is out of the way and the overlay carries the close.
            #expect(!window.isVisible && run.overlay.isVisible)
            // Opening again turns it round from there.
            let now = run.pose
            controller.show(.settings)
            #expect(controller.phase == .opening && run.startPose?.rect == now.rect && controller.isOpen)
            #expect(ticks.blocks.isEmpty)
        }
    }
}

/// A view that counts its body runs, over a store it reads.
@Observable @MainActor private final class ProbeModel { var n = 0 }
@MainActor private final class ProbeCount { var bodies = 0 }

private struct ProbeView: View {
    let model: ProbeModel
    let count: ProbeCount
    var body: some View {
        count.bodies += 1
        return Text("\(model.n)").frame(width: 200, height: 100)
    }
}
