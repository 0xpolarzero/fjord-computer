import AppKit
import SwiftUI

// Fjord Computer as a window: everything the bar holds, with the bar's items as a navigation sidebar. The other mode is
// the bar docked on a screen edge; whoever switches between them calls `show` and listens to `onClose`.

/// How the app is present on the system. An accessory app has no Dock icon and no menu bar; while the app window is open
/// Fjord Computer is a regular app (Dock icon, ⌘-Tab, menu bar).
@MainActor
enum AppPolicy {
    /// The policy the app wants now. A test run keeps it to itself: applied, every test that opens the window would put
    /// its test helper in the Dock and take the focus, and with test runs side by side the Dock fills with them.
    private(set) static var current: NSApplication.ActivationPolicy = .accessory

    /// Regular while `windowOpen`, else accessory (the bar only).
    static func update(windowOpen: Bool) {
        current = windowOpen ? .regular : .accessory
        guard !UnderTest.isRunning else { return }
        if NSApp.activationPolicy() != current { NSApp.setActivationPolicy(current) }
    }

    /// Fjord Computer to the front, unless this is a test run (which must not take the focus from whoever is at the Mac).
    static func activate() {
        guard !UnderTest.isRunning else { return }
        watchActivations()
        request.asked(active: NSApp.isActive, at: ProcessInfo.processInfo.systemUptime)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// The app with windows that was in front before Fjord Computer last was: where the keyboard goes back to as the
    /// window closes. Held (a weak one would let go of it as the workspace does) and dropped once it has quit.
    private static var previous: NSRunningApplication?
    private static var activations: NSObjectProtocol?

    /// Whether the keyboard can go back to an app: a regular one (a menu-bar or launcher app, such as Raycast or a password
    /// manager, has no window to type in) other than Fjord Computer, still running.
    static func canTakeFocusBack(policy: NSApplication.ActivationPolicy, isSelf: Bool, terminated: Bool) -> Bool {
        policy == .regular && !isSelf && !terminated
    }

    private static func remember(_ app: NSRunningApplication?) {
        if let app = takingFocusBack(app) { previous = app }
    }

    /// `app`, if the keyboard can go back to it as it is now (`canTakeFocusBack`).
    static func takingFocusBack(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, canTakeFocusBack(policy: app.activationPolicy, isSelf: app == NSRunningApplication.current,
                                        terminated: app.isTerminated) else { return nil }
        return app
    }

    private static func watchActivations() {
        guard activations == nil else { return }
        activations = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                remember(app)
                // Another app came to the front after the request: it was refused, or has been overtaken.
                if let app, app != NSRunningApplication.current { request.overtaken() }
            }
        }
        remember(NSWorkspace.shared.frontmostApplication)
        becameActive = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                              queue: .main) { _ in
            MainActor.assumeIsolated { becameActiveNow() }
        }
        resignedActive = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification,
                                                                object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { request.resigned() }
        }
    }

    private static var becameActive: NSObjectProtocol?
    private static var resignedActive: NSObjectProtocol?
    /// An activation `activate` asked for, until it lands or the app resigns.
    private static var request = ActivationRequest()

    /// Whether an activation Fjord Computer asked for has yet to land.
    static var activationPending: Bool { request.isPending(at: ProcessInfo.processInfo.systemUptime) }

    /// An activation asked for, from the asking until it lands (`didBecomeActive`), the app resigns or another app comes to
    /// the front (refused, or overtaken), and at most `life` seconds of uptime: long enough for a main thread busy bringing
    /// the window in, short enough that a refusal no one reported can't pass a later activation of the user's for ours.
    struct ActivationRequest: Equatable {
        static let life: TimeInterval = 5
        private(set) var askedAt: TimeInterval?

        /// Asked (`now`: system uptime); none comes when the app is active already.
        mutating func asked(active: Bool, at now: TimeInterval) { if !active { askedAt = now } }

        func isPending(at now: TimeInterval) -> Bool { askedAt.map { now - $0 < Self.life } ?? false }

        /// The app became active: whether that was the activation asked for.
        mutating func landed(at now: TimeInterval) -> Bool {
            defer { askedAt = nil }
            return isPending(at: now)
        }

        mutating func resigned() { askedAt = nil }
        mutating func overtaken() { askedAt = nil }
    }

    /// The close's tidying, as a safety net: still active with no window, while an activation asked for is pending (its
    /// notice still to come), the keyboard goes back.
    static func yieldsAtTidy(active: Bool, windowShown: Bool, pending: Bool) -> Bool { active && !windowShown && pending }
    /// The user made Fjord Computer active (⌘-Tab, the Dock) while its window was closing: the app delegate opens it again.
    static var reopen: (() -> Void)?

    private static func becameActiveNow() {
        let ours = request.landed(at: ProcessInfo.processInfo.systemUptime)
        switch onActivation(ours: ours, windowShown: AppWindowController.anyShown, closing: AppWindowController.anyClosing) {
        case .yield: yieldFocus()
        case .reopen: reopen?()
        case .stay: break
        }
    }

    enum Activation: Equatable { case stay, yield, reopen }

    /// What Fjord Computer does as it becomes active. An activation it asked for (`ours`, an opening's) that lands with no
    /// window open or on its way in (the close was quick: under Reduce Motion, or with no morph) gives the keyboard back
    /// again. One it didn't ask for (⌘-Tab, the Dock) while the window closes is the user asking for it: the window opens
    /// again. Anything else stays (the user's, or a banner's click, which opens what it opens).
    static func onActivation(ours: Bool, windowShown: Bool, closing: Bool) -> Activation {
        if ours { return windowShown ? .stay : .yield }
        return closing ? .reopen : .stay
    }

    /// The keyboard back to the app that had it before, as the window starts closing: what you type next goes there at
    /// once rather than after the close's motion (the Dock icon still goes at its end, `update`). Fjord Computer yields its
    /// activation to that app, which is then asked to the front; with no such app, or one that won't come, Fjord Computer
    /// just stops being active. Nothing when it is not active, or under a test.
    static func yieldFocus() {
        guard !UnderTest.isRunning, NSApp.isActive else { return }
        // Asked again now: it may have quit, or turned into an app without windows, since it was remembered.
        previous = takingFocusBack(previous)
        guard let previous else {
            NSApp.deactivate()
            return
        }
        let asked: Bool
        if #available(macOS 14, *) {
            NSApp.yieldActivation(to: previous)
            asked = previous.activate(from: .current, options: [])
        } else {
            asked = previous.activate(options: [])
        }
        if !asked { NSApp.deactivate() }
    }
}

