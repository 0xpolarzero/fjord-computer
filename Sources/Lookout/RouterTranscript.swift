import SwiftUI

// The Router page's text and status pieces as Claude's Code tab draws them (docs/design/spec/transcript.md, compact density,
// text 14/20): assistant prose, the status caret, and the clay working mark while something works.

// MARK: - Width

private struct ColumnWidthKey: EnvironmentKey { static let defaultValue = CDS.Transcript.measure }

extension EnvironmentValues {
    /// The transcript column's content width, for the prose's text stop and the bubble's 85%.
    var cdsColumnWidth: CGFloat {
        get { self[ColumnWidthKey.self] }
        set { self[ColumnWidthKey.self] = newValue }
    }
}

// MARK: - Prose

/// §3 assistant prose: 14/20 at wght 360, paragraphs .75em apart, lists indented 2em with secondary markers, `strong` at
/// 560, inline code in danger red on white 5%, links in accent; 4 in from the start, the text stop from the end.
struct CDSProse: View {
    let text: String
    var color: Color = CDS.Text.primary
    /// Inside a card the insets reset to 0.
    var inset = true
    @Environment(\.cdsColumnWidth) private var width

    private enum Block { case paragraph(String), list([String], ordered: Bool) }

    var body: some View {
        let blocks = Self.blocks(text)
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { i, block in
                Group {
                    switch block {
                    case .paragraph(let p):
                        line(p)
                    case .list(let items, let ordered):
                        VStack(alignment: .leading, spacing: CDS.Transcript.itemFlow) {
                            ForEach(Array(items.enumerated()), id: \.offset) { n, item in
                                HStack(alignment: .firstTextBaseline, spacing: 0) {
                                    Text(ordered ? "\(n + 1)." : "•").cdsText(CDS.Transcript.text, .regular, CDS.Text.secondary)
                                        .frame(width: CDS.Transcript.listIndent - 6, alignment: .trailing)
                                        .padding(.trailing, 6)
                                    line(item).padding(.leading, CDS.Transcript.itemPad - (inset ? CDS.Transcript.textInset : 0))
                                }
                            }
                        }
                    }
                }
                .padding(.top, i == 0 ? 0 : Self.isList(blocks[i - 1]) ? CDS.Transcript.flow * 2 : CDS.Transcript.flow)
            }
        }
        .padding(.leading, inset ? CDS.Transcript.textInset : 0)
        .padding(.trailing, inset ? CDS.Transcript.textStop(width) : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ s: String) -> some View {
        Text(Self.attributed(s, color: color))
            .cdsText(CDS.Transcript.text, .regular, color)
            .tint(CDS.Text.accent)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private static func isList(_ b: Block) -> Bool { if case .list = b { true } else { false } }

    /// Blank lines split paragraphs; a run of "- ", "* " or "1. " lines is a list.
    private static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        for chunk in text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n\n") {
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            guard !lines.isEmpty else { continue }
            let bullets = lines.compactMap(bullet)
            if bullets.count == lines.count {
                out.append(.list(bullets.map(\.text), ordered: bullets[0].ordered))
            } else {
                out.append(.paragraph(chunk))
            }
        }
        return out.isEmpty ? [.paragraph(text)] : out
    }

    private static func bullet(_ line: String) -> (text: String, ordered: Bool)? {
        let t = line.drop { $0 == " " }
        if t.hasPrefix("- ") || t.hasPrefix("* ") { return (String(t.dropFirst(2)), false) }
        if let dot = t.firstIndex(of: "."), !t[..<dot].isEmpty, t[..<dot].allSatisfy(\.isNumber),
           t[t.index(after: dot)...].hasPrefix(" ") {
            return (String(t[t.index(dot, offsetBy: 2)...]), true)
        }
        return nil
    }

    /// The inline Markdown with Claude's prose styles set run by run (Anthropic Sans's weights are variable axes, so
    /// SwiftUI's own bold would not reach 560).
    static func attributed(_ s: String, color: Color = CDS.Text.primary) -> AttributedString {
        var out = RouterText.inline(s)
        for run in out.runs {
            let intent = run.inlinePresentationIntent ?? []
            let range = run.range
            if intent.contains(.code) {
                out[range].font = CDS.mono(CDS.Transcript.codeSize)
                out[range].foregroundColor = CDS.Text.danger
                out[range].backgroundColor = CDS.Transcript.codeFill
                continue
            }
            var font = CDS.sans(CDS.Transcript.text.0, intent.contains(.stronglyEmphasized) ? .bold : .regular)
            if intent.contains(.emphasized) { font = font.italic() }
            out[range].font = font
            if intent.contains(.strikethrough) {
                out[range].strikethroughStyle = Text.LineStyle(pattern: .solid, color: color.opacity(0.6))
            }
            if run.link != nil {
                out[range].foregroundColor = CDS.Text.accent
                out[range].underlineStyle = Text.LineStyle(pattern: .solid, color: CDS.Text.accent.opacity(0.4))
            }
        }
        // §3 inline code's .25em side padding: a thin space on white 5% either side.
        var padded = AttributedString()
        var lastWasCode = false
        for run in out.runs {
            let isCode = (run.inlinePresentationIntent ?? []).contains(.code)
            if isCode != lastWasCode { padded += pad(code: true) }
            padded += AttributedString(out[run.range])
            lastWasCode = isCode
        }
        if lastWasCode { padded += pad(code: true) }
        return padded
    }

    private static func pad(code: Bool) -> AttributedString {
        var s = AttributedString("\u{2009}")
        s.font = CDS.sans(CDS.Transcript.text.0)
        s.backgroundColor = CDS.Transcript.codeFill
        return s
    }
}

