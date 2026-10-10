# S3 — Witnesses (testimonios)

**Status:** design, 2026-10-10. Slice S3 of `../plans/2026-08-01-filemaker-import-slices.md`,
which holds the measurements this design rests on (S3 section). Modelled on S4,
`2026-10-07-s4-bibliography-design.md`: same import shape, same renderer pattern, same surfaces.

A play's witnesses are the manuscripts and early printings its text survives in: Hamlet's Q1
(1603), Q2 (1604) and First Folio (1623); Lope's autograph of *El bastardo Mudarra*. Each play gets
its list, imported once from FileMaker, edited in Playcode from then on, written into the TEI
header and shown on `/plays/:code` and the static site the way emothe.uv.es shows it.

## Why now

- **The data arrived on 2026-10-10:** `T03_ObraTestimonio` and its three lookup tables, in
  `doc/ctce_dades/` (git-ignored). 512 witnesses on 107 plays we hold, all 107 complete.
- **The apparatus needs it.** Every `wit` siglum in the six plays with an `<app>` resolves, to a
  witness here (21) or to a modern edition's `bibliography_entries.siglum` from S4 (21), none to
  nothing. With S3, the `<app>` work (`docs/tei-apparatus-and-code.md`) can point a reading at a
  row instead of a string.
- **TEI drops it today.** EMOTHE0460's `sourceDesc/listWit` is lost on import (CLAUDE.md, *Data
  dropped on import*).

## Decisions

From the project owner, 2026-10-10:

| Question | Answer | What it means here |
|---|---|---|
| Which fields are public | Do what emothe.uv.es does; add to TEI what fits cleanly, but not more | The renderer prints exactly emothe.uv.es's fields. Siglum and type are stored because they fit TEI cleanly; they are not printed. The holding library and the information source are not imported |
| Test rows | Skip them | Record 32 is skipped; so are the 5 empty records |
| `TES2` | Clean it up | The siglum is cleared on its edition; the S4 import learns to drop it (task 0) |
| EMOTHE0530's `1623b`, `1626a`… | Fix them if they are typos | They are not: they are the editor's sigla, editions by year, used consistently in the file's apparatus. Only the `xml:id` needs a rule (see TEI) |
| Jodelle on Spanish witnesses | Unsure | Imported with no attribution and reported (see Import) |

From this design:

- **A one-time import**, as S4. FileMaker is a bootstrap, not a dependency; once imported,
  witnesses are edited in Playcode. A re-run skips plays already imported.
- **Witnesses are their own table, not `play_sources`.** `play_sources` is `sourceDesc/bibl`, the
  edition the digital text was made from (`T07.531_Fuente` in FileMaker). A witness documents the
  text's transmission and has a siglum, a type and a shelfmark.
- **Hand order.** FileMaker's order is its record id, which reproduces the published order on all
  94 checkable versions. It is chronological in most plays but not all (Hamlet lists F4, 1685,
  before Q6, 1676, and Q9 and Q10 before Q8), and emothe.uv.es prints that order, so witnesses
  carry a `position` and the admin can reorder.

## Done when

- `mix playcode.import.witnesses` brings FileMaker's witnesses into the plays we hold.
- Researchers can add, edit, reorder and delete witnesses on `/admin/plays/:id/witnesses`.
- The TEI export carries them in `sourceDesc/listWit`, and the TEI import reads them back:
  export → import → export changes nothing, and EMOTHE0460's `listWit` survives an import.
- `/plays/:code` and the static site's title page list them as emothe.uv.es does.

## The model

```
play_witnesses
  play_id          references plays, on delete cascade
  siglum           Q1, F1, MP, Aut., 1623b; nullable (468 of the 512 have none)
  title            as printed on the witness: "THE Tragicall Historie of HAMLET Prince of Denmarke."
  normalized_title "The Tragical History of Hamlet, Prince of Denmark"
  attribution      the author the witness bears, "Surname, Name" as FileMaker holds it
  pub_place        city, plain text
  publisher        printer or bookseller, plain text: "Ling, Nicholas; Trundell, John"
  date             verbatim: "1603", "1625 ?", "1527/1529", "s. a."
  format           "2º", "4º", "8º", "12º"
  witness_type     see below; nullable
  shelfmark        "BN 16630", "MSS/18072"
  note             the observation; printed
  position         integer, order within the play
  origin           manual | filemaker | tei
  filemaker_id     "T03:<id>"; provenance only
  timestamps
  unique (play_id, siglum) where siglum is not null
```

Every text column is `text`. All values are trimmed and otherwise kept verbatim; `<<…>>` in a
title or note stays, as the app's italics marker.

