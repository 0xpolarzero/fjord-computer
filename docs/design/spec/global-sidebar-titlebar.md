# Claude desktop, Code tab: global tokens, sidebar, title bar (dark mode)

Read from Claude's own shipped web code. Every value below is traced to a source rule or class string. Values marked MEASURED come from the reference screenshot and only cross-check a traced value, or stand in where the class could not be found (those are also marked UNKNOWN). All sizes are CSS px; at 100% zoom 1 CSS px = 1 pt in a native macOS app.

## 0. Sources and how the build was picked

- Bundles: `/tmp/claude-web-d/`. Several builds of each chunk exist. The current build was picked from the Chromium HTTP cache (`~/Library/Application Support/Claude/Cache/Cache_Data`, mtime of the entry that holds each asset URL). The newest build is the one cached on 2026-10-09 at 21:25. It is not always the largest file: for example `c1c1ec7b9-DU5lyQpQ.js` is newest, not `c1c1ec7b9-1y55QW_K.js`.
- Files used (all from the current build):
  - `c6a992d55-Drv_MyUK.css`: CDS tokens, Tailwind utilities, font weights.
  - `shared-styles-B1jXfLTX.css`: the desktop frame ("dframe"): sidebar, rows, title row, status dots.
  - `shared-22-CuhAVIje.js`: frame shell (`dframe-root`, sidebar `<aside>`, sidebar title row). Function `QF` builds the root and `OF` builds the sidebar.
  - `shared-21-9nKMA7m6.js`: search field (`gE`), New row (`PR`), New circle (`FA`), More row (`CL`), sidebar toggle (`lE`), back/forward (`ZC`), group "+" (`rB`/`tB`).
  - `shared-18-CIJT4aK5.js`: row primitive (`mE`, `dE`), group label (`UE`), session status glyphs (`zD`, `AD`, `fD`, `gD`, `iD`, `vw`, `pw`), status dot (`$v`), app-switch wrapper (`eV`).
  - `shared-20-BUWXZWmU.js`: app switch (`qR`), filter button (`uX`/`dX`), nav badge (`LZ`).
  - `shared-19-BebVWfVJ.js`: footer account button (`RN`).
  - `shared-frame-BAME2HDg.js`: CDS components: Button, Badge, Avatar, SegmentedControl, Icon sizes.
  - `shared-l-m-0-VOJMFcoz.js` and `shared-l-p-m-0-DWK7nXH5.js`: density and variant selection.
  - `c8782095c-DPKhJ2m0.js` and `shared-6-BoBG7Dp0.js`: Code session title bar.
  - Fonts: `/tmp/claude-src/.vite/renderer/main_window/assets/MainWindowPage-yE7nSc5c.css` (`@font-face`) and `AnthropicSans-Roman-Variable-DDVos-BJ.woff2`.
- Reference screenshot scale. Chromium stores the claude.ai zoom level as `0.5` (`per_host_zoom_levels → claude.ai: 0.5` in `~/Library/Application Support/Claude/Preferences`), which is a factor of 1.2^0.5 = 1.0954. `config.json` agrees: `windowControlsZoomFactor: 1.0954451150103321`. The screenshot is 2× Retina, so it shows **2.191 image px per CSS px**. Every MEASURED value below has been divided by 2.191. Cross-checks that fit: selected row 57 px → 26.0, status dot 13 px → 6, transcript line pitch 44 px → 20. To match what the user sees at their zoom, multiply spec values by 1.0954.

## 1. Global

### 1.1 Density, size step, rem scale

- **Rem scale = 1 on desktop.** `--cds-rem-scale:calc(16 / 17)` exists only inside `@supports (font:-apple-system-body) and (-webkit-touch-callout:default)` (iOS). On macOS `1rem = 16px`. Source: `c6a992d55-Drv_MyUK.css`.
- **The frame (sidebar and window chrome) is compact.** The sidebar density comes from `fd()` (`shared-l-m-0`, exported as `Pu`):

  ```
  function fd(){let[e]=td(),t=dd()==="web",n=Ne();return se(e??(t&&!n?"comfortable":"compact"))}
  ```

  - `td()` reads the setting `"appearance:sidebarDensity"`. The user's Local Storage has no value for it.
  - `Ne()` means "is the Claude desktop app" (UA check `wT`, which requires `window.claudeAppBindings`).
  - So the default in the desktop app is `compact`. It is written to `<aside class="dframe-sidebar" data-density=…>` and to `<div class="dframe-root" data-sidebar-density=…>`, and the sidebar's own `CdsRoot` provider gets `density:xe`.
  - MEASURED agrees: row height 26, row text 13 px.
- **Frame variant = `web`, even in the desktop app.** `dd()` returns `ru||ud?"web":"desktop"`, where `ud = isClaudeApp(navigator.userAgent)`. So `data-variant="web"`: the sidebar is flush and full-height with a 0.5 px right border, and the title row is 46 px. MEASURED agrees: flush sidebar and a 0.5 px border at x ≈ 279.
- **Hub rail is on.** The aside carries `df-hub-rail` (`Ye=d&&"df-hub-rail"`). That sets `--df-iconless-pad:8px` and `--df-rail-shift:4px`, which pushes every leading slot 4 px to the right. MEASURED agrees: nav text x = 42 = 8 + 2 + 4 + 24 + 4.
- **Session list is the "classic" layout.** `data-code-list` is absent: it needs `Df()&&mode==="code"` (a gate). The `[data-code-list]` overrides (row-h 28, row-ctl 24) therefore do not apply. MEASURED row height is 26, not 28.
- **Main content `CdsRoot`:** `dframe-root` is rendered by `T({font:s,render:div.dframe-root})` with no density prop, so it inherits the context default `Bi=ge("comfortable")` (`shared-frame`). Dialogs inside force `density:"comfortable"`.
  - The Code session title text measures 13 px (the compact or xs body size). The provider that makes it 13 px was not traced, so the title bar's density is UNKNOWN; size it with the compact values below, which match the measurement.
