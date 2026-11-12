# Playcode daily brief, 2026-11-12 (main @ 858233d)

Current focus: none.

## Open questions (`docs/stakeholder/preguntas.html`)
**5 easiest**
- [q7](docs/stakeholder/preguntas.html#q7) Rover's 40 hidden stage directions: yes/no, show them?
- [q39](docs/stakeholder/preguntas.html#q39) Hamlet v. 3315 "Oh! and": one choice of reading
- [q37](docs/stakeholder/preguntas.html#q37) Spanish Tragedy Additions marks: confirm the "Q4" reading
- [q19](docs/stakeholder/preguntas.html#q19) Who edited *La ocasión perdida*: file or FileMaker, one name
- [q20](docs/stakeholder/preguntas.html#q20) Elena Ramírez Sáenz on Every Man In His Humor: yes/no

**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays; unblocks backlog C1 and a re-import
- [q69](docs/stakeholder/preguntas.html#q69) Renumber 16 hand-numbered plays: corpus-wide numbering, then Generate
- [q53](docs/stakeholder/preguntas.html#q53)-[q57](docs/stakeholder/preguntas.html#q57) Relations between plays (53 version vs original, 54 English names, 55-56 kinds, 57 plays with no text): the whole "Relations" phase waits
- [q67](docs/stakeholder/preguntas.html#q67) Chorus/TODOS in statistics: ~119 roles in 89 plays count as characters
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast to readers: a round-trip gap in 3 outputs

## Round trip (`ida-y-vuelta.html`, cells short of "yes")
- Original cast, revision history, source of the digital text: not on the play page, site or downloads (q28 for the cast).
- Asides: the play page and site mark them less than the downloads.
- Collective speakers count as one character in statistics (q67).
- `sp@who` naming no cast role: 2,508 refs in 29 plays lose their character; stage `@n` (376) dropped.

## Top 3 to build
1. **"Review character in text" page**: fixes the 2,508 broken `sp@who` links, which restores those plays' statistics; needs no answer.
2. **Folio words leak while the switch is off**: the site's search and endnotes still show hidden Hamlet passages, a reader-visible bug.
3. **Asides on the play page and static site**: the downloads already mark them, and the other outputs lag.

Skipped, waiting on the project or on UV: C1, numbering, relations, Giovanni (q50), site deploy (PHP 7.2).
