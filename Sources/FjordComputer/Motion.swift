import AppKit
import SwiftUI

// The app's motion: one vocabulary, each token carrying its Reduce Motion fallback, so a call site asks for the token and
// the flag and gets the right animation back.
//
//   Token     Use                                           Value                                  Reduce Motion
//   instant   hover-on fills, press                         none                                   none
//   release   hover-off fills                               easeOut .12                            none
//   fade      presence (appear, disappear)                  easeOut .14                            the same
//   spatial   moves and resizes                             spring, critically damped, .3          easeOut .12
//   glass     glass shapes morphing, and what must stay     spring .35, bounce .12                 easeOut .12
//             in step with them (the page's inset in the fold)
//   scroll    a scroll to a place asked for once            spring, critically damped, .3          none (it jumps)
//   follow    a scroll following the keyboard's pick        spring, critically damped, .18         none (it jumps)
//   window    the morph between the bar and the window: Core Animation springs, not SwiftUI, so not a token here. They
//             live in AppTransition.swift (`AppTransition.Spring.opening` / `.closing`, and the `reducedDuration`
//             cross-fade under Reduce Motion).
//
// A scroll has no fade to fall back to, so under Reduce Motion it jumps. `follow` is short so a held arrow key never
// leaves the list trailing, and a wheel scroll has less time to fight one in flight.
//
// Under Reduce Motion `spatial` and `glass` become a short ease: what moves gets there in .12 s without a spring, and the
// transitions that fall back to `.opacity` (`AnyTransition.slide(from:reduce:)`, `.scaleFade(_:reduce:)`) fade.
//
// Rules, which RouterMotionTests checks over every source file:
// 1. Hover-on is instant, hover-off eases: `.hoverMotion(hovering)` (or `Motion.hover(on:)`). A press is instant both ways.
// 2. Springs for space, fades for presence.
// 3. Every animation is resolved for Reduce Motion: `.motion(_:value:)` reads it from the environment; elsewhere
//    `withAnimation(Motion.spatial.resolved(reduce: reduce))`, with `@Environment(\.accessibilityReduceMotion) var reduce`
//    in a view or `Motion.systemReduce` outside one.
// 4. Nothing loops in SwiftUI: a repeating animation runs in Core Animation (see `BlinkingDot`).

enum Motion: Equatable {
    case instant, release, fade, spatial, glass, scroll, follow

    /// What a token runs, as plain values (testable; `animation` turns it into SwiftUI's).
    enum Curve: Equatable {
        case none
        case easeOut(TimeInterval)
        case spring(duration: TimeInterval, bounce: Double)

        var animation: Animation? {
            switch self {
            case .none: nil
            case .easeOut(let duration): .easeOut(duration: duration)
            case .spring(let duration, let bounce): .spring(duration: duration, bounce: bounce)
            }
        }
    }

    /// The token's curve, with Reduce Motion on or off.
    func curve(reduce: Bool) -> Curve {
        switch self {
        case .instant: .none
        case .release: reduce ? .none : .easeOut(0.12)
        case .fade: .easeOut(0.14)
        case .spatial: reduce ? .easeOut(0.12) : .spring(duration: 0.3, bounce: 0)
        case .glass: reduce ? .easeOut(0.12) : .spring(duration: 0.35, bounce: 0.12)
        case .scroll: reduce ? .none : .spring(duration: 0.3, bounce: 0)
        case .follow: reduce ? .none : .spring(duration: 0.18, bounce: 0)
        }
    }

    /// The animation to run (nil: none), with Reduce Motion on or off. Pass to `withAnimation`, `.animation` or a
    /// `Transaction`.
    func resolved(reduce: Bool) -> Animation? { curve(reduce: reduce).animation }

    /// A hover fill's token: instant as the pointer comes in, released as it goes.
    static func hover(on: Bool) -> Motion { on ? .instant : .release }

    /// Reduce Motion read from the system, for code with no view (the environment's value follows the playground too).
    static var systemReduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

extension Animation {
    /// No animation at all when Reduce Motion is on: for the few deliberate curves that are not tokens (a control's own
    /// press or knob, a badge's count). Prefer a `Motion` token.
    func resolved(reduce: Bool) -> Animation? { reduce ? nil : self }
}

extension AnyTransition {
    /// Slides in from an edge; a plain fade with Reduce Motion.
    static func slide(from edge: Edge, reduce: Bool) -> AnyTransition { reduce ? .opacity : .move(edge: edge) }
    /// Scales up from `scale` while fading; a plain fade with Reduce Motion.
    static func scaleFade(_ scale: CGFloat = 0.96, reduce: Bool) -> AnyTransition {
        reduce ? .opacity : .scale(scale: scale).combined(with: .opacity)
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    let motion: Motion
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content.animation(motion.resolved(reduce: reduce), value: value)
    }
}

private struct CurveModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduce

    func body(content: Content) -> some View {
        content.animation(animation.resolved(reduce: reduce), value: value)
    }
}

private struct HoverMotionModifier: ViewModifier {
    let hovering: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    /// The animation is read as the value changes, so it is the new value's: none coming in, `release` going out.
    func body(content: Content) -> some View {
        content.animation(Motion.hover(on: hovering).resolved(reduce: reduce), value: hovering)
    }
}

extension View {
    /// `.animation(_:value:)` with a motion token, following Reduce Motion live from the environment.
    func motion<V: Equatable>(_ motion: Motion = .spatial, value: V) -> some View {
        modifier(MotionModifier(motion: motion, value: value))
    }

    /// `.animation(_:value:)` with a deliberate curve that is not a token: dropped under Reduce Motion, live.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(CurveModifier(animation: animation, value: value))
    }

    /// A hover fill's animation (rule 1): none as `hovering` turns true, `release` as it turns false.
    func hoverMotion(_ hovering: Bool) -> some View {
        modifier(HoverMotionModifier(hovering: hovering))
    }
}
