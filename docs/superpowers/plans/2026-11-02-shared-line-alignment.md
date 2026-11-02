# Shared-line alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every output starts a shared line's middle and last parts where the part before ended, as the site does, and falls back to the fixed step (`part-m` / `part-f`) where the line has no room.

**Architecture:** One function computes each part's lead, the earlier parts' text: `SplitVerses.leads/1`, moved out of `StaticSite.Edition.ghosts/1`. Every output prints the fixed step plus an invisible lead that is `display: none`. One script in `site.js`, `EMOTHE.align/1`, switches the lead on (`data-aligned`) for each line that still fits on one line. It runs on the site, on the play page (a hook), in the HTML download and in the PDF (inlined; ChromicPDF runs it once before printing). The EPUB cannot count on scripts, so it decides by the whole line's plain length: 45 characters or less aligns.

**Tech Stack:** Elixir/Phoenix LiveView, plain JS (`priv/static_site/site.js`), ChromicPDF.

**Spec:** `docs/backlog.md` B2, and questions 44 and 61 in `docs/stakeholder/preguntas.html`.

## Global Constraints

- With scripts off, every middle or last part takes the fixed step: the site's step is `3em` / `6em`, the play page's `.part-m` / `.part-f` in `app.css`, and the export's 50px / 100px.
- A lead is `aria-hidden="true"`, `visibility: hidden` once shown, and carries no note links.
- The EPUB limit is `@epub_align_max 45`, the whole shared line's `InlineMarkup.plain/1` length. It is proposed to the owner, not approved, and question 61 says so.
- `site.js` stays within 15,000 bytes (`static_site_test.exs`).
- The compare pages keep their own "Split verses" switch with fixed steps: they get no leads.

## Review Focus

- A LiveView patch drops `data-aligned` from the lines it re-renders. The hook's `updated()` must re-run `align`, so the container carries `data-switches` (as `stepper/1` does) and changes whenever a text switch changes.
- Hiding inline stage directions on the play page changes a line's length, so alignment must be re-measured after that switch.
- Resizing re-measures, but a phone's URL bar hiding (a change of height only) must not.
- Web fonts load late on the site: re-measure on `document.fonts.ready`.
- In the PDF, ChromicPDF's window is not the paper's width, so the page is pinned to the paper's text width before the script measures.

---

### Task 1: Leads in one place; the site defaults to the fixed step and the script aligns

**Files:**
- Modify: `lib/playcode/play_content/split_verses.ex`, `lib/playcode/play_content/element.ex`, `lib/playcode/export/static_site/edition.ex:513-538`, `lib/playcode/export/static_site/components.ex:720-776`, `priv/static_site/style.css:142`, `priv/static_site/site.js`
- Test: `test/playcode/export/static_site_play_test.exs:524-554`

**Interfaces:**
- Produces: `SplitVerses.leads(lines) :: %{id => %{lead: String.t(), line: String.t()}}`. `lines` are verse lines in reading order (maps with `id`, `part`, `content`). It has one entry per middle or last part that has an earlier part. `lead` is the earlier parts' content joined by `" "`, and `line` is every part of that shared line joined by `" "`. The rules are `ghosts/1`'s: "I" opens, "M" carries on, "F" closes, and anything else resets.
- Produces: `Element.verse_lines(divisions)`, the verse lines of `load_play_content/2` divisions in reading order: a division's own elements, then its children's, at any depth.
- Produces: `EMOTHE.align(scope)` in `site.js`. For each `.ghost` in `scope`, its parent is the line's text box. It sets `data-aligned` on every box (a write), reads every box's height (a read), and removes the attribute where the height is at least 1.5 × the computed line height (a write). If the line height is "normal", use 1.2 × the font size. On DOMContentLoaded it runs on `document`, again on a `resize` that changes `innerWidth`, after `document.fonts.ready`, and after any `[data-toggle]` change.

- [ ] **Step 1: Update the test.** In "a middle or last part with no first part before it…", expect `classes["Verso partido"] == ["l", "part-f"]`, with a comment that every part now takes the fixed step and the script aligns it. In the ghost test, also assert that the `.ghost`'s parent `.t` has no `data-aligned` in the markup. Add a CSS assertion: `css =~ ~r/^\.ghost \{[^}]*display: none/m` and `css =~ ~r/\[data-aligned\] > \.ghost \{[^}]*visibility: hidden/`.
- [ ] **Step 2: Run** `mix test test/playcode/export/static_site_play_test.exs`. Expected: FAIL on `"Verso partido"` (`["l"]`).
- [ ] **Step 3: Implement.**
  - Add `leads/1` and `verse_lines/1`. `Edition` keeps its `ghosts` field as `%{id => lead}` from `SplitVerses.leads/1`.
  - `orphan_part/2` becomes a plain `part_class(el)`: the fixed step for every M/F part.
  - CSS: `.ghost { display: none; }`, `[data-aligned] > .ghost { display: inline; visibility: hidden; }`, `.l.part-m .t[data-aligned], .l.part-f .t[data-aligned] { padding-left: 0; }`.
  - Add `E.align` to `site.js`.
- [ ] **Step 4: Run** the same file. Expected: PASS.
- [ ] **Step 5: Browser check** with `S/cdp.mjs` on a generated play that has shared lines, at `W=1280` and `W=360`: short shared lines are aligned (`data-aligned`), and a long one at 360 is not. Then run `node --test test/js/*.test.mjs`.
- [ ] **Step 6: Refactor while green, then commit** `feat: the site's shared lines take the fixed step unless they fit aligned`.

