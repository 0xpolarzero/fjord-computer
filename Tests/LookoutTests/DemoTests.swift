import Foundation
import Testing
@testable import Lookout

@MainActor
@Suite struct DemoScenarios {
    private func populated(_ scenario: Demo.Scenario) -> Store {
        let store = Store()
        Demo.populate(store, scenario)
        return store
    }

    @Test func everyScenarioFillsAStoreThatSavesNothing() {
        for scenario in Demo.Scenario.allCases {
            let store = populated(scenario)
            #expect(!store.persists, "\(scenario)")
        }
    }

    @Test func theDemoFlagTakesEachScenarioByItsName() {
        #expect(Set(Demo.Scenario.allCases.map(\.rawValue)).count == Demo.Scenario.allCases.count)
        for scenario in Demo.Scenario.allCases { #expect(Demo.Scenario(rawValue: scenario.rawValue) == scenario) }
    }

    private func open(_ store: Store, _ name: String) -> [InboxEntry] {
        guard let category = store.categories.first(where: { $0.name == name }) else { return [] }
        return store.entries(in: category.id)
    }

    @Test func theCausesThatEmptyAListLeaveItEmptyAndTheRestFull() {
        let store = populated(.signedOut)
        #expect(store.me == nil && store.authError != nil && store.lastSync == nil)
        #expect(populated(.inboxFailed).inboxError != nil)
        #expect(populated(.rateLimited).rateRemaining == 0)
        let first = populated(.firstSync)
        #expect(first.isSyncing && first.things.isEmpty)
        #expect(populated(.empty).things.isEmpty)
        let bots = populated(.botChatterEmpty)
        #expect(open(bots, "Bot chatter").isEmpty && !open(bots, "Contributions").isEmpty)
        #expect(populated(.doneEmpty).doneEntries.isEmpty && !populated(.busy).doneEntries.isEmpty)
        let caught = populated(.contributionsEmpty)
        #expect(open(caught, "Contributions").isEmpty && open(caught, "Reviews for you").isEmpty && !open(caught, "Bot chatter").isEmpty)
        #expect(populated(.error).inboxError == nil && populated(.error).rateRemaining == 312)
        #expect(populated(.hiddenCategory).categories.contains { $0.hidden })
    }

    @Test func ciScenariosHoldWhatTheirNamesSay() {
        func workflows(_ store: Store) -> [Thing] { store.things.values.filter { $0.kind == .workflow } }
        #expect(workflows(populated(.noCI)).isEmpty)
        #expect(workflows(populated(.allPassing)).allSatisfy { $0.checks == .passing })
        let many = populated(.manyCI)
        let ci = many.categories.first { $0.isCI }!
        #expect(workflows(many).count == 15 && many.count(ci.id) == 9)
        #expect(workflows(many).filter { $0.checks == .pending }.count == 2)
        let running = workflows(populated(.ciRunning))
        #expect(running.contains { $0.checks == .pending } && !running.contains { $0.checks == .failing })
    }

    @Test func sessionScenariosHoldWhatTheirNamesSay() {
        #expect(populated(.sessionsNone).claudeSessions.isEmpty)
        #expect(populated(.sessions12).claudeSessions.count == 12)
        let waiting = populated(.sessionsWaiting10)
        #expect(waiting.claudeSessions.values.filter { $0.summary?.blocked == true }.count == 10)
        let many = populated(.sessionsManyNew)
        #expect(many.agents.entries.filter { !$0.kept }.count == 11)
        #expect(populated(.sessionsNewActivity).agents.entries.contains { !$0.kept })
    }

    @Test func theUpdateScenariosPutTheUpdaterInEachPhase() {
        #expect(populated(.updateAvailable).updater.phase == .available)
        let downloading = populated(.updateDownloading).updater
        #expect(downloading.phase == .downloading && downloading.fraction == 0.42)
        #expect(populated(.updateReady).updater.phase == .ready)
    }
}
