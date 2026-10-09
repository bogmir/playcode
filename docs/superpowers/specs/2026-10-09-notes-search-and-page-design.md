# Notes in search, and a Notes page per play

`docs/static-site-improvements.md`, items 6 and 7. Follows the in-text notes project
(`2026-10-08-in-text-notes-design.md`), whose *Out of scope* left both.

## Decisions (agreed 2026-10-09)

- **A note is a search hit of its own**, pointing at the line it hangs on. The Text facet gets a
  third value, **Notes**, beside Spoken and Stage directions. Notes count under **All**, as stage
  directions do.
- **The index format stays.** Shards, lines files and `plays.js` keep their shape. A note is told
  apart by its number: note entries are numbered from `1_000_000` (approach A).
- **Note text files are named `n<k>.js`** (`search/lines/<CODE>/n0.js`, `n1.js`, …), the same
  shape as the lines files.
- **The glossed word** is the note's `term` when it has one (326 of the 503 body notes in the
  fixture corpus), otherwise the last word before the note's offset in its text. A note at the
  start of its text has none.
- **The Notes page** exists on the static site (`plays/<CODE>/notes.html`) and on
  `/plays/:code` (a view beside Text and Statistics), only for a play with notes.
- **Links land on the note's own marker**, `#nref-<n>`: the exact word, whether the note is on a
  line, a speaker label or a heading.

## How the search index works today

Measured on the dev build, `sueño`:

- `search/plays.js`: the plays; a play's position is its number (2 is EMOTHE0382).
- `search/index/su.js`: `"sueño": [2, 5, 4054, 106, …]` is play 2, five entries, then each
  `d = (line − previous) × 2 + flag`, flag 1 for a stage direction: 4054 is line 2027, spoken.
- `search/lines/EMOTHE0382_AdonisYVenus/20.js`: lines 2000–2099. Line 2027 is
  `["act-3", "l1864", "III, 1864", 1, "v", "Pero yo soy el que sueño,"]`: page, anchor,
  reference, speaker, kind, text.

The facet counts are computed from the shards alone, before any lines file loads, so a hit's
kind must be readable from its posting. The one flag bit is taken by stage directions.

## Search

### Writer (`StaticSite.Search.write_play/2`)

- After the play's lines, one entry per note in reading order, entry `i` numbered
  `1_000_000 + i` (`Search.note_base/0`). Postings as for a line, flag 0. A play with a million
  lines raises rather than collide (none has 5,000).
- Note entries go to `search/lines/<CODE>/n<k>.js`, key `"<CODE>/n<k>"`, 100 per file, in the
  lines files' shape: `{"speakers": […], "lines": [[slug, anchor, ref, speaker, "n", text]]}`.
  - `slug`: the first page that lists the note (`Edition.page_notes/1`), so a split act's
    heading note goes to the act's own page, not to every scene page that prints it again.
  - `anchor`: `nref-<number>`, the marker's id on that page.
  - `ref`: as a search result cites the line the note hangs on (see *Where a note is*).
  - `speaker`: the speakers of that line or speech; none for a heading.
  - `text`: the note's paragraphs, plain (`InlineMarkup.plain/1`), joined by a space. The term is
    not indexed: it is a word of the line, which already has its own hit.
- The first gap of a note posting is about 2,000,000, seven digits, once per word per play.

### Browser (`priv/static_site/search.js`)

- `S.NOTE_BASE = 1000000`. `S.chunkKey(code, line)` gives `code/n<k>` at or above it.
- `S.kind(line, flag)`: `"note"` at or above `NOTE_BASE`, else `"stage"` for flag 1, else
  `"spoken"`. `S.hits` maps `"play:line"` to that kind instead of the flag; the Text facet maps
  the kind to Spoken, Stage directions or Notes.
- A note hit is drawn like a line, its text in `class="line note"`; its link opens
  `<slug>.html#nref-<n>`.
- Phrase search reads the note's text as it reads a line's. The count stays "N lines in M plays".

Unchanged: shard sharding and file names, `plays.js`, the lines files of the play text, the
normaliser.

## Where a note is

`Note.with_anchors(divisions)`: each note in reading order with what it hangs on, as
`%{note, anchor, division, scene}` (`anchor` an `Element` or a `Division`; `division` the
top-level one; `scene` its child or nil). `Note.reading_order/1` becomes its `note`s, so the
numbering and the walk stay one.

