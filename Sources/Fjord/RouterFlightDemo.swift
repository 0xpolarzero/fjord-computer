import AppKit
import SwiftUI

/// `--window --flight-demo`: tooling only. The Router's page on the demo data, playing messages typed into its composer
/// through the real dispatcher, with Jev, the prepare and the send standing in at their usual pace: one to a working session,
/// one to a finished one (it comes into Working), one that starts a session, and one the Router isn't sure of (you pick).
/// For seeing and recording the send-flight (`RouterFlights`); nothing reaches a real session.
@MainActor enum RouterFlightDemo {
    static let flag = "--flight-demo"
    /// The demo plays: the demo's sends go through the dispatcher, not the demo's canned reply.
    static private(set) var on = false

    private static let lcu = "/Users/me/code/lcu"

    private struct Step {
        var text: String
        /// Where Jev sends it; nil: he isn't sure.
        var target: String?
        /// For an ask: the pick, after a moment.
        var pick: String? = nil
    }

    private static let steps = [
        Step(text: "also cover the error notifications while you're at it", target: "session:local_demo-lookout"),
        Step(text: "archive the old fork now that the transfer is done", target: "session:local_demo-transfer"),
        Step(text: "add a --json flag to the CLI's status command", target: "new:\(lcu)"),
        Step(text: "ship it tomorrow morning", target: nil, pick: "session:local_demo-ci"),
    ]

    static func install(_ store: Store) {
        on = true
        let dispatcher = store.routerDispatcher
        dispatcher.clearPreview()
        dispatcher.effects = RouterDispatcher.Effects(
            rank: { _, message, _ in
                try await Task.sleep(for: .milliseconds(1300))
                guard let step = steps.first(where: { $0.text == message }), let target = step.target else {
                    return .init(scored: [.init(target: "session:local_demo-ci", p: 0.41), .init(target: "session:local_demo-transfer", p: 0.33),
                                          .init(target: "session:local_demo-calc", p: 0.14)], sure: false)
                }
                return .init(scored: [.init(target: target, p: 0.94)], sure: true)
            },
            prepare: { _, session in
                try await Task.sleep(for: .milliseconds(450))
                return .init(to: "demo", text: "", body: "", original: "", rephrased: false, session: session, newSessionIn: nil)
            },
            start: { _, folder, _, _ in
                try await Task.sleep(for: .milliseconds(900))
                return .delivery(.init(to: "demo", text: "demo", body: "demo", original: "demo", rephrased: false, session: "local_demo-json",
                                       newSessionIn: store.folderName(folder)))
            },
            send: { _, _ in
                try await Task.sleep(for: .milliseconds(650))
                return nil
            },
            answer: { _, _, _ in "" },
            run: { _, _, _ in throw RouterTools.Failure("not in the flight demo") })
    }

    /// Types each message into the composer and sends it, as you would.
    static func play(store: Store, model: RouterModel) {
        // In front, wide enough for Now and History side by side, with Working open and Needs you folded:
        // the rows the messages land on in view.
        model.setFolded(.working, false)
        model.setFolded(.needs, true)
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }), let screen = window.screen ?? NSScreen.main {
                let size = CGSize(width: min(1480, screen.visibleFrame.width - 40), height: min(940, screen.visibleFrame.height - 40))
                window.setFrame(CGRect(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.midY - size.height / 2,
                                       width: size.width, height: size.height), display: true)
                window.makeKeyAndOrderFront(nil)
            }
            try? await Task.sleep(for: .seconds(2))
            for step in steps {
                model.draft = ""
                for ch in step.text {
                    model.draft.append(ch)
                    try? await Task.sleep(for: .milliseconds(32))
                }
                try? await Task.sleep(for: .milliseconds(450))
                model.send(store: store)
                if let pick = step.pick {
                    try? await Task.sleep(for: .seconds(4))
                    if let ask = store.routerDispatcher.askBacks.last { store.routerDispatcher.pick(ask.id, target: pick) }
                }
                try? await Task.sleep(for: .seconds(4.2))
            }
        }
    }
}
