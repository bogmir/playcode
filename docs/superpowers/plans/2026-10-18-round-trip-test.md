# A Test That Holds the Round Trip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One test builds a play with every part filled in, exports it to TEI, imports the file into an empty Playcode and asserts the play comes back whole, but for an explicit list of known gaps.

**Architecture:** The play is built through the contexts, as the forms build it, inside a `Repo.transaction` that snapshots it, exports it and rolls back, so the import meets an empty Playcode: no leftover bibliography entry or place for it to link to instead of reading the file. The snapshot is read through the contexts' public functions and built from each struct's `__schema__(:fields)` minus a drop list, so a new column joins the comparison without anyone adding it. The known gaps patch the original's snapshot to what the round trip gives; closing a gap turns the test red until its entry goes.

**Tech Stack:** Elixir, ExUnit, Ecto (`Playcode.DataCase`), `Playcode.ImportHelpers`.

**Spec:** the backlog item *A test that holds the round trip* (`docs/backlog.md`, *Round trip*), the handoff `/tmp/handoff-round-trip-test.md`, and the design approved in chat on 2026-10-18, whose decisions are below.

## Decisions (approved 2026-10-18)

- **Known gaps:** the test asserts the difference is exactly an explicit list, each entry naming its backlog item. A red test would block every deploy (CI deploys every green `main`).
- **Read back** through `Catalogue.get_play_with_all!/1`, `PlayContent.load_play_content/1`, `PlayContent.list_characters/1`, `Witnesses.list_for_play/1`, `Bibliography.list_for_play/1`, `Places.list_play_places/1` and `Places.ancestors/2`. Rows are compared as ordered lists; `position` and the foreign keys are dropped. This deliberately reaches past "what an outsider observes" (the export cannot show a column it never writes); the moduledoc says so.
- **`show_variants`** is a fifth thing kept out of the file on purpose: a switch for what readers see, as completeness is; TEI has no place for it, and a play imported from a file arrives as a draft.
- **A second cast list** cannot be built in Playcode; it is a comment in the known gaps, not a comparison.
- **New gaps the first run finds** go into the known gaps and `docs/backlog.md`, not fixed on this branch, unless the fix is one line.

## Global Constraints

- Branch `round-trip-test` off `main`; never offer a PR or keeping the branch.
- `mix format`, `mix compile --warnings-as-errors` and the whole `mix test` before every commit. DB timeouts under load: mention, do not loop the suite.
- Plays' codes without hyphens (the importer strips them, and the snapshot holds `code`).
- Places through `place_fixture/1` with derived slugs (`CLAUDE.md`: two async tests creating the same place deadlock).
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01Qn6uzvKzs1SuXXooez2oeu`.

## Review Focus

1. A drop list too broad passes the test trivially: the researchers' notes are dropped per schema (`Bibliography.Entry.note`, `Bibliography.Link.note`), never `:note` by name, which would hide the notes of witnesses, sources, places and readings.
2. A row left behind after the rollback lets the import link to it instead of reading the file: the test asserts the rollback left no place behind (`Places.list_places/0` is `[]`); the bibliography entries go in the same rollback.
3. Rows whose order depends on insertion time (`Bibliography.list_links/1` orders by `inserted_at`) would make the test flaky: read the bibliography through `list_for_play/1`, ordered by citation.
4. A builder value equal to the column's default proves nothing: every curated column and every boolean is set away from its default (`is_hidden: true`, `is_aside: true`, `back: true`, `is_fictional: true`).
5. A known-gap path that no longer matches anything would pass silently: `put_in/3` on a path into a missing list index raises, so a stale entry fails loudly.

---

### Task 1: The test

**Files:**
- Create: `test/playcode/complete_copy_test.exs` (module `Playcode.CompleteCopyTest`, `use Playcode.DataCase, async: true`)
- Modify: `docs/backlog.md` (one item per new gap the first run finds, under *Round trip*)

**Interfaces:**
- Consumes: `Playcode.ImportHelpers.export_tei/1`, `import_tei!/1`; `Playcode.TestFixtures.place_fixture/1`; the contexts' create and list functions named above.
- Produces (private to the file):
  - `build_play(original :: Play.t()) :: Play.t()`: every part, through the contexts; ends with `PlayContent.refresh_derived/1`, as the content editor does after an edit.
  - `snapshot(play_id) :: map()`: `%{play:, editors:, sources:, paratexts:, characters:, witnesses:, bibliography:, places:, divisions:}`.
  - `fields(struct) :: map()`: `module.__schema__(:fields)` minus `@dropped` and the module's entries in `@private`, recursing into embeds (`revisions`, `readings`).
  - `known_gaps() :: [{backlog_item :: String.t(), path :: list(), value :: term()}]`

- [ ] **Step 1: Branch**

`git checkout -b round-trip-test`

- [ ] **Step 2: Write the test, its known gaps empty**

```elixir
test "a play with every part filled in comes back whole from its TEI file" do
  original = play_fixture(%{"code" => "CCO#{System.unique_integer([:positive])}"})

  # Building inside a transaction rolled back is what makes the import's Playcode empty:
  # bibliography entries and places are shared by the corpus, so purging the play would
  # leave them for the import to link to instead of reading the file.
  {:error, {built, xml}} =
    Repo.transaction(fn ->
      play = build_play(original)
      Repo.rollback({snapshot(play.id), export_tei(play)})
    end)

  assert Places.list_places() == []

  imported = import_tei!(xml)

  assert snapshot(imported.id) ==
           Enum.reduce(known_gaps(), built, fn {_item, path, value}, s -> put_in(s, path, value) end)
