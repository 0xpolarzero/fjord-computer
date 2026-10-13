import Foundation
import Testing
@testable import FjordComputer

@MainActor @Suite struct CanvasMemoTests {
    private func setup() -> (Store, RouterModel) {
        let store = Store()
        store.persists = false
        Demo.populate(store, .routerCanvas)
        let model = RouterModel()
        model.pickCanvas()
        return (store, model)
    }

    @Test func foldersFollowProjectNamesColorsMutingAndNewCardsAfterAMemoHit() throws {
        let (store, model) = setup()
        let page = model.zones(store)
        let first = try #require(model.canvasFolders(store, page: page).first)
        #expect(model.canvasFolders(store, page: page).first == first)
        store.folderNames[first.key] = "Renamed"
        store.agents.folderColors[first.key] = 5
        let renamed = try #require(model.canvasFolders(store, page: model.zones(store)).first { $0.key == first.key })
        #expect(renamed.name == "Renamed" && renamed.color == Theme.projectColors[5])
        store.agents.mutedFolders.append(first.key)
        #expect(!model.canvasFolders(store, page: model.zones(store)).contains { $0.key == first.key })
        store.agents.mutedFolders.removeAll { $0 == first.key }
        store.router.cards.append(RouterCard(id: "new", sessionID: "new", kind: .question, title: "New", folder: first.key,
                                            text: "Ready?", createdAt: Date()))
        #expect(model.canvasFolders(store, page: model.zones(store)).flatMap { $0.shown.flatMap(\.items) }.contains { $0.id == "new" })
    }

    @Test func packingFollowsFoldsSizesAndHandPlacementAfterAMemoHit() throws {
        let (store, model) = setup()
        let folders = model.canvasFolders(store, page: model.zones(store))
        let first = try #require(folders.first)
        let before = model.canvas.packedPlaces(folders)
        #expect(model.canvas.packedPlaces(folders) == before)
        model.canvas.positions[first.key] = CGPoint(x: -80, y: -40)
        #expect(model.canvas.packedPlaces(folders)[first.key] == CGPoint(x: -80, y: -40))
        let others = model.canvas.packedPlaces(folders).filter { $0.key != first.key }
        model.canvas.sizes[first.key] = CGSize(width: 560, height: 2000)
        let resized = model.canvas.packedPlaces(folders)
        #expect(resized.filter { $0.key != first.key } != others)
        #expect(resized[first.key] == CGPoint(x: -80, y: -40))
        model.canvas.positions = [:]
        model.canvas.sizes = [:]
        model.canvas.folderFolds[first.key] = true
        #expect(model.canvas.packedPlaces(folders) != before)
    }
}
