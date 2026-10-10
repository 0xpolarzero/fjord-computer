# Claude Code tab: composer and overlay surfaces (dark mode, numeric spec)

Read from Claude's shipped web bundles (`/tmp/claude-web-d/`, the desktop app's cache) and checked against
`docs/design/references/claude-code-tab.jpg` (4112×2580 px, a 2× capture, so 1 pt = 2 px). Every value below
comes from a class string or CSS variable; anything that couldn't be traced says **UNKNOWN**. Unless a section
says otherwise, sizes are CSS px (= macOS points) at `--cds-rem-scale: 1` and **compact** density. The Code tab
runs compact: a composer card measures 44 pt, which matches compact plus the 28 px control override. Menus are
forced compact with `density:"compact"` wrappers in `cc43287c9-*`.

## 0. Sources and build

The cache holds several builds. **The newest build matches the screenshot.** It is the only one with the 14 px
composer radius and 28 px row height; the measured corner radius is ≈ 13.5 pt and the card is 44 pt tall.

| Short name | File |
|---|---|
| CSS (tokens + utilities) | `c6a992d55-Drv_MyUK.css`: the only CSS that has the `[--cds-radius-composer:calc(0.875rem…)]` utility the newest JS uses. Token rules: `:root` / `:where(:root,:host)` / `.cds-root` / dark `@media screen{[data-mode=dark] .cds-root…}` / `[data-size=xs]` |
| Token cross-check | `/tmp/claude-src/.vite/renderer/main_window/assets/MainWindowPage-yE7nSc5c.css` (same ramp and values) |
| ChatComposer (CDS) | `shared-5-D2grcPP-.js` (newest); helper vars in `shared-1-DginuSTZ.js` (same strings as `shared-1-F36TOMAv.js`) |
| Code-tab composer wrapper | `c0e82e24a-bLjWDEyE.js` (newest; older: `c099c328d-CWpEPL4X.js`) |
| Code-tab session view | `cc43287c9-CZKZapce.js` (newest; older: `cc43287c9-Bf_jKSHQ.js`) |
| Code column, dock, branch row, composer overrides | `shared-6-BoBG7Dp0.js` (newest; older: `shared-7-Bpm00-LM.js`) |
| Footer / chin contents | `c82492f2c-QZnRuzoE.js` (newest; older: `cc70f2bdf-D2tjET3U.js`) + `c73f45bc3-JiJn6FcR.js` |
| PR / branch strip | `cb1afaa4b-D5tA6fBW.js` + `shared-7-Bpm00-LM.js` |
| CDS components (Button, SplitDropdownButton, Menu, Popover, Tooltip, MentionDropdown, Dialog) | `shared-frame-BAME2HDg.js` (newest; same strings as `shared-frame-CZdrar-k.js`) |
| ModelSelector / ModelSelectorEffort | `shared-8-BLHirzVQ.js` |
| Slash-command menu | `shared-5-OvqWVY2h.js` (container) + `ccc334009-CRxN9eWx.js` (rows) |
| Toast | `shared-common-mcp-msg-6-Cmbl7lDQ.js` |
| Epitaxy (Code tab) CSS | `shared-styles-CL-_MuPW.css` |

## 1. Resolved dark tokens (everything below uses these)

Source: big CSS `.cds-root{…}`, overridden by the dark block `@media screen{[data-mode=dark] .cds-root…{…}}`.

**Gray ramp:** 0 `#ffffff`, 50 `#f0efec`, 100 `#e1e0d9`, 200 `#c3c2b7`, 300 `#a5a49a`, 400 `#898781`,
500 `#6d6b67`, 600 `#52514e`, 700 `#383835`, 750 `#2c2c2a`, 800 `#20201f`, 810 `#1e1e1d`, 830 `#1a1a19`,
850 `#151515`, 870 `#111111`, 900 `#0b0b0b`. Dark `--cds-neutral-900` = `#ffffff`, so every alpha step is white.

