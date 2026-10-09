# Notes in Search and a Notes Page — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-10-09-notes-search-and-page-design.md`

**Goal:** a note's body is found by the static site's search (Text facet value "Notes"), and each
play with notes has a Notes page on the static site and a Notes view on `/plays/:code`, filterable
by type, every entry linking back to the note's marker in the text.

## Global constraints

- Run mix plainly. Red → green → refactor for every task; a test written for code that already
  works is proved by breaking the line it covers.
- After every task: `mix format`, `mix compile --warnings-as-errors`, the whole `mix test`, and
  `node --test test/js/*.test.mjs` when JS changed; then commit. Commit messages end with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Test through the outermost API: the site through `generate!/2`, the live page through `live/2`.

## Tasks

1. **`Note.with_anchors/1` and `Note.glossed/2`.** `reading_order/1` becomes the `note`s of
   `with_anchors/1`. Unit test for `glossed/2`'s word boundaries (term wins; last word before the
   offset; punctuation between; offset 0 gives nil; italics markers do not count).
2. **`Edition.notes` and marker ids.** Each note once: first page that lists it, ref, speakers,
   glossed word. Static markers get `id="nref-<n>"`. Covered through the pages in tasks 3 and 5;
   the marker id has its own assertion here.
3. **Search writer.** Note entries numbered from `Search.note_base/0`, in `n<k>.js`. Tests: posting
   at the base, the row's slug, anchor, ref, speaker and text; a split act's heading note points at
   the act page.
4. **`search.js`.** `NOTE_BASE`, `kind/2`, `chunkKey` for notes, hits as kinds, the Notes facet,
   note rows styled. Node tests; the stage-flag case updated with a comment.
5. **Static Notes page.** `pages/notes.html.heex`, written only with notes; Notes in
   `play_contents/1`; the filter fieldset and its few lines of `site.js`; `about.html` sentence;
   CSS for the list. Tests as the spec lists.
6. **Live Notes view.** View switcher entry, list, `filter_notes`, `show_note` + `scroll-to`
   listener in `app.js`, live markers' ids, Spanish translations. Tests as the spec lists.
7. **Docs.** `CLAUDE.md` (static site architecture, output structure, routes unchanged),
   `docs/static-site-improvements.md` items 6 and 7 done.