- **Size steps.** `[data-size=xs|sm|lg]` maps tokens to `--cds-*--xs|sm|lg`, which differ per density. The values used here are in §1.3.

### 1.2 CDS tokens: compact (`.cds-root`) vs comfortable (`.cds-root[data-density=comfortable]`)

| token | compact | comfortable |
|---|---|---|
| `--cds-radius` | 6 | 8 |
| `--cds-radius-composer` | 12 | 14 |
| `--cds-panel-radius` | 10 | 12 |
| `--cds-h-control` | 24 | 32 |
| `--cds-h-control-nested` | 18 | 22 |
| `--cds-icon` | 16 | 20 |
| `--cds-pad-xs / sm / md / lg / xl` | 4 / 6 / 8 / 12 / 20 | 6 / 8 / 12 / 16 / 24 |
| `--cds-gap-xs / sm / md / lg / xl` | 6 / 8 / 12 / 20 / 32 | 8 / 12 / 16 / 28 / 40 |
| `--cds-avatar-xs / sm / md / lg` | 16 / 20 / 28 / 36 | 20 / 24 / 32 / 40 |
| `--cds-checkbox` | 16 | 20 |

Text roles, as font-size / line-height:

| role (class) | compact | comfortable |
|---|---|---|
| caption (`text-caption`) | 11 / 17 | 12 / 17 |
| footnote (`text-footnote`) | 12 / 15 | 13 / 17 |
| code (`text-code`, mono) | 12 / 17 | 13 / 19 |
| body (`text-body`) | 13 / 19 | 14 / 20 |
| prose | 14 / 20 | 16 / 24 |
| heading | 14 / 18 | 15 / 20 |
| title | 20 / 25 | 22 / 28 |

### 1.3 Size-step tokens used by sidebar controls

| token | compact | comfortable |
|---|---|---|
| `--cds-h-control--xs / sm / lg` | 20 / 20 / 28 | 24 / 28 / 40 |
| `--cds-h-control-nested--xs / sm / lg` | 16 / 16 / 20 | 18 / 20 / 28 |
| `--cds-radius--xs / sm / lg` | 5 / 5 / 7 | 6 / 7 / 10 |
| `--cds-pad-sm--xs / sm / lg` | 4 / 4 / 8 | 6 / 8 / 12 |
| `--cds-font-size-caption--xs / sm / lg` | 10 / 10 / 12 | 11 / 12 / 13 |
| `--cds-font-size-body--xs / sm / lg` | 12 / 12 / 14 | 13 / 14 / 15 |

### 1.4 Fonts, weights, rendering

- **Sans.** `--cds-font-sans: var(--font-anthropic-sans), system`, where `--font-anthropic-sans: "anthropic-sans", ui-sans-serif, -apple-system, …`.
  - `@font-face anthropic-sans`: `AnthropicSans-Roman-Variable` and `…-Italic-Variable`, `font-weight:300 800`, `font-feature-settings:"dlig" 0`.
  - Font axes: `wght` 300–800 (default 400) and `opsz` 16–48 (default 16). Internal name: "Anthropic Sans Variable Text". unitsPerEm 2000, capHeight 1440 (0.72 em), xHeight 1080, ascender 1985, descender −515, lineGap 0.
- **Mono.** `--cds-font-mono: var(--font-anthropic-mono,"SF Mono"), "SF Mono", ui-monospace, Menlo, …`, where `--font-anthropic-mono: "anthropic-mono", ui-monospace, monospace` (`@font-face anthropic-mono`, `font-weight:300 800`).
- **Dark-mode weights** (`[data-mode=dark] .cds-root…` block):

  | CDS variable | value |
  |---|---|
  | `--cds-font-wght-regular` | `"wght" 360` |
  | `--cds-font-wght-medium` | `"wght" 460` |
  | `--cds-font-wght-semibold` | `"wght" 540` |
  | `--cds-font-wght-bold` | `"wght" 560` |

  These apply through `font-variation-settings: var(--font-opsz-axis,) var(--cds-font-axis-wght,) "GRAD" var(--cds-font-grad,0)`.
  - The CSS `font-weight` values stay 400 / 500 / 580 / 600, but the `wght` axis setting is what renders.
- **Role weights:**
  - `--cds-font-wght-body`, `-control` and `-header` are all `initial`, so `.font-control` and `.font-header` fall back to regular. **Body = control = header = wght 360.**
  - `text-body-medium` and `.font-medium` = 460. `.font-semibold` = 540. `b`, `strong` and `.font-bold` = 560.
  - Older `[data-theme=claude][data-mode=dark]` rules (`.font-medium` 460, `.font-semibold` 560, `b/strong/.font-bold` 660) are overridden by later same-specificity rules that point back to the CDS variables, so the CDS values win.
