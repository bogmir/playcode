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

Moved to its own spec, `superpowers/specs/2026-10-16-critical-apparatus-design.md`, with what a
re-reading of the corpus added (the 62 copies inside notes, the readings' notes, the empty
entries) and how each part is stored, written back and shown.

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
importer will read the old HTML forms and the new TEI forms alike. The TEI forms for the Folio
passages and the Additions are proposals to the editors, questions 36 and 37. Question 36 was
answered on 2026-10-16 (yes, for now); question 37 is open.

- **Hamlet's Folio-only text** (question 5; the encoding, question 36): hidden, with a "Folio
  interpolations" switch showing it in grey between superscript F's, as before. A passage
  inside one element is an `<app>` in the line, the Folio words a reading the base text (Q2)
  lacks: `O God, <app type="folio"><lem wit="#Q2"/><rdg
  wit="#F1">O</rdg></app> God,`. Stored, when built, as a marker in the line like `<stage>`
  (`<folio lem="#Q2" rdg="#F1">O</folio>`), so note offsets keep working; the word count is
  Q2's and search still finds the Folio words. Still open: whether the downloads, which have
  no switch, print them. **Correction (2026-10-16): not every passage sits in one element.**
  The 247 `<span class="folio">`s are one per element; a passage runs from one superscript F
  to the next, about 131 passages of which some 42 cross elements, the longest 26 speeches
  (115 spans have no F beside them: the inner elements of such a passage). So a long passage
  needs the start-and-end form of the Additions, and so does the reading of today's file.
  The file also holds 263 F's and one `<sup>and</sup>`, so one F is unpaired. Hamlet is left
  for later.

  **Question 36, answered 2026-10-16:** yes, for now, as better than what there is.
  `type="folio"` means an interpolation the web edition can show or hide, which is the
  switch above. The editor would judge it better on seeing how the whole apparatus is
  encoded. So the passages inside one element can be built as proposed; the long ones share
  the Additions' form, which question 37 leaves open.

  **Built 2026-10-16 to 17** (`superpowers/specs/2026-10-16-hamlet-folio-passages-design.md`,
  `history.md`), with these departures from the plan above. A full read of the file counts
  264 labels, 263 "F" and one "and", which pair into **132 passages: 119 inside one element,
  13 across elements** (2 to 28 elements, the longest 14 speeches), where the first count said
  131 and 42. The marker is a plain `<folio>…</folio>` in the text it sits in, with no
  attributes but `part="I|M|F"` where a passage crosses elements (`I` its start, `M` a whole
  element, `F` its end), in a line's, paragraph's or stage direction's text or a speech's
  speaker label. Unlike the plan, the word count includes the Folio words (search finds
  them too), and the downloads, which have no switch, print the passages in grey between
  their F's (question 38).
  - *Read:* in a file with superscript labels, the labels in document order alternately open
    and close a passage; an "F" label's text is dropped, any other word is kept before the
    passage's end (v. 3315, `Oh!<sup>and</sup>`, reads "Oh! and": question 39). The
    `<span class="folio">` strings are not read, so the slips in v. 3057 (a `</span>` too
    early) and v. 1322 (a span opened twice) change nothing. An `<app type="folio">` of exactly
    the proposed shape, in any file, is the same marker; any other stays a variant.
  - *Written back:* a passage inside one element as that `<app type="folio">` (119 in
    Hamlet); one across elements in the file's own form, one span to an element and an F at
    its start (`I`) and end (`F`), until question 37 settles a TEI one. Exporting, importing
    and exporting again gives the same file, with the two damaged spots mended. The export
    pairs a crossing passage's pieces in reading order, not by their stored parts alone: two
    neighbouring texts join when the first ends in an `I` or `M` piece and the second starts
    with an `M` or `F` one, and a piece joined on neither side goes out as the `<app>`. So an
    edit inside a passage (a piece deleted, a text put between two) cannot unbalance the file.
  - One passage, v. 2632 (`[Calling within<F> “Hamlet, Lord Hamlet!”<F>]`), sits inside an
    inline stage direction in a paragraph. It is stored and written back as three stages
    (before, inside the passage, after), each with the stage's type where the source has one.
  - Still open: the Additions and the TEI form of the 13 long passages (question 37); the
    statistics of the Q2 text alone (`backlog.md`).
