# Claude Code tab: forms, plan approval, permission cards, buttons (dark mode spec)

All values below were read from Claude's shipped web bundles in the desktop app's cache. Nothing is guessed: each value is traced to a class string and a CSS rule. Anything that couldn't be traced is marked **UNKNOWN**.

## 0. Sources and conventions

**Build.** Re-verified against the current build (2026-10-09 21:25). Every file cited below is on `/tmp/specwork/current.txt`.

| Short name | File (current build) | What it holds |
|---|---|---|
| `MAIN` | `/tmp/claude-web-d/c1c1ec7b9-DU5lyQpQ.js` | Approval host (picks the AskUserQuestion layout), plan card, permission card + body, inline CSS strings (`.epitaxy-radio-mark`, `.epitaxy-question-card`, `.epitaxy-answer-option`, `.epitaxy-approval-actions`) |
| `QCARD` | `/tmp/claude-web-d/c2f6611a3-EupEyHw3.js` | AskUserQuestion: dock card (export `n`, imported as `Tme`) and inline card (export `t`, imported as `UT`), option row, `KO` (now `lt`), `bk` (now `kt`), `yk` (now `Ot`), radio mark |
| `CARD` | `/tmp/claude-web-d/c2d1aeb56-DV24YGQL.js` | Approval card shell, body, placement context (`r("dock")`, the `"card"` provider), class constants formerly `Ql`, `$l`, `Zl`, `eu` |
| `HOST` | `/tmp/claude-web-d/shared-13-DaZlZESq.js` | Card host queue "ghost" stack (`Ky=2`, `Jy=6`, `qy=.03`) |
| `HDR` | `/tmp/claude-web-d/shared-5-D2grcPP-.js` | Card header `wN` (formerly `AS` / `$c`) |
| `ACT` | `/tmp/claude-web-d/shared-10-p2sUQDxj.js` | Approval actions row and action button (formerly `Cu` / `wu`) |
| `CDS` | `/tmp/claude-web-d/shared-frame-BAME2HDg.js` | CDS components: Button (root cva `Nl`, paint cva `Fl`), Shortcut/Kbd, Checkbox, RadioGroup, Switch, SegmentedControl, SplitDropdownButton, ButtonGroup, TextArea, TextLink, Icon sizes, CDS `Root` |
| `PANES` | `/tmp/claude-web-d/cb1afaa4b-DwQCLcnF.js`, `/tmp/claude-web-d/cc43287c9-CZKZapce.js` | `EpitaxyInlineApprovalHost` and the session body that chooses `presentation:"card"|"dock"` |
| `FRAME` | `/tmp/claude-web-d/shared-22-CuhAVIje.js`, `/tmp/claude-web-d/shared-l-m-0-VOJMFcoz.js`, `/tmp/claude-web-d/shared-17-C94HnSsM.js`, `/tmp/claude-web-d/shared-styles-B1jXfLTX.css` | App frame, sidebar density, chat column |
| `CSS` | `/tmp/claude-web-d/c6a992d55-Drv_MyUK.css` | Tailwind v4 utilities and CDS tokens (unchanged file) |
| `ICSS` | Inline `<style>` strings in `MAIN`, ids `c031798b2` and `c9bddf7be` | `.epitaxy-question-card`, `.epitaxy-answer-option`, `.epitaxy-radio-mark`, `.epitaxy-approval-actions` |

**Identifier names.** The short minified names used in the sections below (`XO`, `Sk`, `YO`, `KO`, `Ql`, `$c`, `Cu`, `Vc`, …) are from the earlier build `c1c1ec7b9-1y55QW_K.js`. Minified names change every build; the class strings don't. Every class string and CSS rule cited in this document was searched for verbatim in the current files (about 90 strings).

### 0.0 Changes found in the current build

1. **Button text weight hook.** Every Button variant now also carries `font-control`. Old: `primary: "text-on-primary font-medium [--cds-shortcut-cap-ink:currentColor] …"`. New: `"text-on-primary font-medium font-control …"`; secondary, ghost, danger and brand likewise. `.font-control{--_cds-font-weight-role:var(--cds-font-weight-control); --_cds-font-axis-wght-role:var(--cds-font-axis-wght-control)}` in `CSS`.
   - `--cds-font-weight-control` and `--cds-font-wght-control` are `initial` on `.cds-root`, so the role variables are invalid and the `var()` fallbacks apply.
   - **Effective values don't change:** medium 500 (dark `wght` 460) for primary, danger and brand; regular 400 (dark `wght` 360) for secondary and ghost. It's a theming hook, unused in dark.
2. **Plan-comment rows** (revise mode, §2) are restructured. Old: one button `"flex w-full flex-col gap-0.5 rounded-[5px] bg-alpha-1 p-1.25 text-left hover:bg-alpha-2"`. New (`MAIN`) has three parts:
   - Each `<li>` is `"flex items-center gap-0.5 rounded-[5px] bg-alpha-1 pe-1.25 hover:bg-alpha-2"`: radius 5, white 5% (white 10% on hover), 5px end padding, 2px gap.
   - Its first child is the open-plan button: `"flex min-w-0 flex-1 flex-col gap-0.5 rounded-[5px] p-1.25 text-left … focus-visible:shadow-focus"`. Its content is unchanged: caption row `"flex items-center gap-0.75 text-caption text-muted"` with a 12px `ChatSimple` icon and the truncated quote, then the comment `"text-body text-primary"`.
   - **New:** a trailing ghost, icon-only, base-size Button with icon `X` (32×32, 20px icon) and `className:"shrink-0"`, labelled "Delete comment".
3. **Everything else is unchanged.** That covers question cards, the card shell, header, actions row, plan and permission cards, Button geometry, Kbd, Checkbox, Radio, Switch, SegmentedControl, TextArea, TextLink, icon sizes, queue ghosts (2 layers, 6px, 0.03 scale), inline CSS and all tokens (same `CSS` file).

**Token resolution.** Tokens resolve from `CSS` in this order: `@layer theme :root`, `.cds-root`, `.cds-root[data-density=comfortable]`, then the dark block `@media screen { [data-mode=dark] .cds-root… }`. `light-dark()` takes its second argument. `--cds-rem-scale` is undefined, so it falls back to 1. 1rem = 16px.

**Density: the cards render comfortable. Only the sidebar is compact.**

- CDS `Root` (`CDS` `co`) computes `T = experimental.densityOverride ?? (coarsePointer ? "comfortable" : density ?? context)`. The context default is `ba=q("comfortable")`.
- The claude.ai app root (`shared-l-p-m-6` `Hj`) passes no `density`, only `densityOverride` from the internal `antTools:densityOverride` setting.
- The desktop's compact density is the **sidebar density**: `shared-l-m-0` `fd()` returns the user setting, or else `"comfortable"` on web and `"compact"` in the desktop app.
  - It's consumed only by the sidebar (`shared-22` `OF`, `data-testid="sidebar"`), wrapped in `T,{density:xe}`, and by the frame attribute `data-sidebar-density`.
  - `shared-styles-B1jXfLTX.css` uses it only as `.dframe-sidebar[data-density=compact]`.
