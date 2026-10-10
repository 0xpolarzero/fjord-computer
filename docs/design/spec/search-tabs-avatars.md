# Claude desktop: search palette, Tabs, Badge, Avatar, list rows, empty states, scroll fades (dark mode)

Read from Claude's own shipped web code, current build only (the files listed in `/tmp/specwork/current.txt`, cached 2026-10-09 21:25). Every value is traced to a class string or CSS rule. UNKNOWN marks anything that could not be traced. All sizes are CSS px (1 CSS px = 1 pt in a native app at 100% zoom; the user's claude.ai zoom adds ×1.0954, see global §0).

Read `global-sidebar-titlebar.md` §1 first. It defines the tokens, the densities, the text roles and the dark variable weights used here:

| CDS weight | `wght` |
|---|---|
| regular | 360 |
| medium | 460 |
| semibold | 540 |
| bold | 560 |

Colours used throughout (dark):

| role | value |
|---|---|
| `text-primary` | `#f0efec` |
| `text-secondary` | `#c3c2b7` |
| `text-muted` | `#898781` |
| `surface-3` | `#20201f` |
| `border` | white 10% |
| `border-strong` | white 20% |
| `fill-ghost-hover` | white 7.5% |
| `fill-ghost-selected` | white 15% |
| `fill-control` | white 10% |
| `fill-accent` | `#2a78d6` |
| `fill-brand` | `#c6613f` |

Size-step tokens for both densities (from `c6a992d55-Drv_MyUK.css`, `.cds-root` vs `.cds-root[data-density=comfortable]`). These drive Tabs and Badge.

| token | compact base / xs / sm / lg | comfortable base / xs / sm / lg |
|---|---|---|
| `--cds-h-control` | 24 / 20 / 20 / 28 | 32 / 24 / 28 / 40 |
| `--cds-h-control-nested` | 18 / 16 / 16 / 20 | 22 / 18 / 20 / 28 |
| `--cds-pad-md` | 8 / 6 / 6 / 10 | 12 / 8 / 10 / 16 |
| `--cds-pad-sm` | 6 / 4 / 4 / 8 | 8 / 6 / 8 / 12 |
| `--cds-radius` | 6 / 5 / 5 / 7 | 8 / 6 / 7 / 10 |
| body size / leading | 13/19, 12/17, 12/17, 14/20 | 14/20, 13/19, 14/20, 15/22 |
| caption size (leading always 17) | 11 / 10 / 10 / 12 | 12 / 11 / 12 / 13 |

`[data-step="1"]` (used by Badge `xxs`) sets: h-control 20, h-control-nested 16, radius 5, icon 12, pad-sm 4, pad-md 6, caption 10, body 12/17.

---

## 1. Search dialog / command palette (sidebar "Search", ⌘K)

### 1.0 Sources

| part | file | symbol |
|---|---|---|
| Mount, open/close, shortcuts | `shared-20-BUWXZWmU.js` | `eI`, `oI`, `aI`; lazy entry `command_palette` → `CommandPaletteBody` |
| Dialog shell | `shared-19-BebVWfVJ.js` | `ST` (export `eo`); constants `sT…fT`, `pT`, `mT`, `Zw` |
| CDS Dialog popup | `shared-frame-BAME2HDg.js` | `o_.Popup` = `Zg`, backdrop `wg`, surface root `gf` |
| Palette body | `c2771e1f6-BijuVm54.js` | `Sg` → `Ng` (input row, list, footer); entry chip `Sp`; close `Jh`; skeletons `$h`/`sg` |
| Rows, footer, empty, filter tabs | `ce8be540f-DNXDbtXp.js` | row `Vn`, icon+dot `Bn`, snippet `Dn`, title `Q`/`On`, footer `ln`, empty `Un`, type tabs `Xt`, keycap `an`/`on`, time `Sn` |
| Row primitive | `c01b6d4ec-CPF9M9MR.js` | `c` (button), `o` (class), `s` (trailing) |
| Keycap (CDS Shortcut) | `shared-frame-BAME2HDg.js` | `Rs`, `Ns`, `Ps`, `Fs` |

### 1.1 Density and feature gate

- **Density: comfortable.** The palette is mounted in the app shell (`Xq` in `shared-23`, through `gs`→`sI`), above the frame. No density provider sits above it, so it inherits the CDS context default `ba=q("comfortable")`. The popup's surface root `gf` takes `density:a??Ha()`.
  - Cross-check: the body's own height model `Ep={paddingY:20,groupTitle:37,row:36,groupGap:4}` only adds up with comfortable text. A row is 8 + 20 (body leading 20) + 8 = 36; a group title is 12 + 17 + 8 = 37.
- **Restyle gate.** Several details depend on GrowthBook gate `"__gb__1669033294"` (`bR` in `shared-18`). It reaches the body as `U=tr()` and as context `Ua`/`ye` (=`Ao()`). Its value for this user is **UNKNOWN**: it isn't in Local Storage, IndexedDB or the HTTP cache. Both branches are given below, marked **gate on** and **gate off**.

### 1.2 Dialog surface

| property | value | source |
|---|---|---|
| position | `fixed left-1/2 -translate-x-1/2 top-[var(--cp-top)]` | `ST` |
| width | `w-[calc(100vw-2rem)] md:w-[calc(100vw-5rem)] max-w-2xl`, so **min(viewport − 80, 672)** at ≥768 wide | `ST`; `--container-2xl:42rem` |
| background | `bg-surface-3` **`#20201f`** | inner div in `ST` |
| radius | `rounded-[calc(var(--cds-radius-composer)+0.375rem)]` = 14 + 6 = **20** (outer popup and inner panel) | `ST` |
| border | `border-0.5 border-strong`: **0.5 px, white 20%** | `ST` |
| shadow | `shadow-2xl`: **`0 25px 50px -12px rgba(0,0,0,.25)`** | CSS |
| clip | `overflow-hidden` | |
| backdrop | `fixed inset-0 bg-backdrop`: **black 50%**, fades over `duration-base` (200 ms) ease-out | `wg` |
| inner column | `flex flex-col max-h-[calc(min(100vh,var(--cp-visible-h,100vh))-var(--cp-top)-2rem)]` | `mT` |

