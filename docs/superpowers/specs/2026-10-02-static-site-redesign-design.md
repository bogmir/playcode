# Static site redesign

**Status:** design, 2026-10-02. Replaces the look, structure and search of the site
`Playcode.Export.StaticSite` generates for the public EMOTHE archive. Deferred work found while
scoping it is in `docs/static-site-improvements.md`; the first item there (in-text editorial
notes) is the next project.

The published site today reuses the admin platform's look, renders every play on one page, and
searches only titles, authors and codes. This redesign gives it a scholarly identity of its own,
splits plays by act, adds full-text search across the corpus and much richer statistics, and
restructures the generator so it is safe and maintainable.

## Goals

- **Scholarly and high-end, clearly not Playcode.** A modern digital edition: serif text,
  restrained interface, generous margins.
- **Very fast.** Static HTML/CSS, no third-party requests, small JS that only enhances.
- **Endings-compliant.** Readable with JS off; works from a web host *and* from the unzipped
  archive opened as `file://`, search included.
- **Full-text search across every published play**, run entirely in the browser.
- **Statistics a philologist would use:** metrical synopsis, per-character figures, who shares
  the stage.

## What the code does today, and what is wrong with it

`lib/playcode/export/static_site/renderer.ex` (1,019 lines) builds every page, the stylesheet
and the statistics by string interpolation; `search.ex` holds the JS in a heredoc.

- **Italics print as `<<word>>`.** The importer stores `<emph>` / `<hi rend="italic">` as
  `<<…>>`. Only the live page (`PlaycodeWeb.Components.PlayText`, private
  `split_inline_markup/1`) turns it back into `<em>`; the renderer escapes it.
- **Escaping is by hand.** Any `#{}` without `escape/1` writes raw HTML into a public site.
- **The play text is rendered five times**: `Renderer`, `Export.Html`, `Export.CompareHtml`,
  `Export.Epub` (each with its own `render_element` and `escape/1`) and `PlayText`.
- **Labels are duplicated** between the renderer and `StatisticsPanel`.
- **CSS and JS live in Elixir strings**: no highlighting, no linting, no devtools round trip.
- **`search-index.json` is built and never read**; `search.js` filters the DOM on three fields.
- **CLAUDE.md says `plays/<CODE>/index.html`**; the code writes `plays/<CODE>.html`.

This redesign fixes all of these for the static site. The other three exporters keep their
copies for now (`docs/static-site-improvements.md`, items 2 and 3).

## Findings that shape the design

Measured against the tracked fixtures and `playcode_dev` on 2026-10-02.

- **Verse forms are mostly not on the line group that holds them.** TEI splits a stanza that
  runs across speeches into `<lg part="I|M|F">`; often only the `I` fragment carries the form and
  the continuations say `type="free"`. In *La vida es sueño* (EMOTHE0020) 409 line groups are
  `free`, holding 1,939 of 3,319 verses. The existing `verse_type_distribution` counts
  fragments, so it reports `free` as the most common form. The metrical synopsis below counts
  verses and lets fragments inherit.
- **Six plays carry `type="nil"` in the source** (EMOTHE0648, 0724, 0728, 0734, 0759, 0763; 554
  line groups in 0724 alone). Not an importer bug; treated as unmarked.
- **32 of 83 plays encode no scenes**, *La vida es sueño* among them: Spanish comedias often
  divide only into jornadas.
- **Rhyme is not encoded**, so two consecutive romances with different assonance cannot be told
  apart.
- **Only 3 plays are marked complete in dev** (EMOTHE0038 and its translations 0052, 0139). The
  published catalogue is that small until curators mark more; the design is sized for the full
  corpus of 82.
- **In-text `<note>` and inline `<stage>` are pasted into the line they sit in** (333 notes in
  13 tracked fixtures). Out of scope here (improvements item 1); search will surface it, e.g.
  EMOTHE0020 v. 2064 is stored as "(En sueños) Piadoso príncipe es".

## Architecture

Approach: HEEx templates inside the Elixir export. Considered and rejected: exporting JSON to a
separate generator (adds Node and a second build to the admin "generate" button) and a
client-rendered app (breaks no-JS reading and Endings).

