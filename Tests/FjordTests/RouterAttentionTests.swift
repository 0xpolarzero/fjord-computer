import Foundation
import Testing
@testable import Fjord

/// Fewer, better-timed banners: what can wait waits; away, only what can't wait comes, and one summary when you're back.
@MainActor
@Suite(.serialized) struct RouterAttentionTests {
    final class Idle { var seconds: TimeInterval = 0 }

    private func card(_ id: String, _ kind: RouterCard.Kind, urgency: Double? = nil, minutes: Double = 0) -> RouterCard {
        var c = RouterCard(id: id, sessionID: id, kind: kind, title: "T \(id)", folder: "/code/\(id)", text: "x",
                           createdAt: Date().addingTimeInterval(minutes * 60))
        if let urgency { c.triage = RouterTriage(state: .asks, urgency: urgency) }
        return c
    }

    private func store() -> (Store, Idle, () -> [String]) {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.settings.notifications = true
        let idle = Idle()
        s.routerAttention.idleSeconds = { idle.seconds }
        var posted: [String] = []
        s.notifier.onPost = { posted.append($0.identifier) }
        s.routerAttention.cards = { [weak s] in s?.router.cards ?? [] }
        s.routerAttention.onBack = { [weak s] strip in if let s { RouterBanners.postBack(strip, store: s, windowIsKey: false) } }
        return (s, idle, { posted })
    }

    @Test func whatStopsASessionOrIsSoonBannersAndTheRestWaits() {
        #expect(RouterAttention.bannerNow(card("q", .question), away: false))
        #expect(RouterAttention.bannerNow(card("p", .plan), away: false))
        #expect(RouterAttention.bannerNow(card("ok", .approval, urgency: 0), away: false))
        #expect(RouterAttention.bannerNow(card("s", .stuck), away: false))
        #expect(RouterAttention.bannerNow(card("soon", .asks, urgency: 3), away: false))
        #expect(RouterAttention.bannerNow(card("unrated", .asks), away: false))
        #expect(!RouterAttention.bannerNow(card("later", .asks, urgency: 1.4), away: false))
        #expect(!RouterAttention.bannerNow(card("d", .done), away: false))
        #expect(!RouterAttention.bannerNow(card("w", .waiting), away: false))
        // Away: only what can't wait (a session stopped mid-turn counts as blocking now).
        #expect(RouterAttention.bannerNow(card("q", .question), away: true))
        #expect(RouterAttention.bannerNow(card("now", .asks, urgency: 4), away: true))
        #expect(!RouterAttention.bannerNow(card("ok", .approval, urgency: 1), away: true))
        #expect(!RouterAttention.bannerNow(card("s", .stuck), away: true))
    }

    @Test func awayTheLowUrgencyWaitsAndComingBackSaysWhatCameOnce() {
        let (s, idle, posted) = store()
        let ask = card("ask", .asks, urgency: 1, minutes: -3)
        let urgent = card("urgent", .asks, urgency: 4, minutes: -2)
        let done = card("done", .done, minutes: -1)
        var ready = card("ready", .waiting)
        ready.triage = RouterTriage(state: .waiting, waitingOn: .ci)
        ready.triage?.ready = .init(result: "passing", at: Date())
        s.router.cards = [ask, urgent, done, ready]

        idle.seconds = 400
        RouterBanners.post([ask, urgent, done], store: s, windowIsKey: false)
        RouterBanners.postReady(ready, store: s, windowIsKey: false)
        #expect(posted() == [RouterBanners.prefix + "urgent"])
        #expect(s.routerAttention.awaySince != nil && s.routerAttention.strip == nil)
        // Still away: nothing more.
        s.routerAttention.refresh()
        #expect(posted().count == 1)

        idle.seconds = 2
        s.routerAttention.refresh()
        let strip = s.routerAttention.strip
        #expect(strip?.line(s.router.cards) == "2 need you, 1 finished, 1 ready to continue")
        #expect(strip?.listed(s.router.cards).map(\.id) == ["urgent", "ask", "ready", "done"])
        // One summary, opening on the most urgent.
        #expect(posted() == [RouterBanners.prefix + "urgent", RouterBanners.prefix + "urgent"])
        s.routerAttention.refresh()
        #expect(posted().count == 2)
        // Handled since: it leaves the strip; dismissed, the strip is gone.
        s.setCardAddressed("urgent", true)
        #expect(strip?.line(s.router.cards) == "1 needs you, 1 finished, 1 ready to continue")
        s.routerAttention.dismissStrip()
        #expect(s.routerAttention.strip == nil)
    }