- **GRAD** is 0 everywhere, except the `.grad-semibold` (180) and `.grad-bold` (200) utilities. Neither is used in these components.
- **opsz:** `--font-opsz-axis` is only set by `.font-display`, `.font-heading`, `.font-title`, `.font-xl*` and `.font-claude-response-*`, none of which are used here. With no explicit opsz, the browser's automatic optical sizing applies, which equals the font size clamped to 16–48. All UI text here is at most 16 px, so **opsz 16** (the font default).
- **Letter-spacing:** none on these components. **Font features:** `"dlig" 0` from `@font-face`.
- **Smoothing:** `.cds-root{-webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;font-synthesis:none}`.
- **Icons** are a font: `[data-cds=Icon]` uses `Anthropicons-Variable` (wght 400–700), `font-feature-settings:"liga" 0`, `width:1em;height:1em;line-height:1`.
  - Sizes (`shared-frame`, table `Po`): xs 12, sm 16, md 20, lg 24, xl 28, xxl 32.
  - `size:"auto"` resolves to sm (16) in compact and md (20) in comfortable.
  - Glyph weight: `400 + 300·(stroke·master/px − lo)/(hi − lo)`, with masters `{16:{lo:.8,hi:1.25},20:{lo:1.125,hi:1.8}}`. Results:

    | size | regular | strong |
    |---|---|---|
    | xs | 577.8 | n/a |
    | sm | 533.3 | 700 |
    | md | 433.3 | 566.7 |
    | lg | 418.5 | n/a |

  - Frame chrome buttons force 16 px at 533.3: `.df-chrome-btn … span[style*=font-size]{font-size:var(--df-chrome-icon-size)!important;font-weight:533.3!important}` with `--df-chrome-icon-size:16px`.

### 1.5 Colour ramp (dark)

The gray scale is `:where(:root,:host)`. In dark, the neutral ramp is inverted: `--cds-neutral-N → gray-(900−N)`, so `neutral-900` = `#fff`.

| token | resolves to |
|---|---|
| `--cds-text-primary` | gray-50 `#f0efec` |
| `--cds-text-secondary` | gray-200 `#c3c2b7` |
| `--cds-text-muted` | gray-400 `#898781` |
| `--cds-text-disabled` | alpha-4 = white 35% |
| `--cds-alpha-1 / 2 / 3 / 4 / 5` | white 5% / 10% / 20% / 35% / 50% |
| `--cds-border` | alpha-2 = white 10% |
| `--cds-border-strong` | alpha-3 = white 20% |
| `--cds-surface-0 / 1 / 2 / 3` | gray-900 `#0b0b0b` / gray-850 `#151515` / gray-830 `#1a1a19` / gray-800 `#20201f` |
| `--cds-fill-ghost-hover` | white 7.5% |
| `--cds-fill-ghost-selected` | white 15% |
| `--cds-fill-secondary` | alpha-2 (10%) |
| `--cds-fill-secondary-hover` | white 14% |
| `--cds-fill-field` | alpha-1 (5%) |
| `--cds-fill-control` | alpha-2 (10%) |
| `--cds-bg-neutral` | alpha-1 (5%) |
| `--cds-segmented-control-track` | alpha-1 (5%) |
| `--cds-segmented-control-thumb` | alpha-2 (10%) |
| `--cds-fill-accent` | role-accent-450 = blue-450 `#2a78d6` (not overridden in dark) |
| `--cds-text-accent` (dark) | blue-300 `#6da7ec` |
| `--cds-fill-warning` | role-warning-200 = yellow-200 `#fab219` (not overridden in dark) |
| `--cds-text-warning` (dark) | yellow-300 `#db9300` |
| git (dark) | added `#32d74b`, removed `#ff2c56`, modified `#ffd014`, merged `#b796ff`, closed `#ff6159`, conflicting `#fa832e`, draft `#a6a6a6`; opened = added, queued = modified |
| `--cds-ring-color` (dark) | alpha-2 |
| `--cds-ring-hairline` | 1px |
| `--cds-focus-shadow` (dark) | `inset 0 0 0 1px var(--cds-page-bg), 0 0 0 1px var(--cds-fill-accent), 0 0 6px 1px hsl(from blue-600 / 60%)` |

### 1.6 Page and sidebar backgrounds, dividers

- **Page / transcript background** = `--df-bg-page`. The variant-web rule `:root .dframe-root[data-variant=web]{--df-bg-page-hsl:from var(--cds-surface-1) h s l}` beats `[data-mode=dark] .dframe-root{--df-bg-page-hsl:var(--_gray-850)}` on specificity, so the background is surface-1 = **`#151515`**. The transcript default `--epitaxy-transcript-surface` also falls back to `--cds-surface-1`. MEASURED `(21,21,21)` agrees.
- **Sidebar background:** `[data-mode=dark] .dframe-root[data-variant=web] .dframe-sidebar{--df-web-sidebar-bg:color-mix(in srgb, var(--df-bg-page) 80%, black)}`, which works out to **`#111111`**. MEASURED `(17,17,17)` agrees.
- **Sidebar edge:** `.dframe-root[data-variant=web]:not([data-collapsed]) .dframe-sidebar{border-right:.5px solid var(--cds-border);box-shadow:none;border-radius:0;top:0;bottom:0}`. That is a **0.5 px line, white 10%**. MEASURED: one image pixel at `(41,41,41)`.
- **Other dividers:** `--cds-border` (white 10%). The footer tray hairline is `.df-bottom-tray:before{border-top:.5px solid var(--cds-border)}`.
- **Sidebar width:** `--df-sidebar-width` is set inline from the store. `Ii={MIN:200,MAX:420,DEFAULT:288}` (`shared-l-p-m-2`), so the default is **288**. MEASURED: the user has it at about 279. `--df-sidebar-left` is 0 in the web variant. The sidebar is user-resizable via `.dframe-resize-handle`.
- **Sidebar font:** `.dframe-sidebar{font-family:var(--cds-font-sans);line-height:1.5;user-select:none}` plus classes `font-normal font-control`, which give wght 360.

### 1.7 Status dots and session glyphs

