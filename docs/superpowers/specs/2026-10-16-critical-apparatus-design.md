# The critical apparatus (`<app>`): design

Status: implemented, 2026-10-16 (commits 463f8dd to e3d2782), from the project's answers to
questions 1-4 of `docs/stakeholder/preguntas.html`. The corpus analysis it rests on, and the
`<code>` fragments that share its background, are in `docs/tei-apparatus-and-code.md`; this
file is the design.

## The problem

604 `<app>` entries in 6 plays (EMOTHE0560 212, 0460 127, 0187 98, 0010 94, 0530 63, 0435 10).
The importer reads every word inside an `<app>` into the line, so readers see the variant
readings pasted into the text and the export writes them back as text:

- *La discreta enamorada*, v. 72: "mucho la hermosura llama llamafalta infama ,"
- *Hamlet*, v. 8: "Barnardo. Barnardo. Barnardo?"
- notes holding a copy of their line's entry read "an an and learn me that"

The readings' own notes (`<lem>…<note>`) are pulled out as numbered notes of the line, so
those six plays' note numbers count them.

## What the corpus holds (re-read 2026-10-16)

- Every `<app>` has `n`; 584 a `type` (`substantive` 552, `orthographical` 32), 11 a `to`.
- Children: `lem` first when there is one (472 have one), `rdg`s, and the entry's own
  `<note>` last (31). No text directly inside an `<app>`.
- A `lem` or `rdg` holds text, `<emph>` and at most one `<note>` (181 do); that note holds
  text and `<emph>` only, never `<p>` or `<lb>`, and no attributes. The entry's note likewise.
- 4 `<app>`s are empty, all in Hamlet's v. 189, 240 and 313. 3 readings have `wit="#"`.
- The same `n` appears twice outside notes in 0460 (1239) and 0530 (538), and four times in
  Hamlet's v. 189 (106, the damage the analysis describes).
- 63 `<app>`s sit inside a `<note>`. 62 are copies of an entry of the same element (same
  `n`, same readings): EMOTHE0187 34, 0560 23, 0010 4, 0530 1. One, EMOTHE0530 `n="496"`, is
  only in the note on "ne" (v. 141).
- All are in the body: in `<l>`, `<stage>`, `<p>`, `<speaker>`, `<head>`, `<seg>`, `<emph>`,
  and a note's `<term>` and `<p>`.

## Design

### Storage

A variant is a `play_notes` row with `type` `"variante"`, so offsets, the carrying of offsets
through edits (`update_element/2`, `update_division/2`), anchors, `position` and the
content-version trigger are the notes' own. New columns:

| Column | Holds |
|---|---|
| `variant_type` | the `<app>`'s `type`, as written (`substantive`, `orthographical`, none); written back, shown nowhere |
| `range_end` | its `to`, as written (`"#em0560-es-0013"`), the `#` included; written back |
| `readings` | JSONB, `embeds_many` `Note.Reading`: `lemma` (true for the `lem`), `wit` as written (`"#1623b #1626a"`), `text` with `<<italics>>`, `note`, the reading's own note |

`n` is the `<app>`'s `n`; `body` is the entry's own note, nil when it has none (`body` becomes
nullable; `Note.changeset` still requires it of a note). `term` stays nil. An empty `<app>` is
kept as it is: a variant with no readings and no body.

`"variante"` is not `variantes`, the type of 3 ordinary notes in the corpus, which stay
notes.

### Import

- In the play text an `<app>` is read as a `<note>` is: it leaves the text and is stored at
  its offset, after the word it follows, with the same rule for the whitespace beside it.
- Inside a note, an `<app>` reads as nothing, its neighbours joined as written: the note
  keeps the base text's words ("an learn me that", "Q2 «ho! Who is»"). An `<app>` inside a
  note whose `n` no `<app>` of the same element has is moved into the line, at the note's
  offset, just after the note (EMOTHE0530 `n="496"`, after "ne").
- A reading's text leaves out its note; the note is the reading's `note`.
- In a line or paragraph partly or wholly aside, an `<app>` is neither spoken text nor
  dropped: it is kept as a note is.
- A re-import replaces a play's variants with the file's, as it does its notes.

### Export

At the variant's offset, as `build_note/1` writes a `<note>`:

```xml
<app type="substantive" n="908"><lem wit="#H">llama<note>Corrección de Hartzenbusch…</note></lem><rdg wit="#P3">falta</rdg><rdg wit="#MP">infama</rdg></app>
```

A missing `type`, `n`, `to` or `wit` writes no attribute; a reading with no text and no note
is an empty element (`<lem wit="#Q2"/>`); the entry's note goes last, its paragraphs as
`<p>`s. A copy that sat inside a note is written once, in the line. Exporting, re-importing
and exporting again gives the same file.

### Numbering

Notes are numbered in reading order as today, variants left out: a variant has its own
sequence, used only for ids (`var-3`). The readings' notes are no longer counted, so the note
numbers of the six plays go down once they are re-imported.

### What readers see (questions 1, 3 and 4)

- **The marker**: a superscript `*` after the word, apart from the numbered notes, a button
  labelled "Textual variant N" (Spanish "Variante textual N") that opens a pop-up.
- **The pop-up**: "Textual variant", then one line per reading, in the file's order: each
  siglum in italics followed by its short name in parentheses, then the reading, then the
  reading's own note in parentheses; after them the entry's note. As the old site listed
  them; the lemma is not marked out.

  > *H* (Hartzenbusch, 1860) llama (Corrección de Hartzenbusch, …)
  > *P3* (Madrid, 1653) falta
  > *MP* (1735) infama

- **The short names**, worked out from the play's own rows, `Playcode.Witnesses.short_names/1`:
  - a witness (`play_witnesses`, same siglum): its place and date, as written, a trailing
    colon dropped: "Madrid, 1653", "1735", "London, [1518-19?]";
  - else a modern edition the play links to (`bibliography_entries.siglum`): its editors'
    surnames (the part of each person in `monogr_editors` before the first comma; two joined
    by "&", which needs no translation, three or more the first and "et al.") and `year_text`:
    "Hartzenbusch, 1860", "Bruster & Rasmussen, 2009", "Thompson & Taylor, 2006",
    "Taylor et al., 2016";
    the year alone when the siglum is the first surname ("Dyce (1831)", "Bevington (2002)")
    or there are no editors ("POPE1 (1723)");
  - else nothing: the siglum alone ("Aut.", "PXXIV").
  A `wit` naming several sigla names each; `#` alone names none.
- **The switch**: on the play page and the site, "Variants", on by default, shown only on a
  play that has variants; it hides the asterisks. The site remembers it as it does the
  others.
- **Where variants are not**: the play page's Notes view, the site's Notes page and its
  search list numbered notes only. The comparison download (`CompareHtml`) prints no notes
  and no variants, as today.
- **The downloads** (HTML, PDF, EPUB): the `*` links to its entry; after each act's notes, a
  "Variants" list, one entry per variant, laid out as the pop-up (in the EPUB, footnotes the
  e-reader shows as pop-ups, as the notes are).

### Hamlet (question 2): "Show variant readings"

A per-play setting, `plays.show_variants`, on by default, in the play form. Off, the play's
variants are left out of everything readers see (play page, comparison page, site,
downloads); the TEI export and the admin keep them. A migration turns it off for EMOTHE0010
until its editor has finished.

It is a curated column the TEI import never writes (`@platform_owned`), and like
`is_complete` it is kept out of the file: it is Playcode's switch for what visitors see, not
part of the edition. **This extends the rule in `CLAUDE.md` that `is_complete` is "the one"
such column; it needs the project owner's agreement.** The import preview reports it as
preserved only when it is off: "preserved" now means "differs from a new play's default"
for every platform-owned column.

### Editing (design point 8)

In the content editor's notes section, "Add variant" beside "Add note". A variant's form:
where it goes (the word it follows), its readings as a list (witnesses, reading, comment, and
"Edition's reading" for the lemma; add, remove), and a comment on the whole entry. Its type
and `to` are kept, not edited. The admin Notes tab lists variants as "Textual variant",
filters by it, and edits them with the same fields. A variant stays a variant and a note a
note.

## Out of scope

- The Folio passages and the Q4 Additions (questions 36 and 37), which will also be
  `<app>`s of their own `type`.
- Resolving a siglum to a link to its witness or edition; the short name is text.
- Search over the readings.
- Marking the lemma, or the range a `to` covers, on the page (the editors name the range in
  the note: "vv. 13-14 Estos dos versos…").
- Repairing Hamlet's damaged entries; they are imported and written back as they are.
