import Foundation

// The palette's matcher and ranking (docs/design/palette/DESIGN.md, Ranking): text folded once per open, a match tier per
// query word (exact title, prefix, word-start prefix, acronym, substring, subsequence, keyword), a score inside the tier,
// and the usage store that reorders equals. The signatures at the top of each type are the contract the model relies on.

// MARK: - Folding

/// Text folded for matching: lowercased, accents dropped, œ/æ/ß spelled out, curly quotes straight, no-break spaces plain.
enum PaletteText {
    /// `text` folded: the same on the query and on the items, so "Œuvre", "oeuvre" and "ŒUVRE" are one string.
    static func fold(_ text: String) -> String {
        var folder = PaletteFolder()
        folder.append(text)
        var view = String.UnicodeScalarView()
        for v in folder.scalars { view.append(Unicode.Scalar(v) ?? " ") }
        return String(view)
    }
}

/// The folding itself, scalar by scalar, keeping for each folded scalar where it came from (so highlight ranges map back
/// to the original title) and whether it starts a word there (so camelCase and separators count, which folding loses).
fileprivate struct PaletteFolder {
    var scalars: [UInt32] = []
    /// Per folded scalar: bit 0 set when it starts a word of the original text.
    var flags: [UInt8] = []
    /// Per folded scalar: the offset, in unicode scalars, of the original scalar it came from.
    var origin: [Int32] = []
    private var cache: [UInt32: [UInt32]] = [:]

    enum Kind { case none, other, lower, upper, digit }

    mutating func append(_ text: String) {
        let src = Array(text.unicodeScalars)
        var prev = Kind.none
        for (i, s) in src.enumerated() {
            if s.value < 128 {
                let kind = Self.kind(of: s)
                var v = s.value
                if kind == .upper { v += 32 } else if (9...13).contains(v) { v = 32 }
                emit(v, start: Self.starts(kind, after: prev, next: i + 1 < src.count ? src[i + 1] : nil), from: i)
                prev = kind
            } else {
                let out = folded(s)
                if out.isEmpty { continue }
                let kind = Self.kind(of: s)
                var start = Self.starts(kind, after: prev, next: i + 1 < src.count ? src[i + 1] : nil)
                for v in out {
                    emit(v, start: start, from: i)
                    start = false
                }
                prev = kind
            }
        }
    }

    private mutating func emit(_ v: UInt32, start: Bool, from i: Int) {
        scalars.append(v)
        flags.append(start ? 1 : 0)
        origin.append(Int32(i))
    }

    private mutating func folded(_ s: Unicode.Scalar) -> [UInt32] {
        if let hit = cache[s.value] { return hit }
        let out = Self.foldNonASCII(s)
        cache[s.value] = out
        return out
    }

    /// What a non-ASCII scalar becomes: nothing for a combining mark, a few letters for the ligatures and the letters
    /// Unicode does not decompose (Foundation's diacritic folding leaves œ, æ, ø and ł alone), otherwise its base letters
    /// lowercased.
    private static func foldNonASCII(_ s: Unicode.Scalar) -> [UInt32] {
        switch s.value {
        case 0x153, 0x152: return [111, 101]
        case 0xE6, 0xC6: return [97, 101]
        case 0xDF, 0x1E9E: return [115, 115]
        case 0xF8, 0xD8: return [111]
        case 0x142, 0x141: return [108]
        case 0x111, 0x110, 0xF0, 0xD0: return [100]
        case 0xFE, 0xDE: return [116, 104]
        case 0x131: return [105]
        case 0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2BC: return [39]
        case 0x201C...0x201F, 0x2033: return [34]
        case 0x2010...0x2015, 0x2212: return [45]
        default: break
        }
        if s.properties.isWhitespace { return [32] }
        var out: [UInt32] = []
        for c in String(s).decomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
            if c.properties.generalCategory == .nonspacingMark { continue }
            out.append(c.properties.isWhitespace ? 32 : c.value)
        }
        return out
    }

    static func kind(of s: Unicode.Scalar) -> Kind {
        switch s.value {
        case 65...90: return .upper
        case 97...122: return .lower
        case 48...57: return .digit
        case 0..<128: return .other
        default:
            let p = s.properties
            if p.isWhitespace { return .other }
            if p.isUppercase { return .upper }
            if p.isLowercase || p.isAlphabetic { return .lower }
            return p.generalCategory == .decimalNumber ? .digit : .other
        }
    }

    /// Whether a scalar of `kind` after one of `prev` begins a word: after a separator or at the start, an uppercase letter
    /// after a lowercase one or a digit (getUserById), or the last capital of a run before a lowercase one (HTTPServer).
    private static func starts(_ kind: Kind, after prev: Kind, next: Unicode.Scalar?) -> Bool {
        switch kind {
        case .other, .none: return false
        default: break
        }
        switch prev {
        case .none, .other: return true
        case .lower, .digit: return kind == .upper
        case .upper: return kind == .upper && next.map { Self.kind(of: $0) == .lower } == true
        }
    }
}

