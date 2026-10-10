# Claude desktop: Settings window, pages and controls (dark mode, numeric spec)

Read from Claude's own shipped web code (current build, cached 2026-10-09 21:25; every file below is on `/tmp/specwork/current.txt`). Each value is traced to a class string and the CSS rule it compiles to. **UNKNOWN** means the source wasn't in the cache or couldn't be traced. Sizes are CSS px (1 CSS px = 1 pt natively at 100% zoom; the user's Claude zoom is ×1.0954, see global-sidebar-titlebar.md §0).

Tokens, weights and text roles are the ones in global-sidebar-titlebar.md §1 and forms-buttons.md §0.1. This file only restates the values it uses.

## 0. Sources

| Short name | File | What it holds |
|---|---|---|
| `NAV` | `shared-20-BUWXZWmU.js` | Settings modal shell `sT`, modal host `aT`, nav `Uw`, nav item `Kw`, group list `qw`, stacked header `Qw`/`$w`, section table `dw` (ids, labels, icons, groups), placeholder pane `cT`/`hT`/`mT`, error pane `yT` |
| `CONTENT` | `cc011544b-CJa-Na7X.js` | `SettingsModalContent` (`cn`), nav search `SettingsNavSearch` (`Yt`), search result row `Jt`, section host `Nt`, "opens in a full page" empty state `St`, section → chunk map |
| `PRIM` | `shared-1-DginuSTZ.js` | Settings primitives: row `Ud` (export `Sv`), group/section `Jd` (`_v`), nest card `Wd` (`vv`), rail `Gd` (`xv`), save bar `Xd` (`Cv`), page title `tf` (`yv`), plain-rows panel `Zd` (`mv`), search-jump highlight `Hd` |
| `CODE` | `c71860c77-BiZd4YV6.js` | The **Claude Code** settings page (the only settings page whose chunk is in the cache). Real uses of every primitive: switches, selects, text inputs, segmented control, list management, destructive actions |
| `DECL` | `c51ac4bf6-YOmtdJSJ.js` | Declarative setting rows: control by kind (switch / segmented / select / text), scope badge, modified dot, hover-revealed Reset |
| `CDS` | `shared-frame-BAME2HDg.js` | CDS components: TextInput `Nb` (+ field `HD`/`BD`/`ID`/`LD`/`RD`/`zD`), Combobox/Select `Kk`/`WO` (trigger `iO`/`aO`/`oO`/`lO`, popup `mO`/`hO`, item `bO`, group label `TO`, separator `CO`), Switch `HE`, SegmentedControl `kD`, Badge `_s`, InfoTip `IT`, TextLink `xd`, Button `Gl`, Dialog `o_`, ConfirmationDialog `l_`, CdsRoot `co`, panel helper `Hm` |
| `CSS` | `c6a992d55-Drv_MyUK.css` | Tailwind utilities, CDS tokens, `.settings-group-dividers`, `.feature-anchor-*` |

Which pages could be traced: only **Claude Code** (`CODE`) and the shared primitives. The chunks for General, Account, Privacy, Capabilities, Connectors, System, Extensions and Developer (`c71860c77-*` other than `BiZd4YV6`, `cc5f29bb3-…`, `c953053b7-…`) are referenced by `CONTENT` but are **not in the cache**. Their row content is UNKNOWN; they use the same primitives (`ca25db325-D80Owk_L.js` and `cd19fedd2-CbIQfl9D.js` hold only their search index: labels like "Theme", "Chat font", "Interface font", "Transcript text size" Small/Medium/Large, "Transcript width" Narrow/Medium/Wide).

### 0.1 Density: comfortable