end
```

`Repo` is aliased in place, with the comment above saying why (`DataCase` does not import it).

`@dropped`: `id`, `play_id`, `parent_id`, `division_id`, `element_id`, `entry_id`, `place_id`, `parent_place_id`, `parent_play_id`, `position`, `origin`, `filemaker_id`, `inserted_at`, `updated_at`, `content_version`, `deleted_at`, `pending_original_code`, `is_complete`, `show_variants`. `@private`: `%{Bibliography.Entry => [:note], Bibliography.Link => [:note]}`.

What `snapshot/1` adds beyond `fields/1`: the play's `parent` (the original's `code`); a speech's `who` (its characters' `xml_id`s, in order); an element's and a division's `notes` (variants included) and `children`; a division's `elements` (`loaded_elements`); a bibliography link's `entry`; a play place's `place`, with its `names` and its `ancestors`.

`build_play/1` fills each row of `docs/stakeholder/ida-y-vuelta.html` whose *Read from TEI* is not "—" or "Not yet", every column off its default:
- the play: every metadata column, a non-Spanish `language`, `relationship_type: "traduccion"` and `parent_play_id: original.id`, the composition date (both years and a note), the historical time and its note, `form: "mixed"`, two `edition_notes` (one with `\n`), two `revisions` (one with two people, `"A; B"`, and a note);
- editors in three roles, one a digital editor, one with an organisation; a source with every column, `distributor` among them, its note in `<<…>>`;
- two witnesses with every column, a `\n` in one title, `witness_type` from `Witness.types/0`;
- two bibliography entries through `Bibliography.create_entry_for_play/4`: a modern edition with the link's `volume` and `pages`, and an article (analytic and monogr levels) with a `public_note`; both with a researcher's `note` on entry and link;
- a place inside a parent place (two names, coordinates, authority and id, `is_fictional`, a note), linked with a note;
- paratexts: a dedication with a heading, two paragraphs, a `\n` and `<<…>>`; a heading alone; one with `back: true`; the scene of the action (`lugar_accion`);
- the cast list: an `elenco` division with a heading; three characters, one hidden, one with an `actor`, one with a `<<…>>` description;
- the text: an act with a heading note, holding a scene; in it a stage direction with a `stage_type` and a note; a speech by two characters with a note on its speaker label, holding a line group with a `verse_type` and verse lines covering `line_number`, `line_id`, a split verse (`part` I and F), `rend`, a line all aside, `<<…>>`, an inline `<stage type="…">`, an `<aside>`, a `<folio>` passage, a note and a variant (`variant_type`, `range_end`, a lemma and a reading with `wit` naming a witness's siglum, a reading's note); a prose paragraph with `\n` and `<lb n="…"/>`; an unspoken prose paragraph; a trailer.

- [ ] **Step 3: Run it and watch it fail**

Run: `mix test test/playcode/complete_copy_test.exs`
Expected: FAIL, the assertion's diff showing at least `form` (`"mixed"` against `nil`). A failure before the assertion is a builder bug: fix the builder, not the drop list.

- [ ] **Step 4: Triage every difference the diff shows**

For each one: a known gap (an item of `docs/backlog.md`) becomes an entry of `known_gaps/0` naming that item; a new gap gets a backlog item under *Round trip*, then its entry; a difference that is not data loss (a column worked out again on import) goes into `@dropped` with a comment saying why. The first entry, and the second cast list as a comment:

```elixir
defp known_gaps do
  [
    {"Verse, prose or mixed", [:play, :form], nil}
    # "A second cast list": Playcode cannot hold one yet, so the play has none to lose.
  ]
