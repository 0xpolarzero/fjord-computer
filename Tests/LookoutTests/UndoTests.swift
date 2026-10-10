import AppKit
import Carbon
import Foundation
import SwiftUI
import Testing
@testable import Lookout

/// Done can be taken back: ⌘Z and the line's button, for 30 seconds.
@MainActor
@Suite(.hostsWindows) struct Undo {
    private func store(_ numbers: [Int]) -> Store {
        let s = InboxFixture.store(numbers.map { InboxFixture.pr($0) })
        s.undoStack.announce = { _ in }
        return s
    }

    private func entry(_ s: Store, _ n: Int) -> InboxEntry? { s.entries.first { $0.id == "pr:a/one#\(n)" } }
    private func isDone(_ s: Store, _ n: Int) -> Bool? { entry(s, n)?.isDone }

    @Test func undoPutsBackWhatDoneMovedAsItWas() {
        let s = store([1, 2])
        // The second was seen before; the first is still unread.
        s.markSeen(entry(s, 2)!)
        s.finish(entry(s, 1)!)
        s.finish(entry(s, 2)!)
        #expect(isDone(s, 1) == true && isDone(s, 2) == true)
        // Newest first, each as it was: unread stays unread.
        #expect(s.undoLast() && isDone(s, 2) == false && entry(s, 2)?.isUnread == false && isDone(s, 1) == true)
        #expect(s.undoLast() && isDone(s, 1) == false && entry(s, 1)?.isUnread == true)
        #expect(!s.undoLast())
    }

    @Test func undoLeavesAloneWhatChangedSince() {
        let s = store([1, 2])
        s.finish(entry(s, 1)!)
        s.restore(entry(s, 1)!)  // already back, by hand
        #expect(!s.undoLast() && isDone(s, 1) == false)
        // A thing that is gone is skipped for the one before it.
        s.finish(entry(s, 2)!)
        s.finish(entry(s, 1)!)
        s.things["pr:a/one#1"] = nil
        #expect(s.undoLast() && isDone(s, 2) == false)
    }

    @Test func undoOnlyReachesBack30Seconds() {
        let s = store([1])
        s.finish(entry(s, 1)!)
        #expect(!s.undoStack.undo(now: Date().addingTimeInterval(UndoStack.validFor + 1)) && isDone(s, 1) == true)
    }

    @Test func doneIsNotAskedTwice() {
        let s = store([1])
        s.finish(entry(s, 1)!)
        s.finish(s.doneEntries[0])
        #expect(s.undoStack.entries.count == 1)
    }

    @Test func theLineShowsThenGoesAndTheUndoStaysForCommandZ() async throws {
        let s = store([1])
        let gate = Gate()
        s.undoStack.sleep = { _ in await gate.wait() }
        s.finish(entry(s, 1)!)
        #expect(s.undoStack.line?.message == "Moved to Done")
        gate.open()
        try await eventually { s.undoStack.line == nil }
        #expect(s.undoStack.line == nil && s.undoLast() && isDone(s, 1) == false)
    }

    @Test func commandZInTheHubUndoesButAFocusedFieldKeepsIt() {
        let s = store([1])
        let hub = HubState()
        hub.pinned = true
        let keys = HubKeys(store: s, ui: UIState(persists: false, edge: .right), hub: hub)
        func press(in window: NSWindow? = nil) -> Bool {
            keys.key(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                      windowNumber: window?.windowNumber ?? 0, context: nil, characters: "z",
                                      charactersIgnoringModifiers: "z", isARepeat: false, keyCode: UInt16(kVK_ANSI_Z))!)
        }
        s.finish(entry(s, 1)!)
        // The search field's ⌘Z is its own undo: its field editor has the keyboard.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 60), styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(frame: NSRect(x: 10, y: 10, width: 180, height: 24))
        window.contentView?.addSubview(field)
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        window.makeFirstResponder(field)
        defer { window.close() }
        hub.searchFocused = true
        hub.searchOpen = true
        #expect(!press(in: window))
        #expect(isDone(s, 1) == true)
        hub.endSearch()
        window.makeFirstResponder(nil)
        #expect(press(in: window) && isDone(s, 1) == false)
        #expect(!press(in: window))
    }

    @Test func theFocusedUndoButtonKeepsSpaceAndReturn() async throws {
        let s = store([1, 2])
        let ui = UIState(persists: false, edge: .right)
        let hub = HubState()
        hub.pinned = true
        let keys = HubKeys(store: s, ui: ui, hub: hub)
        func press(_ code: Int, _ chars: String, in window: NSWindow) -> Bool {
            keys.key(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                      context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false,
                                      keyCode: UInt16(code))!)
        }
        s.finish(entry(s, 1)!)
        keys.select("i:pr:a/one#2")
        // The line as the hub shows it, its Undo button on the Tab ring.
        let host = NSHostingView(rootView: LookoutHub(store: s, ui: ui, hub: hub).undoLine.frame(width: 400))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 60), styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = host
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.orderFrontRegardless()
        defer { window.close() }
        // Until its button is laid out, however slowly.
        await waitUntil {
            host.layoutSubtreeIfNeeded()
            return host.first(NSButton.self) != nil
        }
        let undo = try #require(host.first(NSButton.self))
        #expect(window.makeFirstResponder(undo))
        // Space and Return are the button's: the picked row is not marked seen, and the button still activates.
        #expect(!press(kVK_Space, " ", in: window) && !press(kVK_Return, "\r", in: window) && !press(kVK_ANSI_KeypadEnter, "\r", in: window))
        #expect(entry(s, 2)?.isUnread == true && isDone(s, 1) == true)
        undo.performClick(nil)
        #expect(isDone(s, 1) == false)
        // Off the button they are the hub's again.
        window.makeFirstResponder(nil)
        #expect(press(kVK_Space, " ", in: window) && entry(s, 2)?.isUnread == false)
    }
}

private extension NSView {
    /// The first view of `type` at or below this one.
    func first<V: NSView>(_ type: V.Type) -> V? {
        (self as? V) ?? subviews.lazy.compactMap { $0.first(type) }.first
    }
}

/// Holds a sleeper until the test lets it go.
@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

/// Waits for `condition`, which something the test started brings about (see `waitUntil`).
@MainActor private func eventually(_ condition: () -> Bool) async throws {
    await waitUntil(condition)
}
