# Playcode daily brief, 2026-11-13 (main @ 47bf3d6)

Current focus: none.

## Open questions (links: docs/stakeholder/preguntas.html#qN)
**5 easiest**
- [q18](docs/stakeholder/preguntas.html#q18) Who edited El diablo blanco / Il diavolo bianco: Eva Soler Sasera or Victoria Soler Sánchez? One name.
- [q19](docs/stakeholder/preguntas.html#q19) La ocasión perdida editor: Tronch or Durá Celma? Same shape.
- [q20](docs/stakeholder/preguntas.html#q20) Did Elena Ramírez also edit Every Man In His Humor? Yes/no.
- [q39](docs/stakeholder/preguntas.html#q39) Hamlet v. 3315: "Oh! and" or "Oh!"? One reading, one editor.
- [q13](docs/stakeholder/preguntas.html#q13) Who replaces Jodelle on 11 witnesses? One fact, six plays.

**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays; backlog C1 waits on it.
- [q69](docs/stakeholder/preguntas.html#q69) Renumber 16 hand-numbered plays: the whole Numbering section waits.
- [q67](docs/stakeholder/preguntas.html#q67) Does a chorus/TODOS count as a speaker: fixes statistics for ~89 plays (Round trip item).
- [q14](docs/stakeholder/preguntas.html#q14) Nine plays with a web edition but no TEI: corpus completeness for publishing.
- [q57](docs/stakeholder/preguntas.html#q57) Source plays without text: unblocks the Relations section (q53-56 follow it).

## Round trip (backlog; ida-y-vuelta cells short of yes)
- Collective speakers count as one character in statistics (q67).
- Asides are marked less on the play page and site than in downloads (needs no answer).
- Verse/prose boundary (q23 follow-up): proposal applied, question still open.
- Original cast (`characters.actor`) printed nowhere (q28); new FileMaker slices (S8 genre) must go into the TEI.

## Top 3 features
1. **Package 4: "Download .zip" off the export page** - a 666 MB zip inside the page process looks dead for minutes; independent, ready now.
2. **Package 5: drop six unread statistics keys** - nothing reads them since `/api/v1` went; less cache and compute per play.
3. **Asides on the play page and site** - downloads already mark them; needs no answer.
Skipped: C1, numbering (project), relations (after parity), translation alignment (parked), PHP 7.2 deploy.

## Speed win
- `lib/playcode/export/static_site/search.ex:34-43` `normalise/1` runs five passes (NFC, downcase, ñ swap, NFD, `\p{Mn}` regex) on every line and note of every play, and `words/1` calls it each time.
- Change: when the text is pure ASCII (`for <<c <- text>>, c > 127` is empty) return `String.downcase(text)`; most English lines skip four passes.
- Gain: guess ~2-3x on `write_play` indexing for English plays, not measured; time `Search.write_play/2` over one English play with `:timer.tc` before/after.
- Risk: low; `search_normalisation.json` runs against both halves and must stay green. Differs from the previous brief (edition.ex statistics).
