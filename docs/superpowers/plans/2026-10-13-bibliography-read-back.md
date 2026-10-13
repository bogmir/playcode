# Reading the Bibliography Back: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A play imported from a TEI file gets its bibliography back from `<back>`: shared references recognised by their description, the play's own volume and pages on its link, nothing in Playcode changed or removed, and new references added on every import.

**Architecture:** The file stays a plain bibliographic description (no FileMaker or Playcode identifier). `Bibliography.Entry` holds the TEI type tables both directions use; `Bibliography.description/1` gives an entry in the file's terms, which is what a reference is matched on. The parser reads `biblStruct`s into descriptions; `TeiImport` matches or creates entries and links them, after the text, on every import; `preview_import/1` reports what it would add.

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
| `lib/playcode/bibliography/entry.ex` | the TEI type tables (`@list_types`, `@bibl_types` from `TeiXml`), both directions |
| `lib/playcode/bibliography.ex` | `description/1`; `find_identical/2` |
| `lib/playcode/bibliography/link.ex` | moduledoc: `origin` may be `"tei"` |
| `lib/playcode/export/tei_xml.ex` | the tables from `Entry`; the link's volume and pages as `citedRange` |
| `lib/playcode/import/tei_parser.ex` | `back` → `bibliography: [%{description, volume, pages}]` |
| `lib/playcode/import/tei_import.ex` | `write_bibliography/2`; `preview_import/1` lists the references it would add |
| admin import page, `mix playcode.import.tei --dry-run` | print the references an import would add |
| tests | `tei_roundtrip_test.exs`, `export/tei_xml_test.exs`, `export/tei_validator_test.exs`, `import/tei_import_test.exs`, the import page's and the mix task's tests |
| docs | round-trip page, backlog, history, `CLAUDE.md` (TEI mappings, the `origin` values) |

### Task 1: The TEI type tables in `Bibliography.Entry`

Pure refactor; the export's output does not change.

- [ ] Move `@list_types` and `@bibl_types` from `TeiXml` to `Bibliography.Entry`, with `tei_list(kind)`, `kind_from_tei_list(type)`, `tei_type(pub_type)`, `pub_type_from_tei(type)`.
- [ ] `TeiXml` calls them. The bibliography tests in `export/tei_xml_test.exs` stay green unchanged, which is the proof.
- [ ] Commit: `refactor(bibliography): the TEI type tables live with the entry`

### Task 2: The play's own volume and pages in `citedRange`

- [ ] Reverse the test "a modern edition: the play's own volume and pages…" in `export/tei_xml_test.exs`, with a comment saying why: the link's `volume` 5 and `pages` 2366-2466 are `citedRange`s at the end of the `biblStruct`, and the entry's `volume` 1 is a `biblScope` again. Watch it fail.
- [ ] `build_monogr/2` writes only the entry's `biblScope`s; `build_bibl_struct/1` appends `citedRange[@unit="volume"|"page"]` from the link, after `series`, `note` and `ptr`.
- [ ] Schema: the bibliography test in `tei_validator_test.exs` already links a modern edition with its own volume and pages; run it with `--include slow`.
- [ ] Commit: `feat(tei): a play's own volume and pages in an edition are a citedRange`

### Task 3: `Bibliography.description/1`

- [ ] Test (in `tei_roundtrip_test.exs`, describe "the bibliography"): for an entry of every publication type, with every field filled, a URL with a stray ". " and a `volumes_total`, `description(entry)` equals what Task 4's reader gives for that entry's `biblStruct`. Write it now against a stub reader; it fails.
- [ ] `description/1`: the public fields as the file carries them, each whitespace-collapsed, nil for blank; `url` only when `build_bibl_struct/1` would write it (share that predicate); `volumes_total` as written in "N vols.". Researchers' `note` is not part of it.
- [ ] Commit with Task 4.

### Task 4: Reading `<back>`

- [ ] Parser test (purity): a play with a `back/div[@type="bibliografia"]` reads without the database; add every new app call to `@pure_helpers`.
- [ ] `TeiParser` gives `bibliography: [%{description: map, volume: _, pages: _}]` from every `listBibl/biblStruct` under a `div[@type="bibliografia"]` in `back`; `kind` from the `listBibl`, the rest from the `biblStruct`. A `div` holding `p` or `bibl` (the seven prose bibliographies) gives nothing: test with EMOTHE0310's shape.
- [ ] Task 3's test goes green.
- [ ] Commit: `feat(tei): the parser reads the bibliography`

### Task 5: Importing it

Tests first, all through `import_tei!/1` and `Playcode.Bibliography`:

- [ ] Every publication type comes back: entries' fields, the link's volume and pages, `origin: "tei"`. (Fails: nothing is imported yet.)
- [ ] Two plays' files with the same reference give one entry with two links.
- [ ] A re-import adds a reference new to the file, and changes nothing else: an entry corrected in Playcode is not undone, a link typed by hand stays, the order of the play's links is unchanged.
- [ ] An older file's version of a corrected reference is added as a new entry (the known gap, asserted so a change of rule is a decision).
- [ ] A `biblStruct` that cannot become an entry (no kind, nothing to name it) is skipped, and the rest of the play imports.
- [ ] Researchers' notes stay out of the file and come back nil.

Then:

- [ ] `Bibliography.find_identical(description, play_id)`: the play's own links first, then any entry with the same `monogr_title` (else `analytic_title`) in SQL, compared in full with `description/1`; the oldest of several.
- [ ] `TeiImport.write_bibliography(refs, play)`, after the text, on first import and re-import alike: link (`Bibliography.link_entry/3`, `origin: "tei"`, set on the struct) when found and not yet linked, else `create_entry_for_play/3`; a changeset error is logged and skipped, never `Repo.rollback`.
- [ ] Refactor while green: one place decides "same reference".
- [ ] Commit: `feat(tei): a play's bibliography comes back from its file`

### Task 6: The preview lists what would be added

- [ ] Test: `TeiImport.preview_import/1` on a file with one known and one new reference reports the new one only (title, author, year), for a new play and for a re-import.
- [ ] The admin import page and `mix playcode.import.tei --dry-run` print them: test through the LiveView and `Mix.Task.rerun/2`.
- [ ] Commit: `feat(import): the preview lists the references an import would add`

### Task 7: Measure, then docs

- [ ] On dev: export each of the 115 plays with a bibliography, read the file back, and compare every link's description, volume and pages with the database. Expected differences only: researchers' notes, non-`http(s)` URLs. Record the numbers.
- [ ] Dry run of the corpus re-import for EMOTHE0784 *Le Favori*: 0 references to add.
- [ ] Round-trip page: the bibliography row, Read from TEI "Yes", note 9 rewritten (what a rebuild gives up, from the spec); backlog item moved to history; `CLAUDE.md`: the `back` mapping is read, `play_bibliography.origin` may be `tei`, and a rebuilt installation does not re-run the FileMaker bibliography import.
- [ ] `mix test`, `mix test --include slow`, `mix compile --warnings-as-errors`.
- [ ] Commit: `docs: the bibliography comes back from the file`