end
```

A path into a list uses `Access.at/1`.

- [ ] **Step 5: Run it and watch it pass**

Run: `mix test test/playcode/complete_copy_test.exs`
Expected: PASS

- [ ] **Step 6: Prove it bites**

Stop the export writing the actor (`lib/playcode/export/tei_xml.ex`, the `if char.actor` in the cast list, ~line 820: write `children` alone). Run the file: FAIL on the character's `actor`. Put it back; run again: PASS. Do the same with a column the snapshot finds by itself, the source's `distributor`. Say both in the commit message.

- [ ] **Step 7: Refactor while green**

Clear names; the builder in the order of the table page's rows; no helper `ImportHelpers` or `TestFixtures` already has. Run the file after each change.

- [ ] **Step 8: The whole suite, format, compile**

Run: `mix format && mix compile --warnings-as-errors && mix test`
Expected: 0 failures.

- [ ] **Step 9: Commit**

```bash
git add test/playcode/complete_copy_test.exs docs/backlog.md
git commit -m "test: a play with every part filled in comes back whole from its TEI file"
```

### Task 2: The docs say so

**Files:**
- Modify: `CLAUDE.md` (*The TEI file is a complete copy of a play*)
- Modify: `docs/stakeholder/ida-y-vuelta.html`
- Modify: `docs/backlog.md`, `docs/history.md`

- [ ] **Step 1: `CLAUDE.md`**

In *The TEI file is a complete copy of a play*: whether variants are shown (`show_variants`) is kept out of the file on purpose, beside completeness, for the same reason; and `test/playcode/complete_copy_test.exs` holds the rule: a new column joins its comparison by itself, and gets written to the file, dropped there with a reason, or listed as a known gap with its backlog item.

- [ ] **Step 2: `docs/stakeholder/ida-y-vuelta.html`**

*Into the TEI*: five things stay out, the fifth whether a play's variant readings are shown. *What happens next*: the check is built (18 October 2026) and runs with every change. The status line's "Updated on 18 October" sentence says so. A new gap from Task 1 changes its row's *Read from TEI* cell to "Partly" or "No", with a note.

- [ ] **Step 3: Backlog to history**

Move *A test that holds the round trip* from `docs/backlog.md` to `docs/history.md`, in the history's form, naming the known gaps it lists.

- [ ] **Step 4: Verify and commit**

Run: `mix test test/rename_guard_test.exs && mix format --check-formatted`
Expected: PASS.

```bash
git add CLAUDE.md docs/
git commit -m "docs: the round trip is held by a test; show_variants stays out of the file"
```

## Finishing

Ask only "merge and push?". On yes: `git checkout main && git merge --no-ff round-trip-test`, `mix test` on the merge, `git push`, `git branch -d round-trip-test`. Then republish the Round Trip artifact (https://claude.ai/artifact/SSTtmSMyH3KtU9kCBvh8Zj) following the memory note `stakeholder-artifacts-account.md`.
