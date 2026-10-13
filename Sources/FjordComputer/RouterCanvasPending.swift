import SwiftUI

// Your messages on the canvas (docs/design/spec/router-canvas.md §6): each waits over the composer with what the Router is
// doing to it, and the questions it asks back under them; once sent, it flies along an arc to the card of the session it
// went to, the canvas panning there first, and lands with a ripple and "You: …" under the card. One that went nowhere on
// the canvas (the Router answered it, it failed, or it changed Fjord Computer) fades, and its answer is in the history.

// MARK: - Departures

/// Where a message flies: a node of the canvas (a card, or a session's row), or the frame of a project whose session isn't
/// drawn yet (one just started).
enum FlightTarget: Equatable {
    case node(String)
    case folder(String)
}

enum RouterFlights {
    /// A message leaving the pending area: its entry, its words, where it goes (nil: it fades).
    struct Departure: Equatable {
        let id: UUID
        let text: String
        let target: FlightTarget?
    }

    /// How much of your message the pending line and the flight show.
    static let clip = 60

    /// A message of yours, as the composer sends it (routed, or forked from): not something you did on a card, nor an
    /// action's message.
    static func isMessage(_ decision: RouterDecision) -> Bool {
        guard case .you = decision.trigger, decision.fromAction == nil else { return false }
        return decision.decision.intent == "message" || decision.decision.intent == "fork"
    }

    /// Your messages under way, oldest first, but those the Router asks you about (their question stands for them).
    static func pending(_ decisions: [RouterDecision], asking: Set<UUID> = []) -> [RouterDecision] {
        decisions.filter { isMessage($0) && $0.outcome == .pending && !asking.contains($0.id) }
    }

    /// Your messages settled: none of them flies when the canvas comes.
    static func settled(_ decisions: [RouterDecision]) -> Set<UUID> {
        Set(decisions.lazy.filter { isMessage($0) && $0.outcome != .pending }.map(\.id))
    }

    /// The messages settled since `settled`, and what is settled now. A message taken back flies nowhere; one that failed
    /// or reached no session fades. `folder`: a session's project, for one not on the canvas yet.
    static func departures(settled: Set<UUID>, now decisions: [RouterDecision], folders: [CanvasFolder],
                           folder: (String) -> String?) -> (departures: [Departure], settled: Set<UUID>) {
        var settled = settled
        var out: [Departure] = []
        for decision in decisions where isMessage(decision) && decision.outcome != .pending {
            guard settled.insert(decision.id).inserted, !decision.isCancelled else { continue }
            out.append(Departure(id: decision.id, text: RouterDecision.clip(decision.triggerText, clip),
                                 target: target(decision, folders: folders, folder: folder)))
        }
        return (out, settled)
    }

    /// Where a settled message goes: the session it was sent to (its card, else its row), or the card it answered; that
    /// session's project when it isn't drawn yet; nothing when it failed or reached no session.
    static func target(_ decision: RouterDecision, folders: [CanvasFolder], folder: (String) -> String?) -> FlightTarget? {
        if decision.done.contains(where: { if case .failed = $0 { true } else { false } }) { return nil }
        let items = folders.flatMap { $0.shown.flatMap(\.items) }
        let session = decision.sentMessage?.session ?? decision.delivered?.session ?? decision.links.sessions.first
            ?? decision.links.cards.lazy.compactMap { id in items.first { $0.id == id }?.sessionID }.first
        guard let session else { return nil }
        let mine = items.filter { $0.sessionID == session }
        if let card = mine.first(where: { if case .working = $0 { false } else if case .waiting = $0 { false } else { true } }) ?? mine.first {
            return .node(card.id)
        }
        guard let key = folder(session), folders.contains(where: { $0.key == key }) else { return nil }
        return .folder(key)
    }
}

// MARK: - State

/// A message in the air: from its pending line to its node, in the Router's space.
struct CanvasFlight: Identifiable, Equatable {
    let id: UUID
    let text: String
    let from: CGRect
    let to: CGRect
    /// The node it lands on (none for a frame).
    let node: String?
    /// Off the view: the node or frame its edge marker points to once it arrives, and where it was.
    var marker: (key: String, label: String, rect: CGRect)? = nil

    static func == (a: CanvasFlight, b: CanvasFlight) -> Bool {
        a.id == b.id && a.text == b.text && a.from == b.from && a.to == b.to && a.node == b.node && a.marker?.key == b.marker?.key
    }
}

/// What landed on a node.
struct CanvasLanding: Equatable {
    let text: String
    var id = UUID()

    /// How long "You: …" stays under the card.
    static let shown: TimeInterval = 6
}

