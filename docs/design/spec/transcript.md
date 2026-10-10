# Claude desktop, Code tab: transcript components (dark mode)

Traced from Claude's shipped web code (current build, 2026-10-09). All files are in
`/tmp/claude-web-d/` and in `/tmp/specwork/current.txt`. Abbreviations used below:

| Short | File | Holds |
|---|---|---|
| CSS | `c6a992d55-Drv_MyUK.css` | Tailwind v4 utilities, CDS tokens and component rules, `.epitaxy-*` rules, `.prose` |
| DU5 | `c1c1ec7b9-DU5lyQpQ.js` | Code-tab transcript: rows, gaps, file-change card, working mark slot |
| ROOT | `c11959232-DIX11l1F.js` | Code-tab root (`epitaxy-root`), density |
| S2 | `shared-2-4X4u-Rge.js` | CDS `UserMessage` |
| S9 | `shared-9-4ZhNlFs5.js` | CDS `AssistantMessage`, `TurnStatus`, `TurnStatusStep` |
| S11 | `shared-11-DofzRAfw.js` | Clay working mark |
| SF | `shared-frame-BAME2HDg.js` | Icons, shimmer text, `Banner`, row class constants |
| S6 | `shared-6-BoBG7Dp0.js` | Transcript column class |
| C425 | `c425fb3cf-Cc9ycALf.js` | Summary-card container classes |
| C632 | `c63275c0a-Cs5fvhoH.js` | `epitaxy-user-turn` wrapper, user quote card |
| C19E | `c19e90103-BBZkDOzs.js` | Code fence (`epitaxy-codeblock`) |

The reference screenshot (`docs/design/references/claude-code-tab.jpg`) is at **2.191 px per CSS px**
(Retina 2x times Claude zoom 1.0954). Screenshot measurements below have already been divided by 2.191.

---

## 0. Context that sets every number

| Setting | Value in the Code tab | Source |
|---|---|---|
| Density | **compact**. The Code-tab root is wrapped in `density:"compact"` | ROOT: `c(v,{density:"compact",...})` around `"epitaxy-root text-body text-primary break-words select-none h-full w-full flex flex-col"` |
| rem scale | `--cds-rem-scale` = 1 on desktop (the `16/17` value applies only under `@supports (-webkit-touch-callout)`, iOS) | CSS |
| Chat text size | setting `chatTextSize`, default `"m"` (choices s/m/l) | DU5 settings block `default:"m"` |
| Message text size | `oq(textSize) = textSize ?? (density==="compact" ? "md" : undefined)` -> `data-text-size="md"` on messages | S2 `function oq` |
| Transcript width | setting `transcriptWidthChoice`, default `"s"` (Narrow) | DU5 settings `default:"s"` |
| Mode | dark: `--cds-neutral-900` = `#fff`, so alpha steps are white | CSS dark `.cds-root` block |

### Compact-density tokens (dark), resolved

| Token | Value | | Token | Value |
|---|---|---|---|---|
| `--cds-pad-xs` | 4px | | `--cds-gap-xs` | 6px |
| `--cds-pad-sm` | 6px | | `--cds-gap-sm` | 8px |
| `--cds-pad-md` | 8px | | `--cds-gap-md` | 12px |
| `--cds-pad-lg` | 12px | | `--cds-radius` | 6px |
| `--cds-h-control` | 24px | | `rounded-card` | radius + 4 = **10px** |
| `--radius-lg` (`rounded-lg`) | 8px | | `--spacing` | 4px (Tailwind numeric steps) |
| `--cds-font-size-body` / leading | 13 / 19px (base); **14 / 20px** with `data-text-size=md` | | `--cds-font-size-prose` / leading | **14 / 20px** |
| `--cds-font-size-heading` / leading | 14 / 18px | | `--cds-font-size-footnote` / leading | 12 / 15px |
| `--cds-font-size-caption` / leading | 11 / 17px | | `--cds-font-size-code` / leading | 12 / 17px |

### Colors (dark)

