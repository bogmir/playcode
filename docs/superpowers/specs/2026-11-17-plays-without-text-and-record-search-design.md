# Plays without a text, and a record search for the catalogue

Design, 2026-11-17. Four linked features:

1. **Plays without a text**: Playcode holds a play's record with no text, and every output knows what to do with it.
2. **The record search**: the published site's catalogue becomes its one search, with the old database form's filters over a new record index, full text included.
3. **FileMaker's plays without a text**: the 121 works FileMaker holds with no web edition become plays.
4. **Downloads on the published site**: each play with a text offers its TEI file, an EPUB, and a print button for a PDF.

Plans, numbered 1 to 5 in the order they are built (plan 5 may run any time after plan 1):

| Plan | Needs |
|---|---|
| `docs/superpowers/plans/2026-11-17-plays-without-text.md` | nothing |
| `docs/superpowers/plans/2026-11-17-search-record-index.md` | plan 1 (the `text` field) |
| `docs/superpowers/plans/2026-11-17-catalogue-search-filters.md` | plans 1 and 2 |
| `docs/superpowers/plans/2026-11-17-filemaker-plays-without-text.md` | plan 1 only |
| `docs/superpowers/plans/2026-11-17-static-site-downloads.md` | plan 1 only |

The search form as the researcher will see it: `2026-11-17-buscador-del-catalogo-maqueta.html`, beside this file.

## 1. Why

The project's emails say Playcode holds source plays, and their translations and adaptations, even when nobody has edited their text (question 57). The old FileMaker database held such works and let a reader search every field of a record: witnesses, performances, places, characters. Playcode today holds only plays that came from a TEI or Word file, and the published site searches the text and four facets. The researcher answered question 57 on 2026-11-17; this design builds the answer.

## 2. Decided by the researcher on 2026-11-17 (not reopened)

- A work with no text joins the catalogue like any other play. It is marked as having no text, has no HTML, PDF or parallel formats, and its record page has an empty text section. Search finds it through its record fields only.
- Its code is `EMOTHE` plus FileMaker's number (`FilemakerXml.version_code/1`). There are 121 such works, EMOTHE0034 to EMOTHE0632, none clashing with a code that has a text. Some records FileMaker marks "no web edition" do have a TEI file here, so an import skips codes Playcode already holds.
- The static site gets one search: the catalogue, extended with the old database form's filters. The result is a list of plays.
- Every field of the list in section 7.5 is wanted.
- One state, not two: `is_complete` means the record is complete and the work is published. No new switch.

## 3. Goals, non-goals, anti-goals

**Goals**

- A play with no text is an ordinary play everywhere: created in the play form or by an import, exported to a valid TEI file that imports back to the same rows, published by Generate when complete.
- A reader of the published site finds plays by any of 23 fields, from one form, on the catalogue page, with the site still working from `file://` and without JavaScript (as a plain list).
- The 121 FileMaker works arrive as drafts with everything today's export says about them.
- A reader of the published site takes a play away as TEI, as EPUB, or on paper or as a PDF through the browser's print.

**Non-goals**

- No new column or switch saying "no text". No bulk "mark complete".
- No pages per company, actor or venue (stays in `docs/backlog.md`, *Performances: search and pages for companies and actors*; the search half of that item is done by this design).
- The old form's fields the researcher did not list: genre (two columns; Playcode stores none), translator, translation year, criticism year, annotated, collated. Recorded in the backlog.
- Kind and original of the 121: today's export does not say (section 7.6).
- Multiple choice in a list, or counts that follow the other filters.
- PDF files on the published site (section 6, *PDF on the published site*).

**Anti-goals** (a failure even if it works)

- A play with text reported as having none, or the reverse.
- A TEI file of a play without a text that the schema refuses or the import reads back differently.
- A search that needs a server, a third-party request, or that leaves the catalogue blank without JavaScript.
- A record index that can be stale after Generate.

## 4. Constraints (from `CLAUDE.md`)

- **Complete copy**: export, import into an empty database, every row and column back. `test/playcode/complete_copy_test.exs` holds it.
- **TEI validity**: `priv/schemas/tei_all.rng`.
- **Static site**: Endings; pure HTML, CSS and JS; data files are scripts calling `EMOTHE.search.load/3`, because `fetch` fails on `file://`. Every build goes through `SiteBuilder`. Generate rebuilds only what changed. Assets are linked as `assets/…?v=` with `@site.assets`. Size budgets are asserted in `test/playcode/export/static_site_test.exs`.
- **The two search normalisers agree**: `StaticSite.Search.normalise/1` and `EMOTHE.normalise` in `site.js`, both against `test/fixtures/search_normalisation.json`.
- **Access**: every decision through `Authz.can?/3`; ids from the browser resolved with scoped getters.
- **Text from a TEI file holds `<<…>>`**: print through the renderers, `InlineMarkup.plain/1` where markup cannot go. The record index is such a place.
- **Accessibility** of admin pages: `test/playcode_web/accessibility_test.exs`.
- **Tests** go through the outermost API and are proved to bite (`bin/bites`).