    @Test func aStuckTurnThatCameAwayIsWeighedAgainOnceJevRatesItAndBanneredOnce() async {
        let (s, idle, posted) = store()
        s.router.enabled = true
        s.routerTriager.rescanned = true
        s.claudeSessions = ["a": ClaudeSession(id: "a", title: "Deploy", folder: "/code/a", completedTurns: 2, lastActivity: Date(),
                                               summary: .init(blocked: true, detail: "Can't reach the server"), cliID: "cli-a")]
        let stuck = RouterCard(id: "a#t2", sessionID: "a", kind: .stuck, title: "Deploy", folder: "/code/a", text: "Can't reach the server",
                               createdAt: Date())
        s.router.cards = [stuck]
        s.onNewRouterCards = { [weak s] in if let s { RouterBanners.post($0, store: s, windowIsKey: false) } }
        idle.seconds = 900
        // Untriaged (no key yet): held for when you're back, at the urgency a turn has unrated.
        s.onNewRouterCards?([stuck])
        #expect(posted().isEmpty)
        // Jev rates it blocking now: it comes.
        s.routerTriager.reader = { _ in "I can't reach the deploy server; the release is blocked until you restore access." }
        s.routerTriager.earlier = { _ in [] }
        s.routerTriager.asker = { _, _ in
            ["state": .choice(.init(choice: "blocked", confidence: 0.9, probabilities: ["blocked": 0.9, "done": 0.1])),
             "urgency": .score(4, confidence: 0.9)]
        }
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(s.router.cards[0].kind == .stuck && s.router.cards[0].triage?.urgency == 4)
        #expect(posted() == [RouterBanners.prefix + "a#t2"])
        // Once: coming again changes nothing.
        s.onNewRouterCards?([s.router.cards[0]])
        s.applyTriage(s.router.cards[0].triage!, to: "a#t2")
        #expect(posted().count == 1)
    }

    @Test func aFinishedTurnWhoseLateSummarySaysBlockedIsBanneredOnce() {
        let (s, _, posted) = store()
        s.claudeLink = .ok
        s.agents.enabled = true
        s.claudeIsFrontmost = { false }
        s.onNewRouterCards = { [weak s] in if let s { RouterBanners.post($0, store: s, windowIsKey: false) } }
        var session = ClaudeSession(id: "a", title: "Deploy", folder: "/code/a", completedTurns: 2, lastActivity: Date(), cliID: "cli-a")
        s.claudeSessions = ["a": session]
        s.router.cards = [RouterCard(id: "a#t2", sessionID: "a", kind: .done, title: "Deploy", folder: "/code/a",
                                     text: RouterFeed.placeholder, createdAt: Date())]
        s.feedRouter()
        #expect(s.router.cards[0].kind == .done && posted().isEmpty)
        // Its summary comes after, blocked: the card that was there needs you now, and says so (no key, no triage to wait for).
        session.summary = .init(blocked: true, detail: "Can't reach the server")
        s.claudeSessions = ["a": session]
        s.feedRouter()
        #expect(s.router.cards[0].kind == .stuck && posted() == [RouterBanners.prefix + "a#t2"])
        // Once.
        s.feedRouter()
        #expect(posted().count == 1)
    }

    @Test func whatTheSummaryToldOfAsYouCameBackGetsNoBannerOfItsOwn() {
        let (s, idle, posted) = store()
        var waiting = card("wait", .waiting)
        waiting.triage = RouterTriage(state: .waiting, waitingOn: .ci,
                                      watch: .init(target: .ci(thing: "pr:o/r#1"), label: "CI on o/r#1", ref: "o/r#1"))
        let stuck = card("stuck", .stuck)
        s.router.cards = [waiting, stuck]
        idle.seconds = 400
        RouterBanners.post([waiting, stuck], store: s, windowIsKey: false)
        #expect(posted().isEmpty)
        // Back, before the timer looked: its CI went green meanwhile, so the summary that coming back makes tells of it.
        idle.seconds = 1
        s.router.cards[0].triage?.ready = .init(result: "passing", at: Date())
        RouterBanners.postReady(s.router.cards[0], store: s, windowIsKey: false)
        #expect(s.routerAttention.strip?.line(s.router.cards) == "1 needs you, 1 ready to continue")
        #expect(posted() == [RouterBanners.prefix + "stuck"])
        // Nor the stuck one, weighed again after its triage.
        RouterBanners.post([stuck], store: s, windowIsKey: false)
        #expect(posted().count == 1)
        // Away again: what comes then is new.
        idle.seconds = 400
        s.routerAttention.refresh()
        idle.seconds = 1
        RouterBanners.postReady(s.router.cards[0], store: s, windowIsKey: false)
        #expect(posted().count == 2)
    }