- **Desktop app = "slotted / balanced top".** `d=Ls(t)` is `ZM()`, which returns `isClaudeApp() || gate dramatic_shrimp`, so it is true. The classes `fT` and style `pT` apply:
  - `--cp-inset: var(--desktop-titlebar-inset, 45px)`
  - `--cp-clearance: inset + 16`
  - `--cp-top: clearance` below 640 px wide
  - At ≥640 px: `--cp-cap: 15vh` (25vh at ≥1024 px) and `--cp-top: max(clearance, min(cap, max(inset + 32, (100vh − 583.9 + inset) / 2)))`, with `--cp-settled-h: 583.9px`.
  - Example: a 900-tall, ≥1024-wide window gives top = min(225, 180.6) = **180.6**.
- **Enter animation** (`x==="dialog"`): from `opacity-0 scale-[0.98]` to 1, `origin-top transition-[opacity,scale] ease-out`, over `duration-base` (200 ms) on enter and `duration-snap` (120 ms) on exit. Opened from the keyboard (`openedBy==="keyboard"`): `transition-none`, so it is instant.
- **Recede** (a nested card is open, `Zw`): the panel scales to 0.97. A veil `absolute inset-0 bg-surface-0` (`#0b0b0b`) plus `after:bg-backdrop` is shown at opacity 0.2.

### 1.3 Input row

Container `Us` = `flex items-center gap-2 pl-[1.5rem] pt-[1.1rem] pr-2.5 pb-[0.9rem]` (with gate on, also `relative`):

| side | padding |
|---|---|
| left | 24 |
| top | 17.6 |
| right | 10 |
| bottom | 14.4 |

The gap between children is 8. Children, in order:

1. **Search-mode marker** (only when the entrypoint is `"search"` and the gate didn't fold it into default, `Sp`): `flex items-center flex-shrink-0 -ml-1 mr-1` holding Icon `Search`, size md (20 px, wght 433.3), `text-muted`.
   - The "actions" entrypoint instead shows a chip: `flex items-center gap-1 flex-shrink-0 border-0.5 rounded-lg p-0.5 pl-2 -my-1.5 -ml-2`, with a `Keyboard` icon (md, muted) and a ghost xs X button.
2. **Filter chips** (`Do`, gate on, search-type filters only): not traced in detail.
3. **Textarea** `#command-palette-input`. Classes `rc`:

   ```
   flex-1 bg-transparent border-none font-base text-primary !outline-none !ring-0 !shadow-none resize-none
   ```

   - Text: `font-base` = body comfortable **14/20, wght 360, `#f0efec`**.
   - **Gate on:** adds `min-w-[5rem] py-1.5` (6 px top and bottom, so the box is 32 tall) and `placeholder:text-muted` (`#898781`). Single-line mode adds `overflow-x-auto overflow-y-hidden u-hidden-scrollbar`.
   - **Gate off:** adds `placeholder-text-500/80`, i.e. `color-mix(in oklab, #898781 80%, transparent)`, and `overflow-y-auto`.
   - Inline style: `maxHeight: 6rem` (96). `rows=1` (compose: 2–3). It auto-grows past 50 characters or on a newline.
   - Placeholder: "Search sessions and projects" (Code route) or "Search chats and projects". Default entry: "Search or start a session" or "Search or start a chat". Actions entry: "Search actions".
4. **Spinner slot:** `flex size-4 shrink-0 items-center justify-center` (16×16). It holds a CDS Spinner, size md, delay 150 ms, label "Searching deeper..." while a deeper search runs.
5. **Close:** CDS Button `variant:"ghost" iconOnly icon:"X"`. In comfortable that is **32×32**, radius 8, a 20 px glyph, hover background white 7.5% (see forms-buttons.md for ghost button states).

Row height: max(textarea, 32) + 32 = **64**.

**Divider** under the row (not in compose mode): `h-[0.5px] bg-border w-full`, a **0.5 px line, white 10%**.

**Type filter tabs** (gate on, `Xt`), when shown:
- Wrapper `flow-root pb-[0.9rem]`.
- Scroller `-mx-[1.5rem] -my-2 min-w-0 scroll-px-[1.5rem] overflow-x-auto overscroll-x-contain px-[1.5rem] py-2 u-hidden-scrollbar`.
- Inside, a CDS `Tabs.List size:"sm"` ("All", then one tab per type). See §2 for the sm comfortable tab: 28 tall, 10 px padding, 14/20.

### 1.4 Results list

**Scroller** (`mc`): `p-2.5 min-h-0 overflow-y-auto`, plus `transition-[height,max-height] duration-150 ease-out` (`Jn`).
- Padding 10 on all sides.
- `max-height: calc(440px + var(--cp-footer-collapsed,0) * 41px)` (`Kn`), so 440, or 481 when the footer is collapsed.

**Top scroll shadow** (sticky, appears once content scrolls under it):
- `pointer-events-none sticky -top-2.5 z-1 -mx-2.5 -mt-2.5 -mb-2.5 h-2.5 shrink-0 overflow-hidden`.
- It contains `absolute inset-x-0 bottom-full h-2.5 shadow-[0_2px_8px_color-mix(in_srgb,var(--cds-black)_6%,transparent)]`. The visible effect is a **0 2px 8px rgba(0,0,0,.06)** shadow along the top edge.
- Followed by a cover strip `pointer-events-none relative z-2 -mx-2.5 h-2.5 shrink-0 bg-surface-3` (10 px of `#20201f`) that hides the shadow until the list scrolls.

**Listbox** `#command-palette-results`: `flex shrink-0 flex-col gap-1`, so **4** between groups.

**Group:** `role=group`. An untitled results group directly after another untitled group gets `[&:not(:first-child)]:mt-2` (8).

**Section header:** `px-3.5 pt-3 pb-2 font-small text-muted flex gap-2 items-center`.
- Padding: left/right 14, top 12, bottom 8. Height **37**.
- Text: caption comfortable **12/17, wght 360, `#898781`**. No letter-spacing, sentence case (e.g. "Recents", "Actions", "Quick actions").
- Clickable variant ("Actions" → actions mode, "Recents" → search): `button.flex items-center gap-1 hover:text-secondary transition-colors`. Hover text `#c3c2b7`. Trailing Icon `CaretRight` xs (12, wght 577.8) with `opacity-75 translate-y-[0.5px]`.
- Notice line under a header: `px-3.5 pb-2 font-small text-muted` ("Search covers the titles shown.").

### 1.5 Result row

**Button** (`o()` in `c01b6d4ec`), `role=option`:

```
w-full text-left px-3 py-2 rounded-lg flex items-center justify-between gap-3 truncate font-base
```

| property | value |
|---|---|
| padding | 12 horizontal, 8 vertical |
| radius | 8 |
| gap (content to trailing) | 12 |
| text | 14/20, wght 360 |
| one-line height | **36** |

**States:**

| state | classes | rendering |
|---|---|---|
| unselected | `text-secondary` | `#c3c2b7`, no background |
| selected / highlighted | `bg-fill-ghost-hover text-primary` | **white 7.5%** fill, `#f0efec` |
| hover | moves the selection (`onMouseMove`→`onHoverIndex`); `hoverTint` is not passed | no separate hover fill |
| archived | unselected `text-muted`; selected `text-secondary` | |
| disabled, not shimmering | `opacity-60 cursor-wait` | |
| loading | title in a CDS ShimmerText `variant:"secondary"` | |

**Content box:** `flex items-center gap-2 flex-1 min-w-0` (gap 8). When there's a row-actions slot it adds `me-7` (28 right margin).

**Leading icon:** CDS Icon size md = **20 px, wght 433.3**, colour inherited from the row.

| row type | icon |
|---|---|
| chat | a chat icon (`he.thread`/`me(P)`) |
| project | `he.project`, or a project icon at `customSize:20` in the project's colour |
| code / desktop session | `he.codeSession` |
| action | its own icon with `shrink-0` |

**Status dot on the icon** (`Bn`):
- **Gate on:** CDS Pulse, `block size-[0.375rem] rounded-full` (6×6), not animated, at `absolute -top-px -right-px`, with `box-shadow: 0 0 0 0.5px var(--cds-page-bg)` (page-bg inside the palette = surface-3 `#20201f`). The icon gets a cut-out mask: `--dot-r: 3px; mask-image: radial-gradient(circle at calc(100% - r + 1px) calc(r - 1px), transparent calc(r + 2px), black calc(r + 2.5px))`.

  | state | dot colour |
  |---|---|
  | awaiting / error / unread | `#2a78d6` |
  | running | `#c6613f` |

- **Gate off:** only `running` shows a dot: `absolute -bottom-0.5 -right-0.5 size-2.5 rounded-full bg-brand-100 border-2 border-bg-000`. That is a 10×10 `#d97757` circle with a 2 px ring in the page background.

**Title** (`Q`): `span.truncate`. Matched characters: `span.font-semibold.text-primary` (wght **540**, `#f0efec`).

**Two-line rows** (chat with a matched message snippet, gate off): a `div.flex flex-col min-w-0 flex-1` (`Tn`) with:
- Line 1: the title, 14/20.
- Line 2: the snippet `span.text-xs text-muted truncate`: **12/16** (`--text-xs:.75rem`, leading `1/.75`), `#898781`. Matched characters in the snippet are 540 primary.
- Row height 8 + 20 + 16 + 8 = **52**.

**Gate on:** the snippet sits on the same line instead. Wrapper `En` = `flex items-baseline gap-2 min-w-0 flex-1`; snippet `text-xs text-muted max-w-[60%] shrink-0 overflow-hidden whitespace-nowrap`, wrapped in “ ”.

**Thread rows** add a project suffix `span.min-w-0 max-w-[160px] shrink truncate text-muted` with "· Project" (`kn`: `flex min-w-0 items-baseline gap-1`).

**Trailing meta** (`s`, the `secondary` slot): `span.text-xs text-muted shrink-0`, **12/16, `#898781`**.
- Content is a relative time bucket (`Sn`): "Just now" (<5 min), "Past hour", "Today", "Yesterday", "Past week", "Past month", "Past year", otherwise nothing.
- Code sessions: "PR #n · time". Projects: "By {name} · time" (`inline-block max-w-[150px] truncate align-bottom`).
- Archived: a neutral Badge `xxs` with icon `Archive` (§3).
- **When the row is selected** (fine pointer), the meta is replaced by Icon `ArrowReturn` size sm (**16 px**, wght 533.3) in the same muted colour.
- Accent-badge variant: `bg-brand-100 text-oncolor-100 -me-1.5 size-6 -my-1 rounded-md` (24×24, `#d97757`, white glyph).

**Action rows:**
- Trailing shortcut (see keycaps below), or `span.block truncate max-w-[15rem]` secondary text.
- Optional Badge `variant:"accent" size:"xxs"`.
- When selected with an external link: Icon `ArrowOutSquare` sm.

**Row actions** (gate on): `span.pointer-events-none absolute inset-y-0 end-9 flex items-center` (36 from the right) holding a ghost Button size xs, icon-only `DotsHorizontal`, shown on the selected row.

### 1.6 Footer hints

The footer is hidden on touch. Container (`ln`):

```
group/footer pointer-coarse:hidden flex-shrink-0 border-t-0.5 pr-4 pl-5 py-2.5 bg-surface-3
```

| property | value |
|---|---|
| top border | 0.5 px, white 10% (base `border-color: var(--cds-border)`) |
| padding | left 20, right 16, top and bottom 10 |
| background | `#20201f` |
| height | about **40.5** (matches the 41 in `Kn`) |

- Inner: `flex min-h-5 items-center justify-between text-caption text-muted`: min height 20, caption **12/17, wght 360, `#898781`**.
- Left group: `flex items-center gap-5` (20 between hints). Each hint is `flex items-center gap-2` (8): label, then keycaps.
- Hints in order:
  - "Select" ↑↓, or "Close" esc when `escHint`
  - type tabs ←→ (`hidden sm:flex`)
  - filters `/` (`hidden md:flex`)
  - "Actions" Tab
  - "Actions" alt+enter (row actions)
  - "Open menu" + the palette shortcut
- Right group (optional): `flex items-center gap-3` with a ghost `xxs` view-switch button (`text-muted`) plus a `kbd` Tab.
- Compose mode: no top border, `pr-4 pl-5 pb-2.5`; hints "Send" enter and attach.
- Footer collapse: with gate on and a non-empty query (`footerCollapsed`), the footer collapses: `grid-rows-[0fr] opacity-0` over 150 ms.

**Keycaps, gate on** (CDS Shortcut, `Rs.keycap` + `Ns`):

```
group:  inline-flex shrink-0 items-center gap-[2px] text-caption
cap:    inline-flex shrink-0 items-center justify-center h-[calc(1em+6px)] rounded-[var(--cds-keycap-radius,4px)]
        [color:var(--cds-shortcut-cap-ink)] bg-[color:var(--cds-shortcut-cap-fill)] border border-[color:var(--cds-shortcut-cap-line)]
        font-inherit [line-height:1]
```

| property | value |
|---|---|
| cap height (12 px caption) | **18** |
| one-glyph cap width | 18 (`w-[calc(1em+6px)] px-0`) |
| multi-glyph cap | `min-w-[calc(1em+6px)] px-[3px]` |
| radius | 4 |
| ink | `#a5a49a` |
| fill | transparent |
| border | 1 px, `color-mix(currentColor 22%, transparent)` |
| gap between caps | 2 |
| icon caps (⌘, ⏎, arrows) | xs Icon (12) |

**Keycaps, gate off** (`an`, `small`): a wrapper `flex items-center gap-1`, then per key:

```
kbd.font-base select-none inline-flex items-center justify-center rounded-[4px] min-w-5 h-5 px-1 bg-bg-300
```

The footer and rows override it with `*:!bg-transparent *:border-0.5 *:border-border-300 *:font-small`:

| property | value |
|---|---|
| size | **20×20** min, 4 px horizontal padding |
| radius | 4 |
| fill | transparent |
| border | 0.5 px, white 10% |
| text | caption 12/17 |

### 1.7 Empty, loading, error

**No results** (`Un`):
- Container `flex min-h-fit flex-1 flex-col items-center justify-center gap-3 px-6 text-center` (gap 12, side padding 24).
- Words: `p.max-w-full break-words text-secondary` (`#c3c2b7`). Text: "No results found", or a scoped message with the query. Its font size isn't set; it inherits (`.cds-root` sets no font-size), so it is UNKNOWN.
- Under it, either a CDS Button `variant:"secondary" size:"sm"` ("Clear filters"), or a hint `p.flex items-center gap-1.5 text-muted`.
- "Something went wrong" uses the same layout.

**Loading skeletons** (`$h`, `sg`): `flex min-h-0 grow basis-0 flex-col flex-wrap content-start overflow-hidden`, made of title bars (width 88 or 56) and 1 to 13 row placeholders. The skeleton rows' own geometry (`zr`, `Vr`) was not traced (UNKNOWN).

**Screen-reader live region:** "{n} results available".

---

## 2. CDS Tabs (`data-cds="Tabs"`)

Source: `shared-10-p2sUQDxj.js`, `bl={Root, List:hl, Tab:vl, Panel:yl}`, built on Base UI Tabs.

### 2.1 Structure

- **Root:** `data-cds="Tabs"`. When collapsed it also gets `min-w-0 max-w-full`.
- **List** (`hl`): `flex items-center font-sans` (`ol`). There is **no gap**: tabs abut.
  - `size` prop → `data-size` (xs/sm/lg; base has no attribute).
  - `flush` → `-ml-pad-md`, so the first label aligns with the content edge.
  - When the tabs overflow, the list hides (`invisible absolute size-0 …`) and a collapsed menu trigger (`al`) replaces it. That trigger's look is UNKNOWN.
- **Tab** (`vl`), class `gl`:

  ```
  relative isolate inline-flex shrink-0 items-center justify-center gap-1.5 rounded-none h-control px-md cds-reset whitespace-nowrap
  select-none outline-none bg-transparent text-body font-medium font-control text-muted
  before:absolute before:inset-y-0 before:inset-x-px before:rounded before:-z-[1] before:transition-shadow before:duration-fast
  [&:not([data-active]):not([data-disabled])]:hover:text-secondary [&:not([data-active]):not([data-disabled])]:hover:before:bg-fill-ghost-hover
  data-[active]:text-primary data-[active]:before:bg-fill-ghost-hover
  focus-visible:before:shadow-focus data-[disabled]:opacity-disabled data-[disabled]:pointer-events-none
  ```

- **Panel:** `cds-reset outline-none`.

### 2.2 Geometry by size

| size | compact h / px / text / radius | comfortable h / px / text / radius |
|---|---|---|
| base | 24 / 8 / 13/19 / 6 | 32 / 12 / 14/20 / 8 |
| xs | 20 / 6 / 12/17 / 5 | 24 / 8 / 13/19 / 6 |
| sm | 20 / 6 / 12/17 / 5 | 28 / 10 / 14/20 / 7 |
| lg | 28 / 10 / 14/20 / 7 | 40 / 16 / 15/22 / 10 |

- Icon-to-label gap: 6.
- Text weight: `font-medium` (**wght 460**). It beats `font-control`, as on the title bar (global §3).

### 2.3 Indicator and states

The indicator is a **pill**, not an underline. Each tab paints its own background on `::before`, so the indicator doesn't animate between tabs.

- The `::before` spans the full tab height, inset 1 px left and right. The first tab's pill starts at 0 and the last tab's pill ends at 0 (`sl`, `cl`). Two adjacent pills therefore have a **2 px gap**.
- Pill radius = `--cds-radius` of the size.

| state | text | pill |
|---|---|---|
| unselected | `#898781` (muted) | none |
| hover (unselected, enabled) | `#c3c2b7` (secondary) | white 7.5% |
| selected (`data-active`) | `#f0efec` (primary) | **white 7.5%** |
| disabled | opacity 0.4, no pointer events | |
| focus-visible | | pill gets `--cds-focus-shadow`: inset 1 px `#0b0b0b` + 1 px `#2a78d6` + `0 0 6px 1px rgba(24,79,149,.6)` |

Transition: `box-shadow` over 60 ms.

### 2.4 Count badge

- Tabs have **no built-in count**; tab children are free content.
- In the current build, the Settings tabs append an unseen marker (`Lw`→`Pw`→`jw`): `span.inline-flex shrink-0 ms-1.5 align-middle` holding the status dot `kind:"ready"`, a **6×6 `#2a78d6`** circle (global §1.7), placed 6 after the label.
- If a numeric count is wanted, the CDS pattern is a Badge (§3) inside the tab, after the 6 px gap. That use is not observed in the current build (UNKNOWN).
- Tabs are used in:
  - the palette type filter (`size:"sm"`)
  - Settings (`shared-20` `Dy.Tab`)
  - analytics (`size:"sm"`, `cf6ae6197`)
  - org skills (`size:"sm"`, `ca44b2238`)
  - option tabs (`shared-10` `Ig`, with a `mr-0.5 text-disabled` letter prefix)

---

## 3. CDS Badge (`data-cds="Badge"`) and count pills

Source: `shared-frame-BAME2HDg.js`, `_s` (export `xl`).

### 3.1 Structure

```
span[data-cds=Badge]: inline-flex items-center gap-1 align-middle h-control-nested whitespace-nowrap rounded-chip
                      px-sm (icon-only: aspect-square w-control-nested justify-center px-0)
                      font-sans text-caption font-medium leading-[round(1.25em,1px)]  (+ shrink-0, or min-w-0 when truncate)
```

- Gap 4 between icon, text and remove button.
- Text: caption size of the step, **wght 460**.
- `rounded-chip` = `h-control-nested / 4`.

### 3.2 Sizes

Size → attribute: `xxs` → `data-step="1"`; `xs`, `sm`, `lg` → `data-size`; base has none.

| size | compact h / px / text / radius | comfortable h / px / text / radius |
|---|---|---|
| xxs | 16 / 4 / 10 / 4 | 16 / 4 / 10 / 4 |
| xs | 16 / 4 / 10 / 4 | 18 / 6 / 11 / 4.5 |
| sm | 16 / 4 / 10 / 4 | 20 / 8 / 12 / 5 |
| base | 18 / 6 / 11 / 4.5 | 22 / 8 / 12 / 5.5 |
| lg | 20 / 8 / 12 / 5 | 28 / 12 / 13 / 7 |

- **Line-height** `round(1.25em,1px)`: 10→13, 11→14, 12→15, 13→16.
- When the only child is text, it is wrapped in a span:
  - On step 1 (all `xxs`; also compact `xs` and `sm`, since `ya` clamps to 1): `leading-[0.75rem] py-[0.125em] -my-[0.125em]`, i.e. 12 px leading.
  - Otherwise: `pb-[0.05em]`.
- **Icon:** size from `gs`:

  | density | lg | base | sm | xs | xxs |
  |---|---|---|---|---|---|
  | comfortable | md 20 | sm 16 | sm 16 | xs 12 | xs 12 |
  | compact | sm 16 | xs 12 | xs 12 | xs 12 | xs 12 |

  - Left margin `(h-nested − icon)/2 − pad-sm + 1`, right margin −0.8. Examples: comfortable base −4; compact xs −1.
- **Remove "×"** (`onRemove`):
  - Size `max(h-nested − 6, 12)` (comfortable base 16; compact xs 12).
  - Radius `h-nested/4 − min(3, (h-nested − 12)/2)`.
  - X icon xs at `'wght' 577.8`, 700 on hover.
  - Hover fill `color-mix(currentColor 10%)` (20% when `bold`).
  - Hit area at least 24×24.

### 3.3 Colours (dark)

Default variant is **`accent`**.

| variant | tinted (default) | `bold` |
|---|---|---|
| neutral | `bg-neutral` white 5%; text `#c3c2b7` | `#5f5e5a` bg (`dark:bg-gray-550`); white text |
| accent | `bg-tint-blue`; text `#6da7ec` | `#256abf`; white |
| success | `bg-tint-green`; text `#55bf50` | `#008300`; white |
| warning | `bg-tint-yellow`; text `#db9300` | `#945d00`; white |
| danger | `bg-tint-red`; text `#ec7e7e` | `#d03b3b`; white |
| pro | `bg-tint-violet`; text `#a096eb` | `#7161e0`; white |

Tint backgrounds are `rgb(from TINT (c − 5.25)/.75 …) / 75%`, which composites back to TINT over `#151515`. Out-of-range channels clamp to 0–255 when rendered:

| tint | TINT hex | rgba |
|---|---|---|
| blue | `#032042` | `rgba(0,36,81,.75)` |
| green | `#11260f` | `rgba(16,44,13,.75)` |
| yellow | `#311a00` | `rgba(58,28,0,.75)` |
| red | `#3c0e0e` | `rgba(73,12,12,.75)` |
| violet | `#1d1649` | `rgba(32,22,90,.75)` |
| orange | `#371407` | `rgba(66,20,2,.75)` |
| aqua | `#022720` | `rgba(0,45,36,.75)` |
| magenta | `#390f1f` | `rgba(69,13,34,.75)` |

The colour palette variants use the same tints:

| colour | text | bold background |
|---|---|---|
| red | `#ec7e7e` | `#d03b3b` |
| orange | `#ec835a` | `#c25124` |
| yellow | `#db9300` | `#945d00` |
| green | `#55bf50` | `#008300` |
| aqua | `#3bbd8c` | `#0f7e5c` |
| blue | `#6da7ec` | `#256abf` |
| violet | `#a096eb` | `#7161e0` |
| magenta | `#e87ba4` | `#c04873` |

Bold variants always use white text.

### 3.4 Count pills in the current build

- **The quoted sidebar group count pill does not exist in the current build.** The string `inline-flex h-4 min-w-4 items-center justify-center rounded px-1 text-footnote tabular-nums ${unread?"bg-fill-accent text-on-accent":"bg-alpha-1 text-muted"}` appears only in the older chunk `c1c1ec7b9-1y55QW_K.js`, inside a `group/hdr` section header ("New messages"). The current `c1c1ec7b9-DU5lyQpQ.js` doesn't have it. For reference, resolved in comfortable:

  | property | value |
  |---|---|
  | height | 16 |
  | min-width | 16 |
  | horizontal padding | 4 |
  | radius | `--cds-radius` (8 comfortable, 6 compact) |
  | text | footnote 13/17 (12/15 compact), tabular numbers |
  | default | white 5% fill, `#898781` text |
  | unread | `#2a78d6` fill, white text |

- **Current sidebar group "badge"** (`[data-group-badge]`, `shared-18` `UE`): `-my-1 ml-auto flex size-6 shrink-0 items-center justify-center`. In `.df-session-list` it becomes `width:auto; margin-left:2px`, and it is hidden when empty. Its content is `eM` (`shared-21`), a **status dot** (`$j kind` awaiting/ready…, 6×6, global §1.7), not a number.
- **Other count pills in the current build:**
  - Pending-invite avatar badge (`shared-19`): `absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full border-2 border-[hsl(var(--df-surface-primary))] bg-fill-danger px-1 text-caption font-medium text-on-danger`. That is 16 tall, full radius, `#d03b3b` with white caption 460, and a 2 px ring in the sidebar colour.
  - Remote-sessions counter (`ca80fca8d`): `shrink-0 rounded-sm px-1 py-0.5 text-footnote tabular-nums hover:bg-alpha-2`, text `text-warning` (`#db9300`) at capacity, otherwise `text-muted`.
  - Neutral count Badges: `fe variant:"neutral" className:"tabular-nums"` (`shared-21`, "N new runs").
  - The sidebar "Beta" badge is a neutral `xxs` Badge with `!text-on-accent` (`shared-18`). The nav one is neutral `xs` (global §2).

---

## 4. CDS Avatar (`data-cds="Avatar"`)

Source: `shared-frame-BAME2HDg.js`, `OA` (export `Jr`), variants `EA`, initials `DA`, stack `EF`.

### 4.1 Base

```
span[data-cds=Avatar]: inline-flex shrink-0 select-none items-center justify-center overflow-hidden rounded-full font-sans font-medium leading-none
```

- Always a **circle**, with **no ring or border** on a single avatar.
- Text weight **460**, line-height 1.

### 4.2 Sizes

| size | compact | comfortable | initials text |
|---|---|---|---|
| xs | 16 | 20 | `--cds-avatar-text-xs`: 8 compact / 9 comfortable; **one** initial |
| sm | 20 | 24 | fixed 9 px; two initials |
| md (default) | 28 | 32 | footnote: 12 compact / 13 comfortable |
| lg | 36 | 40 | body: 13 compact / 14 comfortable |

### 4.3 Variants (dark)

| variant | background | text |
|---|---|---|
| default | `bg-fill-control` white 10% | `#f0efec` |
| pro | `#7161e0` | `#fff` |
| claude | `#c6613f` | `#fff`; shows the Claude mark at 60% of the size instead of initials |

### 4.4 Initials and image

- **Initials** (`DA`): the first grapheme of the first word, plus the first grapheme of the last word when two are wanted and there are at least two words. They are upper-cased in the locale. "?" is the fallback.
- **Image:** `img.size-full object-cover`, `draggable=false`, clipped by the circle. On a load error it falls back to initials.
- **Sidebar footer use:** sm with `!size-5` (20), for example "P" (global §2).

### 4.5 AvatarStack (`data-cds="AvatarStack"`)

`isolate inline-flex shrink-0 items-center`. Each item is wrapped in `relative inline-flex rounded-full bg-[var(--cds-page-bg)] [box-shadow:0_0_0_2px_var(--cds-page-bg)]`:

| property | value |
|---|---|
| ring | 2 px in the page background (`#0b0b0b` by default; the surface colour inside surfaces) |
| overlap | `margin-inline-start: -25% of the size` |
| z-order | later items sit under earlier ones (`zIndex = n − 1 − i`) |
| max shown | 5 |

Surplus chip "+N": `bg-fill-control text-secondary rounded-full font-medium leading-none`, same height and text as the size. Chip padding: xs 4, sm 6, md 8, lg 12. It adds start/end padding to clear the overlap.

---

## 5. Two-line list rows (chats and sessions)

- **Recents page (`/recents`): UNKNOWN.** The route loads chunk `c623cddd3-Coc-_YDH.js` (`PS` in `shared-17`), which isn't in the cache for the current build (only older builds' copies exist). Its row classes can't be traced from current code.
- The two-line rows that are in the current build are below.