## 5. What the code does today (checked 2026-11-17)

A play made with no text and marked complete (the check was a throwaway test, since deleted):

- `/plays/CODE`, its compare page, the admin statistics page, `/export/:id/html` and `/epub`, and Generate all render without an error.
- **The TEI export is invalid**: `<body/>` fails `tei_all.rng` ("Expecting an element, got nothing"). `<body><p/></body>` and `<body><div/></body>` validate.
- **The file does not import back to the same play**: `Catalogue.update_form_and_verse_count/1` gives a play with no elements `auto_form: "prose"` and `verse_count: 0`, where the play form leaves the column default and nil. The catalogue then says "Prosa".
- **The static site** writes an empty `text.html` and `statistics.html`, and the title page links "Full text".
- The importer reads only `div1` and `div` children of `<body>` (`slot?/2`, `lib/playcode/import/tei_parser.ex`), so a `<p/>` there is already read as nothing.
- `auto_form` and `verse_count` are recomputed on every TEI import and every content edit (`lib/playcode/import/tei_import.ex`, `lib/playcode/play_content.ex`, `lib/playcode/release.ex`).
- **Playcode already has a rule for "no text"**: `Catalogue.without_text/1` and the play list's `:no_text` status (`lib/playcode/catalogue.ex`) call a play without a text when it has no verse line and no line of prose, and `/admin/plays` shows a "No text" badge and filter by it. Nothing else uses the rule.

The search today:

- `search/plays.js` holds code, title, author, language, language name and kind per play (`Search.play_entry/1`).
- `index.html` (`pages/catalogue.html.heex`) filters its rows on `data-lang`, `data-form`, `data-kind`, `data-coll` and `data-text`, with code in `site.js` (`initCatalogue`), and four radio facets with server-rendered counts.
- `search.html` is the full-text page; `search.js` holds both the engine and the page (facets built from the hits).
- `priv/static_site/search.js` is 13,854 bytes and `site.js` 13,669, each under a 15,000 byte budget.
- `StaticSite.write_catalogue/3` runs on every Generate (`generate/1` and `apply_changes/2`) and rewrites `index.html` from all published plays.
- Every table the record fields come from already moves `plays.content_version` (`test/playcode/content_version_test.exs`: characters, witnesses, performances, cast rows, company and actor renames, places and the places containing them).

The preview is about to change. The unmerged branch `feature/preview-real-site-pages` (design `docs/superpowers/specs/2026-11-15-preview-real-site-pages-design.md` on that branch) deletes `PlayShowLive` and the preview's `PlayCompareLive`: `/plays/:code` becomes the play's static pages, built on demand by `Playcode.Export.PlayPreview`. The `/export/:id/*` routes stay. Each plan task that touches the old preview says to skip it when `lib/playcode_web/live/play_show_live.ex` is gone, since the static page then covers it.

Downloads and their cost (dev, 407 plays, one run on a laptop, 2026-11-17):

| | Time | Size |
|---|---|---|
| EPUB, every play, one at a time (`Export.Epub.generate/1`) | 65 s in all; median 0.15 s, 90th percentile 0.26 s, longest 0.5 s | 33 MB in all; median 82 KB, largest 205 KB |
| PDF, seven plays across the lengths (`Export.Pdf.generate/1`) | 1.7 s (1,581 elements), 3.1, 3.9, 5.3, 11.0, 7.0, and 33.8 s for the longest (9,524 elements) | 0.7 to 2.7 MB each; about 600 MB for every play |

- The site is 465 MB (371 plays, 2026-10-07) and Deploy pushes it to `bogmir/emothe-static`.
- The Fly machine stops when it sees no web traffic, and an SSH session is not traffic (`docs/production-reimport.md`), so a timer inside the app cannot run a nightly job.
- The site has print styles (`@media print` in `priv/static_site/style.css`); a browser's print does not re-measure the shared lines (`docs/backlog.md`, *A shared line's lead carries no note numbers*).
- `priv/static_site/style.css` is 24,842 of its 25,000 bytes.

FileMaker:

