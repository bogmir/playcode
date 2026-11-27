# Premarked text preview Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A page per play where a researcher pastes premarked text (or drops the .docx), sees the play as the Word import would store and print it with warnings tied to lines, and imports with one button.

**Architecture:** `WordParser` parses paragraphs into its in-memory acts structure, each node carrying the paragraph index it came from. A new `Playcode.Import.WordDraft` turns that into the `%Division{}`/`%Element{}`/`%Character{}` structs the import inserts (ids generated in memory), numbered with `Numbering.expected/3`. The import inserts exactly those structs; the preview prints them through `PlayText.play_body`. A LiveView at `/admin/plays/:id/premarked` drives it; one JS hook handles caret ↔ preview and `localStorage`.

**Tech Stack:** Elixir 1.19, Phoenix 1.8, LiveView 1.1, daisyUI/Tailwind 4, `node --test` for the hook's pure helpers.

**Spec:** `docs/superpowers/specs/2026-11-27-premarked-preview-design.md` (read it first). The screen: `tmp/mockups/premarcado-a-pantalla.html`, with these choices made: side by side on wide screens, one above the other below ~900 px; linked scrolling; a margin mark for a warning's line; text kept in `localStorage` per play; summary above the preview.

## Global Constraints

- TDD per CLAUDE.md: failing test, watch it fail, smallest pass, **refactor while green**, `mix test` whole suite before claiming done. A test written for code that already works must be proved to bite (`bin/bites FILE OLD NEW TEST_PATH`), said in the commit.
- Test through the outermost API: the parser through `WordParser`'s public functions, asserted on what the play then exports (`export_tei/1`, `xml_elements/3`, `docx/1` from `test/support/import_helpers.ex`) or reads back through `PlayContent` public functions; the page through `live/2`, `form/3`, `render_change/1`, `render_submit/1`, `file_input/3`.
- New files get no comments (`test/comment_ratchet_test.exs`); an existing file's comments only go down unless a why needs one, with the baseline raised in the same commit.
- UI text in Spanish through gettext (msgids in English, as the codebase does), informal "tú" as the admin uses; after `mix gettext.extract --merge` check every entry marked fuzzy. Glossary words from `CONTEXT.md` (aside = aparte, paratext, stage direction = acotación).
- An id or a line number from a LiveView event came from the browser: never index server data by it.
- `mix format` after every task. Branch `feature/premarked-preview` (exists, spec committed). No PR; commits without Claude attribution.
- Fixtures: `test/fixtures/word_files/ejercicio.docx`, `test/fixtures/word_files/bartholomew_fair.docx` (2,174 paragraphs).

## Review Focus

1. **Pasted text with Windows line endings (`\r\n`) or a trailing newline**: the preview and import read the same paragraphs as the .docx; `\r` never reaches stored text. Test in Task 1.
2. **A pasted text with no act heading and no scene** (only `{p}`/`{v}` lines): the parser's `ensure_act` path; the preview shows it and the comparison test holds. Test in Task 2.
3. **Re-importing over a play that already has text, hand-typed paratexts and notes**: the preview prints the kept paratexts, the import keeps them, the old text's notes are gone. Test in Task 2.
4. **An empty or whitespace-only text box**: no preview, Import disabled, no crash. Test in Task 7.
5. **A complete play reached by URL**: sent back to the play's page with a flash, nothing importable. Test in Task 7.

---

### Task 1: Paragraphs from a .docx or from text, one import over them

**Files:**
- Modify: `lib/playcode/import/word_parser.ex` (`extract_paragraphs/1` → public `paragraphs/1`; new `paragraphs_from_text/1`; `import_content/2` takes a path or a list)
- Test: `test/playcode/import/word_parser_test.exs`

**Interfaces:**
- Produces: `WordParser.paragraphs(path :: String.t()) :: {:ok, [String.t()]} | {:error, term}`; `WordParser.paragraphs_from_text(text :: String.t()) :: [String.t()]` (split on `\r\n` or `\n`, blank lines kept as `""` so index = text-box line, 0-based); `WordParser.import_content(play_id, path_or_paragraphs)` → `{:ok, play} | {:error, reason}` (a binary is a path, a list is paragraphs).

