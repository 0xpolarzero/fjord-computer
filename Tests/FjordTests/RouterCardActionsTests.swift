import AppKit
import Carbon
import Foundation
import Testing
@testable import Fjord

/// The actions on the Router page: archive and reopen a card, mute a project. Each is done at once and recorded as an applied
/// change in the history, which Revert undoes.
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

    private func world(cards: [RouterCard] = [], sessions: [ClaudeSession] = []) -> Store {
        let store = InboxFixture.store([])
        store.router.enabled = true
        store.agents.enabled = true
        store.claudeSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        store.router.cards = cards
        return store
    }

    private func open(_ store: Store, _ id: String) -> Bool? { store.router.cards.first { $0.id == id }?.isOpen }

    private func archive(_ c: RouterCard) -> CardAction { .archive(card: c.id, title: c.title, project: "lookout") }
    private func reopen(_ c: RouterCard) -> CardAction { .reopen(card: c.id, title: c.title, project: "lookout") }

    @Test func archivingActsAtOnceAndRevertReopensIt() throws {
        let a = card("a#1", kind: .question, title: "Fix login redirect"), b = card("b#1", title: "Dark theme colours")
        let store = world(cards: [a, b], sessions: [session("a", a.title), session("b", b.title)])
        let change = try #require(store.act(archive(a)))
        #expect(change.title == "Archive “Fix login redirect” (lookout)" && !change.isPending && !change.isReverted)
        #expect(open(store, "a#1") == false && store.router.cards.first { $0.id == "a#1" }?.addressedBy == .you && open(store, "b#1") == true)
        // The history shows it, linked to an entry of its own.
        #expect(store.router.decisions.contains { $0.links.changes.contains(change.id) })
        #expect(store.revertFjordChange(change.id)?.isReverted == true)
        #expect(open(store, "a#1") == true)
    }

    @Test func archivingACardAlreadyHandledRecordsNothing() {
        let a = card("a#1", title: "Login redirect")
        let store = world(cards: [a])
        store.setCardAddressed("a#1", true)
        #expect(store.act(archive(a)) == nil && store.router.changes.isEmpty)
    }

    @Test func reopeningActsAtOnceAndRevertArchivesItAgain() throws {
        let a = card("a#1", title: "Docs pass", open: false), b = card("b#1", title: "Login redirect", open: false)
        let store = world(cards: [a, b], sessions: [session("a", a.title), session("b", b.title)])
        let change = try #require(store.act(reopen(a)))
        #expect(change.title == "Reopen “Docs pass” (lookout)" && !change.isPending)
        #expect(open(store, "a#1") == true && open(store, "b#1") == false)
        store.revertFjordChange(change.id)
        #expect(open(store, "a#1") == false)
    }

    @Test func reopeningIsRefusedWhileTheSessionHasAnotherOpenCard() {
        let a = card("a#1", title: "Docs pass", open: false)
        let store = world(cards: [a, card("a#2", title: "Docs follow-up")], sessions: [session("a", "Docs pass")])
        #expect(store.act(reopen(a)) == nil)
        #expect(store.router.changes.isEmpty && open(store, "a#1") == false && open(store, "a#2") == true)
    }

    @Test func aCardASessionsNewerOneReplacedCantBeReopened() {
        var old = card("a#1", title: "Docs pass", open: false)
        old.addressedBy = .superseded
        let store = world(cards: [old], sessions: [session("a", "Docs pass")])
        #expect(store.act(reopen(old)) == nil && open(store, "a#1") == false)
    }

    @Test func revertingAnArchiveWhoseSessionGotAnotherOpenCardSaysWhyAndStaysApplied() throws {
        let a = card("a#1", title: "Docs pass")
        let store = world(cards: [a], sessions: [session("a", "Docs pass")])
        let change = try #require(store.act(archive(a)))
        store.router.cards.append(card("a#2", title: "Newer"))
        let after = store.revertFjordChange(change.id)
        #expect(after?.isReverted == false && after?.failureNote?.contains("another open card") == true)
        #expect(open(store, "a#1") == false && open(store, "a#2") == true)
    }

    @Test func mutingActsAtOnceAndRevertUnmutes() throws {
        let store = world(sessions: [session("a", "One", folder: "/code/microsandbox"), session("b", "Two", folder: "/code/lookout")])
        let change = try #require(store.act(.mute(project: "/code/microsandbox", name: "microsandbox", muted: true)))
        #expect(change.title == "Mute project microsandbox" && !change.isPending)
        #expect(store.isFolderMuted("/code/microsandbox") && !store.isFolderMuted("/code/lookout"))
        store.revertFjordChange(change.id)
        #expect(!store.isFolderMuted("/code/microsandbox"))
        // Muted already: nothing to change, nothing recorded.
        store.setFolderMuted("/code/microsandbox", true)
        let count = store.router.changes.count
        #expect(store.act(.mute(project: "/code/microsandbox", name: "microsandbox", muted: true)) == nil && store.router.changes.count == count)
        let unmute = try #require(store.act(.mute(project: "/code/microsandbox", name: "microsandbox", muted: false)))
        #expect(!store.isFolderMuted("/code/microsandbox") && unmute.title == "Unmute project microsandbox")
    }

    @Test func aGuestProjectIsMutedByItsRouterIdentityNotItsHostMirrorFolder() throws {
        let projectID = UUID()
        let location = SessionLocation.computer(deviceId: "owner", computerId: "c1")
        let store = world(sessions: [session("g", "Guest work", folder: "/mirror/host/proj")])
        store.router.runsOnProjects = [RunsOnProject(id: projectID, name: "Proj", sourceFolder: "/code/proj",
                                                     placement: .computer(deviceId: "owner", computerId: "c1", guestPath: "/workspace/proj"))]
        store.router.pendingDesktopStarts = [PendingDesktopStart(projectID: projectID, location: location, alias: "vm", folder: "/workspace/proj",
                                                                  prompt: "Start", state: .matched, desktopSessionID: "g", guestSessionID: "cli-g")]
        let key = store.routerProjectGroupKey(sessionID: "g", folder: "/mirror/host/proj")
        #expect(key.hasPrefix("guest-project:"))
        let project = try #require(store.routerProjects().first { $0.key == key })
        store.act(.mute(project: project.key, name: project.name, muted: true))
        #expect(store.agents.mutedFolders == [key] && !store.isFolderMuted("/mirror/host/proj"))
    }

    @Test func theRouterPagesArchiveAndReopenButtonsRecordTheSameChanges() throws {
        let a = card("a#1", title: "Docs pass")
        let store = world(cards: [a], sessions: [session("a", "Docs pass")])
        let model = RouterModel()
        model.address("a#1", store: store)
        #expect(open(store, "a#1") == false)
        let archived = try #require(store.router.changes.last)
        #expect(archived.title == "Archive “Docs pass” (lookout)" && !archived.isPending)
        model.reopen("a#1", store: store)
        #expect(open(store, "a#1") == true && store.router.changes.last?.title == "Reopen “Docs pass” (lookout)")
    }

    @Test func onTheBriefTheInboxShortcutsActOnTheHighlightUnderThePointer() throws {
        let a = card("a#1", kind: .question, title: "Fix login redirect")
        let store = world(cards: [a], sessions: [session("a", a.title)])
        final class Opened { var count = 0 }
        let opened = Opened()
        store.interceptOpen = { _ in opened.count += 1 }
        let model = RouterModel()
        model.layout = .brief
        let keys = RouterKeys(store: store, model: model)
        func key(_ code: Int, _ chars: String = "") -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                             characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: UInt16(code))!
        }
        model.digest.hovered = "/code/lookout#a"
        #expect(DigestAction.available(session: "a", store: store) == [.archive(card: "a#1"), .open(session: "a")])
        // Archive (⌫), then Mark as read or unread (Space) opens it again, and Open (Return) opens its session.
        #expect(keys.key(key(kVK_Delete), responder: nil) && open(store, "a#1") == false)
        #expect(DigestAction.available(session: "a", store: store) == [.reopen(card: "a#1"), .open(session: "a")])
        #expect(keys.key(key(kVK_Space, " "), responder: nil) && open(store, "a#1") == true)
        #expect(keys.key(key(kVK_Return, "\r"), responder: nil) && opened.count == 1)
        // Words in the composer keep their keys.
        model.composerFocused = true
        model.draft = "hi"
        #expect(!keys.key(key(kVK_Space, " "), responder: NSTextView()) && open(store, "a#1") == true)
        // Off the highlight, nothing of it.
        model.composerFocused = false
        model.digest.hovered = nil
        #expect(model.digestAction(store.shortcut(.discard), store: store) == nil)
    }

    @Test func closingTheBriefsOpenCardTakesItsReplyUnlessItIsBeingWritten() {
        let a = card("a#1", kind: .question, title: "Fix login redirect")
        let store = world(cards: [a], sessions: [session("a", a.title)])
        let model = RouterModel()
        model.layout = .brief
        model.digest.open = "lead-you#a"
        model.select("a#1", store: store, reveal: false)
        model.closeDigestCard(store: store)
        #expect(model.digest.open == nil && model.replyTo == nil)
        model.digest.open = "lead-you#a"
        model.select("a#1", store: store, reveal: false)
        model.draft = "yes, go"
        model.closeDigestCard(store: store)
        #expect(model.digest.open == nil && model.replyTo == "a#1")
    }

    @Test func aChangeSavedAsAProposedStopIsDroppedOnReading() throws {
        let stop = """
        {"id":"\(UUID().uuidString)","date":0,"title":"Stop","patch":{"cardAction":{"_0":{"stop":{"session":"a","title":"t","project":"p","place":"x","since":0,"decision":"\(UUID().uuidString)","nonce":"n"}}}},"pending":"Stopping can't be undone"}
        """
        let data = Data("{\"changes\":[\(stop)]}".utf8)
        let state = try JSONDecoder().decode(RouterState.self, from: data)
        #expect(state.changes.isEmpty)
    }
}
