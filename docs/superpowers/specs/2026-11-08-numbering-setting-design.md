# A numbering rule per play (problem 4)

Problem 4 of six on numbering and identifiers (index: `/tmp/playcode-numbering/00-README.md`,
handoff `04-numbering-setting.md`, grilled with the owner on 2026-11-08). Problems 1 (numbers as
written), 2 (identifiers on export) and 3 (site anchors) are merged; this one keeps the numbers
problem 1 stores right, and gives problem 3 the restart it guessed.

## Why

The corpus numbers its plays in several ways and nothing checks them; hand edits broke some.
FileMaker had a per-play setting, "Configuración del texto": what is numbered (solo versos,
verso y prosa, intervenciones), whether counting is manual, and where the count restarts
(continua, por acto/jornada, por escena). The researcher approved bringing it back
(2026-11-08). After this change every play says how it is numbered, Playcode recounts the
numbers on every save of a play that is not Manual, and the import finds the plays that break
their own rule.

## The setting

Three columns on `plays`, never null:

| Column | Values | Default |
|---|---|---|
| `numbering_type` | `V`, `VP`, `VL`, `S` | `V` |
| `numbering_restart` | `never`, `act`, `scene` | `never` |
| `numbering_manual` | boolean | `false` |

| Type | What gets a number |
|---|---|
| **V** | Each verse once, on its first piece (`part` nil, `""` or `I`); an `M`/`F` piece and prose get none. FileMaker's "solo versos". |
| **VP** | As V, plus each prose paragraph, in the same series. FileMaker's "verso y prosa". The handoff's 4 "P" files (prose numbered, no verse) are VP. |
| **VL** | As V, plus each printed prose line: the paragraph's own number for its first line, then each `<lb n>` marker inside it. Not a FileMaker option; 29 files follow it (English-edition and Folger tradition). |
| **S** | One number per speech, on its first verse line (whatever its `part`) or prose paragraph. FileMaker's "intervenciones". Text outside a speech gets none. |

**Restart.** `never`: one count through the play. `act`: every top-level division starts at
1, prologues and epilogues included (Q21). `scene`: every scene starts at 1, and so does every
top-level division's own text before its scenes, a prologue or epilogue included (Q21: the
researcher's "like a scene"). Corpus files whose prologue or epilogue continues the count fit no
rule and go Manual (about 9: 0103, 0354, 0369, 0554, 0672, 0695…).

**Manual.** A Manual play's numbers are typed by hand and never recounted. It keeps a type and a
restart: the citation label reads the type, the site's anchors and references the restart.

## Numbers are stored and recounted (QA, Q24)

Numbers stay where problem 1 put them: a verse's `line_number`, and a prose paragraph's own
number as the leading `<lb n="…"/>` marker of its `content` (Q29: no column; a VL recount
rewrites the markers inside the text anyway, and the cost is per changed row either way). A
printed line's number inside a paragraph is an inner `<lb n>` marker; only VL counts those,
and the other types leave them as they are.

**The recount** (`Playcode.PlayContent.Numbering.recount/1`) reads the play's verse lines and
paragraphs in reading order (one light query, the walker `split_verses_out_of_order/1` uses
today, generalised), counts by the setting, compares with what is stored, and writes only the
rows that differ, in one `UPDATE play_elements … FROM unnest(ids, numbers, contents)`. A Manual
play is never touched. No Renumber button (Q24): it runs

- in `PlayContent.refresh_derived/1`, which the content editor calls after every write that
  moves text (and `reorder_children`, which does not call it today, will);
