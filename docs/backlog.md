# Backlog

Open work, moved here from `CLAUDE.md` on 2026-10-10. Done work is in `docs/history.md`; when an
item here is done, move it there with `[x]` and say what was built. Static-site and exporter
items with a longer write-up live in `docs/static-site-improvements.md`.

## Production rollout

- [ ] **Re-import the TEI files for notes and inline stages** - deploying this does not move any note out of a line; every play already in the database still has its notes pasted into its lines until its TEI file is re-imported (`mix playcode.import.tei --force` in dev; on Fly, copy the files to the machine with `flyctl ssh sftp put` and run `Playcode.Release.import_tei(dir, dry_run: true, force: true)`, then without `dry_run`. The dry run counts, per play, the hand edits to its text since its last import that the forced re-import would undo). Re-import every TEI file whose `<body>` holds a `<note>`, or a `<stage>` inside an `<l>`, `<p>` or `<seg>` (20 and 59 plays in the fixture corpus; production may hold more; simplest: every file), and do it before the first Generate, whose full rebuild the changed site fingerprint forces anyway. The same re-import carries the inline stage directions (`play_elements.content`), so one re-upload of the TEI files does both, and a play with stages that is not re-imported keeps their words pasted into its lines; the dev command is unchanged, and `--force` is run only with the project owner's go-ahead.

## Round trip (2026-10-11)

A play exported to TEI and imported into an empty database must come back whole (`CLAUDE.md`, *The
TEI file is a complete copy of a play*). Measured on all 394 plays in dev by exporting each one and
importing the file as a new play; the table, for the project, is `docs/stakeholder/ida-y-vuelta.html`,
and the technical detail is here.

