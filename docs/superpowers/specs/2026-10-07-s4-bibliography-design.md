# S4 — Bibliography

**Status:** implemented, 2026-10-07 (`e82c968..369a077`). Slice S4 of `../plans/2026-08-01-filemaker-import-slices.md`.
Research, field by field: `2026-09-25-s4-bibliography-research.md`. The project's answers to that
document's open questions arrived on 2026-10-07 through `docs/stakeholder/bibliografia-selecta.html`,
and they reverse one of its proposals: entries are now shared between plays, not copied per play.

Each play gets a bibliography in four kinds: modern editions, criticism, translations and
adaptations. It is imported once from the FileMaker dump, edited in Playcode from then on, shown
on `/plays/:code` and on the static site's title page, and written into the play's TEI file.

## Decisions from the project

| Question | Answer | What it means here |
|---|---|---|
| The 86 records with no category | Criticism that was never categorised; include them | Imported as `criticism` |
| The 118 records newer than the web export | Ready, publish them | Imported and shown like the rest. There is no publish flag |
| Broken links and unlinked records | Drop all of them | Skipped by the import, counted in its report |
| A translation showing its original's bibliography | No, each version shows only its own list | No inheritance through `parent_play_id` |
| The `Nota` field | Keep it for researchers only, "may be subject to change" | An admin-only column. Never on the public pages or in the TEI file |
| Order | Alphabetical by default; perhaps hand order or other criteria later | Computed on read. No `position` column until hand order is asked for |
| One correction to a shared edition | Should reach every play | One corpus-wide entry table, linked to plays |

And from this design's own discussion: **the import is a one-time move** (2026-10-07). The project
will not keep entering bibliography in FileMaker, so there is no repeated sync, no conflict
reporting, and no upload in `/admin/filemaker`.

## Done when

- A play's bibliography shows on `/plays/:code` and on the static site's title page, grouped by
  kind.
- Researchers can add, edit, link and remove entries on `/admin/plays/:id/bibliography` without
  an import, and an edit to a shared entry reaches every play that has it.
- `mix playcode.import.bibliography` brings the FileMaker bibliography into the plays we hold.
- The TEI export carries the bibliography in `<back>`.

## The model

Entries are corpus-wide, the way places are: one row per work cited, linked to each play that cites
it. A modern edition of the Wells and Taylor *Complete Works* is one entry linked to every play it
contains, so correcting it once corrects it everywhere.

```
bibliography_entries
  kind                  criticism | translation | adaptation | modern_edition   (required)
  pub_type              article | book_section | scholarly_edition | book | proceedings
                        | prologue | festschrift | electronic | thesis | collection   (nullable)
  language              es | fr | en | it | pt | de, nil when unknown
  analytic_author       the article, chapter or section
  analytic_title
  analytic_editors
  analytic_translators
  monogr_author         the book or journal
  monogr_title
  monogr_editors
  monogr_translators
  original_title
  edition
  volume
  volumes_total
  issue
  pages
  pub_place             plain text, copied from T13.1 at import
  publisher             plain text, copied from T13.2 at import
  year_text             verbatim: "2005", "1957-75", "[s.a.]"
  url
  url_accessed_on       text, as FileMaker holds it
  series                modern editions
  siglum                modern editions: ARD3Q2, RSC
  public_note           printed at the end of the citation (EdiMod_Nota)
  note                  internal (BibSel_Nota)
  filemaker_id          "T12:2544" or "T04:576"; unique where not null
  timestamps

play_bibliography
  play_id               references plays, on delete cascade
  entry_id              references bibliography_entries, on delete cascade
  volume                where this play sits in a modern edition
  pages
  note                  internal (ObrBibSel_Nota)
  origin                manual | filemaker
  timestamps
  unique (play_id, entry_id)
```

Every text column is `text`. The author, editor and translator columns hold names as FileMaker
does, `Surname, Name; Surname, Name`: nothing in S4 needs individual people.

**Rules:**

