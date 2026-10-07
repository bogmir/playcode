# S4 — Bibliography: research

**Status:** research, 2026-09-25, **revised 2026-10-01** when the FileMaker bibliography
tables arrived, and **2026-10-02** when the full 41-field export of the records and the
modern-editions tables completed them. **All S4 data is now in hand.**

**Stakeholder page:** the questions in "Open questions" also exist as a page for the project's
domain lead, kept at `docs/stakeholder/bibliografia-selecta.html`. It is self-contained: open it
in a browser or attach it to an email. Answers are saved in the reader's browser and come back
as text through its "Copy answers" button. The same page is published at
https://claude.ai/artifact/1sMoU3oTkFK2QuuDDQiccp. Change the repo copy first, then republish. **Not a design yet**: the shape at the end is a proposal, and the open
questions decide whether it holds. Slice S4 of `../plans/2026-08-01-filemaker-import-slices.md`.

Two sources, measured in full:

- **The dump** (2026-10-01/02): tables exported straight from FileMaker's master database
  `ctce_dades.fmp12` (FileMaker Pro 16), kept git-ignored in `doc/ctce_dades/`. It is the
  source of record for all four kinds: `T12*` for criticism, translations and adaptations,
  `T04*` for modern editions, and `T13.1`/`T13.2` for cities and publishers.
- **The web export** (2026-09-25): the four rendered `pub_*` fields of the 439 `T01_tituloEM`
  rows in `doc/w3emothe_T01_tituloEM.ndjson`. Fully superseded. It remains useful only as a
  cross-check of what the website showed.

## Summary

- **The records are structured, and we now have them.** 2,640 bibliography records and
  2,658 links to versions. They split into an analytic level (`Autor`/`Titulo`: article or
  chapter) and a monograph level (`Autor2`/`Titulo2`: book or journal), with year, volume,
  pages, URL, note, and codes for category, language and type. That is a direct fit for
  TEI `<biblStruct>`.
- **The join is exact.** `T12._k_IdObraTitulo` = `T01._IdTituloEmothe`. On 101 of the 106
  versions with published criticism, the dump reproduces the published list text for text.
- **Criticism, translations and adaptations are complete.** The full export of `T12.1`
  (41 fields, 2026-10-02) accounts for every piece of every printed citation:
  - editors: 519 of 519 `Ed.` segments come from `Editor`/`Editor2`
  - translators: 229 of 229 `Tra.` segments come from `Traductor`/`Traductor2`
  - issue: 512 of 514 come from `Ejemplar`; the other 2 have the issue typed into the volume
  - original title 47/47, edition 15/15, number of volumes 20/20
  - city and publisher names, from `T13.1_Ciudad` and `T13.2_Editorial`
- **Modern editions are complete too** (`T04*`, received 2026-10-02). 985 editions and 968 links
  reproduce the website's list exactly on 118 of 120 versions. Each link carries the play's own
  volume and pages within the edition. See "Modern editions".
- **The "~690 hidden records" finding was wrong.** It came from `bus_criticaAnyo`, a stale
  search index: 33 of those 40 versions have no linked record at all. The real unpublished
  set is **118 records on 10 versions, newer than the web export**, plus 86 records with no
  category.
- **Order is computed:** year descending, confirmed against the dump on 99 of 102 published
  lists. There is no position to keep.
- **On the 82 plays we hold:** 325 records on 14 plays. Five of those plays (EMOTHE0659,
  0670, 0749, 0777, 0779) are not in the web export at all, so the dump is their only source.
- **TEI has nothing to import.** No fixture carries a secondary bibliography. Its home is
  `text/back`, written as `<biblStruct>`.

## The dump