| Token | Dark value |
|---|---|
| `--cds-surface-0` / `--cds-page-bg` | `#0b0b0b` (gray-900) |
| `--cds-surface-1` | `#151515`. The screenshot's transcript background is exactly `#151515`; the Code-tab column paints surface-1 (the `--cds-page-bg:var(--panel-card-surface,var(--df-sidebar-bg,var(--cds-surface-1)))` utility exists; which element sets it is UNKNOWN) |
| `--cds-surface-2` / `--cds-surface-panel` | `#1a1a19` |
| `--cds-surface-3` / `--cds-surface-popover` / `--cds-tooltip-bg` | `#20201f` |
| `--cds-alpha-1/2/3/4/5` | white 5% / 10% / 20% / 35% / 50% |
| `--cds-border`, `--cds-ring-color`, `--cds-fill-secondary`, `--cds-fill-field-ring` | white 10% |
| `--cds-border-strong` | white 20% |
| `--cds-fill-secondary-hover` | white 14% |
| `--cds-fill-ghost-hover` | white 7.5% |
| `--cds-fill-secondary-ring` | transparent |
| `--cds-text-primary` / `--cds-tooltip-fg` | `#f0efec` |
| `--cds-text-secondary` | `#c3c2b7` |
| `--cds-text-muted` | `#898781` |
| `--cds-text-disabled` | white 35% |
| `--cds-text-accent` | `#6da7ec` |
| `--cds-fill-accent` | `#2a78d6` |
| `--cds-text-git-added` / `--cds-text-git-removed` | `#32d74b` / `#ff2c56` |
| `--cds-text-git-merged` / `--cds-text-git-queued` (modified) | `#b796ff` / `#ffd014` |
| `--cds-fill-brand` / hover / `--cds-on-brand` | `#c6613f` / `#d97757` / `#ffffff` |
| `--cds-text-warning` / `--cds-bg-warning` / `--cds-border-warning` | `#db9300` / `#311a00` / `#512e00` |
| `--cds-text-danger` / `--cds-bg-danger` / `--cds-border-danger` / `--cds-fill-danger` | `#ec7e7e` / `#3c0e0e` / `#641919` / `#d03b3b` |
| `--cds-black` | `#000000` |
| `--cds-shadow-color` | `#0000003d` (black 24%) |
| `--cds-shadow-sm` | `0 1px 2px 0 rgba(11,11,11,.06), 0 2px 8px 0 rgba(0,0,0,.24)` |
| `--cds-shadow-md` | `0 2px 4px 0 rgba(11,11,11,.07), 0 6px 16px 0 rgba(0,0,0,.24)` |
| `--cds-shadow-lg` | `0 4px 8px 0 rgba(11,11,11,.08), 0 12px 28px -2px rgba(0,0,0,.24)` |
| `--cds-shadow-popover` | `0 8px 24px rgba(0,0,0,.32), 0 2px 6px rgba(0,0,0,.20)` (`#00000052`, `#0003`) |
| `--cds-ring-inner` / `--cds-ring-outer` | `1px` / `0px` |
| `--cds-focus-shadow` (dark) | `inset 0 0 0 1px <page-bg>, 0 0 0 1px #2a78d6, 0 0 6px 1px rgba(24,79,149,.6)` |
| `--cds-opacity-disabled` | `0.4` |
| `--cds-backdrop` | `#00000080` |
| Durations / easing | fast 60 ms, snap 120 ms, base 200 ms; `--cds-ease-out` = cubic-bezier(.165,.84,.44,1); `--cds-ease-snap` = cubic-bezier(.32,.72,0,1) |

**Compact sizes** (`.cds-root`):

| Token | Value |
|---|---|
| `--cds-radius` (`rounded`) | 6 |
| `rounded-card` | radius + 4 = 10 |
| `--cds-radius-composer` | 12 |
| `--cds-h-control` | 24 |
| `--cds-h-control-nested` | 18 |
| icon `auto` | 16 (sm) |
| pad xs / sm / md / lg / xl | 4 / 6 / 8 / 12 / 20 |
| gap xs / sm / md / lg / xl | 6 / 8 / 12 / 20 / 32 |
| caption | 11/17 |
| footnote | 12/15 |
| code | 12/17, mono |
| body | 13/19 |
| prose | 14/20 |
| heading | 14/18 |

**`[data-size=xs]` scope:** radius 5, h-control 20, nested 16, `--cds-icon` 12, pad-md 6, pad-sm 4, body 12/17,
caption 10. Tailwind radii: `rounded-sm` 4, `rounded-md` 6, `rounded-lg` 8, `rounded-xl` 12. Spacing unit is 4 px.

**Icon component sizes** (`Ja` in shared-frame): xs 12, sm 16, md 20, lg 24, xl 28, xxl 32. `auto` resolves
to sm (16) in compact and md (20) in comfortable; `auto-sm` steps one size down (12 in compact). A Button's
icon is `auto`, except in xs/xxs button sizes, where it is `auto-sm`.

**Fonts:**

