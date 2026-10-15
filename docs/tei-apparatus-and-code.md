# Critical apparatus (`<app>`) and literal HTML (`<code>`) in the TEI corpus

Analysis of 2026-10-10, corrected 2026-10-11, decided 2026-10-16, from the 370 production TEI files (`doc/tei_corpus/`, git-ignored), the
dev database after a full re-import, and the old EMOTHE pages
(`https://emothe.uv.es/biblioteca/textosEMOTHE/<file>.php`) with their stylesheet. Both are
listed in `backlog.md`, *Found by the corpus round trip*. The questions only the project can
answer are 1 to 8 of `stakeholder/preguntas.html`, the project's running list of questions;
`stakeholder/variantes-y-codigo.html` is their background. All but 7 were answered on
2026-10-16; the design below follows the answers.

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
below). The 4 are the prose entries at v. 1319 and vv. 3256-3257.

Hamlet's apparatus looks unfinished (checked 2026-10-11). 4 of the 94 are copies of an entry
inside the editor's own `<note>` (v. 19's sits in the note's `<term>` and its `<p>` too, and so
does v. 313's); of the 90 in the text, 81 are in the first 313 lines (1.1 and 1.2). Damage: at
v. 189 the entry for "an ... a" was inserted after every letter "a" of the line
(`With a<app/>n a<app/>uspicious a<app/>nd a<app/> dropping eye`); v. 313's and one at
v. 240 are empty `<app>`s; three readings carry `wit="#"`; one `to` points at
`#em0010-en-0000`, which does not exist. Question 2.

### Design (decided 2026-10-16)

1. **Import**: the whole `<app>` leaves the line's text, as a `<note>` does, so the line reads
   as the old site showed it. The entry is stored at its offset, after the word it annotates.
