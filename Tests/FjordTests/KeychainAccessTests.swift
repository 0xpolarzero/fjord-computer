import Foundation
import Testing
@testable import Fjord

@MainActor
@Suite(.serialized) struct KeychainAccessTests {
    private func model(_ engine: MockEngineClient) -> ComputersModel {
        ComputersModel(client: engine, initialInventory: engine.inventory)
    }

    @Test func noBannerWhileEveryItemIsUsable() async {
        let engine = MockEngineClient()
        let model = model(engine)
        await model.refreshKeychainStatus()
        #expect(!model.keychainNeedsPermission)
    }

    @Test func deniedItemsFromTheStatusShowTheBanner() async {
        let engine = MockEngineClient()
        engine.denyCredentials()
        let model = model(engine)
        await model.refreshKeychainStatus()
        #expect(model.keychain.deniedCount == 3)
        #expect(model.keychainNeedsPermission)
    }

    @Test func aCredentialRefusalErrorShowsTheBannerWithoutAStatus() {
        let model = model(MockEngineClient())
        model.actionError = EngineClientError.coded(code: "credential_access_denied", message: "x").localizedDescription
        #expect(model.keychainNeedsPermission)
        #expect(EngineErrorText.isCredentialAccessDenied(OperationJobError(code: "credential_access_denied", message: "x").userMessage))
    }

    @Test func repairingAllowsAccessAndClearsTheRefusalErrors() async {
        let engine = MockEngineClient()
        engine.denyCredentials()
        let model = model(engine)
        await model.refreshKeychainStatus()
        model.actionError = EngineClientError.coded(code: "credential_access_denied", message: "x").localizedDescription
        await model.repairKeychainAccess()
        #expect(engine.credentialRepairCount == 1)
        #expect(!model.keychainNeedsPermission)
        #expect(model.actionError == nil)
        #expect(model.keychain.stillBlocked == nil)
    }

    @Test func aDeclinedDialogLeavesTheBannerAndNamesWhatIsBlocked() async {
        let engine = MockEngineClient()
        engine.denyCredentials()
        engine.credentialRepairDeclines = true
        let model = model(engine)
        await model.refreshKeychainStatus()
        await model.repairKeychainAccess()
        #expect(model.keychainNeedsPermission)
        let blocked = model.keychain.stillBlocked ?? ""
        #expect(blocked.contains("GitHub sign-in") && blocked.contains("Always Allow"))
    }

    @Test func aFailedRepairIsReportedAndRetryable() async {
        let engine = MockEngineClient()
        engine.denyCredentials()
        engine.credentialRepairFailure = .invalidAction("A Keychain access repair is already running.")
        let model = model(engine)
        await model.refreshKeychainStatus()
        await model.repairKeychainAccess()
        #expect(model.keychain.failure == "A Keychain access repair is already running.")
        #expect(model.keychainNeedsPermission)
        #expect(!model.keychain.isRepairing)
        engine.credentialRepairFailure = nil
        await model.repairKeychainAccess()
        #expect(!model.keychainNeedsPermission)
        #expect(model.keychain.failure == nil)
    }

    @Test func anOlderEngineWithoutTheMethodIsQuiet() async {
        let model = ComputersModel(client: UnavailableEngineClient(), initialInventory: nil)
        await model.refreshKeychainStatus()
        #expect(!model.keychainNeedsPermission)
    }

    @Test func theSecureTokenNoteReachesTheRowAsInformationNotFailure() throws {
        let engine = MockEngineClient()
        engine.setComputerNote("No SecureToken.", for: MockEngineClient.devID)
        let row = try #require(engine.inventory.computer(MockEngineClient.devID))
        #expect(row.note == "No SecureToken.")
        #expect(row.detail == nil)
        #expect(row.displayState == .running)
        let wire = #"{"kind":"macos","id":"a","name":"n","cpus":1,"memoryGiB":1,"diskGiB":1,"state":"stopped","displayOpen":false,"installed":true,"setupComplete":true,"needsPersonalizing":false,"checkpoints":[],"checkpointOperation":null,"pendingRestore":null,"note":"No SecureToken."}"#
        let decoded = try JSONDecoder().decode(MacosComputer.self, from: Data(wire.utf8))
        #expect(decoded.note == "No SecureToken.")
        #expect(MockEngineClient.demoInventory.allComputers.allSatisfy { $0.note == nil })
    }
}
