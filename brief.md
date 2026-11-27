# Daily brief 2026-11-27 (c7b7397)
Current focus: none.

## Questions: 19 of 74 questions open
Open: 7, 13, 14, 28, 34, 37, 48, 50, 53, 54, 55, 56, 66, 68, 69, 70, 71, 72, 73.
**5 easiest**
- [q28](docs/stakeholder/preguntas.html#q28) Original cast shown? - one yes/no.
- [q54](docs/stakeholder/preguntas.html#q54) English names of the relation kinds - a list to translate.
- [q70](docs/stakeholder/preguntas.html#q70) Genders a character can have - three options offered.
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number - one short choice.
- [q66](docs/stakeholder/preguntas.html#q66) Confirm the 45 prologues listed - a review of a list.
**5 most important**
- [q66](docs/stakeholder/preguntas.html#q66) Blocks backlog item C1 (prologues on the wrong side).
- [q69](docs/stakeholder/preguntas.html#q69) Blocks the 16 hand-numbered plays (Numbering section).
- [q53](docs/stakeholder/preguntas.html#q53) Families to correct (Doctor Faustus, the Rover); relations phase.
- [q54](docs/stakeholder/preguntas.html#q54) Relations phase needs the kind names (with q55, q56).
- [q34](docs/stakeholder/preguntas.html#q34) Epilogues of The Rover and El hombre a la moda; paratext/body rule.

## Round trip (only backlog.md read; I did not read ida-y-vuelta.html cell by cell)
- Where verse and prose ends: q23 follow-up still open; proposal applied since 2026-11-09 (`Play.auto_form/2`).
- Original cast (`characters.actor`) is written to TEI but printed nowhere: q28.

## Top 3 features (verified in code)
1. **Word importer reads document.xml with Regex** - `<w:t>` split by `<w:tab/>`/`<w:br/>` loses text, and numeric entities are not decoded. `lib/playcode/import/word_parser.ex:45-48` (+ `unescape_xml` :17). Fix: parse with Saxy.
2. **Import page writes each file twice** - the preview's numbering rule writes the file in a rolled-back transaction, about as costly as the import (4.2 s vs 4.1 s). `lib/playcode_web/live/admin/import_live.ex:93` -> `tei_import.ex:181-183`. Fix: `numbering: false` or compute from the parsed file. The backlog leaves the form of the fix open.
3. **A shared line's lead carries no note numbers** - a later part can start up to ~28px short. `lib/playcode/play_content/split_verses.ex:63` (lead built from content only). Fix: print the markers as a plain `<sup>`, no id or link, in each renderer.
Skipped: Folio search (a choice), dead validation warnings (`import_live.ex:172`, a choice), the rest wait on questions.
Stale in backlog: none found.

## One speed win
- `lib/playcode/statistics.ex:121-138`: counts of the elements run as about six separate `Enum.count`/`filter`/`map` passes over the same list.
- Change: one `Enum.reduce` collecting every counter.
- Gain: small, maybe 5-15% of the pure-Elixir compute per play, and the DB loads still dominate. Measure with `:timer.tc` around `Statistics.compute` on Hamlet.
- Risk: low; `statistics_test.exs` covers the figures. I checked `docs/` for it and found it neither listed nor done. Last brief's pick was `Catalogue.with_all`, so this is a different place.
- Not picked: `Records.entries` needs every preload it makes (characters, witnesses, performances' cast).
