# The comparison on the static site (problem 5, step 2)

Designed with the owner on 2026-11-11. Step 2 of
`docs/superpowers/specs/2026-11-08-translation-alignment-design.md` (*Order of work*); step 1,
computed speech pairs in Playcode's comparison, is built and merged.

## Why

The researcher, 2026-11-10: "los paralelos son también parte de la Biblioteca". Readers of the
site read an original beside its translations, but the static site has no comparison page:
today they get one only in Playcode (`/plays/:code/compare`) or as an admin download. Step 1
made the scrolling follow the speeches instead of drifting by proportion; this step puts that
comparison where the Biblioteca's readers are.

## What the reader sees (decided by the owner)

- **A "Compare" button on the original's line of the site's catalogue** (`index.html`), as on
  Playcode's catalogue (the ⇄ icon on the parent play's row), shown only when the original has
  at least one published derived play (translation, version or adaptation: each gets a page,
  below; Playcode's icon shows for the same plays). The "any derived play" is my call.
- **The button opens the original beside one translation**: the original on the left, the
  first translation the catalogue lists under it on the right.
- **A menu in the page's bar switches translation** (the owner chose this over a list opened
  from the button). Choosing one opens that pair's own page.
- **One translation at a time.** Several side by side may come later; not now.
- **The page is Playcode's comparison page, on the site**: a back link, the display switches,
  two panels each with its header (title; author and code) scrolling on its own, kept together
  by `assets/js/sync_scroll.mjs` with step 1's pairs. "Very similar to what we have already,
  but the scroll works better in parallel now."

## Goals and non-goals

- **Goal:** a reader on the site reads any published original beside any of its published
  translations, and scrolling one panel keeps the other at the same speech.
- **Not now:** more than two panels; a button on the translation's line or on a play's own
  pages; correcting a pair (steps 3–5 of the alignment spec).
- **A failure even if it works:** a page that breaks opened from disk (`file://`), or that
  makes a request to another site (Endings); a comparison that shows a play differently from
  the play's own pages; a translation page left stale after its original changed.

## Constraints (the site's rules, `CLAUDE.md` and `docs/static-site.md`)

- Pure HTML, CSS and JS, no third-party requests, everything working from the unzipped
  archive opened as `file://`: each page holds both texts; no `fetch`, no iframes.
- Every path built from a play code goes through `StaticSite.safe_code!/1`.
- A page links styles and scripts as `assets/…?v=` with `@site.assets`.
- `site.js` and `search.js` stay within 15 KB each, `style.css` within 25 KB
  (`static_site_test.exs`).
- Generate rebuilds only what changed; a page Generate misses is a tracking bug.
  `fingerprint_test.exs` fails while the export calls an app module that is not
  fingerprinted: `Playcode.Alignment` joins the fingerprint.
- The site is in English (`in_english/1`).

## How (the builder's calls, marked as such; the owner may overrule)

- **One page per pair, in the translation's folder: `plays/<TRANSLATION>/compare.html`.**
  Written by `write_play/3` when it writes a translation, adaptation or version whose parent
  is published. My call. Why there: Generate already re-exports a changed play's published
  original and translations in full (`relatives/3`, because their title pages link each
  other), so the page is rebuilt when either play changes with no new tracking. Building it
  needs the original's `Edition` too; load it once per translation.
- **Which plays get a page:** every published play whose `parent_play_id` names a published
  play, whatever its relationship. Translations and versions get step 1's pairs
  (`Alignment.mark_pairs/1`); an adaptation keeps the proportion, as in Playcode. My call.
- **The menu** lists the published plays with the same parent, in the catalogue's order
  (`works/1` sorts translations by normalised title). Each option links to that play's
  `compare.html`. My call.
- **The catalogue button** links the first of the original's published derived plays, in
  that order. A play whose parent is itself a translation (a chain) gets its page beside its
  parent and is reached from that parent's menu only, not from the root's button. My call;
  chains are rare.
- **The text is drawn as the site's full-text page draws it** (`text.html`'s components):
  the same line numbers and anchors, stage directions, notes and variants in popovers, so the
  comparison never shows a play differently from its own pages. Speeches carry
  `data-sync-act` and, where step 1 pairs them, `data-pair`, as Playcode's comparison does.
  My call.
- **The back link** goes to the original's title page (`plays/<ORIGINAL>/index.html`). My
  call.
- **Generate needs nothing new**: checked 2026-11-11, `StaticSite.outdated/1` turns each
  changed play into `{:add, id}`, and `apply_changes/2` re-exports the published relatives of
  every play it adds.
- **The look is the site's own** (its `style.css`: colours, fonts, light and dark), not
  Playcode's admin look. My call.
- **Switches: the site's own set** (decided by the owner, 2026-11-11), not Playcode's five:
  the play pages' Show group (stage directions, verse forms, variants, Folio interpolations,
  tagged names) and Highlight group (shared lines, stage directions), each offered only when
  one of the two plays has what it switches, through `site.js`'s existing `data-toggle`
  handling and its remembered choices (`reader.*` in `localStorage`). A switch acts on both
  panels.
- **The scroll sync**: `sync_scroll.mjs` reaches the site as an asset, its `export` keywords
  stripped as `Export.CompareHtml` does, loaded only by the comparison page (so `site.js`'s
  budget is untouched), stamped `?v=` like the others.
- **Switching translation keeps the place**: the menu's links carry the original panel's top
  speech (its place among the original's speeches) in the URL's fragment, and the new page
  scrolls its original panel there on load, the other panel following. My call; on a page
  without pairs (an adaptation) the place is still the original's speech, so it works too.
- **Two columns at every width**, as in Playcode; each panel scrolls in its own box (a
  scrolling box gets `tabindex="0" role="region" aria-label`, as the accessibility rules
  ask). My call.
- **Size:** about 1 MB of HTML per page before compression (the 0038/0084 download is
  1,064,911 bytes). The build reports the largest page gzipped; no budget is asserted for
  comparison pages. My call.
- **Not in the search index**; the play pages already are.
- **Tests:** through `StaticSite.generate/1` and `apply_changes/2` as `static_site_test.exs`
  does: the page exists for a published pair and not for a draft one; the catalogue's button
  and the menu link the right pages; speeches carry `data-pair`; the page is rebuilt when the
  original changes; the page makes no outside request and the script runs alone (as the
  download's test runs it under `node`). `docs/static-site.md` gains the page in *Output
  structure*.

## Open

Nothing: the one open question (which switches) was decided on 2026-11-11.