- The chat column (`shared-17`) sets `density:"compact"` only while the chat is a floating peek (`Lr=yt?"compact":void 0`).
- No density wrapper surrounds the approval host or the question cards in `MAIN`, `QCARD`, `CARD` or `PANES`. The `density:` literals in `cc43287c9` wrap dialogs (`"comfortable"`) and popups or the environment picker (`"compact"`).
- So questions, plans and approvals render in the transcript's comfortable density. **Every value below assumes comfortable**; §5.6 lists compact for reference.

**Screenshot.** The reference screenshot `claude-code-tab.jpg` was taken at Claude zoom 0.5 (×1.0954). It has **2.191 device px per CSS px**, not 2; divide measurements by 2.191. It was only used here for colour sampling: transcript background `#151515` = `--cds-surface-1` dark, composer `#212121` = white 5% over it. Zoom doesn't affect those.

**Placements, and which AskUserQuestion layout the desktop Code tab uses.**

- The placement context is `CARD` `_=r("dock")`, so `"dock"` is the default (the area above the composer). `MAIN` picks `let e=we?UT:Tme` with `we=GT()!=="dock"`: the inline card (§1A) when not dock, the dock card (§1B) when dock.
- In the current build the session body (`cc43287c9`) renders the approval host `EpitaxyInlineApprovalHost` (`cb1afaa4b` `ki`) with `presentation: Lo ? "card" : "dock"`.
  - `Lo = _o !== null`, where `_o` is the session store's `inlineApprovalSlotEl`. That slot is only placed when `inlineApprovals` (`lo`) is on.
  - `lo = aj(sessionId)`, and `aj` (`ce8202212` `l`) is a feature gate latched per session view: `sT(viewKey, Pd())`, with `Pd()` the gate `"claudeai_cc_epitaxy_session_presets_main"` (`shared-11`).
- **With the gate on, the desktop Code tab shows the inline card (§1A)** in the transcript, and cards behind the head are listed under "Also waiting". With it off, it uses the dock card (§1B).
- The gate's value lives in server-side feature flags, not in the bundles or the local app data (searched): **UNKNOWN from source**. The current code path makes inline the intended desktop presentation: the inline host is new and exported for the session body. Confirm by triggering one AskUserQuestion.
- Permission and plan cards follow the same `presentation`, with the shell differences noted in §2 and §3.

### 0.1 Dark tokens used throughout (resolved)

Alpha colours are white at the given opacity. The over-surface-1 composite assumes background `#151515`; the over-panel composite assumes `#1a1a19`.

| Token | Value (dark) | Over surface-1 | Over panel |
|---|---|---|---|
| `--cds-alpha-1` | `rgba(255,255,255,.05)` | `#212121` | `#252524` |
| `--cds-fill-ghost-hover` | `rgba(255,255,255,.075)` | `#272727` | `#2b2b2a` |
| `--cds-alpha-2` = `--cds-border` = `--cds-fill-secondary` = `--cds-ring-color` | `rgba(255,255,255,.10)` | `#2c2c2c` | `#313130` |
| `--cds-fill-secondary-hover` | `rgba(255,255,255,.14)` | `#363636` | `#3a3a39` |
| `--cds-alpha-3` = `--cds-border-strong` | `rgba(255,255,255,.20)` | `#444444` | `#484847` |
| `--cds-border-stronger` | `rgba(255,255,255,.40)` | | |
| `--cds-fill-secondary-ring` | `transparent` (light: `--cds-border`) | | |

| Token | Value (dark) |
|---|---|
| `--cds-surface-0` = `--cds-page-bg` | `#0b0b0b` |
| `--cds-surface-1` (transcript bg) | `#151515` |
| `--cds-surface-2` = `--cds-surface-panel` | `#1a1a19` |
| `--cds-surface-3` = `--cds-surface-popover` | `#20201f` |
| `--cds-text-primary` | `#f0efec` |
| `--cds-text-secondary` | `#c3c2b7` |
| `--cds-text-muted` | `#898781` |
| `--cds-text-disabled` | `rgba(255,255,255,.35)` |
| `--cds-text-accent` | `#6da7ec` |
| `--cds-fill-primary` | `#ffffff` |
| `--cds-fill-primary-hover` | `#e1e0d9` |
| `--cds-on-primary` | `#0b0b0b` |
| `--cds-fill-accent` | `#2a78d6` |
| `--cds-fill-accent-hover` | `#3987e5` |
| `--cds-on-accent` | `#ffffff` |
| `--cds-bg-accent` (pressed toggle) | `#032042` |
| `--cds-border-accent` | `#0d366b` |
| `--cds-fill-danger` | `#d03b3b` |
| `--cds-fill-danger-hover` | `#e34948` |
| `--cds-on-danger` | `#ffffff` |
| `--cds-fill-brand` | `#c6613f` |
| `--cds-fill-brand-hover` | `#d97757` |
| `--cds-on-brand` | `#ffffff` |
| `--cds-bg-warning` | `#311a00` |
| `--cds-text-warning` | `#db9300` |
| `--cds-fill-field` | `rgba(255,255,255,.05)` |
| `--cds-fill-field-ring` | `rgba(255,255,255,.10)` |
| `--cds-shortcut-cap-ink` | `#a5a49a` (gray-300) |
| `--cds-shortcut-cap-fill` | `transparent` |
| `--cds-shortcut-cap-line` | `color-mix(in srgb, currentColor 22%, transparent)` |
| `--cds-switch-track` | `rgba(255,255,255,.10)` |
| `--cds-switch-track-hover` | `rgba(255,255,255,.20)` |
| `--cds-switch-knob` | `#ffffff` |
| `--cds-segmented-control-track` | `rgba(255,255,255,.05)` |
| `--cds-segmented-control-thumb` | `rgba(255,255,255,.10)` |
| `--cds-radio-group-card-selected` | `#03162c` |

**Focus and shadow tokens**

- `--cds-focus-shadow`: `inset 0 0 0 1px #0b0b0b, 0 0 0 1px #2a78d6, 0 0 6px 1px rgba(24,79,149,.60)`
- `--cds-focus-shadow-danger`: `inset 0 0 0 1px #0b0b0b, 0 0 0 1px #d03b3b, 0 0 6px 1px rgba(142,38,38,.60)`
- `--cds-shadow-sm`: `0 1px 2px 0 rgba(11,11,11,.06), 0 2px 8px 0 rgba(0,0,0,.24)`
- `--cds-shadow-popover`: `0 8px 24px rgba(0,0,0,.32), 0 2px 6px rgba(0,0,0,.20)`

**Motion.** `--cds-dur-fast` 60ms, `--cds-dur-snap` 120ms, `--cds-dur-slow` 450ms. `--cds-ease-out` `cubic-bezier(.165,.84,.44,1)`, `--cds-ease-overshoot` `cubic-bezier(.34,1.3,.64,1)`.

**Font.** `--cds-font-sans` is `"anthropic-sans", system-ui, …`. `--cds-font-mono` is `"anthropic-mono", ui-monospace, …, "SF Mono", Menlo`.

**Dark text weights.** In dark mode CDS drives the variable `wght` axis through `--cds-font-axis-wght` / `font-variation-settings`. The CSS `font-weight` stays 400/500/580/600. The `wght` axis values are:

| Class | CSS weight | Dark `wght` axis |
|---|---|---|
| `font-normal` / default body | 400 | **360** |
| `font-medium` | 500 | **460** |
| `font-semibold` / `text-body-semibold` | 580 | **540** |
| `font-bold`, `b`, `strong` | 600 | **560** |

