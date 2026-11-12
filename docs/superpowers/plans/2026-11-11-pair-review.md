# Pair review (problem 5, step 5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the admin comparison gets a *Revisión de pares* tab beside *Lectura paralela* that
lists how Playcode paired a translation's speeches with its original's, marks the doubtful
ones, and links each speaker to its Elenco line; the comparison's HTML download goes.

**Architecture:** `Playcode.Alignment.review/2` turns the existing `align/2` result into
rows in the original's order (cuts included) with a length flag; the admin
`PlayCompareLive` reads `?view=pairs&translation=<id>` in `handle_params/3` and renders the
rows; the content editor already opens on its characters tab, so a speaker links to
`/admin/plays/:id/content#entry-<id>`.

**Tech Stack:** Elixir, Phoenix LiveView.

**Spec:** `docs/superpowers/specs/2026-11-11-pair-review-design.md`.

## Global Constraints

- Tab names: "Lectura paralela" (msgid `Side by side`), "Revisión de pares" (msgid
  `Pair review`); every string through `gettext`, Spanish filled, no fuzzy left in `es`.
- Staff only: the public `/plays/:code/compare` does not change.
- Kinds and their labels: same speaker (`same`), split (`split`), other speaker (`other`),
  added (`added`), cut (`cut`).
- Only translations and versions are reviewed (`Alignment.paired?/1`); adaptations never.
- The review reads; it stores nothing and corrects nothing.
- A translation id from the URL is resolved against the page's family, never trusted.
- Text from TEI is printed through `InlineMarkup.plain/1` or the text's renderers.
- TDD per task: red, green, refactor, `mix test`, `mix format`; prove new tests bite with
  `bin/bites`.

## Review Focus

1. **A `translation` param naming no play of the family, an adaptation, or garbage:** the
   tab falls back to the default choice, never raises, never shows another family's play.
   Test in Task 2.
2. **A family with nothing to review** (an original with only adaptations, or a play with
   no family): the tab says so, no crash. Test in Task 2.
3. **A speech with no characters, or a speaker the translation's Elenco lacks** (an `sp`
   naming no cast role): the row prints the speech's label and no link. Test in Task 3.
4. **Two short speeches of the same speaker** ("Yes." / "Oui, monseigneur."): no length
   warning. Test in Task 3.
5. **An original with acts but a translation without them** (segments fall back to the
   whole play): the rows still come out in the original's order. Test in Task 2.

---

### Task 1: The comparison's HTML download goes

**Files:**
- Delete: `lib/playcode/export/compare_html.ex`
- Modify: `lib/playcode_web/router.ex` (the `compare/export/html` route),
  `lib/playcode_web/controllers/admin/export_controller.ex` (`compare_html/2`),
  `lib/playcode_web/live/admin/play_compare_live.ex` (the button)
- Modify tests: `test/playcode_web/authorization_test.exs` (its row),
  `test/playcode_web/inline_markers_test.exs` ("the comparison download"),
  `test/playcode_web/controllers/admin/export_controller_test.exs` and
  `test/playcode_web/controllers/export_controller_test.exs` (their compare cases)