- Sans: `anthropic-sans`, the variable font the app ships as `AnthropicSans-Roman-Variable`, weight axis 300–800.
- Mono: `--cds-font-mono` = `"anthropic-mono", ui-monospace` (web-hosted woff2; on macOS the fallback is SF Mono).
- Dark-mode weights go through `font-variation-settings` (big CSS `:where([data-mode=dark] .cds-root…) .font-normal`):
  regular `"wght" 360`, medium `"wght" 460`, semibold `"wght" 540`, bold `"wght" 560`. The CSS `font-weight`
  values stay 400 / 500 / 580 / 600. In light mode the axis is `normal`.

## 2. Composer dock (placement)

- **Column** (`shared-6-BoBG7Dp0` `vh`/`Sh`):
  `mx-auto max-w-[calc(var(--max-content-width)+gutter-start+gutter-end)] ps-[gutter-start] pe-[gutter-end]`.
  - `--max-content-width` = `var(--chat-column-measure, 768px)`. With `[data-transcript-width=m]` it is 960; with `l` it is 1280.
  - Gutters = `var(--chat-gutter, 32px)` each. Below a 560 px tile the gutter is 16 (`[@container_tile-slot_(max-width:560px)]:[--chat-gutter:16px]`).
  - The composer, the branch strip and the transcript share the same column width.
  - In the screenshot that width is **841 pt** (x 760.5→1601.5 pt), so a `--chat-column-measure` or tile measure was in effect. Its exact derivation is UNKNOWN.
- **Dock stack** (`qh`/`Wh`): `flex flex-col gap-1.5` (6 px between dock rows: approval cards, branch strip, composer).
  Measured gap between strip and card: 6.5 pt. CDS `ChatComposerDock` itself: children other than items get
  `margin-bottom: var(--cds-gap-xs)` = 6 (big CSS `.cds-root [data-cds=ChatComposerDock]>:not(…,:last-child)`); class
  `pointer-events-none flex w-full min-w-0 flex-col`; dock item `flow-root pb-[var(--cds-gap-xs)]`.
- **Bottom margin:** the source class is UNKNOWN. Measured: the chin's bottom edge sits about 12 pt above the window bottom.
  In the screenshot the field's bottom is at y = 1252 pt and the window is 1290 pt tall. The chin (§6) adds 6 + 20.

## 3. Context strip above the field (branch / PR row)

Source: `shared-6-BoBG7Dp0` `Eg`/`Cg`/`xg`, the same strings as `shared-7-Bpm00-LM` `El`/`Cl`/`xl`. Contents are in
`cb1afaa4b-D5tA6fBW` (`ro`, `no`, `eo`, `to`).

- **Row:** `flex items-center gap-[5px] w-full min-h-[40px] p-[8px] rounded-[10px] bg-alpha-1 @container/branch-row`.
  - Height 40, padding 8 on all sides, radius 10, gap 5.
  - Background white 5% over `#151515` = **`#212121`** (sampled `#212121`). The row has no border.
  - Accent variants: purple `bg-git-merged`, yellow `bg-git-queued`, blue `bg-accent-muted`.
- **Repo name + branch:** chip `inline-flex h-control min-w-0 items-center px-1.25 text-body font-normal`.
  That is height 24, horizontal padding 5, 13/19.
  - Repo: `epitaxy-branch-repo … text-muted max-w-[160px] shrink`.
  - Branch: `truncate font-mono-ui` + `text-muted`. Mono, 13 px (inherits `text-body`), `#898781`.
  - Newer chip wrapper: `flex-1 flex items-center gap-0 min-w-0 @container/branch-chip text-body`.
  - Sampled text `#8e8e8c`.
- **PR number (when there is a PR):** `min-w-0 truncate [direction:rtl] px-1.25 text-body tabular-nums` in muted, after a 16 px state glyph.
- **Diff chip `+840 −339`:** `inline-flex h-control shrink-0 items-center whitespace-nowrap rounded text-body font-normal text-primary bg-fill-secondary shadow-field`, plus `gap-1 px-md`.
  - Height 24, radius 6, horizontal padding 8, gap 4.
  - Fill white 10% (over the strip: `#373737`, sampled `#373737`).
  - `shadow-field` = `inset 0 0 0 1px transparent, 0 1px 2px 0 rgba(0,0,0,.05)`.
  - Digits: `tabular-nums text-body-medium`, 13/19, medium (`wght` 460 in dark). Signs are literal `+` and `−` (U+2212).
  - `+n` in `#32d74b`, `−n` in `#ff2c56`.
