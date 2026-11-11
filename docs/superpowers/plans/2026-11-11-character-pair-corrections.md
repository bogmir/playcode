# Character pair corrections (problem 5, step 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a researcher corrects which original character a translation's character goes
with (another character, or none); every comparison pairs the rest by rule, as today, with
the corrections on top; the corrections travel in the TEI file and back.

**Architecture:** two columns on `characters` (`original_xml_id`, `no_original`), read by
`Playcode.Alignment` when it pairs characters; written as `castItem corresp="orig:X"` /
`castItem ana="sin-original"` with a `listPrefixDef` in the header, read back by the parser;
set from a select in the cast-entry modal of the content editor's characters tab.

**Tech Stack:** Elixir, Ecto/Postgres, Phoenix LiveView, Saxy / xml_builder.

**Spec:** `docs/superpowers/specs/2026-11-08-translation-alignment-design.md` (*Design*,
the character bullet and its builder's calls; *TEI*; *Order of work*, step 3).

## Global Constraints

- Only corrections are stored; an uncorrected character is paired by rule at every build.
- A correction names the original character by its `xml:id`, never a row id.
- A pointer naming no character of the original counts as no correction.
- `castItem`, not `role`, carries the pointer: `role corresp` already means a later list
  naming a character declared earlier.
- The prefix: `<prefixDef ident="orig" matchPattern="(.+)" replacementPattern="../<CODE>/<CODE>.xml#$1"/>`,
  `<CODE>` the original's code (`Catalogue.original_code/1` names it even while waiting).
- A TEI file names no database id; the complete-copy rule holds (`complete_copy_test.exs`).
- An id or value from the browser is resolved against the play's own rows (`get_entry/2`,
  `get_character/2`) and the original's characters, never trusted.
- `characters` already has its `play_row_changed()` trigger: a new column needs none.
- TDD per task: red, green, refactor, `mix test`, `mix format`; prove new tests bite with
  `bin/bites`.

## Review Focus

1. **The original re-imported after a correction:** its characters get new row ids, the
   correction (an `xml:id`) still pairs. Test in Task 2.
2. **The translation re-imported from a corpus file with no pointers:** its corrections stay
   for the characters whose `xml:id` the file still has. Test in Task 2.
3. **A pointer to a character the original no longer has** (renamed in a corrected file):
   the character pairs by rule, and the select shows the pointer as missing rather than
   silently picking another. Tests in Tasks 1 and 3.
4. **A value from the browser that is no character of the original:** refused, nothing
   stored. Test in Task 3.
5. **A play that is not a translation or version, or has no original:** no select, and the
   export writes no prefix. Tests in Tasks 2 and 3.

---

### Task 1: The corrections and the pairing

**Files:**
- Create: `priv/repo/migrations/20261111150000_add_original_to_characters.exs`
- Modify: `lib/playcode/play_content/character.ex` (fields, changeset)
- Modify: `lib/playcode/alignment.ex` (`text/1` keeps the two fields and `xml_id`;
  `pair_characters/2` applies corrections first, then the greedy rule over the rest)
- Test: `test/playcode/export/static_site_compare_test.exs`, `test/playcode/alignment_test.exs`
  (create if absent)

**Interfaces:**
- Produces: `Character` fields `original_xml_id :string` (nil), `no_original :boolean`
  (false); `Character.changeset/2` casts both and clears `original_xml_id` when
  `no_original` is true. `Alignment.character_pairs(original_divisions, translation_divisions, opts \\ []) :: %{translation_character_id => original_character_id}`,
  corrections applied; `corrections: false` gives the rule's own pick, which Task 3's
  select shows as "Automatic".

- [ ] **Step 1: Write the failing tests**
  - `static_site_compare_test.exs`, "a corrected character pairs its speeches with its
    correction's": `split_speech_editions()`, then correct `antoine` to `CLEO` and
    `cleopatre` to `ANT` (`PlayContent.update_character/2`), generate; the French panel's
    first speech has `data-pair="1"` (Antoine, made Cleopatra, goes with her speech; the
    automatic pairs were `["0", "1", "1", "2"]`). If `List.myers_difference/2` chooses
    another common sequence, pin what it gives with a comment deriving it.
  - `alignment_test.exs`, "a character with no original pairs with none, one naming a
    missing character pairs by rule": through `Alignment.character_pairs/3` on the
    fixture's divisions (`PlayContent.load_play_content/2`): `cleopatre` with
    `no_original: true` is absent from the map; `antoine` with `original_xml_id: "GONE"`
    maps to `ANT`'s id.
- [ ] **Step 2: Run them, watch them fail** (`mix test` on both files; expected: unknown
  field / undefined function).
- [ ] **Step 3: Migration** adding both columns (`original_xml_id` string null,
  `no_original` boolean not null default false); schema fields; changeset.
