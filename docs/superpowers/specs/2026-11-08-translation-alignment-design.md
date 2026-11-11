# Aligning a translation with its original (problem 5)

Problem 5 of the six on numbering, identifiers and alignment; 1–4 and 6 are built (the
2026-11-08 specs beside this one). Grilled 2026-11-08, Q26 decided 2026-11-09, proof of
concept 2026-11-09, **design revised by the owner on 2026-11-11** after the researcher's
answers: the pairs are computed, not stored (see *Design*). Step 1 built 2026-11-11 on
`feature/computed-speech-pairs`.

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

## The researcher's answers (2026-11-10)

Asked how the parallel view is used, after seeing the proof of concept:
- **It belongs on the static site:** "los paralelos son también parte de la Biblioteca". The
  site export builds no comparison page today; readers get it only in Playcode
  (`/plays/:code/compare`) or as a download from the admin.
- **Readers use it** to read an original beside its translations. Not a tool for the team.
- **Nobody corrects a translation while comparing:** it is final before it is encoded. So no
  live comparison.
- **The report helps a coder** find the differences; a Playcode tool to correct them would be
  welcome, but the project prefers to save and keep Playcode a coding platform and database.
- **Rows 89 and 91 of the report do not correspond and are not marked:** the French gives the
  messengers' lines to other people, so the speakers line up and the words are one speech off.
  "Same" in the report means the same speaker, not the same content.

## Design (revised by the owner on 2026-11-11)

Replaces the Q26 decision of 2026-11-09 (stored links for every speech, a click to re-pair on
the comparison page): it cost a table of some 1,200 rows per translation, rebuilt at every
import, and a `corresp` on every `<sp>` that goes stale when the original changes.

