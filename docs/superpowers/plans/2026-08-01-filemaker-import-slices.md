# FileMaker Import — Feature Slices (roadmap)

**Status:** written 2026-08-01, revised 2026-09-25.

| Slice | State |
|---|---|
| S0 — corpus baseline | **done** — `archive/README.md` |
| S0b — soft delete, re-importable plays | **done** — `archive/README.md` |
| S1 — work families and language | **done** — `archive/README.md` |
| Admin sync page (`/admin/filemaker`) | **done** — see below |
| S2 — version metadata | **in progress**, one field at a time; S2a, S2c done — `archive/README.md`, `../specs/2026-08-05-s2c-composition-date-design.md` |
| S2d | scoped below, **waiting on a question to the project** |
| S2e — `legacy_url` | **dropped** — derivable from code + filename, see below |
| S2f — titles | **dropped as an import** — nothing to import, folded into S7's cross-check |
| S3, S5–S8 | scoped below, each gets its own plan when it comes up |
| S4 — bibliography | **designed** 2026-10-07, after the project answered the research's questions: shared entries, a one-time import — `../specs/2026-10-07-s4-bibliography-design.md` (research: `../specs/2026-09-25-s4-bibliography-research.md`) |
| S9 — places | **Phase 1 done** (the app, no FileMaker code) — `CLAUDE.md` |
| S9b — `pub_LugAccion` import | **scoped, build it** — 138 links / ~94 places at full corpus; after the ~300 import |

Completed plans live in `archive/`, with exactly what shipped, the commit list, and what each
slice learned that its plan did not say. Read that before starting a new slice.

## How a sync is run

Two front doors onto the same pure domain layer (`Playcode.Import.Filemaker` +
`Playcode.Import.FilemakerSync`):

- `mix playcode.import.filemaker [--dry-run] [--force] [--path ...]` — the terminal path, for a bulk
  apply against a file on the server.
- **`/admin/filemaker`** — `PlaycodeWeb.Admin.FilemakerSyncLive`. Upload the NDJSON export, read the
  diff, tick individual conflicts, apply. Permission `:import_filemaker`, **admin only** and
  deliberately not researcher-level: a sync is corpus-wide and its force path overwrites curated
  research metadata across every play at once, where a TEI import replaces one named file's play.
  The upload is parsed inside `consume_uploaded_entries` and never stored anywhere — the plan lives
  in assigns and dies with the session.

Shipped 2026-08-03. Plan: `2026-08-03-filemaker-sync-admin-page.md`. Spec:
`../specs/2026-08-03-filemaker-sync-admin-page-design.md`. Commits `356c389`, `4fc3cea`, `f39d92f`,
`5663de5`, `3ec628e`, `2b8b6ae`, `8362e28`.

**Every later slice gets this page for free.** No template names a metadata column — field and value
labels go through `field_label/1` and `value_label/3`, both with catch-all clauses — so a new column
appears in the UI the moment `FilemakerSync.plan/3` puts it in `sets` or `conflicts`. Adding a
`field_label/1` clause is optional polish: it turns `"place of action"` into a translated label.

**Interactive companion:** `doc/filemaker-import-analysis.html` — field-by-field verdicts,
work families, and the exact corrections slice 1 makes. Regenerate after any corpus change:

```bash
python3 docs/build_import_analysis.py
```

---

## What we are importing from

`doc/w3emothe_T01_tituloEM.ndjson`, pulled from the FileMaker Data API at
`artelopefms.uv.es`. One file, two tables, each wrapped in its own `_meta` / `_end` envelope:

| Table | Records | Grain | What it holds |
|---|---|---|---|
| `T00_indiceEM` | 203 | one per **work** | `pub_listaObras`: rendered HTML listing every published version — language tag, code, title, credit + role (`ed.` / `tra.`), TEI download path |
| `T01_tituloEM` | 439 | one per **version** | 48 research fields: historical time, place of action, dating, witnesses, bibliography, performances, dramatis personae, genre codes |

An earlier CSV export of the same data is at `doc/emothe_export.csv`. **Do not use it** — FileMaker
flattened every repeating related record into one space-joined cell. The JSON keeps the
publication HTML (`<ul><li>` per related record), which is what makes slices S3–S5 possible at all.

**Second source, 2026-10-01: the master tables.** The NDJSON is the *web* database, `w3emothe`,
and its `pub_*` fields are a rendered snapshot that has gone stale. The structured records live in
the master database, `ctce_dades.fmp12`. Its bibliography tables were exported as FileMaker XML
(`FMPXMLRESULT`) into `doc/ctce_dades/`, which is git-ignored, and they now replace
`pub_BibSelecta*` as S4's source; see S4. The edition-credits tables (`T07.51*`) followed the same
day (see S7), then the city, publisher and information-source tables (`T13*`; see S4 and S5).
**The same request is worth making for S3 and S5**:
witnesses and performances are probably structured tables there too, and the dump would beat
parsing their rendered HTML in the same way.

### The master database, mapped *(2026-10-02)*

Five screenshots of `ctce_dades`'s relationship graph (Manage Database → Relaciones) are kept in
`doc/ctce_dades/relaciones/`. They show which tables hold what, so each slice can ask for exact
tables instead of describing data. Table purposes are **read from names and links, not
confirmed**.

Every play-level table hangs off the version id, `_k_IdObraTitulo` = `T01._IdTituloEmothe`. The
graph also has whole groups that assemble TEI (`Montaje del texto TEI completo`, `Cálculo de
códigos TEI-XML…`), which means **our TEI fixtures are FileMaker output** built from these tables.

