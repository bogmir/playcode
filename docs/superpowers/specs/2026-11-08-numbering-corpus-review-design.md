# Problem 6: reviewing the plays whose numbering is broken

Decided with the owner on 2026-11-08 (Q33). Move this file to `docs/superpowers/specs/` when
the session starts (`/tmp` is cleared on reboot).

## What it is for

Problem 4 (merged, `docs/superpowers/specs/2026-11-08-numbering-setting-design.md`) gave every
play a numbering rule: type, restart and Manual. A play whose stored numbers fit no rule was
set to Manual, with the closest rule recorded, so its numbers are never recounted. In the
development database that left **51 plays Manual**. This problem settles the ones whose fix is
obvious, keeps the deliberate ones Manual, and gives the researcher a list of the rest.

## State at hand-off

- Problems 1–4 are merged and pushed (`main` = `origin/main` at `3d59509`), so Fly runs them.
- **`Playcode.Release.settle_numbering` was being run on Fly on 2026-11-08 by the owner.**
  Confirm it finished, and that Generate followed. Production's output (one line per play from
  `Numbering.describe/1`, e.g. "V never, Manual: 1 number differs") is the authority. The
  lists below come from dev, which was loaded from the same corpus. To get the per-play lines
  again:
  `bin/playcode rpc 'Playcode.Release.settle_numbering(dry_run: true)'` (writes nothing).
- **Q34 (owner): the researcher is *not* told about the identifier changes** (recounted on
  export, on speeches and stage directions, no leading zeros). Don't mention them in the
  question.
- The question about citation words (v., l., int.) is question 68 in `preguntas.html`, already
  asked. It is not this problem's.

## Decisions (Q33)

| Group | Plays | What | Who |
|---|---|---|---|
| **A. One number off** | 23 | Switch Manual off: the recount changes exactly one number | us |
| **B. Prologue or epilogue continues the count** | 9 | Switch Manual off: the researcher already ruled they restart (Q21) | us, after checking |
| **C. Numbered by the editor's own scheme** | 2 | Stay Manual for good; no question | nobody |
| **D. Wrong throughout** | ~14 | Stay Manual (as they are); list them for the researcher in one question | researcher |

### A. One number off (settle)

Each play: the recount changes one number and nothing else moves.

- **A stray number on the last verse, or one near the end:**
  - AL0569, AL0750 ("5431" for 3097), AL0784, AL0790, AL2000;
  - EMOTHE0005 ("3170" for 2189), 0006, 0022, 0044, 0046, 0049, 0058, 0061, 0175, 0201,
    0204, 0268, 0298, 0319.
- **One verse or paragraph without a number:** 0503, 0544, 0662.
- **One paragraph numbered 75 where its scene restarts at 1:** 0341.

### B. Prologue or epilogue continues the count (settle, after checking)

0103, 0343, 0346, 0354, 0363, 0369, 0554, 0672, 0695: between 6 and 89 numbers each.

**Check first:** every number the recount would change must lie inside a prologue, epilogue
or induction (a top-level division that is not an act). The dev triage did not verify this.
A play with a change elsewhere moves to D.

### C. Keep Manual (no question)

- 0010, Hamlet: "3-4", "124.1".
- 0372, Timon of Athens: "4-5".

These are deliberate, not errors.

### D. Leave Manual, list for the researcher

| Kind | Plays | Numbers a recount would change (dev) |
|---|---|---|
| Numbers copied from the identifier count | 0111, 0132, 0173, 0178, 0182, 0220, 0262, 0275, 0314 | 36 to 1,788 per play |
| Off by one from some point to the end | 0472 (from verse 853), 0658 (the whole play) | 253, 1,047 |
| A scene that doesn't restart | 0697 | 475 |
| Damaged | 0329; 0622 (numbers and identifiers both go by threes) | 1,346, 3,485 |
| **Unknown until production's counts** | 0283, 0367, 0427 | the dev script counted padded prose numbers ("0001" vs "1") as differences, which Playcode treats as equal |

Sort the three unknowns into A, B or D by production's output.

## Step by step

1. **Get production's per-play lines.** Compare the Manual plays with the lists above, and
   re-sort anything that differs. Production may hold corrections that dev doesn't (files
   uploaded with `mix playcode.fly.reimport files`).
2. **Check B.** For each B play, list the rows a recount changes and their divisions. Use
   `Numbering.differences/2` over `PlayContent.reading_order/1`, joined to each row's
   division type; `scripts/triage.exs` is the starting point. Anything outside a
   prologue, epilogue or induction moves the play to D.