### 5.1 Sidebar session row with description

Source: `shared-18` `mE`/`hE`; `shared-styles-B1jXfLTX.css`. This is the frame's own two-line row, used for described sessions.

- **Row:** `mE` variant `session` + `described:true` → `df-described-row flex-col items-stretch justify-center`. It keeps the row hover and selected treatment `dE`: `rounded-[var(--df-radius-pill)]`, hover `var(--df-hover)` (white 7.5%), selected `var(--df-selected)` (white 15%, text `#f0efec`). The radius is 6 (global §2).
- **Padding** (compact frame, classic list): `padding-block: (row-h − row-ctl)/2 + tuck − trim` = (26 − 20)/2 + 4 − 2 = **5** top and bottom. `.df-session-list` has `--df-described-trim: tuck/2`.
- **Gap and line boxes:** `row-gap: 2px`. Each line box is `height: (--df-described-line ?? row-ctl) − tuck` = 20 − 4 = **16**.
- **Total height:** 5 + 16 + 2 + 16 + 5 = **44**. With the gated `data-code-list` layout (not active, global §1.1): row-h 28, line 20, gap 4, padding 5/7, so 48.
- **Line 1** `df-described-title flex min-w-0 items-center gap-[var(--df-row-gap)]`:
  - **13 px**, line-height 16 (`.dframe-sidebar[data-density=compact] .df-session-list .df-described-title{line-height:16px}`), wght 360.
  - Colour `#c3c2b7`; `#f0efec` when selected.
  - Contains the leading slot (24, glyph 16) and the title, 4 apart.
