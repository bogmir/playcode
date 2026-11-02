# Shared lines and stage directions (B3, B4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two highlight switches, on the play page and the published site, each with arrows that step to the next or previous one and an "N of M" count: "Shared lines" (B3) and "Stage directions" (B4).

**Architecture:** Shading is CSS, switched by a body attribute on the site (as the other toggles) and by a LiveView assign on the play page. Stepping is one JS function in `priv/static_site/site.js`, `EMOTHE.stepper`, which the site wires to its rail and the play page's `Stepper` hook reuses (app.js imports site.js). It steps from the scroll position, not from a remembered index, so a reader who scrolls away steps from where they are.

**Tech Stack:** Phoenix LiveView 1.1, HEEx, plain browser JS (`node --test`), Tailwind/daisyUI on the play page, `style.css` on the site.

**Spec:** `docs/backlog.md`, *Proposed from the answers of 1 and 2 November*, B3 and B4; questions 45, 52, 62 and 65 in `docs/stakeholder/preguntas.html`.

## Global Constraints

- Name: "Shared lines" everywhere readers see it, the switch and the statistics (question 65). Spanish: "Versos compartidos".
- The count is of shared lines, not of their parts: one per first part (`part == "I"`), as `Statistics.count_split_verses/1` counts.
- Shading: first, middle and last parts in three greys, with a legend; text over each grey keeps 4.5:1 in both themes (light and dark, site and play page).
- The play page's "Split verses" switch goes: the parts always step in on the play page (the comparison page keeps passing `show_split_verses: false`).
- The switch that hides the stage directions stays (question 62). No study mode, no J/K keys.
- Stepping skips what is hidden (a hidden stage direction, a Folio passage while its toggle is off).
- Site: no third-party requests, works from `file://`; `site.js` ≤ 15 000 bytes, `style.css` ≤ 25 KB (`static_site_test.exs`).
- Every button named (`aria-label`); the count `aria-live="polite"`; `accessibility_test.exs` passes.
- TDD per CLAUDE.md: red, green, refactor, full `mix test`, prove each new test bites; `mix format`, `mix compile --warnings-as-errors`.

## Review Focus

- A play or page with no shared lines (a prose play, a cast list page), or no stage directions: that option is not shown at all, no switch, no arrows, no "0 of 0" (owner, 2026-11-02) — tests in Task 2 and Task 3.
- Next at the last one, previous at the first: stays put, no wrap — node test in Task 1.
- The stage directions hidden while their highlight is on: nothing to step, count "0 of 0" — node test in Task 1 (hidden elements skipped).
- An inline stage direction (`.sdi`, one in four) is a step target as well as a block one, in reading order — Task 3 asserts both carry the target marker.
- LiveView re-render (another switch clicked) must not drop the shading or the count: shading lives in server markup, the hook recounts in `updated()` — Task 2.

---

### Task 1: `EMOTHE.stepper`, the stepping core

**Files:**
- Modify: `priv/static_site/site.js`
- Test: `test/js/stepper.test.mjs` (new, loads site.js in `vm` as `search.test.mjs` does)

**Interfaces:**
- Produces: `EMOTHE.step(tops, line, dir) -> index` (pure): `tops` the viewport tops of the visible targets in reading order, `line` the reading line (half the viewport height), `dir` `1` or `-1`. Returns the first index whose top is below `line + 1` for `1`, the last above `line - 1` for `-1`, or `-1` when there is none.
- Produces: `EMOTHE.stepper(box, selector)`: wires a box holding `[data-step="-1"]`, `[data-step="1"]` and `[data-step-count]`. On click it collects `document.querySelectorAll(selector)` that have client rects (hidden ones skipped), picks with `step`, scrolls it to the centre (`scrollIntoView({block: 'center'})`), marks it `data-current` (removing the mark from the last one) and writes `"N of M"` (the word from `box.dataset.of`, default `of`). Returns `{refresh()}`, which recounts M and disables both buttons when M is 0 (only while every target is hidden, say the stage directions switched off: a page with none never shows the box).

- [ ] **Step 1: Write the failing tests**: with `tops [-50, 10, 300, 900]` and `line 300`, next (`1`) is index 3 (300 sits on the line, so it is the current one) and previous (`-1`) is index 1. Next past the last returns `-1`; previous before the first returns `-1`; empty `tops` returns `-1` both ways.
- [ ] **Step 2: Run** `node --test test/js/stepper.test.mjs`. Expected: FAIL, `EMOTHE.step is not a function`.
- [ ] **Step 3: Implement `step` and `stepper`** in site.js, defined before the `if (!root.document) return;` line only for `step` (the vm has no document); `stepper` goes after it. On `-1` from `step`, leave the current one and the count as they are.
- [ ] **Step 4: Run** `node --test test/js/*.test.mjs`. Expected: all pass. Break the `+ 1` margin, watch the on-the-line case go red, put it back.
- [ ] **Step 5: Commit** with Task 3 (the site wiring): no reader sees Task 1 alone.

