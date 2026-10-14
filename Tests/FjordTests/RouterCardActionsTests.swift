import Foundation
import Testing
@testable import Fjord

/// The Router's actions on its own page: archive and reopen a card, mute a project, stop a running session's turn. Each acts
/// only on what the user's message names, and leaves its line in the history.
@MainActor
struct RouterCardActionsTests {
    private let now = Date()

    private func card(_ id: String, kind: RouterCard.Kind = .done, title: String, folder: String = "/code/lookout", open: Bool = true) -> RouterCard {
        let session = String(id.split(separator: "#").first ?? "")
        var c = RouterCard(id: id, sessionID: session, kind: kind, title: title, folder: folder, text: "Text of \(session)", createdAt: now,
                           addressedAt: open ? nil : now.addingTimeInterval(-60), addressedBy: open ? nil : .you)
        c.triage = RouterTriage(state: kind == .asks ? .asks : .done)
        return c
    }

    private func session(_ id: String, _ title: String, folder: String = "/code/lookout", running: Bool = false) -> ClaudeSession {
        ClaudeSession(id: id, title: title, folder: folder, completedTurns: 1, lastActivity: now, running: running, cliID: "cli-\(id)")
    }

    private func world(_ text: String, cards: [RouterCard] = [], sessions: [ClaudeSession] = []) -> (Store, RouterTools) {
        let store = InboxFixture.store([])
        store.router.enabled = true
        store.agents.enabled = true
        store.claudeSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        store.router.cards = cards
        let tools = RouterTools(store: store)
        tools.beginTurn(text)
        return (store, tools)
    }

    private func open(_ store: Store, _ id: String) -> Bool? { store.router.cards.first { $0.id == id }?.isOpen }

    // MARK: Naming

    @Test func aMessageNamesATitleByAWordOfIt() {
        #expect(FjordGate.namesTitle("archive the login card", title: "Fix login redirect"))
        #expect(FjordGate.namesTitle("I'll do the theme one myself", title: "Dark theme colours"))
        #expect(FjordGate.namesTitle("stop the CI session", title: "Fix CI"))
        // Plurals count; the little words and the commands don't name anything.
        #expect(FjordGate.namesTitle("archive the logs", title: "Old log cleanup"))
        #expect(!FjordGate.namesTitle("archive the card", title: "Fix the card session"))
        #expect(!FjordGate.namesTitle("I'll handle it myself", title: "Fix login redirect"))
        #expect(!FjordGate.namesTitle("archive everything", title: "Archive"))
    }

    // MARK: archive_cards

    @Test func archivingTakesAnyOpenCardTheMessageNamesAndLeavesAHistoryLine() async {
        let (store, t) = world("I'll handle the login question myself", cards: [
            card("a#1", kind: .question, title: "Fix login redirect"), card("b#1", title: "Dark theme colours")],
            sessions: [session("a", "Fix login redirect"), session("b", "Dark theme colours")])
        let r = await t.call("archive_cards", ["cards": ["a#1"]])
        #expect(r?.isError == false && r?.text.contains("Archived") == true)
        #expect(open(store, "a#1") == false && store.router.cards.first { $0.id == "a#1" }?.addressedBy == .you)
        let line = store.router.decisions.last
        #expect(line?.trigger == .you("Archived") && line?.links.cards == ["a#1"])
        #expect(open(store, "b#1") == true)
    }

    @Test func archivingRefusesACardTheMessageDoesntName() async {
        let (store, t) = world("I'll handle the login question myself", cards: [
            card("a#1", title: "Fix login redirect"), card("b#1", title: "Dark theme colours")])
        let other = await t.call("archive_cards", ["cards": ["b#1"]])
        #expect(other?.isError == true && other?.text.contains("doesn't name") == true)
        // Reached by words too, or in a batch: only the named one goes.
        let both = await t.call("archive_cards", ["cards": ["theme", "a#1"]])
        #expect(both?.isError == false && both?.text.contains("Not archived") == true)
        #expect(open(store, "a#1") == false && open(store, "b#1") == true)
        #expect(store.router.decisions.count == 1)
    }

