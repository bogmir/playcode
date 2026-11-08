# Numbers as Written Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A verse line's `@n` is stored, shown and exported as the file writes it (`"3-4"`, `"124.1"`), so Hamlet's and Timon's numbers survive a round trip.

**Architecture:** `play_elements.line_number` goes from integer to text. The TEI parser stores the attribute as written, except that a value of digits only loses its leading zeros (`"0001"` to `"1"`, the 2026-11-06 decision). Every reader that assumed an integer takes the string: the site's anchors and margin, the statistics' labels, the content editor's field, `/api/v1`. Prose is not touched: its `p@n` stays the leading `<lb n>` marker (Q29, deferred to problem 4).

**Tech Stack:** Elixir/Phoenix, Ecto + PostgreSQL, Saxy parser, LiveView.

**Spec:** `docs/superpowers/specs/2026-11-08-numbers-as-written-design.md`

## Global Constraints

- Column keeps its name `line_number`; Ecto type `:string`, Postgres `text`.
- Digits-only values lose leading zeros (`"0001"` -> `"1"`); every other value is kept verbatim after trimming; empty is `nil`.
- `/api/v1` returns `line_number` as the string, same field.
- Prose paragraphs unchanged (`InlineMarkup.number_marker/1`, `paragraph_number/1` untouched).
- `parse_int/1` in `tei_parser.ex` stays for divisions (lines 1527, 1586); only line 1696 stops using it.
- TDD per `CLAUDE.md`; every new test proven with `bin/bites`; `mix format`; no Claude attribution in commits.

## Review Focus

1. `<l n="">`: no number, so no margin number and an anchor that is not `l` (Task 1 test).
2. A content-editor number cleared to empty: saved as `nil`, not `""` (Task 2 editor test).
3. A whole number that is a multiple of 5 still gets the site margin's `m5`; `"3-4"` never does (Task 2 site test).
4. `"3-4"` and `"3"` in the same play: two distinct anchors, `l3-4` and `l3`, neither suffixed (Task 2 site test).
5. A passage whose first verse is `"3-4"`: its statistics range reads `3-4` (Task 2 statistics test).

---

### Task 1: Store verse numbers as written