- The modal is rendered by `aT` inside CDS `Root` (`co`) with only `mode` set. `co` computes `densityOverride ?? (coarsePointer ? "comfortable" : density ?? context)`. No ancestor of the modal passes `density`, so it takes the context default `comfortable` (the compact density is only the sidebar's, see global-sidebar-titlebar.md §1.1).
- So every value below uses **comfortable** tokens.

### 0.2 Tokens used (dark, comfortable)

| Token | Value |
|---|---|
| `--cds-h-control` | 32 (size sm 28, xs 24, lg 40) |
| `--cds-h-control-nested` | 22 (sm 20, xs 18, lg 28) |
| `--cds-radius` (`rounded`) | 8 (sm 7, xs 6, lg 10) |
| `rounded-card` | radius + 4 = 12 |
| `--cds-pad-xs / sm / md / lg / xl` | 6 / 8 / 12 / 16 / 24 |
| `--cds-gap-xs / sm / md / lg / xl` | 8 / 12 / 16 / 28 / 40 |
| `--spacing` | 4 (so `pt-2` = 8, `gap-1` = 4, `gap-1.5` = 6, `ps-6` = 24, `pt-8` = 32) |
| body | 14 / 20 |
| footnote | 13 / 17 |
| caption | 12 / 17 |
| heading | 15 / 20 |
| title | 22 / 28 |
| `--cds-surface-1` | `#151515` |
| `--cds-surface-2` | `#1a1a19` |
| `--cds-surface-3` | `#20201f` |
| `--cds-text-primary / secondary / muted` | `#f0efec` / `#c3c2b7` / `#898781` |
| `--cds-text-accent` | `#6da7ec` |
| `--cds-text-danger` | `#ec7e7e` |
| `--cds-alpha-1 / 2 / 3` | white 5% / 10% / 20% |
| `--cds-fill-ghost-hover` | white 7.5% |
| `--cds-fill-ghost-selected` | white 15% |
| `--cds-fill-field` | white 5% |
| `--cds-fill-field-ring` | white 10% |
| `--cds-border-strong` | white 20% |
| `--cds-fill-accent` | `#2a78d6` |
| `--cds-fill-danger` | `#d03b3b` |
| `--cds-fill-control` | white 10% |
| `--cds-backdrop` | `#00000080` |
| `--cds-focus-shadow` | `inset 0 0 0 1px #0b0b0b, 0 0 0 1px #2a78d6, 0 0 6px 1px rgba(24,79,149,.60)` |
| `shadow-panel-sm` | `inset 0 0 0 1px rgba(255,255,255,.10), 0 1px 2px rgba(11,11,11,.06), 0 2px 8px rgba(0,0,0,.24)` |
| `shadow-panel` | `inset 0 0 0 1px rgba(255,255,255,.10), 0 8px 24px rgba(0,0,0,.32), 0 2px 6px rgba(0,0,0,.20)` |
| `--cds-dur-fast / snap / base` | 60 / 120 / 200 ms |
| `--cds-ease-out` | `cubic-bezier(.165,.84,.44,1)` |

Dark `wght` axis: regular 360, `font-medium` 460, `font-semibold` / `*-semibold` 540, bold 560. Anthropic Sans, opsz 16 (auto), GRAD 0.

## 1. Settings window (modal)

Settings is a modal dialog over the app, not a route page. `/settings/*` routes open it (`CODE` `$a` → `wt` with `section:"claude-code"`).

### 1.1 Shell (`NAV` `sT`)

- **Backdrop:** Dialog backdrop `wg`: `fixed inset-0 bg-backdrop`, `#000000` at 50%, fades with the popup (`transition-opacity duration-base ease-out`).
- **Popup classes:** `fixed inset-0 m-auto flex h-[calc(100dvh-2rem)] w-[calc(100vw-2rem)] {size} overflow-hidden dark:border dark:border-alpha-1 rounded-card bg-surface-2 shadow-panel-sm cds-reset text-body text-primary outline-none transition-[opacity,scale] duration-base ease-out data-[starting-style]:opacity-0 data-[starting-style]:scale-[0.98] data-[ending-style]:opacity-0 data-[ending-style]:scale-[0.98]`.
- **Size:**
  - In the desktop app (`hasRail` = `isClaudeApp()` and not stacked and not focused): `max-h-[max(50rem,min(60rem,calc(100dvh-6rem)))] max-w-[max(1024px,min(1280px,calc(100vw-6rem)))]`. Width = min(window − 32, max(1024, min(1280, window − 96))). Height = min(window − 32, max(800, min(960, window − 96))).
  - Otherwise `max-h-[50rem] max-w-[1024px]`.
  - When the title bar inset `s > 0`, inline `height: calc(100vh - 2·s px)`.
  - Centred (`inset-0 m-auto`).
- **Surface:** radius 12. Fill `#1a1a19`. Border 1px white 5% (`dark:border-alpha-1`). Shadow `shadow-panel-sm` (inset 1px white 10% ring plus the small drop shadow). The 1px border and the 1px inset ring both draw.
- **Open/close motion:** opacity 0 → 1 and scale 0.98 → 1, 200 ms `cubic-bezier(.165,.84,.44,1)`.
- **Layout:** row: nav (§1.2) | content pane (§1.4). Below 768 px wide (`(max-width: 767px)`) it stacks (`flex-col`) and the nav becomes a header with tabs (§1.3).

### 1.2 Left nav (`NAV` `Uw`)

**Container** `<nav>`: `flex w-48 shrink-0 flex-col gap-sm border-e border-alpha-2 bg-surface-1`.

- Width **192**. Fill `#151515` (darker than the content `#1a1a19`). Right border 1px white 10%. Vertical gap 12 between its parts.
- First child: the "Settings" title, `sr-only` (not visible).

**Search field** (`CONTENT` `Yt`), wrapper `shrink-0 px-md pt-md` (12 left/right, 12 top):

- Field: `flex h-control w-full cursor-text items-center gap-sm rounded px-sm bg-fill-field shadow-field-ring transition duration-fast [&:hover:not(:focus-within)]:shadow-field-hover has-[:focus-visible]:shadow-focus`.
  - 168 × 32, radius 8, padding 8 left/right, gap 12.
  - Fill white 5%. Ring inset 1px white 10%; hover inset 1px white 20%; focus = focus shadow.
- Leading icon `Search` (Anthropicons), size md 20 (glyph wght 433.3), `text-muted` `#898781`.
- Input: `cds-input hide-focus-ring min-w-0 flex-1 border-0 bg-transparent p-0 text-body text-primary outline-none placeholder:text-muted`. 14/20, wght 360, `#f0efec`. Placeholder "Search", `#898781`.
- ⌘F / Ctrl+F focuses and selects it.
- **Results popup:** Popover `side:"bottom" align:"start" sideOffset:4`, class `!max-w-none w-[280px]`; inner list `max-h-[min(320px,var(--available-height))] overflow-y-auto p-1` (4 padding).
  - Row: menu-item class (`nx`) plus `h-auto !px-1 py-1.5 text-left`: 4 left/right, 6 top/bottom, radius 8, 14/20, highlighted white 7.5%.
  - Row content: `flex items-center gap-sm` → section icon (md 20, `text-secondary`) + label `min-w-0 flex-1 truncate`. A matched sub-row shows below as `truncate ps-[calc(20px+var(--cds-gap-sm))] text-footnote text-muted` (indent 32, 13/17, `#898781`).
  - Child match rows (`{row} in {section}`): `flex min-w-0 flex-1 items-center gap-sm ps-[calc(20px+var(--cds-gap-sm))]` (indent 32). "+N more" is `text-muted`.
  - **Empty:** `flex min-h-[120px] flex-col items-center justify-center gap-sm px-md text-center text-muted` → icon `SearchCircle` size xl (28) + "No matching settings" `text-body`.

**Group list:** `flex min-h-0 flex-1 flex-col gap-sm overflow-y-auto scroll-fade-y scroll-fade-size-6 px-md pb-md`.

- Padding 12 left/right, 12 bottom. Gap 12 between every child (group title, list, next title…). Edge fade 24 px top and bottom (`--cds-scroll-fade-size` = 24), shown only when scrolled.

**Group title:** `px-sm pt-md text-caption text-muted`.

- 12/17, wght 360, `#898781`, left padding 8, top padding 12.
- Groups and titles (unified nav, `NAV` `nw` with order `["account","customize","products","desktop"]`):
  - **Account:** General, Account, Privacy, Billing, Usage, Capabilities, Memory, …
  - **Customize:** Plugins / Skills / Connectors, System prompt.
  - **Products:** Claude Code, Cowork, Claude in Chrome.
  - **This computer:** System, Extensions, Developer.
  - The non-unified variant has one untitled group, then "This computer", then "Customize".
- Optional trailing groups: "Organization" admin link and "Platform" → "API keys" link: the same row, with a trailing `ArrowUpRight` md 20 icon in `text-muted`.

**Item list:** `<ul class="flex flex-col gap-px">`, 1 px between items.

**Nav item** (`NAV` `Kw`): `<button class="flex h-control w-full items-center gap-sm rounded px-sm text-left text-body …">`.

- **Geometry:** 168 × 32, radius 8, padding 8 left/right, gap 12.
- **Icon:** md, 20 px glyph, `shrink-0 text-secondary` `#c3c2b7` in every state.
- **Label:** `min-w-0 flex-1 truncate`, 14/20.
- **Trailing:** optional badge, then the "new items shared" dot (`Lw`: a `ready` status dot, 6 px `#2a78d6`, `ms-1.5`).

| State | Class (`shared-19` `gg`) | Fill | Text | Weight |
|---|---|---|---|---|
| inactive | `text-secondary` | none | `#c3c2b7` | 360 |
| inactive hover | `hover:bg-fill-ghost-hover hover:text-primary` | white 7.5% | `#f0efec` | 360 |
| active (`aria-current=page`) | `bg-fill-ghost-selected font-medium text-primary` | white 15% | `#f0efec` | **460** |
| disabled | `pointer-events-none cursor-default opacity-50` | none | 50% opacity | 360 |

A disabled item gets a tooltip with the reason, on the inline-end side.

**Section icons** (Anthropicons names, traced from `NAV` icon objects):

| Section | Icon |
|---|---|
| General | `Settings` |
| Account | `UserCircle` |
| Privacy | `LockShield` |
| Billing | `CreditCard` |
| Usage | UNKNOWN |
| Insights | `ChartLine` |
| System prompt | `Prompt` |
| Capabilities | `Tool` |
| Memory | `Memory` |
| Design systems | `Palette` |
| Reflect | `Sunset` |
| Time limits | `MoonStars` |
| Claude Code | `Code` |
| Cowork | `Tasks` |
| Import | `Download` |
| Claude in Chrome | `Globe` |
| AI fluency | `GraduationCap` |
| Teachers | `Book` |
| System (desktop) | `Computer` |
| Extensions | `Plugin` |
| Developer | `Wrench` |
| Plugins | `Plugin` |
| Skills | `Scroll` |
| Connectors | `Connectors` |
| Organization | `Organization` |
| API keys | `Key` |

**Loading placeholder for the search field** (`Hw`): `flex h-control items-center` holding a 100%-wide × 32 skeleton.

### 1.3 Stacked header (window narrower than 768 px; `NAV` `Qw`)

- `<header class="flex shrink-0 flex-col gap-sm border-b border-alpha-2 bg-surface-1 px-md pt-md pb-sm">`: padding 12 left/right, 12 top, 8 bottom; gap 12; bottom border 1px white 10%.
- Top row: `flex items-center justify-between gap-md`. The "Settings" title is `min-w-0 text-heading font-medium font-header text-primary` (15/20, wght 460). The Close button sits at the end.
- Below it, CDS `Tabs.List` with every section as a tab: `-mx-px overflow-x-auto px-px [scrollbar-width:none]`. The Tabs visual is not traced here.

### 1.4 Content pane (`CONTENT` `cn`)

- **Root:** `flex min-h-0 min-w-0 flex-1 flex-col bg-surface-2` (`#1a1a19`).
- **Header row** (when not a customize page): `flex shrink-0 items-center justify-between pl-xl pr-md pt-md pb-sm`.
  - Padding: left 24, right 12, top 12, bottom 8.
  - Left: an empty slot `flex min-w-0 items-center` that subpages fill with a back control.
  - Right: Close = ghost, icon-only, base Button with icon `X` (32 × 32, icon 20 at wght 433.3, hover fill white 7.5%, radius 8, no tooltip).
  - Row height = 12 + 32 + 8 = **52**.
  - **There is no page title in the modal.** The nav's selected item names the page. (`PRIM` `tf`, the page title, is defined but none of the cached pages import it; see §2.7.)
- **Banner slot:** `shrink-0 px-xl` (24 left/right), holding an identity-verification Banner (`w-full mb-6`, 24 below) only when needed.
- **Scroll area:**
  - Classes: `relative min-h-0 flex-1 overflow-x-hidden overflow-y-auto px-xl pb-lg pt-2 [scrollbar-gutter:stable]`.
  - Padding: 24 left/right, 8 top, 16 bottom. The scrollbar gutter is always reserved.
  - **No max width.** The column fills the pane: up to 1280 − 192 − 48 = 1040 px.
  - It also carries `[&_[data-settings-section]]:gap-4 [&_[data-settings-section]]:mb-4 [&_[data-settings-section]]:pb-4 [&_[data-settings-section-title]]:text-heading-medium [&_[data-settings-primary-text]]:text-body [&_[data-settings-section-subtitle]]:text-footnote [&_[data-settings-section-subtitle]]:text-secondary` for legacy page markup. Those attributes aren't used by the cached Claude Code page.
- **Top fade** (first child of the scroll area): `pointer-events-none sticky -top-2 z-[1] -mx-xl -mt-2 h-2 bg-gradient-to-b from-[var(--cds-surface-2)] to-transparent`.
  - An 8 px strip, full width (bleeds the 24 padding), from `#1a1a19` to transparent.
  - It sticks 8 px above the scroll top, so scrolled content fades under the header row.
- **Switching sections:** the old content stays with `opacity-60 transition-opacity` and `inert` while the next chunk loads.

### 1.5 Pane-level states

- **Placeholder / skeleton:** `aria-busy`, same root `cT`, header row `mT` (same classes as §1.4), body `min-h-0 flex-1 overflow-hidden px-xl pb-lg pt-2 [scrollbar-gutter:stable]`. Skeleton blocks are CDS `Skeleton` (not detailed here).
- **Load error** (`NAV` `yT`):
  - Container: `flex min-h-0 flex-1 flex-col items-center justify-center gap-md px-xl pb-lg text-center`.
  - Text block `flex flex-col gap-xs` (gap 8): "Settings couldn't load" in `text-heading-medium text-primary` (15/20, wght 460), then "A newer version of Claude may be available…" in `text-body text-secondary` (14/20, `#c3c2b7`).
  - Then a secondary base Button "Reload". Gap 16 between the text block and the button.
- **Section that opens in a full page** (`CONTENT` `St`):
  - Container: `flex min-h-full flex-col items-center justify-center gap-md p-lg text-center` (gap 16, padding 16).
  - Icon disc `flex size-12 items-center justify-center rounded-full bg-fill-control text-secondary`: 48 px circle, white 10%, icon `ArrowUpRight` size lg (24) in `#c3c2b7`.
  - Text `text-body text-secondary`, then a secondary base Button "Open".

## 2. Settings page primitives (`PRIM`)

### 2.1 Section / group (`Jd`, export `_v`; used as `Me` in `CODE`)

```
<section id class="mb-xl last:mb-0 {className}" data-settings-section-titled?>
  [header: data-settings-group-header]
  <div class="settings-group-dividers [&>:not([role=group]):not([data-cds=DataTable]):not([role=treegrid]):not([data-settle-slot])]:py-md">children</div>
</section>
```

- **Spacing between sections:** 40 below each (`mb-xl`), 0 after the last.
- **Header:** `mb-md flex items-start justify-between gap-lg`. 16 below, 28 gap to the action.
  - With `leading` and no children it becomes `flex items-center justify-between gap-lg` with no margin.
  - Title column: `flex min-w-0 flex-col gap-1` (gap 4).
  - **Title** `<h3 class="text-heading-semibold text-primary settings-row-title self-start outline-none">`: **15/20, wght 540, `#f0efec`**.
  - A title adornment sits in `flex items-center gap-xs self-start` (gap 8).
  - **Description:** `text-footnote text-secondary`, **13/17, wght 360, `#c3c2b7`**.
  - **Action slot:** `flex shrink-0 items-center gap-sm` (gap 12), top-aligned to the title.
- **Leading** (optional icon or avatar beside the whole section): `flex items-start gap-md` (16) with `shrink-0` leading and `min-w-0 flex-1` body.
- **Dividers between rows** (`CSS`): `.settings-group-dividers>:where(:not(:first-child)){border-top:1px solid var(--cds-alpha-1)}`.
  - A **1px line, white 5%** (over `#1a1a19` ≈ `#252524`), full width of the column, on top of every child except the first.
  - No line before or after a Banner, DataTable, treegrid or nest card (`[data-settings-nest]`), nor directly after one (`border-top-width:0` rules).
  - `dividers={false}` drops the class (no lines).
- **Non-row children** (anything that isn't `role=group`) get `py-md` (12 top and bottom).
- **No card, fill or ring** around a group. Groups sit directly on the `#1a1a19` pane; only nests (§2.4) are boxed.

### 2.2 Setting row (`Ud`, export `Sv`; used as `Z` in `CODE`)

```
<div role="group" data-settings-row
     class="flex items-center justify-between gap-lg py-md {indent ? 'ps-lg'} {className}">
  [leading?] <div class="flex min-w-0 flex-1 flex-col justify-center gap-1">
                <div id=label class="text-body text-primary"><span class="settings-row-title inline-block align-top">Label</span></div>
                <div data-settings-desc class="text-body text-muted">Description</div>
             </div>
  <div data-settings-control class="flex shrink-0 items-center">control</div>
</div>
```

- **Row:** padding 12 top and bottom (`py-md`), 0 left/right. Gap 28 between the text column and the control. Items vertically centred. Height = 24 + text column height: a one-line label with no description is **44** (or 24 + control height when the control is taller; a 32 control gives **56**).
- **Label:** `text-body text-primary`, **14/20, wght 360, `#f0efec`**. Not bold.
  - `labelHidden` makes it `sr-only`.
  - A label adornment (§2.3) sits beside it in `inline-flex items-center gap-1.5` (gap 6).
- **Description:** `text-body text-muted`, **14/20, wght 360, `#898781`**. 4 below the label (`gap-1`). Wraps freely. Inline links inside are TextLink (§3.8).
  - With a hidden label plus an adornment, the description becomes `flex items-start gap-1.5` with the adornment in `flex h-lh shrink-0 items-center` (one line tall).
- **Leading** (optional): `flex min-w-0 flex-1 items-center gap-sm` → `shrink-0` leading (gap 12) then the text column.
- **Control:** `flex shrink-0 items-center`. With `controlWrapsBelow` it's `flex min-w-0 items-center` and the row is `flex flex-col gap-sm @[52rem]:flex-row @[52rem]:items-center @[52rem]:justify-between @[52rem]:gap-lg`: stacked (gap 12) until the container is ≥ 832 px. The `@container` ancestor wasn't traced: UNKNOWN which element it measures.
- **Indent:** `indent` → `ps-lg` (16). In `CODE` a dependent row instead uses `className:"ps-6"` (24), e.g. "Create as draft" under "Create pull requests automatically".
- **`below` content** (extra UI under a row): the row becomes `flex flex-col gap-sm py-md` (gap 12) wrapping `flex items-center justify-between gap-lg` (the main line), then the below content.
- **Row states:** no hover or pressed fill on rows; only their controls react.
- **Search-jump highlight** (`Hd` + `CSS`), when a search result opens a row:
  - The row title gets `.feature-anchor-highlight`: an `::after` wavy underline 5 px tall, 4 px below the text, colour `--cds-fill-warning` `#fab219`. It's drawn as an SVG mask of an 8 × 5 sine wave, stroke 1.3. It wipes in left to right, then fades; 1.95 s ease-out, keyframes 0% hidden → 17.9% fully drawn → 53.8% held → 100% opacity 0.
  - The row gets `.feature-anchor-row-fill`: `::before` inset 4 px top/bottom and −4 px left/right, radius 6, `color-mix(#fab219 22%, transparent)`. Opacity 0 → 1 → 1 → 0 on the same 1.95 s timeline.
  - Reduced motion: both shown statically.

### 2.3 Declarative row extras (`DECL`)

Rows built from a setting definition get `className:"group/setting"` and a label adornment `inline-flex h-5 items-center gap-1.5` (20 tall, gap 6), holding in order:

1. **Modified dot** (value ≠ default, not managed): `inline-block size-1.5 shrink-0 rounded-full bg-fill-accent`, a **6 px `#2a78d6` circle**.
2. **Scope badge** (only when the scope differs from the page's own): Badge `variant:"neutral" size:"xs"` reading "This computer" or "All devices" (or "Managed" when org-managed), followed by an InfoTip `size:"xs"` (`Info` icon 12 px, `rounded p-1 -m-1 text-muted hover:text-secondary`, popup side top, offset 6, delay 300 ms).
   - Neutral xs badge: height 18, padding 6 left/right (`px-sm` at xs), radius 18/4 = 4.5, `font-sans text-caption font-medium` (xs caption 11, line `round(1.25em)` = 14, wght 460), fill white 5%, text `#c3c2b7`.
3. **Reset** (modified only): ghost Button size xxs "Reset" (20 tall, padding 6, radius 5, 12/17 text, wght 360), in `inline-flex opacity-0 transition-opacity group-hover/setting:opacity-100 has-[:focus-visible]:opacity-100`. It appears only while the row is hovered or the button is focused, with a tooltip "Changed from the default (value).".

**Write failure** (shown below the row): `<p class="text-footnote text-danger">` (13/17, `#ec7e7e`), optionally followed by a ghost xxs "Check for updates".

**Control by kind** (`DECL` `De`):

| kind | control | width |
|---|---|---|
| `switch` | Switch, base (§3.3) | 36 |
| `segmented` | SegmentedControl, base, contained (§3.4) | intrinsic |
| `select` | Select `mode:"select" align:"end" searchable:false` (§3.2) in a div `w-[160px]` (or `w-[220px]` when `width:220`) | 160 or 220 |
| `text` | TextInput `fullWidth:false className:"w-56"`, commits on blur or Enter (§3.1) | 224 |

When disabled the control is wrapped in a disabled-reason tooltip ("Managed by your organization" / "Loading…").

### 2.4 Nest card (`Wd`, export `vv`; `Ne` in `CODE`)

The only boxed container on settings pages: `<div data-settings-nest class="rounded-card ring-1 ring-inset ring-alpha-2 {padding}">`.

- **Radius 12. No fill** (transparent over `#1a1a19`). Ring: inset 1px white 10%.

| `padding` | classes | result |
|---|---|---|
| `md` (default) | `px-4 [&>:not([role=group])]:py-md` | 16 left/right; non-row children 12 top/bottom; rows keep their own `py-md` (12) |
| `sm` | `!px-md !py-2 [&>[role=group]]:!py-sm [&>[role=group]:first-child]:!pt-0 [&>[role=group]:last-child]:!pb-0` | 12 left/right, 8 top/bottom; direct-child rows 8 top/bottom, first row 0 top, last row 0 bottom |
| `lg` | `px-6 py-2` | 24 / 8 |
| `none` | `!p-0 flow-root` | 0 |

- Children inside a nest get **no divider lines**. `.settings-group-dividers` only targets direct children of a group body, and the nest is itself a child.
- In `CODE` the folder list wraps each row in an extra `<div>`, so the `sm` row overrides don't match and those rows keep `py-md` (12). The traced gaps are therefore 8 (card) + 12 (row) at the edges and 24 between rows.

### 2.5 Rail (`Gd`, export `xv`; `Pe` in `CODE`)

`<div data-settings-nest data-settings-rail class="mb-md flex flex-col gap-md border-s border-strong ps-xl last:mb-0 empty:hidden [&>[role=group]]:!py-0">`

- A vertical **1px line, white 20%**, on the leading edge, with 24 px padding after it. Children are 16 apart (`gap-md`), rows inside have 0 vertical padding, and the rail has 16 below. Used for options that depend on a parent toggle.

### 2.6 Save bar (`Xd`, export `Cv`)

- `data-size="sm"`.
- Classes: `flex min-h-control items-center gap-sm`, min height 28 (sm control), gap 12.
- Buttons: primary sm "Save changes" (busy-capable, optional shortcut), then ghost sm "Discard". With `align:"end"`: `justify-end` and Discard first.
- Leading note: `text-footnote text-muted` (`order-last ms-auto` at start alignment, `me-auto` at end).
- Sticky variant when dirty: `sticky bottom-0 z-[1] border-t bg-surface-1 py-md`. 1px white 10% top border, fill `#151515`, padding 12 top/bottom.
- Not dirty: `!border-t-0`. Hidden entirely when nothing to show.

### 2.7 Page title and plain-rows panel (defined, unused by cached pages)

- **`tf` (export `yv`):** `<h2 class="mb-8 text-title-semibold text-primary">` → **22/28, wght 540, `#f0efec`, 32 below**.
  - With an intro: no `mb-8` on the title; then `<p class="mb-8 mt-1 text-footnote text-secondary">` (4 above, 32 below, 13/17, `#c3c2b7`).
  - With an action: `flex items-start justify-between gap-lg`.
- **`Zd` (export `mv`) "plain rows" panel:**
  - Consecutive titled sections are separated by a 1px top border (`border-t`, white 10%) with 32 above it (`!mb-8`) and 32 below it (`pt-8`), instead of 40 margin.
  - The last row before each boundary loses its bottom padding.
  - Adds `.settings-panel-plain-rows`, which turns off the in-group row dividers.
- **DataTable in settings (`Qd`):** `rounded-card border border-alpha-2 overflow-clip`, radius 12, 1px white 10%.

## 3. Controls on setting rows (dark, comfortable)

### 3.1 TextInput (`CDS` `Nb`, `data-cds="TextInput"`)

Plain (no slots):

```
cds-input cds-reset h-control pl-md rounded bg-fill-field shadow-field-ring data-[invalid]:shadow-field-invalid
font-sans text-body font-normal text-primary transition duration-fast pr-md w-full
placeholder:text-muted outline-none focus-visible:outline-hidden
enabled:[&:hover:not(:focus):not([data-invalid])]:shadow-field-hover disabled:opacity-disabled
focus-visible:shadow-focus data-[invalid]:focus-visible:shadow-focus-danger
```

- **Box:** height **32**, padding **12** left/right, radius **8**, fill white 5% (over `#1a1a19` ≈ `#252524`).
- **Text:** 14/20, wght 360, `#f0efec`. Placeholder `#898781`.

| State | Box shadow |
|---|---|
| rest | `inset 0 0 0 1px rgba(255,255,255,.10)` |
| hover (not focused) | `inset 0 0 0 1px rgba(255,255,255,.20)` |
| focus (text inputs match `:focus-visible` on click too) | `inset 0 0 0 1px #0b0b0b, 0 0 0 1px #2a78d6, 0 0 6px 1px rgba(24,79,149,.60)`: a 1px dark inner gap, a 1px blue ring outside the box, and a 6px blue glow |
| invalid | `inset 0 0 0 1px #d03b3b` |
| invalid + focus | danger focus: `inset 0 0 0 1px #0b0b0b, 0 0 0 1px #d03b3b, 0 0 6px 1px rgba(142,38,38,.60)` |
| disabled | opacity 0.4 |

- **With slots** (`slotStart` / `slotEnd` / clearable): outer `div` `h-control pl-md rounded bg-fill-field shadow-field-ring … inline-flex items-center gap-[var(--cds-pad-sm,6px)]` (gap 8) with focus on `has-[:focus-visible]`.
  - Leading slot `flex shrink-0 items-center text-muted`.
  - End slot `flex shrink-0 items-center gap-[pad-sm] text-muted`, padding right `pr-md` (12), or `(32 − 22)/2 = 5` when it holds a button.
  - Clear button: ghost icon-only size sm, `X`, forced to 22 × 22 with radius 8 − (32 − 22)/2 = 3.
- **Sizes:** `size` sets `data-size`: sm 28 h / 10 pad / radius 7; xs 24 / 8 / 6; lg 40 / 16 / 10.
- **Widths in settings:** full width by default. `CODE` uses `w-[220px]` (Branch prefix) and `w-56` (224, code font family, `fullWidth:false`).
- **Inline error under a settings input** (`CODE`): `text-danger text-body mt-1` (14/20, `#ec7e7e`, 4 above).
- **Field wrapper** (`HD` with `label`/`hint`/`error`; `BD` → `ID`):
  - `data-cds="Field"`, `flex flex-col gap-xs font-sans` (gap 8).
  - Label `LD`: `text-body font-medium leading-none text-primary` (14, line height 14, wght 460).
  - Hint `RD`: `text-footnote font-normal leading-snug text-muted` (13, line height 1.375 = 17.875, `#898781`).
  - Error `zD`: `flex items-start gap-1 text-footnote font-normal leading-snug text-danger` with a `WarningCircle` sm (16) icon `mt-px shrink-0`.
  - Order: label, input, hint, error.

### 3.2 Select / dropdown (`CDS` `Kk` convenience `WO`, `mode:"select"`, `data-cds="Combobox"`)

**Trigger** (outline variant, the default): a `div` with `iO aO.outline oO.select pr-sm w-full min-w-0`:

```
cds-reset group/cbx inline-flex items-center gap-1.5 h-control rounded font-sans text-body font-normal font-control text-primary
outline-none transition duration-fast data-[disabled]:opacity-disabled data-[disabled]:pointer-events-none
bg-fill-field shadow-field-ring data-[invalid]:shadow-field-invalid
[&:hover:not(:focus-visible):not(:has(:focus-visible)):not([data-invalid]):not([data-disabled])]:shadow-field-hover
pl-0 has-[:focus-visible]:shadow-focus data-[invalid]:has-[:focus-visible]:shadow-focus-danger data-[disabled]:cursor-default pr-sm
```

The inner button: `lO` = `cds-reset flex min-w-0 flex-1 items-center gap-1.5 self-stretch pl-sm text-left border-0 bg-transparent p-0 outline-none`. Its children:

- Value `<span class="min-w-0 flex-1 truncate">`. When empty, the placeholder is `font-normal font-control text-muted`.
- Caret `CaretDown` size sm (16 px, wght 533.3), `mr-0.5 shrink-0 text-muted transition-colors group-hover/cbx:text-secondary`.

| Part | Value |
|---|---|
| Height / radius | **32 / 8** |
| Padding | **8 left** (button `pl-sm`), **8 right** (`pr-sm`); caret has 2 extra right margin, so the caret glyph's right edge is 10 from the box edge |
| Gap value ↔ caret | 6 |
| Fill / ring | white 5% / inset 1px white 10%; hover inset 1px white 20% |
| Text | 14/20, wght 360, `#f0efec`; placeholder `#898781` |
| Caret | 16 px, `#898781`; `#c3c2b7` while the trigger is hovered |
| Focus | focus shadow (same as TextInput) |
| Open | no special trigger fill for outline (only the ghost variant fills when expanded) |
| Disabled | opacity 0.4, no pointer events |

- **Width:** fills its wrapper; settings use `w-[160px]` or `w-[220px]` wrappers.
- **Ghost variant:** `bg-transparent hover:bg-fill-ghost-hover aria-expanded:bg-fill-ghost-hover`.
- **Above-field label** (when `label` is passed): `text-body text-primary font-medium leading-none`, in `gap-xs flex-col` (gap 8).
- **Clear button** (when clearable): a 32 × 32 square slot holding a ghost xs icon-only `X` (forced to 22 × 22).

**Popup** (`Dk`/`kk`; class `mO` + `rx`):

```
draggable-none flex flex-col max-h-[min(var(--available-height,100dvh),var(--cds-popup-max-h,320px))]
rounded-card bg-surface-3 shadow-panel cds-reset text-body font-normal text-primary outline-none
rounded-[calc(var(--cds-radius)+var(--cds-menu-gutter,0.25rem))]
```

- **Placement:** side bottom, sideOffset **6**. Align start by default; settings rows pass `align:"end"`, so the popup's right edge lines up with the trigger's.
- **Width:** positioner `w-[var(--anchor-width)] min-w-[12rem]`: the trigger width, at least **192**. A 160 trigger therefore gets a 192 popup, end-aligned.
- **Surface:** radius **12** (8 + 4), fill `#20201f`. Shadow `inset 0 0 0 1px rgba(255,255,255,.10), 0 8px 24px rgba(0,0,0,.32), 0 2px 6px rgba(0,0,0,.20)`. Max height 320.
- **Inner:** `hO` = `flex min-h-0 flex-1 flex-col overflow-hidden rounded-[inherit] p-[var(--cds-menu-gutter,0.25rem)]` (padding 4; `--cds-menu-gutter` is `initial`, so the 4 fallback applies). The list `_O` is `overflow-y-auto scroll-fade-y`.
- **Search field** (only when `searchable`; settings pass `false`): `yO`, full-bleed, bottom border white 10%, padding `py-2` and 16 horizontal, 14/20.

**Item** (`bO`):

```
cds-reset group/cbx-item flex w-full items-center gap-2 min-h-control px-md py-1 rounded text-body font-normal font-control text-primary
select-none outline-none data-[highlighted]:bg-fill-ghost-hover data-[disabled]:opacity-disabled
```

- Min height **32**, padding **12** left/right and 4 top/bottom, gap **8**, radius **8**, 14/20, wght 360, `#f0efec`.
- **Highlighted** (hover or keyboard): white 7.5% (over `#20201f` ≈ `#2f2f2e`).
- **Content:** optional icon (`cs`, auto size 20), then `flex min-w-0 flex-1 flex-col gap-0.5` with the label `truncate` and an optional description (`whitespace-normal break-words text-footnote leading-snug text-muted`, 13 / 17.875).
- **Selected indicator** (`Pk`, end of row): `Check` size md (20), bold (glyph wght 566.7), `shrink-0 text-accent` `#6da7ec`. It's top-aligned (`flex h-[1lh] items-center self-start`) when a description is present.
- **Group label** (`TO`): `px-md pt-2 pb-1 text-footnote font-medium text-muted select-none` (12 horizontal, 8 top, 4 bottom, 13/17, wght 460, `#898781`).
- **Separator** (`CO`): `mx-pad-md my-1 h-px bg-border` (1px white 10%, inset 12, 4 above and below).
- **Footer** (`OO`/`kO`): a 1px white 10% line inset 12, then `shrink-0 pt-1`.
- **Empty:** "No results".

### 3.3 Switch (`CDS` `HE`)

Same as forms-buttons.md §5.3:

- **Base track:** 36 × 20, 2 px padding, fully round. Off white 10% (hover 20%); on `#2a78d6` (hover `#3987e5`).
- **Knob:** 16 px, `#ffffff`, `shadow-sm`. It moves 16 px over 120 ms `cubic-bezier(.34,1.3,.64,1)`.
- **States:** disabled opacity 0.4; focus = focus shadow.
- **Size sm** (folder rows in `CODE`): 32.4 × 18, knob 14, travel 14.4.
- **Labelling:** settings switches are labelled by the row (`aria-labelledby` = row label id). A `disabledReason` wraps the switch in a tooltip.

### 3.4 SegmentedControl (`CDS` `kD`)

Same as forms-buttons.md §5.4. Contained (default):

- **Track:** 32 high, radius 8, white 5% track, 1 px padding.
- **Thumb:** radius 7, white 10%, `inset 0 0 0 1px rgba(255,255,255,.10), 0 1px 2px rgba(0,0,0,.05)`.
- **Items:** 12 padding, radius 6, gap 6, 14/20, wght 360. Text `#898781`; checked or hovered `#f0efec`.

Used in `CODE` for the credential type (Bearer / Basic), with a field label above it: `text-body font-medium leading-none text-primary` in `flex flex-col gap-xs` (gap 8). Declarative `segmented` settings (§2.3) use it too, e.g. "Transcript text size" Small / Medium / Large.

### 3.5 Buttons on rows

| Use (traced in `CODE`) | Button |
|---|---|
| Row action ("Manage", "Delete…") | `secondary`, base: 32 high, 12 horizontal padding, radius 8, fill white 10% (hover 14%), text `#f0efec` 14/20 wght 360 |
| Row action in dense rows, list add ("Add folder"), "Remove" on list rows | `secondary`, size `sm`: 28 high, 10 horizontal padding, radius 7, 14/20 |
| Pin toggle on list rows | `ghost` sm icon-only (`Pin` / `PinFilled`, `pressed`): 28 × 28, icon 20; pressed: text `#6da7ec`, fill `#032042` |
| Form submit / cancel in a nest | `primary` sm (white fill `#ffffff`, text `#0b0b0b`, wght 460) and `secondary` sm, in `flex justify-end gap-sm` (gap 12) |

- **Destructive actions are not red on the row.** A destructive setting ("Delete sessions stored by Anthropic") uses a **secondary** "Delete…" button.
- That button opens a ConfirmationDialog (`CDS` `l_`, size `sm` = `max-w-[400px]`):
  - Title: `text-heading font-medium font-header` (15/20, wght 460).
  - Description: `mt-1 text-body font-normal text-secondary` (14/20, `#c3c2b7`).
  - Footer: `mt-pad-lg flex flex-col-reverse gap-2 sm:flex-row`, end-aligned, 16 above, gap 8. It holds a secondary "Cancel" and the confirm Button with `variant:"danger"`: fill `#d03b3b` (hover `#e34948`), white text, wght 460, red focus ring.
  - Dialog surface: see composer-overlays.md §12.
- Button anatomy, press "squish" and focus are in forms-buttons.md §4.

### 3.6 Badge (`CDS` `_s`, `data-cds="Badge"`)

- **Classes:** `inline-flex items-center gap-1 align-middle h-control-nested whitespace-nowrap rounded-chip px-sm font-sans text-caption font-medium leading-[round(1.25em,1px)]`.
- **Sizes:**

  | size | height | padding | radius | text |
  |---|---|---|---|---|
  | sm | 20 | 8 | 5 | 12 / 15, wght 460 |
  | xs | 18 | 6 | 4.5 | 11 / 14 |

- **Colours:**

  | Variant | Fill | Text |
  |---|---|---|
  | `neutral` | `bg-neutral` white 5% | `#c3c2b7` |
  | `accent` | `bg-tint-blue` ≈ rgba(0,36,81,.75), ≈ `#072143` over `#1a1a19` | `#6da7ec` |

- **Used in `CODE`:** accent sm next to a row label, and neutral sm `cursor-help font-mono` for tool names inside a Tooltip.

### 3.7 InfoTip (`CDS` `IT`, `data-cds="InfoTip"`)

- **Trigger:** `cds-reset inline-flex shrink-0 items-center justify-center rounded p-1 -m-1 text-muted outline-none transition-colors duration-fast hover:text-secondary focus-visible:text-secondary focus-visible:shadow-focus data-[popup-open]:text-secondary`.
- **Icon:** `Info`, default size sm (16); settings adornments use xs (12).
- **Popup:** side top, align centre, offset 6, delay 300 ms, opens on hover. Its surface classes (`PT`/`FT`) are template strings, not traced: UNKNOWN; tooltip-like (composer-overlays.md §9).

### 3.8 Inline help links (TextLink, `CDS` `xd`)

`cds-reset cds-text-link`, colour `#6da7ec`. Underline offset 3; its colour is the link colour at 40%, rising to 100% on hover or focus. Radius 2, 60 ms transitions (forms-buttons.md §5.8).

- **External links** ("Learn more" → docs): `external:!0` or `target:"_blank"` adds a hidden "(opens in new tab)" and an end icon (`iconPosition` default `"end"`). The icon glyph wasn't traced: UNKNOWN.
- **Placement:** links sit inside the row description (`text-body text-muted`), so they're 14/20.
- A TextLink with `onClick` and no `href` is used as an inline toggle ("Show all" / "Show fewer" in the folder list).

### 3.9 Keyboard shortcut chips / recorder

- **Display chips (keycaps):** CDS `Shortcut`/`kbd`, 18 high, radius 4, 1px border at 22% ink, ink `#a5a49a`, 12 px caption (forms-buttons.md §4.6). Inside menu items the ink is `--cds-text-muted`.
- **Keyboard shortcuts dialog:** `shared-19` `EM`, a modal wrapped in `density:"comfortable"`, height 760 (`h-[760px]`) except on Code routes (full height). Its body chunk `c518a31cc--t8velML.js` is **not in the cache**: layout UNKNOWN.
- **Shortcut recorder:** no settings shortcut recorder found in the cached build: UNKNOWN.

## 4. List-of-items management (traced: Claude Code page, folders list `CODE` `na` / `ta`)

Connectors and MCP server lists live in chunks that aren't cached (`c71860c77-BYwK66Jd.js` for Connectors, `c71860c77-q95IVlyQ.js` for Developer): UNKNOWN. The Claude Code page's folder list is the traced pattern:

```
Section (§2.1) title + footnote description
├─ Row (§2.2) label "N folders", description (counts, "Show all" TextLink), control = secondary sm "Add folder"
│   below:
│   └─ Nest card padding "sm" (§2.4)
│       └─ per item: <div> Row
│             label: <span class="block truncate">Folder name</span>      14/20 #f0efec
│             description (text-body text-muted, 14/20 #898781):
│               <span class="block break-all">~/path/to/folder</span>
│               <span class="block break-all ps-md">…folded paths (indent 12)</span>
│               <span class="block">status line</span>
│             control: <div class="flex items-center gap-lg">                 gap 28
│               <span class="text-footnote text-secondary">used 3 days ago</span>   13/17 #c3c2b7
│               <span class="flex items-center gap-xs">                         gap 8
│                  <span class="text-footnote text-secondary">Worktree</span> + Switch size sm
│               ghost sm icon-only Pin/PinFilled (pressed state)
│               secondary sm "Remove"
└─ empty: <span class="text-footnote text-secondary">No folders yet…</span>
   at limit: <span class="text-footnote text-secondary">…limit…</span>
```

- **Row geometry inside the card:** card padding 12 left/right, 8 top/bottom, radius 12, 1px white 10% inset ring. Rows have 12 top and bottom padding (see §2.4 on why the `sm` overrides don't apply) and **no divider lines** between them.
- **Add button:** the list header row's trailing control, secondary sm. It's disabled with a reason tooltip when not permitted. At the limit it opens a small Dialog (header + description + primary "OK").
- **Items with an icon** use the row's `leading` slot: `flex min-w-0 flex-1 items-center gap-sm`, gap 12. The search results show connector icons at 20 px box / 14 px image.
- **Credential list** (`CODE` "copper-lantern", Authorization tokens):
  - Row with `below` = `flex flex-col gap-md pt-sm`: gap 16, 8 above.
  - Below it: a Nest `padding:"sm"` with the saved items, and a Nest (default `md` padding) holding the add/edit form.
  - Form: heading `<h4 class="text-body font-medium text-primary">` (14/20, wght 460), then Fields with labels (§3.1), a SegmentedControl (§3.4), a two-column `grid grid-cols-2 gap-sm` (gap 12) for username/password, a footnote `text-footnote text-muted`, an optional Banner (danger or neutral), and buttons `flex justify-end gap-sm`: secondary sm "Cancel" + primary sm submit.
- **Toggle list rows** (`CODE` `la`): row with Switch, and `below` status text in `text-body text-muted` or `text-body text-danger`.

## 5. Other traced page patterns (Claude Code page)

- **Code appearance preview:**
  - Grid `grid grid-cols-2 gap-md py-md` (2 columns, gap 16, 12 top and bottom).
  - Each column `flex min-w-0 flex-col gap-sm` (gap 12): a full-width Select (theme), then a preview box `min-h-[94px] overflow-clip rounded-lg border` (radius 8, 1px white 10%, min height 94) holding a diff render.
- **Status / help lines:** `text-footnote text-secondary` (13/17, `#c3c2b7`) and `text-footnote text-muted` (13/17, `#898781`).
- **Monospace values:** `min-w-0 flex-1 truncate rounded bg-surface-2 px-2 py-1 font-mono text-caption text-secondary` (radius 8, `#1a1a19`, padding 8 × 4, 12/17 mono, `#c3c2b7`).
- **Two-column descriptive block:** `flex items-start justify-between gap-md py-sm` (gap 16, 8 top and bottom).

## 6. UNKNOWN / not traced

- Page bodies of General (Appearance: theme, chat font, interface font, transcript size and width, motion; Notifications), Account, Privacy, Capabilities, Connectors, System, Extensions, Developer: their chunks aren't cached. Only their search labels are known (§0).
- Keyboard shortcuts dialog body and any shortcut recorder.
- Connectors / MCP server list rows (icon size, subtitle, trailing menu).
- The `@container` that the `@[52rem]` row breakpoint measures.
- InfoTip popup classes (`PT`, `FT`), the TextLink external-link icon, and the Tabs visuals in the stacked header.
- The Usage section's nav icon.
- Light mode (out of scope).
