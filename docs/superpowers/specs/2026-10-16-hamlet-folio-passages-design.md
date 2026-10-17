# Hamlet's Folio passages: design

Status: implemented 2026-10-16 to 2026-10-17 (commits 8f11454, 03a4932 the marker; 3ed177c, acf9815 a passage inside one element;
2be2088, a111e47, ae54006 passages across elements, and v. 2632; 6d04562, 025a022 the play page; b8de76e, 64594b6 the site;
0963c94, 348952a the downloads; then the editor's hint and the docs). One departure: the design counts v. 2632 among the 6
passages in a stage direction, but it sits inside an inline stage direction in a paragraph, and is stored and written back as
three stages (`docs/backlog.md`).

Designed 2026-10-16, from the project's answers to questions 5 (hidden, with a switch
showing them in grey, as before) and 36 (the proposed `<app type="folio">`, yes for now) of
`docs/stakeholder/preguntas.html`. Question 37, the form of a passage that crosses elements,
is still open; this design writes those back in the file's own form until it is settled. The
background is `docs/tei-apparatus-and-code.md`, *`<code>`: literal HTML in the text*.

## The problem

Hamlet (EMOTHE0010) takes Q2 as its base text and adds the words only the 1623 Folio prints,
each passage between two superscript F's, typed as HTML in `<code>`:

```xml
O God, <code>&lt;span class="folio"&gt;</code><code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>O<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code><code>&lt;/span&gt;</code> God,
```

Playcode stores the strings as text, so readers see "O God, `<span class="folio">` `<sup>` F
`</sup>` O …", and the export writes them back as text, not as `<code>`.

## What the file holds (read 2026-10-16)

- 264 `<sup>…</sup>` labels: 263 "F" and one "and" (v. 3315, `Oh!<sup>and</sup>`), which
  closes the passage it ends. Taken in order, they pair into **132 passages**.
- 247 `<span class="folio">` and 247 `</span>`. Every word inside a passage is inside a span
  and every word inside a span is inside a passage, but for one `</span>` set too early
  (v. 3057, `<span><sup>F</sup></span>and more strange<sup>F</sup></span>`); v. 1322 opens a
  span twice. The spans repeat what the labels say, and are not read.