### Modules

| Module | Role |
|---|---|
| `Playcode.Export.StaticSite` | Orchestrator. Public API unchanged: `generate/1`, `generate_single_play/2`, `remove_single_play/2`, `rebuild_index/1`, `list_exported_codes/1`. Loads plays, writes pages, copies `priv/static_site/`, builds search. |
| `StaticSite.Pages` | `use Phoenix.Component`, `embed_templates "pages/*"`, one `.html.heex` per page type; `render/2` returns a string via `Phoenix.HTML.Safe.to_iodata/1`. |
| `StaticSite.Components` | Play text (speech, verse line, split-verse ghost, stage direction, prose, empty note slot), charts (band, bar, matrix), rail, header, footer. |
| `StaticSite.Search` | Normaliser, word splitter, shard and lines writers. |
| `Playcode.PlayContent.InlineMarkup` | The `<<…>>` parser, moved from `PlayText`, which then calls it. No web dependency. |
| `PlaycodeWeb.PlayLabels` | Gains the verse-form and act labels now duplicated in the renderer and `StatisticsPanel`. The static site pins the English locale, as it does today. |

`Renderer` is deleted. The moduledoc's "no Phoenix dependencies" rule goes with it: it is what
forced hand-rolled escaping.

### Static assets — `priv/static_site/`

`style.css`, `site.js` (reading tools, catalogue filter), `search.js`, and `fonts/`: Source
Serif 4 (text, roman + italic) and Inter (interface), woff2, Latin + Latin Extended subsets,
with their OFL licence files. Copied verbatim to `_site/assets/`.

### Output

```
_site/index.html                  catalogue
_site/search.html
_site/about.html
_site/assets/                     style.css, site.js, search.js, fonts/
_site/search/plays.js             play list and facet data
_site/search/index/<xx>.js        word → [play, line] shards
_site/search/lines/<CODE>.js      line text and references, per play
_site/plays/<CODE>/index.html     title page
_site/plays/<CODE>/act-1.html …   one page per act; prologue.html etc. for other text divisions
_site/plays/<CODE>/text.html      full text
_site/plays/<CODE>/statistics.html
_site/plays/<CODE>/<CODE>.xml     TEI-XML
_site/plays/<CODE>.html           redirect stub (meta refresh + link) to plays/<CODE>/
```

- Act files are `act-N` whatever the act is called (jornada, acto, act, acte).
- Any other top-level division with text gets a page named by its type (`prologo.html`,
  `argumento.html`, `dedicatoria.html`), with `-2`, `-3` for repeats. The cast list (`elenco`)
  and the front-matter notes go on the title page.
- Verse lines are anchored `#l<number>`; prose paragraphs and unnumbered fragments `#p<n>`,
  `n` counting within the play.
- A play with no act divisions gets `text.html` and no act pages.
- `list_exported_codes/1` and `remove_single_play/2` move from `plays/*.html` to `plays/*/`.
- The redirect stubs keep links to the current layout working.

## Visual design

Chosen in the brainstorm (mockups under `.superpowers/brainstorm/`, git-ignored):

- **Direction B, "contemporary archive"**: Source Serif 4 for the text, Inter for the
  interface, ink-navy accent `#1f3a5f` on paper `#fbfbf9`, hairlines `#e3e6ea`.
- **Top bar from direction A**: wordmark left in small caps, `catalogue · search · about` right,
  set in the text face; current page underlined. No search field in the header.
- The wordmark is typed `EMOTHE` and set `font-variant: all-small-caps`.
  `test/rename_guard_test.exs` fails on lower-case `emothe` in tracked files, so class names, JS
  globals and file names never use it.
- Speakers in Inter caps, accent colour; stage directions italic, indented; line numbers in a
  left gutter, Inter, muted, tabular figures; verse-form labels in the right margin.
- Light and dark follow `prefers-color-scheme`. No toggle.

### Chart colours

The metrical synopsis puts any two forms side by side, so its colours are validated all-pairs,
and only three categorical slots pass that. Forms are therefore coloured by **family**, always
with a text label or legend:

| Role | Light | Check (`validate_palette.js --pairs all --surface #fbfbf9`) |
|---|---|---|
| Romance | `#2f66a8` | all PASS: CVD ΔE 9.1, normal-vision ΔE 20.7, all ≥ 3:1 |
| Spanish stanzas | `#cf6a3a` | |
| Italianate | `#22a07a` | |
| Other / unmarked | neutral grey | not a categorical slot |

Dark-mode steps are chosen and validated against the dark paper colour during implementation;
they are not an automatic flip.

## Pages

### Shell

Top bar; a rail on the left from 960 px wide, collapsing below that into a `<details>`
"Contents & tools" panel at the top (no JS needed); footer with version, build date, licence
and the Endings link.

### Catalogue (`index.html`)

- One entry per work: the original, with its published translations nested beneath. A
  translation whose original is not published or not linked is its own entry, tagged
  "translation".
- Facet rail with counts: language; verse/prose; original/translation; collection, EMOTHE or
  ARTELOPE, from the code prefix (`AL` is ARTELOPE).
- Filter field (title, author, code) and sort by author, title or composition date; plays
  without a date sort last.
- No JS: the full list, facets hidden. With JS, filtering works on data attributes already in
  the page; no requests.

### Title page (`plays/<CODE>/index.html`)

Author, title, original title, code, language, verse/prose and verse count, composition date and
note, historical time, places; editors with roles; sources; licence; TEI download; links to the
original or translations in the same work family; front-matter notes; cast list; contents
(acts and scenes, linking to act pages and anchors); a "Cite this edition" block with a copy
button.

### Act pages and full text

Act heading, scenes, text; previous/next act at top and bottom. The rail shows the acts with the
current one expanded to its scenes, then the reading tools. `text.html` is the same with every
act, and is the page the print stylesheet targets.

### Reading tools

JS reveals the controls and remembers each reader's choices in `localStorage`; without JS the
defaults apply.

1. Line numbers: all / every 5th (default, done in CSS) / off.
2. Stage directions shown or hidden.
3. Verse-form labels in the margin, one at the start of each metrical passage (not each stanza).
4. Highlight one character: their speeches get the accent rule, the rest dims.
5. Line links: tapping a number copies its URL (`…/act-2.html#l2186`) and a one-line citation.
6. Print stylesheet: no chrome, a page break per act, numbers every 5th.

### Text rendering

- **Split verses align exactly.** Before an `M` or `F` fragment the build renders the text of
  the verse's earlier fragments in a `visibility: hidden; aria-hidden="true"` span, so the
  fragment starts where the previous one ended. Replaces today's fixed 50 px / 100 px offsets;
  needs no JS and prints correctly.
- Asides get a small "aparte" mark in the margin.
- `<<…>>` becomes `<em>` through `InlineMarkup`.
- An empty note slot is in the markup, for the notes project to fill.

### Statistics page (`plays/<CODE>/statistics.html`)

As approved in the mockup for *La vida es sueño*:

1. Summary figures: acts, verses, metrical passages, speeches, speaking characters, stage
   directions, verses in asides.
2. **Metrical synopsis**: a band of passages drawn to scale, coloured by family, with dashed
   act separators and a family legend with totals; then the table (act, form, verse range,
   lines). A note says rhyme is not encoded.
3. **Characters**: speeches, lines, share of the play (bar), first words (act and verse), main
   verse forms.
4. **Who shares the stage**: a character × column matrix; columns are scenes, or metrical
   passages for a play with no scenes, labelled as such.

Charts are server-rendered HTML/CSS; JS adds hover tooltips. Every chart's numbers are also in
a table.

### Search page (`search.html`)

Results grouped by play (option B), ranked by number of hits, five lines per play with "show
all"; each hit shows act and verse, speaker and the line with matches highlighted, and links
to its anchor. Facet rail: language, author, original/translation, spoken text / stage
directions. Without JS: "Search needs JavaScript", with a link to the catalogue.

### About page

Only facts the build knows: number of plays, version and build date, how to cite, TEI
downloads, Endings. Text about the project itself comes from the project and lives in a
hand-edited template; the build does not invent it.

## Statistics

Computed in `Playcode.Statistics`, stored in the existing `play_statistics.data` JSONB. New keys
are added; the old ones stay because `StatisticsPanel` still reads them (improvements item 4).

