# Reading the Bibliography Back: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A play imported from a TEI file gets its bibliography back from `<back>`: shared references recognised by their description, the play's own volume and pages on its link, nothing in Playcode changed or removed, and new references added on every import.

**Architecture:** The file stays a plain bibliographic description (no FileMaker or Playcode identifier). `Bibliography.Entry` holds the TEI type tables both directions use; `Bibliography.Entry.description/1` gives an entry in the file's terms, which is what a reference is matched on. The parser reads `biblStruct`s into descriptions; `TeiImport` matches or creates entries and links them, after the text, on every import; `preview_import/1` reports what it would add.

**Spec:** `docs/superpowers/specs/2026-10-13-bibliography-read-back-design.md` (read it first).

## Global Constraints

- Branch `bibliography-read-back`; never commit to `main`.
- TDD for every change, in CLAUDE.md's order: failing test, watch it fail, smallest implementation, watch it pass, **refactor while green**, then `mix test` (the whole suite).
- `mix format` after every task; `mix compile --warnings-as-errors` before every commit.
- TEI as round trips (`test/support/import_helpers.ex`); read back through `Playcode.Bibliography`, never `Repo`.
- The parser stays pure: every new app function it calls goes on `@pure_helpers` in `test/playcode/import/tei_parser_test.exs`.
- No FileMaker or Playcode identifier is written into the file (CLAUDE.md).
- A test written for code that already works must be broken once to show it bites.

## File map

| File | Change |
|---|---|
| `lib/playcode/bibliography/entry.ex` | the TEI type tables (`@list_types`, `@bibl_types` from `TeiXml`), both directions; `description/1`; `tei_url/1` |
| `lib/playcode/bibliography.ex` | `find_identical/2` |
| `lib/playcode/bibliography/link.ex` | moduledoc: `origin` may be `"tei"` |
| `lib/playcode/export/tei_xml.ex` | the tables from `Entry`; the link's volume and pages as `citedRange` |
| `lib/playcode/import/tei_parser.ex` | `back` → `bibliography: [%{description, volume, pages}]` |
| `lib/playcode/import/tei_import.ex` | `write_bibliography/2`; `preview_import/1` lists the references it would add |
| admin import page, `mix playcode.import.tei --dry-run` | print the references an import would add |
| tests | `tei_roundtrip_test.exs`, `export/tei_xml_test.exs`, `export/tei_validator_test.exs`, `import/tei_import_test.exs`, the import page's and the mix task's tests |
| docs | round-trip page, backlog, history, `CLAUDE.md` (TEI mappings, the `origin` values) |

### Task 1: The TEI type tables in `Bibliography.Entry`

Pure refactor; the export's output does not change.

- [x] Move `@list_types` and `@bibl_types` from `TeiXml` to `Bibliography.Entry` (`@tei_lists`, `@tei_types`), with `tei_list(kind)` and `tei_type(pub_type)`. The reverse lookups, `kind_from_tei_list/1` and `pub_type_from_tei/1`, come with Task 4, where the parser uses them and a test covers them.
- [x] `TeiXml` calls them. The bibliography tests in `export/tei_xml_test.exs` stay green unchanged, which is the proof (a mistyped type name turns "an article: …" red).
- [x] Commit: `refactor(bibliography): the TEI type tables live with the entry`

### Task 2: The play's own volume and pages in `citedRange`

- [x] Reverse the test "a modern edition: the play's own volume and pages…" in `export/tei_xml_test.exs`, with a comment saying why: the link's `volume` 5 and `pages` 2366-2466 are `citedRange`s at the end of the `biblStruct`, and the entry's `volume` 1 is a `biblScope` again. Watch it fail.
- [x] `build_monogr/1` writes only the entry's `biblScope`s; `build_bibl_struct/1` appends `citedRange[@unit="volume"|"page"]` from the link, after `series`, `note` and `ptr`.
- [x] Schema: the bibliography test in `tei_validator_test.exs` links a modern edition with its own volume and pages, and now asserts its `citedRange`; run with `--include slow`.
- [x] Commit: `feat(tei): a play's own volume and pages in an edition are a citedRange`. Only files with such a link change: 136 links on 43 plays in dev.

### Task 3: `Bibliography.Entry.description/1`

In `Entry`, not the `Bibliography` context: it is pure, and the parser builds an `%Entry{}` from the file and passes it through the same function, so "the file's terms" is defined once.

- [x] Test (in `tei_roundtrip_test.exs`, describe "the bibliography"): for an entry of every publication type, with every field filled, a double space, a URL with a stray ". " and a `volumes_total`, `description(entry)` and the link's volume and pages equal what the reader gives for the exported file. Failed first (no `description/1`); a reader that drops `issue`, or a description that does not collapse whitespace, turns it red.
- [x] `description/1`: the public fields, each whitespace-collapsed, nil for blank; `url` through `Entry.tei_url/1`, the predicate the export now shares. Researchers' `note` is not part of it.
- [x] Committed with Task 4.

