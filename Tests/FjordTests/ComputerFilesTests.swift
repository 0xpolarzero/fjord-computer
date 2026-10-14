import Testing
@testable import Fjord

@MainActor
@Suite struct ComputerFilesTests {
    @Test func linuxFilesStartAtWorkspaceRoot() async {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)

        await model.loadFiles(.thisMac(MockEngineClient.linuxID))

        #expect(model.filePaths[GuestReference.thisMac(MockEngineClient.linuxID).key] == "/workspace")
        #expect(Set(model.fileLists[GuestReference.thisMac(MockEngineClient.linuxID).key]?.entries.map(\.path) ?? []) ==
                Set(["/workspace/Projects", "/workspace/README.md"]))
        #expect(ComputerFilesPath.parent(of: "/workspace", kind: .linux) == "/workspace")
        #expect(ComputerFilesPath.parent(of: "/workspace/Projects", kind: .linux) == "/workspace")
        #expect(ComputerFilesPath.parent(of: "/workspace/Projects/One", kind: .linux) == "/workspace/Projects")
        #expect(ComputerFilesPath.parent(of: "/workspace/../../etc", kind: .linux) == "/workspace")
    }

    @Test func macosFilesStayUnavailableUntilTheEngineDefinesTheirRoot() async {
        let client = MockEngineClient()
        let model = ComputersModel(client: client, initialInventory: client.inventory)

        await model.loadFiles(.thisMac(MockEngineClient.devID))

        #expect(ComputerFilesPath.root(for: .macos) == nil)
        #expect(!client.generatedCalls.contains("files.list"))
        #expect(model.filePaths[GuestReference.thisMac(MockEngineClient.devID).key] == nil)
    }
}
