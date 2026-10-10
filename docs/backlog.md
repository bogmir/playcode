# Backlog

Open work, moved here from `CLAUDE.md` on 2026-10-10. Done work is in `docs/history.md`; when an
item here is done, move it there with `[x]` and say what was built. Static-site and exporter
items with a longer write-up live in `docs/static-site-improvements.md`.

## Code health

- [ ] **Separate parsing from writing in `TeiParser`** - from the Groxio audit (2026-10-08), never
  recorded until now. `lib/playcode/import/tei_parser.ex` (1,768 lines) creates rows while it walks
  the XML: about 48 `Repo`/context calls between `import_file/1`'s transaction (line 78) and the
  end of the file, so no part of the import can be run or tested without a database, and
  `preview_import/1` reads the tree a second way instead of reusing the parse. The audit's advice
  was to do it together with the inline `<stage>`/`<note>` work, which rewrote the same code; that
  work shipped (2026-10-08/09) without it. Shape to copy: `FilemakerSync.plan/3` (pure) against
  `apply_plan/2` (writes), and `Bibliography.Citation` (`parts/2` feeding `plain/2` and `html/2`):
  a pure `parse` from the Saxy tree to plain data (play attrs, characters, divisions, elements,
  notes, places, bibliography), then one function that writes it. The TEI round-trip tests are the
  net: they go through `import_file/1` and stay green across the split. Worth doing before the
  next importer feature (`<app>`, `<lb/>`, `<code>` below)

## Production rollout

- [ ] **Re-import the TEI files for notes and inline stages** - deploying this does not move any note out of a line; every play already in the database still has its notes pasted into its lines until its TEI file is re-imported (`mix playcode.import.tei --force` in dev; on Fly `Playcode.Release` has no TEI import, so re-upload the files at `/admin/plays/import`, which updates the play in place). Re-import every TEI file whose `<body>` holds a `<note>`, or a `<stage>` inside an `<l>`, `<p>` or `<seg>` (20 and 59 plays in the fixture corpus; production may hold more; simplest: every file), and do it before the first Generate, whose full rebuild the changed site fingerprint forces anyway. The same re-import carries the inline stage directions (`play_elements.content`), so one re-upload of the TEI files does both, and a play with stages that is not re-imported keeps their words pasted into its lines; the dev command is unchanged, and `--force` is run only with the project owner's go-ahead.

## High Priority

- [ ] **Render** — `render.yaml` and `Dockerfile.render` exist but the blueprint has never been applied

## Medium Priority

- [ ] **Stage direction navigator** (`« N / M »`) - client-side JS hook to scroll between stage directions in play text

## Found by the corpus round trip (2026-10-09)
Method: the 370 production TEI files (`doc/tei_corpus/`) imported into `playcode_dev`, the 360 whose code matches their file name exported again with `TeiXml.generate/1`, and every element and attribute counted in both (per section, `parent>child`). Counts below are source totals over the 360 unless they say otherwise. Nothing here is fixed yet; each is a decision or a project of its own.

