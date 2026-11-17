# Search Record Index Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every Generate writes `search/records.js`, one entry per published play holding the record fields the catalogue's search filters on.

**Architecture:** A new module, `Playcode.Export.StaticSite.Records`, turns a play with its record loaded into a small map and writes all of them as one script. `StaticSite.write_catalogue/3`, which already runs on every build and rewrites `index.html` from all published plays, calls it, so the file is written whole from the database every time and needs no tracking. Nothing reads the file yet: plan 3 does.

**Tech Stack:** Elixir, Ecto preloads, Jason, ExUnit.

**Spec:** `docs/superpowers/specs/2026-11-17-plays-without-text-and-record-search-design.md`, section 7.4 (the entry's keys, word for word) and the search half of section 5. Read both before Task 1.

**Needs:** plan `2026-11-17-plays-without-text.md` merged (`Play.has_text?/1`, `play_without_text_fixture/1`).

## Global Constraints

- Work on branch `feature/search-record-index` in a git worktree of its own. Check the branch before every commit.
- Every task is red, green, refactor, then commit. Prove a test bites with `bin/bites FILE OLD NEW TEST_PATH` when it passes at once, and say so in the commit.
- Tests read the file a visitor's browser gets: `generate!/2` or `StaticSite.apply_changes/2`, then the helper of Task 1. No test calls `Records.entry/3` directly.
- The entry's keys and shapes are spec 7.4's table: `c t a l o k s f x d h w r p n`. An absent value is left out of the entry, an empty list too; inside a `w` or `r` tuple a missing value is `null`.
- Values are as displayed, not normalised. Text read from a TEI file goes through `InlineMarkup.plain/1` (titles, characters' names).
- Every path built from a play code goes through `StaticSite.safe_code!/1`; this file's path holds no code.
- A fixed number of queries for any number of plays.
- Plain `mix test PATH`; `mix format` after every task; no `Co-Authored-By` trailer.
- A test that creates a place uses `place_fixture/1` without a `"slug"` (CLAUDE.md, the places deadlock).

## Review Focus

1. **A title or a character's name with italics** (`<<Celestina>>`): the entry holds the plain words. Test in Tasks 1 and 2.
2. **A witness dated "s.a.", or with no date**: `from` and `to` are null, the witness is still listed. Test in Task 2.
3. **A performance with no place, no company and no cast**: a tuple of nulls and an empty actors list, not a crash. Test in Task 2.
4. **A translation whose original is a draft** (not published): its `o` is its own language, as it is the root of what is published. Test in Task 1.
5. **A play removed from the site, or renamed data shared by many plays** (a company): the next `apply_changes/2` drops or updates the entries. Test in Task 3.

---

### Task 1: The file, with each play's own fields

**Files:**
- Create: `lib/playcode/export/static_site/records.ex`
- Modify: `lib/playcode/export/static_site.ex` (`write_catalogue/3` at 627; `root_id/2` at 697 stays private, used to build the roots map)
- Modify: `lib/playcode/export/static_site/search.ex` (`write_js!/4` is not reused: the records file has its own one-line writer, since it calls another function)
- Modify: `test/support/static_site_helpers.ex` (add `records!/1`)
- Test: `test/playcode/export/static_site_records_test.exs` (new, `use Playcode.DataCase, async: true`)

**Interfaces:**
- Produces:
  - `Playcode.Export.StaticSite.Records.write(dir :: Path.t(), plays :: [%Play{}], roots :: %{binary() => %Play{}}) :: non_neg_integer()` — writes `dir/search/records.js` as `EMOTHE.records.load(<json array>);\n` (`Jason.encode!(entries, escape: :javascript_safe)`), entries in the order of `plays`; returns the bytes written.
  - `Playcode.StaticSiteHelpers.records!(dir) :: [map()]` — decodes `search/records.js` (regex `\AEMOTHE\.records\.load\((.*)\);\n\z`s) to the list of entries.
  - After this task an entry holds `c t a l o k s f x d h`; Task 2 adds `w r p n`.

- [ ] **Step 1: Write the failing tests.**

```elixir
defp complete(attrs), do: play_fixture(Map.put(attrs, "is_complete", true))
defp entry(dir, play), do: Enum.find(records!(dir), &(&1["c"] == play.code))

test "a play's entry holds its own fields, under their keys" do
  play = complete(%{"title" => "La <<Celestina>>", "original_title" => "Tragicomedia de Calisto y Melibea",
    "author_name" => "Fernando de Rojas", "language" => "es", "form" => "prose",
    "composition_date_from" => 1499, "composition_date_to" => 1502, "historical_time" => "siglo_xv"})
  assert entry(generate!([play]), play) == %{
    "c" => play.code, "t" => ["La Celestina", "Tragicomedia de Calisto y Melibea"], "a" => "Fernando de Rojas",
    "l" => "es", "o" => "es", "k" => "original", "s" => "EMOTHE", "f" => "prose", "x" => 1,
    "d" => [1499, 1502], "h" => "siglo_xv"}
end

test "what a play lacks is left out, and a single year is both ends of its dating" do
  play = play_without_text_fixture(%{"is_complete" => true, "title" => "El Adonis", "author_name" => nil, "composition_date_from" => 1632})
  assert entry(generate!([play]), play) ==
    %{"c" => play.code, "t" => ["El Adonis"], "l" => "es", "o" => "es", "k" => "original", "s" => "EMOTHE", "d" => [1632, 1632]}
end

test "a translation's original language is its published root's" do
  original = complete(%{"language" => "en"})
  translation = complete(%{"language" => "fr", "parent_play_id" => original.id, "relationship_type" => "traduccion"})
  dir = generate!([original, translation])
  assert entry(dir, translation)["o"] == "en"
  assert entry(dir, translation)["k"] == "translation"
end

test "with its original a draft, a translation is its own root" do          # Review Focus 4
  original = play_fixture(%{"language" => "en"})
  translation = complete(%{"language" => "fr", "parent_play_id" => original.id, "relationship_type" => "traduccion"})
  assert entry(generate!([translation]), translation)["o"] == "fr"
end

test "the entries are in the catalogue's order, and a draft has none" do
  [b, a] = [complete(%{"title" => "B", "title_sort" => "b"}), complete(%{"title" => "A", "title_sort" => "a"})]
  draft = play_fixture()
  codes = generate!([a, b, draft]) |> records!() |> Enum.map(& &1["c"])
  assert codes == [a.code, b.code]
end

test "a bare play's entry is under 200 bytes" do
  play = complete(%{"title" => "Hamlet", "author_name" => "William Shakespeare"})
  assert generate!([play]) |> entry(play) |> Jason.encode!() |> byte_size() < 200
end
```

- [ ] **Step 2: Run** `mix test test/playcode/export/static_site_records_test.exs` — expected: FAIL, `search/records.js` does not exist (`File.read!` raises `:enoent`).

- [ ] **Step 3: Implement.** `Records.write/3` and a private `entry/2` (play, roots). `write_catalogue/3` builds `roots` (`Map.new(plays, &{&1.id, by_id[root_id(&1, by_id)]})`) and calls `Records.write(dir, plays, roots)`. Kind through `Components.kind/1`, collection through `Components.collection/1`, form through `Play.form/1`, `x` through `Play.has_text?/1`. Drop nil and `[]` values before encoding.

- [ ] **Step 4: Run** the file — expected: PASS. Then `mix test test/playcode/export/static_site/fingerprint_test.exs` — expected: PASS (the module is under the `StaticSite` prefix; if it names a module to list, list it in `Fingerprint`'s `@modules`).

- [ ] **Step 5: Refactor while green.** `entry/2` reads as the spec's table, one line per key, in its order.

- [ ] **Step 6: Commit** — `feat: Generate writes each published play's record fields to search/records.js`

---

### Task 2: Witnesses, performances, places of action, characters

**Files:**
- Modify: `lib/playcode/export/static_site/records.ex`
- Modify: `lib/playcode/catalogue.ex` (add `preload_record/1`)
- Test: `test/playcode/export/static_site_records_test.exs`

**Interfaces:**
- Consumes: `Places.gazetteer/0`, `Places.ancestors/2` (`lib/playcode/places.ex`), `Performances.Actor.display_name/1`, the fixtures `performance_fixture/2`, `place_fixture/1`, `play_place_fixture/3` (`test/support/fixtures.ex`), and for witnesses and characters the context functions the admin tabs call (`Witnesses`, `PlayContent.create_character/2`).
- Produces: `Playcode.Catalogue.preload_record(plays :: [%Play{}]) :: [%Play{}]` — the plays with `characters`, `witnesses`, `play_places` and `performances: [:company, cast: :actor]` loaded, each list in its `position` order, in one query per association. Entries gain:
  - `"w"`: `[[witness_type, pub_place, from, to, format], …]`
  - `"r"`: `[[toponyms :: [String.t()], venue, venue_type, from, to, company_name, actors :: [String.t()]], …]`
  - `"p"`: `[[name, …], …]`, per place link every name of the place and of the places containing it, the place's own first
  - `"n"`: `[name, …]`, hidden characters left out

- [ ] **Step 1: Write the failing tests.**

```elixir
test "a witness is its support, city, years and format" do
  play = complete(%{})
  witness!(play, %{"witness_type" => "loose", "pub_place" => "London", "date" => "1733-1737", "format" => "4º"})
  witness!(play, %{"witness_type" => "manuscript", "date" => "s.a."})                   # Review Focus 2
  witness!(play, %{"witness_type" => "early_edition", "pub_place" => "Madrid", "date" => "1612"})
  assert entry(generate!([play]), play)["w"] == [
    ["loose", "London", 1733, 1737, "4º"], ["manuscript", nil, nil, nil, nil], ["early_edition", "Madrid", 1612, 1612, nil]]
end

test "a performance is its place and the places around it, its venue, years, company and actors" do
  play = complete(%{})
  england = place_fixture(%{"names" => [%{"name" => "England", "language" => "en"}, %{"name" => "Inglaterra", "language" => "es"}]})
  london = place_fixture(%{"parent_place_id" => england.id, "names" => [%{"name" => "London", "language" => "en"}]})
  performance_fixture(play, %{"place_id" => london.id, "venue" => "The Globe", "venue_type" => "commercial_theatre",
    "year_from" => 1601, "company" => "The King’s Men", "cast" => [%{"forename" => "Richard", "surname" => "Burbage", "role" => "Hamlet"}]})
  performance_fixture(play, %{})                                                         # Review Focus 3
  assert entry(generate!([play]), play)["r"] == [
    [["London", "England", "Inglaterra"], "The Globe", "commercial_theatre", 1601, 1601, "The King’s Men", ["Richard Burbage"]],
    [[], nil, nil, nil, nil, nil, []]]
end

test "a place of action is listed with the places containing it" do
  play = complete(%{})
  spain = place_fixture(%{"names" => [%{"name" => "España", "language" => "es"}]})
  seville = place_fixture(%{"parent_place_id" => spain.id, "names" => [%{"name" => "Sevilla", "language" => "es"}, %{"name" => "Seville", "language" => "en"}]})
  play_place_fixture(play, seville)
  assert entry(generate!([play]), play)["p"] == [["Sevilla", "Seville", "España"]]
end

test "its characters are named plain, the hidden ones left out" do
  play = complete(%{})
  for {name, hidden} <- [{"DON <<JUAN>>", false}, {"CATALINÓN", false}, {"TODOS", true}],
      do: {:ok, _} = PlayContent.create_character(%{"play_id" => play.id, "name" => name, "is_hidden" => hidden})
  assert entry(generate!([play]), play)["n"] == ["DON JUAN", "CATALINÓN"]             # Review Focus 1
end

test "the queries do not grow with the plays" do
  count = fn plays ->
    dir = site_dir!()
    counted(fn -> StaticSite.Records.write(dir, plays, Map.new(plays, &{&1.id, &1})) end)
  end
  two = for _ <- 1..2, do: complete(%{})
  six = two ++ for _ <- 1..4, do: complete(%{})
  assert count.(two) == count.(six)
end
```

Write `witness!/2` in the test file through the `Witnesses` function the witnesses tab saves with; take the fixtures' real attribute shapes (a place's names, a performance's company and cast) from `test/support/fixtures.ex` and adjust the inputs, never the expected entries. `counted/1` attaches a `:telemetry` handler to `[:playcode, :repo, :query]` for the call and returns how many fired; this one test reaches the module, because a query count is not visible in the file (say so in a comment).

- [ ] **Step 2: Run** the file — expected: FAIL, the entries have no `"w"`, `"r"`, `"p"`, `"n"`.

- [ ] **Step 3: Implement.** `Catalogue.preload_record/1` (one `Repo.preload/2`, the nested lists ordered by `position`). `Records.write/3` calls it once and `Places.gazetteer/0` once, and passes the gazetteer to `entry`. Years of a witness: `Regex.scan(~r/\b\d{4}\b/, date)`, first and last, as integers. Place names: `[place | Enum.reverse(Places.ancestors(place, gazetteer))]`, each one's names in their stored order, nearest container first.

- [ ] **Step 4: Run** the file and `mix test test/playcode/export/static_site/fingerprint_test.exs` — expected: PASS.

- [ ] **Step 5: Refactor while green.** One private function per key group (`witnesses/1`, `performances/2`, `places/2`, `characters/1`); the names-of-a-place-and-its-containers helper used by both `r` and `p`.

- [ ] **Step 6: Commit** — `feat: the record index holds witnesses, performances, places and characters`

---

### Task 3: It follows every change

**Files:**
- Modify: nothing expected in `lib/`; this task pins the behaviour of spec 7.4, *Why it cannot be stale*
- Test: `test/playcode/export/static_site_changes_test.exs`

**Interfaces:**
- Consumes: `StaticSite.apply_changes/2`, `StaticSite.outdated/1` (what Generate asks), `records!/1`.

- [ ] **Step 1: Write the tests** in a `describe "the record index"`:

```elixir
test "a renamed company reaches every play it staged, on the next Generate" do
  [one, two] = for _ <- 1..2, do: play_fixture(%{"is_complete" => true})
  for play <- [one, two], do: performance_fixture(play, %{"company" => "Lady Elizabeth's Men"})
  dir = generate!([one, two])
  rename_company!("Lady Elizabeth's Men", "Lady Elizabeth’s Men")          # through Performances' public function
  {:ok, _} = StaticSite.apply_changes(StaticSite.outdated(dir), output_dir: dir)
  for entry <- records!(dir), do: assert [[_, _, _, _, _, "Lady Elizabeth’s Men", _]] = entry["r"]
end

test "a play taken off the site leaves the index, and one added joins it" do
  [stays, goes] = for _ <- 1..2, do: play_fixture(%{"is_complete" => true})
  dir = generate!([stays, goes])
  joins = play_fixture(%{"is_complete" => true})
  {:ok, _} = StaticSite.apply_changes([{:remove, goes.code}, {:add, joins.id}], output_dir: dir)
  assert records!(dir) |> Enum.map(& &1["c"]) |> Enum.sort() == Enum.sort([stays.code, joins.code])
end

test "a new character is in the index after its play is built again" do
  play = play_fixture(%{"is_complete" => true})
  dir = generate!([play])
  {:ok, _} = PlayContent.create_character(%{"play_id" => play.id, "name" => "NUEVO"})
  {:ok, _} = StaticSite.apply_changes(StaticSite.outdated(dir), output_dir: dir)
  assert "NUEVO" in hd(records!(dir))["n"]
end
```

- [ ] **Step 2: Run** `mix test test/playcode/export/static_site_changes_test.exs` — expected: PASS if Tasks 1 and 2 hang the file on `write_catalogue/3`. Prove they bite: with `bin/bites`, remove the `Records.write` call from `write_catalogue/3` and watch all three go red.

- [ ] **Step 3: If one fails as written**, `outdated/1` missed a change: that is a tracking bug in `plays.content_version`'s triggers (`test/playcode/content_version_test.exs`), to fix there with its own test, not by forcing a rewrite here.

- [ ] **Step 4: Refactor while green; commit** — `test: the record index follows renames, removals and edits`

---

### Task 4: Its size reported, and written down

**Files:**
- Modify: `lib/playcode/export/static_site.ex` (`generate/1`'s result near line 110; `write_catalogue/3` returns the bytes)
- Modify: `lib/mix/tasks/playcode.export.site.ex` (the report line near 68)
- Modify: `docs/static-site.md`, `docs/architecture.md`
- Test: `test/playcode/export/static_site_records_test.exs`, `test/mix/tasks_test.exs`

**Interfaces:**
- Produces: `StaticSite.generate/1` returns `{:ok, %{… , records_bytes: non_neg_integer()}}`.

- [ ] **Step 1: Write the failing tests**: `StaticSite.generate/1`'s result has `records_bytes` equal to the file's size on disk; the export task's output holds `"record index "` followed by a size (in `tasks_test.exs`, beside the test that reads the task's report).
- [ ] **Step 2: Run** both — expected: FAIL, no `records_bytes` key.
- [ ] **Step 3: Implement**: thread the size from `Records.write/3` through `write_catalogue/3` into the result; print it after the search index's figures.
- [ ] **Step 4: Run** both — expected: PASS.
- [ ] **Step 5: Measure on the dev corpus.** `mix playcode.export.site --all -o /tmp/site-records` (or the flags `mix help playcode.export.site` names for every play and an output folder), then `wc -c /tmp/site-records/search/records.js && gzip -c /tmp/site-records/search/records.js | wc -c`. The design estimated 250 KB and 75 KB gzipped for about 530 plays; if the gzipped figure is over 150 KB, stop and tell the owner before going on.
- [ ] **Step 6: Documents.** `docs/static-site.md`: the file, its keys (point at the spec's table, do not copy it), when it is written, the two measured figures with their date. `docs/architecture.md`: `StaticSite.Records` in the file map. `docs/backlog.md` and `docs/history.md`: this plan's part of the record search done.
- [ ] **Step 7: Run** `mix precommit` and `node --test test/js/*.test.mjs` — expected: 0 failures. Paste both summaries into the commit body.
- [ ] **Step 8: Refactor while green; commit** — `feat: Generate reports the record index's size`
- [ ] **Step 9:** Tell the owner the branch is ready to merge. No pull request; merge and push only when told.
