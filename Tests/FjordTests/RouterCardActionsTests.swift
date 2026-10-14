import Foundation
import Testing
@testable import Fjord

/// The Router's actions on its own page: archive and reopen a card, mute a project, stop a running session's turn. Each is
/// only proposed, as a change that waits for the user's Apply; Apply does it and Revert (but for a stop) undoes it.
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

    private func waiting(_ store: Store) -> [FjordChange] { store.router.changes.filter(\.isPending) }

    // MARK: archive_cards

    @Test func archivingOnlyProposesUntilApplyThenRevertReopens() async {
        let (store, t) = world("I'll handle the login question myself", cards: [
            card("a#1", kind: .question, title: "Fix login redirect"), card("b#1", title: "Dark theme colours")],
            sessions: [session("a", "Fix login redirect"), session("b", "Dark theme colours")])
        let r = await t.call("archive_cards", ["cards": ["a#1"]])
        #expect(r?.isError == false && r?.text.contains("nothing yet") == true && r?.text.contains("waits") == true)
        // Nothing is done: the card is open, and one change waits, saying exactly what Apply will do.
        #expect(open(store, "a#1") == true && open(store, "b#1") == true)
        let change = waiting(store)
        #expect(change.count == 1 && change[0].title == "Archive “Fix login redirect” (lookout)")
        #expect(store.router.decisions.contains { $0.links.changes.contains(change[0].id) })
        // Apply archives it, as the Archive button does.
        #expect(store.applyFjordChange(change[0].id)?.pending == nil)
        #expect(open(store, "a#1") == false && store.router.cards.first { $0.id == "a#1" }?.addressedBy == .you && open(store, "b#1") == true)
        // Revert opens it again.
        #expect(store.revertFjordChange(change[0].id)?.isReverted == true)
        #expect(open(store, "a#1") == true)
    }

    @Test func aRequestThatLooksInjectedStillOnlyProposes() async {
        // The message never names the card, the way a session's text steering the model would have it: it is only a proposal.
        let (store, t) = world("run the tests", cards: [card("a#1", title: "Login tests")], sessions: [session("a", "Login tests")])
        #expect(await t.call("archive_cards", ["cards": ["a#1"]])?.isError == false)
        #expect(open(store, "a#1") == true && waiting(store).count == 1)
        // Discarding it leaves everything as it was.
        store.discardFjordChange(waiting(store)[0].id)
        #expect(open(store, "a#1") == true && waiting(store).isEmpty)
    }

    @Test func proposingTheSameArchiveTwiceWaitsOnce() async {
        let (store, t) = world("archive the login card", cards: [card("a#1", title: "Login redirect")])
        _ = await t.call("archive_cards", ["cards": ["a#1"]])
        _ = await t.call("archive_cards", ["cards": ["login"]])
        #expect(waiting(store).count == 1)
    }

    @Test func applyingAnArchiveOfACardAlreadyHandledRefusesAndKeepsItWaiting() async {
        let (store, t) = world("archive the login card", cards: [card("a#1", title: "Login redirect")])
        _ = await t.call("archive_cards", ["cards": ["a#1"]])
        store.setCardAddressed("a#1", true)
        let after = store.applyFjordChange(waiting(store)[0].id)
        #expect(after?.isPending == true && after?.failureNote?.contains("isn't open") == true)
    }

    @Test func archivingRefusesAmbiguousWordsAndMissingCards() async {
        let (store, t) = world("archive the login card", cards: [card("a#1", title: "Login redirect"), card("b#1", title: "Login docs")])
        let ambiguous = await t.call("archive_cards", ["cards": ["login"]])
        #expect(ambiguous?.isError == true && ambiguous?.text.contains("more than one") == true)
        #expect(await t.call("archive_cards", ["cards": ["zzz"]])?.isError == true)
        #expect(await t.call("archive_cards", ["cards": [String]()])?.isError == true)
        #expect(store.router.cards.allSatisfy(\.isOpen) && store.router.changes.isEmpty)
    }

    @Test func archivingNeedsAUserTurn() async {
        let (store, t) = world("archive the login card", cards: [card("a#1", title: "Login redirect")])
        t.endTurn()
        #expect(await t.call("archive_cards", ["cards": ["a#1"]])?.isError == true)
        #expect(open(store, "a#1") == true && store.router.changes.isEmpty)
    }

    @Test func markingSeenStaysImmediateWithTheSameHistoryLine() async {
        let (store, t) = world("seen the docs", cards: [card("a#1", title: "Docs pass")])
        #expect(await t.call("mark_seen", ["cards": ["a#1"]])?.isError == false)
        #expect(open(store, "a#1") == false)
        #expect(store.router.decisions.last?.trigger == .you("Archived") && store.router.decisions.last?.links.cards == ["a#1"])
    }

    // MARK: reopen_card

    @Test func reopeningIsProposedThenAppliedAndRevertedBack() async {
        let (store, t) = world("reopen the docs card", cards: [
            card("a#1", title: "Docs pass", open: false), card("b#1", title: "Login redirect", open: false)],
            sessions: [session("a", "Docs pass"), session("b", "Login redirect")])
        let r = await t.call("reopen_card", ["card": "docs"])
        #expect(r?.isError == false && open(store, "a#1") == false && open(store, "b#1") == false)
        let change = waiting(store)
        #expect(change.count == 1 && change[0].title == "Reopen “Docs pass” (lookout)")
        store.applyFjordChange(change[0].id)
        #expect(open(store, "a#1") == true && open(store, "b#1") == false)
        store.revertFjordChange(change[0].id)
        #expect(open(store, "a#1") == false)
        #expect(await t.call("reopen_card", ["card": "zzz"])?.isError == true)
    }

    @Test func reopeningIsRefusedWhileTheSessionHasAnotherOpenCard() async {
        let (store, t) = world("reopen the docs card", cards: [
            card("a#1", title: "Docs pass", open: false), card("a#2", title: "Docs follow-up")], sessions: [session("a", "Docs pass")])
        let r = await t.call("reopen_card", ["card": "a#1"])
        #expect(r?.isError == true && r?.text.contains("another open card") == true)
        #expect(store.router.changes.isEmpty && open(store, "a#1") == false && open(store, "a#2") == true)
    }

    @Test func applyingAReopenAfterTheSessionGotAnOpenCardRefusesAndSupersedesNothing() async {
        let (store, t) = world("reopen the docs card", cards: [card("a#1", title: "Docs pass", open: false)], sessions: [session("a", "Docs pass")])
        _ = await t.call("reopen_card", ["card": "a#1"])
        store.router.cards.append(card("a#2", title: "Newer"))
        let after = store.applyFjordChange(waiting(store)[0].id)
        #expect(after?.isPending == true && after?.failureNote?.contains("another open card") == true)
        #expect(open(store, "a#1") == false && open(store, "a#2") == true)
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

    @Test func mutingIsProposedThenAppliedAndReverted() async {
        let sessions = [session("a", "One", folder: "/code/microsandbox"), session("b", "Two", folder: "/code/lookout")]
        let (store, t) = world("mute microsandbox", sessions: sessions)
        #expect(await t.call("mute_project", ["project": "microsandbox", "muted": true])?.isError == false)
        #expect(!store.isFolderMuted("/code/microsandbox"))
        let change = waiting(store)
        #expect(change.count == 1 && change[0].title == "Mute project microsandbox", "\(change.map(\.title))")
        store.applyFjordChange(change[0].id)
        #expect(store.isFolderMuted("/code/microsandbox") && !store.isFolderMuted("/code/lookout"))
        store.revertFjordChange(change[0].id)
        #expect(!store.isFolderMuted("/code/microsandbox"))
        // Nothing to change: said so, and nothing waits.
        #expect(await t.call("mute_project", ["project": "microsandbox", "muted": false])?.text.contains("already") == true)
        #expect(await t.call("mute_project", ["project": "nothing", "muted": true])?.isError == true)
        // Unmute is a proposal too.
        store.setFolderMuted("/code/microsandbox", true)
        t.beginTurn("tell microsandbox to rest")
        #expect(await t.call("mute_project", ["project": "microsandbox", "muted": false])?.isError == false)
        #expect(store.isFolderMuted("/code/microsandbox") && waiting(store).count == 1)
    }

    @Test func mutingAnAmbiguousProjectListsTheChoices() async {
        let sessions = [session("a", "One", folder: "/work/app"), session("b", "Two", folder: "/code/app")]
        let (store, t) = world("mute app", sessions: sessions)
        let r = await t.call("mute_project", ["project": "app", "muted": true])
        #expect(r?.isError == true && r?.text.contains("more than one project") == true)
        #expect(store.router.changes.isEmpty)
    }

    @Test func aQualifiedProjectNameIsResolved() async {
        let sessions = [session("a", "One", folder: "/work/app"), session("b", "Two", folder: "/code/app")]
        let (store, t) = world("mute code/app", sessions: sessions)
        #expect(await t.call("mute_project", ["project": "code/app", "muted": true])?.isError == false)
        store.applyFjordChange(waiting(store)[0].id)
        #expect(store.isFolderMuted("/code/app") && !store.isFolderMuted("/work/app"))
    }

    @Test func aGuestProjectIsMutedByItsRouterIdentityNotItsHostMirrorFolder() async throws {
        let projectID = UUID()
        let location = SessionLocation.computer(deviceId: "owner", computerId: "c1")
        let (store, t) = world("mute the guest project", sessions: [session("g", "Guest work", folder: "/mirror/host/proj")])
        store.router.runsOnProjects = [RunsOnProject(id: projectID, name: "Proj", sourceFolder: "/code/proj",
                                                     placement: .computer(deviceId: "owner", computerId: "c1", guestPath: "/workspace/proj"))]
        store.router.pendingDesktopStarts = [PendingDesktopStart(projectID: projectID, location: location, alias: "vm", folder: "/workspace/proj",
                                                                  prompt: "Start", state: .matched, desktopSessionID: "g", guestSessionID: "cli-g")]
        let key = store.routerProjectGroupKey(sessionID: "g", folder: "/mirror/host/proj")
        #expect(key.hasPrefix("guest-project:"))
        #expect(await t.call("mute_project", ["project": "Proj", "muted": true])?.isError == false)
        store.applyFjordChange(try #require(waiting(store).first).id)
        #expect(store.agents.mutedFolders == [key] && !store.isFolderMuted("/mirror/host/proj"))
        // The board lists it as muted, and unmuting it goes through the same key.
        let board = try #require(JSONSerialization.jsonObject(with: Data(await t.board(store).utf8)) as? [String: Any])
        #expect((board["mutedProjects"] as? [String])?.joined().contains("Proj") == true)
        t.beginTurn("unmute it")
        _ = await t.call("mute_project", ["project": "Proj", "muted": false])
        store.applyFjordChange(try #require(waiting(store).first).id)
        #expect(store.agents.mutedFolders.isEmpty)
    }

    // MARK: stop_session

    private func delivery(_ store: Store, session id: String, nonce: String = "n1", turns: Int = 1, busy: Bool = false, abortable: Bool = true) -> UUID {
        var entry = RouterDecision(at: now, trigger: .you("run the tests"), outcome: .done)
        entry.delivered = .init(session: id, cli: "cli-\(id)", nonce: nonce, at: now.addingTimeInterval(-30), turns: turns, busy: busy, abortable: abortable)
        store.router.decisions.append(entry)
        return entry.id
    }

    @Test func stoppingIsProposedThenApplyStopsTheRunningTurnAndRecordsIt() async throws {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true), session("b", "Login", running: true)])
        let id = delivery(store, session: "a")
        var cancelled: [String] = []
        store.deliveryCanceller = { sent, gate in
            #expect(gate() == nil)
            cancelled.append(sent.nonce)
            return .aborted
        }
        let r = await t.call("stop_session", ["session": "ci"])
        #expect(r?.isError == false && r?.text.contains("nothing yet") == true && cancelled.isEmpty)
        let change = try #require(waiting(store).first)
        #expect(change.title.hasPrefix("Stop “Fix CI” (lookout, this Mac, since ") && change.pending?.contains("can't be undone") == true)
        #expect(store.router.decisions.first { $0.id == id }?.delivered?.cancelled == nil)
        #expect(await store.applyStopChange(change.id)?.pending == nil)
        #expect(cancelled == ["n1"])
        let entry = store.router.decisions.first { $0.id == id }
        #expect(entry?.delivered?.cancelled == .aborted && entry?.done.last == .cancelled(.aborted))
        // A stop isn't revertible.
        #expect(store.revertFjordChange(change.id) == nil)
    }

    @Test func stoppingTargetsTheRunningDeliveryNotAQueuedOne() async throws {
        // One delivery started the running turn; another found it busy and waits for the next one.
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true)])
        _ = delivery(store, session: "a", nonce: "queued", turns: 1, busy: true)
        _ = delivery(store, session: "a", nonce: "running", turns: 1, busy: false)
        _ = await t.call("stop_session", ["session": "ci"])
        let change = try #require(waiting(store).first)
        guard case .cardAction(.stop(_, _, _, _, _, _, let nonce)) = change.patch else { Issue.record("not a stop"); return }
        #expect(nonce == "running")
        // Only a queued one: nothing is running that Fjord started.
        let (other, t2) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true)])
        _ = delivery(other, session: "a", nonce: "queued", turns: 1, busy: true)
        let none = await t2.call("stop_session", ["session": "ci"])
        #expect(none?.isError == true && none?.text.contains("sent through Fjord") == true && other.router.changes.isEmpty)
    }

    @Test func applyingAStopRefusesWhenThatDeliveryIsNoLongerTheRunningTurn() async throws {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true)])
        _ = delivery(store, session: "a")
        store.deliveryCanceller = { _, _ in Issue.record("nothing should be stopped"); return .aborted }
        _ = await t.call("stop_session", ["session": "ci"])
        let id = try #require(waiting(store).first?.id)
        // The turn finished meanwhile and another began.
        store.claudeSessions["a"]?.completedTurns = 2
        let after = await store.applyStopChange(id)
        #expect(after?.isPending == true && after?.failureNote?.contains("nothing to stop") == true)
    }

    @Test func theAbortWriteIsGatedAndRefusedWhenTheTurnEndsBeforeIt() async throws {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true)])
        _ = delivery(store, session: "a")
        _ = await t.call("stop_session", ["session": "ci"])
        let id = try #require(waiting(store).first?.id)
        store.deliveryCanceller = { _, gate in
            // The turn ends between the check and the write.
            store.claudeSessions["a"]?.completedTurns = 2
            if let why = gate() { throw RouterTools.Failure(why) }
            Issue.record("the gate should have refused")
            return .aborted
        }
        let after = await store.applyStopChange(id)
        #expect(after?.isPending == true && after?.failureNote?.contains("isn't running") == true)
    }

    @Test func stoppingSaysWhyWhenItCant() async {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true), session("b", "Docs", running: false)])
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
        #expect(store.router.changes.isEmpty)
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
    @Test func aMutedGuestProjectIsMutedForEveryReader() async throws {
        let projectID = UUID()
        let location = SessionLocation.computer(deviceId: "owner", computerId: "c1")
        let guest = session("g", "Guest work", folder: "/mirror/host/proj")
        let local = session("l", "Local work", folder: "/code/other")
        let (store, _) = world("mute", sessions: [guest, local])
        store.router.runsOnProjects = [RunsOnProject(id: projectID, name: "Proj", sourceFolder: "/code/proj",
                                                     placement: .computer(deviceId: "owner", computerId: "c1", guestPath: "/workspace/proj"))]
        store.router.pendingDesktopStarts = [PendingDesktopStart(projectID: projectID, location: location, alias: "vm", folder: "/workspace/proj",
                                                                  prompt: "Start", state: .matched, desktopSessionID: "g", guestSessionID: "cli-g")]
        let key = store.routerProjectGroupKey(sessionID: "g", folder: "/mirror/host/proj")
        store.setFolderMuted(key, true)
        // The session-side readers (sessions list, notifications, the feed) compare the session's folder.
        let muted = store.mutedSessionIDs()
        #expect(muted.contains("g") && !muted.contains("l"))
        // A local project's key is its folder, so its mute reads as it always did.
        store.setFolderMuted("/code/other", true)
        #expect(store.mutedSessionIDs().contains("l"))
        // The canvas and the Brief group by the Router's key: the guest frame is gone.
        var page = RouterPage()
        page.needs = [card("g#1", kind: .asks, title: "Guest work", folder: "/mirror/host/proj")]
        let frames = RouterCanvasModel.make(page: page, done: [], muted: Set(store.agents.mutedFolders), name: { $0 }, color: { _ in nil },
                                            projectKey: store.routerProjectGroupKey, projectSource: store.routerProjectGroupSource)
        #expect(frames.isEmpty)
    }

    @Test func twoGuestProjectsSharingAMirrorFolderAreMutedApart() async throws {
        let location = SessionLocation.computer(deviceId: "owner", computerId: "c1")
        let a = session("a", "A work", folder: "/mirror/host/proj")
        let b = session("b", "B work", folder: "/mirror/host/proj")
        let (store, _) = world("mute apart", sessions: [a, b])
        let one = RunsOnProject(id: UUID(), name: "One", sourceFolder: "/code/one", placement: .computer(deviceId: "owner", computerId: "c1", guestPath: "/w/one"))
        let two = RunsOnProject(id: UUID(), name: "Two", sourceFolder: "/code/two", placement: .computer(deviceId: "owner", computerId: "c1", guestPath: "/w/two"))
        store.router.runsOnProjects = [one, two]
        store.router.pendingDesktopStarts = [
            PendingDesktopStart(projectID: one.id, location: location, alias: "vm", folder: "/w/one", prompt: "Start", state: .matched, desktopSessionID: "a", guestSessionID: "cli-a"),
            PendingDesktopStart(projectID: two.id, location: location, alias: "vm", folder: "/w/two", prompt: "Start", state: .matched, desktopSessionID: "b", guestSessionID: "cli-b")]
        store.setFolderMuted(store.routerProjectGroupKey(sessionID: "a", folder: "/mirror/host/proj"), true)
        #expect(store.mutedSessionIDs() == ["a"])
        // Changing the mute is read at once, not from the kept answer.
        store.setFolderMuted(store.routerProjectGroupKey(sessionID: "b", folder: "/mirror/host/proj"), true)
        #expect(store.mutedSessionIDs() == ["a", "b"])
    }

    @Test func aStopRefusedBeforeItsWriteStaysWaitingAndRetryable() async throws {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true)])
        _ = delivery(store, session: "a")
        _ = await t.call("stop_session", ["session": "ci"])
        let change = try #require(waiting(store).first)
        var refused = false
        store.deliveryCanceller = { _, gate in
            // The final look refuses (the Router went off): nothing was written.
            store.router.enabled = false
            refused = gate() != nil
            throw RouterTools.Failure("The Router is off")
        }
        let after = await store.applyStopChange(change.id)
        #expect(refused && after?.isPending == true && after?.applying == nil && after?.failureNote?.contains("Couldn't stop") == true)
    }

    @Test func aStopStillApplyingWhenFjordQuitSettlesAsSentButUnconfirmed() {
        var state = RouterState()
        var change = FjordChange(title: "Stop it", patch: .cardAction(.mute(project: "/p", name: "p", muted: true)))
        change.pending = "Stopping can't be undone"
        change.applying = "Stopping…"
        state.changes = [change]
        state.settleInterrupted()
        #expect(state.changes[0].pending == nil && state.changes[0].applying == nil)
        #expect(state.changes[0].failureNote == "The stop was sent, but Fjord quit before it was confirmed.")
    }

    // MARK: stop identity and state

    @Test func twoSessionsOfOneTitleGetDistinguishableStopProposals() async throws {
        let (store, t) = world("stop run tests in lookout", sessions: [session("a", "Run tests", folder: "/code/lookout", running: true),
                                                                        session("b", "Run tests", folder: "/code/silo", running: true)])
        _ = delivery(store, session: "a")
        _ = delivery(store, session: "b", nonce: "n2")
        _ = await t.call("stop_session", ["session": "a"])
        t.beginTurn("stop run tests in silo")
        _ = await t.call("stop_session", ["session": "b"])
        let titles = waiting(store).map(\.title)
        #expect(titles.count == 2 && Set(titles).count == 2)
        #expect(titles.contains { $0.contains("lookout, this Mac") } && titles.contains { $0.contains("silo, this Mac") })
        // Open goes to that exact session.
        let targets = waiting(store).map { $0.target(in: store) }
        #expect(targets.contains(.session("a")) && targets.contains(.session("b")))
    }

    @Test func onceTheAbortIsWrittenDiscardIsGoneAndTheAcknowledgementSettlesIt() async throws {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true)])
        let id = delivery(store, session: "a")
        _ = await t.call("stop_session", ["session": "ci"])
        let change = try #require(waiting(store).first)
        var discardDuring: FjordChange?? = .none
        store.deliveryCanceller = { _, gate in
            #expect(gate() == nil)
            // The abort is committed: the card says it is stopping, and Discard does nothing.
            discardDuring = .some(store.discardFjordChange(change.id))
            #expect(store.router.changes.first { $0.id == change.id }?.applying == "Stopping…")
            return .aborted
        }
        let after = await store.applyStopChange(change.id)
        #expect(discardDuring == .some(nil))
        #expect(after?.pending == nil && after?.applying == nil && after?.isDiscarded == false && after?.failureNote == nil)
        #expect(store.router.decisions.first { $0.id == id }?.delivered?.cancelled == .aborted)
    }

    @Test func aStopWhoseAcknowledgementFailsAfterTheWriteSettlesAndSaysSo() async throws {
        let (store, t) = world("stop the CI session", sessions: [session("a", "Fix CI", running: true)])
        _ = delivery(store, session: "a")
        _ = await t.call("stop_session", ["session": "ci"])
        let change = try #require(waiting(store).first)
        store.deliveryCanceller = { _, gate in
            #expect(gate() == nil)
            throw RouterTools.Failure("no answer")
        }
        let after = await store.applyStopChange(change.id)
        #expect(after?.isPending == false && after?.applying == nil && after?.failureNote?.contains("sent") == true)
        #expect(store.discardFjordChange(change.id) == nil)
    }

}
