import Testing
@testable import Fjord

@MainActor
@Suite struct ComputersTests {
    @Test func quitPromptNamesOnlyRunningComputers() throws {
        let prompt = try #require(ComputerQuitPrompt.make(inventory: MockEngineClient.demoInventory))
        #expect(prompt.runningComputers.map(\.name) == ["dev", "linux-1"])
        #expect(prompt.message == "Quit Fjord? 2 computers are running: dev, linux-1.")
    }

    @Test func noPromptWhenEveryComputerIsStopped() throws {
        var inventory = MockEngineClient.demoInventory
        inventory.linux.computers = inventory.linux.computers.map { row in
            var row = row
            row.state = .stopped
            row.stateDetail = "Stopped"
            return row
        }
        inventory.macos.computers = inventory.macos.computers.map { row in
            var row = row
            row.state = .stopped
            return row
        }
        #expect(ComputerQuitPrompt.make(inventory: inventory) == nil)
    }

    @Test func normalQuitSkipsComputerInspectionWhenComputersAreOffOrEngineIsAbsent() {
        #expect(!AppTermination.shouldInspectComputers(computersEnabled: false, engineAvailable: true))
        #expect(!AppTermination.shouldInspectComputers(computersEnabled: true, engineAvailable: false))
        #expect(AppTermination.shouldInspectComputers(computersEnabled: true, engineAvailable: true))
    }

    @Test func cancelLeavesEngineConnectedAndDoesNotStopComputers() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client)
        let prompt = try #require(ComputerQuitPrompt.make(inventory: client.inventory))
        try await model.resolveQuit(.cancel, prompt: prompt)
        #expect(!client.disconnected)
        #expect(client.stopRequests.isEmpty)
    }

    @Test func keepRunningDisconnectsOnlyTheClient() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client)
        let prompt = try #require(ComputerQuitPrompt.make(inventory: client.inventory))
        try await model.resolveQuit(.keepRunning, prompt: prompt)
        #expect(client.disconnected)
        #expect(client.stopRequests.isEmpty)
    }

    @Test func stopAndQuitWaitsForRunningComputersToStop() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client)
        try await model.connect()
        let inventory = try await client.computersList(deviceId: nil)
        let prompt = try #require(ComputerQuitPrompt.make(inventory: inventory))
        try await model.resolveQuit(.stopAndQuit, prompt: prompt)
        #expect(Set(client.stopRequests) == Set(prompt.runningComputers.map(\.computerId)))
        #expect(client.disconnected)
        #expect(prompt.runningComputers.allSatisfy { model.inventory?.computer($0.computerId)?.displayState == .stopped })
    }

    @Test func stateMappingCoversLinuxAndMacOSStates() throws {
        let inventory = MockEngineClient.demoInventory
        #expect(try #require(inventory.computer(MockEngineClient.linuxID)).displayState == .running)
        #expect(try #require(inventory.computer(MockEngineClient.failedID)).displayState == .failed)
        #expect(try #require(inventory.computer(MockEngineClient.startingID)).displayState == .starting)

        var linuxStopping = try #require(inventory.linux.computers.first { $0.id == MockEngineClient.linuxID })
        linuxStopping.state = .starting
        linuxStopping.stateDetail = "Stopping"
        #expect(ComputerRow.linux(linuxStopping).displayState == .stopping)
    }
}