| Token | Value | Notes |
|---|---|---|
| `--cds-text-primary` | `#f0efec` | gray-50 |
| `--cds-text-secondary` | `#c3c2b7` | gray-200 |
| `--cds-text-muted` | `#898781` | gray-400 |
| `--cds-text-danger` | `#ec7e7e` | red-300 |
| `--cds-text-accent` | `#6da7ec` | blue-300 (links) |
| `--cds-text-warning` | `#db9300` | |
| `--cds-surface-1` | `#151515` | transcript background (`--epitaxy-transcript-surface` falls back to it). Screenshot: rgb(21,21,21) |
| `--cds-surface-2` | `#1a1a19` | |
| `--cds-surface-3` | `#20201f` | |
| `--cds-alpha-1` = `--cds-bg-neutral` | white 5% | over #151515 = `#212121` |
| `--cds-alpha-2` = `--cds-border` = `--cds-ring-color` | white 10% | over #151515 = about `#2c2c2c` |
| `--cds-alpha-3` = `--cds-border-strong` | white 20% | |
| `--cds-fill-ghost-hover` | white 7.5% | |
| `--cds-fill-accent` (focus) | `#2a78d6` | |
| `--cds-clay` | `#d97757` | working mark |
| `--cds-text-git-added` | `#32d74b` | |
| `--cds-text-git-removed` | `#ff2c56` | |
| `--cds-bg-danger` / `--cds-border-danger` | `#3c0e0e` / `#641919` | |
| `--cds-bg-warning` | `#311a00` | |

### Type

* Sans: `"anthropic-sans"` (`--font-anthropic-sans`), system-ui fallbacks. Mono: `"anthropic-mono"`, then `"SF Mono"`, ui-monospace, Menlo.
* Dark mode uses the variable `wght` axis, not `font-weight` alone (`font-variation-settings: "wght" N`):
  regular / body **360**, medium **460**, semibold **540**, bold **560** (`b`, `strong`, prose headings). `font-weight` stays 400/500/600 for fallback fonts.
* Icons are the Anthropicons variable font (`[data-cds=Icon]:not(svg)`: 1em box, `line-height:1`). Sizes (SF `Po`): xs **12px** (stroke .8), sm **16px** (1), md **20px** (1.2), lg 24, xl 28, xxl 32.

### Transcript typography override (applies to everything in the transcript)

CSS:
```
.epitaxy-root .epitaxy-transcript-typography{--chat-body:calc(.875rem*var(--cds-rem-scale,1));--chat-leading:1.42857;
  --chat-turn-gap:calc(var(--chat-body)*var(--chat-leading)*.75);--chat-item-gap:calc(var(--chat-body)*var(--chat-leading)*.5);
  font-size:var(--chat-body);line-height:var(--chat-leading)}
.epitaxy-root .epitaxy-transcript-typography :where(.text-body):not(button,input,textarea)…,
  … [data-cds=TurnStatusStep]>:where(.text-body){font-size:var(--chat-body);line-height:var(--chat-line,var(--chat-leading))}
… [data-transcript-row] [data-cds=AssistantMessage][data-turn-key], … [data-cds=UserMessage][data-turn-key]
  {--chat-body:var(--cds-font-size-body);--chat-line:var(--cds-leading-body)}
```
Result at the default size: every `text-body` in the transcript is **14px / 20px**. `--chat-item-gap` = **10px**, `--chat-turn-gap` = **15px**.
Small (`data-chat-text-size=s`) = 13px; Large (`l`) = 15px with leading 1.46667 (22px).

---

## 1. Transcript column

Structure: scroll container -> sticky top fade strip -> `div.relative.epitaxy-transcript-typography` (`data-testid="transcript-sizer"`) -> rows (`[data-transcript-row]`, `[data-transcript-column-row]`).

| Property | Value | Source |
|---|---|---|
| Column class | `mx-auto max-w-[calc(var(--max-content-width)+var(--chat-column-gutter-start)+var(--chat-column-gutter-end))] ps-[var(--chat-column-gutter-start)] pe-[var(--chat-column-gutter-end)]` | S6 `vh` |
| Content width | `--max-content-width: var(--chat-column-measure,768px)`; `[data-transcript-width=m]` 960px; `l` 1280px. Default (Narrow) **768px** | S6 `Sh` |
| Gutters | `--chat-gutter:32px` (`.epitaxy-root`) -> start **32px**, end **32px**; max column 832px. Under a 560px-wide tile the gutter drops to 16px | CSS `.epitaxy-root{…--chat-gutter:32px…}` |
| Background | `bg-[var(--epitaxy-transcript-surface,var(--cds-surface-1))]` = `#151515` | CSS |
| Screenshot check | file card and composer outer edges both 767.7px wide; transcript centered in the main pane | measured |