- [ ] **Step 1: Failing tests** in a new `describe "pasted text"`:
  - `"imports as the .docx it was copied from"`: `{:ok, ps} = WordParser.paragraphs("test/fixtures/word_files/ejercicio.docx")`; import `Enum.join(ps, "\n") |> WordParser.paragraphs_from_text()` into play A and the .docx into play B; `export_tei` of both equal after replacing each play's code/id-bearing parts (compare `speeches/1` and `xml_elements(xml, "l")` texts, which carry no code).
  - `"reads Windows line endings and skips blank lines"`: `WordParser.paragraphs_from_text("{e}Escena 1\r\n\r\n{p}FEBO {v}Uno.\r\n")` returns `["{e}Escena 1", "", "{p}FEBO {v}Uno.", ""]`; importing it gives one speech whose text has no `\r`.
- [ ] **Step 2:** `mix test test/playcode/import/word_parser_test.exs` — FAIL, undefined functions.
- [ ] **Step 3:** Implement. `parse_content/1` must already skip `""` (it does: an empty paragraph parses to `[]`, which is untagged-empty and skipped); keep it so.
- [ ] **Step 4:** Tests pass. Refactor while green. `mix test`.
- [ ] **Step 5:** Commit "The Word import reads pasted text as well as a .docx".

### Task 2: The draft: the rows the import inserts, built in memory