`Note.glossed(note, text)`: the term, or the last word (`[\p{L}\p{N}'’]+`) of the plain `text`
before `offset`, or nil. The caller passes `PlayContent.anchor_text(anchor)`.

`Edition.notes`: each note once, `%{note, slug, ref, speakers, glossed}`, read by the search
writer and the Notes page alike:

- `ref`: an element that is a line, paragraph, stage direction or trailer has its own
  `Edition.refs` entry; a speech (a note on its speaker) takes its first line's; a division's
  heading takes its page's title, and a scene's heading `"<act page title>, <scene title>"`.

## Static site: the Notes page

- `plays/<CODE>/notes.html` (`pages/notes.html.heex`), written by `StaticSite` only when the
  play has notes; the play's folder is rebuilt whole, so a play that loses its notes loses the
  page.
- The contents list (`Components.play_contents/1`, rail and title page) gets **Notes** after
  Statistics, when there are notes.
- An `<ol data-notes>`; each `<li data-type="…" value="<number>">` holds the type label
  (`PlayLabels.note_type_label/1`), the glossed word in italics, a link
  `<a href="<slug>.html#nref-<n>">` reading the `ref`, and the note's paragraphs.
- **The filter**: a fieldset of radio buttons, All and each type the play uses (first appearance
  order), `hidden` in the markup and shown by `site.js`, which hides the other types' items. Only
  with two or more types. Without JS, and in print, every note shows.
- The markers get an id: `<button id="nref-<n>" class="nref" …>` (`Components.part/1`). No page
  prints the same note's marker twice, so the ids stay unique per page.
- `about.html` names the Notes page among a play's pages.

## Live page (`/plays/:code`)

- A **Notes** view in the View switcher, after Statistics, only when the play has notes.
- The same list: number, type label, glossed word, a location, the paragraphs. The location is
  the division's title, the scene's, and the line number when the anchor has one.
- **The filter**: buttons, All and each type the play uses, `aria-pressed`; `phx-click`
  `"filter_notes"`. Only with two or more types.
- **Back to the text**: the location is a button; `"show_note"` with the note's id switches to
  Text and `push_event("scroll-to", %{id: "nref-<id>"})`, which a listener in `assets/js/app.js`
  scrolls into view. An id that is not one of the play's notes does nothing.
- The live page's markers get `id="nref-<note.id>"` (`PlayText.part_html/2`): uuids, so a compare
  page showing two plays keeps them unique.

## Tests

- **Search** (`static_site_search_test.exs`, through `generate!/2` and `load_js!/2`): a word only
  in a note has a posting at `note_base + 0` in its shard; `search/lines/<CODE>/n0.js` holds the
  note's row, pointing at the first page that lists it, `nref-<n>`, the line's ref and speaker; a
  split act's heading note points at the act page.
- **JS** (`test/js/search.test.mjs`): `S.kind`, `S.chunkKey` for a note, `S.hits` giving kinds.
  The existing "keep the stage flag" case is updated: the map now holds the kind.
- **Notes page** (`static_site_play_test.exs`): the page lists each note with type, glossed word
  (term, and fallback), link and text; the link's target exists on the page it names; the filter
  is there for two types and absent for one; the rail links the page; a play without notes has no
  page and no rail entry.
- **Note** functions: `glossed/2` through the pages, not directly, except the word-boundary cases
  in a short unit test, as `InlineMarkup` has.
- **Live** (`play_show_live_test.exs`): the Notes view lists the notes; `filter_notes` narrows the
  list; `show_note` switches to Text and pushes `scroll-to` with an id the page holds; no Notes
  view for a play without notes.
- `fingerprint_test.exs` stays green (the new code is in fingerprinted modules or data access).

## Out of scope

- Hamlet's notes nested in another note's `<p>` (an import limit, unchanged).
- Notes in `/api/v1`, `Export.CompareHtml` and the downloads' endnotes (they have their own).
- A hidden inline stage direction hides its notes' markers on the live page; a link to one then
  scrolls nowhere.
- Indexing a note's term.

## Rollout

The search index and the pages change, and so does the site fingerprint (the export's code), so
the next Generate rebuilds every play; nothing to run by hand. Plays whose notes were imported
before 2026-10-08 still need their TEI re-imported to have notes at all (`CLAUDE.md`, *Rollout*).