- Docs: `CLAUDE.md` (the scroll-sync line: the static site's `Comparison` inlines it),
  `docs/architecture.md:156`, `docs/static-site.md:49`, `docs/stakeholder/ida-y-vuelta.html`
  (the character pairs row's *Downloads* cell becomes "—")

- [ ] **Step 1: The failing test:** in the admin compare's test (create
  `test/playcode_web/live/admin/play_compare_live_test.exs`), the page has no link to
  `/admin/plays/compare/export/html`, and a `get` to it is a 404.
- [ ] **Step 2: Run, watch it fail.**
- [ ] **Step 3: Remove** the route, action, module and button; drop the tests that asserted
  the download. Before deleting the italics case in `inline_markers_test.exs`, name the
  test that still covers italics in a comparison (the static site's compare test, or the
  live page's); if none does, move the case to the live page.
- [ ] **Step 4: Green; `mix test`; `mix format`; docs; commit**
  `feat: the comparison's HTML download goes; the site publishes compare.html`.

### Task 2: The two tabs and the rows

**Files:**
- Modify: `lib/playcode/alignment.ex` (`review/2`)
- Modify: `lib/playcode_web/live/admin/play_compare_live.ex` (`handle_params/3`, tabs,
  the review's markup)
- Test: `test/playcode_web/live/admin/play_compare_live_test.exs`,
  `test/playcode_web/accessibility_test.exs` (the pairs view's path)

**Interfaces:**
- Produces: `Alignment.review(original_divisions, translation_divisions) :: [%{kind:
  :same | :split | :other | :added | :cut, original: %Element{} | nil, translation:
  %Element{} | nil, long: boolean}]`, divisions as `PlayContent.load_play_content/2` gives
  them; rows in the original's reading order, each original speech followed by the
  translation speeches paired with it, a cut as a row with no translation. `long` is
  Task 3's; false until then.

- [ ] **Step 1: The failing tests** (`split_speech_editions()`; `live/2` on
  `/admin/plays/#{french.id}/compare`):
  - Two tab links, "Lectura paralela" (`aria-current` on it by default) and "Revisión de
    pares"; following the second patches to `?view=pairs` and marks it current.
  - The pairs view lists four rows: ANTONY/ANTOINE same, CLEOPATRA/CLÉOPÂTRE same,
    the second CLÉOPÂTRE split, ANTONY/ANTOINE same; counts at the top (same 3, split 1).
    Select rows by a stable id (`#pair-row-<n>`) and the kind by its text.
  - Opened on the original (`/admin/plays/#{original.id}/compare?view=pairs`), the menu
    offers the French and opens on it.
  - `?view=pairs&translation=<not of the family>` and `translation=garbage`: the default
    translation, no error (Review Focus 1).
  - An original whose only derived play is an adaptation: "nothing to review" text
    (Review Focus 2).
  - Acts in the original, none in the translation: rows still in the original's order
    (Review Focus 5).
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: `review/2`** from `align/2`'s `speeches` and `unpaired`, with the speech
  elements by id from the loaded divisions; then the LiveView: `handle_params/3` reads
  `view` and `translation`, resolves the translation among the family's paired plays
  (`PlayComparison.build_family/1` gives the family), loads both texts only for the pairs
  view. Each row: number, the original speech's act/scene heading, `line_number` of its
  first line, speaker label, opening words (the full text in `title`), the kind, the
  translation speech likewise. A legend with each kind's meaning (the proof of concept's
  `@meanings`, in Spanish).
- [ ] **Step 4: Green; refactor; `mix test`; `mix format`; bites; gettext; commit**
  `feat: the admin comparison's pair review`.

### Task 3: Doubtful rows: the length warning, the filter, the Elenco link

**Files:**
- Modify: `lib/playcode/alignment.ex` (`long` in `review/2`), the LiveView
- Test: `test/playcode_web/live/admin/play_compare_live_test.exs`

- [ ] **Step 1: The failing tests:**
  - A same-speaker pair of very different length (one line against eight) is marked
    "doubtful" ("longitud muy distinta"); two short ones ("Yes." / "Oui, monseigneur.")
    are not (Review Focus 4).
  - "Sólo las filas dudosas": the plain same rows are hidden except one either side of a
    doubtful one (a split, an other, an added, a cut or a long row).
  - The French speaker links to `/admin/plays/#{french.id}/content#entry-<its first
    entry's id>`; a speech whose `sp` names no cast role prints its label, no link (Review
    Focus 3).
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3:** words through `Metrics.words/1` over the speech's lines and paragraphs
  (not its stage directions); `long` when the larger count is over 4× the smaller and the
  larger is over 20 words (a first guess; Task 4 tunes it). The filter as a `phx-click`
  toggle, rows hidden by class, no reload of the texts. The entry for the link: the
  character's first entry in `PlayContent.list_cast_lists/1`'s order.
- [ ] **Step 4: Green; refactor; `mix test`; `mix format`; bites; gettext; commit**
  `feat: the pair review marks the doubtful rows and links to the Elenco`.

### Task 4: Tune, document, check

- [ ] On dev: open 0084's review; rows 89 and 91 (the proof of concept's numbering) must be
  marked. Count the long rows across every translation on dev (a `mix run` script in the
  scratchpad, through `Alignment.review/2`); tune the two numbers in Task 3 if needed, and
  write the result in the spec's builder's calls. A tuning that changes Task 3's tests
  updates them, saying why.
- [ ] `docs/stakeholder/ida-y-vuelta.html` (note 40: the review), `docs/backlog.md`
  (step 5 built), the alignment spec's *Order of work* (step 5 built), `docs/architecture.md`
  (the compare route's `view` param).
- [ ] Browser check on dev: the two tabs on 0084's comparison, the filter, a link to the
  Elenco landing on the line.
- [ ] `mix test`, `node --test test/js/*.test.mjs`, `mix format`; commit
  `docs: the pair review`.
