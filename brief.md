# Playcode brief, 2026-11-19 (main @ 66b003d)

Current focus: none.

## 18 of 72 questions open (docs/stakeholder/preguntas.html)

**Easiest**
- [q28](docs/stakeholder/preguntas.html#q28) Show original cast actors? One yes/no; the data is already stored.
- [q72](docs/stakeholder/preguntas.html#q72) Link a translation to its original's RoleCall chart? Yes/no.
- [q7](docs/stakeholder/preguntas.html#q7) Show The Rover's 40 hidden stage directions? Yes/no.
- [q13](docs/stakeholder/preguntas.html#q13) Whom do 11 Jodelle witnesses name instead? One name.
- [q34](docs/stakeholder/preguntas.html#q34) Are two epilogues part of the play? Two plays, one rule.

**Most important**
- [q66](docs/stakeholder/preguntas.html#q66) Confirm 45 prologues on the wrong side (33 plays): unblocks backlog C1 and the file corrections.
- [q69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays: unblocks the Numbering item and a Generate.
- [q53](docs/stakeholder/preguntas.html#q53) Which "version" plays are originals: gates the relations design (q53-56) and a migration.
- [q14](docs/stakeholder/preguntas.html#q14) Which of two Pyrame et Thisbé editions and three text-less plays to keep: affects what is published.
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: touches every play's numbering display.

## Round trip (docs/backlog.md; ida-y-vuelta.html cells not re-read today)
- Verse/prose threshold (q23 follow-up): our corpus copies still label 61 plays `verso`.
- Original cast (q28): stored and edited, printed nowhere.
- `sp@who` naming no cast role: 2,508 refs in 29 plays lose their character and statistics.
- `stage@n`: 376 dropped on import, mostly Hamlet and Timon.

## Top 3 features, clear to implement (checked in code)
1. **Log "mark complete/draft"** - on 2026-11-17 El Adonis went live with no record of who did it. `play_detail_live.ex:111-117` calls `Catalogue.update_play_from_form/2` (`catalogue.ex:329`), which never logs; other handlers do (`notes_component.ex`, `live_helpers.ex`). Fix: write an activity-log entry.
2. **Emphasised "aside" refused** - one file (EMOTHE0398) fails whole because `<<aside>>` holds the aside marker. `play_content/element.ex:293-306` (`validate_aside_markers`). Fix: ignore markers inside `<<…>>`.
3. **Shared line's lead drops note numbers** - a later part of a split verse starts up to ~28px short. `play_content/split_verses.ex:44-62` joins earlier parts' `content` as the lead. Fix: print the markers there as a plain `<sup>`, no id or link, in each renderer. Not checked against the renderers today.

Skipped, waits on a choice: Folio words still searched while the switch is off ("either/or"). Stale in backlog: none found.

## Speed win
`lib/playcode/statistics.ex:28-46` + `export/static_site/edition.ex:67`: `Edition.load` already holds `play.content_version`, yet `get_statistics` runs `content_version/1` again. Pass it in: one query less per play per Generate. The gain is tiny (about 1 ms a play, round trips only matter on Fly), so it is simplification more than speed; measure with Ecto telemetry query counts over a Generate. Risk: low, as long as the value is the one read before the content (it is: `edition.ex:50`). A larger candidate I did not look into: the backlog's import page writing each file twice is already listed.