Source: `shared-styles-B1jXfLTX.css` and `shared-18` (`zD` → `AD`, `fD`, `gD`).

| state | element | size | colour | notes |
|---|---|---|---|---|
| running | `.status-dot[data-kind=running]` | 6×6 circle | `--cds-text-muted` `#898781` | `animation:1.2s ease-in-out infinite dframe-dot-blink` (opacity .3 → 1 → .3). Under `.df-chorus-code`: `opacity:.7; animation:none`. |
| awaiting | `.status-dot[data-kind=awaiting]` | 6×6 | `--cds-fill-warning` `#fab219` | static. MEASURED `(244,179,59)`. |
| ready (unread) | `.status-dot[data-kind=ready]` | 6×6 | `--cds-fill-accent` `#2a78d6` | static. MEASURED `(67,115,226)`. If the "needs you = blue" setting is on, awaiting is drawn as ready (`UT`). |
| idle | `gD`: `block size-[6px] rounded-full border border-current text-muted opacity-50` | 6×6 ring, 1 px border | `#898781` at 50% | the hollow circles |
| PR states | `vw` icon, `customSize:14`, bold (≥14) | 14 px glyph | `pw` map below | the branch-like icons in the list |
| error | `SD`: Warning icon, sm | 16 px | `text-danger` or `text-secondary` | |
| archived | `TD` | n/a | n/a | |

- PR colours (`pw`):

  | state | icon | colour |
  |---|---|---|
  | open | `GitPullRequest` | git-opened `#32d74b` |
  | merged | `GitMergedSimple` | `#b796ff` |
  | closed | `GitPullRequestClosed` | `#ff6159` |
  | draft | `GitPullRequestDraft` | `#a6a6a6` |
  | conflicting | `GitMergeConflict` | `#fa832e` |
  | queued | `GitMergeQueue` | `#ffd014` |
  | approved | `CheckCircle` | opened |
  | changesRequested | `XCircle` | closed |

  MEASURED: purple `(180,155,247)` and red `(228,106,93)` match merged and closed.
- **Glyph wrapper** (`iD`): `flex min-h-3.5 min-w-3.5 shrink-0 items-center justify-center`, a 14×14 box that is centred in the 24 px leading slot.

## 2. Sidebar (`aside.dframe-sidebar`)

Variables in effect: `.dframe-root` defaults (compact) plus hub rail.

| var | value |
|---|---|
| `--df-row-h` | 26 |
| `--df-row-px` | 2 |
| `--df-row-ctl` | 20 |
| `--df-row-gap` | 4 |
| `--df-row-font` | 13 |
| `--df-group-font` | 12 |
| `--df-icon-size` | 16 |
| `--df-leading-slot` | 24 |
| `--df-new-circle-size` | 18 |
| `--df-new-circle-glyph` | 13 |
| `--df-group-pt` | 12 |
| `--df-radius-pill` | 6 |
| `--df-chrome-icon-size` | 16 |
| `--df-footer-btn-size` | 24 |
| `--df-footer-gap` | 3 |
| `--df-header-h` | 48 |
| `--df-iconless-pad` | 8 (hub rail) |
| `--df-rail-shift` | 4 (hub rail) |
| `--df-hover` | `--cds-fill-ghost-hover` (white 7.5%) |
| `--df-selected` | `--cds-fill-ghost-selected` (white 15%) |

The hover and selected values come from `[data-mode=dark] .dframe-root .dframe-sidebar`, which is later in the file than the web-variant `--df-hover:neutral-50` rule at the same specificity, so it wins. MEASURED selected row `(52,52,52)` on `#111` is 14.7% white.

### 2.1 Structure (top to bottom)

1. Title row (`div.df-titlebar`), §2.2.
2. Body: `div.dframe-sidebar-body flex flex-col flex-1 min-h-0 gap-2 px-2 pt-3 pb-1.5 [overflow:clip]`.
   - `pt-3` is overridden by `.dframe-sidebar-body:not(:has(>.df-pills)){padding-top:4px}`.
   - So the body padding is **top 4, sides 8, bottom 6**, with an 8 px gap between blocks.
3. Inside the body: search field (§2.3), then New (§2.4), then nav rows (§2.5), then a 12 px spacer (`[data-testid=nav-pin-rows]>.h-3`), then sections: Pinned and project groups (§2.6 label, §2.7 rows).
4. Bottom tray with the account row (§2.9).

MEASURED vertical positions (CSS px from window top): title row 0–46, search 54–80, New centre 101, then Projects / Artifacts / Customize / More centres every 26.5, "Pinned" label baseline region about 252, first session row centre 280, account row centre 1155.6 (window 1177.6 tall). These match the traced values.

### 2.2 Sidebar title row (traffic lights, toggle, back/forward, Chat|Code switch)

- **Row** (`shared-22`): `df-titlebar draggable h-11 shrink-0 flex items-center px-2`.
  - The variant rule `.dframe-root[data-variant=web]:not([data-web]) .df-titlebar{height:46px}` sets the height to **46**.
  - `.dframe-root[data-variant=web]:not([data-web]):not([data-wco]) .df-titlebar{padding-top:2px}` adds 2 px at the top.
  - Horizontal padding is 8.
- **Traffic-light spacer:** `div.shrink-0` with `width: var(--df-traffic-light-spacer, Npx)`.
  - The value is computed in JS from `Nl().trafficLightSpacerWidth`; the CSS fallback is 74. The exact number is UNKNOWN.
  - MEASURED: the toggle centre at x = 95.9 implies about 74.