- **The Q4 Additions** (question 6; the encoding, question 37): a line in the margin beside
  the whole passage and a superscript Q4 at each end, in all four versions, wherever the text
  is printed. An Addition crosses speeches and scenes, so it is marked start to end:
  `<anchor xml:id="q4-1"/>`…the passage…`<anchor xml:id="q4-1-end"/><app type="addition"
  from="#q4-1" to="#q4-1-end"><lem wit="#Q4"/><rdg wit="#Q1"/></app>`; the printed "Q4" is the
  `lem`'s witness. `<addSpan>` was set aside: it marks text added into one document, while an
  Addition is a difference between printings.

  **Question 37, 2026-10-16: open.** The edition's base text is Q1, so the `<lem>` must name
  Q1, not Q4 (`<lem wit="#Q1"/><rdg wit="#Q4"/>`), and two empty elements in a row are
  unusual; the form could serve for the moment, but the editors are checking the TEI
  Guidelines and the TEI mailing list. Naming Q1 brings out the question underneath: with
  `from` and `to`, TEI reads the words between the anchors as the lemma's, and Q1 lacks
  them, since the edition prints Q4's words inside a Q1 text. Whatever form they settle on,
  the printed "Q4" can no longer be "the `lem`'s witness": it is Q4's, wherever the form
  names it. Nothing is built for the Additions until they answer.

  The marks, read in full on 2026-10-16: 14 in English, 14 in French, 12 in Italian, 10 in
  Spanish, a start and an end for every Addition. One rule tells them apart: a "Q4" followed
  by text starts an Addition, a "Q4" followed by the end of its element or a `<lb/>` ends one;
  the direction the tags are typed in says nothing. A mark may hold a note (`Q4<note>…</note>`,
  the start of the English Addition 5). Most sit at the edge of a line or stage direction; two
  start in a scene heading ("[SCENE XIIA]", English and French), one in a speaker label
  (French), and three French ones in the middle of a prose paragraph, at a `<lb/>`. So the
  planned storage is a start and an end marker at the exact place in the text, the margin
  line worked out by walking the elements in reading order (a French paragraph an Addition
  starts inside gets the line in full); a flag per element would move those Q4s to the
  paragraph's edge.
- **The Rover's directions** (question 7, waiting on the play's digital-text editor, David
  Amelang): until he answers, shown as the stage directions they are, the HTML dropped; the
  mark stays in the project's file. In a file that marks no Folio passage (no superscript F
  anywhere) the importer drops every `<span class="folio">` wrapper and keeps its words: The
  Rover's 40 and the Spanish version's 4 around Additions 2-5. Hamlet's are left as they are.
- **Mariamne** (question 8): "trône". Our copy of the file is corrected and the play
  re-imported, and the project gets the same correction for its own file.
- **An unknown `<code>` string** will be refused on import, once the Folio passages and the
  Additions are read; until then they are its only other uses.

### Working order

The project's TEI files stay the master while Playcode is tested against the corpus;
Playcode's export takes over only once it carries every feature of the files. Of the HTML
fragments, The Rover's and the Spanish wrappers and Mariamne came first; Hamlet's Folio passages
followed (2026-10-16 to 17), the ones inside one element as `<app type="folio">` (question 36)
and the long ones in the file's own form; the Additions, and a TEI form for the long passages,
wait on question 37. The variants needed neither and were built first (2026-10-16). The site is
deployed as it stands, and each fix reaches it with the next Generate and Deploy.
