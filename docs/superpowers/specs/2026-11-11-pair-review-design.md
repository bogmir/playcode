# Pair review (problem 5, step 5)

Decided with the owner on 2026-11-11. Replaces step 5 of
`docs/superpowers/specs/2026-11-08-translation-alignment-design.md` ("the coder's report as
a download"): the report becomes a tab of the admin comparison, and the comparison's HTML
download goes.

## What it is for

Since steps 1–3 every comparison (Playcode's page, the static site's `compare.html`) pairs a
translation's speeches with its original's through `Playcode.Alignment`, characters first,
corrections on top. Nobody can see that pairing except by scrolling and noticing a drift.
The team needs to see where it is doubtful: to correct a character pair on the Elenco tab,
to find encoding slips (a speaker repeated after a stage direction, a speech given to the
wrong character), and to learn whether speech corrections (step 4, parked) are ever needed.

Not a correction screen: the review only reads. Corrections stay on the Elenco tab.

## The admin comparison gets two tabs

`/admin/plays/:id/compare` (staff only; the public `/plays/:code/compare` does not change):

1. **Lectura paralela** (*Side by side*): the comparison as it is today.
2. **Revisión de pares** (*Pair review*): the report below.

The tab is part of the URL, so a reload or a shared link opens the same tab.

## Revisión de pares

For one translation or version against its original:

- **Which translation:** a menu of the original's translations and versions the reader may
  open (`Alignment.paired?/1`). It opens on the page's own play when that is one, else on
  the first. Adaptations are not offered: they keep the proportion (step 1), and the tab
  says so when the family has nothing to review.
- **One row per speech**, in the original's order, as the proof of concept's report
  (`poc/align.exs` on branch `poc/translation-alignment`) lays them out: the row's number,
  act and scene, the original speech (its first line's `n`, speaker, opening words, the
  whole speech on hover), the kind of pairing, the translation speech likewise.
- **Kinds of pairing:** same speaker; split (a speaker repeated after a stage direction:
  two translation speeches with one original); other speaker (paired by position, the
  speakers differ); added (nothing in the original); cut (an original speech nothing points
  to). Each has its colour and a count at the top.
- **The length warning:** a same-speaker row whose two speeches differ sharply in length is
  marked doubtful. It is what the proof of concept missed on 0084's rows 89 and 91, where
  the French gives the messengers' lines to others: same speakers, the words a speech off.
- **"Only the doubtful rows"**: a switch that hides the plain same-speaker rows, keeping one
  row either side of each doubtful one.
- **A speaker links to its line on the translation's Elenco tab**, where its original is
  corrected. After a correction, reloading the review shows the new pairing.

## The comparison's HTML download goes

The "Export HTML" button on the admin comparison, its route
(`GET /admin/plays/compare/export/html`) and `Playcode.Export.CompareHtml` are removed: the
static site publishes every comparison as `compare.html`, which a reader can save. The play
page's own "Export HTML" (the play's download) stays.

## Builder's calls

- **The length warning's threshold:** set so that 0084's rows 89 and 91 are marked; report
  how many rows it marks across the dev corpus's translations, and keep the rule simple (a
  ratio of word counts above a floor of words, so two short lines never warn). **Set
  2026-11-11:** the longer speech over 3.5 times the shorter and over 15 words. Rows 89
  (5 words against 19) and 91 (18 against 3) are marked; 1,182 of the 102,351
  same-speaker rows of the 145 translations on dev (1.15%), in 100 plays, at most 130 in
  one. The first guess, 4 times and 20 words, missed both rows.
- **Where the rows come from:** `Alignment` already computes them for `align/2`; the review
  reads them through one public function. The proof of concept is the reference for the
  kinds, not code to copy.
- **The Elenco link** needs the content editor to open on a tab named in the URL and scroll
  to the entry; today the tab is chosen by a click only.
- **Size:** about 1,200 rows for 0038/0084, rendered once when the tab opens; no streaming
  unless it measures slow.
- **Removing the download:** its row in `authorization_test.exs` goes. Its test in
  `inline_markers_test.exs` goes too: the static site's comparison test covers the
  comparison's italics; check that and say so in the commit. `CLAUDE.md` (Static site
  export, the scroll-sync line), `docs/architecture.md`, `docs/static-site.md` and the
  *Downloads* cell of the character pairs row in `docs/stakeholder/ida-y-vuelta.html` stop
  naming it.
- **Access:** the review tab lives inside the admin comparison, so it needs no new
  permission and no new row in `authorization_test.exs`; it is added to
  `accessibility_test.exs`.

## Out of scope

Correcting from the review; speech corrections (step 4, parked); a download of the review;
the review on the public page or the static site.