/// One bit per character (a–z, 0–9, the rest hashed together): an item can only match a word whose bits it has all of.
@inline(__always)
fileprivate func paletteCharBit(_ c: UInt32) -> UInt64 {
    switch c {
    case 97...122: return 1 << UInt64(c - 97)
    case 48...57: return 1 << UInt64(26 + c - 48)
    default: return 1 << UInt64(36 + c % 28)
    }
}

// MARK: - The prepared items

/// Every item's folded title and keywords in one flat buffer, with the word starts, the origins of the folded scalars, and
/// a character bitmask per item to refuse most items before scoring. Built once per open, only read afterwards.
fileprivate final class PaletteCorpus: @unchecked Sendable {
    let scalars: UnsafeMutablePointer<UInt32>
    let flags: UnsafeMutablePointer<UInt8>
    /// Per folded scalar (titles only meaningful): offset of its original scalar.
    let origin: [Int32]
    let titleStart: [Int32]
    let titleCount: [Int32]
    /// Keyword spans of item `i` are `kwStart/kwCount[kwFirst[i]..<kwFirst[i + 1]]`.
    let kwFirst: [Int32]
    let kwStart: [Int32]
    let kwCount: [Int32]
    let mask: [UInt64]
    let titleMask: [UInt64]
    let weight: [Double]
    /// Seconds since 1970, negative infinity for no date (it sorts last).
    let dates: [Double]
    let slotByID: [String: Int]

    init(_ items: [PaletteItem]) {
        var folder = PaletteFolder()
        var titleStart: [Int32] = [], titleCount: [Int32] = []
        var kwFirst: [Int32] = [], kwStart: [Int32] = [], kwCount: [Int32] = []
        var mask: [UInt64] = [], titleMask: [UInt64] = [], weight: [Double] = [], dates: [Double] = []
        var slotByID: [String: Int] = [:]
        titleStart.reserveCapacity(items.count)
        for (slot, item) in items.enumerated() {
            slotByID[item.id] = slot
            let start = folder.scalars.count
            folder.append(item.title)
            titleStart.append(Int32(start))
            titleCount.append(Int32(folder.scalars.count - start))
            var tm: UInt64 = 0
            for k in start..<folder.scalars.count { tm |= paletteCharBit(folder.scalars[k]) }
            var all = tm
            kwFirst.append(Int32(kwStart.count))
            for keyword in item.keywords {
                let from = folder.scalars.count
                folder.append(keyword)
                let count = folder.scalars.count - from
                if count == 0 { continue }
                kwStart.append(Int32(from))
                kwCount.append(Int32(count))
                for k in from..<folder.scalars.count { all |= paletteCharBit(folder.scalars[k]) }
            }
            mask.append(all)
            titleMask.append(tm)
            weight.append(max(0, item.weight))
            dates.append(item.date?.timeIntervalSince1970 ?? -.infinity)
        }
        kwFirst.append(Int32(kwStart.count))
        let total = folder.scalars.count
        scalars = .allocate(capacity: max(total, 1))
        flags = .allocate(capacity: max(total, 1))
        scalars.initialize(from: folder.scalars, count: total)
        flags.initialize(from: folder.flags, count: total)
        origin = folder.origin
        self.titleStart = titleStart
        self.titleCount = titleCount
        self.kwFirst = kwFirst
        self.kwStart = kwStart
        self.kwCount = kwCount
        self.mask = mask
        self.titleMask = titleMask
        self.weight = weight
        self.dates = dates
        self.slotByID = slotByID
    }

    deinit {
        scalars.deallocate()
        flags.deallocate()
    }
}