These come from `--cds-font-wght-regular:"wght" 360`, `-medium:"wght" 460`, `-semibold:"wght" 540`, `-bold:"wght" 560` in the dark `.cds-root` block. The `.font-*` rules under `[data-theme=claude][data-mode=dark]` resolve to the same variables, because the later rule wins. `GRAD` is 0.

**Type roles (comfortable)**

| Class | Size / line height | Source |
|---|---|---|
| `text-body` | 14 / 20 | `--cds-font-size-body` / `--cds-leading-body` |
| `text-body-semibold` | 14 / 20, `wght` 540 | |
| `text-footnote` | 13 / 17 | |
| `text-caption` | 12 / 17 | |
| `text-code` | 13 / 19, mono | |
| `--chat-body` in transcript | 14 / 1.42857 | `.epitaxy-transcript-typography` |

**Spacing tokens (comfortable)**

| Token | xs | sm | md | lg | xl |
|---|---|---|---|---|---|
| `--cds-pad-*` | 6 | 8 | 12 | 16 | 24 |
| `--cds-gap-*` | 8 | 12 | 16 | 28 | 40 |

| Class | Value |
|---|---|
| `--spacing` | 4px (so `gap-0.5`=2, `gap-0.75`=3, `gap-1`=4, `gap-1.5`=6, `py-1`=4, `p-1.25`=5) |
| `rounded` | `--cds-radius` = 8px |
| `rounded-card` | radius + 4 = **12px** |
| `rounded-lg` | 8px |
| `rounded-md` | 6px |
| `rounded-xl` | 12px |
| `--cds-panel-radius` | 12px |

**Borders.** Default border colour is `:not(html){border-color:var(--cds-border)}`, which is white at 10%.

---

## 1. AskUserQuestion

There's no `data-cds=AskUserQuestion` attribute anywhere in the bundles. The component is found by its strings: `"Skip"`, `"Submit"`, `"Next"`, `"Other"`, `"Type your own answer here"`, `"{position} of {count}"`.

### 1A. Inline / transcript card (`Sk`, placement `"card"`)

Source: `MAIN` `Sk` (uncompiled branch) plus `ICSS` `c031798b2`. This is the version that shows in the conversation.

**Container**

Rendered by `Fv` (`CARD` `nu`) with these classes:

- From `Sk`: `className:"epitaxy-question-card max-w-[480px] outline-none"`, `role:"group"`.
- Added by `nu` when placement isn't dock: `Ql` + `"epitaxy-card-outline"` + `data-approval-presentation="card"`.
- `Ql` = `"epitaxy-approval-card relative isolate flex flex-col rounded-card p-[12px] gap-[12px] max-h-[60vh] origin-top @container animate-code-approval-promote …"`

Two `ICSS` rules then override the utilities. Unlayered CSS beats `@layer utilities`, and the second rule comes later at equal specificity:

- `.epitaxy-root .epitaxy-approval-card[data-approval-presentation=card]{border-radius:calc(var(--cds-radius) + .25rem); padding:var(--cds-pad-lg) …}`
- `.epitaxy-root .epitaxy-approval-card.epitaxy-question-card{gap:0;max-height:none;padding:0;overflow:clip}`

The effective result:

- **Width:** max 480px.
- **Radius:** 12px.
- **Padding and gap:** 0.
- **Overflow:** clipped.
- **Background:** none. In card placement there's no backdrop (`backdrop: a ? void 0 : <Zl/>`), so the transcript `#151515` shows through.
- **Outline:** `.epitaxy-card-outline{box-shadow:0 0 0 1px var(--cds-border)}`, an outer 1px ring at white 10%.
- **Enter animation:** `epitaxy-approval-inline-enter`, opacity 0 to 1 over 160ms ease-out. The utility `animate-code-approval-promote` is defined as 220ms `cubic-bezier(.215,.61,.355,1)`, from `opacity:.75; translateY(-6px) scale(.97)` to none. The unlayered `animation:` rule on `[data-approval-presentation]` replaces it. Both are skipped under reduced motion.

**Structure, top to bottom**