### Top fade
* `[--epitaxy-top-fade-height:32px]` (when `animation-timeline:scroll()` is supported).
* Element: `div.scroll-fade-strip-top [--cds-scroll-fade-size:var(--epitaxy-top-fade-height)] [--cds-scroll-fade-strip-color:var(--epitaxy-transcript-surface,var(--cds-surface-1))]` (DU5).
* Rule (CSS `.scroll-fade-strip-top`): `position:sticky; top:0; height:32px; margin-bottom:-32px; z-index:1; pointer-events:none;`
  `background: linear-gradient(to bottom, #151515, rgba(21,21,21,.85) 13%, rgba(21,21,21,.5) 40%, rgba(21,21,21,.15) 70%, transparent)`.
  Opacity is driven by scroll: animation `cds-scroll-fade-strip-in` over the first 32px of scroll (`animation-range:0px var(--cds-scroll-fade-size)`), so it is 0 at the top of the transcript and 1 once scrolled 32px.

### Vertical rhythm
Source (DU5 `PGe`, `VHe`, `RHe` + shared-13 constants):
* Rows inside one turn: row `padding-bottom: var(--chat-item-gap)` = **10px**.
* Between turns: `pb-[var(--chat-turn-gap)]` = **15px**. When the `g8` class is on the sizer, `--chat-turn-gap` is forced to `calc(var(--spacing)*5)` = 20px, compact 16px (`g8="[--chat-turn-gap:calc(var(--spacing)*5)]! compact:[--chat-turn-gap:calc(var(--spacing)*4)]!"`). Whether `g8` is on in the normal Code tab: UNKNOWN (gated by a runtime flag `_e`/`de`).
* Blocks inside one AssistantMessage: `gap-5 compact:gap-4` = **16px** (S9 `Tw`).
* Row wrapper margin constants (shared-13): turn `mt-6 compact:mt-5` (20px), reply `mt-xs` (6px), item `mt-5 compact:mt-4` (16px).

Screenshot measurements (line-box to line-box, px):
| Between | Measured |
|---|---|
| prose line pitch | 20.1 |
| last prose line -> "Ran N commands" row (24px tall) | about 12 |
| "Ran N commands" row -> next prose line | about 11 |
| list item pitch | 23.5 (20 + 3.5 li margin) |
| file-change card bottom -> user bubble top | 50.7 |
| user bubble bottom -> first assistant line | about 36.5 |

The user-turn spacing (50.7 / 36.5) includes the hidden hover line with message actions; its exact composition is UNKNOWN.

---

## 2. User message bubble

Structure: `div.epitaxy-user-turn` (C632 `xg="epitaxy-user-turn flex w-full flex-col min-w-0 ms-auto items-end"`, with `gap-sm` 8px or `gap-xs` 6px)
-> `div[data-cds=UserMessage][data-text-size=md][data-author]` (S2):
`group/message-row flex w-full min-w-0 flex-col gap-xs font-sans ms-auto items-end`
-> bubble div -> `div.cds-user-message-body` -> text.

Bubble class (S2 `mJ`): `relative flex min-w-0 flex-col gap-xs` + `rq` + `text-heading font-normal break-words select-text` + `text-primary` + `iq` + `bg-[var(--cds-bg-user-message)]`
* `rq` = `rounded-[var(--cds-message-bubble-radius)] px-[var(--cds-message-bubble-pad-x)] py-[var(--cds-message-bubble-pad-y)]`
* `iq` = `max-w-[var(--cds-message-bubble-measure)]`