- **Create PR split button:** CDS `SplitDropdownButton`, default variant `secondary`, joined (`shared-frame` `iE`, `VT`, `LT`, `HT`).
  - Primary segment: Button `secondary`, h 24, `px-md` 8, `rounded` 6 with `rounded-e-none`, `text-body font-normal text-primary`, `bg-fill-secondary`, `shadow-field`.
  - Seam: `relative w-px self-stretch bg-fill-secondary`, with an inner line `absolute inset-x-0 inset-y-[4px] bg-border` (1 px, white 10%, inset 4 top and bottom).
  - Caret segment: icon-only `CaretDown`, style `{aspectRatio:auto, paddingInline:4}`. Caret size `jy(compact, base)` = **xs, 12 px**, `text-muted`. Segment width 4 + 12 + 4 = 20.
  - Hover fills white 14%. When disabled the whole group is opacity 0.4; the screenshot shows the disabled state (bg `#2a2a2a`, text `#7a7879`).
  - Ghost-row placeholder geometry (`cb1afaa4b` stale row): label `px-md`, divider `w-px … inset-y-[4px] bg-border`, caret box `aspect-square w-control` (24).
- **Close ×:** `dismissable` reserves `aspect-square w-control shrink-0` (24×24).
  - The live control's icon name is UNKNOWN. Presumably a ghost icon-only Button (transparent, hover white 7.5%, radius 6).
- **Trailing cluster:** `epitaxy-branch-trailing contents`. Gaps come from the row's `gap-[5px]`.

## 4. Composer card (editor box)

**Base:** CDS `ChatComposer` card (`shared-5-D2grcPP-` `un`; helpers `shared-1` `ts`/`ns`/`os`/`_s`):

```
bg-surface-3 [--cmp-pad-x:0.5rem] relative z-[1] flex w-full min-w-0 flex-col text-primary rounded-composer
px-[var(--cmp-pad-x)] py-2 [--cmp-gap-y:0.375rem] gap-y-[var(--cmp-gap-y)]
<type vars> shadow-composer hover:…:shadow-composer-hover focus-within:shadow-composer-focus cursor-text
transition-[background-color,border-color,box-shadow,opacity] duration-200
```

**Code-tab override:** single-row "picker row" card. `cc43287c9-CZKZapce` passes
`rootClassName: xo` = `shared-6` `yg`:

```
[--cds-h-control:calc(1.75rem*…)] [--cds-radius-composer:calc(0.875rem*…)] [--cmp-font-size:var(--prompt-text-size)]
```

`.epitaxy-root{--prompt-text-size:.875rem}`. With `[data-chat-text-size=s]` it is .8125rem; with `l` it is .9375rem.

| Property | Value |
|---|---|
| Width | 100% of the composer column (841 in the screenshot) |
| Background | `--cds-surface-3` **`#20201f`** (sampled `#202020`) |
| Radius | **14** (Code-tab override; plain CDS default is 12). Measured ≈ 13.5 pt |
| Padding | x = `--cmp-pad-x` 8, y = `py-2` 8 |
| Row geometry | type size = max(entry floor 0, 14) = **14**; leading = round(14×1.4) = **20**; row-py = (28−20)/2 = 4; row-h = 28 |
| Min height | 8 + 28 + 8 = **44** (measured 44 pt). Root also has `min-h-[calc(var(--cds-h-control)+var(--spacing)*4)]` = 44 (`mg`) |
| Border / ring | **None as a border.** `shadow-composer` = `inset 0 0 0 1px rgba(255,255,255,.10), 0 4px 20px rgba(0,0,0,.035)` |
| Hover ring | `shadow-composer-hover` = `inset 0 0 0 1px rgba(255,255,255,.20), 0 4px 20px rgba(0,0,0,.035)`. Not applied while hovering a button, link or label inside the card |
| Focus ring | `shadow-composer-focus` = `inset 0 0 0 1px rgba(255,255,255,.20), 0 4px 20px rgba(0,0,0,.075)` (`--cds-border-strong`). No accent ring |
| Transition | 200 ms on bg / border / box-shadow / opacity |
| Text | Anthropic Sans 14/20, `font-normal` (dark `wght` 360), `text-primary` `#f0efec` |
| Placeholder | "Type / for commands"; same 14/20, `text-muted` **`#898781`** (sampled `#8d8d8d`), single-line `truncate` (`placeholderFit: "clamp"`) |
| Text inset | No in-card leading actions, so `startInset = "text"` and the editor adds `pl-[4px]` (compact). Text starts 8 + 4 = **12** from the card edge (measured ≈ 13 pt) |
| Max height | Editor `maxHeight: "min(24rem, 40svh)"` (`c0e82e24a` `Lt`), so ≤ 384 px, about 19 lines at 20 px. CDS editor class also has `max-h-96 overflow-y-auto break-words` |
| Min lines | 1 (Code tab passes `editorMinLines` only for new-session drafts: 2) |
| Multi-line | Card switches to `data-multiline` once text wraps. Actions then sit on their own row: `pb-[calc(var(--cds-h-control)+var(--cmp-gap-y))]` = 28 + 6 |
| Inline code in prompt | `epitaxy-root div.ProseMirror :not(pre)>code`: `color #ec7e7e`, bg white 5%, `.5px solid` white 10%, mono `.928571em`, radius .4em, padding `.0625em .25em` (shared-styles) |