- [ ] **The bibliography is not read back** - the export writes `<back>` as `listBibl/biblStruct` and the import ignores it: 2,804 links on 115 plays lost (S4 deferred it). Open questions: matching shared entries, a `tei` origin for links, where volume and pages land. The seven original files with a prose bibliography (EMOTHE0310, 0451, 0488, 0489, 0644, 0652, 0686) must not become entries
- [ ] **Curated play columns are not in the file** - a fresh import comes back as a draft (373 plays), with no original for a translation (153), no historical time (109, 38 with a note) and no dating that is only a note (18). Proposed homes, each read back by the import: completeness as `revisionDesc/@status` (`published`/`draft`); the original as `notesStmt/relatedItem[@type="original"]` pointing at its code, and the kind as `title/@type` beyond `traduccion` (`adaptacion`, `refundicion`); `historical_time` and its note as `settingDesc/setting/time`; a dating in words as `creation/date` with no `@when`; a curated form as `textClass/keywords`. Listed for the project in `docs/stakeholder/ida-y-vuelta.html`, *Into the TEI*
- [ ] **The cast list's heading and a second cast list** - one `<div type="elenco">` with no `<head>` is written: 319 plays lose the heading, and 5 plays with a cast list per act or part (EMOTHE0112, 0283, 0555, 0714, fixture 0277) come back with one and their characters reordered. The heading is a plain `<head>` to write back. The second list is a gap in Playcode itself: the parser flattens every `castList` into the play's characters and keeps the `elenco` divisions empty, so no row records which list a character is in, and the play page prints every character under each heading. Fix the model (a character's `elenco` division) before the export
- [ ] **Witnesses and bibliography lose their FileMaker key** - `filemaker_id` (`T03:…`, `T12:…`/`T04:…`) is not in the file (510 witnesses on 107 plays; every bibliography entry), so a file cannot say which FileMaker record a row came from. Proposed: an `idno[@type="filemaker"]` in the witness's `bibl` and in the entry's `monogr`, read back into `filemaker_id`, with `origin` following from it. Line breaks in witness fields come back as spaces (25 fields)
- [ ] **New FileMaker slices go into the TEI from the start** - S5 performances as `front/performance` (its cast as `castList/castItem/actor`, the information source as a `bibl`), S8 genre as `textClass/keywords` or `catRef`, S9b places as the `settingDesc` Playcode already writes; each slice's export and import ship together, and its row goes into `docs/stakeholder/ida-y-vuelta.html`
- [ ] **Small losses** - two digital editors come back as `editor` (6 rows, 3 plays), a source's `editor_role` "canon60" (EMOTHE0727), the attribution "fiable" (EMOTHE0653), adjacent italics merged (6 elements) and an empty `<<>>` in 4 notes
- [ ] **Trailers are on no page** - the static site, HTML, PDF, EPUB and the comparison have no clause for `trailer` and print nothing: 224 trailers in 131 plays, in the `.xml` but on no page. Only `/plays/:code` shows them
- [ ] **A test that holds the round trip** - the fixpoint test (`tei_roundtrip_test.exs`, "exporting, re-importing and exporting again changes nothing") compares XML, so data the export never writes passes it. Wanted: a play with every feature filled, exported, imported as a new play, and read back through the contexts' public functions; it fails on each gap above until it is closed
- [ ] **`mix playcode.import.tei` reads the FileMaker fixtures as TEI** - `test/fixtures/**/*.xml` includes `test/fixtures/filemaker/ctce_dades/`, the "8 unreadable" of every run

## High Priority

- [ ] **Render** — `render.yaml` and `Dockerfile.render` exist but the blueprint has never been applied

## Medium Priority

- [ ] **Stage direction navigator** (`« N / M »`) - client-side JS hook to scroll between stage directions in play text

## Found by the corpus round trip (2026-10-09)
Method: the 370 production TEI files (`doc/tei_corpus/`) imported into `playcode_dev`, the 360 whose code matches their file name exported again with `TeiXml.generate/1`, and every element and attribute counted in both (per section, `parent>child`). Counts below are source totals over the 360 unless they say otherwise. Nothing here is fixed yet; each is a decision or a project of its own.

**Text corrupted on import (readers see it)**
- [ ] **`<app>` (critical apparatus) is pasted into the line** - 604 entries in 6 plays (EMOTHE0560 212, 0460 127, 0187 98, 0010 94, 0530 63, 0435 10), `type` substantive or orthographical, each a `<lem wit>`, `<rdg wit>`s and often a `<note>`. `text_content/2` reads all of it, so "Barnardo.<app><lem>Barnardo.</lem><rdg>Barnardo?</rdg></app>" exports as "Barnardo. Barnardo. Barnardo?". In most entries the lemma repeats the word just before the `<app>` (the base text stands outside it); in some the `<lem>` is the only copy of the word, and a few have readings only. Likely fix, the same shape as notes: take the `<app>` out of the text, keep a `<lem>` that is the only copy in the line, and store the entry anchored at its offset (a note of type `apparatus` with its readings and witnesses as data, shown as a pop-up and written back as `<app>`). The witnesses it cites are `listWit` (S3). Analysis and the design agreed so far: `docs/tei-apparatus-and-code.md`; questions 1-4 for the project: `docs/stakeholder/preguntas.html`
- [ ] **`<code>` holds literal HTML, shown as text** - 1,211 in 7 plays (EMOTHE0010 Hamlet 1,022; EMOTHE0503 80; the Spanish Tragedy family 0111, 0112, 0307, 0218 about 108; 0239 1), only four strings: `<sup>`, `</sup>`, `<span class="folio">`, `</span>`. An ad hoc apparatus: superscript witness sigla (F, Q2, Q4) and Folio-only passages, as in `O God, <code>&lt;span class="folio"&gt;</code><code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>O…`. Stored as text, so 236 lines in 8 plays read "`<sup> Q4 </sup> [Draws his sword.]`". Stripping the tags alone would glue the sigla to the words ("FOF God"). Options: turn the four strings into inline markup on import (a superscript marker like `<<…>>`, and a class for the Folio span), or have the editors re-encode the 7 files in TEI (`<hi rend="sup">`, `<app>`). Undecided. Four uses, each its own choice (Hamlet's Folio-only text, which the old site hid; *The Spanish Tragedy*'s Q4 Additions; *The Rover*'s Aside/Exit labels; a typo in *Mariamne*): `docs/tei-apparatus-and-code.md`; questions 5-8 in `docs/stakeholder/preguntas.html`
- [ ] **`<lb/>` is flattened to a space** - 26,571 inside body paragraphs in 178 plays, 3,936 in front matter, 634 in the back. Two uses. (1) Prose lineation, 40 plays: `<p n="4">` carries the number of the paragraph's first printed line and each `<lb n="5"/>` marks where the next line of the printed edition starts (EMOTHE0313 *The Way of the World*), the prose equivalent of verse numbers, for citing prose by line; together with `p@n` (49,423 lost in 81 plays) it is lost, so prose has no edition line numbers. (2) Real line breaks, about 10,800 bare `<lb/>`: letters, songs and verse quoted in prose, verse quoted in notes, dedications in front matter; these should render as a break. A fix keeps both in `content`, like the stage markers: a break as a marker rendered `<br>`, a numbered `<lb n>` as a line start with its number in the margin. How each should show: questions 9 and 10 in `docs/stakeholder/preguntas.html`

**Data dropped on import, to recover from the TEI** (none of the FileMaker exports in `doc/` holds it)
- [ ] **`teiHeader/fileDesc/notesStmt/note`** - an editor's note on the edition, 16 notes in 15 plays ("El epílogo figura en la edición de Ferrara de 1581…")
- [ ] **`front/set`** - the scene of the action, 15 plays (`<set><head>SCENE:</head><p>An English wood and Clunch's house…</p></set>`)
- [ ] **`castItem/actor`** - the original cast, 14 actors in 3 plays ("Mr. Betterton")

**Data dropped on import, belonging to a FileMaker slice**
- [ ] **`revisionDesc/change`** - who revised the TEI and when, 341 plays (`<change><date>2021</date><persName>Muñoz Pons, Carlos</persName> Revisión de la obra en formato TEI-XML</change>`): credits, S7

**Other losses**
- [ ] **`sourceDesc/bibl/distributor`** - who supplied the digital text the edition was made from, 152 plays: *Canon 60* 30, *Gallica* 15, *Internet Shakespeare Editions* 6, the TC/12 groups (PROLOPE, DICAT, ROJAS ZORRILLA…), *Project Gutenberg*, *Biblioteca Virtual Miguel de Cervantes*…, and a placeholder *Texto base* in 59. Provenance of the source text; a `distributor` column on `play_sources` would hold it
- [ ] **`sp@who` that names no cast role** - 2,508 references in 29 plays, errors in the source files: case or spelling variants (`#D’Amville` against `#D’AMVILLE`, 369), comma-joined lists (`#ERPINGHAM,GOWER,FLUELLEN,MACMORRIS,JAMY`). The speech keeps its label but loses its character, and with it the statistics. The "Review character in text" page (Low Priority) is where they get fixed
- [ ] **`castItem@ana` groups** - `ana="grupo"` 92 and `ana="grupo oculto"` 468 (a role that is a group: soldiers, servants) are imported as hidden or nothing, so the group is lost. Character reconciliation, S6
- [ ] **The cast list's own heading** - "PERSONNAGES", "INTERLOCUTORI", "Le persone che parlano": 323 lost
- [ ] **Front matter flattened** - italics in editorial notes and roles (about 950 `<emph>`), and their unnumbered `<note>`s (about 270)
- [ ] **Back matter other than the bibliography** - 16 plays: two cast lists, some verse, headed sections
- [ ] **`xml:id` on speeches, paragraphs, stages, scenes, segments and `lb`** - about 460,000 dropped; only verse lines (`line_id`) keep theirs. `seg@next` (9,257), which links the halves of a split segment, goes with them. `stage@n` (375), `seg@type` other than aside (352) and `trailer@xml:id` (194) too
- [ ] **Admin: `stage_type` and `line_id`** - imported and exported but no control in the content editor (a stage direction's type: entrance, exit, delivery…; a verse line's `xml:id`)
- Dropped on purpose, fine as is: `classCode` (the CDU number, which follows the language), `encodingDesc/appInfo` (FileMaker and Oxygen versions), `editionStmt/edition` and `titlePage` (derived from title and author), empty act `<head/>`s (220)

## Awaiting the project (static site)
Questions only the stakeholders can answer, recorded in `docs/static-site-improvements.md`, "Awaiting the project", and asked as questions 15-17 in `docs/stakeholder/preguntas.html`:
- [ ] **Adaptations are labelled "translation"** - `Components.kind/1` calls every `relationship_type` a translation, `adaptacion` and `refundicion` included
- [ ] **Verse-form families** - the romance / Spanish stanzas / Italianate grouping in `Metrics` `@families` needs the philologists' confirmation
- [ ] **Labels for the other note types** - 11 of the dev corpus's 17 note types (`falta_tipo`, `latinismo`, `toponimo_accion`, …) have no label, read "Note", and share one option in the Notes pages' type filter

## Low Priority / Future

- [ ] **"Review character in text" UI** — admin page to review and assign/reassign `character_id` (the `who` attribute) on speeches across an entire play. Researchers need to: (1) define character identifiers (`xml_id`, the "acrónimo" e.g. `don_diego`) in the dramatis personae, (2) associate each `<speaker>` with a character to generate `<sp who="#don_diego">`, and (3) bulk-review all speech-character associations throughout the play. Character CRUD and import-time `who` resolution already exist; what's missing is the review/bulk-assign UI.
- [ ] **Places Phase 2** — in-text mentions (`<placeName ref>` in the body, an `element_places` table and the tagging UI), map rendering from the stored coordinates, catalogue browse-by-place, multiple authority links per place, and the FileMaker `pub_LugAccion` import
- [ ] **FileMaker import (S5-S8)** — historical performances, character reconciliation, credits, genre (S3, witnesses, is done: `docs/history.md`). Roadmap: `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`. Governing rule: the export is a bootstrap, not a dependency — every field it carries gets a permanent column *and* an admin form. As with S2, `/admin/filemaker` needs no change for these — it already renders whatever `sets` and `conflicts` contain
- [ ] **TEI import improvements** - handle more TEI variants, better error reporting
- [ ] **Full-text search** with PostgreSQL tsvector
- [ ] **TEI validation** - validate exported XML against TEI schema
- [ ] **Responsive mobile design** refinements
- [ ] **API endpoints** for programmatic access
- [ ] **Batch export** - export multiple plays at once
- [ ] **Custom OTel spans** for TEI import, export, statistics computation
- [ ] **Line number frequency control** - "show every N lines" option (original Artelope had "Mostrar cada 5")
- [ ] **HTML email templates** - replace plain-text bodies in `user_notifier.ex` with `html_body/1` using `Phoenix.Swoosh` for branded transactional emails
- [ ] **Login audit log** - store failed/successful login attempts in a DB table for security review
- [ ] **Session activity tracking** - add `last_active_at` to users table, update on each request