### Cache versioning

`data` gains `"version"`. `get_statistics/1` recomputes when it is missing or older than the
module's `@version`, so every cached row refreshes on first read. No migration, no manual
recompute.

### `metrical_passages`

List in document order of `%{"act", "form", "from", "to", "verses"}`.

- A line group with a real form and no `part`, or `part="I"`, opens a passage, unless it has
  the same form as the passage already open, which it then continues.
- A line group with `part="M"` or `"F"` continues the open passage, whatever type it carries.
  With no passage open it opens one with its own type.
- `free` with no `part`, an empty type, and `"nil"` are **unmarked**; consecutive unmarked
  groups form one passage.
- A new act closes the open passage.
- `verses` counts verse lines with no `part` or `part="I"`, so a split verse counts once;
  `from`/`to` are the first and last verse numbers in the passage.
- A play whose passages are all unmarked (most French and English plays) has no synopsis.

Checked against EMOTHE0020: 16 passages, ending Jornada II with the décimas 2018–2187.

### Families

**To be reviewed by the project's philologists.** Unknown forms fall into Other.

| Family | Forms in the corpus |
|---|---|
| Romance | `romance_tirada`, `romancillo_o_endecha` |
| Spanish stanzas | `redondilla`, `quintilla`, `decima`, `copla_arte_mayor`, `copla_estructura_abierta` |
| Italianate | `terceto`, `octava_real`, `soneto`, `lira`, `sexteto_lira`, `silva_tirada`, `cancion_canzone`, `endecasilabos_sueltos_tirada`, `pareados_endecasilabos`, `cuarteto`, `verso_suelto` |
| Other | `pareados`, `pareado_hexasilabo`, anything new, unmarked |

### `characters`

One entry per character, identified by the character id from `element_characters`, falling
back to `speaker_label` as `character_appearances` does today:

- speeches;
- lines — every verse-line fragment counts for its speaker, so a split verse counts once for
  each speaker;
- words, in verse and prose, with `<<>>` stripped;
- first words: act and verse;
- verses in asides;
- longest speech, in lines;
- verses per form;
- the presence columns they speak in, with lines per column.

Share of the play is measured in lines for a verse play and in words for a prose play
(`is_verse`).

### `presence`

Column list: the play's scenes if it has any, else its metrical passages, each with a label.
Rows come from `characters`.

### `divisions`

Per act and scene: verses, speeches, speaking characters.

## Search

### Scope

Verse lines, prose and stage directions of every published play.

### Normalisation

Identical at build time (Elixir) and query time (JS):

1. Lowercase.
2. NFD, then drop combining marks, so `á→a`, `ç→c` — **except `ñ`, which is kept**, so *año*
   and *ano* stay apart.
3. Words are runs of letters and digits: `l’onde` → `l`, `onde`.

Old spellings (`desta`, `u/v`, `i/j`) are not mapped.

### Files

Loaded by `<script>` injection, not `fetch`, so they work from `file://`. Each calls
`EMOTHE.search.load(kind, key, data)`.

- `search/plays.js`: per play its code, title, author, language, original/translation, plus the
  speaker list.
- `search/index/<xx>.js`: word → list of `[play_index, line_index]`, sharded by the word's first
  two characters (one-letter words by that letter). Characters outside `a-z0-9` are written as
  `u` plus four hex digits in the file name.
- `search/lines/<CODE>.js`: per line its act, verse number, page, anchor, speaker index, kind
  (verse, prose, stage) and original text.

### Queries

- Several words: all must occur in the same line.
- `"…"`: a phrase, checked against the line's normalised words in order.
- Mode "starts with" (default) or "whole word". In "starts with" mode every shard key beginning
  with the query word matches.
- State lives in the URL (`search.html?q=sueño&mode=prefix`) via `history.replaceState`.
- Highlighting normalises each word of the original line and marks those that match.
- Lines files are fetched only for plays on screen; "show all" fetches more.

### Size

Postings are plain arrays. The build reports the total index size and the largest shard. If
the largest shard passes 300 KB, delta-encode the postings; that upgrade is not built now.

## Testing

