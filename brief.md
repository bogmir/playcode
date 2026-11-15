# Playcode brief, 2026-11-15 (commit 8adc0d1)

## 19 of 72 questions open ([preguntas](docs/stakeholder/preguntas.html))
**Easiest**
- [q72](docs/stakeholder/preguntas.html#q72) RoleCall link for translations: yes/no, one sentence
- [q70](docs/stakeholder/preguntas.html#q70) Character genders: a short list to pick or amend
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast: yes/no
- [q13](docs/stakeholder/preguntas.html#q13) Jodelle's 11 witnesses: one fact (who really)
- [q7](docs/stakeholder/preguntas.html#q7) The Rover's 40 hidden stage directions: show or hide
**Most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays wait on it (backlog C1)
- [q69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays: corpus-wide numbering
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: shapes every citation on the site
- [q14](docs/stakeholder/preguntas.html#q14) Nine web editions with no TEI file: missing plays on the site
- [q57](docs/stakeholder/preguntas.html#q57) Plays without a text (with q53-56: the relations project)

## Round trip
- Asides: play page and site mark them less than the downloads (note 37)
- Verse/prose label vs text (q23 follow-up): our rule applied, project not yet confirmed
- Original cast (`characters.actor`) printed nowhere, waits on q28
- Not re-read this run: the cell-by-cell table in ida-y-vuelta.html

## Top 3 features (clear to implement)
1. **EMOTHE0443's closing `<set>` note** (Next): the last front-matter note lost on import; fix: read it as a paratext's note is read.
2. **Front matter header texts through `escape/1`** (Next): `<<…>>` would show for `<emph>` in titles/editors; fix: print through `NoteMarkup.inline/3`, then give the inline-markers test italics.
3. **Space added after a line's opening `<stage>`** (Next; the cast-list tabs part is vaguer): `</stage>El Sol` gains a space; fix: stop adding it.
Skipped: the UV deploy (waits on UV), Folio words in search (choice between two options).

## Speed win
- `lib/playcode/statistics.ex:69-95` (`compute/1`): about eight separate passes over `all_elements` (counts by type, `stage_count`, `asides_started`, aside verses, split verses), plus `Metrics.words` per spoken item.
- Change: one `Enum.reduce` over the elements into a counter map, or at least one parse of each element's inline content for stage and aside counts.
- Gain: statistics per play, so small per play but paid on every content change of every play in a Generate on the shared CPU; measure with `:timer.tc(&Statistics.compute/1)` on Hamlet. I read only this file, not `Metrics`, so the real size is unknown.
- Risk: low, `statistics` tests pin the numbers. Differs from the previous brief (search.ex `stage_only`).
