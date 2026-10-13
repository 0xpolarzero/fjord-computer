import AppKit
import Carbon
import ServiceManagement
import UserNotifications

// MARK: - Notifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    /// A click: the notification's id (`inbox:<thing id>` for a thing) and the page it is about (for when the thing is gone).
    var onOpen: ((_ id: String, _ url: String?) -> Void)?
    /// Tests: every post and withdrawal, whether or not the system would show it.
    var onPost: ((UNNotificationRequest) -> Void)?
    var onRemove: (([String]) -> Void)?
    /// Bulk summaries ("7 new in your inbox") belong to no one thing: identified by this and a unique suffix.
    nonisolated static let summaryPrefix = "summary#"
    /// Banners need an app bundle; a test run, hosted in one or not, never has the system's.
    private var available: Bool { Self.canReachSystem }
    private nonisolated static var canReachSystem: Bool { Bundle.main.bundleIdentifier != nil && !UnderTest.isRunning }

    func setup() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Whether macOS refuses this app's banners: said no at the first prompt, or turned off since in System Settings.
    static func isBlocked() async -> Bool {
        guard canReachSystem else { return false }
        return await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func post(id: String, title: String, subtitle: String, body: String, quiet: Bool, url: URL? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.userInfo = ["id": id, "url": url?.absoluteString ?? ""]
        content.threadIdentifier = quiet ? "bots" : "main"
        if quiet {
            content.interruptionLevel = .passive
        } else {
            content.sound = .default
        }
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        onPost?(req)
        guard available else { return }
        UNUserNotificationCenter.current().add(req)
    }

    /// Withdraws banners.
    func remove(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        onRemove?(ids)
        guard available else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let id = info["id"] as? String ?? ""
        let url = info["url"] as? String
        DispatchQueue.main.async { self.onOpen?(id, url) }
        completionHandler()
    }
}

// MARK: - Global hotkeys

/// What registers a key combination with the system: Carbon, or a stand-in under test.
protocol HotKeyBackend {
    /// What holds the registration, or nil when another app holds the combination.
    func register(_ shortcut: Shortcut, id: UInt32) -> AnyObject?
    func unregister(_ registration: AnyObject)
}

/// Carbon hot keys, which the system delivers to the app wherever the keys are pressed.
final class CarbonHotKeys: HotKeyBackend {
    private final class Registration {
        let ref: EventHotKeyRef
        init(_ ref: EventHotKeyRef) { self.ref = ref }
    }

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &id)
            HotKeys.handlers[id.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }

    func register(_ shortcut: Shortcut, id: UInt32) -> AnyObject? {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         EventHotKeyID(signature: OSType(0x4C4B4F54), id: id),
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { return Registration(ref) }
        NSLog("Fjord Computer: global shortcut \(shortcut.display) unavailable (\(status))")
        return nil
    }

    func unregister(_ registration: AnyObject) {
        if let registration = registration as? Registration { UnregisterEventHotKey(registration.ref) }
    }
}

/// System-wide shortcuts, one registration per id. Matched by key position, so any keyboard layout works.
/// Key combinations go through Carbon hot keys; lone modifier taps (e.g. right ⌘) through event monitors,
/// which need Accessibility access to see the keys typed in other apps.
final class HotKeys {
    static let debug = ProcessInfo.processInfo.environment["FJORD_DEBUG"] != nil
    fileprivate static var handlers: [UInt32: () -> Void] = [:]
    /// Where the key combinations are registered with the system.
    private let backend: HotKeyBackend
    private var refs: [UInt32: AnyObject] = [:]
    /// The key combinations asked for, kept while suspended so they come back as they were.
    private var combos: [UInt32: (shortcut: Shortcut, handler: () -> Void)] = [:]
    /// While true, the key combinations are released so the keys reach the app (e.g. a shortcut being recorded).
    var isSuspended = false {
        didSet {
            guard isSuspended != oldValue else { return }
            for id in combos.keys { register(id) }
        }
    }
    var registeredIDs: Set<UInt32> { Set(refs.keys) }
    private var taps: [UInt32: (key: UInt16, handler: () -> Void)] = [:]
    /// Mouse button shortcuts, caught (and kept from the app under the pointer) by an event tap.
    private var buttons: [UInt32: (button: Int, flags: NSEvent.ModifierFlags, handler: () -> Void)] = [:]
    private var buttonTap: CFMachPort?
    /// Buttons whose press was a shortcut: their release is kept from the app under the pointer too.
    private var swallowedUps: Set<Int> = []
    private var tap = ModifierTap()
    private var monitors: [Any] = []
    /// Waits for Fjord Computer to come back to the front while taps or mouse buttons are set and Accessibility is not
    /// granted.
    private var activation: NSObjectProtocol?
    /// When the held modifier went down (event timestamps, i.e. system uptime), to ask whether anything else happened since.
    private var heldSince: TimeInterval?
    /// Taps are ignored while this is true (e.g. while a shortcut is being recorded).
    var paused: () -> Bool = { false }