- **Sidebar toggle** (`I_` = `lE`, `size` undefined): CDS ghost icon-only Button, `icon:"Sidebar"`, `className:"df-chrome-btn"`. Its wrapper has class `draggable-none ml-0.5` (2 px left margin).
  - Size: `h-control` 24 square, radius `--cds-radius` 6. Glyph 16 at 533.3.
  - Colour `--cds-text-secondary`. Hover: text `--cds-neutral-900` (white), background `--df-hover`. `.df-chrome-btn` transitions are 0 s.
  - Tooltip "Hide sidebar" (⌘B).
- **Back / forward** (`Q_` = `ZC` → `Ap`, `buttonClassName:"df-chrome-btn"`, size default): two 24×24 ghost icon buttons, back to back, same styling as the toggle.
  - MEASURED centres: 95.9, 119.6, 144.3. That is a 24 px pitch with no gap.
  - The forward arrow appears dimmed when there is no forward history. The disabled style is `[&:disabled:not([aria-busy])]:opacity-disabled`, with `--cds-opacity-disabled:.4`.
- **Chat|Code app switch** (`yu` = `qR` in `shared-20`):
  - Outer wrapper: `draggable-none ml-auto flex items-center`, then `df-app-switch flex`, then CDS `SegmentedControl` `size:"lg"` (`VR()` returns `"lg"` in compact).
  - Container: `relative inline-flex w-fit shrink-0 items-stretch h-control font-sans rounded bg-[var(--cds-segmented-control-track)] p-px`.
    - `h-control--lg` compact = **28**. `.df-app-switch{--cds-radius:999px}` makes it a pill.
    - Track = white 5%. Padding 1.
  - Thumb: `invisible absolute left-0 origin-left rounded-[calc(var(--cds-radius)-1px)] bg-[var(--cds-segmented-control-thumb)] top-px bottom-px [box-shadow:inset_0_0_0_1px_var(--cds-border),0_1px_2px_0_rgb(0_0_0/0.05)]`.
    - Thumb fill = white 10%, with a 1 px inset ring of white 10%.
  - Segment (`pD`): `cds-reset relative z-[1] inline-flex h-full items-center justify-center gap-1.5 … rounded-[calc(var(--cds-radius)-2px)] text-body font-normal font-control [&:not([data-disabled])]:hover:text-primary data-[checked]:text-primary … text-secondary aspect-square`.
    - Width is forced by `.df-app-switch [data-cds=SegmentedControl] span[role=radio]{aspect-ratio:auto;width:calc(2.125rem*…)}` to **34**. MEASURED total width is 68.5.
    - Unchecked and not hovered: `--cds-text-muted`. Checked: `--cds-text-primary`.
  - Icons: `Chats` and `Code`, forced to 16 px (`[data-cds=Icon]{font-size:1rem!important;font-weight:533.3!important}`). Checked: 700 (`--df-app-switch-code-weight,700`).
  - Unread indicator (top-right of the Chat icon): radius `--seg-dot-r:0.1875rem`, so 6 px wide.
    - Position: `--seg-dot-x: calc(100% - r + 1px)`, with `-me-px -mt-px`.
    - A radial mask cuts the icon 2–2.5 px around the dot.
    - Colour: MEASURED blue (fill-accent). The indicator element (`ee(...)`) was not traced.

### 2.3 Search field (`gE`, `shared-21`)

- **Container:** `mb-2` (8 px below).
- **Field:** a `ol` link styled as a field: `df-search-field mx-[calc(var(--df-rail-shift,0px)/2)] mt-1 flex h-[var(--df-row-h)] w-[calc(100%-var(--df-rail-shift,0px))] shrink-0 items-center gap-[var(--df-row-gap)] rounded-[var(--df-radius-pill)] border-none bg-fill-field px-[var(--df-row-px)] text-left text-[length:var(--df-row-font)] text-muted`.

  | property | value |
  |---|---|
  | height | 26 |
  | margin | top 4, sides 2 (half the rail shift) |
  | radius | 6 |
  | background | white 5% (`#1d1d1d` on `#111`; MEASURED `(29,29,29)`) |
  | padding | 0 2 |
  | gap | 4 |
  | text | 13 px, wght 360, `--cds-text-muted` `#898781` |

- **Ring:**
  - `.df-search-field:not(:focus-visible){box-shadow:inset 0 0 0 var(--cds-ring-hairline) var(--cds-ring-color), var(--shadow-field-drop,0 1px 2px 0 #0000000d)}`, which is a 1 px inset white 10% ring plus a `0 1px 2px #0000000d` drop.
  - Hover: background `--cds-fill-secondary-hover` (white 14%); shadow `var(--shadow-field, inset 0 0 0 1px var(--cds-fill-secondary-ring), 0 1px 2px #0000000d)`. In dark, `--cds-fill-secondary-ring` is transparent.
  - Transition: `background-color var(--cds-dur-fast)` (60 ms) `var(--cds-ease-out)`.
- **Leading:** `span[data-leading-slot] ml-[calc(var(--df-rail-shift,0px)/2)] flex size-[var(--df-leading-slot)] …` (24×24, 2 px extra left margin). It holds the `Search` icon at size sm: 16 px, wght 533.3, colour inherits muted. MEASURED `(142,141,139)`.
- **Label:** `span[data-row-label] min-w-0 flex-1 truncate`, text "Search".
- **Shortcut:** `df-search-field-keys flex shrink-0 items-center pr-[calc((var(--df-row-h)-1em-6px)/2-var(--df-row-px))] text-caption`. It has opacity 0 and becomes 1 on hover or focus-visible.

### 2.4 "New" row (`PR`, `FA`, `shared-21`)

