import AppKit
import Carbon
import Foundation
import SwiftUI
import Testing
import UserNotifications
@testable import Lookout

/// The Router's UI: the window's keys and model, the banners and the shortcut.
@MainActor
@Suite struct RouterUITests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func demo(_ scenario: Demo.Scenario = .router) -> Store {
        let store = Store()
        Demo.populate(store, scenario)
        store.interceptOpen = { _ in }
        return store
    }

    private func key(_ code: Int, _ chars: String = "", _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
    }

    /// The composer's text view holding `text`, the caret at `caret` (the end by default), as the keys see it.
    private func editor(_ model: RouterModel, _ text: String, caret: Int? = nil) -> NSTextView {
        model.draft = text
        let view = NSTextView()
        view.string = text
        view.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        model.followCaret(view)
        return view
    }

    // MARK: Window keys

    @Test func arrowsWalkTheCardsAndSpaceAddressesThePickedOne() {
        let store = demo()
        let model = RouterModel()
        var closed = false
        let keys = RouterKeys(store: store, model: model) { closed = true }
        let open = model.cards(store).filter(\.isOpen).map(\.id)
        #expect(keys.key(key(kVK_DownArrow), responder: nil))
        #expect(model.selection == open[0])
        #expect(keys.key(key(kVK_DownArrow), responder: nil))
        #expect(model.selection == open[1])
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        #expect(store.router.cards.first { $0.id == open[1] }?.addressedBy == .you)
        // The addressed card goes up to the history: the next open one is picked.
        #expect(model.selection == open[2])
        #expect(keys.key(key(kVK_Escape), responder: nil) && closed)
    }

    @Test func theArrowsWalkTheCardsInTheOrderThePageShowsThem() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        reopenTransfer(store)
        // Two addressed cards in the history, the one addressed now below the older one.
        store.setCardAddressed(store.openRouterCards.first { $0.kind == .stuck }!.id, true)
        // Down the page: the history's addressed cards as it draws them (oldest first, above), then what needs you, then the
        // finished turns. Not the newest first, which puts a finished turn second and walks the history upwards.
        let (needs, done, earlier) = model.sections(store)
        let listed = (earlier + needs + done).map(\.id)
        #expect(!needs.isEmpty && !done.isEmpty && earlier.count > 1)
        #expect(earlier.map(\.id) == store.routerHistory.compactMap { if case .card(let c) = $0 { c.id } else { nil } })
        #expect(earlier.map(\.addressedAt!) == earlier.map(\.addressedAt!).sorted())
        #expect(model.cards(store).map(\.id) == listed)
        // None picked, ↓ starts at the top of Needs you and goes down the screen.
        var walked: [String] = []
        for _ in needs + done {
            #expect(keys.key(key(kVK_DownArrow), responder: nil))
            walked += model.selection.map { [$0] } ?? []
        }
        #expect(walked == (needs + done).map(\.id))
        // At the bottom it stays there; ↑ walks back up the same way, into the history up to its oldest card.
        #expect(keys.key(key(kVK_DownArrow), responder: nil) && model.selection == listed.last)
        walked = []
        for _ in 1..<listed.count {
            #expect(keys.key(key(kVK_UpArrow), responder: nil))
            walked += model.selection.map { [$0] } ?? []
        }
        #expect(walked == listed.dropLast().reversed())
        #expect(keys.key(key(kVK_UpArrow), responder: nil) && model.selection == listed.first)
    }

    /// The demo's finished turn whose session is idle, open again: its only open one is from a session still running things.
    private func reopenTransfer(_ store: Store) {
        guard let i = store.router.cards.firstIndex(where: { $0.sessionID == "local_demo-transfer" && $0.kind == .done }) else { return }
        store.router.cards[i].addressedAt = nil
        store.router.cards[i].addressedBy = nil
    }

    @Test func aFinishedTurnNotShownWhileItsSessionRunsThingsIsNotWalkedPickedNorCounted() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let hidden = store.openRouterCards.first { $0.sessionID == "local_demo-ci" && $0.kind == .done }!
        #expect(!(store.claudeTasks["local_demo-ci"] ?? []).isEmpty)
        #expect(!store.routerPage.needs.contains { $0.id == hidden.id })
        #expect(!model.cards(store).contains { $0.id == hidden.id })
        // The arrows never land on it, a pick on it moves off, and Return and Space can't reach it.
        for _ in 0...model.cards(store).count {
            #expect(keys.key(key(kVK_DownArrow), responder: nil))
            #expect(model.selection != hidden.id)
        }
        model.selection = hidden.id
        model.reconcile(store: store)
        #expect(model.selection != hidden.id)
        #expect(keys.key(key(kVK_Return, "\r"), responder: nil) && model.replyTo != hidden.id)
        // Away, it isn't said to have finished, nor counted.
        #expect(AwayStrip(since: Date(), cards: [hidden.id]).line(store.routerShownCards) == nil)
        #expect(store.routerCounts.done == 0)
        // Once what it ran ends, it is everywhere.
        store.claudeTasks["local_demo-ci"] = nil
        #expect(store.routerPage.needs.contains { $0.id == hidden.id })
        #expect(model.cards(store).contains { $0.id == hidden.id })
        #expect(AwayStrip(since: Date(), cards: [hidden.id]).line(store.routerShownCards) == "1 finished")
        #expect(store.routerCounts.done == 1)
    }

    @Test func mutingAProjectWhoseFinishedSessionStillRunsThingsKeepsItsCardHiddenOnThePageAsForTheKeys() {
        let store = demo()
        let model = RouterModel()
        let hidden = store.openRouterCards.first { $0.sessionID == "local_demo-ci" && $0.kind == .done }!
        store.setFolderMuted(store.claudeSessions["local_demo-ci"]!.folderKey, true)
        // Its Working row goes with the mute; what it runs doesn't, and the page goes by that as the keys and counts do.
        #expect(!store.routerWorkingRows.contains { $0.id == "local_demo-ci" })
        #expect(!store.routerPage.needs.contains { $0.id == hidden.id })
        #expect(!store.routerZones.needs.contains { $0.id == hidden.id })
        #expect(!model.cards(store).contains { $0.id == hidden.id })
        #expect(store.routerCounts.done == 0)
        store.claudeTasks["local_demo-ci"] = nil
        #expect(store.routerPage.needs.contains { $0.id == hidden.id })
        #expect(model.cards(store).contains { $0.id == hidden.id })
    }

    @Test func aFinishedTurnNotShownIsNeitherASupersededCardsSuccessorNorATargetOfJevsOrASend() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let hidden = store.openRouterCards.first { $0.sessionID == "local_demo-ci" && $0.kind == .done }!
        var older = hidden
        older.id = hidden.id + "-older"
        older.addressedAt = hidden.createdAt
        older.addressedBy = .superseded
        store.router.cards.append(older)
        // Space on the superseded card in the history: its session's newer card isn't on the page, so the pick stays.
        model.select(older.id, store: store)
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        #expect(model.selection == older.id && model.replyTo == nil)
        // Jev neither offers it nor goes to it, and a pin on it doesn't hold; the history's card is still replied to.
        let tools = RouterTools(store: store)
        #expect(!tools.targets(store).contains { $0.target == "answer:\(hidden.id)" })
        #expect(!store.routerDispatcher.eligible("answer:\(hidden.id)", store: store))
        #expect(store.routerDispatcher.option("answer:\(hidden.id)", store: store) == nil)
        #expect(!RouterModel.targets(store).contains(hidden.id))
        #expect(store.routerDispatcher.option("answer:\(older.id)", store: store) != nil)
        #expect(RouterDispatcher.plan(text: "hi", context: RouterContext(replyTo: older.id), store: store)
                == .reply(session: older.sessionID, card: older.id))
        // Once what it ran ends, it is all of these.
        store.claudeTasks["local_demo-ci"] = nil
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        #expect(model.selection == hidden.id)
        #expect(tools.targets(store).contains { $0.target == "answer:\(hidden.id)" })
        #expect(store.routerDispatcher.eligible("answer:\(hidden.id)", store: store))
        #expect(RouterModel.targets(store).contains(hidden.id))
    }

    @Test func spaceOpensAgainOnlyWhatReopenDoesNotACardWhoseSessionIsGone() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let ids = store.routerShownOpenCards.filter { $0.kind != .waiting }.prefix(2).map(\.id)
        #expect(ids.count == 2)
        let i = store.router.cards.firstIndex { $0.id == ids[0] }!
        store.router.cards[i].addressedAt = now
        store.router.cards[i].addressedBy = .gone
        #expect(!store.router.cards[i].canReopen)
        // Space on the archived session's card in the history: it stays addressed, with its reason.
        model.select(ids[0], store: store)
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        #expect(store.router.cards[i].addressedBy == .gone && !store.router.cards[i].isOpen)
        model.reopen(ids[0], store: store)
        #expect(store.router.cards[i].addressedBy == .gone)
        // A card you addressed opens again with Space, as with Reopen.
        store.setCardAddressed(ids[1], true)
        #expect(store.router.cards.first { $0.id == ids[1] }!.canReopen)
        model.select(ids[1], store: store)
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        #expect(store.router.cards.first { $0.id == ids[1] }!.isOpen)
    }

    @Test func aHandledCardIsNotOpenedAgainOnceItsSessionIsArchivedOrDeleted() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let ids = store.routerShownOpenCards.filter { $0.kind != .waiting }.prefix(2).map(\.id)
        #expect(ids.count == 2)
        let cards = ids.map { id in store.router.cards.first { $0.id == id }! }
        #expect(cards[0].sessionID != cards[1].sessionID)
        for id in ids { store.setCardAddressed(id, true) }
        let handled = ids.map { id in store.router.cards.first { $0.id == id }! }
        #expect(handled.allSatisfy { store.routerCanReopen($0) })
        // Handled, then its session archived (the first) or deleted (the second): only open cards are marked gone.
        store.claudeSessions[cards[0].sessionID]?.isArchived = true
        store.claudeSessions[cards[1].sessionID] = nil
        for card in handled { #expect(!store.routerCanReopen(card)) }
        model.reopen(ids[0], store: store)
        model.select(ids[1], store: store)
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        #expect(ids.allSatisfy { id in store.router.cards.first { $0.id == id }?.isOpen == false })
        // Before the sessions are read, nothing is known gone.
        store.claudeLink = .off
        #expect(store.routerCanReopen(handled[1]))
    }

    @Test func returnInTheComposerSendsAndShiftReturnDoesNot() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let editor = NSTextView()
        model.composerFocused = true
        model.draft = "tell lookout to run the tests"
        let before = store.router.decisions.count
        #expect(keys.key(key(kVK_Return, "\r", .shift), responder: editor))
        #expect(store.router.decisions.count == before && !model.draft.isEmpty)
        #expect(keys.key(key(kVK_Return, "\r"), responder: editor))
        #expect(model.draft.isEmpty)
        #expect(store.router.decisions.dropFirst(before).first?.triggerText == "tell lookout to run the tests")
        // Typing in the composer is its own.
        #expect(!keys.key(key(kVK_ANSI_A, "a"), responder: editor))
    }

    @Test func typingWithNothingFocusedGoesToTheComposer() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let request = model.focusRequest
        #expect(keys.key(key(kVK_ANSI_H, "h"), responder: nil))
        #expect(model.focusRequest != request && model.pendingKeys.count == 1)
    }

    @Test func spaceNeverReopensACardThatWasSupersededUnderIt() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let question = store.openRouterCards.first { $0.kind == .question }!
        model.select(question.id, store: store)
        model.reconcile(store: store)
        // A newer card for the same session supersedes the picked one, which is no longer open.
        var newer = question
        newer.id = question.id + "-newer"
        newer.createdAt = Date()
        RouterFeed.address(&store.router, question.sessionID, .superseded, Date())
        store.router.cards.append(newer)
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        let old = store.router.cards.first { $0.id == question.id }!
        #expect(old.addressedBy == .superseded)
        #expect(model.selection != question.id && !store.openRouterCards.contains { $0.id == question.id })
        // Nothing picked at all: Space does nothing.
        model.selection = nil
        let before = store.router.cards
        #expect(keys.key(key(kVK_Space, " "), responder: nil))
        #expect(store.router.cards == before)
    }

    // MARK: Sending

    @Test func theComposerIsShutWhileTheRouterOrTheSessionsAreOff() {
        let store = demo()
        let model = RouterModel()
        let before = store.router.decisions.count
        #expect(model.canSend(store))
        store.router.enabled = false
        #expect(!model.canSend(store))
        store.router.enabled = true
        store.agents.enabled = false
        #expect(!model.canSend(store))
        model.draft = "hello"
        model.send(store: store)
        #expect(model.draft == "hello" && store.router.decisions.count == before)
        // Typing with nothing focused doesn't go to a composer that can't send.
        let keys = RouterKeys(store: store, model: model) {}
        #expect(!keys.key(key(kVK_ANSI_H, "h"), responder: nil))
    }

    @Test func claudeCodeMissingIsSaidOnceLookedForAndSendWaits() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("router-ui-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // A store of a real Router (not a demo's), the app's folder of Claude Code in `dir`.
        let store = writing(nil)
        store.routerStatus.codeRoot = dir
        defer { store.persists = false; try? FileManager.default.removeItem(at: dir) }
        let model = RouterModel()
        #expect(model.claudeCodeMissing == nil && model.canSend(store))
        await model.checkClaudeCode(store)
        #expect(model.claudeCodeMissing == true && !model.canSend(store))
        model.draft = "hello"
        model.send(store: store)
        #expect(model.draft == "hello")
        // The app's copy appears: looking again finds it.
        let bin = dir.appendingPathComponent("2.1.293/abc/claude.app/Contents/MacOS")
        try? FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appendingPathComponent("claude").path, contents: Data(),
                                       attributes: [.posixPermissions: 0o755])
        await model.checkClaudeCode(store)
        #expect(model.claudeCodeMissing == false && model.canSend(store))
    }

    // MARK: Reply and @

    @Test func returnOnAPickedCardRepliesToItAndTheReplyGoesWithTheMessage() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let card = model.cards(store).filter(\.isOpen)[1]
        model.select(card.id, store: store)
        #expect(keys.key(key(kVK_Return, "\r"), responder: nil))
        #expect(model.replyTo == card.id)
        model.tokens = ["/Users/me/code/lookout"]
        model.draft = "go ahead in \(MentionText.markString)"
        model.send(store: store)
        let line = store.router.decisions.last
        #expect(line?.links.cards == [card.id])
        #expect(line?.triggerText.hasPrefix("go ahead in @") == true && line?.triggerText.contains(MentionText.markString) == false)
        // The chips go with the message.
        #expect(model.replyTo == nil && model.projects.isEmpty && model.draft.isEmpty)
    }

    @Test func escClearsTheSuggestionsThenTheReplyThenCloses() {
        let store = demo()
        let model = RouterModel()
        var closed = false
        let keys = RouterKeys(store: store, model: model) { closed = true }
        model.composerFocused = true
        model.replyTo = store.openRouterCards[0].id
        let editor = editor(model, "tell @mi")
        #expect(!model.suggestions(store).isEmpty)
        #expect(keys.key(key(kVK_Escape), responder: editor))
        #expect(model.suggestions(store).isEmpty && model.replyTo != nil && !closed)
        #expect(keys.key(key(kVK_Escape), responder: editor))
        #expect(model.replyTo == nil && !closed)
        #expect(keys.key(key(kVK_Escape), responder: editor))
        #expect(closed)
    }

    @Test func atSuggestsProjectsAndReturnOrTabPicksOne() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        model.composerFocused = true
        _ = editor(model, "check @")
        let all = model.suggestions(store).map(\.name)
        #expect(all.count >= 3)
        var view = editor(model, "check @lc")
        #expect(model.suggestions(store).first?.name == "lcu")
        #expect(keys.key(key(kVK_DownArrow), responder: view))
        let second = model.suggestions(store)[1].folder
        #expect(keys.key(key(kVK_Tab, "\t"), responder: view))
        #expect(model.projects == [second] && model.tokens == [second])
        #expect(model.draft == "check \(MentionText.markString) " && model.caretRequest == 8)
        // Picked projects aren't suggested again; Return picks too.
        view = editor(model, "check \(MentionText.markString) and @")
        #expect(!model.suggestions(store).map(\.folder).contains(second))
        #expect(keys.key(key(kVK_Return, "\r"), responder: view))
        #expect(model.projects.count == 2 && model.tokens[0] == second && model.draft.filter { $0 == MentionText.mark }.count == 2)
        // An @ inside a word (an email) is not a tag.
        #expect(RouterModel.mentionQuery(in: "me@lookout") == nil)
        #expect(RouterModel.mentionQuery(in: "@look out") == nil)
        #expect(RouterModel.mentionQuery(in: "hey @look") == "look")
    }

    @Test func theSuggestionsFollowTheCaretNotTheEndOfTheText() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        model.composerFocused = true
        // Mid-message: the @ word the caret is in is the one suggested, and picking it keeps the rest of the text.
        let view = editor(model, "ask @lc about the tests", caret: 7)
        #expect(model.suggestions(store).first?.name == "lcu")
        #expect(keys.key(key(kVK_Return, "\r"), responder: view))
        #expect(model.draft == "ask \(MentionText.markString) about the tests" && model.caretRequest == 6)
        #expect(model.projects.count == 1)
        // The caret moved off a trailing @ word: no suggestions, and ↑↓ and Return are the composer's again.
        let away = editor(model, "tell @mi", caret: 2)
        #expect(model.suggestions(store).isEmpty)
        #expect(!keys.key(key(kVK_DownArrow), responder: away))
        let before = store.router.decisions.count
        #expect(keys.key(key(kVK_Return, "\r"), responder: away))
        #expect(store.router.decisions.count > before)
    }

    /// The composer in a window: typing through its own text view, then moving the caret, drives the suggestions.
    @Test(.hostsWindows) func aMountedComposerFollowsTheCaret() async throws {
        let store = demo()
        let model = RouterModel()
        let hosting = NSHostingView(rootView: RouterCodeView(store: store, model: model, checksClaudeCode: false)
            .frame(width: 1100, height: 720))
        let window = AwayWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 720), styleMask: .titled, backing: .buffered,
                                defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        // Other tests' windows may hold the keyboard: the composer's own text view is given it here, once it is drawn.
        func fields(_ view: NSView) -> [MentionTextView] { (view as? MentionTextView).map { [$0] } ?? [] + view.subviews.flatMap(fields) }
        await waitUntil { !fields(hosting).isEmpty }
        // The composer asks for the keyboard as it appears, two main-queue hops later: that is done with before the test
        // types and moves the caret, so it can't land in the middle.
        for _ in 0..<3 {
            await drainMainQueue()
            hosting.layoutSubtreeIfNeeded()
        }
        let composer = fields(hosting).first
        await waitUntil {
            if window.firstResponder !== composer, let composer { window.makeFirstResponder(composer) }
            return window.firstResponder === composer
        }
        let field = try #require(window.firstResponder as? NSTextView)
        /// What the view does happens on its next update, which other tests' work on the main actor can hold back.
        func settle(_ done: () -> Bool) async throws {
            await waitUntil(done)
        }
        field.insertText("ask @mi about it", replacementRange: NSRange(location: 0, length: 0))
        try await settle { model.draft == "ask @mi about it" }
        #expect(model.draft == "ask @mi about it" && model.suggestions(store).isEmpty)
        field.setSelectedRange(NSRange(location: 7, length: 0))
        try await settle { !model.suggestions(store).isEmpty }
        #expect(model.suggestions(store).first?.name == "microsandbox")
        // The composer losing the keyboard (here, as SwiftUI may take it from a field in a window that isn't key) ends its
        // editing, which moves the editor's selection: that is not the composer's caret moving.
        window.makeFirstResponder(nil)
        await drainMainQueue()
        await waitUntilSteady(turns: 10) { model.caret }
        #expect(model.caret == 7 && model.suggestions(store).first?.name == "microsandbox")
        // Other text views moving their caret (another window's, one elsewhere in this window, even holding the same text)
        // leave the composer's alone.
        let other = AwayWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 100), styleMask: .titled, backing: .buffered,
                               defer: false)
        other.isReleasedWhenClosed = false
        defer { other.close() }
        let elsewhere = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        other.contentView = elsewhere
        let beside = NSTextView(frame: CGRect(x: 0, y: 0, width: 100, height: 40))
        hosting.addSubview(beside)
        defer { beside.removeFromSuperview() }
        for view in [elsewhere, beside] {
            view.string = "ask @mi about it"
            view.setSelectedRange(NSRange(location: 1, length: 0))
        }
        // Whatever the view does with those notifications it does on its next updates: once the caret has read the same over
        // several turns of the main actor, it has had them.
        await drainMainQueue()
        await waitUntilSteady(turns: 10) { model.caret }
        #expect(model.caret == 7 && model.suggestions(store).first?.name == "microsandbox")
        // The composer's own caret moving away still counts (given the keyboard again if the others took it).
        await waitUntil {
            if window.firstResponder !== field, let composer { window.makeFirstResponder(composer) }
            return window.firstResponder === field
        }
        let own = try #require(window.firstResponder as? NSTextView)
        own.setSelectedRange(NSRange(location: 1, length: 0))
        try await settle { model.suggestions(store).isEmpty }
        #expect(model.suggestions(store).isEmpty)
    }

    @Test func aClickedFinishedCardIsOpenedThenStaysPicked() {
        let store = demo()
        let model = RouterModel()
        let done = store.openRouterCards.first { $0.kind == .done }!
        model.open(done.id, store: store)
        model.reconcile(store: store)
        // Opening addressed it (down to Earlier); the pick stayed on it.
        #expect(store.router.cards.first { $0.id == done.id }?.isOpen == false)
        #expect(model.selection == done.id)
    }

    @Test func returnRepliesOnlyToAListedCard() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        // Picked, then gone from the list (the file dropped it): Return replies to the listed card next to it.
        let listed = model.cards(store).map(\.id)
        model.selection = listed[1]
        model.reconcile(store: store)
        store.router.cards.removeAll { $0.id == listed[1] }
        #expect(keys.key(key(kVK_Return, "\r"), responder: nil))
        #expect(model.replyTo == listed[2])
        // Nothing listed at all: Return only focuses the composer.
        store.router.cards.removeAll()
        #expect(model.cards(store).isEmpty)
        model.replyTo = nil
        let request = model.focusRequest
        #expect(keys.key(key(kVK_Return, "\r"), responder: nil))
        #expect(model.replyTo == nil && model.focusRequest != request)
    }

    @Test func backspaceAtTheStartTakesTheReplyOff() {
        let store = demo()
        let model = RouterModel()
        let keys = RouterKeys(store: store, model: model) {}
        let editor = NSTextView()
        model.composerFocused = true
        model.replyTo = store.openRouterCards[0].id
        #expect(keys.key(key(kVK_Delete), responder: editor))
        #expect(model.replyTo == nil)
        // Nothing left: the key is the field's. Not at the start: the field's.
        #expect(!keys.key(key(kVK_Delete), responder: editor))
        model.replyTo = store.openRouterCards[0].id
        editor.string = "abc"
        editor.setSelectedRange(NSRange(location: 3, length: 0))
        #expect(!keys.key(key(kVK_Delete), responder: editor) && model.replyTo != nil)
    }

    @Test func aFailedRemovalStaysInSightWithTheRouterOffAndCanBeTriedAgain() async throws {
        let dir = TempDir(), cli = FakeClaudeCLI()
        cli.folderVersion = ClaudePlugin.version(app: "1.0.0")
        let s = Store()
        s.persists = false
        s.routerPaths = RouterPaths(support: dir.path("support"), claudeDir: dir.path("claude"))
        s.routerExecutable = "/Applications/Lookout.app/Contents/MacOS/Lookout"
        s.routerPluginRunner = cli.runner
        s.routerClaudeBinary = { "/fake/claude" }
        s.routerAppVersion = "1.0.0"
        s.agents.enabled = true
        s.setRouterEnabled(true)
        await s.routerHookWork?.value
        cli.failing = "plugin uninstall"
        s.setRouterEnabled(false)
        await s.routerHookWork?.value
        let error = try #require(s.routerRemovalError)
        #expect(error.contains("boom"))
        // Settings shows it, and the button that tries again, though the Router's own lines are hidden while it is off.
        let tree = try await AccessibilityTree.render(SettingsView(store: s, hub: HubState()).frame(width: 440, height: 2400),
                                                      size: CGSize(width: 440, height: 2400))
        #expect(tree.all.contains { $0.role == "AXButton" && $0.label == "Try again" })
        cli.failing = nil
        s.retryRouterRemoval()
        await s.routerHookWork?.value
        #expect(s.routerRemovalError == nil && s.routerPluginStatus == .notInstalled && cli.plugins.isEmpty)
    }

    @Test func fuzzyMentionsRankPrefixesFirst() {
        let ranked = RouterMentions.rank([("/a", "microsandbox"), ("/b", "lcu"), ("/c", "lcu-research"), ("/d", "lookout")],
                                         query: "lc", limit: 6).map(\.name)
        #expect(ranked == ["lcu", "lcu-research"])
        #expect(RouterMentions.rank([("/a", "microsandbox")], query: "msb", limit: 6).map(\.name) == ["microsandbox"])
        #expect(RouterMentions.rank([("/a", "microsandbox")], query: "zz", limit: 6).isEmpty)
    }

    // MARK: Forms

    @Test func aFormIsAnsweredOnceEveryQuestionIs() async {
        let store = demo()
        let card = store.openRouterCards.first { $0.kind == .question }!
        let form = store.pendingForm(for: card)!
        let model = RouterModel()
        #expect(model.answers(form) == nil)
        let q = form.questions[0]
        model.pick("Ask first", in: q, of: form)
        #expect(model.answers(form) == [q.question: "Ask first"])
        // Your own words replace the pick of a one-choice question.
        model.setOther("Ask once a week", in: q, of: form)
        #expect(model.answers(form) == [q.question: "Ask once a week"])
        model.sendAnswer(form, card: card.id, store: store)
        // Written off the main thread: "Sent" shows once it is; meanwhile nothing can be changed or sent again.
        #expect(model.sending.contains(form.id) && !model.sent.contains(form.id) && model.locked(form))
        model.pick("Install silently", in: q, of: form)
        model.setOther("changed my mind", in: q, of: form)
        #expect(model.answers(form) == [q.question: "Ask once a week"])
        await model.lastWrite?.value
        #expect(model.sent.contains(form.id) && model.formErrors[form.id] == nil && model.sending.isEmpty)
        // Once sent: what was answered (read-only), and still nothing to change.
        #expect(model.delivered[form.id] == [q.question: "Ask once a week"] && model.locked(form))
        model.pick("Install silently", in: q, of: form)
        #expect(model.answers(form) == [q.question: "Ask once a week"])
    }

    /// A store that writes for real, its forms folder in `dir` (nil: never started, as with the Router off).
    private func writing(_ dir: URL?) -> Store {
        let store = demo()
        store.stateFile = FileManager.default.temporaryDirectory.appendingPathComponent("router-ui-\(UUID().uuidString).json")
        store.persists = true
        if let dir { store.formBridge.start(dir: dir) { _ in } }
        return store
    }

    @Test func anAnswerIsWrittenToTheFormsFolder() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("router-forms-\(UUID().uuidString)")
        let store = writing(dir)
        defer { store.formBridge.stop(); store.persists = false; try? FileManager.default.removeItem(at: dir) }
        let card = store.openRouterCards.first { $0.kind == .question }!
        let form = store.pendingForm(for: card)!
        let model = RouterModel()
        model.pick("Ask first", in: form.questions[0], of: form)
        model.sendAnswer(form, card: card.id, store: store)
        await model.lastWrite?.value
        #expect(model.sent.contains(form.id))
        #expect(FileManager.default.fileExists(atPath: FormBridge.answerURL(form.id, in: dir).path))
    }

    @Test func answeringWhileTheRouterIsSwitchedOffWritesNothing() async {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("router-forms-\(UUID().uuidString)")
        let store = writing(dir)
        defer { store.formBridge.stop(); store.persists = false; try? FileManager.default.removeItem(at: dir) }
        let card = store.openRouterCards.first { $0.kind == .question }!
        let form = store.pendingForm(for: card)!
        let model = RouterModel()
        model.pick("Ask first", in: form.questions[0], of: form)
        model.sendAnswer(form, card: card.id, store: store)
        // Switched off before the write happens.
        store.router.enabled = false
        await model.lastWrite?.value
        #expect(!model.sent.contains(form.id) && !model.locked(form))
        #expect(model.formErrors[form.id] == FormWriter.Cancelled().errorDescription)
        #expect(!FileManager.default.fileExists(atPath: FormBridge.answerURL(form.id, in: dir).path))
    }

    @Test func aRefusedAnswerShowsWhyAndIsNotSent() async {
        // A real write (not a demo's), with no forms folder to write to (the Router off): an error, nothing written.
        let store = writing(nil)
        defer { store.persists = false; try? FileManager.default.removeItem(at: store.stateFile!) }
        let card = store.openRouterCards.first { $0.kind == .question }!
        let form = store.pendingForm(for: card)!
        let model = RouterModel()
        model.pick("Ask first", in: form.questions[0], of: form)
        model.sendAnswer(form, card: card.id, store: store)
        await model.lastWrite?.value
        #expect(!model.sent.contains(form.id) && model.formErrors[form.id] != nil && model.sending.isEmpty)
    }

    // MARK: Plans

    @Test func aPlanIsApprovedOrSentBackFromItsCard() async throws {
        let store = demo()
        let card = try #require(store.openRouterCards.first { $0.kind == .plan })
        let form = try #require(store.pendingForm(for: card))
        #expect(form.isPlan)
        let model = RouterModel()
        model.setPlanNote("Use the existing CI runner", of: form)
        model.decidePlan(form, approve: false, card: card.id, store: store)
        #expect(model.sending.contains(form.id) && model.locked(form))
        // Nothing changes while it is written, nor once it is.
        model.setPlanNote("changed my mind", of: form)
        model.decidePlan(form, approve: true, card: card.id, store: store)
        await model.lastWrite?.value
        #expect(model.sent.contains(form.id) && model.formErrors[form.id] == nil && model.sending.isEmpty)
        #expect(model.planDecided[form.id] == .init(approve: false, feedback: "Use the existing CI runner"))
        #expect(model.planNote(form) == "Use the existing CI runner")
    }

    @Test func anApprovalIsWrittenToTheFormsFolder() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("router-forms-\(UUID().uuidString)")
        let store = writing(dir)
        defer { store.formBridge.stop(); store.persists = false; try? FileManager.default.removeItem(at: dir) }
        let card = try #require(store.openRouterCards.first { $0.kind == .plan })
        let form = try #require(store.pendingForm(for: card))
        let model = RouterModel()
        // A note typed, then Approve: an approval carries no note.
        model.setPlanNote("unused", of: form)
        model.decidePlan(form, approve: true, card: card.id, store: store)
        await model.lastWrite?.value
        #expect(model.planDecided[form.id]?.approve == true)
        let written = try JSONSerialization.jsonObject(with: Data(contentsOf: FormBridge.answerURL(form.id, in: dir))) as? NSDictionary
        #expect(written == ["plan": ["approve": true, "feedback": ""]] as NSDictionary)
    }

    @Test func severalChoicesAreJoinedAsTheFormTakesThem() {
        let q = PendingForm.Question(question: "Which?", header: "", multiSelect: true,
                                     options: [.init(label: "A", description: ""), .init(label: "B", description: "")])
        let form = PendingForm(id: "k", cliSessionID: "c", transcriptPath: "", questions: [q], createdAt: now, pid: 0)
        let model = RouterModel()
        model.pick("A", in: q, of: form)
        model.pick("B", in: q, of: form)
        #expect(model.answers(form) == ["Which?": "A, B"])
        model.pick("A", in: q, of: form)
        #expect(model.answers(form) == ["Which?": "B"])
    }

    // MARK: What works

    @Test func aBrokenReadOfClaudesFilesIsSaidOnTheBar() async throws {
        func says(_ link: ClaudeLink, _ configure: @escaping (HubState) -> Void) async throws -> Bool {
            let tree = try await AccessibilityTree.render(edge: .top, scenario: .router, configure: { store, hub in
                store.claudeLink = link
                configure(hub)
            })
            return tree.all.contains { ($0.label + $0.value).contains("Claude's sessions") }
        }
        let state = { (hub: HubState) in hub.section = .router }
        #expect(try await says(.missing, state))
        #expect(try await !says(.ok, state))
    }

    @Test func theBarNamesTheRouterAtRestAndPeeking() async throws {
        for edge in [DockEdge.right, .top] {
            for peeking in [false, true] {
                let tree = try await AccessibilityTree.render(edge: edge, scenario: .router,
                                                              configure: { _, hub in hub.section = peeking ? .router : nil })
                #expect(tree.all.contains { $0.label == "Router" }, "\(edge) \(peeking)")
            }
        }
    }

    @Test func theWorkingListIsWhatRunsLongestFirstAndOpensIt() {
        let store = demo(.router)
        var opened: [String] = []
        store.interceptOpen = { opened.append($0) }
        let rows = store.routerWorkingRows
        // The turn that works, and the finished one still running its subagents and command (oldest of them first).
        #expect(rows.map(\.id) == ["local_demo-ci", "local_demo-lookout"])
        #expect(!rows[0].session.running)
        #expect(!rows.contains { $0.waitsForYou })
        store.openAgent(rows[1].id)
        #expect(opened.first?.contains("Agent completion notifications") == true)
    }

    // MARK: Banners

    @Test func bannersAreForWhatNeedsYouAndNotWhileTheWindowHasTheKeys() {
        let store = demo()
        store.settings.notifications = true
        var posted: [String] = []
        store.notifier.onPost = { posted.append($0.identifier) }
        let cards = store.openRouterCards
        RouterBanners.post(cards, store: store, windowIsKey: true)
        #expect(posted.isEmpty)
        RouterBanners.post(cards, store: store, windowIsKey: false)
        #expect(posted.sorted() == cards.filter { RouterAttention.bannerNow($0, away: false) }.map { RouterBanners.prefix + $0.id }.sorted())
        #expect(!posted.isEmpty)
        posted = []
        store.settings.snoozeUntil = Date().addingTimeInterval(600)
        RouterBanners.post(cards, store: store, windowIsKey: false)
        #expect(posted.isEmpty)
    }

    @Test func aBannersClickOpensTheWindowOnItsCard() {
        let store = demo()
        var opened: String?
        var other: String?
        store.notifier.onOpen = { id, _ in other = id }
        RouterBanners.attach(store: store, windowIsKey: { false }) { opened = $0 }
        store.notifier.onOpen?(RouterBanners.prefix + "card#1", nil)
        store.notifier.onOpen?("item", nil)
        #expect(opened == "card#1" && other == "item")
    }

    // MARK: Shortcut

    @Test func theRoutersDefaultKeyIsFreeAndEachGlobalKeyHasItsOwnID() {
        let others = ShortcutAction.allCases.filter { $0 != .router }.map(\.defaultShortcut)
        #expect(!others.contains(ShortcutAction.router.defaultShortcut))
        // Each global key is registered under an id of its own.
        let globals = ShortcutAction.allCases.filter(\.isGlobal)
        #expect(Set(globals.map(\.hotKeyID)).count == globals.count)
    }

    // MARK: The page

    @Test func thePageGroupsAndOrdersItsThreeZones() {
        let store = demo()
        let page = store.routerPage
        // Needs you: blockers first (a question or plan before a stuck turn, newest first among equals), then finished
        // turns; only open cards.
        #expect(!page.needs.isEmpty && page.needs.allSatisfy(\.isOpen))
        let kinds = page.needs.map { $0.kind == .done }
        #expect(kinds == kinds.sorted { !$0 && $1 })
        let blockers = page.needs.filter { $0.kind != .done }
        #expect(blockers.map(\.kind) == [.question, .plan, .stuck])
        // Working: the sessions running on their own, none of them stopped on you.
        #expect(Set(page.working.map(\.id)) == Set(store.routerWorkingRows.map(\.id)))
        #expect(!page.working.isEmpty && page.working.allSatisfy { !$0.waitsForYou })
        // History: oldest first, addressed cards, runs and summaries together, no open card.
        #expect(page.history.map(\.date) == page.history.map(\.date).sorted())
        let cardLines = page.history.compactMap { entry -> RouterCard? in if case .card(let c) = entry { c } else { nil } }
        #expect(!cardLines.isEmpty && cardLines.allSatisfy { !$0.isOpen })
        #expect(page.history.count == store.router.decisions.count + store.router.summaries.count + store.router.cards.filter { !$0.isOpen }.count)
        // The keys' order is the page's: the keys walk Needs you the way it is shown.
        let (needs, done, _) = RouterModel().sections(store)
        #expect(page.needs.map(\.id) == (needs + done).map(\.id))
    }

    @Test func theHistoryIsWorkedOutOnlyWhenWhatItIsMadeOfChanges() {
        let store = demo()
        #expect(store.routerHistory == RouterPage.history(cards: store.router.cards, decisions: store.router.decisions,
                                                         summaries: store.router.summaries))
        #expect(Set(store.routerHistory.map(\.id)).count == store.routerHistory.count)
        var notified = false
        withObservationTracking { _ = store.routerHistory } onChange: { notified = true }
        // A session's stamp, a wait, an open card's text: the history (and the views drawing it) are left alone.
        store.router.seen["local_demo-lookout"] = "a new stamp"
        store.router.waits["local_demo-lookout"] = 42
        let open = store.router.cards.firstIndex(where: \.isOpen)!
        store.router.cards[open].text = "Edited"
        #expect(!notified)
        store.logDecision(RouterDecision(at: Date(), trigger: .you("one more"), outcome: .done))
        #expect(notified && store.routerHistory.last?.id == store.router.decisions.last?.id.uuidString)
    }

    @Test func aDuplicatedIdIsOneLineOfTheHistory() {
        let decision = RouterDecision(at: Date(), trigger: .you("twice"), outcome: .done)
        let history = RouterPage.history(cards: [], decisions: [decision, decision], summaries: [])
        #expect(history.map(\.id) == [decision.id.uuidString])
    }

    @Test func anAddressedCardGoesToTheHistoryAndReopensIntoNeedsYou() {
        let store = demo()
        let model = RouterModel()
        let card = store.routerPage.needs[0]
        let before = store.routerPage
        model.address(card.id, store: store)
        let after = store.routerPage
        #expect(!after.needs.contains { $0.id == card.id })
        #expect(after.history.contains { $0.id == card.id })
        // The card, and the decision it logged.
        #expect(after.history.count == before.history.count + 2)
        #expect(store.router.decisions.last?.trigger == .you("Marked handled"))
        // Its line sits at the time it was addressed, after the older entries.
        #expect(after.history.last { $0.id == card.id }?.date == store.router.cards.first { $0.id == card.id }?.addressedAt)
        model.reopen(card.id, store: store)
        let back = store.routerPage
        #expect(back.needs.contains { $0.id == card.id })
        #expect(!back.history.contains { $0.id == card.id })
        // Reopening picks it and opens nothing in the history.
        #expect(model.selection == card.id && !model.expanded.contains(card.id))
    }

    @Test func aSupersededCardIsNotReopened() {
        let store = demo()
        let model = RouterModel()
        let card = store.router.cards.first { $0.addressedBy == .answered }!
        store.router.cards[store.router.cards.firstIndex { $0.id == card.id }!].addressedBy = .superseded
        model.reopen(card.id, store: store)
        #expect(store.router.cards.first { $0.id == card.id }?.isOpen == false)
    }

    @Test func aWorkingSessionThatNeedsYouMovesToNeedsYou() {
        let store = demo()
        let id = "local_demo-lookout"
        var page = store.routerPage
        #expect(page.working.contains { $0.id == id } && !page.needs.contains { $0.sessionID == id })
        // It stops on a question: the feed makes its card, and it leaves Working.
        let at = Date()
        store.claudeActivity[id] = ClaudeActivity(text: "Which branch?", since: at, waitsForYou: true, tool: "AskUserQuestion",
                                                 toolUseID: "toolu_x")
        store.router.cards.append(RouterCard(id: "\(id)#w\(RouterFeed.Stamp.ms(at))", sessionID: id, kind: .question,
                                             title: "Agent completion notifications", folder: nil, text: "Which branch?", createdAt: at))
        page = store.routerPage
        #expect(!page.working.contains { $0.id == id })
        #expect(page.needs.first?.sessionID == id, "the newest blocker is first")
        // A turn that ends leaves Working too.
        let other = "local_demo-ci"
        #expect(store.routerPage.working.contains { $0.id == other })
        store.claudeTasks[other] = []
        #expect(!store.routerPage.working.contains { $0.id == other })
    }

    @Test func selectingAnAddressedCardOpensItInTheHistoryAndAsksThePageToScroll() {
        let store = demo()
        let model = RouterModel()
        let card = store.router.cards.first { !$0.isOpen }!
        model.select(card.id, store: store)
        #expect(model.expanded.contains(card.id) && model.revealRequest?.id == card.id && model.highlighted == card.id)
        model.select(nil, store: store)
        #expect(model.revealRequest?.id == RouterModel.endID)
    }

    @Test func oneNeedsYouCardIsOpenAtATimeTheAskedForOneElseTheNewest() {
        let store = demo()
        let page = store.routerPage
        #expect(page.openNeed(preferred: nil) == page.needs.first?.id)
        let other = page.needs[2].id
        #expect(page.openNeed(preferred: other) == other)
        #expect(page.openNeed(preferred: "gone") == page.needs.first?.id, "a card that left falls back to the newest")
        // Picking a card in the list (or with the arrows) opens it on the page.
        let model = RouterModel()
        model.select(other, store: store)
        #expect(model.expandedNeed == other)
    }

    @Test func clickingAnOpenCardShowsItInFullAndRepliesToIt() {
        let store = demo()
        let model = RouterModel()
        let card = store.routerPage.needs[2]
        let request = model.focusRequest
        model.tap(card.id, store: store)
        #expect(model.expandedNeed == card.id && model.replyTo == card.id && model.selection == card.id)
        #expect(model.focusRequest != request)
        // Clicked again it stays shown in full.
        model.tap(card.id, store: store)
        #expect(store.routerPage.openNeed(preferred: model.expandedNeed) == card.id && model.replyTo == card.id)
    }

    @Test func clickingAResolvedCardShowsItInFullRepliesToItAndTheReplyGoesToItsSession() {
        let store = demo()
        let model = RouterModel()
        let card = store.router.cards.first { !$0.isOpen }!
        model.tap(card.id, store: store)
        #expect(model.expanded.contains(card.id) && model.replyTo == card.id)
        // It was clicked where it is: the history isn't asked to scroll anywhere.
        #expect(model.revealRequest == nil)
        // Clicked again it folds back; the reply stays armed.
        model.tap(card.id, store: store)
        #expect(!model.expanded.contains(card.id) && model.replyTo == card.id)
        #expect(RouterDispatcher.plan(text: "one more thing", context: RouterContext(replyTo: card.id), store: store)
            == .reply(session: card.sessionID, card: card.id))
        model.draft = "one more thing"
        model.send(store: store)
        #expect(store.router.decisions.last?.links.cards == [card.id] && model.replyTo == nil)
    }
}
