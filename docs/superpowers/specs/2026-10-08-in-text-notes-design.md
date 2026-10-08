# In-text notes

**Status:** design approved 2026-10-08; not yet implemented. Item 1 of
`../../static-site-improvements.md`, and the open "In-text `<note>` is pasted into the line" gap
in `CLAUDE.md`.

A `<note>` inside the play text is the editor's or translator's gloss on one word. Today the
importer pastes it into the line it sits in, so the database, the TEI export, the live page,
the static site and every download show the corrupted line:

> Buscad por todas partes … <<"partes …">> (14) De aquí en adelante hasta la conclusión de la
> tragedia es natural el estilo sin ser humilde, …

(EMOTHE0053 Hamlet, act 5, `#p1282` on emothe.uv.es.) After this project the line reads
"Buscad por todas partes …", a small number follows "partes …", and the note opens in a pop-up,
as on the old EMOTHE site.

## Decisions

| Question | Answer |
|---|---|
| Fix the inline `<stage>` flattening in the same project? | No. Notes only. Inline `<stage>` (3,148 in 59 plays, same root cause) is its own follow-up, reusing the offset idea below once it is proven |
| Is this a FileMaker slice? | No. Notes are in the TEI files, and TEI stays the source of truth for the text; the slices roadmap already leaves FileMaker's `T07.52`–`.54` notes out |
| Where do notes show? | Static site, `/plays/:code`, the HTML/PDF/EPUB downloads, and the TEI export |
| Can curators edit notes? | Yes: add, edit and delete in `/admin/plays/:id/content` |
| How does a note remember its place? | A character offset into the line's plain text, in its own table. The line's `content` stays clean |
| What number do readers see? | 1, 2, 3… through the play in reading order. Not the source's `n` |

## The corpus

Every fixture, tracked and `tei_files/`, surveyed on 2026-10-08:

- **503 notes in the play text, in 20 plays.** EMOTHE0752 has 154, Hamlet 147, EMOTHE0706 62.
- **Parents:** `<l>` 272, `<p>` 170, `<stage>` 13, `<speaker>` 13, `<head>` 5, and 28 inside an
  `<emph>` or `<seg>` within a line.
- **416 sit mid-line**, right after the word they gloss:
  `Nous voyent<note n="6089" type="editor"><term>voyent</term><p>On maintient…</p></note> dans la ville`.
  87 sit at the end of their line.
- **Shape:** `n`, `type`, usually a `<term>` naming the glossed word, then one or more `<p>`, which
  may hold `<emph>`. Older files (Hamlet, EMOTHE0139) have no `<term>`; their first `<p>` is the
  quoted word, `<p><emph>"partes …"</emph></p>`.
- **Types:** `traductor` 230, `editor` 178, `editor_critico` 47, `editor_digital` 47, `autor` 1.
- **`n` is not unique.** Hamlet has five notes with `n="55"`. Elsewhere `n` is a corpus-wide
  number such as 6089.
- **Front matter:** about 20 unnumbered notes sit directly in a front `<div>` (cast list,
  dedication). The importer drops them today; they are not pasted anywhere. One sits inside a
  front `<p>` and is pasted into the editorial note. Both are out of scope.
- **Header:** 82 notes in `sourceDesc/bibl`, read directly by `find_child(children, "note")`.
  Unaffected.

## Done when

- No note text is in any element's `content`, speaker label or division title after
  `mix playcode.import.tei --force`.
- The TEI export puts every note back where it was, and the real-fixture round trip proves it.
- The static site, `/plays/:code` and the HTML/PDF/EPUB downloads show a numbered marker after
  the glossed word, and the note with its type, term and paragraphs.
- A curator can add, edit and delete a note on a line, a speaker or a heading, and a note stays
  after its word when the line around it is edited.

## The model

New table `play_notes`, UUID primary key:

| Column | Type | |
|---|---|---|
| `play_id` | references `plays`, `on_delete: :delete_all` | |
| `element_id` | references `play_elements`, `on_delete: :delete_all`, nullable | |
| `division_id` | references `play_divisions`, `on_delete: :delete_all`, nullable | |
| `offset` | integer, `>= 0` | graphemes into the anchor's plain text |
| `position` | integer | order among notes at the same offset |
| `n` | string, nullable | the source's number, kept for the round trip, never shown |
| `type` | string, nullable | `traductor`, `editor`, `editor_critico`, `editor_digital`, `autor` |
| `term` | text, nullable | the glossed word |
| `body` | text, required | paragraphs separated by a blank line, `<<…>>` for italics |

