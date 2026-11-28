# Playcode brief 2026-11-28 (main @ 0599f9e)

## 19 of 74 questions open ([preguntas](docs/stakeholder/preguntas.html))
**5 easiest** (one fact or a pick from a list)
- [q70](docs/stakeholder/preguntas.html#q70) Genders a character can have: three words (woman, man, X) to approve.
- [q71](docs/stakeholder/preguntas.html#q71) Where readers see gender: tick boxes.
- [q72](docs/stakeholder/preguntas.html#q72) Link a translation to its original's RoleCall chart: yes or no.
- [q68](docs/stakeholder/preguntas.html#q68) The word before a cited number: one word.
- [q7](docs/stakeholder/preguntas.html#q7) Show The Rover's 40 hidden stage directions: yes or no.

**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) 45 prologues on the wrong side in 33 plays: blocks backlog item C1.
- [q69](docs/stakeholder/preguntas.html#q69) Renumber 16 hand-numbered plays: whole Numbering section waits.
- [q53](docs/stakeholder/preguntas.html#q53) Which "version" plays are originals: blocks the Relations model, with q54-56.
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast: decides the `characters.actor` round-trip gap.
- [q50](docs/stakeholder/preguntas.html#q50) Edition layout of two lines and one stage direction: blocks the corpus-copy fix.

## Round trip
- Verse/prose labels: 61 plays still carry `verso` in the corpus copies; waits on q23 (`Play.auto_form/2`).
- Original cast (`characters.actor`) edited and exported but printed nowhere: q28.
- Hamlet v. 2632 exports as three stage directions, the source has one; waits on q37.
- `stage@n` (376) dropped on import; `sp@who` naming no cast role (2,508 in 29 plays) loses its character.

## Top 3 features (verified in code)
1. **Log "mark complete/draft"** - `set_status` leaves no activity row, so nobody can say who published *El Adonis* on 2026-11-17. `play_detail_live.ex:63-68` calls `Catalogue.update_play_from_form/2` (`catalogue.ex:328`), which logs nothing. Fix: `LiveHelpers.log_activity` (used in `play_performances_live.ex`) after `{:ok, _}`.
2. **Word importer reads XML with regexes** - `<w:t>` text split by `<w:tab/>` or `<w:br/>` is lost, and only five entities decode. `word_parser.ex:56-59`, `unescape_xml` at :28. Fix: parse with Saxy as `TeiParser` does.
3. **Word import writes no activity log** - it replaces a play's whole text with no row, unlike the TEI import. `WordParser.import_content/2` has no `ActivityLog` call (grep empty). Fix: log it as the TEI import does.

Candidates skipped: "aside in a stage" refusal (`element.ex:314-327`) is real, but the fix is not stated beyond "the test should not see a marker inside `<<…>>`"; the first Next items wait on UV or on a choice. Stale in backlog: none found.

## Speed win
- `lib/playcode/catalogue.ex:563` (`preload_record/1`): load only visible characters (`where: not c.is_hidden`) and drop the `not c.is_hidden` filter at `static_site/records.ex:111`.
- Faster: the catalogue rebuild stops loading hidden characters for 400+ plays. The gain is small (one query, fewer rows), so measure rows loaded and `Records.entries/2` time on dev.
- Risk: low, but other `preload_record` callers must not need hidden characters. Searched: statistics (`statistics.ex:31-70`) already cached by `content_version`; the catalogue's repeated reads (`static_site.ex:166,517`) were measured and rejected (`docs/static-site-improvements.md:197`). No bigger win found within the read budget.
