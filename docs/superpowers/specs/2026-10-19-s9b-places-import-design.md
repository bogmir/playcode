# S9b — The place of action from FileMaker, and historical states

**Status:** designed 2026-10-19, not built. Slice S9b of
`../plans/2026-08-01-filemaker-import-slices.md`. Builds on S9 Phase 1, the gazetteer
(`2026-08-04-s9-places-design.md`), and takes its import shape from S3
(`2026-10-10-s3-witnesses-design.md`).

Where a play is set: Hamlet at Elsinore, in the Kingdom of Denmark; *Antony and Cleopatra* in
Rome, Alexandria, Athens and near Misenum. FileMaker has recorded this for 130 plays, with the
historical state each place belonged to at the time and every name in five languages. This slice
brings it into the plays we hold, once, and teaches Playcode one thing it cannot say today: the
historical state a place belonged to *in a given play*.

## Why now

- **The tables arrived on 2026-10-19**, in `doc/ctce_dades/` (git-ignored): `T10_ObraAccionLugar`
  (the links), `T10.1_Continente`, `T10.2_Pais`, `T10.3_Region`, `T10.4_Ciudad`, `T10.5_Locvaga`
  (the places, one table per level), `T10.11_NombreToponimo` (their names; `T10.11InsertNombre_Toponimo`
  is a byte-identical copy), `T10.X_TopoRelacion` (historical record → modern record),
  `T10.99_TipoToponimo` (the five levels).
- **The roadmap's plan is obsolete.** It meant to parse `pub_LugAccion`, the published HTML line,
  and guess which names in which languages were the same place. The tables say it outright.
- **The TEI corpus has no places.** None of the 372 production files has a `listPlace` or a
  `setting`; FileMaker is the only source.

## Decisions

From the project owner, 2026-10-19:

| # | Question | Answer |
|---|---|---|
| 1 | FileMaker's copies of one place | One Playcode place per real place. Old names become historical names. Pairs that are not the same place stay apart, named in a hand list |
| 2 | Historical states | Places of their own, type `country`, under their continent. A FileMaker "historical" country that is today's country under the same name merges with it |
| 3 | FileMaker's bracketed places | Vague places, not "mentioned": role `setting`, a fitting type, no coordinates. The generic ones are shared fictional places. "Sin especificar" is no link |
| 4 | How much of the gazetteer | Only the places our plays use, their parents and the modern records that give them their parents: about 105 |
| 5 | Language of names | Unchanged: the interface language on the play page, Spanish on the site |
| 6 | FileMaker's free text (`espacio`) | The link's note, as written |
| 7 | Existing places and re-runs | S3's rules: dry run first, existing links kept, existing places reused, each play imported once |
| 8 | Scope | Not the performance places (S5), not the genre tables (S8), not the plays we do not hold |
| 9 | Where "then part of" lives | On the play's link, as an optional historical state. The gazetteer stays today's geography |
| 10 | What readers see | The historical line, today's names in brackets where they differ |
| 11 | TEI | `<country ref>` inside the link's `<placeName>` |
| 12 | The word | *Historical state* (*estado histórico*) |
| 13 | A link to a whole state | Prints "Castilla, Europa"; a state does not record today's counterparts |
| 14 | The "Italian Peninsula" cities | Under Italia today; "Península itálica" is their links' historical state: "Verona, Península itálica, Europa (hoy Italia)" |

## Done when

- `mix playcode.import.places --dry-run` prints the plan; without `--dry-run` it writes it.
  `Playcode.Release.import_places/2` does the same on Fly.
- The plays we hold have FileMaker's places, each link with its historical state where FileMaker
  names one.
- A researcher sets or clears a link's historical state on the play's Places tab.
- `/plays/:code` and the static site print Hamlet's place as "Elsinor, Reino de Dinamarca, Europa
  (hoy Dinamarca)", and the English play page as "Elsinore, Kingdom of Denmark, Europe (today
  Helsingør, Denmark)". Spanish calls the town Elsinor today as well; FileMaker's modern record
  says so, and the brackets print only what differs.
