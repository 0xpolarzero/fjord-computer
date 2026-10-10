import AppKit

// Claude Code runs this binary as its form hook (see `FormHook`): no app, nothing on stdout but the hook's decision.
if CommandLine.arguments.dropFirst().first == "--form-hook" { FormHook.main() }

ClaudeFonts.load()
// Text drawn as Claude's web view draws it (`-webkit-font-smoothing: antialiased`): no stem thickening. For this process
// only, as if launched with `-AppleFontSmoothing 0`.
UserDefaults.standard.setVolatileDomain(["AppleFontSmoothing": 0], forName: UserDefaults.argumentDomain)

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