| File | Table | Rows | What it is |
|---|---|---|---|
| `T12.1_BibliografiaSelecta.xml` | `BibliografiaSelecta` | 2,640 | the records, all 41 fields (the full export of 2026-10-02; the first export's 26 fields were a strict subset, value for value) |
| `T12_ObraBibliografiaSelecta.xml` | `ObraBibliografiaSelecta` | 2,658 | links: record ↔ version, with a note |
| `T12.11_BiblioSelTipo.xml` | `BiblioSelTipo` | 10 | publication types |
| `T12.12_BiblioSelCategoria.xml` | `BiblioSelCategoria` | 3 | categories |
| `T12.13_BiblioSelIdioma.tab` | `BiblioSelIdioma` | 6 | languages (tab-separated, CR line ends) |
| `T13.1_Ciudad.xml` | `Ciudad` | 256 | city, plus a country on 92 |
| `T13.2_Editorial.xml` | `Editorial` | 743 | publisher name |

The `T13` lookups are shared with `FuenteInformacion`, the information-source table of roadmap
slice S5, which arrived in the same batch. All 14 tables sit together in `doc/ctce_dades/`.

The XML files are `FMPXMLRESULT`: `METADATA/FIELD` gives the column names, then each
`RESULTSET/ROW/COL/DATA` holds a value in that order. An empty column is `<COL></COL>` or
`<COL/>`. The parse is a dozen lines of `Regex` or Saxy; nothing needs a new dependency.

### Fields of a record

| FileMaker field | Filled | Meaning |
|---|---|---|
| `_kp_IdBiblioSelecta` | 2,640 | record id |
| `_k_IdBiblioSelCategoria` | 2,554 | 1 Bibliografía crítica (2,258), 2 Traducción (236), 3 Adaptación/versión (60); **86 blank** |
| `_k_IdBiblioSelTipo` | 2,633 | publication type, table below |
| `_k_IdBiblioSelIdioma` | 1,394 | 1 castellano, 2 francés, 3 inglés, 4 italiano, **5 portugués** (never used), 6 alemán |
| `BibSel_Autor`, `BibSel_Titulo` | 1,974 / 2,036 | **analytic**: author and title of the article, chapter or section |
| `BibSel_Autor2`, `BibSel_Titulo2` | 654 / 2,581 | **monograph**: author and title of the book, or the journal title. For a book (type 4) only this level is filled |
| `BibSel_NumVolTomo` | 1,417 | volume (`29`, sometimes `57, 2`) |
| `BibSel_Pag` | 1,846 | pages |
| `BibSel_Ano` | 2,598 | year, as text despite the NUMBER type. 40 are not a plain year: `2009-2010`, `1973 ?`, `[s.a.]`, `letra del s. XIX`, and page ranges typed into the wrong field (`121-123`, `308-322`) |
| `_k_IdCiudad`, `_k_IdEditorial` | 981 / 889 | foreign keys into `Ciudad` and `Editorial`. All 177 city ids resolve. 385 of 386 publisher ids resolve; the other is a name typed into the key field (`B.R. Grüner Publishing Company`, on 2 records) |
| `BibSel_Editor`, `BibSel_Editor2` | 33 / 488 | **editors**, analytic and monograph level: the editor of the chapter or edited text, and the editor of the book. Printed as `Ed. …`. Both filled on 2 records |
| `BibSel_Traductor`, `BibSel_Traductor2` | 67 / 165 | **translators**, same two levels: the translator of a play inside an anthology section, and of the whole book. Printed as `Tra. …` |
| `BibSel_Ejemplar` | 519 | journal issue. FileMaker prints it as `vol. 4` before the bare volume number (`2005, vol. 4, 29`), which is why the order looked reversed |
| `BibSel_TituloOriginal` | 47 | original title of a translation, printed `(Orig: …)` |
| `BibSel_Edicion` | 15 | edition; mostly a year (`2021`, `2010`) |
| `BibSel_VolTomoTotal` | 20 | number of volumes, printed `N vols.` |
| `BibSel_URL_FechaAcceso` | 1 | URL access date. Its one value is a page range (`853-960`), typed into the wrong field |
| `BibSel_URL` | 14 | URL |
| `BibSel_Nota` | 178 | free note, **printed on only 3**. Mostly internal: `Sobre: <<Adonis y Venus>>…`, `Toma ejemplos de…`, plus misplaced data (a URL, a publisher, a university) |
| `_tc_BibSel_ComposicionExtensa` | 2,633 | the full rendered citation, `{Falta …}` placeholders included (505 records) |
| `_tc_BibSel_ComposicionBreve` | 2,633 | a short form: author, titles, year |
| `_tc_BibSel_ComposicionExtensaAlt` | 2,633 | the extensa without the author, starting from the title |
| `w3_BiblioSelecta` | 2,640 | the extensa as HTML, with `<<…>>` turned into `<i>…</i>` |
| `w3_BibSelAnyo_*`, `w3_BibSelIdioma_*` | 2,236 / 362, 1,063 / 331 | year and language per category: the sources of the web export's `bus_criticaAnyo`, `bus_tradAnyo` and `bus_tradIdioma` |
| `w3_BiblioSelecta*` | — | the extensa wrapped in `<li>`, one column per category and per translation language. **This is what the web export's `pub_*` fields concatenate** |

Types, with how many records use each:

| Id | Tipo | Records |
|---|---|---|
| 1 | artículo revista | 1,368 |
| 4 | libro / sitio internet | 617 |
| 2 | sección libro / página internet | 580 |
| 5 | acta | 36 |
| 9 | tesis de doctorado | 18 |
| 3 | edición estudioso | 8 |
| 8 | pub. electrónica | 6 |
| 6, 7, 10 | prólogo, homenaje, colección | 0 |
| — | none | 7 |

### Links

`ObraBibliografiaSelecta` has `_k_IdBiblioSelecta`, `_k_IdObraTitulo` and `ObrBibSel_Nota`.
`ObrBibSel_Signatura` exists but is empty everywhere.

- `_k_IdObraTitulo` is `T01._IdTituloEmothe`. That is the same id `version_code/1` falls back
  on (`"EMOTHE" <> zero-padded id`), which agrees with the web edition's href on 275 of 276
  rows.
- **2,565 valid links over 142 versions.** Of the rest, 74 links have no record id and 19
  point at a record that no longer exists. 102 records are linked to nothing.
- **Sharing is rare.** 30 records sit on 2 or 3 versions; everything else belongs to one.
- `ObrBibSel_Nota` holds a DOI or ProQuest URL on 17 links. It belongs to the link, not the
  record.
- **16 linked versions are absent from the web export's `T01`** (ids 83, 436, 576, 659, 660,
  664, 670, 671, 697–699, 714, 749, 777, 779, 784), with 164 records between them.