- The TEI export writes the historical state and the TEI import reads it back;
  `complete_copy_test.exs` passes with the new column in its comparison.
- Renaming a historical state moves the `content_version` of every play whose links name it.

## How FileMaker codes places

Read this before the import rules; every rule answers something in it.

- **Five levels**, one table each, keyed by `(level, id)`: continent (1), country (2), region (3),
  city (4), vague place (5, *localización vaga*). Ids collide across levels (city 113 and region
  113 are different records), so a record is always named by both.
- **Each record carries its parents**: a city row has `_k_IdContinente`, `_k_IdPais`,
  `_k_IdRegion`. So whenever the country around a city changes, FileMaker makes a new city
  record. Rome is five records: in the Papal States (*La Calandria*, 0007), the Roman Republic
  (0038, 0240), the Roman Empire (0353, 0445, 0676), the Roman Kingdom (*Lorazia*, 0499), and
  modern Italy (no play). Madrid, Atenas, Sevilla and Teruel have three; Londres two; every vague
  place on our plays two.
- **Two worlds.** A play's link always points at a *historical* record, with its historical chain
  ("Elsinore, Kingdom of Denmark, Europe"). `T10.X_TopoRelacion` (126 rows) pairs historical
  records with modern ones ("Helsingør, Denmark, Europe"), and emothe.uv.es prints only the
  modern line. Every toponym row has `zz_esHistoricoValue = 1`, a constant, so the flag that
  means anything is `esHistorico` on the *names*: every name of a historical record has it.
- **Some modern records lack today's country.** Helsingør (city 92) sits straight under Europe.
  Mantua, Verona, Palermo, Florence, Genoa and Sicily (stored as a *city*) sit under the region
  "Península itálica", which has no country, and their links name no country either: "Verona.
  [Italian Peninsula]. []. Europe" (*Romeo and Juliet*). Sparta sits under "Antigua Grecia", also
  with no country; so do the regions Moldavia and Palestina.
- **The pairing table is incomplete and sometimes wrong.** Modern Helsingør (city 92), Santarém
  (111) and Faversham (202) exist, but Elsinore (113), Santarén (110) and Faversham (203) are not
  paired with them. Old Ford is paired with London, though it is a district inside London. The
  Republic of Venice is paired with Cyprus, because *Othello* links the Republic of Venice to mean
  "Cyprus, then Venetian". One Roman Republic record is paired with Italy and another with Israel.
