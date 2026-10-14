import Testing
@testable import Fjord

@MainActor
@Suite struct ComputerJobOutcomeTests {
    @Test func uploadConflictOutcomeIsPresentedWithConflictingNames() {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        let outcome = OperationJobFinished(jobId: "transfer:conflict",
            result: .object(["status": .string("conflict"), "names": .array([.string("notes.txt")])]))

        model.presentJobOutcome(outcome, action: "Upload files")

        #expect(model.actionError?.contains("notes.txt") == true)
    }

    @Test func uploadDataCancellationIsPresentedAsCancelled() {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        let outcome = OperationJobFinished(jobId: "transfer:cancelled",
            result: .object(["status": .string("cancelled")]))

        model.presentJobOutcome(outcome, action: "Upload files")

        #expect(model.actionError?.localizedCaseInsensitiveContains("cancelled") == true)
    }

    @Test func uploadConflictOffersKeepBothWithTheOriginalSelection() async throws {
        let client = MockEngineClient()
        client.nextUploadOutcome = SiloWireUploadOutcome(names: ["notes.txt"], status: .conflict)
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        let paths = ["/tmp/notes.txt"]

        await model.uploadFiles(computerId: MockEngineClient.linuxID, directory: "/workspace", paths: paths)

        let conflict = try #require(model.pendingUploadConflict)
        #expect(conflict.names == ["notes.txt"])
        #expect(client.uploadRequests.count == 1)
        #expect(client.uploadRequests[0].conflict == .ask)
        #expect(client.uploadRequests[0].paths == paths)
        #expect(client.acknowledgedJobs.isEmpty)

        await model.resolveUploadConflict(jobId: conflict.jobId, policy: .keepBoth)

        #expect(client.uploadRequests.count == 2)
        #expect(client.uploadRequests[1].computerId == MockEngineClient.linuxID)
        #expect(client.uploadRequests[1].directory == "/workspace")
        #expect(client.uploadRequests[1].paths == paths)
        #expect(client.uploadRequests[1].conflict == .keepBoth)
        #expect(client.acknowledgedJobs.first == conflict.jobId)
    }

}
