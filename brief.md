# Playcode daily brief, 2026-11-13 (main @ 5843a4a)

Focus: none. 53 questions open.

## Easiest questions (preguntas.html)
- [q7](docs/stakeholder/preguntas.html#q7) The Rover's 40 hidden stage directions: yes/no, one play.
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast's actors: yes/no.
- [q13](docs/stakeholder/preguntas.html#q13) Jodelle on 11 witnesses: one fact, a slip of the form.
- [q54](docs/stakeholder/preguntas.html#q54) English names for relation kinds: a list to correct.
- [q66](docs/stakeholder/preguntas.html#q66) Confirm the list of 45 prologues on the wrong side: confirm or strike.

## Most important questions
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number: every play's citations.
- [q69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays: unblocks the Numbering backlog.
- [q66](docs/stakeholder/preguntas.html#q66) Prologues: unblocks corpus check C1, 33 plays.
- [q67](docs/stakeholder/preguntas.html#q67) Chorus/TODOS in statistics: ~119 roles in 89 plays, a Round trip item.
- [q15](docs/stakeholder/preguntas.html#q15) Label for 11 adaptations on the public site: three backlog items hang on it (with q53-57).

## Round trip (short of "yes")
- Collective speakers (CORO, TODOS) count as one character in statistics; waits on q67.
- Asides: play page and site mark less than the downloads (ida-y-vuelta note 37); needs no answer.
- Verse/prose form boundary (q23 follow-up): proposal applied, 61 plays labelled `verso` in the corpus copies.
- Original cast actors are stored and exported but printed nowhere; waits on q28.

## Top 3 features
1. **Download .zip off the export page** (package 4): 666 MB zipped in the page process, no feedback, repeats on a second click.
2. **Statistics no page reads** (package 5): drop six dead cached keys after `/api/v1` went; smaller code, cheaper cache.
3. **Asides on the play page and site**: the downloads already mark them; no answer needed, closes a Round trip gap.

## Speed win
- `lib/playcode/export/static_site.ex:314` and `:474`: `outdated/1` loads `list_plays(complete: true)` and `relatives/3` loads `list_plays()` again; `published_plays/1` (`:484`) a third time. Pass the plays already in hand (or load once per Generate) instead of re-querying the whole catalogue.
- Gain: guess, two to three catalogue queries fewer per Generate (a few hundred ms to a second on 1 GB, not the hours); measure with `:timer.tc` around `Catalogue.list_plays/1` in one `mix playcode.export.site` run.
- Risk: low; a stale list within one build if a play changes mid-run, which `SiteBuilder` already serialises. Differs from the previous brief (search.ex normalise).