1. **Header row.** Class `` `bg-alpha-1 px-lg flex gap-md py-md items-center` `` (`items-start` when there's an engine title/body).
   - Background white 5%, `#212121` over the transcript. Padding 12px vertical, 16px horizontal. Gap 16px.
   - **Question text:** `"min-w-0 flex-1 text-body text-primary select-text break-words"`. 14/20, `wght` 360, `#f0efec`. This is not semibold.
   - **Engine-confirm variant** (`ye!==null`): a column with gap-xs (8px).
     - Title: `"text-body-semibold text-primary text-balance"`.
     - Body: `"text-body text-secondary text-pretty"` (`#c3c2b7`).
   - **Pagination**, only when there's more than one question: `"-my-xs -mr-sm flex shrink-0 items-center gap-xs text-caption text-muted"`. That's 12/17 `#898781`, gap 8px, margins −6px vertical and −8px right.
     - Contents: a ghost, icon-only, `size:"sm"` Button with icon `CaretLeft`, then the text `"{position} of {count}"` (for example `1 of 2`), then the same Button with `CaretRight`.
     - The buttons are 28×28 with 7px radius and a 20px icon (§4). They're disabled at the first and last page, and while sending.

2. **Option rows.** Container `"flex flex-col"`, no gap. Each row is `xk`.
   - **Button class (`bk`):** `"epitaxy-answer-option flex w-full items-start gap-md px-lg py-lg text-left focus-visible:outline-hidden hide-focus-ring focus-visible:shadow-focus"`. Padding 16px all round. Gap 16px between the mark and the text. `aria-pressed` follows the selection.
   - **Separator:** `ICSS` `.epitaxy-answer-option+.epitaxy-answer-option{border-top:1px solid var(--cds-border)}`. A 1px white 10% line sits between consecutive rows, including before "Other". There's no line between the header and the first row.
   - **Mark:** a radio (`ik`) for single-select or a CDS Checkbox (`j`) for multi-select, with class `de` = `mt-[calc((1lh - var(--cds-checkbox,1rem))/2)]`. With a 20px line height and a 20px mark the top margin is 0.
     - Radio mark, from `ICSS`:
       - Unchecked: `.epitaxy-radio-mark{width:var(--cds-checkbox); height:…; border:1px solid var(--cds-border-strong); border-radius:9999px}`. That's 20×20, a 1px white 20% border, transparent fill.
       - Checked (`[data-checked]`): `background:var(--cds-fill-accent); border:0`. Fill `#2a78d6`.
       - Dot (`.epitaxy-radio-mark-dot`): (20 − 10) = **10×10**, `#ffffff`, round.
     - Checkbox: see §5.1. In this card it's 20×20 with 5px radius.
   - **Text column:** `"flex min-w-0 flex-1 flex-col gap-xs select-text"`, gap 8px.
     - Label: `"text-body text-primary"`. 14/20, `wght` 360, `#f0efec`.
     - Description: `"text-body text-secondary"`. 14/20, `#c3c2b7`. Only shown when the option has a description.
   - **Hover:** no hover background on these rows. **Focus:** `--cds-focus-shadow` on the row. **Disabled while sending:** the native `disabled` attribute; no visual class (**UNKNOWN** beyond the browser default of none).

3. **"Other" row.** Hidden when `engineConfirm`. Class `` `epitaxy-answer-option relative grid grid-cols-[auto_1fr] items-start gap-x-md gap-y-sm px-lg py-lg` ``: columns 16px apart, rows 12px apart, padding 16px.
   - A transparent full-row button: `"absolute inset-0 …focus-visible:shadow-focus"`.
   - The mark (same as the option rows), then the text `"Other"` (`text-body text-primary`).
   - When selected, a CDS TextArea (§5.7) appears in column 2, row 2. Class `"relative col-start-2 row-start-2 w-full"`, `rows=1`, autosize.
     - Placeholder: `"Type your own answer here"`.
     - Max height: `calc(4lh + 2 * var(--cds-pad-sm))` = 80 + 16 = **96px**.
     - Min height: `1lh + 2×8` = **36px**.
     - Pressing ⌘↩ in the field submits.

4. **Footer.** Class `` `epitaxy-approval-actions flex items-center justify-end gap-sm px-lg pb-lg pt-md` ``. Gap 12px; padding 12px top, 16px horizontal, 16px bottom.
   - `Skip`: Button `variant:"secondary"`. Hidden when `engineConfirm`.
   - `Submit` on the last page, `Next` otherwise: Button `variant:"primary"`, `busy` while sending.
     - Shows the shortcut `"cmd+enter"` (keycaps ⌘ ⏎, §4.6) when the panel is active.
     - Disabled until the current question is answered. Its `disabledReason` tooltip says `"Choose an option or skip this question"` or `"Question {n} is unanswered"`.
   - At container width ≤420px (`ICSS` `c9bddf7be`), the actions stack in a column and stretch.

**After answering ("receipt").** `MAIN` `wZ`: `"epitaxy-question-receipt epitaxy-card-outline flex w-full max-w-[480px] flex-col overflow-clip rounded-lg select-text"`. That's an 8px radius with a 1px white 10% outer ring.

- Each row: `"flex flex-col gap-0.5 px-lg py-md"` (2px gap, padding 12/16).
  - Question: `"text-body font-medium text-primary"` (`wght` 460).
  - Answer: `"text-body text-secondary"`.
- `ICSS` puts `border-top:1px solid var(--cds-border)` between rows.
- Enters with a 200ms opacity fade.

### 1B. Dock card (`XO`, placement `"dock"`)

Source: `MAIN` `XO` and `YO`; `CARD` `nu`, `Zl`, `$l`; `HOST` `tp`. This version sits above the composer.

**Container**

`Fv` gets class `Ql` + `"outline-none"`. The host `tp` (`variant:"host"`) renders:

- **Backdrop `Zl`:** `"absolute inset-0 -z-[1] rounded-[inherit] pointer-events-none bg-surface-panel shadow-panel-sm"`.
  - Fill: `#1a1a19`.
  - Shadow: `inset 0 0 0 1px rgba(255,255,255,.10), 0 0 0 0px …, 0 1px 2px rgba(11,11,11,.06), 0 2px 8px rgba(0,0,0,.24)`.
- **Queue ghosts:** when more requests are queued, up to `Qf=2` layers with class `$l` (`"rounded-card bg-surface-1 …"`, `#151515`) are drawn behind the card. Layer *n* has `transform: translateY(-6n px) scale(1 - 0.03n)`, `z-index: -n`, `opacity: 1 - 0.25n`.
- **Box:** radius 12px (`rounded-card`), padding 12px, gap 12px, `max-height: 60vh`.
- **Enter animation:** `code-approval-promote`, 220ms `cubic-bezier(.215,.61,.355,1)`, from `opacity .75, translateY(-6px) scale(.97)`.

**Body `ey`** (`CARD` `iu`): `"epitaxy-approval-body flex min-h-0 flex-col gap-[12px] overflow-y-auto -mx-[12px] px-[12px] -mt-[4px] pt-[4px] -mb-[8px] pb-[8px]"`, with `overscroll-contain` in the dock. It scrolls with `epitaxy-scroll-clamp scroll-fade-y`.

**Header `$c`** (`HDR` `AS`)

- Row: `"text-primary min-h-[24px] flex items-center gap-1"`.
- Title column: `"flex flex-1 min-w-0 flex-col gap-[2px]"`.
  - Title: `"text-body-semibold min-w-0 break-words"`. The question, at 14/20, `wght` 540, `#f0efec`.
  - Subtitle: `"text-body text-muted"`.
- **Leading counter**, only with more than one question: `"grid shrink-0 place-items-center rounded-full bg-warning px-sm text-caption tabular-nums text-warning"`.
  - Height `var(--cds-leading-body)` = 20px. Text is `"{i}/{n}"`, for example `1/2`.
  - Fill `#311a00`, text `#db9300`, 12px, 8px horizontal padding.
- **Trailing:** `"flex items-center gap-0.5"` (2px gap) holding two ghost, icon-only, `size:"base"` Buttons (32×32, 20px icons):
  - `CaretRight`, rotated 90° when expanded (`transition-transform duration-fast`).
  - `X`, labelled "Dismiss question".

**Options** (inside a collapsible `NC`): `"flex flex-col gap-0.75"`, so 3px between rows.

- **Row `YO`:** `"flex items-center gap-sm rounded-[5px] px-md py-md text-left focus-visible:outline-hidden hide-focus-ring focus-visible:shadow-focus transition-[background-color]"`. Radius 5px, padding 12px, gap 12px.
  - Default: `bg-alpha-1`, white 5% (`#252524` on the panel).
  - Hover, or the keyboard-highlighted row in multi-select: `bg-alpha-2`, white 10% (`#313130`).
  - Selected: `KO` = `"bg-[light-dark(var(--cds-surface-popover),var(--cds-alpha-2))] [box-shadow:inset_0_0_0_1px_var(--cds-fill-secondary-ring)]"`. In dark that's white 10% with a transparent ring, so **selected looks the same as hover**. (In light it's the popover surface with a 1px border ring.)
- **Text column:** `"flex flex-col gap-0.5 min-w-0 flex-1 select-text"` (2px gap).
  - Label: `"text-body text-primary"`.
  - Description: `"text-footnote text-muted whitespace-pre-wrap"`. 13/17, `#898781`. This differs from 1A, which uses body size in `text-secondary`.
- **Trailing glyph:**
  - Multi-select: a CDS Checkbox inside `data-size="sm"`, so 18×18, 5px radius, 16px glyph (§5.1).
  - Single-select: a digit keycap Shortcut showing the row number, `keys:String(i+1)`, inside `"pointer-events-none flex pointer-coarse:hidden"` (§4.6). It's 18×18.
  - Typing the digit (1 to n+1) picks that row.
- **"Other" row:** `` `flex flex-col gap-[12px] rounded-[5px] px-md py-md` `` with the same three background states as an option row.
  - Inner button: `"flex items-center gap-sm text-body text-primary text-left …"` with `"Other"`, then a checkbox or the keycap n+1.
  - Below it, always shown, a CDS TextArea: `rows=1`, autosize, max height 96px, placeholder `"Type your own answer here"`. Typing in it selects "Other".

**Footer** (collapsible): `"flex items-center justify-end gap-[8px]"`.

- `Back`: secondary, `mr-auto`. Only after page 1.
- `Skip`: secondary.
- `Submit` or `Next`: primary, disabled until something is selected.
- No keycaps in the dock footer.

---

## 2. Plan approval (ExitPlanMode)

