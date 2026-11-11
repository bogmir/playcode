# The comparison on the static site: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a page on the static site for each published play beside its published original
(`plays/<TRANSLATION>/compare.html`), reached from a Compare link on the original's line of
the catalogue, scrolling by step 1's computed speech pairs.

**Architecture:** `write_play/3` writes the page when the play's parent is published, loading
the original's `Edition` beside it. `StaticSite.Comparison` gives both editions a `sync` map
(each speech's act key and pair, each heading's key) that the site's existing speech and
heading components print as `data-sync-act`, `data-pair` and `data-sync-div`, and inlines
`assets/js/sync_scroll.mjs` in the page as `Export.CompareHtml` does. Generate needs nothing
new: re-adding a play already re-exports its published relatives (`relatives/3`).

**Tech stack:** Elixir, HEEx templates under `lib/playcode/export/static_site/pages/`,
`priv/static_site/style.css`, plain JS, `node --test`.

**Spec:** `docs/superpowers/specs/2026-11-11-static-site-comparison-design.md` (and
`docs/superpowers/specs/2026-11-08-translation-alignment-design.md`, step 1).

## Global constraints

- Works from `file://`; no request to another site; no `fetch`, no iframes.
- Every path built from a play code goes through `StaticSite.safe_code!/1`.
- `style.css` at most 25 KB (now 22,128 bytes: about 2.8 KB to spend); `site.js` and
  `search.js` 15 KB each, untouched by this plan.
- English only; the page is built inside `in_english/1` like every other.
- TDD: failing test first, watch it fail, smallest code, green, refactor, `mix test`, prove
  each new test bites (`bin/bites`); `mix format`; `node --test test/js/*.test.mjs`.