- **Names.** `T10.11` has 1,775 rows: `_k_IdTipoToponimo` + `_k_IdToponimo` name the record,
  `_k_IdIdioma` the language (1 es, 2 fr, 3 en, 4 it, 5 pt, checked against Spain's five names),
  `nombreToponimo` the name (trim it: "Italy ", "Faversham ", "España "), `esAlternativo` an
  extra name (4 rows: Byzantium beside Constantinople). Most records have one name per language;
  41 have one name only (Illyria, English only). Five countries (1371–1374, 1380) have none.
- **A link** (`T10_ObraAccionLugar`, 228 rows) has `_k_IdObraTitulo` (the version: 38 is
  EMOTHE0038) or `_k_IdObraRepresentacion` (a performance; 49 rows, out of scope), the ids of
  its chain, `espacio` (free text), and two computed lines, `denominacionAntigua` and
  `denominacionActual`, useful for reports only. The linked place is the deepest id set:
  vague place, else city, else region, else country, else continent.
- **Brackets.** The published line puts brackets round a vague place: "( Miseno ) [Italy].
  Europe". All 11 bracketed links are vague places and all 11 vague-place links are bracketed.
  The roadmap read the brackets as "named, not staged"; that was wrong. The action happens there:
  the Forest of Arden in *As You Like It*, Bosworth in *Richard III*.

### The numbers, against the plays we hold

Measured against the 372 files in `doc/tei_corpus/`; the database also holds the test fixtures,
so the import's own report is the final word.

| | |
|---|---|
| Links on versions | 179, on 130 plays |
| Links on plays we hold | 150, on 106 plays (78 have one, 18 two, 5 three, 4 four, 1 five) |
| With `espacio` text | 40 |
| Bracketed (vague place) | 11 |
| Naming only a continent | 6 (Friar Bacon, King Lear, Othello, Sofonisba, A Game at Chess, one more) |
| Naming only a historical state | 18 (Castilla ×3, Reino de Inglaterra ×5, Reino de Escocia, Bretaña ×2, Reino de Nápoles ×2, Imperio romano, Bohemia, Illyria, República de Venecia ×2) |
| No place at all | 3: "sin especificar" (Endymion, Everyman) and an empty link (0653) |
| Places after merging | about 105: 46 cities, 19 historical states, 20 modern countries, 10 regions, 7 vague places, the continents |

## The model

One new column:

```
play_places
  historical_state_id   references places, on delete restrict; nullable
```

A link says: this play uses this place (`place_id`), and in this play the place belonged to that
historical state (`historical_state_id`). The state is a place in the gazetteer like any other,
type `country`, its parent its continent. The gazetteer itself stays today's geography: Rome's
parent is Italy, once, for every play.

- `PlayPlace.changeset` casts the column and refuses a state equal to the link's own place.
- `Places.get_play_place/2`, `list_play_places/1` and the loads behind the play page, the site and
  the TEI export (`Catalogue`'s `play_places: [place: :names]`) preload the state with its names.
- **The content-version trigger.** `place_changed()` (migration
  `20261005120000_track_play_content_version`) touches the plays whose `play_places.place_id` is
  the changed place or below it. It must also touch the plays whose `historical_state_id` is: a
  new migration replaces the function. `test/playcode/content_version_test.exs` gets a case:
  renaming a state moves the play that names it.
- **The gazetteer's play count** (`Place.play_count`, `/admin/places`) counts both columns, so
  Castilla shows its 26 plays. Deleting a state a link names is refused, as deleting a linked
  place is now (the foreign key is `restrict`; the list page's error names it).

### The glossary

`CONTEXT.md` gains:

> **Historical state** (*estado histórico*): the state a place belonged to at the time of a play —
> Castilla, Reino de Inglaterra, República romana — or the wider area the editors name when they
> name no state (Península itálica). A place in the gazetteer like any other; a play's link
> names it.
> _Avoid_: polity, then part of, país histórico.

## The import

`Playcode.Import.Places`, S3's shape: `load/1` reads the T10 tables through
`Playcode.Import.FilemakerXml`; `plan/2` decides, reading the database and writing nothing;
`apply_plan/2` writes the plan in one transaction; `report/1` prints it. The mix task
`playcode.import.places` and `Playcode.Release.import_places/2` call them as
`playcode.import.witnesses` and `import_witnesses/2` do.

### Which plays

The version id is the play code's number, as in S3 (`version_code/1`: 38 → EMOTHE0038), matched
against `Play.short_code/1`. A link on a version we do not hold counts in the report and is
skipped. A play already imported is skipped whole: one with a `filemaker` link, or with the
activity-log row `apply_plan/2` writes (`action: "import"`, `resource_type: "play_place"`,
`metadata: %{"source" => "filemaker"}`), which outlives the links. So a curator's deletions stick,
and a later run only picks up plays added since.

### From FileMaker records to places

Run over the records the held plays' links reach, their parents, and the records they pair with.
Nothing else in the 395 is imported.

1. **The referent.** A historical record's referent is its modern twin: the hand list first, then
   `T10.X_TopoRelacion`. A record with neither is its own referent, and the report lists it.
2. **The hand list** is a map in the importer, in the style of `Witnesses`'s `@types`. On our
   plays it holds:
   - Elsinore (city 113) → Helsingør (92); Santarén (110) → Santarém (111); Faversham (203,
     and any other historical Faversham record a held play reaches) → Faversham (202).
   - Old Ford is not London: its own place, type `district`, parent London.
   - *Othello*'s "[Republic of Venice]" (country-level, twice) is one link to Cyprus (FileMaker's
     modern country record Chipre, under Europe as FileMaker has it), historical state the
     Republic of Venice.
   - Sardis (132) and Carthage (219): FileMaker's modern line gives no country ("[]"); each is
     its own place under the link's continent.
   The hand list also corrects a modern record's parent or type where FileMaker leaves out
   today's country (decision 9: the gazetteer is today's geography):
   - Helsingør (92) → parent Dinamarca. Its names stay as FileMaker has them: Spanish "Elsinor" is
     the town's Spanish name today, not a historical one.
   - Esparta → parent Grecia.
   - Sicilia → type `region`, parent Italia.
   - Mantua, Verona, Palermo, Florencia, Génova → parent Italia. The editors framed them, and
     Sicilia, as the "Península itálica" rather than any state of the time; that framing becomes
     their links' historical state (decision 14, below).
   - Moldavia and Palestina stay as FileMaker has them, regions under their continent with no
     country: neither maps to one country today.
   The dry run lists every historical record that is twinless and not in the list, and every
   place that would end up with no country between it and its continent, so the list is complete
   before the real run. Continents are their own referents and are not reported.
3. **Historical states.** A country-level historical record is the same place as its modern twin
   when the two share a name in any language (Francia/Francia, España/España, Germany/Alemania by
   "Germany", Italy/Italia by "Italy", Portugal/Portingale by "Portugal"). Otherwise it is a
   historical state: its own place, type `country`, parent its continent. Two historical records
   with a name in common are one state (the two Roman Republic records). When the records of one
   state sit on different continents, the state has no parent: the Roman Republic is under Europe
   in one record (*Antony and Cleopatra*, *Julius Caesar*) and under Asia in the other (*Mariam*,
   0337; *Les Juives*, 0538), and it was both. Today's countries come in as places only as the
   parents of today's places; a modern country that is only a state's twin (the Czech Republic
   and Slovakia, for Bohemia) is not created, since a state records no counterparts (decision 13).
4. **Names.** A place gets its referent's names, each language's name preferred, the alternates
   as further names. Every other record merged into it adds, with `is_historical`, each name
   whose language has no name with the same text yet: Helsingør (Spanish "Elsinor" already) gains
   English Elsinore, Italian Elsinora and Portuguese Elsenor. A record
   whose names all repeat the referent's (the four historical Romes) adds nothing. A record with
   no name in any language is reported and skipped, with its links.
5. **Parents.** A place's parent is its referent's: a modern city's `_k_IdRegion`, else its
   `_k_IdPais`, else its continent, each resolved through these same rules. A historical state's
   is its continent. A twinless record outside the hand list gets the link's continent.
6. **Vague places** get their type from a hand list (the Forest of Arden and Birnam Wood `forest`,
   Bosworth and the Costa de Tarragona `other`, Miseno `town`, Amalec `city`) and no
   coordinates, which is how Playcode already says "not pinned to a point". The two generic ones,
   "Una isla" and "bosque pastoril", are `is_fictional`, each one place shared by every play that
   uses it (the three pastoral plays share one wood). "Sin especificar" is no place.
7. **The slug** (also the TEI `xml:id`) is `Places.slugify/1` of the Spanish name, or of the first
   name there is: `republica-romana`, `elsinor`, `illyria`.
8. **Existing places are reused.** Before creating a place the plan looks for one already in the
   gazetteer with any of its names, in any language, case-insensitive (`Places.find_by_name/1` per
   name, or a query in the same spirit). A match is linked as it is, never changed: the gazetteer
   is curated. The report lists every reuse.

### From FileMaker links to play links

- **The place** is the referent of the deepest record the link names.
- **The historical state** is the link's country when that country became a historical state
  (rule 3) and the link's place lies below it (a city, region or vague place). A link naming only
  a state links to the state, with no historical state ("Castilla, Europa"). A link whose country
  merged with today's (Francia) has none. A link whose FileMaker place sits under the region
  "Península itálica" (the two region records, 115 and 116, are one place, type `region`, under
  Europa) gets that region as its historical state: *Romeo and Juliet*, *El anzuelo de Fenisa*,
  *Every Man in His Humour*, *The Malcontent*, *La Mandragola*, *Rosmunda*, *Philaster*.
- **Role** `setting`, always; `mentioned` stays for curators.
- **Note**: `espacio`, trimmed, as written. A continent-only link with text (A Game at Chess,
  "A chessboard, representing England and Spain.") keeps it the same way.
- **Order**: FileMaker's record id (`_kp_IdObraAccionLugar`), after any links the play already has.
- **Skipped, and reported with the play and FileMaker's text**: a link to no place ("sin
  especificar"; Endymion's, which holds only a citation to Wiggins), an empty link (0653), a link
  to a place the play already has (the second of Othello's two "[Republic of Venice]"; its note,
  if it has one, joins the first's after a blank line).
- **Origin** `filemaker`. A TEI re-import deletes only `tei` links, so these survive it.

### The report

What the dry run prints, and the real run after writing: per play, its links as lines
(`EMOTHE0038  Roma — República romana`); then the places to create and the places reused; the
merges whose names differ (so a wrong merge is caught by eye: Elsinore → Helsingør); the twinless
records; the skipped links with their reasons; the versions not held; the plays already imported.

## What readers see

A link with a historical state prints the historical line, then today's names in brackets where
they differ:

| Play | Line |
|---|---|
| Hamlet | Elsinor, Reino de Dinamarca, Europa (hoy Dinamarca) |
| Hamlet, English play page | Elsinore, Kingdom of Denmark, Europe (today Helsingør, Denmark) |
| Mariam (a state with no continent) | Jerusalén, República romana (hoy Israel, Asia) |
| Romeo and Juliet (decision 14) | Verona, Península itálica, Europa (hoy Italia) |
| La verdad sospechosa | Madrid, Castilla, Europa (hoy España) |
| Antony and Cleopatra | Roma, República romana, Europa (hoy Italia) |
| Othello | Chipre, República de Venecia, Europa |
| As You Like It (no state) | Ardenas, Francia, Europa |
| 0394 (a whole state) | Castilla, Europa |

- **The historical line**: the place's historical name in the locale if it has one (else its
  usual name, `Places.display_name/2`), then the state, then the state's ancestors.
- **The brackets**: the place's own breadcrumb (`Places.breadcrumb/3`) minus every name already
  printed; no brackets when nothing is left. "hoy" is gettext ("today" in English).
- **A link with no state** prints `Places.breadcrumb/3` exactly as now.

One function builds the line for both the play page (`PlayShowLive`, `@locale`) and the static
site (`StaticSite.Components.place_links/1`, `"es"`), which print it where they print the
breadcrumb now, note and badges unchanged. If it lands in a module the site's
`StaticSite.Fingerprint` does not cover, add it there, or Generate will not rebuild the plays.

## The admin

The play's Places tab (`PlayPlacesLive`) gains, on each link's row, a "Historical state" /
"Estado histórico" field: the tab's place search, picking or clearing a place, saved with the
row's role and note. A state chosen from the browser is resolved with `Places.get_place/1` (the
access-control rule for ids from the browser). The row shows the line readers will see. Adding a
link stays as it is; the state is set on the row afterwards.