/// The items of one open palette, prepared once (folded text) so each keystroke only scores.
struct PaletteIndex {
    let items: [PaletteItem]
    fileprivate let corpus: PaletteCorpus

    init(_ items: [PaletteItem]) {
        self.items = items
        corpus = PaletteCorpus(items)
    }
}

// MARK: - Matching one query against the corpus

/// How well a query word matched: a higher tier always wins, the score (0 to 100) orders inside a tier.
fileprivate enum PaletteTier {
    static let keyword = 1
    static let subsequence = 2
    static let substring = 3
    static let acronym = 4
    static let wordPrefix = 5
    static let prefix = 6
    static let exact = 7
}

/// One query's scan over a corpus: tiers and scores per item, and the matched stretches of a title when asked. A class for
/// its scratch memory (the query words and the subsequence matrix), allocated once per ranking.
fileprivate final class PaletteMatcher {
    private let corpus: PaletteCorpus
    private let query: UnsafeMutablePointer<UInt32>
    private var wordOffset: [Int] = []
    private var wordLength: [Int] = []
    private(set) var wordMask: [UInt64] = []
    private(set) var queryMask: UInt64 = 0
    private var phraseOffset = 0
    private var phraseLength = 0
    private var matrix: UnsafeMutablePointer<Int32>?

    /// The lowest tier worth finding: once the best rows are full of better matches, a weaker tier is not looked for.
    var minTier = 0
    /// Whether `marks` is filled: pairs (from, to) of folded title scalars the query matched.
    var collect = false
    var marks: [Int32] = []

    private static let maxFuzzyTitle = 256
    private static let maxFuzzyWord = 32
    private static let none: Int32 = -1_000_000_000

    init(_ corpus: PaletteCorpus, words: [[UInt32]]) {
        self.corpus = corpus
        let letters = words.reduce(0) { $0 + $1.count }
        query = .allocate(capacity: letters * 2 + words.count + 1)
        var at = 0
        for w in words {
            wordOffset.append(at)
            wordLength.append(w.count)
            var mask: UInt64 = 0
            for c in w {
                query[at] = c
                mask |= paletteCharBit(c)
                at += 1
            }
            wordMask.append(mask)
            queryMask |= mask
        }
        phraseOffset = at
        for (n, w) in words.enumerated() {
            if n > 0 {
                query[at] = 32
                at += 1
            }
            for c in w {
                query[at] = c
                at += 1
            }
        }
        phraseLength = at - phraseOffset
    }

    deinit {
        query.deallocate()
        matrix?.deallocate()
    }

    /// The tier and score of item `slot` for the whole query, or nil when it does not match: every word must match the
    /// title or a keyword, and the tier is the worst word's, unless the whole phrase is better placed in the title.
    func evaluate(_ slot: Int) -> (tier: Int, score: Double)? {
        let start = Int(corpus.titleStart[slot]), count = Int(corpus.titleCount[slot])
        let text = corpus.scalars + start, flags = corpus.flags + start
        let base = marks.count
        var tier = Int.max
        var total = 0.0
        for w in 0..<wordLength.count {
            let q = query + wordOffset[w], m = wordLength[w]
            var found: (Int, Double)?
            if wordMask[w] & ~corpus.titleMask[slot] == 0 { found = titleMatch(q, m, text, flags, count) }
            if found == nil, minTier <= PaletteTier.keyword { found = keywordMatch(q, m, slot) }
            guard let found else {
                if collect { marks.removeSubrange(base...) }
                return nil
            }
            tier = min(tier, found.0)
            total += found.1
        }
        var score = total / Double(wordLength.count)
        if wordLength.count > 1, tier < PaletteTier.exact, phraseLength <= count,
           let phrase = phraseMatch(text, count), phrase.0 > tier {
            tier = phrase.0
            score = phrase.1
            if collect {
                marks.removeSubrange(base...)
                marks.append(contentsOf: [Int32(phrase.2), Int32(phrase.2 + phraseLength)])
            }
        }
        return (tier, score)
    }

    @inline(__always)
    private func same(_ q: UnsafePointer<UInt32>, _ m: Int, _ t: UnsafePointer<UInt32>) -> Bool {
        var i = 0
        while i < m {
            if q[i] != t[i] { return false }
            i += 1
        }
        return true
    }

    private func mark(_ from: Int, _ to: Int) {
        if collect {
            marks.append(Int32(from))
            marks.append(Int32(to))
        }
    }

    /// The whole multi-word query as one stretch of the title: all of it, its start, or somewhere inside (tier, score, at).
    private func phraseMatch(_ t: UnsafePointer<UInt32>, _ n: Int) -> (Int, Double, Int)? {
        let q = query + phraseOffset, m = phraseLength
        if same(q, m, t) {
            return m == n ? (PaletteTier.exact, 100, 0) : (PaletteTier.prefix, 80 + 20 * Double(m) / Double(n), 0)
        }
        var j = 1
        while j <= n - m {
            if t[j] == q[0], same(q, m, t + j) {
                return (PaletteTier.substring, max(1, 40 + 40 * Double(m) / Double(n) - 0.5 * Double(min(j, 40))), j)
            }
            j += 1
        }
        return nil
    }

    /// A word against the title, in the best tier it reaches (marking what it matched), or nil.
    private func titleMatch(_ q: UnsafePointer<UInt32>, _ m: Int, _ t: UnsafePointer<UInt32>, _ f: UnsafePointer<UInt8>,
                            _ n: Int) -> (Int, Double)? {
        if m > n { return nil }
        let ratio = Double(m) / Double(n)
        if same(q, m, t) {
            mark(0, m)
            return m == n ? (PaletteTier.exact, 100) : (PaletteTier.prefix, 80 + 20 * ratio)
        }
        var inside = -1, wordStart = -1
        var j = 1
        while j <= n - m {
            if t[j] == q[0], same(q, m, t + j) {
                if inside < 0 { inside = j }
                if f[j] & 1 != 0 {
                    wordStart = j
                    break
                }
            }
            j += 1
        }
        if wordStart >= 0 {
            mark(wordStart, wordStart + m)
            return (PaletteTier.wordPrefix, 50 + 30 * ratio - 0.25 * Double(min(wordStart, 40)))
        }
        if m >= 2, let score = acronym(q, m, t, f, n) { return (PaletteTier.acronym, score) }
        if inside >= 0 {
            mark(inside, inside + m)
            return (PaletteTier.substring, max(1, 40 + 40 * ratio - 0.5 * Double(min(inside, 40))))
        }
        if m >= 2, minTier <= PaletteTier.subsequence, let score = subsequence(q, m, t, f, n) {
            return (PaletteTier.subsequence, score)
        }
        return nil
    }

    /// The query letters as the initials of title words, in order, skipping words if need be (getUserById, Router tools).
    private func acronym(_ q: UnsafePointer<UInt32>, _ m: Int, _ t: UnsafePointer<UInt32>, _ f: UnsafePointer<UInt8>,
                         _ n: Int) -> Double? {
        let base = marks.count
        var next = 0, skipped = 0
        for j in 0..<n where f[j] & 1 != 0 {
            if t[j] == q[next] {
                mark(j, j + 1)
                next += 1
                if next == m { return max(10, 90 - 6 * Double(skipped)) }
            } else {
                skipped += 1
            }
        }
        if collect { marks.removeSubrange(base...) }
        return nil
    }

    /// The query letters in order anywhere in the title, the best way through them: word starts and runs of consecutive
    /// letters score, gaps and a late start cost (the spirit of fzf's and Sublime's matchers).
    private func subsequence(_ q: UnsafePointer<UInt32>, _ m: Int, _ t: UnsafePointer<UInt32>, _ f: UnsafePointer<UInt8>,
                             _ n: Int) -> Double? {
        // Cheap refusal: the letters must appear in order at all.
        var next = 0
        for j in 0..<n where t[j] == q[next] {
            next += 1
            if next == m { break }
        }
        if next < m { return nil }
        if m > Self.maxFuzzyWord || n > Self.maxFuzzyTitle {
            // Too long for the matrix: the first letters found in order, scored low.
            if collect {
                var at = 0
                for j in 0..<n where t[j] == q[at] {
                    mark(j, j + 1)
                    at += 1
                    if at == m { break }
                }
            }
            return 10
        }
        if matrix == nil { matrix = .allocate(capacity: Self.maxFuzzyWord * Self.maxFuzzyTitle) }
        let grid = matrix!
        let none = Self.none
        for i in 0..<m {
            var gap = none
            let row = grid + i * n
            for j in 0..<n {
                if i > 0, j >= 2 { gap = max(gap - 1, grid[(i - 1) * n + j - 2] - 3) }
                var best = none
                if t[j] == q[i] {
                    let bonus: Int32 = f[j] & 1 != 0 ? 8 : 0
                    if i == 0 {
                        best = 16 + 2 * bonus - Int32(min(j, 12))
                    } else {
                        if j >= 1 {
                            let p = grid[(i - 1) * n + j - 1]
                            if p > none / 2 { best = p + 16 + max(bonus, 5) }
                        }
                        if gap > none / 2 { best = max(best, gap + 16 + bonus) }
                    }
                }
                row[j] = best
            }
        }
        let last = grid + (m - 1) * n
        var end = -1
        var top = none / 2
        for j in 0..<n where last[j] > top {
            top = last[j]
            end = j
        }
        if end < 0 { return nil }
        if collect { trace(grid, q, m, f, n, from: end) }
        let size = Double(m) * 24 + 8
        let score = max(1, min(100, 100 * Double(top) / size))
        return score * (1 - 0.15 * Double(min(n, 100)) / 100)
    }

    /// Walks the matrix back from the best last letter to where each letter matched, and marks them.
    private func trace(_ grid: UnsafePointer<Int32>, _ q: UnsafePointer<UInt32>, _ m: Int, _ f: UnsafePointer<UInt8>, _ n: Int,
                       from end: Int) {
        let none = Self.none
        var j = end
        var found: [Int32] = []
        var i = m - 1
        while true {
            found.append(Int32(j))
            if i == 0 { break }
            let here = grid[i * n + j]
            let bonus: Int32 = f[j] & 1 != 0 ? 8 : 0
            if j >= 1, grid[(i - 1) * n + j - 1] > none / 2, grid[(i - 1) * n + j - 1] + 16 + max(bonus, 5) == here {
                j -= 1
            } else {
                var k = j - 2
                while k >= 0 {
                    let p = grid[(i - 1) * n + k]
                    if p > none / 2, p - 3 - Int32(j - 2 - k) + 16 + bonus == here { break }
                    k -= 1
                }
                j = max(k, 0)
            }
            i -= 1
        }
        for p in found.reversed() { mark(Int(p), Int(p) + 1) }
    }

    /// A word against the item's keywords: the best of equal, prefix, word start, inside (one letter only counts at a word
    /// start, or every keyword would hold it). Keywords are never highlighted.
    private func keywordMatch(_ q: UnsafePointer<UInt32>, _ m: Int, _ slot: Int) -> (Int, Double)? {
        var best = 0.0
        for k in Int(corpus.kwFirst[slot])..<Int(corpus.kwFirst[slot + 1]) {
            let n = Int(corpus.kwCount[k])
            if m > n { continue }
            let start = Int(corpus.kwStart[k])
            let t = corpus.scalars + start, f = corpus.flags + start
            if same(q, m, t) {
                if m == n { return (PaletteTier.keyword, 100) }
                best = max(best, 70 + 15 * Double(m) / Double(n))
                continue
            }
            var j = 1
            while j <= n - m {
                if t[j] == q[0], same(q, m, t + j) {
                    if f[j] & 1 != 0 {
                        best = max(best, 55 + 15 * Double(m) / Double(n))
                        break
                    }
                    if m >= 2 { best = max(best, 35 + 15 * Double(m) / Double(n)) }
                }
                j += 1
            }
        }
        return best > 0 ? (PaletteTier.keyword, best) : nil
    }
}

