# S5 — Historical performances from FileMaker

**Status:** designed 2026-10-19, not built. Slice S5 of
`../plans/2026-08-01-filemaker-import-slices.md`. Takes its import shape from S9b
(`2026-10-19-s9b-places-import-design.md`) and S3 (`2026-10-10-s3-witnesses-design.md`), its
sources from S4 (`2026-10-07-s4-bibliography-design.md`).

When and where a play was staged, by whom, and who says so: *The Alchemist* by the King's Men at
the Globe or the Blackfriars in 1610, after Wiggins's *British Drama 1533–1642*, vol. 6, p. 83.
emothe.uv.es printed these under "Representaciones antiguas", from FileMaker. This slice brings
them into the plays we hold, once, prints them on the play page and the site, lets researchers add
and correct them by hand, and writes them into the TEI file.

## Why now

- **Nothing blocks it.** The performance tables arrived on 2026-10-10 (`T11*`, `T13*`, in
  `doc/ctce_dades/`, git-ignored); the performances' places were found on 2026-10-19, in S9b's
  `T10_ObraAccionLugar`; question 11 was decided on 2026-10-16 and question 12 answered on
  2026-10-19.
- **The TEI corpus has none.** No file of `doc/tei_corpus/` or `test/fixtures/` has a
  `<performance>`; FileMaker is the only source, and is not gone back to after this.

## Decisions

From the project owner, 2026-10-19, and from the project's answers to questions 11 and 12:

| # | Question | Answer |
|---|---|---|
| 1 | What it is | emothe.uv.es's list, per play, on the play page and the site. Not a performance database to browse across plays — but built so that one can be added without redoing the data |
| 2 | What keeps its identity now | Whatever FileMaker already knows is one thing: companies and actors are shared records, corpus-wide; the place is a gazetteer link; the source is a bibliography entry (question 11) |
| 3 | What stays text | What is text in FileMaker too: the venue as written, and the date as written, with a year from/to beside it for sorting (and a later period filter) |
| 4 | Managing companies and actors | No pages of their own yet: a curator picks one in the performance form or types a new one, and a "Rename" beside it corrects the record for every performance (2026-10-20). Merging, list pages and browsing come with the search. One no performance names is deleted, as an entry is |
| 5 | What readers see | Layout B (below): one line per performance, the sources once below the list |
| 6 | The role in a cast | Text ("Argan"), not a link to the play's character: a TEI re-import rebuilds the characters, and 10 cast rows name a role |
| 7 | *The Way of the World*'s 1700 performance | A switch, "cast as in the cast list": it prints the 12 actors `characters.actor` holds, copying none (as question 28's text promised) |
| 8 | FileMaker's source records | Merged into works by a hand list, as S9b merged places. Wiggins is one entry; each performance holds its own volume and pages |
| 9 | Where the sources appear | Only beside the performance, never in the play's bibliography (question 12) |
| 10 | Re-importing a TEI file | Replaces the play's `tei` performances only; FileMaker's and hand-entered ones survive |
| 11 | Scope | Not the HTML/PDF/EPUB downloads, not pages for companies or actors, not a cross-play search, not the witnesses' T13 sources, not question 28 |

## Done when

- `mix playcode.import.performances --dry-run` prints the plan; without `--dry-run` it writes it.
  `Playcode.Release.import_performances/2` does the same on Fly.
- `/plays/:code` and the static site print a play's performances as layout B, with the source of
  each and its volume and pages, and CATCOM's credit line wherever CATCOM is cited.
- A researcher adds, edits and deletes a performance and its cast on the play's Performances tab.
- The TEI export writes the performances, the TEI import reads them back, and
  `complete_copy_test.exs` passes with the new tables in its comparison.
- Changing anything a performance prints (the performance, its cast, its company, an actor, its
  place, its source entry) moves the play's `content_version`.

## How FileMaker codes performances

