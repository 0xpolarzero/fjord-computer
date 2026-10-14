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

    @Test func acceptedJobFailureIsShownBeforeItIsAcknowledged() async throws {
        let client = MockEngineClient()
        client.nextJobFailure = OperationJobError(code: "internal", message: "disk image could not be opened")
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        try await model.connect()

        await model.start(MockEngineClient.failedID)

        #expect(model.actionError == "Start failed: disk image could not be opened")
        let jobId = try #require(model.jobAwaitingAcknowledgement)
        #expect(client.acknowledgedJobs.isEmpty)
        await model.acknowledgePresentedJob(jobId)
        #expect(client.acknowledgedJobs == [jobId])
        #expect(model.jobAwaitingAcknowledgement == nil)
    }

    @Test func staleComputerListResponseCannotReplaceANewerEvent() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        try await model.connect()

        var staleLinux = client.inventory.linux
        let computerID = try #require(staleLinux.computers.first?.id)
        staleLinux.computers[0].state = .stopped
        staleLinux.computers[0].stateDetail = "Stopped"
        client.inventory.linux = staleLinux
        client.suspendNextComputersList = true
        let refresh = Task { try await model.refresh() }
        await client.waitForSuspendedComputersList()

        var newerLinux = staleLinux
        newerLinux.computers[0].state = .running
        newerLinux.computers[0].stateDetail = "Running"
        client.deliver(.event(sequence: 2, event: .computersChanged(ComputersChangedPayload(linux: newerLinux))))
        client.resumeSuspendedComputersList()
        try await refresh.value

        #expect(model.inventory?.linux == newerLinux)
        #expect(model.inventory?.computer(computerID)?.displayState == .running)
    }

    @Test func sequenceGapAndReconnectReReadComputerAndOperationState() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        try await model.connect()
        let initialReads = client.computersListCallCount

        var afterGap = client.inventory
        afterGap.linux.computers.removeAll()
        client.inventory = afterGap
        client.deliver(.event(sequence: 3, event: .operationsQueueChanged(.empty)))
        await model.waitForRecovery()
        #expect(client.computersListCallCount > initialReads)
        #expect(model.inventory?.linux.computers.isEmpty == true)

        var afterReconnect = client.inventory
        afterReconnect.macos.computers.removeAll()
        client.inventory = afterReconnect
        let readsBeforeReconnect = client.computersListCallCount
        client.deliver(.reconnected)
        await model.waitForRecovery()
        #expect(client.computersListCallCount > readsBeforeReconnect)
        #expect(model.inventory?.macos.computers.isEmpty == true)
    }

    @Test func retainedJobOutcomeIsRecoveredThroughJobGet() async throws {
        let client = MockEngineClient()
        client.retainFinishedJob(OperationJobFinished(jobId: "retained:failed",
                                                       error: OperationJobError(code: "internal", message: "recovered failure")))
        let model = ComputersModel(client: client, initialInventory: client.inventory)

        try await model.connect()

        #expect(client.jobGetCallCount == 1)
        #expect(model.finishedJobs["retained:failed"]?.error?.message == "recovered failure")
        #expect(model.actionError == "Computer operation failed: recovered failure")
        #expect(model.jobAwaitingAcknowledgement == "retained:failed")
    }

    @Test func jobGetRecoversACompletionWhenTheFinishedEventIsLost() async throws {
        let client = MockEngineClient()
        client.nextJobFailure = OperationJobError(code: "internal", message: "completion event was lost")
        client.dropNextFinishedEvent = true
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        try await model.connect()

        await model.start(MockEngineClient.failedID)

        #expect(client.jobGetCallCount > 1)
        #expect(model.actionError == "Start failed: completion event was lost")
        #expect(model.jobAwaitingAcknowledgement != nil)
    }

    @Test func waitingQueueEntryRendersWithoutProgressAndCanBeCancelled() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        try await model.connect()
        let entry = OperationQueueEntry(id: 42, jobId: "job:queued-macos", label: "Create macOS computer",
                                        kind: "computerConfiguration", computerId: MockEngineClient.devID,
                                        computerName: "dev", sinceMs: 1, cancellable: true, blockedByHidden: false)
        let queue = OperationsList(running: [], waiting: [entry], unacknowledgedJobIds: [])

        client.publishOperationQueueChange(queue)

        #expect(model.operationQueue.waiting == [entry])
        #expect(model.activeJob?.jobId != entry.jobId)
        await model.cancelJob("job:queued-macos")

        #expect(client.cancelRequests == ["job:queued-macos"])
        #expect(model.operationQueue.waiting.isEmpty)
        #expect(model.actionError == nil)
        #expect(model.finishedJobs["job:queued-macos"]?.error?.code == "cancelled")
    }

    @Test func completedCheckpointJobsApplyDelayedCheckpointEvents() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        try await model.connect()
        let linuxID = MockEngineClient.failedID

        await model.createCheckpoint(for: linuxID)
        var checkpoints = try #require(model.inventory?.computer(linuxID)?.checkpoints)
        #expect(checkpoints.count == 1)
        let checkpointID = try #require(checkpoints.first?.id)
        #expect(model.checkpointUsage[linuxID]?.checkpoints.map(\.id) == [checkpointID])

        await model.restoreCheckpoint(checkpointID, computerId: linuxID)
        guard case .linux(let restored)? = model.inventory?.computer(linuxID) else {
            Issue.record("The Linux computer should remain in the inventory after restore.")
            return
        }
        #expect(restored.pendingCheckpointRestore?.checkpointId == checkpointID)

        await model.forkCheckpoint(checkpointID, computerId: linuxID, computerName: "linux-source")
        #expect(model.inventory?.allComputers.contains(where: { $0.name == "linux-source-fork" }) == true)

        await model.deleteCheckpoint(checkpointID, computerId: linuxID)
        checkpoints = try #require(model.inventory?.computer(linuxID)?.checkpoints)
        #expect(checkpoints.isEmpty)
        #expect(model.checkpointUsage[linuxID]?.checkpoints.isEmpty == true)
        #expect(client.checkpointListCallCount == 0)
    }

    @Test func setupProgressDecodesEveryCanonicalFieldAndDrivesPresentation() throws {
        let fixture = Data("""
        {
          "jobId":"setup:linux-setup-1",
          "kind":"computerConfiguration",
          "computerId":"computer-1",
          "source":"setup",
          "data":{
            "schemaVersion":1,"type":"computer-configuration","requestId":"linux-setup-1",
            "phase":"computer-configuration","step":"download-image","computer":"devbox",
            "fraction":0.625,"message":"Downloading the runtime image","safeForDisplay":true,
            "timestamp":"2026-10-14T10:00:00Z","level":"warning","elapsedSeconds":12.5,
            "downloadedBytes":640,"totalBytes":1024,"failureCode":"network","exitCode":7,
            "diagnostic":"connection dropped","partial":true
          }
        }
        """.utf8)
        let progress = try JSONDecoder().decode(OperationJobProgress.self, from: fixture)
        guard case .setup(let setup) = progress.data else {
            Issue.record("Setup source must decode to its own progress type.")
            return
        }

        #expect(setup.schemaVersion == 1)
        #expect(setup.type == "computer-configuration")
        #expect(setup.requestId == "linux-setup-1")
        #expect(setup.phase == "computer-configuration")
        #expect(setup.step == "download-image")
        #expect(setup.computer == "devbox")
        #expect(setup.fraction == 0.625)
        #expect(setup.message == "Downloading the runtime image")
        #expect(setup.safeForDisplay)
        #expect(setup.timestamp == "2026-10-14T10:00:00Z")
        #expect(setup.level == "warning")
        #expect(setup.elapsedSeconds == 12.5)
        #expect(setup.downloadedBytes == 640)
        #expect(setup.totalBytes == 1024)
        #expect(setup.failureCode == "network")
        #expect(setup.exitCode == 7)
        #expect(setup.diagnostic == "connection dropped")
        #expect(setup.partial)
        #expect(progress.data.presentationProgress == 0.625)
        #expect(progress.data.presentationTitle == "Downloading the runtime image")

        let encoded = try JSONEncoder().encode(progress)
        #expect(try JSONDecoder().decode(OperationJobProgress.self, from: encoded) == progress)

        let lifecycle = try JSONDecoder().decode(OperationJobProgress.self, from: Data("""
        {"jobId":"job:lifecycle-1","source":"lifecycle","data":{"computerId":"computer-1","action":"start","step":"network"}}
        """.utf8))
        guard case .lifecycle(let lifecycleData) = lifecycle.data else {
            Issue.record("Lifecycle source must decode to its own progress type.")
            return
        }
        #expect(lifecycleData == LifecycleJobProgressData(computerId: "computer-1", action: "start", step: "network"))

        let macos = try JSONDecoder().decode(OperationJobProgress.self, from: Data("""
        {"jobId":"job:macos-1","source":"macos","data":{"computerId":"computer-2","state":"running","progress":0.75,"detail":"Booting","checkpointOperation":{"kind":"capture","status":"running","stage":"Saving memory"}}}
        """.utf8))
        guard case .macos(let macosData) = macos.data else {
            Issue.record("macOS source must decode to its own progress type.")
            return
        }
        #expect(macosData.computerId == "computer-2")
        #expect(macosData.state == "running")
        #expect(macosData.progress == 0.75)
        #expect(macosData.detail == "Booting")
        #expect(macosData.checkpointOperation?.stage == "Saving memory")
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