### Task 4: Reading `<back>`

- [x] Parser purity: `Entry.description/1`, `kind_from_tei_list/1` and `pub_type_from_tei/1` on `@pure_helpers`; the test reading a prose bibliography runs with no database.
- [x] `Entry.kind_from_tei_list/1` and `Entry.pub_type_from_tei/1`, the reverse of Task 1's lookups.
- [x] `TeiParser` gives `bibliography: [%{description: map, volume: _, pages: _}]` from every `listBibl/biblStruct` under a `div[@type="bibliografia"]` in `back`; `kind` from the `listBibl`, the rest from the `biblStruct`. A `div` holding `p` (the seven prose bibliographies) gives nothing: tested with EMOTHE0310's shape. `tei/1` in `import_helpers.ex` gains a `:back` option.
- [x] Task 3's test goes green.
- [x] Commit: `feat(tei): the parser reads the bibliography`

### Task 5: Importing it

Tests first, all through `import_tei!/1` and `Playcode.Bibliography` (all red first):

- [x] A play rebuilt from its file (its entries gone with their last links) gets every reference back: descriptions, the link's volume and pages, `origin: "tei"`, no researchers' notes.
- [x] Two plays' files with the same reference give one entry with two links.
- [x] A re-import adds a reference new to the file and changes nothing else: a link typed by hand stays, an identical reference is not added twice.
- [x] An older file's version of a corrected reference comes in beside the corrected entry, which stays (the known gap, asserted so a change of rule is a decision).
- [x] A `biblStruct` that cannot become an entry (an unknown `listBibl` type, nothing to name it) is skipped, a reference twice in one file is linked once, and the play imports.

Then:

- [x] `Bibliography.identical_entries(descriptions, play_id)`: candidates by title in SQL (whitespace collapsed as `description/1` collapses it; entries with no title always), compared in full with `description/1`; the play's own entry first, else the oldest. One query per import, not per reference.
- [x] `create_entry_for_play/4` and `link_entry/4` take the link's `origin` (default `"manual"`).
- [x] `TeiImport.write_bibliography/2`, after the text, on first import and re-import alike: link the identical entry when the play does not link it yet, else create entry and link; a reference that fails `Entry.changeset` is logged and skipped before any write, because a failed write in the import's transaction would roll the play back.
- [x] Links list by insertion second then id, so the tests compare them sorted. Matching off breaks sharing and the re-import test; no validity check breaks the skipping test.
- [x] `mix test --include slow`: 1,027 tests, the corpus sweep included.
- [x] Commit: `feat(tei): a play's bibliography comes back from its file`

### Task 6: The preview lists what would be added

- [x] Test: `TeiImport.preview_import/1` reports `bibliography_adds`, the references the play would gain, as `Citation.plain/2` prints them: all of a new play's, then only the new one on a re-import, once each though the file gives it twice. Without the "already linked" filter it goes red.
- [x] `mix playcode.import.tei --dry-run` prints ", adds N reference(s)" on the play's line and one "+ citation" line each (`Mix.Task.rerun/2` test); the admin import page lists them in the card that asks before replacing a play (LiveView test). A new play imports without a card, so only the dry run shows its additions.
- [x] Shared with the import: `Bibliography.linked_entry_ids/1`, and the validity check that skips a reference.
- [x] Spanish: "Añade %{count} referencia(s) a la bibliografía:".
- [x] Commit: `feat(import): the preview lists the references an import would add`

### Task 7: Measure, then docs

- [x] On dev: export each of the 115 plays with a bibliography, read the file back, compare every link's description, volume and pages with the database, and preview importing the file in place. First run: 3 plays read back differently and 10 would gain references. Two causes, both fixed test first: (1) a space after italics ("<<Adonis y Venus>> : hacia"): the bibliography's inline fields now go out on one line (`inline_element/3`) and the parser reads them as they run (`running_text/1`, no space added between pieces); (2) Postgres's `\s` misses the non-breaking spaces FileMaker left in titles, so candidates are filtered in Elixir with `Entry.collapse/1`. After: 2,804 links on 115 plays, 0 differ, 0 would be added.
- [x] Dry run of EMOTHE0784 *Le Favori*'s source file against dev: 0 references to add.
- [x] Round-trip page: the bibliography row reads "Yes" from TEI, note 9 rewritten, the "references lost" tally and the "read the bibliography back" next step gone; backlog item moved to history; `CLAUDE.md`: the `back` mapping is read, `play_bibliography.origin` may be `tei`, a rebuilt installation does not re-run the FileMaker bibliography import.
- [x] `mix test`, `mix test --include slow`, `mix compile --warnings-as-errors`.
- [x] Commit: `fix(tei): a reference reads back as the database holds it` and `docs: the bibliography comes back from the file`