Source: `MAIN` `$k` (uncompiled branch near the strings `"Claude proposed a plan"` and `"Revise…"`). The same component is used in the dock and in the card; only the shell changes, as in §1A and §1B.

The card **doesn't contain the plan text.** `"Open plan"` calls `onOpenPlan`, which opens a plan viewer in a pane. That viewer, in `/tmp/claude-web-d/cccc2cf0a-q7oO0Eid.js` (same class strings as before), is `"h-full select-text overflow-y-auto [contain:strict] [scrollbar-gutter:stable_both-edges] p-lg"`, with an inner `"mx-auto max-w-[68ch]"` and markdown rendered through a prose component (`font:"sans", size:"sm"`). Its typography values weren't traced: **UNKNOWN**.

**Structure**

1. **Body (`ey`), gap 12px.**
   - Header `$c`: title `"Claude proposed a plan"` (`text-body-semibold`, `wght` 540, `#f0efec`).
   - Header trailing: `"Open plan"`, a CDS TextLink with `className:"text-footnote"` (§5.8). 13/17, `#6da7ec`, underlined with a 3px offset at 40% of the text colour, 100% on hover.
2. **Default actions row.** `"epitaxy-approval-actions flex flex-wrap justify-between gap-x-1 gap-y-[8px] [&>div]:grow"`: 4px between columns, 8px between wrapped rows.
   - **Left group** (`"flex gap-[8px]"`):
     - `Reject`: secondary.
     - `Revise…`: secondary, `shortcut:"esc"`, shows an `Esc` keycap. Esc also opens revise.
   - **Right group** (`"flex flex-wrap justify-end gap-[8px]"`):
     - `Return to terminal`: secondary. Ultraplan mode only.
     - `Accept`: secondary, `shortcut:"cmd+shift+enter"`, keycaps ⇧ ⌘ ⏎. Shown when the trust mode isn't `"default"` and default-accept is allowed; with the defaults it's shown.
     - The primary action, labelled from `Zk`: `"Accept and allow edits"` by default (`trustForwardMode:"acceptEdits"`, `acceptOptions:["acceptEdits"]`). It's `shortcut:"cmd+enter"`, keycaps ⌘ ⏎. Other labels: `"Accept and auto mode"`, `"Accept and bypass permissions"`, `"Accept"`.
     - With more than one accept option, the primary becomes a **SplitDropdownButton** (§4.5), primary variant, menu labelled `"More accept options"`, opening upward and aligned to the end.
3. **Revise mode.** Esc or `Revise…` switches to this.
   - The body adds a CDS TextArea (`rows:3`, no autosize; §5.7), labelled `"Plan feedback"`, placeholder `"What should change? (optional)"`. If the plan already has inline comments, the placeholder is `"Anything else to add?"` and the comments list appears above it.
   - Comments list: `"flex max-h-[176px] scroll-p-[8px] flex-col gap-1 overflow-y-auto -m-[8px] p-[8px]"`. Each row is `"flex items-center gap-0.5 rounded-[5px] bg-alpha-1 pe-1.25 hover:bg-alpha-2"` (radius 5, white 5%, white 10% on hover) containing:
     - A button `"flex min-w-0 flex-1 flex-col gap-0.5 rounded-[5px] p-1.25 text-left"` (padding 5) holding a caption row (`"text-caption text-muted"`, a 12px `ChatSimple` icon and the truncated quote, gap 3px) and the comment (`"text-body text-primary"`).
     - A ghost, icon-only `X` Button (32×32), "Delete comment". (New in the current build; see §0.0.)
   - Actions (`"epitaxy-approval-actions flex flex-wrap justify-between gap-x-1 gap-y-[8px]"`): `Back` (secondary), then `Revise` (primary). Enter sends the revision; Shift+Enter adds a newline.
4. **Keyboard.** ⌘↩ accepts with the trust mode. ⌘⇧↩ accepts as `default`. Esc opens revise; inside revise, Esc closes it.

---

## 3. Tool permission card (`epitaxy-approval-card`)

Source: `MAIN` permission component (uncompiled branch ending `Q(Fv,{queueDepth:b,className:C("gap-[24px]",Zv,Ze==="card"&&"w-full max-w-[480px]")…`), body `vF`, actions `dd` = `ACT` `Cu`/`wu`.

**Shell.** `Ql` plus:

- `gap-[24px]`, which overrides `gap-[12px]` because `.gap-\[24px\]` comes later in `CSS`.
- `Zv` = `"focus-visible:outline-1 focus-visible:outline-fill-accent focus-visible:outline-offset-2"`.

| Placement | Background | Radius | Padding | Width | Gap |
|---|---|---|---|---|---|
| Dock | `#1a1a19` + `shadow-panel-sm` (inset 1px white 10% ring) | 12px | 12px | full | 24px |
| Card | transparent, outer 1px white 10% ring | 12px | 16px (`ICSS` `[data-approval-presentation=card]`) | max 480px | 24px |

**Body (`ey` with `className:"gap-[24px]"`) → `vF`:**

1. **Outer column:** `"flex flex-col gap-[10px]"`.
2. **Header `$c`** (row `text-primary min-h-[24px] flex items-center gap-1`, title `text-body-semibold`, `wght` 540).
   - Optional leading icon at `size:"sm"` (16px), `self-center`.
   - Title templates: `"Allow Claude to <b>{action}</b>?"`, `"… <b>{action}</b> <meta>{metaText}</meta>?"`, `"Allow Claude to <b>{action} {tail}</b>?"`, and so on. The `<b>` and `<meta>` runs are `"text-primary [unicode-bidi:plaintext]"`, so the whole title is `#f0efec`. Long titles use `line-clamp-2`.
3. **Detail column** (`"flex flex-col gap-[12px]"`), parts in order as present:

   | Part | Classes | Effective |
   |---|---|---|
   | Served text | `"rounded bg-alpha-1 px-lg py-md text-body"` with inner `"whitespace-pre-wrap text-secondary"` | radius 8, padding 12/16, `#c3c2b7` |
   | Chip | `"flex flex-col rounded-lg bg-alpha-1 px-md py-sm"`; each value `"font-mono-ui text-body text-primary … whitespace-pre-wrap break-all"`; multi-value rows `"border-t border-alpha-2 py-1"` | radius 8, padding 8/12 |
   | Lede | `XP` = `"text-body text-secondary …"` or, when compact, `ZP` = `"text-footnote text-muted …"` | |
   | Tool identity | `"text-footnote text-secondary"` | |
   | Description | `YP` = `"text-body text-secondary … max-h-[calc(3*var(--cds-leading-body))] overflow-y-auto"` | at most 60px tall |
   | Reason | `YP`, or `XP` when shown in full | |
   | Change groups | heading `"text-footnote text-muted"`; lines `"text-body text-primary"`; group gap 3px | |
   | Command / detail block | `$P` = `"bg-alpha-1 rounded-[5px] py-md px-lg text-code text-secondary whitespace-pre-wrap break-words select-text"` | white 5%, radius 5, padding 12/16, mono 13/19, `#c3c2b7` |
   | Folded detail | trigger `"text-footnote text-muted"`; panel `"mt-1 bg-alpha-1 rounded-[5px] py-md px-lg text-code text-secondary"` | |
   | "What Claude sent" rows | `"flex flex-col gap-1 rounded bg-alpha-1 px-lg py-md"`, with an optional caption `"text-footnote text-muted"` | |
   | Warning boxes | `"rounded-lg bg-alpha-1 px-lg py-2.5 text-body text-secondary"` | padding 10/16 |
   | Footnote | `"text-body text-secondary"` | |

