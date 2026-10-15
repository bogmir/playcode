# Paratexts: what stands before and after the text

**Status:** designed 2026-10-14, revised 2026-10-15 after a grilling session (its decisions
below). Plan: `../plans/2026-10-14-back-matter.md`. Words as in `CONTEXT.md`: a **paratext**
is any text before or after the text without being part of it; an **editorial text** is a
paratext written for this edition; the **scene of the action** is not a paratext; a
paratext's **kind** is what it is.

The import reads only the bibliography from `<back>`; everything else there is dropped, and the
round-trip page lists it as "not read yet". Surveying it (the 372 production files under
`doc/tei_corpus/` and the fixtures, one file per code) turned up a second, older loss in the
front: every kind outside five became `nota`.

## What the files hold

**After the text**, 21 plays, 29 `div`s, none nested, all direct children of `<back>`:

| What | Plays | Kinds (`div/@type`) |
|---|---|---|
| A heading and paragraphs | 0125, 0133, 0147, 0157, 0310, 0444, 0460 (4), 0503 (2), 0644, 0662, 0714, 0715, 0750 | `epilogo`, `despedida`, `colofon`, `licencia`, `apendice`, `prologo` |
| A sonnet in verse: `head`, `lg` of 14 `l`, `trailer` "FIN" | 0542 and its translation 0743 | `epilogo` |
| A cast list | 0404, 0718 | `elenco` |
| The bibliography | 8 plays | `bibliografia` (read already) |

What they are, read one by one:

- **The appendices are editorial texts**: Everyman's (0460) "The Early Texts: Analysis",
  "Editorial Procedures", "Bibliography"; the "Critical Apparatus" of 0644; a translator's note on
  the cast list (0310).
- **The epilogues of The Rover (0503) and El hombre a la moda (0662) are spoken**, to the
  audience, in verse, written as one `<p>` with 43 and 35 `<lb/>`, no speaker. The project's manual
  (`docs/Instrucciones edición digital en EMOTHE 2020.docx`) makes a spoken epilogue a division.
- **The sonnet of 0542/0743 is commendatory**, in praise of the author, spoken by no character.
- **The back `prologo` (0444) is the 1635 edition's address to readers.** No front `div` holds
  speeches or verse: every front `prologo` is prose.
- **Four kinds are wrong**: 0125, 0133 (`licencia`) and 0715 (`colofon`) are performance notices,
  0750 (`colofon`) a privilege. A fifth before the text: 0271's `licencia` is an address to the
  reader ("Advertissement").

emothe.uv.es prints every back section after the text, each with its heading and an entry in its
navigation index (checked 2026-10-14 on 0503, 0460, 0542, 0404), and 0404's back cast list as a
second "Elenco"; 0718's, all `ana="oculto"`, it does not print.

**The cast lists.** EMOTHE0718 has no cast list but the one in `<back>`: it imports with 0
characters and none of its 282 speeches has a speaker. EMOTHE0404 has a front list of 17 names
without ids and a back list, "[EDITORIAL CASTLIST", of 20 roles with the ids its 893 speeches point
at; it imports the front 17 and links no speech. Both wait on question 29.

**The kinds before the text.** `TeiParser.section_type/1` keeps five words and turns any other into
`nota`. On dev 285 front sections have lost their kind that way (all 509 rows on dev came from
files; none is hand-entered):

