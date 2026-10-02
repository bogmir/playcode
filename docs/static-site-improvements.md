# Static Site and Exporters — Deferred Improvements

Found while scoping the static site redesign (2026-10-02). The redesign itself restructures
`Playcode.Export.StaticSite` (HEEx templates, real CSS/JS/font files under `priv/`, shared
inline-markup and label helpers) and adds full-text corpus search. Everything below was
deliberately left out of it.

## 1. In-text editorial notes (next project)

**Problem**: `<note>` inside the play body is not modelled. `text_content/1`
(`lib/playcode/import/tei_parser.ex`) collects the text of every child element, a
`<note>` included, so the note — every `<p>` of it — is pasted into the line it sits in.
The live page, every exporter and the TEI export all show the corrupted line.

Tracked fixtures: 333 body notes in 13 plays; 271 inside `<l>`, 13 inside `<stage>`, the rest
between elements. EMOTHE0752 alone has 147. Types seen: `editor`, `editor_critico`, with `n`.

**Why the tests miss it**: `RoundtripTest` counts lines, speeches and stage directions; it
never compares a line's text against the source.

**Fix**:
- Schema for anchored notes: `n`, `type`, content (paragraphs kept), the element they hang on.
- Importer excludes `<note>` from `text_content/1` and stores it instead.
- TEI export writes `<note>` back in place; a roundtrip test that compares line *text*.
- Rendering: the redesign reserves the slot (margin note on wide screens, pop-up on narrow),
  so the static site only needs a template change. The live page needs its own.

**Same root cause**: the "Inline `<stage>` is flattened" gap in CLAUDE.md is `text_content/1`
flattening a child too. Fix both in this project.

## 2. Italics show as literal `<<word>>` in the other exporters

**Problem**: the importer stores `<emph>` / `<hi rend="italic">` as `<<…>>` inside the text.
Only the live page (`PlaycodeWeb.Components.PlayText`, private `split_inline_markup/1`) turns it back into `<em>`.
`Export.Html`, `Export.Pdf` (reuses Html), `Export.Epub` and `Export.CompareHtml` escape it and
print the brackets. The redesign fixes the static site only.

**Fix**: switch them to the shared inline-markup helper the redesign introduces.

## 3. Move `Html`, `CompareHtml` and `Epub` onto HEEx and the shared helpers

**Problem**: each has its own `render_element` clauses and its own hand-rolled `escape/1`,
building HTML by string interpolation. A fix in one copy misses the others (item 2 is the
proof), and any `#{}` without `escape/1` writes raw HTML.

**Fix**: the pattern the static site redesign establishes — HEEx templates rendered with
`Phoenix.HTML.Safe.to_iodata/1`, CSS as real files, labels and inline markup from the shared
module. One exporter per change; the output must stay byte-comparable where tests pin it.

## 4. Show the new statistics on the live play page

**Problem**: the redesign adds a metrical synopsis, a per-act/scene table, a configuration
matrix and per-character figures (verses, share, words, scenes, first entrance, asides,
longest speech, verse forms spoken) to `Playcode.Statistics`. Only the static site renders
them; `PlaycodeWeb.Components.StatisticsPanel` still shows the old set.

The old `verse_type_distribution` the panel shows is also wrong: it counts `line_group`
fragments, and TEI splits a stanza that runs across speeches into `<lg part="I|M|F">`
fragments whose continuations are typed `free`. In *La vida es sueño* it reports `free` as
the most common form (409 fragments, 1,939 of 3,319 verses). The metrical synopsis fixes the
unit (verses, with `M`/`F` fragments inheriting the open passage's form).

**Fix**: render the new keys in the statistics panel on `/plays/:code` and drop the old
verse-type chart. The data is already in the cached JSONB, so this is a component change only.

## 5. Two size budgets the full corpus misses

**Problem**: the redesign's size budget (largest act page 80 KB gzipped; a first search,
meaning the largest shard plus the five largest `search/lines/*.js`, at most 300 KB) holds for
the three plays published today but not for the full dev corpus (83 plays, `--all`):

- Largest act page: 84.7 KB gzipped (EMOTHE0254 act-1, EMOTHE0084 act-1) against 80 KB.
  Today's published plays: 31.4 KB.
- First search: about 2.4 MB raw, 0.75 MB gzipped, against 300 KB; the largest shard, "de",
  is 626,640 B. Today's published plays: about 877 KB raw, 280 KB gzipped.

Neither is asserted by a test; the build only reports them (`generate/1`'s return, the mix
task's printed line), so nothing fails when they are exceeded.

**Being fixed**: `docs/superpowers/specs/2026-10-02-static-site-followups-design.md`, parts A
(lines files in 100-line chunks, delta-encoded postings, ten plays on the first screen) and C
(a page per scene for a division over 120,000 bytes of text). The act-page overruns turned out
to be content, not markup: the three pages hold 200–218 KB of text each.

## Awaiting the project

Questions only the project can answer. Nothing here is built; each stays as it is until
someone with the authority decides.

### Adaptations are labelled "translation"

`StaticSite.Components.kind/1` calls every play with a `relationship_type` a translation, in
the catalogue's Kind facet, its "translation" tag and the search page's Originals/Translations
facet. The schema also allows `adaptacion` and `refundicion` (`Play.changeset/2`). Should an
adaptation or a *refundición* be labelled as such, counted as a translation, or as an
original? **Needs**: the stakeholders' answer; then a label per type and a facet value each.

### The grouping of verse forms into families

The metrical synopsis colours passages by family: romance, Spanish stanzas, Italianate,
other (`Playcode.Statistics.Metrics`, `@families`). The grouping is the design's, not a
philologist's. In particular: where do `cuarteto`, `verso_suelto`, `copla_arte_mayor` and
`pareados` belong? **Needs**: the project's philologists to confirm or correct the table in
the redesign spec ("Statistics › Families"); then edit `@families` and bump
`Playcode.Statistics` `@version` so cached statistics recompute.