4. **Read hint** above the actions, only when a detail must be scrolled through first: `"epitaxy-approval-read-hint text-footnote text-muted text-end text-balance"`. Example: "Scroll through the whole command to allow it." It's in a wrapper `"flex flex-col gap-sm"`.

**Actions** (`ACT` `Cu`)

- **Root:** `"flex flex-wrap gap-x-md gap-y-sm items-start justify-between"` + `epitaxy-approval-actions`, with `justify-end` added in card placement (`.justify-end` comes after `.justify-between` in `CSS`, so it wins). Gaps are 16px between columns and 12px between wrapped rows.
- **Order:** the Deny button (digit 1) comes first, then the allows group `"flex min-w-0 flex-wrap gap-sm items-start"` (12px gap).
- **Each action:** a default-size Button (32px).
  - Label span: `"min-w-0 [unicode-bidi:plaintext] truncate"`.
  - With `wrapLabel`: `"h-auto min-h-control shrink py-1"`.
- **Default set:**
  - `Deny`: secondary, keycap `Esc`.
  - `Always allow`: secondary, persistent, keycaps ⇧ ⌘ ⏎. Its tooltip is `"Don't ask again for this tool"`. Some scopes label it `"Allow for all tasks"`, and in some contexts there's `Allow for this session`.
  - `Allow once`: primary, keycaps ⌘ ⏎.
  - When there are extra options, `Allow once` becomes a primary SplitDropdownButton with menu `"More allow options"`. The menu includes `Always allow` and `"Allow and switch to Auto"` ("Auto reviews the rest of this session.").
- **Card placement:** the `Esc` and ⌘⇧⏎ hints are hidden (`chordHintHidden: Ze!=="dock"`), but the ⌘⏎ hint stays.
- **Dock:** with the panel active, digit keycaps 1, 2, 3… are appended inside each button (`showDigitKeycaps`).
- **Narrow:** at container width ≤420px (`ICSS` `c9bddf7be`), the actions stack in a column, stretch, and become full width.

---

## 4. CDS Button (`data-cds="Button"`)

Source: `CDS` `Vc` (uncompiled branch near offset 88452) and the `cva` sets `kc` (root) and `jc` (paint). Helpers: `Ds`, `Os`, `ks`, `Es`, `Ps`, `As`, `js`, `Ms`, `Ns`.

### 4.1 Anatomy

**Root** (`kc`): `"cds-reset group/btn relative isolate inline-flex shrink-0 items-center justify-center gap-1.5 whitespace-nowrap select-none border-0 outline-none rounded h-control font-sans text-body [&:disabled:not([aria-busy])]:opacity-disabled disabled:pointer-events-none transition-shadow duration-fast"` plus:

- Text-only: `px-md`.
- Icon-only: `aspect-square w-control px-0`.

**Attributes**

- `data-cds="Button"`.
- `data-cds-icon-only` when icon-only.
- `data-cds-ghost` when ghost.
- `data-size=xs|sm|lg`. Size `base` sets nothing; size `xxs` sets `data-step="1"`.

**Paint layer** (first child, `aria-hidden`)

- Outer span `Fs`: `"absolute -z-[1] rounded-[inherit]"`, then:
  - `inset-[0.5px]` for solid variants (primary, danger, brand) that aren't joined; otherwise `inset-0`.
  - `cds-btn-squish` when not joined.
- Inner span `data-cds-part="paint"`: `ks` = `"absolute inset-0 rounded-[inherit] transition-[background-color,box-shadow,color] duration-fast ease-out group-focus-visible/btn:shadow-[inset_0_0_0_1px_var(--cds-page-bg)]"`, then the variant fill from `jc`, then `Ms` (the pressed-toggle fill), then `js` for an un-joined secondary.

**Content:** `"inline-flex min-w-0 items-center gap-1"` (4px).

- A leading icon gets `-ms-1` (−4px), so it sits 8px from the left edge at base size. A trailing icon gets `-me-1`.
- A shortcut appends a Shortcut with `"pointer-coarse:hidden ms-1"` plus `Oc` = `"me-[calc((var(--cds-h-control)-1em-6px)/2-var(--cds-pad-md))]"`. At base size: (32 − 12 − 6)/2 − 12 = −5px, so the keycap sits 7px from the right edge and 7px from the top and bottom, equal insets.

**Busy:** the content goes to `opacity-0` and a centred Spinner (`size:"sm"`, inherits colour) overlays it. `aria-disabled`.

**Press:** `.cds-root .group/btn:not([disabled]):active .cds-btn-squish{transform:scale(.975); transition:transform 60ms ease-out}`. On release it springs back over `transform 450ms var(--cds-btn-spring)`, where `--cds-btn-spring` = `linear(0, .2459, .6526, .9468, 1.0764, 1.0915, 1.0585, 1.0219, .9993, .9914, .9921, .9957, .9988, 1.0004, 1)`. Only the paint scales; the label doesn't.

**Hover:** applies only under `@media (hover:hover)` (`group-hover/btn:*`). The `[aria-haspopup][aria-expanded=true]` state uses the hover fill.

**Disabled:** the whole button at `opacity .4`, `pointer-events:none`. A `disabledReason` adds a tooltip wrapper.

**Focus:**

- Root: `focus-visible:shadow-focus`, i.e. `inset 0 0 0 1px #0b0b0b, 0 0 0 1px #2a78d6, 0 0 6px 1px rgba(24,79,149,.6)`. Danger uses the danger focus shadow.
- Paint: adds `inset 0 0 0 1px #0b0b0b`, a 1px dark gap inside the blue ring.

**Pressed toggle** (`aria-pressed=true`): the paint is `bg-accent` `#032042` (on hover too). Secondary and ghost text turns `text-accent` `#6da7ec`. Secondary's paint shadow becomes `shadow-field-pressed`: `inset 0 0 0 1px rgba(255,255,255,.10), 0 1px 2px rgba(0,0,0,.05)`.

### 4.2 Variants (dark)

In the current build every variant's text classes also include `font-control`. That's a weight-role hook whose tokens are `initial` (§0.0), so the weights below are unchanged.

| Variant | Text | Weight (dark `wght`) | Paint fill | Hover fill | Paint shadow | Focus |
|---|---|---|---|---|---|---|
| **primary** | `text-on-primary` `#0b0b0b` | `font-medium` 500 (460) | `bg-fill-primary` `#ffffff`, inset 0.5px | `#e1e0d9` | none | blue |
| **secondary** (default) | `text-primary` `#f0efec` | `font-normal` 400 (360) | `bg-fill-secondary` `rgba(255,255,255,.10)` | `rgba(255,255,255,.14)` | `shadow-field`: `inset 0 0 0 1px transparent, 0 1px 2px rgba(0,0,0,.05)` | blue |
| **ghost** | `text-primary` `#f0efec` | 400 (360) | transparent | `rgba(255,255,255,.075)` | none | blue |
| **danger** | `text-on-danger` `#ffffff` | 500 (460) | `#d03b3b`, inset 0.5px | `#e34948` | none | red (`--cds-focus-shadow-danger`) |
| **brand** | `text-on-brand` `#ffffff` | 500 (460) | `#c6613f`, inset 0.5px | `#d97757` | none | blue |
| onContent / onAccent | `text-primary`, medium | | `#0000008c` + `backdrop-blur-md` + `inset 0 0 0 1px var(--cds-button-on-content-ring)` | `--cds-button-on-content-hover` | | `0 0 0 2px rgba(255,255,255,.7)` |

