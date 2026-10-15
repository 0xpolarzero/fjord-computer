import Foundation
import Testing
@testable import Fjord

@MainActor
private final class StubService: EngineAgentServicing {
    func status() -> EngineAgentStatus { .enabled }
    func register() throws {}
    func unregister() async throws {}
    func openSystemSettings() {}
}

@MainActor
private final class StubConnector: EngineSocketConnecting {
    private(set) var calls = 0
    func connect() async throws -> EngineConnection {
        calls += 1
        return EngineConnection(client: MockEngineClient(), version: "9.9.9", build: nil, source: .sharedEngine)
    }
}

@MainActor
@Suite(.serialized) struct GuestEngineConnectTests {
    /// A Send or Retry right after launch used to fail with "guest file client isn't connected" until the Computers page
    /// had connected the engine; the guest lookup now connects it on demand.
    @Test func guestClientLookupConnectsTheEngineWithoutTheComputersPage() async throws {
        let connector = StubConnector()
        let launcher = EngineLauncher(candidateVersion: "1.0.0", service: StubService(), connector: connector)
        let store = Store(engineClient: UnavailableEngineClient(), engineLauncher: launcher)
        store.persists = false
        let runtime = GuestRouterRuntime.shared
        let guest = MockGuestClient()
        runtime.clientFactory = { $0 is MockEngineClient ? guest : nil }
        defer { runtime.clientFactory = nil; runtime.stopAll() }
        await runtime.rehydrate(store: store)
        let location = SessionLocation.computer(deviceId: "local", computerId: "c-\(UUID().uuidString)")

        #expect(runtime.guestClient(for: location) == nil)
        #expect(store.hasEngineConnection == false)

        let client = await runtime.connectedGuestClient(for: location)
        #expect(client != nil)
        #expect(store.hasEngineConnection)
        #expect(connector.calls == 1)

        // Already connected: no second attempt.
        _ = await runtime.connectedGuestClient(for: location)
        #expect(connector.calls == 1)
    }
}
