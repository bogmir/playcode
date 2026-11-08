# A Numbering Rule per Play Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every play carries a numbering rule (type, restart, Manual), written to and read from its TEI header; Playcode recounts the numbers of a play that is not Manual on every save, and the import detects the rule a file follows.

**Architecture:** Three columns on `plays`. One module, `Playcode.PlayContent.Numbering`, counts a play's verse lines and paragraphs (read in reading order by `PlayContent.reading_order/1`) by a rule, diffs against what is stored, detects the closest rule, and writes changed rows in one `UPDATE`. `refresh_derived/1`, the TEI and Word imports and the play form call it; the exporter writes the rule as `refsDecl`/`citeStructure`, and the static site reads the rule instead of guessing restarts.

**Tech Stack:** Elixir, Ecto/Postgres, Saxy, xml_builder, Phoenix LiveView, the static site's `site.js`.

**Spec:** `docs/superpowers/specs/2026-11-08-numbering-setting-design.md`

## Global Constraints

- Branch `fix/numbering-setting` from `main` (exists). Commit the spec and this plan as the branch's first commit.
- No `Co-Authored-By` or any Claude attribution in commits. Never open or offer a PR; merge and push only when the owner says (a push deploys to Fly).
- TDD: failing test, watch it fail, implement, pass, refactor while green, then the full `mix test`. Prove each new test bites with `bin/bites FILE OLD NEW TEST_PATH`, and say so in the commit message.
- Run mix plainly (`mix test`, `mix format`), never with an `export PATH=…` prefix.
- Values, exactly: types `V VP VL S`; restarts `never act scene`; defaults `V`, `never`, Manual `false`; existing rows Manual `true`.
- Labels, exactly: V verse `v.`; VP/VL verse `v.`, prose `l.`; S `int.` for both; passage ranges `vv.` except S `int.`.
- Header units, exactly: V `verse`, VP `line`, VL `printed-line`, S `speech`; levels `act`, `scene`; Manual `<refsDecl n="manual">`.
- A Manual play's rows are never written by a recount.
- Only `<lb n="…"/>` markers are numbers; a bare line break (a newline in `content`, `<lb/>` in the file) never counts.
- An existing test that breaks because of a deliberate change here (an unnumbered snippet now numbered; typed numbers recounted) is updated with a comment saying why; a test that types numbers sets its play Manual.

## Review Focus

- A per-scene play's act text before its first scene, and a prologue (top-level division without scenes): each restarts at 1 under `scene`, and under `act` the prologue restarts (Task 2, test "prologue").
- An S speech whose first verse is an `F` piece gets the number; a speech that is only stage directions takes none and does not consume one (Task 2, test "S").
- A VL paragraph typed with `<lb n="0"/>` inside: recount numbers it and shifts the next verse (Task 2, test "VL").
- Re-importing a Playcode export of a Manual play whose numbers happen to fit a rule: stays Manual (Task 3, test "header manual").
- A play form save that changes only the title of a play that is not Manual: saves at once, no confirm, no rows written (Task 7, test "no numbers move").

---

### Task 1: the setting, and the TEI header

**Files:**
- Create: `priv/repo/migrations/20261108180000_add_numbering_to_plays.exs`
- Modify: `lib/playcode/catalogue/play.ex` (fields, `changeset/2` cast + `validate_inclusion`, moduledoc, `number_label/2`)
- Modify: `lib/playcode/export/tei_xml.ex` (`build_encoding_desc/1`, ~line 427: `refsDecl` after `classDecl`)
- Modify: `lib/playcode/import/tei_parser.ex` (`extract_encoding/1`, ~line 742; play attrs ~line 498)
- Modify: `lib/playcode/import/tei_import.ex` (`write_play`: take `numbering` attrs)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/complete_copy_test.exs`

**Interfaces:**
- Produces: `Play` fields `numbering_type :: String.t()`, `numbering_restart :: String.t()`, `numbering_manual :: boolean()`; `Play.numbering_types/0`, `Play.numbering_restarts/0`; `Play.number_label(%Play{}, :verse | :prose | :range) :: String.t()`.
- Produces: the parser's play attrs carry `numbering_type`, `numbering_restart`, `numbering_manual` only when the header has a recognised `refsDecl`, and `tei.play.numbering_from_header? :: boolean` (Task 3 reads it).

- [ ] **Step 1: Write the failing tests** in `tei_roundtrip_test.exs`, `describe "the numbering rule"`:

```elixir
for type <- ~w(V VP VL S), restart <- ~w(never act scene), manual <- [false, true] do
  test "#{type} #{restart} manual=#{manual} survives export and import" do
    play = import_tei!(tei(body: @one_scene))
    {:ok, play} = Catalogue.update_play(play, %{numbering_type: unquote(type),
      numbering_restart: unquote(restart), numbering_manual: unquote(manual)})
    again = play |> export_tei() |> import_tei!()
    assert {again.numbering_type, again.numbering_restart, again.numbering_manual} ==
             {unquote(type), unquote(restart), unquote(manual)}
  end