**Text corrupted on import (readers see it)**
- [ ] **`<app>` (critical apparatus) is pasted into the line** - 604 entries in 6 plays (EMOTHE0560 212, 0460 127, 0187 98, 0010 94, 0530 63, 0435 10), `type` substantive or orthographical, each a `<lem wit>`, `<rdg wit>`s and often a `<note>`. `text_content/2` reads all of it, so "Barnardo.<app><lem>Barnardo.</lem><rdg>Barnardo?</rdg></app>" exports as "Barnardo. Barnardo. Barnardo?". In most entries the lemma repeats the word just before the `<app>` (the base text stands outside it); in some the `<lem>` is the only copy of the word, and a few have readings only. Likely fix, the same shape as notes: take the `<app>` out of the text, keep a `<lem>` that is the only copy in the line, and store the entry anchored at its offset (a note of type `apparatus` with its readings and witnesses as data, shown as a pop-up and written back as `<app>`). The witnesses it cites are `listWit` (S3). Analysis and the design agreed so far: `docs/tei-apparatus-and-code.md`; questions for the project: `docs/stakeholder/variantes-y-codigo.html`
- [ ] **`<code>` holds literal HTML, shown as text** - 1,211 in 7 plays (EMOTHE0010 Hamlet 1,022; EMOTHE0503 80; the Spanish Tragedy family 0111, 0112, 0307, 0218 about 108; 0239 1), only four strings: `<sup>`, `</sup>`, `<span class="folio">`, `</span>`. An ad hoc apparatus: superscript witness sigla (F, Q2, Q4) and Folio-only passages, as in `O God, <code>&lt;span class="folio"&gt;</code><code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>O…`. Stored as text, so 236 lines in 8 plays read "`<sup> Q4 </sup> [Draws his sword.]`". Stripping the tags alone would glue the sigla to the words ("FOF God"). Options: turn the four strings into inline markup on import (a superscript marker like `<<…>>`, and a class for the Folio span), or have the editors re-encode the 7 files in TEI (`<hi rend="sup">`, `<app>`). Undecided. Four uses, each its own choice (Hamlet's Folio-only text, which the old site hid; *The Spanish Tragedy*'s Q4 Additions; *The Rover*'s Aside/Exit labels; a typo in *Mariamne*): `docs/tei-apparatus-and-code.md` and `docs/stakeholder/variantes-y-codigo.html`
- [ ] **`<lb/>` is flattened to a space** - 26,571 inside body paragraphs in 178 plays, 3,936 in front matter, 634 in the back. Two uses. (1) Prose lineation, 40 plays: `<p n="4">` carries the number of the paragraph's first printed line and each `<lb n="5"/>` marks where the next line of the printed edition starts (EMOTHE0313 *The Way of the World*), the prose equivalent of verse numbers, for citing prose by line; together with `p@n` (49,423 lost in 81 plays) it is lost, so prose has no edition line numbers. (2) Real line breaks, about 10,800 bare `<lb/>`: letters, songs and verse quoted in prose, verse quoted in notes, dedications in front matter; these should render as a break. A fix keeps both in `content`, like the stage markers: a break as a marker rendered `<br>`, a numbered `<lb n>` as a line start with its number in the margin

**Data dropped on import, to recover from the TEI** (none of the FileMaker exports in `doc/` holds it)
- [ ] **`teiHeader/fileDesc/notesStmt/note`** - an editor's note on the edition, 16 notes in 15 plays ("El epílogo figura en la edición de Ferrara de 1581…")
- [ ] **`front/set`** - the scene of the action, 15 plays (`<set><head>SCENE:</head><p>An English wood and Clunch's house…</p></set>`)
- [ ] **`castItem/actor`** - the original cast, 14 actors in 3 plays ("Mr. Betterton")

**Data dropped on import, belonging to a FileMaker slice**
- [ ] **`revisionDesc/change`** - who revised the TEI and when, 341 plays (`<change><date>2021</date><persName>Muñoz Pons, Carlos</persName> Revisión de la obra en formato TEI-XML</change>`): credits, S7
- [ ] **`sourceDesc/listWit/witness`** - 10 witnesses in 1 play (EMOTHE0460, with `variantEncoding`): S3

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
Questions only the stakeholders can answer, recorded in `docs/static-site-improvements.md`, "Awaiting the project":
- [ ] **Adaptations are labelled "translation"** - `Components.kind/1` calls every `relationship_type` a translation, `adaptacion` and `refundicion` included
- [ ] **Verse-form families** - the romance / Spanish stanzas / Italianate grouping in `Metrics` `@families` needs the philologists' confirmation
- [ ] **Labels for the other note types** - 11 of the dev corpus's 17 note types (`falta_tipo`, `latinismo`, `toponimo_accion`, …) have no label, read "Note", and share one option in the Notes pages' type filter

## Low Priority / Future

- [ ] **"Review character in text" UI** — admin page to review and assign/reassign `character_id` (the `who` attribute) on speeches across an entire play. Researchers need to: (1) define character identifiers (`xml_id`, the "acrónimo" e.g. `don_diego`) in the dramatis personae, (2) associate each `<speaker>` with a character to generate `<sp who="#don_diego">`, and (3) bulk-review all speech-character associations throughout the play. Character CRUD and import-time `who` resolution already exist; what's missing is the review/bulk-assign UI.
- [ ] **Places Phase 2** — in-text mentions (`<placeName ref>` in the body, an `element_places` table and the tagging UI), map rendering from the stored coordinates, catalogue browse-by-place, multiple authority links per place, and the FileMaker `pub_LugAccion` import
- [ ] **FileMaker import (S3, S5-S8)** — witnesses, historical performances, character reconciliation, credits, genre. Roadmap: `docs/superpowers/plans/2026-08-01-filemaker-import-slices.md`. Governing rule: the export is a bootstrap, not a dependency — every field it carries gets a permanent column *and* an admin form. As with S2, `/admin/filemaker` needs no change for these — it already renders whatever `sets` and `conflicts` contain
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