    @Test func aRenewedCompletionAfterTheSummaryToldOfAnEarlierOneBanners() {
        let (s, idle, posted) = store()
        var waiting = card("wait", .waiting)
        waiting.triage = RouterTriage(state: .waiting, waitingOn: .ci,
                                      watch: .init(target: .ci(thing: "pr:o/r#1"), label: "CI on o/r#1", ref: "o/r#1"))
        s.router.cards = [waiting]
        // CI failed while away: the summary on coming back tells of it.
        idle.seconds = 400
        s.routerAttention.refresh()
        s.router.cards[0].triage?.ready = .init(result: "failed", at: Date())
        RouterBanners.postReady(s.router.cards[0], store: s, windowIsKey: false)
        idle.seconds = 1
        s.routerAttention.refresh()
        #expect(posted().count == 1)
        // Rerun: pending, then passing. That is a new completion.
        s.router.cards[0].triage?.ready = nil
        s.router.cards[0].triage?.ready = .init(result: "passing", at: Date().addingTimeInterval(60))
        RouterBanners.postReady(s.router.cards[0], store: s, windowIsKey: false)
        #expect(posted().count == 2)
    }

    @Test func aCardTheSummaryToldOfAsFinishedStillBannersOnceItNeedsYou() {
        let (s, idle, posted) = store()
        let done = card("done", .done)
        s.router.cards = [done]
        idle.seconds = 400
        RouterBanners.post([done], store: s, windowIsKey: false)
        // Back before Jev answered: the summary says it finished.
        idle.seconds = 0
        s.routerAttention.refresh()
        #expect(posted() == [RouterBanners.prefix + "done"] && s.routerAttention.strip?.line(s.router.cards) == "1 finished")
        // His triage: it asks for your OK. That is news, and it comes.
        s.router.cards[0].kind = .approval
        RouterBanners.post([s.router.cards[0]], store: s, windowIsKey: false)
        #expect(posted().count == 2)
    }

    @Test func aCardLeftOutOfTheSummaryWhileTheRouterWasOffStillBanners() {
        let (s, idle, posted) = store()
        let ask = card("ask", .asks, urgency: 1)
        s.router.cards = [ask]
        idle.seconds = 400
        RouterBanners.post([ask], store: s, windowIsKey: false)
        #expect(!s.routerAttention.admitInbox(.low))
        // Back with the Router off: only the inbox is said.
        s.router.enabled = false
        idle.seconds = 0
        s.routerAttention.refresh()
        #expect(posted().count == 1)
        // On again, it comes as it is: a stop of the session's.
        s.router.enabled = true
        s.router.cards[0].kind = .question
        RouterBanners.post([s.router.cards[0]], store: s, windowIsKey: false)
        #expect(posted().count == 2)
    }

    @Test func withTheRouterOffComingBackSaysOnlyWhatCameInTheInbox() {
        let (s, idle, _) = store()
        var bodies: [String] = []
        s.notifier.onPost = { bodies.append($0.content.body) }
        let ask = card("ask", .asks, urgency: 1, minutes: -1)
        s.router.cards = [ask]
        idle.seconds = 400
        RouterBanners.post([ask], store: s, windowIsKey: false)
        #expect(!s.routerAttention.admitInbox(.low))
        // Off while you're away: its card is not said when you're back, the inbox still is.
        s.router.enabled = false
        idle.seconds = 0
        s.routerAttention.refresh()
        #expect(bodies == ["1 in your inbox"])
        // Nothing but its cards: nothing at all.
        idle.seconds = 400
        RouterBanners.post([ask], store: s, windowIsKey: false)
        s.router.enabled = true
        RouterBanners.post([ask], store: s, windowIsKey: false)
        s.router.enabled = false
        idle.seconds = 0
        s.routerAttention.refresh()
        #expect(bodies == ["1 in your inbox"])
    }

    @Test func aLockedScreenIsAwayAndNothingCameMeansNoSummary() {
        let (s, _, posted) = store()
        s.routerAttention.locked = true
        #expect(s.routerAttention.refresh())
        s.routerAttention.locked = false
        #expect(!s.routerAttention.refresh())
        #expect(s.routerAttention.strip == nil && posted().isEmpty)
    }

