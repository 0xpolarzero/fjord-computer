# Fjord Computer on macOS 26: Liquid Glass, motion and latency

A plan, not a record: nothing here is built yet. Written against `main` at `1a30029`, macOS 26.5 and the Xcode 26.5 SDK
(26.5, 25F70). Every API named was checked in that SDK (§11). Anything not verified is marked **unverified** and has a
spike that settles it before anything depends on it. Revision 5, after four Fable reviews (the fourth: ready) (§11 lists what changed).

## 1. Goal and the bar it has to clear

Make Fjord Computer look like a first-class macOS 26 app (Liquid Glass where Apple puts it, the new shapes, motion that
feels physical) while it stays what it is today: **zero CPU at rest, motion that starts on the next frame, nothing that
pops**. A glass look that costs idle CPU, drops frames or adds latency doesn't ship.

"Done" means:

1. The bar on the screen edge and its panels are Regular glass over the desktop, like the Dock, the panel growing out of
   the bar as one shape — *if* the spikes show glass behaves in a never-key panel (§4, S1–S3). Otherwise they keep
   today's look and everything else still ships.
2. The window follows the macOS 26 model: an inset glass sidebar (a glass rail when folded), glass controls floating
   over content that scrolls under them with the system's scroll edge effect, corners concentric with the window's.
3. Opening the window from the bar is one continuous motion that starts as the bar's glass.
4. Every budget in §7 is met, measured by scripts that stay in the repo.
5. Reduce Transparency, Increase Contrast, Reduce Motion and the system's "Liquid Glass look" setting all behave, in light
   and dark; macOS 14/15 look exactly as today.

Out of scope: features; content design (rows, cards, transcript, Settings rows stay as they are); layout changes other
than the three the glass model needs, each named and budgeted: the inset sidebar (§5.2), pages scrolling under the top
bar (§5.3), the Router transcript scrolling under its composer (§5.4).

## 2. Ground rules

- **Glass is the navigation and control layer only**: bar, panels, sidebar, floating controls. Never rows, cards, lists,
  Settings sections or the transcript (HIG Materials: "Don't use Liquid Glass in the content layer"; WWDC25 219).
- **Glass only where something moves under it.** Glass over a flat, still colour reads as a grey plate: it earns its
  place over the desktop (the bar) or over content that scrolls under it (top bar controls, the composer). §5.2 says
  what the sidebar looks like as a consequence.
- **Regular, never Clear** (Clear needs a dimming layer; Silo shipped Clear and moved to Regular because desktop text
  competed with its navigation).
- **No tint, no painted backdrop** (Silo removed both). Claude's blue stays the accent; fonte stays out of the UI.
- **No glass on glass**: on a glass surface, use fills and the label styles, not more glass.
- **Content is opaque** (`CDS.Surface.s1`).
- **The material's own accessibility is the system's**; the app owns everything it draws over or around it (§6).
- **This codebase's performance rules hold** (its comments and commits): nothing loops in SwiftUI (Core Animation moves
  it, 42a7a5d); nothing watched at rest (no global mouse monitor while the bar is at rest, `HubController.swift:276`;
  one runs only while the pointer is on the hub, `:299`); the motion starts before anything is built
  (`AppTransition.swift:5-19`); build at idle, out of sight; let go under memory pressure; shadows from shapes, never a
  blurred composite (`HubView.swift:204`).
- **macOS 14/15 keep today's layout and look**, behind `if #available(macOS 26, *)`.

## 3. What exists today (the parts this touches)

From the code survey (`Sources/FjordComputer/`):

- **No glass or vibrancy anywhere.** Reduce Transparency is never read; Increase Contrast once (`RouterComposer.swift:27`,
  ring at `:142`).
- **The bar**: a `PillPanel` (`Windows.swift:58`; `FloatingPanel` above it: borderless, non-activating, never key,
  `.floating`, clear, non-opaque, `.canJoinAllSpaces/.fullScreenAuxiliary/.stationary`), spanning the screen edge
  (`HubController.swift:230`). The bar's shape: radius 20, screen-side corners square (`HubPeek.swift:177`), filled
  `Theme.bg`, ringed `CDS.border`, live `.shadow`s (near at rest, far with a panel, `HubView.swift:208`). Panels 400 or
  232 wide, radius 16 (`HubPeek.swift:204`), same fill, joined to the bar by an opaque seam patch (`:166`), opening after
  a 100 ms dwell (`HubView.swift:87`) with opacity + 6pt offset (`HubPeek.swift:113-117`) over 0.14 s
  (`.motion(Theme.Motion.fade)`, `HubView.swift:216`). Pieces assuming an opaque bar: the badge ring
  (`HubComponents.swift:768`), the seam, the shadow casters (`HubView.swift:211`, `HubPeek.swift:139`).
