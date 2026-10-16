# Line breaks and prose line numbers

**Status:** design, approved section by section on 2026-10-16. Answers questions 9 and 10 of
`docs/stakeholder/preguntas.html` (answered 2026-10-15), and closes the backlog item "`<lb/>` is
flattened to a space in the play text" and the round-trip rows "Line breaks in prose, letters
and songs" and "Line numbers of prose".

A TEI file marks where a line ends inside a paragraph with `<lb/>`, and, in 40 plays, gives the
number of the printed line that starts there:

```xml
<!-- EMOTHE0053, a song inside a speech -->
<p><stage type="delivery_">[Canta.]</stage>Yo amé en mis primeros años, <lb/>dulce cosa lo juzgué; <lb/>pero casarme, eso no, <lb/>que no me estuviera bien.</p>

<!-- EMOTHE0010 Hamlet 2.2: prose numbered by printed line -->
<p n="1319">Beggar that I am, I am ever poor in thanks, <lb n="1320"/>but I thank you, and sure, dear friends, my thanks <lb n="1321"/>are too dear a halfpenny.</p>
```

Today the importer reads every `<lb/>` as a space and drops `p@n`, so the song runs on, Hamlet's
prose has no numbers (verse 1208 is followed by 1454 on screen), and the TEI export writes
neither back. After this project the song shows in its lines, the numbers show where each
printed line starts, and the export writes back every `<lb/>`, `<lb n>` and `p@n`.

## Decisions

| Question | Answer |
|---|---|
| How are unnumbered breaks shown? | Every one as a new line, the eight plays that copy their book's line ends included (question 10) |
| How are numbered breaks shown? | As the number, inline where the printed line starts; the prose runs on (question 9, option 1, as the old site did) |
| How is an unnumbered break stored? | As `\n`, the way paratexts, the notes on the edition and the witnesses already store a line break. One rule for a line break in every text Playcode holds |
| How is a numbered break stored? | As a marker in `content`, `<lb n="1320"/>`, next to the `<stage>` markers. It is not a line break on screen but a number, so it has its own notation |
| How is `p@n` stored? | As a numbered marker at the very start of the paragraph. The export tells the two apart by position (below) |
| Why not `line_number` for `p@n`? | About a dozen readers take a `line_number` to mean a verse line: the verse count, renumbering on insert and delete, page ranges, statistics |
| Why not a column of number offsets? | The offsets would have to move with every edit, as notes' do, and an editor could not see or correct a number in the text (the inline-stage design rejected spans for the same reason) |
| Why not one element per printed line? | It shatters paragraphs: notes, search hits, paragraph statistics and editing all change |
| Which numbers show? | Every `<lb n>` and every `p@n`, the 44 plays whose `p@n` counts paragraphs (1, 2, 3…) included, as the old site printed them (checked on *Jules César*, EMOTHE0254) |
| A migration? | None. `line_number` stays the verse number only |

## The corpus

The 393 plays, one file per code (`doc/tei_corpus/` winning over a fixture), surveyed on
2026-10-16:

| Where | Unnumbered | Numbered |
|---|---|---|
| Prose paragraphs of the play text | 13,828 in 120 plays | 11,677 in 40 plays: all of them |
| Notes in the play text | 1,010 in 26 plays | 0 |
| Standalone stage directions | 3 in 2 plays | 0 |
| Verse lines | 0 | 0 |
| Front matter (paratexts, already kept as `\n`) | 3,943 in 198 plays; 11 inside italics (EMOTHE0373); 62 in notes | 0 |
| Back matter (paratexts, already kept as `\n`) | 634 in 16 plays | 0 |

- **`p@n`:** 50,041 paragraphs in 84 plays. In the 40 lineated plays it is the number of the
  paragraph's first printed line, running on from the verse; in the other 44 it counts
  paragraphs, often restarting each scene.
- **Number formats:** all whole numbers but 7 `p@n` and 26 `lb@n` (`1311-2`, `2690.1`,
  `3610.01`); kept as written.
