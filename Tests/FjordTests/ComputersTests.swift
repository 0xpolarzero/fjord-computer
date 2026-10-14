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

    @Test func platformOnlyComputerEventsMergeWithoutReplacingOtherPlatform() throws {
        let original = MockEngineClient.demoInventory
        let linuxJSON = Data("""
        {"linux":{"computers":[]}}
        """.utf8)
        let linuxChange = try JSONDecoder().decode(ComputersChangedPayload.self, from: linuxJSON)
        let linuxMerged = original.applying(linuxChange)
        #expect(linuxMerged.linux.computers.isEmpty)
        #expect(linuxMerged.macos == original.macos)

        var macosState = original.macos
        macosState.computers = []
        let macosJSON = try JSONEncoder().encode(ComputersChangedPayload(macos: macosState))
        let macosChange = try JSONDecoder().decode(ComputersChangedPayload.self, from: macosJSON)
        let macosMerged = original.applying(macosChange)
        #expect(macosMerged.macos.computers.isEmpty)
        #expect(macosMerged.linux == original.linux)
    }

    @Test func linuxDeleteCarriesAndEnforcesExpectedConfiguration() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        let configuration = try #require(client.inventory.linux.computers.first { $0.id == MockEngineClient.failedID }?.configuration)

        await model.delete(MockEngineClient.failedID)
        #expect(client.deleteRequests.first?.expected == configuration)
        #expect(model.actionError == nil)

        do {
            _ = try await client.computersDelete(ComputerDeleteRequest(computerId: MockEngineClient.failedID))
            Issue.record("The mock must reject a Linux delete without expected configuration.")
        } catch {
            #expect(error.localizedDescription.contains("expected configuration"))
        }
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

    @Test func refusedMacosStopRestoresQuitChoicesAfterJobSuccess() async throws {
        var inventory = MockEngineClient.demoInventory
        inventory.linux.computers = inventory.linux.computers.map { row in
            var row = row
            row.state = .stopped
            row.stateDetail = "Stopped"
            return row
        }
        let client = MockEngineClient(inventory: inventory)
        client.stopRefusalIDs = [MockEngineClient.devID]
        let model = ComputersModel(client: client, initialInventory: inventory)
        let prompt = try #require(ComputerQuitPrompt.make(inventory: inventory))
        try await model.connect()
        model.presentQuitPrompt(prompt)
        model.chooseQuit(.stopAndQuit)
        try await Task.sleep(for: .milliseconds(1_200))
        #expect(model.quitError?.contains("refused") == true)
        #expect(!model.isQuitWorking)
        #expect(model.quitPrompt != nil)
    }

    @Test func quitStopWaitHasABoundedDeadline() async throws {
        var inventory = MockEngineClient.demoInventory
        inventory.linux.computers = []
        inventory.macos.computers[0].state = .stopping
        let client = MockEngineClient(inventory: inventory)
        let model = ComputersModel(client: client, initialInventory: inventory)

        do {
            try await model.waitUntilStopped([MockEngineClient.devID], timeout: .milliseconds(30))
            Issue.record("A computer that remains stopping must time out.")
        } catch {
            #expect(error.localizedDescription.contains("deadline"))
        }
    }

    @Test func overlappingActivationsAndTeardownLeaveNoLateSubscription() async {
        let client = MockEngineClient()
        client.suspendNextSubscription = true
        let model = ComputersModel(client: client)
        let listActivation = Task { await model.activate() }
        await client.waitForSuspendedSubscription()
        let detailActivation = Task { await model.activate() }
        await Task.yield()
        await model.deactivate()
        client.resumeSuspendedSubscription()
        await listActivation.value
        await detailActivation.value

        #expect(client.subscribeCallCount == 1)
        #expect(client.activeSubscriptionCount == 0)
        #expect(client.unsubscribeCallCount == 1)
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
