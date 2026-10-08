# Inline stage directions

**Status:** design, 2026-10-09. The follow-up named in `2026-10-08-in-text-notes-design.md`
("Out of scope") and the "Inline `<stage>` is flattened" gap in `CLAUDE.md`.

A `<stage>` inside a verse line or a prose paragraph is a stage direction in the middle of
spoken text:

```xml
<l xml:id="fr-0140" n="0137"><stage xml:id="em0008-fr-st-0004">(A Léonor.)</stage>Allez l'entretenir en cette galerie.</l>
```

(EMOTHE0008 Le Cid.) Today the importer reads it as plain words of the line. The line is
stored as `(A Léonor.) Allez l'entretenir en cette galerie.`, the TEI export writes those words back as bare text, so
`<stage>` and its `type` are lost, and no page can set it apart or hide it with the
"Stage directions" toggle. After this project the line keeps the stage as a marker, every
page shows it in italics and hides it with the toggle, the TEI export writes `<stage>` back
where it was, and statistics and search count it as a stage direction.

## Decisions

| Question | Answer |
|---|---|
| How is the stage kept apart from the line's words? | A marker in `content`, next to `<<italics>>`: `<stage type="delivery">…</stage>`. No table, no migration, no offsets to carry |
| Why not a table of spans, like notes? | A span needs two offsets that survive edits inside it, and splitting around both notes and italics, for one attribute (`type`). Not worth it |
| Why not separate `stage_direction` elements? | A mid-paragraph stage (964 in the prose) would shatter the paragraph, a mid-verse one (10) the line |
| What do readers get? | Italic, hidden by the toggle, on the static site, `/plays/:code` and the downloads; written back by the TEI export; counted in statistics and search; editable in the content editor |
| Asides (`<stage type="delivery">Aparte</stage>`)? | Unchanged. The importer drops the stage and flags the line `is_aside`; the TEI export writes `<seg type="aside">`, not the stage. Logged as a known gap |
| FileMaker? | Not a slice. The stage directions are in the TEI files |

## The corpus

Every fixture, tracked and `tei_files/`, one file per play code (82 plays), surveyed on
2026-10-09. A stage that is a direct child of `sp`, `lg` or a division already becomes its own
`stage_direction` element and is not counted here.

- **3,148 inline stages in 59 plays**: 2,884 plain, in 52 plays, and 264 asides, in 22.
- **Where (plain):** in `<p>` 1,803 (839 at the start of the paragraph, 964 in the middle, all in
  Italian and Spanish prose), in `<l>` 1,081 (1,071 at the start of the line, mostly French
  verse; 10 in the middle).
- **242 lines hold more than one stage.**
- **Attributes:** `xml:id` on every one, `type` on 737: `delivery` 580, `delivery_` 62 (a
  spelling variant, kept as written), `business` 50, `exit` 26, `entrance` 15, `mixed` 4. The
  other 2,147 have none.
- **Contents:** text; one holds a `<note>`; a few hold a `<code>` element, read as text.
  None holds a stage, none sits inside `<emph>`, `<hi>` or `<seg>`, none is empty.

## Done when

- A re-imported play's lines keep each inline stage as a marker, and the TEI export writes it
  back as `<stage>` inside the `<l>` or `<p>`, with its `type`.
- The static site, `/plays/:code` and the HTML, PDF and EPUB downloads show it in italics; the
  toggle hides it on the first two.
- `total_stage_directions` includes it, `words` does not, and a search for a word that occurs
  only in an inline stage is a "Stage directions" hit.
- A researcher can add, change or remove one in the content editor, and a malformed marker is
  refused with a message.

## The marker

`<stage>…</stage>`, or `<stage type="delivery">…</stage>` with a type. The type is a run of
letters, digits and `_`, kept as written. A stage is flat: no stage in a stage. Italics may sit
inside one (`<stage>a <<b>> c</stage>`); a stage inside italics is not allowed.

`InlineMarkup.parts/1` gives each part a `stage`: `nil` outside a stage, else
`%{type: binary | nil, run: integer}`, `run` counting the stages in the text, so two touching
stages stay two. `plain/1` drops the stage tags as well as `<<` and `>>` and keeps the stage's
words, so note offsets, search text and the offset-carrying on edits do not move.

`parts/2` places a note as it places one in italics: a note inside a stage's text splits the
stage part and carries the same `stage`; a note at the end of the stage's text follows it,
outside. A stage that ends in a note therefore exports with the note after it: the same
offset, so the second export equals the first.

`Element.changeset` refuses a `content` holding a `<stage` or `</stage>` that is not part of a
well-formed, unnested marker with a valid type. The message has a Spanish translation in
`errors.pot` (`error_translations_test.exs` fails without one).

## Importer

Under `:mark` reading (the play text; the header and front matter still paste), a `<stage>`
child of an `<l>`, `<p>` or `<seg>` is read as `<stage type="…">` + its text + `</stage>`. The
wrap goes on children, never on the element being read, so a standalone `<stage>` read by
`import_stage_direction/5` is not wrapped.

- Italics and note marks inside the stage are read as now.
- Spacing is today's: the pieces of an element join with a space, so a line's words are the
  ones stored today.
