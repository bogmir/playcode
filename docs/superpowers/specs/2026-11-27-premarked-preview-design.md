# Premarked text: paste it, see the play, then import

Option A of `tmp/mockups/premarcado.html`. The brief: `tmp/prompts/premarcado-a.md`. The
screen, with the choices made: `tmp/mockups/premarcado-a-pantalla.html`.

## Why

Today a researcher uploads a premarked .docx on the play's page and the play's text is replaced
at once. A mistyped tag, a speaker's name tagged as prose or an untagged note becomes stored
text, found only afterwards, one line at a time, in the content editor. Bartholomew Fair's file
alone has 30 names tagged as prose, 32 untagged paragraphs and one `{R}`.

The goal: the researcher sees the play exactly as the import would store and print it, with
every problem tied to its line, while there is still nothing to undo.

## Goals

- One page per play: paste the premarked text, or drop the .docx; the play as it would be
  stored appears beside it, updated after a short pause in typing, with no button.
- The preview is what `import_content` stores, from the same parser, printed by the same
  component as the play's preview page.
- Warnings, each tied to its paragraph; choosing one selects the line in the text box and shows
  it in the preview.
- A summary above the preview: acts and scenes, verses, speakers with their speech counts.
- Import is one button, the same import as today; warnings never block it (a row the database
  would refuse is an error, not a warning, and does: see *Warnings*).
- `((…))` is read as the aside it marks (the owner's decision, 2026-11-27).

## Non-goals

- Guessing tags from an unmarked text (option B).
- Keeping the premarked text with the play after the import.
- A tag-colouring editor: the text box is a plain `<textarea>`.
- Replacing the regex reading of `document.xml` (`docs/backlog.md`), unless a test shows the
  preview needs it.

## Anti-goals

- A second reading of the tags written for the preview. If the preview and the import can
  disagree, the page is worse than none: it would vouch for a text the import then stores
  differently.
- Anything written to the database before the researcher presses Import.

## Approaches

1. **Run the import in a transaction and roll it back** (what `TeiImport.preview_import/1` does
   to settle its numbering), then load the play and print it. Exact by construction. Measured
   on Bartholomew Fair (2,174 paragraphs): 3.4, 3.6 and 4.7 s, median 3.6 s, with dev query
   logging on. Too slow to run on every pause, and each run holds a transaction that deletes
   the play's text.
2. **Print the parsed structure with a renderer of its own.** Fast, but a second printer that
   drifts from the play page's.
3. **Build the rows in memory, once, for both** (chosen). `WordParser` turns paragraphs into the
   division and element structs the import would insert, each with an id generated in memory
   and the paragraph it came from. The import inserts those structs; the preview numbers them
   with `Numbering.expected/3` (pure) and prints them with `PlayText.play_body`. Parsing
   Bartholomew Fair in memory takes 38–62 ms (median of three: 41 ms). One builder, one printer:
   the preview cannot drift from the import without the tests that compare them failing.

## The design

### Parser (`lib/playcode/import/word_parser.ex`)

The public surface becomes:

- `WordParser.paragraphs(path)` → `{:ok, [String.t()]}`: the .docx's paragraphs, as
  `extract_paragraphs/1` reads them today. The drop zone uses it to fill the text box.
- `WordParser.paragraphs_from_text(text)` → the pasted text split on newlines, blank lines kept
  as empty entries so that a paragraph's index is its line in the text box (**my call**: the
  hook then maps caret to line with no table). The parser skips an empty paragraph, as today; a .docx paragraph holds no newline (`extract_paragraphs`
  joins `w:t` runs), so text from a .docx survives the text box unchanged.