// MARK: - Ranking

/// One ranked row: the item, and the ranges of its title the query matched (for the highlight).
struct PaletteHit: Identifiable {
    let item: PaletteItem
    let ranges: [Range<String.Index>]
    var id: String { item.id }
}

@MainActor
enum PaletteRanker {
    /// The items matching `query`, best first, at most `limit`. An empty query matches nothing (the empty palette shows
    /// its groups instead).
    static func rank(_ query: String, in index: PaletteIndex, usage: PaletteUsage?, now: Date = Date(), limit: Int = 50)
        -> [PaletteHit] {
        let words = queryWords(query)
        let corpus = index.corpus
        guard !words.isEmpty, limit > 0, !index.items.isEmpty else { return [] }
        let matcher = PaletteMatcher(corpus, words: words)

        // The usage boosts of the few items that have one, spread over the slots once.
        var boostAt: [Double]?
        if let usage {
            let folded = words.map { word -> String in
                var view = String.UnicodeScalarView()
                for v in word { view.append(Unicode.Scalar(v) ?? " ") }
                return String(view)
            }.joined(separator: " ")
            let boosts = usage.boosts(query: folded, now: now)
            if !boosts.isEmpty {
                var dense = [Double](repeating: 1, count: index.items.count)
                for (id, boost) in boosts { if let slot = corpus.slotByID[id] { dense[slot] = boost } }
                boostAt = dense
            }
        }

        struct Candidate {
            var slot: Int
            var tier: Int
            var score: Double
        }
        var top: [Candidate] = []
        top.reserveCapacity(limit + 1)
        let items = index.items
        func before(_ a: Candidate, _ b: Candidate) -> Bool {
            if a.tier != b.tier { return a.tier > b.tier }
            if a.score != b.score { return a.score > b.score }
            let (xd, yd) = (corpus.dates[a.slot], corpus.dates[b.slot])
            if xd != yd { return xd > yd }
            let order = items[a.slot].title.localizedStandardCompare(items[b.slot].title)
            if order != .orderedSame { return order == .orderedAscending }
            return items[a.slot].id < items[b.slot].id
        }
        for slot in 0..<items.count where corpus.mask[slot] & matcher.queryMask == matcher.queryMask {
            guard let (tier, score) = matcher.evaluate(slot) else { continue }
            let candidate = Candidate(slot: slot, tier: tier, score: score * corpus.weight[slot] * (boostAt?[slot] ?? 1))
            if top.count == limit, !before(candidate, top[limit - 1]) { continue }
            var low = 0, high = top.count
            while low < high {
                let mid = (low + high) / 2
                if before(top[mid], candidate) { low = mid + 1 } else { high = mid }
            }
            top.insert(candidate, at: low)
            if top.count > limit { top.removeLast() }
            if top.count == limit { matcher.minTier = top[limit - 1].tier }
        }

        matcher.collect = true
        matcher.minTier = 0
        return top.map { candidate in
            matcher.marks.removeAll(keepingCapacity: true)
            _ = matcher.evaluate(candidate.slot)
            let item = items[candidate.slot]
            return PaletteHit(item: item, ranges: ranges(of: matcher.marks, in: item.title, slot: candidate.slot, corpus: corpus))
        }
    }