- **`T11_ObraRepresentacion`**, one row a performance: `_kp_IdObraRepresentacion`, the version
  `_k_IdObraTitulo` (38 is EMOTHE0038, as in S3), `ObrRep_Fecha` (text), `ObrRep_NombreCircunstancia`
  (the venue's name, text), `_k_IdCirEscenica` (the venue type; `_k_IdCirEscenicaOld` is a
  superseded copy: the published line follows the first), `_k_IdCompaniaNombre`,
  `_k_IdFuenteInformacion` (the source), `ObrRep_Nota`. `w3_RepAntigua` (Spanish) and
  `w3_RepAntiguaHieronimo` (English) are the published `<li>`, the renderer's oracle. The
  `z_new*`, `g_Filtro*` and `_kz_Picker*` fields are form scratch. `_k_IdObraAccionLugar` (142
  rows) points at records that do not exist in `T10_ObraAccionLugar`; it is dead, and the
  published "Topónimo:" is blank on every row.
- **The place** is in `T10_ObraAccionLugar`: 49 rows with `_k_IdObraRepresentacion` set, S9b's
  shape (the ids of the chain, `espacio`), all cities.
- **`T11.2_CircumstanciaEscenica`**, the 8 venue types, Spanish and English: 1 teatro público /
  public theatre, 2 palacio / palace / court, 3 calle, plaza / street, square, 4 otro / other,
  5 teatro privado / private theatre, 6 desconocido / unknown, 7 universidad / "inns of court" /
  university, inns of court, 8 teatro comercial / commercial theatre.
- **`T11.3_CompaniaNombre`**, 91 records, 88 named. Four names are two records each: Troupe de
  Molière (101, 123), The Duke's Company (30, 52), Comédie Française (96, 98), An English
  company / Company (80, 81).