- `WordParser.draft(paragraphs, play)` → `%{divisions, paratexts, warnings, summary}`:
  - `divisions`: the top-level `%Division{}` structs in the shape `PlayContent.load_play_content/1`
    returns (cast list with its entries and characters, acts with children and
    `loaded_elements`, elements with `children`, `notes: []`, `element_characters`), numbered by
    the play's rule (`numbering_type`, `numbering_restart`) through `Numbering.expected/3`, as
    the import's `refresh_derived/1` numbers them, since the import sets `numbering_manual: false`.
  - `paratexts`: what the stored play's outline would hold: the play's paratexts the import
    keeps (every one not of origin `"word"`, passed in by the caller, so `draft/2` stays pure)
    plus the new front matter of origin `"word"`, at the positions the import gives them today
    (front matter 0, cast list 1, acts from 2). **My call**: the preview prints them, so it
    shows what the play page would. Those fixed positions can collide with a kept paratext's
    (the digital-edition note every new play starts with sits at 0): that is today's
    behaviour, not changed here; the comparison test below covers it and an item in
    `docs/backlog.md` records it.
  - `warnings`: `%{line: index, kind: atom, text: snippet}`, `line` the paragraph's index in the
    list given, in text order.
  - `summary`: `%{acts, scenes, verses, speakers: [{label, speeches}]}`, speakers by count,
    descending.
  - every element and division carries the paragraph it came from (a `line` map, element id →
    paragraph index, beside the structs; the schema gets no new field).
- `WordParser.import_content(play_id, paragraphs)` inserts exactly the structs `draft/2` built
  (same ids, positions, contents), in the transaction and with the deletes it has today, then
  `refresh_derived/1`. `import_content(play_id, path)` stays for the tests and reads the
  paragraphs first. The old card's caller goes away.

How the inserts reuse the structs (insert each through the existing `create_element` /
`create_division` changesets with the id preset, or `insert_all` after validating each
changeset) is the builder's call. The validation `Element.changeset` does today must still run.

### Asides

- `((…))` inside a `{pr}` or verse segment becomes an `<aside>` marker around those words
  (`InlineMarkup.aside_marker/0`), the rest of the line ordinary speech: a line partly spoken
  aside, as `docs/tei-mapping.md` (`seg[@type="aside"]`) stores one.
- `{ap}` in a paragraph that has `((…))`: its text ("(Aparte)") is the delivery, kept as a
  `<stage>` marker right before the aside, as the TEI import keeps a delivery stage. The
  paragraph is not wholly aside. **My call**, from the convention the exercise shows; the
  owner can overrule it.
- `{ap}` in a paragraph with no `((…))`: as today, the whole paragraph aside, its text dropped.
- First, a test pinning today's behaviour (`((…))` left as typed; "(Aparte)" dropped), then the
  change, red to green.
- `docs/tei-mapping.md` and `docs/stakeholder/ida-y-vuelta.html` gain the Word side of this.

### Warnings

Each a kind with its own Spanish message, tied to its paragraph:

| kind | when |
|---|---|
| `:untagged` | a paragraph after the first act or scene with no tag that is not an act heading (stored `unrecognized`) |
| `:unknown_tag` | `{x}`-shaped text that is not one of the eleven tags, left in the text as typed (`{R}`) |
| `:dropped_text` | text before a paragraph's first tag, which the parser drops today |
| `:part_without_initial` | a `{tm}` or `{tf}` with no open `{ti}` before it |
| `:initial_unfinished` | a `{ti}` no `{tf}` closes before the next `{ti}` or a whole verse |
| `:speaker_as_words` | a `{pr}` or verse piece whose whole text is one of the play's speaker labels |
| `:end_marker` | `{e}THE END` and the like, kept as an unrecognised line on purpose |
| `:unclosed_aside` | a `((` with no `))` in the same paragraph |
| `:refused` | a row `Element.changeset` refuses (malformed inline markup: an unclosed `<<`, a stray marker). An **error, not a warning**: today `create_element` rolls the whole import back on it (`ok_or_rollback`), so the Import button is disabled while one remains, saying which line. **My call**: the import cannot store it, and dropping it silently would break the anti-goal. `draft/2` runs the changeset on every row (pure, no database) |

