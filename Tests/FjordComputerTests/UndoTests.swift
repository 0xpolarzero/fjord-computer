import AppKit
import Carbon
import Foundation
import SwiftUI
import Testing
@testable import FjordComputer

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

    @Test func aSeenThingCanBeUnreadAgainWithoutNotifyingAgain() {
        let s = store([1])
        s.markSeen(entry(s, 1)!)
        let keys = Set(entry(s, 1)!.facts.map(\.key))
        s.marks["pr:a/one#1"]?.notified = keys
        #expect(entry(s, 1)?.isUnread == false)
        s.markUnread(entry(s, 1)!)
        #expect(entry(s, 1)?.isUnread == true && entry(s, 1)?.isDone == false)
        #expect(s.marks["pr:a/one#1"]?.notified == keys)
    }

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
        var said = 0
        s.undoStack.announce = { _ in said += 1 }
        s.finish(entry(s, 1)!)
        s.finish(s.doneEntries[0])
        #expect(said == 1)
    }

    @Test func theLineShowsThenGoesAndTheUndoStaysForCommandZ() async throws {
        let s = store([1])
        let gate = Gate()
        s.undoStack.sleep = { _ in await gate.wait() }
        s.finish(entry(s, 1)!)
        #expect(s.undoStack.line != nil)
        gate.open()
        try await eventually { s.undoStack.line == nil }
        #expect(s.undoStack.line == nil && s.undoLast() && isDone(s, 1) == false)
    }

    @Test func thePeeksUndoLinePutsTheThingBack() async throws {
        let s = store([1, 2])
        let ui = UIState(persists: false, edge: .right)
        s.finish(entry(s, 1)!)
        // The line as the inbox peek shows it, its Undo button on the Tab ring.
        let host = NSHostingView(rootView: FjordHub(store: s, ui: ui, hub: HubState()).undoLine.frame(width: 400))
        let window = AwayWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 60), styleMask: .titled, backing: .buffered, defer: false)
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
        #expect(isDone(s, 1) == true)
        undo.performClick(nil)
        #expect(isDone(s, 1) == false && entry(s, 2)?.isUnread == true)
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
@MainActor private func eventually(sourceLocation: SourceLocation = #_sourceLocation, _ condition: () -> Bool) async throws {
    await waitUntil(sourceLocation: sourceLocation, condition)
}