- **No two breaks together** in the play text, and **no numbered break opens a paragraph**: the
  six breaks at the start of an element are unnumbered (paragraphs of EMOTHE0144, 0299, 0545;
  italics in 0488's notes).
- **`xml:id` on 15,760 breaks**: still dropped (out of scope).

## Done when

- A re-imported play keeps each unnumbered break as `\n` and each number as a marker, and the
  TEI export writes back `<lb/>`, `<lb n="…"/>` and `p@n` where the file had them.
- The static site, `/plays/:code`, the comparison pages and the HTML, PDF and EPUB downloads show
  each break as a new line and each number inline; the line-number switch hides the numbers on
  the first two.
- `InlineMarkup.plain/1` of a re-imported line has the same length as today's stored text, so
  word counts, search postings and note offsets do not move.
- A researcher types a break with Enter and a number as `<lb n="…"/>`; a malformed marker is
  refused with a message; no edit loses a break.

## Storage

**An unnumbered break is `\n`.** It takes the place of the space an `<lb/>` reads as today, one
character for one: `años, <lb/>dulce` is stored `años,\ndulce`. Allowed in the content of any
element and in a note's body; inside italics (`<<…\n…>>`) and inside an inline stage too.

**A numbered break is `<lb n="…"/>`**, the number a run of letters, digits, `.` and `-`, kept as
written. It stands where the file's `<lb n>` stood, with today's space before it:
`thanks, <lb n="1320"/>but`. It adds nothing to `InlineMarkup.plain/1`, like the `<stage>` tags.

**A paragraph's number is the same marker at the very start of its content:**
`<lb n="1319"/>Beggar that I am…`.

**A note's body** keeps its rule: a blank line between paragraphs, and now a `\n` inside one, as
a paratext's content does.

`InlineMarkup.parts/1` gives a numbered marker a part of its own, `%{number: "1320"}` with no
text, so a renderer can print it and `plain/1` drops it. A `\n` stays in its text part.

`Element.changeset` refuses a `content` holding an `<lb` that is not a well-formed
`<lb n="…"/>`, with a Spanish message in `errors.pot`, as it refuses a malformed `<stage>`.

## Importer

In the play text (the `:mark` reading) and in a note's body:

- `<lb/>` becomes `\n` in place of the space the pieces are joined with, inside italics and
  stages too (`extract_plain_text/2` reads them as well).
- `<lb n="…"/>` becomes the marker, the joining space before it kept.
- `<p n="…">` puts the marker at the start of the paragraph's content.
- `squeeze/1` keeps a `\n` and the spaces it replaces collapse into it; a run of other
  whitespace still becomes one space. Trimming takes spaces, not a `\n`, so the six breaks that
  open an element are kept and come back.
- `plain_length/1`, which gives a note its offset, counts the number marker as zero graphemes
  (it joins `@inline_marker`) and `\n` as one.
- An `<lb>`'s `xml:id` is dropped, as now.

The header still reads `<lb/>` as today; the front and back matter already read it as `\n`
(`lines_text/1`).

## TEI export

- `\n` becomes `<lb/>`, in a paragraph and in a note's `<p>`, the way a paratext's already is.
- A numbered marker at the very start of a prose paragraph becomes the `<p>`'s `n`; any other
  becomes `<lb n="…"/>` where it stands. Two leading markers (`<p n="5"><lb n="6"/>`) come back
  as they were, since only the first is at the very start. A file whose paragraph opens with
  `<lb n="6"/>` and has no `p@n` would come back as `<p n="6">`: the same statement about where
  printed line 6 starts, spelled differently. None of the 393 files does this.
- An editor who types words before a paragraph's leading marker moves the number mid-paragraph,
  and the export writes it as `<lb n>`: the right TEI for a line that now starts there.
- The line is built by `inline_element/3`, one line of mixed content, so whitespace round trips.
  TEI P5 allows `<lb>` in `<p>`, `<note>`, `<stage>` and `<emph>`.

## Renderers

**One renderer for a line break.** Every renderer that walks `InlineMarkup.parts` prints the
`\n` of a text part as `<br>` (`<br/>` in the EPUB's XHTML). The play text, notes and paratexts
then share it: the site's `Components.lines/1` becomes `inline/1` without notes, and the
`white-space: pre-line` the paratexts rely on (`/plays/:code`, the HTML download) is no longer
needed.

**A number** prints as `<span class="pn">1320</span>`, small and muted like the verse numbers,
inline, with no line break; `m5` is added when the number is whole and a multiple of 5. No
anchor: the 44 counter plays restart at 1, so an id built from the number would repeat. Verse
numbers keep theirs.

| Output | `\n` | Number | Switch |
|---|---|---|---|
| Published site | `<br>` | `span.pn` | The All / 5 / Off control: Off hides every `.pn`, 5 the ones without `m5`; the print stylesheet does the same as for verse numbers |
| `/plays/:code`, the comparison pages | `<br>` | `span.pn` | Not rendered when "Line numbers" is off |
| HTML, PDF, EPUB downloads | `<br>` | `span.pn` | Always shown, as the downloads show verse numbers |
| Comparison HTML (`Export.CompareHtml`) | `<br>` | `span.pn` | As the downloads |
| TEI export | `<lb/>` | `<lb n>` or `p@n` | — |
| `/api/v1` | `\n` as stored | the marker as stored, documented like `<stage>` | — |

A hidden inline stage takes its breaks with it. `style.css` gains two rules and stays under its
25 KB budget. The fingerprint and `PdfCache.code_version/0` already cover the modules touched,
so the next Generate rebuilds every play and the PDFs regenerate.

## Statistics and search

Unchanged. They read `InlineMarkup.plain/1`, where a `\n` is whitespace standing where a space
stood and a number is nothing. `Statistics @version` stays; the search index format stays.

## Editor

- The modal form's content field is already a textarea for prose, stage directions and trailers:
  a break is typed with Enter. A one-line hint gives the number's syntax, `<lb n="1320"/>`, in
  Spanish too.
- **The row's quick edit is an `<input type="text">`, and a browser strips the newlines from its
  value**, so saving it would glue the words of a paragraph with a break ("años,dulce"). For an
  element whose content holds a `\n`, the quick edit opens the modal form instead. Verse lines
  keep the one-line field; none holds a break.
- The notes tab is unchanged: its textarea keeps a `\n`, and `Note.paragraphs/1` splits only on a
  blank line.
- Note offsets are carried through edits as now (`update_element/2`).

## Rollout

1. Deploy. Nothing changes in the database: a play shows as today until its file is re-imported.
2. Dev: `mix playcode.import.tei --force`, with the project owner's go-ahead.
3. Production: `mix playcode.fly.reimport prepare` on the whole corpus (its dry run lists any hand
   edit the re-import would lose: stop and look at each), then `run`, about an hour scaled up
   (`docs/production-reimport.md`).
4. Generate from the export page, keeping web traffic going; a full rebuild, as the renderers
   changed. Then check the preview and Deploy.

A re-import replaces the play's elements, divisions and notes: hand edits to its lines are lost.

## Tests

Each is run and seen failing before the code it covers, through the outermost API, per
`CLAUDE.md`; each is proven to bite by breaking the line it covers.

- **`tei_roundtrip_test.exs`:** an unnumbered break in a paragraph, in a note, in an inline stage
  and inside italics; a numbered break; a paragraph's `p@n`; two leading markers; a note just after
  a break keeps its offset; export → import → export changes nothing.
- **`RoundtripTest`:** new count fields, the bare and the numbered `<lb>` inside `<p>` and the
  `p@n`, equal in source and export. The default fixtures hold bare breaks (EMOTHE0776, 0705) and
  `p@n` (0776's 450); the numbered breaks of EMOTHE0281 are in the slow sweep, and the snippet
  tests above cover them on every run.
- **Changeset:** a malformed `<lb` marker is refused, a well-formed one and a `\n` are accepted.
- **Renderers:** `static_site_play_test.exs` (`<br>`, `span.pn`, `m5`, the CSS hook),
  `play_show_live_test.exs` (numbers shown, then gone when the switch is off),
  `export_controller_test.exs` (HTML and EPUB), comparison HTML, and a paratext's break still a
  `<br>` through the shared renderer.
- **Unchanged numbers:** a play with breaks and numbers gives the same `InlineMarkup.plain/1`
  length, word count and search postings as the same play with spaces.
- **Editor:** a break typed in the modal survives a save; the quick edit of a paragraph with a
  break opens the modal; the hint is on the form.
- **Schema:** the slow suite validates an export holding `<lb>` in `<p>` and in `<note>`
  (`tei_validator_test.exs`).

## Order

1. `InlineMarkup` (the number part, `plain/1`, `well_formed?/1`) and the changeset.
2. Importer and TEI export, with the round-trip tests and the real-fixture counts.
3. Renderers: the shared `<br>`, the number, the switch; site, live page, downloads, comparison.
4. Editor: the hint and the quick edit.
5. Docs: `CLAUDE.md` (the TEI mapping, the content markers), the round-trip page's two rows,
   `docs/backlog.md` to `docs/history.md`, questions 9 and 10 marked built, this spec's status.

## Out of scope, and known limits

- **`xml:id` on `<lb>`** (15,760): dropped, as now; the backlog item on `xml:id`s stays.
- **The 11 breaks inside italics** in EMOTHE0373's front matter: `lines_text/1` does not reach
  them; a paratext question, not this one's.
- **The 62 notes of the front matter**: not read at all (backlog, *Front-matter notes dropped*).
- **Prose in its printed lines** (question 9, option 2): the stored marker allows it later with a
  renderer change only.
- **Content search in the editor** matches the marker text, as it does `<stage>`.
- **The Word importer** produces no breaks and is not touched.
