# Fuzzy matching and result ranking for a Swift macOS ⌘K palette

Scope: matcher algorithms, ranking/frecency models, Swift libraries, diacritics/locale handling, and per-keystroke performance, for a palette over a few hundred to a few thousand items (session titles, categories, actions, settings). Verified 2026-10-14 against GitHub API metadata, raw source files and READMEs unless marked otherwise.

## Algorithms: what each matcher does, and what it handles (typos vs. subsequence vs. acronym, highlight output)

### Takeaway
Best-in-class palettes and finders use one of two matcher families. (1) Subsequence matchers that score each matched character, with bonuses for word boundaries, camelCase and consecutive runs and penalties for gaps: fzf v2 and nucleo (Smith-Waterman variants), Sublime/Forrest Smith, VS Code fuzzyScore, cmdk command-score and Zed. These handle abbreviations and acronyms well and return exact match positions for highlighting, but they reject typos: every query character must appear, in order. (2) Approximate matchers: Bitap/fuse.js, or Damerau-Levenshtein as in ordo-one/FuzzyMatch's ED mode. These tolerate typos and transpositions but weight boundaries less well, unless they are combined with a subsequence/acronym pass the way FuzzyMatch does it.

### Cited Findings
**fzf (junegunn/fzf, Go, MIT, 83.6k stars, v0.74.5 released 2026-10-11)**
- FuzzyMatchV1 is greedy and O(n). It scans forward to the first occurrence of the last pattern character, then scans backward for a shorter substring. It "only sees the first occurrence" and so isn't guaranteed to find the highest score. — [fzf algo.go](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go)
- FuzzyMatchV2 is "a modified version of Smith-Waterman" that finds the optimal (highest-scoring) alignment. "Omission or mismatch of a character in the pattern is not allowed", so it has no typo tolerance. It costs O(nm) when a match exists and O(n) otherwise. `--algo=v1` remains available for speed. — [fzf algo.go](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go)
- Constants: scoreMatch=16, scoreGapStart=-3, scoreGapExtension=-1, bonusBoundary=scoreMatch/2 (8), bonusNonWord=8, bonusConsecutive=-(gapStart+gapExtension)=4, bonusFirstCharMultiplier=2, with whitespace and delimiter boundary variants (bonusBoundary+2 / +1 depending on scheme). The parameters were chosen so "the bonus is cancelled when the gap size increases beyond 8 characters". Consecutive chunks inherit the bonus of their first character, which fixes the "foobar vs foo-bar on foob" anomaly. — [fzf algo.go](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go)
- fzf also ships ExactMatchNaive, ExactMatchBoundary, PrefixMatch, SuffixMatch and EqualMatch (the extended-search operators `'`, `^`, `$`). A `normalize.go` table maps Latin letters with diacritics to their base letter (á→a and so on), which is how fzf matches "é" when "e" is typed. — [fzf algo.go](https://github.com/junegunn/fzf/blob/master/src/algo/algo.go); [fzf normalize.go](https://github.com/junegunn/fzf/blob/master/src/algo/normalize.go)

**nucleo (helix-editor/nucleo, Rust, MPL-2.0, 1.5k stars; latest GitHub release nucleo-v0.4.0 2024-02-20, last push 2026-06-24)**
- Uses "the exact same scoring system as fzf" but implements affine-gap Smith-Waterman faithfully, with two matrices where fzf uses one. It therefore "finds the optimal match more often": for `foo` in `xf foo` nucleo matches `x__foo` and fzf matches `xf_oo`. — [nucleo README](https://github.com/helix-editor/nucleo)
- Matches on graphemes (first codepoint) and reports grapheme indices for highlighting. fzf and skim work on codepoints. It uses aggressive prefiltering, an ASCII special case, and a greedy O(N) fallback for very long matches. — [nucleo README](https://github.com/helix-editor/nucleo)
- About 6x faster than skim. Linux-kernel file list: about 2.1–2.6 ms per pattern for nucleo against 17–18 ms for skim. With about 3M items, pasting `///.` takes about 1 s in fzf and about 1 frame in nucleo (Ryzen 5950X, "unscientific"). — [nucleo README](https://github.com/helix-editor/nucleo)

**Sublime Text fuzzy match (Forrest Smith's reverse-engineering, 2016-03-28, updated 2017-02-18)**
- Scores: matched letter +0, unmatched letter −1 each, consecutive +5, separator bonus (after space or underscore) +10, camelCase bonus +10, unmatched leading letters −3 each with a cap of −9. Scores fall roughly between −50 and +50. — [Forrest Smith blog](https://www.forrestthewoods.com/blog/reverse_engineering_sublime_texts_fuzzy_match/)
- The 2017 update replaced first-match search with an exhaustive (recursive) search that returns the best-scoring match. It is slower but gives better results, and followed feedback from Sublime's Jon Skinner. — [Forrest Smith blog](https://www.forrestthewoods.com/blog/reverse_engineering_sublime_texts_fuzzy_match/)
- Perf: 13,164 UE4 filenames in about 5 ms single-threaded C++ on an i5-4670. 355k words in about 50 ms. The JS version is about 25x slower than C++. — [Forrest Smith blog](https://www.forrestthewoods.com/blog/reverse_engineering_sublime_texts_fuzzy_match/)
- Reference code: forrestthewoods/lib_fts (701 stars, last push 2022-11-13, no SPDX license detected by GitHub). — GitHub API, [lib_fts](https://github.com/forrestthewoods/lib_fts)

**VS Code fuzzyScorer (Quick Open)**
- `computeCharScore`: +1 per match, a consecutive bonus of `min(seqLen,3)*6 + max(0,seqLen-3)*3`, +1 for same case, +8 at start of word, separator bonuses (path separators 5, other separators 4), and +2 for a camelCase-style position. — [vscode fuzzyScorer.ts](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/fuzzyScorer.ts)
- Item scoring is tiered with hard thresholds: PATH_IDENTITY_SCORE = 1<<18, LABEL_PREFIX_SCORE_THRESHOLD = 1<<17, LABEL_SCORE_THRESHOLD = 1<<16. Any label prefix match beats any label fuzzy match, which beats description/path matches. Ties break toward label matches, then more compact matches, then shorter labels, then shorter paths. Multi-word queries are scored piece by piece. — [vscode fuzzyScorer.ts](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/fuzzyScorer.ts)

**cmdk command-score (pacocoursey/cmdk, MIT, 13k stars, v1.1.1 2025-03-14)**
- Multiplicative scoring with a maximum of 1: continue match 1.0, word jump after space 0.9, word jump after other separators 0.8, character jump 0.17, transposition 0.1 (cmdk does tolerate adjacent swaps). Per skipped character ×0.999, case mismatch ×0.9999, distance from start ×0.9, incomplete match ×0.99 ("html" ranks above "html5"). — [cmdk command-score.ts](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/command-score.ts)
- The default filter is `commandScore(value, search, keywords)`. Items can carry `keywords` aliases that are matched too, and items are sorted by score. — [cmdk index.tsx](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/index.tsx)

**Zed fuzzy crate**
- A 64-bit `CharBag` bitmask prefilter (the candidate must be a superset of the query's characters), then a recursive scorer. Character score is 1.0 when consecutive, 0.9 after `/`, 0.8 after `-`, `_`, space, a digit or a lower→upper transition, and 0.7 after `.`. Other jumps decay from 0.6 by 0.05 per skipped character down to a floor of 0.2. A case mismatch under smart_case is multiplied by 0.001. — [zed matcher.rs](https://github.com/zed-industries/zed/blob/main/crates/fuzzy/src/matcher.rs)

**fuse.js / Bitap (krisk; Swift ports fuse-swift and Ifrit)**
- Bitap (shift-or) with a threshold: approximate matching that tolerates typos ("stve" → "Steve Hamilton" in the fuse-swift README example), supports weighted keys, and returns matched index ranges (UTF-16 offsets in fuse-swift). — [fuse-swift README](https://github.com/krisk/fuse-swift)
- In the FuzzyMatch benchmark, Ifrit (Bitap) is strong on typos (36/41) but weak on abbreviations (1/12 = 8%), against fzf's 6/12 and nucleo's 4/12. — [FuzzyMatch COMPARISON.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/COMPARISON.md)

**Damerau-Levenshtein hybrid (ordo-one/FuzzyMatch ED mode)**
- Match strategy: exact match, then prefix edit distance, then substring edit distance if the prefix score is below 0.7, then position bonuses, then subsequence matching with bonuses if there is no edit-distance match, then an acronym pass for 2–8-character queries against word initials. — [FuzzyMatch DAMERAU_LEVENSHTEIN.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/DAMERAU_LEVENSHTEIN.md)
- On a 272K-instrument corpus with 152 ground-truth queries: FuzzyMatch ED 98%, Ifrit 88%, FuzzyMatch SW 84%, fzf 82%, RapidFuzz 80–81%, nucleo 79%. Typos: ED 41/41, Ifrit 36/41, nucleo 23/41, fzf 22/41. Note that this is the library author's own benchmark on financial data. — [FuzzyMatch COMPARISON.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/COMPARISON.md)

**Typo / subsequence / acronym summary (from the sources above)**
- Subsequence-only (no typos): fzf v1/v2, nucleo, Sublime, VS Code, Zed. cmdk has subsequence matching plus a heavily penalized adjacent transposition.
- Typo-tolerant: fuse.js/Bitap (Ifrit, fuse-swift) and FuzzyMatch ED (Damerau-Levenshtein with transpositions).
- Acronym: handled implicitly by boundary bonuses in fzf, nucleo, VS Code, Sublime, cmdk and Zed. FuzzyMatch has an explicit acronym pass ("bms" → "Bristol-Myers Squibb").
- Highlight output: fzf positions (`withPos`), nucleo grapheme indices, VS Code `labelMatch` ranges, fuse `indices`, FuzzyMatch `[Range<String.Index>]` and `AttributedString`.

### Inferences
- For a palette with short, human-written titles ("Settings", "New session", French session titles), the important properties are word-boundary and acronym bonuses, a prefix tier above a fuzzy tier (VS Code's threshold design), and some typo tolerance for longer queries. A Smith-Waterman scorer alone will return nothing for "setings". A Bitap scorer alone ranks acronyms poorly. A hybrid (FuzzyMatch ED, or prefix/substring tiers + SW + an edit-distance fallback) covers both.
- Xcode Open Quickly behaves like a boundary-weighted subsequence matcher with camelCase acronyms (e.g. "nsvc" → NSViewController), but I found no primary source on its algorithm (see Gaps).

### Gaps
- Xcode Open Quickly: no published algorithm or source. Its behaviour is anecdotal only.
- I didn't fetch VS Code `filters.ts` (`matchesFuzzy`, `matchesWords`), which the command palette's word filter uses. The scoring constants above come from `fuzzyScorer.ts` (Quick Open files), not from the command palette's filter.
- Superhuman's matcher: no public technical write-up found.

## Ranking: frecency models and how to combine match score with recency and item-type priors

### Takeaway
Shipping palettes mostly keep the match score dominant and use usage history as a tie-breaker or a separate tier, not a blended number. VS Code orders filtered commands by MRU. Zed puts previously used commands first among matches. Raycast reportedly puts frecency 5th, after alias, title and keyword matches. The well-documented frecency formulas are zoxide (bucketed recency multipliers on a hit count, plus global aging) and Firefox (an exponentially decayed sum over sampled visits, 30-day half-life, stored as a projected date so nothing is rescored daily). Firefox's "adaptive input history" (query→chosen-item learning) is the model behind Raycast-style "learned" ranking.

### Cited Findings
**zoxide**
- Each access adds 1 (a new entry starts at 1). At query time the score is multiplied by 4 if last access was within 1 hour, by 2 within 1 day, by 1/2 within 1 week, and by 1/4 when older. — [zoxide wiki: Algorithm](https://github.com/ajeetdsouza/zoxide/wiki/Algorithm)
- Aging: when the total score exceeds `_ZO_MAXAGE`, every score is divided by a factor k chosen so the total becomes about 90% of `_ZO_MAXAGE`, and entries below 1 are deleted. Non-existent entries older than 90 days are pruned lazily. Matching: terms must appear in order, and the last keyword must match the last path component. — [zoxide wiki: Algorithm](https://github.com/ajeetdsouza/zoxide/wiki/Algorithm)
- zoxide: 40.1k stars, v0.10.0 released 2026-07-04. — GitHub API

**Firefox (current frecency, Places)**
- Per visit: `weight × e^(−λ(t_ref − t_visit))` with λ = ln2/30, a 30-day half-life. Total: `(Σ visit scores / samplecount) × visitcount`. Stored as `frecency = t_ref + ln(score)/λ`, the projected day the score decays to 1, so the database never needs daily multiplication. — [Firefox urlbar ranking docs](https://firefox-source-docs.mozilla.org/browser/urlbar/ranking.html)
- Visits fall into buckets: Very High (high plus an "interesting interaction"), High (typed or bookmarked), Medium (link clicks), Low (redirects, reloads). Enough view time or keypresses promotes a visit one bucket. The numeric weights live in prefs (`places.frecency.pages.*`) and aren't listed on the page. — [Firefox urlbar ranking docs](https://firefox-source-docs.mozilla.org/browser/urlbar/ranking.html)
- Adaptive Input History (query→selection learning): `use_count = use_count*0.9 + 1`, which approaches 10. Rank is `ROUND(MAX(use_count) * (1 + (input = :search_string)), 1)`, so an exact repeat of the typed string counts double, and ties break by frecency. Daily decay ×0.975, with entries below 0.975^90 (about 0.1) removed after about 90 days unused. — [Firefox urlbar ranking docs](https://firefox-source-docs.mozilla.org/browser/urlbar/ranking.html)

**VS Code command palette**
- Filtered command picks are sorted as follows: TF-IDF "similar commands" go to the bottom. Otherwise more recently used commands come first (an LRU counter). Used commands beat unused ones. Then come `suggestedCommandIds`. Then non-"Developer" category commands beat Developer ones. Then alphabetical by label. The fuzzy score is used for filtering, not ordering, within these tiers. The list shows "recently used", "similar commands" and "commonly used" separators. — [vscode commandsQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/commandsQuickAccess.ts)
- History is an `LRUCache` persisted in profile storage (`commandPalette.mru.cache`, `commandPalette.mru.counter`). The default length is 50, configurable through `workbench.commandPalette.history`. Recently used items get a remove button. — [vscode commandsQuickAccess.ts](https://github.com/microsoft/vscode/blob/main/src/vs/platform/quickinput/browser/commandsQuickAccess.ts)

**Zed command palette**
- Stores `CommandUsage { last_invoked, invocations }` in a DB. With an empty query, commands are sorted by `Reverse(usage)` (most recent first, then invocation count, through the derived Ord), then by name. After fuzzy matching, matches of previously used commands are moved to the front in usage order, and unused matches keep their fuzzy-score order (stable sort with key usize::MAX). — [zed command_palette.rs](https://github.com/zed-industries/zed/blob/main/crates/command_palette/src/command_palette.rs)

**Raycast**
- The Raycast manual (via search-result summary, not fetched directly) reportedly gives the root search order as: exact alias match, alias prefix match, title fuzzy score, subtitle and keyword matches, then frecency. Root search "learns" which result you pick for a given query or its prefix, and a "Reset Ranking" action clears that. — [Raycast manual: Search Bar](https://manual.raycast.com/search-bar) (unverified quote; via search summary)
- v1.40.0 introduced fuzzy search and ranking that accounts for how often each element is opened and for previously triggered search terms or their prefixes. — [Raycast changelog 1.40.0](https://www.raycast.com/changelog/1-40-0) (via search summary)
- `@raycast/utils` `useFrecencySorting` keeps the input order for never-visited items and exposes `visitItem` and reset. — [raycast/extensions issue #31074](https://github.com/raycast/extensions/issues/31074) (via search summary)

### Inferences
- A practical model for this app: rank by `(tier, adjustedScore, stableKey)`.
  - Tier: exact or alias match > title prefix / word-prefix > fuzzy title > keyword/category/subtitle match > typo-only (edit-distance) match. This follows VS Code's thresholds and Raycast's order.
  - Within a tier: matchScore × (1 + α·frecencyNorm) + a typePrior. Frecency can be zoxide-style buckets or Firefox exponential decay with a half-life of a few days for sessions and longer for settings.
  - Add a per-query learned boost in Firefox adaptive-history style: map typed prefix → chosen item id with a 0.9·x+1 update and daily decay.
  - Empty query: order by frecency/MRU with pins first, as in VS Code, Zed and Raycast.
- Stable order while typing: use a deterministic final tie-break (MRU, then title, then id), keep the selection on the same item id when it is still in the results, and quantize scores so tiny bonus differences don't reshuffle rows on every keystroke. This is my inference. None of the sources documents an "order stability" mechanism beyond deterministic tie-breaks.
- Item-type priors: VS Code demotes the "Developer" category. The equivalent here would be demoting settings and destructive actions below sessions unless the match is strong.

### Gaps
- Alfred's "knowledge"/learning algorithm and Superhuman's command ranking: no primary technical documentation found in this pass.
- Firefox frecency numeric bucket weights and the sample count weren't on the fetched page; they're stored in prefs.
- Raycast's ranking order came through a search-engine summary of the manual. Verify on the manual page before quoting it verbatim.

## Swift libraries: version, platform, tools version, API, maintenance, license (as of 2026-10-14)

### Takeaway
ordo-one/FuzzyMatch is the strongest Swift option for this use case. It is actively maintained (1.4.0 from 2026-06-10, last push 2026-09-23), Apache-2.0, `swift-tools-version: 6.0`, supports macOS 14+ since 1.2.0, and has zero dependencies. It offers both a Damerau-Levenshtein mode (typos plus subsequence plus acronym) and a Smith-Waterman mode (nucleo-compatible), `highlight()` ranges and `attributedHighlight()` (since 1.3.0), with tens of millions of candidates per second. fuse-swift was revived by krisk with a Swift 6 rewrite (2.0.0-rc.1). Ifrit is a fork of the old fuse-swift with a mixed license. The other Swift options are small or stale.

### Cited Findings
**ordo-one/FuzzyMatch**
- 159 stars, Apache-2.0, not archived, last push 2026-09-23, latest release 1.4.0 (2026-06-10). — GitHub API, [repo](https://github.com/ordo-one/FuzzyMatch)
- Release history:
  - 1.0.0: 2026-02-12.
  - 1.0.1: added Latin-1 diacritic stripping.
  - 1.1.0 (2026-03-01): confusable-character normalization.
  - 1.2.0 (2026-03-03): "Support legacy Apple operating systems (macOS 14+, iOS 17+)", which confirms macOS 14 support since 1.2.0.
  - 1.2.2: a library-evolution fix.
  - 1.3.0 (2026-03-13): `attributedHighlight(_:against:applying:)`.
  - 1.3.1/1.3.2: example macOS app.
  - 1.3.3 (2026-05-15): exact-substring ranking fix.
  - 1.4.0: `enableSubsequenceMatching` in `EditDistanceConfig`.
  — [FuzzyMatch releases](https://github.com/ordo-one/FuzzyMatch/releases)
- Package.swift (main): `// swift-tools-version: 6.0`, platforms `.macOS(.v14), .iOS(.v17), .visionOS(.v1), .watchOS(.v10)`, one target, no dependencies. — [Package.swift](https://github.com/ordo-one/FuzzyMatch/blob/main/Package.swift)
- API: `FuzzyMatcher(config:)`, `matcher.score(candidate, against: "q")`, `prepare(_:)` → a prepared query, `makeBuffer()`, `score(_:against:buffer:)` (zero-allocation hot path), `score(utf8:against:buffer:)` (fastest), `topMatches(_:against:limit:)` and `matches(_:against:)`. `ScoredMatch` has `.score` in 0…1 and a `.kind` of exact/prefix/substring/acronym/alignment. `MatchConfig(minScore:algorithm: .editDistance(EditDistanceConfig(maxEditDistance:prefixWeight:substringWeight:wordBoundaryBonus:consecutiveBonus:gapPenalty:firstMatchBonus:)))` or `.smithWaterman(SmithWatermanConfig(...))`. The matcher is `Sendable` and thread-safe, with one buffer per task. — [FuzzyMatch README](https://github.com/ordo-one/FuzzyMatch)
- Highlighting: `highlight(_:against:)` returns coalesced, sorted `[Range<String.Index>]`, including ranges for typo, transposition and diacritic matches ("café" highlighted for "cafe"). `attributedHighlight` returns a styled `AttributedString` (it needs Foundation). Cost is about 1.2 µs (ED) or 0.8 µs (SW) per call, so about 24 µs for 20 visible rows. The README advises calling it only for visible rows. — [FuzzyMatch README](https://github.com/ordo-one/FuzzyMatch)

**krisk/fuse-swift**
- 950 stars, Apache-2.0, last push 2026-05-22. Tags: 2.0.0-rc.1, 1.4.0, 1.3.1. There is no GitHub "release" object, so the latest-release API returns 404. — GitHub API
- Now `swift-tools-version: 6.0`, `swiftLanguageModes: [.v6]`, iOS 15 / macOS 12 / tvOS 15 / watchOS 8 / visionOS 1 / Linux. It calls itself "the official Swift port of fuse.js" with "byte-equivalent results", and 2.0.0-rc.1 has 253 unit tests plus a parity check against fuse-js 7.4.0-beta.5. It builds clean under strict concurrency. API: `Fuse.Search<T>(items, options: FuseOptions(...keys: [FuseKey(... keyPath:, weight:)]))`, `.search(q, limit:)`, and match `indices` as UTF-16 `FuseRange`. — [fuse-swift README](https://github.com/krisk/fuse-swift); [Package.swift](https://github.com/krisk/fuse-swift/blob/main/Package.swift)
- Conflict: Ifrit's README says "Fuze-Swift is dead" and that its async API returned wrong indexes. That describes the old 1.x line, before krisk's 2026 rewrite. — [Ifrit README](https://github.com/ukushu/Ifrit)

**ukushu/Ifrit**
- 99 stars, last push 2026-03-20, v4.0.0 released 2025-12-30. GitHub reports MIT, but the README warns "NOT ALL CODE IS MIT-LICENSED": the FuzzyFind portion is Apache-2.0. `swift-tools-version: 5.9`, macOS 10.15+ / iOS 13+, dynamic and static library products. It offers Fuse (Bitap) plus Levenshtein search, async/await, and AttributedString highlighting, and the README itself lists "Not tested in production" as a disadvantage. — GitHub API; [Ifrit README](https://github.com/ukushu/Ifrit); [Ifrit Package.swift](https://github.com/ukushu/Ifrit/blob/main/Package.swift)

**Others**
- truizlop/FuzzyFind: 153 stars, last push 2023-08-28, license NOASSERTION. Ifrit's README says this code is Apache-2.0. — GitHub API
- yichizhang/SwiftyStringScore: 153 stars, MIT, last push 2020-08-22 (stale), a 0…1 string-score port. — GitHub API
- CleanCocoa/FloatingFilter: 143 stars, MIT, last push 2025-01-11. A Spotlight-like floating filter window for macOS. — GitHub API, [repo](https://github.com/CleanCocoa/FloatingFilter)
- Swift fzf ports are negligible. ralfebert/SwiftFzfAlgorithm (0 stars, MIT, a port of FuzzyMatchV1, pushed 2026-06-30) and ainame/fltr (3 stars, an fzf-inspired CLI) are the only hits. — GitHub search API
- objc.io fuzzy search: not checked in this pass (see Gaps).

**Apple built-ins**
- FuzzyMatch's benchmark measured Foundation baselines on 197 queries × 272K candidates: `lowercased().contains()` 18,582 ms, `localizedCaseInsensitiveContains` 76,913 ms, and `range(of:options:[.caseInsensitive,.diacriticInsensitive])` 111,825 ms. FuzzyMatch ED is 11.5x faster than even the `lowercased().contains()` baseline. — [FuzzyMatch COMPARISON.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/COMPARISON.md)

### Inferences
- For a few thousand items, FuzzyMatch with the default ED config (or SW plus a typo fallback) is a near drop-in choice:
  - Swift 6 tools version and macOS 14 floor.
  - The match `kind` maps directly to the tier system above.
  - `highlight` ranges for visible rows.
  - Run it synchronously on each keystroke.
  - Keep the frecency/tier logic in the app, since the library only gives a 0…1 match score.
- fuse-swift 2.x fits multi-field weighted search (title 0.7, category 0.3) but scores acronyms poorly and is still at a release candidate.
- Apple's `localizedStandardContains` / `range(of:options:)` do substring matching only. They're fine as a substring tier but aren't fuzzy, and they're the slowest option in the benchmark.
- Core Spotlight (CSSearchableIndex / CSSearchQuery) and Search Kit are full-text indexes built for documents and system-wide search. For a few thousand in-memory titles they add persistence and async-index complexity with no ranking benefit. This is inference: I didn't fetch their docs in this pass.

### Gaps
- I didn't check the Swift Package Index pages directly. Compatibility facts come from Package.swift and GitHub.
- objc.io's fuzzy-search article and code (Swift Talk) weren't fetched, so I have no version or license data.
- I didn't fetch Apple docs for `localizedStandardContains`, `folding(options:locale:)`, Search Kit or Core Spotlight in-app search. Their documented semantics (case- and diacritic-insensitive, locale-aware) are from memory, not from this research pass.

## Diacritics, case folding and French/AZERTY input

### Takeaway
All the leading matchers fold diacritics so that unaccented input matches accented text (fzf's normalize table, nucleo's Unicode handling, FuzzyMatch's Latin-1 and combining-mark stripping). FuzzyMatch folds the Latin-1 block (é è ê ë à â ç ù û ô î ï) and strips combining marks, which covers almost all French accents. The ligatures œ/æ and Latin Extended-A letters are not folded, so the app should pre-normalize candidate strings itself, for example with `folding(options: [.diacriticInsensitive, .caseInsensitive], locale:)` plus an œ→oe, æ→ae map, and keep a mapping back to the original string for highlighting.

### Cited Findings
- FuzzyMatch case-folds ASCII, Latin-1 Supplement (U+00C0–U+00FF), Greek and basic Cyrillic. Latin-1 diacritics fold to ASCII (é→e). Combining marks U+0300–U+036F are stripped, so precomposed and decomposed "café" both match "cafe". — [FuzzyMatch DAMERAU_LEVENSHTEIN.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/DAMERAU_LEVENSHTEIN.md)
- FuzzyMatch also normalizes confusables: curly apostrophes, backtick and ´ go to `'`; curly quotes go to `"`; en/em dashes and minus go to `-`; NBSP goes to space. French typography uses ’ and NBSP before `:` `;` `?` `!`, so this is useful. — [FuzzyMatch DAMERAU_LEVENSHTEIN.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/DAMERAU_LEVENSHTEIN.md)
- What FuzzyMatch doesn't support: scripts beyond these blocks aren't case-folded, and edit distance and trigrams are byte-level, so some substitutions cost 2 edits. — [FuzzyMatch DAMERAU_LEVENSHTEIN.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/DAMERAU_LEVENSHTEIN.md)
- fzf maps Latin letters with diacritics (including Latin Extended ranges such as U+0103 and U+01CE) to base letters through `normalize.go`. — [fzf normalize.go](https://github.com/junegunn/fzf/blob/master/src/algo/normalize.go)
- nucleo handles non-ASCII text and grapheme clusters better than skim, whose case insensitivity is ASCII-only. — [nucleo README](https://github.com/helix-editor/nucleo)
- Smart-case: Zed severely penalizes case mismatch only under smart_case. cmdk applies a tiny case-mismatch penalty (×0.9999). VS Code gives +1 for same case. — [zed matcher.rs](https://github.com/zed-industries/zed/blob/main/crates/fuzzy/src/matcher.rs); [cmdk command-score.ts](https://github.com/pacocoursey/cmdk/blob/main/cmdk/src/command-score.ts); [vscode fuzzyScorer.ts](https://github.com/microsoft/vscode/blob/main/src/vs/base/common/fuzzyScorer.ts)

### Inferences
- AZERTY users often type "e" for é/è, especially in a quick palette, and may type "oe" for "œ". Fold diacritics on both sides, with the query matching text in either direction (FuzzyMatch normalizes query and candidate identically). Handle ligatures in a pre-pass, because Latin-1 folding doesn't cover U+0153 œ (it is in Latin Extended-A). This is inferred from the documented Latin-1 range and should be tested.
- Highlighting after pre-normalization: if the app folds strings itself, it must map ranges in the folded string back to the original. Passing the original string to FuzzyMatch avoids this for Latin-1, because `highlight` returns ranges in the original string's indices.

### Gaps
- I didn't test whether FuzzyMatch matches "oeuvre" against "œuvre". It is likely not, given the Latin-1 scope.
- Whether `String.folding(.diacriticInsensitive)` expands œ→oe wasn't verified. Ligatures generally aren't diacritics.

## Practical performance for about 1–10K items per keystroke

### Takeaway
At palette scale, any decent matcher takes well under a millisecond per keystroke. FuzzyMatch runs about 33M candidates/s (ED) and 66M/s (SW) on M4 Max, so 10K items take roughly 0.15–0.3 ms single-threaded, plus about 24 µs to highlight 20 rows. No index, threading or incremental filtering is needed. Even naive Foundation `contains` is fast enough for 10K items, but it gives poor results.

### Cited Findings
- FuzzyMatch on M4 Max: query preparation about 2.2 µs. 1M candidates in about 36 ms single-threaded, about 4.8 ms with 8 workers, about 3.8 ms with 16. On the 272K corpus, about 33M candidates/s (ED) and about 66M/s (SW), against about 97M/s for nucleo in Rust and about 3M/s for the naive `lowercased().contains()`. — [FuzzyMatch README](https://github.com/ordo-one/FuzzyMatch)
- Highlighting is about 1.2 µs (ED) or 0.8 µs (SW) per call on 8–30-character candidates. — [FuzzyMatch README](https://github.com/ordo-one/FuzzyMatch)
- Use the zero-allocation path (`prepare` + `makeBuffer` + `score(_:against:buffer:)`), since the convenience methods allocate a buffer per call. `score(utf8:...)` is 50–100% faster on Swift 6.0, because `String.withUTF8` isn't inlinable. — [FuzzyMatch README](https://github.com/ordo-one/FuzzyMatch)
- Sublime-style C++: 13K filenames in about 5 ms on a 2013 i5. In JS it is about 25x slower. — [Forrest Smith blog](https://www.forrestthewoods.com/blog/reverse_engineering_sublime_texts_fuzzy_match/)
- nucleo: about 2–10 ms per pattern over the entire Linux-kernel file list (tens of thousands of paths). — [nucleo README](https://github.com/helix-editor/nucleo)
- The FuzzyMatch benchmark describes Ifrit as "significantly slower than other matchers on large corpora". I found no per-item number for it. — [FuzzyMatch COMPARISON.md](https://github.com/ordo-one/FuzzyMatch/blob/main/Documentation/COMPARISON.md)

### Inferences
- Per-keystroke latency for 5K items: matching about 0.1–0.2 ms (FuzzyMatch), frecency lookup and sort about 0.1 ms, highlighting the visible rows about 0.03 ms. The real cost will be in SwiftUI/AppKit list diffing and re-rendering, not in matching. Keep row identity stable (by id) to limit view churn.
- Precompute and cache folded and lowercased candidate strings, and the frecency score, once per data change rather than on every keystroke.

### Gaps
- No independent (non-author) benchmarks of FuzzyMatch, fuse-swift 2.x or Ifrit on Apple Silicon were found.
- fuse-swift 2.0 performance numbers weren't published in the README.
