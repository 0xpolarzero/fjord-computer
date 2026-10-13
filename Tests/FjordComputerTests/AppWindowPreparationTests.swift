import AppKit
import Testing
@testable import FjordComputer

@MainActor
@Suite struct AppWindowPreparation {
    @Test func launchPreparationRetriesUntilMouseModifiersAndBarAreIdle() {
        var mouseButtons = 1
        var modifiers: NSEvent.ModifierFlags = []
        var hovering = false
        var prepared = 0
        var retries: [@MainActor () -> Void] = []
        var delays: [TimeInterval] = []
        AppDelegate.prepareWhenIdle(interacting: {
            AppDelegate.preparationIsBlocked(mouseButtons: mouseButtons, modifiers: modifiers, barInteracting: hovering)
        }, prepare: { prepared += 1 }, schedule: { delay, block in
            delays.append(delay)
            retries.append(block)
        })
        #expect(prepared == 0 && delays == [0.25] && retries.count == 1)
        mouseButtons = 0
        modifiers = .command
        retries.removeFirst()()
        #expect(prepared == 0 && delays == [0.25, 0.25] && retries.count == 1)
        modifiers = []
        hovering = true
        retries.removeFirst()()
        #expect(prepared == 0 && delays == [0.25, 0.25, 0.25] && retries.count == 1)
        hovering = false
        // Persistent Caps Lock and Fn are not shortcut modifiers and must not postpone preparation.
        modifiers = [.capsLock, .function]
        retries.removeFirst()()
        #expect(prepared == 1 && retries.isEmpty && delays.count == 3)
    }

    /// The launch's preparing runs its steps one per idle moment of the main run loop, in order, none in the turn that asks.
    @Test func launchPreparationRunsItsStepsInOrderEachAtIdle() async {
        var done: [Int] = []
        AppDelegate.prepare([{ done.append(1) }, { done.append(2) }], interacting: { false })
        #expect(done.isEmpty)
        await waitUntil { done.count == 2 }
        #expect(done == [1, 2])
    }

    /// A close hands the keyboard back only to a regular app still running: never to a menu-bar or launcher app (no window
    /// to type in), nor to Fjord Computer itself.
    @Test func theKeyboardGoesBackOnlyToARegularAppStillRunning() {
        #expect(AppPolicy.canTakeFocusBack(policy: .regular, isSelf: false, terminated: false))
        #expect(!AppPolicy.canTakeFocusBack(policy: .accessory, isSelf: false, terminated: false))
        #expect(!AppPolicy.canTakeFocusBack(policy: .prohibited, isSelf: false, terminated: false))
        #expect(!AppPolicy.canTakeFocusBack(policy: .regular, isSelf: true, terminated: false))
        #expect(!AppPolicy.canTakeFocusBack(policy: .regular, isSelf: false, terminated: true))
        // Asked of an app as it is now: never Fjord Computer itself, nor nothing.
        #expect(AppPolicy.takingFocusBack(.current) == nil && AppPolicy.takingFocusBack(nil) == nil)
    }

    /// Launch wires the banners' routing before the Router chains its own onto it: a Router banner's click opens its card,
    /// any other reaches what the store routes, and nothing the launch does after (`startServices`) sets it again.
    @Test func launchWiresTheBannersBeforeTheRouterChainsOntoThem() {
        let store = Store()
        store.persists = false
        Demo.populate(store, .router)
        store.wireNotifications()
        let stores = store.notifier.onOpen
        #expect(stores != nil)
        var opened: String?
        RouterBanners.attach(store: store, windowIsKey: { false }) { opened = $0 }
        store.notifier.onOpen?(RouterBanners.prefix + "card#1", nil)
        #expect(opened == "card#1")
    }

    /// Becoming active: an activation Fjord Computer asked for landing with no window shown (a quick close got there first)
    /// gives the keyboard back; one the user made (⌘-Tab, the Dock) while the window closes opens it again rather than being
    /// bounced; anything else stays, a banner's click shortly after a close included.
    @Test func whatBecomingActiveDoes() {
        #expect(AppPolicy.onActivation(ours: true, windowShown: false, closing: false) == .yield)
        #expect(AppPolicy.onActivation(ours: true, windowShown: false, closing: true) == .yield)
        #expect(AppPolicy.onActivation(ours: true, windowShown: true, closing: false) == .stay)
        #expect(AppPolicy.onActivation(ours: false, windowShown: false, closing: true) == .reopen)
        #expect(AppPolicy.onActivation(ours: false, windowShown: false, closing: false) == .stay)
        #expect(AppPolicy.onActivation(ours: false, windowShown: true, closing: false) == .stay)
    }

    @Test(arguments: [NSEvent.ModifierFlags.command, .control, .option, .shift])
    func eachShortcutModifierPostponesPreparation(_ modifiers: NSEvent.ModifierFlags) {
        #expect(AppDelegate.preparationIsBlocked(mouseButtons: 0, modifiers: modifiers, barInteracting: false))
    }
}

extension WindowSeams {
    @MainActor
    @Suite(.hostsWindows) struct AppWindowOverlayPreparation {
        @Test func preparingTheOverlayKeepsItHiddenAndTheFirstMorphReusesIt() throws {
            _ = NSApplication.shared
            let window = AwayWindow(contentRect: NSRect(origin: UnderTest.away, size: NSSize(width: 1100, height: 700)),
                                    styleMask: [.titled], backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false
            let screen = try #require(window.screen ?? NSScreen.main)
            let prepared = AppTransition.prepareOverlay(on: screen)
            let run = try #require(AppTransition.makeRun(for: window, picture: nil, bar: nil))
            defer { run.end() }
            #expect(prepared === run.overlay && !prepared.isVisible && !window.isVisible)
            let content = run.overlay.contentView
            run.show()
            #expect(!NSScreen.screens.contains { $0.frame.intersects(run.overlay.frame) })
            #expect(AppTransition.prepareOverlay(on: screen) === prepared)
            #expect(run.overlay.isVisible && run.overlay.contentView === content)
        }
    }
}
