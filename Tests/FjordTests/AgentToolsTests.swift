import Foundation
import Testing
@testable import Fjord

@MainActor
@Suite(.serialized, .ownGuestRuntime) struct AgentToolsTests {
    private let computerID = MockEngineClient.linuxID
    private var target: GuestReference { GuestReference(deviceId: nil, computerId: computerID) }

    private func engine(_ state: SiloWireAgentToolsState) -> MockEngineClient {
        let engine = MockEngineClient()
        engine.mockAgentTools[computerID] = MockEngineClient.agentTools(state)
        return engine
    }

    @Test func statusWordsNameTheMissingToolsAndTheButton() {
        let missing = MockEngineClient.agentTools(.missing)
        #expect(AgentToolsAdvice.actionTitle(missing) == "Set up")
        #expect(AgentToolsAdvice.detail(missing) == "Node.js and Claude Code aren't installed in this computer.")
        let outdated = MockEngineClient.agentTools(.outdated)
        #expect(AgentToolsAdvice.actionTitle(outdated) == "Update")
        #expect(AgentToolsAdvice.headline(outdated) == "Update available")
        #expect(AgentToolsAdvice.detail(outdated).contains("Node.js 24.18.0"))
        #expect(!AgentToolsAdvice.needsSetup(MockEngineClient.readyAgentTools))
        var onlyClaude = missing
        onlyClaude.missing = ["claude"]
        #expect(AgentToolsAdvice.detail(onlyClaude) == "Claude Code isn't installed in this computer.")
    }

    @Test func computersShowsTheStatusAndSetUpRunsTheActionAsAJob() async {
        let engine = engine(.missing)
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        await model.loadAgentTools(target)
        #expect(model.agentTools(for: target)?.state == .missing)

        await model.setUpAgentTools(target, computerName: "linux-1")
        #expect(engine.agentToolsSetupRequests == [computerID])
        #expect(model.agentTools(for: target)?.state == .ready)
        #expect(model.agentToolsSetupMessage[target.key] == nil)
        #expect(model.agentToolsError[target.key] == nil)
    }

    @Test func updateRunsTheSameActionForOutdatedTools() async {
        let engine = engine(.outdated)
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        await model.loadAgentTools(target)
        #expect(model.agentTools(for: target).map(AgentToolsAdvice.actionTitle) == "Update")
        await model.setUpAgentTools(target, computerName: "linux-1")
        #expect(model.agentTools(for: target)?.state == .ready)
    }

    @Test func aFailedSetupKeepsTheStatusAndSaysWhy() async {
        let engine = engine(.missing)
        engine.nextJobFailure = OperationJobError(code: "internal", message: "download failed")
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        await model.loadAgentTools(target)
        await model.setUpAgentTools(target, computerName: "linux-1")
        #expect(model.agentTools(for: target)?.state == .missing)
        #expect(model.agentToolsError[target.key]?.contains("download failed") == true)
    }

    @Test func readyToolsPassTheGateWithoutASetupJob() async throws {
        let engine = engine(.ready)
        var messages: [String] = []
        try await AgentToolsSetup(engine: engine).ensureReady(target, kind: .linux, computerName: "linux-1") { messages.append($0) }
        #expect(engine.agentToolsSetupRequests.isEmpty)
        #expect(messages.isEmpty)
    }

    @Test func missingToolsAreSetUpFirstWithProgress() async throws {
        let engine = engine(.missing)
        var messages: [String] = []
        try await AgentToolsSetup(engine: engine).ensureReady(target, kind: .linux, computerName: "linux-1") { messages.append($0) }
        #expect(engine.agentToolsSetupRequests == [computerID])
        #expect(messages.first == "Setting up Node.js and Claude Code in linux-1")
        #expect(try await AgentToolsSetup(engine: engine).status(target)?.state == .ready)
    }

    @Test func aMacComputerIsRefusedWithTheWayForwardNotSetUp() async {
        let engine = engine(.missing)
        do {
            try await AgentToolsSetup(engine: engine).ensureReady(target, kind: .macos, computerName: "dev")
            Issue.record("a Mac computer without agent tools passed the gate")
        } catch {
            #expect(error as? AgentToolsFailure == .macOSNeedsSetup("dev"))
        }
        #expect(engine.agentToolsSetupRequests.isEmpty)
    }

    @Test func routerSessionStartSetsToolsUpThroughTheComputersModel() async throws {
        let engine = engine(.outdated)
        let model = ComputersModel(client: engine, initialInventory: engine.inventory)
        try await model.ensureAgentTools(target, kind: .linux, computerName: "linux-1")
        #expect(engine.agentToolsSetupRequests == [computerID])
        #expect(model.agentTools(for: target)?.state == .ready)
        #expect(model.agentToolsSetupMessage[target.key] == nil)

        let mac = engine
        mac.mockAgentTools[computerID] = MockEngineClient.agentTools(.missing)
        await #expect(throws: AgentToolsFailure.macOSNeedsSetup("dev")) {
            try await model.ensureAgentTools(target, kind: .macos, computerName: "dev")
        }
    }

    @Test func credentialAccessDeniedHasAClearMessage() {
        let expected = "After this update, Silo's engine needs your permission to use its saved credentials. Use Allow access on the Computers page or in Settings."
        #expect(EngineErrorText.message(code: "credential_access_denied", fallback: "internal") == expected)
        #expect(OperationJobError(code: "credential_access_denied", message: "x").userMessage == expected)
        #expect(EngineClientError.coded(code: "credential_access_denied", message: "x").errorDescription == expected)
        #expect(EngineErrorText.known.contains("credential_access_denied"))
        #expect(SiloWireErrorCode.credentialAccessDenied.rawValue == "credential_access_denied")
    }
}