**Files:**
- Create: `lib/playcode/import/word_draft.ex`
- Modify: `lib/playcode/import/word_parser.ex` (each parsed node gets `:line`, the paragraph index; `import_content/2` inserts the draft's structs; `create_elements`/`create_children`/`create_verse`/`create_stanza`/`create_characters` move into or are replaced by inserting the draft)
- Modify: `lib/playcode/play_content.ex` only if inserting a struct with a preset id needs a function there (see Step 3)
- Test: `test/playcode/import/word_draft_test.exs` (new)

**Interfaces:**
- Consumes: Task 1's `paragraphs/1`, `paragraphs_from_text/1`.
- Produces: `WordParser.draft(paragraphs :: [String.t()], play :: %Play{paratexts: [%Paratext{}]}) :: {:ok, draft} | {:error, reason}` where `draft :: %{divisions: [%Division{}], paratexts: [%Paratext{}], lines: %{Ecto.UUID.t() => non_neg_integer}, warnings: [warning], summary: summary}`.
  - `divisions`: top-level, in the shape `PlayContent.load_play_content/2` returns (cast list `"elenco"` with `entries: [%{character: %Character{}}]`, acts with `children` scenes, each division with `loaded_elements`, elements with `children`, `notes: []`, `element_characters`), positions as `import_content` gives them today (front matter paratext 0, cast list 1, acts from 2), numbered by the play's `numbering_type`/`numbering_restart` through `Numbering.expected/3`.
  - `paratexts`: `play.paratexts` not of origin `"word"`, plus the new `"word"` front matter when there is one.
  - `lines`: every element's and division's id → the paragraph index it came from.
  - `warnings`: `[]` in this task (Task 3 fills it); `summary :: %{acts: n, scenes: n, verses: n, speakers: [{label, speeches}]}`, speakers by speeches descending, then label.
- `import_content/2` = `draft/2` then, in today's transaction and with today's deletes, insert every struct of the draft with its id, then `numbering_manual: false` and `refresh_derived/1`.

- [ ] **Step 1: Failing test, the one that keeps the design honest** — `describe "the draft is what the import stores"`, for each of: `ejercicio.docx`, `bartholomew_fair.docx` (tag `@tag :slow` only if it takes over ~2 s), and `docx(["{p}FEBO {v}Uno.", "{p}RICARDO {v}Dos."])` (no act, no scene: Review Focus 2), and a `"PROLOGUE"` + `{m}` stanza text:
  ```elixir
  play = play_fixture() |> then(&Catalogue.get_play_with_all!(&1.id))
  {:ok, ps} = WordParser.paragraphs(path)
  {:ok, draft} = WordParser.draft(ps, play)
  {:ok, _} = WordParser.import_content(play.id, ps)
  assert tree(draft.divisions) == tree(PlayContent.load_play_content(play.id))
  assert outline(draft) == outline_stored(play.id)
  ```
  `tree/1` (test-private) walks divisions → children → `loaded_elements` → children and keeps `{id, type, title_or_content, number_or_line_number, part, speaker_label, is_aside, aside_continues}` in order; `outline/1` maps `Outline.items(paratexts, divisions)` to `{struct_module, id_or_kind, heading_or_title}` (paratext ids differ: the stored one is new; compare kind and heading for paratexts, id for divisions).
- [ ] **Step 2: Failing test, Review Focus 3** — `"a re-import keeps the hand-typed paratexts and the preview prints them"`: a play with a manual paratext (`Catalogue.create_paratext(%{..., origin: "manual"})`) and an earlier Word import; `draft.paratexts` holds the manual one and the new front matter, not the old `"word"` one; after import `Catalogue.get_play_with_all!` paratexts match.
- [ ] **Step 3: Failing test** — `"the summary counts acts, scenes, verses and each speaker's speeches"`: over `ejercicio.docx`, `summary.acts == 1`, `summary.scenes == 1`, `summary.verses` equals the number of `l` elements in the export after import, and `summary.speakers` starts with `{"RICARDO", _}`.
- [ ] **Step 4:** Run, FAIL.
- [ ] **Step 5: Implement.** `WordDraft.build(parsed, play)` builds structs with `Ecto.UUID.generate/0` ids; numbering: flatten the structs into the rows `Numbering.expected/3` reads (`id, type, part, line_number, content, act_id, scene_id, speech_id`, in reading order, as `PlayContent.reading_order/1` builds them from the database) and write each returned row's `line_number`/`content` back by id. Inserting: each row goes through the same changeset as today (`Element.changeset`, `Division.changeset`, the character's) on a struct whose `id` is preset (`%Element{id: id} |> Element.changeset(attrs) |> Repo.insert()` keeps the id), inside `PlayContent`'s `refresh: false` path, with the speech's characters as `create_element/2` links them today. Whether that is a new `PlayContent.insert_draft/…` or the existing create functions gaining an `:id` is your call; the changesets must run. `Asides.guess/1` runs on the parsed maps before structs are built, as today.
- [ ] **Step 6:** Tests pass; the existing `word_parser_test.exs` and `play_detail_live_test.exs` still pass unchanged. Refactor while green: `import_content/2` should read as "draft, then insert it". `mix test`.
- [ ] **Step 7:** Measure: `WordParser.draft/2` on Bartholomew Fair, median of three (a scratch `mix run` script, not committed). Record the numbers for Task 9. If over 300 ms, stop and report before going on.
- [ ] **Step 8:** Commit "The Word import builds its rows in memory first, the draft a preview prints".

### Task 3: Warnings, each tied to its paragraph

**Files:**
- Modify: `lib/playcode/import/word_parser.ex` (warnings collected in the parsing pass), `lib/playcode/import/word_draft.ex` (`:speaker_as_words` over the built rows)
- Test: `test/playcode/import/word_draft_test.exs`

**Interfaces:**
- Produces: `warning :: %{line: non_neg_integer, kind: kind, text: String.t()}`, `text` the paragraph's (or piece's) text as typed, trimmed; `kind` one of `:untagged | :unknown_tag | :dropped_text | :part_without_initial | :initial_unfinished | :speaker_as_words | :end_marker | :unclosed_aside` (Task 4 adds `:refused`). Sorted by `line`.

