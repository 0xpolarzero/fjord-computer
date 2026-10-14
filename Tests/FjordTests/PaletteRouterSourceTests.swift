import Foundation
import Testing
@testable import Fjord

/// The palette's Router source: what it lists, in what order, and what each row does.
@MainActor
@Suite struct PaletteRouterSourceTests {
    /// The places the palette's actions went to.
    private final class Went {
        var places: [AppDestination] = []
    }

    @MainActor private struct Fixture {
        let store: Store
        let model: RouterModel
        let hub: HubState
        let went = Went()

        var context: PaletteContext {
            let went = went
            return PaletteContext(store: store, navigator: AppNavigator(start: .router, defaults: nil), routerModel: model, hub: hub,
                                  go: { went.places.append($0) })
        }
    }

    private func fixture() -> Fixture {
        let store = Store()
        Demo.populate(store, .router)
        store.interceptOpen = { _ in }
        return Fixture(store: store, model: RouterModel(), hub: HubState())
    }

    private func action(_ id: String, of item: PaletteItem) throws -> PaletteAction {
        try #require(item.actions.first { $0.id == id })
    }

    @Test func theRouterOffListsNothing() {
        let f = fixture()
        f.store.setRouterEnabled(false)
        #expect(!f.store.routerOn)
        let output = PaletteRouterSource.make(f.context)
        #expect(output.needsYou.isEmpty && output.items.isEmpty)
    }

    @Test func needsYouIsTheZonesCardsOldestFirstWithAttentionDots() throws {
        let f = fixture()
        let page = f.store.routerZones
        let expected = (page.needs + page.ready).sorted { $0.createdMs < $1.createdMs }
        try #require(!expected.isEmpty)
        let output = PaletteRouterSource.make(f.context)
        #expect(output.needsYou.map(\.id) == expected.map { "card:" + $0.id })
        #expect(output.needsYou.allSatisfy { $0.dot == .attention && $0.kind == .card && $0.weight == 1.3 })
        let dates = output.needsYou.compactMap(\.date)
        #expect(dates == dates.sorted())
        let first = try #require(output.needsYou.first)
        #expect(first.subtitle?.hasPrefix(expected[0].kind.label + " · ") == true)
        #expect(first.keywords.contains(expected[0].kind.label))
        // The needs-you items are in the searchable list too, and the other open cards besides.
        let ids = Set(output.items.map(\.id))
        #expect(output.needsYou.allSatisfy { ids.contains($0.id) })
        let others = page.notes + page.waiting
        #expect(others.allSatisfy { ids.contains("card:" + $0.id) })
        for card in others {
            let item = try #require(output.items.first { $0.id == "card:" + card.id })
            #expect(item.dot == nil || item.dot == .running)
            #expect(item.weight == 1.1)
        }
    }

    @Test func everySessionIsListedWithItsOwnWeightAndArchivedOnesLast() throws {
        let f = fixture()
        let archived = try #require(f.store.claudeSessions.values.first { !$0.isArchived && !$0.running })
        f.store.claudeSessions[archived.id]?.isArchived = true
        f.store.claudeSessions[archived.id]?.lastActivity = Date()
        let output = PaletteRouterSource.make(f.context)
        let sessions = output.items.filter { $0.kind == .session }
        #expect(sessions.count == f.store.claudeSessions.count)
        let item = try #require(sessions.first { $0.id == "session:" + archived.id })
        #expect(item.weight == 0.5)
        #expect(item.subtitle?.hasSuffix("Archived") == true)
        for session in f.store.claudeSessions.values where !session.isArchived {
            let item = try #require(sessions.first { $0.id == "session:" + session.id })
            let age = Date().timeIntervalSince(session.lastActivity)
            #expect(item.weight == (age < 86_400 ? 1.1 : age < 7 * 86_400 ? 1.0 : 0.8))
            #expect(item.date == session.lastActivity)
            #expect(item.title == session.title)
            if session.running {
                #expect(item.dot != nil)
                #expect(item.subtitle?.contains("Working") == true)
            }
        }
    }