- Never add Claude attribution to a commit.
- Changed from the design's call 8 (the builder's own): the scroll script is inlined in each
  page, not shipped as an asset. A module attribute holds it, so the site fingerprint (every
  `StaticSite*` module's md5) moves when `sync_scroll.mjs` changes and Generate rebuilds the
  pages; an asset would need its own stamp. Update the design's line in Task 4.

## Review focus

1. **A translation whose original is a draft, or a draft translation of a published
   original:** no `compare.html`, no menu entry, and the catalogue's link never points at a
   missing page. Tests in Task 1 and Task 2.
2. **An original whose only published derived play is an adaptation:** the link shows, the
   page has no `data-pair` in the adaptation's panel (proportion) and the original's panel
   still carries its own places, so the menu's "keep the place" works. Test in Task 1.
3. **A translation removed from the site** (unpublished): its folder goes, and its siblings'
   menus and the catalogue's link stop naming it, through the existing relatives re-export.
   Test in Task 4.
4. **The original edited after the site was built:** the translation's `compare.html` shows
   the new text after `apply_changes/2`. Test in Task 4.
5. **A Folio-only speech (Hamlet):** no `data-sync-act` and no `data-pair` on it, as on
   Playcode's comparison, so the sync never lands on a hidden box. Test in Task 1.

---

### Task 1: The page for a published pair

**Files:**
- Modify: `lib/playcode/alignment.ex` (make `places/2` public as `pair_places/2`, add
  `own_places/1` and `paired?/1`; `mark_pairs/1` uses them)
- Modify: `lib/playcode/export/static_site/edition.ex` (struct field `:sync`, default nil)
- Create: `lib/playcode/export/static_site/comparison.ex`
- Modify: `lib/playcode/export/static_site/components.ex` (`division_text/1` and the
  speech clause of `el/1` print the sync attributes; extract `full_text/1` from
  `pages/text.html.heex`)
- Create: `lib/playcode/export/static_site/pages/compare.html.heex`
- Modify: `lib/playcode/export/static_site/pages/text.html.heex` (uses `full_text/1`)
- Modify: `lib/playcode/export/static_site.ex` (`write_play/3` writes `compare.html`)
- Modify: `lib/playcode/export/static_site/fingerprint.ex` (`Playcode.Alignment` joins
  `@modules`)
- Test: create `test/playcode/export/static_site_compare_test.exs`

**Interfaces:**
- Produces:
  - `Playcode.Alignment.paired?(play) :: boolean` — `play.relationship_type in ~w(traduccion version)`.
  - `Playcode.Alignment.own_places(divisions) :: %{speech_id => non_neg_integer}` — each speech's place among the play's speeches, reading order.
  - `Playcode.Alignment.pair_places(original_divisions, translation_divisions) :: %{speech_id => non_neg_integer}` — the translation's speeches only, each the place of its original speech; speeches the alignment gives no original are absent.
  - `%Edition{sync: nil | %{act: %{id => key}, div: %{id => key}, pair: %{id => n}}}`.
  - `StaticSite.Comparison.prepare(original :: Edition.t(), translation :: Edition.t()) :: {Edition.t(), Edition.t()}` — sets `sync` on both: `act` and `div` from `Division.sync_keys/1` (a speech carries its top division's key; a top heading its key; a child heading `"#{top}/#{child}"`, as `PlaycodeWeb.Components.PlayText` does), Folio-only speeches (`Element.folio_only?/1`) left out of `act` and `pair`; `pair` is `own_places` for the original and, when `Alignment.paired?(translation.play)`, `pair_places` for the translation, else `%{}`.
  - `StaticSite.Comparison.script() :: String.t()` — `sync_scroll.mjs` with `^export ` stripped (read at compile time, `@external_resource`, as `CompareHtml` does), then `document.addEventListener("DOMContentLoaded", () => syncPanels(document.getElementById("sync-scroll")))`.
  - `Pages.render(:compare, %{original: Edition.t(), translation: Edition.t(), siblings: [Play.t()], site: map})`; Task 2 fills `siblings`, Task 1 passes `[translation.play]`.
  - `Components.full_text(edition: Edition.t())` — what `text.html` shows inside its `.text` div today (contents and endnotes).

- [ ] **Step 1: Write the failing tests** in `static_site_compare_test.exs`
  (`use Playcode.DataCase, async: true`, `import Playcode.StaticSiteHelpers`,
  `import Playcode.ImportHelpers`):

```elixir
test "a published translation beside its published original gets a comparison page" do
  %{original: original, french: french} = split_speech_editions()
  dir = generate!([original, french])
  page = html!(dir, "plays/#{french.code}/compare.html")

  pairs = fn panel ->
    page |> LazyHTML.query("[data-panel='#{panel}'] [data-pair]") |> LazyHTML.attribute("data-pair")
  end

  assert {pairs.("panel-0"), pairs.("panel-1")} == {["0", "1", "2"], ["0", "1", "1", "2"]}
  assert texts(page, "[data-panel='panel-0'] .spk") == ["ANTONY", "CLEOPATRA", "ANTONY"]
  refute File.exists?(Path.join(dir, "plays/#{original.code}/compare.html"))
end

test "no page when either play is a draft" do
  %{original: original, french: french} = split_speech_editions()
  {:ok, _} = Playcode.Catalogue.update_play(original, %{is_complete: false})
  dir = generate!([original, french])
  refute File.exists?(Path.join(dir, "plays/#{french.code}/compare.html"))
end

test "an adaptation scrolls by proportion, its original keeping its places" do
  %{original: original, french: french} = split_speech_editions("adaptacion")
  page = [original, french] |> generate!() |> html!("plays/#{french.code}/compare.html")

  assert page |> LazyHTML.query("[data-panel='panel-0'] [data-pair]") |> Enum.count() == 3
  assert page |> LazyHTML.query("[data-panel='panel-1'] [data-pair]") |> Enum.count() == 0
  assert page |> LazyHTML.query("[data-panel='panel-1'] [data-sync-act]") |> Enum.count() == 4
end

test "the page runs alone and asks no other site for anything" do
  %{original: original, french: french} = split_speech_editions()
  dir = generate!([original, french])
  html = read!(dir, "plays/#{french.code}/compare.html")
  page = LazyHTML.from_document(html)

  refute html =~ ~r/(src|href)="(https?:)?\/\//
  script = page |> LazyHTML.query("script:not([src])") |> LazyHTML.text()
  # As the download's test runs it: a classic script, matchPair and syncPanels defined.
  {out, 0} =
    System.cmd("node", ["--input-type=commonjs", "-e",
      "globalThis.document = {addEventListener() {}};\n" <> script <>
        "\nconsole.log(matchPair([0, 1, 1, 3], 2), typeof syncPanels)"])
  assert String.trim(out) == "3 function"
end
```

  And a Folio test: import Hamlet's passage as `play_compare_live_test.exs`'s
  "scroll sync and Hamlet's Folio passages" setup does (original and translation complete,
  translation `traduccion` of the original); assert the `.sp.fo` speech in each panel has
  no `data-sync-act` and no `data-pair`, and the other two have both.

- [ ] **Step 2: Run** `mix test test/playcode/export/static_site_compare_test.exs`.
  Expected: every test fails on the missing `compare.html` (`File.read!` enoent), the draft
  one passes already (it bites from Step 4's negative case: break the "parent published"
  condition and watch it go red).

- [ ] **Step 3: Implement**, in this order: the Alignment functions (refactor
  `mark_pairs/1` onto them; `test/playcode_web/live/play_compare_live_test.exs` stays
  green); `Edition` field; `Comparison.prepare/2` and `script/0`; `full_text/1` extracted
  (text.html's output unchanged: `static_site_play_test.exs` stays green); the sync
  attributes in `el/1`'s speech clause (`data-sync-act={@edition.sync && @edition.sync.act[@el.id]}`,
  `data-pair` likewise) and on `division_text/1`'s `h2`/`h3` (`data-sync-div`), nil
  everywhere but the comparison; `compare.html.heex`:
  - `Components.shell` with `root="../../"`, title
    `"#{original.title} and #{translation.title} — EMOTHE"`, `play={@translation.play}`, no rail;
  - a bar: a link `../#{original.code}/index.html` "Back to #{original.title}", the
    translation menu (Task 2), the switches (Task 3);
  - `<div class="compare" id="sync-scroll">` with two `<section class="panel">`, each a
    header (title; author and code) and `<div class="text" data-panel="panel-N" tabindex="0"
    role="region" aria-label={title} lang={play.language}>` holding `full_text`;
  - `<script>{raw(Comparison.script())}</script>` at the end;
  then `write_play/3`: when `play.parent_play` is published (`MapSet.member?(site.published, code)`),
  load `Edition.load(play.parent_play_id)`, `prepare/2`, write
  `Path.join(play_dir, "compare.html")` (the dir already built through `safe_code!`).
  `Playcode.Alignment` joins `Fingerprint`'s `@modules`.

- [ ] **Step 4: Run** the file, then `bin/bites` on: the published-parent condition in
  `write_play/3`; `paired?/1` (add `adaptacion`); the Folio exclusion in `prepare/2`.
  Expected: each red.

- [ ] **Step 5: Run** `mix test` and `node --test test/js/*.test.mjs`: all green
  (`fingerprint_test.exs` included).

- [ ] **Step 6: Commit** `feat: the static site compares a play with its original, scrolling by speech`.

### Task 2: The catalogue's Compare link and the translation menu

**Files:**
- Modify: `lib/playcode/export/static_site.ex` (`works/1` gives each work `compare`, the
  code of its first published play whose `parent_play_id` is the lead's, or nil; siblings
  for `write_play/3`)
- Modify: `lib/playcode/export/static_site/components.ex` (`catalogue_entry/1` gains
  `attr :compare, :string, default: nil`)
- Modify: `lib/playcode/export/static_site/pages/catalogue.html.heex`, `pages/compare.html.heex`
- Modify: `lib/playcode/export/static_site/comparison.ex` (menu and place script)
- Test: `test/playcode/export/static_site_compare_test.exs`

**Interfaces:**
- Consumes: Task 1's page and `Pages.render(:compare, …)` with `siblings`.
- Produces: `StaticSite.translation_order(plays) :: [Play.t()]` — the catalogue's order of
  translations (`Search.normalise(&1.title_sort || &1.title)`), used by `works/1` and by
  `write_play/3` for the siblings (the original's `derived_plays` that are published).

- [ ] **Step 1: Write the failing tests:**
  - "the original's catalogue line links its first translation's comparison": two
    translations of one original (a second `split_speech_editions`-style French imported
    with another title, or `play_fixture` with `parent_play_id` and `is_complete: true`);
    `generate!/1`; in `index.html`, the lead entry has
    `a[href="plays/#{first.code}/compare.html"]` with text "Compare", the first by
    `translation_order/1`; a work with no derived play has no such link.
  - "the menu lists the original's published translations, the shown one selected": in
    the first's `compare.html`, `select[data-compare-menu] option` values are
    `["../#{first.code}/compare.html", "../#{second.code}/compare.html"]`, the first
    `selected`; a draft third translation is absent; `<noscript>` holds the same links.
  - "a draft translation is never linked": the catalogue's link skips a draft first
    translation and points at the published one.

- [ ] **Step 2: Run** the file. Expected: the three fail on the missing link and menu.

- [ ] **Step 3: Implement** `translation_order/1` (and use it in `works/1`), `compare` on
  each work and the entry's link (`<a class="compare" href={"plays/#{@compare}/compare.html"}>Compare</a>`,
  after the title), the menu in the bar (`<label>Translation <select data-compare-menu>`),
  and in `Comparison.script/0` two handlers after `syncPanels`:
  - on the menu's change: `location.href = value + "#s" + p`, `p` the `data-pair` of the
    original panel's top speech (the one `syncPanels` would anchor: nearest the panel's
    top, at most 50 px above it), or no fragment when none;
  - on load, a fragment `#s<n>`: scroll `panel-0` so the speech with `data-pair="n"` is at
    its top, which moves the other panel through the sync.

- [ ] **Step 4: Run** the file, `bin/bites` on the parent filter of `compare` in `works/1`
  and on the published filter of the siblings. Expected: red.

- [ ] **Step 5: Run** `mix test`: green.

- [ ] **Step 6: Commit** `feat: the catalogue links a comparison, and its page switches translation`.

### Task 3: The switches and the layout

**Files:**
- Modify: `lib/playcode/export/static_site/components.ex` (extract `play_tools/1` from
  `play_rail/1`'s `<div class="tools" data-tools>`)
- Modify: `lib/playcode/export/static_site/pages/compare.html.heex`
- Modify: `priv/static_site/style.css`
- Test: `test/playcode/export/static_site_compare_test.exs`

**Interfaces:**
- Produces: `Components.play_tools(variants: boolean, folio: boolean, tagged: boolean, cast: [Character], shared: boolean, stage: boolean, steppers: boolean)` — the rail's tools as today when called from `play_rail/1` (`steppers: true`); the comparison passes each flag as either edition's, `cast: []` (two casts, no single character list) and `steppers: false` (the steppers walk one column).

- [ ] **Step 1: Write the failing tests:**
  - "the comparison offers the site's switches": the page has `[data-tools]` with
    `input[data-toggle="sd"]` and `[data-toggle="vf"]` and the line-number buttons
    `[data-ln-set]`; no `select[data-highlight]`, no `[data-stepper]`.
  - "a switch shows when either play has what it switches": a translation with a variant
    (`<app>` as in `play_compare_live_test.exs`'s variants test) beside an original
    without: the page has `input[data-toggle="va"]`.
- [ ] **Step 2: Run.** Expected: both fail (no tools in the page).
- [ ] **Step 3: Implement** `play_tools/1` (`play_rail/1` calls it: the play pages'
  output unchanged), the tools in the bar, and the CSS: `.compare` a two-column grid at
  every width; each `.panel .text` scrolls in its own box (`overflow-y: auto`, height
  `calc(100vh - <bar and header>)`), `max-width` lifted inside panels; the bar wraps on a
  phone. Stay under 25 KB (`static_site_test.exs` asserts it).
- [ ] **Step 4: Run** the file and `mix test test/playcode/export/static_site_test.exs`
  (the size budget). Expected: green. `bin/bites` on the `va` flag's "either edition".
- [ ] **Step 5: Run** `mix test`: green.
- [ ] **Step 6: Commit** `feat: the comparison page's switches and two scrolling panels`.

### Task 4: Kept current, documented, checked in a browser

**Files:**
- Test: `test/playcode/export/static_site_compare_test.exs`
- Modify: `docs/static-site.md` (*Output structure*: `compare.html`; a paragraph on the
  page beside *Comparison scroll sync*), `docs/architecture.md` (`comparison.ex`),
  `docs/superpowers/specs/2026-11-11-static-site-comparison-design.md` (call 8 inlined),
  `docs/superpowers/specs/2026-11-08-translation-alignment-design.md` (step 2 built),
  `docs/backlog.md` (apply `../backlog-problem5.patch` from the worktrees folder, then say
  step 2 built), `docs/stakeholder/ida-y-vuelta.html` only if it has a comparison row
  (check; it lists outputs per part of a play).

- [ ] **Step 1: Write the tests** (they may pass at once: the relatives re-export exists;
  prove they bite in Step 3):
  - "an edited original reaches its translation's comparison": `generate!/1`; change the
    original's first line through `PlayContent` (as `static_site_test.exs`'s
    `add_act/3` edits text); `StaticSite.apply_changes([{:add, original.id}], output_dir: dir)`;
    the French `compare.html` panel-0 holds the new words.
  - "a translation taken off the site leaves no link to it": two translations; generate;
    mark the second a draft; `apply_changes([{:remove, second.code}], output_dir: dir)`;
    the first's menu and `index.html` no longer name the second's code.
- [ ] **Step 2: Run** the file. Expected: pass.
- [ ] **Step 3: Prove they bite:** `bin/bites` dropping `member.parent_play_id` from the
  `relatives/3` filter (the original's children are then not re-exported). Expected: red.
- [ ] **Step 4: Docs** as listed; `mix format`; `mix test`; `node --test test/js/*.test.mjs`.
- [ ] **Step 5: Browser check:** generate a site from the dev database into the scratchpad
  (`mix playcode.export.site -o <scratchpad>/site --all` or the codes 0038 and 0084 with
  `--all`, since 0084 is a draft on dev), open `plays/<0084>/compare.html` from `file://` in
  headless Chrome over the DevTools protocol (as done for step 1: scroll the French panel to
  "Donne-moi ma robe" and read the English top speech), switch the menu and check the new
  page opens at the same speech; light and dark (`prefers-color-scheme`). Report what was
  seen.
- [ ] **Step 6: Commit** `docs: the comparison on the static site`, and the tests in it
  or before it.
