# Performance

How Fjord stays fast, what was measured, and the rules a change has to keep. Written after the October 2026 performance
pass (branch `perf/snappy`); update the numbers when they move.

## Budgets

| What the user does | Budget | How it's measured |
| --- | --- | --- |
| Close the window (Esc, shortcut) | first moving frame ≤ 1 frame after the request (`Close to first flush` ≤ 16 ms p95) | `scripts/morph-timings.sh` |
| Open the window | first moving frame ≤ 1 frame (`Open to first flush`); window live when the spring settles | same |
| Any capture | never on the critical path of an open, a close, or input | `Capture*` signposts must not sit inside `Open`/`Close` before the handoff |
| Typing (composer, rule editor) | no store write, sort or full relayout per keystroke | code review; `RouterMentionField` coordinator caches |
| Idle, window closed | no repeating main-thread timers; no 1 Hz clock | `sample <pid> 3` should show an idle main thread |
| Idle, window open, nothing changing | main thread near idle; no layout passes | `sample <pid> 3` |

## Measuring

- **`scripts/morph-timings.sh`**: plays `--demo busy --motion-script "open,close x10" --quit-after` on a release build and prints
  every `com.amontlabs.fjord` signpost interval's count, p50, p95 and max from the unified log. No Instruments, nothing kept on
  disk. `--bin` compares another build (e.g. `main` built in a `git archive` copy under `/tmp`); `--json` writes the summary.
  It takes the screen for ~1.5 s per step.
- **Signposts** (subsystem `com.amontlabs.fjord`, category `morph`): `Open`, `Close` (whole intervals), `Open to first flush`,
  `Close to first flush`, `Bring in`, `Capture` (split into `Capture bitmap`, `Capture draw`, `Capture image`, `Capture flag
  on/off`, `Unblend sidebar`), `Glance drawn`, `Install picture`, `Handoff`, `Overlay going`; category `latency`: `Bar away`.
- **The installed app logs these too** (they are persisted): `log show --last 1h --signpost --style compact --predicate
  'subsystem == "com.amontlabs.fjord"'` gives real-world numbers with real data, without running anything.
- **Idle CPU**: `sample <pid> 3 -file /tmp/fjord-sample.txt` on the running app; look at the main thread's share and at the
  `fjord.claude` queue.
- `scripts/motion-trace.sh` (xctrace, hitches) exists for frame-level work; guard the disk (Instruments' scratch in
  `$TMPDIR` once reached ~58 GB) and keep recordings short.
- Demo data at the default window size understates real costs: the same capture was 66 ms on demo data and 520 ms live
  (1617×1188 pt window, real data, heavy Router canvas). Design for the expensive case.

## What made open and close slow (October 2026)

Live, before: open 807–865 ms from request to overlay gone, close ~0.5 s frozen then a 0.46 s shrink.

1. **One synchronous full-window capture on every open and every close** — `cacheDisplay` of the theme frame on the main
   thread. Its cost is SwiftUI's display list redrawn on the CPU in the hosting view's own layer: it scales with content and
   pixel count, not with layer count or effects. 1x is ~3.5× cheaper than 2x. `CALayer.render(in:)` costs the same.
   ScreenCaptureKit needs Screen Recording permission and `CGWindowListCreateImage` is unavailable in the macOS 26 SDK, so
   there is no cheap GPU path to the window's own pixels.
2. **The close waited a display refresh** (with a 100 ms fallback) before moving.
3. **Content re-attach** on each open re-ran every `onAppear`/`.task`/`onChange(initial:)`, and replayed as animations every
   change made while the window was closed.
4. **Work landing mid-morph**: a GitHub sync started one turn after opening, a 20k-folder code scan on app activation, the
   Claude/Router feed applying every ~0.5 s, the inbox memo evaluated inside a view body.
5. **Whole-tree invalidation**: the bar and window roots read whole `router`/`agents` structs and rebuilt their environment
   closures, so every Claude read redrew everything.

After (release build, demo `busy`, `morph-timings "open,close x10"`, default size and 1617×1188):

| | main | perf/snappy |
| --- | --- | --- |
| Open: request → window live | ~391 ms (overlay gone ~495) | p50 308–320, p95 321 |
| Close: request → done | ~460 ms after a 73–100 ms capture (520 live) | p50 314–319, p95 325 |
| Close: request → first moving frame | capture + up to 100 ms refresh wait | p50 7–9, p95 10–14 |
| Captures inside an open or a close | 1 each | 0 |

## The design now

### First-open AutoFill stall (October 13, 2026)

The reported release `open,close x10` run had Open p50/p95 **311/659 ms**, Handoff **37/378 ms**, and a first handoff of
**378 ms** despite a 6 ms `Warm window`. A fresh unmodified run was already fast (Open **309/322**, Handoff **32/41**,
first handoff **24 ms**): the stall is intermittent, not a fixed cost of revealing the window.

Temporary spans around reveal's alpha and ordering, the transaction commit and flush, and display-link creation and
registration measured at most 1 ms. Repeated fresh launches reproduced a **419 ms Handoff / 692 ms Open**. A two-second
`sample` caught the main thread in `SPCompletionListRemoteViewController.resizeRemoteWindow` →
`SPSafariPlatformSupport._updateWindowVisibility` → `SLSConnectionSynchronizeSLSCATransaction` →
`_SLSTransactionWaitSource`, waiting for the WindowServer to order AutoFill's remote completion window. Other launches
stalled before Handoff (Open 673–703 ms). The two-refresh fallback cannot run while this callback blocks the main thread.