The older CDS-shell variant (`shared-7-Bpm00-LM`) used `relative isolate min-h-11 rounded-[10px]` with chrome
`bg-surface-3 epitaxy-composer-chrome`, which epitaxy CSS gives the shadow
`inset 0 0 0 1px rgba(255,255,255,.08), 0 2px 8px 0 rgba(0,0,0,.12)` (focus: 16%, `0 6px 16px`).
The screenshot's 14 px corner rules this variant out.

## 5. Send / stop button

Source: `c0e82e24a` `pd`, `Ku`, and Button `zc`/`Bc` in shared-frame.

- **Send:** Button `variant:"ghost"`, `iconOnly`, icon **`ArrowReturn`**, `tooltip:false`. The tooltip wrapper says "Send ⏎" (`shortcut:"enter"`).
  - Ghost Button: `rounded h-control aspect-square w-control px-0`, so **28×28** inside the card (h-control 28), radius 6.
  - Background transparent; hover white 7.5%. Icon `auto` = 16 px, `text-primary`.
  - When it can't send: `opacity-disabled` (0.4) with `aria-disabled`.
- **Stop:** Button ghost icon-only, icon **`StopCircle`**, 28×28, 16 px glyph, `text-primary` (sampled `#f3f3f3`).
  - Tooltip "Stop", shortcut `escape`. Shown while the session is busy.
  - When a draft exists mid-turn, send sits beside stop: `ml-2` from the CDS primary-action recipe.
- **Placement:** actions are `absolute bottom-0 right-0 flex items-center gap-xs pl-1.5 min-h-[var(--cmp-row-h)]`, so the right edge is 8 from the card edge.
  The send cell is `grid shrink-0 items-center justify-items-end`.
- The generic CDS default (`variant:"brand"`, `ArrowUp`, fill `#c6613f`) is **not** used in the Code tab.

## 6. Footer / chin row (below the card)

Two Code-tab layouts exist (`c82492f2c-QZnRuzoE` `Jr`):

- **"chin" layout:** the screenshot's contents, `+ mic ⌄ Auto … Opus 5.5 Medium ◔`.
- **"row" layout:** used with the picker-row card. Only the mode picker sits on the left; plus/mic move into the card.

**ChatComposerChin**

Container (`shared-5` `Df`):

```
relative z-0 overflow-clip px-2 -mx-2 pt-2 -mt-2 @container [--cmp-pad-x:0.5rem] … pb-2 -mb-2
```

Inner row:

```
flex min-h-control items-center gap-0 text-footnote font-normal text-secondary mt-1.5
ps-[calc(var(--cmp-chin-start)-touch)] pe-[calc(var(--cmp-chin-end)-touch)] [--cmp-chin-row-h:var(--cds-h-control--xs)]
@max-[25rem]:text-caption [&_[data-cds=Button]:not([aria-pressed=true])]:text-secondary [&_[data-cds=Button]]:font-normal
```

It carries `data-size="xs"`.

- Top gap to the card: **6** (`mt-1.5`). Row min height: **20** (xs h-control).
- Default text: 12/15, `text-secondary` `#c3c2b7`, regular. In the screenshot "Auto" samples `#c6c7c2`.
- Leading padding `--cmp-chin-start` (first item is a glyph, card start-inset is "text") = pad-x − 1 = **7**.
- Trailing padding `--cmp-chin-end` (last item is a glyph) = pad-x + 2 = **10**.
- Leading group: `flex items-center self-start`. Trailing group: `ms-auto flex min-w-0 items-center gap-1 ps-2` (gap 4, leading padding 8).
- Open/close animation: grid rows 0fr→1fr over 280 ms ease-out; content `-translate-y-1.5` and opacity 0→1.