extension RouterCanvasState {
    /// The router changed: each message of yours settled since flies to where it went, or fades. The first look only notes
    /// what is settled already.
    func depart(store: Store, model: RouterModel, page: RouterPage, narrow: Bool, reduce: Bool) {
        // The last entries: a message is settled in seconds, long before a hundred more runs are logged.
        let recent = Array(store.router.decisions.suffix(100))
        guard let settled else {
            self.settled = RouterFlights.settled(recent)
            return
        }
        // Most changes settle nothing of yours: the frames are worked out only for one that did.
        guard !RouterFlights.settled(recent).subtracting(settled).isEmpty else { return }
        let folders = model.canvasFolders(store, page: page)
        let next = RouterFlights.departures(settled: settled, now: recent, folders: folders) { store.claudeSessions[$0]?.folderKey }
        self.settled = next.settled
        for departure in next.departures {
            guard let target = departure.target else {
                // The answer is the history's: in a narrow window it shows once the line has faded.
                if narrow {
                    historyTask?.cancel()
                    historyTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(reduce ? 0 : 300))
                        // Unless you've moved on meanwhile (the list, the history already).
                        guard !Task.isCancelled, model.layout == .canvas, model.pane == .now else { return }
                        model.show(.history)
                    }
                }
                continue
            }
            fly(departure, to: target, reduce: reduce)
        }
    }

    private func fly(_ departure: RouterFlights.Departure, to target: FlightTarget, reduce: Bool) {
        let key = switch target {
        case .node(let id): id
        case .folder(let key): CanvasFolder.frameID(key)
        }
        let node: String? = if case .node(let id) = target { id } else { nil }
        let label = "You: " + RouterDecision.clip(departure.text, CanvasLanded.clip)
        guard let rect = nodeRects[key] else {
            if let node { land(departure.text, on: node) }
            return
        }
        // The camera stays where you left it: a node off the view gets the flight to the viewport's edge, towards it, and a
        // marker there that takes you to it.
        let offView = !shows(rect)
        guard !reduce else {
            if let node { land(departure.text, on: node) }
            if offView { mark(rect, id: key, label: label) }
            return
        }
        let camera = self.camera.transform
        // Onto the node's header, as the lines meet it.
        let head = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: min(rect.height, CanvasMetrics.closedH))
        var to = CGRect(x: viewportFrame.minX + camera.origin.x + head.minX * camera.scale,
                        y: viewportFrame.minY + camera.origin.y + head.minY * camera.scale,
                        width: head.width * camera.scale, height: head.height * camera.scale)
        if offView {
            let room = free.insetBy(dx: 110, dy: 18)
            let target = CGPoint(x: camera.origin.x + rect.midX * camera.scale, y: camera.origin.y + rect.midY * camera.scale)
            let at = CanvasMetrics.edgePoint(from: CGPoint(x: free.midX, y: free.midY), to: target, in: room)
            to = CGRect(x: viewportFrame.minX + at.x, y: viewportFrame.minY + at.y - CanvasPendingLine.height / 2, width: 0,
                        height: CanvasPendingLine.height)
        }
        let from = pendingFrames[departure.id]
            ?? CGRect(x: composerFrame.midX - 120, y: composerFrame.minY - 28, width: 240, height: CanvasPendingLine.height)
        flights.append(CanvasFlight(id: departure.id, text: departure.text, from: from, to: to, node: node,
                                    marker: offView ? (key, label, rect) : nil))
        pendingFrames[departure.id] = nil
    }

    /// A flight arrived: on its node, or at the edge, where its marker takes over.
    func arrived(_ flight: CanvasFlight) {
        flights.removeAll { $0.id == flight.id }
        if let node = flight.node { land(flight.text, on: node) }
        if let marker = flight.marker { mark(nodeRects[marker.key] ?? marker.rect, id: marker.key, label: marker.label) }
    }
}

extension CanvasFolder {
    /// The id its frame's box is kept under (`RouterCanvasState.nodeRects`).
    static func frameID(_ key: String) -> String { "frame#\(key)" }
}

// MARK: - Pending area