### Against the web export

- Criticism: the dump's rendered text equals the published list exactly on **101 of 106**
  versions. The other 5 differ by one to three records, added or removed since the export.
- **118 records on 10 versions are linked but were never published.** Their ids run from
  2528 to 2799, while every published record is at most 2544. They are newer than the web
  export, not deselected. Examples: *La place Royale* 22, *El desdén con el desdén* 18,
  *Le menteur* 15.
- **`bus_criticaAnyo` is stale.** It listed 698 criticism years on 40 versions with an empty
  published list, which is where this doc's earlier "~690 hidden records" came from. In the
  dump, 33 of those 40 versions have no linked record at all.
- **There is no "selected" flag.** "Selecta" names the whole bibliography, not a subset.
- Uncategorised records (86) never reach any published list, because the web columns are
  split by category. 76 of them are linked, 50 to plays we hold, 35 of those to EMOTHE0659
  alone. 20 records have neither author nor title, and one (2652) is a blank template.

### On the plays we hold

Codes matched against the 82 fixture files:

| Play | Crítica | Traducción | Adaptación | No category |
|---|---|---|---|---|
| EMOTHE0010 *Hamlet* | 62 | 22 | 7 | 1 |
| EMOTHE0337 *The Tragedy of Mariam* | 60 | | | |
| EMOTHE0346 *Bartholomew Fair* | 37 | 5 | | |
| EMOTHE0341 *Eastward Ho!* | 23 | 1 | | |
| EMOTHE0038 *Antony and Cleopatra* | 14 | 1 | | 1 |
| EMOTHE0777 | 10 | | | |
| EMOTHE0779 | 9 | | | 1 |
| EMOTHE0749 | 8 | | | 2 |
| EMOTHE0659 | 2 | | | 35 |
| EMOTHE0670 | 3 | 2 | | 10 |
| EMOTHE0281, 0008, 0211, 0502 | 4 | 5 | | |
| **Total, 14 plays** | **232** | **36** | **7** | **50** |

The web export gave 234 citations in these three kinds. Plays 0659, 0670, 0749, 0777 and 0779
are not in `T01`, so they reach us only through the dump.

## What was missing, and where it was

**Nothing is missing any more.** The modern editions arrived as well; see "Modern editions".

