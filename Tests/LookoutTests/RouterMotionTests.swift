import Foundation
import Testing

/// Reduce Motion on the Router's page: every animation it starts goes through `Animation.resolved(reduce:)`.
@Suite struct RouterMotionTests {
    private static let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Sources/Lookout")

    @Test func theRoutersAnimationsHonourReduceMotion() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.sources.path)
            .filter { $0.hasPrefix("Router") && $0.hasSuffix(".swift") }
        #expect(files.contains("RouterPage.swift"))
        let bare = try Regex(#"withAnimation\(Theme\.Motion\.\w+\)"#)
        var found: [String] = []
        for file in files {
            let text = try String(contentsOf: Self.sources.appendingPathComponent(file), encoding: .utf8)
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() where line.contains(bare) {
                found.append("\(file):\(i + 1)")
            }
        }
        #expect(found.isEmpty, "Unresolved for Reduce Motion: \(found)")
    }
}