- **An entry needs a kind and at least one author, editor or title at either level.** Two real
  modern editions (273 and 420, Herford and Simpson's Jonson among them) have editors and no title,
  and FileMaker prints them, so a title alone is too strict.
- **`pub_type` may be blank.** Seven FileMaker records have none, and the renderer has a generic
  template for them.
- **Removing an entry from its last play deletes the entry**, in the same transaction. There are no
  orphan entries, which is why S4 needs no corpus-wide page.
- **Change tracking.**
  - `play_bibliography` gets the `play_row_changed()` trigger, like every table with a `play_id`.
  - `bibliography_entries` gets an `AFTER UPDATE` trigger that flags every linked play, on the
    model of `places_touch_plays` (migration `20261005120000`).
  - Deleting an entry cascades to its links, and the cascade fires the link trigger.
- **`origin` lives on the link**, because the link is what the import creates per play.
  `"filemaker"` is also how a re-run of the import recognises a play it has already done.

**Two notes, because FileMaker had two kinds.** `BibSel_Nota` was printed on 3 of 178 records,
and the project chose to keep it internal (answer 5). `EdiMod_Nota` is different: FileMaker
prints it at the end of every modern-edition citation that has one, 108 of 108 linked ("Doct.
dissertation", "First edition in 1964", "Printed by H. Baldwin for J. Rivington and Sons"). Hiding
it would remove published text, so it goes to `public_note`. Found while writing the plan,
2026-10-07.

### Rejected

- **Two entry tables mirroring FileMaker**, records and modern editions. They share about 80% of
  their fields, and two tables would double the form, the renderer, the link table and the TEI
  writer.
- **A JSONB column for the rarer fields.** It gives up changeset validation for no gain at this
  size.
- **An integer `year`.** Sorting is alphabetical now, and TEI's `@when` is derived from
  `year_text` at export time.
- **City and publisher tables.** No feature needs a shared place or publisher, so the names are
  copied into text.
- **`doi`.** FileMaker has no DOI field. The three DOIs it holds sit in link notes, which are
  internal.
- **`EdiMod_Referencia`.** Edition 44 holds only a `Referencia` (`Wells, Stanley, and Gary Taylor,
  gen. eds. <<William Shakespeare: The Complete Works>>…`) and the siglum `OXF2`. It is linked to 9
  versions, and FileMaker prints nothing for it in the modern-editions list. The field names the
  edition a digital text was based on, which is a source (`play_sources`, slice S3), not
  bibliography. S3 reads it from `T04.1` when it is built.

## Import

### Entry points

- `mix playcode.import.bibliography [--dry-run] [--path doc/ctce_dades]`, for dev.
- `Playcode.Release.import_bibliography(dir)`, for Fly. Copy the six files onto the machine with
  `fly ssh sftp`, then run `bin/playcode rpc 'Playcode.Release.import_bibliography("/tmp/ctce")'`.
  A release has no mix tasks, and a one-time move does not justify an upload page.

Both call the same functions:

- **`Playcode.Import.FilemakerXml.read(path)`** reads one FMPXMLRESULT file into a list of maps,
  field name to value, with Saxy. `METADATA/FIELD` gives the names, then each `ROW/COL/DATA` a
  value in that order. An empty `COL` is `""`.
- **`Playcode.Import.Bibliography`**:
  - `load(dir)` reads `T12_ObraBibliografiaSelecta`, `T12.1_BibliografiaSelecta`,
    `T04_ObraModernaRecomendada`, `T04.1_EdModerna`, `T13.1_Ciudad` and `T13.2_Editorial`.
  - `plan(data, plays)` is pure.
  - `apply_plan(plan, user_id)` writes in one transaction and logs one activity entry per play.

The small code tables are module attributes, not files:

| FileMaker | id → value |
|---|---|
| `T12.12` category | 1 `criticism`, 2 `translation`, 3 `adaptation`, blank `criticism` |
| `T12.13` and `T04.12` language (same ids) | 1 `es`, 2 `fr`, 3 `en`, 4 `it`, 5 `pt`, 6 `de` |
| `T12.11` type | 1 `article`, 2 `book_section`, 3 `scholarly_edition`, 4 `book`, 5 `proceedings`, 6 `prologue`, 7 `festschrift`, 8 `electronic`, 9 `thesis`, 10 `collection` |
| `T04.11` type | 1 `book`, 2 `book_section`, blank `book` |

### Matching

- A FileMaker version is a play when `"EMOTHE" <> zero-padded _k_IdObraTitulo` equals
  `FilemakerSync.base_code(play.code)`.
- Only plays from `FilemakerSync.all_plays/0` count, so archived plays are excluded, as in S1 and
  S2.
- **A base code held by two plays links both**, as S1 and S2 treat each play on its own. Dev had
  two such pairs when this was designed: `EMOTHE0435_ElBastardoMudarra` and
  `…_ElBastardoMudarraTragicomedia` (1 modern edition), and `EMOTHE0671_NoPuedeSerGuardarUnaMujer`
  and `…_NoPuedeSer` (9 records, 7 modern editions). The same version imported twice; by the
  time the import ran, the first play of each pair had been removed from dev.
- Versions we do not hold are counted, not listed.

### Field mapping

**`T12.1` records** map level for level:

| FileMaker | Column |
|---|---|
| `BibSel_Autor`, `BibSel_Titulo`, `BibSel_Editor`, `BibSel_Traductor` | `analytic_*` |
| `BibSel_Autor2`, `BibSel_Titulo2`, `BibSel_Editor2`, `BibSel_Traductor2` | `monogr_*` |
| `BibSel_Titulo` on a book (type 4) | `series`: FileMaker prints it after the year as a series on 49 of 51 (`… 1967. Das Bühnenspiel.`) |
| `BibSel_TituloOriginal` | `original_title` |
| `BibSel_Edicion` | `edition` |
| `BibSel_NumVolTomo` | `volume` |
| `BibSel_VolTomoTotal` | `volumes_total` |
| `BibSel_Ejemplar` | `issue` |
| `BibSel_Pag` | `pages` |
| `BibSel_Ano` | `year_text` |
| `BibSel_URL` | `url` |
| `BibSel_URL_FechaAcceso` | `url_accessed_on` |
| `BibSel_Nota` | `note` |
| `_k_IdCiudad` | `pub_place`, through `T13.1` |
| `_k_IdEditorial` | `publisher`, through `T13.2`. A key that is not a number (`B.R. Grüner Publishing Company`, on 2 records) is itself the name |
| `_kp_IdBiblioSelecta` | `filemaker_id` `"T12:<id>"` |

**`T04.1` editions** depend on their type, because that is what FileMaker's own rendering does:
every *Libro* prints as a book and never says "In:", even with a `Titulo2` (251 editions); every
*Capítulo de libro* prints "In:" (176).

- **Libro, or no type:**
  - `EdiMod_Autor`, `Titulo`, `Editor`, `Traductor` go to `monogr_*`.
  - `EdiMod_Titulo2` goes to `series`, which is where FileMaker prints it (`… 2006. The Arden
    Shakespeare.`).
  - The level-two people on a book (`Autor2` once, `Editor2` five times) are dropped. FileMaker
    never prints them, and the one inspected repeats the level-one editor.
- **Capítulo de libro:**
  - Level one goes to `analytic_*`, level two (`Autor2`, `Titulo2`, `Editor2`, `Traductor2`) to
    `monogr_*`.
  - `EdiMod_Titulo3` goes to `series`.
- **Both:**
  - `EdiMod_Edicion` goes to `edition`, `Pag` to `pages`, `Ano` to `year_text`, `URL` and
    `URL_FechaAcceso` to `url` and `url_accessed_on`, `Siglas` to `siglum` and `Nota` to
    `public_note`.
  - `EdiMod_VolTomo` goes to `volumes_total`. It is the edition's number of volumes, which
    FileMaker prints as `6 vols.`. The play's own volume is on the link.
  - City and publisher are looked up as for `T12.1`.
  - The id goes to `filemaker_id` as `"T04:<id>"`.
  - `EdiMod_Referencia` is not imported (see "Rejected").

**Links:**

- `ObrBibSel_Nota` goes to `play_bibliography.note`.
- `ObraEdMod_Volumen` and `ObraEdMod_Paginas` go to `play_bibliography.volume` and `pages`.

**Cleaning:**

- Values are trimmed and otherwise kept verbatim.
- `<<…>>` stays as stored, since it is already the app's italics marker (`InlineMarkup.parts/1`).
- Years like `121-123`, the title typed into `TituloOriginal` (records 2227, 2236, 2267, 2270,
  2274) and similar entry errors are left for curators to fix in admin. Guessing would hide them.

### What a re-run does

The import is re-runnable so that plays imported into Playcode later can pick up their
bibliography. It never changes or deletes anything it wrote before:

- **A play that already has a `filemaker` link is skipped whole** and reported as "already
  imported", so a curator's edits and removals are never undone.
- **An entry whose `filemaker_id` already exists is reused.** That is how a modern edition shared
  with a play imported later stays one entry.
- **Known edge:** a shared entry a curator deleted comes back if a play imported later links to it.
  This is rare and accepted.

### Skipped, and counted by reason

`--dry-run` lists the FileMaker ids for each reason:

- links with no record id, links to a record that no longer exists, and records linked to nothing
  (answer 3)
- records and editions with no author, editor or title at either level
- `T04` test records 9 (`esto es una prueba…`) and 147 (title and translator `w`). The research
  counted three test records; only these two can be identified
- a duplicate link, the same record on the same version twice. It collapses into one link
- `T04.1` id 576 appears twice, one copy blank: the non-blank copy is used

### Expected result

On the dev database's 390 plays (371 EMOTHE base codes, 19 Artelope), as imported on 2026-10-07:

- **Bibliography:** 2,043 entries and 2,051 links on 101 plays. That is 1,807 criticism (74 of them
  uncategorised), 184 translations and 52 adaptations. 17 entries are shared, by two plays at most.
  The 4 duplicate links collapse. 508 links point at versions dev does not hold.
- **Modern editions:** 680 entries and 744 links on 100 plays. 24 entries are shared, by up to 9
  plays. The 4 duplicate links collapse. 199 links point at versions dev does not hold.

The design counted 392 plays, with 2,060 and 752 links on 102 plays each. The difference is
exactly the two duplicate plays removed from dev in between (see "Matching"): 9 records and 8
modern editions. The entry counts did not change. A re-run reports all 114 plays as already
imported and writes nothing.

**The report:**

1. Per play: new entries, reused entries and links.
2. Skips by reason.
3. Plays already imported.
4. The number of FileMaker versions not held.

## Display

### The renderer

`Playcode.Bibliography.Citation`:

- `parts(entry, link \\ nil)` returns segments in the shape `InlineMarkup.parts/1` uses, text plus
  an italic flag, plus the URL as a link segment.
- `plain(entry, link \\ nil)` returns the text alone.
- For a modern edition, the link's `volume` and `pages` win over the entry's when present: they
  say where this play sits in the edition.

The admin page, `/plays/:code` and the static site all render these segments, so the three cannot
drift apart.

**Style: FileMaker's printed form**, which curators know. FileMaker's formula varies by category
and type and has its own slips (an issue printed as `vol. 2`, an editor printed twice), so the
renderer keeps FileMaker's elements and labels in one consistent order per kind:

- **Criticism, translations and adaptations print author first:**
  `Barnett, Timothy Brian. "Lope and Tasso: …". Bulletin of the Comediantes. 2005, 57, 2, p. 238-294.`
- **Modern editions print the editor first:**
  `Thompson, Ann; Taylor, Neil, ed. <i>Hamlet</i>. Shakespeare, William. In: <i>Hamlet: The Texts of 1603 and 1623</i>. London: Thomson Learning, 2006, The Arden Shakespeare.`

In full, the bibliography order is:

1. **Lead.** With an analytic level: author (`, ed.` for a *edición estudioso*), `"title"`,
   `Ed.` and `Tra.` of that level, then the container: its author (not for an article),
   `Ed.`, title, `Tra.`. Without one: author, title, `Ed.`, `Tra.`.
2. **Edition.** `2nd ed.`
3. **Imprint.**
   - Article: `Year, volume, issue, p. pages.`
   - Anything else: `Vol. N.` then `Place: Publisher, Year, p. pages, N vols.`
4. **The rest.** Series, `(Orig: …)`, the public note, then `URL: …` with `(acc. …)`.

Modern editions are the same, with three differences:
- each level prints editors first as `Editors, ed. <i>Title</i>. Author.`
- `In:` sits between the two levels
- pages are `pp.`

The labels (`Ed.`, `Tra.`, `In:`, `Vol.`, `vols.`, `p.`, `pp.`, `Orig:`, `URL:`, `acc.`) are
FileMaker's and are not translated.

Deliberate differences from FileMaker:

- **An empty field drops out with its punctuation.** That means no `{Falta …}`, no `". ."` (a
  *edición estudioso* prints `". . Hispanic Studies…"` today) and no `In: <i></i>`.
- **A URL is a link.**
- **A value that already ends in `.`, `?` or `!` gets no second full stop** (FileMaker printed
  `Armistead, J M..`).

### Order and grouping

- **Kinds, in this order:**
  1. Modern editions
  2. Criticism
  3. Translations, subgrouped by language as the current website does, in the order
     `es en fr it pt de`, with unknown language last
  4. Adaptations

  A kind with no entries is not shown.
- **Within a group, entries are sorted by `plain/2`**, case- and accent-folded (NFD, combining
  marks removed), ignoring leading quotes and punctuation, then by id. A citation starts with the
  first printed name and then the title, so this is "alphabetical by first name printed". It is
  computed on read; the longest list, EMOTHE0176's criticism, has 77 entries.

### Where it shows

- **The static site's title page:** a "Bibliography" section after "Sources", with an `h3` per kind
  and English labels.
- **`/plays/:code`:** a `#meta-bibliography` section with its sidebar entry, in the page's
  language through gettext.
- **Never public:** `note` and the link note (answer 5). They are shown and edited in admin only,
  and the TEI export leaves them out too.
- **Not printed:** `siglum`. FileMaker did not print it either. It is not private, so the TEI
  export carries it as data, `<idno type="siglum">`.

## Its own menu, everywhere

The bibliography is a section of the play's metadata like places and sources, and each surface
gives it its own entry (the project's request, 2026-10-07):

- **Admin:** a "Bibliography" tab in the play context bar, after Sources.
- **`/plays/:code`:** a "Bibliography" entry in the metadata sidebar, after Editors and before the
  editorial notes. That is where its section sits on the page: after Places.
- **Static site:** a "Bibliography" entry in the play's contents rail, after Statistics, linking to
  the title page's `#bibliography`.

## Admin

`/admin/plays/:id/bibliography`, `PlaycodeWeb.Admin.PlayBibliographyLive`:

- **The tab** is "Bibliography", in the play context bar after Sources, with `active_tab:
  :bibliography`.
- **The gate:**
  - `on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :manage_bibliography}}`.
  - `:manage_bibliography` joins `@researcher_actions` in `Playcode.Authz`.
  - The route gets a row in `authorization_test.exs`.

### What the page does

- **The list** is the public grouping and order, through `Citation.parts`. Each row adds:
  - a "shared with N plays" badge when N > 1
  - the entry note and the link note, muted
  - Edit and Remove, icon-only buttons with an `aria-label`

  A filter box matches the plain citation on the server.
- **New entry** opens a modal:
  - `kind` and `pub_type` come first.
  - Then fieldsets: *Article or chapter* (the four `analytic_*`), *Book or journal* (the four
    `monogr_*`), *Publication* (place, publisher, year, edition, volume, number of volumes, issue,
    pages, URL, accessed on) and *Notes* (the printed note, and the internal one).
  - *Modern edition* (series, siglum) shows only for that kind.
  - *In this play* holds the link's volume, pages and note.
  - Under the form, a live preview of the printed citation: `apply_changes/1`, then
    `Citation.parts`. With two levels of author and title, the preview is how a curator sees which
    field goes where.
- **Add existing entry:**
  - Search every entry by author and title (`ILIKE`, entries already on the play excluded), pick
    one, and it is linked.
  - Without this, sharing would end with the import: a play added later could not join the Wells
    and Taylor *Complete Works*.
  - Same interaction as the places page (`term`, `suggestions`, `picked`).
- **Edit** uses the same modal.
  - On a shared entry it opens with a warning: "Shared with N plays (EMOTHE0010, …): changes
    appear on all of them."
  - The *In this play* fields change only this play's link.
- **Remove** deletes this play's link. When it was the last one, the entry goes too, and the
  confirmation says so: "Remove from this play" or "Delete this entry (no other play uses it)".

**The context**, `Playcode.Bibliography`:

- `list_for_play/1`, grouped and sorted
- `get_entry!/1`, `get_link!/1`
- `create_entry_for_play/3`, entry and link in one transaction
- `update_entry/2`, `update_link/2`
- `link_entry/3`
- `unlink/1`, which deletes the entry when it was the last link
- `search_entries/2`
- `plays_for_entry/1`, for the shared warning

**The activity log:** `create`, `update` and `delete` on `bibliography_entry` and
`play_bibliography`, as the places page does.

**Labels:**

- `PlaycodeWeb.PlayLabels` gains `bibliography_kind_label/1` and `pub_type_label/1`, plus a label
  for `de`, which no play language has used so far.
- The changeset's custom message ("needs an author, an editor or a title") is hand-added to
  `errors.pot` and the Spanish PO file. `error_translations_test.exs` fails until it is there.

## TEI export

The bibliography goes in `<back>`, which the exporter writes empty today:

```xml
<back>
  <div type="bibliografia">
    <listBibl type="critica">
      <biblStruct type="articulo_revista" xml:lang="en">
        <analytic>
          <author>Barnett, Timothy Brian</author>
          <title level="a">Lope and Tasso: …</title>
        </analytic>
        <monogr>
          <title level="j">Bulletin of the Comediantes</title>
          <imprint><date when="2005">2005</date></imprint>
          <biblScope unit="volume">57</biblScope>
          <biblScope unit="issue">2</biblScope>
          <biblScope unit="page">238-294</biblScope>
        </monogr>
      </biblStruct>
    </listBibl>
  </div>
</back>
```

**Structure:**

- **`listBibl/@type`** is `ediciones_modernas`, `critica`, `traducciones` or `adaptaciones`, in the
  page's order.
- **`biblStruct/@type`** is FileMaker's type name: `articulo_revista`, `seccion_libro`,
  `edicion_estudioso`, `libro`, `acta`, `prologo`, `homenaje`, `publicacion_electronica`,
  `tesis_doctorado`, `coleccion`. It is omitted when `pub_type` is blank.
- **`@xml:lang`** carries the language.

**Inside `biblStruct`:**

- `<analytic>` is written when any `analytic_*` column is filled.
- **`<monogr>` is always written**, because the schema requires it, in schema order:
  1. `<author>`
  2. `<editor>`, and `<editor role="translator">` for translators
  3. `<title level="j">` for an article, otherwise `level="m"`; plus `<title type="original">`
  4. `<idno type="siglum">`
  5. `<edition>`
  6. `<imprint>` with `<pubPlace>`, `<publisher>`, `<date when="…">year_text</date>` and
     `<date type="access">`. `@when` is written only when `year_text` is a plain four-digit year.
     The schema requires an `<imprint>`, so it is written with an empty `<date/>` when nothing is
     known.
  7. `<extent>N vols.</extent>`
  8. `<biblScope>`: `volume`, `issue` and `page`. The link's volume and pages win, as in the
     renderer.
- **`<series><title level="s">`** comes after `<monogr>`, and `<ptr target>` for the URL comes
  last.

- **`public_note`** is written as `<note>`, last in `biblStruct`.

**Never written:** `note`, the link note. The `.xml` file is published with the static site.

**Import of `<back>` is deferred:**

- The bibliography's home is the database, not the file.
- A re-import of an exported file updates the play in place and touches only `tei` rows, so the
  `manual` and `filemaker` links survive and export → re-import → export still changes nothing.
- What is lost is a TEI file imported into a fresh database.
- The parser's other `<back>` gap, the two fixtures' `epilogo` divisions, stays on the roadmap for
  the slice that teaches the parser `<back>`.

## Testing

Through the outermost API, as CLAUDE.md asks:

| What | Where | Through |
|---|---|---|
| A shared edit shows on both plays; removing the last link deletes the entry; grouping, translation subgroups and order; validation | `test/playcode/bibliography_test.exs` | `Playcode.Bibliography`'s public functions |
| Citations match FileMaker's | `test/playcode/bibliography/citation_test.exs` | A committed oracle, `test/fixtures/filemaker/bibliography_sample.json`, described below |
| The import end to end | `test/mix/tasks_test.exs` | `Mix.Task.rerun/2` on a trimmed dump, described below |
| The admin page: new entry and preview, the shared warning and the edit reaching the other play, add existing, remove (both confirmations), the filter | `test/playcode_web/live/admin/play_bibliography_live_test.exs` | `live/2`, `form/3`, `render_submit/1`; selectors by visible text and `aria-label` |
| Who may open the page | `test/playcode_web/authorization_test.exs` | one new row |
| Public rendering, and that `note` and the link note never appear | `play_show_live_test.exs`, `static_site_play_test.exs` | rendered HTML |
| The `<back>` shape, link volume and pages, no notes, `@when` only for plain years | `test/playcode/export/tei_xml_test.exs`, where export-only data is tested | XPath helpers from `import_helpers.ex` |
| Re-importing a play's own export keeps its bibliography and exports the same file | `tei_xml_test.exs` | the fixpoint test (`tei_roundtrip_test.exs:598`) re-imports under a new code, so a new play; this one re-imports in place |
| An export with every `pub_type` validates | `tei_validator_test.exs`, `:slow` | the schema |
| A link change flags its play; an entry edit flags every linked play | `test/playcode/content_version_test.exs` | as for places |

**The oracle** asks one question of every record: does every word FileMaker printed appear in
our citation? Labels and `{Falta …}` placeholders aside, compared as sets of lower-case words,
with letters split from digits (FileMaker glues `London2010`). It does not compare order or
punctuation; the hand-written examples in `citation_test.exs` pin those.

- **The sample**, `test/fixtures/filemaker/oracle/`, is the six tables cut down to 30 bibliography
  records and 16 modern-edition links. Together they cover every type and every optional field.
  `regenerate.exs` beside them rebuilds it from the dump.
- **A `:slow` sweep** runs the same check over the whole `doc/ctce_dades/` when it is present (it
  is git-ignored).
- **Measured on a prototype, 2026-10-07:** 2,624 of 2,625 bibliography records and 938 of 938
  modern-edition links. The exception is record 2095, a page range typed into the URL access
  date with no URL.

**The trimmed dump** for the import test is six FMPXMLRESULT files in
`test/fixtures/filemaker/ctce_dades/`. Its tests:

- a dry run writes nothing
- an uncategorised record becomes criticism
- a record on two versions becomes one entry with two links
- each skip reason is counted
- a duplicate link collapses
- a Libro's `Titulo2` lands in `series`
- a re-run skips an imported play and does not bring back a link a curator removed
- a play imported later reuses an existing entry

**Existing guards this slice must satisfy:**

- `fingerprint_test.exs` fails until the static site's fingerprint covers `Citation` and
  `Playcode.Bibliography`. The context decides the grouping and order a page shows, so it is
  fingerprinted like `Playcode.Places`, not counted as data access.
- `content_version_test.exs` fails until `play_bibliography` has its trigger.

## Implementation order

1. **Model:** migrations with both triggers, the schemas, `Playcode.Bibliography`.
2. **Renderer:** `Citation` and the oracle fixture.
3. **Import:** `FilemakerXml`, `Import.Bibliography`, the mix task and the `Release` function. Run
   it on dev, so every later step works on real data.
4. **Admin page.**
5. **Public pages:** `/plays/:code` and the static site.
6. **TEI export.**

Then update CLAUDE.md (schema, routes, implemented list) and mark S4 done in the roadmap.

## Out of scope

- **Import of `<back>` from TEI**, and the `epilogo` divisions. See "TEI export".
- **A corpus-wide `/admin/bibliography` page.** Add it when curators ask for cross-play search or for
  merging duplicate entries.
- **Hand order and other sort criteria.** These need a `position` on the link and a reorder UI, and
  the project marked them "maybe, in the future".
- **Showing notes publicly.** Answer 5 may change. If it does, the renderer gains one segment.
- **`EdiMod_Referencia`.** It goes to S3.
- **People as records.** Editors and translators of cited works stay text. S7's credits are a
  different set of people (2 of 194 cited translators appear there).

## Known data issues, for curators after the import

- Records 2227, 2236, 2267, 2270 and 2274 have the book's title in `TituloOriginal` and none in the
  title fields.
- Editions 273 and 420 have editors but no title.
- 40 `BibSel_Ano` values are not a plain year, some of them page ranges (`121-123`, `308-322`).
- Thesis records without a university: FileMaker printed `{Falta nombre Universidad}`; the name is
  sometimes in the note.
- Record 2095 has a page range (`853-960`) as its URL access date, and no URL.
