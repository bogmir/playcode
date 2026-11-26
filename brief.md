# Playcode daily brief 2026-11-26 (main @ 98f5ae1)
Current focus: none.

## 19 of 74 questions open ([preguntas](docs/stakeholder/preguntas.html))
**5 easiest**
- [q72](docs/stakeholder/preguntas.html#q72) RoleCall link for translations: yes/no.
- [q7](docs/stakeholder/preguntas.html#q7) The Rover's 40 stage directions: show or hide, one choice.
- [q28](docs/stakeholder/preguntas.html#q28) Show original-cast actors: yes/no.
- [q71](docs/stakeholder/preguntas.html#q71) Where readers see gender: tick boxes.
- [q70](docs/stakeholder/preguntas.html#q70) Character genders: pick a word list (women/men/X proposed).

**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) 45 prologues on the wrong side: blocks backlog C1 and fixing the files.
- [q53](docs/stakeholder/preguntas.html#q53) "Version" plays: blocks family corrections, the relations design (cited twice).
- [q69](docs/stakeholder/preguntas.html#q69) 16 hand-numbered plays: one yes lets Generate fix their numbers.
- [q14](docs/stakeholder/preguntas.html#q14) Pyrame et Thisbé editions and three textless plays: decides what the corpus keeps.
- [q54](docs/stakeholder/preguntas.html#q54) English names of relation kinds: with q55/q56, last blockers of the relations model.

## Round trip
- Original cast (`characters.actor`) written to TEI but printed nowhere: q28.
- Verse/prose threshold (61 plays "mixed" in dev, corpus copies still say `verso`): q23 follow-up.
- Hamlet v. 2632 stays three stage directions on export (source has one): waits q37.
- `stage@n` (376, Hamlet/Timon) dropped on import.

## TOP 3 FEATURES (verified in code)
1. **Log marking complete/draft**: nobody can tell who published EMOTHE0439. `lib/playcode_web/live/admin/play_detail_live.ex:111-130` calls `update_play_from_form/2` with no `LiveHelpers.log_activity` (delete at :100 has one). Fix: log it.
2. **Word importer reads `document.xml` by regex**: `<w:t>` text split by `<w:tab/>`/`<w:br/>` is lost, five entities only. `lib/playcode/import/word_parser.ex:17,45-48`. Fix: parse with Saxy.
3. **Aside inside `<<…>>` refused**: *The Roman actor* (EMOTHE0398) was imported with an italic dropped. Marker test in `lib/playcode/play_content/element.ex` (Element.changeset) should ignore a marker inside `<<…>>`. Fix stated in backlog; not re-read at line level (budget), check first.

Not listed (wait on a choice): Folio search/notes, import-page warnings (fill or drop column; `import_live.ex:172` still `[]`), preview written twice.
**Stale in backlog**: none found among those checked.

## ONE SPEED WIN
- `lib/playcode/catalogue.ex:540-552` (`with_all/2`, used by `Edition.load`, `edition.ex:50`): preloads `play_places` with every place's `names` (3 queries per play), yet static_site/ reads `play_places` only in `records.ex:52`, which has its own `preload_record`.
- Change: give `Edition.load` a lighter preload without `play_places` (an opt, or a `with_all` that skips it).
- Gain: 3 queries and the place-name rows per play, ~370 plays; small per play (ms) but pure waste on the 1 GB machine. Measure: count queries per `Edition.load` with telemetry or a Repo log on one play.
- Risk: low if no page code reads `play_places` outside static_site/ (Components shared with the admin/TEI? unverified; grep `lib/` first). Differs from yesterday's `refresh_assets` pick.