// MARK: - TurnStatus

/// The caret after a status label: 12 box, a ≈4 × 7 glyph, muted (secondary on hover or open), a quarter turn open.
struct StatusCaret: View {
    let hot: Bool
    let open: Bool

    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(hot || open ? CDS.Text.secondary : CDS.Text.muted)
            .rotationEffect(.degrees(open ? 90 : 0))
            .animation(.easeOut(duration: 0.06), value: open)
            .frame(width: CDS.Transcript.caretBox, height: CDS.Transcript.text.1)
            .accessibilityHidden(true)
    }
}

// MARK: - Working

/// §7: the clay mark in its 20 box, then the label in muted with the sheen passing over it.
struct WorkingStatus: View {
    let label: String

    var body: some View {
        HStack(spacing: CDS.Density.compact.gap.xs) {
            WorkingMark()
            ShimmerText(text: label)
        }
        .frame(height: CDS.Transcript.statusRow)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
}

/// The clay working mark: three dots at the start of a 20 box, the brightest one stepping along (still, the middle one,
/// as the sprite's frame in the reference).
struct WorkingMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { context in
            let lit = reduceMotion ? 1 : Int(context.date.timeIntervalSinceReferenceDate / 0.35) % 3
            HStack(spacing: CDS.Transcript.markDots.pitch - CDS.Transcript.markDots.size) {
                ForEach(0..<3) { i in
                    Circle().fill(CDS.clay.opacity(i == lit ? 1 : 0.55))
                        .frame(width: CDS.Transcript.markDots.size, height: CDS.Transcript.markDots.size)
                }
            }
            .frame(width: CDS.Transcript.markBox, height: CDS.Transcript.markBox, alignment: .leading)
        }
        .accessibilityHidden(true)
    }
}

/// §7's shimmer: muted text, a sheen one text-width wide sweeping across in 3 s (held 15% at either end).
struct ShimmerText: View {
    let text: String
    var role: (CGFloat, CGFloat) = CDS.Transcript.text
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let c = reduceMotion ? -1 : Self.centre(context.date.timeIntervalSinceReferenceDate)
            Text(text)
                .cdsText(role, .regular, CDS.Text.muted)
                .foregroundStyle(LinearGradient(
                    stops: [.init(color: CDS.Text.muted, location: 0), .init(color: CDS.Transcript.shimmerPeak, location: 0.5),
                            .init(color: CDS.Text.muted, location: 1)],
                    startPoint: UnitPoint(x: c - 0.5, y: 0.3), endPoint: UnitPoint(x: c + 0.5, y: 0.7)))
                .lineLimit(1)
        }
    }

    /// The sheen's centre in text widths: −0.5 to 1.5, eased `cubic-bezier(.714,.121,.211,.888)` over 15–85%.
    static func centre(_ t: Double) -> Double {
        let f = t.truncatingRemainder(dividingBy: CDS.Transcript.shimmerPeriod) / CDS.Transcript.shimmerPeriod
        let p = min(1, max(0, (f - 0.15) / 0.7))
        return -0.5 + 2 * bezier(p, 0.714, 0.121, 0.211, 0.888)
    }

    private static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        func coord(_ t: Double, _ a: Double, _ b: Double) -> Double { 3 * a * t * (1 - t) * (1 - t) + 3 * b * t * t * (1 - t) + t * t * t }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if coord(mid, x1, x2) < x { lo = mid } else { hi = mid }
        }
        return coord((lo + hi) / 2, y1, y2)
    }
}

// MARK: - Top fade

extension View {
    /// §1's sticky fade strip over a transcript: 32 tall, #151515 to clear, fading in over the first 32 of scroll.
    func cdsTopFade() -> some View { modifier(TopFade()) }
}

private struct TopFade: ViewModifier {
    /// How far the strip has faded in, 0 to 1: past the first 32 of scroll it stays 1, so scrolling further sets nothing.
    @State private var shown: CGFloat = 0

    func body(content: Content) -> some View {
        let s = CDS.Surface.s1
        let strip = LinearGradient(stops: [.init(color: s, location: 0), .init(color: s.opacity(0.85), location: 0.13),
                                           .init(color: s.opacity(0.5), location: 0.4), .init(color: s.opacity(0.15), location: 0.7),
                                           .init(color: s.opacity(0), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
            .frame(height: CDS.Transcript.fade)
            .allowsHitTesting(false)
        if #available(macOS 15, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) {
                    min(1, max(0, (($0.contentOffset.y + $0.contentInsets.top) / CDS.Transcript.fade * 16).rounded() / 16))
                } action: { shown = $1 }
                .overlay(alignment: .top) { strip.opacity(shown) }
        } else {
            content.overlay(alignment: .top) { strip }
        }
    }
}
