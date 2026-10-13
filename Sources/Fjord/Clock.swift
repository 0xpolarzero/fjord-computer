import AppKit
import Observation
import SwiftUI

/// One shared once-a-second clock for every ticking label. Its timer only runs while a `Ticking` view is on
/// screen, the screen is awake and a window one of them is in is visible: the bar is always on screen, but a label in the
/// app window kept while it is closed, or in a peek's panel put away, doesn't tick. With only coarse labels it ticks
/// every five seconds, all they read.
@MainActor @Observable
final class Clock {
    static let shared = Clock()

    /// Updated every second.
    private(set) var now = Date()
    /// Updated every 5 seconds, for labels that don't need more.
    private(set) var slow = Date()

    @ObservationIgnored private var subscribers = 0
    /// The `Ticking` views on screen, by view: whether each reads the coarse time only.
    @ObservationIgnored private var joined: [ObjectIdentifier: Bool] = [:]
    /// The window each is in, as it said (`place`); one that hasn't said yet counts as visible.
    @ObservationIgnored private var windows: [ObjectIdentifier: Place] = [:]
    private struct Place { weak var window: NSWindow? }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var asleep = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    private init() {
        let ws = NSWorkspace.shared.notificationCenter
        for (name, sleeping) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.asleep = sleeping; self?.update() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        })
    }

    func retain() {
        subscribers += 1
        if subscribers == 1 { now = Date(); slow = now }
        update()
    }

    func release() {
        subscribers = max(0, subscribers - 1)
        update()
    }

    /// A `Ticking` view on screen (`retain`), and the window it is in once known (`place`); `leave` when it goes.
    func join(_ view: Token, coarse: Bool) {
        joined[ObjectIdentifier(view)] = coarse
        retain()
    }

    func place(_ view: Token, in window: NSWindow?) {
        windows[ObjectIdentifier(view)] = Place(window: window)
        if joined[ObjectIdentifier(view)] != nil { update() }
    }

    func leave(_ view: Token) {
        windows[ObjectIdentifier(view)] = nil
        guard joined.removeValue(forKey: ObjectIdentifier(view)) != nil else { return }
        release()
    }

    /// What a `Ticking` view is known by.
    final class Token {}

    private var anyWindowVisible: Bool {
        func shows(_ window: NSWindow) -> Bool { window.isVisible && window.occlusionState.contains(.visible) }
        // Every view on screen said where it is: one of their windows shows (one out of any window doesn't). Else (a
        // `retain` alone, a view not placed yet): any window shows.
        if joined.count == subscribers, joined.keys.allSatisfy({ windows[$0] != nil }) {
            return joined.keys.contains { windows[$0]?.window.map(shows) ?? false }
        }
        return NSApp.windows.contains(where: shows)
    }

    /// Every second, or every five while only coarse labels read it.
    private var period: TimeInterval { joined.count == subscribers && joined.values.allSatisfy { $0 } ? 5 : 1 }

    private func update() {
        let run = subscribers > 0 && !asleep && anyWindowVisible
        if let t = timer, !run || t.timeInterval != period {
            t.invalidate()
            timer = nil
        }
        if run, timer == nil {
            now = Date()
            slow = now
            ticks = 0
            let every = period
            let t = Timer(timeInterval: every, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick(every) }
            }
            t.tolerance = every * 0.3
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func tick(_ every: TimeInterval) {
        now = Date()
        ticks += 1
        if every >= 5 || ticks % 5 == 0 { slow = now }
    }
}

/// Content that depends on the current time, redrawn from the shared clock: every second, or every 5 if `coarse`.
struct Ticking<Content: View>: View {
    var coarse = false
    @ViewBuilder let content: (Date) -> Content
    @State private var token = Clock.Token()

    var body: some View {
        let clock = Clock.shared
        content(coarse ? clock.slow : clock.now)
            .background(ClockWindowProbe { [token] window in clock.place(token, in: window) })
            .onAppear { clock.join(token, coarse: coarse) }
            .onDisappear { clock.leave(token) }
    }
}

/// Says which window a `Ticking` view is in, as it moves into one (or out).
private struct ClockWindowProbe: NSViewRepresentable {
    let moved: (NSWindow?) -> Void

    func makeNSView(context: Context) -> Probe { Probe(moved: moved) }
    func updateNSView(_ view: Probe, context: Context) { view.moved = moved }

    final class Probe: NSView {
        var moved: (NSWindow?) -> Void
        init(moved: @escaping (NSWindow?) -> Void) {
            self.moved = moved
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            moved(window)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