    /// The query's words, folded: split at spaces, none empty.
    private static func queryWords(_ query: String) -> [[UInt32]] {
        var folder = PaletteFolder()
        folder.append(query)
        return folder.scalars.split(separator: 32).map(Array.init)
    }

    /// The ranges of `title` for the matched stretches (pairs of folded scalar offsets): back to the original scalars,
    /// merged where they touch, and widened to whole characters so a letter and its accent are never split.
    private static func ranges(of marks: [Int32], in title: String, slot: Int, corpus: PaletteCorpus) -> [Range<String.Index>] {
        guard !marks.isEmpty else { return [] }
        let first = Int(corpus.titleStart[slot])
        var spans: [(Int, Int)] = []
        for p in stride(from: 0, to: marks.count, by: 2) {
            spans.append((Int(corpus.origin[first + Int(marks[p])]), Int(corpus.origin[first + Int(marks[p + 1]) - 1]) + 1))
        }
        spans.sort { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }
        var merged: [(Int, Int)] = []
        for s in spans {
            if let last = merged.last, s.0 <= last.1 { merged[merged.count - 1].1 = max(last.1, s.1) } else { merged.append(s) }
        }
        // Character boundaries as (scalar offset, index).
        var bounds: [(Int, String.Index)] = []
        var offset = 0
        for i in title.indices {
            bounds.append((offset, i))
            offset += title[i].unicodeScalars.count
        }
        bounds.append((offset, title.endIndex))
        func down(_ o: Int) -> String.Index { bounds.last { $0.0 <= o }?.1 ?? title.startIndex }
        func up(_ o: Int) -> String.Index { bounds.first { $0.0 >= o }?.1 ?? title.endIndex }
        var out: [Range<String.Index>] = []
        for s in merged {
            let range = down(s.0)..<up(s.1)
            if let last = out.last, range.lowerBound <= last.upperBound {
                out[out.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
            } else {
                out.append(range)
            }
        }
        return out
    }
}

// MARK: - Usage

/// What was picked, when, and after typing what: the palette's memory, kept in the user's defaults.
///
/// Two memories feed `boost`: how often and how recently an item was picked at all (frecency, half-life a week), and which
/// item was picked after typing a query (adaptive history: the same query, or one that extends it, finds it first).
@MainActor
final class PaletteUsage {
    /// Where the store lives in the defaults: compact JSON, written on each pick.
    static let defaultsKey = "palette.usage"