- **The window**: one `NSWindow`, transparent titlebar, no toolbar, `NSHostingController` root
  (`AppWindow.swift:534-569`). Sidebar and 48pt top row are SwiftUI: an `HStack` of the sidebar (laid out at its full
  240 always, `AppSidebar.swift:167`, inside a frame of 52 or 240, `AppWindow.swift:699-704`) and the page; the sidebar's
  ground runs across the top row with a 0.5pt rule. **Each page draws its own 48pt title row** (`AppPage`,
  `AppContent.swift:161-178`, used by the inbox, Done, Settings and Categories; the Router's `topBar`,
  `RouterCode.swift:50`), and each page's scroll view starts below it (`AppContent.swift:51`, `SettingsView.swift:27`,
  `CategoriesView.swift:149`, the Router's history `RouterPage.swift:482`, its Now column `:1223`). Traffic lights moved
  by hand to the 48pt line (`TrafficLights.place`, `AppWindow.swift:625`, skipped in full screen, reapplied at `:587-590`).
  Back/forward/sidebar toggle: 26pt ghost buttons (`AppNavButtons`, `:776`). The fold: the frame's width springs
  (`.spring(0.35, 0.15)`, `AppSidebar.swift:10-35`), so the page relayouts every frame of it.
- **The Router**: `RouterMain` is a `VStack` of top bar, setup notice, `RouterPageView`, then the composer *below* it
  (`RouterCode.swift:40-47`); the history pins to the bottom (`defaultScrollAnchor(.bottom)`, `RouterPage.swift:655`).
- **The morph** (`AppTransition.swift`): pictures (`cacheDisplay` of the window's theme frame, `:105`, and of the bar's
  hosting view, `HubController.swift:412`) moved by `CASpringAnimation`s (600/49 open, 400/40 close, `:249-250`) in a
  borderless overlay whose level is above the window and the bar (`:302`), with an opaque `s1` container (`:319`) and a
  synthetic shadow; the real window revealed two display refreshes before the spring settles (`:455`). The opening's
  first frame uses the picture kept from the last close (~15 MB, `AppWindow.swift:116`) or the window's bare surface,
  with nothing captured (`AppTransition.swift:12-15`).
- **Tooling**: `scripts/idle-cpu.sh` (app < 0.1% of a core at rest; WindowServer's cumulative CPU printed "(all
  clients)", not judged); `--lifecycle`; the morph signposts (the app's only `OSSignposter`); `BarLatencyTests`
  (ordering only); `RouterMotionTests` (Reduce Motion scan, `Router*.swift` only); window and playground shots (all
  `cacheDisplay`).

## 4. Spikes: the unknowns, settled first

Throwaway experiments (a scratch target or `FJORD_GLASS_SPIKE`, never merged as is) on this Mac (26.5), results written
into §11 before anything depends on them. They need the live app and LCU screenshots, so they run in as few sessions as
possible, each with the owner's OK. Order: S1–S3 (the bar), then S4–S6 (window, morph).

**Which glass path the bar uses** is fixed before S1: SwiftUI `.glassEffect` inside the existing `NSHostingView`. It
keeps hit-testing exactly as today (an `NSGlassEffectView` through `NSViewRepresentable` would be a real `NSView` taking
mouse events under `HubPiece` and `.onHover`). S1–S2 still try the AppKit view as a comparison, but only the SwiftUI
path can ship without reworking hit-testing.

| # | Question | Why | How | If bad |
|---|---|---|---|---|
| S1 | In a **never-key, non-activating** `PillPanel`, does glass look active or permanently subdued? No report exists for `NSGlassEffectView`/`.glassEffect`; `NSVisualEffectView` is known to go inactive in non-key panels (forum 818901, unanswered) and has `state = .active` to override it; `NSGlassEffectView` has no such property (`NSGlassEffectView.h`). | The bar is never key; a subdued bar is worse than today's crisp one. | The bar's shape with SwiftUI glass (and the AppKit view, for comparison) in a `PillPanel` over a busy desktop, next to the same view in a key window; LCU screenshots; same for a panel while the pointer is on it (S1b). | Bar (S1) and/or panels (S1b) keep today's look. No private API. |
| S2 | Does the backdrop **keep updating**: windows moving under the bar, wallpaper change, a video, the bar over a full-screen app's Space, under Stage Manager? The 26.4 fix (166828089) is in the *SwiftUI* release notes; the AppKit report (forum 810314, Dock-level, non-movable, unanswered) is unconfirmed either way. | A stale backdrop is a bug, not a look. | Same harness; results recorded per path (SwiftUI, AppKit). | Same as S1. |
| S3 | **What does a glass bar cost at rest?** CPU of the app and of WindowServer, WindowServer GPU, WindowServer memory. | Rule 1. | §7's method: pointer parked, display static, `--demo busy` (no working ring), `FJORD_GLASS=0/1` interleaved, ≥ 5 runs each, medians. | Glass on panels only (they're up only while hovered), or none on the bar. |
| S4 | **What do captures of glass give?** `cacheDisplay`, `CALayer.render(in:)`: transparent, the window's background colour, or black, and for which path. **And is the capture flag invisible?** (§5.6: the in-turn sequence never presents a frame with cleared or stand-in chrome.) | The morph's pictures contain glass and what's drawn over it (§5.6). | A scratch key window (or S6's spike `AppRootView`; S4 doesn't wait for Phase 3) with a glass region: snapshot each way, read the pixels; then 20 opens and closes with the flag, recorded, checked frame by frame, plus the Core Animation instrument's commits. | Flag not invisible → M2. |
| S5 | In the **morph's overlay window**, can a glass shape spring from the bar's cell to the window's frame and corner radius at the display's rate with the app drawing nothing per frame? Tried in order: (a) `CASpringAnimation` on an `NSGlassEffectView`'s layer `bounds`/`position`/`cornerRadius` (`cornerRadius` is a view property, not documented animatable: the expected failure); (b) `animator()` under `NSAnimationContext`; (c) SwiftUI `.glassEffect(in:)` with an animatable shape in an `NSHostingView` in the overlay. | Decides the morph (§5.6). | Animation Hitches + Time Profiler (app main thread) during 20 moves; screenshots mid-move. | §5.6's fallback. |
| S6 | The window on glass: (1) SwiftUI `.glassEffect` in our `NSHostingController` window renders, including when the window isn't key (the app is an accessory app; its window is often not key); (2) **W1 over a flat page** (screenshot: does the inset sidebar read as glass or as a plate?); (3) `safeAreaBar(edge: .top)` + `scrollEdgeEffectStyle` with each page's `ScrollView` directly under the bar, including the Router's history (bottom-anchored, `HistoryScrollWatch`) and its sticky zone header with `.hard`; (4) are label styles (`.primary`/`.secondary`) vibrant inside `.glassEffect`, or should fixed `CDS.Text` colours stay? (three wallpapers, side by side); (5) does `ConcentricRectangle` resolve against the window without an explicit `containerShape`; (6) full screen (radius 0), a 60 Hz external display, the window straddling two displays; (7) a live Reduce Transparency toggle: no frame with neither material, no animation of the switch; (8) the cost of one
`GlassEffectContainer` around the whole root (sidebar + nav capsule) against two small ones (one each), GPU and CPU,
picking the cheaper. | Decides the window (§5.2–§5.4). | A spike branch of `AppRootView` and two pages; SwiftUI and Time Profiler traces; LCU screenshots. | W2 (§5.2). |