    init(backend: HotKeyBackend = CarbonHotKeys()) {
        self.backend = backend
    }

    /// `nil` unregisters. A system-wide key that another app holds is refused (`false`), and what the action had stays
    /// registered until a replacement is.
    @discardableResult
    func set(_ id: UInt32, _ shortcut: Shortcut?, handler: @escaping () -> Void = {}) -> Bool {
        defer { updateMonitors(); updateButtonTap(); updateActivation() }
        if let shortcut, shortcut.mouseButton == nil, !shortcut.isModifierTap {
            if combos[id]?.shortcut == shortcut, refs[id] != nil || isSuspended {
                combos[id] = (shortcut, handler)
                if refs[id] != nil { HotKeys.handlers[id] = handler }
                return true
            }
            // The replacement first: Carbon refuses a key another app holds, and the old one should keep working then.
            guard let ref = claim(shortcut, id) else { return false }
            release(id)
            combos[id] = (shortcut, handler)
            if isSuspended {
                backend.unregister(ref)
            } else {
                refs[id] = ref
                HotKeys.handlers[id] = handler
            }
            return true
        }
        release(id)
        guard let shortcut else { return true }
        if let button = shortcut.mouseButton { buttons[id] = (button, shortcut.flags, handler) } else { taps[id] = (shortcut.keyCode, handler) }
        return true
    }

    /// Lets go of whatever `id` holds, of every kind.
    private func release(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { backend.unregister(ref) }
        combos[id] = nil
        HotKeys.handlers[id] = nil
        taps[id] = nil
        buttons[id] = nil
    }

    /// Asks the system for a key combination, which it refuses when another app holds it.
    private func claim(_ shortcut: Shortcut, _ id: UInt32) -> AnyObject? {
        backend.register(shortcut, id: id)
    }

    /// (Re)registers one combination with the system, or only releases it while suspended or removed.
    private func register(_ id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { backend.unregister(ref) }
        HotKeys.handlers[id] = nil
        guard !isSuspended, let (shortcut, handler) = combos[id], let ref = claim(shortcut, id) else { return }
        refs[id] = ref
        HotKeys.handlers[id] = handler
    }

