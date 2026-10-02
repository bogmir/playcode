# Static site follow-ups

**Status:** design, 2026-10-02. Follows the static site redesign
(`docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`, merged at `b729b79`) and
settles the five questions its final review left to the project owner.

## Decisions taken

| # | Question | Decision |
|---|---|---|
| 1 | Two size budgets miss on the full corpus | Fix them, as below (parts A and C) |
| 2 | A mostly-prose play with a few verses is labelled "Verse" | Keep the automatic label; add a field that overrides it (part D) |
| 3 | Adaptations (`adaptacion`, `refundicion`) are labelled "translation" | Known issue, awaiting the project's stakeholders. Not built |
| 4 | Removing a play from the site freezes the admin page | Make builds parallel and the index incremental (part B) |
| 5 | Verse forms grouped into families | Known issue, awaiting the project's philologists. Not built |

Items 3 and 5 are recorded in `docs/static-site-improvements.md` under "Awaiting the project".

## What was measured

On `playcode_dev`, all 83 plays generated with `--all`, at `b729b79`:

- **Act pages.** 3 of 344 exceed 80 KB gzipped: EMOTHE0254 act 1 (86.7), EMOTHE0648 `play`
  (86.5), EMOTHE0084 act 1 (84.6). All three are French prose translations whose TEI puts the
  whole play, or most of it, in one division with 18 to 38 scenes. Their text alone is
  200–218 KB raw, 72–78 KB gzipped, so trimming markup cannot bring them under. The next
  largest page holds 71 KB of text.
- **First search.** `search.js` today loads the whole lines file of each of the first 20
  plays: about 4 MB raw for *amor*, *de*, *que* or *sueño*. The largest shard, `de`, is
  627 KB raw.
- **Builds.** The full corpus takes 23 s sequentially: 8.5 s loading plays, 6.1 s rendering,
  8.3 s building the search data. With four plays at a time: 7.8 s. Adding or removing one
  play today reloads every play on disk to rebuild the search index, inside the admin
  page's own process.

Simulated on the same index, with the formats in part A, the first search for every word
tried (*sueño*, *amor*, *de*, *y*, *honneur*, *que*, *"vida es"*) costs 33–165 KB gzipped.

## Part A — search payload

1. **Lines files in chunks.** `search/lines/<CODE>/<k>.js` holds lines `k*100` to
   `k*100+99` of the play, as `EMOTHE.search.load("lines", "<CODE>/<k>", {speakers, lines})`.
   Each chunk carries only the speakers its lines use. The chunk size, 100, is in
   `test/fixtures/search_normalisation.json` (`lines_per_chunk`), and the Elixir and Node
   tests both assert their side uses it.
2. **Delta-encoded postings.** A shard maps a word to `[play, n, d1 … dn, play, n, …]`, plays
   in index order, where `d = (line − previous line) × 2 + flag` (previous starts at 0; flag 1
   for a stage direction). It halves the shards.
3. **Ten plays first.** The search page loads lines for the first ten groups and, in each,
   only the chunks holding the lines it shows. "Show all" loads more.
4. **The budget is gzipped**, like the act page's: what a visitor downloads. Lines are still
   fetched only for what is on screen; a phrase query loads the chunks of its candidate lines.

## Part B — builds

1. **Parallel.** `generate/1` prepares, renders and indexes plays with `Task.async_stream`,
   at most `min(schedulers, pool size − 2)` at a time, results in catalogue order. Progress
   is reported as each play finishes, in order.
2. **Incremental index.** The shards already in the site are the index. Adding a play
   computes only that play's postings; removing one computes none. `Search.write_index/3`
   carries every other play's postings over from the shards on disk, renumbered to the new
   play order, so no other play is loaded. A play on disk whose postings are missing (a site
   from an older build) is loaded and indexed. Lines files of plays no longer in the site
   are pruned.
3. **Work-family pages follow.** Adding or removing a play re-renders the title pages of its
   published original and translations, so no title page links a play that is gone.
4. **The admin page stays responsive.** Switching a play off runs in a task, like switching
   one on. `SiteBuilder` owns the site directory and refuses a second job while one runs, on
   every admin's page.

## Part C — very long divisions

A top-level division whose text exceeds **120,000 bytes** and that has at least two scenes
gets a page per scene: `act-1-s3.html`, titled "Act I, Scene 3" (the division's and the
scene's titles). The division's own page keeps its heading, any text before its first
scene, and a list of its scenes. Line anchors do not change. The rail and the title page's
contents link the scene pages; previous/next walk them in order; search links land on them.
`text.html` is unchanged. The threshold sits between the largest page that fits (71 KB of
text) and the smallest that does not (200 KB).

## Part D — the form of a play

- `plays.form`: `nil` (automatic), `"verse"`, `"prose"` or `"mixed"` ("Verse and prose").
- `Play.form/1` is the override when set, else the automatic value: `"verse"` when the play has
  any verse (`is_verse`, which the importers and every content edit already recompute from
  the verse lines), `"prose"` otherwise. The automatic value never says `"mixed"`; a curator
  does.
- The admin form replaces the "Verse play" checkbox, which the next content edit silently
  overwrote, with a select: "Automatic (Verse)" / Verse / Prose / Verse and prose.
- `form` is `@platform_owned`: a TEI re-import keeps it, and the import preview says so.
- Everywhere the site or the live page names a play's form, it reads `Play.form/1`: the
  catalogue's Form facet and entry line, the title page, the live play page. The statistics
  page measures characters in lines for a verse play and in words otherwise.

## Testing

TDD per CLAUDE.md, through the outermost API: `StaticSite.generate/1` and the files it
writes, `ExportSiteLive` through `live/2`, the play form through `render_submit/1`,
`TeiParser.preview_import/1`. The Node suite covers the decoder and chunk addressing.

## Out of scope

Items 3 and 5 above; trimming per-line markup (part C makes it unnecessary); asserting the
budgets in a test (the corpus is in the dev database, not in the test fixtures).