Rules (the spec's table): `:untagged` = a paragraph stored `"unrecognized"` that is not an end marker; `:unknown_tag` = `~r/\{[A-Za-z]{1,3}\}/` that is not one of the eleven tags, case-insensitive; `:dropped_text` = a `:text` segment before a paragraph's first tag; `:part_without_initial` = `{tm}`/`{tf}` with no open `{ti}`; `:initial_unfinished` = a `{ti}` still open when a `{v}`, another `{ti}`, a scene or the end comes, reported on the `{ti}`'s line; `:speaker_as_words` = a prose or verse piece whose trimmed text, upcased, equals an upcased speaker label of the draft; `:end_marker` = `{e}THE END…`; `:unclosed_aside` = `((` without a later `))` in the same paragraph.

- [ ] **Step 1: Failing tests**, one per kind, each with a minimal paragraph list and `assert [%{line: n, kind: k}] = draft.warnings` (or the exact list), using the mockup's sample errors: `"{p}RICRDO {v}…"` is not a warning (it is the summary's job) but `"{R}Vase."` is `:unknown_tag` at its line; `"{pr} FEBO {pr}¡Qué pronto!"` with a FEBO speech elsewhere is `:speaker_as_words`; `"{p}RICARDO {tf}¿No lo ves?"` with no `{ti}` before is `:part_without_initial`; a last `"{ti} pues ¿qué te aflige?"` is `:initial_unfinished`; `"{e}THE END"` is `:end_marker`; `"Nota {p}FEBO {v}Uno."` is `:dropped_text`; `"{p}FEBO {pr}Hola ((aparte sin cerrar"` is `:unclosed_aside`.
- [ ] **Step 2: Failing tests over the real files** — `"a text with no warnings"`: the exercise's tagged part only (`ejercicio.docx` paragraphs up to, not including, `"OBSERVACIONES:"`) has `warnings == []`; `"the exercise's notes are untagged lines"`: the whole file has exactly the 5 `:untagged` warnings at the OBSERVACIONES lines; `"Bartholomew Fair"`: counts by kind — the brief says 30 names tagged as prose, 32 untagged paragraphs, one `{R}`. Assert `%{speaker_as_words: 30, untagged: 32, unknown_tag: 1}` ⊆ the frequencies. If the file gives other numbers, read which paragraphs differ before changing the test or the code, and say in the commit which it was (the brief's 32 may count front matter, which is not a warning).
- [ ] **Step 3:** FAIL. **Step 4:** Implement: thread a warnings accumulator through the reduce in `parse_content/1` (the state map already travels); `:speaker_as_words` in `WordDraft` after labels are known. **Step 5:** Pass, refactor while green, `mix test`.
- [ ] **Step 6:** Commit "The draft names what the import would get wrong, line by line".

### Task 4: A row the database would refuse is an error

**Files:**
- Modify: `lib/playcode/import/word_draft.ex`
- Test: `test/playcode/import/word_draft_test.exs`

**Interfaces:**
- Produces: `draft.errors :: [%{line, kind: :refused, text}]` (a separate list from `warnings`); `import_content/2` returns `{:error, {:refused, errors}}` without writing when `errors != []`.

- [ ] **Step 1: Failing test** `"a line with malformed markup is an error, and the import refuses the text"`: paragraphs `["{e}Escena 1", "{p}FEBO {v}Uno <<sin cerrar."]`; `draft.errors` is `[%{line: 1, kind: :refused}]`; `import_content` returns `{:error, {:refused, [_]}}` and `PlayContent.load_play_content(play.id)` is still the play's previous content (import something valid first).
- [ ] **Step 2:** FAIL (today the whole transaction rolls back with an opaque reason, or the row is accepted: read which). **Step 3:** Implement: `WordDraft` runs `Element.changeset(%Element{}, attrs).valid?` (pure) for each element as it builds it. **Step 4:** Pass, refactor, `mix test`. **Step 5:** Commit "A line the database would refuse stops the Word import before it writes".

### Task 5: `((…))` is an aside inside the line; `{ap}` before it is its delivery