    /// Access is granted in System Settings, with Fjord Computer behind it, and the tap that failed before it, or the
    /// monitors that heard nothing, are not tried again by themselves: coming back to the front is when to look.
    /// Nothing listens otherwise.
    private func updateActivation() {
        let waiting = (!taps.isEmpty || !buttons.isEmpty) && !AXIsProcessTrusted()
        if waiting, activation == nil {
            activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                                queue: .main) { [weak self] _ in self?.accessMayBeGranted() }
        } else if !waiting, let observer = activation {
            NotificationCenter.default.removeObserver(observer)
            activation = nil
        }
    }

    private func accessMayBeGranted() {
        guard AXIsProcessTrusted() else { return }
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        updateMonitors()
        updateButtonTap()
        updateActivation()
    }

    private func updateMonitors() {
        if taps.isEmpty {
            monitors.forEach(NSEvent.removeMonitor)
            monitors = []
            heldSince = nil
            return
        }
        guard monitors.isEmpty else { return }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        // Only modifier changes are watched; whether anything else happened during a tap is asked on release.
        let events: NSEvent.EventTypeMask = [.flagsChanged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(local)
        }
    }

    /// Whether a key, click or scroll happened since the modifier went down: the window server remembers, so
    /// nothing has to watch those events (and wake the app) while typing or scrolling.
    private func interrupted(since start: TimeInterval) -> Bool {
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        return types.contains { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) < elapsed }
    }

    /// A session event tap for the mouse buttons in use: it sees them in every app and can keep a shortcut's click
    /// from also going back in a browser. It needs Accessibility access, like modifier taps.
    private func updateButtonTap() {
        if buttons.isEmpty {
            if let tap = buttonTap { CGEvent.tapEnable(tap: tap, enable: false) }
            buttonTap = nil
            return
        }
        guard buttonTap == nil else { return }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
        }
        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue | 1 << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            return Unmanaged<HotKeys>.fromOpaque(info).takeUnretainedValue().button(type, event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            NSLog("Fjord Computer: can't watch mouse buttons (Accessibility access?)")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        buttonTap = tap
    }

    /// Runs on the main run loop. Returns nil to keep the click from the app under the pointer.
    private func button(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = buttonTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let number = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        if type == .otherMouseUp { return swallowedUps.remove(number) == nil ? Unmanaged.passUnretained(event) : nil }
        guard !paused() else { return Unmanaged.passUnretained(event) }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)).intersection(Shortcut.relevant)
        guard let match = buttons.values.first(where: { $0.button == number && $0.flags == flags }) else {
            return Unmanaged.passUnretained(event)
        }
        swallowedUps.insert(number)
        DispatchQueue.main.async { match.handler() }
        return nil
    }

    private func handle(_ event: NSEvent) {
        if Self.debug {
            NSLog("Fjord Computer keys: flagsChanged %d flags %lx trusted %d", event.keyCode, event.modifierFlags.rawValue, AXIsProcessTrusted() ? 1 : 0)
        }
        let held = UInt(event.modifierFlags.rawValue) & Shortcut.sideBits != 0
        let since = heldSince
        if held { if heldSince == nil { heldSince = event.timestamp } } else { heldSince = nil }
        // Without Accessibility the keys typed elsewhere are invisible, so right ⌘ + C would look like a tap.
        guard let key = tap.flagsChanged(keyCode: event.keyCode, flags: event.modifierFlags.rawValue),
              !paused(), AXIsProcessTrusted() else { return }
        if let since, interrupted(since: since) { return }
        for entry in taps.values where entry.key == key { entry.handler() }
    }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        guard !UnderTest.refuses("the login item (Launch at login)") else { return }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var hub: HubController?
    private lazy var hotKeys = HotKeys()
    private var globalShortcuts: GlobalShortcuts?
    private var playground: Playground?
    private var appWindow: AppWindowController?
    private var sigtermSource: DispatchSourceSignal?
    private var motion: MotionScriptPlayer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        handleSigterm()
        store = Store()
        if let i = CommandLine.arguments.firstIndex(of: "--playground-shots"), i + 1 < CommandLine.arguments.count {
            PlaygroundShots.run(to: CommandLine.arguments[i + 1])
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--window-shots"), i + 1 < CommandLine.arguments.count {
            AppWindowShots.run(to: CommandLine.arguments[i + 1])
            return
        }
        if CommandLine.arguments.contains("--window") {
            appWindow = AppWindowDev.open(store)
            return
        }
        if CommandLine.arguments.contains("--playground") {
            playground = Playground()
            playground?.run()
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--update"), i + 1 < CommandLine.arguments.count {
            UpdateCheck.run(as: CommandLine.arguments[i + 1])
            return
        }
        if CommandLine.arguments.contains("--claude") {
            ClaudeCheck.run()
            return
        }
        if CommandLine.arguments.contains("--check-inbox") {
            InboxCheck.run(store: store)
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--check"), i + 1 < CommandLine.arguments.count {
            Check.run(store: store, repo: CommandLine.arguments[i + 1])
            return
        }
        if let i = CommandLine.arguments.firstIndex(of: "--demo") {
            let name = CommandLine.arguments.dropFirst(i + 1).first ?? ""
            Demo.populate(store, Demo.Scenario(rawValue: name) ?? .busy)
        } else {
            store.start()
        }
        let demo = CommandLine.arguments.contains("--demo")
        let window = AppWindowController(store: store)
        appWindow = window
        let hub = HubController(store: store, demo: demo)
        self.hub = hub
        // The window is the bar's other mode: while it is in front the bar is away, and closing it (or leaving it behind) puts the bar back.
        window.onClose = { [weak hub] in hub?.setWindowOpen(false) }
        window.barScreen = { [weak hub] in hub?.dockedScreen }
        window.bar = { [weak hub] in hub?.morph }
        // As the close's motion starts: the bar fades back in, then the keyboard goes back to the app that had it (the Dock
        // icon goes once the motion is over).
        window.onClosing = { [weak hub] in
            hub?.setWindowOpen(false)
            AppPolicy.yieldFocus()
        }
        // The bar is back on its edge while the window is out of sight (another app in front, minimized), away when it returns.
        window.onFront = { [weak hub] front in hub?.setWindowFront(front) }
        hub.openApp = { [weak self] in self?.showWindow($0) }
        hub.openUpdates = { [weak self] in
            self?.appWindow?.showUpdates()
            self?.hub?.setWindowOpen(true)
        }
        hub.pickRouterCard = { [weak window] id in window?.pick(card: id) }
        hub.pickRouterMessage = { [weak window] id in window?.pick(message: id) }
        hub.prefillRouter = { [weak window] thing in window?.prefillRouter(thing: thing) }
        hub.windowPlace = { [weak window] in window?.navigator.selection }
        // Banners for new cards that need you; a demo posts none.
        if !demo {
            RouterBanners.attach(store: store, windowIsKey: { [weak window] in window?.isKey == true && window?.navigator.selection == .router }) {
                [weak self] card in self?.showWindow(.router, card: card)
            }
        }
        // Demo: the window's key on right ⌘ (not saved), to try tap and double-tap.
        if demo {
            store.settings.shortcuts = [ShortcutAction.togglePanel.rawValue: Shortcut(keyCode: 54)]
        }
        hotKeys.paused = { [weak self] in self?.store.isRecordingShortcut ?? false }
        store.onRecordingShortcutChange = { [weak self] on in self?.globalShortcuts?.suspend(on) }
        // A banner's click: the window on the thing's category with it picked (on the archive if it was archived since), or, for a
        // summary, on the first category with something unread.
        store.onOpenInbox = { [weak self] category, thing in
            guard let self else { return }
            if let thing, let entry = self.store.entries.first(where: { $0.id == thing }) {
                self.appWindow?.show(entry: entry)
                self.hub?.setWindowOpen(true)
            } else {
                self.showWindow(category.map { .category($0) } ?? AppDestination(self.store.tabNeedingYou))
            }
        }
        // Default ⌃⌥L: ⌃⌥Space is macOS's "next input source".
        let globals = GlobalShortcuts(store: store, hotKeys: hotKeys) { [weak self] action in
            switch action {
            case .togglePanel: self?.toggleWindow()
            case .router: if self?.store.routerOn == true { self?.showWindow(.router) }
            default: break
            }
        }
        globals.start()
        globalShortcuts = globals
        // The first launch opens on the onboarding, where the tools are picked.
        if CommandLine.arguments.contains("--open") || store.settings.toolsPicked != true { toggleWindow() }
        playMotionScript(demo: demo)
        if CommandLine.arguments.contains(Lifecycle.flag) {
            Lifecycle.start(store)
        } else {
            // The window's content built once at idle, out of sight, so the first open only brings it in. Not under
            // `--lifecycle`, whose idle measurement wants nothing done after launch.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.prepareDelay, qos: .utility) { [weak window, weak hub, weak self] in
                guard let window, let hub else { return }
                Self.prepareWhenIdle(interacting: { [weak hub] in
                    Self.preparationIsBlocked(mouseButtons: NSEvent.pressedMouseButtons, modifiers: NSEvent.modifierFlags,
                                              barInteracting: hub?.isInteracting == true)
                }, prepare: { [weak window, weak hub, weak self] in
                    // Short of memory: none of it (the overlay, once made, is kept for good).
                    guard let window, let hub, !window.memoryShort else { return }
                    if self?.store.router.enabled == true { _ = SessionIcons.drawable }
                    window.prepare()
                    AppTransition.prepareOverlay(on: hub.dockedScreen)
                })
            }
        }
    }

    /// How long after launch the window's content is built (`AppWindowController.prepare`): past the store's first load
    /// and the bar's first draw.
    static let prepareDelay: TimeInterval = 2

    static func preparationIsBlocked(mouseButtons: Int, modifiers: NSEvent.ModifierFlags, barInteracting: Bool) -> Bool {
        mouseButtons != 0 || !modifiers.intersection(Shortcut.relevant).isEmpty || barInteracting
    }

    /// A busy user gets another chance at idle in 250 ms; the scheduler is replaceable so tests can step retries.
    static func prepareWhenIdle(interacting: @escaping () -> Bool, prepare: @escaping () -> Void,
                                schedule: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void = { delay, block in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, qos: .utility) { MainActor.assumeIsolated { block() } }
    }) {
        if interacting() {
            schedule(0.25) { prepareWhenIdle(interacting: interacting, prepare: prepare, schedule: schedule) }
        } else {
            prepare()
        }
    }

    /// Opens the app window on `destination` (the bar leaves the edge), or on a Router card.
    private func showWindow(_ destination: AppDestination?, card: String? = nil) {
        appWindow?.show(destination, card: card)
        hub?.setWindowOpen(true)
    }

    /// The window shortcut: closes the window you are looking at (the bar comes back), else brings it in front where it
    /// was left, whether it was closed, minimized or behind another app.
    private func toggleWindow() {
        if appWindow?.shortcutCloses == true { appWindow?.close() } else { showWindow(nil) }
    }

    /// `--motion-script` (`MotionScript`), with `--demo` only: the motions played on a timer for `scripts/motion-trace.sh`.
    /// A script that doesn't parse ends the app, so a recording never runs on nothing.
    private func playMotionScript(demo: Bool) {
        let script: MotionScript?
        do {
            script = try MotionScript.parse(arguments: CommandLine.arguments)
        } catch {
            FileHandle.standardError.write(Data("motion: not a script (steps among open, close, fold, peek, drag, then xN)\n".utf8))
            exit(2)
        }
        guard let script else { return }
        guard demo else {
            FileHandle.standardError.write(Data("motion: \(MotionScript.flag) plays only with --demo\n".utf8))
            return
        }
        let player = MotionScriptPlayer()
        player.open = { [weak self] in if self?.appWindow?.shortcutCloses == false { self?.toggleWindow() } }
        player.close = { [weak self] in if self?.appWindow?.shortcutCloses == true { self?.toggleWindow() } }
        player.fold = { SidebarState.shared.toggle() }
        player.peek = { [weak self] in
            guard let hub = self?.hub, !hub.barAway else { return nil }
            // The pointer's own check first: off the bar, it lifts the quiet a window's close leaves.
            hub.mouseMoved()
            guard !hub.hub.quiet else { return nil }
            hub.hub.enter(.inbox)
            return {
                hub.hub.cancelDwell()
                hub.hub.section = nil
            }
        }
        player.drag = { [weak self] in self?.hub?.dragToOppositeEdge() ?? false }
        player.play(script, quitAfter: CommandLine.arguments.contains(MotionScript.quitFlag))
        motion = player
    }

    /// The Dock icon (there while the window is open): the window in front, whatever was in front of it.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(nil)
        return false
    }

    @objc private func openSettings() { showWindow(.settings) }

    /// SIGTERM would skip `applicationWillTerminate` and lose a pending save.
    private func handleSigterm() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        sigtermSource = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        // The Router's runs go with the app, the actions' too (a send's `claude` process is ended, not left behind).
        store?.routerDispatcher.stopAll(actions: true)
        store?.flushSave()
    }

    /// The main menu: shown while the app window is open; an accessory app has none, but key equivalents (⌘C/⌘V/⌘A) still route
    /// through it.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Fjord Computer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        appMenu.insertItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",", at: 0)
        appMenu.items[0].target = self
        appMenu.insertItem(.separator(), at: 1)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        main.addItem(GoMenu.shared.makeItem())
        main.addItem(SidebarMenu.shared.makeItem())
        // ⌘W closes the window, which puts the bar back; ⌘Q quits.
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }
}