    @Test func archivingRefusesAmbiguousWordsAndMissingCards() async {
        let (store, t) = world("archive the login card", cards: [card("a#1", title: "Login redirect"), card("b#1", title: "Login docs")])
        let ambiguous = await t.call("archive_cards", ["cards": ["login"]])
        #expect(ambiguous?.isError == true && ambiguous?.text.contains("more than one") == true)
        #expect(await t.call("archive_cards", ["cards": ["zzz"]])?.isError == true)
        #expect(await t.call("archive_cards", ["cards": [String]()])?.isError == true)
        #expect(store.router.cards.allSatisfy(\.isOpen) && store.router.decisions.isEmpty)
    }

    @Test func archivingNeedsAUserTurn() async {
        let (store, t) = world("archive the login card", cards: [card("a#1", title: "Login redirect")])
        t.endTurn()
        #expect(await t.call("archive_cards", ["cards": ["a#1"]])?.isError == true)
        #expect(open(store, "a#1") == true)
    }

    @Test func markingSeenLeavesTheSameHistoryLine() async {
        let (store, t) = world("seen the docs", cards: [card("a#1", title: "Docs pass")])
        #expect(await t.call("mark_seen", ["cards": ["a#1"]])?.isError == false)
        #expect(open(store, "a#1") == false)
        #expect(store.router.decisions.last?.trigger == .you("Archived") && store.router.decisions.last?.links.cards == ["a#1"])
    }

    // MARK: reopen_card

    @Test func reopeningBringsBackANamedArchivedCard() async {
        let (store, t) = world("reopen the docs card", cards: [
            card("a#1", title: "Docs pass", open: false), card("b#1", title: "Login redirect", open: false)],
            sessions: [session("a", "Docs pass"), session("b", "Login redirect")])
        let r = await t.call("reopen_card", ["card": "docs"])
        #expect(r?.isError == false && open(store, "a#1") == true && open(store, "b#1") == false)
        // Another archived card isn't the one named.
        let wrong = await t.call("reopen_card", ["card": "b#1"])
        #expect(wrong?.isError == true && wrong?.text.contains("doesn't name") == true && open(store, "b#1") == false)
        // An open card isn't an archived one.
        #expect(await t.call("reopen_card", ["card": "a#1"])?.isError == true)
    }

    @Test func aCardASessionsNewerOneReplacedCantBeReopened() async {
        var old = card("a#1", title: "Docs pass", open: false)
        old.addressedBy = .superseded
        let (store, t) = world("reopen the docs card", cards: [old], sessions: [session("a", "Docs pass")])
        #expect(await t.call("reopen_card", ["card": "docs"])?.isError == true && open(store, "a#1") == false)
    }

    @Test func theBoardListsTheLastArchivedCardsAndTheMutedProjects() async throws {
        var cards = (0..<12).map { card("s\($0)#1", title: "Card \($0)", open: false) }
        for i in cards.indices { cards[i].addressedAt = now.addingTimeInterval(Double(-60 * (i + 1))) }
        let (store, t) = world("hi", cards: cards + [card("o#1", title: "Open one")],
                               sessions: (0..<12).map { session("s\($0)", "Card \($0)") } + [session("o", "Open one")])
        store.setFolderMuted("/code/lookout", true)
        let board = try #require(JSONSerialization.jsonObject(with: Data(await t.board(store).utf8)) as? [String: Any])
        let archived = try #require(board["archivedCards"] as? [[String: Any]])
        #expect(archived.count == 10 && archived.first?["card"] as? String == "s0#1" && archived.first?["archived"] != nil)
        #expect((board["mutedProjects"] as? [String])?.joined().contains("lookout") == true)
    }

    // MARK: mute_project

    @Test func mutingNeedsTheProjectNamedAndAMuteWord() async {
        let sessions = [session("a", "One", folder: "/code/microsandbox"), session("b", "Two", folder: "/code/lookout")]
        let (store, t) = world("mute microsandbox", sessions: sessions)
        #expect(await t.call("mute_project", ["project": "microsandbox", "muted": true])?.isError == false)
        #expect(store.isFolderMuted("/code/microsandbox") && !store.isFolderMuted("/code/lookout"))
        // A project the message doesn't name.
        let other = await t.call("mute_project", ["project": "lookout", "muted": true])
        #expect(other?.isError == true && other?.text.contains("doesn't name") == true && !store.isFolderMuted("/code/lookout"))
        // Nothing to change: said so.
        #expect(await t.call("mute_project", ["project": "microsandbox", "muted": true])?.text.contains("already") == true)
        #expect(await t.call("mute_project", ["project": "nothing", "muted": true])?.isError == true)
        // And back.
        t.beginTurn("unmute microsandbox")
        #expect(await t.call("mute_project", ["project": "microsandbox", "muted": false])?.isError == false)
        #expect(!store.isFolderMuted("/code/microsandbox"))
        t.beginTurn("tell microsandbox to rest")
        #expect(await t.call("mute_project", ["project": "microsandbox", "muted": true])?.isError == true)
        #expect(!store.isFolderMuted("/code/microsandbox"))
    }