    private struct ItemUse {
        /// log2 of the frecency projected to the epoch: the decayed score at time `t` is `2^(l - t)` in half-lives, so
        /// nothing is rescored as time passes and a new pick is a log-sum-exp.
        var l: Double
        var last: Double
        var seq: Int
    }

    private struct QueryUse {
        /// Picks after this query, each worth 1 at its time and 0.9 of the one before (`count * 0.9 + 1`), decayed since.
        var count: Double
        var last: Double
    }

    private struct Stored: Codable {
        var n = 0
        /// item id → [l, last pick (seconds), sequence]
        var i: [String: [Double]] = [:]
        /// item id → query → [count, last pick (seconds)]
        var q: [String: [String: [Double]]] = [:]
    }

    private static let frecencyHalfLife: Double = 7 * 86400
    private static let queryHalfLife: Double = 21 * 86400
    private static let maxItems = 500
    private static let maxQueries = 2000

    private let defaults: UserDefaults?
    private var items: [String: ItemUse] = [:]
    private var learned: [String: [String: QueryUse]] = [:]
    private var learnedCount = 0
    private var seq = 0

    /// `defaults`: nil keeps nothing (demo, shots, tests).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        guard let data = defaults?.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        seq = stored.n
        for (id, v) in stored.i where v.count == 3 { items[id] = ItemUse(l: v[0], last: v[1], seq: Int(v[2])) }
        for (id, byQuery) in stored.q {
            for (query, v) in byQuery where v.count == 2 {
                learned[id, default: [:]][query] = QueryUse(count: v[0], last: v[1])
                learnedCount += 1
            }
        }
    }