**Files:**
- Modify: `lib/playcode/import/word_parser.ex` (`build_children/1` and the segment reading)
- Modify: `docs/tei-mapping.md` (the Word side of asides), `docs/stakeholder/ida-y-vuelta.html` (the aside row: Word import now reads a partial aside)
- Test: `test/playcode/import/word_parser_test.exs`

- [ ] **Step 1: Pin today first** — test `"((…)) is left as typed and {ap}'s text is dropped"` asserting today's export: the `p` text contains `((En realidad` and no `seg`; `"(Aparte)"` absent. Run: PASS (it describes today). Commit it alone: "Pin what the Word import does with ((…)) today".
- [ ] **Step 2: Change it to the decided behaviour** (update that test, with a one-line comment saying why it changed, as CLAUDE.md asks):
  - `"((…)) marks the words spoken aside, the rest stays ordinary speech"`: `["{e}Escena 1", "{p}RICARDO {pr}Muy bien. ((En realidad prefiero el verso. –)) Y entonces, ¿qué?"]` → export has one `p` with exactly one `seg[@type="aside"]` whose text is `"En realidad prefiero el verso. –"`, the `p` not wholly aside, no `((` or `))` in the text.
  - `"{ap} before ((…)) is the aside's delivery"`: `"{p}RICARDO {ap}(Aparte) {pr}Muy bien. ((En realidad…)) Y entonces."` → `stage` `"(Aparte)"` right before the `seg` (`xml_elements(xml, "stage")` holds it), the `p` not wholly aside.
  - `"{ap} with no ((…)) is still a whole aside"`: today's `"{ap} marks that paragraph's verse or prose as an aside"` stays green unchanged.
  - Works in a verse too: `"{p}DUQUE {v}Bien está ((y mal)) señor"` → `l` with one `seg`.
- [ ] **Step 3:** FAIL. **Step 4:** Implement: in a `{pr}`/verse piece, replace `((…))` with `InlineMarkup.aside_marker/0`'s open/close; when the paragraph has `{ap}` and a `((`, the `{ap}` text becomes a stage marker (`InlineMarkup.stage_marker(nil)`) placed right before the first aside marker and `is_aside` stays false. `Element.changeset`'s `asides_well_formed?` must accept it; read `docs/tei-mapping.md` line 50 for the stored shape. **Step 5:** Pass; the Task 2 comparison still passes; refactor; `mix test`.
- [ ] **Step 6:** Docs: `docs/tei-mapping.md` gains, beside the aside line, the Word reading; `ida-y-vuelta.html`'s aside row. Commit "The Word import reads ((…)) as the aside it marks".

### Task 6: `PlayText` can mark lines

**Files:**
- Modify: `lib/playcode_web/components/play_text.ex` (`play_body/1`, `element_list/1`, `render_element/1` clauses: one attr `lines`)
- Test: in Task 7's LiveView test (the play page's own tests prove nothing changed there)

**Interfaces:**
- Produces: `attr :lines, :map, default: %{}` on `play_body/1`, `%{element_id => %{line: non_neg_integer, warn: boolean}}`; each rendered element (and division heading) whose id is in it gets `data-line={line}` and, when `warn`, `data-warn`; absent ids render exactly as today.

- [ ] **Step 1:** Implement the attr threaded through every clause (`render_element` clauses pass it to children). **Step 2:** `mix test` — the play page, static-site and accessibility tests pass unchanged (that is the "nothing changed" proof). **Step 3:** Commit with Task 7 if smaller to review together; otherwise "The play text can carry each element's source line".

### Task 7: The page

