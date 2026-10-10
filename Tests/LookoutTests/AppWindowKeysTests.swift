import AppKit
import Carbon
import Foundation
import Testing
@testable import Lookout

/// The inbox's keys in the app window: the arrows, the configured actions, undo routing, search and Esc.
@MainActor
@Suite struct AppWindowKeysTests {
    struct Rig {
        let store: Store
        let navigator: AppNavigator
        let hub: HubState
        let search: InboxSearch
        let keys: AppWindowKeys
        let category: UUID
        var closed: Closed
        final class Closed { var count = 0 }
    }

    private func rig() -> Rig {
        let now = Date()
        let store = InboxFixture.store([
            InboxFixture.pr(1, title: "Alpha fix", updated: now),
            InboxFixture.pr(2, repo: "b/two", title: "Beta change", updated: now.addingTimeInterval(-10)),
            InboxFixture.pr(3, title: "Gamma", updated: now.addingTimeInterval(-20)),
        ])
        store.interceptOpen = { _ in }
        let category = store.categories[0].id
        let navigator = AppNavigator(fallback: .category(category), defaults: nil)
        let hub = HubState()
        let search = InboxSearch()
        let closed = Rig.Closed()
        let keys = AppWindowKeys(store: store, navigator: navigator, hub: hub, search: search) { closed.count += 1 }
        keys.isDeadKey = { _ in false }
        return Rig(store: store, navigator: navigator, hub: hub, search: search, keys: keys, category: category, closed: closed)
    }

    private func key(_ code: Int, _ chars: String = "", _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
    }

    private func ids(_ r: Rig) -> [String] { r.keys.targets() }

    // MARK: Selection

    @Test func theArrowsWalkTheRowsAndStopAtTheEnds() {
        let r = rig()
        let rows = ids(r)
        #expect(rows.count == 3)
        // Down from nothing picks the first, up from nothing the last.
        #expect(r.keys.key(key(kVK_DownArrow)))
        #expect(r.hub.selection == rows[0])
        _ = r.keys.key(key(kVK_DownArrow))
        _ = r.keys.key(key(kVK_DownArrow))
        _ = r.keys.key(key(kVK_DownArrow))
        #expect(r.hub.selection == rows[2])
        _ = r.keys.key(key(kVK_UpArrow))
        #expect(r.hub.selection == rows[1])
        #expect(r.hub.keyboardSelection?.id == rows[1])
        r.hub.selection = nil
        _ = r.keys.key(key(kVK_UpArrow))
        #expect(r.hub.selection == rows[2])
    }

    @Test func hoveringPicksAndTheArrowsGoOnFromThere() {
        let r = rig()
        r.hub.selection = ids(r)[1]
        _ = r.keys.key(key(kVK_DownArrow))
        #expect(r.hub.selection == ids(r)[2])
    }

    // MARK: Actions

    @Test func returnOpensOnGitHubAndMarksSeen() {
        let r = rig()
        var opened: [String] = []
        r.store.interceptOpen = { opened.append($0) }
        let rows = ids(r)
        r.hub.selection = rows[0]
        let entry = r.store.entries.first { "i:" + $0.id == rows[0] }!
        #expect(entry.isUnread)
        #expect(r.keys.key(key(kVK_Return)))
        #expect(opened.first?.contains("Alpha fix") == true)
        #expect(!r.store.entries.first { "i:" + $0.id == rows[0] }!.isUnread)
    }

    @Test func spaceMarksSeenAndOptionSpaceMarksAllSeen() {
        let r = rig()
        let rows = ids(r)
        r.hub.selection = rows[1]
        #expect(r.keys.key(key(kVK_Space, " ")))
        #expect(r.store.unreadCount(r.category) == 2)
        #expect(r.keys.key(key(kVK_Space, " ", .option)))
        #expect(r.store.unreadCount(r.category) == 0)
    }