- **Line 2** `df-row-description flex min-w-0 items-center text-muted`:
  - `font-size: var(--df-group-font)` = **12**, line-height 16, `gap: 6px`, colour `#898781`.
  - Left padding: leading slot + gap = **28** when the row has an icon; otherwise `--df-iconless-pad` = 8 in the session list.
  - Right padding 0 in the session list.
  - The meta line (`.df-meta-line`) carries the trailing meta. It fades out at the right edge: `mask-image: linear-gradient(90deg, #000 calc(100% − 12px), transparent)` with 12 px of end padding (24 outside the session list).
- **Trailing controls:** vertically centred on line 1: `top: row-h/2 + tuck/2 − trim` = 13 + 2 − 2 = **13**.
- **Dividers:** none. Rows are separated by `gap-px` (`flex flex-col gap-px`) plus `[data-row]{margin-bottom:.5px}` in the web variant.
- **Skeleton:** `oJ`. Title bar of height `var(--df-row-font,13px)`, description bar `var(--df-group-font,12px)`, widths cycling 68%, 54%, 44%.

### 5.2 Palette row with snippet

See §1.5: 52 tall, 14/20 title over a 12/16 muted snippet, 8 vertical padding, 8 radius, trailing 12/16 muted time.

### 5.3 "Resume a CLI session" picker (Code)