A check constraint requires exactly one of `element_id` and `division_id`. Index on
`(element_id, offset, position)` and `(division_id, offset, position)`. `type` is not
validated: TEI is the source of truth, so the importer keeps whatever a file says, and the
admin form offers the five types.

**The anchor text** is the field the offset counts into:

- a verse line, prose paragraph, stage direction or trailer: its `content`;
- a speech: its `speaker_label`;
- a division: its `title`.

**The offset** counts graphemes of `InlineMarkup.plain(anchor_text)`, so the `<<` and `>>`
markers do not count. An offset equal to the text's length is the end of the line.

**Content version.** The migration adds the `play_row_changed()` trigger to `play_notes`, as the
`20261005120000` migration's moduledoc requires of every table with a `play_id` whose rows appear
on a play's pages. `test/playcode/content_version_test.exs` fails until it has it.

**Re-import.** `reset_tei_content/1` deletes the play's elements and divisions; the foreign keys
cascade to their notes. A note belongs to the text, and the text is TEI's, so a note a curator
added by hand is lost on `--force`, exactly as a curator's edit to a line is today. There is no
`origin` column.

## Importer

`lib/playcode/import/tei_parser.ex`. Only the play text learns about notes: verse lines, prose,
stage directions, trailers, speaker labels and body division headings. The header, the cast list
and the front matter keep today's `text_content/1`.

- Reading an anchor's text no longer descends into `<note>`. Each note is recorded at the plain
  text's length at that point.
- **Whitespace at a note.** The neighbours are joined with a space only when the source had
  whitespace on either side of the note. `Iliria<note>…</note>.` gives `Iliria.`, not
  `Iliria .`; `voyent<note>…</note> dans` gives `voyent dans`, with the note at the end of
  "voyent". Trailing whitespace before `</l>` is trimmed as now.
- A note inside `<emph>` gets its offset inside the italic run. A note inside an aside `<seg>`
  keeps its offset in the aside text that becomes the line; one beside the `<seg>` (AL0644,
  once) goes at the end of the line.
- Inside the note: `<term>` → `term`; each `<p>` → one paragraph of `body`, with `<emph>` and
  `<hi rend="italic">` as `<<…>>`. Anything else in the note keeps its text.
- A note with no text is dropped (two, in the `EMOTHE0010_…_test` fixture).
- Notes are inserted right after their element or division, in the import's transaction. A
  failed insert rolls the import back, as a failed element insert does
  (`{:note_create_failed, cs}`).
- `position` counts notes at the same offset in source order.

## TEI export

`lib/playcode/export/tei_xml.ex`. `build_inline_content` takes the anchor's notes and writes
each one back at its offset:

```xml
<note n="6089" type="editor"><term>voyent</term><p>On maintient…</p></note>
```

`n`, `type` and `<term>` only when set. A note whose offset falls inside an italic run splits
it: `<emph>a</emph><note/><emph>b</emph>`, the same text. `<speaker>` and `<head>` get the same
treatment.

An element whose text holds other elements (`<emph>`, `<note>`) is written on one line,
unindented (`{:iodata, …}` in XmlBuilder): `format: :indent` puts line breaks inside mixed
content, and a break before a `<note>` would read back as a space after the glossed word.

## One shared step for every renderer

`InlineMarkup.parts(text, notes)` adds a third kind of piece, `%{note: note}`, at each note's
offset, splitting an italic piece when the note falls inside it. `parts/1` stays as it is.
`plain/1` never sees notes, so search, the split-verse ghost text and anything else reading
clean text is unaffected.

`Note.reading_order(divisions)` lists the notes of a loaded content tree in reading order
(a division's heading, its own text, its scenes; a speech's speaker before its lines), and
`PlayContent.load_play_content/1` sets each note's virtual `number` from it, 1, 2, 3…. Every
renderer reads `note.number`, so note 57 is note 57 on the act page, on `text.html`, on
`/plays/:code` and in the downloads. `Note` joins the static site's fingerprint, because its
code decides what a page shows.

