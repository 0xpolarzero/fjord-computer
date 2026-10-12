import AppKit
import SwiftUI

// The bar and its panels on glass (docs/design/fjord/glass-plan.md §5.5, §5.8): the bar is Regular glass over the desktop,
// the open panel grows out of it as one shape, and what sits on them uses fills and label styles, not more glass. Opaque
// mode (`Chrome.Mode.opaque`, and macOS 14/15) keeps today's look: every token here takes the opaque value it replaces.

enum BarGlass {
    /// The bar's corners away from the screen.
    static let barRadius: CGFloat = 20
    /// A panel's free corners on glass: the bar's own, so the shape they make together has one radius all round.
    static let panelRadius: CGFloat = barRadius
    /// How near two glass shapes in the bar's container start to blend: bar and panel touch, so they always read as one.
    static let spacing: CGFloat = 12
    /// A panel's content comes in this long after its glass starts growing out of the bar.
    static let contentDelay: TimeInterval = 0.04

    /// The glass shapes' identities in the bar's container.
    enum ID: Hashable, Sendable { case bar, panel }

    // MARK: Fills

    /// A fill over glass: alpha steps of `Brand.ink`.
    enum Step { case hover, selected, selectedHover }

    /// The step's alpha: dark 6 / 9 / 12 %, light 6 / 10 / 14 % (the light values are the plan's starting point, set by the
    /// contrast pass).
    static func alpha(_ step: Step, dark: Bool) -> Double {
        switch step {
        case .hover: 0.06
        case .selected: dark ? 0.09 : 0.10
        case .selectedHover: dark ? 0.12 : 0.14
        }
    }

    /// The fill for a step: on glass its `Brand.ink` step for this appearance, else `opaque` (today's token).
    static func fill(_ step: Step, glass: Bool, scheme: ColorScheme, opaque: Color) -> Color {
        glass ? Brand.ink.opacity(alpha(step, dark: scheme == .dark)) : opaque
    }

    // MARK: Text

    /// Chrome text and glyphs on glass: the label styles, which follow the material in light and dark.
    enum Ink { case primary, secondary, tertiary }

    /// On glass the label style for `level`, else `opaque` (today's colour). Status colours never go through this.
    static func ink(_ level: Ink, glass: Bool, opaque: Color) -> AnyShapeStyle {
        guard glass else { return AnyShapeStyle(opaque) }
        return switch level {
        case .primary: AnyShapeStyle(HierarchicalShapeStyle.primary)
        case .secondary: AnyShapeStyle(HierarchicalShapeStyle.secondary)
        case .tertiary: AnyShapeStyle(HierarchicalShapeStyle.tertiary)
        }
    }
}

extension EnvironmentValues {
    /// The view is drawn on the bar's glass (or its panel's): fills and text take their glass values. False everywhere else,
    /// the app window included, so a view shared with it (an inbox row) keeps its opaque look there.
    @Entry var onBarGlass = false
}

private struct BarChromeInk: ViewModifier {
    let level: BarGlass.Ink
    let opaque: Color
    @Environment(\.onBarGlass) private var glass

    func body(content: Content) -> some View {
        content.foregroundStyle(BarGlass.ink(level, glass: glass, opaque: opaque))
    }
}

private struct BarRowHighlight: ViewModifier {
    let on: Bool
    @Environment(\.onBarGlass) private var glass
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if glass {
            // `rowHighlight`'s padding, radius and motion, with the glass hover step.
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.Radius.shape(Theme.Radius.md)
                    .fill(on ? BarGlass.fill(.hover, glass: true, scheme: scheme, opaque: Theme.Fill.hover) : Theme.Fill.rest))
                .contentShape(Theme.Radius.shape(Theme.Radius.md))
                .hoverMotion(on)
        } else {
            content.rowHighlight(on)
        }
    }
}

/// A panel's content on glass comes in `BarGlass.contentDelay` behind the glass growing out of the bar. With Reduce Motion
/// the panel fades as a whole (its transition), so its content is there from the start.
struct PeekReveal: ViewModifier {
    let reduce: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(reduce || shown ? 1 : 0)
            .onAppear {
                guard !reduce, !shown else { return }
                withAnimation(Motion.fade.resolved(reduce: reduce).map { $0.delay(BarGlass.contentDelay) }) { shown = true }
            }
    }
}

extension View {
    /// Chrome text or a glyph: a label style on the bar's glass, `opaque` elsewhere.
    func chromeInk(_ level: BarGlass.Ink, _ opaque: Color) -> some View {
        modifier(BarChromeInk(level: level, opaque: opaque))
    }

    /// `rowHighlight`, with the glass hover step on the bar's glass.
    func barRowHighlight(_ on: Bool) -> some View {
        modifier(BarRowHighlight(on: on))
    }
}

// MARK: Dragging

/// The bar on glass while it is carried to another edge: drawn out along the motion (narrower across it, so it never grows
/// past the window that is exactly its size), settling as it lands. Reduce Motion: none at all, the move being the motion.
enum BarStretch {
    /// The bar at rest.
    static let rest = CGSize(width: 1, height: 1)
    /// Its scale across the motion while carried.
    static let across: CGFloat = 0.94
    /// The pointer has to have moved this far before the motion has a direction.
    static let threshold: CGFloat = 6

    /// The bar's scale for a drag that has moved by `motion` so far: narrower across the motion's main axis, nothing under
    /// Reduce Motion or before the motion has a direction.
    static func scale(_ motion: CGVector, reduce: Bool) -> CGSize {
        guard !reduce, max(abs(motion.dx), abs(motion.dy)) >= threshold else { return rest }
        return abs(motion.dx) >= abs(motion.dy) ? CGSize(width: 1, height: across) : CGSize(width: across, height: 1)
    }

    /// The trackpad's tick as the bar lands on its edge (Force Touch trackpads; the system may suppress it).
    @MainActor static func landed() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
