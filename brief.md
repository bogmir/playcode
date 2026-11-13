# Playcode brief 2026-11-13 (main @ 8adc0d1)
Focus: none.

## Open questions ([preguntas.html](docs/stakeholder/preguntas.html))
**Easiest**
- [q7](docs/stakeholder/preguntas.html#q7) Rover's 40 stage directions: show or hide, one yes/no
- [q28](docs/stakeholder/preguntas.html#q28) Show original cast actors: yes/no
- [q72](docs/stakeholder/preguntas.html#q72) Translation links to original's RoleCall chart: yes/no
- [q34](docs/stakeholder/preguntas.html#q34) Two epilogues as part of the play: yes/no on two plays
- [q54](docs/stakeholder/preguntas.html#q54) English names of relation kinds: correct our list

**Most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: confirm 45 texts in 33 plays; unblocks backlog C1
- [q69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays: corpus numbering, backlog "Numbering"
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: touches every play's citations
- [q57](docs/stakeholder/preguntas.html#q57) Plays without a text: gates the relations phase (q53-56 sit with it)
- [q14](docs/stakeholder/preguntas.html#q14) Nine web editions with no TEI file: gaps in what gets published

## Round trip
- Asides: play page and site mark them less than the downloads (nothing in prose on the site).
- Verse/prose limit (q23 follow-up): the 1/10-9/10 "mixed" rule is ours until answered.
- Original cast (q28): stored and exported, printed nowhere.
- ida-y-vuelta cells short of "yes" were not re-audited today; the three above are the open backlog bullets.

## Top 3 features
1. EMOTHE0443 closing `<set>` note dropped: the last lost front-matter note, round trip stays incomplete.
2. Folio words searched/noted while the switch is off: readers hit lines they cannot see.
3. Admin import page writes each file twice: preview costs as much as the import (4.2 s vs 4.1 s); fix is `numbering: false` or reuse.
(Skipped: site deploy waits on UV; numbering, prologues, relations wait on the project.)

## Speed win
- `lib/playcode/export/static_site/edition.ex:50,65` with `statistics.ex:28-46`: `Catalogue.get_play_with_all!` already preloads `:statistic` and holds `play.content_version`, yet `get_statistics` re-reads both (2 queries per play).
- Change: give `get_statistics` the loaded play (or its statistic and version) and drop the two lookups.
- Gain: 2 of roughly 15 queries per play, hundreds of plays per Generate; small (seconds), measure with `:timer.tc` over `Edition.load/1` or Ecto query counts in one run.
- Risk: low; the version is read in the same load, so staleness behaviour is unchanged. Differs from the previous brief (catalogue list re-queries).
