# Static-Site Anchors from the Number Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every verse, prose paragraph and stage direction on a static-site play page gets an anchor built from the nearest number the reader sees plus a counter of its own kind, and a numbered prose paragraph's number becomes a citable link.

**Architecture:** One function, `Edition.anchors/3`, walks the play's items in reading order with a small state per unit (the page, or the scene in a play whose count restarts) and builds each anchor from the last number seen. Everything that links to a line (search index, Notes page, stage-directions list) already reads `edition.anchors`, so it follows. The prose `el/1` component renders a paragraph's leading number as a link.

**Tech Stack:** Elixir, Phoenix HEEx components, LazyHTML in tests.

**Spec:** `docs/superpowers/specs/2026-11-08-site-anchors-design.md`

## Global Constraints

- Branch `fix/site-anchors` from `main`. Commit the spec and this plan as the branch's first commit.
- No `Co-Authored-By` or any Claude attribution in commits. Never open or offer a PR; merge and push only when the owner says.
- TDD: write the test, watch it fail, implement, pass, refactor while green, then the full `mix test`. Prove each new test bites with `bin/bites FILE OLD NEW TEST_PATH` and say so in the commit message.
- Run mix plainly (`mix test`, `mix format`), never with an `export PATH=…` prefix.
- Problem 3 only reads numbers: no change to `@n`, the TEI, the database or `Metrics`.
- No TEI identifier in the HTML.
- `site.js` does not change.
- The separator stays `-`. A number goes into the anchor exactly as stored ("3-4", "124.1", "3153c").
- Counter kinds and spellings: `sd` (stage direction), `p` (prose paragraph), `v` (verse); piece letters `b`, `c`, …; clash suffix `-2`, `-3`, … (`unique/3`, unchanged).

## Review Focus

