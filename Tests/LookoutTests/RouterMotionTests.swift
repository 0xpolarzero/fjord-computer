import Foundation
import Testing

/// Reduce Motion on the Router's page: every animation it starts goes through `Animation.resolved(reduce:)`, or `.motion`.
@Suite struct RouterMotionTests {
    private static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/Lookout")

    /// Each `withAnimation(` and `.animation(` with its argument, but neither a TimelineView's schedule
    /// (`TimelineView(.animation(…, paused: reduceMotion))`) nor a fade's own animation (`.opacity.animation(…)`); and
    /// `withAnimation {`, the default animation.
    private static let call = try! NSRegularExpression(pattern: #"(?:withAnimation|(?<![\w(])\.animation)\(([^\n]*)|withAnimation\s*\{"#)

    /// Unresolved for Reduce Motion: the call neither resolves its animation there nor passes one resolved before
    /// (`let motion = ….resolved(reduce:)`, `var spring: Animation? { ….resolved(reduce:) }`), nor no animation.
    static func unresolved(_ text: String) -> [Int] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var found: [Int] = []
        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            for match in call.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                guard match.range(at: 1).location != NSNotFound else { found.append(i + 1); continue }
                let argument = ns.substring(with: match.range(at: 1))
                if argument.contains("resolved(reduce:") || argument.hasPrefix("nil") { continue }
                let name = argument.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !name.isEmpty, argument.dropFirst(name.count).hasPrefix(")") {
                    let declared = try! Regex(#"\b(let|var) \#(name)\b.*resolved\(reduce:"#)
                    if lines.contains(where: { $0.contains(declared) }) { continue }
                }
                found.append(i + 1)
            }
        }
        return found
    }

    @Test func theRoutersAnimationsHonourReduceMotion() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.sources.path)
            .filter { $0.hasPrefix("Router") && $0.hasSuffix(".swift") }
        #expect(files.contains("RouterPage.swift"))
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8)
            found += Self.unresolved(text).map { "\(file):\($0)" }
        }
        #expect(found.isEmpty, "Unresolved for Reduce Motion: \(found)")
    }

    @Test func everyFormOfAnAnimationIsCaught() {
        let caught = """
            Button { withAnimation(.easeOut(duration: 0.15)) { dismiss() } }
            withAnimation(Theme.Motion.spring) { open() }
            withAnimation { open() }
            .animation(.easeOut(duration: 0.06), value: open)
            .animation(Theme.Motion.hover, value: on)
            withAnimation(plain) { open() }
            """
        #expect(Self.unresolved(caught) == [1, 2, 3, 4, 5, 6])
        let fine = """
            private var spring: Animation? { Theme.Motion.spring.resolved(reduce: reduceMotion) }
            withAnimation(spring) { open() }
            if let motion = Theme.Motion.hover.resolved(reduce: reduceMotion) { withAnimation(motion) { go() } }
            withAnimation(Theme.Motion.hover.resolved(reduce: reduceMotion)) { open() }
            .animation(Theme.Motion.fade.resolved(reduce: reduce), value: shown)
            .animation(nil, value: shown)
            .motion(.easeOut(duration: 0.06), value: open)
            .transition(.opacity.animation(.easeOut(duration: 0.2)))
            TimelineView(.animation(minimumInterval: 1 / 15, paused: reduceMotion)) { _ in }
            """
        #expect(Self.unresolved(fine).isEmpty)
    }
}