**`witness_type`** is the leaf of FileMaker's three-level tree (`T03.1`), one column. FileMaker's
"no consta" (not stated) collapses into its parent, which says the same thing:

| Value | FileMaker path | TEI `bibl@type` / `@subtype` |
|---|---|---|
| `manuscript` | manuscrito; manuscrito > no consta | `manuscrito` / — |
| `autograph` | manuscrito > autógrafo | `manuscrito` / `autografo` |
| `copy` | manuscrito > copia | `manuscrito` / `copia` |
| `early_edition` | ediciones antiguas; > no consta | `edicion_antigua` / — |
| `collection` | ediciones antiguas > colección | `edicion_antigua` / `coleccion` |
| `collection_single_author` | … > colección > de autor | `edicion_antigua` / `coleccion_de_autor` |
| `collection_several_authors` | … > colección > de diversos autores | `edicion_antigua` / `coleccion_de_diversos_autores` |
| `loose` | ediciones antiguas > sueltas | `edicion_antigua` / `suelta` |

**Rules:**

- **A witness needs a title, a normalised title or a note.** Every FileMaker record has one of
  the three except the five empty ones (records with no title page carry a normalised title, as
  140, or a note, as 595).
- **A siglum is unique within its play**: it becomes the witness's `xml:id`, and an apparatus
  reading names one witness by it.
- **Change tracking:** the migration adds the `play_row_changed()` trigger, since witnesses show
  on the play's pages. `content_version_test.exs` fails until it does.
- **Not stored:** FileMaker's holding library (`T03.3`, 32 of 512, with test values such as
  `CiudadPrueba`) and information source (`T13`, 297). emothe.uv.es prints neither and neither has
  a clean place in a witness's TEI. The information source can return with S5, which makes `T13`
  a table.

### Rejected