    @Test func mutingAnAmbiguousProjectListsTheChoices() async {
        let sessions = [session("a", "One", folder: "/work/app"), session("b", "Two", folder: "/code/app")]
        let (store, t) = world("mute app", sessions: sessions)
        let r = await t.call("mute_project", ["project": "app", "muted": true])
        #expect(r?.isError == true && r?.text.contains("more than one project") == true)
        #expect(store.agents.mutedFolders.isEmpty)
    }

    // MARK: stop_session

    private func delivery(_ store: Store, session id: String, abortable: Bool = true) -> UUID {
        var entry = RouterDecision(at: now, trigger: .you("run the tests"), outcome: .done)
        entry.delivered = .init(session: id, cli: "cli-\(id)", nonce: "n1", at: now.addingTimeInterval(-30), turns: 1, busy: false, abortable: abortable)
        store.router.decisions.append(entry)
        return entry.id
    }

    @Test func stoppingStopsATurnFjordStartedAndRecordsIt() async {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true), session("b", "Login", running: true)])
        let id = delivery(store, session: "a")
        var cancelled: [String] = []
        t.canceller = { sent in cancelled.append(sent.nonce); return .aborted }
        let r = await t.call("stop_session", ["session": "ci"])
        #expect(r?.isError == false && r?.text.contains("Stopped") == true && cancelled == ["n1"])
        let entry = store.router.decisions.first { $0.id == id }
        #expect(entry?.delivered?.cancelled == .aborted && entry?.done.last == .cancelled(.aborted))
    }

    @Test func stoppingRefusesASessionOrAnAskTheMessageDoesntMake() async {
        let (store, t) = world("stop using the old parser in the CI code", sessions: [session("a", "Fix CI", running: true), session("b", "Login", running: true)])
        _ = delivery(store, session: "a")
        _ = delivery(store, session: "b")
        t.canceller = { _ in Issue.record("nothing should be stopped"); return .aborted }
        // Names another session than the one picked.
        let other = await t.call("stop_session", ["session": "b"])
        #expect(other?.isError == true && other?.text.contains("doesn't name") == true)
        // Names the session but doesn't ask to stop it.
        t.beginTurn("how is the CI session doing")
        let asks = await t.call("stop_session", ["session": "ci"])
        #expect(asks?.isError == true && asks?.text.contains("doesn't ask to stop") == true)
    }

    @Test func stoppingSaysWhyWhenItCant() async {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true), session("b", "Docs", running: false)])
        t.canceller = { _ in Issue.record("nothing should be stopped"); return .aborted }
        // No message of Fjord's started the turn.
        let none = await t.call("stop_session", ["session": "ci"])
        #expect(none?.isError == true && none?.text.contains("sent through Fjord") == true)
        // The plugin can't abort.
        _ = delivery(store, session: "a", abortable: false)
        let plugin = await t.call("stop_session", ["session": "ci"])
        #expect(plugin?.isError == true && plugin?.text.contains("plugin") == true)
        // Not running.
        t.beginTurn("stop the Docs session")
        let idle = await t.call("stop_session", ["session": "docs"])
        #expect(idle?.isError == true && idle?.text.contains("isn't working") == true)
        #expect(await t.call("stop_session", ["session": "nope"])?.isError == true)
    }

    // MARK: Registry

    @Test func theNewActionsAreCapabilitiesOfAChangeRunAndNotOfAQuestion() {
        for tool in ["archive_cards", "reopen_card", "mute_project", "stop_session"] {
            #expect(RouterRun.toolNames(.changeFjord, triage: false).contains(tool) && RouterRun.toolNames(.compound, triage: false).contains(tool))
            #expect(!RouterRun.toolNames(.question, triage: true).contains(tool))
            #expect(!FjordTools.triageNames.contains(tool))
            #expect(RouterRun.role(.changeFjord, triage: false).contains("`\(tool)`"))
        }
    }
}