## TEI

The link's `<placeName>` in `<setting>` gains the state as a `<country ref>`; `<listPlace>`
includes the state (and its ancestors) like any other place the play needs:

```xml
<settingDesc>
  <listPlace>
    <place xml:id="europa" type="continent">
      <placeName xml:lang="es">Europa</placeName> …
      <place xml:id="italia" type="country">
        …
        <place xml:id="roma" type="city">…</place>
      </place>
      <place xml:id="republica-romana" type="country">
        <placeName xml:lang="es">República romana</placeName>
        <placeName xml:lang="en">Roman Republic</placeName> …
      </place>
    </place>
  </listPlace>
  <setting>
    <placeName ref="#roma" ana="setting">
      <country ref="#republica-romana"/>
    </placeName>
  </setting>
</settingDesc>
```

- A state that is not of type `country` is written as a nested `<placeName ref>` instead.
- The parser (`TeiParser`'s `setting_links/1`) reads either into the link's state, and
  `TeiImport.write_settings/2` resolves its slug as it resolves the place's.
- The link's note stays a bare `<note>` inside the `<placeName>`, after the `<country>`.
- `mix test --include slow` validates the export against the TEI schema; it must stay green.
- `complete_copy_test.exs` builds its rarer play's places with a historical state, so the column
  is compared like every other. `docs/stakeholder/ida-y-vuelta.html` gets the row: admin yes, TEI
  export yes, TEI import yes, play page and site yes, HTML/PDF/EPUB no (they print no places
  today, as before).

## Tests

Through the outermost API, as `CLAUDE.md` asks:

- **The import**: small hand-made T10 tables under `test/fixtures/filemaker/places/` (as S3's under `test/fixtures/filemaker/witnesses/`), run through
  `plan/2` and `apply_plan/2`, asserting on what `Places` and the play page give back: Rome once
  with two plays naming different states; Elsinore merged into Helsingør with its historical
  names; Old Ford apart under London; a same-name country merged; a vague place as a setting; the
  "sin especificar" link skipped and reported; a curator's existing "Roma" reused; a second run
  skipping the play; the dry run writing nothing.
- **The mix task** through `Mix.Task.rerun/2` in `test/mix/tasks_test.exs`.
- **The line**: the play page (`live/2`) and the site page show the five shapes in the table above.
- **The Places tab**: setting and clearing a state through the form; a state id from another
  place resolved or refused.
- **The round trip**: `tei_roundtrip_test.exs` (export, import, compare the state) and
  `complete_copy_test.exs`.
- **The trigger**: `content_version_test.exs`, renaming a state.
- `accessibility_test.exs` already renders the Places tab; the new field needs a label.

## Rollout

Dev has no database at the moment: rebuild it (the corpus, then S3 and S4, as `CLAUDE.md` says),
dry-run, read the report, settle the hand lists, run. Production after the deploy, through
`Playcode.Release.import_places/2`: dry run, read, run; then Generate on `/admin/export`, which
rebuilds every play with places. A forced TEI re-import from `doc/tei_corpus/` later keeps the
links (origin `filemaker`).

## Paperwork

- `../plans/2026-08-01-filemaker-import-slices.md`: S9b rewritten to point here; the "( Miseno ) =
  mentioned, confirmed" paragraph corrected; open question 4's `T10*` and genre-table items marked
  received (2026-10-19); S5's missing place table noted as found (the 49 performance links in
  `T10_ObraAccionLugar`).
- `docs/stakeholder/preguntas.html`: the tables-still-to-ask-for list.
- `CONTEXT.md`: *Historical state*.
- `docs/stakeholder/ida-y-vuelta.html`: the row.
- `docs/backlog.md`: matching imported places to Wikidata for coordinates and authority links,
  which this slice does not do. On completion, the slice moves to `docs/history.md`.

## Not in this slice

- **Performance places** (49 links): S5, waiting on question 12.
- **The genre tables** (`T01.42`, `T01.43`, `T14.1`): S8.
- **A state's today's counterparts** ("Castilla (hoy España)"): decision 13.
- **Coordinates and Wikidata links** for the imported places: a curator's job, a backlog item.
- **The 24 FileMaker plays we do not hold**: reported, skipped.