- **Speech pairs are computed when a parallel view is built**, never stored: the comparison
  page when it opens, the comparison download, and the static site at Generate.
  1. Load both texts (the page already does).
  2. Read each translation character's original character.
  3. Pair the speeches by the sequence of speakers, read through the character pairs, per
     scene when both texts have the same scenes, else per act, else the whole play
     (`Playcode.Alignment`, from the proof of concept).
  4. Write the pair into the HTML on each translation speech (`data-pair`, the original
     speech's place); `sync_scroll.mjs` scrolls to it, and keeps the proportion for a speech
     with none (a cut, an added speech, a text whose speakers are not paired).
  The browser computes nothing, so the static site still works from disk. Same text, same
  pairs; an improved rule changes them everywhere at the next Generate (the module is in the
  export's fingerprint).
- **Characters are paired automatically and can be corrected** (no confirmation step). Only
  the corrections are stored (decided by the owner 2026-11-11, replacing "filled by the
  automatic pass on import or linking"): every comparison pairs the characters by rule, as
  step 1 does, then lays the corrections on top, the same pattern as the speech corrections.
  Nothing to run on the existing plays, no hook on each way a play is linked, and an
  improved rule reaches every uncorrected character at the next Generate. A correction is
  either another original character or "no original". Corrected on the translation's
  characters tab, or in the XML. One original per character: a merged role ("PISTOLA, NYM,
  BARDOLFO") stays unpaired and its speeches pair by position. A correction takes effect at
  once.
  - *Builder's calls (step 3):* the correction is held as the original character's
    `xml:id` (`characters.original_xml_id`), not a row id, so re-importing the original,
    which recreates its characters, keeps it, and a translation imported before its
    original keeps its pointer until the original arrives. "No original" is
    `characters.no_original`. A pointer naming no character of the original counts as no
    correction. Re-importing the translation from a file without pointers (the corpus's
    files) keeps the corrections of the characters whose `xml:id` it still has.
- **Speech corrections are the only speech pairs stored:** one nullable column on a
  translation speech, the original speech it goes with, expected a few per play. A correction
  is a fixed point: the pairing runs between corrections, so one fix also mends its
  neighbours (rows 89/91). An original speech deleted empties the column and the speech falls
  back to the computed pair.
- **TEI** (complete copy: what is stored is written): character pairs on
  `castItem corresp`, speech corrections on `sp corresp`, through a prefix declared once in
  the header, so a pointer stays short and the path to the original is written in one place:

  ```xml
  <listPrefixDef>
    <prefixDef ident="orig" matchPattern="(.+)"
               replacementPattern="../EMOTHE0038/EMOTHE0038.xml#$1"/>
  </listPrefixDef>
  …
  <castItem corresp="orig:CLEO">
  <castItem ana="sin-original">
  <sp who="#cleopatre" corresp="orig:em0038-en-sp-1150">
  ```

  - `castItem`, not `role`: the export already gives `role corresp` a meaning (a later cast
    list naming a character declared earlier, `tei_parser.ex` around line 1536).
  - The path is relative to the static site's layout (`plays/<CODE>/<CODE>.xml`); a bare
    `EMOTHE0038.xml#…` would point beside the translation's own file.
  - Character identifiers are kept, so `orig:CLEO` does not go stale. Speech identifiers are
    counted at each export; within one site build both files agree, and a downloaded file
    goes stale only if the original's speeches change later (the texts are final).
  - Import resolves `orig:X` against the play the file names as its original, without the
    path. Until that play is in Playcode the pointer has nothing to resolve to (open: keep it
    as text, or drop it with a warning).
  - Re-importing the original: characters resolve again by their kept `xml:id`; the few
    speech corrections are written down as identifiers before the replace and resolved after,
    and the import preview says how many were lost.
- **The report** (proof of concept) can become a read-only download for a coder, with a "same
  speaker, very different length" warning that would mark rows 89/91. Not a correction screen.
- **Left out:** live updates of the comparison, a click to re-pair on the comparison page, a
  HIERONIMO-style "pupitre virtual".

## Performance (measured 2026-11-11, dev laptop, median of 3 per pair, two runs)

`Alignment.align/2` over all 154 translation/original pairs:

| | run 1 | run 2 |
|---|---|---|
| median | 15 ms | 13 ms |
| 95th percentile | 193 ms | 167 ms |
| slowest (0236/0237) | 682 ms | 587 ms |
| all 154 | 9.1 s | 7.4 s |

Slowest beside 0236/0237: Coriolanus 0676 against 0677 and 0689, 0012/0090, 0013/0120; not
profiled (likely texts whose scenes differ, so the diff runs over the whole play). The page
waits at worst about 0.8 s more (Coriolanus with two translations); cache until either play
changes only if someone notices. Generate: at most about 8 s more for a full rebuild.

## Reverting

- The work is a branch merged as one commit: `git revert -m 1` removes it, and the
  proportion (kept in `sync_scroll.mjs` as the fallback) takes over again.
- The two columns go with a migration; only the hand corrections are lost.
- TEI files exported meanwhile import cleanly into the reverted Playcode: it reads no
  `corresp` on `sp` or `castItem` and no `listPrefixDef` today.

## Order of work

1. **Computed speech pairs in today's comparison** (page and download): `Playcode.Alignment`,
   `data-pair`, `sync_scroll.mjs` follows it. Code only: no column, no TEI change. **Built
   2026-11-11** (`feature/computed-speech-pairs`): the pairs are computed when a panel is
   added or removed, for each translation or version whose original is shown; adaptations
   and translations without their original keep the proportion. On the dev database every
   speech of 0038/0084 and of Coriolanus with two translations gets a pair; building the
   panels, loading included, takes 283–348 ms.
2. **The comparison on the static site**, with the same pairs. **Built 2026-11-11**
   (`feature/static-site-comparison`, design
   `docs/superpowers/specs/2026-11-11-static-site-comparison-design.md`): `compare.html` in
   each published derived play's folder, beside its published original; a Compare link on
   the original's catalogue line and a menu of its translations on the page.
3. **Character pairs**: the column, the automatic pass on import, the dropdown, `castItem
   corresp`. **Built 2026-11-11** (`feature/character-pair-corrections`, plan
   `docs/superpowers/plans/2026-11-11-character-pair-corrections.md`): only corrections are
   stored (`characters.original_xml_id`, `no_original`), the rule pairs the rest at every
   comparison; the select is in the cast entry's form on the characters tab.
4. **Speech corrections**: the column, fixed points in the pairing, `sp corresp`, the import
   and the re-import of the original.
5. **The coder's report** as a download, with the length warning.

## Proof of concept (2026-11-09, branch `poc/translation-alignment`)

`Playcode.Alignment` (pure, stores nothing) and `poc/align.exs`, which reads the dev database:
`mix run poc/align.exs` sweeps every translation against its original (154 pairs, 37 s);
`mix run poc/align.exs 0038 0084` writes one pair side by side as HTML for a person to check.

- **Characters:** Jaro similarity of the names without accents, or, for a weak name match,
  its mean with where in the play the character speaks (20 slices) and, at half weight, how
  much; one-to-one, greedy. Without the "how much", 0084's Paysan and Garde (8 and 2
  speeches, both only in the last scene) swapped with the Countryman and the Guardsman, and
  the whole scene paired one speech off.
- **Speeches:** `List.myers_difference/2` over the speaker sequence, per scene when both
  texts have the same scenes, else per act, else the whole play.
- **The check that does not depend on speakers:** the correlation of the paired speeches'
  lengths (log word counts). A right pairing translates long speeches long.

| | pairs | median length r, aligned | median length r, proportion today | aligned r ≥ 0.85 |
|---|---|---|---|---|
| translations | 142 | 0.96 | 0.71 | 128 |
| adaptations | 11 | 0.04 | 0.05 | 2 (0121, 0317) |

- **0038/0084**, the drift the researcher saw: 0.93 against −0.03. Both French Antoine halves
  point at the one Antony speech; Messenger/Serviteur pairs although the names differ.
- **The weakest translations** are free ones, not failures: 0230 (r 0.30) rewrites the text,
  0775 (0.49), 0674 (0.59), the 0106 family (0.53–0.78, 200+ speeches cut).
- **Characters:** 0226 (Italian *Henry V*) lists groups as one character ("PISTOLA, NYM,
  BARDOLFO") and a cast-list heading as a character ("Scena: Inghilterra, poi Francia");
  one-to-one pairing then pairs "Coro" with Nym.
- **Adaptations do not align** (Dom Juan, Saint Genest, Le Menteur, Il bugiardo).
- **The report** marks a row by its pairing kind; rows 89/91 show that a same-speaker row can
  still be wrong.

## How it interacts with the others

- **Needs 2 (built):** speech identifiers in the export, counted afresh each time, with no
  leading zeros (`em0038-en-sp-3`), for the speech corrections' pointers.
- **No numbering involved:** none of 1, 3 or 4. Pairing by speech means `@n` (verse or speech
  numbers) never has to match across plays: Hamlet numbers verses and Amleto has none.

## Open

- **Statistics:** should a speech repeated after a stage direction (same `@who`) count once?
  The researcher says it inflates speech counts.
- **Adaptations:** the pairing does not work for them (median r 0.04); leave them on the
  proportion, which is what step 1 does for a text whose speakers do not pair.
- **Import order:** a translation's pointers when its original is not in Playcode yet.
