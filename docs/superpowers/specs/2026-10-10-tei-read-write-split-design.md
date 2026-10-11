# Separate reading a TEI file from writing it

`lib/playcode/import/tei_parser.ex` (1,865 lines) creates rows while it walks the XML, so no
part of an import can run or be tested without a database, and `preview_import/1` reads the
header a second way instead of reusing the parse. The next three importer features (`<app>`,
`<lb/>`, `<code>`, `docs/backlog.md`) all change how the file is read; this split comes first so
that each lands in pure code. Backlog item from the Groxio audit (2026-10-08). Agreed 2026-10-10.

**Nothing a user, a caller or a test can observe changes.** No existing test is edited by the
split, and the corpus golden master below is byte-identical before and after.

## Two modules

- **`Playcode.Import.TeiParser`**, pure: no `Repo`, no context function that reads or writes
  the database (pure helpers such as `Places.slugify/1`, `Witnesses.type_from_tei/2` and
  `Play.valid_languages/0` are fine). One public function, `parse_file(path)`:
  `{:ok, tei}` or `{:error, reason}`, the reasons today's callers already get (`:enoent` and
  the other `File.read/1` errors, `{:xml_parse_error, _}`, `:encoding_error`,
  `:missing_tei_header`). The UTF-16 decoding, the Saxy parse, the walk, the XML helpers, the
  inline markup and note marks, and the title normalisation all live here.
- **`Playcode.Import.TeiImport`**, everything that touches the database:
  - `import_file(path)`: `parse_file/1`, then `Repo.transaction(fn -> write(tei) end)`.
    Returns what it returns today.
  - `preview_import(path)`: `parse_file/1`, then the counts for `tei.play.code`. Same result
    map. It now walks the whole file, not only the header; the walk is pure and total, so the
    result is the same.
  - `mixed_ownership_total/1` and `@platform_owned`, unchanged.

No facade module: `TeiImport` is the entry point, `TeiParser` what it calls.

## The parsed play

Plain maps with atom keys, lists in document order. Positions are computed by the reader
exactly as today, including the act's element counter carrying on through its scenes and the
front matter's counter, which body divisions continue.

```elixir
%{
  play: %{code: "EMOTHE0010", title: "…", …},   # today's extract_play_attrs/3, every key
  editors:  [%{person_name, role, organization, position}],
  sources:  [%{title, author, editor, editor_role, publisher, pub_place, pub_date, note,
               language, position}],
  witnesses: [%{siglum, witness_type, title, …, note}],   # all of them; skipping is the writer's
  places:   [%{attrs: %{"slug" => …, "type" => …, "names" => […], …},
               slug_declared: boolean, places: [nested place]}],
  settings: [%{slug: "roma", role: "setting", position: 0, note: nil}],
  characters: [%{xml_id, name, description, is_hidden, position}],
  editorial_notes: [%{section_type, heading, content, position}],
  divisions: [division]                           # <front>'s elenco divisions, then <body>'s
}

division = %{type, number, title, position, notes: [note], elements: [element],
             divisions: [division]}
element  = %{type, position, …its columns, who: [xml_id], notes: [note],
             elements: [element]}               # who only on a speech
note     = %{offset, n, type, term, body}         # notes with no text are already dropped
```

An element's columns are today's: `speaker_label` (speech); `verse_type`, `part` (line
group); `content`, `line_number`, `line_id`, `part`, `rend`, `is_aside` (verse line);
`content`, `stage_type` (stage direction); `content`, `is_aside` (prose); `content`
(trailer).

What is a fact about storage, not about the file, is added by the writer: `play_id`,
`parent_id`, `division_id`, `parent_place_id`, `origin: "tei"`. A `who` stays a list of
xml_ids; the writer turns them into character ids.

## Writing

`TeiImport.write/1`, inside the one transaction, in today's order:

1. **The play, by code.** Existing: `reset_tei_content/1`, update with `@platform_owned`
   dropped, `deleted_at` cleared. New: create. A changeset error rolls back to
   `{:error, changeset}`.