Source: `cc43287c9-CZKZapce.js`, `u6`, `c6`, `d6`. This is a one-line session list in a comfortable Dialog `size:"2xl"`.

- **List:** `ul.flex min-h-0 flex-1 flex-col gap-0.5 overflow-y-auto overflow-x-hidden`, gap 2.
- **Group header:** `px-sm pb-0.75 pt-sm text-caption text-muted`: padding 8 left/right, 8 top, 3 bottom; 12/17 muted.
- **Row:** `li.flex h-8 items-center gap-1 rounded-[5px] px-sm`: **32 tall**, radius 5, padding 8, gap 4.

  | state | treatment |
  |---|---|
  | selected | `bg-fill-ghost-selected text-primary` (white 15%, `#f0efec`) |
  | unselected | `text-secondary` (`#c3c2b7`) |
  | hover | white 7.5% |

  - Status: a dot `size-2 rounded-full` (8).
  - Title: `min-w-[2rem] shrink truncate text-body` (14/20); italic when untitled.
  - Branch: `flex items-center gap-0.5 text-caption text-muted` with Icon `GitBranch` xs.
  - Folder chip: `ml-auto max-w-[7rem] shrink-0 truncate rounded-[3px] px-0.75 text-caption text-muted shadow-field-ring`: 3 px padding, radius 3, inset 1 px white 10% ring.
  - Time: `min-w-[3.5rem] shrink-0 text-right text-caption text-muted tabular-nums` (12/17).