## 5. Design

### 5.1 One switch for the material: `Chrome`

A small `@Observable @MainActor final class Chrome` (new `Chrome.swift`) decides how the navigation layer draws:

- `mode`: `.glass` on macOS 26+ unless Reduce Transparency or Increase Contrast is on, or `FJORD_GLASS=0`; else
  `.opaque`. `FJORD_GLASS=0|1` pins it (A/B runs, shots), like `FJORD_THEME`.
- Reads `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` / `…IncreaseContrast` and observes
  `accessibilityDisplayOptionsDidChangeNotification` on the **workspace's** notification center (the overlay window and
  other AppKit pieces need the value outside SwiftUI's environment; one source serves both). A change applies inside a
  `Transaction(animation: nil)`: the switch never animates and never leaves a frame without a material.
- **What `.opaque` means**: on macOS 26, *the macOS 26 geometry with opaque fills* (the inset sidebar filled
  `CDS.Surface.sidebar`, the top bar's controls on a `CDS.Surface.s2` capsule, the composer on `s3`, the bar and panels
  on `Theme.bg` as today). So toggling an accessibility setting never reflows the window, and shots taken with
  `FJORD_GLASS=0` guard the real geometry. On macOS 14/15, today's layout and look, untouched.
- One instance, put in the environment of each root: `HubRoot` (`HubController.swift:203`), `AppRootView` (which also
  holds `OnboardingView`, `AppWindow.swift:726-731`), the playground, `AppWindowShots` (`:190`); the overlay reads it
  directly. Only chrome views read it, so a change redraws only chrome.

### 5.2 The window: inset sidebar (W1)

- **Sidebar**: an inset panel, 8pt from the window's top, leading and bottom edges, corners concentric with the window's
  (window radius − 8, via `ConcentricRectangle` / `.rect(corners: .concentric(minimum: .fixed(6)))` under a `containerShape` set
  to the window's runtime radius; minimum 6 so full screen, radius 0, still has rounded inner corners). Regular glass via
  `.glassEffect(.regular, in:)`.
- **What it will look like, plainly**: the sidebar sits over the window's own flat `s1`, so its glass has nothing to
  refract but its edge; it reads as a slightly lighter, edge-lit panel, as Finder's and Mail's sidebars do on macOS 26.
  That's the native look, and it's why the sidebar is glass at all: consistency with the system, and the fold's morph.
  The places where the material visibly works are the bar (desktop), the top bar's controls and the composer (content
  scrolling under them). S6(2) shows it on a flat page before Phase 3 is built; if it reads as a dull plate, the sidebar
  takes the opaque fill and keeps the inset shape (no glass) while the controls stay glass.
- **Rail**: folding shrinks the same shape to the rail's width (52 + insets); a `glassEffectID` morphs it.
- **Fold without pops or per-frame waste**, in two steps:
  1. *Measure first* (Phase 0): main-thread time per frame and layout passes of the page subtree during 20 folds, today
     (Time Profiler + SwiftUI template). If every page stays under 2 ms per frame on the main thread (a quarter of a
     120 Hz frame), the page's leading inset keeps animating with the glass on `glass`: simplest, correct, no pop.
  2. *If any page is over*, layout once: the page is laid out at its final inset at once and **offset** by the
     remaining distance (`.offset(x:)` on the same spring, so it lands with the glass), clipped, with an `s1` strip
     covering the gap it uncovers; nothing jumps because the offset starts at the full delta. The nav capsule's leading
     position (today `headerInset`, `AppWindow.swift:696`, which follows the width only because layout animates) rides
     the same offset, so it doesn't jump either.