end

test "the header for V per scene is three citeStructures, verse innermost" do
  # update a play to V/scene, export, then:
  assert [{%{"unit" => "act"}, _}, {%{"unit" => "scene"}, _}, {%{"unit" => "verse"}, _}] =
           xml_elements(xml, "citeStructure")
  assert [{attrs, _}] = xml_elements(xml, "refsDecl")
  refute Map.has_key?(attrs, "n")
end

test "a refsDecl Playcode does not write is no setting" do
  # tei(encoding_desc: "<refsDecl><p>Cite by line.</p></refsDecl>", …) imports with
  # the defaults V / never / false
end
```

`@one_scene`: one `div1` with one `div2` and one speech of one verse numbered `"1"`, which fits all 12 rules, so Task 4's check of the header against the numbers never makes it Manual.

- [ ] **Step 2: Run, watch it fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs`
Expected: FAIL, `numbering_type` unknown field.

- [ ] **Step 3: Implement**
  - Migration: add the three columns `null: false` with defaults `"V"`, `"never"`, `true`, then `alter` `numbering_manual` default to `false` (existing rows Manual, new ones not; spec, *Plays already stored*). The `plays_bump` trigger compares whole rows, so the columns move `content_version` with no trigger change.
  - `Play`: schema defaults `"V"`, `"never"`, `false`; cast and validate inclusion; `number_label/2` per Global Constraints.
  - Export: one `refsDecl` per spec, *The TEI header* (absolute `match` on the outermost level, relative below; `use="position()"` for act and scene, `@n` for the number; `n="manual"` when Manual).
  - Parser: recognise exactly the 12 shapes by `unit`s (innermost unit → type, depth → restart) and `n="manual"`; anything else → no attrs, `numbering_from_header?: false`.

- [ ] **Step 4: Run, pass.** Also `mix test test/playcode/complete_copy_test.exs`: the columns join the comparison by themselves; set the rarer play (the one with the rare encodings) to `numbering_type: "S", numbering_restart: "act", numbering_manual: true` so non-defaults are compared.

- [ ] **Step 5: Schema check:** `mix test --include slow test/playcode/roundtrip_test.exs` validates exports against `tei_all.rng`; the `refsDecl` must pass. Expected: no new failure.

- [ ] **Step 6: Commit** `feat: a play's numbering rule, written to and read from its TEI header`

---

### Task 2: counting and the recount

**Files:**
- Create: `lib/playcode/play_content/numbering.ex`
- Modify: `lib/playcode/play_content.ex` (`reading_order/1` from the walker in `split_verses_out_of_order/1`, lines ~407-444, which is rebuilt on it; `refresh_derived/1` line 54)
- Test: `test/playcode/play_content/numbering_test.exs`

**Interfaces:**
- Consumes: Task 1's columns.
- Produces:
  - `PlayContent.reading_order(play_id) :: [row]`, verse lines and prose paragraphs only, in reading order (an act's own text, then its scenes', as `Metrics.items/1`), `row :: %{id, type, part, line_number, content, speech_id, act_id, scene_id}` (`speech_id` the nearest `speech` ancestor or nil; `act_id` the top-level division; `scene_id` the child division or nil).
  - `Numbering.expected(rows, type, restart) :: [row]`, each row with `line_number`/`content` as the rule gives them.
  - `Numbering.differences(rows, setting) :: [row]`, the expected rows that differ from stored (`setting` a map or `%Play{}` with the three keys).
  - `Numbering.recount(%Play{}) :: non_neg_integer()`, rows written; 0 and no query when Manual.
  - `Numbering.changes(%Play{}, setting) :: non_neg_integer()`, rows a recount under `setting` would write (Task 7).
  - `PlayContent.refresh_derived(play_id)` recounts before `update_form_and_verse_count/1`.

