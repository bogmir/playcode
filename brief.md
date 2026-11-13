# Playcode brief, 2026-11-13 (47bf3d6)

Focus: none. Open questions: 63 of 69 (answers 1-6, 8-12 etc. mostly still open; list below is from the page's `.q` blocks without `.answered`).

## Easiest 5 (one fact or a clear choice)
- [q19](docs/stakeholder/preguntas.html#q19) Who prepared *La ocasión perdida*: Tronch or Durá; one name.
- [q20](docs/stakeholder/preguntas.html#q20) Did Ramírez Sáenz co-prepare *Every Man In His Humor*; yes/no.
- [q18](docs/stakeholder/preguntas.html#q18) Eva Soler Sasera or Victoria Soler Sánchez for the two *White Devil* translations; one name.
- [q13](docs/stakeholder/preguntas.html#q13) Whom the 11 "Jodelle" witnesses should name; a slip of the form, one correction.
- [q54](docs/stakeholder/preguntas.html#q54) English names for the relation kinds; the team only corrects our list.

## Most important 5 (unblock the most)
- [q67](docs/stakeholder/preguntas.html#q67) Does a chorus/"TODOS" count as a character: ~119 roles in 89 plays skew every statistics page (backlog, Round trip).
- [q66](docs/stakeholder/preguntas.html#q66) Confirm the 45 prologues on the wrong side (33 plays): unblocks backlog C1.
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number; every play now carries the numbering configuration, blocks its display.
- [q69](docs/stakeholder/preguntas.html#q69) Recount sixteen hand-numbered plays: waiting item under Numbering.
- [q57](docs/stakeholder/preguntas.html#q57) What to hold for plays without text: gates the Relations section (with q54-56).

## Round trip (cells short of "yes")
- Collective speakers (CORO, TODOS) count as one character in statistics: waits on q67.
- Asides: play page and site mark fewer than the downloads (the site's margin names only a verse start; prose none).
- Verse/prose label vs text (q23): 61 plays computed "mixed"; corpus copies still say `verso`.
- Original cast (q28) and S8 genre: stored/edited but printed nowhere, genre not yet in TEI.

## Top 3 to build
1. **Package 4: "Download .zip" off the page's process** (666 MB zipped with no feedback, the page looks dead for minutes); first open item under the owner's decided heading, independent of 1-3.
2. **Package 5: drop six statistics nothing reads** (`total_verses`, `character_appearances`...): smaller cache rows and less compute per play; also speeds Generate.
3. **Asides on the play page and site**: the downloads already mark them; the other outputs lag, needs no answer.
Skipped: C1 and numbering (project), relations (after parity), translation alignment (parked), PHP 7.2 deploy.

## Speed win
- `lib/playcode/export/static_site/edition.ex:65` calls `Statistics.get_statistics(id)`, though `Catalogue.get_play_with_all!` (line 50) already preloads `:statistic` and the play's `content_version` (`catalogue.ex:506`).
- Change: use `play.statistic` when its `version`/`content_version` match, and fall back to `get_statistics` only if stale; saves 2 queries per play (400 plays: ~800 round trips, a few seconds on the shared CPU; measure with `Ecto` query count over one Generate).
- Risk: low; must keep the stale-row rule (compare against `play.content_version` read first), covered by `statistics_test.exs`.