| Property | Value | Source |
|---|---|---|
| Alignment | trailing (`ms-auto items-end`) | S2, C632 |
| Max width | `--cds-message-bubble-measure: 85%` of the column = 652.8px at 768 | CSS `.cds-root [data-cds=UserMessage]{…--cds-message-bubble-measure:85%}` |
| Width | fits content (screenshot: 634px for a 2-line message) | measured |
| Padding | x `--cds-pad-lg` = **12px**, y `--cds-pad-md` = **8px** | same CSS rule; screenshot 11.4 (+glyph bearing) / 8 |
| Radius | `calc(var(--cds-radius) + .25rem)` = **10px** | same CSS rule |
| Background | `--cds-bg-user-message` = `var(--cds-bg-neutral)` = white 5% -> **#212121** on #151515 | CSS `.cds-root{--cds-bg-user-message:var(--cds-bg-neutral)}`; screenshot rgb(33,33,33) |
| Border | none | |
| Text color | `text-primary` `#f0efec` (`text-[color:…]` personal tint only when `author="self"`) | S2 |
| Text | sans, 14px, wght 360. Class is `text-heading` (14/18 compact) but the screenshot line pitch is **20px**: the 2-line bubble is 56px tall = 2x20 + 2x8. Use 14/20. Which child class sets 20px: UNKNOWN | S2, measured |
| Whitespace | `break-words`; content keeps line breaks | S2 |
| Entrance | `[&_[data-cds=UserMessage]]:animate-code-user-bubble-enter origin-right`: 0.45s `cubic-bezier(.34,1.3,.64,1)`, from `opacity:0; transform:scale(.92) translateY(6px)` to none; none with reduced motion | DU5 `mGe`, CSS keyframes |

Overrides that do **not** apply in the Code tab: `#193c5f` / `#dde8f7`, radius 1.5rem, measure `min(85%,29.5rem)`, pad 1rem/.75rem. They exist in CSS, but no file in the current Code-tab import graph references them. The blue "personal" tint (`--cds-bg-user-message-personal` = blue-800 at 75%, text `#6da7ec`) is used only for `author="self"`. The screenshot confirms the neutral #212121.