**Files:**
- Create: `lib/playcode_web/live/admin/play_premarked_live.ex`
- Modify: `lib/playcode_web/router.ex` (`live "/plays/:id/premarked", PlayPremarkedLive, :index`, beside `/plays/:id/places` in the same scope)
- Modify: `lib/playcode_web/live/admin/play_detail_live.ex` (the card becomes a link; remove `allow_upload(:docx)`, `import_docx`, `validate_upload`, `error_to_string` if unused)
- Modify: `test/playcode_web/authorization_test.exs` (`{"/admin/plays/:id/premarked", :active}`), `test/playcode_web/accessibility_test.exs` (`/admin/plays/:id/premarked` in `@pages`, with text pasted so the preview renders: follow how the file fills other pages)
- Modify: `test/playcode_web/live/admin/play_detail_live_test.exs` (the upload tests move to the new test file; the card test becomes "links to the premarked page")
- Create: `test/playcode_web/live/admin/play_premarked_live_test.exs`
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po`

**Interfaces:**
- Consumes: `WordParser.paragraphs/1`, `paragraphs_from_text/1`, `draft/2`, `import_content/2`; `PlayText.play_body/1` with `lines`; `SplitVerses.leads/1` over the draft's verse lines (`Element.verse_lines/1`), as `PlayShowLive` does.
- Produces: DOM the hook (Task 8) relies on: `<form id="premarked-form" phx-change="preview" phx-submit="import">`, `<textarea id="premarked-text" name="text" phx-debounce="400" phx-hook="PremarkedText" data-play={@play.id}>`, the preview `<div id="premarked-preview" tabindex="0" role="region" aria-label=…>`, warnings as `<button type="button" data-line={w.line}>` in `<ul id="premarked-warnings">`.

Page content (Spanish via gettext), as the mockup: breadcrumb to the play; heading; left card: label + textarea, `.drop_zone` upload (`allow_upload(:docx, accept: ~w(.docx), max_entries: 1, max_file_size: 10_000_000, auto_upload: true, progress: …)` — on completion `WordParser.paragraphs/1` fills `@text` and the textarea), folded `<details>` legend of the eleven tags plus `((…))` and `<<…>>`; right card: summary (acts, scenes, verses, speakers as chips with counts, a one-speech speaker marked), errors then warnings list, the preview; import bar: button "Importar y sustituir el texto" disabled when the text is blank or `errors != []`, with the replaces/keeps sentence (replaces the text, characters and notes; keeps the play's data, editors, sources, bibliography, witnesses, places, performances and paratexts typed by hand; warnings do not block). Layout: `grid lg:grid-cols-2` (side by side from ~900 px up, one above the other below). Text cap: over 5,000,000 bytes the preview shows a "too long" message instead of parsing.

- [ ] **Step 1: Failing tests** (`ConnCase`, a researcher logged in, `t/2` for Spanish):
  - `"pasting text shows the play as it would be stored, and stores nothing"`: `live` the page, `render_change(form(lv, "#premarked-form", text: ejercicio_text))`; preview region has `"Será remedio casarte."` and a speaker `"FEBO"`; summary shows `"RICARDO"`; `PlayContent.load_play_content(play.id)` unchanged.
  - `"a clean text shows no warnings; one with every kind shows each, tied to its line"`: the mockup's error sample; `has_element?(lv, "#premarked-warnings button[data-line='N']")` for each kind's line; the preview has `[data-warn][data-line='N']`.
  - `"dropping the .docx fills the text box"`: `file_input` + `render_upload` with `ejercicio.docx`; textarea contains `"{e}Escena 1"`.
  - `"import replaces the text and returns to the play"`: `render_submit`; redirected to `/admin/plays/:id` with flash `t("Content imported successfully.")`; `/plays/:code` shows `"Entran Febo y Ricardo."`.
  - `"a refused line disables the import"`: text with `<<sin cerrar`; button `disabled`; error listed.
  - `"an empty text shows no preview and cannot be imported"` (Review Focus 4).
  - `"a complete play is sent back to its page"` (Review Focus 5): `{:error, {:live_redirect, %{to: "/admin/plays/#{id}"}}}` (or `:redirect`, whichever the codebase uses for such gates) with a flash.
  - `"a submitted text is read again on the server"`: `render_submit` with a text different from the last change event imports the submitted text (the server never trusts a cached draft).
  - play detail: `"the play's page links to the premarked page while the play is a draft"`; no link on a complete play.
- [ ] **Step 2:** FAIL. **Step 3:** Implement. **Step 4:** Pass. Add the authorization row and accessibility path; run both files, PASS. **Step 5:** `mix gettext.extract --merge`; write the Spanish; check every fuzzy entry. Refactor while green; `mix test`.
- [ ] **Step 6:** Commit "A play's premarked text: paste it, see the play, then import".

### Task 8: The hook: linked scrolling, warnings, `localStorage`

**Files:**
- Create: `assets/js/premarked.mjs` (pure helpers), `test/js/premarked.test.mjs`
- Modify: `assets/js/app.js` (the `PremarkedText` hook, registered in `hooks:`)

**Interfaces:**
- Produces: `lineAt(text: string, offset: number) => number` (0-based line of a caret offset); `rangeOf(text: string, line: number) => [start, end]` (the line's offsets, end excluding its newline; a line past the end → the last line); `nearestMarked(lines: number[], line: number) => number | null` (the greatest marked line ≤ `line`, else the smallest, else null).

Behaviour: on mount, if the textarea is empty and `localStorage["playcode.premarked." + play]` holds text, put it in and dispatch an `input` event so LiveView previews it; on every input, store it (try/catch; failure leaves the page working); caret move (`click`, `keyup`) → scroll `#premarked-preview` to the element `[data-line=nearestMarked(...)]` and give it a brief highlight class; click on a `[data-line]` in the preview → select that line in the textarea (`setSelectionRange(...rangeOf)`, scroll the textarea to it, focus); click on a warning button → both. After a successful import the server `push_event("premarked:clear", %{})` and the hook removes the key. The preview's DOM is re-rendered by LiveView: the hook reads `[data-line]` at the time of each event, never caches nodes.