Labels, in `PlaycodeWeb.PlayLabels`:

| `type` | English (static site, downloads) | Spanish (live page, admin) |
|---|---|---|
| `traductor` | Translator's note | Nota del traductor |
| `editor` | Editor's note | Nota del editor |
| `editor_critico` | Critical editor's note | Nota del editor crítico |
| `editor_digital` | Digital editor's note | Nota del editor digital |
| `autor` | Author's note | Nota del autor |
| nil | Note | Nota |

## Static site and `/plays/:code`

Native `popover`, no JavaScript:

```html
…Buscad por todas partes …<button class="nref" popovertarget="note-57" aria-label="Translator's note 57">57</button>
…
<ol class="notes" role="doc-endnotes">
  <li id="note-57" popover value="57">
    <b>Translator's note</b>
    <button popovertarget="note-57" popovertargetaction="hide" aria-label="Close">×</button>
    <i>"partes …"</i>
    <p>(14) De aquí en adelante…</p>
  </li>
</ol>
```

- **On screen:** a small superscript number; a click opens the note centred on screen; ×, Esc
  or a click elsewhere closes it. Not placed beside the word: that needs CSS anchor positioning,
  which Firefox lacks, or JavaScript.
- **Print, and browsers without `popover`:** the same `<li>`s show as endnotes. A print rule
  overrides the popover's hidden state. The note is in the page once.
- **Where the list goes:** each page lists its own notes at its foot. An act page lists that
  act's, `text.html` all of them, `/plays/:code` at the end of the Text tab.
- **Static site:** `StaticSite.Components` (`el/1` for each element, the speaker, the heading),
  English labels, works from `file://`. `site.js` is not touched. `style.css` stays under its
  25 KB budget.
- **Live page:** `PlaycodeWeb.Components.PlayText`, Spanish labels through gettext. The compare
  pages and the content editor's preview tab draw through `PlayText` too, so they show the
  notes; ids are `note-<uuid>`, unique on a page that shows two plays. The editor's own line
  list does not show markers; a line's modal lists its notes.
- The search index does not include notes.

## Downloads

`Export.Html` and `Export.Epub` render each line through `InlineMarkup.parts(text, notes)`
instead of escaping `content` as stored. Text is escaped, italics become `<em>`, notes become
references. This also fixes item 2 of the improvements doc for these three downloads: italics
render instead of printing `<<…>>`. `Export.CompareHtml` is not changed.

- **HTML and PDF:** `<sup class="nref"><a id="ref-57" href="#note-57">57</a></sup>`; at the end of
  each top-level division, `<section class="notes"><ol>` with `<li id="note-57" value="57">`:
  label, term in italics, paragraphs, and a `↩` link back to `#ref-57`. PDF is this HTML printed
  by ChromicPDF, which keeps the links. Endnotes per act, because page-bottom footnotes need CSS
  Chrome's PDF output does not support.
- **EPUB:** `<a epub:type="noteref" href="#note-57">57</a>`; `<aside epub:type="footnote"
  id="note-57">` at the end of the chapter (one chapter per top-level division, as now). Readers
  that support it show a pop-up; others show endnotes.

## Admin note editor

A LiveComponent, `PlaycodeWeb.Admin.NotesComponent`, in its own file, placed in the element modal
(verse line, prose, stage direction, trailer, speech) and the division modal of
`/admin/plays/:id/content`.

- A **Notas** section, after the modal's own form (forms cannot nest), lists the anchor's
  notes: type label, term, the body's first words, Edit and Delete.
- **Añadir nota** and Edit open a small form:
  - *Tipo*: an untyped note, then the five types;
  - *Después de*: the anchor's words, "Buscad", "por", …, a repeated word numbered ("partes (2)").
    Each option's value is the offset at the end of its word (letters and digits; punctuation
    is not a word). An imported note that is not after a word (`tiene,<note/>`) adds a
    "Donde está ahora" option, selected, so saving its text alone does not move it. An empty
    anchor text offers "Al final". A new note starts after the last word;
  - *Término*: optional, the glossed word as the reader should see it;
  - *Texto*: a textarea; a blank line starts a paragraph, `<<…>>` marks italics.