Counting (the algorithm the tests do not pin alone):

```
unit(row): never → :play; act → row.act_id; scene → {row.act_id, row.scene_id}
for each run of rows with the same unit, counter n starts at 0:
  verse, part in [nil, "", "I"]:  V/VP/VL → n+1 on line_number;  S → see below
  verse, part M/F:               line_number nil (S: see below)
  prose:  V → leading number removed;  VP → leading n+1;
          VL → leading n+1, then each inner <lb n> the next n, in order;
          S → see below
  S: the first verse or prose row of each speech_id (not nil) takes n+1
     (a verse on line_number, a paragraph as its leading marker); every other
     row of that speech none; rows with speech_id nil none.
non-VL types leave inner <lb n> markers untouched.
```

Leading number: `InlineMarkup.paragraph_number/1` and `number_marker/1`.

- [ ] **Step 1: Write the failing tests.** Each test imports a snippet (`import_tei!(tei(body: …))`), sets the rule with `Catalogue.update_play/2` (Manual `false`), calls `PlayContent.refresh_derived(play.id)`, and asserts on the export with `xml_lines/2` (`{attrs, text}`, inner `<lb n>` read as ` [n] `):
  - `"V never: a split verse takes one number, on its first piece; prose none"`: `l` n `["1","2",nil,"3"]` for whole, I, F, whole; a `<p n="9">` loses its `n`.
  - `"V per scene: each scene starts at 1"`: scene 1 `["1","2"]`, scene 2 `["1"]`.
  - `"prologue"`: a top-level `div1 type="prologo"` before act 1 with 2 verses, act 1 with scenes; under `act` act 1 starts at 1; under `scene` the prologue, act 1's own text and each scene start at 1; under `never` act 1 continues at 3.
  - `"VP never: a paragraph between verses takes the next number"`: verses 1-10, `p` n `"11"`, next verse `"12"`.
  - `"VL: a paragraph's printed lines take a number each, a typed <lb n=\"0\"/> included"`: paragraph `"Uno <lb n=\"0\"/>dos <lb n=\"7\"/>tres"` after verse 10 → `p` n `"11"`, text `"Uno [12] dos [13] tres"`; next verse `"14"`.
  - `"S: one number per speech, on its first line or paragraph"`: speech of 3 verses `["1",nil,nil]`; next speech in prose → `p` n `"2"`; a speech opening with an `F` piece takes `"3"`; a speech of only a stage direction takes none.
  - `"a Manual play is never recounted"`: numbers `["5","9"]` stay, `recount/1` returns 0.
  - `"a recount writes only the rows whose number changed"`: a V-never play already numbered 1-3 → `Numbering.recount(play) == 0`.

- [ ] **Step 2: Run, watch them fail**

Run: `mix test test/playcode/play_content/numbering_test.exs`
Expected: FAIL, `Numbering` undefined.

- [ ] **Step 3: Implement** `reading_order/1` (rebuild `split_verses_out_of_order/1` on it, filtering verse rows, chunked by `act_id`), `Numbering` per Interfaces, and the write: one `UPDATE play_elements AS e SET line_number = v.n, content = v.c FROM unnest($1::uuid[], $2::text[], $3::text[]) AS v(id, n, c) WHERE e.id = v.id` through `Repo.query!/2`, skipped when nothing differs.

- [ ] **Step 4: Run, pass;** then `mix test test/playcode/play_content_test.exs` (split verses still listed). Refactor while green.

- [ ] **Step 5: Measure** the worst case in dev on Hamlet (EMOTHE0010): set it not Manual, VL never, then time `Numbering.recount/1` after shifting its first verse (median of 3 runs, `:timer.tc`). Record the number in the commit message; above ~300 ms, stop and tell the owner.

- [ ] **Step 6: Full suite** `mix test 2>&1 | tail -10`. Editor tests that type numbers into a play that is not Manual now get them recounted: set that play Manual with a comment (Global Constraints).

- [ ] **Step 7: Commit** `feat: every save recounts the numbers of a play that is not Manual`

