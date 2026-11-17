# Admin Play Families Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `/admin/plays` lists each original with the plays derived from it (translations, adaptations, versions) indented under it, as the static site's catalogue groups them, and pages by work instead of by row.

**Architecture:** The site's grouping, `root_id/2` in `lib/playcode/export/static_site.ex:726-739`, moves into a small pure module, `Playcode.Catalogue.Families`, which both the export and the admin call. `Catalogue.list_families/1` loads the corpus, groups it by root, keeps the families a search and status filter reach, and pages them in Elixir. `PlayListLive` renders a family as its original's row followed by its derived rows; the archived view stays a flat list.

**Tech Stack:** Phoenix LiveView 1.1, Ecto, ExUnit with `Phoenix.LiveViewTest` and LazyHTML.

**Spec:** none written; the decisions below were agreed in conversation on 2026-11-17 and are the spec.

### Decisions

1. **A family** is a root play and every non-archived play whose `parent_play_id` chain leads to it, flattened to one level under the root (a translation of a translation sits beside the others), as the site's catalogue does.
2. **Search:** a family is listed when any member matches; the whole family is shown, and the rows that do not match are muted.
3. **Status filter** (Drafts, Complete plays, No text): only derived plays that pass it are shown; the root is always shown as the family's heading, muted when it does not pass.
4. **Counts** on the status buttons and in the heading stay counts of plays (`Catalogue.count_plays/1`, unchanged).
5. **Order:** roots by `title_sort, title`, as today; derived plays under a root in the same order. The site's author order is not copied.
6. **Pages** hold 50 families, not 50 rows.
7. **Archived plays** (`?archived=1`) stay a flat list, as today.
8. **A derived play whose original is archived** heads its own family. **A cycle** of `parent_play_id`s (hand-edited data) leaves each play standing alone, as `root_id/2` does today.

## Global Constraints

- Branch `feature/admin-play-families` in a git worktree of its own: other sessions switch branches in the main checkout. Check the branch before every commit.
- Every task is red, green, refactor, then commit. A test that passes at once is proved with `bin/bites FILE OLD NEW TEST_PATH`.
- Tests go through the LiveView (`live/2`, `render_change/2`, `element/3`); select rows by `#play-#{id}` and text by `t/1`. No `Repo`, no CSS-class assertions.
- Muted text is never lighter than `text-base-content/70` (`accessibility_test.exs` cannot check contrast; this is the rule).
- No new gettext strings: the kind's label is `PlaycodeWeb.PlayLabels.relationship_type_label/1` ("Translation", "Adaptation", "Version").
- `mix format` after each task; `mix test` (the whole suite) before the last commit. No `Co-Authored-By` trailer.

## Review Focus

1. A derived play whose original is archived must still be listed (heading its own family), not vanish: test in Task 2.
2. Two plays that name each other as parent must each be listed once, and the page must not hang: test in Task 2.
3. A translation of a translation is listed under the root of its chain, not lost or listed twice: test in Task 2.
4. A search that hits only a derived play still shows the original above it: test in Task 2.
5. A family larger than one page's 50 rows stays on one page; the next family starts the next page: test in Task 2.

---

### Task 1: One grouping for the site and the admin

**Files:**
- Create: `lib/playcode/catalogue/families.ex`
- Modify: `lib/playcode/export/static_site.ex:648-652` (`write_catalogue/3`), `:696-739` (`works/1`, `root_id/2`, `root_id/4`, the last two deleted)
- Modify: `lib/playcode/export/static_site/fingerprint.ex:28` (`@modules`)
- Test: `test/playcode/export/static_site/fingerprint_test.exs` (existing), `test/playcode/export/static_site_catalogue_test.exs` (existing)

**Interfaces:**
- Produces: `Playcode.Catalogue.Families.root_ids(plays :: [Play.t()]) :: %{play_id => root_play_id}`: every play's id mapped to the id of the play at the top of its `parent_play_id` chain *within `plays`*; a play whose parent is not in `plays` is its own root; on a cycle each play of it is its own root (today's `root_id/4` rule, moved unchanged).