- after the play form saves a setting change;
- after a TEI import and after a Word import. The Word parser's own verse counter goes; the
  recount numbers a Word play by its setting (a new play's default, V never).

Measured (handoff, 2026-11-08): rewriting every row of Hamlet with the content trigger is
~132 ms for 2,943 verses, ~30 ms for 451 paragraphs; a typical save changes no number and
writes nothing.

**A printed line break in a VL paragraph** (QG) is typed as a marker with any number,
`<lb n="0"/>`; the recount gives it its number and moves every later one. No bare `<lb/>`, no
button.

## Import: where the setting comes from (Q23, Q28, Q22)

The setting always comes from the file; it does not join `@platform_owned`.

1. **The header carries it** (`encodingDesc/refsDecl`, below): the import takes it. If the play
   is not Manual and its numbers break that rule (the XML was edited by hand), the play is made
   Manual and the import reports it; nothing is recounted silently.
2. **No header setting** (every corpus file today): detection.
   - **Numbers present**: every type × restart (12 rules) is simulated over the play and
     compared with the stored numbers; a rule that matches exactly is taken, Manual off;
     otherwise the closest (fewest differing elements) is taken, Manual on. Ties go to the
     simpler rule: V, VP, VL, S, then never, act, scene (a play without prose fits V, VP and VL
     alike; a one-act play fits every restart).
   - **No number at all** (41 corpus files): V when the play has more verses than prose
     paragraphs, otherwise S; never restarting, Manual off, and numbered at import. This gives
     V to 0151, 0416, 0444 (mostly verse) and S to the other 38, as the researcher asked for
     the prose ones. It is the one case where the import writes numbers the file did not have.

**Plays already stored** (dev, production). The migration gives every existing play Manual on,
so no save recounts a play nobody has looked at (Hamlet would lose its "3-4"); new rows default
to Manual off. `Playcode.Release.settle_numbering/1` (`dry_run: true` first) then runs the same
detection over every stored play, as step 2 above, unnumbered plays numbered included, and
prints one line per play and a count per rule. Run once in dev and once on Fly, then Generate.

A file whose numbers fit its rule is not changed by the import. `preview_import/1` (admin import
page, `mix playcode.import.tei --dry-run`) reports what the import will set ("V per scene";
"V never, Manual: 3 numbers differ"; an unnumbered one "S never, numbers added"), computed by writing the play inside a transaction it
rolls back; the import prints the same per file.

## The TEI header (Q28)

Every export writes the setting as one `refsDecl` at the end of `encodingDesc`, standard TEI P5
(valid against `priv/schemas/tei_all.rng`, 4.11). The nesting is the restart, the innermost
`unit` the type; a Manual play's `refsDecl` has `n="manual"`.

```xml
<!-- V, restarting per scene -->
<refsDecl>
  <citeStructure unit="act" match="/TEI/text/body/div1" use="position()">
    <citeStructure unit="scene" match="div2" use="position()" delim=".">
      <citeStructure unit="verse" match=".//l[@n]" use="@n" delim=", "/>
    </citeStructure>
  </citeStructure>
</refsDecl>

<!-- S, never restarting, Manual -->
<refsDecl n="manual">
  <citeStructure unit="speech" match="/TEI/text/body//sp[(.//l | .//p)[1][@n]]" use="(.//l | .//p)[1]/@n"/>
</refsDecl>
```

| Type | innermost `unit` | `match` (relative form) |
|---|---|---|
| V | `verse` | `.//l[@n]` |
| VP | `line` | `.//l[@n] \| .//p[@n]` |
| VL | `printed-line` | `.//l[@n] \| .//p[@n] \| .//lb[@n]` |
| S | `speech` | `.//sp[(.//l \| .//p)[1][@n]]` |

Restart: one level (`never`, the innermost `match` made absolute under `/TEI/text/body`), two
(`act` > the type), three (`act` > `scene` > the type). The import recognises these 12 shapes
by their `unit`s alone; any other `refsDecl` counts as no header setting.

## The citation label follows the type (QC)

| Type | A verse's number | A paragraph's number | A passage range (statistics) |
|---|---|---|---|
| V | v. | (none numbered) | vv. |
| VP, VL | v. | l. | vv. |
| S | int. | int. | int. |

Placeholders until the researcher picks the words (a new question in `preguntas.html`). Where
it shows:

- the static site's cite button: the text block carries `data-cite-verse` and
  `data-cite-prose`, and `site.js` picks by the number's line (`p.pr` is prose) instead of its
  hard-coded `', v. '`;
- the statistics page's passage ranges (`verses_range/1`, "vv. 230–260"). The legend's
  "{n} vv." is a count of verses, not a number, and stays;
- the content editor's "v. %{number}".

The search results' references ("II, 1236") carry no word and stay so. They show the scene
("II.3, 45") only when the play restarts per scene, read from the setting.

## The setting replaces guessing on the site

`Edition.restarts?/1` (problem 3: "a number met again further on") goes. The anchors' unit is the
scene in a play whose `numbering_restart` is not `never`, as problem 3 built it; the references
add the scene only under `scene`.

## The admin

- **Play form:** the three fields (type, restart, Manual). A save that would change numbers
  (Manual switched off, or type or restart changed on a play that is not Manual) does not save
  at once: the form says "1,200 numbers will change" and saves on a second submit, then
  recounts. A change that moves no number saves at once; switching Manual on never asks.
- **Content editor:** the element form's number input shows only on a Manual play; otherwise the
  number shows read-only.

## Statistics (QB)

`verse_count` counts the structure: every verse once by its first piece, numbered or not
(today: the numbered ones, which in an S play counts speeches). Nothing else in the statistics
reads the setting (Q10).

## Non-goals

- The list of plays that break their rule and where staff see it (problem 6). This problem
  stores the Manual flag and reports detection at import.
- Moving a paragraph's number out of its text into a column.
- A bare `<lb/>` or a line-break button in the editor.
- The final label words (researcher).
- `/api/v1`: unchanged.

## Records

- `CONTEXT.md`: **numbering rule** (type, restart, Manual), beside *number* and *anchor*.
- `docs/tei-mapping.md`: the `refsDecl` line; prose and VL markers.
- `docs/schema.md`: the three `plays` columns; the recount.
- `docs/stakeholder/ida-y-vuelta.html`: a row for the numbering rule (admin, TEI export and
  import: yes).
- `docs/stakeholder/preguntas.html`: a new question for the label words, telling the researcher
  0151, 0416 and 0444 got V; republish the Questions and Round Trip artifacts.
- `docs/static-site.md`: the cite label.
- `docs/backlog.md` to `docs/history.md` when done.

## Tests

- **Counting**, each type × restart on a small TEI snippet through `TeiImport.import_file/1`,
  asserted on the export (`roundtrip/1`, `xml_elements/3`): a split verse, a prologue under
  each restart, a VL paragraph with inner markers, an S speech opening with an `F` piece.
- **Detection**: a file that fits a rule exactly keeps its numbers, Manual off; one that fits
  none (a stray number) comes in Manual with the closest rule; an unnumbered verse file gets V
  and numbers, an unnumbered prose file S; a header setting is taken; a header whose numbers
  break it comes in Manual. `preview_import/1` reports each.
- **Complete copy**: the three columns join the comparison by themselves; the rarer play is
  Manual with a non-default type and restart.
- **Editor through the LiveView**: inserting a verse in scene 2 of a V-per-scene play moves the
  later numbers of scene 2 only; a Manual play is untouched; the number input shows only on
  Manual; reordering scenes recounts.
- **Play form through the LiveView**: switching Manual off shows the count and saves on the
  second submit.
- **Static site**: the cite data attributes per type; the references read the setting.
- **Corpus check** (local, not CI): `settle_numbering(dry_run: true)` over the dev database
  (loaded from `doc/tei_corpus/`), rule counts compared with the handoff's table (299 exact, 45
  none, 41 unnumbered, give or take the prologue files); each difference explained before
  merging.
- **Existing tests** that import an unnumbered snippet now get numbers, and editor tests that
  type numbers into a play that is not Manual get them recounted: each is updated with a
  comment saying why (CLAUDE.md), a test that types numbers by setting its play Manual.