- An act's own elements before its first scene, in a per-scene play: prefix `l<act>-0-`, e.g. `l1-0-sd1` (Task 1, test 2).
- A number with a letter clashing with a piece letter ("3153c" after verse 3153's pieces b and c): suffixed `l3153c-2`, ids unique (Task 1, test 4).
- An element whose division has no page (`page_of` has no slug for it): must not crash; it falls into a `nil` unit. No test: no page prints it.
- An act split into scene pages (over 120 KB): continuous counters restart on each scene page. No test (needs a 120 KB fixture); the per-page rule in test 5 covers the mechanism.
- Search results and note links pointing at the new anchors: covered by the existing `static_site_search_test.exs` (`l12`, `l101`), which must stay green.

---

### Task 1: anchors from the nearest number

**Files:**
- Modify: `lib/playcode/export/static_site/edition.ex` (`load/1` around lines 49-54; `anchors/2`, `unique/3`, `restarts?/1` and their comments, lines 421-476)
- Modify: `docs/static-site.md` line 10 (the anchor forms)
- Modify: `CONTEXT.md` (add **Anchor** after **Identifier**, around line 87)
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: `Metrics.items/1` items (`kind` `:verse | :prose | :stage`, `element`, `act`, `division`, `scene`, `scene_number`); `page_of/2` (element id → page slug); `InlineMarkup.paragraph_number/1` (`{n | nil, rest}`).
- Produces: `edition.anchors` (element id → anchor string) in the new forms; a private `number(item) :: String.t() | nil` (verse: `line_number`; prose: its leading `<lb n>` number; else nil), used by both `anchors/3` and `restarts?/1`.

All tests below use the file's `publish!/1` and `page/3`, plus a local helper:

```elixir
defp line_ids(html), do: html |> LazyHTML.query("div.l, p.sd, p.pr") |> LazyHTML.attribute("id")
```

- [ ] **Step 1: Write the failing tests**

```elixir
describe "a line's anchor, from the nearest number" do
  test "a continuous page: numbers, a later piece, directions and paragraphs after a number" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <stage>Sale el REY.</stage>
        <sp><speaker>REY</speaker><l n="1">¿Quién va?</l><l n="2" part="I">Ya el sol se esconde.</l></sp>
        <sp><speaker>CRIADO</speaker><l part="F">Yo, señor.</l></sp>
        <sp><speaker>REY</speaker><l n="3">Mal me sirve este criado.</l><stage>Vase el criado.</stage></sp>
        <stage>Sale la REINA.</stage>
        <sp><speaker>REINA</speaker><p n="4">Señor, os traigo nuevas.</p><p>Y así lo cuentan todos.</p></sp>
      </div1>
      """)

    assert line_ids(page(dir, play, "act-1.html")) ==
             ~w(sd1 l1 l2 l2b l3 l3-sd1 l3-sd2 l4 l4-p1)
  end

  test "a play numbered per scene keeps the act-scene prefix and looks only inside the scene" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <stage>Antes de la escena.</stage>
        <div2 type="scene" n="1"><head>Scene 1</head><stage>Salen.</stage>
          <sp><speaker>A</speaker><l n="1">one</l><l n="2">two</l></sp></div2>
        <div2 type="scene" n="2"><head>Scene 2</head><stage>Vanse.</stage>
          <sp><speaker>B</speaker><l n="1">uno</l></sp><stage>Sale C.</stage></div2>
      </div1>
      """)

    assert line_ids(page(dir, play, "act-1.html")) ==
             ~w(l1-0-sd1 l1-1-sd1 l1-1-1 l1-1-2 l1-2-sd1 l1-2-1 l1-2-1-sd1)
  end

  test "unnumbered verses count apart, as in a play numbered by speech" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><l>Primero sin número.</l></sp>
        <sp><speaker>B</speaker><l n="12">Doce.</l><l>Sigue.</l><l part="I">Parte uno.</l></sp>
        <sp><speaker>C</speaker><l part="F">Parte dos.</l></sp>
      </div1>
      """)

    assert line_ids(page(dir, play, "act-1.html")) == ~w(v1 l12 l12-v1 l12-v2 l12-v2b)
  end

  test "a piece with a number of its own is anchored by it; a clash takes a suffix" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><l n="961" part="I">a</l></sp>
        <sp><speaker>B</speaker><l n="962" part="M">b</l></sp>
        <sp><speaker>C</speaker><l part="F">c</l></sp>
        <sp><speaker>A</speaker><l n="3153" part="I">d</l></sp>
        <sp><speaker>B</speaker><l part="M">e</l></sp>
        <sp><speaker>C</speaker><l part="F">f</l></sp>
        <sp><speaker>A</speaker><l n="3153c">g</l></sp>
      </div1>
      """)

    assert line_ids(page(dir, play, "act-1.html")) ==
             ~w(l961 l962 l962b l3153 l3153b l3153c l3153c-2)
  end

  # Counters start again on each page and after each number, so a direction added in act 1
  # moves only the directions after the same verse, and act 2 not at all. Also the spec's
  # test 7: both pages have an unsuffixed `sd1`.
  test "a direction added in act 1 moves no anchor in act 2" do
    act_2 = """
    <div1 type="acto" n="2"><head>Acto II</head>
      <stage>Salen.</stage><sp><speaker>A</speaker><l n="3">tres</l></sp><stage>Vase.</stage>
    </div1>
    """

    act_1 = fn extra ->
      """
      <div1 type="acto" n="1"><head>Acto I</head>
        <stage>Sale.</stage><sp><speaker>A</speaker><l n="1">uno</l></sp>#{extra}
        <stage>Otra.</stage><sp><speaker>A</speaker><l n="2">dos</l></sp>
      </div1>
      """
    end

    {before, before_dir} = publish!(act_1.("") <> act_2)
    {added, added_dir} = publish!(act_1.("<stage>Nueva.</stage>") <> act_2)

    assert line_ids(page(before_dir, before, "act-1.html")) == ~w(sd1 l1 l1-sd1 l2)
    assert line_ids(page(added_dir, added, "act-1.html")) == ~w(sd1 l1 l1-sd1 l1-sd2 l2)
    assert line_ids(page(before_dir, before, "act-2.html")) == ~w(sd1 l3 l3-sd1)
    assert line_ids(page(added_dir, added, "act-2.html")) == ~w(sd1 l3 l3-sd1)
  end
end
```

Also replace the existing test "a verse with no number is counted with the paragraphs" (around line 132) with the same snippet asserting `#p1` holds "En prosa." and `#v1` holds "Sin número.". Rewrite its comment: problem 3 gives unnumbered verses their own counter, so a paragraph no longer moves a verse's anchor.

- [ ] **Step 2: Run them and watch them fail**

Run: `mix test test/playcode/export/static_site_play_test.exs`
Expected: the five new tests and the rewritten one FAIL, with today's `p<k>` ids in the left-hand side (e.g. `["p1", "l1", "l2", "p2", …]`).

- [ ] **Step 3: Implement `anchors(items, pages, page_of)` in `edition.ex`**

In `load/1`, compute `page_of` before the anchors and pass it in. Add `number/1` (see Interfaces) and make `restarts?/1` use it.

`anchors/3` walks the items with `Enum.map_reduce`, state: the current unit key, `last` (the base of the last number, nil before one), the counts per kind, the open verse's base and its next letter, and `used` per page slug. The rules, in order:

- Unit key: `{item.division.id, item.scene && item.scene.id}` when the play restarts, else `page_of[item.element.id]`. A new key resets `last`, the counts and the open verse.
- Prefix: `"l#{item.act || 0}-#{scene_ordinal(item)}-"` when the play restarts, else `"l"`.
- An item with `number(item)`: base `prefix <> n`. Sets `last`, clears the counts. If it is a verse, it opens a verse with next letter `b`.
- A verse with `part` M or F, no number, and a verse open: base is the open verse's base plus its letter, and the letter advances.
- Anything else, by kind (`:stage` → `sd`, `:prose` → `p`, `:verse` → `v`): count + 1. Base is `"#{prefix}#{last}-#{kind}#{count}"` after a number. Before one it is `"#{kind}#{count}"`, or `"#{prefix}#{kind}#{count}"` in a restarting play. An unnumbered verse that is whole or part I opens a verse.
- `unique(base, used_on_this_page, 1)`; only the page's own anchors count as taken.

Rewrite the comment above `anchors` to state these rules in two or three lines, citing the spec.

- [ ] **Step 4: Run the tests and see them pass**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode/export/static_site_search_test.exs`
Expected: PASS. The existing restart test (`"l1-2-1" in anchors`, unique ids) and the Hamlet `l3-4` test stay green.

- [ ] **Step 5: Prove the tests bite**

Run each, expecting exit 0 (tests go red):
- `bin/bites lib/playcode/export/static_site/edition.ex '"v"' '"p"' test/playcode/export/static_site_play_test.exs` (adapt OLD to the exact literal that names the verse kind)
- one `bin/bites` that drops the per-page reset of `used` (the stability test must go red)
- one that drops the piece letter (the continuous and pieces tests must go red)

- [ ] **Step 6: Refactor while green**

Reuse `scene_ordinal/1`, `unique/3`, `page_of/2` as they are. Keep `anchors/3` one `map_reduce` with small private helpers, no new module. Re-run the file's tests after each change.

- [ ] **Step 7: Records**

- `docs/static-site.md` line 10: replace the anchor clause with the forms from the spec's table: `#l<n>`; `#l<act>-<scene>-<n>` when the count restarts; a later piece `#l<n>b`; after a number `#l<n>-sd1`, `-p1`, `-v1`; before one `#sd1`, `#p1`, `#v1`; counted per page, or per scene when the count restarts.
- `CONTEXT.md`, after **Identifier**:

  ```markdown
  **Anchor**:
  A line's address on the static site, `act-1.html#l230`: built from the nearest number before it and a counter of its own kind (`l230-sd1`), so it moves when the citation moves. Neither the number nor the identifier.
  _Avoid_: line id
  ```

- [ ] **Step 8: Full suite, format, commit**

Run: `mix format && mix test 2>&1 | tail -5`
Expected: `0 failures`.

```bash
git add lib/playcode/export/static_site/edition.ex test/playcode/export/static_site_play_test.exs docs/static-site.md CONTEXT.md
git commit -m "fix: a line's site anchor is built from the nearest number, not a play-wide counter"
```

The commit message body names the `bin/bites` runs that went red.

---

### Task 2: a numbered paragraph's number is a link

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex` (prose `el/1` clause, line ~759; the comment on `part(%{number: n})`, lines 828-830)
- Modify: `docs/backlog.md` line 70 (move the item), `docs/history.md` (add it with the date)
- Test: `test/playcode/export/static_site_play_test.exs`

**Interfaces:**
- Consumes: `edition.anchors` from Task 1 (a numbered paragraph's anchor is `l<n>`); `InlineMarkup.paragraph_number/1`; the existing `fifth?/1`.
- Produces: markup `<p class="pr" id="l4"><a class="pn" href="#l4">4</a>…</p>`. The cite button's selector `a[href^="#l"]` matches it; `.pn` CSS hides and shows it.

- [ ] **Step 1: Write the failing test**

```elixir
test "a numbered paragraph's number links to it, as a verse's does; its inner line numbers do not" do
  {play, dir} =
    publish!("""
    <div1 type="acto" n="1"><head>Acto I</head>
      <sp><speaker>KENT</speaker><p n="4">I thought<note n="1" type="editor"><p>Glosa.</p></note> the King<lb n="5"/>had more affected the Duke.</p></sp>
    </div1>
    """)

  para = page(dir, play, "act-1.html") |> LazyHTML.query("p#l4")

  link = LazyHTML.query(para, ~s(a.pn[href="#l4"]))
  assert LazyHTML.text(link) == "4"
  assert para |> LazyHTML.query("span.pn.m5") |> LazyHTML.text() == "5"
  assert LazyHTML.text(para) =~ "I thought1 the King"
end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `mix test test/playcode/export/static_site_play_test.exs:LINE` (the new test's line)
Expected: FAIL, because `a.pn` is empty: today the number is a `span.pn`.

- [ ] **Step 3: Implement**

In the prose `el/1` clause, split the content with `InlineMarkup.paragraph_number/1`. Render `<a :if={n} class={["pn", fifth?(n) && "m5"]} href={"#" <> anchor}>{n}</a>` and then `<.inline text={rest} notes={@el.notes} />`. Keep everything on one `phx-no-format` line, as the clause is today. Notes stay put: they are placed by grapheme offset, and a marker has none.

Rewrite the comment on `part(%{number: n})`: a printed line inside a paragraph stays plain text; the paragraph's own number is a link (`el/1`).

- [ ] **Step 4: Run it and see it pass**

Run: `mix test test/playcode/export/static_site_play_test.exs test/playcode_web/accessibility_test.exs`
Expected: PASS.

- [ ] **Step 5: Prove it bites**

`bin/bites lib/playcode/export/static_site/components.ex '<a :if' '<span :if' test/playcode/export/static_site_play_test.exs` (adapt to the exact literal). Expected exit 0.

- [ ] **Step 6: Refactor while green**, then **records**

- `docs/backlog.md` line 70, "An unnumbered verse's anchor on the site moves again": move it to `docs/history.md` under 2026-11-08 (or the merge date), one paragraph: anchors from the nearest number, the forms, the numbered paragraph's link, spec path.
- `/tmp/playcode-numbering/00-README.md` row 3: state "built; spec `docs/superpowers/specs/2026-11-08-site-anchors-design.md`".
- `~/.claude/projects/-home-bogdan-Projects-playcode/memory/numbering-grilling-state.md`: add "Problem 3 built" with the branch, and the four answers (numbered prose gets `l<n>` + link; nearest number + counter, scene-scoped in restart plays; `-` separator; own `v` counter, permanent for S plays).

- [ ] **Step 7: Full verification and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test 2>&1 | tail -5 && node --test test/js/*.test.mjs`
Expected: no warnings, `0 failures`, node tests pass.

```bash
git add lib/playcode/export/static_site/components.ex test/playcode/export/static_site_play_test.exs docs/backlog.md docs/history.md
git commit -m "fix: a numbered prose paragraph's number links to its anchor, so the cite button takes it"
```

Then use superpowers:finishing-a-development-branch: merge into `main` locally when the owner says, push only when told (a push deploys to Fly).