- **Footer:** `flex items-center gap-xs border-t pt-lg text-caption text-muted`: 1 px white 10% top border, 16 top padding, keycaps for ↑↓ "navigate", esc "close", enter "resume".
- **Detail pane:** `aside.flex min-w-0 flex-1 flex-col border-l pl-lg`. Title `truncate text-heading-semibold text-primary`. A `dl.grid grid-cols-[5.5rem_minmax(0,1fr)] gap-x-xs gap-y-1 border-b pb-md text-caption` (terms muted, values secondary).

---

## 6. Empty states and scroll fades

### 6.1 Empty states

- **"No sessions match" dashed box: not in the current build.** The current Code text "No sessions match your search." (`c6`, CLI-resume picker) is a plain list item: `li.text-body text-muted italic px-sm py-1.25`, i.e. 14/20 italic `#898781`, padding 8 horizontal and 5 vertical. No border.
- **Dashed empty boxes that exist:**

  | where | file | classes | rendering |
  |---|---|---|---|
  | "No members found" | `cee2576d5` | `rounded-lg border border-dashed border-strong px-3 py-4 text-center text-caption text-muted` | radius 8, **1 px dashed white 20%**, padding 12×16, caption 12/17 `#898781`, centred |
  | hook-blocked prompt card | `c1c1ec7b9-DU5lyQpQ` | `flex w-full flex-col gap-1 rounded-lg border border-dashed border-alpha-2 p-sm text-secondary` | 1 px dashed white 10%, padding 8 (comfortable) / 6 (compact); body text then a caption muted line |
  | info box | `c12c3079a` | `rounded-card mt-4 border border-dashed px-5 py-4` | default border colour white 10% |