- **Window**: stays opaque (the sidebar samples the window's own content). Whether the sidebar and the nav capsule share
  one `GlassEffectContainer` (wrapping the whole root) or get one each is decided by S6(8)'s numbers. The system shadow and inactive appearance
  stay the system's.
- **Window radius**: read at runtime as today (`AppTransition.cornerRadius(of:)`, `:91`: the private `_cornerRadius`
  via KVC, then 16), published as the root's `containerShape`, and read again and republished on
  `windowDidEnterFullScreen` / `windowDidExitFullScreen` (`.fullScreenPrimary` is on, `AppWindow.swift:565`; today only
  exit reapplies, `:590`), so full screen's radius 0 takes the minimum live. Tested with radius 0 and the fallback. No `NSToolbar`:
  it would change the radius and the titlebar layout `TrafficLights.place` relies on.
- **Traffic lights** stay where they are today on the 48pt line, over the sidebar's glass when expanded. Apple's
  inset-sidebar apps keep the window buttons at the system's position and let the sidebar's glass accommodate them, so
  `TrafficLights.place` is not changed by default; S6 compares with Finder and Mail on 26.5 before anything moves.

**W2 (fallback if S6 fails)**: Silo's flush chrome: sidebar and top row flush with the window's edges as one glass
surface (window non-opaque, `NSGlassEffectView` as the window's content view, hosting view inside, pages opaque). It
samples the desktop; its costs (backdrop under the whole window, a transparent window) are why it's second.

### 5.3 The top bar: content under glass controls

The 48pt row stops being a ground of its own; each page's content scrolls under it.

- **Pages converted**, each so that its `ScrollView` is the direct content under a `safeAreaBar(edge: .top)` holding the
  page's title and its trailing buttons: `AppPage` (`AppContent.swift:145-182`: the inbox lists, Done, Settings,
  Categories, all at once since they share it), and the Router (`RouterMain.topBar`, `RouterCode.swift:50`; its history
  and Now columns). The Now column has its status line between the bar and its scroll view (`RouterPage.swift:1221-1224`:
  `VStack { routerStatus; ScrollView … }`): `routerStatus` moves into the column's `safeAreaBar` as a second row, so the
  column scrolls under both. The Now column's `ScrollView` gets `.scrollEdgeEffectStyle(.hard, for: .top)` because it
  pins its zone headers (`pinnedViews: [.sectionHeaders]`; the modifier goes on the scroll view, not the header); the
  Router's history scroll view and every other page get `.soft`. The 0.5pt rule goes (the edge effect replaces it).
- **Nav controls** (sidebar toggle, back, forward): one glass capsule of three icons (`.buttonStyle(.glass)` in the
  window's `GlassEffectContainer`), after the traffic lights, over the content. They sit beside the sidebar's glass,
  never on it.
- **Page titles** stay plain text in the bar, not on glass (an inference from Apple's toolbar guidance that
  non-interactive items aren't bordered; WWDC25 310, HIG Toolbars).

### 5.4 The Router's composer floats

Today the composer sits below the transcript (`RouterCode.swift:40-47`), on flat `s1`: glass there would be a grey plate.
So it moves over it: the history's `ScrollView` takes the composer as `safeAreaInset(edge: .bottom)`, so the last message
still lands above it (`defaultScrollAnchor(.bottom)` keeps working with the inset) and earlier ones scroll under it. The
composer card (radius 14) becomes Regular glass; its field and pills stay as they are (material on the container only,
WWDC25 356). Increase Contrast: opaque `s3` with its existing ring. This is the one layout change in the Router; it's
its own commit, with the history's scroll behaviours re-tested: "pinned" must still hold at the bottom with the inset
(`HistoryPin.atBottom(contentSize.height, visibleBottom:)`, `RouterPage.swift:658-659`, and `HistoryScrollWatch.swift:70-72`
compare the visible rect's bottom with the content's height; with the inset the visible rect may extend under the
composer by its height, so the comparison subtracts the bottom inset), "Show earlier" at the top unaffected, jumps to a
message land above the composer.

### 5.5 The bar and its panels (if S1–S3 pass)

- **Bar**: `.glassEffect(.regular, in: barOutline)`; the ring, the near shadow and the shape-only shadow casters go in
  glass mode (the material has its own edge and shadow).
- **The panel grows out of the bar**: bar and panel in one `GlassEffectContainer`, each with a `glassEffectID`; when the
  dwell ends, the panel's glass comes out of the bar's edge as one shape (`.matchedGeometry` within the container's
  spacing), its content fading in 40 ms behind. The container merges the shapes, so the seam patch goes.
  **Switching sections** (400 ↔ 232 wide) happens in `Transaction(animation: nil)`, instant as today, so it never
  morphs. Reduce Motion: `glassEffectTransition(.identity)` and a plain fade.
- **Badges**: the 2pt ring painted with `Theme.bg` (`HubComponents.swift:768`) becomes a real cut-out (an inverted
  capsule mask), right on glass and opaque alike.
- **Away and back**: the window's `alphaValue` fade stays (compositor-only, cheap).
- **Drag to another edge**: the glass stretches a little along the motion at the start and settles at the end
  (the stretch uses `spatial` with an explicit Reduce Motion resolution to `nil`: no stretch at all, the bar's move itself
being the content, and written so the source scan sees it resolved), and an `NSHapticFeedbackManager` `.alignment` tick
  when it snaps to an edge (Force Touch trackpads; a Fjord-only cue, the system gives none for window snaps).

### 5.6 The morph

**M1 (if S5 passes): it starts as the bar's glass.** The overlay (level above window and bar, `AppTransition.swift:302`)
holds, bottom to top:

1. **G1**, a glass shape that begins at the bar's cell (its frame and radius, as today) and springs to the window's frame
   and radius on the existing springs. It samples the desktop, and the bar fading under the overlay, like the bar did.
2. A **container** in the window's shape (as today, opaque `s1`) that fades in over the second half, as today.
3. **G2**, a second glass shape at the inset sidebar's frame (scaled with the window's rect), on top of the container,
   so it samples `s1` exactly as the real sidebar does.
4. The **window's picture**, whole and unmasked: everything drawn over the glass (the sidebar's rows, icons and counts,
   the traffic lights, the nav capsule's glyphs) stays in it, as in today's morph.

G2's opacity rides the container's (0 → 1 over the second half): in the first half the sidebar's region shows G1, the
bar's glass growing; G2 arrives with the `s1` it samples, so the material never changes under a still frame.

**Captures and glass (`Chrome.capturing`).** Glass can't be captured (S4 says how it comes out: transparent, `s1` or
black), so every capture renders the glass pieces specially, for one render pass, then restores them:

- **Which pieces**: every piece that draws glass. In the window, the sidebar's background is drawn **clear** (G2 shows
  through it); the nav capsule and the composer are drawn with **their opaque-mode fills** (§5.1: `s2`, `s3`), too small
  for live shapes of their own, so they're in the picture from the first frame and only their material changes at the
  handoff. On the bar, the bar and panel shapes are drawn with their opaque-mode fill (`Theme.bg`).