    @Test func backspaceMovesToDoneAndPicksTheNextRowThenRestoresInDone() {
        let r = rig()
        let rows = ids(r)
        r.hub.selection = rows[0]
        #expect(r.keys.key(key(kVK_Delete)))
        #expect(r.store.entries(in: .done).count == 1)
        #expect(r.hub.selection == rows[1])
        #expect(r.store.entries(in: .category(r.category)).count == 2)
        // In Done the same key puts it back.
        r.navigator.go(.done)
        r.hub.selection = ids(r)[0]
        #expect(r.keys.key(key(kVK_Delete)))
        #expect(r.store.entries(in: .done).isEmpty)
        #expect(r.store.entries(in: .category(r.category)).count == 3)
    }

    @Test func nothingPickedMeansNoRowActionButMarkAllStillWorks() {
        let r = rig()
        #expect(!r.keys.key(key(kVK_Return)))
        #expect(!r.keys.key(key(kVK_Delete)))
        #expect(r.keys.key(key(kVK_Space, " ", .option)))
        #expect(r.store.unreadCount(r.category) == 0)
    }

    @Test func refreshIsHandledOnItsBinding() {
        let r = rig()
        r.store.isSyncing = true
        #expect(r.keys.key(key(kVK_ANSI_R, "r", .command)))
        r.store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_G), modifiers: .command), for: .refresh)
        #expect(!r.keys.key(key(kVK_ANSI_R, "r", .command)))
        #expect(r.keys.key(key(kVK_ANSI_G, "g", .command)))
    }

    // MARK: Layouts

    @Test func actionsMatchByKeyCodeNotByTheCharacterTheLayoutTypes() {
        let r = rig()
        // AZERTY: the key at ANSI R types "r" there too, but the key at ANSI A types "q": only the key position counts.
        r.store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_A)), for: .toggleRead)
        r.hub.selection = ids(r)[0]
        #expect(r.keys.key(key(kVK_ANSI_A, "q")))
        #expect(r.store.unreadCount(r.category) == 2)
        // A rebound Done key.
        r.store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_Semicolon), modifiers: .command), for: .discard)
        r.hub.selection = ids(r)[0]
        #expect(r.keys.key(key(kVK_ANSI_Semicolon, "m", .command)))
        #expect(r.store.entries(in: .done).count == 1)
    }

    @Test func aBoundLetterActsOnThePickBeforeItStartsASearch() {
        let r = rig()
        r.store.setShortcut(Shortcut(keyCode: UInt16(kVK_ANSI_D)), for: .discard)
        r.hub.selection = ids(r)[0]
        #expect(r.keys.key(key(kVK_ANSI_D, "d")))
        #expect(r.store.entries(in: .done).count == 1)
        #expect(r.search.focusRequest == 0)
        // Nothing picked: it is a letter like any other.
        r.hub.selection = nil
        #expect(r.keys.key(key(kVK_ANSI_D, "d")))
        #expect(r.search.focusRequest == 1)
    }

    // MARK: Undo

    @Test func commandZTakesBackADoneOnTheInboxAndShiftCommandZIsLeftAlone() {
        let r = rig()
        r.hub.selection = ids(r)[0]
        _ = r.keys.key(key(kVK_Delete))
        #expect(r.store.entries(in: .done).count == 1)
        #expect(!r.keys.key(key(kVK_ANSI_Z, "z", [.command, .shift])))
        #expect(r.store.entries(in: .done).count == 1)
        #expect(r.keys.key(key(kVK_ANSI_Z, "z", .command)))
        #expect(r.store.entries(in: .done).isEmpty)
        // Z by its character: the key at another position on AZERTY's W.
        #expect(!r.keys.key(key(kVK_ANSI_W, "w", .command)))
    }

    @Test func undoAndRedoOnTheCategoriesGoToTheEditorHistory() {
        let r = rig()
        let history = CategoryHistory(store: r.store)
        r.store.categoryHistory = history
        r.navigator.go(.categories)
        r.store.categories[0].name = "Renamed"
        history.observe(r.store)
        // Inbox's undo stack is not the one asked.
        r.store.undoStack.push("Moved to Done") { false }
        #expect(r.keys.key(key(kVK_ANSI_Z, "z", .command)))
        #expect(r.store.categories[0].name == "Mine")
        #expect(r.keys.key(key(kVK_ANSI_Z, "Z", [.command, .shift])))
        #expect(r.store.categories[0].name == "Renamed")
        // Without a history there is nothing to handle.
        r.store.categoryHistory = nil
        #expect(!r.keys.key(key(kVK_ANSI_Z, "z", .command)))
    }

    @Test func aFieldKeepsItsOwnUndoOnTheInboxButNotOnTheCategories() {
        let r = rig()
        let field = NSTextView()
        r.search.focused = true
        #expect(!r.keys.key(key(kVK_ANSI_Z, "z", .command), responder: field))
        r.navigator.go(.categories)
        r.store.categoryHistory = CategoryHistory(store: r.store)
        #expect(r.keys.key(key(kVK_ANSI_Z, "z", .command), responder: field))
    }

    // MARK: Search

    @Test func typingStartsASearchAndTheFieldGetsTheKey() {
        let r = rig()
        #expect(r.keys.key(key(kVK_ANSI_B, "b")))
        #expect(r.search.focusRequest == 1)
        #expect(r.search.pendingKeys.count == 1)
        // A space is not a start, nor is a chord.
        let spaceFirst = rig()
        #expect(!spaceFirst.keys.key(key(kVK_Space, " ")))
        #expect(!r.keys.key(key(kVK_ANSI_B, "b", .command)))
        // ⌘F asks for the field with no key.
        let find = rig()
        #expect(find.keys.key(key(kVK_ANSI_F, "f", .command)))
        #expect(find.search.focusRequest == 1 && find.search.pendingKeys.isEmpty)
    }

    @Test func searchFiltersAcrossCategoriesAndDoneByTitleRepoAuthorAndFacts() {
        let r = rig()
        r.hub.selection = ids(r)[0]
        _ = r.keys.key(key(kVK_Delete))
        func found(_ q: String) -> [String] { r.store.inboxRows(.category(r.category), search: q).map(\.thing.title) }
        // The one in Done is found too, after the open ones.
        #expect(found("a") == ["Beta change", "Gamma", "Alpha fix"])
        #expect(found("beta") == ["Beta change"])
        #expect(found("b/two") == ["Beta change"])
        #expect(found("@me gamma") == ["Gamma"])
        #expect(found("greptile 3/5").count == 3)
        #expect(found("nothing like it").isEmpty)
        r.search.query = "alpha"
        #expect(ids(r).count == 1)
    }

    @Test func theActionsActOnTheResultsOnlyAndReturnInTheFieldOpensThePick() {
        let r = rig()
        var opened: [String] = []
        r.store.interceptOpen = { opened.append($0) }
        r.search.query = "beta"
        r.search.focused = true
        let field = NSTextView()
        r.hub.selection = ids(r)[0]
        #expect(r.keys.key(key(kVK_Return), responder: field))
        #expect(opened.first?.contains("Beta change") == true)
        // A row the search hides is left alone.
        r.hub.selection = r.store.entries.first { $0.thing.title == "Gamma" }.map { "i:" + $0.id }
        #expect(!r.keys.key(key(kVK_Return), responder: field))
        // Mark all seen in a search is for the results.
        r.hub.selection = nil
        #expect(r.keys.key(key(kVK_Space, " ", .option), responder: field))
        #expect(r.store.unreadCount(r.category) == 2)
        // Typing, Space and Backspace are the field's own.
        #expect(!r.keys.key(key(kVK_Space, " "), responder: field))
        #expect(!r.keys.key(key(kVK_Delete), responder: field))
    }

    // MARK: Esc

    @Test func escapeStepsOutOneLevelAtATimeThenClosesTheWindow() {
        let r = rig()
        r.search.query = "beta"
        r.search.focused = true
        r.hub.selection = ids(r)[0]
        #expect(r.keys.key(key(kVK_Escape), responder: NSTextView()))
        #expect(r.search.query.isEmpty && !r.search.focused)
        #expect(r.hub.selection != nil && r.closed.count == 0)
        #expect(r.keys.key(key(kVK_Escape)))
        #expect(r.hub.selection == nil && r.closed.count == 0)
        #expect(r.keys.key(key(kVK_Escape)))
        #expect(r.closed.count == 1)
    }

    @Test func otherDestinationsKeepTheirOwnKeys() {
        let r = rig()
        for place in [AppDestination.settings, .router] {
            r.navigator.go(place)
            #expect(!r.keys.key(key(kVK_Escape)))
            #expect(!r.keys.key(key(kVK_DownArrow)))
        }
        #expect(r.closed.count == 0)
    }

    @Test func aKeyInAnInputMethodsCompositionIsItsOwn() {
        let r = rig()
        let field = NSTextView()
        field.string = ""
        field.setMarkedText("a", selectedRange: NSRange(location: 0, length: 1), replacementRange: NSRange(location: 0, length: 0))
        #expect(!r.keys.key(key(kVK_Escape), responder: field))
        #expect(r.closed.count == 0)
    }
}

