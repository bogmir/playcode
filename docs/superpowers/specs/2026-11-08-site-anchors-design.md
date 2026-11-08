# Static-site anchors from the number (problem 3)

Problem 3 of six on numbering and identifiers (index: `/tmp/playcode-numbering/00-README.md`,
decisions Q4 and Q11 in the 2026-11-07/08 grilling). Problems 1 (numbers as written) and 2
(identifiers on export) are merged; this one only reads what problem 1 stores.

## Why

A line's anchor is its address on the static site: `act-1.html#l230`. A reader gets it by
clicking a margin number (the cite button copies "La vida es sueño, v. 230. <url>"), and the
site itself links to it from search results, the Notes page and the stage-directions list.

Today only a numbered verse's address follows what the reader sees. Everything else (stage
directions, prose, a split verse's later pieces, verses in unnumbered plays) gets `p<k>`, one
counter through the whole play, so a stage direction added in act 1 moves every such address in
acts 1 to 5, and a saved link lands on the wrong line.

After this change an address is built from the nearest number the reader sees, plus a counter
of its own kind. It moves when the printed citation moves (a recount turns v. 230 into v. 231,
problem 4), or when something of the same kind is inserted in the small gap between that number
and the line. Nothing else moves it, and anyone can work it out from the page: "the 2nd stage
direction after verse 230".

Endings asks for stable page URLs (§5.5) and says nothing about fragments; this is as stable as
an address can be without stored identifiers, which Q2/Q11 ruled out.

## Goals

- Every verse, prose paragraph and stage direction on a play page gets an anchor built from the
  play's numbers, per the rules below.
- A numbered prose paragraph's printed number becomes a link to its own anchor, as a verse's
  number is, so the cite button works on it.
- No TEI identifier reaches the HTML (Q11). None does since problem 2; this keeps it so.

## Non-goals

- Writing numbers. Problem 3 reads `@n`; it never changes it, the TEI or the database.
  Recounting is problem 4.
- The cite label. It stays "v." for every number, prose included, until problem 4 gives the
  play a numbering type.
- Knowing whether a play restarts per act or per scene. The existing detection (`restarts?/1`:
  a number repeated in another division or scene) stays; problem 4's setting replaces it.
- Search-result references ("II, 1236"): unchanged; a prose paragraph's reference stays its
  division alone.
- Anchors inside a paragraph: a prose paragraph's inner printed line numbers (`<lb n>` after its
  start) stay plain text, not links and not anchors.
- Openers and trailers, cast lists, paratexts, divisions: their anchors do not change.
- Redirecting old addresses. `#p<k>` links break once; the site's builds since 2026-11-06 are
  unpublished anyway (deploy blocked).

## The rules

**A number** is a verse line's `line_number`, or a prose paragraph's own number (the
`<lb n="…"/>` marker at the very start of its text, `InlineMarkup.paragraph_number/1`). Inner
`<lb n>` markers are not numbers here.

**The unit** is where "the nearest number" is looked for and where counters start again:

- a play whose count restarts (`restarts?/1`): the scene (its division and scene, `item.act`,
  `item.scene_number`), and every anchor in it carries the prefix `l<act>-<scene>-`
  (`item.act || 0`, `item.scene_number || 0`, as today);
- any other play: the whole play, across its pages. (Ruled while building: the spec first said
  the page, but `text.html` prints every page at once, so page-scoped counters gave it
  duplicate ids. Across pages a continuous play's numbers are unique anyway, so act 2 opens
  with `l<last verse of act 1>-sd1` and stays as stable; only a play with no numbers at all
  counts `v`, `p`, `sd` through the whole play, until problem 4 numbers it.)

**Anchors**, continuous play / per-scene play at act 1, scene 2:

| Element | Continuous | Per scene |
|---|---|---|
| A numbered verse or numbered prose paragraph | `l230` | `l1-2-230` |
| A split verse's later piece without a number of its own | `l230b`, `l230c` | `l1-2-230b` |
| A piece with a number of its own (Hamlet numbers each piece) | `l962` | `l1-2-962` |
| A stage direction after a number | `l230-sd1`, `l230-sd2` | `l1-2-230-sd1` |
| An unnumbered prose paragraph after a number | `l230-p1` | `l1-2-230-p1` |
| An unnumbered verse after a number (S plays number only a speech's first line) | `l230-v1`; its later pieces `l230-v1b` | `l1-2-230-v1` |
| Any of those before the unit's first number | `sd1`, `p1`, `v1`, `v1b` | `l1-2-sd1`, `l1-2-p1`, `l1-2-v1` |

- The three counters (`sd`, `p`, `v`) are separate, start at 1 after each number, and start
  again in each unit. A stage direction never moves a verse's address, nor the reverse.
- A later piece is a verse line with `part` M or F and no number of its own, following a verse
  that opened (whole or first piece, numbered or not). It takes that verse's anchor plus `b`,
  `c`… in order. Stage directions or prose between pieces do not end the verse. A piece with
  no opened verse before it in the unit (a data error) is counted as an unnumbered verse.
- The number goes into the anchor as written: "3-4" gives `l3-4` and `l1-2-3-4` (Q3: the
  separator stays `-`; act and scene are whole numbers, so the first two dashes split them
  off). "3153c" and "124.1" go in as they are.
- **Clashes** (a number repeated within a unit, "3153c" against verse 3153's third piece) get
  `-2`, `-3`… (`unique/3`, unchanged), checked across the play.
- `restarts?/1` takes numbered prose paragraphs as numbers too, so a VP play numbered per scene
  is detected as one.

### Example: `act-1.html` of a continuous play

| Reader sees | Today | After |
|---|---|---|
| *Sale el REY.* | `p1` | `sd1` |
| REY ¿Quién va? **1** | `l1` | `l1` |
| Ya el sol se esconde. **2** (first piece) | `l2` | `l2` |
| CRIADO Yo, señor. (second piece, no number) | `p2` | `l2b` |
| REY (Aparte) Mal me sirve este criado. **3** | `l3` | `l3` |
| *Vase el criado.* | `p3` | `l3-sd1` |
| *Sale la REINA.* | `p4` | `l3-sd2` |
| REINA Señor, os traigo nuevas… **4** (prose, numbered) | `p5` | `l4`, and **4** is a link |
| …y así lo cuentan todos. (prose, no number) | `p6` | `l4-p1` |

`act-2.html` opens with a stage direction after act 1's last verse, 1500: `l1500-sd1`. An S play's speech 12 continuing over three
verses: `l12`, `l12-v1`, `l12-v2`; a per-scene play's scene 2 opening with a direction: `l1-2-sd1`.

### The numbered paragraph's link

The paragraph's leading number renders as `<a class="pn" href="#<anchor>">230</a>` instead of
`<span class="pn">230</span>` (keeping `m5` on every fifth), so:

- the "Line numbers" control and print CSS (`.pn` selectors in `style.css`) still hide and show
  it;
- the cite button (`site.js` `initLinks`, `a[href^="#l"]`, copies the link's text after ", v.")
  picks it up with no JS change.

Notes are placed by grapheme offset in the plain text and a number marker has none, so taking
the leading marker off before `Components.inline/1` does not move a note (check it in a test).

## Where the change lands

- `lib/playcode/export/static_site/edition.ex`, `anchors/2` and `restarts?/1` (and the comment
  above them): the rules above. Items carry `kind` (`:verse`, `:prose`, `:stage`), `act`,
  `scene_number`, `division`, `scene`; `page_of/2` maps an element to its page slug.
- `lib/playcode/export/static_site/components.ex`, the prose `el/1` clause: the leading number as
  a link. The comment on `part(%{number: n})` ("Not a link…") is rewritten: inner numbers stay
  plain, the paragraph's own number links.
- Nothing in `search.ex`, the Notes page or the stage-directions list: they read
  `edition.anchors`.
- `site.js`: no change.

## Tests

Through the export (`publish!/1`, as in `test/playcode/export/static_site_play_test.exs`):

1. The continuous example page above: every `id`, in order.
2. A per-scene play: `l1-2-1`, `l1-2-sd1` for scene 2's opening direction, both scenes on one
   page, no duplicate ids (the existing restart test grows into this).
3. An S-style page: a numbered first line, then unnumbered verses and a split unnumbered verse:
   `l12`, `l12-v1`, `l12-v1b`; and before any number `v1`.
4. Hamlet's pieces numbered each: `l961`, `l962`, and an unnumbered piece after `l962` is
   `l962b`.
5. Stability: two plays identical except for one extra stage direction early in act 1; act 2's
   ids are the same in both, and in act 1 only the directions after the same number differ.
   It also covers test 7 as ruled: act 2 opens with `l2-sd1`.
6. A numbered paragraph: `p#l4` holds `a.pn[href="#l4"]` with text "4", its inner `<lb n>`
   numbers stay `span.pn`, and a note in it stays where it was.
7. ~~Per-page clash scope~~: dropped with the ruling above; the existing full-text test
   ("a division too long for one page", ids unique on `text.html`) guards it instead.

Each new test is shown to bite (`bin/bites`). Existing tests asserting `p<k>` anchors are
updated, with a comment saying why.

## Records

- `docs/static-site.md` line 10: the anchor forms.
- `CONTEXT.md`: **Anchor** (an element's address on the static site, built from the nearest
  number; not the identifier, not the number), beside *Number* and *Identifier*.
- `docs/backlog.md`: the item "An unnumbered verse's anchor on the site moves again" moves to
  `docs/history.md`.
- `docs/stakeholder/ida-y-vuelta.html`: no row covers site addresses; unchanged (my call).
- `/tmp/playcode-numbering/00-README.md` row 3 and the grilling memory: decided, spec here.

## Decided in the 2026-11-08 session

- Q1 (this problem): a numbered prose paragraph gets `l<n>` and its number becomes a link.
- Q2: nearest number plus counter; per-scene plays look only inside the scene and keep the
  prefix (`l1-2-sd1`). A play-wide counter was rejected: one insertion moves every address after
  it.
- Q3: the separator stays `-`.
- Q4: unnumbered verses get their own `v` counter. Not interim: S plays number only a speech's
  first line, so most of their verses are unnumbered for good.

## Calls made while writing (check these)

- ~~Clash checking per page~~: ruled out while building (`text.html`); the unit and the clash
  check are the play.
- `restarts?/1` counts numbered paragraphs as numbers.
- An orphan piece counts as an unnumbered verse.
- No JS test: `site.js` does not change; test 6 asserts the markup the cite button selects.
- Search references for prose unchanged.