- **Which captures**: all three paths. The window's close-time capture (`AppWindow.swift:375` → `makeRun(for:bar:)` →
  `AppTransition.swift:120`, kept as `closedPicture` at `AppWindow.swift:386`, used by the next opening); the opening's
  refresh (`Run.refresh`, `AppTransition.swift:354`, from `payPicture` / `contentChanged`, `AppWindow.swift:269`/`:313`);
  and the bar's (`HubController.swift:412`, still used by M1's close and by M2).
- **The sequence, all in one turn of the main run loop**, on the real window: set the flag → `layoutSubtreeIfNeeded()`
  → `displayIfNeeded()` → `cacheDisplay` → clear the flag → `layoutSubtreeIfNeeded()` → `displayIfNeeded()`. No
  `CATransaction.flush` may sit inside it (`AppTransition.flushInitial`, `:79`, and the flushes at `:470` / `:636` are
  outside every capture today and must stay so), so the only state the run loop's implicit commit ever sends to the
  render server is the restored one. This relies on `NSHostingView` processing a state change inside
  `layoutSubtreeIfNeeded()`, which `AppWindowShots.capture` (`:206-212`) already depends on but Apple doesn't document;
  S4 verifies it: 20 opens and 20 closes recorded (`screencapture -V`, or an LCU recording) with no frame showing a
  cleared sidebar or a stand-in fill. The recording is the gate; the Core Animation instrument's commits per turn are a
  confirmation only (`displayIfNeeded()` itself never commits).
- **Scope**: the flag is per capture target, not on the shared `Chrome` instance: it's an environment value set on the
  root of the window being captured (through `AppRootView`'s hosting controller's `rootView`, or `HubRoot`; the window
  capture itself still runs on the theme frame, `AppTransition.swift:106`, as today), so a window capture never
  re-renders the bar and a bar capture never re-renders the window.
- **Cost**: two re-renders (clear, then restore) of the views in that root that read the flag, per capture, measured
  under the existing "Capture" signpost: ≤ baseline + 1 ms.