- [ ] **Step 1: Point the export at the new module before it exists in the fingerprint.** Create `Families.root_ids/1` (the body is today's `root_id/2`/`root_id/4` over a `by_id` map), and replace the two uses in `static_site.ex`: `write_catalogue/3` builds `roots = Families.root_ids(plays)` and passes `by_id[roots[&1.id]]`; `works/1` groups by `roots[&1.id]`. Delete `root_id/2` and `root_id/4` from `static_site.ex`.

- [ ] **Step 2: Watch the fingerprint test fail.**

Run: `mix test test/playcode/export/static_site/fingerprint_test.exs`
Expected: FAIL in "every module the export calls is in the fingerprint, or only reads play data", listing `Playcode.Catalogue.Families`. (The grouping decides what the catalogue page shows, so a change to it must rebuild the site.)

- [ ] **Step 3: Add `Playcode.Catalogue.Families` to `@modules` in `fingerprint.ex`.**

- [ ] **Step 4: Run the fingerprint and catalogue tests.**

Run: `mix test test/playcode/export/static_site/fingerprint_test.exs test/playcode/export/static_site_catalogue_test.exs`
Expected: PASS, including "a translation of a translation is listed under the original of the chain" and "plays that are each other's parent do not hang the build; each stands alone", which now run through `Families`.

- [ ] **Step 5: Refactor while green.** `@moduledoc` on `Families` says what a family is (decision 1) and the cycle rule in one line each; no other comments. Re-run Step 4.

- [ ] **Step 6: Commit**

```bash
git add lib/playcode/catalogue/families.ex lib/playcode/export/static_site.ex lib/playcode/export/static_site/fingerprint.ex
git commit -m "refactor: a play's family root is found in one module the admin can share"
```

### Task 2: The admin list shows families

**Files:**
- Modify: `lib/playcode/catalogue.ex` (new `list_families/1` beside `list_plays/1`)
- Modify: `lib/playcode_web/live/admin/play_list_live.ex` (`handle_params/3`, `reload/1`, `render/1`)
- Modify: `docs/history.md` (one entry)
- Test: `test/playcode_web/live/admin/play_list_live_test.exs` (new `describe "families"`)

**Interfaces:**
- Consumes: `Families.root_ids/1` (Task 1); `PlaycodeWeb.PlayLabels.relationship_type_label/1`.
- Produces: `Catalogue.list_families(opts) :: {[family], total :: non_neg_integer}`, opts `:search`, `:status` (`nil | :draft | :complete | :no_text`), `:page`, `:per_page`; `family :: %{play: Play.t(), match?: boolean, derived: [%{play: Play.t(), match?: boolean}]}`. `total` counts families, for the page count.

- [ ] **Step 1: Write the failing tests** in a new `describe "families"` of `play_list_live_test.exs`. Every fixture sets `"title_sort"` (the fixture's default is "Play" for all). A helper reads the order of rows as the page prints them:

```elixir
defp row_ids(view),
  do: view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("tbody tr") |> Enum.flat_map(&LazyHTML.attribute(&1, "id"))

defp derived(original, attrs),
  do: play_fixture(Map.merge(%{"parent_play_id" => original.id, "relationship_type" => "traduccion"}, attrs))
```

Tests and their assertions:

1. `"a derived play is listed under its original, named by its kind"` — `middle` (title_sort "Middle"), `original` ("Zeta"), `translation = derived(original, %{"title_sort" => "Alpha"})`, `adaptation = derived(original, %{"title_sort" => "Beta", "relationship_type" => "adaptacion"})`. `row_ids(view) == ["play-#{middle.id}", "play-#{original.id}", "play-#{translation.id}", "play-#{adaptation.id}"]`; `has_element?(view, "#play-#{translation.id} td", t("Translation"))`; `has_element?(view, "#play-#{adaptation.id} td", t("Adaptation"))`; `refute has_element?(view, "#play-#{original.id} td", t("Translation"))`.
2. `"a search that finds one member shows the whole family, the original first"` — `original` titled "El burlador de Sevilla", `trickster = derived(original, %{"title" => "The Trickster of Seville"})`, `other` "Alpha Tragedy". Search "Trickster": `row_ids == ["play-#{original.id}", "play-#{trickster.id}"]`. Search "burlador": both rows still shown (the Trickster through its family); `refute has_element?(view, "#play-#{other.id}")`.
3. `"a status filter keeps the original as the heading of the derived plays it lets through"` — `original` complete, `draft = derived(original, %{})`, `done = derived(original, %{"is_complete" => true})`. On `?status=draft`: rows `original`, `draft`; `refute has_element?(view, "#play-#{done.id}")`. Counts unchanged: `"#{t("Drafts")} · 1"` (the original is complete).
4. `"a translation of a translation is listed under the original of the chain"` — `original`, `first = derived(original, %{"title_sort" => "B"})`, `second = derived(first, %{"title_sort" => "C"})`: rows `original`, `first`, `second` (ordered by title_sort), each id once.
5. `"a derived play whose original is archived heads its own family"` — archive `original` (the `archive/2` helper at the top of the file); `translation` is still listed, under no other play.
6. `"plays that name each other as parent are each listed once"` — `a`, `b` updated to each other's `parent_play_id` with `Catalogue.update_play/2` as in `static_site_catalogue_test.exs:283-297`; `row_ids(view)` holds each once.
7. `"a page holds 50 families, however many derived plays they have"` — one original with 50 derived plays, plus one other original: all 52 rows on page 1 and `refute has_element?(view, "a", t("Next"))`.

- [ ] **Step 2: Run them and watch them fail.**

Run: `mix test test/playcode_web/live/admin/play_list_live_test.exs`
Expected: tests 1-4 and 7 FAIL (rows in flat title order; no kind label; the Trickster's original missing on its search; 52 rows split over two pages). 5 and 6 may pass at once (a flat list already shows them): prove each bites after Step 4 with `bin/bites`, breaking `Families.root_ids/1`'s missing-parent or cycle clause.

- [ ] **Step 3: Implement `Catalogue.list_families/1`.** The filter rule (decisions 2, 3, 8) is not fixed by the signature, so:

```elixir
all = list_plays()                       # non-archived, title order
roots = Families.root_ids(all)
visible = ids(list_plays(status: opts[:status]))
matched = ids(list_plays(search: opts[:search], status: opts[:status]))

families =
  for root <- all, roots[root.id] == root.id,
      members = Enum.filter(all, &(roots[&1.id] == root.id and &1.id != root.id and &1.id in visible)),
      root.id in matched or Enum.any?(members, &(&1.id in matched)),
      do: %{play: root, match?: root.id in matched, derived: Enum.map(members, &%{play: &1, match?: &1.id in matched})}

{Enum.slice(families, (page - 1) * per_page, per_page), length(families)}
```

`Enum.filter` inside the comprehension is O(n²) over ~600 plays; group `all` by root once instead (`Enum.group_by/2` keeps title order within a group). Mark the whole-corpus load with `# ponytail: loads every play per render; a recursive CTE when the corpus outgrows a few thousand plays`.

- [ ] **Step 4: Use it in `PlayListLive`.** Not archived: `{families, total} = Catalogue.list_families(search:, status:, page:, per_page: @per_page)`, `total_pages` from `total`. Archived: `Catalogue.list_plays/1` as today. Both become one assign, `@rows :: [%{play: Play.t(), derived?: boolean, match?: boolean}]` (archived rows: `derived?: false, match?: true`), which the one `<tr :for>` renders; `listen_to/2` and the empty-state check read the plays of `@rows`. `handle_params/3` and `reload/1` load through one private function instead of two copies. In the row:
  - a derived row's title cell is indented (`pl-6`) with `<.icon name="hero-arrow-turn-down-right-mini" class="size-4" aria-hidden="true" />` and a `badge badge-sm badge-ghost` holding `PlayLabels.relationship_type_label(play.relationship_type)` before the title;
  - a row with `match?: false` prints its title link in `text-base-content/70` instead of `text-primary`.

- [ ] **Step 5: Run the tests.**

Run: `mix test test/playcode_web/live/admin/play_list_live_test.exs test/playcode_web/accessibility_test.exs`
Expected: PASS, the file's existing tests included (status counts, archived view, listening, restore). Then the `bin/bites` runs from Step 2 for tests 5 and 6: each goes red with its clause broken and green after.

- [ ] **Step 6: Refactor while green.** One loader in the LiveView; no helper the template no longer uses (`@plays` gone); `list_families/1`'s `@doc` states decisions 2-4 in two sentences. Re-run Step 5.

- [ ] **Step 7: Record it and run the whole suite.** Add one entry to `docs/history.md`: the admin list groups families (decisions 1-7 in a sentence), pages by work, and shares `Families` with the site. Then:

Run: `mix format && mix test 2>&1 | tail -5`
Expected: `0 failures`.

- [ ] **Step 8: Commit**

```bash
git add lib/playcode/catalogue.ex lib/playcode_web/live/admin/play_list_live.ex test/playcode_web/live/admin/play_list_live_test.exs docs/history.md
git commit -m "feat: the admin's play list shows each original with its translations under it"
```