TDD per CLAUDE.md: each test red first, outermost API, assertions on what a reader sees.

**Site** — `test/playcode/export/static_site_test.exs`, `StaticSite.generate(output_dir: tmp)`
on plays imported from TEI snippets, output read with `LazyHTML`:

- the title page lists cast, editors, front notes and contents;
- an act page carries `#l<n>` with the verse text; previous/next links;
- a split verse's `F` fragment is preceded by the ghost text, `aria-hidden`;
- `<<x>>` renders as `<em>x</em>` (regression for the current bug);
- text containing `<script>` is escaped;
- a translation is nested under its original; facet counts;
- `plays/<CODE>.html` redirects to `plays/<CODE>/`;
- `remove_single_play/2` and `list_exported_codes/1` on the folder layout;
- a play with no acts gets only `text.html`;
- the index shards map a word to its line; the lines file holds the original text;
- the existing tests (places and historical time in English whatever the locale; composition
  date as range, year or note; no places section without places; only complete plays) are kept,
  rewritten against the new pages.

**Statistics** — `test/playcode/statistics_test.exs`, through `Statistics.get_statistics/1`:

- passages: `I/M/F` inheritance; `free`/`nil`/empty unmarked; act closes a passage; same-form
  neighbours merge; a split verse counts once; an all-unmarked play has no synopsis;
- characters: lines with a shared verse, words, first words, asides, longest speech, forms;
  share in words for a prose play;
- presence by scene, and by passage when there are no scenes;
- a cached row with an old `version` is recomputed. The test plants that row through `Repo`,
  aliased in place with a comment saying why.

**Search normaliser parity** — one list of cases (input, expected words) in
`test/fixtures/search_normalisation.json`, run by an Elixir test against `StaticSite.Search`
and by `test/js/search.test.mjs` (`node --test`) against `search.js`. CI gains one step,
`node --test test/js/`; Node is preinstalled on GitHub's Ubuntu runners.

**Size budget** — asserted by a test on the generated site, also reported by the build:

| Item | Limit |
|---|---|
| Third-party requests | none |
| `style.css` | ≤ 25 KB |
| `site.js`, `search.js` | ≤ 15 KB each, unminified |
| Fonts | ≤ 300 KB total; `font-display: swap`; roman text face preloaded |
| Longest act page | ≤ 80 KB gzipped |
| First search | ≤ 300 KB: the largest shard plus the five largest lines files |

**Manual check before calling it done.** Run `mix playcode.export.site --all`. Open the result
from `file://` and through `python3 -m http.server`. Check *La vida es sueño* (split verses,
synopsis), *Antony and Cleopatra* (scenes, translations) and a prose play. Check each at 400 px
wide, in dark mode, in print preview and with JS off.

## Rollout

One plan, in this order; `mix test` green after every step:

1. `InlineMarkup` and the labels in `PlayLabels`; `PlayText` and `StatisticsPanel` switch to them.
2. Statistics: version key, passages, characters, presence, divisions.
3. HEEx skeleton: `Pages`, `Components`, `priv/static_site/` assets and fonts, shell.
4. Pages: title, act, full text, statistics, catalogue, about, redirect stubs.
5. Search: builder, shards, `search.js`, search page, parity test, CI step.
6. Delete `Renderer`; size-budget test.
7. CLAUDE.md: the Static Site Export section and its output tree.

## Out of scope

In `docs/static-site-improvements.md`:

1. In-text editorial notes, and the inline `<stage>` flattening with the same root cause.
2. `<<word>>` italics in the HTML, PDF, EPUB and comparison exports.
3. Moving `Html`, `CompareHtml` and `Epub` onto HEEx and the shared helpers.
4. Showing the new statistics on the live play page, and dropping its wrong verse-type chart.

Also not built: a dark/light toggle, a font-size control (browser zoom covers it), a character
network graph (the matrix shows the same thing more exactly), spelling-variant search,
delta-encoded postings.

## Open questions for the project

1. **Families.** Is the grouping of forms into romance, Spanish stanzas and Italianate right?
   Where do `cuarteto`, `verso_suelto`, `copla_arte_mayor` and `pareados` belong?
2. **About page.** Who writes the project text, and in which languages?