- **Sidebar session list** (`eJ`, `shared-20`):
  - Filtered: `div.flex flex-col items-center gap-2 px-4 py-6 text-center` with `p.text-footnote text-muted` ("No sessions match the current filters", 12/15 compact), and a link button `text-footnote text-secondary underline-offset-2 hover:text-primary hover:underline` ("Show all sessions").
  - Empty: `flex min-h-[200px] select-none flex-col last:flex-1 items-center justify-center gap-4 px-4 pb-10 text-center`, with the same footnote text ("Sessions you start will show up here") and an illustration (`xq`, scale 0.55).
  - Load failed: the same centred column with "Couldn't load your sessions" and a Button `sm` "Try again".
  - Empty custom group: `p.df-label-inset flex min-h-[var(--df-row-h)] select-none items-center py-1 pr-[var(--df-row-px)] text-caption text-muted` ("Drag or move sessions here"). It is hidden inside `.df-session-list`.
- **Popover list empties:**
  - Settings search, "No matching settings": `px-md py-sm text-footnote text-muted`, or `flex min-h-[120px] flex-col items-center justify-center gap-sm px-md text-center text-muted` with an xl icon.
  - Artifacts: `mt-10 text-center text-body text-muted`.

### 6.2 Scroll fades

**CDS `scroll-fade-y`** (CSS, used by lists, e.g. icon picker, tool lists). This is a mask on the scroller, driven by scroll timeline:
- `mask-image: linear-gradient(to bottom, transparent, …, #000 var(--cds-scroll-fade-top), #000 calc(100% − var(--cds-scroll-fade-bottom)), …, transparent)`.
- Alpha stops at 15 / 30 / 45 / 60 / 75 / 87 / 100% of the fade length: 0.05, 0.15, 0.30, 0.50, 0.70, 0.85, 1.
- The fade length ramps from 0 to `--cds-scroll-fade-size` over the first and last `size` px of scroll, so there's no top fade at the top and no bottom fade at the end.
- Default size **28 px** (`@property --cds-scroll-fade-size initial-value:28px`). `scroll-fade-size-N` = N × 4 px (e.g. `-6` = 24, `-3` = 12).
- `scroll-fade-x` is the horizontal equivalent. `scroll-fade-hide-top/bottom` turn an edge off.

**Strip variant** (`scroll-fade-strip-top/-bottom`): a sticky element `height: size`, background `linear-gradient(to bottom, C, C/.85 13%, C/.5 40%, C/.15 70%, transparent)`. C = `--cds-scroll-fade-strip-color`, default surface-1 `#151515`. Its opacity follows the scroll position.

**Palette:** a sticky drop shadow instead of a mask (§1.4): 0 2px 8px black 6%, revealed after scrolling.

**Sidebar:**
- `.df-fade-truncate{mask-image:linear-gradient(90deg,#000 calc(100% − 12px),transparent); padding-right:12px; margin:-4px 0; padding-block:4px}`: a 12 px right fade on long labels.
- `.df-meta-line`: a 12 px fade (§5.1).
- The footer suffix: a 12 px right fade (global §2).

---

## 7. Quick reference (dark)

| item | value |
|---|---|
| palette panel | min(100vw − 80, 672) wide, radius 20, `#20201f`, 0.5 px white 20% border, shadow `0 25 50 −12 rgba(0,0,0,.25)`, backdrop black 50% |
| palette input row | padding 24 / 17.6 / 10 / 14.4, gap 8, 14/20 text `#f0efec`, placeholder `#898781`, 32×32 ghost X; then a 0.5 px white 10% divider |
| palette list | padding 10, max height 440, group gap 4, header 14 / 12 / 8 padding, 12/17 muted (height 37) |
| palette row | padding 12×8, radius 8, gap 12 (8 inside), 20 px icon, 14/20 `#c3c2b7`; selected white 7.5% + `#f0efec`; matched text wght 540 primary; height 36 (52 with a snippet line 12/16 muted) |
| palette trailing | 12/16 `#898781` time bucket; on the selected row, a 16 px ⏎ icon |
| palette footer | 0.5 px top border, padding 20 / 16 / 10, 12/17 muted, hints 20 apart, keycaps 18 tall radius 4 with a 1 px 22% border (gate on) or 20×20 with a 0.5 px border (gate off) |
| tab (comfortable base) | 32 tall, 12 padding, 14/20 wght 460; muted → hover secondary + 7.5% pill → active primary + 7.5% pill; pill radius 8, inset 1 px |
| badge (comfortable base) | 22 tall, 8 padding, radius 5.5, 12/15 wght 460; neutral: white 5% + `#c3c2b7`; accent: blue tint + `#6da7ec` |
| avatar | circle; 20/24/32/40 comfortable (16/20/28/36 compact); white 10% fill, `#f0efec` initials wght 460 |
| sidebar two-line row | 44 tall, 5 padding, 16 + 2 + 16; title 13/16 secondary, meta 12/16 muted, meta indented 28 |