2. **Editors and sources**, stamped `origin: "tei"`. A row its changeset refuses is skipped,
   as today.
3. **Witnesses**: a siglum in `Witnesses.taken_sigla/1` or already taken earlier in the file is
   skipped, so is a printed line the play already has (`Witnesses.plain/1`), as today.
4. **Places**: `Places.find_or_create_by_slug/1` down the tree, with the parent's id; the
   "resolved to existing place by name" warning when `slug_declared` is false, the "left
   unchanged" info when it is true; a place its changeset refuses is logged and its nested
   places are not written, as today. Then the `<setting>` links: an unknown slug is logged, a
   link of another origin is left alone, a `"tei"` link is refreshed, a new one is created.
5. **The cast**, one `PlayContent.create_character_unless_exists/1` each (it suffixes a
   clashing xml_id with a different name). Then one `PlayContent.list_characters/1` gives
   `%{xml_id => id}` for every `who`: the same answer as today's lookup per speech, since the
   whole cast is written before any speech. Repeated refs are written once, as today.
6. **Editorial notes**, stamped `origin: "tei"`.
7. **Divisions**, recursively: the division, its heading's notes, its elements, its
   sub-divisions. Each element: the row, its notes, a speech's characters, its children.
   Failures roll back with today's terms: `{:division_create_failed, cs}`,
   `{:element_create_failed, type, cs}`, `{:note_create_failed, cs}`.
8. **`Catalogue.update_verse_count/1`**, whose play is the one returned.

## Order of work and proof

1. **Rename commit**, no logic: `TeiParser` becomes `TeiImport` (`git mv` of the module and of
   `test/playcode/import/tei_parser_test.exs` to `tei_import_test.exs`), every reference
   updated: `import_live.ex`, `tei_corpus.ex`, the mix task, `play.ex`'s moduledoc, the test
   files and `import_helpers.ex`, CLAUDE.md, `docs/architecture.md`,
   `docs/word-import-feature.md`. Not `docs/backlog.md` (its item is retired in step 6) nor
   `docs/static-site-improvements.md` (it names `tei_parser.ex` for how text is read, still
   true after the split). `mix test` green.
2. **Golden master, before the split**, in a scratch database (`MIX_ENV=test
   MIX_TEST_PARTITION=_golden`), never `playcode_dev`. Import the 370 `doc/tei_corpus` files and
   the fixtures as `mix playcode.import.tei` does, and dump every play: its
   `TeiXml.generate/1` output and its rows (play, editors, sources, witnesses, characters,
   editorial notes, divisions, elements with their characters, notes, place links, and the
   gazetteer) with UUIDs and timestamps dropped, a parent named by its path of positions.
   Re-import everything with `--force` (the reset-and-update path) and dump again. The dump
   script stays in the scratchpad.
3. **The failing test**: a new `test/playcode/import/tei_parser_test.exs`,
   `use ExUnit.Case, async: true`, no sandbox checkout. It parses a small TEI file and asserts
   on the parsed play: the code, a character, a speech's `who`, a note's offset and body. Red:
   `parse_file/1` does not exist.
4. **Split commit**: extract the reader until that test is green. Prove it bites: a
   `Repo.get_by` in the reader turns it red with `DBConnection.OwnershipError`; take it out
   again. No existing test file changes in this commit.
5. `mix test`, `mix test --include slow`, `mix format`, `mix compile --warnings-as-errors`.
   The golden master again; `diff -r` against step 2 is empty, both dumps.
6. The backlog item moves to `docs/history.md`, with the two modules' line counts.

Branch `tei-read-write-split`.

## Out of scope

Behaviour of any kind: bulk inserts, a preview that also says what the file brings, the
`ponytail:` note about two adjacent spaced notes in `take_notes/2`, the importer's silent skip
of an editor or source its changeset refuses. Splitting the reader further (header against
text) would need a shared XML-helpers module; reconsider when `<app>` lands.