Fjord has search, editor and composer fields, but no security-code entry. Apple's
[`NSAutoFillRequiresTextContentTypeForOneTimeCodeOnMac`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsautofillrequirestextcontenttypeforonetimecodeonmac)
opts these fields out of macOS 26's unsolicited security-code AutoFill; an explicitly marked `oneTimeCode` field can still
opt in. `Resources/AppInfo.plist` supplies this policy both as the SwiftPM executable's embedded `__TEXT,__info_plist`
and in the packaged app's Info.plist. No window is ordered in, no activation occurs, and no preparation work is added.
The removed `NSAutoFillHeuristicControllerEnabled` default is unsuitable on macOS 26.2 and later
([Chromium's current implementation](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/content/app/mac_init.mm)).

After, without temporary instrumentation, release `open,close x10`: Open **308/323 ms**, Handoff **28/41 ms**, first Open
**308 ms**, first Handoff **25 ms**; no SafariPlatformSupport/AutoFill connection appeared in that process's log. A regression
test reads the built executable's metadata through CoreFoundation, and the bundle metadata merge preserves its identity
and accessory policy. Six more fresh launches (`open,close x1`) had first Open **306–317 ms** and first Handoff **22–36 ms**.

### Window and motion

- **No capture inside an open or a close, ever.** Only the idle keeper captures. It runs while the window is visible, key
  and front; captures only once two looks agree (content at rest), input has been idle for max(0.5 s, 3× the capture's cost),
  no text is being composed, and the content changed. "Changed" is a quarter-scale glance plus `Marks` (window input, asks,
  and `Store.shownRevision`, which every store write that the window draws bumps). Costs are kept per size, scale and page
  (`CaptureCosts`, the last minute's maximum); a capture estimated over 30 ms is skipped, and on Retina the keeper keeps a
  half-scale ("soft") picture.
- **Close** starts in the request's turn: on the kept picture when it is fresh, else the live window fades out over 0.1 s
  above the overlay while the glass shrinks. Focus goes back to the previous app at once.
- **Open** starts from the kept picture (or the bare surface) and, at the handoff, cuts to the real window when the picture
  is exact (rechecked at the cut, `stillExact`) or fades over 0.12 s. The window is laid out and drawn in the turn it is
  brought in, so its first draw never lands on the handoff. It takes clicks once revealed.
- **Springs**: open and close are critically damped at 0.30 s (glass and opaque alike); they are now the floor.
- **`MotionGate`** (`Sources/FjordComputer/MotionGate.swift`): the morph calls `began`/`ended`; main-thread work that can wait
  goes through `whenStill { }` / `await still()`. Released work runs one item per run-loop turn. A missed `ended` lets work go
  after 1.5 s. The sync, the Claude feed, Jev and brief results, `reportOpen`, service start-up and post-open scans use it.
  New work that lands on main and can wait half a second **must** use it.
- **`WindowArrival`** (`Motion.swift`): the window's first update after its content is re-attached is unanimated, so changes
  made while closed don't replay as springs during the handoff.
- **Content is detached on close and re-attached on open** (re-attach measured ~10 ms); keeping it attached would re-render a
  hidden window on every sync.
- **Launch**: `state.json` is decoded off main from `main.swift`, fonts register from a per-archive cache, the bar draws
  before services start, services start after the first frame (and after any first-launch morph).
- **Stored, narrow observables**: `Store.routerOn`/`triageOn` are stored Bools; `routerZones`/`routerCounts` are memoized
  (`RouterMemo`); cards are `Equatable`; selection and highlight are observed per row (`isSelected`, `isMarked`); session rows
  are per-session boxes refreshed only for sessions whose inputs changed.
- **Off main**: GraphQL → `Thing`, CI folding, workflow mapping, code-folder scans (`.utility`), task-folder listings (cached by
  inode/ctime, stat only the live sessions), `ClaudeMark`, `SessionIcons`, Settings' login-item and Accessibility reads, the
  Accessibility trust check behind modifier taps, the mouse-button event tap (its own thread and run loop).

## Rules for new code

1. Nothing synchronous and expensive between a user's action and the first frame that answers it. If it must happen, do it
   at idle beforehand, or after the motion through `MotionGate`.
2. Never read a whole `Store` struct (`router`, `agents`, `things`) in a body that doesn't need all of it. Read a narrow
   stored or memoized value; add one if needed.
3. No sorting, filtering, regex, date formatting or attributed-string building in a `body` without a memo keyed on its inputs
   (and check that the key covers *every* input — stale memos were the most common review finding).
4. Don't create closures for the environment in a root body; build them once.
5. Timers: tolerance always; stop them when their window isn't visible; prefer one shared clock to one per row.
6. Files and processes: never on main. Use `OffMain.run(qos:)` with `.utility` for background scans.
7. Debounced writes must be flushed on disappear, on quit (`PendingEdits`), before undo/redo, and must address their target by
   id, not by index.
8. Anything that holds work for a motion must also handle cancellation after the wait and re-check its fences.
9. Measure before and after with `scripts/morph-timings.sh`, and paste the numbers in the commit message.

## Known open items

- The `router-canvas` branch (not on `main`) re-lays out the canvas continuously while the window is open and idle (30–90% of
  a core in a live sample: `CanvasBoard.place`, `CanvasFolderStack.rows`). Fix it there before it merges.
- The keeper's 30 ms budget means Retina machines keep half-scale pictures, so most openings fade (0.12 s) into the live
  window instead of cutting. A cheaper exact capture path would allow cuts.
- Whether `NSGlassEffectView`'s `cornerRadius` through `animator()` is driven on the main thread is unverified; if it is, the
  3–11 ms glance at the handoff could cost a corner frame.