- **Row:** CDS row primitive `tc variant:"nav"` (§2.5) with `className:"mt-1"` unless it sits under another row. Leading slot holds `FA`.
- **New circle (`FA`):** `span.df-new-circle flex shrink-0 items-center justify-center rounded-full`.
  - Size 18×18 (`--df-new-circle-size`).
  - Background: the variant rule `:where([data-mode=dark]) .dframe-root[data-variant=web] .df-new-circle{background:var(--cds-neutral-150)}` gives gray-750 **`#2c2c2a`**. MEASURED `(44,44,42)`.
  - On row hover: `.dframe-root :is(button,a,.group):hover .df-new-circle{background:color-mix(in srgb, var(--cds-text-muted) 25%, transparent)}`.
  - When the row is selected (focused): transparent.
- **Glyph:** `Add` icon size sm, with `text-secondary group-hover:text-primary group-data-[selected=focused]:text-primary`. The font-size is forced by `.df-new-circle span[style*=font-size]{font-size:var(--df-new-circle-glyph)!important;font-weight:700!important}`: **13 px at weight 700**.
- **Label:** "New" (`min-w-0 truncate`). A `Ws` shortcut chip appears on hover.

### 2.5 Nav rows: Projects (Beta), Artifacts, Customize, More

- **Row primitive** (`mE` + `dE`, `shared-18`):
  - Base: `w-full shrink-0 border-none text-left text-[length:var(--df-row-font)] text-secondary`.
  - Variant `nav`: `flex items-center gap-[var(--df-row-gap)] h-[var(--df-row-h)] px-[var(--df-row-px)] [&_.df-leading-slot]:text-secondary data-[selected=focused]:[&_.df-leading-slot]:text-primary`.
  - States (`dE`): `rounded-[var(--df-radius-pill)] hover:bg-[var(--df-hover)] focus-visible:bg-[var(--df-hover)] data-[selected=focused]:bg-[var(--df-selected)] data-[selected=focused]:text-primary data-[selected=open]:bg-[var(--df-selected)] data-[menu-open=true]:bg-[var(--df-hover)]`.
  - Focus ring (`cE`): `focus-visible:shadow-[inset_0_0_0_1px_var(--cds-fill-accent),0_0_6px_0_color-mix(in_srgb,var(--cds-fill-accent)_20%,transparent)]`.
- **Metrics:**

  | property | value |
  |---|---|
  | height | 26 |
  | horizontal padding | 2 |
  | gap | 4 |
  | radius | 6 |
  | text | 13 px, wght 360, `--cds-text-secondary` `#c3c2b7` |
  | hover background | white 7.5% |
  | selected background | white 15% |
  | selected text and icon | `--cds-text-primary` `#f0efec` |

- **Row spacing:** variant rule `.dframe-root[data-variant=web] .dframe-sidebar-body [data-row]{margin-bottom:.5px}`. The pitch is 26.5; MEASURED 26.4.
- **Leading slot:** `.df-leading-slot{width/height:var(--df-leading-slot)=24; display:flex; center}`. The glyph inside is 16×16, `.df-leading-slot svg{width/height:var(--df-icon-size)}`.
  - Hub rail: `.df-hub-rail .df-leading-slot{margin-left:var(--df-rail-shift)}`, a 4 px left shift.
  - Icons, at size `auto` (sm, 16 px, wght 533.3): Projects `Projects`, Artifacts `Artifacts`, Customize `Tool`. These come from the `AA` list in `shared-23`.
- **Text x offset:** 8 (body) + 2 (row padding) + 4 (rail shift) + 24 (slot) + 4 (gap) = **42**. MEASURED 42.
- **"Beta" badge** (`LZ` in `shared-20`): CDS `Badge` with `variant:"neutral"`, `size:"xs"` and `className:"ml-2"`. The compact xs tokens give:

  | property | value |
  |---|---|
  | height (`h-control-nested`) | 16 |
  | horizontal padding (`px-sm`) | 4 |
  | radius (`rounded-chip` = nested/4) | 4 |
  | background (`bg-neutral`) | white 5% |
  | text | `--cds-text-secondary`; caption xs 10 px, `font-medium` (wght 460) |
  | layout | `inline-flex items-center gap-1 align-middle whitespace-nowrap`, `leading-[round(1.25em,1px)]` |
  | left margin | 8 |

  MEASURED height about 16.
- **"More" row** (`CL`, `shared-21`): nav row whose leading icon is `CaretRight` (size auto, 16) with `className:"opacity-50"`. The label is `span.text-muted` "More" (`#898781`). It opens a hover menu (`openOnHover`, delay 120 ms, close delay 180 ms).

### 2.6 Section labels: "Pinned" and project groups (`UE`, `shared-18`)

- **Label row:** `group/labelrow df-label-inset flex w-full items-center gap-[var(--df-row-gap)] pt-[var(--df-group-pt)] pr-[calc((var(--df-row-h)-24px)/2)] pb-1 text-[length:var(--df-group-font)] leading-4 font-normal font-header text-muted min-h-[calc(var(--df-group-pt)+(var(--df-row-h)-8px)+4px)]`.

  | property | value |
  |---|---|
  | padding-top | 12 |
  | padding-bottom | 4 |
  | padding-right | 1 |
  | padding-left (`.df-label-inset`) | row-px 2 + iconless-pad 8 = **10**, so text sits at x = 18 in the sidebar (MEASURED 18.3) |
  | text | 12 px / 16 line, wght 360, `--cds-text-muted` `#898781` (MEASURED `(141,140,138)`) |
  | min-height | 34 |
  | gap | 4 |

