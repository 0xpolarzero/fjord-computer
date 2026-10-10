import AppKit
import Carbon
import Foundation
import Testing
@testable import Lookout

/// What the user bound comes before the typing that starts a search.
@MainActor
@Suite struct HubKeysBindings {
    private let store = Store()
    private let hub = HubState()
    private let keys: HubKeys

    init() {
        store.persists = false
        keys = HubKeys(store: store, ui: UIState(persists: false, edge: .right), hub: hub)
        store.categories = [InboxFixture.category()]
        store.things = ["pr:a/one#1": InboxFixture.pr(1)]
        hub.pinned = true
        hub.selection = "i:pr:a/one#1"
    }

    @discardableResult
    private func press(_ code: Int, _ flags: NSEvent.ModifierFlags = [], _ chars: String) -> Bool {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                                     characters: chars, charactersIgnoringModifiers: chars.lowercased(), isARepeat: false, keyCode: UInt16(code))!
        return keys.key(event)
    }

    private var entry: InboxEntry? { store.entries.first { $0.id == "pr:a/one#1" } }

    @Test func aLetterBoundToAnActionActsOnThePickedRowInsteadOfSearching() {
        #expect(entry?.isUnread == true)
        store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_T)), for: .toggleRead)
        #expect(press(kVK_ANSI_T, [], "t"))
        #expect(entry?.isUnread == false && hub.query.isEmpty)
        // With Shift: a Shift-letter binding is the same.
        store.marks = [:]
        store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_Y), modifiers: [.shift]), for: .toggleRead)
        #expect(press(kVK_ANSI_Y, [.shift], "Y"))
        #expect(entry?.isUnread == false && hub.query.isEmpty)
    }

    @Test func anUnboundLetterOrOneWithNothingPickedStillSearches() {
        store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_T)), for: .toggleRead)
        // The field types the key (it is handed over, not read here): the search is open and holds it.
        #expect(press(kVK_ANSI_Z, [], "z") && hub.searchOpen && hub.pendingKeys.count == 1)
        // A search that has typed something takes every letter, the bound one too.
        hub.query = "z"
        #expect(press(kVK_ANSI_T, [], "t") && hub.pendingKeys.count == 2 && entry?.isUnread == true)
        hub.endSearch()
        hub.selection = nil
        #expect(press(kVK_ANSI_T, [], "t") && hub.searchOpen && hub.pendingKeys.count == 1)
    }

    @Test func typingWithASectionExpandedStartsTheSearchInTheInbox() {
        // The inbox header holds the field, and an expanded Sessions section leaves it out.
        hub.focus = .agents
        #expect(press(kVK_ANSI_Z, [], "z") && hub.searchOpen && hub.focus == nil)
    }

    @Test func spaceStillTypesInASearchThatHasStarted() {
        // Space is the default Mark read key: it acts on the picked row until a search has started, then it is a space.
        #expect(press(kVK_Space, [], " ") && entry?.isUnread == false)
        hub.query = "two"
        store.marks = [:]
        #expect(press(kVK_Space, [], " ") && hub.pendingKeys.last?.characters == " " && entry?.isUnread == true)
    }
}