---

### Task 3: verse_count counts the structure

**Files:**
- Modify: `lib/playcode/catalogue.ex` (`update_form_and_verse_count/1`, lines 217-245: drop `not is_nil(e.line_number)` from the filter, update the comment)
- Test: `test/playcode/catalogue_test.exs`

- [ ] **Step 1: Failing test** `"verse_count counts every verse once, numbered or not"`: import an S-numbered snippet (one speech of three verses, one with a split I/F pair), set S Manual (no recount), `refresh_derived`; assert `Catalogue.get_play!(id).verse_count == 4`.
- [ ] **Step 2: Run, fail** (counts 1).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, pass; full suite.**
- [ ] **Step 5: Commit** `fix: a play's verse count counts its verses, not its numbers`

---

### Task 4: the import settles the rule

**Files:**
- Modify: `lib/playcode/play_content/numbering.ex` (`detect/1`, `settle/2`, `describe/1`)
- Modify: `lib/playcode/import/tei_import.ex` (`write/1` ~line 284; `preview/1` ~line 145)
- Modify: `lib/playcode/import/tei_corpus.ex` (`preview_lines/3` ~line 95: append the numbering line)
- Modify: `lib/playcode_web/live/admin/import_live.ex` (~line 305: print `p.numbering`)
- Test: `test/playcode/import/tei_import_test.exs`, `test/playcode/import/tei_preview_test.exs`

**Interfaces:**
- Consumes: Task 1's `numbering_from_header?`; Task 2's `reading_order/1`, `differences/2`, `recount/1`.
- Produces:
  - `Numbering.detect([row]) :: %{numbering_type, numbering_restart, numbering_manual, differ: non_neg_integer(), unnumbered: boolean()}`. No numbered row → V if verse first pieces > prose rows else S, `never`, Manual false, `unnumbered: true`. Else `Enum.min_by` over the 12 rules in order V, VP, VL, S × never, act, scene of `length(differences)`; `differ == 0` → Manual false, else true.
  - `Numbering.settle(%Play{}, from_header? :: boolean) :: {%Play{}, report}`: header → keep the play's setting, and if not Manual and `differences != []` set Manual and report it; no header → `detect/1` and store; then `recount/1` (numbers only unnumbered or fitting plays: a mismatch is Manual by then). `report :: %{numbering_type, numbering_restart, numbering_manual, differ, unnumbered, header_broken: boolean}`.
  - `Numbering.describe(report) :: String.t()`, exactly: `"V per scene"`, `"V never"`, `"V never, Manual: 3 numbers differ"`, `"S never, numbered at import"`, `"VP per act, Manual: the header's rule breaks on 2 numbers"`. (`act` reads `per act`, `scene` `per scene`.)
  - `preview_import/1`'s map gains `numbering :: String.t()`, computed by `write/1` inside a transaction it rolls back.

- [ ] **Step 1: Failing tests** in `tei_import_test.exs`, `describe "the numbering rule a file follows"`, asserting on the stored play and the export:
  - fits V per scene exactly → `{"V","scene",false}`, numbers unchanged;
  - a stray number at the end (`…"9","10","3170"`) → `{"V","never",true}`, `"3170"` kept;
  - unnumbered, 3 verses and 1 paragraph → V, numbered `["1","2","3"]`;
  - unnumbered, 1 verse and 3 paragraphs → S, never, each speech's first line or paragraph numbered;
  - a header saying V never, Manual off, with numbers `["1","3"]` → Manual on, numbers kept;
  - Review Focus: a header with `n="manual"` and numbers that fit V → still Manual.

  In `tei_preview_test.exs`: `preview_import/1` on the stray-number file gives `numbering: "V never, Manual: 1 number differs"`, and the database is unchanged afterwards (`Catalogue.get_play_by_code` is nil for a new code).

- [ ] **Step 2: Run, fail.**
- [ ] **Step 3: Implement;** `write/1` calls `settle/2` after `sync_characters` and before `update_form_and_verse_count`; `@platform_owned` does not change. Plural: `"1 number differs"` / `"3 numbers differ"`.
- [ ] **Step 4: Run, pass.**
- [ ] **Step 5: Full suite.** Tests importing unnumbered snippets now see numbers: update each with a comment ("an unnumbered file is numbered at import, numbering spec"); where the numbers are beside the point, give the snippet's play a `refsDecl n="manual"` through `tei(encoding_desc: …)` instead. List the files touched in the commit message.
- [ ] **Step 6: Commit** `feat: the import takes a file's numbering rule from its header or detects it`

