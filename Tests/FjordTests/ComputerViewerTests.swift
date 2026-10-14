import Testing
@testable import Fjord

@MainActor
@Suite struct ComputerViewerTests {
    @Test func viewerPageEventsRemainOrderedAcrossCoalescedModelUpdates() async throws {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)
        try await model.connect()
        let connectionId = "viewer-commands"
        let scripts = ["first", "first", "third"]

        for (index, script) in scripts.enumerated() {
            client.deliver(.event(sequence: UInt64(index + 2),
                                  event: .viewerPage(SiloWireViewerPageEvent(connectionId: connectionId,
                                                                             script: script))))
        }

        let commands = model.viewerScripts[connectionId] ?? []
        #expect(commands.map(\.script) == scripts)
        #expect(commands.allSatisfy { $0.connectionId == connectionId })
        model.acknowledgeViewerScriptCommand(connectionId: "another-viewer", commandId: commands[0].id)
        #expect(model.viewerScripts[connectionId]?.map(\.script) == scripts)
        model.acknowledgeViewerScriptCommand(connectionId: connectionId, commandId: commands[0].id)
        #expect(model.viewerScripts[connectionId]?.map(\.script) == ["first", "third"])
    }

    @Test func viewerQueuesPageScriptsUntilReadyAndExecutesIdenticalCommandsTwice() {
        var evaluated: [String] = []
        let coordinator = LinuxComputerWebView.Coordinator(evaluateScript: { script, completion in
            evaluated.append(script)
            completion()
        })
        let first = "window.commands.push('first')"
        let third = "window.commands.push('third')"

        coordinator.accept(first)
        coordinator.accept(first)
        coordinator.accept(third)

        #expect(!coordinator.pageReady)
        #expect(evaluated.isEmpty)

        coordinator.pageDidFinishLoading()

        #expect(evaluated == [first, first, third])
    }
}