Everything a printed bibliography citation shows is now in a column:

| Printed as | Field | Checked |
|---|---|---|
| `Ed. Cottegnies, Line; …` | `BibSel_Editor`, `BibSel_Editor2` | 519 of 519 segments |
| `Tra. Martínez Sierra, María` | `BibSel_Traductor`, `BibSel_Traductor2` | 229 of 229 segments |
| the `4` in `2005, vol. 4, 29` | `BibSel_Ejemplar` | 512 of 514; the other 2 have the issue in `NumVolTomo` (`vol. LXIX, núm. 137`) |
| `(Orig: Antony and Cleopatra)` | `BibSel_TituloOriginal` | 47 of 47 |
| edition | `BibSel_Edicion` | 15 of 15 |
| `10 vols.` | `BibSel_VolTomoTotal` | 20 of 20 |
| `Paris: Gallimard` | `_k_IdCiudad`, `_k_IdEditorial` → `T13.1`, `T13.2` | every city id; 385 of 386 publisher ids |
| a thesis's university | the publisher id, on 8 of 18 theses | the other 10 print `{Falta nombre Universidad}`; the name sometimes sits in `Nota` |

**The lookups need cleaning before use.**

- Both carry test rows (`ciudad_prueba`, `ciudad_test 2`, `Editorial_Prueba`, `edi_test 2`)
  and blanks (6 cities, 14 publishers). No bibliography record points at either.
- Country names mix languages (`Francia` and `France`, `USA` and `Estados Unidos de
  América`), so normalise them before using them for anything but display.

**How it was found**, so nobody repeats the search (all 2026-10-02):

- **Not another table.** The first export carried 26 of `T12.1`'s 41 fields.
  - The relationship graph (`doc/ctce_dades/relaciones/5-calculos-descripcion.png`) builds the
    citation from `T12.1`, `T12.11`, `T13.1` and `T13.2` only.
  - The *Campos* tab (`6-campos-T12.1.png`) shows the formula reading `BibSel_Editor`,
    `BibSel_Editor2` and `BibSel_Traductor…` directly.
  - A plain re-export came out byte-for-byte identical, because FileMaker's export dialog
    reuses the previous field selection. Name the fields when asking.
- **Not `T13_FuenteInformacion`.** Only 6 of the 519 `Ed.` segments and 2 of the 229 `Tra.`
  segments appear anywhere in it. It keeps its *own* sources' editors in `Autor2` without a
  role. Scholarly editions here do the same with `Autor` (`Bevington, David, ed.`).
- **Not `T07.51*`.** Those are the credits of each digital edition, the TEI header's
  `<respStmt>`, which belong to roadmap slice S7. Only 2 of the 194 cited translators appear
  among its 55 people.

## Order is computed, not curated

FileMaker sorts each published list by `BibSel_Ano`, descending, with non-digits stripped.
So `1957-75` sorts as 195775, above 2014, and a range year opens 17 criticism lists. Checked
against the dump: 99 of 102 published lists follow it exactly. `year desc nulls last` gives the intended
order, and there is no curated position to import.

## Modern editions *(received 2026-10-02)*

Four tables, in `doc/ctce_dades/`:

| File | Rows | What it is |
|---|---|---|
| `T04.1_EdModerna.xml` | 985 | the editions, 29 fields |
| `T04_ObraModernaRecomendada.xml` | 968 | links: edition ↔ version, plus **where the play sits in that edition** (`ObraEdMod_Volumen`, `ObraEdMod_Paginas`) and the printed citation for that link (`w3pub_EdModernaItem`) |
| `T04.11_EdModTipo.tab` | 2 | 1 Libro, 2 Capítulo de libro (tab-separated) |
| `T04.12_EdModIdioma.xml` | 6 | the same six languages as the bibliography |

**It is complete.**

- The links reproduce the website's modern-editions list exactly on **118 of 120** versions.
  The other 2 differ by one record each.
- 935 of the 938 printed citations are fully explained by edition, link, city and publisher
  fields. The remaining 3 only fail the check's own handling of `<<…>>` and `Vol. V`.
- 10 versions carry 78 links that are not on the website yet, the same staleness as the
  bibliography's 118.

The fields, read from names and renders:

| Field | Filled | Meaning |
|---|---|---|
| `EdiMod_Editor` | 766 | the edition's editor, printed first: `Thompson, Ann; Taylor, Neil, ed.` |
| `EdiMod_Titulo`, `EdiMod_Autor` | 926 / 621 | the play as edited, and its author |
| `EdiMod_Titulo2`, `EdiMod_Editor2` | 461 / 131 | the containing volume and its editors: `In: Wells, Stanley; Taylor, Gary, ed. William Shakespeare: The Complete Works` |
| `EdiMod_Titulo3` | 7 | series (`The Arden Shakespeare`, `The RSC Shakespeare`) |
| `EdiMod_VolTomo`, `EdiMod_Pag` | 25 / 3 | volume and pages at edition level; the link's `ObraEdMod_Volumen` (90) and `ObraEdMod_Paginas` (141) say where *this* play is |
| `EdiMod_Edicion` | 37 | `2nd`, `4th` |
| `EdiMod_Siglas` | 62 | **the edition's siglum** (`ARD3Q2`, `ARD3F1`, `RSC`, `TES2`): the short code a critical apparatus cites it by |
| `EdiMod_Referencia` | 84 | a free-text reference, printed separately (`w3_ReferenciaEdModerna`): `Lope de Vega: Los locos de Valencia, Hélène Tropé (ed.), Madrid, Castalia, 2003.` |
| `EdiMod_Autor2`, `EdiMod_Traductor`, `EdiMod_Traductor2` | 25 / 8 / 3 | second author, translators |
| `EdiMod_URL`, `EdiMod_URL_FechaAcceso` | 41 / 7 | URL (stored without angle brackets) and access date |
| `EdiMod_Nota` | 121 | note |
| `EdiMod_Ano` | 912 | year as text, with stray spaces (` 1936`) and lost digits (`956`, `192`) |
| `_k_IdEdicionModernaTipo`, `_k_IdEdicionModernaIdioma` | 898 / 252 | type; language on only a quarter |
| `_k_IdCiudad`, `_k_IdEditorial` | 889 / 879 | into the shared `T13.1` / `T13.2` |
| `EdiMod_NumVolTomo`, `EdiMod_TituloNota`, `EdiMod_TituloOriginal` | 0 | unused |
| `_tc_EdiMod_ComposicionExtensa` | 0 | empty in the export; the printed form lives on the link |

**Sharing is real here.** 856 editions are linked; 23 of them sit on several versions, up to
11: the Wells and Taylor *Complete Works*, *Drama of the English Renaissance II*, *English
Drama 1580-1642*. Each link keeps its own volume and pages.

**Cleaning before import:**

- 38 blank records, one of them under a duplicated id (576)
- 3 test records, 2 of them linked (`esto es una prueba de una referencia…`, a translator `w`)
- 129 editions linked to nothing; 3 links without an edition and 4 to a missing one

**On the plays we hold:** 102 links on 10 plays: EMOTHE0010, 0038, 0281, 0337, 0341, 0346,
0659, 0670, 0749, 0777. The web export gave 84 on 6. 14 linked versions are absent from `T01`,
as with the bibliography.

## Proposed shape *(proposal, pending the open questions)*

One table per play, structured like the FileMaker record, keyed back to it for the sync:

```
play_bibliography
  play_id           FK plays, on delete cascade
  kind              criticism | translation | adaptation | modern_edition
  pub_type          article | book_section | scholarly_edition | book | proceedings
                    | prologue | festschrift | electronic | thesis | collection
  language          ISO code as plays.language (es fr en it pt de); nil when unknown
  analytic_author   BibSel_Autor
  analytic_title    BibSel_Titulo
  monogr_author     BibSel_Autor2
  monogr_title      BibSel_Titulo2   -- book or journal
  analytic_editors      BibSel_Editor      -- editor of the chapter or edited text
  monogr_editors        BibSel_Editor2     -- editor of the book
  analytic_translators  BibSel_Traductor   -- translator of a play inside an anthology
  monogr_translators    BibSel_Traductor2  -- translator of the book
  original_title    BibSel_TituloOriginal
  volume            BibSel_NumVolTomo
  volumes_total     BibSel_VolTomoTotal
  issue             BibSel_Ejemplar
  pages             BibSel_Pag
  edition           BibSel_Edicion
  url_accessed_on   BibSel_URL_FechaAcceso
  pub_place, publisher
  year_text         BibSel_Ano verbatim ("1957-75", "[s.a.]")
  year              integer, first 4-digit year in year_text; sort only
  url, doi
  note              BibSel_Nota; internal, not printed
  siglum            EdiMod_Siglas      -- modern editions only: ARD3Q2, RSC
  series            EdiMod_Titulo3     -- modern editions only
  reference         EdiMod_Referencia  -- modern editions only, free text
  filemaker_id      _kp_IdBiblioSelecta or _kp_IdEdicionModerna; nil for rows typed in Playcode
  origin            manual | filemaker | tei
  timestamps
```