- **If S4 fails** (a cleared frame reaches the screen, or the update isn't processed in-turn), there's no safe way to
  capture glass differently from what's shown, and the morph falls back to **M2**.

At the handoff (real window revealed under the overlay two refreshes before the spring settles, as today), the real
sidebar replaces G2 sampling the same `s1`, with the same content over it: no pop. Closing mirrors it into the cell; G1
hands back to the bar's glass fading in under the overlay.

What M1 changes for latency: the bar's capture (`bar()` → `HubController.morph`'s `cacheDisplay`, `:412`) runs at
`AppWindow.swift:175`, *inside* the "Open to first flush" interval (`:154`), before the first frame is flushed. M1 needs
no picture of the bar (G1 *is* the bar's glass), so it removes that capture from the opening's critical path: shortcut →
first moving frame gets shorter by the capture's time. Reduce Motion: today's 0.15 s cross-fade at the window's frame.

**M2 (fallback)**: today's picture morph, the overlay unchanged. If S4's in-turn flag works, the sidebar is captured with
its opaque-mode fill too (so the whole window is opaque stand-ins whose material changes at the handoff); if it doesn't,
captures take the glass as S4 found it, and the real window's glass fades in over 120 ms after the handoff.

### 5.7 Motion

One vocabulary in `Motion.swift`, replacing `Theme.Motion` and the ad hoc curves (survey §5), each with its Reduce Motion
fallback built in:

| Token | Use | Value | Reduce Motion |
|---|---|---|---|
| `instant` | hover-on fills, press | none | none |
| `release` | hover-off fills | easeOut 0.12 | none |
| `fade` | presence (appear/disappear) | easeOut 0.14 | same |
| `spatial` | moves and resizes | spring, critically damped, response 0.3 | fade 0.12 (as the fold does today, `AppSidebar.swift:24`) |
| `glass` | glass shapes morphing, and whatever must stay in lockstep with them (the page's leading inset during the fold) | spring response 0.35, bounce 0.12 | fade 0.12 |
| `window` | the morph | existing CA springs | 0.15 cross-fade |

Rules, enforced by a source scan over the whole app (extending `RouterMotionTests`, §8):

1. **Hover-on is instant, hover-off eases** (today both ease 0.12 s, `Components.swift:135`: a felt lag on every row).
2. **Springs for space, fades for presence.**
3. **Interruptible**: every spatial animation reverses from where it is (the morph already does, `pose`, `:408`).
4. **No per-frame relayout over 2 ms** (§5.2's fold rule, applied everywhere).
5. **Nothing loops in SwiftUI.** `BlinkingDot` (`RouterSessions.swift:57`) already respects Reduce Motion and stands
   still while the window is closed (its content is taken out, `AppWindow.swift:135`); it moves to Core Animation for
   the open window's sake, not for idle.

### 5.8 Colours and shapes over glass

- **Fills over glass** (sidebar rows, bar cells, panel rows): alpha steps of `Brand.ink` for hover / selection /
  selected-hover. Dark: 6 / 9 / 12% white, as Silo's dark theme. Light: this plan's own starting values, 6 / 10 / 14% ink
  (Silo's light theme used 25 / 44 / 55% *white*, which assumes its teal tint), set by the contrast pass (§6). Opaque mode
  keeps today's tokens.
- **Text over glass**: decided by S6(4). If label styles are vibrant inside `.glassEffect`, use `.primary` /
  `.secondary`; if not, keep `CDS.Text` colours. Status colours (amber, red) stay fixed either way.
- **Hairlines, the bar's ring, shadows**: none on glass pieces; kept in opaque mode.
- **Radii, derived**: window (runtime) → sidebar (− 8, min 6) → sidebar rows (concentric, min 6); bar 20 → wells
  (already `max(10, r − 6)`) → cells 6; panels concentric with the bar's radius. Dead tokens deleted: `CDS.Sidebar.width`
  (288), `CDS.Sidebar.titleRow` (46), `BarMorph.radius` (18), `Theme.Radius.panel`, `Theme.panel`, `Theme.popover`.
- **Tint**: none.

### 5.9 What stays as it is

Pages and everything on them; Settings controls; editors and chips; cards; the onboarding page (content); tooltips
(`TipBubble`: small, short-lived, over content; keeping them opaque is this plan's call, not an Apple rule); SwiftUI
`.popover`s (the system draws those, glass on 26 by itself); menus (system); and all of macOS 14/15.

## 6. Accessibility

| Setting | System material | The app |
|---|---|---|
| Reduce Transparency | frosts glass | `Chrome.mode = .opaque` (26 geometry, opaque fills) |
| Increase Contrast | dark/light with borders | `.opaque`; the composer keeps its contrast ring |
| Reduce Motion | calms glass | every motion token's fallback (§5.7); morph cross-fade; panel without materialize |
| Liquid Glass look (26.1: Clear / Tinted) | follows it | nothing; checked in the visual pass |
| Differentiate Without Colour | — | unchanged (playground shots cover it) |

Contrast is measured on the composited result (live screenshots over a light, a dark and a busy wallpaper) for sidebar
labels, bar counts, panel rows and nav glyphs: WCAG 2.2 AA (4.5:1 text, 3:1 non-text). A gate (§7).

## 7. Budgets (the gates) and how each is measured

**Baselines first** (Phase 0), recorded in §11; then after each phase. Method for every rest measurement: pointer parked
off the bar, display otherwise static (no clock in the menu bar's second hand, no video), `--demo busy` so no working
ring animates, `FJORD_GLASS=0` and `=1` runs interleaved, ≥ 5 runs each, medians and spread reported. On this Mac's
built-in display; a 60 Hz external one too when connected.

| Measure | How | Budget |
|---|---|---|
| App CPU at rest (bar only; window open) | `idle-cpu.sh` | < 0.1% of a core (unchanged) |
| WindowServer CPU at rest, glass vs opaque | `idle-cpu.sh` delta, method above | median delta ≤ 0.3 points of a core *and* within the opaque runs' spread |
| WindowServer GPU at rest | Metal System Trace, system-wide, 30 s, WindowServer track (or `powermetrics --samplers gpu_power`, which needs sudo: the owner runs it) | no recurring frames for us while nothing changes; GPU delta reported and judged by the owner |
| WindowServer memory, glass vs opaque | `footprint WindowServer` / `vmmap` IOSurface lines (may need the owner's sudo) | delta ≤ 30 MB with bar + window open |
| App memory, window open / closed | `footprint` on the app | ≤ baseline + 10 MB open; ≤ baseline closed |
| Shortcut → first moving frame | "Open to first flush" signpost, 20 opens; a new "Bar capture" signpost around `bar()` gives the baseline's share | p95 ≤ baseline − the bar capture's time (M1) / ≤ baseline (M2) |
| Click on the bar → bar away starts | new "Bar away" signpost | p95 ≤ baseline |
| A capture with the flag | the existing "Capture" signpost | ≤ baseline + 1 ms |
| Dwell end → panel's first frame | new "Peek" signpost | ≤ 1 frame |
| Dropped frames: morph, panel open, fold, drag | Animation Hitches, 20 of each | 0 at 120 Hz built-in; ≤ 1 per 20 at 60 Hz external |
| Main-thread time per frame during the fold | Time Profiler (main thread) + SwiftUI template (layout lane), 20 folds | ≤ 2 ms per frame, every page |
| Contrast | composited screenshots | WCAG 2.2 AA (§6) |

A budget that isn't met means the piece falls back (bar opaque, M2, W2, opaque sidebar fill), not that the budget moves.
Changing a budget is the owner's call, written here.

## 8. Tooling (Phase 0, kept)

1. **`scripts/idle-cpu.sh`**: WindowServer's delta judged (`WS_LIMIT`, method of §7: interleaved `FJORD_GLASS=0/1`,
   medians, spread); `--baseline FILE` stores and compares.
2. **`scripts/motion-trace.sh`** (new): `xcrun xctrace record` with Animation Hitches, Time Profiler, SwiftUI and Metal
   System Trace against a `--demo` build driven by a dev flag `--motion-script open,close,fold,peek,drag x20` (the app
   triggers each motion on a timer, so no person or LCU is needed); exports hitches and signpost intervals to JSON;
   compares with a stored baseline.
3. **Signposts**, added in Phase 0 so the baselines have them: "Peek", "Fold", "Drag", "Bar away", and "Bar capture"
   around the bar's `cacheDisplay` (`HubController.swift:412`, which has none today); same subsystem as the morph's.
4. **Source scans** (tests): every animation resolves for Reduce Motion (all files); no `repeatForever` in SwiftUI;
   `.glassEffect` only in the chrome files; no `.shadow` on a glass piece.
5. **Shots**: `--window-shots` / `--playground-shots` with `FJORD_GLASS=0` (glass can't be captured) guard the 26
   geometry; `--glass-check` opens the live bar, a panel and the window over three wallpapers and prints window IDs, for
   LCU screenshots in the visual pass (owner's OK: it takes focus).
6. **Tests**: `Chrome` (OS, preferences, flag, no-animation switch); concentric radius math incl. radius 0 and the
   fallback 16, republished on full screen; motion fallbacks; the morph's poses with G1/G2 and the capture flag's
   effect on the picture (`AppTransitionTests`); `BarLatencyTests`
   and `HubRetentionTests` with glass on (hit-testing unchanged); the Router history's scroll behaviours with the
   composer inset (pinned at the bottom with the inset, "Show earlier", jumps).

## 9. Phases and commits

Each commit is one verified piece: implement → `swift test` → the relevant budgets → Codex review → (visual pass with
the owner's OK where it changes the look) → commit.

**Phase 0** (no visible change): baselines; `idle-cpu.sh` WindowServer verdict; `motion-trace.sh` + `--motion-script`;
the new signposts; spikes S1–S6 written up.

**Phase 1** (no visible glass), one commit each:
1. Dead tokens removed.
2. Hover-on instant.
3. `Motion.swift` + the app-wide Reduce Motion scan.
4. `BlinkingDot` to Core Animation.
5. `Chrome` (+ environment wiring, `FJORD_GLASS`).
6. Derived radii (window radius as `containerShape`).
7. Badge cut-out.

**Phase 3, the window** (proceeds on S6 alone, independent of the bar):
1. Inset sidebar + rail (W1, or W2's flush chrome), with the fold per §5.2.
2. Pages under the top bar (`AppPage` users) + nav glass capsule.
3. The Router under the top bar (history `.soft`; Now column `.hard`, with its status line in its bar).
4. The Router's composer floating (§5.4).

**Phase 2, the bar** (if S1–S3 pass; may land before or after Phase 3):
1. Bar glass.
2. Panel growing out of the bar (+ seam removal).
3. Drag stretch + haptic.

**Phase 4, the morph**: M1 (or M2), after the bar and the window.

**Phase 5, polish**: contrast pass (sets §5.8's light values); light-mode pass; Liquid Glass look (Clear / Tinted) pass;
60 Hz pass; the wordmark at the sidebar's top (Geist Medium, the j's dot a fonte disc: the only fonte in the app, as
identity).

## 10. Risks

| Risk | Likelihood | Effect | Mitigation |
|---|---|---|---|
| Glass in a never-key panel looks subdued (S1) | unknown | bar and/or panels can't be glass | they keep today's look; the window still ships; no private API |
| Stale backdrop in the panel (S2) | SwiftUI path: low (26.4 fix); AppKit path: unknown | glitch | S2 per path; the bar uses the SwiftUI path |
| WindowServer cost of an always-on glass bar (S3) | unknown | battery | glass on panels only, or none |
| Glass not animatable in the overlay (S5) | medium | M1 impossible | M2 |
| Inset sidebar reads as a dull plate (S6-2) | medium | no visual gain | opaque inset sidebar, glass controls only |
| Router scroll behaviours under the composer inset | medium | regressions | own commit, tests, re-check pinning and jumps |
| Hand-placed traffic lights vs the inset sidebar | medium | misalignment | they stay at the system position; S6 compares with Finder/Mail; they move only if Apple's inset apps move them |
| Private `_cornerRadius` read stops working | low | wrong concentric radii | fallback 16, tested; radius floor 6 |
| macOS 27 changes (`effectIsInteractive`, `cornerConfiguration`, edge effect `.automatic` → hard) | certain, later | drift | everything behind `#available(macOS 26)`; a later pass adopts 27 APIs |
| Shots can't show glass | certain | less automated look coverage | opaque-mode shots (real geometry) + live `--glass-check` |

## 11. Research notes, decisions, results

- **SDK facts (Xcode 26.5)**: `NSGlassEffectView` (`contentView`, `cornerRadius`, `tintColor`, `style` Regular/Clear;
  no `state`), `NSGlassEffectContainerView` (`contentView`, `spacing`; batches similar glass), `NSBackgroundExtensionView`,
  `NSBezelStyleGlass`, `NSButton.tintProminence`, `NSView.LayoutRegion.safeArea(cornerAdaptation:)`; SwiftUI(Core)
  `glassEffect(_:in:)`, `Glass` (`.regular/.clear/.identity`, `tint`, `interactive`), `GlassEffectContainer(spacing:)`,
  `glassEffectID(_:in:)`, `glassEffectUnion`, `glassEffectTransition` (`matchedGeometry`, `materialize`, `identity`),
  `ConcentricRectangle`, `Edge.Corner.Style.concentric(minimum:)`, `containerShape(_: some RoundedRectangularShape)`,
  `.glass`/`.glassProminent`, `backgroundExtensionEffect`, `scrollEdgeEffectStyle(_:for:)`, `safeAreaBar(edge:)`. Not in
  26.5: `effectIsInteractive`, `NSViewCornerConfiguration` (macOS 27); WWDC25's `.containerConcentric` doesn't exist
  (`.concentric`). AppKit scroll edge style: 26.1. `CGWindowListCreateImage`: obsoleted (`SCREEN_CAPTURE_OBSOLETE(10.5,
  14.0, 15.0)`).
- **Apple guidance**: WWDC25 219 (Meet Liquid Glass), 310 (AppKit), 323 (SwiftUI; the "one sampling pass" container line
  is attributed to it here, unverified), 356 (design system); HIG Materials, Sidebars, Toolbars, Windows; "Adopting
  Liquid Glass"; macOS 26.4 release notes, SwiftUI section (166828089).
- **Silo** (`microsandbox-workspaces/docs/SiloUI-GLASS-STUDY.md`, `app/SiloUI/src-tauri/src/window_material.rs`):
  Regular over Clear; no tint; content 100% opaque; the opaque path from `NSWorkspace` + notification; app appearance
  drives native appearance (here windows inherit the Mac's; `Brand.appearance` pins per window: already consistent);
  traffic lights placed by hand and reapplied on resize and focus. Silo never measured glass's cost; this plan does.
- **Revision 2** (after Fable's first review): S1's premise corrected (no report exists for glass in a non-key panel;
  NSVisualEffectView's has a public `state`, glass has none); S2 per path; the composer floats (§5.4) instead of being
  glass on flat `s1`; the fold measured first, then offset-based layout-once if needed; fold budget in main-thread ms;
  opaque mode = 26 geometry with opaque fills; the top bar converted page by page; the sidebar's look stated plainly and
  gated on S6(2); M1 with G1/G2 and a masked picture; latency targets tied to real work removed (the bar's capture);
  rest measurements with a method (parked pointer, `--demo busy`, interleaved, medians) and GPU/WindowServer memory;
  bar on the SwiftUI glass path for hit-testing; section switch without morph; Reduce Motion spelled out per token;
  roots listed correctly; Phase 1 split into commits; Phase 3 independent of the bar; citations fixed.
- **Revision 5** (after Fable's fourth review, verdict "ready"): the capture flag scoped per capture target; the
  recording named as S4's gate; the fold's inset on the `glass` curve in lockstep with the shape; `.soft` on the
  Router's history spelled out; a stale "(b)" label removed.
- **Revision 4** (after Fable's third review): the capture flag always applies (no case split), to every glass piece and
  every capture path (both window captures, cited where they're taken, and the bar's); its in-turn sequence is spelled out
  and S4 verifies no cleared frame is ever presented, M2 if not; G2 fades in with the container; signposts added in
  Phase 0; the drag stretch's Reduce Motion resolution named; the risk table matches §5.2 on the traffic lights; S4 runs
  on a scratch window.
- **Revision 3** (after Fable's second review): the morph keeps the whole picture (no mask) with glass backgrounds
  cleared for captures when S4 requires it, and the small glass pieces captured as opaque stand-ins; M1 shortens the
  first frame by the bar's capture (it is on that path); Reduce Motion fades rather than cuts for spatial and glass
  motion; traffic lights stay at the system's position; the Router's Now status line joins its bar, `.hard` on the
  scroll view; the history's pin check subtracts the composer's inset; the nav capsule rides the fold's offset; radius
  republished on full screen; one vs two glass containers measured; `.concentric(minimum: .fixed(6))`; citations.
- **Spike results**: _to be written here (S1–S6)._
- **Baselines**: _to be written here._