/// Where the window goes when it opens on the bar's screen.
@Suite struct AppWindowPlacementTests {
    private let main = NSRect(x: 0, y: 0, width: 1600, height: 1000)
    private let side = NSRect(x: 1600, y: 100, width: 1200, height: 800)

    @Test func aFrameAlreadyOnTheScreenIsKept() {
        let frame = NSRect(x: 200, y: 150, width: 1180, height: 760)
        #expect(AppWindowPlacement.frame(frame, from: main, in: main) == frame)
    }

    @Test func aFrameHalfOffTheScreenIsPulledInside() {
        let frame = NSRect(x: 1200, y: 600, width: 1180, height: 760)
        #expect(AppWindowPlacement.frame(frame, from: main, in: main) == NSRect(x: 420, y: 240, width: 1180, height: 760))
    }

    @Test func anotherScreenKeepsTheRelativePlaceAndSize() {
        // Centred on the main screen: centred on the other.
        let frame = NSRect(x: 210, y: 120, width: 1180, height: 760)
        let moved = AppWindowPlacement.frame(frame, from: main, in: side)
        #expect(moved.size == NSSize(width: 1180, height: 760) || moved.size.width <= side.width)
        #expect(side.contains(moved.origin))
        #expect(abs(moved.midX - side.midX) < 1 && abs(moved.midY - side.midY) < 1 || moved.width == side.width)
        // A frame at the main screen's left edge lands at the other's left edge.
        let left = NSRect(x: 0, y: 100, width: 800, height: 600)
        let placed = AppWindowPlacement.frame(left, from: main, in: side)
        #expect(placed.minX == side.minX && side.contains(NSPoint(x: placed.maxX - 1, y: placed.maxY - 1)))
    }

    @Test func aSmallScreenShrinksTheWindowToFit() {
        let small = NSRect(x: 3000, y: 0, width: 900, height: 600)
        let frame = NSRect(x: 100, y: 100, width: 1180, height: 760)
        let moved = AppWindowPlacement.frame(frame, from: main, in: small)
        #expect(moved == small)
    }

    @Test func withNoScreenToComeFromItIsCentred() {
        let frame = NSRect(x: -5000, y: -5000, width: 1000, height: 600)
        let moved = AppWindowPlacement.frame(frame, from: nil, in: side)
        #expect(moved == NSRect(x: 1700, y: 200, width: 1000, height: 600))
    }
}
