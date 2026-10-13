# Reading the bibliography back from the TEI file

**Status:** designed, 2026-10-13. Plan: `../plans/2026-10-13-bibliography-read-back.md`.

The export writes a play's bibliography into `<back>` as structured TEI (S4,
`2026-10-07-s4-bibliography-design.md`) and the import ignores it, so a play rebuilt from its file
comes back with none: 2,804 links on 115 plays in dev, the largest loss on the round-trip page
(`docs/stakeholder/ida-y-vuelta.html`). This design reads it back.

## The model, unchanged

Plays and references are many-to-many: `bibliography_entries` holds each work once, shared by every
play citing it, and `play_bibliography` is the join table, one row per play and entry (unique), with
what belongs to that pairing alone: the play's `volume` and `pages` in an edition, a researcher's
`note`, `origin`. Dev: 2,732 entries, 2,804 links, 24 entries linked by more than one play. No table
or column is added; `play_bibliography.origin` gains the value `tei`.

## Decisions

From the project owner, 2026-10-13:

| Question | Answer | What it means here |
|---|---|---|
| Identifiers in the file | None of FileMaker's or Playcode's; only play codes (`EMOTHE0312`) and what TEI defines | No record numbers, no database ids in `<back>`. A reference is recognised by its description |
| Shared references | One entry, linked by every play citing it | Importing a play finds the entry Playcode already has instead of copying it |
| A reference already in Playcode | The file only adds what is missing | An import never changes or removes an entry or a link |
| Later imports | New references are still added | Every import adds, the first and every re-import |
| The play's own volume and pages | In their own element, apart from the edition's | `citedRange` for the link's, `biblScope` for the entry's |

## The file

Unchanged but for one thing. Today `build_monogr/2` writes the link's volume and pages in place of
the entry's (`biblScope`), so a reader cannot tell whose "volume 5" it is. From now on:

- the entry's `volume`, `issue` and `pages` stay in `monogr/biblScope`, as now;
- the link's `volume` and `pages` go in `biblStruct/citedRange[@unit="volume"|"page"]`, after the
  `series`, `note` and `ptr` (TEI's order: analytic, monogr and series, then notes, pointers and
  cited ranges). `citedRange` is TEI's "the part of a work being cited".

Researchers' notes (`entries.note`, `play_bibliography.note`) stay out, as before: the file is
published.

## Reading

The parser reads every `back//div[@type="bibliografia"]/listBibl/biblStruct` and nothing else, so the
seven source files with a bibliography in prose (EMOTHE0310, 0451, 0488, 0489, 0644, 0652, 0686) give
none. Each `biblStruct` becomes `%{description: map, volume: _, pages: _}`:

- `kind` from the `listBibl/@type` (`ediciones_modernas` → `modern_edition`…), `pub_type` from
  `@type`, `language` from `@xml:lang`, through the maps the export uses, moved to
  `Bibliography.Entry` so both directions read one table;
- the people and titles of `analytic` and `monogr`, `original_title`, `siglum`, `edition`, the
  imprint (`pub_place`, `publisher`, the year's text, the access date), `volumes_total` from
  `extent` ("6 vols." → "6"), the entry's `biblScope`s, `series`, `public_note`, `url` from `ptr`;
- the link's `volume` and `pages` from `citedRange`.

## Recognising a reference

Two descriptions are the same reference when **every public field is identical once whitespace is
collapsed**: kind, type, language, people, titles, imprint, volumes, pages, series, siglum, public
note, URL. Not folded for case or accents: "identical" means a correction is a different
description.

The comparison is between descriptions as the file carries them, so a field the export does not
write faithfully cannot make a false difference: `Bibliography.Entry.description/1` gives an entry's
description in the file's terms (the URL only when it is an `http(s)` address, as `build_bibl_struct`
writes it; `volumes_total` as its number), and the parser gives the file's in the same terms. A test
holds them together: for every publication type, `Entry.description(entry)` equals what the parser reads
from the export of that entry.

Where to look, in order:

1. the entries the play already links;
2. any entry, found by its title (`monogr_title`, else `analytic_title`, in SQL), then compared in
   full. Where several entries are identical (FileMaker copies), the oldest is taken.

## Importing

On every import, after the text, for each reference of the file:

1. the play already links an identical entry: nothing;
2. another entry is identical: the play is linked to it (`origin: "tei"`, the volume and pages of
   `citedRange`);
3. none: a new entry and its link are made (`Bibliography.create_entry_for_play/3`), `origin: "tei"`.

Nothing is changed or removed: no entry is updated from a file, no link is deleted, and a re-import
does not touch the links the play has. An entry that fails its changeset (no kind, nothing to name
it) is skipped and logged, not a rollback of the play.

**The one way a duplicate gets in:** an older file re-imported after a curator corrected a reference
in Playcode. Its description no longer matches the corrected entry, so it comes in as a new one.
Against that, **the import preview lists the references an import would add** (`preview_import/1`,
shown on the admin import page and by `--dry-run`), so the stale one is seen before the import is
confirmed, and unlinking it deletes it (`Bibliography.unlink/1`, no orphans).

## What a rebuild from files gives up

- Researchers' notes on entries (137 in dev) and links (15), as on purpose.
- FileMaker numbers: they stay in the installation that imported them. The FileMaker
  bibliography import counts a play with `tei` links as imported (`imported_play_ids/0`), so
  a run on a rebuilt installation does not bring FileMaker's copies in beside the file's.
- FileMaker's identical copies merge: 72 entries in dev are word-for-word copies of another, in 32
  groups (*The Chief British Dramatists Excluding Shakespeare*, 1924, six times, once per play). A
  rebuild makes each group one shared entry; in 4 cases a play links two copies of one and comes back
  with one link.
- A URL that is not an `http(s)` address (FileMaker's ". http://…"), which the export leaves out.

## Rollout

- Production's source files carry no structured bibliography but one: EMOTHE0784 *Le Favori*, whose
  nine `biblStruct` are the nine entries FileMaker gave it (Playcode's own format). The planned
  re-import of the TEI files (`docs/backlog.md`, *Production rollout*) will match them; its dry run
  must show "0 references to add" for *Le Favori*, and any other count is looked at first.
- The export change moves the link's volume and pages, so every play with a bibliography gets a
  changed `.xml` and the next Generate republishes it.

## Tests

Round trips in `tei_roundtrip_test.exs`, through `TeiImport.import_file/1` and the contexts' public
functions:

- every publication type and field comes back (the bibliography of `export/tei_xml_test.exs`);
- the play's own volume and pages come back on the link, the edition's on the entry;
- one reference in two plays' files is one entry with two links;
- a re-import adds a reference new to the file and changes nothing else; a corrected entry is not
  undone; a link typed by hand stays;
- an older file's version of a corrected reference is added, and the preview lists it;
- researchers' notes stay out; a prose bibliography gives no entries;
- `description/1` agrees with the parser for every publication type.

A schema test for `citedRange`, and a measurement on dev: export the 115 plays, read each file back
and compare every link's description, volume and pages with the database.