### Task 2: The play page

**Files:**
- Modify: `lib/playcode_web/live/play_show_live.ex` (assigns, events, side panel, the `Stepper` hook's markup)
- Modify: `lib/playcode_web/components/play_text.ex:305-315` (a verse line carries `data-part`; a stage direction and an inline one carry `data-sd`)
- Modify: `lib/playcode_web/components/statistics_panel.ex:69` (label "Shared lines")
- Modify: `assets/js/app.js` (`import "../../priv/static_site/site.js"`; hook `Stepper`: `mounted()` calls `window.EMOTHE.stepper(this.el, this.el.dataset.selector)`, `updated()` calls `refresh()`)
- Modify: `assets/css/app.css` (the three greys, the stage-direction highlight, `[data-current]` outline)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`
- Test: `test/playcode_web/live/play_show_live_test.exs`, `test/playcode_web/accessibility_test.exs` (only if a new modal or page; the panel is on a listed page already)

**Interfaces:**
- Consumes: `EMOTHE.stepper` (Task 1).
- Produces: assigns `:shade_shared` and `:shade_stage` (both `false` at mount); `:has_shared_lines` and `:has_stage_directions`, set at mount as `:has_variants` is (any verse line with `part == "I"`; any stage direction, a block one or inline in a line's content), and each row of the Highlight section renders only when its flag is true (the section itself only when either is); events `"toggle_shared_lines"`, `"toggle_stage_highlight"`; the text wrapper `#play-tab-text` gains `data-shared="on"` / `data-sd-mark="on"` while each is on. Removed: `:show_split_verses` from the play page, its event and its switch (the `play_text` attr stays, default `true`, for the comparison page).

Side panel: a new section after "Visual markers", heading "Highlight" (gettext; Spanish "Resaltar"), two rows, each a checkbox ("Shared lines", "Stage directions") and, while it is on, the stepper box: `<div id="step-shared" phx-hook="Stepper" data-selector="#play-tab-text [data-part=I]" data-of={gettext("of")}>` with `‹` `›` buttons named "Previous shared line" / "Next shared line" (and "Previous stage direction" / "Next stage direction", selector `#play-tab-text [data-sd]`) and an `aria-live="polite"` count. While "Shared lines" is on, a legend under it: three swatches, "First part", "Middle part", "Last part".

Greys, by CSS on `[data-shared=on] [data-part=I|M|F] ` (the text span only, not the line number): `oklch(from var(--color-base-content) l c h / 0.07)`, `/ 0.14`, `/ 0.21`. Stage directions while marked: `bg-primary/10`. Check 4.5:1 for base-content and the muted stage-direction colour over the darkest grey in both themes with a short script (WCAG relative luminance from the computed colours); raise the alpha steps down if it fails, and note the measured ratios in the commit.

- [ ] **Step 1: Write the failing tests** in `play_show_live_test.exs`, `describe "the highlight switches"`, through `live/2`:
  - no "Split verses" label on the page; a "Shared lines" checkbox is there (`t("Shared lines")`, Spanish "Versos compartidos");
  - a play with an I, M and F line: before the click, `#play-tab-text[data-shared=on]` is absent and no legend; after `lv |> element("#shared-lines-switch") |> render_click()` (the checkbox's stable id; the stage directions' is `#sd-highlight-switch`) the wrapper carries `data-shared="on"`, the legend's three labels render, the lines carry `data-part="I"`, `"M"`, `"F"`, and `#step-shared` has the buttons named "Next shared line" and "Previous shared line";
  - the same for "Stage directions" under Highlight: `#step-sd` appears, the block and the inline stage direction both carry `data-sd`;
  - turning "Shared lines" on, then clicking "Line numbers", keeps `data-shared="on"` (re-render);
  - the statistics tab says "Shared lines", not "Split Verses";
  - a play with no `I` part has no `#shared-lines-switch` and no `#step-shared`; a play with no stage direction has no `#sd-highlight-switch`; a play with neither has no "Highlight" heading.
- [ ] **Step 2: Run** `mix test test/playcode_web/live/play_show_live_test.exs`. Expected: FAIL on the missing label.
- [ ] **Step 3: Implement** as above; `mix gettext.extract --merge`, then fill the Spanish (check every fuzzy).
- [ ] **Step 4: Run** the file, then `mix test test/playcode_web/accessibility_test.exs`. Expected: PASS. Break one line (drop `data-part`), watch it go red, restore.
- [ ] **Step 5: Look at it in the browser** (`mix phx.server`, a play with shared lines, both themes): greys, legend, arrows step, count reads "1 of N".
- [ ] **Step 6: Commit** `feat: shared lines and stage directions highlighted and stepped through on the play page`.

### Task 3: The published site

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex:111-138` (rail tools), `:684-700` (verse line), `:699-702` (stage direction), `:752-753` (`sdi`)
- Modify: `priv/static_site/site.js` (`initTools` wires the two steppers and their toggles)
- Modify: `priv/static_site/style.css` (greys as tokens `--sh-i`, `--sh-m`, `--sh-f` in `:root` and the dark block; shading; `[data-current]`)
- Test: `test/playcode/export/static_site_play_test.exs` (rail and markup), `test/js/stepper.test.mjs`, the size budget test as it stands

**Interfaces:**
- Consumes: `EMOTHE.stepper` (Task 1).
- Produces: `<body … data-sh="off" data-sdm="off">`; toggles `data-toggle="sh"` and `data-toggle="sdm"` (remembered like the others: add both keys to `initTools`' list); a verse line `div.l` carries `data-part="I|M|F"`; `.sd` and `.sdi` are the stage-direction targets (no new attribute needed: selector `.text .sd, .text .sdi`).

Rail, under the existing "Highlight" heading (which today holds the character select; show the heading when there is a cast, shared lines or stage directions): `<label><input type="checkbox" data-toggle="sh" /> Shared lines</label>` and its stepper box `<div data-stepper=".text .l[data-part=I]" data-of="of">` with buttons named "Previous shared line"/"Next shared line" and `<span data-step-count aria-live="polite"></span>`; the box shows while the toggle is on (`body[data-sh="off"] [data-stepper^=".text .l"] { display: none }` or `hidden` toggled in JS: pick the CSS rule, no JS). The legend as on the play page. The same for "Stage directions" with `data-toggle="sdm"`. Each row only when the page has one to step to (owner, 2026-11-02: no option, no "0 of 0"): the shared-lines row when the page holds a first part, the stage-directions row when it holds a stage direction. Decide per page, not per play: a cast list page or a prose act has none. Compute both in the page's assigns from the page's elements (the elements `page_text/1` renders), not in `Edition`, which is per play.

Greys on the site: `body[data-sh="on"] .l[data-part=I] .t` etc., token values chosen so `--ink` over `--sh-f` is ≥ 4.5:1 in both themes (light: start `#f1f2f4`, `#e4e6e9`, `#d6d9dd`; dark: `#1d2126`, `#262b31`, `#30363d`; verify with the same script as Task 2). Stage directions while marked: `background: var(--mark)`.

- [ ] **Step 1: Write the failing tests** in `static_site_play_test.exs`: a play with I/M/F lines and a stage direction builds a division page whose rail has the "Shared lines" toggle (`data-toggle="sh"`), buttons named "Next shared line" and "Previous shared line", the "Stage directions" highlight (`data-toggle="sdm"`); its lines carry `data-part="I"`, `"M"`, `"F"`; the body starts `data-sh="off"`. A prose-only page has no `data-toggle="sh"` and no "Next shared line" button; a page with no stage direction has no `data-toggle="sdm"`.
- [ ] **Step 2: Run** `mix test test/playcode/export/static_site_play_test.exs`. Expected: FAIL.
- [ ] **Step 3: Implement**; site.js `initTools` calls `E.stepper(box, box.dataset.stepper)` for each `[data-stepper]` and `refresh()` when its toggle changes.
- [ ] **Step 4: Run** the file, `node --test test/js/*.test.mjs`, `mix test test/playcode/export/static_site_test.exs` (budgets). Expected: PASS. Break the `data-part` attribute, watch it go red, restore.
- [ ] **Step 5: Build one play and open it from `file://`** (`mix playcode.export.site -o S/site` limited to a play with shared lines if the task takes a filter, else the dev corpus): both toggles, arrows, count, both themes, the toggle state remembered on the next page.
- [ ] **Step 6: Commit** Tasks 1 and 3 together: `feat: shared lines and stage directions highlighted and stepped through on the site`.

### Task 4: Docs and the questions

**Files:**
- Modify: `docs/backlog.md` (B3, B4 out; the order line), `docs/history.md` (one entry), `docs/static-site.md` (the rail's tools), `docs/stakeholder/preguntas.html` (questions 45, 52, 62, 65: "Not built yet" becomes "Built on 2 November 2026" with one line each of what readers see; 52's C stays for B5), `docs/stakeholder/acotaciones.html` only if it says A is unbuilt.
- No tests (docs only).

- [ ] **Step 1: Edit** the files above.
- [ ] **Step 2: Run** `mix test` (whole suite), `node --test test/js/*.test.mjs`, `mix format --check-formatted`, `mix compile --warnings-as-errors`. Expected: 0 failures.
- [ ] **Step 3: Commit** `docs: shared lines and stage directions built`, push to `main`. Republish Questions per the artifacts rule (skip and note if the account is wrong).