    @Test func awayTheInboxBannersOnlyWhatJevRatesHighForYou() {
        let (s, idle, posted) = store()
        let me = s.inboxContext.me
        func rated(_ n: Int, _ level: Importance, viewer: String? = nil) -> Thing {
            var t = InboxFixture.pr(n, repo: "o/r")
            t.kind = .issue
            t.assignees = [me]
            t.signals = ThingSignals(importance: ImportanceSignal(level: level, stamp: InboxEngine.importanceStamp(t, context: s.inboxContext) ?? "?"),
                                     viewer: viewer ?? InboxEngine.viewer(me))
            return t
        }
        let low = rated(1, .low), high = rated(2, .urgent), elses = rated(3, .urgent, viewer: "someone-else")
        s.things = [low.id: low, high.id: high, elses.id: elses]
        #expect(InboxEngine.importance(high, context: s.inboxContext) == .urgent)
        let id = { (t: Thing) in Store.inboxNotificationPrefix + t.id }
        s.notify(id: id(low), title: "", subtitle: "", body: "", quiet: false)
        #expect(posted().count == 1)
        idle.seconds = 900
        // Away: the urgent one comes; the low one, and one rated for someone else, wait.
        for t in [low, high, elses] { s.notify(id: id(t), title: "", subtitle: "", body: "", quiet: false) }
        #expect(posted() == [id(low), id(high)])
        idle.seconds = 0
        s.routerAttention.refresh()
        #expect(s.routerAttention.strip?.line([]) == "2 in your inbox")
        #expect(posted().last?.hasPrefix(Notifier.summaryPrefix) == true)
    }

    @Test func awayAnInboxBatchIsOnlyOfWhatMayInterruptAndTheRestIsCounted() {
        let (s, idle, posted) = store()
        let me = s.inboxContext.me
        let levels: [Importance] = [.low, .low, .low, .low, .low, .urgent]
        func things(greptile: Int) -> [String: Thing] {
            Dictionary(uniqueKeysWithValues: levels.enumerated().map { i, level in
                var t = InboxFixture.pr(i + 1, greptile: greptile)
                t.assignees = [me]
                t.signals = ThingSignals(importance: ImportanceSignal(level: level, stamp: InboxEngine.importanceStamp(t, context: s.inboxContext) ?? "?"),
                                         viewer: InboxEngine.viewer(me))
                return (t.id, t)
            })
        }
        s.things = things(greptile: 4)
        s.announceInbox()
        #expect(posted().isEmpty)
        // Away, six new: the five rated low wait (no batch of them), the urgent one comes on its own.
        idle.seconds = 900
        s.things = things(greptile: 3)
        s.announceInbox()
        #expect(posted() == [Store.inboxNotificationPrefix + "pr:a/one#6"])
        idle.seconds = 0
        s.routerAttention.refresh()
        #expect(s.routerAttention.strip?.line([]) == "5 in your inbox")
        // Here, more than four at once is one banner, as before.
        s.things = things(greptile: 2)
        s.announceInbox()
        #expect(posted().count == 3 && posted().last?.hasPrefix(Notifier.summaryPrefix) == true)
    }

    @Test func aTrivialTurnIsLeftOutOfWhatCameAndJevIsAskedInTheSameCall() async {
        let s = InboxFixture.store([])
        s.router.enabled = true
        s.routerTriager.rescanned = true
        s.claudeSessions = ["a": ClaudeSession(id: "a", title: "Typo", folder: "/code/a", completedTurns: 1, lastActivity: Date(), cliID: "cli-a")]
        s.router.cards = [RouterCard(id: "a#t1", sessionID: "a", kind: .done, title: "Typo", folder: "/code/a", text: "Fixed", createdAt: Date())]
        s.routerTriager.reader = { _ in "Fixed the typo." }
        s.routerTriager.earlier = { _ in [] }
        var calls = 0
        s.routerTriager.asker = { questions, _ in
            calls += 1
            #expect(questions["trivial"] != nil)
            return ["trivial": .noul(0.9)]
        }
        s.triageTurns()
        await s.routerTriager.idle()
        #expect(calls == 1 && s.router.cards[0].triage?.trivial == true && s.router.cards[0].kind == .done)
        var other = RouterCard(id: "b#t1", sessionID: "b", kind: .done, title: "B", folder: nil, text: "", createdAt: Date())
        other.triage = RouterTriage(state: .done)
        let strip = AwayStrip(since: Date(), cards: ["a#t1", "b#t1"])
        #expect(strip.line(s.router.cards + [other]) == "1 finished")
        #expect(AwayStrip(since: Date(), cards: ["a#t1"]).line(s.router.cards) == nil)
    }
}