3. **Settle A and B on production.** In each play's form, switch Manual off: the form shows
   "N numbers will change" and saves on the second submit, then recounts. Check that N matches
   the expected count before confirming. For 32 plays a one-off `bin/playcode rpc` loop may
   be easier. It must go through the same path as the form (save the setting, then
   `Numbering.recount/1`), and it is run by the owner with `!`. Then **Generate**. There is no
   Deploy to emothe.uv.es while it is blocked.
4. **Do the same in dev,** so both agree.
5. **Record what was done** in `docs/stakeholder/preguntas.html`, section "Files corrected":
   one entry per kind, naming the plays and what changed (e.g. "EMOTHE0005: the last verse
   was numbered 3170; it is 2189"). No answer is asked for. Republish the Questions artifact
   (memory *Artifacts sync later*: republish without asking; on the wrong account, skip it).
6. **Ask about D:** a new question at the end of `preguntas.html` (numbers never change, so
   use the next free one), with a background page beside it if it needs one. For each play:
   - its title and code;
   - what is wrong, in one line;
   - how many numbers a recount by its rule would change;
   - the rule it would get.

   Ask whether we may renumber each one (a published number that someone may cite would
   change), and ask for the hand-corrected 0622 file. 0622's background: our copy's numbers
   and identifiers both go up by threes (`…-0001, -0004, -0007`, verses 1, 4, 7). So the
   verse numbers were taken from FileMaker's identifier count, which seems to include two
   records per line that never reach the file. That would explain why "reiniciar la
   numeración" in FileMaker fixed nothing. The researcher fixed it by hand for a teacher, and
   asked the FileMaker developer why.
7. **Records:** `docs/backlog.md` gets an item for D waiting on the researcher;
   `docs/history.md` gets what A and B settled.

## How it interacts with the others

- **Needs problem 4 (done):** Manual, the closest rule, the form's confirmation, the recount.
- **Problem 3:** a settled play's site anchors move with its new numbers. That's expected; the
  site has been unpublished since 2026-11-06 anyway.
- **Problem 5** (alignment, parked): unrelated.
- **Statistics:** unaffected. Verse counts come from the structure, not the numbers.

## Tests

- Mostly data work, no new code. If a `Release` helper is written for step 3, test it in
  `release_test.exs`, through the same path as the form, and prove the test bites
  (`bin/bites`).
- Before switching anything on production, run the dev equivalent and compare counts.

## Suggested skills

- `superpowers:verification-before-completion`: counts checked before and after each switch.
- `mattpocock-skills:grilling`, only if production's output reshuffles the groups.

## Outcome (2026-11-09)

Re-sorted from dev's counts (`Numbering.differences/2` per play, each change joined to its
top-level division's type):

- **0363 moves from B to D.** Its prologue continues the induction's count, as expected, but
  act 1's opening four lines continue it too (150–154), and in 4.3 an unnumbered shared verse
  (I/F after v. 57) shifts 65 numbers.
- **0314 moves from D to B** (owner, 2026-11-09). Its only changes are its unnumbered
  epilogue's 36 lines, numbered 1–36; every act fits.
- **0343's 13 other changes are in two interludes**, top-level divisions that are not acts: B.
- The unknowns: **0367 goes to A** (one printed line `0032` for 15 in the prologue); **0283 goes to D**
  (4.1: a shared verse coded I-F-I-M-F; the file counts all five parts as v. 38, so the second
  I is probably an M); **0427 goes to D** (2.2 continues 2.1, 27–59).

A: 24 plays, each 1 change. B: 9 plays (0103 8, 0314 36, 0343 15, 0346 6, 0354 14, 0369 18,
0554 32, 0672 89, 0695 67). C: 2. D: 16.

Settled by a one-off script (owner, 2026-11-09: no Release helper), not kept in the repo: for
each code and expected count, a Manual play whose `Numbering.changes/2` equals the count gets
`Catalogue.update_play(play, %{numbering_manual: false})` and `PlayContent.refresh_derived/1`
in one transaction, then must show no differences; anything else is printed and skipped. Run
with `Code.eval_string(File.read!(path), dry_run: true | false)`, through `mix run -e` in dev
and `bin/playcode rpc` on Fly. Dev: 33 changed, 18 Manual left.

Records: `preguntas.html` "Files corrected" (8 November entry) and question 69 with
`numeracion.html`; `docs/backlog.md` "Numbering (2026-11-09)"; `docs/history.md`.

Production (2026-11-09): the dry run matched dev on its 28 plays; it holds none of the five
AL plays, and one Manual play dev lacks, EMOTHE0800 (a draft, 1,659 of 1,774 numbers off),
left out of question 69 until the owner says whose it is. The 28 were found already settled
when the real run came (switched off between the dry run and it); the public API shows them
recounted (0005 ends at 2189, 0544 has v. 576, 0354's and 0672's epilogues restart at 1).
Generate rebuilt 47 plays; no Deploy.
