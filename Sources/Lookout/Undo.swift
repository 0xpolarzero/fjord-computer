import AppKit
import Foundation
import Observation
import SwiftUI

// Undo for Done: a line under the inbox's header offers it for a few seconds, ⌘Z works for 30.

/// The last few things moved out of sight, newest last. Each is good for `validFor` seconds; the line on show is dismissed
/// by a one-shot timer, cancelled whenever it is replaced, undone or dismissed (nothing ticks at rest).
@MainActor @Observable
final class UndoStack {
    struct Entry: Identifiable {
        let id = UUID()
        /// The undo line's text: "Moved to Done".
        let message: String
        let at: Date
        /// Whether anything was put back: false once what it concerned is gone.
        let revert: @MainActor () -> Bool
    }

    /// How long the line stays, and how long ⌘Z keeps working after the action.
    static let lineLifetime: Duration = .seconds(6)
    nonisolated static let validFor: TimeInterval = 30
    static let depth = 10

    private var entries: [Entry] = []
    /// The entry whose line is showing.
    private(set) var visibleID: Entry.ID?
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// What a screen reader is told; the tests replace it (there is no app to post to).
    @ObservationIgnored var announce: (String) -> Void = { text in
        guard NSApp != nil else { return }
        AccessibilityNotification.Announcement(text).post()
    }
    /// Waits out the line's lifetime; the tests swap in one they release by hand.
    @ObservationIgnored var sleep: @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }

    /// The entry to show in the undo line.
    var line: Entry? {
        guard let visibleID else { return nil }
        return entries.last { $0.id == visibleID }
    }

    func push(_ message: String, now: Date = Date(), revert: @escaping @MainActor () -> Bool) {
        entries.removeAll { now.timeIntervalSince($0.at) > Self.validFor }
        let entry = Entry(message: message, at: now, revert: revert)
        entries.append(entry)
        if entries.count > Self.depth { entries.removeFirst(entries.count - Self.depth) }
        show(entry)
        announce(message + ". Undo available")
    }

    /// Takes back the newest action still within its 30 s that has something left to put back; false when there is none.
    @discardableResult
    func undo(now: Date = Date()) -> Bool {
        entries.removeAll { now.timeIntervalSince($0.at) > Self.validFor }
        dismiss()
        while let entry = entries.popLast() {
            if entry.revert() {
                announce("Undone")
                return true
            }
        }
        return false
    }

    /// Hides the line (the action stays undoable with ⌘Z until it expires).
    func dismiss() {
        timer?.cancel()
        timer = nil
        visibleID = nil
    }

    private func show(_ entry: Entry) {
        timer?.cancel()
        visibleID = entry.id
        timer = Task { [weak self] in
            await self?.sleep(Self.lineLifetime)
            guard !Task.isCancelled, let self, visibleID == entry.id else { return }
            visibleID = nil
        }
    }
}

extension Store {
    /// ⌘Z and the line's button.
    @discardableResult func undoLast() -> Bool { undoStack.undo() }
}

// MARK: - The categories page's history

/// Undo and redo for the categories page: snapshots of the categories and groups, taken as they change (every edit is
/// applied at once). Typing in one field is one step until it pauses.
@MainActor @Observable
final class CategoryHistory {
    struct Snapshot: Equatable {
        var categories: [InboxCategory]
        var groups: [InboxGroup]
        var sections: [CategorySection] = []
    }

    static let limit = 200
    /// A pause this long ends a run of typing in one field.
    nonisolated static let pause: TimeInterval = 1

    private(set) var undos: [Snapshot] = []
    private(set) var redos: [Snapshot] = []
    @ObservationIgnored private var current: Snapshot
    @ObservationIgnored private var lastField: ObjectIdentifier?
    @ObservationIgnored private var lastAt = Date.distantPast

    var canUndo: Bool { !undos.isEmpty }
    var canRedo: Bool { !redos.isEmpty }
    /// New category's draft is open: ⌘Z is its fields', not the page's.
    @ObservationIgnored var drafting = false

    init(store: Store) { current = Snapshot(categories: store.categories, groups: store.groups, sections: store.categorySections) }

    /// Notes what the store holds now. `field` is the text field being typed in, if any: changes in it, each within a
    /// second of the last, are one step.
    func observe(_ store: Store, field: ObjectIdentifier? = nil, now: Date = Date()) {
        let snapshot = Snapshot(categories: store.categories, groups: store.groups, sections: store.categorySections)
        guard snapshot != current else { return }
        let merges = field != nil && field == lastField && now.timeIntervalSince(lastAt) <= Self.pause && !undos.isEmpty
        if !merges {
            undos.append(current)
            if undos.count > Self.limit { undos.removeFirst(undos.count - Self.limit) }
        }
        redos.removeAll()
        current = snapshot
        lastField = field
        lastAt = now
    }

    @discardableResult func undo(_ store: Store) -> Bool {
        flush(store)
        guard let previous = undos.popLast() else { return false }
        redos.append(current)
        apply(previous, to: store, as: .undo)
        return true
    }

    @discardableResult func redo(_ store: Store) -> Bool {
        flush(store)
        guard let next = redos.popLast() else { return false }
        undos.append(current)
        apply(next, to: store, as: .redo)
        return true
    }

    /// Forgets every step and takes the store as it is now as the start: a change made elsewhere (the Router's) is not a step
    /// of the page, and undoing one made before it would undo that too.
    func reset(to store: Store) {
        undos.removeAll()
        redos.removeAll()
        current = Snapshot(categories: store.categories, groups: store.groups, sections: store.categorySections)
        lastField = nil
    }

    /// An edit the page has not yet been told about counts as the step it belongs to.
    private func flush(_ store: Store) {
        observe(store, field: lastField, now: lastAt)
    }

    private func apply(_ snapshot: Snapshot, to store: Store, as source: InboxChangeSource) {
        current = snapshot
        lastField = nil
        store.changingInbox(source) {
            store.categories = snapshot.categories
            store.groups = snapshot.groups
            store.categorySections = snapshot.sections
        }
    }
}

extension CategoryHistory {
    /// The text field being typed in: its owner, so two fields are two steps.
    static func typingField() -> ObjectIdentifier? {
        guard let text = NSApp?.keyWindow?.firstResponder as? NSTextView else { return nil }
        return ObjectIdentifier((text.delegate as AnyObject?) ?? text)
    }
}