| Kind | Front | What it is |
|---|---|---|
| `nota_edicion_digital` | 152 | note on this digital edition (not the header's `notesStmt`: the same text in 1 play of 152) |
| `circunstancia_accion` | 45 | the scene of the action, after the cast list in 44, never beside a `<set>` |
| `introduccion_editor_digital` | 31 | introduction to the digital edition |
| `head_title` | 28 | the title at the head of the text: 12 a heading only, 1 a heading and a `<note>` (0728), 7 a heading and paragraphs, 8 paragraphs only; 20 before the cast list, 7 after it |
| `epistola` | 14 | an epistle, Molière's *placets* |
| `introduccion_autor` | 8 | the author's address to the reader |
| `title_page` | 8 | a title page in prose |
| `noticia_representacion` | 6 | a notice of the performance |
| `introduccion_traductor` | 5 | the translator's note |
| `licencia` | 4 (and 3 after the text) | a licence to print: privilege, approbation |

One front `div` says `nota`: 0784's "Note sur cette édition numérique". None has no `@type`.

**Line breaks.** About 3,200 `<lb/>` in the front matter of 190 plays and 634 in the back; 640
pairs (`<lb/><lb/>`, an empty line, mostly before a signature) in the front of 140 plays. Question
10 is answered (2026-10-15): readers see every break.

**TEI** (P5; exports are validated against stock `tei_all` 4.11.0, `priv/schemas/tei_all.rng`).
TEI has elements for some kinds: `<set>`, `<performance>`, `<argument>`, `<postscript>`,
`<prologue>`, `<epilogue>`; its `div/@type` values (`dedication`, `preface`, `colophon`,
`appendix`) are suggestions, so the files' Spanish words are valid. Placement bites: `<argument>`
stands only before the first `div` or after the last, `<postscript>` only last in `<back>`;
`<performance>`, `<set>`, `<prologue>`, `<epilogue>` may stand between divs. `<imprimatur>` lives
only in `<titlePage>`; TEI's `<licence>` is the edition's terms of use, not a licence to print.
TEI has no marker for an editor's text beyond `@resp`; the kind says it here.

## Decisions

From the grilling of 2026-10-14/15 (the user, for the project):

| Question | Decision |
|---|---|
| The word | **Paratext**, the umbrella; an editorial text is a paratext written for this edition; the scene of the action is not a paratext. `CONTEXT.md` holds the glossary |
| The table | `play_editorial_notes` becomes `play_paratexts` (schema `Paratext`); context functions, admin tab ("Paratexts"/"Paratextos"), activity-log type (`paratext`) follow |
| Concept | Decided by the kind, through a fixed map. A misfiled paratext is fixed by correcting its kind |
| Kinds outside the list | Kept as the file gives them, as a stage direction's kind is; an unknown word is a paratext |
| `circunstancia_accion` | The scene of the action: read as `lugar_accion`, written as `<set>` |
| `nota` | Read as `nota_edicion_digital` (0784's is one); the admin no longer offers a generic "Note" |
| `licencia` | Named "Licence to print" / "Licencia de impresión" |
| Wrong kinds in the files | Kept; the project gets the list and corrects them in the admin |
| Encoding | `div type="<the word>"`, and `<set>` for the scene; TEI's elements wait on question 35 |
| Heading-only paratexts | Read (the 12 `head_title`, 4 `nota_edicion_digital`, 0728's heading) |
| Line breaks | Kept in paratexts: `<lb/>` a line break, `<lb/><lb/>` a new paragraph |
| Where printed | Where the file puts them, before or after the text; editorial texts moving to "about this edition" is question 33 |
| The site's Contents | Lists the paratexts after the text |
| Order | Editors drag paratexts into order; a new one goes last |
| Admin kind select | Labelled "Kind" ("Tipo"), grouped: printed with the play, editorial texts, scene of the action |
| API | `paratexts` (each `kind`, `heading`, `content`, `back`, `editorial`) and `scene_of_action` |
| Admin fixes and re-imports | The import preview counts the file rows edited since import that a re-import would replace |
| 0404's and 0718's cast lists | Neither read: question 29 |
| The sonnet | Deferred: question 30 |
| Spoken epilogues (0503, 0662) | Read as paratexts after the text, as the files have them; question 34. If they are divisions, editors re-enter them by hand (no conversion tool) |
| Prologue to the reader vs spoken prologue | Two things; question 31 |
| Paratexts after the cast list | Printed above it, as now; question 32 |

## The model

- `play_editorial_notes` is renamed `play_paratexts`; `Playcode.Catalogue.PlayEditorialNote`
  becomes `Playcode.Catalogue.Paratext`, `Play.editorial_notes` becomes `Play.paratexts`,
  `Catalogue.*_play_editorial_note*` become `*_paratext*`. A table rename keeps its
  `play_row_changed()` trigger. Old `activity_logs` rows with `resource_type = "editorial_note"`
  are migrated to `"paratext"`.
- `play_paratexts.back`, boolean, default false, not null: the paratext stands after the text.
  The kind cannot tell where a paratext stands: `prologo` and `licencia` come in both. A scene
  of the action cannot be `back` (it is printed with the cast list and written as the front's
  `<set>`).
- `content` holds paragraphs separated by a blank line and line breaks as `\n`, as a witness's
  fields do; `content` is required only when there is no heading.
- `Paratext.kinds/0`, the known kinds in the order the admin offers them, and
  `Paratext.editorial?/1` and `scene?/1`, the fixed map: `nota_edicion_digital`,
  `introduccion_editor_digital`, `introduccion_editor`, `introduccion_traductor` and `apendice` are
  editorial texts, `lugar_accion` the scene, every other word a paratext printed with the play.
  The changeset checks the kind is one TEI token (`~r/^[^\p{C}\p{Z}]+$/u`, `teidata.enumerated`),
  not that it is known.
- Labels: `PlayLabels.kind_label/1` and `kind_options/1`, beside the stage directions' pair
  (`with_current/3` keeps a file's unknown word). The content editor's private pair and the static
  site's `Components.note_heading/1` go.

## Reading

- Front: the file's word is kept; `circunstancia_accion` becomes `lugar_accion`, `nota` and a
  `div` with no `@type` become `nota_edicion_digital`.
- Back: every `back/div` but `bibliografia` and `elenco` is read as the front reads a paratext,
  with `back: true`, positions continuing after the body's divisions. A back `div` holding an
  `lg` (the sonnet) is not read, though it has a heading (question 30). A cast list in `<back>` is
  not read (question 29).
- A paratext is kept when it has a heading or paragraphs.
- Each `<p>` is read with its `<lb/>`s as `\n` (the parser's `lines_text/1`, which witnesses use);
  an empty line between two breaks therefore reads as a paragraph break.

## Writing

- `build_front/3` writes the paratexts not `back`; `build_back` writes the `back` ones, in position
  order, as `div[@type]` with `head` and `p`, before the bibliography's `div`.
- A kind is written as stored, so the 285 come back with their own word on re-import.
- A `\n` inside a paragraph is written as `<lb/>` (the export's `lines/2`).

## Printing

One rule, `PlayLabels.split_paratexts(paratexts, divisions)` → `{front, scene, back}`, replacing
`split_front_matter/2`; every output prints line breaks.

| Output | Paratexts after the text |
|---|---|
| Play page | after the text, each with its heading; listed in the side navigation after the divisions |
| HTML/PDF download | after the text |
| EPUB | one chapter each, after the text's chapters, titled by its heading or its kind |
| Published site | after the text on the full-text page and the last text page; an entry each in the title page's Contents |

An untitled paratext is named by its kind wherever a name is needed (navigation, EPUB chapter, site
heading, Contents). Paratexts stay out of the site's search and the statistics, as today.

## Admin

- The tab is "Paratexts" ("Paratextos"). The kind select is labelled "Kind" ("Tipo") and grouped:
  printed with the play, editorial texts, scene of the action; a file's unknown word shows as
  itself and is kept.
- An "After the text" checkbox; the scene of the action refuses it.
- The paratexts are dragged into order, as the cast list is (`.DragSortList`); a new one goes last.

## The API

`/api/v1` returns `paratexts`, each with `kind`, `heading`, `content` (line breaks as `\n`), `back`
and `editorial`, and `scene_of_action`, the scene's `heading` and `content`. `editorial_notes` goes:
no consumer is documented.

## The import preview

`TeiImport.preview_import/1` and `mix playcode.import.tei --dry-run` report, per play, the rows
from the file edited since their import (`updated_at > inserted_at`) that a re-import would
replace: the text's divisions, elements and notes, and the paratexts, editors, sources,
witnesses and place links from the file. Nothing is refused; the person
importing is told.

## Rollout

1. Deploy (the migration renames the table and adds `back`).
2. On production, list the file paratexts edited since their import; look at any before going on.
3. Re-import every play (`Playcode.Release`, `--force`), so every play gets its kinds, back matter
   and line breaks.
4. Only then do the editors correct: the five kinds on the questions page, and the order.

A later re-import of a play's original file replaces its file rows again, editors' fixes included;
the play text's line breaks (answers 9 and 10) will need one. The preview's count is what makes
that visible.

## Not in this work

- The cast lists of 0404 and 0718 (question 29), the sonnet (question 30), the questions 31–35.
- The play text's line breaks and prose line numbers (answers 9 and 10): a project of its own.
- The `<note>` inside 0133's licence: with the ~270 notes of dedications and introductions.
- `ana="grupo oculto"`: 0718's JUDEOS and TODOS, with the "groups in the cast list" item.
