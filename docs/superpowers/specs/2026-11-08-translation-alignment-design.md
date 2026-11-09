# Aligning a translation with its original (problem 5, parked)

**Parked by the owner on 2026-11-09**; Q26 decided the same day (see *Design*), nothing built. This is problem 5 of the six on
numbering, identifiers and alignment. Problems 1–4 and 6 are built: see the 2026-11-08 specs
beside this one. This file is the handoff written during the grilling (2026-11-08), kept
here so the analysis survives. Start with a grilling or brainstorming session on the open
questions at the end, before writing a plan.

## What it is for

The side-by-side comparison scrolls an original and its translations together. In March 2026
the researcher tested Antony and Cleopatra (0038) with three translations and saw drift. The
French one (0084) repeats a speaker's name after a stage direction in the middle of a speech,
which creates a second `<sp>` with the same `@who`: 1,195 speeches against the original's
1,179. This problem makes the pairing explicit and editable.

## How it works today

- **Headings** pair by position: `Division.sync_keys/1`
  (`lib/playcode/play_content/division.ex:53`) gives keys like "act-0" and "scene-2".
- **Speeches** pair by proportion within their act (`assets/js/sync_scroll.mjs`,
  `counterpart/3`): speech i of n matches speech round(i·(m−1)/(n−1)) of the other panel's m.
  With no acts, the proportion runs over the whole play.
- **Error:** the first and last speeches always pair, so the error is largest where cuts or
  additions concentrate, often mid-play.
- **Where it runs:** the live page imports the module, and `Export.CompareHtml` inlines it.
- No identifiers are involved.

## What translations do in the corpus (development database, `plays.parent_play_id`)

| Kind | Example |
|---|---|
| Speeches cut | 0012 *Gl'ingannati*: 1,213 speeches; 0090 *Los engañados*: 556 |
| Speeches split or added | 0013 *La verdad sospechosa*: 756; 0120 *Il bugiardo*: 1,363 |
| Adaptations | 0201 *El burlador*: 933, against 0192 *Dom Juan*: 642; 0044: 838, against 0049 *Saint Genest*: 270 |
| Verse becomes prose | 0010 *Hamlet*, 2,794 verses; 0050 *Amleto*, all prose. 0020 *La vida es sueño*; 0021 and 0023, all prose |
| Verse to verse, other counts | 0113 *Tartuffe*: 1,963 verses; 0121: 3,038 (the metre changes) |
| Characters dropped | 0182 *Henry V*: 46 speaking characters; 0226: 25. 0236: 26; 0687: 10 |
| Characters added | 0278: 29; 0279: 35 |

Some of the character difference is encoding (groups, "Todos").

What follows:
- align by speech, never by verse;
- characters need their own mapping, which allows roles that are unmatched, merged or renamed.

## The researcher's proposal and why `corresp` is better

The proposal: Playcode puts a numbered `<anchor>` before every `<sp>` in every text; the coder
deletes the extra ones; Playcode renumbers. Its flaws, with an invented example in which the
original has sp1–sp5 (Philo, Cleopatra, Antony, Cleopatra, Antony):

1. **Each pairing depends on the count before it.**
   - French repeats Antony, so it has anchors 1–6.
   - If the coder forgets to delete anchor 4, French 4 pairs with original 4, and every later
     speech is off by one to the end of the play.
2. **The original's anchors are shared by every translation.**
   - An editor adds a speech the original's encoding missed (Demetrius, at the start).
   - The original's anchors renumber, and all three translations shift at once. Each must be
     fixed by hand.
3. **A cut needs an anchor with no speech.**
   - Spanish drops sp4.
   - The coder must add an anchor 4 next to anchor 5, and the renumbering must not remove it.
4. **It isn't portable.**
   - "Anchor 4 here goes with anchor 4 there" is our own convention.
   - The file alone says nothing about what it aligns with.

`corresp` on the translation's speeches, for example
`<sp who="#antoine" corresp="EMOTHE0038.xml#em0038-en-sp-3">`:
- **Splits:** both French Antony halves point at sp3.
- **Cuts:** nothing points at sp4.
- **Merges:** one speech points at two: `corresp="… #…-sp-4 #…-sp-5"`.
- **Mistakes stay local:** a wrong pointer is wrong for one speech only.
- **Nothing is renumbered:** Playcode stores the pairing as a relation between rows, not as
  text, and writes the current identifiers at each export. Adding Demetrius changes nothing
  that has to be fixed.