@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    /// The window the Go menu acts on: the last one made.
    static weak var active: AppWindowController?
    /// The controllers whose window has been brought in: whether another is still open when one's close is tidied.
    private static let broughtIn = NSHashTable<AppWindowController>.weakObjects()
    /// Whether a window is open or on its way in (`isOpen`), of those brought in or the last one made.
    static var anyShown: Bool { active?.isOpen == true || broughtIn.allObjects.contains { $0.isOpen } }
    /// Whether a window is on its way out (its close's motion playing).
    static var anyClosing: Bool { active?.phase == .closing || broughtIn.allObjects.contains { $0.phase == .closing } }
    static let autosave = "FjordApp"
    static let minSize = NSSize(width: 1000, height: 600)

    let store: Store
    let navigator: AppNavigator
    let routerModel: RouterModel
    /// Called once the window has closed (by the user or `close()`): the place to put the bar back on its edge.
    var onClose: (() -> Void)?
    /// The screen the bar is docked on: the window opens there. Nil (or no answer) is the main screen.
    var barScreen: () -> NSScreen? = { nil }
    /// Where the bar is, to morph out of when the window opens and into when it closes. Nil: no morph.
    var bar: () -> BarMorph? = { nil }
    /// The window starts closing (its morph is under way): the bar may fade back in now. `onClose` follows.
    var onClosing: (() -> Void)?
    /// The window came to the front, or went out of sight (another app in front, minimized, covered): the bar is away
    /// while the window is in front, and back on its edge otherwise.
    var onFront: ((Bool) -> Void)?
    private var lastFront: Bool?
    private var observers: [NSObjectProtocol] = []
    /// What a morph in progress is, so a new `show` or `close` can take it over.
    private(set) var run: AppTransition.Run?
    private var generation = 0

    /// Where the window is in its morph. The bar's presence is not told of the window's comings and goings meanwhile (the
    /// window is out of sight on purpose), and is told what they came to once it is over.
    enum Phase { case idle, opening, closing }
    private(set) var phase = Phase.idle
    private(set) var window: NSWindow?
    private let checksClaudeCode: Bool
    /// The rows' picked state, Settings' scroll requests and the category editor's step back, shared by the destinations.
    let hub = HubState()
    private lazy var keys = RouterKeys(store: store, model: routerModel) { [weak self] in self?.close() }
    /// The inbox's search, and the keys of the inbox destinations (see `AppWindowKeys`).
    let search = InboxSearch()
    private(set) lazy var inboxKeys: AppWindowKeys = {
        let keys = AppWindowKeys(store: store, navigator: navigator, hub: hub, search: search) { [weak self] in self?.close() }
        keys.openInRouter = { [weak self] thing in
            guard let self else { return }
            routerModel.open(thing: thing, in: navigator)
        }
        return keys
    }()
    private var monitor: Any?
    /// The window's corner radius, for the root's shapes.
    let corner = WindowCorner()
    /// The window's capture flag: its glass pieces draw their stand-ins while the morph takes its picture (`GlassCapture`).
    let capture = GlassCapture()

    /// `routerModel`: the Router's chat state, shared with whatever else shows the Router. `remembers`: open on the place left
    /// last (off for shots and tests).
    init(store: Store, routerModel: RouterModel? = nil, remembers: Bool = true, checksClaudeCode: Bool = true) {
        self.store = store
        self.routerModel = routerModel ?? RouterModel(defaults: remembers ? .standard : nil)
        self.checksClaudeCode = checksClaudeCode
        navigator = AppNavigator(fallback: store.firstPlace, defaults: remembers ? .standard : nil)
        super.init()
        // The place changed by whatever changes it (the Go menu, back and forward, a chip) while the window is on its way
        // in: the overlay shows the new one.
        navigator.onChange = { [weak self] in self?.contentChanged() }
        Self.active = self
        settle()
        Self.watchMemory()
    }

    /// The system short of memory: the window made last lets go of what it keeps only to open faster (see `releaseKept`),
    /// and keeps nothing more until memory is back (see `memoryShort`).
    private static var memoryWatch: DispatchSourceMemoryPressure?

    private static func watchMemory() {
        guard memoryWatch == nil else { return }
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        source.setEventHandler {
            let event = source.data
            MainActor.assumeIsolated { active?.memoryPressure(elevated: !event.contains(.normal)) }
        }
        source.resume()
        memoryWatch = source
    }

    /// Whether the system is short of memory (a warning or a critical pressure, until it says normal again): the window
    /// prepares nothing, keeps no picture at a close, and lets go of its content once a close has taken it out.
    private(set) var memoryShort = false

    /// The system's memory pressure went up (`elevated`) or back to normal.
    func memoryPressure(elevated: Bool) {
        memoryShort = elevated
        if elevated { releaseKept() }
    }

    /// Lets go of the picture kept from the last close and, while the window is closed, of its content (a window's worth
    /// of views, and the picture some 15 MB): the next opening makes them again, as a first one does. Content still in the
    /// window stays (a close under way takes it out a turn later, and lets go of it then while memory is short).
    func releaseKept() {
        closedPicture = nil
        guard phase == .idle, pending == nil, window?.isVisible != true, window?.contentViewController == nil else { return }
        content = nil
    }

    /// Whether a picture from the last close is kept for the next opening.
    var keepsPicture: Bool { closedPicture != nil }

    /// Open, or on its way in (its morph plays before the window itself is in); one on its way out is closed already (a
    /// toggle opens it again).
    var isOpen: Bool { phase == .opening || (phase != .closing && window?.isVisible == true) }
    /// What the window shortcut does: close the window you are looking at (or one on its way in), else bring it in front.
    /// A window open behind another app or minimized comes forward: closing it would leave nothing to see.
    var shortcutCloses: Bool { Self.shortcutCloses(phase: phase, front: isFront) }

    static func shortcutCloses(phase: Phase, front: Bool) -> Bool { phase == .opening || (phase == .idle && front) }
    /// The window's content, kept while the window is closed: out of the window it stands still (no body runs, no clock,
    /// timeline or animation ticks, its tasks are cancelled), and back in it picks up where it was, its scroll positions and
    /// the rest of its state kept, its appearing (`onAppear`, `.task`, `onChange(initial:)`) run again as on a first open.
    private(set) var content: NSViewController?
    /// The window's picture as it was last seen: kept the window as drawn while it is open and still (`keepPicture`), so a
    /// close starts on it with nothing captured, then kept from the close for the next opening to start on (see
    /// `startOpening`), until the window has stayed closed `keptPictureLife`.
    private var closedPicture: AppTransition.Picture?
    /// The opening whose picture was checked against its window once already (see `payPicture`).
    private var checked: Int?
    /// Input to the window and what was asked of it, counted (see `AppTransition.Marks`).
    private var changes = 0
    private var inputWatch: Any?
    /// Keeps `closedPicture` fresh while the window is open (see `keepPicture`): its next look, and whether it keeps.
    private var pictureKeeper: Timer?
    private var keeping = false
    /// The keeper's last look at a window that had moved on from its picture, and the marks then: a picture is taken only
    /// once the next look finds it alike (the window at rest).
    private var restGlance: (glance: AppTransition.Glance, marks: AppTransition.Marks)?
    /// Lets go of `closedPicture` once the window has stayed closed `keptPictureLife`.
    private var pictureExpiry: DispatchWorkItem?
    /// How long a closed window keeps its picture (some 15 to 30 MB): by then what it shows has likely moved on (its times,
    /// its counts), so an opening would not hand over on it anyway.
    static let keptPictureLife: TimeInterval = 300
    /// An opening whose window is still to be brought in: its generation.
    private var pending: Int?
    /// A fresh picture the overlay of an opening still needs, and whether it fades in over the one shown. Taken once the
    /// window has the keyboard (its buttons as they will be when it takes over), else just before it does.
    private var owed: (generation: Int, crossFade: Bool)?
    private var keyWatch: NSObjectProtocol?
    /// The morph under way, from its request to its overlay gone: its signpost interval, and the motion gate it holds.
    private var span = MorphSpan()
    /// Whether the window has the keyboard, or is about to (no banner for the Router then: you are looking at the cards).
    var isKey: Bool { window?.isKeyWindow == true || pending != nil }

    /// Shows the window in front, on `destination` when one is given (else where it was left). `card`: a Router card to pick
    /// (it opens on the Router).
    func show(_ destination: AppDestination? = nil, card: String? = nil) {
        // Until the opening's first frame is flushed (see `startOpening`), or at once when there is no morph.
        let asked = MorphSignposts.signposter.beginInterval("Open to first flush")
        defer { MorphSignposts.signposter.endInterval("Open to first flush", asked) }
        LatencySignposts.windowAsked()
        Self.active = self
        settle()
        var destination = destination
        if card != nil { destination = .router }
        if let card {
            routerModel.select(card, store: store)
            changes &+= 1
        }
        // Another place, while on its way in: the navigator says so (see `init`).
        if let destination { navigator.go(destination.resolved(shown: shownIDs, tools: store.tools)) }
        let window = self.window ?? makeWindow()
        self.window = window
        // Opened again: the kept picture is wanted after all.
        pictureExpiry?.cancel()
        pictureExpiry = nil
        // A window on its way out comes back from where it is (minimized on its way in included: its close's end would close
        // it otherwise); one on its way in just goes on.
        let reversing = phase == .closing && run != nil
        let arriving = phase == .opening
        let opening = !arriving && (reversing || (!window.isVisible && !AppTransition.isMiniaturized(window)))
            && AppTransition.enabled
        if !window.isVisible && !reversing && !arriving {
            if UnderTest.isRunning { window.setFrameOrigin(UnderTest.away) } else { moveToBarScreen(window) }
        }
        // The bar as it is now, before whoever called us hides it.
        let morph = opening && !reversing && !AppTransition.reduceMotion ? bar() : nil
        if opening {
            window.alphaValue = 0
            window.ignoresMouseEvents = true
            startOpening(window, bar: morph, reversing: reversing)
        } else {
            // One on its way in with its window still to come gets it then.
            if pending == nil { bringIn(window) }
        }
        // The app regular and asked to the front in this turn, after the opening's first frame is submitted: the activation
        // (the window's keyboard, and so the opening's fresh picture, wait for it) goes on while the window is brought in,
        // rather than being asked only once it is.
        AppPolicy.update(windowOpen: true)
        AppPolicy.activate()
        // A card picked on the way in: the place may be the same, what it shows is not.
        if card != nil, arriving { contentChanged() }
        watchKeys()
        watchInput()
        watchFront()
        reportFront()
    }

    /// The window and its content made ahead of a first open, at idle, so that open only brings them in (see `bringIn`): the
    /// window is not ordered in, the app's policy and the bar are not told, and the content is built and laid out at the
    /// window's size, then taken out of it again, where it stands still as after a close. A content that was never in a
    /// window would not: laid out, it runs its body and appearing and redraws on every change of the store behind it. No-op
    /// once the content exists or while the window is open or on its way. No close is involved, so nothing a close leaves
    /// for later (see `windowWillClose`) is either.
    func prepare() {
        guard content == nil, phase == .idle, pending == nil, window?.isVisible != true, !memoryShort else { return }
        settle()
        let window = self.window ?? makeWindow()
        self.window = window
        let content = makeContent(size: window.contentRect(forFrameRect: window.frame).size)
        self.content = content
        seedCorner(window)
        window.contentViewController = content
        content.view.layoutSubtreeIfNeeded()
        window.contentViewController = nil
    }

    /// What shows the window: its content (built once, kept across closes), the window in front with the keyboard (once the
    /// app is active: `show` asks for that). The heavy part of an opening, which waits until its morph's first frame has
    /// been submitted.
    private func bringIn(_ window: NSWindow) {
        let signpost = MorphSignposts.signposter.beginInterval("Bring in")
        defer { MorphSignposts.signposter.endInterval("Bring in", signpost) }
        if window.contentViewController == nil {
            // The window takes its content's size: kept content is given the window's as it is now (it may have been fitted
            // to a smaller screen since), new content is made at it.
            let size = window.contentRect(forFrameRect: window.frame).size
            let content = self.content ?? makeContent(size: size)
            if content.view.frame.size != size { content.view.setFrameSize(size) }
            self.content = content
            seedCorner(window)
            // What changed while it was out is drawn as it is now, not played as it goes back in: from before the window takes
            // it until it has been laid out and drawn, and a turn after.
            WindowArrival.appWindow.arrive(laying: content.view)
            window.contentViewController = content
        }
        Self.broughtIn.add(self)
        window.makeKeyAndOrderFront(nil)
    }

    /// The window opens: the overlay grows out of the bar's cell (or picks up from where a close had got to) while the real
    /// window waits at its frame, invisible; then the real window takes over under the overlay. The motion comes first: the
    /// overlay starts on the picture kept from the last close (or the window's bare surface) and its first frame is flushed
    /// to the render server (submitted: drawn as soon as the server can) before the window is built and brought in, a turn
    /// later, which gives it a fresh picture.
    private func startOpening(_ window: NSWindow, bar: BarMorph?, reversing: Bool) {
        phase = .opening
        // Work that can wait holds until the window has handed over (`handedOver`), or a close that takes over ends.
        span.begin("Open")
        generation += 1
        let mine = generation
        stopKeepingPicture()
        let current: AppTransition.Run?
        let chrome = glassWindow(window)
        let glass = AppTransition.usesGlass
        // Taken in another appearance, at another size or scale, with the sidebar folded otherwise: not even for a moment.
        let kept = closedPicture.flatMap { $0.fits(window, glass: glass, sidebar: chrome.sidebar) ? $0 : nil }
        if reversing, let run {
            // Keep the overlay's bounds and coordinate origin for the whole trip, including this reversal.
            current = run
        } else {
            run?.end()
            current = AppTransition.makeRun(for: window, picture: kept, bar: bar, glassWindow: chrome, glass: glass)
        }
        run = current
        guard let current else {
            bringIn(window)
            reveal(window)
            finishOpening(mine)
            return
        }
        // Whatever the overlay starts on is checked against the window once it is in and has the keyboard (`payPicture`): a
        // picture still the window's stays, another is taken when it can be in before the handoff, faded in over the one
        // shown (none, another place's, or one the window has moved on from since: the store, a message or a card asked
        // for while it was closed or on its way out).
        let other = current.shows != navigator.selection
        pending = mine
        owed = (generation: mine, crossFade: reversing || other || kept == nil)
        current.open(reduced: AppTransition.reduceMotion || current.bar == nil) { [weak self, weak window] in
            guard let self, let window, self.generation == mine else { return }
            // The real window must be in before it takes over. No picture is taken now: it would hold the handoff up. The
            // overlay cuts to the real window when its picture is the window as drawn now, and fades into it otherwise.
            self.bringInPending(mine)
            self.owed = nil
            self.stopKeyWatch()
            // Looked at again whatever was checked before (a few ms, within the handoff's two-refresh lead): what the
            // window's appearing changed a turn after the last look must not pop as the overlay cuts away.
            let exact = current.picture?.exact == true && current.glance != nil
                && AppTransition.glance(of: window)?.same(as: current.glance) == true
            // Work that can wait goes once the real window shows (the overlay's shadow fades on the render server).
            current.handoff(fading: !exact, reveal: { self.reveal(window) }, handedOver: { self.handedOver(mine) },
                            finished: { self.finishOpening(mine) })
        }
        // The motion submitted to the render server, nothing captured or built yet: the rest waits a turn.
        AppTransition.flushInitial()
        AppTransition.nextTurn { [weak self] in self?.bringInPending(mine) }
    }

    /// The window of the opening `mine` brought in, if it is not yet.
    private func bringInPending(_ mine: Int) {
        guard pending == mine, generation == mine, phase == .opening, let window else { return }
        pending = nil
        bringIn(window)
        payPicture(mine)
    }

    /// The picture the opening `mine` shows checked against its window, once the window is in and has the keyboard (the
    /// app becomes active a little after it is asked to: the check waits for it, as the picture would): still the window
    /// as drawn (a glance, a few ms), it stays; otherwise a fresh one is taken if it can be in before the handoff (by what
    /// pictures cost lately), else the handoff fades into the real window from what the overlay shows.
    private func payPicture(_ mine: Int) {
        guard let owed, owed.generation == mine, generation == mine, pending == nil, let window, let run else { return }
        // The overlay has let go of its picture: the real window shows itself, nothing is owed.
        guard !run.handedOver else {
            self.owed = nil
            stopKeyWatch()
            return
        }
        guard AppTransition.isKey(window) else {
            guard keyWatch == nil else { return }
            keyWatch = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                              queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.stopKeyWatch()
                    self?.payPicture(mine)
                }
            }
            return
        }
        self.owed = nil
        stopKeyWatch()
        let now = AppTransition.glance(of: window)
        let first = checked != mine
        checked = mine
        let marks = self.marks
        let fresh = run.picture.map {
            AppTransition.freshness(of: $0, glance: now, marks: marks, destination: navigator.selection,
                                    tolerance: AppTransition.Glance.openTolerance)
        } ?? .stale
        if fresh == .same, run.picture?.exact == true { return }
        // Just brought in, the window may still be drawing what changed while it was out (its appearing runs a turn
        // later): the first look is taken again a turn on before a picture is.
        if fresh == .stale, run.image != nil, first {
            self.owed = owed
            AppTransition.nextTurn { [weak self] in self?.payPicture(mine) }
            return
        }
        // The handoff is never held up for a picture: one sure to be in before it (by the most such pictures have cost),
        // else for a window that moved on a softer one sure to be (the handoff then fades from it), else none (the
        // handoff fades from what shows). A picture off by noise only, or soft, is taken again only at full scale.
        let fade = owed.crossFade ? AppTransition.pictureFade * Double(AppTransition.slowdown) : 0
        let full = window.backingScaleFactor, soft = AppTransition.reducedScale(of: window)
        let scale: CGFloat
        if AppTransition.pictureFits(window, pixelScale: full, before: run.settlesAt, after: fade) {
            scale = full
        } else if fresh == .stale, soft < full,
                  AppTransition.pictureFits(window, pixelScale: soft, before: run.settlesAt, after: fade) {
            scale = soft
        } else {
            self.owed = owed
            run.fadeHandoff()
            return
        }
        refresh(run, window, crossFade: owed.crossFade, glance: now, pixelScale: scale)
        if run.picture?.exact != true { run.fadeHandoff() }
    }

    /// What may have changed the window since a picture was taken, besides its pixels (see `AppTransition.Marks`).
    var marks: AppTransition.Marks {
        AppTransition.Marks(changes: changes, inbox: store.inboxRevision, inboxDisplay: store.inboxDisplayRevision,
                            router: store.routerRevision)
    }

    /// Counts the user's input to the window (a key, a click, a scroll; not the pointer's moves, whose hovers are noise),
    /// for `marks`.
    private func watchInput() {
        guard inputWatch == nil else { return }
        inputWatch = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                                                 .scrollWheel]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return }
                self.changes &+= 1
                self.nudgeKeeper()
            }
            return event
        }
    }

    /// The overlay's picture taken again, of the place the window shows now (`glance`: the window's, taken just before;
    /// `pixelScale`: see `AppTransition.takePicture`).
    private func refresh(_ run: AppTransition.Run, _ window: NSWindow, crossFade: Bool = false,
                         glance: AppTransition.Glance? = nil, pixelScale: CGFloat? = nil) {
        run.refresh(window, destination: navigator.selection, crossFade: crossFade, glance: glance, pixelScale: pixelScale,
                    marks: marks)
    }

    /// While the window is open, in front and has the keyboard (started as it opens or becomes key, stopped as it resigns
    /// it or closes), its picture is kept the window as drawn, so a close starts on it at once with nothing captured:
    /// half a second after it starts then about every second, once nothing was pressed or moved for three times what a
    /// picture would cost (half a second at least), and no text is being composed, a glance says whether the window still
    /// is what `closedPicture` shows, and when it isn't a picture is taken there and then, soft when a sharp one would
    /// cost over `idleCaptureBudget`, at most a twentieth of the main thread's time (`mayCaptureAtIdle`). Not short of
    /// memory.
    func keepPictureFresh() {
        guard AppTransition.enabled else { return }
        keeping = true
        keeperPace = Self.keeperPaces.shortest
        scheduleKeeper(after: keeperPace)
    }

    /// The keeper's looks: every half second while the window changes, twice as far apart (up to 4 s) each look that
    /// finds nothing to do; back to half a second on the user's input.
    static let keeperPaces = (shortest: 0.5, longest: 4.0)

    private func scheduleKeeper(after delay: TimeInterval) {
        pictureKeeper?.invalidate()
        // One look at a time: a controller gone takes its keeper with it, as no further look is asked.
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] timer in
            guard let self else { return timer.invalidate() }
            MainActor.assumeIsolated {
                self.pictureKeeper = nil
                self.keepPicture()
            }
        }
        timer.tolerance = delay / 4
        // The default mode only: not while a scroll, a drag or a menu tracks.
        RunLoop.main.add(timer, forMode: .default)
        pictureKeeper = timer
    }

    private func stopKeepingPicture() {
        keeping = false
        restGlance = nil
        pictureKeeper?.invalidate()
        pictureKeeper = nil
    }

    /// The user did something to the window: the keeper looks again soon.
    private func nudgeKeeper() {
        guard keeping else { return }
        keeperPace = Self.keeperPaces.shortest
        if let fire = pictureKeeper?.fireDate, fire.timeIntervalSinceNow <= keeperPace { return }
        scheduleKeeper(after: keeperPace)
    }

    /// How far apart the keeper's looks are now (see `keeperPaces`).
    private(set) var keeperPace = keeperPaces.shortest

    /// The kept picture let go once the window has stayed closed `after` (an opening calls it off).
    private func expireKeptPicture(after: TimeInterval) {
        pictureExpiry?.cancel()
        let expiry = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.phase == .idle, self.window?.isVisible != true else { return }
                self.closedPicture = nil
                self.pictureExpiry = nil
            }
        }
        pictureExpiry = expiry
        DispatchQueue.main.asyncAfter(deadline: .now() + after, execute: expiry)
    }

    /// Whether the kept picture is a soft one (see `AppTransition.reducedScale`).
    var keptPictureIsSoft: Bool { closedPicture?.exact == false }

    /// Whether the kept picture is to be let go (the window closed, and not opened since).
    var keptPictureExpires: Bool { pictureExpiry != nil }

    /// The idle keeper's timer, while it runs (the tests look).
    var keeperTimer: Timer? { pictureKeeper }

    /// One look of the idle keeper (see `keepPictureFresh`).
    func keepPicture() {
        defer { if keeping, pictureKeeper == nil { scheduleKeeper(after: keeperPace) } }
        func slower() { keeperPace = min(keeperPace * 2, Self.keeperPaces.longest) }
        guard let window, window.isVisible else { return stopKeepingPicture() }
        guard phase == .idle, !memoryShort, AppTransition.isFront(window), AppTransition.isKey(window), !MotionGate.moving,
              !AppTransition.composing(in: window) else { return }
        let full = window.backingScaleFactor
        let scale = AppTransition.estimate(window, pixelScale: full) > AppTransition.idleCaptureBudget
            ? AppTransition.reducedScale(of: window) : full
        let cost = AppTransition.estimate(window, pixelScale: scale)
        // Idle long enough that a key typed after a pause like this one is not likely to wait on the picture.
        guard AppTransition.inputIdle(max(0.5, 3 * cost)) else {
            keeperPace = Self.keeperPaces.shortest
            return
        }
        let chrome = glassWindow(window)
        let glass = AppTransition.usesGlass
        let marks = self.marks
        let kept = closedPicture.flatMap {
            $0.fits(window, glass: glass, sidebar: chrome.sidebar) && $0.destination == navigator.selection ? $0 : nil
        }
        // As good as the keeper would make it (sharp, or soft when sharp costs too much).
        let good = kept.map { $0.exact || scale < full } ?? false
        // Nothing typed, clicked, asked or synced since the kept picture: it still stands, with no glance (what moved
        // since is the window's own noise, a ticking duration or the thinking dots, which a close forgives).
        if let kept, good, kept.marks == marks { return slower() }
        let now = AppTransition.glance(of: window)
        if let kept, good, now?.same(as: kept.glance) == true {
            closedPicture?.marks = marks
            return slower()
        }
        // A picture only of a window at rest: two looks in a row alike (but for noise), nothing happening between.
        guard let rest = restGlance, rest.marks == marks,
              now?.within(AppTransition.Glance.closeTolerance, of: rest.glance) == true else {
            restGlance = now.map { ($0, marks) }
            keeperPace = Self.keeperPaces.shortest
            return
        }
        guard AppTransition.mayCaptureAtIdle(cost: cost) else { return }
        if let picture = AppTransition.picture(of: window, glassWindow: chrome, glass: glass,
                                               destination: navigator.selection, glance: now, pixelScale: scale,
                                               marks: marks) {
            closedPicture = picture
            restGlance = nil
            slower()
        }
    }

    /// What an opening's window shows changed after its overlay's picture was taken (another place, a card, a row or a
    /// section asked for): a fresh one fades in over it, a turn later (once the change has been drawn), at the latest as
    /// the real window takes over. Not once it has (its live pixels show).
    private func contentChanged() {
        // Asked of the window open or not: no picture taken before stands for it, whatever its pixels.
        changes &+= 1
        guard phase == .opening, let run, !run.handedOver else { return }
        let mine = generation
        owed = (mine, crossFade: true)
        AppTransition.nextTurn { [weak self] in self?.payPicture(mine) }
    }

    private func stopKeyWatch() {
        if let keyWatch { NotificationCenter.default.removeObserver(keyWatch) }
        keyWatch = nil
    }

    /// What the glass morph needs of `window`: its capture flag, and its inset sidebar's frame (none during the onboarding,
    /// nor before macOS 26).
    private func glassWindow(_ window: NSWindow) -> AppTransition.GlassWindow {
        var sidebar: NSRect?
        if #available(macOS 26, *), store.settings.toolsPicked == true {
            sidebar = GlassMorph.sidebarFrame(windowSize: window.frame.size, collapsed: SidebarState.shared.collapsed)
        }
        return AppTransition.GlassWindow(capture: capture, sidebar: sidebar)
    }

    /// The real window, shown (under the overlay), with the keyboard.
    private func reveal(_ window: NSWindow) {
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.makeKeyAndOrderFront(nil)
    }

    /// The opening `mine` has handed over: its interval ends and the motion gate opens.
    private func handedOver(_ mine: Int) {
        guard generation == mine else { return }
        span.end()
    }

    private func finishOpening(_ mine: Int) {
        guard generation == mine else { return }
        stopKeyWatch()
        // The picture the overlay handed over on is kept as it was taken (with the glance of what it shows), so a close at
        // once starts on it when the window is still that (near enough); the idle keeper takes another once it has moved on.
        if let picture = run?.picture, picture.key, picture.glance != nil, !memoryShort {
            closedPicture = picture
        } else {
            closedPicture = nil
        }
        run = nil
        phase = .idle
        span.end()
        keepPictureFresh()
        reportFront()
    }

    func close() {
        // An opening whose window is not in yet: in now, so there is a window to close.
        if let pending { bringInPending(pending) }
        window?.performClose(nil)
    }

    /// Closing morphs the window into the bar: an overlay takes the window's place first, then the real window goes and the
    /// overlay shrinks into the bar's cell, then it really closes.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard AppTransition.enabled, phase != .closing, phase == .opening || isFront else { return phase != .closing }
        // Until the close's first frame is flushed: the time to the first moving frame.
        let asked = MorphSignposts.signposter.beginInterval("Close to first flush")
        // An opening whose overlay has let go of its picture shows the real window already: it closes as an open one does.
        let interrupting = phase == .opening && run?.handedOver != true
        // One that has let go but whose overlay is still fading out over the real window (its picture, or its shadow):
        // the close takes that overlay over, rather than dropping it half faded.
        let fading = phase == .opening && !interrupting && run?.ended == false ? run : nil
        phase = .closing
        // Held until the overlay is gone (`finishClosing`), or an opening that turns it round has handed over.
        span.begin("Close")
        generation += 1
        let mine = generation
        pending = nil
        owed = nil
        stopKeyWatch()
        sender.ignoresMouseEvents = true
        stopKeepingPicture()
        let existing = interrupting ? run : nil
        let current: AppTransition.Run?
        let chrome = glassWindow(sender)
        if let existing {
            current = existing
        } else {
            if fading == nil { run?.end() }
            let glass = AppTransition.usesGlass
            let barMorph = AppTransition.reduceMotion ? nil : bar()
            // The picture kept at idle, when the window is still (near enough, `Glance.closeTolerance`) as it was drawn
            // then: the close starts on it at once. Otherwise a soft one is taken now, before anything moves.
            let now = AppTransition.glance(of: sender)
            let picture: AppTransition.Picture?
            if let kept = closedPicture, kept.fits(sender, glass: glass, sidebar: chrome.sidebar), AppTransition.isKey(sender),
               AppTransition.freshness(of: kept, glance: now, marks: marks, destination: navigator.selection,
                                       tolerance: AppTransition.Glance.closeTolerance) != .stale {
                picture = kept
            } else {
                // Never one at the window's own scale (520 ms on heavy content): a softer one, a quarter of its pixels,
                // which the shrink and its fade (gone by half of it) hide.
                picture = AppTransition.takePicture(of: sender, glassWindow: chrome, glass: glass,
                                                    destination: navigator.selection, glance: now, restoreLater: true,
                                                    pixelScale: AppTransition.reducedScale(of: sender), marks: marks)
            }
            if let fading, let picture, fading.isGlass == glass {
                // On the overlay still fading out: back to the window's picture whole, from where it is.
                fading.takeBack(picture)
                current = fading
            } else {
                fading?.end()
                current = picture.flatMap {
                    AppTransition.makeRun(for: sender, picture: $0, bar: barMorph, glassWindow: chrome, glass: glass)
                }
            }
        }
        guard let current else {
            MorphSignposts.signposter.endInterval("Close to first flush", asked)
            finishClosing(sender, mine)
            return false
        }
        run = current
        // Kept for the next opening to start on, when it was taken with the window key, as it was taken (an opening cut
        // short may still show the place, the sidebar or the size it started on), unless memory is short.
        if !memoryShort, let picture = current.picture, picture.key { closedPicture = picture }
        if !interrupting {
            // The overlay shows the window before the real one goes, in this turn: its frame is submitted to the render
            // server ahead of the window going, which reaches the server after it, so no frame shows neither.
            current.present()
            CATransaction.flush()
        }
        // Out of sight at once (a window's alpha is cheap); ordered out only once the motion is submitted, as ordering a
        // key window out takes some 11 ms (its key and main status handed on). After the overlay's flush, not inside its
        // transaction: if AppKit sends the alpha with the next commit, it lands with or after the overlay either way; if it
        // sends it at once, only this order has the overlay's frame reach the server first.
        sender.alphaValue = 0
        current.close(reduced: AppTransition.reduceMotion || current.bar == nil) { [weak self, weak sender] in
            guard let self, let sender, self.generation == mine else { return }
            self.finishClosing(sender, mine)
        }
        MorphSignposts.signposter.endInterval("Close to first flush", asked)
        if generation == mine { sender.orderOut(nil) }
        if generation == mine { onClosing?() }
        return false
    }

    private func finishClosing(_ window: NSWindow, _ mine: Int) {
        guard generation == mine else { return }
        run?.end()
        run = nil
        phase = .idle
        span.end()
        window.orderOut(nil)
        window.alphaValue = 1
        window.ignoresMouseEvents = false
        window.close()
    }

    /// Whether the window is in front of the user: the app is active and the window is on screen and not covered.
    var isFront: Bool { isFront(active: NSApp.isActive) }

    func isFront(active: Bool) -> Bool {
        guard active, let window, window.isVisible, !window.isMiniaturized else { return false }
        return window.occlusionState.contains(.visible)
    }

    /// Tells `onFront` when that changes. `active` is passed by the notifications that know it before `NSApp` does.
    func reportFront(active: Bool = NSApp.isActive) {
        guard phase == .idle else { return }
        let front = isFront(active: active)
        guard front != lastFront else { return }
        lastFront = front
        onFront?(front)
    }

    private func watchFront() {
        guard observers.isEmpty, let window else { return }
        let center = NotificationCenter.default
        func watch(_ name: Notification.Name, object: AnyObject?, active: Bool? = nil) {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let active { self?.reportFront(active: active) } else { self?.reportFront() }
                }
            })
        }
        watch(NSApplication.didResignActiveNotification, object: nil, active: false)
        watch(NSApplication.didBecomeActiveNotification, object: nil, active: true)
        watch(NSWindow.didChangeOcclusionStateNotification, object: window)
        watch(NSWindow.didMiniaturizeNotification, object: window)
        watch(NSWindow.didDeminiaturizeNotification, object: window)
        // Fjord Computer made active (⌘-Tab) while the window is open behind another app or minimized: the window comes
        // in front, as any app's does. The bar never makes the app active, so this is the user asking for
        // Fjord Computer.
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.raise() }
        })
    }

    private func raise() {
        guard phase == .idle, pending == nil, let window, window.isVisible || window.isMiniaturized,
              !window.isKeyWindow else { return }
        window.makeKeyAndOrderFront(nil)
    }

    /// Opening puts the window on the bar's screen, where it was left if that is the one, else at the same place relative
    /// to the screen it was on.
    private func moveToBarScreen(_ window: NSWindow) {
        guard let target = barScreen() ?? NSScreen.main else { return }
        let screens = NSScreen.screens
        let previous = screens.max { overlap(window.frame, $0.visibleFrame) < overlap(window.frame, $1.visibleFrame) }
        let from = previous.flatMap { overlap(window.frame, $0.visibleFrame) > 0 ? $0.visibleFrame : nil }
        let frame = AppWindowPlacement.frame(window.frame, from: from, in: target.visibleFrame)
        if frame != window.frame { window.setFrame(frame, display: false) }
    }

    private func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// Settings, scrolled to Updates: where Check for Updates shows what it found. The request is the window's own, so it
    /// reaches the Settings page shown here whether it opens now or was open already.
    func showUpdates() {
        show(.settings)
        hub.showUpdates()
        contentChanged()
    }

    /// An inbox entry picked and scrolled to, on its category (the archive if it was archived since): where a banner's click lands.
    func show(entry: InboxEntry) {
        show(entry.isDone ? .done : .category(entry.categoryID))
        hub.selection = "i:" + entry.id
        hub.requestScroll("i:" + entry.id)
        contentChanged()
    }

    /// A Router card picked from the bar (the window opens on the Router next).
    func pick(card: String) {
        routerModel.select(card, store: store)
        contentChanged()
    }

    /// A message the Router left asked for from the bar, scrolled to in its conversation (the window opens on the Router next).
    func pick(message: UUID) {
        routerModel.show(message: message)
        contentChanged()
    }

    /// A thing's "Open in Router" from the bar: its pill in the Router's composer (the window opens on the Router next).
    func prefillRouter(thing: String) {
        routerModel.prefill([.notification(thing)])
        contentChanged()
    }

    /// The Go menu's destinations with their titles, in the sidebar's order (none during the onboarding).
    var goItems: [GoMenuModel.Item] {
        guard store.settings.toolsPicked == true else { return [] }
        return GoMenuModel.items(AppDestination.all(shown: shownIDs, tools: store.tools)) { title(for: $0) }
    }

    func title(for destination: AppDestination) -> String {
        switch destination {
        case .category(let id): store.categories.first { $0.id == id }?.title ?? "Inbox"
        case .done: "Archive"
        case .router: "Router"
        case .settings: "Settings"
        case .categories: "Inbox categories"
        case .snippets: "Snippets"
        }
    }

    private var shownIDs: [UUID] { store.shownCategories.map(\.id) }

    /// Keeps the selection on a place that exists.
    private func settle() { navigator.settle(shown: shownIDs, tools: store.tools) }

    /// `size`: the window's content size, so that setting the content keeps the window as it is (left alone, the content
    /// would size it to its own minimum, too small to see).
    private func makeContent(size: NSSize) -> NSViewController {
        let root = AppRootView(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                               checksClaudeCode: checksClaudeCode, corner: corner, capture: capture)
        let controller = NSHostingController(rootView: root)
        // The window sizes the content, not the other way round.
        controller.sizingOptions = []
        controller.view.frame = NSRect(origin: .zero, size: size)
        return controller
    }

    private func makeWindow() -> NSWindow {
        let window = AwayWindow(contentRect: NSRect(origin: .zero, size: NSSize(width: 1180, height: 760)),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: true)
        Self.style(window)
        window.delegate = self
        if !window.setFrameUsingName(Self.autosave) { window.center() }
        window.setFrameAutosaveName(Self.autosave)
        return window
    }

    /// The window's look: dark like the bar's panels, the content running up under a transparent unified title bar.
    static func style(_ window: NSWindow) {
        window.title = "Fjord Computer"
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.appearance = Brand.appearance
        window.backgroundColor = NSColor(CDS.Surface.s1)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.allowsToolTipsWhenApplicationIsInactive = true
        TrafficLights.place(window)
    }

    /// The Router's keys (see `RouterKeys`) while the window is key and shows the Router; Esc dismisses a tooltip first.
    private func watchKeys() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let consumed = MainActor.assumeIsolated {
                // The onboarding has no page's keys: only its own fields and button.
                guard let window = self.window, window.isKeyWindow, event.window === window,
                      !self.store.isRecordingShortcut, self.store.settings.toolsPicked == true else { return false }
                if TipCenter.dismissVisible(for: event) { return true }
                return self.navigator.selection == .router ? self.keys.key(event) : self.inboxKeys.key(event)
            }
            return consumed ? nil : event
        }
    }

    // AppKit lays the window's three buttons out again on these: they go back on the header's line each time.
    func windowDidResize(_ notification: Notification) { window.map(TrafficLights.place) }
    func windowDidBecomeKey(_ notification: Notification) {
        window.map(TrafficLights.place)
        readCorner()
        // Back in front with the keyboard (after a minimize, a hide, another app): the keeper looks again.
        if phase == .idle { keepPictureFresh() }
    }
    /// Out of the keyboard: nothing to close from, so no picture to keep fresh, and no wakeups.
    func windowDidResignKey(_ notification: Notification) {
        if phase == .idle { stopKeepingPicture() }
    }
    func windowDidEnterFullScreen(_ notification: Notification) { readCorner() }
    func windowDidExitFullScreen(_ notification: Notification) {
        window.map(TrafficLights.place)
        readCorner()
    }

    /// The window's corner radius as it is now, for the root's `containerShape` (none in full screen).
    private func readCorner() {
        guard let window else { return }
        let radius = AppTransition.cornerRadius(of: window)
        if window.isVisible, !window.styleMask.contains(.fullScreen) { Self.knownRadius = radius }
        if corner.radius != radius { corner.radius = radius }
    }

    /// The radius a window shown last reported, out of full screen: the next content starts with it.
    private static var knownRadius: CGFloat?

    /// The radius the content will have, given before it goes in (or is made), so that reading it again as the window
    /// becomes key changes nothing: a change then would redraw the root's shapes in the middle of the opening.
    private func seedCorner(_ window: NSWindow) {
        let radius = window.styleMask.contains(.fullScreen) ? 0 : Self.knownRadius ?? AppTransition.cornerRadius(of: window)
        if corner.radius != radius { corner.radius = radius }
    }

    func windowWillClose(_ notification: Notification) {
        // Every close, a morph's or not (a window closed out of sight): the keeper stops, the picture is let go in a while.
        stopKeepingPicture()
        expireKeptPicture(after: Self.keptPictureLife)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let inputWatch { NSEvent.removeMonitor(inputWatch) }
        inputWatch = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        lastFront = nil
        routerModel.composerFocused = false
        // The bar returns before taking the content out and changing the policy, so its fade starts before that work.
        // Not if the window was opened again meanwhile (on its way in, it is not visible yet), or from the callback.
        let closed = generation
        AppTransition.nextTurn { [weak self] in
            guard let self, self.generation == closed, self.phase == .idle, self.pending == nil,
                  self.window?.isVisible != true else { return }
            self.onClose?()
            guard self.generation == closed, self.phase == .idle, self.pending == nil,
                  self.window?.isVisible != true else { return }
            AppTransition.nextTurn { [weak self] in
                guard let self, self.generation == closed, self.phase == .idle, self.pending == nil,
                      self.window?.isVisible != true else { return }
                // The content leaves the window, which stops it; kept for the next open, it no longer ticks while closed.
                self.window?.contentViewController = nil
                // Short of memory: not kept either (it was still in the window as the pressure came).
                if self.memoryShort { self.releaseKept() }
                // Only the last window's close puts the app back to the bar only: one closing late (its work is deferred)
                // must not take the policy from another that has opened since. Asked of the windows themselves, so a close
                // whose tidying never came (or a controller gone) leaves nothing behind that reads as open.
                Self.broughtIn.remove(self)
                // An opening's activation landing after the close gave the keyboard back gives it back again as it lands
                // (`AppPolicy.onActivation`); active already with that notice still to come, it goes back here.
                if AppPolicy.yieldsAtTidy(active: NSApp.isActive, windowShown: Self.anyShown,
                                          pending: AppPolicy.activationPending) { AppPolicy.yieldFocus() }
                AppPolicy.update(windowOpen: Self.broughtIn.allObjects.contains { $0.isOpen })
            }
        }
    }
}

