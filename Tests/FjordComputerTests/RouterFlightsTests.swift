import Foundation
import Testing
@testable import FjordComputer

/// Canvas destinations use the shared flight's canonical keys and page measurements.
@MainActor
@Suite struct RouterFlightsTests {
    private var folders: [CanvasFolder] {
        var page = RouterPage()
        page.needs = [RouterCard(id: "q", sessionID: "a", kind: .question, title: "Question", folder: "/code/app",
                                 text: "", createdAt: Date())]
        page.working = ["a", "b"].map {
            AgentRow(session: ClaudeSession(id: $0, title: $0, folder: "/code/app", lastActivity: Date(), running: true),
                     entry: AgentEntry(id: $0), label: $0)
        }
        return RouterCanvasModel.make(page: page, done: [], name: { $0 }, color: { _ in nil })
    }

    @Test func aSessionLandsOnItsCardBeforeItsWorkingRowAndAnAnswerNamesItsCard() {
        #expect(CanvasFlightPlaces.target("session:a", folders: folders, folder: { _ in nil }, fallback: false) == .node("q"))
        #expect(CanvasFlightPlaces.target("session:b", folders: folders, folder: { _ in nil }, fallback: false)
                == .node(RouterModel.workingID("b")))
        #expect(CanvasFlightPlaces.target("card:q", folders: folders, folder: { _ in nil }, fallback: false) == .node("q"))
    }

    @Test func aMissingOrFoldedNodeWaitsBeforeFallingBackToItsProject() {
        #expect(CanvasFlightPlaces.target("session:new", folders: folders, folder: { _ in "/code/app" }, fallback: false) == nil)
        #expect(CanvasFlightPlaces.target("session:new", folders: folders, folder: { _ in "/code/app" }, fallback: true)
                == .folder("/code/app"))
        #expect(CanvasFlightPlaces.target("session:a", folders: folders, folder: { _ in nil }, fallback: true) == .folder("/code/app"))
        #expect(CanvasFlightPlaces.target("session:muted", folders: folders, folder: { _ in "/code/muted" }, fallback: true) == nil)
        #expect(CanvasFlightPlaces.target("history", folders: folders, folder: { _ in nil }, fallback: true) == nil)
    }

    @Test func aHiddenGroupOrAnAnsweredCardUsesItsFrameWithoutChangingFilters() {
        var hidden = folders
        for i in hidden[0].groups.indices { hidden[0].groups[i].hidden = true }
        #expect(CanvasFlightPlaces.target("card:q", folders: hidden, folder: { _ in "/code/app" }, fallback: false) == nil)
        #expect(CanvasFlightPlaces.target("card:q", folders: hidden, folder: { _ in "/code/app" }, fallback: true) == .folder("/code/app"))
        #expect(hidden[0].shown.isEmpty)
    }

    @Test func aNodeScrolledOutOfItsResizedFrameCannotReceiveAFlight() {
        let canvas = RouterCanvasState()
        canvas.free = CGRect(x: 16, y: 56, width: 868, height: 600)
        let rect = CGRect(x: 120, y: 300, width: 420, height: 100)
        let clip = CGRect(x: 100, y: 100, width: 560, height: 150)
        #expect(canvas.flightPlace(.node("q"), frames: ["canvas:q": rect], clip: clip) == nil)
        let header = CGRect(x: 100, y: 56, width: 560, height: 194)
        #expect(canvas.flightPlace(.folder("/code/app"), frames: ["canvas:frame#/code/app": header])?.rect.height == 44)
    }

    @Test func theTransformedHeaderUsesThePageMeasurementExactlyOnce() throws {
        let canvas = RouterCanvasState()
        canvas.camera.transform = CanvasTransform(origin: CGPoint(x: 60, y: 80), scale: 0.5)
        canvas.viewportFrame = CGRect(x: 200, y: 100, width: 900, height: 700)
        canvas.free = CGRect(x: 16, y: 56, width: 868, height: 600)
        // Content (100, 200, 420, 100) projected into the page by SwiftUI's FlightFrame.
        let rect = CGRect(x: 310, y: 280, width: 210, height: 50)
        let place = try #require(canvas.flightPlace(.node("q"), frames: ["canvas:q": rect]))
        #expect(place.target == "canvas:q")
        #expect(place.rect == CGRect(x: 310, y: 280, width: 210, height: 26))
    }

    @Test func aPartiallyVisibleCardLandsOnItsVisiblePartInsteadOfAnAbsentMarker() throws {
        let canvas = RouterCanvasState()
        canvas.free = CGRect(x: 16, y: 56, width: 800, height: 500)
        let rect = CGRect(x: -200, y: 100, width: 420, height: 52)
        let place = try #require(canvas.flightPlace(.node("q"), frames: ["canvas:q": rect]))
        #expect(place.rect == CGRect(x: 16, y: 100, width: 204, height: 52))
    }

    @Test func anOffViewTargetFliesToItsMarkerAndLandingKeepsTheCameraStill() throws {
        let canvas = RouterCanvasState()
        canvas.freezeFlight = 0.5
        canvas.camera.transform = CanvasTransform(origin: CGPoint(x: -2000, y: 100), scale: 0.5)
        canvas.viewportFrame = CGRect(x: 200, y: 100, width: 900, height: 700)
        canvas.free = CGRect(x: 16, y: 56, width: 868, height: 600)
        canvas.nodeRects["q"] = CGRect(x: 100, y: 200, width: 420, height: 52)
        let rect = CGRect(x: -1750, y: 300, width: 210, height: 26)
        let place = try #require(canvas.flightPlace(.node("q"), frames: ["canvas:q": rect]))
        #expect(place.rect.midX == 326, "the marker sits 110 points inside the left edge of the free canvas")
        #expect(canvas.free.offsetBy(dx: 200, dy: 100).contains(CGPoint(x: place.rect.midX, y: place.rect.midY)))
        let camera = canvas.camera.transform
        canvas.flightLanded(.init(id: UUID(), text: "go on", status: "", from: .zero, to: place.rect, target: place.target))
        #expect(canvas.marker?.node == "q")
        #expect(canvas.landed["q"]?.text == "go on")
        #expect(canvas.camera.transform == camera)
        canvas.goToMarker(reduce: true)
        #expect(canvas.marker == nil && canvas.camera.transform != camera)
    }
}