`:dropped_text` and `:unclosed_aside` are additions to the brief's list. The warnings come from
the same pass that builds the rows, not a second scan, except `:speaker_as_words`, which needs
every label first and runs over the built rows.

### The page

- Route `live "/admin/plays/:id/premarked", PlayPremarkedLive, :index`, in the researchers'
  scope beside the play's other tabs; the play's page's "Replace the text from Word" card (shown
  only while the play is not complete) becomes a link to it. A complete play's page shows no
  link, and the route sends a complete play back to its page with a flash, as the card's
  absence does today.
- Wide screens: text box left, preview right. Below about 900 px: one above the other.
- Left: a labelled `<textarea>` (`phx-change`, `phx-debounce="400"`), a .docx drop (LiveView
  upload; on drop, `WordParser.paragraphs/1` fills the text box and the preview), a folded
  `<details>` legend of the tags, `((…))` and `<<…>>`.
- Right: the summary (counts; speakers as chips, a one-speech speaker marked), the warning list
  (buttons, "línea N: message: «snippet»"), then the preview, a focusable named region
  (`tabindex="0" role="region" aria-label`) printing `PlayText.play_body` over the draft.
- A warning's line in the preview: a mark in the margin. `PlayText` gets one optional attr, a
  map element id → `%{line, warn?}`, rendered as `data-line` and `data-warn` on the element's
  wrapper; the play page passes nothing and prints as today.
- Scrolling is linked: moving the caret in the text box scrolls the preview to that paragraph's
  element (the nearest one before it, when the paragraph made none); clicking an element in the
  preview selects its paragraph in the text box; choosing a warning does both. One JS hook
  (`PremarkedText`), browser-side only: no event round trip for scrolling.
- The text survives a reload: the hook keeps it in `localStorage` under the play's id, restored
  on mount and pushed to the server, cleared after a successful import. `localStorage` failing
  (private window) leaves the page working, empty.
- Import: one button, stating what it replaces (the play's text, characters and notes) and what
  it keeps, in `ImportLive`'s wording; it runs `import_content/2` over the text box's paragraphs
  and redirects to the play's page with the count, as the card did.
- An empty text box: no preview, no import button enabled.

### Browser input

The text and the line number of a "go to" are the browser's. The text is bounded (the upload's
10 MB limit applies to the .docx; the textarea gets a server-side cap of the same order, beyond
which the preview says it is too long). A line number only drives the hook; the server never
indexes by one it received.

### Performance

The preview re-parses the whole text on every pause: about 40 ms for Bartholomew Fair in
memory, plus building the structs, numbering and rendering. The plan's last task measures the
whole round trip (median of three) on that file; if it is over ~300 ms, the fix is proposed
before it is built.

## Tests

- Parser, through `WordParser`'s public functions, asserted as what the play then exports
  (`docx/1`, `roundtrip`-style helpers): `((…))` as an aside, `{ap}(Aparte)` as delivery, the
  exercise and Bartholomew Fair producing the warnings the brief names.
- **The preview is the import**: for the exercise and for Bartholomew Fair, `draft/2`'s divisions
  and elements equal `load_play_content/1` after `import_content/2` over the same paragraphs
  (content, type, part, number, aside fields, order) and the outline's paratexts in order, the
  test that keeps approach 3 honest.
- The page through `live/2`, `render_change/1`, `render_submit/1`, uploads: a clean text shows
  no warnings; a text with every kind shows each; import replaces and redirects; nothing is
  written before.
- `authorization_test.exs` row (researchers yes, visitors no), `accessibility_test.exs` path.
- The hook's pure parts (caret offset ↔ paragraph index) under `node --test`, if any are pure.

## Left to the builder

- How `draft/2` and `import_content/2` share the struct-building code internally.
- The hook's exact scrolling offsets.
- Spanish wording, through gettext, with the glossary's words (`CONTEXT.md`).