- `FilemakerSync` never creates a play. `Filemaker.load_versions/1` reads T01 (`doc/w3emothe_T01_tituloEM.ndjson`, layout `T01_tituloEM`, 439 records) for historical time and dating only.
- T01 records with `bus_edicionWeb == "0"` whose code no TEI file here holds: **121, EMOTHE0034 to EMOTHE0632**. 58 more with that flag are held.
- `bus_idioma` against the language of 283 held plays: `1` es, `2` fr, `3` en, `4` it, `5` pt, with no disagreement.
- Play codes in a database loaded from the corpus carry a tail (`EMOTHE0195_Macbeth`); `Play.short_code/1` gives the part FileMaker knows.
- Held plays store `author_name` as "William Shakespeare" and `author_sort` as "Shakespeare, William"; T01's `pub_Autor` is the second form.

## 6. Approaches considered

Each was put to the owner on 2026-11-17; the pick is marked.

**How "no text" is known**

- **Picked: a play has a text when it has at least one verse line or line of prose**, the rule the admin's play list already applies. Cast lists (divisions), characters, paratexts, and an act with a heading and nothing spoken do not make a text, so FileMaker's character lists can become real cast lists. (Put to the owner as "no elements"; narrowed to the existing rule when it was found, so Playcode has one.)
- No divisions and no elements: a researcher adding a cast list would silently turn the work into one "with text". Rejected.
- A stored switch: the researcher decided one state, not two. Rejected.

**The TEI file**

- **Picked: `<body><p/></body>`**, one empty paragraph when the body has no item. Valid, the usual TEI form of a header-only record, no new vocabulary, and the importer needs no change.
- An explicit marker (`<div type="sin-texto"/>`): an EMOTHE value to invent and an import rule to drop it. Rejected.
- No file for such a play: FileMaker's data would live only in the database, against the complete-copy rule. Rejected.

**Catalogue and search pages**

- **Picked: merged into `index.html`.** One form, one list. `search.html` stays as a redirect.
- Two pages sharing one form: two result renderers to keep alike, and "one search" becomes two. Rejected.

**The record index**

- **Picked: one file, `search/records.js`**, every published play, loaded on first use of the form, written whole on every Generate.
- Two files with the characters apart (they are over half the bytes): saves about 40 KB gzipped for a reader who never searches characters, at the cost of a second loader. Rejected.
- Everything in `data-` attributes: about 250 KB inside `index.html` for every reader. Rejected.
- Incremental writing with carry-over, as the full-text shards do: nothing to gain, since the catalogue page is rewritten from all plays anyway, and tracking is what goes stale. Rejected.

**Where the browser code lives**

- **Picked: a third script, `assets/catalogue.js`**, with its own 15,000 byte budget, linked by `index.html` only. The catalogue code leaves `site.js`; `search.js` keeps the full-text engine and loses its page.
- Raising the two existing budgets: every page of every play would carry the form's code. Rejected.

**PDF on the published site**

- **Picked: a print button.** "Imprimir o guardar como PDF" on the full-text page calls the browser's print over the site's print styles. No file, nothing nightly, nothing added to Deploy, and it works from `file://`.
- PDF files rendered once a night for the plays whose version changed: about 600 MB, which more than doubles the site and takes the repository Deploy pushes past GitHub's recommended 1 GB, each re-render adding about 1.5 MB to its history. The machine sleeps at night, so the run would need a GitHub Actions schedule calling a guarded endpoint and polling it to keep the machine awake, and the first fill a scaled-up machine as a re-import does. Rejected on those measurements.

**Where the catalogue's styles live**

- **Picked: a second stylesheet, `assets/catalogue.css`**, linked by `index.html` only, with its own budget; the catalogue's rules leave `style.css`, which has 158 bytes to spare.
- Raising `style.css`'s budget: every page of every play would carry the form's styles. Rejected.

## 7. Design

### 7.1 A play without a text

**Definition.** A play has a text when it has at least one element of type `verse_line` or `prose`: the rule `Catalogue.without_text/1` already applies. Nothing else counts: not a division, a cast list, a paratext, a speech with no line, or a stage direction alone.

