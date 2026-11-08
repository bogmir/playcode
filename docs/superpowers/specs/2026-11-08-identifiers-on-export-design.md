# Problem 2: identifiers on export, in FileMaker's format

Built 2026-11-08 on `fix/identifiers-on-export`. The handoff from the numbering grilling
(`/tmp/playcode-numbering/02-identifiers-on-export.md`), with the two open points settled by
the owner and what was built at the end. FileMaker's rule below is what the corpus files
write; what the export writes differs in the padding only (Q32).

## What it is for

The researcher asked for identifiers "con el mismo formato y numerados en el orden del texto",
and noticed that the `<sp>` elements Playcode exports have no `xml:id`. Identifiers are
addresses that other elements point at: multi-line asides (`seg next=`), variants (`app to=`),
and later translation alignment (`corresp=`, problem 5). Nobody cites them. Folger and LEMDO
also put identifiers on speeches and stage directions.

## How it works today

- A line keeps the identifier read from its file (`play_elements.line_id`).
- A new line gets the highest identifier plus one (`play_content.ex` 660-716:
  `put_next_line_id/1`, `next_line_id/1`, `line_id/2`). The comment at line 671, "no line is
  renumbered, so no link to a line breaks", overstates it.
- Speeches, stage directions and scenes are exported with no identifier.
- Only the asides and variants use identifiers:
  - `TeiXml.with_aside_links`, about line 1430, writes `{line}-segNN` and `next=`;
  - `range_end` (`note.ex:54`) is written back as `to=` (`tei_xml.ex` about line 1626).
- The editor's split-verse warning shows `line.line_id` (`play_content_editor_live.ex:1420`).
- `CLAUDE.md` lists "a speech's `xml:id`" as a gap in Playcode. The decision below closes it
  differently: the identifier is computed, not stored.

## FileMaker's rule (what the export writes)

- Prefix `em{4-digit code}-{language}-`, with the language taken from the play's language:
  `em0756-es-`. Plays whose code is not EMOTHE's get `es-` with no `em` part.
- One counter in text order over every `l`, `p` and `lb` (each split-verse piece counts):
  `em0756-es-0001`, `-0002`…
- Separate counters:

  | For | Shape |
  |---|---|
  | speeches | `em0756-es-sp-0001` |
  | stage directions | `-st-0001` |
  | scenes | `-sc-0001` |
  | trailers | `-tr-0001` |
  | aside pieces | `{line identifier}-seg01` |

- Always 4 digits; the largest play in the corpus reaches 7784.
- Corpus check (385 files):
  - 289 follow the line counter exactly;
  - 47 count line breaks that they write without an identifier;
  - about 42 have hand-edit jumps;
  - 7 are out of order.
- The ~80 files in the older `es-0001` shape gain the `em` prefix (Q12).

## Decisions

- **Q2:** recount on every export, so nothing is stored.
- **Q9:** every element gets one.
- **Q12:** one shape.
- **Q13:** at import, the file's counted identifiers are read only to resolve pointers, then
  dropped.
  - `seg next=`: 9,613 in the corpus, 39% pointing at nothing.
  - `app to=`: 12, in 0010, 0435, 0560 and one more file.
  - Each becomes a stored relation between rows.
  - Named identifiers are kept: characters (`sp who`) and witnesses (`wit`).
  - `line_id`, `next_line_id` and the comment go. The editor warning shows the verse number
    instead.
- **Q30 (owner, 2026-11-08):** FileMaker's one shared counter for `l`, `p` and `lb`;
  splitting it into `-l-`, `-p-`, `-lb-` adds nothing, because the kind is already the
  element's name.
- **Q32 (owner, 2026-11-08):** no padding. Q12's 4 digits only copied FileMaker's look, and
  the identifiers are counted afresh on every export anyway: `em0756-es-1`, `-sp-1`,
  `-st-1`, `-sc-1`, `-tr-1`, `{line identifier}-seg1`. The code's own digits stay
  (`em0756`). The examples below keep FileMaker's padded shape, as the files have it.

## Step by step

**Export of a scene**

Play 0756 opens with a split verse and a stage direction:

```xml
<sp xml:id="em0756-es-sp-0001" who="#rey">
  <l xml:id="em0756-es-0001" part="I" n="1">¿Quién va?</l></sp>
<sp xml:id="em0756-es-sp-0002" who="#criado">
  <l xml:id="em0756-es-0002" part="F">Yo, señor.</l>
  <stage xml:id="em0756-es-st-0001">Vase.</stage></sp>
```

**A line is inserted before the first one**
- At the next export every line identifier moves up by one (`-0001` becomes `-0002`).
- Nothing breaks: the aside and variant pointers are rebuilt in the same export from stored
  relations, so `next=` and `to=` follow.

**A variant is imported**
- `<app to="#em0010-en-0230">` resolves at import to the row of the line with that identifier.
- The export writes that row's identifier at the time of export, whatever it has become.

**An aside over two lines**

The file has
`<seg xml:id="em0756-es-0040-seg01" next="#em0756-es-0041-seg01">`.

- Import stores "this piece continues in that piece".
- Export writes the two current identifiers.

## How it interacts with the others

- **Independent of 1 and 4:** identifiers don't depend on numbers (Q1).
- **Problem 3:** the site does not use TEI identifiers (Q11); `line_id` stops being an anchor
  fallback.
- **Problem 5:** writes `corresp` pointing at the original's speech identifiers at export. It
  is safe because the pairing is stored as a relation, not as text.
- **Caveat:** recounting is safe only while no file outside Playcode keeps our identifiers.
  Folger can cite its line-count identifiers (FTLN) because its printed text never changes.

## Records and tests

- **Tests:** round trips that assert the identifier shapes and counters; a multi-line aside and
  a variant still resolving after a line is inserted; complete copy.
- **Docs:** `tei-mapping.md`; `CONTEXT.md` (number vs identifier; "line id" is a term to
  avoid); `CLAUDE.md`'s "speech's `xml:id`" sentence; `ida-y-vuelta.html`.

## What was built

- **Export** (`TeiXml.identify/2`): the body is built as an XmlBuilder tree, its one-line
  elements (`inline_element/3`) marked and generated last (`realize/1`), so one walk in
  document order numbers every element, inline `<lb>` and `<stage>` included. That settles
  the open `lb` question: a break inside a paragraph counts where it stands. Only the text's
  divisions are walked; inside a note, an `<app>`, a `<head>`, a `<speaker>` or a cast list
  nothing is numbered, and paratexts and cast lists between the acts have none, as in the
  corpus.
- **Pointers:** a line or paragraph carries its row's id (`_ref`) into the tree, and aside
  pieces and a variant's `to` name rows; a second walk writes the identifiers those rows got.
  A `to` whose row has no identifier is left out.
- **Import:** a file's `l` identifiers are read to resolve `app to` into
  `play_notes.range_end_id` (`TeiImport.resolve_ranges/1`), then dropped. Aside chains were
  already a relation (`aside_continues`).
- **Removed:** `play_elements.line_id`, `play_notes.range_end` (the migration resolves stored
  `to`s through `line_id` first), `PlayContent.put_next_line_id/1`, `line_id/2`, the Word
  import's identifier counter, the Content tab's "Identifier" line (its split-verse warning
  names the verse number), and the site's identifier anchor (`p<n>` again until problem 3).
- **Tests:** `tei_roundtrip_test.exs`, "identifiers" (shapes and counters, the non-EMOTHE
  prefix, an aside and a variant following an inserted line, a dangling `to`);
  `complete_copy_test.exs` compares a variant's reached line by its text. Each bites
  (`bin/bites`).