- A stage with no text is dropped. Its `xml:id` is dropped, as for standalone stage directions.
- `plain_length/1`, which gives a note its offset, counts a stage's tags as markers one at a
  time, as it counts `<<` and `>>`. A note inside a stage is read while the stage is still open
  (`<stage>foo`), so `InlineMarkup.plain/1` cannot do it.
- An aside line still drops its delivery stage (`verse_line_content/2`), including a second
  stage on the same line (2 lines in the corpus).

## TEI export

`inline_nodes` wraps each run of stage parts in `<stage type="…">`, with italics and notes
nested inside it, as it nests a note inside `<emph>`. The line is built by `inline_element/3`
as one line of mixed content, so the whitespace round trips. TEI P5 allows `<stage>` in `<l>`
and `<p>`; the slow suite validates against the schema.

## Renderers

Each renderer walks `InlineMarkup.parts`. A stage part is wrapped; a part split by a note or
italics is wrapped piece by piece.

- **Static site:** `<span class="sdi">`, italic in the muted ink of `.sd`.
  `body[data-sd="off"] .sdi { display: none }` makes the existing toggle hide it. A note marker
  inside a hidden stage goes with it; its endnote stays on the page, so a number can be
  missing. A standalone stage direction with a note already does this.
- **`/plays/:code`:** `inline_content` takes `show_stage_directions`; the stage parts are
  skipped when it is off, italic when on.
- **HTML, PDF, EPUB:** `NoteMarkup.part/2` wraps a stage part in `<span class="stage">`;
  each document's CSS makes it italic. No toggle.
- **Comparison HTML:** goes through `NoteMarkup.inline(content, [], :html)`, so no marker
  appears as literal text. This also turns its `<<…>>` into `<em>`, closing that gap. If a
  test pins the brackets, it is updated with a comment saying why. It still shows no notes.
- **`/api/v1`:** `content` stays raw, `<<…>>` and markers included. Documented.

The fingerprint already covers the export modules and `InlineMarkup`; `PdfCache.code_version/0`
already covers `NoteMarkup` and `InlineMarkup`. `style.css` stays under its 25 KB budget.

## Editor

No new form: a stage is edited as text, like italics. The content field of the element form
gets a one-line hint with the syntax, in Spanish too. A refused marker shows as the changeset
error, in the modal and in the row's inline edit. The preview tab shows the result.

## Statistics

- `total_stage_directions` adds the inline stages to the standalone elements.
- `Metrics.words/1` counts the words outside any stage. Today the pasted stage text counts as
  spoken; counted raw, the marker's own `stage`, `type` and `delivery` would count too.
- `Statistics @version` goes to 3, so the cache recomputes.

The published numbers move for re-imported plays: fewer words, more stage directions.

## Search

The index format does not change. For each line, a word that occurs in the stage parts and in
no spoken part gets the stage flag; any other word keeps flag 0, so there is still one posting
per word and line. A result row shows the whole line as before. The "Stage directions" facet
now finds `(tout bas)` inside a verse line. The fingerprint covers `Search`, so the next
Generate rebuilds the index.

## Rollout

A deploy changes nothing in the database: a play renders as today until its TEI file is
re-imported. Dev: `mix playcode.import.tei --force`, run only with the project owner's go-ahead.
Production: re-upload the TEI files at `/admin/plays/import`. If the in-text notes re-upload has
not happened yet, it covers both, once, before the first Generate. A re-import replaces the
play's elements, divisions and notes: its hand edits are lost.

## Tests

Each is run and seen failing before the code it covers. Through the outermost API, per
`CLAUDE.md`.

- **`tei_roundtrip_test.exs`:** a stage at the start, middle and end of a verse line and of a
  paragraph; typed and untyped; two in one line, touching and apart; a note inside one; an
  export → import → export fixpoint.
- **`RoundtripTest`:** a new count field, the `<stage>` children of `<l>` and `<p>`, equal in
  source and export. A fixture with inline stages joins the default set, as `EMOTHE0705` did
  for notes; the slow sweep covers all.
- **`InlineMarkup`:** parts, `plain/1` and the note placement around a stage; the changeset's
  refusals.
- **Renderers:** `static_site_play_test.exs` (marker, toggle hook), `play_show_live_test.exs`
  (shown and hidden), `export_controller_test.exs` (HTML, EPUB), comparison HTML.
- **Statistics and search:** the totals, a spoken-only `words`, and the posting flag for a
  stage-only word against a word that is also spoken.
- **Editor:** the hint is on the form, and a malformed marker is refused on save and on inline
  edit.
- **Prove each bites:** break the line it covers, watch it go red, put it back.

## Order

1. `InlineMarkup` (`parts`, `plain`) and the changeset's validation.
2. Importer and TEI export, with the round-trip tests and the real-fixture count.
3. Renderers: static site, live page, downloads, comparison HTML.
4. Statistics and search.
5. Editor hint.
6. Docs: `CLAUDE.md`, `docs/static-site-improvements.md`, this spec's status.

## Out of scope, and known limits

- **Aside stages.** The stage text of the 264 aside stages is not kept or exported, and a second
  stage on an aside line is dropped with it.
- **`xml:id`** of an inline stage is not kept, as for standalone stage directions.
- **A note at the end of a stage** exports after it.
- **A hidden stage with a note** leaves a gap in the visible numbers.
- **Content search** in the editor matches the marker text too (a search for "stage" finds a
  line with a marker).
- **The Word importer** produces no inline stages and is not touched.