- **Display.** Playcode prints each citation from its columns, with one template per
  `pub_type`. Empty fields are simply omitted, so `{Falta …}` placeholders cannot appear.
  Titles inside titles (`<<…>>`) become italics, as `w3_BiblioSelecta` already does.
- **The renderer has a ready-made test oracle.** FileMaker's own extensa exists for 2,633
  records. Rendering the same fields and diffing against it, placeholders aside, shows every
  template difference before a curator sees one.
- **Sort** by `year desc nulls last`, then `monogr_title`. There is no `position`.
- **For modern editions,** `volume` and `pages` come from the link (`ObraEdMod_Volumen`,
  `ObraEdMod_Paginas`) when it has them, because they say where this play sits in the
  edition. Otherwise they come from the edition.
- **Sync** is keyed on `(play_id, kind, filemaker_id)`, because the two FileMaker tables
  number their records independently. A record shared by three versions
  becomes three rows. It is fill-only, as in S2:
  - a key not yet present is inserted
  - a present row that nobody has edited is updated
  - a row a curator edited is reported as a conflict and left alone
  - a key that disappeared from the dump is reported, never deleted

  This replaces the earlier per-play-and-kind rule, which only existed because the web
  export had no record identity.
- **Skip on import, and report:** uncategorised records (until question 3 is answered),
  records with neither author nor title, and links to missing records.
- **Admin:** one page per play, grouped by kind, with add, edit, delete and a filter box.
  *Hamlet* has 62 criticism records.

**Rejected for now:**

- **A corpus-global `bibliography_entries` table**, joined to plays the way places are.
  Revisited 2026-10-02 with the modern editions in hand, and still rejected for now:
  - Sharing is small: 30 of 2,550 bibliography records sit on more than one version, at most
    three ways; 23 of 856 modern editions, at most 11 ways.
  - The per-link volume and pages fit a per-play row naturally.
  - The cost is that correcting a shared anthology means editing up to 11 rows.

  `filemaker_id` keeps the copies findable, so a later "fix every copy" action, or a
  migration to shared entries, is mechanical. Promote when curators actually hit it (open
  question 9).
- **Parsing the web export's strings into fields.** The dump makes it unnecessary for all four
  kinds.

## TEI

**There is nothing to import.** All 96 fixture files, UTF-16 decoded, have zero
`<listBibl>`, `<biblStruct>` or `<relatedItem>`. `<back>` is empty in 94. The only `<bibl>`
elements are the `sourceDesc` base-text entries, which are already `play_sources`. The other 2
files hold a `<div type="epilogo">` in `<back>`, which the parser ignores, so those
epilogues are silently dropped on import. That is a separate bug, to fix in the same pass
that teaches the parser `<back>`.

**Not in `sourceDesc/listBibl`.** The parser already reads `sourceDesc/listBibl/bibl` into
`play_sources` (`lib/playcode/import/tei_parser.ex:729-733`), and `sourceDesc` describes the
sources of this edition, which is S3's witnesses. Secondary bibliography is not a source.

**In `<back>`, as `<biblStruct>`.** The type values are in Spanish, to match the corpus's
`acto`/`escena`/`elenco`. The two FileMaker levels map one to one:

