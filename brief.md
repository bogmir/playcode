# Playcode brief, 2026-11-15 (8adc0d1)

## Questions: 19 of 72 questions open
Easiest (a clear choice or one fact):
- [q7](docs/stakeholder/preguntas.html#q7) The Rover's 40 hidden stage directions: show or not, yes/no.
- [q13](docs/stakeholder/preguntas.html#q13) Jodelle attribution: one name for 11 witnesses.
- [q54](docs/stakeholder/preguntas.html#q54) English names for the relation kinds: a translation list to confirm.
- [q72](docs/stakeholder/preguntas.html#q72) RoleCall link for translations: yes/no.
- [q70](docs/stakeholder/preguntas.html#q70) Character genders: pick the vocabulary (women, men, X).

Most important (unblock the most):
- [q66](docs/stakeholder/preguntas.html#q66) 45 prologues on the wrong side in 33 plays: the whole C1 section waits on it.
- [q69](docs/stakeholder/preguntas.html#q69) Renumber 16 hand-numbered plays: the Numbering section waits (also q68).
- [q57](docs/stakeholder/preguntas.html#q57) Plays without a text: gates the Relations work (with q55, q56).
- [q14](docs/stakeholder/preguntas.html#q14) Nine plays with a web edition but no TEI: corpus completeness.
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast: a Round trip gap, published pages.

## Round trip (docs/backlog.md, Round trip)
- Asides: play page and site mark them less than the downloads.
- Verse/prose/mixed: `auto_form` rule applied since 11-09, follow-up of q23 still open.
- Original cast (`characters.actor`) is written to TEI but printed nowhere (q28).
- ida-y-vuelta: cells short of "yes" follow the same three items.

## Top 3 features (current focus: none)
1. Front matter titles through `NoteMarkup.inline/3`: `<<…>>` shows in the header's italics today.
2. Hidden Folio words still searched and their notes still listed: a hit lands on text the reader cannot see.
3. Admin import preview writes the file twice (the preview costs as much as the import).
(Skipped: site deploy waits on UV's PHP patch; numbering, prologues, relations wait on the project.)

## Speed win
- `lib/playcode/export/static_site/search.ex:131-140`: per line and word, `word in entry.stage_only` scans a list.
- Change: build `stage_only` as a MapSet once per entry (or per play) and test with `MapSet.member?`.
- Gain: small to moderate per line, millions of tests over a 394-play index on the shared CPU; measure with `:timer.tc` around `write_play/2`. I did not confirm `stage_only` is a list: check its type first.
- Risk: low. Differs from the previous brief (compare page's original Edition load).