- **Collapsible label:** a toggle button with `group/label -my-1 -ml-1 flex min-w-0 flex-1 items-center rounded-[var(--df-radius-pill)] py-1 pl-1 text-left hover:text-secondary gap-1` and the same accent focus shadow.
  - Name: `span[data-group-name] min-w-0 truncate`.
  - Caret: `CaretRight` size xs (12 px, wght 577.8), `shrink-0 transition-transform duration-fast`. It is visible when collapsed (`opacity-100`). When expanded it is `opacity-0 rotate-90` and becomes visible on section hover or focus.
- **Trailing buttons** in project group headers:
  - **"+" (new session in group)** (`rB`, `shared-21`): wrapper `span.-my-1`.
    - kind `group`: `tB`, a ghost icon-only Button `icon:"Add"` with `className:"df-chrome-btn"`. Size is `xs` in comfortable and default in compact, so **24×24**.
    - kind `section`: the `Xs` wrapper with `Icon name:"Add" size:"auto"` (16). `Xs` classes were not traced (UNKNOWN), and it is not known which kind the screenshot shows.
  - **Filter** (`uX`/`dX`, `shared-20`): ghost icon-only `icon:"Filter"`, size undefined in compact (**24×24**), `className:"df-chrome-btn relative -my-1"`. Shown as the code recents header trailing.
  - **Colours:** `.df-chrome-btn` sets `--cds-text-primary:var(--cds-text-secondary)`, so the icon is `#c3c2b7` (MEASURED `(199,198,194)`). Hover: `--cds-neutral-900` (white) on `--df-hover`. Glyph 16 at 533.3.
  - The `[data-sidebar-group-label] .df-chrome-btn` heading-ink override only applies inside `.df-session-list`. It is not in effect in the classic list, which agrees with the measured secondary colour.

### 2.7 Session rows

- **Row:** primitive variant `session` (`mE` compound, `shared-18`): `flex pl-[calc(var(--df-row-px)+var(--df-row-indent,0px))] pr-[var(--df-row-px)] items-center gap-[var(--df-row-gap)] h-[var(--df-row-h)]`, plus `dE` (radius, hover and selected as in §2.5), plus the `cE` focus ring and `group`.

  | property | value |
  |---|---|
  | height | 26 |
  | padding | left 2 (+ indent), right 2 |
  | gap | 4 |
  | radius | 6 |

- **Leading:** `span.df-leading-slot.text-secondary` (24 px, plus the 4 px rail shift) holding the status glyph from §1.7. MEASURED dot centre at x = 25.8; traced value 8 + 2 + 4 + 12 = 26.
- **Label:** `span[data-row-label] flex-1 min-w-0`, text 13 px, wght 360.
  - Colour `--cds-text-secondary`. When selected (focused): `--cds-text-primary`.
  - Overflow fades instead of using an ellipsis: `[&:where([data-overflowing])]:[mask-image:linear-gradient(to_right,black_calc(100%_-_24px),transparent_100%)]` (`DE`), a 24 px fade at the end. When row actions show on hover, the fade widens: `black calc(100% - 44px) → transparent calc(100% - 20px)` (`OE`, `AE`).
- **Pitch:** row 26, plus `[data-row]` margin-bottom 0.5, plus a 1 px column gap from the `flex-col gap-px` list container (the class the code-list override rule targets) = **27.5**. MEASURED 27.5.
- **Nested (child) rows:** the indent is `--df-row-indent: calc(var(--df-icon-size)+var(--df-row-gap))` = **20** (`iB`/`zq`). MEASURED: the child dot is 20 px right of the parent dot.
- **Hover row actions:** an absolutely positioned cluster `absolute right-[var(--df-row-ctl-inset,calc((var(--df-row-h)-var(--df-row-ctl))/2))] -translate-y-1/2 flex items-center gap-0.5` (right 3, gap 2).
  - Buttons: `df-row-control size-6 flex items-center justify-center rounded-md text-secondary hover:text-primary hover:bg-[var(--df-hover)]`, 24×24 with radius 6.
  - Visibility: opacity 0, and 1 on row hover or focus.
- **Selected row:** background white 15% (`#343434` on `#111`), text `#f0efec`.

### 2.8 Scrolling

- The nav scroller (`.dframe-nav-scroll`) uses `mask-image:linear-gradient(#0000 0,#000 12px)` once scrolled (`[data-scrolled]`), a 12 px top fade.
- The scrollbar seen in the screenshot is the native overlay scrollbar. Its styling is UNKNOWN.

### 2.9 Footer account row (`RN` in `shared-19`; tray rules in `shared-styles`)

- **Tray:**
  - `.df-bottom-tray{margin:-8px -8px -6px;position:relative}`, with `:before{border-top:.5px solid var(--cds-border)}`, a 0.5 px white 10% hairline.
  - Row: `.dframe-root[data-variant=web] .df-bottom-tray>.df-footer-row:last-child{padding:8px}`.
- **Button:** `df-user-menu-btn cds-reset flex h-[max(28px,var(--df-footer-btn-size))] max-w-full items-center gap-[var(--df-row-gap)] rounded-[var(--df-radius-pill)] pl-[var(--df-row-px)] pr-2 text-left outline-none hover:bg-[var(--df-hover)] focus-visible:shadow-focus`.

  | property | value |
  |---|---|
  | height | 28 |
  | gap | 4 |
  | radius | 6 |
  | padding | left 2, right 8 |
  | hover background | white 7.5% |

  MEASURED centre y = 1155.6, which is window height minus 22 (8 + 14).
