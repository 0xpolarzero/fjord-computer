import Foundation

/// The occupied ground, indexed by the frames' fixed horizontal edges. A vertical interval union at each segment-tree
/// node lets a packed frame skip a whole stack at once, without comparing it with every previously placed frame.
struct CanvasObstacles {
    private let edges: [CGFloat]
    private let root: Column?

    init(_ rects: [CGRect]) {
        edges = Array(Set(rects.flatMap { [$0.minX - CanvasMetrics.pad / 2, $0.maxX + CanvasMetrics.pad / 2] })).sorted()
        root = edges.count > 1 ? Column(0, edges.count - 1) : nil
    }

    private func index(_ value: CGFloat) -> Int {
        var lo = 0, hi = edges.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if edges[mid] < value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    func insert(_ rect: CGRect) {
        root?.insert(index(rect.minX - CanvasMetrics.pad / 2), index(rect.maxX + CanvasMetrics.pad / 2),
                     rect.minY - CanvasMetrics.rowGap / 2, rect.maxY + CanvasMetrics.rowGap / 2)
    }

    func bottom(overlapping rect: CGRect) -> CGFloat? {
        root?.bottom(index(rect.minX - CanvasMetrics.pad / 2), index(rect.maxX + CanvasMetrics.pad / 2),
                     rect.minY - CanvasMetrics.rowGap / 2, rect.maxY + CanvasMetrics.rowGap / 2)
            .map { $0 + CanvasMetrics.rowGap / 2 }
    }

    private final class Column {
        let lo: Int, hi: Int
        let all = Intervals(), own = Intervals()
        var left: Column?, right: Column?
        init(_ lo: Int, _ hi: Int) { self.lo = lo; self.hi = hi }

        func insert(_ x0: Int, _ x1: Int, _ y0: CGFloat, _ y1: CGFloat) {
            guard x0 < hi, x1 > lo else { return }
            all.insert(y0, y1)
            if x0 <= lo, x1 >= hi { own.insert(y0, y1); return }
            let mid = (lo + hi) / 2
            if x0 < mid {
                if left == nil { left = Column(lo, mid) }
                left?.insert(x0, x1, y0, y1)
            }
            if x1 > mid {
                if right == nil { right = Column(mid, hi) }
                right?.insert(x0, x1, y0, y1)
            }
        }

        func bottom(_ x0: Int, _ x1: Int, _ y0: CGFloat, _ y1: CGFloat) -> CGFloat? {
            guard x0 < hi, x1 > lo else { return nil }
            if x0 <= lo, x1 >= hi { return all.bottom(y0, y1) }
            let values = [own.bottom(y0, y1), left?.bottom(x0, x1, y0, y1), right?.bottom(x0, x1, y0, y1)]
            return values.compactMap { $0 }.max()
        }
    }

    /// Disjoint vertical intervals in a treap: inserts merge overlaps, and a query finds its last overlap in logarithmic
    /// expected time. Priorities are a deterministic mixed sequence, so ordered canvas coordinates don't make a chain.
    private final class Intervals {
        private final class Node {
            let lo: CGFloat, hi: CGFloat, priority: UInt64
            var left: Node?, right: Node?
            init(_ lo: CGFloat, _ hi: CGFloat, _ priority: UInt64) { self.lo = lo; self.hi = hi; self.priority = priority }
        }
        private var root: Node?
        private var sequence: UInt64 = 0

        private func priority() -> UInt64 {
            sequence &+= 0x9e3779b97f4a7c15
            var x = sequence
            x = (x ^ (x >> 30)) &* 0xbf58476d1ce4e5b9
            x = (x ^ (x >> 27)) &* 0x94d049bb133111eb
            return x ^ (x >> 31)
        }

        private func before(_ key: CGFloat, inclusive: Bool) -> Node? {
            var node = root, found: Node?
            while let current = node {
                if current.lo < key || (inclusive && current.lo == key) { found = current; node = current.right }
                else { node = current.left }
            }
            return found
        }

        private func after(_ key: CGFloat) -> Node? {
            var node = root, found: Node?
            while let current = node {
                if current.lo >= key { found = current; node = current.left } else { node = current.right }
            }
            return found
        }

        func bottom(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat? {
            guard let node = before(hi, inclusive: false), node.hi > lo else { return nil }
            return node.hi
        }

        func insert(_ lower: CGFloat, _ upper: CGFloat) {
            var lo = lower, hi = upper
            if let previous = before(lo, inclusive: true), previous.hi >= lo {
                lo = previous.lo; hi = max(hi, previous.hi)
                root = erase(root, previous.lo)
            }
            while let next = after(lo), next.lo <= hi {
                hi = max(hi, next.hi)
                root = erase(root, next.lo)
            }
            root = insert(root, Node(lo, hi, priority()))
        }

        private func merge(_ left: Node?, _ right: Node?) -> Node? {
            guard let left else { return right }
            guard let right else { return left }
            if left.priority < right.priority { left.right = merge(left.right, right); return left }
            right.left = merge(left, right.left); return right
        }

        private func erase(_ node: Node?, _ key: CGFloat) -> Node? {
            guard let node else { return nil }
            if key == node.lo { return merge(node.left, node.right) }
            if key < node.lo { node.left = erase(node.left, key) } else { node.right = erase(node.right, key) }
            return node
        }

        private func insert(_ root: Node?, _ node: Node) -> Node {
            guard let root else { return node }
            if node.lo < root.lo {
                root.left = insert(root.left, node)
                if let left = root.left, left.priority < root.priority {
                    root.left = left.right; left.right = root; return left
                }
            } else {
                root.right = insert(root.right, node)
                if let right = root.right, right.priority < root.priority {
                    root.right = right.left; right.left = root; return right
                }
            }
            return root
        }
    }
}
