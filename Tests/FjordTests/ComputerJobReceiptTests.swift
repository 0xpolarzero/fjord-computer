import Testing
@testable import Fjord

@MainActor
@Suite struct ComputerJobReceiptTests {
    @Test func successfulJobIsRetainedUntilItsReceiptIsPresented() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)

        _ = await model.perform("Start", on: nil) {
            try await client.computersStart(ComputerReference(computerId: MockEngineClient.failedID))
        }

        #expect(client.acknowledgedJobs.isEmpty)
        let jobId = try #require(model.finishedJobs.keys.first)
        let receipt = try #require(model.currentJobReceipt)
        #expect(receipt.jobId == jobId)
        #expect(receipt.message == "Start completed.")
        await model.acknowledgePresentedJob(jobId)
        #expect(client.acknowledgedJobs == [jobId])
        #expect(model.finishedJobs[jobId] == nil)
    }

    @Test func failedStartShowsItsErrorInTheToastAndOnTheComputer() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        let target = GuestReference.thisMac(MockEngineClient.failedID)
        client.nextJobFailure = OperationJobError(code: "internal", message: "The runtime did not complete the operation")

        await model.start(target)

        let receipt = try #require(model.currentJobReceipt)
        #expect(receipt.message.hasPrefix("Start failed:"))
        #expect(receipt.tone == .danger)
        #expect(model.computerFailures[target.key]?.hasPrefix("Start failed:") == true)
        #expect(model.actionError?.hasPrefix("Start failed:") == true)

        await model.start(target)
        #expect(model.computerFailures[target.key] == nil)
    }

    @Test func chunkedOutcomeIsReadFromTheEngineBeforeDecidingSuccess() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        let target = GuestReference.thisMac(MockEngineClient.failedID)
        // The event says `outcomeChunked` and carries no error; the retained outcome is a failure.
        client.nextJobFailure = OperationJobError(code: "internal", message: "The runtime did not complete the operation")
        client.chunkNextFinishedEvent = true

        await model.start(target)

        #expect(client.jobGetCallCount > 0)
        let receipt = try #require(model.currentJobReceipt)
        #expect(receipt.message.hasPrefix("Start failed:"))
        #expect(receipt.tone == .danger)
    }

    @Test func chunkedOutcomeThatSucceededStillSucceeds() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        client.chunkNextFinishedEvent = true

        await model.start(GuestReference.thisMac(MockEngineClient.failedID))

        #expect(client.jobGetCallCount > 0)
        #expect(model.currentJobReceipt?.message == "Start completed.")
    }
}