- **The cast**: `T11.1_ActorRepresentacion` (`_k_IdObraRepresentacion`, `_k_IdActorNombre`,
  `_k_IdActorRol`, `ActRep_Indice` the order), `T11.11_ActorNombre` (`ActNom_Apellidos`,
  `ActNom_Nombre`, `ActNom_Apodo` the nickname, `_k_IdActorSexo`), `T11.12_ActorSexo` (1 hombre,
  2 mujer, 3 desconocido; a `.tab` file), `T11.22_ActorRol` (the role's name). **The cast row's
  actor key carries a trailing "|"** (`"6|"`); stripped, 52 of the 54 match. The other two
  (`"1|Actor38|"` on performance 358, `"14|Actor54|"` on 360) are picker leftovers with no name
  in `ActRep_Indice` and none published. Burbage (13, 30) and
  Joseph Taylor (22, 28) are two records each; record 3 has its names swapped ("John, Taylor").
- **`T13_FuenteInformacion`**, the sources, S4's two levels: `FueInf_Autor`/`FueInf_Titulo`
  (analytic), `FueInf_Autor2`/`FueInf_Titulo2` (monograph), `FueInf_Ano`, `FueInf_NumVolTomo`,
  `FueInf_Pag`, `FueInf_URL`, `FueInf_Nota`, `_k_IdCiudad`/`_k_IdEditorial` (`T13.1`, `T13.2`,
  the lookups S4 reads), `_k_IdFuenteInfoTipo` (`T13.3`: T12.11's first nine types, same ids).
  FileMaker made a record for nearly every volume and page cited: Wiggins is 77 records on our
  plays, under ten spellings of its title, 6 of them with the volume in the title ("Volume 5:
  1603-1608", one "Volume IX") and the rest in `FueInf_NumVolTomo`. `_tc_FueInf_ComposicionBreve`,
  the published citation, leaves out the page, and prints `{Falta año pub}` and the like
  wherever a field is empty.

### The numbers, against the plays we hold

Measured against `playcode_dev` (393 plays: the corpus and the fixtures) on 2026-10-19; the
import's own report is the final word.

| | |
|---|---|
| Performances | 244 on 60 plays (317 on 89 versions in FileMaker) |
| With a date | 232: 183 a plain year, 49 anything else ("1597-9", "c. 1620", "1590s", "Before 1642", "04/05//1674", "30 y 31 de marzo de 1682", "1701-1702: 1 Oct, 21 Oct") |
| With a venue / a venue type | 215 / 225 (commercial theatre 136, palace / court 64) |
| With a company | 196, naming 74 companies |
| With a note | 142 |
| With a source | 188, through 99 records (one, `105`, missing from `T13`) |
| With a place | 49: Madrid 19, Paris 13, London 9, Sevilla 3, Valladolid 2, Lisboa, Valencia, Nápoles |
| Cast | 41 rows on 12 performances, 36 actors, 10 rows with a role |

The works behind the 188: Wiggins 110 (77 records), CATCOM 46 (records 119 and 468), Mora Sena's
*Restoration Comedy, 1671–1682* 7 (7 records, five spellings of its authors), *The London Stage
Database* 6, Nicoll's *History of English Drama* 4, Harbage's *Annals of English Drama* 4,
Chambers's *William Shakespeare* 2, and one each: Gómez-Lara's *Restoration Comedy 1660–1670*,
Child's "Stage-History of Hamlet" in Wilson's *Hamlet*, Greg's *Henslowe Papers*, *Richard Brome
Online*, Massinger's *Selected Plays*, Dryden's *Works* vol. XIII, the Ulivi–Savini *Aminta*, and
record 479, a bare URL to data.bnf.fr (*Saül le furieux*, 0491).

## The model

Four new tables.

```
performance_companies                corpus-wide
  name                text, not null; unique, case-insensitive
  timestamps

performance_actors                   corpus-wide
  surname             text
  forename            text
  nickname            text           "Molière", "Gros-René"
  sex                 text           "man" | "woman" | nil (FileMaker's "desconocido")
  timestamps                         needs a surname or a nickname ("Rosimond")

play_performances
  play_id             references plays, on delete cascade
  date_text           text           as written: "c. 1620", "04/05//1674"
  year_from           integer
  year_to             integer
  venue               text           as written: "Globe or Blackfriars"
  venue_type          text           one of Performance.venue_types/0
  company_id          references performance_companies, on delete restrict
  place_id            references places, on delete restrict
  historical_state_id references places, on delete restrict
  note                text
  source_entry_id     references bibliography_entries, on delete restrict
  source_volume       text           where this performance is in the source
  source_pages        text
  cast_from_cast_list boolean, default false
  position            integer        set only by the context
  origin              text           "filemaker" | "manual" | "tei"
  filemaker_id        text           "T11:<id>"; never written to the TEI file
  timestamps

performance_cast
  performance_id      references play_performances, on delete cascade
  actor_id            references performance_actors, on delete restrict
  role                text           "Argan"
  position            integer
```

- **A new context, `Playcode.Performances`**, owns the four tables, as `Playcode.Witnesses` owns
  witnesses: list a play's performances (preloaded with company, place, state, source, cast and
  actors), get one scoped to the play (`get_performance/2`, nil for another play's, the
  access-control rule), create, update, delete, and what the form needs of companies and
  actors: find by name, create, rename (`update_company/2`, `update_actor/2`, each refusing a
  name another record has), and how many performances name one.
- **No orphan companies or actors.** Deleting a performance, removing a cast row, pointing a
  performance at another company or actor, and a TEI re-import replacing `tei` performances
  each delete a company or actor no performance names any more, so the datalists hold only
  names in use.
- **`Performance.venue_types/0`**: `public_theatre`, `palace`, `street`, `other`,
  `private_theatre`, `unknown`, `university`, `commercial_theatre` — FileMaker's ids 1–8 in that
  order — with FileMaker's Spanish and English labels. The labels live in the module, not in
  gettext, so the static site's fingerprint covers them (S9b's reason for the "hoy"/"today" map).
- **The years.** `Performance.years/1` reads a date as written into `{from, to}`: the first and
  last four-digit years, "1597-9" and "1610-11" completing the second, "1590s" 1590–1599,
  "Before 1642" `{nil, 1642}`; nothing for a date with no year. The import fills both columns
  from it; the form fills a blank one on save, and keeps one a curator set.
- **The order**: by `coalesce(year_from, year_to)`, undated last, then `position` (FileMaker's id
  on import; a new one goes last).
- **The place** follows S9b exactly: `place_id` the place, `historical_state_id` the state it
  belonged to in that performance (London, Kingdom of England). `Places.place_line/3` takes any
  struct with `place` and `historical_state_id`, not only a `PlayPlace`.
- **`cast_from_cast_list`**: at most one performance per play has it (a partial unique index).
  Its cast is the play's characters with an `actor`, in cast-list order; it may hold cast rows of
  its own besides, printed after.
- **Sources.** `Entry` gains the kind `catalogue` (Wiggins, CATCOM, the London Stage Database),
  for works that fit none of the bibliography's four groups. It prints through `Citation`'s
  general clause, as it is. The play's Bibliography tab neither offers it as a kind nor finds a
  catalogue entry in its search, so question 12 holds without a check elsewhere. Any entry, of
  any kind, can be a performance's source.
- **No orphan entries.** An entry is deleted with its last citation, a performance's or a play's:
  `Bibliography.unlink/1` counts performances citing the entry, and deleting a performance or
  changing its source deletes an entry nothing else cites, through one shared function.
- **The content-version triggers** (one new migration; `content_version_test.exs` gets a case
  for each):
  - `play_performances`: `play_row_changed()`.
  - `performance_cast`: a function touching the performance's play, as
    `element_character_changed()` touches a speech's.
  - `performance_companies` and `performance_actors`, on update: the plays whose performances
    name them.
  - `bibliography_entry_changed()` replaced to also touch the plays whose performances cite the
    entry; `place_changed()` replaced to also touch the plays whose performances are at the
    place, or in the state, or anywhere inside them.
  - `characters` already touch their play, so editing an actor in the cast list reaches the
    *Way of the World* performance.

### The glossary

`CONTEXT.md` gains:

> **Performance** (*representación*): one staging of a play recorded by a source — a date, a
> venue, a company, a cast. The play page's "Performances". _Avoid_: historical performance in
> the interface (all of them are), representación antigua.
>
> **Company** (*compañía*): who staged it, a record shared by every performance it gave.
>
> **Venue** (*lugar de la representación*): where, as the source names it ("The Rose
> playhouse"); text, not a place. Its **venue type** (*circunstancia escénica*) is one of eight.
> The town is the performance's place, from the gazetteer.

## The import

`Playcode.Import.Performances`, S9b's shape: `load/1` reads the tables through
`Playcode.Import.FilemakerXml` (the `T11.12` `.tab` file by hand: three tab-separated lines);
`plan/2` decides, reading the database and writing nothing; `apply_plan/2` writes the plan in one
transaction; `report/1` prints it. The mix task `playcode.import.performances` and
`Playcode.Release.import_performances/2` call them as `playcode.import.places` and
`import_places/2` do.

### Which plays

As S9b: the version id is the play code's number, matched against `Play.short_code/1`; a
performance on a version we do not hold is counted and skipped. A play already imported is
skipped whole: one with a `filemaker` performance, or with the activity-log row `apply_plan/2`
writes (`action: "import"`, `resource_type: "play_performance"`, `metadata: %{"source" =>
"filemaker"}`), which outlives them.

### From FileMaker rows to performances

- **Date**: `ObrRep_Fecha` as written; the years from `Performance.years/1`. The report lists
  every date it cannot read.
- **Venue**: `ObrRep_NombreCircunstancia`, as written. One venue holds CATCOM's credit line,
  typed after the name (EMOTHE0379, performance 164: "Casa de comedias de Toledo" and then
  "Información extraída de: CATCOM…"): the venue keeps the first line. The credit prints with
  CATCOM's citation instead.
- **Venue type**: `_k_IdCirEscenica`, through the ids above.
- **Company**: one Playcode company per name, compared case-insensitively, so FileMaker's twins
  merge (The Duke's Company 30 and 52 are one). A company already in Playcode under that name is
  reused.
- **Cast**: the actor key with its "|" stripped; one Playcode actor per full name
  (surname, forename, nickname), so Burbage's two records merge; the role from `T11.22`; the
  order from `ActRep_Indice`. A cast row whose key matches no actor is skipped and reported
  (the two picker leftovers on performances 358 and 360).
- **Note**: `ObrRep_Nota`, as written.
- **Place**: the `T10_ObraAccionLugar` row naming the performance, resolved by S9b's own rules —
  the referent, the hand lists, the historical state (Valladolid in Castilla, London in the
  Kingdom of England, Nápoles in the Reino de Nápoles) — through functions `Import.Places`
  exposes for it, not a copy. A place not yet in the gazetteer is created by those rules; an
  existing one is reused, never changed.
- **Origin** `filemaker`; `filemaker_id` `"T11:<id>"`; `position` FileMaker's id order.
- **The *Way of the World* switch**: set on EMOTHE0313's 1700 performance (145), which has no cast
  in FileMaker, by a one-line rule in the importer naming it.

### From FileMaker source records to entries

- **The hand list**, a map in the importer in the style of S9b's: record id → work, for every
  record of a work that FileMaker split. Wiggins's 77 records are one work; CATCOM's 119 and 468
  one; Mora Sena's 7 one. Each such work's entry is written out in the list — authors, title,
  imprint, year, kind — as the project's editors would cite it: Wiggins "Wiggins, Martin, in
  association with Catherine Richardson. *British Drama 1533–1642: A Catalogue*. Oxford: Oxford
  University Press, 2012–."; CATCOM with its URL and, as `public_note`, its credit line ("Copyright
  © DICAT Grupo de investigación teatral bajo Licencia Creative Commons BY-NC-ND."), the licence's
  requirement.
- **Volume and pages.** For a work in the hand list, each record's `FueInf_NumVolTomo` (or the
  volume its title names: "Volume 5: 1603-1608" is 5, "Volume IX" 9) and `FueInf_Pag` go on the
  performance, `source_volume` and `source_pages`. A record that is a work on its own keeps them
  on the entry: Child's chapter is pp. lxix–xcvii of Wilson's *Hamlet*.
- **A record that is a work on its own** becomes an entry from its fields, as S4's
  `record_attrs/2` reads `T12.1` (the two levels, the type through `T13.3`, the city and
  publisher through `T13.1` and `T13.2`), kind `criticism` unless the hand list says
  `catalogue` (the London Stage Database, Harbage's *Annals*, Gómez-Lara's catalogue).
  `FueInf_Nota` becomes the entry's `note`, for researchers, unless the hand list makes it
  something else (Brome's address is a URL; "Arden Early Modern Drama" a series).
- **Record 479**, a bare data.bnf.fr address with no author or title, which an entry cannot be:
  the hand list names it ("data.bnf.fr", kind `catalogue`). **Record 105**, missing: the
  performance comes in without a source, and the report says so.
- **`filemaker_id`** `"T13:<id>"` of the first record of each work (the column is unique, and S4
  uses `T12:` and `T04:`). An entry already in Playcode with an identical description
  (`Bibliography.identical_entries/2`) is reused instead.
- **A record that is an edition S4 already brought in** is sent by the hand list to that entry,
  by its `filemaker_id`, keeping the entry's kind: record 97 (Gibson's *Selected Plays of Philip
  Massinger*) to `T04:116`, 98 (*The Antipodes* in *Richard Brome Online*) to `T04:385`, 81 (the
  Dryden *Works*, vol. XIII) to `T04:418`. Each is already in its play's bibliography (EMOTHE0309,
  0472, 0373) as a modern edition; a second entry would cite one edition twice on one page.
- The dry run lists every record it reads, with the work it went to, so the hand list is
  complete before the real run.

### The report

What the dry run prints, and the real run after writing: per play, its performances as lines
(`EMOTHE0304  1610  Globe or Blackfriars · The King's Men · commercial theatre [Wiggins 6, 83]`);
the companies and actors to create, the twins merged, the ones reused; the entries to create and
reuse, each with its records; the dates without a year; the skipped cast rows and sources; the
versions not held; the plays already imported.

## What readers see

Layout B (the mockup the owner chose, 2026-10-19). A section "Performances" / "Representaciones"
on the play page, between Witnesses and Bibliography, laid out like them (label left, list
right), in the page's section index (`meta-performances`); the same on the static site's play
page.

```
Performances   1610     Globe or Blackfriars · The King's Men · commercial theatre  [1] vol. 6, p. 83
                        The play was reportedly hissed occasionally.
               1610-11  Whitehall Palace · The King's Men · commercial theatre  [1] vol. 6, p. 83
               1673     …
                        Cast: Jean François Poquelin, “Molière” (Argan); M. de la Thorillière (Argan)
               ─────
               [1] Wiggins, Martin, in association with Catherine Richardson. British Drama
                   1533–1642: A Catalogue. Oxford: Oxford University Press, 2012–.
```

- **A line**: the date as written, in bold, then the venue, the place line, the company and the
  venue type, those present, joined by " · "; at its end, in small type, the source's number and
  the performance's volume and pages. An undated performance starts with its venue. A
  performance with nothing but a venue type prints that ("street, square").
- **Below it**, each in small type: the cast ("Cast: " and each actor, with the role in brackets),
  then the note.
- **An actor**: forename and surname, then the nickname in quotes after a comma ("Jean François
  Poquelin, “Molière”"); a nickname alone, alone ("Rosimond"). The *Way of the World*'s cast
  prints each character's `actor` with the character's name as the role ("Mr. Betterton
  (Fainall)").
- **The sources**, numbered in order of first citation in the list, printed once below it through
  `Citation.html/1` with no link (the entry's own volume and pages, not a performance's), the
  `public_note` included — so CATCOM's credit line prints once per play that cites it.
- **The place line**: `Places.place_line/3`, as the Places section prints it (the interface
  language on the play page, Spanish on the site).
- **Labels and venue types** follow the page's language; the site's interface is English, as now.
- **No FileMaker placeholder prints**: the citation is built from the entry's fields, never from
  `_tc_FueInf_ComposicionBreve`.

`Playcode.Performances` and whatever it renders through go into `StaticSite.Fingerprint`, which
`fingerprint_test.exs` enforces.

## The admin

A "Performances" / "Representaciones" tab on the play (`PlayPerformancesLive`,
`/admin/plays/:id/performances`), beside Witnesses, for everyone with the content actions
(researchers included), shaped like the Witnesses tab: the list as readers will see it, and a
form to add or edit one.

- **The form**: date (as written), year from and to, venue, venue type (a select of the eight,
  blank allowed), company (a text field offering the companies as a datalist; a name no company
  has creates one on save), place (the Places tab's search) and historical state (the Places
  tab's select), note, source (a search over every entry, of any kind; or a new entry, through
  the bibliography tab's entry fields, extracted into a component both tabs use), volume and
  pages, and "Cast as in the cast list".
- **Correcting a source.** Beside the chosen source, "Edit source" opens the same entry fields on
  the entry itself, with the Bibliography tab's warning that the entry is shared, naming the
  plays that cite it. A catalogue is cited by no play's bibliography, so this is the only place
  Wiggins or CATCOM can be corrected, and question 11's reason for making them entries ("a
  correction reaches every performance") depends on it. `Bibliography.plays_for_entry/1` and
  `link_counts/1` count a play whose performances cite the entry as well as one that links it.
- **The cast**, inside the form: rows of actor (picked by name from a datalist, or a new one with
  surname, forename, nickname and sex) and role, added and removed in place, in order.
- **Ids from the browser** (a performance, a company, an actor, a place, an entry) are resolved
  through getters scoped as `CLAUDE.md` asks (`Performances.get_performance/2`,
  `Places.get_place/1`, and a non-raising entry getter beside `Bibliography.get_entry!/1`); a stale one reloads the list with
  `put_gone_flash/1`.
- Each save and delete writes the activity log, as the other tabs do.
- **Choosing and renaming are two controls.** The company field and each cast row's actor field
  choose who this performance names: an existing record, or a new one created on save. Beside a
  chosen company or actor, "Rename" corrects the record itself, for every performance that names
  it, and says how many those are ("The King's Men — 40 performances in 12 plays"): a company's
  name; an actor's surname, forename, nickname and sex, which is how FileMaker's "Hart, Charles
  Hart" and "John, Taylor" get fixed. A rename to a name another record has is refused (merging
  is not here). Each rename writes the activity log and moves the `content_version` of every play
  concerned, through the triggers above.
- **Not here**: merging two companies or two actors, a page listing them.

## TEI

Each performance is a `<performance>` in `text/front`, after the cast list and the scene, in the
list's order:

```xml
<performance xml:id="performance-1">
  <p>
    <date when="1610">1610</date>
    <name type="venue">Globe or Blackfriars</name>
    <placeName ref="#londres"><country ref="#reino-de-inglaterra"/></placeName>
    <orgName>The King’s Men</orgName>
    <term type="venue_type">commercial_theatre</term>
  </p>
  <castList>
    <castItem><role>Argan</role><actor>
      <forename>Jean François</forename> <surname>Poquelin</surname>
      <addName type="nickname">Molière</addName></actor></castItem>
  </castList>
  <note>The play was reportedly hissed occasionally.</note>
  <biblStruct>…the source, as the bibliography writes an entry…
    <citedRange unit="volume">6</citedRange><citedRange unit="page">83</citedRange>
  </biblStruct>
</performance>
```

The encoding above is the shape, not the letter; the builder settles it against the schema
(`mix test --include slow` validates every export) under these rules:

- **Everything round-trips**: the date as written and its years (`when`, or `notBefore`/
  `notAfter`, as the composition date does), the venue, the venue type, the company, the place
  and its state (the place and its ancestors join the `settingDesc`'s `listPlace`, as S9b's do),
  the note, each cast row with the actor's four fields (sex as TEI's `actor@sex`), the source with
  the performance's own volume and pages, and the *Way of the World* switch, as a pointer between
  the performance and the cast list's `castList`.
- **The source travels whole.** Question 12 keeps it out of the play's bibliography, so the
  performance carries its own `biblStruct`, written by the bibliography's export code, and the
  import links it to the entry with an identical description (`Bibliography.identical_entries/2`)
  or creates one, as `back/div[@type="bibliografia"]` does. Wiggins is written once per
  performance citing it; that is the cost of a file that is a complete copy.
- **Companies and actors are found by name** on import (the company's name, case-insensitively;
  the actor's four fields), else created. A file names no Playcode id: `xml:id`s are the file's
  own (`performance-1`), not database ids.
- **On every import**, a play's `tei` performances are replaced by the file's; `filemaker` and
  `manual` ones are left alone, and a file's performance identical to one of them (every printed
  field equal) is skipped, S0b's leave-alone rule. `TeiImport.preview_import/1` lists the
  performances an import would add and replace.
- `complete_copy_test.exs`: the ordinary play gets one performance; the rarer one every column
  filled (a state, a source with volume and pages, a cast with a nickname and a sex, the
  cast-list switch). The table check makes the snapshot read `play_performances` and its cast;
  `filemaker_id` is dropped with its reason, as the witnesses' is.
- `docs/stakeholder/ida-y-vuelta.html` gets the row: admin yes, TEI export yes, TEI import yes,
  play page and site yes, HTML/PDF/EPUB no (the downloads print what question 24 listed).

## Tests

Through the outermost API, as `CLAUDE.md` asks:

- **The import**: small hand-made tables under `test/fixtures/filemaker/performances/` (the `T11*`,
  `T13*` and the few `T10` rows they need), run through `plan/2` and `apply_plan/2`, asserting on
  what `Performances` and the play page give back: two Wiggins records becoming one entry with
  two performances' own pages; the volume read from a title; CATCOM's credit leaving the venue
  and printing with the citation; two company twins merged; an actor key with its "|"; a
  performance's place with its historical state; a date with no year reported; record 105
  reported; a second run skipping the play; the dry run writing nothing.
- **The mix task** through `Mix.Task.rerun/2` in `test/mix/tasks_test.exs`.
- **The years**: `Performance.years/1` on the dates listed above.
- **The play page and the site page**: the line, the cast, the sources once, the numbering, the
  credit line, an undated performance last, *The Way of the World*'s cast from its cast list.
- **The Performances tab**: add, edit, delete through the form; a new company and a new actor
  created on save; renaming a company reaching another play's page, and a rename onto a taken
  name refused; the last performance of a company deleted taking the company with it; an id from
  another play resolved or refused.
- **The round trip**: `tei_roundtrip_test.exs` (export, import, compare) and
  `complete_copy_test.exs`; a re-import keeping a `filemaker` performance and skipping its copy.
- **The rules**: `Bibliography.unlink/1` keeping an entry a performance cites; deleting the last
  performance citing an entry deleting it; the Bibliography tab not finding a catalogue.
- **The triggers**: `content_version_test.exs`, one case per trigger above.
- **The gates**: a row in `authorization_test.exs` for the new route, its path in
  `accessibility_test.exs`.

## Rollout

Dev: after S9b's places (the performances reuse its places), dry-run, read the report, settle
the hand list, run. Production after the deploy, through
`Playcode.Release.import_performances/2`: dry run, read, run; then Generate on `/admin/export`,
which rebuilds the 60 plays. A forced TEI re-import from `doc/tei_corpus/` later keeps them
(origin `filemaker`).

## Paperwork

- `../plans/2026-08-01-filemaker-import-slices.md`: S5 points here.
- `CONTEXT.md`: *Performance*, *Company*, *Venue*.
- `docs/stakeholder/ida-y-vuelta.html`: the row.
- `docs/backlog.md`: the "New FileMaker slices go into the TEI from the start" item loses S5;
  new items for what this slice leaves out — the performance search and the pages for companies
  and actors (with merging), venues as gazetteer places, the 365 witnesses citing `T13` sources
  (the hand list and the T13 reading here serve them). On completion, the slice moves to
  `docs/history.md`.
- `CLAUDE.md`: the four tables in *Database Schema*, the `<performance>` mapping in *TEI-XML
  Format*, and the import's commands beside S9b's.

## Not in this slice

- **A search across plays** (by company, actor, venue, period): decision 1; the data keeps what
  it needs.
- **Pages for companies and actors**, and merging two: decision 4. Renaming is in the form.
- **The downloads** (HTML/PDF/EPUB): they print what question 24 listed.
- **The witnesses' sources**: 365 witnesses cite 62 `T13` records (DEEP, Greg, ESTC; 5 shared with
  performances), which S3 did not import.
- **Question 28**, whether readers see the original cast in the cast list: the switch prints it
  under the performance whichever way it is answered.
- **The 73 performances on versions we do not hold**: reported, skipped.
