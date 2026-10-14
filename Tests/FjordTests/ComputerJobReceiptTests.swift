import Testing
@testable import Fjord

@MainActor
@Suite struct ComputerJobReceiptTests {
    @Test func successfulJobIsRetainedUntilItsReceiptIsPresented() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)

        _ = await model.perform("Start") {
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
}
