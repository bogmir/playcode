# Problem 1: keep `@n` exactly as written

## What it is for

A verse's number is what a reader cites. Today Playcode keeps only the number's leading digits,
so some numbers come back from export wrong, and two different lines can end up with the same
anchor on the site. After this change, whatever `@n` a file writes is what Playcode shows and
exports.

## How it works today

- Verse lines: `play_elements.line_number` is an integer. `TeiParser.parse_int/1`
  (`lib/playcode/import/tei_parser.ex`, around line 2559; called at line 1696) runs
  `Integer.parse` and keeps the leading digits.
- Prose paragraphs: `p@n` is not a column at all. It is stored as the marker `<lb n="12"/>` at
  the start of the paragraph's text (`prose/2`, about line 1870).
  `InlineMarkup.number_marker/1` (`lib/playcode/play_content/inline_markup.ex:368`) drops any
  value that does not match `[A-Za-z0-9.-]`. `TeiXml` reads it back with
  `InlineMarkup.paragraph_number/1`.
- Line breaks inside prose: `lb@n` is the same kind of marker, inside the text (`line_break/1`,
  about line 2057).
- Padded numbers (`0001`) are already fixed: the export writes `1` (`fix/plain-line-numbers`,
  merged).

## What changes (decided 2026-11-08)

1. A verse's `@n` is stored as a string, exactly as written: `"3-4"`, `"124.1"`, `"230"`.
   The column keeps its name, `line_number`: it still holds verse numbers only.
2. `/api/v1` returns `line_number` as that string, in place (no known outside client).
3. Prose is unchanged. Q29 (move `p@n` from the leading marker into the column) is deferred
   to problem 4: today's round trip of prose numbers is exact (52,571 prose rows in dev, no
   corpus paragraph opens with a numbered `<lb>`, so the shared storage never collides), and
   the column would only spare a recount the leading marker, while a rule numbering printed
   lines rewrites every inner `<lb n>` in the text anyway.
4. Scope in the corpus: Hamlet (EMOTHE0010, 235 verse numbers like "3-4") and Timon of Athens
   (EMOTHE0372, 61) are the only files that lose a verse number today.

## Step by step

**Hamlet, a verse numbered "3-4"**
- File: `<l n="3-4">…</l>`.
- Today: `line_number = 3`, so the export writes `n="3"`, the site anchor is `#l3`, and it
  clashes with the real verse 3.
- After: the value `"3-4"` is stored, exported as `n="3-4"`, and printed as "3-4".

**Every fifth number in the margin**
- `components.ex` (about line 749) prints a number when `rem(line_number, 5) == 0`.
- With strings, it prints only when the value is a whole number divisible by 5. `"3-4"` is
  never printed in the margin, but it is still the verse's label.

## What reads `line_number` (all must take the string)

| Where | Files |
|---|---|
| Import | `tei_parser.ex`, `word_parser.ex` |
| Export | `tei_xml.ex`, `download.ex`, `compare_html.ex`, `static_site/edition.ex`, `static_site/components.ex` |
| Statistics | `statistics/metrics.ex`: `number_fragments/1`, `passages/1`, `add_verse` from/to, `line/1` |
| Web | `play_text.ex`, `play_show_live.ex`, `play_compare_live.ex` (two of them), `play_comparison.ex`, `play_content_editor_live.ex`, `catalogue.ex`, `demo_ui_controller.ex` |
| API | `api/play_controller.ex`: `/api/v1` returns `line_number`, now the string. |

## How it interacts with the others

- **Problem 3** builds anchors from this string. Watch out: `"3-4"` inside the act-scene form
  `l1-2-3-4` is ambiguous (problem 3 decides the separator).
- **Problem 4** recounts by writing this column for verse, and rewriting the leading and
  inner `<lb n>` markers for prose. Q29 is decided there.
- **Statistics** count from the structure (`part`, element types), never from the number
  (Q10). The number only labels a passage's range and where a character first speaks, so
  those labels become strings.

## Records and tests

- **Migration:** `line_number` integer to text, `USING line_number::text`: no stored value changes, and
  Hamlet and Timon get their full numbers by re-importing them (see `docs/development.md` and `docs/production-reimport.md`).
  `play_elements` already has the `content_version` trigger.
- **Tests:** a round trip of `<l n="3-4">` and `<l n="124.1">` in `tei_roundtrip_test.exs`; the
  `complete_copy_test.exs` comparison; a metrics label test.
- **Docs:** `docs/schema.md`, `docs/tei-mapping.md`, the row in `ida-y-vuelta.html`.

## Open

Nothing. Q29 moved to problem 4.