**Leading items, in order** (chin layout `un`, `Be`, `Sn`):

1. **Plus (+):** attach / plus menu. Props `{size:"base", dockGlyph:true}` (`cde6354a0` `Ua`). Ghost icon-only; icon class
   `text-secondary group-hover/btn:text-primary group-aria-pressed/btn:text-accent` (`Wa`); icon size `auto` → 16.
   - With `size:"base"` the button is not xs: 24×24, radius 6 (an inference from `size:"base"`; the exact box is UNKNOWN).
2. **Microphone:** dictation. Ghost icon-only, `Microphone`, same icon class. The `⌄` next to it is the
   device-switch caret (dictation SplitDropdown when dictation is available). Group: `flex shrink-0 items-center gap-xs empty:hidden` (gap 6, squared seam).
3. **Mode picker ("Auto"):** Menu trigger rendering Button `variant:"ghost"`, class `min-w-0 shrink`.
   - Label `overflow-x-clip text-ellipsis whitespace-nowrap` (`text-warning` when flagged).
   - In the xs chin: h 20, `px-md` 6, radius 5, 12/17 `text-secondary`, regular.
   - Hover fill white 7.5%. Its menu header reads "Mode".

**Trailing items** (`Gn`, wrapped in `grid min-w-0 grid-flow-col auto-cols-[minmax(0,max-content)] items-center gap-1`):

- Optional footer indicator Badge (`neutral`, `sm`, `max-w-[12ch]`, prefixed "◆").
- **ModelSelector ("Opus 5.5"):** `TriggerButton variant:"ghost" data-cds="ModelSelector"`, class `min-w-0 max-w-full`.
  - Label `truncate`. Qualifiers (fast/thinking) are `text-muted`, hidden under 280 px.
  - Because its `data-cds` is `ModelSelector`, not `Button`, the chin's text-secondary override does **not** apply. It stays `text-primary` `#f0efec` (sampled `#f4f4f4`), 12/17 regular, h 20, `px-md` 6.
  - Popup class `max-w-[min(26rem,var(--available-width))]`.
- **ModelSelectorEffort ("Medium"):** Button `variant:"ghost"`, `min-w-0 shrink-0`, label `min-w-0 truncate`, `text-primary` (sampled `#f2f2f2`). Optional `Warning` xs icon.
- **Context ring (◔):** ghost icon-only Button `shrink-0`. The icon is a ring with track `--cds-alpha-2` (white 10%) and a configurable stroke.
  - Sampled stroke ≈ `#3f78cf`, consistent with `--cds-fill-accent` `#2a78d6`. The exact stroke token is UNKNOWN.
  - Opens a usage popover.

**"row" layout overrides** (picker-row card):

- Chin className `-mt-1 compact:-mt-1 -mb-2.5`.
- Leading wrapped in `flex items-center ms-0.5`.
- Trailing gets `compact:me-1`.
- Both get `[--cds-h-control:1.5rem] [--cds-pad-md:.375rem] [--cds-font-size-body:.8125rem] [--cds-leading-body:1.25rem]`: controls 24 high, padding 6, 13/20 text.

## 7. Suggestion popovers

**@-mention dropdown**

Source: CDS `MentionDropdown`, `shared-frame` `yT`/`vT`, Code-tab wrapper `c099c328d` `mp`.

- Popover popup:
  - Surface: `rounded-card bg-surface-3 shadow-panel`. Radius **10**, bg **`#20201f`**, shadow `inset 0 0 0 1px rgba(255,255,255,.10), 0 8px 24px rgba(0,0,0,.32), 0 2px 6px rgba(0,0,0,.20)`.
  - Class `max-h-[min(var(--available-height),384px)] max-w-none select-none`, padding none.
  - Placement: side top, align start, sideOffset **24** from the caret, collisionPadding 16.
- Width (Code tab `cp`): **420** base and grouped, **560** when any option has a description. CDS defaults are 240 / 420 / 576.
- List: `p-1` (4 px).
- **Row** (menu item recipe `qv` + `text-left`):
  `cds-reset flex w-full items-center gap-xs px-2 py-[calc((var(--cds-h-control)-var(--cds-leading-body))/2)] rounded text-body font-normal`.
  - Height **24** (19 + 2×2.5), horizontal padding 8, gap 6, radius 6.
  - Text 13/19 regular `text-primary`.
