import Foundation
import Testing
@testable import FjordComputer

@Suite struct CanvasObstaclesTests {
    /// The specification as a slow exhaustive oracle, independent of the interval index.
    private func exhaustive(_ frames: [(origin: CGPoint, size: CGSize, placed: Bool)]) -> [CGPoint] {
        var points = frames.map(\.origin)
        var occupied = frames.filter(\.placed).map { CGRect(origin: $0.origin, size: $0.size) }
        let order = frames.indices.filter { !frames[$0].placed }.sorted {
            let a = frames[$0].origin, b = frames[$1].origin
            return a.y != b.y ? a.y < b.y : a.x != b.x ? a.x < b.x : $0 < $1
        }
        for i in order {
            var rect = CGRect(origin: frames[i].origin, size: frames[i].size)
            while true {
                let collisions = occupied.filter {
                    rect.minX < $0.maxX + CanvasMetrics.pad && $0.minX < rect.maxX + CanvasMetrics.pad
                        && rect.minY < $0.maxY + CanvasMetrics.rowGap && $0.minY < rect.maxY + CanvasMetrics.rowGap
                }
                guard let bottom = collisions.map(\.maxY).max() else { break }
                rect.origin.y = bottom + CanvasMetrics.rowGap
            }
            points[i] = rect.origin
            occupied.append(rect)
        }
        return points
    }

    @Test func theIndexKeepsPackingExactAcrossOverlapsGapsNegativeCoordinatesAndWideFrames() {
        var seed: UInt64 = 1234
        func next(_ limit: Int) -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((seed >> 32) % UInt64(limit))
        }
        for _ in 0..<40 {
            let frames = (0..<32).map { i in
                (origin: CGPoint(x: next(2400) - 800.25, y: next(1200) - 400.5),
                 size: CGSize(width: next(900) + 320, height: next(900) + 44), placed: i % 5 == 0)
            }
            #expect(CanvasMetrics.resolve(frames) == exhaustive(frames))
        }
    }

    @Test func aThousandFramesStackWithoutAPairwiseScanAndPlacedFramesStayPut() {
        let frames = (0..<1000).map { i in
            (origin: CGPoint.zero, size: CGSize(width: 560, height: 44), placed: i == 0)
        }
        let points = CanvasMetrics.resolve(frames)
        #expect(points == (0..<1000).map { CGPoint(x: 0, y: CGFloat($0) * 92) })
    }
}
