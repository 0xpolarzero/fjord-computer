import AppKit

/// `--motion-script open,close,fold,peek,drag x20`: tooling only (`scripts/motion-trace.sh`), and only with `--demo`. Plays
/// the steps in order, the whole list `count` times, one step every 1.5 s, through the app's own paths, so a trace of the
/// motions needs no person or pointer: open and close as the window's shortcut does, fold as View ▸ Collapse Sidebar does,
/// peek as the pointer settling on the bar's inbox does (then leaving it), drag as a drop by the opposite edge does. One line
/// per step on stdout. With `--quit-after` the app quits once the last step has had its time.
struct MotionScript: Equatable {
    enum Step: String, CaseIterable {
        case open, close, fold, peek, drag
    }

    static let flag = "--motion-script"
    static let quitFlag = "--quit-after"
    /// The time each step is given: past the longest motion (the morph), with the frames after it at rest.
    static let interval: Duration = .milliseconds(1500)
    /// How long a peek stays open before the pointer is said to have left.
    static let peekHold: Duration = .milliseconds(700)

    var steps: [Step]
    var count = 1

    /// "open,close,fold x20", or the steps alone (once). Nil for anything else: an unknown or empty step, a count that is not
    /// a whole number from 1 to 1000.
    init?(_ text: String) {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)
        guard (1...2).contains(words.count) else { return nil }
        let names = words[0].split(separator: ",", omittingEmptySubsequences: false)
        let steps = names.compactMap { Step(rawValue: String($0)) }
        guard !names.isEmpty, steps.count == names.count else { return nil }
        self.steps = steps
        if words.count == 2 {
            let digits = words[1].dropFirst()
            guard words[1].first == "x", digits.allSatisfy({ $0.isASCII && $0.isNumber }), let count = Int(digits),
                  (1...1000).contains(count) else { return nil }
            self.count = count
        }
    }

    init(steps: [Step], count: Int = 1) {
        self.steps = steps
        self.count = count
    }

    enum Problem: Error, Equatable {
        /// The flag with nothing after it, or something that is not a script.
        case malformed
    }

    /// The script the arguments ask for: nil without the flag. The steps and the count may be one argument
    /// (`--motion-script "open,close x20"`) or two (`--motion-script open,close x20`).
    static func parse(arguments: [String]) throws -> MotionScript? {
        guard let i = arguments.firstIndex(of: flag) else { return nil }
        let rest = arguments.dropFirst(i + 1)
        guard let first = rest.first, !first.hasPrefix("--") else { throw Problem.malformed }
        var text = first
        if let next = rest.dropFirst().first, next.hasPrefix("x"), !first.contains(" ") { text += " " + next }
        guard let script = MotionScript(text) else { throw Problem.malformed }
        return script
    }

    /// Every step in the order played.
    var played: [Step] { Array(repeating: steps, count: count).flatMap { $0 } }
}

/// Plays a `MotionScript` on the app's own paths, handed in by the app's delegate.
@MainActor
final class MotionScriptPlayer {
    var open: () -> Void = {}
    var close: () -> Void = {}
    var fold: () -> Void = {}
    /// Shows a peek; the returned block closes it.
    var peek: () -> (() -> Void)? = { nil }
    /// False when the bar can't be carried now (the window is in front).
    var drag: () -> Bool = { false }

    private var task: Task<Void, Never>?

    func play(_ script: MotionScript, quitAfter: Bool) {
        let played = script.played
        task = Task { [weak self] in
            for (n, step) in played.enumerated() {
                try? await Task.sleep(for: MotionScript.interval)
                guard let self, !Task.isCancelled else { return }
                let note = await self.run(step)
                Self.say("motion: \(n + 1)/\(played.count) \(step.rawValue)\(note.map { " (\($0))" } ?? "")")
            }
            try? await Task.sleep(for: MotionScript.interval)
            Self.say("motion: done")
            if quitAfter { NSApp.terminate(nil) }
        }
    }

    /// Runs one step; says why it did nothing, if it didn't.
    private func run(_ step: MotionScript.Step) async -> String? {
        switch step {
        case .open: open()
        case .close: close()
        case .fold: fold()
        case .peek:
            guard let leave = peek() else { return "the bar is away or quiet" }
            try? await Task.sleep(for: MotionScript.peekHold)
            leave()
        case .drag:
            if !drag() { return "the bar is away" }
        }
        return nil
    }

    private static func say(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}