Notes:

- `onContent` and `onAccent` are for use over imagery. Their ring and hover token values weren't resolved: **UNKNOWN**.
- Primary, danger and brand set `[--cds-shortcut-cap-ink:currentColor]`, so their keycaps take the button's text colour.
- A primary keycap therefore draws with `#0b0b0b` ink and a `rgba(11,11,11,.22)` outline.

### 4.3 Sizes (comfortable)

Size is applied through `data-size`, which rescopes `--cds-h-control`, `--cds-radius`, `--cds-pad-md`, `--cds-font-size-body` and `--cds-leading-body` (`CSS` `.cds-root [data-size=…]` plus the `--x--xs|sm|lg` values in `.cds-root[data-density=comfortable]`).

| `size` | Height (and icon-only width) | Horizontal padding (`px-md`) | Radius | Font / line height | Icon (`zc`→`Lc`→`$a`) |
|---|---|---|---|---|---|
| `xxs` (`data-step=1`) | 20 | 6 | 5 | 12 / 17 | `auto-sm` → 16 |
| `xs` | 24 | 8 | 6 | 13 / 19 | `auto-sm` → 16 |
| `sm` | 28 | 10 | 7 | 14 / 20 | `auto` → 20 |
| `base` (default) | **32** | **12** | **8** | **14 / 20** | `auto` → 20 |
| `lg` | 40 | 16 | 10 | 15 / 22 | `md` → 20 |

Icon pixel sizes come from `Ja`: xs 12, sm 16, md 20, lg 24, xl 28, xxl 32. In comfortable density `auto` is `md` (20px) and `auto-sm` is `sm` (16px); in compact `auto` is `sm` (16px).

### 4.4 Icon-only

Root `aspect-square w-control px-0`: square at the size's height, with the same radius and paint as the variant. The icon is centred at the size's icon size; the 20px icon in a 32px button leaves 6px all round. The tooltip defaults to the aria-label.

Ghost icon-only (`data-cds-ghost data-cds-icon-only`) is used for the question card's caret and X (32px) and for its pagination (28px).

### 4.5 SplitDropdownButton and ButtonGroup

Source: `CDS` `dE`, `JT`, `qT`, `WT`, `UT`.

- **Group:** `data-cds="SplitDropdownButton"`, wrapped in a joined ButtonGroup: `"relative inline-flex w-fit shrink-0 items-stretch rounded"`.
  - Secondary groups add `shadow-field-drop` (`0 1px 2px rgba(0,0,0,.05)`) and an `::after` ring `inset 0 0 0 1px var(--cds-fill-secondary-ring)`, which is transparent in dark.
- **Segments:** the main segment is `rounded-e-none` and the caret segment is `rounded-s-none`. Joined segments have no squish and their paint isn't inset.
- **Seam:** a 1px-wide divider filled with the variant colour, holding a line inset 4px top and bottom.
  - Secondary: `bg-border`, white 10%.
  - Primary: `#0b0b0b` at 25% opacity, which reads `#c2c2c2` on white.
  - Danger and brand: `#ffffff` at 25%.
  - The seam line hides while either segment is hovered, pressed or has its menu open.
- **Caret segment:** an icon-only Button with inline style `{aspectRatio:"auto", paddingInline:4, minWidth:0, width:"auto"}`, so it's 4 + 16 + 4 = 24px wide at base height.
  - The `CaretDown` icon is `sm` (16px) in comfortable (`My()`: density step ≥4 → `sm`, otherwise `xs`).
  - On secondary and ghost the caret is `text-muted`.
- **Main segment:** `px-md` (12px), label `"min-w-0 shrink"`, plus any shortcut keycaps.

### 4.6 Keyboard hint (Shortcut / keycap)

Source: `CDS` `$o`, `Go`, `Ko`, `qo`, `Xo`.

- **Wrapper:** `data-cds="Shortcut"`, `"inline-flex shrink-0 items-center gap-[2px] text-caption"`. 12px text, 2px between caps.
- **Each key:** a `<kbd>` with `"inline-flex shrink-0 items-center justify-center h-[calc(1em+6px)] rounded-[var(--cds-keycap-radius,4px)] [color:var(--cds-shortcut-cap-ink)] bg-[color:var(--cds-shortcut-cap-fill)] border border-[color:var(--cds-shortcut-cap-line)] font-inherit [line-height:1]"`.
  - **Height:** 18px.
  - **Radius:** 4px. `--cds-keycap-radius` is undefined, so the 4px fallback applies.
  - **Border:** 1px, ink at 22%.
  - **Fill:** transparent.
  - **Ink:** `#a5a49a`, or the button text colour inside primary, danger and brand.
  - **Width:** single glyph 18×18 (`w-[calc(1em+6px)] px-0`). Multi-character labels have `min-w-[18px] px-[3px]`.
- **Glyphs (macOS):** cmd ⌘, shift ⇧, alt/option ⌥, ctrl ⌃, enter ⏎, esc `Esc`, tab ⇥, space ␣, backspace ⌫, arrows ← ↑ → ↓.
- **Order:** modifiers sort as ctrl, alt, shift, cmd. For example `cmd+enter` renders as **⌘ ⏎** and `cmd+shift+enter` as **⇧ ⌘ ⏎**.
- **Sequences:** keys pressed in sequence are separated by `"then"` (`px-[2px]`).

The modifier order is traced in `CDS` `hs()`: modifiers are split from the keys and sorted by their index in `ss` = `["ctrl","control","alt","option","shift","cmd","command","meta"]`. So the plan card's Accept and the permission card's Always allow render **⇧ ⌘ ⏎**, not ⌘ ⇧ ⏎ as the shortcut strings are written. Each key is its own 18px cap, 2px apart.

---

## 5. Option controls

### 5.1 Checkbox (`data-cds="Checkbox"`, `CDS` `S_`)

- **Box (`y_`):** `"flex shrink-0 size-[var(--cds-checkbox)] items-center justify-center rounded-[var(--cds-checkbox-radius)] border border-strong bg-transparent"`.
  - **Unchecked:** 1px border at white 20%, transparent fill.
  - **Checked or indeterminate:** `bg-fill-accent border-transparent`. Fill `#2a78d6`.
  - **Glyph:** a `Check` icon, or `Minus` when indeterminate, at `size:"sm"`, bold, `font-size: var(--cds-checkbox-glyph)`, inside `text-on-accent` (`#ffffff`).
  - No hover style is defined on the box.

| Scope | Box | Radius | Glyph |
|---|---|---|---|
| base | 20 | 5 | 16 |
| `data-size=sm` | 18 | 5 | 16 |
| `data-size=xs` | 16 | 4 | 16 |
| `data-size=lg` | 24 | 6 | 20 |

- **Vertical alignment with a text line:** `b_` = `mt-[calc((1lh - var(--cds-checkbox))/2)]`.