2. **A kind of note**: a `play_notes` row of a new type, `variante` ("Textual variant",
   "Variante textual"), keeping the `<app>`'s `n`, its type in a new `variant_type` column
   (stored and written back, never shown), its own note as the body, its `to` when it has
   one, and its readings in a new `readings` field (`embeds_many`, JSONB: `lemma` true or
   false, `wit` as written, `text` with `<<italics>>`, the reading's own `note`). Offsets,
   the carrying of offsets through edits, pop-ups and the content-version trigger are the
   notes' own.
3. **Display** (questions 1, 3 and 4): a superscript `*` after the word, apart from the
   numbered notes, opening the readings as the old site listed them, each siglum followed
   by a short name worked out from what it names: a witness's place and year
   ("P3 (Madrid, 1653)", "MP (1735)"), a modern edition's editor's surname and year
   ("H (Hartzenbusch, 1860)", "BRA (Bruster and Rasmussen, 2009)"), the year alone for a
   siglum that is already the surname ("Dyce (1831)"), the siglum alone when it names
   nothing. Shown by default, with a "Variants" switch to hide them, on the play page and
   the site. The downloads, which have no pop-ups, list each act's variants after its
   notes.
4. **Hamlet** (question 2): a per-play setting, "Show variant readings", on by default, off
   for EMOTHE0010 until its editor has finished; it hides the asterisks only, never the
   Folio switch. Its entries, damaged ones included, are imported as they are and written
   back. When it is switched on, its marker (the old site's `F` or `*`) is decided then.
5. **Copies inside notes**: 51 of the 52 `<app>`s inside a `<note>` (EMOTHE0187 34, 0560 12,
   0010 4, 0530 1) repeat the line's entry, same `n`, same readings. They are read as that
   entry: the note keeps its words ("an learn me that"), and the export writes the entry
   once, in the line. The 52nd (EMOTHE0530 v. 141, `n="496"`) exists only in the note on
   "ne"; it moves into the line as a variant after that word.
6. **Ranges**: the 11 entries with `to="#id"` show their asterisk where they sit, the pop-up
   prints the note as written (the editors name the range in it: "vv. 13-14 Estos dos
   versos…"), and `to` is kept and written back.
7. **TEI round trip**: the export writes `<app type n to><lem wit>…</lem><rdg wit>…</rdg>
   <note>…</note></app>` back at the note's offset from the stored data, as `build_note/1`
   writes a `<note>` today. A test imports, exports, re-imports and exports again and
   expects the same file, as for notes and inline stages.
8. **Editor**: a variant is edited in the note editor, with its readings as a list (witness,
   reading, comment) to add to, change or remove.

## `<code>`: literal HTML in the text

### In the corpus

1,211 `<code>` elements in 7 plays, holding only four strings: `<sup>` (315), `</sup>` (314),
`<span class="folio">` (291), `</span>` (291). They sit in `<p>` 490, `<l>` 446, `<stage>`
187, `<speaker>` 78, `<seg>` 6, `<head>` 4. They spell out HTML that the old site printed as
it was. Four different uses:

| Use | Plays | Example |
|---|---|---|
| **Folio-only text** in Hamlet: words found in the 1623 Folio and not in Q2, between two superscript F's | EMOTHE0010 (1,022 `<code>`, 247 spans) | `O God, <span class="folio"><sup>F</sup>O<sup>F</sup></span> God,` (v. 316) |
| **The Q4 Additions** of *The Spanish Tragedy*: the passages added in the 1602 quarto, a superscript Q4 at each end; the closings are written backwards in English and Italian (all) and French (4 of 7); the Spanish version numbers only the first (Q4.1), writes its closings correctly, and wraps Additions 2-5 in the Folio class | EMOTHE0111 (en), 0112 (fr), 0218 (it), 0307 (es), 108 in all | `<sup>Q4</sup> [Draws his sword.] </sup>Q4<sup>` |
| **Stage directions set apart** with the Folio class, each inside a TEI `<stage>`: "Aside" 28, "Aside to Hellena", "within" 5, "Exit" 2, "To Hellena", "To Willmore", and the names "Diego" and "Boy" inside two entrances | EMOTHE0503 *The Rover* (40 spans) | `<stage type="delivery"><span class="folio">Aside</span></stage>` |
| **A typo**: one stray `<sup>` | EMOTHE0239 *Mariamne*, v. 623 | `tr<sup>ne du Dieu qui tonne`, for "trône" |

### What the old site did

It printed the strings as HTML, and its stylesheet (`visualizacion_comun.css`) has
`.folio { color: #777; display: none; }`. Only Hamlet's page has a control to show it: the side
panel's "Folio interpolations: Show" (`funcionFolio()` in `js/libreriaFunciones.js`).

- **Hamlet**: the Folio-only words were hidden by default, so readers saw the Q2 text ("O God,
  God,"); the switch showed them in grey.
- **The Rover**: the 40 directions were hidden, with no switch. Little was lost with the asides,
  marked by their own style; the rest was missing ("Enter Antonio and his page ; Antonio
  knocks…").
- **The Spanish Tragedy**: the opening Q4 was printed in superscript. A backwards closing
  (`</sup>Q4<sup>`) printed "Q4" full size; its stray `<sup>` mostly fell at the end of the
  line, so only once did text run on in superscript (French, after the third Addition: "Bon
  voyage, Messieurs !…"). The Spanish version's Folio spans open inside a line and are closed
  by the browser at its end, so the first line of Additions 2-5 was hidden, with its Q4 and the
  translator's note announcing it.
- **Mariamne**: the stray `<sup>` sets the rest of the line in superscript.

### What Playcode does today

The strings are stored as text and shown as text, with spaces around them: 236 lines in 8 plays
(7 corpus plays and a test file, EMOTHE0277). Hamlet v. 316 reads
"O God, `<span class="folio">` `<sup>` F `</sup>` O `<sup>` F `</sup>` `</span>` God,"; a stage
direction of *The Spanish Tragedy* reads "`<sup>` Q4 `</sup>` [Draws his sword.] `</sup>` Q4
`<sup>`".

### Decided, per use (2026-10-16)

The three uses that mark a difference between printed witnesses become `<app>`s, told apart
by `type`, so variants, Folio passages and Additions are read and written by one path. The
importer reads the old HTML forms and the new TEI forms alike, and refuses an unknown
`<code>` string rather than showing it.

- **Hamlet's Folio-only text** (question 5): hidden, with a "Folio interpolations" switch
  showing it in grey between superscript F's, as before. All 247 passages sit inside one
  element, so each is an `<app>` in the line, the Folio words a reading the base text (Q2)
  lacks: `O God, <app type="folio"><lem wit="#Q2"/><rdg wit="#F1">O</rdg></app> God,`. The
  form is proposed to Hamlet's editor, who is re-encoding the variants and the Folio
  interpolations, so that his file and Playcode's export agree.
- **The Q4 Additions** (question 6): a line in the margin beside the whole passage and a
  superscript Q4 at each end, in all four versions, wherever the text is printed (the play
  page, the site, the downloads). An Addition crosses speeches and scenes, so it is marked
  start to end, the way the 11 range entries already are: `<anchor xml:id="q4-1"/>`…the
  passage…`<anchor xml:id="q4-1-end"/><app type="addition" from="#q4-1" to="#q4-1-end">
  <lem wit="#Q4"/><rdg wit="#Q1"/></app>`; the printed "Q4" is the `lem`'s witness. Every
  mark sits at the start or end of a line, stage direction or heading, so an Addition is a
  run of whole elements. The backwards closings are mended, the Spanish version's "Q4.1"
  prints as "Q4", its Folio wrappers are dropped, and the English and Italian italics stay.
  `<addSpan>` was considered and set aside: it marks text added into one document, while an
  Addition is a difference between printings.
- **The Rover's directions** (question 7, waiting on the play's digital-text editor, David
  Amelang): until he answers, shown as the stage directions they are, the HTML dropped; the
  mark stays in the project's file.
- **Mariamne** (question 8): "trône". Our copy of the file is corrected and the play
  re-imported, and the project gets the same correction for its own file.

### Working order

The project's TEI files stay the master while Playcode is tested against the corpus;
Playcode's export takes over only once it carries every feature of the files. The HTML
fragments come first (236 lines show tags today), then the variants. The site is deployed
as it stands, and each fix reaches it with the next Generate and Deploy.