    @Test func idsAreStableAndUnique() {
        let f = fixture()
        let first = PaletteRouterSource.make(f.context)
        let second = PaletteRouterSource.make(f.context)
        #expect(first.items.map(\.id) == second.items.map(\.id))
        #expect(Set(first.items.map(\.id)).count == first.items.count)
        #expect(first.items.allSatisfy { $0.id.hasPrefix("card:") || $0.id.hasPrefix("session:") })
        #expect(first.items.allSatisfy { !$0.actions.isEmpty })
    }

    @Test func aCardsFirstActionPicksItAndGoesToTheRouter() throws {
        let f = fixture()
        let output = PaletteRouterSource.make(f.context)
        let item = try #require(output.needsYou.first)
        let card = try #require(f.store.routerZones.needs.first { "card:" + $0.id == item.id }
            ?? f.store.routerZones.ready.first { "card:" + $0.id == item.id })
        let first = try #require(item.actions.first)
        #expect(first.title == "Show in Router")
        first.run()
        #expect(f.went.places == [.router])
        #expect(f.model.selection == card.id)
        #expect(item.actions.map(\.id).starts(with: ["show", "reply", "open"]))
        #expect(try action("archive", of: item).destructive)
        #expect(try action("reply", of: item).caps == ["↩"])
        // Archive takes the card off the open ones.
        try action("archive", of: item).run()
        #expect(f.store.router.cards.first { $0.id == card.id }?.isOpen == false)
    }

    @Test func replyArmsTheComposerOnTheCard() throws {
        let f = fixture()
        let item = try #require(PaletteRouterSource.make(f.context).needsYou.first)
        try action("reply", of: item).run()
        #expect(f.went.places == [.router])
        #expect(f.model.replyTo == f.model.selection)
        #expect(f.model.replyTo != nil)
    }

    @Test func aSessionWithoutACardIsShownThroughTheWorkingRow() throws {
        let f = fixture()
        let withCard = Set(f.store.routerZones.needs.map(\.sessionID) + f.store.routerZones.ready.map(\.sessionID)
                           + f.store.routerZones.notes.map(\.sessionID) + f.store.routerZones.waiting.map(\.sessionID))
        let working = try #require(f.store.routerZones.working.first { !withCard.contains($0.id) })
        let item = try #require(PaletteRouterSource.make(f.context).items.first { $0.id == "session:" + working.id })
        #expect(item.actions.first?.title == "Show in Router")
        #expect(item.actions.contains { $0.id == "summary" } == working.session.running)
        item.actions[0].run()
        #expect(f.went.places == [.router])
        #expect(f.model.revealRequest?.id == RouterModel.workingID(working.id))
        try action("ask", of: item).run()
        #expect(f.went.places == [.router, .router])
    }

    @Test func anUnlistedSessionOpensInClaudeFirst() throws {
        let f = fixture()
        let listed = Set(f.store.allAgentRows.map(\.id))
        let carded = Set(f.store.router.cards.map(\.sessionID))
        let unlisted = try #require(f.store.claudeSessions.values.first { !listed.contains($0.id) && !carded.contains($0.id) })
        let item = try #require(PaletteRouterSource.make(f.context).items.first { $0.id == "session:" + unlisted.id })
        #expect(item.actions.first?.id == "open")
    }

    @Test func aSessionWithACardSelectsItsCard() throws {
        let f = fixture()
        let card = try #require(f.store.routerZones.needs.first)
        let item = try #require(PaletteRouterSource.make(f.context).items.first { $0.id == "session:" + card.sessionID })
        item.actions[0].run()
        #expect(f.model.selection == card.id)
        #expect(f.went.places == [.router])
    }

    @Test func sendIsNilWhenBlankOrTheRouterCannotSend() throws {
        let f = fixture()
        #expect(PaletteRouterSource.send("", f.context) == nil)
        #expect(PaletteRouterSource.send("  \n ", f.context) == nil)
        let item = try #require(PaletteRouterSource.send("  what is blocked? ", f.context))
        #expect(item.id == "send:router" && item.kind == .send)
        #expect(item.title == "Send to the Router")
        #expect(item.subtitle == "“what is blocked?”")
        f.model.claudeCodeMissing = true
        #expect(PaletteRouterSource.send("what is blocked?", f.context) == nil)
        f.model.claudeCodeMissing = false
        f.store.setRouterEnabled(false)
        #expect(PaletteRouterSource.send("what is blocked?", f.context) == nil)
    }

    @Test func sendTruncatesALongQueryAndSendsItAndGoesToTheRouter() throws {
        let f = fixture()
        let long = String(repeating: "word ", count: 60)
        let item = try #require(PaletteRouterSource.send(long, f.context))
        #expect((item.subtitle ?? "").count < 90)
        let before = f.store.router.cards.count
        item.actions[0].run()
        #expect(f.went.places == [.router])
        #expect(f.store.router.cards.count >= before)
    }

    @Test func aLedgerRunLinkingASessionAddsThePRActionAndKeywords() throws {
        let f = fixture()
        let thing = try #require(f.store.entries.first { !$0.isDone && $0.thing.kind == .pr }?.thing)
        let entry = try #require(f.store.entries.first { $0.id == thing.id })
        let session = try #require(f.store.claudeSessions.values.first)
        var run = ActionRun(category: entry.categoryID, thing: thing.id, action: UUID(), trigger: "enter", state: .done, at: Date())
        run.sessionID = session.id
        f.store.actionLedger.set(run)
        let item = try #require(PaletteRouterSource.make(f.context).items.first { $0.id == "session:" + session.id })
        let link = try action("thing", of: item)
        #expect(link.title == "Open the PR")
        let number = try #require(thing.number)
        #expect(item.keywords.contains("#\(number)"))
        #expect(item.keywords.contains("\(thing.repo)#\(number)"))
        // Shown in the window on its category.
        link.run()
        #expect(f.hub.selection == "i:" + thing.id)
        let shown = f.store.triageOn && f.store.categories.first { $0.id == entry.categoryID }?.hidden == false
        #expect(f.went.places == (shown ? [.category(entry.categoryID)] : []))
        // A session without a run has no such action.
        let other = try #require(PaletteRouterSource.make(f.context).items.first { $0.kind == .session && $0.id != item.id })
        #expect(!other.actions.contains { $0.id == "thing" })
    }

    @Test func aWaitingCardWatchingCIOffersItsWorkflowOrPR() throws {
        let f = fixture()
        Demo.routerTriage(f.store)
        let card = try #require(f.store.router.cards.first {
            if case .ci? = $0.triage?.watch?.target { return $0.isOpen } else { return false }
        })
        guard case .ci(let id)? = card.triage?.watch?.target else { return }
        var thing = Thing(id: id, kind: .pr, repo: "me/lookout", number: 212, title: "A PR", url: URL(string: "https://github.com/me/lookout/pull/212")!,
                          createdAt: Date(), updatedAt: Date())
        thing.checks = .pending
        f.store.things[id] = thing
        let output = PaletteRouterSource.make(f.context)
        let item = try #require(output.items.first { $0.id == "card:" + card.id })
        #expect(try action("thing", of: item).title == "Open the PR")
        #expect(item.keywords.contains("#212"))
        let session = try #require(output.items.first { $0.id == "session:" + card.sessionID })
        #expect(session.actions.contains { $0.id == "thing" })
        #expect(session.keywords.contains("me/lookout#212"))
    }

    @Test func aFewThousandSessionsAreMadeQuickly() {
        let f = fixture()
        for n in 0..<3000 {
            f.store.claudeSessions["perf-\(n)"] = ClaudeSession(id: "perf-\(n)", title: "Session \(n)", folder: "/code/p\(n % 40)",
                                                                lastActivity: Date().addingTimeInterval(-Double(n) * 600), cliID: "cli-\(n)")
        }
        let start = ContinuousClock.now
        let output = PaletteRouterSource.make(f.context)
        let took = ContinuousClock.now - start
        #expect(output.items.count >= 3000)
        // Generous: a debug build, on a busy machine.
        #expect(took < .milliseconds(250))
    }
}