States (S2):
* Long message (collapsible): collapses past 300px to `maxHeight = 200px` with `[mask-image:linear-gradient(to_bottom,black_calc(100%_-_3rem),transparent)]`. "Show more" / "Show less" is a ghost `xs` button with `self-start -ms-pad-md`.
* Pending: `animate-pulse text-secondary`. Queued: `text-muted`.
* Failed: row `flex items-center justify-between gap-sm text-caption font-normal select-none` (11/17) with `span.text-danger` "Failed to send" (#ec7e7e) and a Retry button.
* Editing: `bg-surface-1 shadow-card-ring … focus-within:shadow-focus`.

Quote attached to a user turn (C632 `Tg`): `blockquote.line-clamp-6 shrink-0 border-l-2 border-strong pl-sm text-body text-muted whitespace-pre-wrap`, so a 2px left border at white 20% (`border-strong` = `--cds-border-strong`), 6px left padding (`pl-sm` = `--cds-pad-sm`), muted text. The card holding it: `flex flex-col gap-1 max-w-full min-w-0 max-h-[280px] overflow-y-auto p-md text-body`.

---

## 3. Assistant prose

Structure: `div[data-cds=AssistantMessage][data-text-size=md]` (S9 `kw`):
`group/message-row relative flex w-full min-w-0 flex-col gap-xs break-words select-text`
-> `div.flex.min-w-0.flex-col.gap-5.compact:gap-4` (16px between blocks)
-> blocks: `div.prose[data-cds=Prose]` (shared-l-p-m-6 `nw`, size "base" -> no `data-size`), TurnStatus rows, cards.

Message-level variables (CSS `.cds-root [data-cds=AssistantMessage]`):
* `--cds-assistant-message-text-inset: 4px`: `p, dt, h1–h6` get `padding-inline-start: 4px`.
* `--cds-assistant-message-text-stop: clamp(0px, (100% - 384px) * .175, 56px)`: `p, h1–h6, ul, ol, dl` get `padding-inline-end`. At 768px this is **56px**. Screenshot: text stops 57.5px before the column's right edge.
* Cards inside (Card, Banner, Table, …) reset both to 0.

Prose (CSS `.prose` + `@scope(.prose) to (.not-prose,[data-not-prose])`):

| Element | Spec (px at 14px base) |
|---|---|
| Body | sans, **14px / 20px** (`--cds-font-size-prose:.875rem; --cds-leading-prose:1.25rem`, compact), `"wght" 360`, color inherited `#f0efec`, `overflow-wrap:break-word` |
| Paragraph spacing | `--_prose-flow:.75em`: each `p, ul, ol, dl, blockquote, pre, table, figure, details` gets `margin-block-start:.75em` (**10.5px**), end 0; first child 0 |
| After a list | `calc(flow * 2)` = **21px** |
| After a heading | `calc(flow * .667)` = **7px** |
| `strong`, `b` | `font-weight:600`, `"wght" 560` |
| `em`, `i` | italic |
| `del`, `s` | line-through, decoration currentColor 60% |
| Links `a` | color `#6da7ec`; underline; `text-underline-offset:3px`; decoration color = currentColor at 40% (`color-mix(in srgb, currentColor, transparent 60%)`); hover/focus decoration = full currentColor; transition 60ms `cubic-bezier(.165,.84,.44,1)`; radius 2px; focus `outline-offset:2px` + `--cds-focus-shadow` |
| `ul`, `ol` | `padding-inline-start:2em` (28px); `ul` disc -> circle -> square; `ol` decimal -> lower-alpha -> lower-roman |
| `li` | `margin-block-start: flow * .333` (**3.5px**); `padding-inline-start:.5em` (7px); `li::marker` color `#c3c2b7` (text-secondary) |
| `h1` | 1.75em = **24.5px**, line-height 1.25; margin-top = .75em x 3 (em of the heading) = 55.1px |
| `h2` | 1.375em = **19.25px**, lh 1.25; margin-top .75em x 2.5 = 36.1px |
| `h3` | 1.125em = **15.75px**, lh 1.3; margin-top .75em x 2 = 23.6px |
| `h4` | 1em = 14px, lh 1.3; x 1.667 = 17.5px |
| `h5` / `h6` | .875em = 12.25px, lh 1.3; `h6` color text-secondary |
| Headings weight | 600 / `"wght" 560`; sans |
| Inline `code` | mono; color `var(--cds-prose-code-color, var(--cds-text-danger))` = **#ec7e7e** (nothing in the Code tab sets the var); bg white 5%; border `.5px solid` white 10%; radius `.4em`; padding `.0625em .25em`; `font-size:.9em` (12.6px); `line-height:1`; `white-space:pre-wrap` |
| `blockquote` | `border-inline-start:4px solid` white 10%; color `#c3c2b7`; `margin-inline:.5em 0` (7px); `padding-inline-start:1em` (14px) |
| `hr` | `border-block-start:.5px solid` white 10%; margin-top 21px; `margin-inline:.375em` |
| `table` | `border:1px solid` white 10%; radius `--cds-radius` 6px; width 100%; `th, td` padding `.4375em .75em` (6.1 / 10.5px); `th` bg white 5%, weight 500 / `"wght" 460`; row dividers 1px white 10% |
| `kbd` | mono .8125em; border 1px white 10%, bottom 2px; radius 6px; bg white 5%; padding `.0625em .375em` |
| `mark` | bg `color-mix(#fab219 33%, transparent)`, radius 2px |

### Code fence (`epitaxy-codeblock`, C19E)
* Outer: `epitaxy-codeblock relative max-w-full` + `w-full` (or `w-fit`).
* Box: `div.epitaxy-diff.epitaxy-fence.rounded-lg.overflow-clip`: radius **8px**. Border via CSS `.epitaxy-fence:after{content:"";border-radius:inherit;box-shadow:inset 0 0 0 1px var(--cds-border), inset 0 0 0 1px var(--epitaxy-transcript-surface)}` (1px white 10%), active for `[data-code-theme-dark=claude-dark]`.
* Text: `--diffs-font-size: var(--cds-font-size-code)` **12px**, `--diffs-line-height` **17px**, mono. Gaps: inline `--cds-pad-md` 8px, block `--cds-pad-xs` 4px.
* Background: about `#1a1a1a` measured (≈ surface-2 `#1a1a19`). The variable that sets it: UNKNOWN (diff renderer).
* Language label: `flex h-control … font-sans text-caption text-muted` (11px, `#898781`), plus a copy button.

---

## 4. Collapsed tool/status line ("Ran 2 commands ›")

Component: CDS `TurnStatus` (`[data-cds=TurnStatus]`, S9 `HT`), and per step `TurnStatusStep` (S9 `MT`).

Structure:
```
div[data-cds=TurnStatus] .group/status.flex.w-full.min-w-0.flex-col
  div (row)  [rj + items-center + nj] style --cds-outset-x: var(--cds-pad-xs)
    span label        "Ran 2 commands"
    button (toggle)   -> span chevron icon
  [panel when open]   expanded step list (§5)
```

Row classes (SF):
* `rj` = `flex min-w-0 items-center gap-xs text-start font-sans text-body font-normal`
* `nj` = `w-stretch px-xs ms-[calc(var(--cds-assistant-message-text-inset,0px)_-_var(--cds-outset-x,0px)_-_var(--cds-turn-status-hang,0px))] me-[calc(var(--cds-assistant-message-text-stop,0px)_-_var(--cds-outset-x,0px))]`
* `aj` = `py-[calc((var(--cds-h-control)_-_1lh)_/_2)]` (step rows)
* expandable: `relative isolate rounded`, `select-none`; focus `rounded outline-none focus-visible:[box-shadow:inset_0_0_0_1px_var(--cds-fill-accent)]`

| Property | Value |
|---|---|
| Height | 24px (`h-control`): 20px line + 2px top/bottom |
| Horizontal | padding-inline 4px; margin-start 4 - 4 = **0**, so the label's left edge lines up with the prose text (4px inset). Screenshot: label at x=5.5px vs prose 5.0px (glyph bearing) |
| Gap label -> chevron | `gap-xs` 6px with the toggle's `-ms-1` (-4px), icon centered in a 12px box. Measured glyph-to-glyph ≈ 8px |
| Label text | sans **14px / 20px**, `"wght" 360`, **`#898781`** (text-muted). Screenshot rgb(136,135,129) |
| Hover (row) | label -> `#c3c2b7` (`group-hover/status:text-secondary`, `group-hover/step:text-secondary`); chevron -> text-secondary |
| Open | label `group-data-[open]/status:text-secondary`; chevron `rotate-90 text-secondary` |
| Chevron | toggle button `Yw` = `cds-reset -ms-1 inline-flex h-[1lh] shrink-0 items-center self-start border-0 bg-transparent p-0` + `Xw` (`after:absolute after:inset-0 after:rounded`, focus ring `inset 0 0 0 1px #2a78d6`). Icon span `Kw`: `inline-flex h-[1lh] items-center justify-center text-muted transition-transform duration-fast` (60ms). Icon **Anthropicons `CaretRightFilled` (U+F011), size xs = 12px**, color `#898781`. It renders as a small right chevron (measured glyph ≈ 4 x 7px) |
| Focus | inset 1px `#2a78d6` ring on the row, rounded 6px |
| Underline variant (navigating rows) | `cds-text-link-underline`, line transparent, on hover line = currentColor |

Busy/outcome words on a step: span `shrink-0` + tone class; tone colors: UNKNOWN (strings in SF `ej` not resolved).

---

## 5. Expanded step list (when "Ran N commands" is opened)

S9 `BT` / `AT`:
* Panel wrapper: `pt-sm pb-xs` -> 6px top, 4px bottom.
* Card: `flex min-w-0 flex-col divide-y overflow-y-clip rounded-card shadow-card-ring`: radius **10px**, ring `inset 0 0 0 1px` white 10% (`shadow-card-ring` = `inset 0 0 0 var(--cds-ring-inner) var(--cds-ring-color)`, inner 1px, outer 0). Dividers 1px, border color `--cds-border` (white 10%). Background: transparent (#151515 shows through).
* Each cell: `min-w-0 px-md py-sm` -> **8px x 6px**, text inset reset to 0.
* Each cell holds a `TurnStatusStep` row (same row spec as §4, `text-muted` label; a meta span `text-primary` truncated, `py-[0.125em] -my-[0.125em]`).
* Step detail body (`AT`): `flex min-w-0 items-start gap-xs font-sans text-body font-normal text-secondary not-italic` (14/20, `#c3c2b7`); spacing "row" adds `pt-xs` (6px), "card" `pt-sm` + `pb-[calc(var(--cds-pad-md)-var(--cds-pad-sm))]` (6 / 2px), "cell" `py` 2px.

---

## 6. File-change card ("index.html +141 −0 ›")

DU5 `vFe` -> single file `a2` -> row `i2`; containers C425.

```
div.mt-pad-xs + Qx  (card)
  ul.flex.w-full.min-w-0.flex-col  (Nx)
    li  X0
      button Q0
        span $0: [icon span][label span][detail span?]
      span r2: span.flex.items-center.gap-2.5 [counts Y0][chevron mFe]
```

| Part | Classes | Values |
|---|---|---|
| Card | `mt-pad-xs` + `flex w-full select-text flex-col gap-1 rounded-lg px-md py-xs shadow-[inset_0_0_0_1px_var(--cds-border)]` | margin-top 4px; padding 8px x 4px; radius **8px**; border = inset 1px white 10% (screenshot ≈ #2d2d2d line); background none (#151515); height **36px** (measured 35.6) |
| Row `li` | `relative -mx-pad-xs flex min-w-0 items-center gap-1 px-xs` | margin-inline -4px, padding-inline 4px, gap 4px |
| Button | `flex min-h-7 min-w-0 grow items-center gap-xs py-0.5 before:absolute before:inset-0 before:rounded-[5px] before:content-[''] text-left focus-visible:outline-hidden hover:before:bg-fill-ghost-hover focus-visible:before:shadow-focus` | min-height **28px**, padding-block 2px, gap 6px. Hover: overlay white 7.5%, radius **5px**, covering the whole row (the `li` is the positioned ancestor). Focus: `--cds-focus-shadow` |
| Icon | `span.flex.shrink-0.text-muted` > file-type icon `Woe{fileName,size:"sm"}` | 16px box. Per-type glyph color (orange `#` for HTML in the screenshot): UNKNOWN |
| File name | `min-w-0 truncate text-body text-primary` | 14/20, `#f0efec`, wght 360, truncates |
| Folder hint (optional) | `ms-xs text-footnote text-muted` | 12/15, `#898781`, margin-start 6px |
| Right group | `pointer-events-none relative flex shrink-0 items-center gap-1` > `flex items-center gap-2.5` | counts -> chevron gap **10px** |
| Counts | `flex shrink-0 items-center gap-0.5 text-body tabular-nums` | 14/20, tabular figures, gap 2px. `+141` in `text-git-added` **#32d74b**; `−0` uses U+2212 MINUS, `text-git-removed` **#ff2c56** |
| Chevron | `span.flex.shrink-0.text-secondary` > icon `CaretRight`, `customSize:14` | 14px, `#c3c2b7` |
| Inset check | icon box starts 8px inside the card (glyph 12px), name at 30px, chevron glyph 12.3px from the right edge | measured |

Several files: a header row `i2{icon:"ChangesPlusMinus", label:"Edited N files", meta:counts, chevron}`, then the first 3 files, then "Show N more" (`min-w-0 truncate text-body text-secondary` with a 16px `size-4` spacer). The "Undo" ghost button uses `text-footnote`.

---

## 7. Working indicator ("··· Using lcu: js 1m 15s ›")

A `TurnStatus` row with `state:"busy"` and a `leading` mark. DU5 `sHe` -> S11 `pp{mark:"clay",phase:"working"}` -> `hp` -> `up` -> `ap` (`[data-cds=WorkingMark]`).

| Part | Spec |
|---|---|
| Mark box | `relative flex size-[20px] min-h-[20px] min-w-[20px] shrink-0 items-center justify-start` (S11 `fp`) |
| Mark | `span[data-cds=WorkingMark].relative.block.shrink-0.select-none`, 20 x 20, `color: var(--cds-clay, #d97757)`. Animated from per-activity sprite sheets (`backgroundImage` strips, frame timing from the sheet). Frame contents: UNKNOWN (raster). Screenshot frame: three clay dots, group 11.4px wide x 3.7px tall, pitch ≈ 4.6px, middle dot brighter |
| Static fallback | `span.absolute.inset-0.m-auto.block.rounded-full.bg-current`, size 20 x 0.35 = **7px** clay circle |
| Mark -> label | row `gap-xs` 6px after the 20px box. Measured label start 29px after the dots' left edge |
| Label | Shimmer text, variant "secondary" (SF `qA`, `GA`/`kA`). Dark: fill `#898781`; sheen `linear-gradient(120deg, #898781 37.5%, color-mix(in srgb, #898781 30%, white) 50%, #898781 62.5%)` (peak ≈ `#dcdbd9`), `background-size:400% 100%`, `bg-clip-text`. Animation `cds-shimmer-text-shine 3s linear infinite`: 0–15% hold at `background-position:83.333% 0`, eases `cubic-bezier(.714,.121,.211,.888)` to `16.667% 0` at 85%, holds to 100%. Reduced motion: plain `#898781`. 14/20, wght 360 |
| Elapsed ("1m 15s") | in the same row after the label; measured color ≈ `#8e8e8c` (muted). Class: UNKNOWN |
| Chevron | as §4 (12px CaretRightFilled, muted) |

The older "Working…" dot animation (`cc-working-dots`, 1.4s, 0.2s stagger) belongs to the project overview, not the session transcript.

---

## 8. Error and notice lines

* Danger text color: `--cds-text-danger` **#ec7e7e**.
* Failed user message: §2 (caption 11/17, `text-danger`).
* Message warning / stop notice (S11 `zp`/`Up` -> SF `Banner`, `data-testid="message-warning"`), placed with S11 `Cp`: `!w-full mx-[calc(var(--msg-block-inset,0.5rem)*-0.5)] mt-4 mb-1` (margin-inline -4px, top 16px, bottom 4px).
* Banner root (SF `Gw`): `flex items-start gap-xs py-md font-sans text-body font-normal px-lg rounded-card` + variant:

| Variant | Classes | Resolved |
|---|---|---|
| neutral | `bg-surface-1 text-primary shadow-card-ring` | bg #151515, text #f0efec, inset 1px white 10% |
| warning | `bg-warning text-warning shadow-ring-warning` | bg #311a00, text #db9300, ring color: UNKNOWN |
| danger | `bg-danger text-danger shadow-ring-danger` | bg #3c0e0e, text #ec7e7e, ring inset 1px #641919 |

Padding 12px x 8px; radius 10px; gap 6px; text 14/20. Icon: neutral `Info` (`text-secondary`), warning/danger `Warning`, in `flex min-h-[1lh] shrink-0 items-center`. Action slot: `flex shrink-0 items-center gap-xs min-h-control my-[calc((1lh-var(--cds-h-control))/2)] -ms-[2px]`. Dismiss: ghost icon-only `X`.

---

## 9. Card-like blocks

* `[data-cds=Card]`: `.cds-card-fill` background `#151515` (surface-1). With a `CardLink`, hover -> `#1a1a19` (surface-2). Press: scale transition `.45s` spring; radius `calc(var(--cds-radius)+.25rem)` = 10px (CSS).
* Generic outlines in the Code tab: `.epitaxy-card-outline` = `box-shadow:0 0 0 1px var(--cds-border)`; `-inset` variant = inset 1px; `-overlay` = `outline:1px solid var(--cds-border); outline-offset:-1px`.
* Summary-card variant (C425 `H`): `epitaxy-summary-card-control-text flex w-full select-text flex-col gap-1 rounded-card px-md py-xs shadow-[inset_0_0_0_1px_var(--cds-border)]` (radius 10px instead of 8px). Header row: `flex h-control min-w-0 items-center justify-between gap-sm px-xs`; divider `-mx-[calc(var(--cds-pad-md)-1px)] h-px bg-alpha-2`.

---

## UNKNOWN / not traced

* Whether `g8` (turn gap 16px compact) is on in the normal Code tab; the composition of the measured 50.7 / 36.5px around user turns (hover action line).
* The exact child class that gives the user-bubble text 20px leading (bubble class says `text-heading`, 14/18).
* File-type icon glyph colors (`Woe`).
* Working-mark sprite frames.
* Elapsed-time text class.
* Busy/outcome tone colors on steps.
* Code fence background variable.
* `shadow-ring-warning` color.
