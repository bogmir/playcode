# Asides over several verses: one aside, through Playcode and back

**Status:** designed 2026-10-25, from a corpus measurement the same day (the scripts:
`chains.py`, `segnum.py`, `simulate.py`, kept in the session's scratchpad). Plan:
`../plans/2026-10-25-aside-chains.md`. Backlog item: *An aside that runs over several verses is
cut into pieces* (`docs/backlog.md`, Medium Priority). Words as in `CONTEXT.md`; this design adds
**piece** (of an aside).

## Why

A `<seg>` cannot cross an `<l>`, so the files cut an aside over several verses into one
`<seg type="aside">` per verse, a **piece**, and say which pieces make one aside in two ways:

- the seg's `xml:id` numbers the piece within its aside: `es-0411-seg01`, `es-0412-seg02`… In *La
  vida es sueño* (EMOTHE0020) Clotaldo's aside, "(¡Válgame el cielo! ¿Qué escucho?" (v. 395) to
  "sin saber que soy su padre.)" (v. 468), is 74 pieces, `es-0411-seg01` to `es-0484-seg74`;
- each piece but the last names the next in `next`: `es-0411-seg01` names `es-0412-seg02`.

Playcode reads neither. The importer keeps each piece as an aside, `is_aside` on a line all aside
or an `<aside>` marker in a line partly aside, and drops the seg's `xml:id` and `next`: there is no
column for them. The export writes a bare `<seg type="aside">`, so the file Playcode writes no
longer says which pieces are one aside. That breaks the rule that a TEI file is a complete copy of
a play, and readers see it:

- the statistics count pieces as asides: 321 in *El amor al uso* (EMOTHE0384), where emothe.uv.es
  counts 124;
- the site printed "aparte" beside each of Clotaldo's 74 verses. Since 2026-10-25 it labels a
  speech's consecutive aside verses once (`Edition.aside_starts/1`), a guess that shows two asides
  back to back as one (23 times in the corpus).

The chains the files give are faulty, so they cannot be kept as written either. Over the 385 files
of `doc/tei_corpus/`: of the `next` links, 5,379 lead to the next verse, 2,868 are empty, 754 point
at no piece, and none has the `#` a TEI pointer needs. In *La vida es sueño* 130 of 254 point at
nothing, off by one line: Clarín's `es-1203-seg01` (v. 1166) names `es-1205-seg02`, and the next
piece is `es-1204-seg02`. The numbering is sound where the links are not: wherever both a sound
link and a number exist they agree (5,882 of 5,888; the 6 others are `seg00` and links to
themselves).

## What gets built

### One column: does this element's aside continue the one before it

`play_elements.aside_continues`, a boolean, not null, false by default: **the element's first
piece continues the aside of the last piece before it**, in the play's reading order, across
speeches, stage directions and lines not aside. False on an element not aside.

Pieces after the first in the same element are not stored: a later piece continues the one
before it unless spoken words stand between them (a note, a line break or a stage direction is
not spoken). Checked against the files' numbering, this agrees in 289 of 292 cases; the 3 others
are one aside interrupted by spoken words inside a line, in EMOTHE0419, which become two asides.

One function on `Element` gives how many asides **start** in an element: its first piece when
`aside_continues` is false, plus each later piece with spoken words before it. Every reader below
counts or labels from it, so the rule is written once.

### Reading a file

For the first piece of each line or paragraph holding an aside, the importer decides
`aside_continues` by the first rule that applies:

1. **Its number.** An `xml:id` ending `-segNN` with NN of 1 or more: 01 starts an aside, 02 or
   more continues one. Decides 12,518 of the corpus's 18,486 elements with an aside.
2. **The links.** A piece some other piece's `next` names (with or without `#`, never itself)
   continues one; a piece with an `xml:id` that no `next` names starts one. This is what TEI
   means by `next`, so it reads a file from elsewhere; in the corpus it decides 2 (`seg00` in
   EMOTHE0230).
3. **A delivery stage right before it** in its element, "(Aparte.)", "[Aside]": it starts one.
   In the files that number their pieces, a delivery stage stands before a first piece 2,559
   times and before a later one twice. Decides 4,467, mostly prose and the plays with no ids.
4. **Otherwise**, the guess the site makes today: it continues when the line or paragraph before
   it in the same speech holds an aside. Decides 1,499.

Run over the corpus, the rules give *El amor al uso* 124 asides from 321 pieces, emothe.uv.es's
count exactly; *La vida es sueño* 43 from 254, Clotaldo's 74 pieces one; the corpus 8,858 from
18,852.

### Writing a file

The export gives every piece an `xml:id` ending in its number within its aside, and every piece
but an aside's last `next="#…"` naming the one after it, in reading order (the next piece may be
another speaker's):

- a piece in a verse line with an identifier is `<line_id>-segNN`, the files' own shape, NN two
  digits (more past 99): Clotaldo's come back as `es-0411-seg01` … `es-0484-seg74`, and Clarín's
  `es-1203-seg01` now names `#es-1204-seg02`;
- a piece in a paragraph, or in a line with no identifier, gets an identifier of a shape no line
  can have, also ending `-segNN`, the same on every export of the same play.

Every piece is numbered, a one-piece aside too, so the import reads each back by rule 1 and two
asides back to back come back as two. The export pairs pieces in a pass over the play's reading
order before writing, as `TeiXml.with_folio_parts/1` already does for Folio passages that cross
elements.

### What readers see

- **The site** prints "aparte" beside a verse where an aside starts, and beside the first aside
  verse of a speech whose aside continues another speaker's: in *La vida es sueño* Clarín's "(Yo
  apuesto" (after v. 2389), numbered as the third piece of Clotaldo's aside, still gets its label.
  `Edition.aside_starts/1` reads the column instead of guessing.
- **The statistics** count asides, not pieces, on the play page and the site: *El amor al uso*
  124. "Verses in asides" stays a count of verses.
- **The play page, the downloads and the comparison** shade each line aside as today; they print
  no label, so nothing changes there.
- **`/api/v1`** returns `aside_continues` beside `is_aside`.

### Editing

The Content tab's line and paragraph form gets a checkbox under "Aside": **"Continues the aside
before it"**, unticked by default. Saved with "Aside" unticked, it is stored false
(`Element.changeset`). A curator adding a verse inside Clotaldo's aside ticks both.

The Word import's `{ap}` marks one paragraph, usually one verse, so it says nothing about where an
aside ends: the Word import guesses as rule 4 does, an aside line or paragraph continuing when the
one before it in its speech is aside. A curator separates two asides back to back in the Content
tab.

Deleting the verse an aside starts on would leave the next one continuing whatever aside came
before it, perhaps another speaker's. So when a line or paragraph that starts an aside is deleted,
the next one in its speech, if it continued that aside, starts it instead.

### The rows already stored

The migration adds the column and sets it on every element aside by the rule the site uses today:
a verse continues when the verse before it in its speech is aside; anything else is false. That
keeps the site's labels as they are until the re-import, and, as the trigger moves the
`content_version` of every play it touches, every play with an aside has its statistics recomputed
and its pages rebuilt at the next Generate.

The corpus is then re-imported, on dev and on production (`docs/production-reimport.md`, a dry
run first: a re-import replaces a play's lines, so any hand edit to them is lost), which replaces
the guess with the files' own answer.

## Goals

- A play's asides come back whole from its TEI file: export, import into an empty Playcode, and
  `aside_continues` is the same on every row (`complete_copy_test.exs`).
- The file Playcode writes holds sound chains: every `next` a `#` pointer to a piece in the file.
- The statistics count asides as emothe.uv.es did (EMOTHE0384: 124), and the site labels each
  aside once, and again for each new speaker.

## Non-goals

- emothe.uv.es's aside navigator, its "Apartes" switch and arrows stepping from one aside to the
  next. The column makes it possible; it would come with question 52's stage-direction navigator
  if the project wants both.
- Keeping the files' seg identifiers as written: they are rebuilt from the line's identifier and
  the piece's number, so a file whose identifiers were consistent comes back with the same ones,
  and one whose identifiers drifted (Clarín's) comes back corrected.
- An aside interrupted by spoken words inside one line (3 in EMOTHE0419) stays two asides.
- Correcting the team's copies of the files: Playcode's export writes sound chains, and the
  project can take them from there.
- The delivery stage, "(Aparte.)", stays dropped from a line all aside, as today
  (`docs/tei-mapping.md`).

## Anti-goals

- **Storing the files' `next` and identifiers and printing from them.** The 754 dangling and 2,868
  empty links would reach readers, and every line added in the Content tab would need a chain kept
  by hand.
- **A table of asides.** One boolean on the element says everything the readers need.
- **Rewriting the stored text.** The `<aside>` markers stay as they are; no re-encoding of
  `content`, so nothing a curator typed changes.

## Constraints

- The column is read from the file, so a re-import writes it: it is not `@platform_owned`.
- `play_elements` already has the `play_row_changed()` trigger; the column needs none of its own.
- Every test goes through the outer API: the importer and exporter as round trips
  (`roundtrip/1`, `xml_elements/3`), the site through `generate!/2`, the Content tab through
  `live/2`, the migration's rule through the rows it leaves (`PlayContent` reads).
- `docs/tei-mapping.md` (the `seg[@type="aside"]` line), `docs/schema.md`,
  `docs/stakeholder/ida-y-vuelta.html` (note 30 and the asides row) and `CONTEXT.md` (piece)
  change with the code; the backlog item moves to `docs/history.md` when the re-import is done.

## Left to the builder

- The identifier shape for a piece with no line identifier, as long as it ends `-segNN`, no line
  identifier can take it, and it is the same on every export.
- Two asides that both start in one line would both be `-seg01`; the builder breaks the tie so
  identifiers stay unique (none in the corpus).
- Function names, and how the parser hands the pieces' identifiers and links to the pass that
  decides `aside_continues`.
- Where the checkbox sits in the form and how the element list shows it.

## Calls made in this design, for review

1. **One label per speaker.** An aside that runs into another speech is labelled again at the new
   speaker, though the file counts it as one aside.
2. **Every piece gets an identifier on export**, a one-piece aside too; otherwise a one-piece aside
   right after another would come back merged with it.
3. **The number outranks `next` on import**, since the numbers held where the links drifted.
4. **The migration guesses with today's rule** until the re-import, so the site never regresses
   in between.
5. **The checkbox starts unticked**, so a line added in the Content tab is its own aside unless the
   curator says otherwise.
6. **The Word import guesses** with rule 4, the same as a file with nothing else to go by.