/// The window's three buttons on the 48pt header's line, where the sidebar toggle, back, forward and the page's title are:
/// AppKit centres them in its own 28pt title bar, 8pt higher. The title bar's container grows to the header's height and
/// the buttons sit in its middle, as far from the window's edge as from its top.
enum TrafficLights {
    static let spacing: CGFloat = 20

    static func place(_ window: NSWindow) {
        guard !window.styleMask.contains(.fullScreen),
              let close = window.standardWindowButton(.closeButton),
              let container = close.superview?.superview else { return }
        let height = CDS.TitleBar.header
        container.frame = NSRect(x: container.frame.minX, y: window.frame.height - height,
                                 width: container.frame.width, height: height)
        let inset = ((height - close.frame.height) / 2).rounded()
        for (i, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            window.standardWindowButton(kind)?.setFrameOrigin(NSPoint(x: inset + CGFloat(i) * spacing, y: inset))
        }
    }

    /// Where the three end, from the window's edge.
    static var end: CGFloat { ((CDS.TitleBar.header - 14) / 2).rounded() + 2 * spacing + 14 }
}

/// Where the window goes when it opens on a screen.
enum AppWindowPlacement {
    /// `frame` on the screen whose usable area is `visible`. Kept (inside the screen) when its centre is already there;
    /// else the same relative place as on `from` (the area of the screen it was on), centred when that is unknown. Never
    /// larger than the screen.
    static func frame(_ frame: NSRect, from: NSRect?, in visible: NSRect) -> NSRect {
        let size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        var center = NSPoint(x: frame.midX, y: frame.midY)
        if !visible.contains(center) {
            if let from, from.width > 0, from.height > 0 {
                center = NSPoint(x: visible.minX + (center.x - from.minX) / from.width * visible.width,
                                 y: visible.minY + (center.y - from.minY) / from.height * visible.height)
            } else {
                center = NSPoint(x: visible.midX, y: visible.midY)
            }
        }
        let x = min(max(center.x - size.width / 2, visible.minX), visible.maxX - size.width)
        let y = min(max(center.y - size.height / 2, visible.minY), visible.maxY - size.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}

private extension InboxTab {
    var categoryID: UUID? {
        if case .category(let id) = self { return id }
        return nil
    }
}

extension RouterModel {
    /// "Open in Router" on an inbox thing: its pill in the composer (after what the draft holds), and `navigator` on the
    /// Router. The composer takes the keyboard, its caret after the pill, also when the page is made only now.
    func open(thing: String, in navigator: AppNavigator) {
        prefill([.notification(thing)])
        navigator.go(.router)
    }
}

/// The window's corner radius as the window reports it (`AppTransition.cornerRadius(of:)`): read when it becomes key and
/// on entering and leaving full screen, where it is 0.
@MainActor @Observable
final class WindowCorner {
    var radius: CGFloat

    init(radius: CGFloat = AppTransition.fallbackRadius) { self.radius = radius }
}

/// The window's root: the sidebar and the destination side by side, as Claude's Code tab lays them out (a split view
/// would draw the system's floating sidebar). The window's buttons sit over the sidebar's top; the sidebar toggle, back and
/// forward over the content's. On macOS 26 the sidebar is an inset panel and the page rides the fold (`InsetWindowLayout`).
struct AppRootView: View {
    let store: Store
    let navigator: AppNavigator
    let routerModel: RouterModel
    let hub: HubState
    let search: InboxSearch
    let checksClaudeCode: Bool
    let sidebar: SidebarState
    /// How the sidebar and the floating controls draw: the app's, or a fixed one in tests and shots.
    let chrome: Chrome
    /// The window's corner radius, which the shapes inside it are concentric with.
    let corner: WindowCorner
    /// The window's capture flag (`GlassCapture`): none in shots and tests, which draw no glass to capture.
    let capture: GlassCapture?

    static let sidebarWidth: CGFloat = 240

    /// What the window's lists do to it, made once with the root: the same closures on every update, so the environment
    /// that carries them never tells the views that read them (each row) that they changed.
    private let actions: AppRootActions

    @MainActor
    init(store: Store, navigator: AppNavigator, routerModel: RouterModel, hub: HubState, search: InboxSearch? = nil,
         checksClaudeCode: Bool = true, sidebar: SidebarState = .shared, chrome: Chrome = .shared,
         corner: WindowCorner? = nil, capture: GlassCapture? = nil) {
        self.store = store
        self.navigator = navigator
        self.routerModel = routerModel
        self.hub = hub
        self.search = search ?? InboxSearch()
        self.checksClaudeCode = checksClaudeCode
        self.sidebar = sidebar
        self.chrome = chrome
        self.corner = corner ?? WindowCorner()
        self.capture = capture
        actions = AppRootActions(store: store, navigator: navigator, routerModel: routerModel, hub: hub)
    }

    // Reads nothing that changes: what does is read by the small pieces below (the page, the corner, the follow-ups and the
    // Router's offer), so a settings write, a corner read when the window becomes key or a category's change redraws them
    // alone, not the root and every reader of its environment.
    var body: some View {
        AppRootPage(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                    checksClaudeCode: checksClaudeCode, sidebar: sidebar, chrome: chrome)
            .frame(minWidth: 640, minHeight: 600)
            .environment(chrome)
            .environment(\.glassCapture, capture)
            // A shape inside the window can be concentric with its corners (`ConcentricRectangle`, `Theme.Radius.concentric`).
            .modifier(WindowCornerShape(corner: corner))
            .foregroundStyle(Theme.text)
            .modifier(Brand.Scheme())
            .tipSpace()
            .ignoresSafeArea(.container, edges: .top)
            .background(CDS.Surface.s1)
            .modifier(AppRootFollow(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search))
            .environment(\.openRouter, actions.openRouter)
            .environment(\.pickRouterCard, actions.pickRouterCard)
            // Chips in the window's own lists: a place, or the Router on the message an action left in its conversation.
            .environment(\.openApp, actions.openApp)
            .environment(\.openRouterMessage, actions.openRouterMessage)
            .environment(\.openChange, actions.openChange)
            .modifier(AppRootRouterOffer(store: store, openInRouter: actions.openInRouter))
            // Its content put back in after a close draws what changed meanwhile as it is (`WindowArrival`).
            .windowArrival()
    }
}

/// The window's actions on itself, for its lists' chips, cards and changes (see `AppRootView.actions`).
@MainActor
final class AppRootActions {
    let openRouter: (String?) -> Void
    let pickRouterCard: (String) -> Void
    let openInRouter: (String) -> Void
    let openApp: (AppDestination) -> Void
    let openRouterMessage: (UUID) -> Void
    let openChange: (FjordChange) -> Void

    init(store: Store, navigator: AppNavigator, routerModel: RouterModel, hub: HubState) {
        openRouter = { card in
            if let card { routerModel.select(card, store: store) }
            navigator.go(.router)
        }
        pickRouterCard = { card in routerModel.select(card, store: store) }
        openInRouter = { routerModel.open(thing: $0, in: navigator) }
        openApp = { navigator.go($0.resolved(shown: store.shownCategories.map(\.id), tools: store.tools)) }
        openRouterMessage = { message in
            routerModel.show(message: message)
            navigator.go(.router)
        }
        openChange = { change in
            switch change.target(in: store) {
            case .category(let id): navigator.go(.categories); hub.openCategory(id)
            case .group(let id): navigator.go(.categories); hub.openGroup(id)
            case .categories: navigator.go(.categories)
            case .settings(let section):
                navigator.go(.settings)
                hub.settingsScroll = ScrollRequest(id: section, seq: (hub.settingsScroll?.seq ?? 0) + 1)
            case .entry(let thing, let category, let isDone):
                navigator.go(isDone ? .done : (category.map { .category($0) } ?? .done))
                hub.selection = "i:" + thing
                hub.requestScroll("i:" + thing)
            }
        }
    }
}

/// The window's corners for the shapes inside it, read here alone: a new radius redraws what is concentric with them.
private struct WindowCornerShape: ViewModifier {
    let corner: WindowCorner

    func body(content: Content) -> some View { content.containerShape(.rect(cornerRadius: corner.radius)) }
}

/// A row's "Open in Router", while the Router is on: the one value of the root's environment that follows the store.
private struct AppRootRouterOffer: ViewModifier {
    let store: Store
    let openInRouter: (String) -> Void

    func body(content: Content) -> some View {
        content.environment(\.openInRouter, store.offers(.openInRouter) ? openInRouter : nil)
    }
}

/// What the window keeps in step as the store and the place change: the place settled on one that exists, and another
/// place's own pick and search.
private struct AppRootFollow: ViewModifier {
    let store: Store
    let navigator: AppNavigator
    let routerModel: RouterModel
    let hub: HubState
    let search: InboxSearch

    func body(content: Content) -> some View {
        content
            .onChange(of: store.shownCategories.map(\.id)) { _, shown in navigator.settle(shown: shown, tools: store.tools) }
            // Another place has its own pick and search; a row asked for there (a banner's click) stays.
            .onChange(of: navigator.selection) { _, place in
                search.end()
                routerModel.endSearch()
                if let pick = hub.selection, let tab = place.tab, store.entries(in: tab).contains(where: { "i:" + $0.id == pick }) { return }
                hub.selection = nil
                hub.keyboardSelection = nil
            }
            .onChange(of: store.tools) { _, tools in navigator.settle(shown: store.shownCategories.map(\.id), tools: tools) }
    }
}

/// The window's page: the onboarding until the tools are picked, then the sidebar and the destination.
private struct AppRootPage: View {
    let store: Store
    let navigator: AppNavigator
    let routerModel: RouterModel
    let hub: HubState
    let search: InboxSearch
    let checksClaudeCode: Bool
    let sidebar: SidebarState
    let chrome: Chrome

    var body: some View {
        if store.settings.toolsPicked == true {
            if #available(macOS 26, *) {
                InsetWindowLayout(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                                  checksClaudeCode: checksClaudeCode, sidebar: sidebar, chrome: chrome)
            } else {
                flat(collapsed: sidebar.collapsed)
            }
        } else {
            OnboardingView(store: store) {
                store.settings.toolsPicked = true
                navigator.go(store.firstPlace.resolved(shown: store.shownCategories.map(\.id), tools: store.tools))
            }
        }
    }

    /// macOS 14 and 15: the flat sidebar beside the page, the top bar the sidebar's ground the whole width. The sidebar
    /// toggle, back and forward stay put after the window's three buttons: over the sidebar when it is out, at the
    /// content's start when it is a rail, the page's title after them. The room follows the sidebar's width on the same
    /// spring (an implicit animation here would end up fighting the explicit one).
    private func flat(collapsed: Bool) -> some View {
        let headerInset = collapsed ? AppNavButtons.end - AppSidebar.railWidth : 0
        return HStack(spacing: 0) {
            AppSidebar(store: store, navigator: navigator, hub: hub, collapsed: collapsed)
                .padding(.top, CDS.TitleBar.header)
                .frame(width: collapsed ? AppSidebar.railWidth : AppRootView.sidebarWidth, alignment: .leading)
                .frame(maxHeight: .infinity)
                .clipped()
                .background(CDS.Surface.sidebar)
                // Its edge starts under the top bar: the window's three buttons sit above it.
                .overlay(alignment: .trailing) {
                    Rectangle().fill(CDS.border).frame(width: CDS.Sidebar.edge).padding(.top, CDS.TitleBar.header)
                }
            AppContent(store: store, navigator: navigator, routerModel: routerModel, hub: hub, search: search,
                       checksClaudeCode: checksClaudeCode, leadingInset: headerInset)
        }
        // The top bar: the sidebar's ground the whole width (the pages draw theirs under it), a rule beneath.
        .background(alignment: .top) { CDS.Surface.sidebar.frame(height: CDS.TitleBar.header) }
        .overlay(alignment: .top) {
            Rectangle().fill(CDS.border).frame(height: CDS.Sidebar.edge)
                .padding(.top, CDS.TitleBar.header - CDS.Sidebar.edge)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            AppNavButtons(navigator: navigator,
                          sidebarShown: Binding(get: { !sidebar.collapsed }, set: { sidebar.set(collapsed: !$0) }))
                .padding(.leading, AppNavButtons.leading)
                .frame(height: CDS.TitleBar.header)
        }
    }
}

/// Sidebar toggle, back and forward: Claude's 26pt ghost icon buttons, 4 apart.
struct AppNavButtons: View {
    let navigator: AppNavigator
    @Binding var sidebarShown: Bool
    /// Their start, from the window's edge: just after the window's three buttons.
    static var leading: CGFloat { TrafficLights.end + 10 }
    /// What the three buttons take, with the gaps.
    static let width: CGFloat = 3 * CDS.TitleBar.button + 2 * CDS.TitleBar.buttonGap
    /// Their end, from the window's edge.
    static var end: CGFloat { leading + width }
    /// On macOS 26 the room round them on the title line, and their width with it.
    static let capsulePad: CGFloat = 3
    static var capsuleWidth: CGFloat { width + 2 * capsulePad }

