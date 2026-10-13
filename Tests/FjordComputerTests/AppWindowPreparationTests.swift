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
            let run = try #require(AppTransition.makeRun(for: window, image: nil, bar: nil))
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