    /// Remembers a pick of `itemID` after typing `query` (empty: picked from the empty palette).
    func record(_ itemID: String, query: String, now: Date = Date()) {
        let t = Self.halfLives(now)
        let seconds = Self.round(now.timeIntervalSince1970, 3)
        seq += 1
        if let old = items[itemID] {
            let high = max(old.l, t), low = min(old.l, t)
            items[itemID] = ItemUse(l: Self.round(high + log2(1 + exp2(low - high)), 4), last: seconds, seq: seq)
        } else {
            items[itemID] = ItemUse(l: Self.round(t, 4), last: seconds, seq: seq)
        }
        let typed = Self.normalized(query)
        if !typed.isEmpty {
            let before = learned[itemID]?[typed]
            let decayed = before.map { Self.decayedCount($0, at: now) } ?? 0
            learned[itemID, default: [:]][typed] = QueryUse(count: Self.round(decayed * 0.9 + 1, 4), last: seconds)
            if before == nil { learnedCount += 1 }
        }
        prune(keeping: itemID, now: now)
        save()
    }

    /// The ids picked last, newest first.
    func recent(_ count: Int) -> [String] {
        items.sorted {
            if $0.value.last != $1.value.last { return $0.value.last > $1.value.last }
            if $0.value.seq != $1.value.seq { return $0.value.seq > $1.value.seq }
            return $0.key < $1.key
        }.prefix(max(0, count)).map(\.key)
    }

