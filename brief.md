# Playcode daily brief, 2026-11-18 (66b003d)

Current focus: none.

## Questions: 18 of 72 questions open
**5 easiest** ([preguntas](docs/stakeholder/preguntas.html))
- [q7](docs/stakeholder/preguntas.html#q7) The Rover's 40 stage directions: show or hide? A yes/no.
- [q13](docs/stakeholder/preguntas.html#q13) Who replaces Jodelle on 11 witnesses? One fact.
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast's actors? Yes/no.
- [q34](docs/stakeholder/preguntas.html#q34) Are the two epilogues part of the play? Yes/no, two plays.
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: one word to choose.

**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays wait; the backlog's C1 item is blocked on it.
- [q69](docs/stakeholder/preguntas.html#q69) Re-count 16 hand-numbered plays: unblocks the Numbering section, then Generate.
- [q53](docs/stakeholder/preguntas.html#q53) Which "version" plays are originals: gates the families migration (Relations).
- [q54](docs/stakeholder/preguntas.html#q54) English names of the relation kinds: gates the relations design with q55, q56.
- [q14](docs/stakeholder/preguntas.html#q14) Which editions/plays with no text to keep: corpus-wide, affects what is published.

## Round trip
- Verse/prose threshold (q23 follow-up): 61 plays are "mixed" in dev, but the corpus copies still say `verso`.
- Original cast (`characters.actor`) is written back to TEI but printed nowhere (q28).
- Hamlet v. 2632 exports as three stages where the source has one (waits on q37).
- `sp@who` naming no cast role: 2,508 references in 29 plays lose their character; `stage@n` (376) is dropped.

## Top 3 features (verified in code)
1. **Log "marked complete/draft" in the activity log.** On 2026-11-17 El Adonis went live with nobody recorded. `play_detail_live.ex:111-131` calls `Catalogue.update_play_from_form/2` (`catalogue.ex:329`) and never `LiveHelpers.log_activity` (used at `:100` for delete). Fix: add a `log_activity` call on success.
2. **An emphasised "aside" in a stage direction refuses the whole file.** FileMaker's EMOTHE0398 fails: `<<aside>>` contains the substring `<aside>`, so `InlineMarkup.holds?/2` (`inline_markup.ex:421-422`) fires the check in `element.ex:292-306`. Fix: the marker test must ignore text inside `<<…>>`.
3. **Admin import page writes each file twice.** `import_live.ex:93` calls `preview_import/1`, whose `numbering/1` (`tei_import.ex:178-190`) writes the file and rolls back: 4.2 s against 4.1 s on one fixture. Fix: show the numbering rule after the import, or compute it from the parsed file.

Skipped: "Folio words searched while the switch is off" (a choice between two options); "cast list note loses tabs" (no fix stated).
Stale in backlog: none found among the items read.

## Speed win
- `lib/playcode/catalogue.ex:550` (`with_all`) preloads `:statistic` (a full JSON blob), and `Edition.load` (`edition.ex:50,67`) then calls `Statistics.get_statistics/2`, which reads the row again (`statistics.ex:31`).
- Change: drop `:statistic` from the static site's play load (or have `get_statistics` take the preloaded row).
- Gain: one query and one JSON decode less per play, about 370 plays; small (seconds), so measure with `Repo` query counts on `Edition.load/1`.
- Risk: low, but check that no page reads `play.statistic` first. The previous brief's pick (`bibliography.ex` batching) is a different place.