### 5.2 Radio: CDS RadioGroup item (`CDS` `xM`, `hM`, `mM`, `pM`)

- **Item:** `"cds-reset group/rd inline-flex items-center|items-start gap-2 text-start text-body font-normal text-primary data-[disabled]:opacity-disabled"`. 8px gap.
  - Label, then an optional description in `"text-footnote leading-snug text-muted"` (13px, line height 1.375).
- **Circle (`pM`):** `"flex shrink-0 size-[var(--cds-checkbox)] items-center justify-center rounded-full border border-strong bg-transparent"`. 20×20 with a 1px white 20% border.
  - Hover: `border-stronger`, white 40%.
  - Checked: `bg-fill-accent border-0` (`#2a78d6`). Checked + hover: `#3987e5`.
  - Disabled + hover: keeps `border-strong`.
- **Dot:** `size-[calc(var(--cds-checkbox) - .625rem)]`, i.e. 10×10, round, `#ffffff`.
- **Focus:** the circle gets the focus shadow.
- **Group:** `"flex flex-col gap-2 font-sans"`, 8px between items.
- **Card variant (`gM`):** `"group/rd flex w-full items-start gap-md rounded-card border bg-surface-1 p-md …"`.
  - Default: radius 12, 1px white 10% border, `#151515` fill, padding 12, gap 16.
  - Hover: `border-strong`.
  - Checked: `border-accent` `#0d366b` and fill `#03162c`.
  - Focus: focus shadow. Disabled: `opacity .4`.
- **Question-card radio:** the epitaxy radio mark (§1A) has the same geometry but no hover style.

### 5.3 Switch (`data-cds="Switch"`, `CDS` `Xx`, `Gx`, `Kx`, `qx`, `Jx`)

- **Track:**
  - Size: height `var(--cds-switch-h)`, width `calc(h*1.8)`, padding 2px, `rounded-full`. Base is **20 × 36**; `sm` is 18 × 32.4; `xs` is 16 × 28.8; `lg` is 24 × 43.2.
  - Colours: unchecked `rgba(255,255,255,.10)`, hovering `.20`; checked `#2a78d6`, hovering `#3987e5`.
  - Disabled: `opacity .4`, and the hover colour is suppressed.
  - Focus: focus shadow.
- **Knob:** `size: calc(h - 4px)` (16px at base), `rounded-full`, `#ffffff`, `shadow-sm`.
  - Checked: `translateX(calc(h*0.8))`, 16px at base.
  - Motion: `transition-transform duration-snap ease-overshoot`, i.e. 120ms `cubic-bezier(.34,1.3,.64,1)`.

### 5.4 SegmentedControl (`data-cds="SegmentedControl"`, `CDS` `hS`, `xS`, `SS`, `CS`, `wS`, `TS`)

- **Root:** `"relative inline-flex w-fit shrink-0 items-stretch h-control font-sans"`, 32px tall.
  - **Contained** (default) adds `"rounded bg-[var(--cds-segmented-control-track)] p-px"`: 8px radius, white 5% track, 1px padding.
  - **Plain** adds `"gap-[1px]"`.
- **Thumb** (an animated, absolutely positioned element):
  - Base: `"rounded-[calc(var(--cds-radius)-1px)] bg-[var(--cds-segmented-control-thumb)]"`. 7px radius, white 10%.
  - Contained: `"top-px bottom-px [box-shadow:inset_0_0_0_1px_var(--cds-border),0_1px_2px_0_rgb(0_0_0/0.05)]"`.
  - Plain: `"inset-y-0 [box-shadow:inset_0_0_0_1px_var(--cds-border)]"`.
- **Item:** `"relative z-[1] inline-flex h-full items-center justify-center gap-1.5 rounded-[calc(var(--cds-radius)-2px)] text-body font-normal data-[checked]:text-primary hover:text-primary data-[disabled]:opacity-disabled focus-visible:shadow-focus"`. 6px radius, 14/20, `wght` 360, gap 6px.
  - Contained items: text `text-muted` `#898781`.
  - Plain items: text `text-secondary` `#c3c2b7`, with a hover fill of white 7.5% on unchecked items.
  - Text items get `px-md` (12px); icon-only items are `aspect-square`.
  - Checked text is `#f0efec`.

### 5.5 Shared field states

These cover the TextArea and other inputs.

- **Fill:** `bg-fill-field`, white 5%.
- **Ring:** `shadow-field-ring`, `inset 0 0 0 1px rgba(255,255,255,.10)`.
- **Hover:** `shadow-field-hover`, `inset 0 0 0 1px rgba(255,255,255,.20)`.
- **Focus:** `--cds-focus-shadow`.
- **Invalid:** `shadow-field-invalid`. Its value wasn't resolved: **UNKNOWN**.
- **Disabled:** `opacity .4`.

### 5.6 Compact density

For reference only: comfortable is the default.

| Token | Compact value |
|---|---|
| Control height | 24 |
| Radius | 6 |
| Pad xs / sm / md / lg | 4 / 6 / 8 / 12 |
| Gap xs / sm / md / lg | 6 / 8 / 12 / 20 |
| Body | 13 / 19 |
| Footnote | 12 / 15 |
| Caption | 11 / 17 |
| Checkbox | 16 (radius 4) |
| Switch height | 16 |
| Button xs / sm / lg height | 20 / 20 / 28 |

### 5.7 TextArea (`data-cds="TextArea"`, `CDS` `xx`, `j_`, `D_`)

- **Classes:** `"cds-reset w-full cds-input font-normal rounded bg-fill-field shadow-field-ring px-md py-sm transition duration-fast enabled:[&:hover:not(:focus):not([data-invalid])]:shadow-field-hover focus-visible:shadow-focus resize-none font-sans text-body text-primary placeholder:text-muted disabled:opacity-disabled"`.
  - Radius 8.
  - Padding 8px vertical, 12px horizontal.
  - Text 14/20, `#f0efec`. Placeholder `#898781`.
- **Autosize:** `[field-sizing:content]`, with `min-h-[calc(rows*1lh + 2*var(--cds-pad-sm))]`.

### 5.8 TextLink (`data-cds="TextLink"`, `CDS` `Yl`; `CSS` `.cds-text-link`)

- **Colour:** `--cds-text-accent` `#6da7ec`.
- **Underline:** offset 3px. Its colour is `color-mix(currentColor, transparent 60%)`, so 40%, rising to 100% on hover or focus.
- **Radius:** 2px.
- **Transitions:** 60ms `cubic-bezier(.165,.84,.44,1)`.
- **Focus:** focus shadow.

---

## 6. UNKNOWN or not traced

- **`data-cds=AskUserQuestion`:** this attribute doesn't exist in any bundle.
- **Plan viewer markdown:** typography inside the plan viewer pane (`cccc2cf0a` `Lf`/`it`, `size:"sm"`).
- **Unresolved tokens:** `--cds-button-on-content-ring` and `-hover`, `shadow-field-invalid`.
- **Disabled option rows:** the visual of disabled `epitaxy-answer-option` buttons while sending. No class is applied.
- **Placement gate value:** the dock vs inline choice is driven by the feature gate `claudeai_cc_epitaxy_session_presets_main` (§0). Its value isn't in the bundles or local app data.
- **Light mode:** values are out of scope here. The light value of `--cds-fill-secondary-ring` is `--cds-border`, which is why `KO` shows a ring in light mode only.