- **119 passages lie inside one element**: 56 in a verse line, 56 in a paragraph (4 across a
  printed line's `<lb/>`), 6 in a stage direction, 1 inside a `<seg type="aside">`. Both
  labels are children of the same element.
- **13 cross elements**, from 2 to 28 elements, the longest 14 speeches. Both labels sit
  directly in a line, paragraph, stage direction or speaker label. Inside them: whole
  speeches, their speaker labels Folio-only ("{F hamlet}"), lines, paragraphs, stage
  directions, an inline stage ("Within").
- No passage holds a note, an `<app>` or italics. No two passages touch: Q2 words always
  stand between them.
- A passage may start at a speaker label and end inside the speech's paragraph, so in the Q2
  text the rest of the paragraph has no label (v. 3224, "I'll put another question to
  thee"), as on the old site.

## Design

### Storage: a `<folio>` marker

A passage is a marker in the text it sits in, like `<aside>`: `<folio>…</folio>`, the words
only the Folio prints. A passage that crosses elements is a marker in each of them, with the
part it is: `part="I"` its start (runs to the end of the element's text), `part="M"` the
whole element, `part="F"` its end (from the start of the element's text):

```
O God, <folio>O</folio> God,
him and he her. <folio part="I">She kneels and makes show of protestation unto</folio>
<folio part="F">him.</folio> He takes her up and declines his head upon her neck; he
```

It may stand in a verse line's, a paragraph's or a stage direction's `content`, and in a
speech's `speaker_label` (`<folio part="I">hamlet</folio>`). No column and no migration.

Rules, held by `Element.changeset` as the other markers are:

- closed, flat (no folio in a folio), holding words;
- outside italics and stage markers (it may hold them, and printed lines' markers and line
  breaks); it may sit inside an `<aside>` but holds none;
- `part`, when given, is `I`, `M` or `F`; an `I` marker ends the text, an `F` marker starts
  it, an `M` marker is the whole text (a paragraph's own number, `<lb n>` at its very start,
  may come before an `F` or `M` marker).

`InlineMarkup.plain/1` keeps the Folio words (note offsets, search), and so does `spoken/1`:
the statistics count them, as they do today. A Q2-only count is out of scope.

### Import

In a file with superscript labels (Hamlet), before the text is read:

- the `<code>` span strings are dropped;
- the labels are taken in document order, alternately opening and closing a passage; a
  label's own text is dropped when it is "F" and kept, before the passage's end, when it is
  not (v. 3315 reads `<folio>Oh! and</folio>`, question 39);
- a passage opened and closed in one element becomes `<folio>…</folio>` there; one still
  open at the end of its element becomes `part="I"` there, `part="M"` in each element
  wholly inside it (line, paragraph, stage direction, speaker label), and `part="F"` where
  it closes.

The markers are written into the text nodes either side of a label, so the words keep the
spacing the file gives them ("Very like<folio>, very like</folio>. Stayed it long?").

In any file, an `<app type="folio">` of exactly the proposed shape, an empty `<lem
wit="#Q2"/>` and one `<rdg wit="#F1">`, is the marker `<folio>` around the reading's
contents. Any other `<app type="folio">` stays an entry of the critical apparatus, which
loses nothing. A file with no superscript label (The Rover, the Spanish version of The
Spanish Tragedy) drops the wrappers and keeps their words, as now.

### Export

- `<folio>…</folio>`: `<app type="folio"><lem wit="#Q2"/><rdg wit="#F1">…</rdg></app>`, the
  reading holding the marker's contents (a stage, a printed line's `<lb n>`, a break).
- A marker with a `part`: the file's own form, until question 37 is settled:
  `<code>&lt;span class="folio"&gt;</code>`, then `<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>`
  if the passage starts here (`I`), the words, the closing F if it ends here (`F`),
  `<code>&lt;/span&gt;</code>`. One span per element, around its whole piece.

Exporting, importing and exporting again gives the same file. Hamlet's export writes the
two damaged spots (vv. 3057 and 1322) mended.

### What readers see (question 5)

- **The play page and the site**: a switch, "Folio interpolations" ("Interpolaciones del
  Folio"), beside the others, only on a play with Folio passages, **off by default**; the
  site remembers it as it does the others. Off: the passages are not there; an element left
  with no words is not there either (a line, with its number; a paragraph; a stage
  direction; a speaker label; a speech or a line group all of whose parts are gone). On:
  the passages in grey (muted text, contrast kept), a superscript F where each passage
  starts and where it ends (not at the inner edges of a passage that crosses elements). A
  note inside a passage goes with it.
- **Independent of "Show variant readings"**: that setting is about the asterisks; Hamlet's
  stays off, and its Folio switch is there.
- **The comparison page**: no switch; the passages are hidden (Q2's text).
- **The downloads (HTML, PDF, EPUB) and the comparison download**: no switch, so the
  passages are printed, in grey between their F's, so that nothing is lost (question 38,
  decided by Playcode). The comparison download prints speaker labels through the same
  renderer, not escaped as text.

### Editing

The content editor shows and edits the markers as it does `<aside>`, with a hint ("Words
only the Folio prints: <folio>…</folio>"). A malformed marker is refused with "has a Folio
marker that is not well formed".

### Questions for the project

- **38, decided by Playcode**: the downloads print the passages in grey between their F's.
- **39, for Hamlet's editor**: v. 3315 closes its passage with `<sup>and</sup>`: is the
  Folio passage "Oh! and", or "Oh!" with the closing F mistyped? Playcode reads "Oh! and"
  until told. The two span slips (vv. 3057, 1322) need no answer: the labels say where the
  passages run, and the export writes them mended.

## Out of scope

- Statistics of the Q2 text alone.
- The TEI form of a passage that crosses elements (question 37).
- The Q4 Additions of *The Spanish Tragedy* (question 37).
- Hamlet's variants (`show_variants` stays off).
- A Folio passage across a division boundary, or one whose label sits inside an inline
  element of a passage crossing elements: none in the file.
