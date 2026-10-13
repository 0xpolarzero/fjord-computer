import OSLog
import QuartzCore

// The latency signposts (subsystem com.amontlabs.fjord, category "latency"), beside the morph's: what the budgets of
// docs/design/fjord/glass-plan.md §7 are read from, in Instruments or `scripts/motion-trace.sh`. Each is an interval:
// "Peek" (a dwell's end to the panel's first commit), "Fold" (the sidebar's fold to its animation's end), "Drag" (the
// bar's glide to its new edge), "Bar away" (the window asked to open to the bar starting to fade out) and "Bar capture"
// (the bar's picture for the morph). Each begins with the motion it times: nothing runs at rest.

/// The latency signposts.
@MainActor
enum LatencySignposts {
    nonisolated static let signposter = OSSignposter(subsystem: InboxLog.subsystem, category: "latency")

    /// A "Bar away" begun by an opening and not ended yet.
    private static var barAway: OSSignpostIntervalState?

    /// The window was asked to open: "Bar away" runs until the bar starts fading out (`barLeaving`).
    static func windowAsked() {
        barStayed()
        barAway = signposter.beginInterval("Bar away")
    }

    /// The bar starts fading out.
    static func barLeaving() {
        guard let state = barAway else { return }
        barAway = nil
        signposter.endInterval("Bar away", state)
    }

    /// The opening left the bar where it was (it was away already): ended as "kept", which the scripts leave out.
    static func barStayed() {
        guard let state = barAway else { return }
        barAway = nil
        signposter.endInterval("Bar away", state, "kept")
    }

    /// Ends `name` once the current Core Animation transaction has been committed: the change made this turn is then on
    /// its way to the render server, its first frame. Core Animation commits as this turn of the main run loop ends (macOS
    /// has no commit handler), so a block queued now runs just after that commit, on the next turn; a completion block would
    /// wait for the change's animations to finish instead.
    static func endAfterCommit(_ name: StaticString, _ state: OSSignpostIntervalState) {
        DispatchQueue.main.async { signposter.endInterval(name, state) }
    }
}