- Create, update and delete go to the activity log, `resource_type: "note"`.
- No new route, so no new row in `authorization_test.exs`. Notes are content: whoever may edit
  the play's lines may edit its notes.

Context functions in `Playcode.PlayContent`: `list_notes/1` (by element or division),
`create_note/1`, `change_note/2`, `update_note/2`, `delete_note/1`, `anchor_text/1`. Schema
`Playcode.PlayContent.Note`. The component looks a note id from the browser up among its
anchor's notes only, so it never acts on another line's or play's row (the rule of
`0575c3b`), and it sets the anchor's ids itself, never from the form's params.

## Keeping offsets right after an edit

`PlayContent.update_element/2` and `update_division/2` compare the old and new anchor text. When
it changed, they move every note on that anchor in the same transaction:

- walk `String.myers_difference(old_plain, new_plain)`; an `:eq` run moves the offset along, an
  `:ins` before the note pushes it right, a `:del` that holds the note's offset leaves the note
  where the deletion was;
- an offset past the new end is set to the end.

The inline edit, the modal save and the bulk speaker relabel all call these two functions, so
all three are covered by this one change. Clearing a speaker label keeps its notes at offset 0.
Deleting an element or a division deletes its notes through the foreign key.

## Tests

Red first, through the outermost API (`CLAUDE.md`, *How To Work In This Repo*).

- **`tei_roundtrip_test.exs`**: one snippet with a mid-line note, a note at the end of a line, a
  note before punctuation (`Iliria<note/>.`), a note inside `<emph>`, a note on `<speaker>`, one
  on `<head>`, and a Hamlet-style note without `<term>`. Import, export, and assert with
  `xml_texts/3` that each line's text has no note text and no stray space, and with
  `xml_elements/3` that each `<note>` sits after the right word with its `n`, `type`, `<term>`
  and paragraphs.
- **`RoundtripTest`** (real fixtures): a `notes` count, and a line-text check: each `<l>` and
  `<p>` in the body, its notes removed, has the same text in the source and the export. That is
  the check whose absence let this bug through. EMOTHE0705 (17 notes, on lines and speakers)
  joins EMOTHE0746 and 0776 in the default run; `--include slow` sweeps the corpus, with
  Hamlet and EMOTHE0752 as the heavy cases.
- **`content_version_test.exs`**: passes once the trigger is in the migration.
- **Static site**: generate a play with notes; on the act page, the marker follows the right
  word and the endnote carries label, term and paragraphs; `text.html` lists every note.
- **`/plays/:code`**: `live/2`, the marker selected by its `aria-label`.
- **Downloads**: HTML, the reference after the word and the endnote in its act's section, and
  `<<…>>` no longer printed; EPUB, unzip and find the `noteref` and the `footnote` aside in the
  chapter; PDF, still generates.
- **Admin editor**: `live/2` on the content editor; add a note through the form, edit it, delete
  it, each checked through the TEI export.
- **Offsets**: a note after "partes"; add words before it; delete "partes"; after each edit the
  TEI export has the `<note>` where expected. Through the content editor's inline save, so the
  test goes through the route.
- New Spanish strings in the PO files (`mix gettext.extract --merge`, then check every fuzzy
  entry).

## Order

One plan, four phases, each green on `mix test` before the next:

1. Migration, schema, importer, TEI export, round-trip tests. Then `mix playcode.import.tei
   --force` on `playcode_dev` and a check that Hamlet's `#p1282` is clean.
2. `InlineMarkup.parts/2`, `note_numbers/1`, labels, static site, `/plays/:code`.
3. HTML, PDF, EPUB.
4. Admin editor, offset remapping.

Afterwards: `CLAUDE.md` (schema list, the open gap marked done) and
`docs/static-site-improvements.md` (item 1 done; item 2 done for HTML, PDF and EPUB).

## Out of scope

- Inline `<stage>` inside lines: the follow-up project.
- Front-matter notes (cast list, dedication, editorial introduction).
- Notes in search and in `Export.CompareHtml` (the downloaded comparison).
- Placing the pop-up beside the word.
