# Note Names Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The nine subject kinds of note and `variantes` get the names question 17 decided, each its own option in the Notes filters; the two slips `video` and `nota_editor_digital` are read as `traductor` and `editor_digital`.

**Architecture:** One clause per kind in `PlayLabels.note_type_label/1` and the kinds in `Note.types/0`, which already drive every reader's label, the filter keys and the admin's select. `variantes` shares the critical apparatus's filter key, so a play with both (EMOTHE0560) shows one "Textual variant" option. The slips are mapped where the TEI parser reads a note's type, as `stage_type/1` maps `delivery_`, and a data migration rewrites the two stored notes, as `20261013140000_spell_delivery_as_tei_does` did.

**Tech Stack:** Elixir/Phoenix, gettext, Ecto migrations.

**Spec:** question 17 in `docs/stakeholder/preguntas.html` ("What should these thirteen kinds of note be called?", the table's last column) and "Labels for the other note types" in `docs/static-site-improvements.md`. Handoff: `/tmp/handoff-note-names.md`.

## Global Constraints

- The English names, word for word: `latinismo` Latinism, `toponimo_aludido` Place mentioned, `toponimo_accion` Place of the action, `atrezzo` Props, `oficio` Trades and offices, `vestuario` Costume, `espacio` Stage space, `gesto_movimiento` Gesture and movement, `efectos_especiales` Special effects, `variantes` Textual variant.
- `falta_tipo` stays a plain "Note" (question 17 still open for it). Do not add it anywhere.
- `variantes` stays an ordinary note: `Note.variant?/1` keeps matching `variante` only.
- Spanish (`priv/gettext/es/LC_MESSAGES/default.po`), our wording, from the files' own words: Latinismo, Topónimo aludido, Topónimo de la acción, Atrezo, Oficios y cargos, Vestuario, Espacio escénico, Gesto y movimiento, Efectos especiales. "Textual variant" already has "Variante textual".
- Work on branch `note-names`. Merge and push only when the user says so.
- Every task ends with `mix format`, `mix compile --warnings-as-errors`, `mix test`. One rerun of a failure that does not come back: say so and move on, no loops.

## Review Focus

1. EMOTHE0560 has 189 variants and 3 `variantes` notes: the admin Notes tab must offer "Textual variant" once, listing both. Test in Task 1.
2. A stored `video` or `nota_editor_digital` note on a play not re-imported must read as the right kind. The migration in Task 2; checked on dev by count.
3. Editing a note of a kind the select did not list (`falta_tipo` now, `latinismo` before) must keep its type. The content editor test is moved to `falta_tipo` in Task 1.
4. `mix gettext.extract --merge` fuzzy-matches new msgids onto old ones. Task 1 checks every new entry in the es `.po` by hand.
5. The next Generate rebuilds every play (`PlayLabels` and `Note` are in `StaticSite.Fingerprint` `@modules`). Nothing to build; say so in the history entry. One full rebuild is pending anyway.

---

### Task 1: The ten names, and their filter options

**Files:**
- Modify: `lib/playcode/play_content/note.ex:29` (`@types`)
- Modify: `lib/playcode_web/play_labels.ex:35-61` (`note_type_label/1`, `note_type_key/1`, their docs)
- Modify: `priv/gettext/es/LC_MESSAGES/default.po`, `priv/gettext/default.pot`, `priv/gettext/en/LC_MESSAGES/default.po` (via `mix gettext.extract --merge`)
- Test: `test/playcode/export/static_site_play_test.exs` ("the Notes page")
- Test: `test/playcode_web/live/admin/play_notes_live_test.exs`
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs:1122` (moved to `falta_tipo`)

**Interfaces:**
- Produces: `Note.types/0` = `~w(traductor editor editor_critico editor_digital autor latinismo toponimo_aludido toponimo_accion atrezzo oficio vestuario espacio gesto_movimiento efectos_especiales variantes)`, in that order (it orders the admin's select). `PlayLabels.note_type_key("variantes") == "variante"`.

- [ ] **Step 1: Branch**

Run: `git switch -c note-names`

- [ ] **Step 2: Write the failing site test**

In `static_site_play_test.exs`, a new `describe "the names of the kinds of note"` using `publish!/1` as "the Notes page" does: one act, one speech, eleven lines `n="1"`..`n="11"`, each with one note of type, in order, `latinismo`, `toponimo_aludido`, `toponimo_accion`, `atrezzo`, `oficio`, `vestuario`, `espacio`, `gesto_movimiento`, `efectos_especiales`, `variantes`, `falta_tipo`.

```elixir
test "each kind the project named is shown by its name and filtered by itself", %{notes: notes} do
  heads = notes |> LazyHTML.query("ol[data-notes] > li > p:first-child b") |> Enum.map(&LazyHTML.text/1)

  assert heads == [
           "Latinism", "Place mentioned", "Place of the action", "Props", "Trades and offices",
           "Costume", "Stage space", "Gesture and movement", "Special effects",
           "Textual variant", "Note"
         ]

  [filter] = notes |> LazyHTML.query("fieldset[data-note-filter]") |> Enum.to_list()

  # falta_tipo is still a plain Note (question 17); variantes shares the apparatus's key.
  assert filter |> LazyHTML.query("input") |> LazyHTML.attribute("value") ==
           ["", "latinismo", "toponimo_aludido", "toponimo_accion", "atrezzo", "oficio",
            "vestuario", "espacio", "gesto_movimiento", "efectos_especiales", "variante", "other"]
end
```

- [ ] **Step 3: Write the failing admin test**

In `play_notes_live_test.exs`, beside the variant test:

```elixir
# EMOTHE0560 has both: the files' three "variantes" notes and the apparatus.
test "a note of kind variantes is a textual variant, filtered with the variants", %{conn: conn}
```

Body: `import_tei!` the variant test's line with its note's `type="editor"` made `type="variantes"`; open `/admin/plays/:id/notes`; `[variant, note] = notes(play)`; then

```elixir
assert texts(view, ~s(#notes-filter select option)) == [t("All types"), t("Textual variant")]
view |> form("#notes-filter", filter: %{type: "variante"}) |> render_change()
assert rows(view) == [row(variant), row(note)]
assert texts(view, "##{row(note)} .note-type") == [t("Textual variant")]
```

- [ ] **Step 4: Run both, watch them fail**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode_web/live/admin/play_notes_live_test.exs`
Expected: the new site test fails on `heads` (ten "Note"s); the admin test fails on the options (`t("Note")` beside "Textual variant").

- [ ] **Step 5: Implement**

- `Note`: the `@types` of *Interfaces*; its doc stays "The note types the corpus uses".
- `PlayLabels.note_type_label/1`: one clause per name of *Global Constraints*, after `autor`, before `variante`; `variantes` reads `gettext("Textual variant")`.
- `PlayLabels.note_type_key/1`: `def note_type_key(type) when type in ["variante", "variantes"], do: "variante"`. Docs of `note_type_key/1` and `note_type_options/1`: `falta_tipo` is now the example of a type with no label (drop `latinismo`), and say `variantes` files with the variants.

- [ ] **Step 6: Run both, watch them pass**

Same command. Expected: the two new tests pass; "the Notes page" test and the content editor's "?division= opens a heading's modal" fail, since `latinismo` is no longer unlabelled.

- [ ] **Step 7: Move the two old tests to `falta_tipo`**

Their premise is "a type with no label"; `latinismo` now has one. Change `type="latinismo"` to `type="falta_tipo"` in "the Notes page" setup (`static_site_play_test.exs:524`, and the comment at `:542`: "falta_tipo here, the one kind still unnamed (question 17); or none") and in `play_content_editor_live_test.exs:1129` and `:1142`, with a one-line comment that `latinismo` has had a name since question 17. Run both files: PASS.

- [ ] **Step 8: Prove the new tests bite**

Comment out the `note_type_key` `variantes` clause: the admin test goes red. Remove the `latinismo` label clause: the site test goes red. Put both back, green.

- [ ] **Step 9: Translations**

Run: `mix gettext.extract --merge`. In the es `.po`, give the nine new msgids the Spanish of *Global Constraints*, and check each entry the command marked `#, fuzzy` that is one of them (remove the flag once the msgstr is right). Leave the en `.po`'s old fuzzies alone.

- [ ] **Step 10: Refactor while green, then the gates**

Run: `mix format && mix compile --warnings-as-errors && mix test 2>&1 | tail -5`
Expected: 0 failures.

- [ ] **Step 11: Commit**

```bash
git add lib/playcode/play_content/note.ex lib/playcode_web/play_labels.ex priv/gettext test/playcode/export/static_site_play_test.exs test/playcode_web/live/admin/play_notes_live_test.exs test/playcode_web/live/admin/play_content_editor_live_test.exs
git commit  # "feat: the kinds of note question 17 named", saying which tests were made red and how
```

### Task 2: The two slips, read as what they are

**Files:**
- Modify: `lib/playcode/import/tei_parser.ex:1997` (`parse_note/2`), new `defp note_type/1` beside `stage_type/1` (`:1781`)
- Create: `priv/repo/migrations/20261018140000_read_the_note_slips.exs`
- Test: `test/playcode/tei_roundtrip_test.exs` ("in-text notes")

**Interfaces:**
- Consumes: nothing from Task 1.

- [ ] **Step 1: Write the failing round trip**

In "in-text notes":

```elixir
# La tragedia española's note on "Belona" is typed "video", Marta la piadosa's one
# "nota_editor_digital": slips for a translator's and a digital editor's (question 17).
test "a slip in a note's kind comes back as the kind it is" do
  xml = roundtrip(tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker>
    <l n="1">Belona<note n="1" type="video"><p>Diosa.</p></note></l>
    <l n="2">Marta<note n="2" type="nota_editor_digital"><p>Errata.</p></note></l>
  </sp></div1>)))

  assert Enum.map(xml_notes(xml), & &1.type) == ["traductor", "editor_digital"]
end
```

- [ ] **Step 2: Run it, watch it fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs:LINE` (the new test's line)
Expected: FAIL, `["video", "nota_editor_digital"]`.

- [ ] **Step 3: Implement `note_type(attrs) :: String.t() | nil`**

Same shape as `stage_type/1`: a comment naming the two files, `"video" -> "traductor"`, `"nota_editor_digital" -> "editor_digital"`, any other as written. `parse_note/2` calls it for `type:`.

- [ ] **Step 4: Run it, watch it pass**

Same command: PASS.

- [ ] **Step 5: The migration**

`Playcode.Repo.Migrations.ReadTheNoteSlips`, modelled on `20261013140000_spell_delivery_as_tei_does.exs` (moduledoc saying why, not reversible, the triggers move `content_version`; `down` is `:ok`):

```sql
UPDATE play_notes SET type = 'traductor' WHERE type = 'video'
UPDATE play_notes SET type = 'editor_digital' WHERE type = 'nota_editor_digital'
```

No test: the precedent has none, and the SQL is two literals. Check it on dev instead:

Run: `mix ecto.migrate && mix run -e 'IO.inspect Playcode.Repo.query!("SELECT type, count(*) FROM play_notes WHERE type IN (''video'', ''nota_editor_digital'') GROUP BY type").rows'`
Expected: `[]` (before migrating, the same query gives one row of each if dev holds EMOTHE0307 and EMOTHE0579; note the before counts for the commit).

- [ ] **Step 6: Gates, prove it bites, commit**

Break the `"video"` clause, watch Step 1 go red, restore. Then `mix format && mix compile --warnings-as-errors && mix test 2>&1 | tail -5`, 0 failures.

```bash
git add lib/playcode/import/tei_parser.ex priv/repo/migrations/20261018140000_read_the_note_slips.exs test/playcode/tei_roundtrip_test.exs
git commit  # "fix(import): video and nota_editor_digital are read as the kinds they are"
```

### Task 3: The docs

**Files:**
- Modify: `docs/backlog.md` (remove *Labels for the other note types* from *Awaiting the project (static site)*; the section's lead line still names question 17 for `falta_tipo`)
- Modify: `docs/history.md` (a new `- [x] **The names of the kinds of note** (2026-10-18)` entry: the ten names, `variantes` with the variants' filter, the slips and the migration with dev's counts, the tests by name, the next Generate rebuilding every play, `falta_tipo` left to question 17)
- Modify: `docs/static-site-improvements.md:162` (the section says what was built; `falta_tipo` still waits)
- Modify: `docs/stakeholder/preguntas.html` (question 17's `answered` block: a "Built on 18 October 2026: readers see it once the site is generated." line, as question 1's)

- [ ] **Step 1: Edit the four files, commit**

```bash
git add docs/
git commit  # "docs: the names of the kinds of note are built"
```

- [ ] **Step 2: Finish the branch**

`superpowers:finishing-a-development-branch`; merge and push only when the user says so. After the push, republish the Questions artifact (https://claude.ai/artifact/H6n5YQ6JViV69D3GndJpwn) with `files: {"preguntas.html": "docs/stakeholder/preguntas.html"}`, following the memory note `stakeholder-artifacts-account.md`.