```xml
<back>
  <div type="bibliografia">
    <listBibl type="critica">
      <biblStruct type="articulo_revista" xml:lang="en">
        <analytic>
          <author>Taylor, Miles</author>
          <title level="a">'Teach Me This Pedlar's French': The Allure of Cant in 'The Roaring Girl'…</title>
        </analytic>
        <monogr>
          <title level="j">Renaissance and Reformation/Renaissance et Réforme</title>
          <imprint><date when="2005">2005</date></imprint>
          <biblScope unit="volume">29</biblScope>
          <biblScope unit="issue">4</biblScope>
          <biblScope unit="page">107-24</biblScope>
        </monogr>
      </biblStruct>
    </listBibl>
    <listBibl type="traducciones">
      <biblStruct type="libro" xml:lang="es">
        <monogr>
          <author>Jonson, Ben</author>
          <title level="m">Teatro de Ben Jonson</title>
          <editor role="translator">Martínez Sierra, María</editor>
          <imprint><pubPlace>Buenos Aires</pubPlace><publisher>Hachette</publisher><date when="1958">1958</date></imprint>
        </monogr>
      </biblStruct>
    </listBibl>
    <listBibl type="adaptaciones">…</listBibl>
    <listBibl type="ediciones_modernas">…</listBibl>
  </div>
</back>
```

- `title level`: `a` for the analytic title, `j` for a journal (type 1), `m` otherwise.
- `year_text` goes in the `<date>` text, `year` in `@when`. A note goes in `<note>`, a URL in
  `<ptr target>`, a DOI in `<idno type="DOI">`.
- **Round-trip.** The parser reads `back/div[@type="bibliografia"]` and writes rows with
  `origin: "tei"`. A re-import deletes only that play's `tei` rows, and skips a
  `<biblStruct>` that matches an existing row of another origin. That is S9's leave-alone
  rule; without it, export then re-import duplicates every `manual` and `filemaker` row.
- **Why bother.** The static site publishes `plays/<CODE>/<CODE>.xml`, and with the
  bibliography in `<back>` that file is self-contained.
- **Sequence.** Table, admin page and import first; TEI in both directions last.

## Open questions

**Answered by the dump:**

- ~~Can the bibliography table be exported?~~ Yes, and complete for three of the four kinds:
  all 41 fields of `T12.1`, received 2026-10-02. The modern editions are question 2.
- ~~What decides whether a record is published?~~ Nothing on the record does. The 118
  unpublished records are newer than the web export (question 4), and the 698 came from a
  stale index.
- ~~Is language code 5 Portuguese?~~ Yes: 1 castellano, 2 francés, 3 inglés, 4 italiano,
  5 portugués, 6 alemán.
- ~~What record types exist?~~ Ten, listed under "Fields of a record".

**For the FileMaker side:**

1. ~~Export `T12.1` with the nine fields left out.~~ **Received 2026-10-02**, all 41 fields.
2. ~~Export the modern editions~~ **Received 2026-10-02**: `T04`, `T04.1`, `T04.11`, `T04.12`.
3. **What are the 86 uncategorised records?** 76 are linked, 35 of them to EMOTHE0659. Are
   they criticism that was never categorised, or drafts?
4. **Are the 118 records newer than the web export ready to publish?**
5. **Can the broken links go?** 74 have no record and 19 point at deleted records. 102
   records are linked to nothing.

**For us:**

6. **Per version or per work?** FileMaker attaches bibliography to versions. Should a
   translation's page also show its family head's list, through `parent_play_id`?
7. **The `Nota` field.** 178 notes, 3 printed. Keep them as internal notes, show them, or
   drop them?
8. **Order.** The data says year descending is automatic. Do curators want a hand order
   anyway? That would bring back `position` and a reorder UI.
9. **Shared editions.** 23 modern editions sit under several plays (up to 11). Are corrections
   to them rare enough that a per-play copy is fine, or should one edit reach every play?

## Reproducing the numbers

- **Dump counts** are per record or per link, across the whole dump.
- **"Plays we hold"** matches `"EMOTHE" <> zero-padded _k_IdObraTitulo` against the code
  prefixes of the 82 fixture files.
- **Web-export counts** are per `T01` row. Any count per play we hold must go through
  `Filemaker.load_versions/1`, which handles the empty-href fallback.
- **The translation nesting** in `pub_BibSelectaTraduccion` defeats the flat `@list_item`
  regex. Match the language groups first, with
  `<li>\s*([A-Z]{2})\s*:\s*<ul>(.*?)</ul>\s*</li>`, then the items inside each group.
