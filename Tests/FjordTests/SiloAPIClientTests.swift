import Foundation
import Testing
@testable import Fjord

@MainActor
@Suite struct SiloAPIClientTests {
    @Test func checkedInSchemaFixturesDecodeWithGeneratedCodableTypes() throws {
        let inventory = try JSONDecoder().decode(SiloWireComputersListResult.self, from: fixture("computers-list.json"))
        #expect(inventory.linux.computers.isEmpty)
        #expect(inventory.macos.supported)
        #expect(inventory.macos.minDiskGiB == 64)

        let handshake = try JSONDecoder().decode(SiloWireHandshakeResult.self, from: fixture("handshake-result.json"))
        #expect(handshake.handshakeResultProtocol == 1)
        #expect(handshake.capabilities.contains("operations.*"))

        let progress = try JSONDecoder().decode(SiloWireJobProgress.self, from: fixture("job-progress.json"))
        #expect(progress.source == .lifecycle)
        #expect(progress.data.computerId == "computer-1")
        #expect(progress.data.step == "network")

        let event = try JSONDecoder().decode(SiloWireEventEnvelope.self, from: fixture("job-progress-event.json"))
        #expect(event.event == .operationsJobProgress)
        #expect(event.seq == 7)
        #expect(event.subscription == "sub-1")

        let finished = try JSONDecoder().decode(SiloWireJobFinished.self, from: fixture("job-finished.json"))
        #expect(finished.jobId == "job:lifecycle-1")
        #expect(finished.result != nil)
    }

    @Test func unixSocketHandshakesCorrelatesRequestsAndResyncsEventGaps() async throws {
        let server = try FakeSiloUnixServer()
        defer { server.stop() }
        let deliveries = SocketDeliveryRecorder()
        let client = SocketEngineClient(path: server.path, protocolRange: SiloWireProtocolRange(min: 1, max: 2))

        let subscription = try await client.eventsSubscribe(events: ["computers.*", "operations.*"]) { delivery in
            deliveries.append(delivery)
        }
        await deliveries.waitForCount(3)
        #expect(subscription != "sub-1")
        #expect(deliveries.values.count == 3)
        guard case .event(let progressSequence, .jobProgress(let progress)) = deliveries.values[0] else {
            Issue.record("The fake server's first event must decode as job progress.")
            return
        }
        #expect(progressSequence == 1)
        #expect(progress.source == .lifecycle)
        guard case .event(let finishedSequence, .jobFinished(let finished)) = deliveries.values[1] else {
            Issue.record("The fake server's second event must decode as job finished.")
            return
        }
        #expect(finishedSequence == 2)
        #expect(finished.jobId == "job:fake")
        #expect(deliveries.values[2] == .reconnected)

        async let firstSnapshot = client.operationsJobGet(jobId: "job:first", deviceId: nil)
        async let secondSnapshot = client.operationsJobGet(jobId: "job:second", deviceId: nil)
        let snapshots = try await [firstSnapshot, secondSnapshot]
        #expect(snapshots.map(\.jobId) == ["job:first", "job:second"])
        #expect(snapshots.allSatisfy { $0.state == .finished && $0.outcome?.result != nil })
        try await client.operationsJobAcknowledge(jobId: "job:first", deviceId: nil)
        await client.eventsUnsubscribe(subscription: subscription)
        try await client.engineDisconnect()

        let requests = await server.requestLog.requests
        #expect(requests.map(\.method) == ["engine.handshake", "events.subscribe", "operations.job.get", "operations.job.get",
                                            "operations.job.acknowledge", "events.unsubscribe", "engine.disconnect"])
        #expect(Set(requests.map(\.id)).count == requests.count)
        #expect(requests.first?.protocolMin == 1)
        #expect(requests.first?.protocolMax == 2)
        #expect(Set(requests.filter { $0.method == "operations.job.get" }.compactMap(\.jobId)) == ["job:first", "job:second"])
        #expect(requests.first(where: { $0.method == "operations.job.acknowledge" })?.jobId == "job:first")
    }

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SiloAPI/\(name)")
        return try Data(contentsOf: url)
    }
}

@MainActor
private final class SocketDeliveryRecorder {
    private(set) var values: [EngineEventDelivery] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func append(_ delivery: EngineEventDelivery) {
        values.append(delivery)
        let ready = waiters.filter { $0.0 <= values.count }
        waiters.removeAll { $0.0 <= values.count }
        ready.forEach { $0.1.resume() }
    }

    func waitForCount(_ count: Int) async {
        if values.count >= count { return }
        await withCheckedContinuation { continuation in waiters.append((count, continuation)) }
    }
}