- [ ] **Step 1: Failing `node --test` tests**: `lineAt("a\nbb\nc", 0) === 0`, `lineAt("a\nbb\nc", 3) === 1`, `lineAt("a\r\nb", 3) === 1`; `rangeOf("a\nbb\nc", 1)` deep-equals `[2, 4]`; `rangeOf("a\nbb", 9)` deep-equals `[2, 4]`; `nearestMarked([2, 5, 9], 6) === 5`, `nearestMarked([2, 5], 0) === 2`, `nearestMarked([], 3) === null`.
- [ ] **Step 2:** `node --test test/js/*.test.mjs` FAIL. **Step 3:** Implement helpers and hook. **Step 4:** PASS. Add a LiveView test that the import pushes `premarked:clear` (`assert_push_event(lv, "premarked:clear", _)`). **Step 5:** Check by hand in the browser (dev server): paste, caret moves preview, warning click selects line, reload keeps text, import clears it. Refactor; `mix test`; `node --test test/js/*.test.mjs`.
- [ ] **Step 6:** Commit "The premarked page links the text and the preview, and keeps the text through a reload".

### Task 9: Measure, document, finish

**Files:**
- Modify: `docs/architecture.md` (the route and the draft design: one builder, the import inserts the preview's rows), `docs/history.md` (the item), `docs/backlog.md` (follow-ups: the fixed-position collision between the Word import's rows and kept paratexts; anything else found and left), `docs/development.md` only if it describes the Word import
- Verify only: screenshots

- [ ] **Step 1:** Measure the page's full round trip on Bartholomew Fair: a scratch script timing `paragraphs_from_text` + `draft/2` + rendering the LiveView once (`render_change` in a test-shaped script, or `:timer.tc` around `Phoenix.LiveViewTest.rendered_to_string` of the preview component), median of three. Over ~300 ms: report with the timings and a proposed fix before building it.
- [ ] **Step 2:** Docs as listed. Remove the play detail upload's mention from any doc that describes it.
- [ ] **Step 3:** `mix precommit` and `node --test test/js/*.test.mjs`: both pass, output shown.
- [ ] **Step 4:** Screenshots (dev server, headless Chrome or the browser extension): the page with the exercise pasted, and with Bartholomew Fair. Save to the scratchpad, show to the owner.
- [ ] **Step 5:** Commit "Docs: the premarked page". Do not merge or push until the owner says so.