/// Over the composer, on the canvas: your messages under way, each with what the Router is doing to it, then the questions
/// it asks back (where a message goes; ⌘1…4 pick, as in the list). Each line's box is kept as its flight's start.
struct RouterPendingStack: View {
    let store: Store
    let model: RouterModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let asks = store.routerDispatcher.askBacks
        let pending = RouterFlights.pending(Array(store.router.decisions.suffix(100)), asking: Set(asks.map(\.id)))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(pending) { decision in
                CanvasPendingLine(text: RouterDecision.clip(decision.triggerText, RouterFlights.clip), status: decision.status(store))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RouterMain.space)) } action: { rect in
                        model.canvas.pendingFrames[decision.id] = rect
                    }
                    .transition(.asymmetric(insertion: .scaleFade(0.97, reduce: reduceMotion), removal: .opacity))
            }
            ForEach(asks) { ask in
                AskBackCard(store: store, ask: ask)
                    // Its wash over the page's ground, not over the canvas showing through it.
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CDS.Surface.s1))
                    .onDisappear { model.canvas.pendingFrames[ask.id] = nil }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RouterMain.space)) } action: { rect in
                        // Its message flies from it once you've picked.
                        model.canvas.pendingFrames[ask.id] = CGRect(x: rect.minX, y: rect.minY, width: min(rect.width, 320),
                                                                    height: CanvasPendingLine.height)
                    }
                    .transition(.scaleFade(0.97, reduce: reduceMotion))
            }
        }
        // Over the canvas only, in a wide window (the composer is as wide as both columns): the history keeps its side.
        .frame(maxWidth: room, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, pending.isEmpty && asks.isEmpty ? 0 : 8)
        .motion(.spatial, value: pending.map(\.id) + asks.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your messages under way")
    }

    /// From the composer's start to the canvas's end, less a margin; none while either isn't laid out.
    private var room: CGFloat? {
        let canvas = model.canvas
        guard canvas.viewportFrame.width > 0, canvas.composerFrame.width > 0 else { return nil }
        return max(240, canvas.viewportFrame.maxX - canvas.composerFrame.minX - CanvasMetrics.pad)
    }
}

/// A message waiting: your words, and what the Router is doing with it, shimmering.
struct CanvasPendingLine: View {
    let text: String
    let status: String
    /// In the air (`CanvasFlightView`): on the composer's surface, lifted.
    var flying = false

    static let height: CGFloat = 24

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.circle").font(.system(size: 10, weight: .medium)).foregroundStyle(CDS.Text.muted)
            Text(text).cdsText((12, 16), .regular, CDS.Text.secondary).lineLimit(1).truncationMode(.tail).layoutPriority(1)
            if !status.isEmpty { ShimmerText(text: "· " + status, role: (12, 16)) }
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous).fill(flying ? CDS.Surface.s3 : CDS.Surface.s2)
        }
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(CDS.border, lineWidth: 1) }
        .shadow(color: .black.opacity(flying ? 0.18 : 0), radius: 8, y: 3)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(text)")
        .accessibilityValue(status)
    }
}

// MARK: - Flights

/// The messages in the air, over the Router's window: each along its arc, landing on its node.
struct CanvasFlights: View {
    let canvas: RouterCanvasState

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(canvas.flights) { flight in
                CanvasFlightView(flight: flight, freeze: canvas.freezeFlight) { canvas.arrived(flight) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CanvasFlightView: View {
    let flight: CanvasFlight
    let freeze: CGFloat?
    let arrived: () -> Void
    @State private var progress: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The arc's time, eased in and out.
    static let duration: TimeInterval = 0.7

    var body: some View {
        CanvasPendingLine(text: flight.text, status: "", flying: true)
            .modifier(ArcFlight(progress: freeze ?? progress, from: CGPoint(x: flight.from.midX, y: flight.from.midY),
                                to: CGPoint(x: flight.to.minX + min(flight.to.width / 2, 140), y: flight.to.midY)))
            .onAppear {
                guard freeze == nil else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Self.duration)) { progress = 1 } completion: { arrived() }
            }
    }
}

/// A point along a quadratic arc from `from` to `to`, its control 120 over their midpoint: the chip's centre, shrinking a
/// little and fading as it lands.
struct ArcFlight: ViewModifier, Animatable {
    var progress: CGFloat
    let from: CGPoint
    let to: CGPoint

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    static func point(_ t: CGFloat, from: CGPoint, to: CGPoint) -> CGPoint {
        let control = CGPoint(x: (from.x + to.x) / 2, y: min(from.y, to.y) - 120)
        let u = 1 - t
        return CGPoint(x: u * u * from.x + 2 * u * t * control.x + t * t * to.x,
                       y: u * u * from.y + 2 * u * t * control.y + t * t * to.y)
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.12 * progress)
            .opacity(progress < 0.85 ? 1 : max(0, (1 - progress) / 0.15))
            .position(Self.point(progress, from: from, to: to))
    }
}

// MARK: - Landing

/// On the bottom edge of a node a message landed on: "You: …" for a few seconds, its ripple over the card as it lands.
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

/// The ring a landing draws over its card: out a little and gone.
struct CanvasRipple: View {
    let landing: CanvasLanding
    /// Shots: held at its start.
    var frozen = false
    @State private var spread = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if !reduceMotion {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(CDS.Fill.accent, lineWidth: 1.5)
                .scaleEffect(spread ? 1.04 : 1)
                .opacity(spread ? 0 : 0.6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .onAppear {
                    guard !frozen else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { spread = true }
                }
                .id(landing.id)
        }
    }
}