    /// How much more `itemID` is worth among equal matches for the (folded) `query`: 1 for an item never picked, up to 3.6
    /// for one picked often and lately after this very query. Never below 1.
    func boost(for itemID: String, query folded: String, now: Date) -> Double {
        let typed = Self.normalized(folded)
        var boost = items[itemID].map { Self.frecencyBoost($0, at: now) } ?? 1
        if let byQuery = learned[itemID] { boost *= Self.learnedBoost(byQuery, typed: typed, now: now) }
        return boost
    }

    /// The boost of every item that has one (more than 1), by id: what the ranker spreads over its slots in one go.
    func boosts(query folded: String, now: Date) -> [String: Double] {
        let typed = Self.normalized(folded)
        var out: [String: Double] = [:]
        for (id, use) in items { out[id] = Self.frecencyBoost(use, at: now) }
        if !typed.isEmpty {
            for (id, byQuery) in learned {
                let boost = Self.learnedBoost(byQuery, typed: typed, now: now)
                if boost > 1 { out[id, default: 1] *= boost }
            }
        }
        return out
    }

    // MARK: Boost arithmetic

    /// 1 plus a share that grows with the decayed pick score and stops at 1.8.
    private static func frecencyBoost(_ use: ItemUse, at now: Date) -> Double {
        let score = exp2(use.l - halfLives(now))
        return 1 + min(0.8, 0.3 * log2(1 + score))
    }

    /// 1 plus what the item was picked for after queries the typed one equals or extends (a full share) or is the start of
    /// (a smaller one: "ro" finds what "router" found), at most 1.
    private static func learnedBoost(_ byQuery: [String: QueryUse], typed: String, now: Date) -> Double {
        guard !typed.isEmpty else { return 1 }
        var share = 0.0
        for (query, use) in byQuery {
            let weight: Double
            if typed.utf8.starts(with: query.utf8) {
                weight = 1
            } else if query.utf8.starts(with: typed.utf8) {
                weight = 0.7
            } else {
                continue
            }
            share += weight * decayedCount(use, at: now)
        }
        return 1 + min(1, 0.5 * share)
    }

    private static func decayedCount(_ use: QueryUse, at now: Date) -> Double {
        use.count * exp2(-max(0, now.timeIntervalSince1970 - use.last) / queryHalfLife)
    }

    private static func halfLives(_ date: Date) -> Double { date.timeIntervalSince1970 / frecencyHalfLife }

    private static func round(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10, Double(places))
        return (value * scale).rounded() / scale
    }

    /// A query as stored and compared: folded, words separated by one space.
    private static func normalized(_ query: String) -> String {
        PaletteText.fold(query).split(separator: " ").joined(separator: " ")
    }

    // MARK: Keeping it small

    /// Drops the weakest items and learned queries past their caps, never the one just picked.
    private func prune(keeping itemID: String, now: Date) {
        if items.count > Self.maxItems {
            let t = Self.halfLives(now)
            let weakest = items.filter { $0.key != itemID }.sorted { $0.value.l - t < $1.value.l - t }
            for (id, _) in weakest.prefix(items.count - Self.maxItems) { items[id] = nil }
        }
        if learnedCount > Self.maxQueries {
            var all: [(id: String, query: String, strength: Double)] = []
            for (id, byQuery) in learned {
                for (query, use) in byQuery { all.append((id, query, Self.decayedCount(use, at: now))) }
            }
            all.sort { $0.strength != $1.strength ? $0.strength < $1.strength : ($0.id, $0.query) < ($1.id, $1.query) }
            for entry in all.prefix(learnedCount - Self.maxQueries) where entry.id != itemID {
                learned[entry.id]?[entry.query] = nil
                if learned[entry.id]?.isEmpty == true { learned[entry.id] = nil }
                learnedCount -= 1
            }
        }
    }

    private func save() {
        guard let defaults else { return }
        var stored = Stored(n: seq)
        for (id, use) in items { stored.i[id] = [use.l, use.last, Double(use.seq)] }
        for (id, byQuery) in learned { stored.q[id] = byQuery.mapValues { [$0.count, $0.last] } }
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
