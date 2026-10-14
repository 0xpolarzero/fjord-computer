import SwiftUI

// Canvas destinations adapt the shared RouterFlights machinery: the same pill, loader, frame wait, arc and failure state.
// Targets are measured in FlightSpace after the camera transform; off-view flights end at the existing edge marker.

enum CanvasFlightTarget: Equatable {
    case node(String)
    case folder(String)
}

struct CanvasLanding: Equatable {
    let text: String
    var id = UUID()
    static let shown: TimeInterval = 6
}

extension CanvasFolder {
    static func frameID(_ key: String) -> String { "frame#\(key)" }
}

enum CanvasFlightPlaces {
    /// A routed session lands on its card first, then its working row; a folded or not-yet-drawn node uses its frame.
    static func target(_ key: String, folders: [CanvasFolder], folder: (String) -> String?, fallback: Bool) -> CanvasFlightTarget? {
        for frame in folders {
            let items = frame.shown.flatMap(\.items)
            let item: CanvasItem?
            if key.hasPrefix("card:") {
                item = items.first { $0.id == String(key.dropFirst(5)) }
            } else if key.hasPrefix("session:") {
                let session = String(key.dropFirst(8))
                let mine = items.filter { $0.sessionID == session }
                item = mine.first { if case .working = $0 { false } else { true } } ?? mine.first
            } else { item = nil }
            if let item { return fallback ? .folder(frame.key) : .node(item.id) }
        }
        guard fallback, key.hasPrefix("session:") || key.hasPrefix("card:"),
              let project = folder(String(key.dropFirst(key.hasPrefix("session:") ? 8 : 5))),
              folders.contains(where: { $0.key == project }) else { return nil }
        return .folder(project)
    }
}

extension RouterModel {
    func canvasFlightPlace(_ key: String, frames: [String: CGRect], fallback: Bool, store: Store) -> RouterFlights.Place? {
        if key == "history" {
            return frames["pane:history"].map { RouterFlights.Place(target: "pane:history", rect: $0) }
        }
        let folders = canvasFolders(store, page: zones(store))
        let target = CanvasFlightPlaces.target(key, folders: folders, folder: { id in
            if key.hasPrefix("card:") {
                guard let card = store.router.cards.first(where: { $0.id == id }) else { return nil }
                return store.routerProjectGroupKey(sessionID: card.sessionID, folder: card.folder ?? "")
            }
            guard let session = store.claudeSessions[id] else { return nil }
            return store.routerProjectGroupKey(sessionID: id, folder: session.folderKey)
        }, fallback: fallback)
        guard let target else {
            guard fallback else { return nil }
            let chip = key.hasPrefix("session:") ? "chip:working" : "chip:needs"
            for alternate in [chip, "pane:history"] {
                if let rect = frames[alternate] { return RouterFlights.Place(target: alternate, rect: rect) }
            }
            return nil
        }
        let clip: CGRect?
        if case .node(let id) = target, let frame = folders.first(where: { $0.shown.flatMap(\.items).contains { $0.id == id } }) {
            clip = frames["canvasBody:\(frame.key)"]
        } else { clip = nil }
        return canvas.flightPlace(target, frames: frames, clip: clip)
    }
}

extension RouterCanvasState {
    func flightPlace(_ target: CanvasFlightTarget, frames: [String: CGRect], clip: CGRect? = nil) -> RouterFlights.Place? {
        let id: String
        switch target {
        case .node(let node): id = node
        case .folder(let folder): id = CanvasFolder.frameID(folder)
        }
        let key = "canvas:\(id)"
        guard let rect = frames[key], rect.width > 1, rect.height > 1, free.width > 0 else { return nil }
        let height: CGFloat = if case .folder = target { CanvasMetrics.header } else { CanvasMetrics.closedH }
        let head = CGRect(x: rect.minX, y: rect.minY, width: rect.width,
                          height: min(rect.height, height * camera.transform.scale))
        if let clip {
            let inside = head.intersection(clip)
            guard inside.width >= head.width * 0.7, inside.height >= head.height * 0.7 else { return nil }
        }
        let view = free.offsetBy(dx: viewportFrame.minX, dy: viewportFrame.minY)
        let intersection = head.intersection(view)
        if intersection.width >= head.width * 0.7 && intersection.height >= head.height * 0.7 {
            return RouterFlights.Place(target: key, rect: head)
        }
        // The canvas's marker design treats any visible part as in view; land on that part instead of an absent marker.
        let direction = if case .folder = target { head } else { rect }
        let visible = direction.intersection(view)
        if visible.width > 1, visible.height > 1 {
            return RouterFlights.Place(target: key, rect: CGRect(x: visible.minX, y: visible.minY, width: visible.width,
                                                               height: min(visible.height, height * camera.transform.scale)))
        }
        let room = free.insetBy(dx: min(110, free.width / 4), dy: min(18, free.height / 4))
        let at = CanvasMetrics.edgePoint(from: CGPoint(x: free.midX, y: free.midY),
                                        to: CGPoint(x: direction.midX - viewportFrame.minX, y: direction.midY - viewportFrame.minY), in: room)
        return RouterFlights.Place(target: key,
                                  rect: CGRect(x: viewportFrame.minX + at.x - 100, y: viewportFrame.minY + at.y - 13,
                                               width: 200, height: 26))
    }

    func flightLanded(_ flight: RouterFlights.Flight) {
        guard flight.target.hasPrefix("canvas:") else { return }
        let id = String(flight.target.dropFirst(7))
        if !id.hasPrefix("frame#") { land(flight.text, on: id) }
        if let rect = nodeRects[id] { mark(rect, id: id, label: "You: " + RouterDecision.clip(flight.text, CanvasLanded.clip)) }
    }
}

// MARK: - Landing

/// On the bottom edge of a node a message landed on: "You: …" for a few seconds, the shared flight glow over the card as it lands.
struct CanvasLanded: View {
    let landing: CanvasLanding

    /// How much of your words it shows: it sits on the card's edge, not under it.
    static let clip = 40

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrowshape.turn.up.right").font(.system(size: 9, weight: .medium)).foregroundStyle(CDS.Fill.accent)
            Text("You: \(RouterDecision.clip(landing.text, Self.clip))").cdsText((12, 16), .regular, CDS.Text.secondary).lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(CDS.Surface.s2))
        .overlay { Capsule().strokeBorder(CDS.Fill.accent.opacity(0.5), lineWidth: 1) }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
