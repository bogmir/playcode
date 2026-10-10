# Critical apparatus (`<app>`) and literal HTML (`<code>`) in the TEI corpus

Analysis of 2026-10-10, from the 370 production TEI files (`doc/tei_corpus/`, git-ignored), the
dev database after a full re-import, and the old EMOTHE pages
(`https://emothe.uv.es/biblioteca/textosEMOTHE/<file>.php`) with their stylesheet. Both are
listed in `CLAUDE.md`, *Found by the corpus round trip*. The questions only the project can
answer are in `stakeholder/variantes-y-codigo.html`.

## `<app>`: the critical apparatus

### In the corpus

604 entries in 6 plays:

| Play | Entries |
|---|---|
| EMOTHE0560 *La discreta enamorada* | 212 |
| EMOTHE0460 *The Summoning of Everyman* | 127 |
| EMOTHE0187 *Friar Bacon and Friar Bungay* | 98 |
| EMOTHE0010 *The Tragedy of Hamlet* | 94 |
| EMOTHE0530 *Les amours tragiques de Pyrame et Thisbé* | 63 |
| EMOTHE0435 *El bastardo Mudarra* | 10 |

- `type` is `substantive` (552) or `orthographical` (32); 20 have none. `n` numbers them.
- Each holds a `<lem wit>` (the reading the edition follows, and its witness), any number of
  `<rdg wit>` (other witnesses' readings), and often a `<note>`: on one reading (inside `<lem>`
  123, inside `<rdg>` 58) or on the whole entry (31). Readings may hold `<emph>`.
- **The base text always stands outside the `<app>`**, which follows the word or phrase it
  annotates. The `<lem>` repeats that word, sometimes in another spelling:
  ```xml
  <l n="72">mucho la hermosura llama<app type="substantive" n="908">
    <lem wit="#H">llama<note>Corrección de Hartzenbusch, lección que acepto por ajustarse
      mejor a la rima consonante y al sentido del pasaje.</note></lem>
    <rdg wit="#P3">falta</rdg> <rdg wit="#MP">infama</rdg></app>,</l>
  ```
  A few have readings only (`<app><rdg wit="#Dyce …">lovely</rdg></app>` after "lively").
- Where they sit: in `<l>` 391, `<stage>` 104, `<p>` 32, a note's `<term>` 30, `<seg>` 18,
  `<speaker>` 13, `<emph>` 13, `<head>` 3.
- 11 carry `to="#id"`: the entry covers lines up to that id, as in "vv. 13-14 Estos dos versos
  faltan en *PXXIV*", with no readings.
- Witnesses are sigla as the editor wrote them: `#Q2`, `#F1`, `#Aut.`, `#PXXIV`, `#H`, `#P3`,
  `#MP`, `#Dyce`. Only EMOTHE0460 lists its witnesses (`sourceDesc/listWit`, FileMaker slice S3).
  Every siglum resolves in FileMaker (2026-10-10): 21 to a witness in `T03_ObraTestimonio`, 21 to
  a modern edition's `bibliography_entries.siglum`, none to nothing. S3 gives them rows to point
  at; see `superpowers/plans/2026-08-01-filemaker-import-slices.md`, S3.

### What Playcode does today

The importer reads every word inside the `<app>` into the line, so the readings are pasted in
and the TEI export writes them back as text:

- *La discreta enamorada*, Jornada I, v. 72: "mucho la hermosura llama llamafalta infama ,"
- the stage direction before v. 75: "Salen LUCINDO, GERARDA y HERNANDO, criado de LUCINDO Salen
  Lucindo y Gerarda, Hernando, criado de Lucindo. Salen Lucindo, Gerarda y Hernando. ."
- *Hamlet*, v. 8: "Barnardo. Barnardo. Barnardo?"

### What the old site did

The line shows the base text only, followed by a `*` (an `F` in Hamlet). Clicking it opens a
box, separate from the numbered notes (`N`), with one line per reading, the witness in italics,
a reading's own note in brackets, then the entry's note:

> mucho la hermosura llama\*,
> – *H* llama (Corrección de Hartzenbusch, lección que acepto…) – *P3* falta – *MP* infama

Counts on the old pages: 59 entries for 0187, 200 for 0560, 10 for 0435, and only 4 for
Hamlet, whose 94 entries were otherwise not shown (its Folio readings went through `<code>`,
below).

### Proposed design (agreed so far)

1. **Import**: the whole `<app>` leaves the line's text, as a `<note>` does, so the line reads
   as the old site showed it. The entry is stored at its offset, after the word it annotates.