- **Highlighted row:** `data-[highlighted]:bg-fill-ghost-hover`, white 7.5% (≈ `#313130` over `#20201f`).
- Leading icon slot: `flex size-icon shrink-0 items-center justify-center overflow-hidden`, 16×16. Code-tab icons: File, Folder, Agent, ChatSimple, Chats, Artifacts, avatar.
- Label: `truncate text-primary`.
- Secondary: `truncate text-caption text-muted`, 11/17 `#898781`, in `flex min-w-0 flex-1 items-baseline gap-xs`.
  - For file paths, the matched path part is wrapped in `text-secondary` (`fp`).
- Group header: `px-2 py-1 text-footnote font-medium text-muted flex items-center gap-xs select-none`, 12/15 medium `#898781`.
- Hover tooltip per row: side right, offset 8, delay 200 ms, `max-w-[360px]` when there is a description.

**/ slash-command menu**

Container `shared-5-OvqWVY2h` `yC`; rows `ccc334009-CRxN9eWx`.

- Surface: `popover` recipe (same as above: radius 10, `#20201f`, `shadow-panel`) + `flex flex-col min-w-60 max-w-lg max-h-96`. Width 240–512, max height 384.
- Anchored top-start of the caret: vertical offset **10**, horizontal −16. Viewport padding 8.
- Rows use the same menu-item recipe: 24 high, `px-2`, gap 6, radius 6, highlight white 7.5%.
  - Icon slot `size-icon` 16 (skills dimmed `opacity-50`).
  - Label `min-w-0 flex-1 truncate`; query matches `font-semibold` (`wght` 540 in dark).
  - Alias `text-muted`. Subtitle / suffix `ml-auto shrink-0 pl-2 text-caption text-muted` (11 px).
  - Submenu caret `CaretRight` sm, `text-muted`. Check `Check` in `text-accent`.
- Section header: `px-2 py-1 text-footnote font-medium text-muted`. Separator: `mx-2 my-1 h-px bg-border` (1 px white 10%).
- Loading skeleton row: `flex h-control items-center gap-xs px-2` (20×20 + 128×16 bars). At most 11 visible skeleton rows.
- Submenu: placement right-start, offset −8 / 0, max height 384.

## 8. Generic Menu / dropdown

Source: `shared-frame` `gv`, `qv`, `Ey`, `uv`. Code-tab menus are wrapped in `density:"compact"`.

- **Popup:** `cds-reset group/menu-popup relative flex flex-col min-w-[128px] max-w-[320px] max-h-[var(--available-height)] rounded-card bg-surface-3 shadow-panel text-body font-normal text-primary`.
  - Width 128–320, radius 10, bg `#20201f`.
  - Shadow `inset 0 0 0 1px rgba(255,255,255,.10), 0 8px 24px rgba(0,0,0,.32), 0 2px 6px rgba(0,0,0,.20)`.
  - Scroll body `p-1` (4 px), `scroll-fade-y`.
  - Max visible height per row = max(h-control, leading-body) = 24; list = n×24 + 8.
- **Item:** `flex w-full items-center gap-xs px-2 py-[calc((24-19)/2)] rounded text-body font-normal font-control`.
  - 24 high, horizontal padding 8, gap 6, radius 6, 13/19.
  - Default `text-primary`; highlighted `bg-fill-ghost-hover` (white 7.5%).
  - Danger variant: `text-danger`; highlighted `bg-fill-danger` `#d03b3b` with `text-on-danger` white.
  - Disabled: opacity 0.4.
- **Item trailing:** hint / detail `max-w-[160px] shrink-0 truncate text-footnote text-muted` (12 px `#898781`) inside `ml-md flex shrink-0 items-center gap-xs` (margin 8). Shortcut caps use ink `--cds-text-muted`.
- **Group label / header:** `px-2 py-1 text-footnote font-medium text-muted`, 12/15 medium, height 23.
- **Separator:** `mx-2 my-1 h-px bg-border`. 1 px white 10%, inset 8, 4 above and below.
- **Default placement:** Popover side `"bottom"`, sideOffset **6**. Footer chin menus open `side:"top"`.

## 9. Tooltip

Source: `shared-frame` `tf`, `Ed`, `Zd`, `Ad`, `Od`.

- **Box:** `rounded-[0.375rem] bg-[var(--cds-tooltip-bg)] text-[var(--cds-tooltip-fg)] shadow-sm dark:shadow-panel-sm text-[0.8125rem]/[1.125rem] font-normal px-2`.
  - Radius **6**, bg **`#20201f`**, text **`#f0efec`** 13/18 regular (dark `wght` 360).
  - Horizontal padding **8**.
  - Dark shadow `inset 0 0 0 1px rgba(255,255,255,.10), 0 1px 2px rgba(11,11,11,.06), 0 2px 8px rgba(0,0,0,.24)`.
