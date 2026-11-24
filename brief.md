# Playcode brief 2026-11-24 (c4f77bd)

Focus: none.

## 19 of 73 questions open
**5 easiest** ([preguntas](docs/stakeholder/preguntas.html))
- [q70](docs/stakeholder/preguntas.html#q70) Character genders: pick the words (woman/man/X).
- [q72](docs/stakeholder/preguntas.html#q72) Translation links to original's RoleCall chart: yes/no.
- [q54](docs/stakeholder/preguntas.html#q54) English names for relation kinds: a table to correct.
- [q71](docs/stakeholder/preguntas.html#q71) Where readers see gender: tick boxes.
- [q7](docs/stakeholder/preguntas.html#q7) Show The Rover's 40 hidden stage directions: yes/no.

**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays; blocks backlog C1.
- [q37](docs/stakeholder/preguntas.html#q37) Hamlet `<app>` form: blocks Q4 Additions and the 13 crossing Folio passages.
- [q68](docs/stakeholder/preguntas.html#q68) Citation word before a number: every play's numbering output.
- [q69](docs/stakeholder/preguntas.html#q69) Renumber 16 hand-numbered plays: corpus-wide numbering.
- [q14](docs/stakeholder/preguntas.html#q14) Pyrame et Thisbé and 3 plays with no text: corpus completeness.

## Round trip (cells short of "yes")
- Verse/prose boundary (q23 follow-up): our 61 mixed-form corpus copies are still labelled `verso`.
- Original cast (`characters.actor`) is printed nowhere; waits on q28.
- Also open in backlog: `stage@n` (376) dropped; `sp@who` naming no role (2,508 in 29 plays).
- Hamlet v. 2632 exports as three stages, where the source has one.

## Top 3 features (verified in code)
1. **Import page's validation warnings are never filled**: the results column and its strings are dead. `lib/playcode_web/live/admin/import_live.ex:172` has `validation_warnings = []`. Fix: fill from `TeiValidator`, or drop the column and the tuple's fifth element.
2. **Word importer reads `document.xml` with regexes**: `<w:t>` text split by `<w:tab/>` or `<w:br/>` is missed, and numeric entities are not decoded. `lib/playcode/import/word_parser.ex:45-48` (`Regex.scan`), `:17` (`unescape_xml`). Fix: parse with Saxy.
3. **Admin import writes each file twice**: preview rolls back a full write for the numbering rule (4.2 s against 4.1 s on one fixture). `lib/playcode_web/live/admin/import_live.ex:93` calls `preview_import(path)`; `lib/playcode/import/tei_import.ex:140` has the `numbering: false` option. Fix: show the rule after the import, or compute it from the parsed file.

Not checked (budget): "Folio words still searched" (Next); `search.ex` shows no Folio filter, so it likely stands but is unconfirmed. It needs a choice (open the switch, or drop the words), so it is not "clear".

Stale in backlog: none found.

## Speed win
No new candidate found in the budget. `Edition.load` has no Repo calls and `build_plays` already bounds concurrency and loads an original once per family. The one live idea is item 3 above (import-page double write, roughly 2x on every admin import), already listed in the backlog, so not proposed again.
