# Aside Chains Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Playcode knows which pieces of an aside make one aside: it reads that from a TEI file,
writes it back as sound `xml:id`/`next` chains, labels each aside once on the site and counts
asides, not pieces.

**Architecture:** One boolean, `play_elements.aside_continues` (the element's first piece
continues the aside of the last piece before it, in reading order); pieces later in the same
element are worked out from the text by `Element.asides_started/1`, which every reader counts
from. The TEI parser decides the column by four ranked rules; the export numbers and links every
piece in a pass over the play's reading order, as `TeiXml.with_folio_parts/1` does for the Folio.

**Tech Stack:** Elixir 1.19, Phoenix LiveView 1.1, Ecto/PostgreSQL, Saxy, xml_builder.

**Spec:** `docs/superpowers/specs/2026-10-25-aside-chains-design.md`

## Global Constraints

- TDD per `CLAUDE.md`: failing test, watch it fail, smallest code, pass, **refactor while green**, `mix test` whole suite, then commit.
- Tests go through the outer API: TEI as round trips (`import_tei!/1`, `roundtrip/1`, `export_tei/1`, `xml_elements/3` in `test/support/import_helpers.ex`), counts through `Statistics.get_statistics/1`, the site through `generate!/2`, the Content tab through `live/2`. Never `Repo` in a test.
- The column is not `@platform_owned`: a re-import writes it.
- Piece identifiers end `-segNN`, NN two digits, more past 99; `next` is always `#` plus an identifier in the file.
- The parser's rules, in order (spec, *Reading a file*): number (`-segNN`, NN ≥ 1: 01 starts, ≥ 02 continues); links (named by another piece's `next`, with or without `#`, not itself: continues; has an `xml:id` no `next` names: starts); a `<stage type="delivery">` right before the piece in its element: starts; otherwise continues when the line or paragraph before it in the same speech holds an aside.
- Within one element, a later piece starts a new aside only when spoken words stand between it and the piece before (stage markers, `<lb …/>` markers and italics markers are not spoken).
- `mix format` and `mix compile --warnings-as-errors` before every commit; commit messages end with the `Co-Authored-By` line.

## Review Focus

