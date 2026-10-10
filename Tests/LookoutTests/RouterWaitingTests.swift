import Foundation
import Testing
@testable import Lookout

/// A session waiting on something Lookout sees finish: ready to continue, told by you or on its own, logged.
@MainActor
@Suite(.serialized) struct RouterWaitingTests {
    final class Sent { var messages: [(String, String)] = []; var fail = false }

    private func ci(_ checks: CheckState?, jobs: [String] = []) -> Thing {
        var thing = InboxFixture.pr(1, repo: "o/app")
        thing.checks = checks
        thing.failingJobs = jobs
        return thing
    }

    private func store(watch: RouterTriage.Watch, things: [Thing] = [], auto: Bool? = nil) -> (Store, Sent) {
        let s = InboxFixture.store(things)
        s.router.enabled = true
        s.claudeSessions = [
            "a": ClaudeSession(id: "a", title: "Deploy fix", folder: "/code/app", completedTurns: 3, lastActivity: Date(), cliID: "cli-a"),
            "b": ClaudeSession(id: "b", title: "Migration", folder: "/code/db", completedTurns: 5, lastActivity: Date(), running: true),
        ]
        var card = RouterCard(id: "a#t3", sessionID: "a", kind: .waiting, title: "Deploy fix", folder: "/code/app", text: "Waiting on CI",
                              createdAt: Date())
        card.triage = RouterTriage(state: .waiting, waitingOn: .ci, watch: watch)
        s.router.cards = [card]
        if let auto { s.router.autoContinue = auto }
        let sent = Sent()
        s.routerTriager.sender = { session, text in
            if sent.fail { throw RouterTools.Failure("not delivered") }
            sent.messages.append((session, text))
        }
        return (s, sent)
    }

    private func settle() async { for _ in 0..<20 { await Task.yield() } }

    private let ciWatch = RouterTriage.Watch(target: .ci(thing: "pr:o/app#1"), label: "CI on o/app#1")

    @Test func ciGoingGreenMakesTheSessionReadyAndSaysSo() async {
        let (s, sent) = store(watch: ciWatch, things: [ci(.pending)])
        var ready: [RouterCard] = []
        s.routerTriager.onReady = { ready.append($0) }
        s.resolveWaits()
        #expect(s.router.cards[0].triage?.ready == nil)
        s.things["pr:o/app#1"]?.checks = .passing
        let card = s.router.cards[0]
        #expect(card.isOpen && card.triage?.ready?.result == "passing")
        #expect(RouterWaits.message(card.triage!) == "The CI on o/app#1 finished: passing.")
        #expect(ready.map(\.id) == ["a#t3"])
        await settle()
        #expect(sent.messages.isEmpty)
        // Said once.
        s.resolveWaits()
        #expect(ready.count == 1)
    }

    @Test func redSaysWhichJobsFailed() {
        let (s, _) = store(watch: ciWatch, things: [ci(.pending)])
        s.things["pr:o/app#1"] = ci(.failing, jobs: ["lint", "test (macos)"])
        #expect(s.router.cards[0].triage?.ready?.result == "failing (lint, test (macos))")
    }

    @Test func anotherSessionFinishingItsTurnEndsTheWait() {
        let watch = RouterTriage.Watch(target: .session(id: "b", turns: 5), label: "session “Migration”")
        let (s, _) = store(watch: watch)
        s.resolveWaits()
        #expect(s.router.cards[0].triage?.ready == nil)
        // Its next turn finishes.
        s.claudeSessions["b"]?.completedTurns = 6
        s.resolveWaits()
        #expect(s.router.cards[0].triage?.ready == nil)
        s.claudeSessions["b"]?.running = false
        s.resolveWaits()
        #expect(RouterWaits.message(s.router.cards[0].triage!) == "The session “Migration” finished: it finished its turn.")
    }

    @Test func tellItSendsOnceLogsItAndAddressesTheCard() async {
        let (s, sent) = store(watch: ciWatch, things: [ci(.passing)])
        s.resolveWaits()
        s.tellWaiting("a#t3")
        s.tellWaiting("a#t3")
        await settle()
        #expect(sent.messages.count == 1 && sent.messages[0] == ("a", "The CI on o/app#1 finished: passing."))
        let entry = s.router.decisions.last!
        #expect(entry.trigger == .you("Tell it to continue") && entry.done == [.sent(to: "Deploy fix", text: "The CI on o/app#1 finished: passing.", original: nil)])
        #expect(entry.links.sessions == ["a"] && !s.router.cards[0].isOpen && s.router.cards[0].addressedBy == .router)
    }

    @Test func aFailedSendIsLoggedAndCanBeTriedAgain() async {
        let (s, sent) = store(watch: ciWatch, things: [ci(.passing)])
        sent.fail = true
        s.resolveWaits()
        s.tellWaiting("a#t3")
        await settle()
        #expect(s.router.cards[0].isOpen && s.router.cards[0].triage?.told == nil)
        #expect(s.router.decisions.last?.done == [.failed("not delivered")])
        sent.fail = false
        s.tellWaiting("a#t3")
        await settle()
        #expect(sent.messages.count == 1 && !s.router.cards[0].isOpen)
    }

    @Test func continuingAutomaticallySendsOnItsOwnAsLookoutsRun() async {
        let (s, sent) = store(watch: ciWatch, things: [ci(.pending)], auto: true)
        var ready = 0
        s.routerTriager.onReady = { _ in ready += 1 }
        s.things["pr:o/app#1"]?.checks = .passing
        await settle()
        #expect(sent.messages.count == 1 && ready == 0)
        let entry = s.router.decisions.last!
        #expect(entry.trigger == .system && entry.done.count == 1 && entry.reply != nil)
    }

    @Test func aSessionsOwnChoiceOverridesTheDefault() async {
        let (s, sent) = store(watch: ciWatch, things: [ci(.pending)], auto: true)
        s.setContinuesAutomatically("a", false)
        #expect(!s.continuesAutomatically("a") && s.router.autoContinueSessions == ["a": false])
        s.things["pr:o/app#1"]?.checks = .passing
        await settle()
        #expect(sent.messages.isEmpty && s.router.cards[0].triage?.ready != nil)
        // Back to the default: no override kept.
        s.setContinuesAutomatically("a", true)
        #expect(s.router.autoContinueSessions.isEmpty)
        // Off by default, and on for one session only.
        let (t, sentT) = store(watch: ciWatch, things: [ci(.pending)])
        #expect(!t.router.autoContinue)
        t.setContinuesAutomatically("a", true)
        t.things["pr:o/app#1"]?.checks = .failing
        await settle()
        #expect(sentT.messages.count == 1)
    }

    @Test func theWaitOptionsAreTheOtherSessionsAndTheRunningChecksOfTheSessionsRepo() {
        var other = ci(.pending)
        other.id = "pr:o/other#2"
        other.repo = "o/other"
        let (s, _) = store(watch: ciWatch, things: [ci(.pending), other, { var t = ci(.passing); t.id = "pr:o/app#3"; return t }()])
        let options = s.waitOptions(for: s.claudeSessions["a"]!)
        #expect(options.map(\.key) == ["s0", "c0"])
        #expect(options[0].watch.target == .session(id: "b", turns: 5) && options[1].watch.target == .ci(thing: "pr:o/app#1"))
    }
}
