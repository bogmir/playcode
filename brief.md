# Playcode brief, 2026-11-17 (commit 1df4962)

Current focus: none.

## Questions: 19 of 72 questions open
**5 easiest** (yes/no or one fact):
- [q7](docs/stakeholder/preguntas.html#q7) The Rover's 40 hidden stage directions: show them? yes/no.
- [q28](docs/stakeholder/preguntas.html#q28) Show the original cast's actors? yes/no; data already stored.
- [q34](docs/stakeholder/preguntas.html#q34) Are the two epilogues divisions of the play? yes/no, two plays.
- [q72](docs/stakeholder/preguntas.html#q72) Translation links to the original's RoleCall chart? yes/no.
- [q13](docs/stakeholder/preguntas.html#q13) Who replaces Jodelle on 11 witnesses? One name to give.

**5 most important** (what they unblock):
- [q66](docs/stakeholder/preguntas.html#q66) Prologues on the wrong side: 45 texts in 33 plays; blocks backlog C1 and the corpus fixes.
- [q69](docs/stakeholder/preguntas.html#q69) Recount 16 hand-numbered plays; a yes lets Manual go and Generate follow.
- [q68](docs/stakeholder/preguntas.html#q68) Word before a cited number; the site's cite button and statistics ranges use it.
- [q57](docs/stakeholder/preguntas.html#q57) Plays without a text; gates the whole relations design (q53-57).
- [q14](docs/stakeholder/preguntas.html#q14) Nine plays with a web edition but no TEI file; corpus completeness.

## Round trip
- Original cast (`characters.actor`) is written to TEI but printed nowhere: waits on q28.
- Verse/prose label: our 61 corpus copies still say `verso` for the "mixed" plays; waits on q23's follow-up.
- Nothing else short of "yes" in ida-y-vuelta that is not already tied to a question.

## Top 3 features (clear to implement, verified in code)
1. **Admin import writes each file twice**: preview costs as much as the import (4.2 s vs 4.1 s). `lib/playcode_web/live/admin/import_live.ex:93` calls `preview_import(path)` with numbering on (`tei_import.ex:147`) just to decide whether to ask for confirmation; the filter never reads `numbering`. Fix: `numbering: false` there, compute it only for files that reach the confirm screen (shown at `import_live.ex:329`).
2. **A shared line's lead carries no note numbers**: `lib/playcode/play_content/split_verses.ex:44-66` builds `lead` from `content` only, so a part after one with a note starts up to ~28px short, in every output. Fix: print the markers in the lead as a plain `<sup>`, no id or link, in each renderer (`download.ex:360` and its siblings).
3. **Front matter prints header text through `escape/1`**: `lib/playcode/export/download.ex:51-52` (title, author; also 107, 124, 146) would show `<<…>>` for an `<emph>` in a header; latent, none of the 385 files has one. Fix: `NoteMarkup.inline/3`, then give `inline_markers_test.exs` its italics.

Stale in backlog: none found. Skipped as a choice between options: "Folio words searched while the switch is off".

## Speed win
- Weak find; the big paths are measured or batched (catalogue reads: `static-site-improvements.md:197`; TEI import: already `insert_all` in 1,000-row batches, `tei_import.ex:965`). Remaining: `lib/playcode/import/bibliography.ex:155-165` inserts each FileMaker link with `Repo.insert!` in an `Enum.each`; batch it with `insert_all`.
- Gain: one round trip per link instead of thousands, seconds at most, on a one-time import; measure with `mix playcode.import.bibliography` on dev.
- Risk: low; `insert_all` skips `Link.changeset` validation, so keep a check on volume/pages/note. Not worth doing before the items above.