1. **Deleting the verse an aside starts on.** The next verse of the aside should start it, not join an earlier aside (perhaps another speaker's). Test in Task 5.
2. **Two asides starting in one line** (`<l xml:id="es-0001"><seg>a</seg> dicho <seg>b</seg></l>`). Both are `seg01`; their identifiers must still be unique, or the file is invalid. Test in Task 3.
3. **A piece in a paragraph, with no line identifier.** It needs an identifier no line can take, the same on every export. Test in Task 3.
4. **A line aside only by its delivery stage, with no `<seg>`** ("No seg" in `tei_roundtrip_test.exs`). It counts as one piece and must be decided like any other. Test in Task 2.
5. **Word asides in consecutive paragraphs.** They become one aside, and a new speech starts a new one. Test in Task 5.

---

### Task 1: The column, and asides counted once

**Files:**
- Create: `priv/repo/migrations/20261025120000_add_aside_continues_to_play_elements.exs`
- Modify: `lib/playcode/play_content/element.ex` (schema, `changeset/2`, new `asides_started/1`)
- Modify: `lib/playcode/statistics.ex:218` (`count_asides/1`)
- Modify: `lib/playcode_web/controllers/api/play_controller.ex` (`serialize_element/1`, verse line and prose)
- Test: `test/playcode/statistics_test.exs`, `test/playcode/play_content_test.exs`, `test/playcode_web/controllers/api/play_controller_test.exs`

**Interfaces:**
- Produces: `Element` field `aside_continues :boolean, default: false`, cast by `changeset/2` and stored false unless `type in ~w(verse_line prose)` and `is_aside`.
- Produces: `Element.asides_started(element) :: non_neg_integer`, how many asides start in the element: 0 when not `is_aside`; for a line all aside (`whole_aside?/1`) 1 unless `aside_continues`; with `<aside>` markers, the first marker counts unless `aside_continues`, and each later marker counts when spoken words stand before it.
- Produces: statistics `"total_asides"` = the sum of `asides_started/1` over the play's elements.

- [ ] **Step 1: Write the failing tests**

In `statistics_test.exs`, built like its first test (`play_with_structure_fixture/0`, `PlayContent.create_element/1`):

```elixir
test "an aside over several verses counts once; a paragraph with two asides, twice" do
  %{play: play, line_group: group, scene: scene} = TestFixtures.play_with_structure_fixture()
  base = %{play_id: play.id, division_id: scene.id, parent_id: group.id, type: "verse_line", is_aside: true}

  for {content, continues, position} <- [{"uno", false, 10}, {"dos", true, 11}, {"tres", true, 12}] do
    {:ok, _} = PlayContent.create_element(Map.merge(base, %{content: content, aside_continues: continues, position: position}))
  end

  {:ok, _} =
    PlayContent.create_element(%{play_id: play.id, division_id: scene.id, type: "prose", position: 13,
      content: "<aside>a</aside> <lb n=\"2\"/><aside>sigue</aside> dicho <aside>b</aside>"})

  assert Statistics.get_statistics(play.id).data["total_asides"] == 3
end
```

In `play_content_test.exs`: `"a line not aside does not continue an aside"`: `create_element/1` a verse with `is_aside: false, aside_continues: true`; `PlayContent.get_element(play.id, id).aside_continues == false`.

In `play_controller_test.exs`: the play's text endpoint returns `"aside_continues"` on a verse line and a paragraph.

- [ ] **Step 2: Run them, watch them fail.** `mix test test/playcode/statistics_test.exs test/playcode/play_content_test.exs test/playcode_web/controllers/api/play_controller_test.exs`. Expected: `total_asides` 4 against 3 (counted by element), the key missing.

- [ ] **Step 3: Write the migration.** Add the column (`null: false, default: false`), `flush()`, then set it on every aside row with today's site rule, so the site keeps its labels until the re-import and the trigger moves every such play's `content_version`:

```sql
WITH verses AS (
  SELECT l.id,
         lag(l.is_aside) OVER (
           PARTITION BY coalesce(CASE WHEN p.type = 'line_group' THEN p.parent_id ELSE l.parent_id END, l.division_id)
           ORDER BY CASE WHEN p.type = 'line_group' THEN p.position ELSE l.position END,
                    CASE WHEN p.type = 'line_group' THEN l.position ELSE 0 END
         ) AS previous_aside
  FROM play_elements l LEFT JOIN play_elements p ON p.id = l.parent_id
  WHERE l.type = 'verse_line'
)
UPDATE play_elements e
SET aside_continues = coalesce((SELECT previous_aside FROM verses v WHERE v.id = e.id), false)
WHERE e.is_aside
```

`down` drops the column.

- [ ] **Step 4: Implement** the field, the changeset rule, `Element.asides_started/1` (split the content on `~r{<aside>.*?</aside>}s` as `TeiXml.spoken_content/2` does), `count_asides/1` and the API key.

- [ ] **Step 5: Run the tests, watch them pass.** Same command. Then check the migration's guess on dev. Before migrating, count the site's labels for La vida es sueño: `mix playcode.export.site -o <scratch dir>`, then `grep -o 'class="aparte"' <scratch dir>/plays/EMOTHE0020/text.html | wc -l`. Run `mix ecto.migrate`. The play page's statistics for EMOTHE0020 should show that many asides, give or take its lines partly aside, where they showed 254 before.

- [ ] **Step 6: Refactor while green.** One split of content into pieces, not two (`asides_started/1` and Task 3's export will both need it: make it `Element.aside_pieces(element) :: [{:aside | :spoken, String.t()}]` now if it reads better, and say so in the commit).

- [ ] **Step 7: `mix test`, then commit.** `feat: an aside over several verses counts once`

### Task 2: The TEI import decides where each aside starts

**Files:**
- Create: `lib/playcode/import/asides.ex`
- Modify: `lib/playcode/import/tei_parser.ex` (`verse_line/2` at 1637, `prose/2` at 1722, `text/1` at 1154)
- Test: `test/playcode/tei_roundtrip_test.exs` (the describe block holding "an aside, however the delivery is spelled, stays an aside")

**Interfaces:**
- Consumes: `aside_continues` (Task 1), cast by `Element.changeset/2`, so `TeiImport.collect_element/6` needs no change.
- Produces: `Playcode.Import.Asides.guess(elements :: [map]) :: [map]`. It walks parsed element maps (`:elements` children, speeches through their line groups), and sets `aside_continues` on each `verse_line`/`prose` map with `is_aside: true` and no `:aside_continues` key: true when the verse line or paragraph before it in the same speech is aside, else false. Task 5's Word import uses it too.
- Produces: the parser's `verse_line` and `prose` maps carry `aside_continues` for every aside.

- [ ] **Step 1: Write the failing tests.** Each imports a body with `import_tei!(tei(body: …))` and asserts `Statistics.get_statistics(play.id).data["total_asides"]`:

| Test name | Body (speeches of one act) | Asides |
|---|---|---|
| `"pieces numbered -segNN make one aside, and -seg01 starts the next"` | ANA: `es-0001-seg01` (`next="es-0003-seg02"`, dangling as Clarín's), `es-0002-seg02`, `es-0003-seg01` | 2 |
| `"a piece another's next names continues an aside; one with an id no next names starts one"` | ANA: `a1 next="#a2"`, `a2 next="a3"`, `a3`, `a4` | 2 |
| `"a delivery stage before a piece starts an aside"` | ANA: `<l><seg>uno</seg></l>`, `<l><stage type="delivery">(Aparte.)</stage><seg>dos</seg></l>` | 2 |
| `"with nothing else to go by, a speech's consecutive aside lines are one aside"` | ANA: seg, seg, plain line, seg; then BRUNO: seg | 3 |
| `"a line aside by its delivery stage alone is a piece like any other"` | ANA: `<l><seg>uno</seg></l>`, `<l><stage type="delivery">(Aparte.)</stage>dos</l>` | 2 |

- [ ] **Step 2: Run them, watch them fail.** `mix test test/playcode/tei_roundtrip_test.exs`. Expected: the first, second and fourth fail, counting one aside per piece (3, 4, 5). The third and fifth pass before the change, because until then every piece is an aside of its own. After Step 4, prove they bite: turn rule 3 off, watch both go red (1 aside: rule 4 merges them), and turn it back on.

- [ ] **Step 3: Implement.** `verse_line/2` and `prose/2` record each aside piece of the element, in order (`id`, `next`, whether a delivery stage stands right before it); a line aside by a delivery stage with no seg is one piece with no id after a delivery stage. `text/1` then makes two passes over the divisions in file order: one collects every `next` target (without `#`, never the piece itself), the other sets `aside_continues` from the element's first piece by rules 1 to 3 (Global Constraints), leaving the key off where none applies. `Asides.guess/1` then fills the rest. The raw piece list may stay on the map: `Element.changeset/2` ignores keys it does not cast.

- [ ] **Step 4: Run the tests, watch them pass.**

- [ ] **Step 5: Refactor while green.** The rules read as one ranked `cond` or `with` in one function, each line naming its rule; no rule repeated in `Asides`.

- [ ] **Step 6: `mix test`, then commit.** `feat: the TEI import reads where each aside starts`

### Task 3: The export numbers and links every piece

**Files:**
- Modify: `lib/playcode/export/tei_xml.ex` (`generate/2` near 812, `spoken_content/2` at 1341, `aside_piece/2`)
- Modify: `lib/playcode/play_content/element.ex` (one virtual field)
- Modify: `test/playcode/complete_copy_test.exs` (the rarer-encodings play)
- Test: `test/playcode/tei_roundtrip_test.exs`

**Interfaces:**
- Consumes: `Element.asides_started/1` or `aside_pieces/1` (Task 1), `aside_continues` read back by Task 2.
- Produces: `Element` virtual field `aside_links: [%{id: String.t(), next: String.t() | nil}]`, one per piece in order, set only inside the export by `TeiXml.with_aside_links(divisions)`, a pass like `with_folio_parts/1` over the reading order.

- [ ] **Step 1: Write the failing tests** (round trips; `seg_attrs = for {a, _} <- xml_elements(xml, "seg"), do: Map.take(a, ["xml:id", "next"])`):

- `"an aside's pieces are numbered and linked, and a drifted link comes back sound"`: ANA `es-1203` `seg01` with `next="es-1205-seg02"`, `es-1204` `seg02`, `es-1205` `seg03`. Expected attrs: `es-1203-seg01` → `#es-1204-seg02` → `#es-1205-seg03` (no `next`).
- `"two asides back to back come back as two"`: `es-0001-seg01`, `es-0002-seg01`. Expected: both `seg01`, no `next`; and `total_asides` is 2 after importing the exported file again.
- `"a paragraph's pieces get identifiers no line has, the same on every export"`: a `<p>` with `<seg>a</seg> <lb n="2"/><seg>b</seg>`, no ids. Expected: two ids ending `-seg01` and `-seg02`, the first's `next` the second; no id equal to any `l`'s `xml:id`; `export_tei/1` twice gives the same ids.
- `"two asides starting in one line get distinct identifiers"`: `<l xml:id="es-0001"><seg>a</seg> dicho <seg>b</seg></l>`. Expected: two distinct ids.
- In `complete_copy_test.exs`, the rarer-encodings play: after `cuatro todo aparte`, a verse aside with `aside_continues: true`, then a verse aside with `aside_continues: false`. The test compares the column by itself.

- [ ] **Step 2: Run them, watch them fail.** `mix test test/playcode/tei_roundtrip_test.exs test/playcode/complete_copy_test.exs`. Expected: segs with no `xml:id`; the complete copy reads `aside_continues` false where true was stored.

- [ ] **Step 3: Implement** `with_aside_links/1` and its use in `spoken_content/2`. A piece's number counts within its aside, across elements. The id is `<line_id>-segNN` in a line with a `line_id`. Anywhere else, it is a shape no `line_id` can take, ending `-segNN` (say `<line_id prefix>-p<NNNN>-segNN`, NNNN counting the play's paragraphs that hold an aside). A clash takes the next free number. `next` is `"#" <> id` of the following piece of the same aside.

- [ ] **Step 4: Run the tests, watch them pass.** Also `mix test --include slow test/playcode/roundtrip_test.exs`: the exports still validate against TEI.

- [ ] **Step 5: Refactor while green.** `spoken_content/2`'s two branches write a seg through one helper; no second regex split of the content.

- [ ] **Step 6: `mix test`, then commit.** `feat: the TEI export writes each aside's chain`

### Task 4: The site labels each aside, and each new speaker

**Files:**
- Modify: `lib/playcode/export/static_site/edition.ex` (`aside_starts/1`)
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: `Element.asides_started/1` (Task 1), the column as Task 2 imports it.

- [ ] **Step 1: Write the failing test** `"two asides back to back are named twice; an aside carried to another speaker is named again"`:

```elixir
{play, dir} =
  publish!("""
  <div1 type="acto" n="1"><head>Acto I</head>
    <sp><speaker>A</speaker><lg>
      <l n="1"><seg type="aside" xml:id="es-0001-seg01">uno</seg></l>
      <l n="2"><seg type="aside" xml:id="es-0002-seg02">dos</seg></l>
      <l n="3"><seg type="aside" xml:id="es-0003-seg01">tres</seg></l>
    </lg></sp>
    <sp><speaker>B</speaker><lg><l n="4"><seg type="aside" xml:id="es-0004-seg02">cuatro</seg></l></lg></sp>
  </div1>
  """)

act = page(dir, play, "act-1.html")
assert for(n <- 1..4, act |> LazyHTML.query("#l#{n} .aparte") |> Enum.any?(), do: n) == [1, 3, 4]
```

- [ ] **Step 2: Run it, watch it fail.** Expected `[1, 4]`: today's guess merges verses 1 to 3.

- [ ] **Step 3: Implement.** A verse is in `aside_starts` when `Element.asides_started/1` is positive, or when it is the first aside verse of a run in its speech (today's chunk rule, kept for the new speaker). The comment says which rule is which.

- [ ] **Step 4: Run `test/playcode/export/static_site_play_test.exs`, watch it pass.** "an aside over several verses is named once, where it starts" stays green (no ids: rule 4).

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: `mix test`, then commit.** `feat: the site names each aside once, and again for a new speaker`

### Task 5: Editing: the Content tab, the Word import, deleting a start

**Files:**
- Modify: `lib/playcode_web/live/admin/play_content_editor_live.ex` (verse line and prose forms, near the "Words spoken aside" hints at 3417 and 3451)
- Modify: `priv/gettext/default.pot`, `priv/gettext/es/LC_MESSAGES/default.po` ("Continues the aside before it" → "Continúa el aparte anterior")
- Modify: `lib/playcode/import/word_parser.ex` (after `build_children/1`, per speech: `Asides.guess/1`)
- Modify: `lib/playcode/play_content.ex` (`delete_element/1` at 739)
- Test: `test/playcode_web/live/admin/play_content_editor_live_test.exs`, `test/playcode/import/word_parser_test.exs`

**Interfaces:**
- Consumes: `Asides.guess/1` (Task 2), `Element.asides_started/1` (Task 1).

- [ ] **Step 1: Write the failing tests.**
  - Editor, `"a verse ticked as continuing the aside before it joins that aside"`: import ANA with `es-0001-seg01` and `es-0002-seg01` (2 asides), open the second line's form through its card's `Edit` button (`card/2`, `aria-label` `t("Edit")`), `form("#element-form", element: %{"aside_continues" => "true"}) |> render_submit()`. Expected: `total_asides` 1.
  - Editor, `"deleting the verse an aside starts on leaves the rest an aside of their own"`: ANA with `es-0001-seg01`, a plain line, `es-0003-seg01`, `es-0004-seg02`. Delete the third line in the tab. Expected: `total_asides` 2 (without the hand-over, the fourth line would continue the first aside: 1).
  - Word, `"{ap} lines in a row are one aside, and a new speech starts another"`: `import_word(["{e}Escena 1", "{p}ANA {ap} {v}uno", "{ap} {v}dos", "{p}REY {ap} {v}tres"])`. Expected: the segs' ids end `seg01`, `seg02`, `seg01`.

- [ ] **Step 2: Run them, watch them fail.** Expected: the form has no such field; 1 aside after the delete; `seg01` three times.

- [ ] **Step 3: Implement.** The checkbox, `<.input field={@form[:aside_continues]} type="checkbox" label={gettext("Continues the aside before it")} />` in both forms. The Word import's guess. In `delete_element/1`, inside its transaction: when the element deleted starts an aside, the next verse line or paragraph of its speech, if `aside_continues`, is updated to false through `update_element/2`, so the activity log records it. Then `mix gettext.extract --merge` and the Spanish entry (check every entry it marks fuzzy).

- [ ] **Step 4: Run the tests, watch them pass.** Add `test/playcode_web/accessibility_test.exs` to the run: the new checkbox is named by its label.

- [ ] **Step 5: Refactor while green.**

- [ ] **Step 6: `mix test`, then commit.** `feat: curators mark an aside as continuing; Word and deletes keep asides whole`

### Task 6: Documents, and the corpus re-imported

**Files:**
- Modify: `docs/tei-mapping.md:43`, `docs/schema.md` (`play_elements`), `CONTEXT.md` (**piece**), `docs/stakeholder/ida-y-vuelta.html` (note 30 and the asides row), `docs/backlog.md`, `docs/history.md`

- [ ] **Step 1: Documents.**
  - `tei-mapping.md`: the `seg[@type="aside"]` line gains the four rules and what the export writes.
  - `schema.md`: the column, with its meaning.
  - `CONTEXT.md`: piece.
  - `ida-y-vuelta.html`: note 30 says the asides come back whole, and the statistics count asides.
  - `docs/backlog.md`: the item *An aside that runs over several verses is cut into pieces* moves to `docs/history.md`, with the counts from Step 2.

- [ ] **Step 2: Re-import on dev.** `mix playcode.import.tei --force --dry-run` (no hand edit to lose, or list them for the owner), then without `--dry-run`. Check on the play pages' statistics: *El amor al uso* (EMOTHE0384) **124** asides, *La vida es sueño* (EMOTHE0020) **43**; on the generated site, Clotaldo's aside (vv. 395–468) has one "aparte". If a number differs from the spec's, stop and find out why before going on.

- [ ] **Step 3: `mix test --include slow`, then commit** the documents. `docs: asides come back whole through Playcode`

- [ ] **Step 4: Production: ask the owner first.** Deploy (CI on `main`), then the re-import per `docs/production-reimport.md` with its dry run, and Generate. The Deploy to emothe.uv.es stays blocked (memory: certificate and PHP2Shell).
