# Three fixes from the researcher's review of 0756's TEI

Handoff written 2026-11-09. The researcher compared the TEI that Playcode exported for
*La Diana* (EMOTHE0756) on 21 September with FileMaker's file. Checked again against
production today (`/export/<id>/tei`, downloaded 2026-11-09), most points are fixed:
- `@n` on `div1`;
- the stage direction inside the first verse;
- plain `n="1"`;
- the encoder's `resp` wording;
- `<revisionDesc>`;
- the paratext kinds;
- the scene as `<set>` after the cast list.

Three remain. Each is its own commit (TDD: red, green, refactor; `bin/bites` for every new
test).

## 1. The identifier prefix drops the play number on every play (bug, small)

**Seen:** `<sp who="#DIANA" xml:id="es-sp-1">`, `<div2 type="scene" xml:id="es-sc-1">`.
0755 gives `fr-sp-1`. The decision (problem 2, Q12;
`docs/superpowers/specs/2026-11-08-identifiers-on-export-design.md`; `docs/tei-mapping.md`
line 48) is `em0756-es-sp-1`.

**Cause:** `TeiXml.id_prefix/1` (`lib/playcode/export/tei_xml.ex`, about line 1739) matches
`~r/^EMOTHE(\d+)$/`. Real codes carry the title (`EMOTHE0756_LaDianaComedia`), so nothing
matches and every play takes the non-EMOTHE branch. The tests in
`test/playcode/tei_roundtrip_test.exs`, `describe "identifiers"` (about line 3860), build bare
codes (`"EMOTHE#{n}"`), which is why they pass.

**Fix:**
- Anchor only the start: `~r/^EMOTHE(\d+)/`.
- A failing test first, with a real-shaped code: `"EMOTHE0756_LaDianaComedia"` gives
  `em0756-es-sp-1`.
- Keep the non-EMOTHE test (an `AL0569_…` code gives `es-…`), and decide whether a code like
  `EMOTHE0756x` should still count as EMOTHE.
- Existing assertions that expect `es-sc-1` for an EMOTHE code (about lines 1610 and 3927)
  only look right because of the bug. Update them, with a comment.

**After merging:** every exported file's identifiers change (they are recounted on export
anyway), and the site doesn't use them (Q11), so nothing needs re-importing. Production gets
the fix on the next deploy. Generate is only needed if `Fingerprint` tracks the export module.

## 2. Notes inside a paratext are lost at import (bug, medium)

**Seen:** 0756's `introduccion_editor_digital` ends with
`<note><p>NOTA: Incluida en la edición de la obra de 1820: <emph>Œuvres de Jean Rotrou</emph>…</p></note>`,
and its `argumento` ends with `<note><p>NOTA: “Rotrou le Jeune”, es decir, Pierre Rotrou…</p></note>`.
Neither is in the dev database's `play_paratexts`, nor in production's export. The cast
list's note survives (`castList` already has `intro` and `note`, `tei_parser.ex` about line
1462).

**Cause:** `TeiParser.paratext/3` and `paratext_paragraphs/1` (`tei_parser.ex`, about lines
1398–1425) take only the div's direct `<p>` children, and `play_paratexts` has no column for a
note. `docs/tei-mapping.md` (line 32, `text/front/div`) doesn't mention notes, and the backlog
doesn't either.

**Scope** (corpus scan, 2026-11-09): 33 notes inside `<front>` paratexts (cast lists left
out), in 19 files:

| By kind | Notes |
|---|---|
| prologo | 11 |
| dedicatoria | 9 |
| argumento | 5 |
| introduccion_editor_digital | 3 |
| epistola | 2 |
| circunstancia_accion | 1 |
| title_page | 1 |
| head_title | 1 |

| By file | Notes |
|---|---|
| 0030, 0133, 0310, 0755 | 3 each |
| 0709 | 4 |
| 0058, 0719, 0756 | 2 each |
| 0113, 0117, 0161, 0210, 0237, 0705, 0706, 0713, 0721, 0728, 0739 | 1 each |

By position:
- **30** are the div's last child: a note closing the paratext, as in 0756.
- **3** sit inside a `<p>`: 1 as its last child, 2 in the middle (anchored to a word). Find
  them first.
- Also scan paratexts *between or after* the acts (`div1 ana="paratexto"`, `<back>`), which
  this scan didn't cover.

**Proposed design** (settle it with the owner before building):
- A `note` column on `play_paratexts`, the same shape as a cast list's note: paragraphs, with
  `<<…>>` italics and `\n` line breaks.
  - Import: the div's closing `<note>`.
  - Export: `<note><p>…</p></note>` as the div's last child.
  - Print it after the paratext on the play page, HTML/PDF/EPUB and the static site, styled
    as the cast list's note is.
- The 3 notes inside a `<p>`: either append them to the same column (losing the anchor), or
  keep them inline as play notes are. Decide once you've seen them.
- Under the complete-copy rule:
  - the column joins `complete_copy_test.exs` by itself; fill it in the rarer play;
  - give it a row (or a line in the paratexts row) in
    `docs/stakeholder/ida-y-vuelta.html`;
  - add it to `docs/tei-mapping.md` line 32 and to `docs/schema.md`.
- `play_paratexts` already has its `play_row_changed()` trigger; check it.
- A re-import replaces `"tei"`-origin paratexts, so the corpus files bring the notes back on
  the next re-import of those 19 plays (dev, then production, then Generate).

## 3. A space appears after a stage direction inside a line (small; check first)

**Seen:** the source has
`<stage xml:id="em0756-es-st-0001">(sola, con el nombre de Celirea)</stage>El Sol ha abandonado…`.
The dev database stores `<stage>(sola, con el nombre de Celirea)</stage> El Sol ha abandonado…`,
so the space is added at **import**, and the export writes it back.

**Check first:**
- Is it deliberate? Look for a comment or a history entry about joining a stage direction to
  the following text: the parser's text joining, `lines_text/1` and the inline-marker
  building.
- Is it everywhere? Count corpus lines where `</stage>` touches a letter, against stored
  contents with `</stage> `.
- The reading pages may rely on the space to separate the stage from the words.

**If not deliberate:** keep the text as written, with no added space.
- Test: a round trip of `<l><stage>(aparte)</stage>Texto</l>` gives the same content back.
- Make sure the HTML still separates the two visually, through CSS rather than a stored
  character.
- Stored rows change only on re-import.

## Records

- `docs/backlog.md`: one item for the three (added with this file), moved to
  `docs/history.md` when done.
- `docs/tei-mapping.md`: lines 32 (paratext notes) and 48 (the prefix example still holds).
- `docs/stakeholder/preguntas.html`: no question needed. Optionally, under "Files corrected"
  or in a reply, tell the researcher that the paratext notes are back. Q34 still stands:
  don't announce identifier details.

## Suggested skills

- `superpowers:test-driven-development`;
- `superpowers:systematic-debugging` for fix 3's cause;
- `mattpocock-skills:grilling` for fix 2's design choices;
- `superpowers:finishing-a-development-branch` (merge locally; no PR; push only when told).