- **Remaining gap:** a file downloaded before the original changed keeps old pointers.
- **Standard:** it is standard TEI, and self-describing.

## Design (Q26, decided by the owner on 2026-11-09)

The four parts of Q26 and their answers:
- **A. Storage: links between rows,** not the `corresp` text as written. Identifiers are
  recounted at every export (problem 2), so a stored pointer would silently name the wrong
  speech once the original gains one.
- **B. Characters are paired too, and stored,** so a wrong character pair can be corrected
  and the correction lasts.
- **C. The first pass is automatic (speaker sequence), but only after a proof of concept**
  shows it works on the test plays (0038 against 0084, 0052 and 0139; 0010 against 0050;
  0012 against 0090; 0013 against 0120). The POC reads only: no tables, no TEI change.
- **D. Correction both ways:** on the comparison page, and by editing `corresp` and
  re-importing.

- **Storage:**
  - speech pairs: a relation from a translation speech to one or more original speeches;
  - character pairs: a relation from a translation character to one or more original
    characters.
  - **Re-importing the original** replaces its speech rows, which would delete every
    translation's links to it. Before the replace, each link is written down as the
    original's current speech identifier and resolved again afterwards; a speech the new
    file no longer has loses its pair, and the import preview says how many.
- **First pass (automatic, after the POC):**
  1. Map characters, starting from names and the order in which they first speak; the coder
     confirms.
  2. Align speeches by the sequence of speakers, as a diff does. The French repeated speaker
     falls out by itself: the same character speaks twice in a row in the translation and
     once in the original.
- **Correction:** on the comparison page, click to re-pair a speech. A coder working in XML
  can edit one `corresp` and re-import.
- **Export:**
  - speeches get `corresp="{original}.xml#{original speech identifier}"`, using problem 2's
    identifiers at export time;
  - characters get `role corresp`. Note: the import already reads `role corresp` *within* a
    file (`tei_parser.ex` around line 1434: a cast-list role refers to a character), so a
    pointer into another file is new.
- **Import:** resolve `corresp` to the original's rows. Open: what happens when the
  translation is imported before its original.
- **Comparison page:** use the pairs where they exist; fall back to the proportion elsewhere.

## Step by step

1. The researcher opens 0038 against 0084. Playcode has proposed pairs: French Antoine ↔
   Antony, Cléopâtre ↔ Cleopatra, …
2. The speeches are aligned by speaker sequence. Both French Antoine speeches at the repeated
   speaker pair with original sp3.
3. The researcher spots one wrong pair at a cut and re-pairs it with a click. Only that speech
   changes.
4. Export 0084: `<sp who="#antoine" corresp="EMOTHE0038.xml#em0038-en-sp-3">`, twice.
5. Later 0038 gains a speech at the start. At the next export of 0084 the pointers read
   `…-sp-4` by themselves.

## How it interacts with the others

- **Needs 2 (built):** speech identifiers in the export, counted afresh each time, with no leading zeros (`em0038-en-sp-3`).
- **No numbering involved:** none of 1, 3 or 4. Pairing by speech means `@n` (verse or speech
  numbers) never has to match across plays: Hamlet numbers verses and Amleto has none.

## Open

- **Q26:** decided 2026-11-09, see *Design* above. Next: the proof of concept.
- **Statistics:** should a speech repeated after a stage direction (same `@who`) count once?
  The researcher says it inflates speech counts.
- **Adaptations** (Dom Juan, Le Menteur, Saint Genest): align them, or leave them out of the
  comparison?
- **Import order** when the original is missing.
- **The researcher has been answered** (2026-11-08): the four flaws of anchors, and how
  `corresp` would be filled. The text is in the grilling transcript,
  `~/.claude/projects/-home-bogdan-Projects-playcode/3617a47a-728e-4ef6-a9ad-7b94b0f59fa9.jsonl`.

## Suggested skills

- `superpowers:brainstorming`, or `mattpocock-skills:grilling`, before any design is fixed.
- `mattpocock-skills:prototype` for the comparison page's re-pairing interaction.