### Task 2: The play page

**Files:**
- Modify: `lib/playcode_web/components/play_text.ex`, `lib/playcode_web/live/play_show_live.ex`, `assets/js/app.js`, `assets/css/app.css:174-190`
- Test: `test/playcode_web/live/play_show_live_test.exs`

**Interfaces:**
- Consumes: `SplitVerses.leads/1`, `Element.verse_lines/1`, and `EMOTHE.align/1` (Task 1).
- Produces: a `leads` attr (map, default `%{}`), threaded through `play_text` the way `show_split_verses` is. A verse line with a lead renders `<span class="ghost" aria-hidden="true">` with the lead's `inline_content` (no notes, stage shown as `show_stage_directions` says) and a space, inside the part's span, which keeps its `part-m` / `part-f` class. The text container gets `phx-hook="AlignParts"` and `data-switches={text_switches(assigns)}`.

- [ ] **Step 1: Write the failing test.** "a shared line's later part carries the earlier part's words, hidden, and the fixed step": import a play with `<l n="1" part="I">Verso</l><l part="F">partido</l>`, mark it complete, `live(conn, ~p"/plays/#{code}")`. The `[data-part="F"]` span has the class `part-f` and holds `.ghost[aria-hidden="true"]` with the text "Verso".
- [ ] **Step 2: Run it.** Expected: FAIL (no `.ghost`).
- [ ] **Step 3: Implement.**
  - `play_show_live` assigns `leads = divisions |> Element.verse_lines() |> SplitVerses.leads() |> Map.new(fn {id, %{lead: l}} -> {id, l} end)` and passes it.
  - `app.css` gets the `.ghost` and `[data-aligned]` rules as in Task 1, for `.verse-line .part-m` and `.part-f`.
  - The `AlignParts` hook calls `EMOTHE.align(this.el)` in `mounted()` and `updated()`.
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Browser check** on dev's `/plays/EMOTHE0560` (`S/c.exs` to make it complete, then revert): the lines are aligned at 1280; after toggling stage directions the attributes are back.
- [ ] **Step 6: Refactor, then commit** `feat: the play page lines up a shared line's parts where there is room`.

### Task 3: The HTML download and the PDF

**Files:**
- Modify: `lib/playcode/export/html.ex`, `lib/playcode/export/pdf.ex`
- Test: `test/playcode_web/controllers/export_controller_test.exs`

**Interfaces:**
- Consumes: `SplitVerses.leads/1`, `Element.verse_lines/1`, and `site.js` (read at compile time, `@external_resource`, as `CompareHtml` does `sync_scroll.mjs`).
- Produces: `Html.generate(play, opts \\ [])`. With `text_width: "6.9in"`, it adds `@media screen { .page { max-width: none; width: 6.9in; padding: .5rem 0; } }`, so the screen layout the script measures is the printed one. `Pdf.generate/1` passes it, with a comment: Letter is 8.5in less two 0.8in margins.

- [ ] **Step 1: Write the failing test** in `export_controller_test.exs`, through `get(conn, ~p"/export/#{play.id}/html")`. The `F` part's `.content` has the class `part-f` and a `.ghost` holding "Verso", and the page holds a `<script>` defining `EMOTHE.align`.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement.** Keep the leads in the export's render pass, the CSS rules as in Task 1, `<script>` with `site.js` before `</body>`, and the `text_width` option.
- [ ] **Step 4: Run** it. Expected: PASS.
- [ ] **Step 5: PDF check:** generate EMOTHE0560's PDF from `mix run`, render page 2 with `pdftoppm -png`, and look: the parts are aligned. If ChromicPDF does not run the script, rule on it in the ledger (`evaluate:` option).
- [ ] **Step 6: Refactor, then commit** `feat: the HTML and PDF line up a shared line's parts where there is room`.

### Task 4: The EPUB

**Files:**
- Modify: `lib/playcode/export/epub.ex`
- Test: `test/playcode_web/controllers/export_controller_test.exs`

**Interfaces:**
- Consumes: `SplitVerses.leads/1` and `Element.verse_lines/1`.
- Produces: `@epub_align_max 45`. A part whose `line` has a plain length of 45 or less renders an inline `<span class="ghost" aria-hidden="true">` (CSS `visibility: hidden`) and no step class. A longer one takes `part-m` / `part-f` and no lead.

- [ ] **Step 1: Write the failing test,** through `/export/:id/epub`, reading the chapter XHTML from the zip. The 13-character "Verso partido" gets a ghost and no `part-f`. A 46-character shared line (I "Sire, miséricorde! Ô Dieux!" + F "qu'ai-je commis? Ah") gets `part-f` and no ghost.
- [ ] **Step 2: Run it.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run it.** Expected: PASS.
- [ ] **Step 5: Refactor, `mix test`, and commit** `feat: the EPUB lines up a short shared line's parts`.

### Task 5: Docs

- [ ] Move B2 from `docs/backlog.md` to `docs/history.md`, and update the item "How split verses are laid out" in the backlog.
- [ ] In `docs/static-site.md`, describe the fallback.
- [ ] In `preguntas.html`, update questions 44 and 61, with question 61 proposing the 45-character EPUB limit and the measured shares.
- [ ] Update the split-verse row in `ida-y-vuelta.html` if it names the layout.
- [ ] Commit as `docs: shared lines aligned in every output`, push, and republish Questions and Round Trip.
