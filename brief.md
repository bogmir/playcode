# Playcode daily brief, 2026-11-20 (commit 66b003d)

Current focus: none.

## 18 of 72 questions open ([preguntas](docs/stakeholder/preguntas.html))
**Easiest**
- [q54](docs/stakeholder/preguntas.html#q54) English names of the relation kinds: one wording list.
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: one word.
- [q72](docs/stakeholder/preguntas.html#q72) Translation links to original's RoleCall chart: yes/no.
- [q70](docs/stakeholder/preguntas.html#q70) Genders a character may have: a short list.
- [q71](docs/stakeholder/preguntas.html#q71) Where readers see a character's gender: pick a place.

**Most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: unblocks backlog C1 (listed for the team to confirm).
- [q69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays: the numbering item waits on a yes; plays carry wrong numbers today.
- [q53](docs/stakeholder/preguntas.html#q53) Which "version" plays are originals: gates the families migration and the whole relations design.
- [q55](docs/stakeholder/preguntas.html#q55) Transforms or imitates (with q54, q56): the relations model waits on 53-57.
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast's actors: `characters.actor` is stored and printed nowhere.

## Round trip (backlog)
- Verse/prose limit (q23 follow-up): 61 plays labelled "mixed" by our proposal; corpus copies still say `verso`.
- Original cast (q28): `characters.actor` written to TEI, printed nowhere.
- ida-y-vuelta cells short of "yes": the same two, plus the hand-set curated columns kept out of the file by design.

## Top 3 features (clear to implement, checked in code)
1. **Log "mark complete/draft"** - `set_status` changes what the next Generate publishes with no trace (El Adonis, 2026-11-17). `play_detail_live.ex:116` calls `Catalogue.update_play_from_form/2` (`catalogue.ex:329`) without logging; fix: `LiveHelpers.log_activity`, as the delete handler at `:100`.
2. **Emphasised aside in a stage direction is refused** - one FileMaker play (*The Roman actor*, EMOTHE0398) fails to import whole. `element.ex:297`/`:305`: `holds?(content, :aside)` sees `<aside>` inside `<<aside>>` and errors. Fix: the marker test skips `<<…>>`.
3. **Shared line's lead has no note numbers** - a later verse part starts up to ~28px short after a part with a note. `play_content/split_verses.ex:44` `leads/1` joins plain content. Fix: print the markers as a plain `<sup>` in the lead, in each renderer.

Stale in backlog: none found.

## Speed win
`lib/playcode/catalogue.ex:551` `with_all/2` preloads `:statistic` (a jsonb row) for every `Edition.load`, which then reads it again (`statistics.ex:28`, `edition.ex:67`). Drop it for the export through an opt (`preload_statistic: false`). Saves one query and one jsonb decode per play on Generate; measure with Ecto query counts. Risk: the play page's panel (`statistics_panel.ex:20`) still needs it, so keep it the default.