---

### Task 5: settling the plays already stored

**Files:**
- Modify: `lib/playcode/release.ex` (`settle_numbering/1`)
- Test: `test/playcode/release_test.exs`

**Interfaces:**
- Consumes: Task 4's `detect/1`, `settle/2`, `describe/1`.
- Produces: `Playcode.Release.settle_numbering(opts \\ []) :: %{String.t() => non_neg_integer()}`, the count per described rule (`"V never" => 220`, Manual ones under `"Manual"`); prints `"  EMOTHE0005  V never, Manual: 1 number differs"` per play, archived ones included; `dry_run: true` writes nothing.

- [ ] **Step 1: Failing test:** two plays imported from snippets whose header is a Manual V-never `refsDecl` (so the import neither detects nor numbers them, as the migration leaves existing rows): one numbered 1-3, one unnumbered; `settle_numbering(dry_run: true)` leaves both Manual; `settle_numbering()` sets the first to V never not Manual, numbers the second; output captured with `ExUnit.CaptureIO` names both codes.
- [ ] **Step 2: Run, fail. Step 3: Implement** (the dry run inside a rolled-back transaction, as `preview_import/1`). **Step 4: Run, pass; full suite.**
- [ ] **Step 5: Corpus check in dev.** `mix run -e 'IO.inspect(Playcode.Release.settle_numbering(dry_run: true))'` on the dev database. Compare with the handoff's table: 220 V, 8 V per scene, VL 11/1/17, VP 11/5, S 10/2/10, P 4 (now VP), 45 none, 41 unnumbered (38 S + 3 V: 0151, 0416, 0444). Explain each difference in the commit message (expected: the prologue files 0103, 0354, 0369, 0554, 0672, 0695 Manual). A difference you cannot explain: stop and tell the owner. Then run it for real in dev.
- [ ] **Step 6: Commit** `feat: settle the numbering rule of the plays already stored`

---

### Task 6: the Word import numbers by the rule

**Files:**
- Modify: `lib/playcode/import/word_parser.ex` (drop the counter, lines ~650, 879-890; line ~705 calls `PlayContent.refresh_derived/1` instead of `update_form_and_verse_count/1`)
- Test: `test/playcode/import/word_parser_test.exs`

- [ ] **Step 1:** Find the existing test that asserts a Word import numbers its verses; add one: a Word import into a play set to S never numbers each speech's first line (`docx/1`, `export_tei`, `xml_elements("l")`).
- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass** (the existing V test still passes: a new play is V never). Full suite.
- [ ] **Step 5: Commit** `refactor: the Word import leaves numbering to the recount`

---

### Task 7: the play form and the content editor

**Files:**
- Modify: `lib/playcode_web/live/admin/play_form_live.ex` (three fields beside `is_complete`/`show_variants` ~line 709; `save_play(:edit, …)` ~line 305)
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex` (`reorder_children` calls `refresh_derived`; the `line_number` input ~line 3512 only when `@play.numbering_manual`, otherwise the number read-only; `"v. %{number}"` ~line 1422 and `L{…}` ~line 2814 use `Play.number_label(@play, :verse)`)
- Modify: `test/playcode_web/accessibility_test.exs` only if a new control needs a path
- Modify: `priv/gettext/` (`mix gettext.extract --merge`, check every fuzzy entry; Spanish: "Numeración", "Elementos numerados", "Reinicio", "Conteo manual", "%{count} números cambiarán. Guarda de nuevo para confirmar.")
- Test: `test/playcode_web/live/admin/play_form_live_test.exs`, `test/playcode_web/live/admin/play_content_editor_live_test.exs`

**Interfaces:**
- Consumes: `Numbering.changes/2`, `Numbering.recount/1` (Task 2).
- Produces: the edit form posts `play[numbering_type]`, `play[numbering_restart]`, `play[numbering_manual]`, and `confirm_numbering` (the count) on the second submit.

Save flow: `count = Numbering.changes(play, new_setting)` when the setting changed and the new one is not Manual; `count > 0` and `params["confirm_numbering"] != to_string(count)` → re-render with the message and a hidden `confirm_numbering`; otherwise save, then `PlayContent.refresh_derived(play.id)`.

- [ ] **Step 1: Failing tests** (selectors by label text, `t/2`):
  - form: `"switching Manual off says how many numbers will change, and saves on the second submit"`: a Manual play numbered `["5","9"]`; submit Manual off → page shows `t("%{count} numbers will change. Save again to confirm.", count: 2)` and the play is still Manual; submit again → not Manual, numbers `["1","2"]`.
  - form, Review Focus: `"a save that moves no number saves at once"`: not Manual, numbered 1-2, title changed → saved, redirected.
  - editor: `"a verse inserted in scene 2 of a V-per-scene play moves the later numbers of scene 2 only"` (through `#element-form`, `new_element_before`), asserting `numbers(play)`.
  - editor: `"reordering scenes recounts a continuous play"`.
  - editor: `"the number field shows only on a Manual play"`.
- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass;** `mix test test/playcode_web/accessibility_test.exs`; full suite.
- [ ] **Step 5: Commit** `feat: the play form sets the numbering rule, and the editor numbers by it`

---

### Task 8: the static site reads the rule

**Files:**
- Modify: `lib/playcode/export/static_site/edition.ex` (`restarts?/1` ~line 504 goes; `anchors` ~line 428 uses `play.numbering_restart != "never"`; `refs/1` ~line 537 adds the scene only for `"scene"`)
- Modify: `lib/playcode/export/static_site/components.ex` (the `[data-cite]` element gains `data-cite-verse` / `data-cite-prose` from `Play.number_label/2`; `verses_range/1` ~line 1075 uses `Play.number_label(play, :range)`)
- Modify: `priv/static_site/site.js` (~line 230: `number.closest('p.pr') ? text.dataset.citeProse : text.dataset.citeVerse` instead of `'v.'`)
- Modify: `docs/static-site.md` (the cite label)
- Test: `test/playcode/export/static_site_play_test.exs`, `test/playcode/export/static_site_search_test.exs`

- [ ] **Step 1: Failing tests:** an S play's text block has `data-cite-verse="int."` and `data-cite-prose="int."`; a VP play's `"v."` and `"l."`; a per-act play (numbers restarting per act, setting `act`) gets search references `"II, 12"` without a scene, a per-scene one `"II.3, 12"`; a play numbered continuously whose numbers repeat across scenes (Timon's case) but set `never` keeps continuous anchors.
- [ ] **Step 2: Run, fail. Step 3: Implement. Step 4: Run, pass;** `node --test test/js/*.test.mjs`; the size budgets in `static_site_test.exs`; full suite.
- [ ] **Step 5: Commit** `feat: the static site cites and anchors by the play's numbering rule`

---

### Task 9: records

**Files:**
- Modify: `CONTEXT.md` (**Numbering rule** beside *Number* and *Anchor*)
- Modify: `docs/tei-mapping.md` (`refsDecl`/`citeStructure`; prose leading and VL inner `<lb n>` recounted)
- Modify: `docs/schema.md` (the three columns, the migration's Manual backfill, the recount)
- Modify: `docs/stakeholder/ida-y-vuelta.html` (row "Regla de numeración": admin, TEI export, TEI import yes; site: cite label)
- Modify: `docs/stakeholder/preguntas.html` (a new question at the end: the label words "int." and "l."; tell the researcher 0151, 0416, 0444 got V)
- Modify: `docs/backlog.md` → `docs/history.md`; `docs/production-reimport.md` (run `Playcode.Release.settle_numbering(dry_run: true)` then for real on Fly, then Generate; never Deploy while blocked)
- Modify: `/tmp/playcode-numbering/00-README.md` (row 4: built, spec path); memory `numbering-grilling-state.md` (Q19–Q23, Q27–Q29 decided)

- [ ] **Step 1:** Write the records. **Step 2:** Republish the Questions and Round Trip artifacts (memory *Stakeholder artifacts account*; wrong account: skip, note it). **Step 3:** `mix format`, `mix test 2>&1 | tail -10`, `node --test test/js/*.test.mjs`. **Step 4: Commit** `docs: the numbering rule in the glossary, the mapping, the schema and the stakeholder pages`.