**Files:**
- Create: `priv/repo/migrations/20261108120000_line_number_as_text.exs`
- Modify: `lib/playcode/play_content/element.ex:56` (field type), `:24` (doc line)
- Modify: `lib/playcode/import/tei_parser.ex:1696` (new `verse_number/1` beside `parse_int/1`)
- Modify: `lib/playcode/import/word_parser.ex:894` (`Integer.to_string/1` of the counter)
- Modify: `lib/playcode/statistics/metrics.ex:103` (`is_integer` -> `is_binary`)
- Modify: `lib/playcode/export/static_site/edition.ex:432,435,473` (`is_integer` -> `is_binary`)
- Modify tests whose fixtures pass an integer (Ecto refuses to cast one to `:string`): `test/support/fixtures.ex:170`, `test/playcode/complete_copy_test.exs:255-336`, `test/playcode/statistics_test.exs:57,441,461`, `test/playcode/import/tei_parser_test.exs:86`, `test/playcode_web/live/admin/play_form_live_test.exs:222`, `test/playcode_web/controllers/api/play_controller_test.exs:192` (expects `"1"`; comment: the number is the file's string since 2026-11-08)
- Test: `test/playcode/tei_roundtrip_test.exs`
- Docs: `docs/schema.md` (a `play_elements.line_number` line), `docs/tei-mapping.md:41` (the `l` line)

**Interfaces:**
- Produces: `%Element{line_number: String.t() | nil}` everywhere; `TeiParser` private `verse_number(String.t() | nil) :: String.t() | nil`.

- [ ] **Step 1: Write the failing test** in `tei_roundtrip_test.exs`, beside the poem test (~line 1313):

```elixir
# Hamlet numbers a verse the editions split "3-4" and Timon one "124.1": the number is the
# file's, kept as written (it was cut to its leading digits, 3 and 124, before 2026-11-08).
# A padded "0007" comes back plain, as decided on 2026-11-06; an empty one is no number.
test "a verse line's number comes back as the file writes it" do
  xml =
    roundtrip(
      tei(
        body:
          ~s(<div type="poem"><lg><l n="3-4">Uno</l><l n="124.1">Dos</l><l n="0007">Tres</l><l n="">Cuatro</l></lg></div>)
      )
    )

  assert for({attrs, _} <- xml_elements(xml, "l", within: "body"), do: attrs["n"]) ==
           ["3-4", "124.1", "7", nil]
end
```

- [ ] **Step 2: Run it, watch it fail**

Run: `mix test test/playcode/tei_roundtrip_test.exs -k "as the file writes it"` (or by line)
Expected: FAIL, left `["3", "124", "7", nil]`.

- [ ] **Step 3: Migration**: `alter table(:play_elements), do: modify(:line_number, :text, from: :integer)`. No data moves: integers become their plain text. The table already has the content trigger.

- [ ] **Step 4: Schema and parser.** `field :line_number, :string`. In `tei_parser.ex:1696` call `verse_number(attr_value(attrs, "n"))`: trimmed; `""` -> `nil`; `~r/\A\d+\z/` -> `String.to_integer |> Integer.to_string`; else the trimmed string. Word parser: `Integer.to_string(:counters.get(verses.counter, 2))`.

- [ ] **Step 5: Readers that matched an integer**: `metrics.ex:103` and `edition.ex:432,435,473` guard `is_binary(n)`. Nothing else in `lib/` does arithmetic on the column (`tei_xml.ex:1332` `to_string/1`, the views interpolate).

- [ ] **Step 6: Migrate and run the test**

Run: `mix ecto.migrate && mix test test/playcode/tei_roundtrip_test.exs`
Expected: PASS.

- [ ] **Step 7: Fixtures to strings**, then `mix test 2>&1 | tail -10`. Expected: 0 failures. Any other failure is a reader this plan missed: fix it in place and add it to the Files list.

- [ ] **Step 8: Refactor while green**; `bin/bites lib/playcode/import/tei_parser.ex 'verse_number(attr_value(attrs, "n"))' 'parse_int(attr_value(attrs, "n"))' test/playcode/tei_roundtrip_test.exs` (types differ, so expect red); docs lines; `mix format`.

- [ ] **Step 9: Commit** `fix: a verse line's number is kept as the file writes it, "3-4" in Hamlet`, body naming the bites run.

### Task 2: Readers show the string

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex:749` (`rem(@el.line_number, 5)` -> `fifth?(@el.line_number)`, the helper at :876)
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex:3512` (`type="number"` -> `type="text"`)
- Test: `test/playcode/export/static_site_play_test.exs`, `test/playcode/statistics_test.exs`, `test/playcode_web/live/admin/play_content_editor_live_test.exs`, `test/playcode_web/controllers/api/play_controller_test.exs`

**Interfaces:**
- Consumes: Task 1's string `line_number`.

- [ ] **Step 1: Write the failing tests**
  - Site (the play page built from TEI, as the `.pn.m5` test at ~line 440 does): verses `n="3"`, `n="3-4"`, `n="5"`. Assert the verse anchors are `["l3", "l3-4", "l5"]`, the margin texts `["3", "3-4", "5"]`, and `.m5` only on `"5"`.
  - Statistics: a passage opening on `"3-4"` and closing on `"10"` gives `"from" => "3-4", "to" => "10"`; a character first speaking there gives `"line" => "3-4"`.
  - Editor: submit `#element-form` with `"line_number" => "3-4"`, then the Content tab shows `L3-4`; submit `""`, the line shows no `L`.
  - API: an element stored with `"3-4"` returns `"line_number" => "3-4"`.

- [ ] **Step 2: Run them**: `mix test <the four files>`. Expected: the site test FAILS (`rem/2` raises on a string); the editor test FAILS (`type="number"` input refuses `3-4` in `form/3`) or passes; record which. A test passing here is proven with `bin/bites` in Step 5 instead.

- [ ] **Step 3: Implement** the two Modify lines above.

- [ ] **Step 4: Run** the four files, then `mix test 2>&1 | tail -10`. Expected: 0 failures.

- [ ] **Step 5: Bites and refactor**: `bin/bites` each test that passed before Step 3 against the line it covers (statistics: the `is_binary` guard at `metrics.ex:103`; API: `line_number: element.line_number` at `play_controller.ex:199`); `mix format`.

- [ ] **Step 6: Commit** `fix: the site, statistics, editor and API take a verse number as a string`.

### Task 3: Records and the two plays

**Files:**
- Modify: `docs/stakeholder/ida-y-vuelta.html` (a dated line under *What has changed*: Hamlet's 235 and Timon's 61 verse numbers such as "3-4" now come back as written; "Last updated" date)
- Modify: `docs/history.md` (the item), `docs/backlog.md` (nothing open for problem 1; Q29 is in problem 4's handoff)
- Modify: `CONTEXT.md` only if it names the number's type

- [ ] **Step 1: Re-import EMOTHE0010 and EMOTHE0372 in dev**: `mix playcode.import.tei --force` restricted to the two files (see `docs/development.md` for the flag), then

Run: `PGPASSWORD=postgres psql -h localhost -U postgres playcode_dev -Atc "select count(*) from play_elements where line_number !~ '^[0-9]+$'"`
Expected: 296 (235 + 61).

- [ ] **Step 2: Records** as listed; `mix format`; `mix test --include slow 2>&1 | tail -10` and `node --test test/js/*.test.mjs`. Expected: 0 failures.

- [ ] **Step 3: Commit** `docs: verse numbers as written in the round-trip table and history`.

After merge, when the owner says: push deploys the migration to Fly; the owner then runs `mix playcode.fly.reimport files --dir DIR` with the two files (`!`, per memory), which Generates. No Deploy to emothe.uv.es.
