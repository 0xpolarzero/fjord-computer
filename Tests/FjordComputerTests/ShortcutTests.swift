import AppKit
import Carbon
import Foundation
import Testing
@testable import FjordComputer

@MainActor
@Suite struct Shortcuts {
    private func key(_ code: Int, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                         context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false,
                         keyCode: UInt16(code))!
    }

    @Test func eventMatchesByKeyPositionAndModifiers() {
        #expect(Shortcut(key(kVK_Space)) == Shortcut(keyCode: UInt16(kVK_Space)))
        #expect(Shortcut(key(kVK_Space, [.option])) != Shortcut(keyCode: UInt16(kVK_Space)))
        // Caps lock / fn don't change what was pressed.
        #expect(Shortcut(key(kVK_ANSI_R, [.command, .capsLock, .function])) == Shortcut(keyCode: UInt16(kVK_ANSI_R), modifiers: .command))
    }

    @Test func modifierTapRecognizesALoneSidedKey() {
        let rightCmd: UInt = 0x10 | NSEvent.ModifierFlags.command.rawValue
        let leftCmd: UInt = 0x08 | NSEvent.ModifierFlags.command.rawValue
        var tap = ModifierTap()
        #expect(tap.flagsChanged(keyCode: 54, flags: rightCmd) == nil)
        #expect(tap.flagsChanged(keyCode: 54, flags: 0) == 54)
        // Left ⌘ is a different key.
        #expect(tap.flagsChanged(keyCode: 55, flags: leftCmd) == nil)
        #expect(tap.flagsChanged(keyCode: 55, flags: 0) == 55)
        // Right ⌘ + C is a combination, not a tap.
        _ = tap.flagsChanged(keyCode: 54, flags: rightCmd)
        tap.interrupt()
        #expect(tap.flagsChanged(keyCode: 54, flags: 0) == nil)
        // Both ⌘ keys held together is not a tap either.
        _ = tap.flagsChanged(keyCode: 54, flags: rightCmd)
        _ = tap.flagsChanged(keyCode: 55, flags: rightCmd | leftCmd)
        _ = tap.flagsChanged(keyCode: 55, flags: rightCmd)
        #expect(tap.flagsChanged(keyCode: 54, flags: 0) == nil)
        // Shift doesn't tap.
        _ = tap.flagsChanged(keyCode: 60, flags: 0x04 | NSEvent.ModifierFlags.shift.rawValue)
        #expect(tap.flagsChanged(keyCode: 60, flags: 0) == nil)
    }

    @Test func customizeAndReset() {
        let store = Store()
        store.persists = false
        var registered: Shortcut?
        store.onGlobalShortcutChange = { _, shortcut in registered = shortcut; return true }
        let custom = Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: [.control, .command])
        store.setShortcut(custom, for: .togglePanel)
        #expect(store.shortcut(.togglePanel) == custom)
        #expect(registered == custom)
        store.setShortcut(nil, for: .togglePanel)
        #expect(store.shortcut(.togglePanel) == ShortcutAction.togglePanel.defaultShortcut)
        #expect(store.settings.shortcuts == nil)
    }

    private func hotKeysAreReleasedWhileSuspended(_ backend: HotKeyBackend) {
        let hotKeys = HotKeys(backend: backend)
        let f19 = Shortcut(keyCode: UInt16(kVK_F19), modifiers: [.control, .option, .command, .shift])
        let f18 = Shortcut(keyCode: UInt16(kVK_F18), modifiers: [.control, .option, .command, .shift])
        // A combination can be registered once, so a second ID getting it shows the first was released.
        func isFree(_ shortcut: Shortcut) -> Bool {
            let probe = HotKeys(backend: backend)
            probe.set(91, shortcut) {}
            defer { probe.set(91, nil) }
            return probe.registeredIDs == [91]
        }
        hotKeys.set(90, f19) {}
        defer { hotKeys.set(90, nil) }
        #expect(!isFree(f19))
        hotKeys.isSuspended = true
        #expect(isFree(f19))
        // A change made meanwhile applies on resume.
        hotKeys.set(90, f18) {}
        #expect(isFree(f18))
        hotKeys.isSuspended = false
        #expect(isFree(f19))
        #expect(!isFree(f18))
        hotKeys.set(90, nil)
        #expect(isFree(f18))
    }

    @Test func hotKeysAreReleasedWhileSuspended() {
        hotKeysAreReleasedWhileSuspended(SystemKeys())
    }

    @Test func globalShortcutRunsBeforeItsMainThreadEventHandlerReturns() throws {
        // The real Carbon callback receives a synthetic press; no key is registered with the system.
        let carbon = CarbonHotKeys()
        let hotKeys = HotKeys(backend: SystemKeys())
        let store = Store()
        store.persists = false
        var performed: [ShortcutAction] = []
        let globals = GlobalShortcuts(store: store, hotKeys: hotKeys) { action in
            #expect(Thread.isMainThread)
            performed.append(action)
        }
        #expect(globals.register(.togglePanel))
        defer { hotKeys.set(ShortcutAction.togglePanel.hotKeyID, nil) }
        var event: EventRef?
        #expect(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0,
                            EventAttributes(kEventAttributeNone), &event) == noErr)
        let press = try #require(event)
        defer { ReleaseEvent(press) }
        var id = EventHotKeyID(signature: OSType(0x4C4B4F54), id: ShortcutAction.togglePanel.hotKeyID)
        #expect(SetEventParameter(press, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  MemoryLayout<EventHotKeyID>.size, &id) == noErr)
        #expect(SendEventToEventTarget(press, GetApplicationEventTarget()) == noErr)
        #expect(performed == [.togglePanel])
        withExtendedLifetime((carbon, globals)) {}
    }

    /// Registers F18 and F19 with the real system, which another app holding one would fail: only when asked for, with
    /// `FJORD_REAL_HOTKEYS=1`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["FJORD_REAL_HOTKEYS"] != nil))
    func systemHotKeysAreReleasedWhileSuspended() {
        hotKeysAreReleasedWhileSuspended(CarbonHotKeys())
    }

    @Test func startingARecorderStopsTheOneListening() {
        let store = Store()
        store.persists = false
        var changes: [Bool] = []
        store.onRecordingShortcutChange = { changes.append($0) }
        var firstStopped = false
        store.beginRecordingShortcut {
            firstStopped = true
            store.endRecordingShortcut()
        }
        #expect(store.isRecordingShortcut)
        store.beginRecordingShortcut { store.endRecordingShortcut() }
        #expect(firstStopped)
        #expect(store.isRecordingShortcut)
        // Released once the first stopped, then held again for the second.
        #expect(changes == [true, false, true])
        store.endRecordingShortcut()
        #expect(!store.isRecordingShortcut)
    }

    @Test func aClearedShortcutMatchesNothingAndComesBackWithReset() {
        let store = Store()
        store.persists = false
        store.setShortcut(.unassigned, for: .markAllRead)
        #expect(store.shortcut(.markAllRead).isUnassigned)
        #expect(!store.shortcut(.markAllRead).isModifierTap && store.shortcut(.markAllRead).mouseButton == nil)
        // Whatever key is pressed, none is the cleared one.
        for code in [kVK_Space, kVK_Delete, kVK_Return, kVK_ANSI_Z] {
            #expect(Shortcut(key(code, [.option])) != store.shortcut(.markAllRead))
        }
        store.setShortcut(nil, for: .markAllRead)
        #expect(store.shortcut(.markAllRead) == ShortcutAction.markAllRead.defaultShortcut)
    }

    @MainActor private func connected(_ store: Store, _ keys: SystemKeys) -> GlobalShortcuts {
        store.persists = false
        store.agents.enabled = true
        store.router.enabled = true
        let globals = GlobalShortcuts(store: store, hotKeys: HotKeys(backend: keys)) { _ in }
        globals.start()
        return globals
    }

    @MainActor @Test func aKeyAnotherAppHoldsIsRefusedAndTheWorkingOneStays() {
        let store = Store()
        let keys = SystemKeys()
        let globals = connected(store, keys)
        let keep = ShortcutAction.togglePanel.defaultShortcut
        let held = Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: [.control, .command])
        keys.taken = [held]
        let refusal = store.setShortcut(held, for: .togglePanel)
        #expect(refusal == .unavailable(held))
        // Stored and registered as before: nothing shows a key that does nothing, and the old one still works.
        #expect(store.shortcut(.togglePanel) == keep && store.settings.shortcuts == nil)
        #expect(keys[.togglePanel] == keep)
        // A refused reset of a custom key keeps the custom one too.
        let moved = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.control, .command])
        #expect(store.setShortcut(moved, for: .togglePanel) == nil)
        keys.taken = [keep]
        #expect(store.resetShortcut(for: .togglePanel) == .unavailable(keep))
        #expect(store.shortcut(.togglePanel) == moved && keys[.togglePanel] == moved)
        withExtendedLifetime(globals) {}
    }

    @MainActor @Test func resetRefusesADefaultAnotherActionHasTakenAndKeepsTheWorkingKey() {
        let store = Store()
        let keys = SystemKeys()
        let globals = connected(store, keys)
        let keepDefault = ShortcutAction.togglePanel.defaultShortcut
        let moved = Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: [.control, .command])
        store.setShortcut(moved, for: .togglePanel)
        // Open the Router takes the key the window's shortcut used to have: nothing holds it, so the recorder allows it.
        #expect(store.shortcutConflict(keepDefault, for: .router) == nil)
        store.setShortcut(keepDefault, for: .router)
        let refusal = store.resetShortcut(for: .togglePanel)
        #expect(refusal == .usedBy(.router))
        #expect(store.shortcut(.togglePanel) == moved)
        #expect(store.shortcut(.router) == keepDefault)
        #expect(keys[.togglePanel] == moved && keys[.router] == keepDefault)
        // Once the other action lets go of it, the reset goes through.
        store.setShortcut(nil, for: .router)
        #expect(store.resetShortcut(for: .togglePanel) == nil)
        #expect(store.shortcut(.togglePanel) == keepDefault)
        #expect(keys[.togglePanel] == keepDefault && keys[.router] == ShortcutAction.router.defaultShortcut)
        withExtendedLifetime(globals) {}
    }

    @MainActor @Test func restoreDefaultsResetsEveryShortcutAndRegistersTheGlobalOnesAgain() {
        let store = Store()
        store.persists = false
        var registered: [ShortcutAction] = []
        store.onGlobalShortcutChange = { action, _ in registered.append(action); return true }
        store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: [.control, .command]), for: .togglePanel)
        store.setShortcut(.unassigned, for: .discard)
        #expect(store.hasCustomShortcuts)
        registered = []
        #expect(store.restoreDefaultShortcuts() == nil)
        #expect(!store.hasCustomShortcuts)
        for action in ShortcutAction.allCases { #expect(store.shortcut(action) == action.defaultShortcut) }
        #expect(Set(registered) == [.togglePanel, .router])
    }

    @MainActor @Test func restoreDefaultsAfterSwappingTheGlobalKeysRegistersBothDefaults() {
        let store = Store()
        let keys = SystemKeys()
        let globals = connected(store, keys)
        let keep = ShortcutAction.togglePanel.defaultShortcut, sessions = ShortcutAction.router.defaultShortcut
        // Swapped the way the recorder allows it: through a key neither holds.
        store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: [.control, .command]), for: .togglePanel)
        store.setShortcut(keep, for: .router)
        store.setShortcut(sessions, for: .togglePanel)
        #expect(keys[.togglePanel] == sessions && keys[.router] == keep)
        // Each reset alone is refused, the other action holding its default.
        #expect(store.resetShortcut(for: .togglePanel) == .usedBy(.router))
        #expect(store.resetShortcut(for: .router) == .usedBy(.togglePanel))
        #expect(store.restoreDefaultShortcuts() == nil)
        #expect(keys[.togglePanel] == keep && keys[.router] == sessions)
        #expect(store.shortcut(.togglePanel) == keep && store.shortcut(.router) == sessions)
        #expect(store.refusedShortcuts.isEmpty)
        withExtendedLifetime(globals) {}
    }

    @MainActor @Test func restoreDefaultsRefusedByAnotherAppChangesNothing() {
        let store = Store()
        let keys = SystemKeys()
        let globals = connected(store, keys)
        let keep = ShortcutAction.togglePanel.defaultShortcut
        let moved = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.control, .command])
        store.setShortcut(moved, for: .togglePanel)
        store.setShortcut(.unassigned, for: .discard)
        let before = store.settings.shortcuts
        // Another app took the window shortcut's default after it was let go of.
        keys.taken = [keep]
        let refusal = store.restoreDefaultShortcuts()
        #expect(refusal == .defaultUnavailable(keep))
        // What worked still does, and so does what was cleared: stored, registered, shown.
        #expect(store.settings.shortcuts == before && store.shortcut(.togglePanel) == moved && store.shortcut(.discard).isUnassigned)
        #expect(keys[.togglePanel] == moved && keys[.router] == ShortcutAction.router.defaultShortcut)
        #expect(store.refusedShortcuts.isEmpty)
        // Once the other app lets go, the restore goes through.
        keys.taken = []
        #expect(store.restoreDefaultShortcuts() == nil && !store.hasCustomShortcuts)
        #expect(keys[.togglePanel] == keep && keys[.router] == ShortcutAction.router.defaultShortcut)
        withExtendedLifetime(globals) {}
    }

    @MainActor @Test func aKeyAnotherAppHeldAtLaunchIsStoredSaidOnceAndShownToDoNothing() async {
        let store = Store()
        let keys = SystemKeys()
        store.persists = false
        let held = Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: [.control, .command])
        store.setShortcut(held, for: .togglePanel)
        keys.taken = [held, ShortcutAction.router.defaultShortcut]
        store.router.enabled = false
        await Announced.exclusively {
            var said: [String] = []
            Announce.sink = { said.append($0) }
            let globals = GlobalShortcuts(store: store, hotKeys: HotKeys(backend: keys), perform: { _ in })
            globals.start()
            #expect(store.isShortcutHeldByAnotherApp(.togglePanel))
            #expect(said.count == 1)
            // The switcher is not registered while the Router is off, so there is nothing to refuse yet.
            #expect(!store.isShortcutHeldByAnotherApp(.router))
            store.agents.enabled = true
            store.router.enabled = true
            globals.register(.router)
            #expect(store.isShortcutHeldByAnotherApp(.router))
            // Another key that works clears it, as does the other app letting go.
            keys.taken = []
            #expect(store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.control, .command]), for: .togglePanel) == nil)
            #expect(!store.isShortcutHeldByAnotherApp(.togglePanel))
            globals.register(.router)
            #expect(!store.isShortcutHeldByAnotherApp(.router))
            // A refusal of a key just chosen leaves the old one stored and working: nothing to say.
            keys.taken = [held]
            #expect(store.setShortcut(held, for: .togglePanel) != nil)
            #expect(!store.isShortcutHeldByAnotherApp(.togglePanel))
        }
    }

    @MainActor @Test func aKeyAnotherAppTookWhileRecordingIsWarnedAboutAndCanBeTriedAgain() async {
        let store = Store()
        store.persists = false
        let keys = SystemKeys()
        await Announced.exclusively {
            var said: [String] = []
            Announce.sink = { said.append($0) }
            let globals = GlobalShortcuts(store: store, hotKeys: HotKeys(backend: keys), perform: { _ in })
            globals.start()
            let held = ShortcutAction.togglePanel.defaultShortcut
            #expect(keys[.togglePanel] == held)
            globals.suspend(true)
            #expect(keys[.togglePanel] == nil)
            keys.taken = [held]
            globals.suspend(false)
            #expect(keys[.togglePanel] == nil)
            #expect(store.isShortcutHeldByAnotherApp(.togglePanel))
            #expect(said.count == 1)
            // The other app lets go: asking again registers it and clears the warning.
            keys.taken = []
            #expect(store.retryShortcut(.togglePanel))
            #expect(keys[.togglePanel] == held)
            #expect(!store.isShortcutHeldByAnotherApp(.togglePanel))
            // Still held, it stays warned about.
            keys.taken = [held]
            globals.suspend(true)
            globals.suspend(false)
            #expect(!store.retryShortcut(.togglePanel))
            #expect(store.isShortcutHeldByAnotherApp(.togglePanel))
        }
    }

    @MainActor @Test func aRefusedReplacementKeepsTheWarningOfTheKeyStillStored() {
        let store = Store()
        let keys = SystemKeys()
        store.persists = false
        let a = Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: [.control, .command])
        let b = Shortcut(keyCode: UInt16(kVK_ANSI_J), modifiers: [.control, .command])
        store.setShortcut(a, for: .togglePanel)
        keys.taken = [a, b, ShortcutAction.router.defaultShortcut]
        let globals = GlobalShortcuts(store: store, hotKeys: HotKeys(backend: keys)) { _ in }
        globals.start()
        #expect(store.isShortcutHeldByAnotherApp(.togglePanel))
        // B is refused as well: A is still the stored binding and still does nothing.
        #expect(store.setShortcut(b, for: .togglePanel) == .unavailable(b))
        #expect(store.shortcut(.togglePanel) == a && store.isShortcutHeldByAnotherApp(.togglePanel))
        // A replacement that registers clears it.
        keys.taken = [a]
        let c = Shortcut(keyCode: UInt16(kVK_ANSI_H), modifiers: [.control, .command])
        #expect(store.setShortcut(c, for: .togglePanel) == nil)
        #expect(!store.isShortcutHeldByAnotherApp(.togglePanel) && store.refusedShortcuts[.togglePanel] == nil)
        withExtendedLifetime(globals) {}
    }

    @MainActor @Test func aClearedGlobalShortcutIsUnregisteredNotRegisteredAsNothing() {
        let store = Store()
        let keys = SystemKeys()
        let globals = connected(store, keys)
        store.setShortcut(.unassigned, for: .togglePanel)
        #expect(keys[.togglePanel] == nil)
        #expect(keys[.router] == ShortcutAction.router.defaultShortcut)
        store.setShortcut(nil, for: .togglePanel)
        #expect(keys[.togglePanel] == ShortcutAction.togglePanel.defaultShortcut)
        withExtendedLifetime(globals) {}
    }

    /// The Router's switch is what turns it off and on (Claude's sessions follow it): its keys go and come back with it.
    @MainActor @Test func theRoutersKeysAreRegisteredOnlyWhileTheRouterIsOn() async {
        let store = Store()
        let keys = SystemKeys()
        let globals = connected(store, keys)
        #expect(keys[.router] == ShortcutAction.router.defaultShortcut)
        #expect(keys[.router] == ShortcutAction.router.defaultShortcut)
        store.router.enabled = false
        await waitUntil { keys[.router] == nil && keys[.router] == nil }
        #expect(keys[.router] == nil && keys[.router] == nil)
        // The window's key isn't the Router's: it stays.
        #expect(keys[.togglePanel] == ShortcutAction.togglePanel.defaultShortcut)
        store.router.enabled = true
        await waitUntil { keys[.router] != nil && keys[.router] != nil }
        #expect(keys[.router] == ShortcutAction.router.defaultShortcut)
        #expect(keys[.router] == ShortcutAction.router.defaultShortcut)
        withExtendedLifetime(globals) {}
    }
}

/// The system's hot keys as Carbon keeps them: a combination already held, by Fjord Computer or by another app, is refused.
private final class SystemKeys: HotKeyBackend {
    private final class Registration {
        let id: UInt32, shortcut: Shortcut
        init(_ id: UInt32, _ shortcut: Shortcut) { self.id = id; self.shortcut = shortcut }
    }
    private var held: [Registration] = []
    /// Keys that other apps hold.
    var taken: Set<Shortcut> = []

    /// The key the system holds for `action`.
    subscript(action: ShortcutAction) -> Shortcut? { held.last { $0.id == action.hotKeyID }?.shortcut }

    func register(_ shortcut: Shortcut, id: UInt32) -> AnyObject? {
        guard !taken.contains(shortcut), !held.contains(where: { $0.shortcut == shortcut }) else { return nil }
        let registration = Registration(id, shortcut)
        held.append(registration)
        return registration
    }

    func unregister(_ registration: AnyObject) {
        held.removeAll { $0 === registration }
    }
}