- [ ] **Step 4: `Alignment`**: corrections first (a pointer resolving to an original
  character of the text, `no_original` dropping the character), then the existing greedy
  pass over the characters and originals left; `character_pairs/3` exposes it.
- [ ] **Step 5: Run the tests, green; refactor; `mix test`; `mix format`; bites.**
- [ ] **Step 6: Commit** `feat: a translation's characters take their corrected originals`.

### Task 2: The corrections in the TEI file

**Files:**
- Modify: `lib/playcode/export/tei_xml.ex` (the declaring `castItem`: `corresp`, the
  `sin-original` mark beside `grupo`/`oculto`; `encodingDesc`: `listPrefixDef` when the
  play has an original code and a corrected character)
- Modify: `lib/playcode/import/tei_parser.ex` (`cast_item`: `corresp` on the `castItem`,
  its `orig:` or `…#` prefix dropped, into `original_xml_id`; `sin-original` into
  `no_original`)
- Modify: `lib/playcode/import/tei_import.ex` (before `reset_tei_content/1`, the play's
  corrections by `xml_id`; after `write_characters/2`, a character the file gives no
  correction takes its kept one)
- Test: `test/playcode/tei_roundtrip_test.exs`, `test/playcode/complete_copy_test.exs`
- Docs: `docs/tei-mapping.md` (castItem lines and the header's prefix)

**Interfaces:**
- Consumes: Task 1's fields.

- [ ] **Step 1: Write the failing tests**
  - Round trip: a translation with one character corrected and one marked no original
    exports `castItem corresp="orig:CLEO"`, `castItem ana="sin-original"`, and one
    `prefixDef ident="orig"` whose `replacementPattern` is `../<ORIGINAL>/<ORIGINAL>.xml#$1`;
    imported into an empty database (`roundtrip/1`), the two characters come back corrected.
  - No prefix for a play with no original and no correction (`xml_elements/3` empty).
  - "the original re-imported keeps its translations' corrections": correct `antoine`,
    re-import the original's file; the French panel's first speech still has
    `data-pair="1"` (Task 1's case).
  - "a corpus file re-imported keeps the corrections": correct `antoine`, re-import the
    French file without pointers; `antoine` is still corrected, a character the file no
    longer has is gone.
  - `complete_copy_test.exs`: the rarer play's characters carry one correction and one
    `no_original`; the comparison passes with no new gap.
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: Export, parser, import as above.**
- [ ] **Step 4: Green; refactor; `mix test`; `mix format`; bites.**
- [ ] **Step 5: `docs/tei-mapping.md`**, then commit
  `feat: a translation's character corrections travel in its TEI file`.

### Task 3: The select on the characters tab

**Files:**
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex` (the entry modal's
  "In every list" fieldset; `save_entry/2` validates the value)
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs` (or the file that
  covers the entry modal), `test/playcode_web/accessibility_test.exs` if the modal is listed

**Interfaces:**
- Consumes: `Alignment.character_pairs/3` (with and without corrections),
  `Catalogue`'s preload of the parent.

- [ ] **Step 1: Write the failing tests** (through `live/2`, `form/3`, `render_submit/1`):
  - On a translation's entry modal, a select labelled "Original character" offers
    "Automatic (ANTONY)" (the rule's pick), each original character by name, and "No
    original"; choosing CLEOPATRA and saving stores `original_xml_id: "CLEO"` (read back
    through `PlayContent.get_character/2`); "No original" stores `no_original: true`;
    "Automatic" clears both.
  - A value that is no character of the original (`"GONE"` posted by hand) stores nothing
    and shows the form's error.
  - A stored pointer the original lacks shows as "Missing: GONE" selected, not another.
  - An original's entry modal, and an adaptation's, have no such select.
- [ ] **Step 2: Run, watch them fail.**
- [ ] **Step 3: The select**: values `""` (automatic), `"-"` (no original: no `xml:id`
  starts with a hyphen), else an original's `xml:id`; mapped to the two fields in
  `save_entry/2`; the original's characters and the automatic pick loaded when
  the modal opens, only for a play `Alignment.paired?/1` with an original. Strings through
  `gettext`, `mix gettext.extract --merge`, Spanish entries checked.
- [ ] **Step 4: Green; refactor; `mix test`; `mix format`; bites.**
- [ ] **Step 5: Commit** `feat: the characters tab corrects a character's original`.

### Task 4: Docs and the check

- [ ] `docs/schema.md` (the two columns), `docs/stakeholder/ida-y-vuelta.html` (a row:
  character pairs, every cell), `docs/backlog.md` (step 3 built) and the spec's *Order of
  work*.
- [ ] Browser check on dev: correct a character of 0084 on its tab, open Playcode's
  comparison of 0038/0084 and see the sync follow.
- [ ] `mix test`, `node --test test/js/*.test.mjs`, `mix format`; commit
  `docs: character pair corrections`.