| Slice | Tables | State |
|---|---|---|
| S2a historical time | `T09` (version ↔ `_k_IdTiempoHistorico`), `T09.1` (vocabulary) | done from the web export; not needed |
| S2c dating | `T06` (`_k_IdIntervaloFechaA` / `_Z`) → `T06.1` (date intervals) | done from the web export; `T06` would give structured intervals if wanted |
| S3 witnesses | not visible in the five screenshots | **ask** where the testimonios live |
| S4 bibliography | `T12` (links), `T12.1` (records), `T12.11` type, `T12.12` category, `T12.13` language, `T13.1` city, `T13.2` publisher | **received, complete** — `T12.1` with all 41 fields since 2026-10-02 |
| S4 modern editions | `T04` (version ↔ `_k_IdEdicionModerna`, with the play's volume and pages), `T04.1` (editions: city, publisher, language, type, siglum), `T04.11` types, `T04.12` languages | **received, complete** 2026-10-02 |
| S5 performances | `T11` (performance: company, `_k_IdCirEscenica`, information source, place, version), `T11.1` cast (actor, role), `T11.11` actor names, `T11.12` actor sex, `T11.22` actor roles, `T11.2` stage circumstance, `T11.3` company names, `T13` sources | `T13` (+`T13.3`) **received**; **ask** for the other seven. `T11.2` is probably the value list behind `bus_repCircunstancia` |
| S6 characters | `T07.31` (`_kp_IdPersonajeObra`, the speaker codes), `T07.311` (group ↔ member) | optional: would replace parsing `bus_personaje` for the completeness check; TEI stays the source |
| S7 credits | `T07.5`, `T07.51`, `T07.511`–`.514` | **received**; see S7 |
| S7 authors | `T02` (version ↔ author, with `_k_IdAutorFiabilidad`, `_k_IdAutorRol`), `T02.1` authors, `T02.2` attribution reliability, `T02.3` author roles | **ask** if attribution reliability is wanted; TEI carries `author_attribution` already |
| S8 genre | `T01.42_GeneroHier…` (name cut off at the screenshot's edge) | **ask**: the genre table replaces the request for the `bus_genero` value lists |
| S9b places | `T10` (version ↔ city, continent, vague location, country, region), `T10.11_Ciudad` / `_Continente` / `_Vaga` / `_Pais` / `_Region`, `T10.3_Region` (with ISO code and a language selector) | **ask**: replaces the request for a language-tagged `bus_lugAccion` |
| Text, licence, paratexts | `T07.x` (text rows, divisions, variants, speakers, stage-direction and metre types), `T07.3` paratexts, `T07.52`–`.54` notes, sources, licence | not needed: TEI stays the source of truth for the text |

**How to ask.** FileMaker's XML export writes only the fields chosen in the export dialog. Ask
for *Export Records → Move All* on each table, or failing that for a screenshot of the table's
*Campos* tab, which lists every field.

## The point of the exercise

The export is a **bootstrap, not a dependency**. When these slices are done, every field FileMaker
holds has a permanent column or table in our schema *and* a way for a researcher to type it,
correct it and extend it in the admin UI. At that point `w3emothe_T01_tituloEM.ndjson` can be
deleted: it is one convenient way to fill those fields the first time, not the only way, and not the
thing of record.

Two consequences that bind every slice:

1. **No import without an editor.** A slice that writes a field but gives no admin form is not
   done. Data you can only obtain by re-running an import against a file outside git is data you do
   not really own.
2. **An import must never silently destroy what a human typed.** Handled once, in S0b: rows carry
   an `origin`, the importer replaces only its own, and it says what it is about to replace before
   it writes.

## Scope decision

**Only plays we already hold — but that set is going to grow.** The export describes 379 published
plays; we hold 82. Every slice applies to plays that exist in our database, and nothing here creates
a play.

**Revised 2026-08-05:** importing the remaining ~300 plays is now intended (open question 5 is a
"when", not an "if"). That changes how slices get *sized*, not how they behave. A slice measured
against 82 plays can look not-worth-writing and be clearly worth writing at 379 — S9b was drafted as
dropped on exactly that mistake. **Size every remaining slice against both columns**, and prefer
running an importer once, after the big import, over running it twice.

Consequences, measured at the present 82:

| Set | Count | Notes |
|---|---|---|
| TEI files on disk (`test/fixtures/**/*.xml`) | 82 | 14 basenames appear in two directories; dedupe by code |
| …of which Artelope (`AL####`) | 19 | absent from this export entirely — they get nothing, ever, from FileMaker |
| …covered by the published index | 62 | these get language, work family, credits |
| …with a `T01` research record | 22 | hard ceiling for metadata, witnesses, bibliography, performances |
| Imported into `playcode_dev` | 82 | all of them, since S0 |

That 62 / 22 split is why the index slice went first: it is the only one that touches most of the
corpus, and it needed no new columns. Everything from S2 on is capped at those 22 plays, so the
panel and the tables it fills will be empty for 60 of 82 — by design, not by omission.

Per-field scale, measured 2026-08-05 against `playcode_dev` through `Filemaker.load_versions/1`.
**Read both columns.** The left is what a slice writes today; the right is what it writes once the
~300 plays land. Every slice grows 10–20×, which is the difference between "an afternoon of typing
beats an importer" and "an importer is the only sane option":

| Field | Slice | Plays now | Plays at 379 | Child records now → then |
|---|---|---|---|---|
| `bus_coleccion` | S2d | 22 | 438 | — |
| `bus_personaje` | S6 | 18 | 308 | 712 → **8450** names |
| `bus_tiemHistorico` | S2a *(done)* | 11 | 150 | — |
| `pub_BibSelectaCritica` | S4 | 7 | 106 | 198 → **2003** |
| `pub_testimonio` | S3 | 7 | 105 | 27 → **450** |
| `pub_EdModernas` | S4 | 6 | 120 | 84 → **823** |
| `pub_datacion` | S2c | 6 | 97 | 11 → 125 |
| `pub_LugAccion` | S9b | 6 | 101 | 9 → 138 |
| `pub_RepAntiguas` | S5 | 5 | 77 | 12 → **265** |
| `bus_genero` | S8 | 5 | 82 | — |
| `pub_BibSelectaTraduccion` | S4 | 4 | 61 | 29 → 187 |
| `pub_BibSelectaAdaptacion` | S4 | 1 | 17 | 7 → 50 |

Two things follow. **S4 becomes the biggest slice by an order of magnitude** — over 3000 citations
across four fields, where the present corpus suggests a few hundred. And **S6's completeness check
goes from 712 names to 8450**, which stops being something a human reviews row by row and starts
needing a real reconciliation UI.

## The join, once

```
T00_indiceEM.pub_listaObras   one <li> per published version
  → code (EMOTHE0053, HIE0393)     27 versions are HIE####, never format the number yourself
  = split_part(plays.code, '_', 1) our plays.code is the full filename stem
T00._IdIndiceCtce = T01._IdObraEmothe   the work family — validated, 152 works, 0 title disagreements
```

`_kp_IdIndiceEM` is **not** the work key (3 agreements out of 144). `pub_TituloWP` is wrong on
50 of 95 rows and must never be used.

## Slices

Each slice is a vertical: parse → persist → show. Each ends with something visible in the app.

### S0, S0b, S1 — done

Corpus baseline, soft delete and re-importable plays, work families and language. What shipped,
the commit list, and the traps each one hit: **`archive/README.md`**.

The one rule they leave behind that binds everything below: **a new curated `plays` column gets
appended to `@platform_owned` in `lib/playcode/import/tei_parser.ex`, or the next TEI re-import
erases it.** A new child table either carries `origin` or stays outside the importer's reach.

### S2 — Version metadata panel *(in progress, one field at a time)*

The research metadata that has no home in TEI. Taken **field by field**: each sub-slice is its own
migration, import, admin control and row in the panel, and ships before the next starts. The first
one builds the panel; the rest add rows to it.

Everything drawing on `T01` is capped at the 22 plays with a `T01` record. S2c is the exception:
its from/to come from the published *index*, which covers all 203 index records, so it reaches
plays no `T01` row mentions.

| | Field | Source | Coverage | State |
|---|---|---|---|---|
| **S2a** | `historical_time` + `historical_time_note` | `bus_tiemHistorico` + `pub_TiemHistorico` | 11 coded, 4 with a note (of 22) | **done** — `archive/README.md` |
| **S2c** | `composition_date_from/_to` + note | index header + `pub_datacion` | 7 of 82 today; 64 dated headers corpus-wide, 60 with a family head | **done** — `../specs/2026-08-05-s2c-composition-date-design.md` |
| S2d | `collection` | `bus_coleccion` | 22 | labels decoded below, **blocked** on whether the field is still wanted |
| ~~S2b~~ | `place_of_action` | `pub_LugAccion` | 6 | **split out** — toponym-based, now **S9**; the import is **S9b** |
| ~~S2e~~ | `legacy_url` | `pub_edicionWeb` href | 13 | **dropped** — derivable, see below |
| ~~S2f~~ | `original_title`, `title_sort` | `pub_TituloObra`, `T00.pub_tituloOrden` | 22 | **dropped as an import** — nothing left to import, see below |

**S2a — historical time. Done, 2026-08-02.** Spec:
`../specs/2026-08-02-s2a-historical-time-design.md`. Plan and outcome:
`archive/2026-08-02-s2a-historical-time.md` and the S2a section of `archive/README.md`.
Establishes three things every later sub-slice reuses:

1. `Filemaker.load_versions/1`, the `T01_tituloEM` reader, keyed by the code in the
   `pub_edicionWeb` href.
2. A **fill-only** sync policy with a `conflicts` bucket and `--force`. The S1 fields stay
   overwrite-always — the index is authoritative for those. Research metadata a curator edits is
   never stomped.
3. `<section id="meta-study">` on `/plays/:code`, hidden when empty, in the sidebar scroll-spy.

The vocabulary in the earlier draft of this roadmap was wrong. Correct, recovered by pairing the
code against the rendered label across all 439 rows: 1 Tiempo indeterminado, 2 Antiguo Testamento,
5 Edad Media, 6 Siglo XV, 7 Siglo XVI, 8 Siglo XVII, 9 Tiempo maravilloso (intemporal),
10 Antigüedad clásica, 11 Tiempo alegórico. Codes 3 and 4 do not occur.

- **Done when:** S2d has landed or been dropped — the panel renders on `/plays/:code` for
  the plays that have data, and admins can edit every field it shows. As of 2026-08-05 S2a and S2c
  have landed, S2b is now S9, S2e and S2f are dropped, so S2d is all that is left of S2 and it is
  waiting on an answer from the project.

#### S2c — composition date *(done, 2026-08-05 — see below for what shipped differently)*

6 of our 22 plays, 97 of the 439 export rows. Each `<li>` is a **competing dating**, and
`bus_datacion` is the expanded year union — a search index, not a source:

```
EMOTHE0010  <ul><li>¿1600? y ¿1601?</li>
                <li>posterior 1600 y hasta 1601</li>
                <li>alrededor de 1601</li></ul>
EMOTHE0337  <ul><li>anterior o hasta 1602 y hasta o posterior 1609</li><li>1605</li></ul>
EMOTHE0281  <ul><li>desde 1613 y hasta 1613</li></ul>
EMOTHE0346  <ul><li>1614</li></ul>
EMOTHE0341  <ul><li>¿1694? y ¿1605?</li></ul>            ← typo in the source
```

Vocabulary seen across all 97: `desde X y hasta Y`, `(desde o) posterior X`, `anterior o hasta X`,
`alrededor de X`, `¿X?` (conjectural), bare year.

**Proposal:**

- Three columns: `composition_date_from :integer`, `composition_date_to :integer`,
  `composition_date_note :text`.
- **from/to = min and max 4-digit year across *all* the `<li>`s.** Ordering-independent, because the
  `<li>` order carries no documented preference — and it agrees with `bus_datacion`, which is that
  same union. Do not try to model the qualifiers.
- **note = every `<li>` verbatim, joined with `"; "`.** Nothing is lost, and a curator reads the
  competing datings in the admin form.
- **Sanity guard: a span wider than 40 years is reported as a conflict and not written.** Catches
  EMOTHE0341, where `¿1694? y ¿1605?` would otherwise store 1605–1694.
- Public: one `#meta-study` row, `1605–1607`, collapsing to a single year when from == to, note
  beneath. Admin: two number inputs plus a textarea in the Research Metadata fieldset.
- Fill-only like every S2 field. All three columns go into `@platform_owned`.

**The question that needs answering before this is built:** the competing datings are
**unattributed** — the field names no scholar for any of them. If a dating has to carry its
attribution to be publishable, the shape is not three columns but a child table
(`play_datings(from, to, note, source, position)`) with its own admin CRUD, which makes this an
S3-sized slice rather than an afternoon.

Known parse edge, export-wide but outside our 22: EMOTHE0178 is `desde 1587 y hasta 92` — a
two-digit end year, so min/max yields 1587–1587. Acceptable; the note keeps the truth.

**What actually shipped diverges from the proposal above in two ways** — spec:
`../specs/2026-08-05-s2c-composition-date-design.md`, both worth carrying forward since S7 will
re-read the same header:

- **The from/to source is the index header, not `pub_datacion`.** `pub_datacion`'s min/max is the
  union of *competing* datings, which is wider than the accepted one — EMOTHE0038 is the case that
  proves it: `pub_datacion` spans 1605–1607 (a rejected dating starts a year earlier) but the index
  header says `=1606 - =1607`, the accepted range. `pub_datacion` becomes the note instead, falling
  back to the header verbatim when blank.
- **Head-only: a translation does not inherit its original's dating.** The index dating is per
  *work*, so writing it to every version in the family would put 1606 on a translation composed
  decades later. Written only where `relationship_type` is nil (the family head) — 7 of 82 plays
  today, not the 18 a naive per-version write would touch.

Applied to `playcode_dev`: `updated 7, failed 0` (EMOTHE0010, 0038, 0281, 0337, 0346, 0777 from the
index, plus EMOTHE0341 note-only), zero conflicts, idempotent on a second run. Answered without
waiting on the attribution question below — see open question 2.

#### S2d — collection *(blocked on a question to the project)*

22 of 22, and a bare numeric code with no text counterpart anywhere in either table. Unlike S8's
`bus_genero`, **no value list is needed from FileMaker** — the mapping is unambiguous once the code
is correlated against the play code prefix and `bus_idioma` across all 439 rows:

| Code | Rows | What they are |
|---|---|---|
| `1` | 358 | every `EMOTHE####`, all five languages — the EMOTHE library proper |
| `2` | 27 | every `HIE####`, all English — old-spelling quartos |
| `3` | 53 | `EMOTHE####`, 52 English + 1 Spanish — modern-spelling English |

Our 22: nineteen `1`, three `3` (EMOTHE0337, EMOTHE0341, EMOTHE0346), zero `2` — we hold no HIE
files at all.

**Blocked, on purpose.** What editorially distinguishes collection `1` from `3` is not recoverable
from the export, and if the distinction does not survive into the new system the right move is to
delete this sub-slice rather than build it. Ask the project two things: is the collection still a
meaningful grouping, and if so what is the `1` / `3` difference. The single `3` row carrying
`bus_idioma: 1` (Spanish, in a modern-spelling *English* collection) looks like a data-entry slip on
their side and is worth raising in the same message.

#### S2e — legacy URL *(dropped 2026-08-04)*

Not built. `pub_edicionWeb` is
`<a href='../biblioteca/textosEMOTHE/EMOTHE0053_Hamlet.php'>Enlace</a>` — code plus the filename
stem, both of which we already hold, against a base URL that has to be hardcoded either way. A
column would store nothing the play row does not already imply. If the link is ever wanted on the
public page it is a one-line helper, not a migration.

Only 13 of 22 carried an href in any case. Those nine blanks are why `version_code/1` in
`lib/playcode/import/filemaker.ex` falls back to `"EMOTHE" <> padded _IdTituloEmothe`, and that
fallback stays — it is what matches all 22 records, not just the published ones.

#### S2f — titles *(dropped as an import 2026-08-04)*

Checked against the schema, the TEI parser and `playcode_dev`: **there is nothing to import.**

- Both columns exist and both are already filled from TEI — `title[@key="orden"]` → `title_sort`,
  `title[@type="original"]` → `original_title` (`lib/playcode/import/tei_parser.ex:329-375`). Both
  round-trip through the exporter and both are editable on the play form.
- `title_sort` is populated on **82 of 82** plays. `original_title` is set on 36 and blank on 46 —
  blank exactly where the play *is* the original, which is correct, not a gap.
- **`pub_TituloObra` is not the original title.** It is the work-family title with the leading
  article stripped: `Le Cid` → `Cid`, `La vida es sueño` → `vida es sueño`,
  `La verdad sospechosa` → `verdad sospechosa`. S1 already links every version to its work through
  `parent_play_id`, so that value is derivable from data we hold and adds nothing.
- `T01.pub_TituloOrden` differs from ours only in convention — `"Cid, Le"` against our `"Cid Le"` —
  and ours is deliberate.

What the comparison *did* find is two defects on our side, both inherited from the TEI and both a
hand fix rather than an import: EMOTHE0254 has `title_sort: "JULES CÉSAR"` (shouting, from
`title[@key="orden"]` in the file) and EMOTHE0341 has `"Eastward Ho"`, having lost the `!`.

**"But the columns exist, so the importer can just fill them"** — it can, in about ten lines and no
migration, and it is still wrong. Measured against `playcode_dev` on 2026-08-04:

- `title_sort` is set on 82 of 82 plays, so fill-only never fires: **0 writes, 13 conflicts**, of
  which 11 differ only by FileMaker's comma (`"Cid, Le"` against our `"Cid Le"`). Accepting them
  under `--force` flips our sort convention to theirs — a style decision dressed as an import.
- `original_title` is blank on 12 of the 22, so fill-only *would* write, and **all 12 writes are
  wrong**: every blank is a play that *is* the original, and `pub_TituloObra` there is its own title
  minus the article. It would stamp `Le Cid` as a version of `Cid`.
- Corpus-wide, **0 of 82 plays have a `parent_play_id` and a blank `original_title`.** There is no
  row anywhere the import could legitimately fill.

The fill-only policy points the wrong way for both fields: the one that is safe to write is never
blank, and the one that is blank must stay blank. So this becomes a report, not a migration — folded
into **S7**, which is already a cross-check slice.

Two findings from that check that outlive S2f:

- **21 plays have `original_title` set but `parent_play_id` nil** — translations S1 never linked.
  Not fixable from this export and not fixable from our own data either: all 21 originals were
  title-matched against the corpus and **none of them is a play we hold**. Real gap in the work
  families, no cheap fix, tracked as open question 9.
- The lost punctuation on EMOTHE0341 and EMOTHE0211 (`Cortigiana 1525`, missing the parentheses) is
  a sort-title handling defect in the TEI import, worth fixing at the source rather than papering
  over per play.

### S3 — Witnesses (testimonios)

- **From:** `T01.pub_testimonio` — one `<li>` per witness: `<i>Title</i>. Author. City. Publisher.
  Year. Format. Notes.`
- **Into:** existing `play_sources` (title, author, pub_place, publisher, pub_date already fit),
  plus new `source_type` (from `bus_testSoporte`) and `format` columns
- **Scale:** 7 plays, 27 witness records **today; 105 plays and 450 records** once the ~300 land.
  Build it after that import, not before (question 5)
- **Cross-check:** `bus_testCiudad` / `bus_testAnyo` / `bus_testFormato` line counts match the
  `<li>` count on 75 of 105 rows across the whole export — use them to validate the parse, not as
  the source
- **Done when:** witnesses appear in the existing sources admin page and on the public page
- **FileMaker:** the witnesses' master table is not in the five relationship screenshots. Ask
  where the testimonios live before building, because a structured table would beat parsing
  `pub_testimonio`, as it did for S4. See "The master database, mapped"
- **Also check `T04.1.EdiMod_Referencia`** (84 modern editions, found during S4's design,
  2026-10-07). It reads like the edition a digital text was based on, for example
  `Lope de Vega: Los locos de Valencia, Hélène Tropé (ed.), Madrid, Castalia, 2003.`, which is
  `play_sources`' job rather than the bibliography's. Edition 44, the Oxford *Complete Works* on 9
  versions, holds nothing else, and FileMaker never prints it in the modern-editions list. S4 does
  not import the field, so read it from `T04.1` when building this slice

### S4 — Bibliography *(designed 2026-10-07 — `../specs/2026-10-07-s4-bibliography-design.md`)*

**The design supersedes the proposal below** where they differ. On the project's answers, entries
are corpus-wide and linked to plays, so one correction reaches every play. The import is a one-time
move, lists are alphabetical, and notes stay internal. The headlines below are the research as it
stood before those answers.

**Research: `../specs/2026-09-25-s4-bibliography-research.md`** — the dump's fields, what it still
lacks, the proposed table, TEI mapping. Headlines:

- **From:** the FileMaker master tables, dumped from `ctce_dades.fmp12` on 2026-10-01 and kept
  git-ignored in `doc/ctce_dades/`. `T12.1_BibliografiaSelecta` holds 2,640 structured
  records, and `T12_ObraBibliografiaSelecta` holds 2,658 links to versions. The join is
  `_k_IdObraTitulo` = `T01._IdTituloEmothe`, and it reproduces the published criticism exactly on
  101 of 106 versions. `T01.pub_*` (the web export) is fully superseded.
- **Structured, in two levels:** `Autor`/`Titulo` (article, chapter) and `Autor2`/`Titulo2` (book,
  journal), plus year, volume, pages, URL, note, and codes for category, type (10) and language
  (`5` is Portuguese).
- **Complete for three kinds** since 2026-10-02. The first export had carried 26 of `T12.1`'s 41
  fields. The full export adds editors and translators at both levels (`Editor`/`Editor2`,
  `Traductor`/`Traductor2`), the issue (`Ejemplar`), the original title, the edition and the
  volume count. With `T13.1_Ciudad` and `T13.2_Editorial`, every piece of every printed citation is
  in a column: 519/519 `Ed.`, 229/229 `Tra.`, 512/514 issues.
- **Modern editions complete too** (`T04*`, 2026-10-02):
  - 985 editions and 968 links, reproducing the website's list exactly on 118 of 120 versions.
  - Each link carries the play's own volume and pages within the edition. Editions carry a
    siglum (`ARD3Q2`, `RSC`), the code an apparatus cites them by.
  - 23 editions are shared, up to 11 ways (complete works, anthologies). Per-play rows are
    still proposed; promote to shared entries if corrections to them prove common.
- **The earlier "~690 never-rendered records" was a stale search index** (`bus_criticaAnyo`).
  The real unpublished set is 118 records newer than the web export, plus 86 with no category.
- **Order is computed** — year descending, 99 of 102 published lists. No `position`, no reorder
  UI.
- **Into (proposed):** `play_bibliography`, one row per (play, record):
  - `kind`, `pub_type`, `language`
  - the two levels as `analytic_*` / `monogr_*`
  - volume, issue, pages, place, publisher, `year_text`, plus `year` for sorting
  - `filemaker_id`, `origin`

  The sync is keyed on `(play_id, filemaker_id)` and fill-only at the row level. Citations are
  printed from the columns, with FileMaker's own rendering (2,633 records) as the renderer's test oracle;
  kept for display.
- **TEI:** none of the 96 fixtures has a secondary bibliography. Its home is
  `text/back/div[@type="bibliografia"]/listBibl/biblStruct`, **not** `sourceDesc`: the parser
  already reads `sourceDesc/listBibl/bibl` into `play_sources`. The parser ignores `<back>` today,
  which also silently drops the two fixtures' `epilogo` divs.
- **Scale:** 325 records on 14 plays **today** (232 crítica, 36 traducción, 7 adaptación,
  50 uncategorised). Five of those plays, EMOTHE0659/0670/0749/0777/0779, are not in the web
  export, so only the dump reaches them. **2,565 linked records on 142 versions** at full corpus,
  plus the 823 modern editions. This is still the largest remaining slice. Build it after the
  ~300-play import (question 5)
- **Done when:** a bibliography section renders per play grouped by kind, **and** admins can add,
  edit and delete entries without an import
- **S0b:** the table carries `origin`. A TEI re-import replaces only that play's `tei` rows, and
  skips an entry that already exists under another origin — S9's leave-alone rule

### S5 — Historical performances

- **From:** `T01.pub_RepAntiguas` — labelled `<b>Company</b>`, `<b>Venue</b>`, `<b>Date</b>`,
  `<b>Cast</b>` (nested `<ul>`, one `<li>` per actor), `<b>Location</b>`, `<b>Venue type</b>`,
  `<b>Note</b>`, `<b>Information source</b>`
- **Into:** new `play_performances` + `play_performance_cast` tables
- **Scale:** 5 plays, 12 performances **today; 77 plays and 265 performances** once the ~300 land,
  plus their cast rows. Build it after that import (question 5)
- **Sources:** CATCOM and Wiggins, *British Drama 1533-1642* — keep the attribution text, it is
  a licensing requirement of CATCOM
- **The source table has arrived** (2026-10-01, `doc/ctce_dades/T13_FuenteInformacion.xml`).
  - **Shape:** 378 records shaped like S4's bibliography (`Autor`/`Titulo`, `Autor2`/`Titulo2`,
    year, volume, pages, URL, note) with its own type list (`T13.3_FuenteInfoTipo`, 9 types),
    sharing the `Ciudad`/`Editorial` lookups. 17 records are empty.
  - **Match:** its short rendering (`_tc_FueInf_ComposicionBreve`) equals the published
    `Information source` exactly on 219 of the 242 entries in `pub_RepAntiguas` — Wiggins,
    Chambers, Child's *Stage-History of Hamlet*, CATCOM.
  - **Model:** so the performance's source becomes a reference to a source record, not a
    string.
  - **Still needed:** the performances table itself, with its link to `FuenteInformacion` and
    its cast, which has not been exported yet. Ask for it in the same message as S4's
    remaining tables
- **Done when:** performances render per play with their source attribution, **and** admins can add
  a performance and its cast by hand — the 12 rows FileMaker holds are a seed, not the ceiling
- **S0b:** both new tables stay outside the importer's reach

### S6 — Character reconciliation

**FileMaker:** the master database has a characters table, `T07.31` (`_kp_IdPersonajeObra`,
which feeds the TEI speaker codes), plus `T07.311` for grouped speakers. It is optional: it would
replace parsing `bus_personaje` for the check below. See "The master database, mapped".

Not an import: TEI stays the source of truth for characters. `T01.bus_personaje` (one name per
line, 18 of our 22 plays) is a completeness check — flag characters present in FileMaker but
missing from the imported cast list, and vice versa. Feeds the "review character in text" UI
already on the roadmap in `CLAUDE.md`.

**Scale changes what this has to be.** 18 plays and 712 names today; **308 plays and 8450 names**
once the ~300 land. At 712 a curator reads the report; at 8450 they cannot, so the output has to be
per-play, sorted by how bad the mismatch is, and dismissible — a reconciliation screen, not a
printout. Also still blocked by question 7: a TEI re-import replaces the whole cast list, so any fix
a curator makes here is lost on the next import.

### S7 — Editor & translator credits

Cross-check `play_editors` against the credits printed in the index (`Tronch, Jesús, ed.`,
`Hugo, François-Victor, tra.`). Same parse as S1, kept separate so S1 stays small.
`bus_autorAdaptacion` supplies the sort form of each name, `bus_traductor` the display form.

**Carries the dropped S2f with it:** report where our `title_sort` / `original_title` disagree with
`T01.pub_TituloOrden` / `pub_TituloObra`, same as the credits comparison and for the same reason —
a difference is a question for a curator, not a write. Two known hits already: EMOTHE0254 and
EMOTHE0341, see S2f.

**The master credits tables arrived 2026-10-01** (`doc/ctce_dades/T07.51*`, measured the same day).
They are the source FileMaker generated each TEI header's `<respStmt>` from:

- `Persona` (55 people), `Rol` (4 roles: Edición digital, Revisión y edición, Revisión técnica,
  Traducción) and `Grupo` (12 research groups: Artelope, Prolope, Griso, Dicat…).
- `PersonaRol` holds one credit each, with a person, role and group, plus `TeiPerRol_Xml`, the
  rendered `<respStmt>`. 462 rows.
- `Responsables` links credits to versions through `Tei_Metadatos_T01::_kp_IdObraTitulo`, which
  is the same EMOTHE id as `T01._IdTituloEmothe`.
- **458 credits on 409 versions**, at most 2 per version, 453 of them *Edición digital*.
  Integrity: 1 credit has no `Responsables`, 3 sit on a `Responsables` with no version, and 7
  point at a missing or blank person.
- **Redundant with TEI for what we hold.** On 60 of our 63 EMOTHE plays, every credit already
  appears in the TEI header once accents and spaces are normalised (`Jesús` vs `Jesus`). Two of
  the other three carry a blank person in FileMaker. The research group is in TEI too: all 82
  fixtures carry `<orgName>`, which the parser imports as `organization`.
- **No route to Artelope.** `AL####` numbers are not these ids: on the 9 `AL` plays where the
  number collides with a credited id, the names never match the TEI.

So for S7 these tables replace parsing the index's `ed.`/`tra.` credits. A cross-check report is
the whole job, unless the plays arriving with the ~300-play import turn out to have TEI headers
that are thinner than FileMaker's. `Persona` is also the clean, accented form of each name, which
is worth having if `play_editors` is ever normalised into a people table.

These are **not** the people S4 needs. The translators and editors of *cited* works are a
different relation, still unrequested on the FileMaker side.

### S8 — Genre *(blocked)*

**FileMaker (2026-10-02):** ask for the genre table itself, `T01.42_GeneroHier…` in
`ctce_dades` (its name is cut off in the screenshot), instead of the value lists below. Artelope
has its own, see the end of this section.

`bus_genero` and `bus_generoAnnals` are bare numeric codes with **no text counterpart anywhere in
either table**. Send the value lists for `bus_genero`, `bus_generoAnnals` and
`bus_repCircunstancia`. Everything else the CSV was missing, the JSON supplied.

**Artelope has its own FileMaker database, `al_dades` (Artelope FMS)**, seen 2026-10-02 in three
screenshots kept in `doc/al_dades/`:

- Its genre is a six-level hierarchy, layout `t14.1_GENERO` with fields
  `ArgGenero1`…`ArgGenero6` and `ArgGeneroNota`, for example *Drama > historial > profano >
  hechos particulares > honra villana*.
- The vocabulary has 44 combinations (`t14.1_GENERO_LISTA`), set on 591 records keyed by
  `IdFicha`.
- This changes the roadmap's standing assumption that `AL####` plays "get nothing, ever, from
  FileMaker": a second database exists, and it is reachable.
- Not yet checked: whether `IdFicha` is the number in `AL####`. The two fichas shown, 561 and
  640, are not plays we hold. Worth a separate scoping pass: genre is the obvious first field,
  and `al_dades` may well hold the Artelope equivalents of S2–S9.

Exactly which codes need a label, measured 2026-08-05 — the value lists can be checked against this,
and anything outside it is a code we never see:

| Field | Distinct codes, corpus-wide | Codes our 22 actually use | Multi-valued? |
|---|---|---|---|
| `bus_genero` | 12 — `3 5 6 8 10 15 16 17 19 20 21 23` | `5`, `20`, `21` | yes, 17 rows carry 2+ |
| `bus_generoAnnals` | 14 — `1 2 3 5 6 7 9 10 11 13 14 15 16 17` | `5`, `16`, `17` | no, always one |
| `bus_repCircunstancia` | 7 — `1 2 3 4 5 6 8` | `2 3 5 8` | yes, 59 rows carry 2+ |

`bus_genero` being multi-valued is a shape decision, not just a label one, and the ~300-play import
settles it: **a single `genre` string column is not enough.** Our five plays each carry one code
today, but 17 export rows carry two or more, and 82 plays get a genre once the rest land. A play with
`20/21` needs either a `{:array, :string}` or a join table — pick when the value lists arrive and the
labels show whether the two codes are alternatives or genuinely co-held.

`bus_repCircunstancia` belongs to **S5**, not here — it qualifies a performance, so it lands on
`play_performances` rather than the play. It is listed with the genre request only because it is the
third code list to ask for in the same message.

What is blocked is the *import*, not the field. An editable `genre` on the play form can ship
whenever it is wanted. The "5 plays is an afternoon of typing" argument **expires with the ~300-play
import** — at 82 plays with a genre the value lists stop being a convenience and become the
difference between an import and a fortnight of data entry.

#### The `bus_lugAccion` request *(added 2026-08-04, ask in the same message as the value lists)*

**Superseded 2026-10-02.** The relationship graph shows places as structured tables: `T10`
(version ↔ city, continent, vague location, country, region), `T10.11_Ciudad` / `_Continente` /
`_Vaga` / `_Pais` / `_Region`, and `T10.3_Region` with an ISO code and a language selector. Ask
for those instead. They should give the containment chain and the per-language names that the
request below was trying to recover, without the positional guessing. See "The master database,
mapped". The analysis below stays as the reason the tables are worth having.

Grouped with S8 only because it is the **second** thing we need from the FileMaker side and one
message should carry both. It has nothing to do with genre. It **gates tier 2 of S9b** — the
historical polities — and it is also the cleanest fix for S9b's cross-language dedupe problem, since
language-tagged names remove the guessing entirely. Kept here so the ask does not get lost.

`bus_lugAccion` sits beside `pub_LugAccion` and holds the same places **as a containment chain with
a name per language**. EMOTHE0038, verbatim, newlines as in the export:

```
Europe / Europa / Europe / Europa / Europa
Roman Republic / República romana / République romaine / Repubblica romana / República Romana
Rome / Roma / Rome / Roma / Roma
                                          ← blank line ends the chain
Africa / África / Afrique / Africa / África
Ptolemaic Egypt / Egipto ptolemaico / Égypte ptolémaïque / Egitto tolemaico / Egito Ptolemaico
Alexandria / Alejandría / Alexandrie / Alessandria / Alexandria
```

This is better than `pub_LugAccion` in two ways that matter to us. It names the **historical**
polity — `Roman Republic`, where `pub_LugAccion` flattens to modern `[Italy]` — and it carries the
names in five languages, which is exactly `place_names`.

**Why we cannot use it as exported.** The grouping is positional with no delimiter, and blank values
are *dropped* rather than held as empty slots, so the block length varies and the boundaries are
unrecoverable:

```
Europe / Europa / Europe / Europa / Europa / Germany        ← 6 lines: Germany has 1 name, not 5
Europe / … / Kingdom of England / Reino de Inglaterra /
         Royaume d'Angleterre / Regno d'Inghilterra /
         England / Reino da Inglaterra                      ← 11 lines: England has 6, not 5
```

**68 of 227 groups (30%) are not a multiple of five**, so no chunking rule recovers which line
belongs to which place, or in which language. Measured across all 439 rows.

**What to ask for:** the same field with each name tagged by language and grouped by place — one
row per (place, language, name), or any JSON/CSV shape that keeps those three together. With that,
`Places.find_or_create_by_slug/1` plus `place_names` takes it directly and the historical polities
land as real places, which no Wikidata lookup gives us for free (Wikidata returns modern `Italy`
for Rome's `P17`). Without it, curators enter the handful of historical names by hand, which the
schema already supports.

Worth saying in the message that this is a **contribution to the gazetteer**, not a blocker: their
five-language place names are research work we would otherwise redo.

### S9 — Place of action *(was S2b; Phase 1 shipped 2026-08-04)*

**Spec: `../specs/2026-08-04-s9-places-design.md`.** Split out of S2 because it is not a text field
and turned out to be a feature rather than a column: a corpus-global gazetteer with a three-layer
place / place-name / mention model, Wikidata as a swappable authority, and TEI `<listPlace>` +
`<setting>` in both directions. **Phase 1 shipped no FileMaker code**, on purpose, and
`plays.place_of_action` was never created. See `Playcode.Places` in `CLAUDE.md`.

Two things were called "Phase 2" and they are not the same work, so they are split here:

- **In-text mentions and the rest of the app work** — `<placeName ref>` in the body, an
  `element_places` table, the tagging UI, map rendering from the stored coordinates,
  catalogue browse-by-place, multiple authority links per place. **Not a FileMaker slice at all**;
  it touches no export field and belongs in its own spec. Scope is recorded in `CLAUDE.md` under
  "Places Phase 2". Not planned as of 2026-08-04, deliberately.
- **S9b, the `pub_LugAccion` import** — what this roadmap promised. **Scoped, build it, see below**,
  after the ~300-play import and ideally after `bus_lugAccion` arrives.

#### S9b — the `pub_LugAccion` import *(scoped 2026-08-05, build it)*

**Size this against the future corpus, not the present one.** The plan is to import the other ~300
plays (open question 5), so the target is the whole field, not the slice of it we happen to hold
today:

| | Today (82 plays) | Full export |
|---|---|---|
| Plays with place data | 6 | **101** |
| Place links (`<li>`) | 9 | **138** |
| Distinct settlements | ~10 | **58** |
| Distinct countries/regions | 6 | **31** |
| Continents | 3 | 5 |
| **Gazetteer rows** | ~16 | **~94** |

At 9 links, hand entry wins and this is not worth writing. At 138 links and a 94-row gazetteer it
is clearly worth writing, and **the earlier "drop it" verdict was sized against the wrong corpus.**
Max 5 places per play; `London` appears in 14 plays, `Madrid` in 9, `Rome` in 6 — which is precisely
the shared-referent case the corpus-global gazetteer was built for.

**It is one grammar, not fifteen shapes.** The fifteen "shapes" are one production with optional
parts:

```
[ "(" ] settlement [ ")" ] "." { "[" region "]" "." } continent { "." note }
   ↑ mentioned, not staged        ↑ 0, 1 or 2 of these      ↑ freeform Spanish
```

Verified against all 138 `<li>`: **135 parse cleanly**, with settlement, region chain, continent and
`mentioned` flag each landing in the right slot. Distribution: 95 have a settlement and 43 do not
(`[Germany]. Europe` is a country-level setting, which the model handles — a link to the country
place); 116 have one bracketed region, 8 have two (`[Kent]. [United Kingdom]`), 14 have none;
33 carry a trailing freeform note; 5 are parenthesised.

The 3 that do not parse are the ones that *should* be reported rather than guessed at:

```
( bosco pastorale )      ← fictional, no continent → is_fictional, no parent
( An island )            ← same
. The play is "based on mythological events…" (Wiggins, 2013)   ← a citation, not a place
```

**One parse trap, found and fixed while measuring.** A parenthesised settlement is not always
followed by a `.`, so splitting on `.` first yields `Miseno ) [Italy` as the settlement and loses the
country. Peel the `( … )` before splitting. `( Miseno ) [Italy]. Europe`, `( Forest of Ardennes )
[France]. Europe` and `( Costa de Tarragona ) [España]. Europa` all depend on this.

**`( Miseno )` → `role: "mentioned"` is confirmed**, no longer "unconfirmed": five `<li>` use the
parenthesis and every one reads as named-not-staged. Phase 1 already has that role.

**The hard part is dedupe across languages, not parsing.** The same referent arrives under different
surface forms depending on the row's language, and a naive `slugify` would create a row for each:

```
Europe / Europa              Africa / África / Afrique
Spain / España               Germany / Alemania
United Kingdom / Reino Unido Italy / Italia / Italie / Italian Peninsula / Península itálica
```

Import blindly and the gazetteer holds ~94 rows for perhaps 60 real referents — the exact drift
Phase 1's no-name-column design exists to prevent, reintroduced by the importer. So:

- `find_or_create_by_slug/1` **is not sufficient on its own** here. It matches on slug, and
  `europe` and `europa` are different slugs.
- The importer needs a **name-based lookup across languages** before it creates: `Places.find_by_name/1`
  already exists and is the seam, but it is exact-match and single-language. Widening it, or adding
  an alias pass, is the real work of this slice.
- **`Italian Peninsula` vs `Italy` is an editorial question, not a string one** — they may be
  deliberately different referents. Report the pair, do not merge it automatically.

**Two tiers, and tier 2 is the one worth waiting for.** Wikidata's `P17` gives Rome's parent as
modern `Italy`; `bus_lugAccion` says `Roman Republic`, which is the editorially right answer for a
play set in antiquity, and it carries the names in five languages — which would also *solve the
dedupe problem above*, because each name arrives language-tagged instead of having to be guessed.

| Play | `pub_LugAccion` | `bus_lugAccion` |
|---|---|---|
| EMOTHE0010 | `[Denmark]` | Kingdom of Denmark |
| EMOTHE0038 | `[Italy]`, `[Egypt]` | Roman Republic, Ptolemaic Egypt |
| EMOTHE0281/0341/0346 | `[United Kingdom]` | Kingdom of England |
| EMOTHE0337 | `[Israel]` | Roman Republic |

- **Tier 1** — parse `pub_LugAccion`, create places from the modern names, link with `role`,
  `position` and `origin: "filemaker"`, report every unparsed `<li>` and every cross-language
  near-duplicate. Buildable from the export as it stands.
- **Tier 2** — needs the language-tagged `bus_lugAccion` (request under S8). Replaces the modern
  country with the historical polity and loads the five-language names. Verified the schema already
  supports it with no change: `Europe > Roman Republic > Rome` resolves through `ancestors/2`, and
  `place_names.is_historical` carries `Roman Republic` / `República romana` / `Repubblica romana`.

**Ordering:** ask for `bus_lugAccion` first. If it arrives, build once and the dedupe problem largely
dissolves. If it is refused, build tier 1 with the cross-language matching done by hand-reviewed
report — and expect that report, not the parser, to be where the time goes.

**Do not build this before the ~300 plays are imported** (open question 5). Running it against 82
plays writes 9 links and then has to run again; running it once, after, writes 138 against a corpus
that can actually use them.

## Shared conventions

Fixed once here so every slice looks the same:

- **Module namespace:** `Playcode.Import.Filemaker` (pure parsing, no DB) and
  `Playcode.Import.Filemaker<Thing>Sync` (reads the DB, writes the DB). Parsing modules must be
  testable without a database.
- **HTML parsing with `Regex`.** There is no HTML library in `mix.exs` and this is a fixed,
  machine-generated markup shape. Do not add Floki for it.
- **Dry run first.** Every sync mix task takes `--dry-run` and prints the report without writing.
  Since 2026-08-03 the same review happens in the browser at `/admin/filemaker`, which previews
  before it applies and can accept conflicts one at a time. That page is the review mechanism for
  the researchers; `--dry-run` is the one for us.
- **Never create plays.** A FileMaker record with no matching play is reported as unmatched and
  skipped. No stub plays, ever.
- **Never touch Artelope.** `AL####` codes are absent from the export; they must come out of every
  report as "not in index", not as an error.
- **Every write is logged** via `Playcode.ActivityLog` with `action: "update"` and
  `metadata: %{source: "filemaker_index"}` — the allowed action list in
  `Playcode.ActivityLog.Entry` is `create update delete import export role_change`, so do not invent
  a new action.
- **Idempotent.** Running a sync twice changes nothing the second time; the second report is all
  "unchanged".
- **Two write policies, on purpose.** Fields the index is *authoritative* for — `language`,
  `relationship_type`, `parent_play_id` — are overwritten whenever they differ. Fields a curator is
  expected to *edit* — everything from S2 on — are fill-only: written when blank, reported as a
  conflict when they differ, overwritten only under `--force`. Introduced in S2a. This is the
  "bootstrap, not a dependency" rule made operational; without it the second import undoes a
  researcher's afternoon.
- **New curated column ⇒ `@platform_owned`.** Append it in `lib/playcode/import/tei_parser.ex`, or
  the next TEI re-import erases it. Add the regression test in the same commit.

## Open questions

Ordered by what is actually blocking work.

1. **Is `collection` still wanted, and what separates code `1` from `3`?** Blocks S2d, and the
   answer may delete it. See S2d for the decoded label table and the one suspect row.
2. **Do competing datings need per-dating attribution?** Closed for S2c, open for whatever comes
   next. S2c shipped as three columns without answering it: the export attributes none of its 97
   `pub_datacion` rows, so there is nothing to attribute yet, and `play_datings(from, to, note,
   source, position)` stays an additive migration if attribution ever arrives. The question now
   applies to a future dating source, not this one. See S2c.
3. ~~**Place of action requirements** — S9.~~ **Closed 2026-08-04** by building it: S9 Phase 1
   shipped the gazetteer. The import is S9b, scoped and buildable — 6 plays, 9 links — and waits on
   the `bus_lugAccion` request in (4) so it can load the historical polities in one pass.
4. **The remaining FileMaker tables** — S3, S4, S5, S8, S9b. Since 2026-10-02 these can be named
   exactly; see "The master database, mapped". One message should carry all of it:
   - ~~**S4:** `T12.1` with every field~~ — received 2026-10-02, all 41
   - ~~**S4 modern editions:** `T04`, `T04.1`, `T04.11`, `T04.12`~~ — received 2026-10-02
   - **S5:** `T11`, `T11.1`, `T11.11`, `T11.12`, `T11.2`, `T11.22`, `T11.3`
   - **S8:** the genre table (`T01.42_GeneroHier…`), instead of the value lists
   - **S9b:** `T10`, `T10.11_*`, `T10.3_Region`, instead of a language-tagged `bus_lugAccion`
   - **S3:** where the testimonios live; not in the screenshots
   - **S6 (optional):** `T07.31`, `T07.311`
   - **When asking, name the fields or say *Mover todo*:** the export dialog reuses the previous
     field selection, which is how `T12.1` first arrived with 26 of its 41 fields
   - **S4 questions** for the project, not the export: what the 86 uncategorised records are,
     whether the 118 records newer than the web export are ready to publish, whether the
     broken links can go. See the S4 research doc.
5. **Importing the other ~300 plays.** *Intended as of 2026-08-05 — a "when", not an "if", and now
   the sequencing constraint for most of what is left.* The index gives a download path for every
   published play (`textosXML/<code>_<Name>.xml`). Still needs permission and a fetch rate from the
   project, but the roadmap should now assume it happens.

   **It should land before S3, S4, S5, S6 and S9b.** Each of those writes child rows per play, so
   running one against 82 plays writes a tenth of its rows and then has to run again over a corpus
   ten times larger — with the second run's dedupe and conflict reporting untested at that scale.
   The scale table under "Scope decision" has the multipliers. S2c, S2d and S8 write a column on the
   play and are indifferent to the ordering.

   Two things to check when it happens, both cheap now and expensive later: whether the 21 unlinked
   translations (question 9) close once their originals exist, and whether `AL####` stays at 19 or
   the Artelope files also grow.
6. **`bus_publicada` vs `is_complete`.** 61 rows are flagged published, but 301 have a real
   web-edition href. Our `is_complete` gates the static-site export, so nothing should write to it
   automatically.
7. **Character re-import identity.** A TEI re-import still replaces the whole cast list, so a
   manual `xml_id` fix on a character is lost. Protecting those needs per-character identity
   matching — bigger than S0b, not scoped anywhere. Blocks nothing in S2–S5; blocks S6.
8. **Multi-`<li>` historical times.** S2a takes the first `<li>` and logs; two of 439 export rows
   carry two historical periods. S2c shipped as three columns, not a child table, so this stays
   open on its own; revisit if a future dating source forces `play_datings` into existence (see
   question 2).
9. **21 unlinked translations.** They carry an `original_title` but no `parent_play_id`, and none of
   their originals is a play we hold, so neither FileMaker nor our own data can close the family.
   Either those originals get imported (see question 5) or work families stay partial and the UI has
   to say so. Found while dropping S2f.

Closed since 2026-08-01: the multi-valued `pub_datacion` shape shipped as S2c, three columns, no
attribution (2); `legacy_url` (S2e) and the title import (S2f) are dropped outright; and the
place-of-action question (3) is closed by S9 Phase 1 shipping, with the import scoped as S9b.

**A measurement trap, recorded because it cost a wrong verdict on 2026-08-04.** Nine of the 22
matched `T01` records have an **empty `pub_edicionWeb`** and are reachable only through
`version_code/1`'s numeric fallback: 0211, 0281, 0286, 0305, 0337, 0341, 0346, 0502, 0542. A quick
script that matches on the href alone silently finds 13 of 22 and understates every coverage number
— it is how S9b was briefly and wrongly written off at "2 of 22" when the answer is 6. Use
`Playcode.Import.Filemaker.load_versions/1`, which handles the fallback, rather than re-deriving the
code in a throwaway script.