- **Single line:** `inline-flex items-center gap-2 min-h-[1.5rem] max-w-[240px] py-[0.1875rem]`. Min height 24, vertical padding 3, gap 8 before a shortcut, max width 240.
- **Multi-line / with detail:** `flex flex-col gap-0.5 max-w-[240px] whitespace-normal py-1.5` (vertical padding 6, gap 2). `text-balance`.
- **Shortcut:** keycap chips after the label (`$o` keys). Detail / secondary hint lines are muted (exact class UNKNOWN).
- **Timing:** delay **300 ms** (mention rows 200 ms), side **top**, sideOffset **4**, hoverable.
- **Animation:** opacity + scale 0.98 → 1, `duration-snap` (120 ms) `ease-snap`.

## 10. Toast

Source: `shared-common-mcp-msg-6-Cmbl7lDQ`.

- **Viewport:** `fixed right-4 bottom-4 flex w-[360px] max-w-[calc(100vw-2rem)] flex-col-reverse gap-md`. 16 from the right and bottom, width 360, gap 12.
  - Stacked toasts: `translateY(index × −14px) scale(1 − index × 0.04)`, 200 ms ease-out.
- **Surface:** `rounded-card bg-surface-3 shadow-panel` + `shadow-panel-md`. The md shadow wins: `inset 0 0 0 1px rgba(255,255,255,.10), 0 2px 4px rgba(11,11,11,.07), 0 6px 16px rgba(0,0,0,.24)`.
  - Radius 10, bg `#20201f`.
  - Warning: `bg-warning` `#311a00` + inset ring `#512e00`, text `#db9300`.
  - Danger: `#3c0e0e` + ring `#641919`, text `#ec7e7e`.
- **Content:** `flex items-start gap-sm px-lg py-md text-body font-normal`. Padding 12 × 8, gap 8, 13/19.
  - Icon: `Info` / `Warning` / `WarningCircle`, size md **20**; neutral icon in `text-secondary`.
  - Title `font-medium`; description below.
  - Dismiss: `-mx-1 -mb-1 -mt-0.5 shrink-0 rounded p-1 hover:bg-fill-ghost-hover`, icon `X` 16.
- **Duration:** minimum **6000 ms** (`EC=6e3`; shorter requested durations are raised to 6 s).

## 11. Banner (inline notices)

Source: `shared-frame` `Banner`.

- **Neutral:** `bg-surface-1 text-primary shadow-card-ring`. Bg `#151515`, inset 1 px white 10%, radius `rounded-card` 10.
- **Warning / danger:** `bg-warning text-warning shadow-ring-warning` and `bg-danger text-danger shadow-ring-danger` (colours as in §10).
- **Body:** `gap-xs py-md font-sans text-body font-normal`, padding `px-md` (8) or `px-lg` (12).
- **Composer notices / queued messages:** only the dock spacing rule is traceable (§2). Their own styling is **UNKNOWN**.

## 12. Dialog (for completeness)

`shared-frame` `cg`/`og`:

- Centred `fixed left-1/2 top-1/2 … w-[calc(100vw-2rem)]`.
- Surface `rounded-card bg-surface-3 shadow-panel shadow-panel-lg`: radius 10, `#20201f`, `inset 1px white 10% + 0 4px 8px rgba(11,11,11,.08), 0 12px 28px -2px rgba(0,0,0,.24)`.
- Backdrop `bg-backdrop` `#00000080`.
- Text 13/19 primary. Code-tab dialogs are wrapped in `density:"comfortable"`.

## 13. Button reference (used by everything above)

`shared-frame` `Oc` / `Ac`: `group/btn relative isolate inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap rounded h-control font-sans text-body`.

- Text button: `px-md`. Icon button: `aspect-square w-control px-0`. The paint layer is an absolute span with `rounded-[inherit]`.
- **Ghost:** transparent, hover / open `bg-fill-ghost-hover` (white 7.5%), text `text-primary`, `font-normal`. Pressed text `text-accent`.
- **Secondary:** `bg-fill-secondary` (white 10%), hover white 14%, `shadow-field` (`0 1px 2px rgba(0,0,0,.05)` + transparent inset ring).
- **Disabled:** opacity 0.4. **Focus-visible:** `--cds-focus-shadow`. Transition: shadow, 60 ms.
- Icon inside a text button gets `-ms-1` (start) or `-me-1` (end).
