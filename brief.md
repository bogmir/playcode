# Playcode daily brief, 2026-11-21 (main @ 3be59b2)

Current focus: none. No earlier brief on the branch, so the speed win has nothing to differ from.

## Questions: 18 of 72 questions open
Links: `docs/stakeholder/preguntas.html#qN`.

**5 easiest**
- q7 The Rover's 40 hidden stage directions: show them? Yes/no.
- q28 Show the original cast's actors? Yes/no, one fact.
- q34 Are the two epilogues (0503, 0662) part of the play? Yes/no on the manual's rule.
- q72 Should a translation link to its original's RoleCall chart? Yes/no.
- q37 Mark the Additions of The Spanish Tragedy as `Q4`? One choice for the editors.

**5 most important**
- q66 Confirm the 45 prologues on the wrong side (33 plays): the backlog's whole C1 section waits on it.
- q68 Word before a number when citing: the Numbering section waits on it, and it affects every play.
- q69 Recount 16 hand-numbered plays: the same Numbering block.
- q14 Two Pyrame et Thisbé editions and three plays with no text: decides what the corpus keeps.
- q54 English names for the relation kinds (q53, q55 and q56 are in the same block): the published site's relations work waits on them.

## Round trip
- Verse/prose threshold (q23 follow-up): the 61 "mixed" plays are labelled `verso` in our corpus copies.
- Original cast (`characters.actor`): kept and written to TEI, never printed (q28).
- `sp@who` naming no cast role: 2,508 references in 29 plays lose their character and the statistics.
- `stage@n`: 376 dropped on import, mostly Hamlet and Timon; Hamlet v. 2632 is split into 3 stage directions on export.

## Top 3 features (clear to implement, checked in code)
1. **Parse the Word `document.xml` with Saxy, not regexes.** `<w:t>` text split by `<w:tab/>` or `<w:br/>` is lost today, and numeric entities are not decoded. `lib/playcode/import/word_parser.ex:45-48` and `:17`. Fix: Saxy SimpleForm, as `TeiParser` does.
2. **The import page's validation-warnings column is always empty.** `lib/playcode_web/live/admin/import_live.ex:172` sets `validation_warnings = []`, so the column and its gettext strings are dead. Fix: fill it from `Export.TeiValidator` (`lib/playcode/export/tei_validator.ex`). The backlog also allows dropping the column; the fix is stated, but the choice is the owner's.
3. **Import page writes every file twice.** `import_live.ex:93` calls `preview_import/1`, whose numbering step writes the whole file and rolls it back (`lib/playcode/import/tei_import.ex:178-182`). It costs as much as the import (4.2 s against 4.1 s). Fix: pass `numbering: false` (line 176 already supports it) and show the numbering rule after the import or compute it from the parsed file.

Passed over: "Folio words still searched" (the backlog offers two options, so it waits on a choice) and the cast-note tabs (the backlog does not say how to fix it).
Stale in backlog: none found among the candidates read.

## One speed win
- `lib/playcode/export/static_site/edition.ex:50,67`: `Edition.load` preloads `:statistic` (`Catalogue.with_all`, `catalogue.ex:540`), then `Statistics.get_statistics/2` queries `content_version` and `PlayStatistic` again (`statistics.ex:29-31`).
- Change: pass the loaded `play` to a `get_statistics` clause that reads `play.content_version` and `play.statistic`, deleting two queries per play.
- Gain: about 2 round trips per play, roughly 740 over the corpus. Small, but it deletes code. Measure with Ecto query telemetry counts per `Edition.load`; do not expect minutes off the two-hour Generate.
- Risk: low. `content_version` must be the value `load` read first (the comment at `edition.ex:47` relies on it), which a reuse of `play.content_version` keeps.
