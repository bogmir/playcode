# Playcode daily brief, 2026-11-12 (main @ 858233d)

Current focus: none.

## Open questions (docs/stakeholder/preguntas.html)

**5 easiest**
- [q19](docs/stakeholder/preguntas.html#q19) Digital editor of *La ocasión perdida*: pick file's or FileMaker's name, one fact.
- [q18](docs/stakeholder/preguntas.html#q18) Editor of the two *White Devil* translations: Eva or Victoria Soler, one fact.
- [q20](docs/stakeholder/preguntas.html#q20) Elena Ramírez Sáenz on *Every Man In His Humor*: yes/no.
- [q69](docs/stakeholder/preguntas.html#q69) Recount sixteen hand-numbered plays: yes/no.
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast's actors: yes/no.

**5 most important**
- [q67](docs/stakeholder/preguntas.html#q67) Does a chorus/"TODOS" count as a speaker: ~119 roles in 89 plays skew the statistics.
- [q23](docs/stakeholder/preguntas.html#q23) Label vs text for verse/prose: 91 plays, drives `auto_form` and the statistics.
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: unblocks corpus check C1 (45 texts, 33 plays).
- [q57](docs/stakeholder/preguntas.html#q57) Plays with no text: gates the relations phase and every page assuming a text.
- [q69](docs/stakeholder/preguntas.html#q69) Numbering: moves the 16 hand-numbered plays out of "Conteo manual" (also easy).

## Round trip (docs/backlog.md, ida-y-vuelta.html)
- Asides: the play page and site mark them less than the downloads (no mark in prose).
- Original cast, revision history, provenance: in TEI both ways, not printed in HTML/PDF/EPUB, page or site (q28 for the cast).
- Collective speakers counted as one character in statistics (waits on q67).
- Genre (S8, 82 plays in FileMaker), places named in the text and per-scene settings: not imported yet.

## Top 3 features to build
1. **Asides on the play page and site**: the only Round trip item not waiting on the project; the downloads already do it.
2. **Review character in text UI**: 2,508 `sp@who` references in 29 plays lose their character, and so the statistics; researchers can fix them without a re-import.
3. **FileMaker S8 genre import** (TEI `textClass` from the start): tables arrived 2026-10-19, nothing built, and FileMaker parity precedes the relations phase.