- **Avatar slot:** `df-on-rail relative flex w-[var(--df-leading-slot)] shrink-0 items-center justify-center` (24 px wide), holding a CDS `Avatar` at size sm with `!size-5`.
  - 20×20, `rounded-full`, `bg-fill-control` (white 10%), `text-primary`.
  - Text 9 px (`text-[calc(0.5625rem…)]`), `font-medium` (460), `leading-none`. One initial is shown at this size ("P").
- **Name:** `whitespace-nowrap text-secondary`, at 13 px (`text-[length:var(--df-row-font)]` on the parent).
- **Suffix:** `·` and the plan name ("Max") as `df-footer-suffix-text text-muted`. The variant rule `.dframe-root[data-variant=web] .df-footer-suffix-text{font-size:calc(var(--df-row-font) - 2px)}` makes it **11 px**.
  - The parent `df-user-menu-trailing flex min-w-0 gap-1 overflow-hidden df-footer-suffix items-baseline` has a 4 px gap. `.df-footer-suffix` has `padding-right:12px` and a 12 px right fade mask.
- **Caret:** `CaretDown` size xs (12 px), `df-user-menu-trailing shrink-0 text-muted`.
- **Right-side aux icon** (`.df-footer-aux`, the small icon at the far right in the screenshot): content and classes UNKNOWN.

## 3. Window title bar (Code session pane)

- **Header strip:** `header.dframe-header h-12 shrink-0 relative isolate z-10`, 48 tall (`shared-18`). It sits on the page background `#151515`, with no divider below it in the screenshot.
- **Session title bar** (`Qf`, `c8782095c`): `epitaxy-titlebar relative flex items-center h-[calc(2rem…)] pl-0 pr-[var(--titlebar-end-inset,12px)] …`. This is a **32** tall row, vertically centred in the 48 px header (MEASURED title centre y = 24.4), with 12 px right padding.
- **Leading origin icon:** a laptop glyph for a local session. MEASURED: 16 px glyph, left edge about 19 px from the content edge, colour about secondary. The class and icon name were not traced (UNKNOWN).
- **Title** (`qt` = `ih` in `shared-6`): `truncate text-body font-medium font-control text-primary select-none`.
  - Colour `#f0efec`, wght 460 (`font-medium` beats `font-control`).
  - Size `--cds-font-size-body`: **13 px** by measurement. Ink width 199.5 matches 13 px at wght 460 (200.8, shaped with HarfBuzz); 14 px would be 216.
  - Wrapper: `flex items-center min-w-[32px]`.
  - Rename input (`rm`): `text-body font-medium font-control text-primary bg-transparent border-0 p-0 rounded-[3px] outline outline-[1.5px] outline-[var(--cds-fill-accent)] outline-offset-[1px] [field-sizing:content]`.
- **Title menu caret** (`om`): ghost icon-only Button with `icon: Icon name:"CaretDown" size:"sm"` (16 px, wght 533.3) and `className` `text-secondary` (`#c3c2b7`).
- **Project chip** ("lookout"): classes UNKNOWN; the component was not located. MEASURED:

  | property | value |
  |---|---|
  | height | about 20 |
  | width | about 52 |
  | text | about 12 px, `--cds-text-secondary`-like |
  | background | about white 5–8% |
  | radius | about 6 |
  | gap after caret | about 12 |

  The size matches a CDS Badge `variant:"neutral"` at comfortable `sm` (`h-control-nested--sm` 20, caption sm 12 px, `rounded-chip` 5), but that is not confirmed.
- **Right cluster** (`Kt` = `Qm` + `Va`): `relative z-[1] epitaxy-titlebar-end ml-auto flex shrink-0 items-center gap-1 ps-[24px] draggable-none [--cds-h-control:26px]`.
  - Each button is a CDS ghost icon-only Button: **26×26**, gap **4**, at least 24 px of space before the cluster. Hover background `--cds-fill-ghost-hover` (white 7.5%), radius `--cds-radius` (6 compact).
  - MEASURED icon pitch 29.8 (26 + 4).
  - Icons observed: terminal (`>_`), diff (`±` in a square), globe (browser), folder, kebab (vertical dots). Glyph size about 16 px; colour MEASURED about `#c3c2b7`, i.e. secondary. Exact icon names and per-button classes are UNKNOWN.

## 4. Quick reference (dark, compact frame, CSS px)

| item | value |
|---|---|
| page bg | `#151515` |
| sidebar bg | `#111111` |
| sidebar edge | 0.5 px, white 10% |
| sidebar width | 288 default (200–420) |
| sidebar padding | 8 sides, 4 top, 6 bottom |
| sidebar title row | 46 tall, 2 px top pad |
| row | 26 h, radius 6, pad 2, gap 4, leading slot 24 (+4 rail shift), glyph 16 at 533.3 |
| row text | 13 px, wght 360, `#c3c2b7` |
| row hover / selected | white 7.5% / white 15% (selected text `#f0efec`) |
| nav pitch / session pitch | 26.5 / 27.5 |
| section label | 12/16, `#898781`, top pad 12, bottom pad 4, left inset 10 |
| status dot | 6 px. Running `#898781` (blinks), awaiting `#fab219`, unread `#2a78d6`, idle = 1 px ring at 50% |
| search field | 26 h, radius 6, white 5% fill, 1 px white 10% inset ring, `#898781` text |
| app switch | 28 h pill, segments 34 wide, track white 5%, thumb white 10% + 1 px ring |
| chrome buttons | 24×24 ghost, `#c3c2b7`, hover white glyph on white 7.5% |
| content header | 48; session title bar 32; title 13 px wght 460 `#f0efec`; right icons 26×26, gap 4 |
| text weights (dark) | 360 regular / 460 medium / 540 semibold / 560 bold; opsz 16; GRAD 0; antialiased |