    var body: some View {
        HStack(spacing: CDS.TitleBar.buttonGap) {
            AppIconButton(symbol: "sidebar.left", help: sidebarShown ? "Hide sidebar" : "Show sidebar", key: "⌘B", enabled: true) {
                sidebarShown.toggle()
            }
            AppIconButton(symbol: "chevron.left", help: "Back", key: "⌘[", enabled: navigator.canGoBack) { navigator.back() }
            AppIconButton(symbol: "chevron.right", help: "Forward", key: "⌘]", enabled: navigator.canGoForward) { navigator.forward() }
        }
    }
}

struct AppIconButton: View {
    let symbol: String
    let help: String
    /// Its shortcut, shown in its tooltip.
    var key: String? = nil
    let enabled: Bool
    let action: () -> Void
    @State private var hovered = false
    /// On glass: label styles and `ChromeFill`'s ink steps rather than Claude's fixed inks and fills.
    @Environment(\.onGlass) private var onGlass
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: CDS.Sidebar.symbol, weight: .medium))
                .foregroundStyle(ink)
                .frame(width: CDS.TitleBar.button, height: CDS.TitleBar.button)
                .background(RoundedRectangle(cornerRadius: CDS.Density.compact.radius, style: .continuous)
                    .fill(ChromeFill.color(selected: false, hovered: hovered && enabled, glass: onGlass, scheme: scheme))
                    // On glass hover comes on at once and eases off; elsewhere it stays instant both ways.
                    .hoverMotion(hovered && enabled))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 }
        .accessibilityLabel(help)
        // The app's tooltip (as every other button's), with its shortcut.
        .tip(help, key)
    }

    private var ink: AnyShapeStyle {
        let level: ChromeInk = !enabled ? .disabled : hovered ? .primary : .secondary
        if onGlass { return level.style(glass: true) }
        return AnyShapeStyle(!enabled ? CDS.Text.disabled : hovered ? Brand.ink : CDS.Text.secondary)
    }
}