- **`play_sources` with a type column** (the roadmap's first draft). Two different relations in
  one table: the base text's edition would sit in `listWit`, and the witnesses in `sourceDesc/bibl`.
- **Corpus-wide witnesses shared between plays, as S4's entries.** A witness is described for one
  play: the First Folio is a separate FileMaker record on each of its plays, with its own
  observation. Nothing asks for one correction to reach several plays.
- **Two type columns** (medium and kind). One leaf column holds the same information, and the
  TEI pair is derived from it.
- **An integer year.** Nothing sorts by it; `date` is printed verbatim, and TEI's `@when` is
  derived when it is a plain four-digit year.

## Import

### Entry points

As S4:

- `mix playcode.import.witnesses [--dry-run] [--path doc/ctce_dades]`, for dev.
- `Playcode.Release.import_witnesses(dir, opts)`, for Fly: copy the four files with
  `fly ssh sftp`, then `bin/playcode rpc 'Playcode.Release.import_witnesses("/tmp/ctce")'`.

Both call `Playcode.Import.Witnesses`:

- `load(dir)` reads `T03_ObraTestimonio`, `T03.1_TestimonioTipo` (to check the type ids below
  against it) and `T03.2_Atribucion` with `Playcode.Import.FilemakerXml.read/1`.
- `plan(data, plays)` is pure.
- `apply_plan(plan, opts)` writes in one transaction and logs one activity entry per play.
- `report(plan)` returns lines of text for the mix task and the release.

### Matching

As S4: a FileMaker version is a play when `"EMOTHE" <> zero-padded _k_IdObraTitulo` equals
`FilemakerSync.base_code(play.code)`, among `FilemakerSync.all_plays/0` (archived plays excluded).
A base code held by two plays gives both the witnesses. Versions we do not hold are counted.

### Field mapping

| FileMaker (`T03`) | Column |
|---|---|
| `ObrTes_Siglas` | `siglum` |
| `ObrTes_TituloTestimonio` | `title` |
| `ObrTes_TituloNormalizado` | `normalized_title` |
| `_k_IdAtribucion` | `attribution`: `T03.2._tc_Atr_Atribucion` |
| `ObrTes_Ciudad` | `pub_place` |
| `ObrTes_Editorial` | `publisher` |
| `ObrTes_Anyo` | `date` |
| `ObrTes_Formato` | `format` |
| `_k_IdTesTip_Nivel1`/`2`/`3` | `witness_type`: the deepest id set, by the table above (ids 2 `manuscript`, 3 `early_edition`, 4 `manuscript`, 5 `autograph`, 6 `copy`, 7 `early_edition`, 8 `collection`, 9 `loose`, 10 `collection_single_author`, 11 `collection_several_authors`) |
| `ObrTes_SignaturaFI` | `shelfmark` |
| `ObrTes_Observacion` | `note` |
| `_kp_IdObraTestimonio` | `filemaker_id` `"T03:<id>"`; ascending id gives `position` |

Not read: `_k_IdLocalizacion`, `_k_IdFuenteInformacion`, `ObrTes_ComposicionNiveles` (the type
path as text) and `w3_ObrTes_Composicion` (FileMaker's rendering; the test oracle, below).

### Skipped, and counted by reason

`--dry-run` lists the FileMaker ids for each:

- **test record:** 32 (`TituloTestimonio`, siglum `TES`, EMOTHE0203), a module attribute as S4's
  `@test_editions`
- **empty:** no title, normalised title or note: 14, 15, 62 (a format and nothing else), 67, 600
- **siglum already on the play** (a curator's or a TEI witness): the FileMaker witness is skipped

### Attributions dropped

`Jodelle, Étienne` (`T03.2` id 13, FileMaker's first attribution record, and id 123) appears on
11 witnesses of six Spanish plays (EMOTHE0013, 0204, 0358, 0382, 0435, 0560), the autograph of
Lope's *El bastardo Mudarra* among them; emothe.uv.es prints it. The import writes those witnesses
with no attribution and lists them under "attribution dropped" in the report, for curators to
fill. The rule: an attribution naming Jodelle on a play whose `author_name` does not contain
"Jodelle". His own plays (EMOTHE0479, 0657, 0674, 0675, 0749) keep it.

### What a re-run does

- **A play the import has written to is skipped whole**, reported as "already imported", so a
  curator's edits and deletions stay. The marker is the per-play activity log entry
  `apply_plan` writes (`metadata.source` `"filemaker_witnesses"`), which survives a curator
  deleting every witness, as S4 learned.
- Plays imported into Playcode later get their witnesses on the next run.

### Expected result

On dev's 392 plays, measured 2026-10-10 on the dump:

- **508 witnesses on 106 plays**: the 512 on plays we hold, less 4 empty (15, 62, 67, 600).
  EMOTHE0020's only witness is empty, so it gets none.
- 44 with a siglum; 11 attributions dropped.
- The test record (32) and one empty record (14) sit on versions we do not hold; with them, 89
  FileMaker witnesses on 27 versions are counted as not held.

The dry run in task 3 confirms these before anything is written.

## Display

### The renderer

`Playcode.Witnesses.parts/1`, `plain/1` and `html/1`, in the shape of `Bibliography.Citation`:
segments of text with an italic flag, through `InlineMarkup.parts/1`. The admin preview,
`/plays/:code` and the static site all go through it.

**emothe.uv.es's line**, element for element:

```
<i>Title</i>. [Normalised title]. Attribution. City. Publisher. Date. Format. Note. Archivo: Shelfmark.
```

As in S4, deliberate differences from FileMaker's output:

- **An empty field drops out with its punctuation**: no `<i></i>. .`, no `. .` where the
  attribution is blank.
- **No second full stop** after a value that ends in `.`, `?` or `!` (`… Denmarke.</i>.`,
  `First Folio..`, `s. a..`).
- **`Archivo:` is FileMaker's label and is not translated**, like S4's `Ed.` and `Tra.`.

Not printed, as on emothe.uv.es: `siglum`, `witness_type`.

### Where it shows

- **Order:** `position`, one flat list, as emothe.uv.es.
- **`/plays/:code`:** a `#meta-witnesses` section, "Testimonios" in Spanish, placed immediately
  before `#meta-bibliography`, with its sidebar entry (`maybe_add_section`) immediately before
  Bibliography's. That is emothe.uv.es's order: Testimonios, then Ediciones modernas.
- **The static site's title page:** a "Witnesses" section with `id="witnesses"` after "Sources",
  before "Bibliography", and its rail entry after Statistics, before Bibliography.
- **`Catalogue`'s `with_all/2` preloads `witnesses`** in `position` order, as it does `sources`, so
  every page and the TEI export read `play.witnesses`.

## Admin

`/admin/plays/:id/witnesses`, `PlaycodeWeb.Admin.PlayWitnessesLive`:

- **The tab:** "Witnesses" ("Testimonios"), in the play context bar after Sources, before
  Bibliography; `active_tab: :witnesses`.
- **The gate:** `:manage_sources`, which researchers already have. Witnesses are the same kind
  of work as sources, and a new action would add a line to `Authz` for no difference in who may
  do it. A row in `authorization_test.exs`; the path in `accessibility_test.exs`.

### What the page does

- **The list,** in order, each row through `Witnesses.html/1`, with the siglum as a badge when
  set, and icon-only Edit, Move up, Move down and Delete buttons, each with an `aria-label`.
- **New witness** and **Edit** open one modal: siglum, title, normalised title, attribution,
  place, publisher, date, format, type (a select grouped Manuscript / Early edition), shelfmark,
  note. Under the form, the line as it will print, from `apply_changes/1` and `Witnesses.parts/1`.
- **Move up / down** swaps `position` with the neighbour, as `Places.move_play_place/2`.
- **Delete** asks for confirmation.
- **Ids from the browser** resolve through `Witnesses.get_witness/2`, scoped to the play; a gone
  row reloads the list and calls `LiveHelpers.put_gone_flash/1`.
- **The activity log:** `create`, `update` and `delete` on `play_witness`.

**The context,** `Playcode.Witnesses`:

- `list_for_play/1`, by position
- `get_witness/2`, scoped to the play
- `create_witness/1` (appends: `position` is max + 1, never passed by a caller), `update_witness/2`,
  `delete_witness/1`, `move_witness/2`
- `parts/1`, `plain/1`, `html/1`

**Labels:** `PlaycodeWeb.PlayLabels.witness_type_label/1`. The changeset's custom message ("needs a
title, a normalised title or a note") is hand-added to `errors.pot` and the Spanish PO file;
`error_translations_test.exs` fails until it is.

## TEI

### Export

`build_source_desc/1` writes the sources, as today, then `listWit` when the play has witnesses:

```xml
<sourceDesc>
  <bibl>…the play's sources, unchanged…</bibl>
  <listWit>
    <witness xml:id="Q1" n="Q1">
      <bibl type="edicion_antigua" subtype="suelta">
        <title>THE Tragicall Historie of HAMLET Prince of Denmarke.</title>
        <title type="normalized">The Tragical History of Hamlet, Prince of Denmark</title>
        <author>Shakespeare, William</author>
        <pubPlace>London</pubPlace>
        <publisher>Ling, Nicholas; Trundell, John</publisher>
        <date when="1603">1603</date>
        <extent>4º</extent>
        <note>Usual abbreviation: Q1. Often referred to as “bad quarto”. Printer: Simmes, Valentine</note>
      </bibl>
    </witness>
    <witness xml:id="wit-1623b" n="1623b">…</witness>
    <witness>…a witness with no siglum…</witness>
  </listWit>
</sourceDesc>
```

- **`@n` is the siglum, verbatim.** `@xml:id` is the siglum when it is a valid NCName (an XML
  name with no colon), and `wit-` plus the siglum otherwise (EMOTHE0530's four start with a digit); a witness with no siglum
  has neither. One function, `Witnesses.xml_id/1`, so the `<app>` work points `wit` at the same
  value.
- **`<bibl>`** in that element order; an empty column writes nothing. `@type`/`@subtype` per the
  type table, omitted when `witness_type` is nil. `<date @when>` only for a plain four-digit year,
  as S4. The shelfmark is `<idno type="shelfmark">`, before `<note>`.
- **The modern editions S4 holds are not repeated in `listWit`.** They are in `<back>` with
  `<idno type="siglum">`; how an apparatus reading points at one is the `<app>` work's decision.
- `<witness>` takes no `@type` (checked against `priv/schemas/tei_all.rng`), which is why the type
  sits on its `<bibl>`.

### Import

`import_sources/2` also reads `sourceDesc/listWit/witness`, recursing into nested `listWit`:

- **Structured `<bibl>`:** each element to its column, as the export writes it. `@n` gives the
  siglum, else `@xml:id`.
- **Plain-text `<bibl>`** (EMOTHE0460's: `anon. [no title page]. London: printed by Richard
  Pynson, [1518-19?]. STC 10604.`): the whole text goes to `note`, not guessed into fields. It
  prints as written and exports as `<bibl><note>…</note></bibl>`, which is a fixpoint from then on.
- **Skipped:** a siglum the play already has under another origin, and a siglum that names a
  modern edition linked to the play (EMOTHE0460's `ADA`, `BEV`, `BRA`, `CAW`, `COL`, `LES`, which
  S4 imported). In a fresh database with no bibliography those six come in as witnesses; that is
  S4's accepted "fresh database" loss in reverse, and harmless.
- **Rows are `origin: "tei"`.** `reset_tei_content/1` deletes this play's `tei` witnesses before a
  re-import, like sources; the import preview's `replaces` and `preserves` gain a `witnesses`
  count, and `mixed_ownership_total/1` sums it.

## Also in this slice: `TES2` (task 0)

`bibliography_entries` `T04:34` (Frenk Alatorre, *Comedias*, 1982, on EMOTHE0013) carries the
siglum `TES2`, FileMaker test data. The edition is real; only the siglum goes.

- `Import.Bibliography` writes `T04:34` with no siglum (`@test_sigla`), with a regression test in
  the import's test that fails first. This covers a database the import has not yet run on.
- Where it has run (dev; Fly if `import_bibliography` was run there), a re-run skips EMOTHE0013 as
  already imported, so the siglum is cleared by hand: the Siglum field on EMOTHE0013's
  Bibliography tab, or `Bibliography.update_entry/2` in IEx on dev.

## Testing

Through the outermost API, as CLAUDE.md asks:

| What | Where | Through |
|---|---|---|
| Create appends, move swaps, delete, the validation rule, the unique siglum, scoping | `test/playcode/witnesses_test.exs` | `Playcode.Witnesses` |
| The printed line: emothe.uv.es's order, empty fields dropping out, no doubled stop, `Archivo:` | `witnesses_test.exs` | `plain/1` on hand-written witnesses |
| Every word FileMaker printed is in ours | `test/playcode/witnesses/oracle_test.exs` | as S4's oracle: a committed sample of `T03` rows covering every field and type, plus a `:slow` sweep of `doc/ctce_dades/` when present |
| The import: dry run writes nothing; mapping, type, position; the skips by reason; Jodelle dropped and reported, kept on Jodelle's play; a re-run skips an imported play and does not restore a deleted witness | `test/mix/tasks_test.exs` | `Mix.Task.rerun/2` on a trimmed dump in `test/fixtures/filemaker/ctce_dades/` |
| `TES2` cleared | the bibliography import's test | `Mix.Task.rerun/2` |
| Admin: add with preview, edit, move, delete, a gone id | `test/playcode_web/live/admin/play_witnesses_live_test.exs` | `live/2`, `form/3`, `render_submit/1`; selectors by visible text and `aria-label` |
| Who may open the page | `authorization_test.exs` | one row |
| Accessibility | `accessibility_test.exs` | the path |
| `/plays/:code` and the static title page list them in order, and print neither siglum nor type | `play_show_live_test.exs`, `static_site_play_test.exs` | rendered HTML |
| `listWit` export and import: every field, both id rules, plain-text `<bibl>`, the skipped edition sigla, a re-import keeping manual witnesses, export → import → export unchanged | `test/playcode/tei_roundtrip_test.exs` | `roundtrip/1`, `xml_elements/3`, `xml_texts/3` |
| A `listWit` shaped like EMOTHE0460's (plain-text `<bibl>`s, four witnesses and six edition sigla): four in, six skipped when the play has those editions | `tei_roundtrip_test.exs` | a snippet; EMOTHE0460 is not a tracked fixture, and `mix test --include slow` sweeps it only when present in the git-ignored `test/fixtures/tei_files/` |
| An export with every witness type validates | `tei_validator_test.exs`, `:slow` | the schema |
| A witness change flags its play | `content_version_test.exs` | as for sources |

Existing guards this slice must satisfy:

- `fingerprint_test.exs` fails until the static site's fingerprint covers `Playcode.Witnesses`,
  which decides what a page prints.
- `content_version_test.exs` fails until `play_witnesses` has its trigger.

## Implementation order

0. `TES2`.
1. **Model:** the migration with its trigger, the schema, `Playcode.Witnesses` with the renderer
   and the oracle fixture.
2. **TEI:** export and import, with the round-trip tests.
3. **Import:** `Import.Witnesses`, the mix task and the `Release` function. Run it on dev, so the
   later steps work on real data, and record the dry run's figures under "Expected result".
4. **Admin page.**
5. **Public pages:** `/plays/:code` and the static site.

Then CLAUDE.md (schema, routes, implemented list, the `listWit` line under *Data dropped on
import*) and the roadmap's S3 row.

## Out of scope

- **The holding library and the information source** (see "The model").
- **The `<app>` apparatus** and how its `wit` points at a modern edition.
- **A corpus-wide witness page** or shared witnesses.
- **Showing the siglum or the type publicly.** emothe.uv.es shows neither; the apparatus, when it
  comes, will show sigla in its own pop-ups.
- **S5's information sources table.**

## Known data issues, for curators after the import

- The 11 witnesses whose Jodelle attribution was dropped (listed by the report).
- Witnesses with an attribution that differs from the play's author are mostly true (a suelta of
  Rojas Zorrilla's play printed under Calderón's name, EMOTHE0390); they are left alone.
- Records 140 and 595 have no printed title (no title page); they print from the normalised title
  or the note.
- Hamlet's Q9 is dated `1965`, a slip for 1695; Q10 has its date and place typed into its title.