**How it is read (builder's call, recorded here).** `plays.auto_form` already holds what Playcode works out from the elements, recomputed on every import and content edit. It becomes nullable, and **nil means the play has no verse line and no line of prose**. One function answers the question everywhere:

```elixir
# lib/playcode/catalogue/play.ex
@doc "Whether the play has a text: at least one element, as the last import or content edit found."
def has_text?(%Play{auto_form: auto_form}), do: not is_nil(auto_form)
```

Nothing else reads `auto_form` to decide this. If the cache ever proves unreliable, this one function becomes a query.

- `Catalogue.update_form_and_verse_count/1`: with no verse line and no line of prose, `auto_form: nil` and `verse_count: nil`; otherwise as today. It counts the rows, not their length, to decide: an empty line of prose is still a line.
- `Catalogue.without_text/1` goes, and the `:no_text` status reads `is_nil(p.auto_form)`: the play list asks `Play.has_text?/1` like everything else, so there is one rule and one place it is worked out.
- `Play` schema: `field :auto_form, :string` with no default. A play created in the form has no text until its first content edit.
- Migration: `auto_form` nullable with no default; plays with no verse line and no line of prose get `auto_form = NULL, verse_count = NULL`. Down: back to `'prose'` and `NOT NULL`.
- `Play.form/1` returns the curated `form`, else `auto_form`, so nil for a play without a text and no curated form. Every caller that prints a form must take nil and print nothing (`Components.form_summary/2`, `entry_meta/1`, `catalogue_entry/1`'s `data-form`, the admin's labels, `PlayLabels.form_label/1`).
- `test/support/fixtures.ex`: `play_fixture/1` keeps `"auto_form" => "verse"`, so the many tests that use it as "some play" are unchanged; a new `play_without_text_fixture/1` passes `"auto_form" => nil`. A test about the derivation itself imports a file or edits content, never sets the column.

**The word.** `CONTEXT.md` gains two entries:

- **Play without a text**: a play Playcode holds the record of and no text: no act, scene or line. It may have a cast list, paratexts, witnesses, performances. _Avoid_: textless play, empty play, stub, record-only play.
- **Record**: what Playcode holds about a play besides its text: title, author, language, dating, relations, witnesses, performances, places of action, historical time, characters, bibliography. _Avoid_: metadata, file (the TEI file).

Interface wording: "sin texto" / "no text"; the notice "EMOTHE no dispone del texto de esta obra." / "EMOTHE does not hold the text of this play."

### 7.2 The TEI file

**Export** (`lib/playcode/export/tei_xml.ex`):

- When the body section of the outline has no item, `<body>` holds one empty `<p/>`. A body with any item is written as today.
- `<extent>` is written only when `Play.form/1` is not nil. With a curated form and no text it carries the form and no count, as today's code already writes for a zero count.
- Everything else is written as for any play: header, cast lists and paratexts in `<front>` and `<back>`, witnesses, performances, bibliography, places.

**Import** (`lib/playcode/import/tei_parser.ex`, `tei_import.ex`):

- A `<p>` child of `<body>` is not a slot and is read as nothing: already so, now pinned by a test.
- The play arrives as a draft, with `auto_form` nil after the recompute.
- **Preview**: `TeiImport.preview_import/1` gains a key, `removes_text`, the number of elements the play holds when the file has none and the code exists (nil otherwise). The admin import page and `mix playcode.import.tei --dry-run` print it as a warning: "Este archivo no tiene texto: se eliminarán las N líneas de la obra." The import itself follows the existing re-import rule (the text is replaced).

**Complete copy**: `test/playcode/complete_copy_test.exs` gains a third play, without a text, with a cast list, a paratext, a witness, a performance, a place and a bibliography link, every curated column filled. Its export validates against the schema in the slow sweep (`test/playcode/roundtrip_test.exs`).

`docs/tei-mapping.md` gains the two lines (`body`, `extent`); `docs/stakeholder/ida-y-vuelta.html` gains a row "Una obra sin texto".

### 7.3 What each output does

| Output | A play without a text | Where |
|---|---|---|
| Preview `/plays/CODE` | The record as today. Where the text goes, the notice. Download buttons: TEI only | `lib/playcode_web/live/play_show_live.ex` |
| `/export/:id/html`, `/pdf`, `/epub` and their `/admin/plays/:id/export/…` twins | Redirect to `/plays/CODE` with the notice as a flash. Nothing rendered, nothing put in the PDF cache. `/tei` works | `lib/playcode_web/controllers/export_controller.ex` |
| Comparison | Not comparable. No Compare link to or from it; it is not in a comparison menu; `/plays/CODE/compare` and `/admin/plays/:id/compare` redirect to the preview or the play's admin page with the notice. The family list still names it and links its record | `play_compare_live.ex` (both), `play_comparison.ex`, `Components.family/1` |
| Statistics | Admin page: the notice in place of the figures. Static `statistics.html` not written | `admin/play_statistics_live.ex`, `StaticSite.write_play/4` |
| Static play folder | `index.html`, `CODE.xml`, and the redirect stub `plays/CODE.html`. No `text.html`, division pages, `notes.html`, `stage-directions.html`, `compare.html`. A folder left from when the play had a text is removed first, as today (`File.rm_rf!`) | `StaticSite.write_play/4`, `write_comparison/4` |
| Static title page | The "Contents" section gives way to a "Text" section holding the notice. The rail shows the title page only. No Form row unless curated. Cast lists, witnesses, performances, places, bibliography, citation and the TEI link as for any play | `pages/title.html.heex`, `Components.play_rail/1`, `play_contents/1` |
| Catalogue row | A "sin texto" tag beside the title; no Compare icon (a lead's Compare link opens its first derived play *with a text*); the meta shows the years only. Counted in "N plays" | `Components.catalogue_entry/1`, `StaticSite.works/1` |
| Full-text index | An empty `search/lines/CODE/` folder (the index's bookkeeping reads a missing folder as an old index), no postings | `Search.write_play/2`, unchanged |
| Admin | The content tabs stay: adding text makes it an ordinary play. The play list's "No text" badge and filter stay, now read from `Play.has_text?/1`. Marking complete is allowed | `admin/play_list_live.ex` |

A comparison whose original is published but has no text is not written either: `write_comparison/4` asks `Play.has_text?/1` of both sides.

### 7.4 The record index

**File.** `search/records.js`, one call:

```js
EMOTHE.records.load([ entry, … ]);
```

`EMOTHE.records.load` is defined by `catalogue.js`, not by `search.js`, which the catalogue page loads only for a full-text search. It is a script and not JSON for the same reason as the search files: `fetch` fails on `file://`. The entries are in the catalogue's order of plays (`Catalogue.list_plays(sort: :title_sort, complete: true)`, the order `search/plays.js` uses). One entry per published play:

| Key | Value | From |
|---|---|---|
| `c` | code | `play.code` |
| `t` | titles, a list: title, then original title when it differs | `title`, `original_title`, through `InlineMarkup.plain/1` |
| `a` | author, or absent | `author_name` |
| `l` | language | `language` |
| `o` | original language: the language of the published play at the root of its family (`StaticSite.root_id/2`), its own when it is the root | |
| `k` | kind: `original`, `translation`, `adaptation`, `version` | `Components.kind/1` |
| `s` | collection | `Components.collection/1` |
| `f` | form, or absent | `Play.form/1` |
| `x` | `1` when the play has a text, absent otherwise | `Play.has_text?/1` |
| `d` | dating, `[from, to]`, or absent | `composition_date_from`, `composition_date_to` (to = from when nil) |
| `h` | historical time key, or absent | `historical_time` |
| `w` | witnesses, a list of `[type, city, from, to, format]`, in their `position` order | `witness_type`, `pub_place`, the first and last four-digit number in `date` (`"1733-1737"` gives 1733 and 1737, `"1612"` gives 1612 twice; both null when it holds none, as "s.a."), `format` |
| `r` | performances, a list of `[toponyms, venue, venue_type, from, to, company, actors]` | toponyms: every name of the performance's place and of the places containing it; `venue`; `venue_type`; `year_from`, `year_to` (to = from when nil); the company's name; the cast's actors as displayed |
| `p` | places of action, a list of lists: per place link, every name of the place and of the places containing it | `play_places`, `place_names` |
| `n` | characters' names, hidden characters left out | `characters.name`, through `InlineMarkup.plain/1` |

An absent value is left out of the entry, an empty list too; inside a tuple a missing value is `null`. Values are as displayed: the browser normalises them with `EMOTHE.normalise` when the file loads, so the index has one normaliser to agree with, not three.

**Module.** `lib/playcode/export/static_site/records.ex`, `Playcode.Export.StaticSite.Records`:

- `entry/2`: a play with its associations loaded, and the map of published plays by id, to the map above.
- `write/3`: `dir`, the published plays, and each play's family root (`%{play_id => %Play{}}`, which `write_catalogue/3` works out with `root_id/2`); loads the associations for all of them in a fixed number of queries (not per play), writes the file, returns its size.
- Data access goes through the contexts' public functions (`Witnesses`, `Performances`, `Places`, `PlayContent`); where one lacks a "for these plays" read, it gains one. `test/playcode/export/static_site/fingerprint_test.exs` decides what is data access.

**When it is written.** In `StaticSite.write_catalogue/3`, beside `index.html`, so on every `generate/1` and every `apply_changes/2`. Whole file, from the database. No entry in `build.json`, no carry-over.

**Why it cannot be stale.** Every table it reads moves `plays.content_version`, which makes the play outdated, which makes Generate run, which rewrites the file. `test/playcode/content_version_test.exs` already covers each table; the plan adds one test that a renamed company reaches `records.js` after `apply_changes/2`.

**Size.** Measured on dev (407 plays): 10,260 character names are 104 KB; 510 witnesses, 239 performances and 148 place links are small. Estimate for about 530 plays: 250 KB, about 75 KB gzipped. Budget asserted in the records' test: **the entry of a play with nothing but its title, author, language and kind is under 200 bytes**, which is what keeps the keys short. `generate/1`'s result gains `records_bytes`, `mix playcode.export.site` prints it, and the plan records the real corpus figure in `docs/static-site.md`. It is not in the fonts' or scripts' budgets.

**Fingerprint.** The module is under `Playcode.Export.StaticSite`, so `Fingerprint.modules/0` includes it. Nothing to add.

### 7.5 The catalogue search

**One page.** `index.html` holds the form and the list. `search.html` becomes a redirect to `index.html` (`pages/redirect`-style stub, so old links work); the navigation's "Search" entry goes (`Components.shell/1`).

**Without JavaScript** the page is the full list, as today; the form is `hidden` until `catalogue.js` shows it.

**The 23 controls**, in six groups in the rail, each group a `<details>` (the first open):

| # | Group | Field | Control | Matches |
|---|---|---|---|---|
| 1 | Obra | Título | text | `t` and `c`, normalised substring |
| 2 | | Autor | text with suggestions | `a` |
| 3 | | Idioma | list, with counts | `l` |
| 4 | | Idioma del original | list | `o` |
| 5 | | Tipo | list, with counts | `k` |
| 6 | | Colección | list, with counts | `s` |
| 7 | | Verso o prosa | list, with counts | `f`; a play with no form matches no value |
| 8 | | Con o sin texto | list: todas, con texto, sin texto | `x` |
| 9 | above the list | Texto y notas | text; mode (whole word, starts with); where (all, spoken, stage directions, notes) | the full-text index |
| 10 | Datación | Datación | year range | overlaps `d` |
| 11 | Testimonios | Soporte | list | `w` type |
| 12 | | Ciudad | text with suggestions | `w` city |
| 13 | | Año | year range | overlaps `w` from–to |
| 14 | | Formato | list | `w` format |
| 15 | Representaciones | Topónimo | text with suggestions | any of `r` toponyms |
| 16 | | Lugar | text with suggestions | `r` venue |
| 17 | | Circunstancia escénica | list | `r` venue type |
| 18 | | Fecha | year range | overlaps `r` from–to |
| 19 | | Compañía | text with suggestions | `r` company |
| 20 | | Reparto | text with suggestions | any of `r` actors |
| 21 | Tiempo y lugar | Tiempo histórico | list | `h` |
| 22 | | Lugar de acción | text with suggestions | any name in any list of `p` |
| 23 | Personajes | Personaje | text | any of `n` |

**Rules** (the owner approved them on 2026-11-17):

- **Lists** are `<select>`, single choice, first option "Todas"/"Todos". Their options are rendered at build time from the values the published plays hold, labels in both languages through the site's `ta/2`; the four that exist today keep their counts, in the option's label.
- **Suggestions** are native `<datalist>`, filled from `records.js` when it loads. Typing is free; the match is a normalised substring.
- **A year range** is two number inputs, either may be empty. A value with from–to matches when the ranges overlap; a value with no year matches no range.
- **The witness fields combine on one witness, the performance fields on one performance**: "4º, London, 1600–1610" finds a play with one witness that is all three.
- **Filters combine with AND.** An empty control filters nothing.
- **"Limpiar filtros"** empties the form.
- **The state is in the address**: `index.html#lang=en&wy=1600-1610`, read on load and on `hashchange`, written with `history.replaceState`. One short name per control, fixed in plan 3.
- **Works.** A work (a lead with its translations) is shown when any of its plays matches. Inside a shown work, plays that do not match are hidden, except the lead, which stays, muted, as the family's heading. The count says how many plays match: "37 obras de 530".
- **Sorting** by author, title or date, as today.

**Full text in the same list.** With words in control 9, `catalogue.js` loads `search.js` (a `<script>` it adds, with the assets' stamp), which finds the hits. The list keeps only plays with hits that also pass the other filters; each row gains its number of hits and a `<details>` with its first five passages, each a link to the line as today's search page gives it, and "show more". Lines are loaded when a row is opened. A play without a text never has a hit. Today's search facets go: language, author and kind are form controls; the type of hit is the "where" choice.

**Loading.** `records.js` is loaded on the first `focusin` or `input` in the form, or at once when the address carries a filter. Until it arrives the controls are enabled and the list unfiltered; filtering runs when it lands.

**Row markup.** A row keeps `data-play` and gains `data-code`; `data-lang`, `data-form`, `data-kind`, `data-coll` and `data-text` go, as the filter reads `records.js` alone. The work keeps its sort keys.

**Scripts and budgets.**

| File | Holds | Budget |
|---|---|---|
| `priv/static_site/site.js` | every page's code, `EMOTHE.normalise`, `EMOTHE.words`, `EMOTHE.say`; `initCatalogue` leaves | 15,000 bytes, unchanged |
| `priv/static_site/catalogue.js` (new) | the form, the record filter, the list, the address state, the full-text rows | 15,000 bytes, new assertion |
| `priv/static_site/search.js` | the full-text engine: load, shards, decode, parse, match, and one entry point the catalogue calls; its page code and facets go | 15,000 bytes, unchanged |
| `priv/static_site/catalogue.css` (new) | the catalogue's list and form; the catalogue-only rules leave `style.css` | 8,000 bytes, new assertion |
| `priv/static_site/style.css` | every other page's styles | 25,000 bytes, unchanged |

The record filter is a pure function (`EMOTHE.records.match(entry, query)`) so `node --test test/js/*.test.mjs` tests it without a page, as it does the search engine.

**Not in this design**: counts that follow the filters, multiple choice, saving searches.

### 7.6 FileMaker's plays without a text

**Task.** `mix playcode.import.filemaker.plays [--dry-run] [--path FILE]`, and `Playcode.Release.import_filemaker_plays/1` (`dry_run: true` first) on Fly, as the other imports. Module `Playcode.Import.FilemakerPlays`, with a pure `plan/2` (records and held plays to a list of plays to create and a report) and `apply_plan/1`, as `FilemakerSync` has.

**Reads** `doc/w3emothe_T01_tituloEM.ndjson`, layout `T01_tituloEM`, through a new reader in `Playcode.Import.Filemaker`, `load_records/1`, beside `load_versions/1`, which stays as it is (`FilemakerSync` merges what it returns into its fills).

**Selects** a record when `bus_edicionWeb` is `"0"` and no play, archived ones included, has its code as `Play.short_code/1`. On today's export and corpus: 121.

**Creates** a draft play (`is_complete: false`) per record, through `Catalogue.create_play/1`, logged in the activity log as the other imports are:

| Column | From |
|---|---|
| `code` | `FilemakerXml.version_code(_IdTituloEmothe)` |
| `title` | `pub_Titulo` |
| `title_sort` | `pub_TituloOrden` |
| `author_sort` | `pub_Autor` ("Molina, Tirso de") |
| `author_name` | `pub_Autor` turned at its first comma ("Tirso de Molina"); as it is when it has no comma |
| `language` | `bus_idioma`: `1` es, `2` fr, `3` en, `4` it, `5` pt |
| `historical_time`, `historical_time_note` | `bus_tiemHistorico`, `pub_TiemHistorico`, read as `load_versions/1` reads them |
| `composition_date_note` | `pub_datacion`, read as `load_versions/1` reads it. The years are not filled: FileMaker's accepted years are in the published index, which lists none of these works |

A record with no language or an unknown one is skipped and reported; one with no author is created with none.

**Does not set** kind and original (`relationship_type`, `parent_play_id`): the export does not say. The dry run and the run both report, per new play, the held plays that share its `_IdObraEmothe` (69 of the 121 have one) and its `bus_tradTraductor` when filled, so a curator sets kind and original in the play form.

**Then the existing imports, unchanged**, fill the new plays, in this order: `mix playcode.import.witnesses`, `mix playcode.import.bibliography`, `mix playcode.import.places`, `mix playcode.import.performances` (`Playcode.Release.import_*` on Fly). Each already works on any held play it has not imported; the plan proves each reaches a play created by this task and fixes what does not. `mix playcode.import.filemaker` is not needed for them: it has no twin on Fly, and what it would fill is written at creation.

**Complete copy**: nothing new is stored, so every column of such a play is already in the TEI file or among the kept-out ones.

**Re-run**: a second run creates nothing (every code is now held).

**Missing from today's export** (also listed in `docs/stakeholder/preguntas.html`, *FileMaker tables we still need*):

1. Each version's kind and its original. The published index (`T00_indiceEM`) lists published versions only.
2. The characters as a table. T01's `bus_personaje` is one unseparated string ("Husband All Master Gentleman"), filled in 13 of the 121.
3. The author of the version against the author of the work: `pub_Autor` gives Corneille for EMOTHE0141, a Guillén de Castro text. 4 of the 121 have none.
4. What `bus_coleccion` 1, 2 and 3 mean. Playcode works a collection out from the code's prefix, so all 121 read EMOTHE.
5. The files of 35 further records with no TEI file here: 29 flagged as having a web edition, 6 with the flag empty.
6. The work's title with its article: `pub_TituloObra` reads "burlador de Sevilla", so `original_title` is not filled.
7. The accepted years of composition of a work with no published version: T01 gives the competing datings as text only, so these plays are not found by the search's dating range until a curator types the years.

### 7.7 Downloads on the published site

A play with a text offers three things from its title page, in a "Descargas" / "Downloads" section that takes the place of today's lone TEI link:

| Download | What | Where it comes from |
|---|---|---|
| TEI-XML | `plays/CODE/CODE.xml` | as today |
| EPUB | `plays/CODE/CODE.epub` | `Export.Epub.generate/1`, written by `StaticSite.write_play/4` with the play's pages |
| Print or PDF | a link to `text.html#print`; on that page a button, "Imprimir o guardar como PDF" | the browser's print over `@media print` |

**EPUB.**

- Written for every play with a text on every build of that play, so it follows `content_version` and the site fingerprint like the play's pages. No cache, no separate tracking.
- `Export.Epub` and the modules it calls that are not yet listed (`Export.Download`, `Export.Html` and what `fingerprint_test.exs` names) join `Fingerprint`'s `@modules`: a change to the EPUB's code rebuilds every play, as a change to a page's does.
- The same play gives the same bytes on every build: the book's `dcterms:modified` and every archive entry's time are the play's `updated_at`, not the clock. Otherwise each rebuild of the whole site (any change to the export's code) would push 33 MB of new binaries to the repository Deploy uses.
- The EPUB is in the downloads' English, as `/export/:id/epub` gives it.
- Cost: about 0.15 s and 80 KB per play built; about 33 MB on the whole site.

**Print.**

- The button is on `text.html`, hidden until `site.js` shows it, and calls `window.print()`. The title page's link opens `text.html#print`, which prints once the page has loaded.
- On `beforeprint`, `site.js` takes the measured alignment off the shared lines (`data-aligned`), so on paper each part keeps the fixed step it has with scripts off, which cannot wrap; on `afterprint` it measures again (`EMOTHE.align`). A browser gives no chance to measure against the paper's column, so the screen's measure is not used there. That closes the site's half of the backlog note.
- The button reuses an existing button style: `style.css` has no room for a new rule beyond a few bytes.
- With scripts off there is no button; the browser's own print command gives the same result.

**A play without a text** has the TEI link alone: no EPUB is written, and there is no `text.html` to print.

**The preview** (`/export/:id/pdf` through `PdfCache`, `/export/:id/epub`, `/export/:id/html`) is unchanged: staff keep the rendered PDF.

**Not built**: PDF files on the site, the nightly run, its trigger.

## 8. Documents each plan updates

| Document | Plan |
|---|---|
| `CONTEXT.md` (two entries) | 1 |
| `docs/tei-mapping.md` (`body`, `extent`) | 1 |
| `docs/schema.md` (`auto_form` nullable, what nil means) | 1 |
| `docs/stakeholder/ida-y-vuelta.html` (row "Una obra sin texto") | 1 |
| `docs/static-site.md` (a play without a text; `records.js`; `catalogue.js` and `catalogue.css`; budgets; the merged search; the downloads) | 1, 2, 3, 5 |
| `docs/architecture.md` (file map) | 1, 2, 3, 4, 5 |
| `docs/development.md` (the new import, its order) | 4 |
| `CLAUDE.md` (the new command; the budgets line) | 3, 4 |
| `docs/stakeholder/ida-y-vuelta.html` (the static site's column: EPUB, print) | 5 |
| `docs/backlog.md` to `docs/history.md` | each, on finishing |

## 9. Left to the builder

- The short names of the 23 controls in the address, and the form's exact markup and styles (within `catalogue.css`'s budget).
- The queries behind `Records.write/2`, within "a fixed number, not per play".
- Whether `Filemaker.load_versions/1` grows or a sibling function reads the creation fields.
- The wording of flashes and badges beyond the two notices fixed in 7.1 and 7.2, in both languages through gettext.

## 10. Calls made by the designer, for the owner to check

- "No text" is read from `auto_form` being nil, a value Playcode already derives on every import and content edit, behind `Play.has_text?/1` (7.1). No new column.
- "No text" means no verse line and no line of prose, the admin list's existing rule, not "no element of any kind" as first put (7.1). `Catalogue.without_text/1` goes.
- `play_fixture/1` keeps giving tests a play that counts as having a text (7.1).
- The import preview's warning is a new key, `removes_text` (7.2).
- Lists are `<select>` with counts in the option label, not radios (7.5).
- In a shown work, the lead stays, muted, when only a translation matches (7.5).
- `records.js` uses one-letter keys and display values, normalised in the browser (7.4).
- The record index's budget is on a bare play's entry, 200 bytes; the whole file's size is reported by Generate, not capped (7.4).
- `records.js` calls `EMOTHE.records.load`, which `catalogue.js` defines (7.4).
- The task is named `mix playcode.import.filemaker.plays` (7.6); it fills historical time and the dating note itself, so the older FileMaker sync is not part of the run.
- The catalogue's page is tested in a real headless Chrome, through the address, in tests tagged `:browser` and left out of the default run and of CI, which has no Chrome (plan 3).
- The catalogue's styles get a stylesheet of their own, `catalogue.css`, 8,000 bytes (7.5).
- Plans run on either base: `main` as it is, or with `feature/preview-real-site-pages` merged (section 5).
- The title page's download link to print is `text.html#print` (7.7).
- `original_title` is not filled from FileMaker (7.6, item 6).