2. **A kind of note**: a `play_notes` row of a new type, `variante` ("Textual variant",
   "Variante textual"), keeping the `<app>`'s `n`, its type in a new `variant_type` column,
   its own note as the body, and its readings in a new `readings` field (`embeds_many`,
   JSONB: `lemma` true or false, `wit` as written, `text` with `<<italics>>`, the reading's own
   `note`). Offsets, the carrying of offsets through edits, pop-ups, endnotes and the
   content-version trigger are the notes' own.
3. **Display**: a marker after the word, with the readings in the pop-up as the old site
   listed them. Whether the marker is a number in the notes' sequence or a separate `*` is
   question 1 for the stakeholders.
4. **TEI round trip**: the export writes `<app type n><lem wit>…</lem><rdg wit>…</rdg><note>…
   </note></app>` back at the note's offset from the stored data, as `build_note/1` writes a
   `<note>` today. A test imports, exports, re-imports and exports again and expects the same
   file, as for notes and inline stages.
5. **Editor**: a variant is edited in the note editor, with its readings as a list (witness,
   reading, comment) to add to, change or remove.

Still to settle in the design: entries inside a note's `<term>` (30), the `to="#id"` ranges
(11), and how the witness sigla are shown (question 3).

## `<code>`: literal HTML in the text

### In the corpus

1,211 `<code>` elements in 7 plays, holding only four strings: `<sup>` (315), `</sup>` (314),
`<span class="folio">` (291), `</span>` (291). They sit in `<p>` 490, `<l>` 446, `<stage>`
187, `<speaker>` 78, `<seg>` 6, `<head>` 4. They spell out HTML that the old site printed as
it was. Four different uses:

| Use | Plays | Example |
|---|---|---|
| **Folio-only text** in Hamlet: words found in the 1623 Folio and not in Q2, between two superscript F's | EMOTHE0010 (1,022 `<code>`, 247 spans) | `O God, <span class="folio"><sup>F</sup>O<sup>F</sup></span> God,` (v. 316) |
| **The Q4 Additions** of *The Spanish Tragedy*: the passages added in the 1602 quarto, a superscript Q4 at each end; several closings are written backwards, and the Spanish version numbers them (Q4.1…) | EMOTHE0111 (en), 0112 (fr), 0218 (it), 0307 (es), 108 in all | `<sup>Q4</sup> [Draws his sword.] </sup>Q4<sup>` |
| **Stage words set apart** with the Folio class | EMOTHE0503 *The Rover* (40 spans) | `<span class="folio">Aside</span>`, `<span class="folio">Exit</span>` |
| **A typo**: one stray `<sup>` | EMOTHE0239 *Mariamne*, v. 623 | `tr<sup>ne du Dieu qui tonne`, for "trône" |

### What the old site did

It printed the strings as HTML, and its stylesheet (`visualizacion_comun.css`) has
`.folio { color: #777; display: none; }`, with no control to show it:

- **Hamlet**: the Folio-only words were hidden, so readers saw the Q2 text ("O God, God,").
- **The Rover**: the "Aside" and "Exit" labels were hidden; asides were marked by their own
  style.
- **The Spanish Tragedy**: the superscript Q4 labels were shown. Where a closing tag is
  written backwards, a `<sup>` stays open and the following text runs on in superscript.
- **Mariamne**: the stray `<sup>` sets the rest of the line in superscript.

### What Playcode does today

The strings are stored as text and shown as text, with spaces around them: 236 lines in 8 plays
(7 corpus plays and a test file, EMOTHE0277). Hamlet v. 316 reads
"O God, `<span class="folio">` `<sup>` F `</sup>` O `<sup>` F `</sup>` `</span>` God,"; a stage
direction of *The Spanish Tragedy* reads "`<sup>` Q4 `</sup>` [Draws his sword.] `</sup>` Q4
`<sup>`".

### Options, per use

- **Hamlet's Folio-only text** (question 5): hide it as before (the reading text is Q2); show
  it set apart (grey, between superscript F's) with a toggle, like the stage directions; or
  turn each passage into a textual variant entry (`F1: O God, O God`), which the `<app>` work
  above already provides and which exports as proper TEI.
- **The Q4 Additions** (question 6): keep the superscript Q4 labels at each end, with the
  backwards closings repaired on import; or mark the whole added passage, which often spans
  several speeches.
- **The Rover's labels** (question 7): make them inline stage directions, or drop them as the
  old site hid them.
- **Mariamne** (question 8): correct the source to "trône".

Whatever is chosen, the importer stops storing these strings as text: an unknown `<code>`
string is refused rather than shown.
