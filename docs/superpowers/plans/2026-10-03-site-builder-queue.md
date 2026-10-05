# Site Builder Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A request that reaches the site builder while it is busy is queued, not refused, and queued adds and removes run as one batch: the pages first, then a single search-index write.

**Architecture:** `StaticSite.apply_changes/2` applies a batch of `{:add, play_id}` and `{:remove, code}` changes. It writes the plays' pages and the catalogue, calls `on_published`, then rewrites the search index once. `SiteBuilder` keeps a queue in its state. When a job ends, it starts the next one: every change at the front of the queue as one `{:batch, changes}`, or a lone `:generate` or `:deploy`. `ExportSiteLive` follows the builder's broadcasts and shows each play's pending change on its switch.

**Tech Stack:** Elixir 1.19, OTP (`GenServer`, `Task.Supervisor.async_nolink`), Phoenix PubSub, Phoenix LiveView 1.1, Gettext.

**Spec:** `docs/superpowers/specs/2026-10-03-site-builder-queue-design.md`

## Global Constraints

- **Starter replies.** `SiteBuilder.generate/1`, `add/2`, `remove/2` and `deploy/1` return `:started` or `:queued`; nothing is refused. A request identical to one already waiting is not queued twice, and still answers `:queued`.
- **Status.** `SiteBuilder.status/0` returns `%{job: job | nil, queue: [request]}`.
  - A job is `:generate`, `{:batch, [{:add, play_id} | {:remove, code}]}` or `:deploy`.
  - A request is `:generate`, `{:add, play_id}`, `{:remove, code}` or `:deploy`.
- **Broadcasts.** All go out on `"static_site"`:
  - `{:site_builder, :queued, request}`
  - `{:site_builder, :started, job}`
  - `{:site_builder, :progress, job, info}`
  - `{:site_builder, :published, {:batch, changes}}`
  - `{:site_builder, :done, job, result}`
  - `{:site_builder, :failed, job, reason}`
- **Batch rule.** When a job ends, every add and remove at the front of the queue runs as one batch, in the order asked. A generate or a deploy runs on its own, in its turn. A batch takes the options of its latest request.
- **`StaticSite.apply_changes(changes, opts)` returns `{:ok, %{skipped: [play_id]}}`.**
  - Only each play's last change counts.
  - Pages and the catalogue are written first, then `opts[:on_published].()` is called, then the search index once.
  - Added plays that no longer exist (deleted or archived) are skipped.
- **Generate** rebuilds the plays on disk at the moment it runs, or every complete play if the site is empty. It ignores any `:play_codes` it was given.
- **Download** is refused while a job runs or requests wait, with the existing msgid "The site is busy with another build. Try again when it finishes."
- **New strings, with their Spanish.** Use the `tú` register; "play" is "obra" (see "Obra añadida al sitio estático."):
  - "Queued: it starts when the current build finishes." → "En cola: empezará cuando termine la operación en curso."
  - "Updating search…" → "Actualizando la búsqueda…"
  - "%{count} changes applied to the static site." → "%{count} cambios aplicados al sitio estático."
  - "Could not apply %{count} changes to the site: %{reason}" → "No se pudieron aplicar %{count} cambios al sitio: %{reason}"
  - ngettext "A play that no longer exists was skipped." / "%{count} plays that no longer exist were skipped." → "Se omitió una obra que ya no existe." / "Se omitieron %{count} obras que ya no existen."
- **Repo rules (CLAUDE.md).**
  - TDD, red first, and prove each new test bites (break the line, watch red, restore).
  - Test through the outermost API, and select by id, ARIA or visible text, never CSS classes or `phx-*`.
  - Run `mix format`; `mix compile --warnings-as-errors` must be clean.
  - Run mix plainly, with no PATH export.
  - Stage by path, never `git add -A`.
  - `test/rename_guard_test.exs` forbids the lower-case old app name in tracked files.
  - `mix gettext.extract --merge` fuzzy-matches new strings: check every fuzzy entry it creates.

## Review Focus

1. **A Generate clicked while a play is being added.** The play must still be in the site afterwards. Today's page sends the plays it showed when clicked. Pinned in Task 2 by "a generate queued behind an add rebuilds the site as it stands when it runs" and "Generate pressed while a play is being added keeps that play".
2. **A play added then removed (or removed then added) inside one batch.** Only the last change counts. Pinned in Task 1 by "only a play's last change counts".
3. **A translation and its original switched on in the same batch.** Both title pages must link each other, although each was written before the other existed on disk. Pinned in Task 1 by "a translation and its original added together link each other".
4. **A batch cut short after its pages.** The next index write must index those plays, not carry their absence forever. Pinned in Task 1 by "a play whose pages a batch wrote, but not its search, is indexed by the next one".
5. **Generate or Deploy double-clicked while busy.** The request runs once. Pinned in Task 2 by "a deploy asked for twice during a build is queued once and runs after it".

---

## File Structure

- `lib/playcode/export/static_site.ex`
  - **New:** `apply_changes/2`, and the private `build_plays/3`, `relatives/3`, `published_plays/1`, `remove_play_files/2`, `write_catalogue/3` and `write_search/3`.
  - **Rewritten as one-change wrappers:** `generate_single_play/2` and `remove_single_play/2`.
  - **Rewritten on the new helpers:** `rebuild_index/2`.
  - **Removed:** `refresh_family/3` and `write_index_pages/4`.
- `lib/playcode/export/site_builder.ex`: the queue, batching, deduplication, the `:queued` and `:published` broadcasts, and Generate reading the site at run time.
- `lib/playcode_web/live/admin/export_site_live.ex`
  - **New:** a `pending` map of play changes, the `busy` and `indexing` flags, and done and failed messages per batch.
  - **Removed:** `exporting_play`, `removing_play`, `reply/2` and `rebuild_codes/1`.
- `priv/gettext/**`: the new strings.
- `test/support/static_site_helpers.ex`: `await_idle_builder/1` compares the new status shape.
- Tests:
  - `test/playcode/export/static_site_test.exs`
  - `test/playcode/export/static_site_search_test.exs`
  - `test/playcode/export/site_builder_test.exs` (rewritten)
  - `test/playcode_web/live/admin/export_site_live_test.exs`
- Docs:
  - `CLAUDE.md`, the SiteBuilder bullet;
  - `docs/superpowers/specs/2026-10-02-static-site-followups-design.md`, Part B item 4.

---

### Task 1: `StaticSite.apply_changes/2`, a batch of adds and removes with one index write

**Files:**
- Modify: `lib/playcode/export/static_site.ex`
- Test: `test/playcode/export/static_site_test.exs`, `test/playcode/export/static_site_search_test.exs`

**Interfaces:**
- Consumes: the existing private `build_play/3`, `write_play/3`, `site/2`, `defaults/1`, `write_assets/1`, `concurrency/0`, `in_english/1` and `safe_code!/1`; `Search.indexed_codes/1`, `Search.write_play/2` and `Search.write_index/3`.
- Produces:
  - `StaticSite.apply_changes([{:add, play_id} | {:remove, code}], opts) :: {:ok, %{skipped: [play_id]}}`.
  - Options as `generate/1` takes them, plus `:on_published` (`fun() -> any`, default a no-op).
  - `generate_single_play/2` and `remove_single_play/2` keep their signatures and return `:ok`.

- [ ] **Step 1: Write the failing tests**

Append to `test/playcode/export/static_site_test.exs`, inside the module and after the family tests. It already has `complete_play/1`, `title_page/2`, `hrefs/1`, and `generate!/2`, `read!/2` and `load_js!/2` from `Playcode.StaticSiteHelpers`.

```elixir
  describe "a batch of changes" do
    test "adds and removes several plays in one go" do
      a = complete_play(%{"title" => "Alfa Batch Tragedy"})
      b = complete_play(%{"title" => "Beta Batch Comedy"})
      c = complete_play(%{"title" => "Gamma Batch Farce"})
      dir = generate!([a])

      assert {:ok, %{skipped: []}} =
               StaticSite.apply_changes([{:add, b.id}, {:remove, a.code}, {:add, c.id}],
                 output_dir: dir
               )

      assert StaticSite.list_exported_codes(dir) == Enum.sort([b.code, c.code])
      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      assert Enum.sort(Enum.map(plays, & &1["code"])) == Enum.sort([b.code, c.code])
      assert read!(dir, "index.html") =~ "Gamma Batch Farce"
      refute read!(dir, "index.html") =~ "Alfa Batch Tragedy"
    end

    test "only a play's last change counts" do
      kept_out = complete_play(%{"title" => "Kept Out"})
      put_back = complete_play(%{"title" => "Put Back"})
      dir = generate!([put_back])

      assert {:ok, _} =
               StaticSite.apply_changes(
                 [
                   {:add, kept_out.id},
                   {:remove, kept_out.code},
                   {:remove, put_back.code},
                   {:add, put_back.id}
                 ],
                 output_dir: dir
               )

      assert StaticSite.list_exported_codes(dir) == [put_back.code]
    end

    # The callback runs in the caller, between the pages and the index, so what the site
    # holds at that moment can be read without a race.
    test "pages and the catalogue are in place before the search index is written" do
      first = complete_play(%{"title" => "Published First"})
      later = complete_play(%{"title" => "Indexed Later"})
      dir = generate!([first])
      test = self()

      at_publish = fn ->
        {"plays", "all", plays} = load_js!(dir, "search/plays.js")

        send(
          test,
          {:published, StaticSite.list_exported_codes(dir), read!(dir, "index.html"),
           Enum.map(plays, & &1["code"])}
        )
      end

      {:ok, _} =
        StaticSite.apply_changes([{:add, later.id}], output_dir: dir, on_published: at_publish)

      assert_received {:published, on_disk, catalogue, searchable}
      assert later.code in on_disk
      assert catalogue =~ "Indexed Later"
      refute later.code in searchable

      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      assert later.code in Enum.map(plays, & &1["code"])
    end

    test "a play that no longer exists is skipped and the rest lands" do
      a = complete_play()
      dir = generate!([a])
      b = complete_play()
      missing = Ecto.UUID.generate()

      assert {:ok, %{skipped: [^missing]}} =
               StaticSite.apply_changes([{:add, missing}, {:add, b.id}], output_dir: dir)

      assert StaticSite.list_exported_codes(dir) == Enum.sort([a.code, b.code])
    end

    test "a translation and its original added together link each other" do
      %{original: original, translation: translation} = translation_family_fixture()
      dir = generate!([complete_play()])

      {:ok, _} =
        StaticSite.apply_changes([{:add, translation.id}, {:add, original.id}],
          output_dir: dir
        )

      assert "../#{translation.code}/index.html" in hrefs(title_page(dir, original))
      assert "../#{original.code}/index.html" in hrefs(title_page(dir, translation))
    end
  end
```

Append to `test/playcode/export/static_site_search_test.exs`, inside `describe "updating a generated site"`. Its setup gives `first` (title "Zeta", word "primero") and `second` (title "Alfa", word "segundo"), and the module defines `one_verse_play/2`.

```elixir
    test "a play whose pages a batch wrote, but not its search, is indexed by the next one",
         %{first: first, second: second} do
      dir = generate!([first, second], all: true)

      # What a batch cut short after its pages leaves behind: the play is on disk, but
      # the index's own list of plays lacks it.
      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      kept = Enum.reject(plays, &(&1["code"] == second.code))

      File.write!(
        Path.join([dir, "search", "plays.js"]),
        ~s|EMOTHE.search.load("plays","all",#{Jason.encode!(kept)});\n|
      )

      third = one_verse_play("Mu", "tercero")

      {:ok, _} =
        Playcode.Export.StaticSite.apply_changes([{:add, third.id}], output_dir: dir)

      # Title order is Alfa (second), Mu (third), Zeta (first): second is play 0.
      {"index", "se", shard} = load_js!(dir, "search/index/se.js")
      assert [0, 1, _] = shard["segundo"]
    end
```

- [ ] **Step 2: Run them to see them fail**

Run: `mix test test/playcode/export/static_site_test.exs test/playcode/export/static_site_search_test.exs`
Expected: 6 failures, each `(UndefinedFunctionError) function Playcode.Export.StaticSite.apply_changes/2 is undefined or private`.

- [ ] **Step 3: Implement `apply_changes/2` and the helpers**

In `lib/playcode/export/static_site.ex`:

1. In the moduledoc, replace the paragraph that begins "`generate/1`, `generate_single_play/2`, `remove_single_play/2` and `rebuild_index/2`
  must not run concurrently" with:

```
  `generate/1`, `apply_changes/2` (and its one-change wrappers `generate_single_play/2`
  and `remove_single_play/2`) and `rebuild_index/2` must not run concurrently on one
  directory: each rewrites the shared search index, so two at once drop a play from it.
  The admin page's builds go through `Playcode.Export.SiteBuilder`, which runs one at a
  time and batches the adds and removes that queue meanwhile. `mix playcode.export.site`
  runs in its own VM and calls `generate/1` directly; its default `_site` is also the
  admin page's directory in dev, so give it `-o` while a server is building.
```

2. In `generate/1`, replace

```elixir
        report = write_index_pages(plays, Map.new(results, &{&1.code, &1.postings}), dir, opts)
```

with

```elixir
        write_catalogue(plays, dir, opts)
        report = write_search(plays, Map.new(results, &{&1.code, &1.postings}), dir)
```

3. Replace the whole of `generate_single_play/2`, `remove_single_play/2` and `rebuild_index/2` (from `@doc "Exports one play into an existing site, then rebuilds the catalogue and index."` down to the end of `rebuild_index/2`) with:

```elixir
  @doc """
  Applies a batch of changes to an existing site: `{:add, play_id}` exports a play and
  `{:remove, code}` takes one out. Only each play's last change counts, so a play added
  then removed in one batch is never written. Every added play is written knowing the
  plays published when the batch ends, and the published originals and translations of
  the plays it touched are re-exported once each. The pages and the catalogue are written
  first, then `opts[:on_published]` is called, then the search index is rewritten once.

  Added plays that no longer exist (deleted or archived since) are skipped. Options as
  `generate/1`, plus `:on_published` (`fun() -> any`).
  """
  def apply_changes(changes, opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      File.mkdir_p!(Path.join(dir, "plays"))

      live = Map.new(Catalogue.list_plays(), &{&1.id, &1})
      skipped = for {:add, id} <- changes, not Map.has_key?(live, id), uniq: true, do: id
      on_disk = MapSet.new(list_exported_codes(dir))

      last =
        Enum.reduce(changes, %{}, fn
          {:add, id}, acc ->
            case live[id] do
              nil -> acc
              play -> Map.put(acc, play.code, {:add, play})
            end

          {:remove, code}, acc ->
            Map.put(acc, code, :remove)
        end)

      adds = for {_code, {:add, play}} <- last, do: play
      removes = for {code, :remove} <- last, MapSet.member?(on_disk, code), do: code

      published =
        on_disk
        |> MapSet.union(MapSet.new(adds, & &1.code))
        |> MapSet.difference(MapSet.new(removes))

      site = site(opts, published)
      Enum.each(removes, &remove_play_files(dir, &1))
      added = build_plays(Enum.map(adds, & &1.id), dir, site)

      removed = Enum.filter(Catalogue.list_plays(include_deleted: true), &(&1.code in removes))

      refreshed =
        (adds ++ removed)
        |> relatives(published, MapSet.new(adds, & &1.code))
        |> Enum.map(& &1.id)
        |> build_plays(dir, site)

      plays = published_plays(dir)
      write_assets(dir)
      write_catalogue(plays, dir, opts)
      opts[:on_published].()
      write_search(plays, Map.new(added ++ refreshed, &{&1.code, &1.postings}), dir)
      {:ok, %{skipped: skipped}}
    end)
  end

  @doc "Exports one play into an existing site: `apply_changes([{:add, play_id}], opts)`."
  def generate_single_play(play_id, opts \\ []) do
    {:ok, _} = apply_changes([{:add, play_id}], opts)
    :ok
  end

  @doc "Removes one play from an existing site: `apply_changes([{:remove, code}], opts)`."
  def remove_single_play(code, opts \\ []) do
    {:ok, _} = apply_changes([{:remove, code}], opts)
    :ok
  end

  @doc """
  Rewrites the catalogue, about and search pages and the search index for the plays on
  disk. `postings` holds freshly computed postings by code; every other play keeps what
  the current index holds for it, and a play the index lacks is loaded and indexed.
  """
  def rebuild_index(opts \\ [], postings \\ %{}) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      plays = published_plays(dir)
      File.mkdir_p!(dir)
      write_assets(dir)
      write_catalogue(plays, dir, opts)
      write_search(plays, postings, dir)
    end)
  end
```

4. In `defaults/1`, add `on_published: fn -> :ok end,` after `on_progress: fn _ -> :ok end,`.

5. Replace `refresh_family/3` (and its comment) with:

```elixir
  # Prepares, writes and indexes several plays at once.
  defp build_plays(ids, dir, site) do
    ids
    |> Task.async_stream(&build_play(&1, dir, site),
      max_concurrency: concurrency(),
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, result} -> result end)
  end

  # A title page links the play's published original and translations, so theirs change
  # when the play is added or removed. Each is re-exported in full: its title page is
  # rendered from the database, so its pages and search lines must be too, or its
  # contents could link a division it was last exported without. Plays in `fresh` were
  # just written knowing the final site, and are left alone.
  defp relatives(plays, published, fresh) do
    ids = MapSet.new(plays, & &1.id)
    parents = MapSet.new(plays, & &1.parent_play_id)

    Enum.filter(Catalogue.list_plays(), fn member ->
      (MapSet.member?(parents, member.id) or MapSet.member?(ids, member.parent_play_id)) and
        MapSet.member?(published, member.code) and not MapSet.member?(fresh, member.code)
    end)
  end

  # The site's plays in catalogue order: those with a folder under plays/.
  defp published_plays(dir) do
    codes = MapSet.new(list_exported_codes(dir))
    Enum.filter(Catalogue.list_plays(sort: :title_sort), &MapSet.member?(codes, &1.code))
  end

  defp remove_play_files(dir, code) do
    safe_code!(code)
    File.rm_rf!(Path.join([dir, "plays", code]))
    File.rm(Path.join([dir, "plays", "#{code}.html"]))
  end
```

6. Replace `write_index_pages/4` with these two functions. The first keeps its body minus the last line:

```elixir
  # The catalogue, about and search pages.
  defp write_catalogue(plays, dir, opts) do
    site = site(opts, MapSet.new(plays, & &1.code))

    assigns = %{
      site: site,
      works: works(plays),
      facets: facets(plays),
      count: length(plays),
      authors:
        plays |> Enum.map(& &1.author_name) |> Enum.reject(&is_nil/1) |> Enum.uniq() |> length()
    }

    File.write!(Path.join(dir, "index.html"), Pages.render(:catalogue, assigns))
    File.write!(Path.join(dir, "about.html"), Pages.render(:about, %{site: site}))
    File.write!(Path.join(dir, "search.html"), Pages.render(:search, %{site: site}))
  end

  # The search index. `postings` holds freshly computed postings by code; every other
  # play keeps what the current index holds for it. A play the index lacks (its pages
  # written by a batch that stopped before its search) is loaded and indexed: the index's
  # own list of plays, `search/plays.js`, is what `Search.indexed_codes/1` reads.
  defp write_search(plays, postings, dir) do
    indexed = MapSet.new(Search.indexed_codes(dir))

    missing =
      plays
      |> Enum.reject(&(Map.has_key?(postings, &1.code) or MapSet.member?(indexed, &1.code)))
      |> Task.async_stream(
        fn play ->
          in_english(fn -> {play.code, Search.write_play(dir, Edition.load(play.id))} end)
        end,
        max_concurrency: concurrency(),
        timeout: :infinity
      )
      |> Map.new(fn {:ok, pair} -> pair end)

    Search.write_index(dir, plays, Map.merge(postings, missing))
  end
```

7. Check that nothing else calls `refresh_family`, `write_index_pages` or the removed `Play` alias use: run `grep -n "refresh_family\|write_index_pages" lib/`, which must print nothing. If `alias Playcode.Catalogue.Play` is now unused, `--warnings-as-errors` will say so; remove it then.

- [ ] **Step 4: Run the tests**

Run: `mix test test/playcode/export/static_site_test.exs test/playcode/export/static_site_search_test.exs`
Expected: PASS. The existing family, removal and incremental-index tests run through the wrappers and must stay green.

- [ ] **Step 5: Prove each new test bites**

For each break below:
1. Make the break.
2. Run the test named.
3. Watch it go red.
4. Restore the code.
5. Record the command and the red output in your report.

The breaks:
- Make `last` keep the first change per play, with `Map.put_new` instead of `Map.put`: "only a play's last change counts".
- Call `opts[:on_published].()` after `write_search`: "pages and the catalogue are in place before the search index is written".
- Build the added plays with `site(opts, MapSet.put(on_disk, play.code))` per play, so each sees only itself and the disk: "a translation and its original added together link each other".
- In `write_search`, treat every play with a `search/lines/<CODE>/` folder as indexed, instead of reading `Search.indexed_codes/1`: "a play whose pages a batch wrote, but not its search, is indexed by the next one".

- [ ] **Step 6: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test && node --test test/js/search.test.mjs`
Expected: all pass.

```bash
git add lib/playcode/export/static_site.ex test/playcode/export/static_site_test.exs test/playcode/export/static_site_search_test.exs
git commit -m "feat: a batch of adds and removes writes the search index once

StaticSite.apply_changes/2 applies {:add, id} and {:remove, code} changes:
only each play's last change counts, every added play is written knowing
the final published set, relatives are re-exported once, and the pages
and catalogue are written before the index (on_published is called
between). generate_single_play/2 and remove_single_play/2 are one-change
wrappers.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The builder queues and batches; the admin page follows

**Files:**
- Modify:
  - `lib/playcode/export/site_builder.ex`
  - `lib/playcode_web/live/admin/export_site_live.ex`
  - `priv/gettext/default.pot`
  - `priv/gettext/en/LC_MESSAGES/default.po`
  - `priv/gettext/es/LC_MESSAGES/default.po`
  - `test/support/static_site_helpers.ex`
  - `CLAUDE.md`
  - `docs/superpowers/specs/2026-10-02-static-site-followups-design.md`
- Test:
  - `test/playcode/export/site_builder_test.exs` (rewritten)
  - `test/playcode_web/live/admin/export_site_live_test.exs`

**Interfaces:**
- Consumes: `StaticSite.apply_changes/2` with `:on_published` (Task 1), `StaticSite.generate/1`, `StaticSite.list_exported_codes/1`, `StaticSite.output_dir/0` and `Deployer.deploy_to_github_pages/3`.
- Produces: the starters `generate/1`, `add/2`, `remove/2` and `deploy/1` return `:started | :queued`. `status/0` returns `%{job: job | nil, queue: [request]}`. The broadcasts are listed in Global Constraints.

- [ ] **Step 1: Rewrite the builder tests**

Replace `test/playcode/export/site_builder_test.exs` with:

```elixir
defmodule Playcode.Export.SiteBuilderTest do
  @moduledoc """
  The one process that writes and ships the admin's static site. Driven through its
  public functions and read back from the files it writes and the broadcasts it sends.
  """
  # Not async: the builder runs in the app's tree, so its tasks reach the database only
  # in the shared sandbox, and it writes the one site directory the admin page also uses.
  use Playcode.DataCase, async: false

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Export.{SiteBuilder, StaticSite}

  setup do
    File.rm_rf!(StaticSite.output_dir())

    on_exit(fn ->
      await_idle_builder()
      File.rm_rf!(StaticSite.output_dir())
    end)

    SiteBuilder.subscribe()
    :ok
  end

  defp in_site, do: StaticSite.list_exported_codes(StaticSite.output_dir())

  defp in_search do
    {"plays", "all", plays} = load_js!(StaticSite.output_dir(), "search/plays.js")
    Enum.map(plays, & &1["code"])
  end

  # Every broadcast up to and including `last`, in the order they arrived, each as
  # {kind, job or request}.
  defp events_until(last, seen \\ []) do
    event =
      receive do
        {:site_builder, kind, job} -> {kind, job}
        {:site_builder, kind, job, _} -> {kind, job}
      after
        10_000 -> flunk("no #{inspect(last)} after #{inspect(Enum.reverse(seen))}")
      end

    if event == last, do: Enum.reverse([event | seen]), else: events_until(last, [event | seen])
  end

  # Not a race, in every test that queues: a build loads from the database and writes
  # files, milliseconds, while the next call follows within microseconds, and the
  # builder marks itself busy before it replies to the first.

  test "a request during a build waits its turn, then lands" do
    a = play_fixture()
    b = play_fixture()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(b.id, [])

    events = events_until({:done, {:batch, [{:add, b.id}]}})
    assert {:queued, {:add, b.id}} in events
    assert {:done, {:batch, [{:add, a.id}]}} in events
    assert in_site() == Enum.sort([a.code, b.code])
    assert Enum.sort(in_search()) == Enum.sort([a.code, b.code])
  end

  test "the adds and removes that queue during a build run as one batch" do
    [a, b, c] = for _ <- 1..3, do: play_fixture()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(b.id, [])
    assert :queued = SiteBuilder.add(c.id, [])
    assert :queued = SiteBuilder.remove(a.code, [])

    batch = {:batch, [{:add, b.id}, {:add, c.id}, {:remove, a.code}]}
    assert {:started, batch} in events_until({:done, batch})
    assert in_site() == Enum.sort([b.code, c.code])
    assert Enum.sort(in_search()) == Enum.sort([b.code, c.code])
  end

  test "a batch announces its pages before its search index" do
    a = play_fixture()
    assert :started = SiteBuilder.add(a.id, [])

    batch = {:batch, [{:add, a.id}]}

    assert events_until({:done, batch}) == [
             {:started, batch},
             {:published, batch},
             {:done, batch}
           ]
  end

  test "a generate queued behind an add rebuilds the site as it stands when it runs" do
    [a, b, _never_published] = for _ <- 1..3, do: play_fixture(%{"is_complete" => true})
    {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [a.code])

    assert :started = SiteBuilder.add(b.id, [])
    # The admin page used to send the plays it showed when clicked, before b landed;
    # rebuilding from that list would delete b.
    assert :queued = SiteBuilder.generate(play_codes: [a.code])
    events_until({:done, :generate})

    assert in_site() == Enum.sort([a.code, b.code])
  end

  test "a play that no longer exists is skipped and the rest of its batch lands" do
    a = play_fixture()
    b = play_fixture()
    missing = Ecto.UUID.generate()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(missing, [])
    assert :queued = SiteBuilder.add(b.id, [])

    batch = {:batch, [{:add, missing}, {:add, b.id}]}
    assert_receive {:site_builder, :done, ^batch, {:ok, %{skipped: [^missing]}}}, 10_000
    assert in_site() == Enum.sort([a.code, b.code])
  end

  @tag :capture_log
  test "a batch that crashes is reported, and the queue carries on" do
    # Play codes are not validated, and one that is not a plain name cannot be a folder.
    bad = play_fixture(%{"code" => "bad/code"})
    good = play_fixture()

    assert :started = SiteBuilder.add(bad.id, [])
    assert :queued = SiteBuilder.add(good.id, [])

    events = events_until({:done, {:batch, [{:add, good.id}]}})
    assert {:failed, {:batch, [{:add, bad.id}]}} in events
    assert in_site() == [good.code]
    assert SiteBuilder.status() == %{job: nil, queue: []}
  end

  test "status names the running job and the requests waiting behind it" do
    a = play_fixture()
    b = play_fixture()

    assert :started = SiteBuilder.add(a.id, [])
    assert :queued = SiteBuilder.add(b.id, [])
    assert SiteBuilder.status() == %{job: {:batch, [{:add, a.id}]}, queue: [{:add, b.id}]}

    events_until({:done, {:batch, [{:add, b.id}]}})
    assert SiteBuilder.status() == %{job: nil, queue: []}
  end

  # A deploy pushes the whole directory, so it waits for the build before it.
  test "a deploy asked for twice during a build is queued once and runs after it" do
    a = play_fixture()
    assert :started = SiteBuilder.add(a.id, [])

    # Invalid on purpose: Deployer rejects a repository without "/" before it pushes
    # anything, so this test can never reach GitHub.
    assert :queued = SiteBuilder.deploy("not a repo")
    assert :queued = SiteBuilder.deploy("not a repo")
    assert SiteBuilder.status().queue == [:deploy]

    events = events_until({:done, :deploy})
    assert Enum.count(events, &(&1 == {:started, :deploy})) == 1

    assert Enum.find_index(events, &(&1 == {:done, {:batch, [{:add, a.id}]}})) <
             Enum.find_index(events, &(&1 == {:started, :deploy}))
  end

  # Regression: an unexpected message crashed the builder, which restarted idle while
  # its job ran on. A {nil, _} while idle even matched the task's reply, whose ref is nil
  # then, and crashed it in demonitor(nil).
  test "a stray message neither stops the builder nor reports anything" do
    builder = Process.whereis(SiteBuilder)
    send(builder, :stray)
    send(builder, {nil, :x})

    # A call is answered only after the messages sent before it.
    assert SiteBuilder.status() == %{job: nil, queue: []}
    assert Process.whereis(SiteBuilder) == builder
    refute_receive {:site_builder, _, _, _}
  end
end
```

Its commit body must say the two deleted tests, "a second job is refused while one runs, and the first lands intact" and "a deploy is refused while a build runs", are replaced. Their behaviour changed from refusing to queueing: the first is covered by "a request during a build waits its turn, then lands", the second by "a deploy asked for twice during a build is queued once and runs after it".

In `test/support/static_site_helpers.ex`, change the first `cond` line of `await_idle_builder/1` from `SiteBuilder.status() == %{job: nil} -> :ok` to:

```elixir
      SiteBuilder.status() == %{job: nil, queue: []} -> :ok
```

- [ ] **Step 2: Add the admin page tests**

In `test/playcode_web/live/admin/export_site_live_test.exs`, add after the test "Download is refused while a build runs":

```elixir
  test "switches flipped during a build wait their turn and land together",
       %{conn: conn, a: a, b: b} do
    c = play_fixture(%{"is_complete" => true, "title" => "Delta Farce"})
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    # Not a race: adding a loads a play and writes files, milliseconds, while the next
    # clicks follow within microseconds, so they reach a busy builder and queue.
    lv |> element(switch(a)) |> render_click()
    lv |> element(switch(b)) |> render_click()
    lv |> element(switch(c)) |> render_click()

    # On its way in: shown on, and not clickable until it lands.
    assert has_element?(lv, "#{switch(b)}[checked][disabled]")

    wait_for(fn -> render(lv) =~ t("%{count} changes applied to the static site.", count: 2) end)

    assert has_element?(lv, "#{switch(b)}[checked]")
    assert has_element?(lv, "#{switch(c)}[checked]")
    refute has_element?(lv, "#{switch(c)}[disabled]")
    assert response(preview(conn, "plays/#{c.code}/index.html"), 200)
  end

  test "Generate pressed while a play is being added keeps that play",
       %{conn: conn, a: a, b: b} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    lv |> element(switch(b)) |> render_click()

    assert lv |> element("form[phx-submit=generate]") |> render_submit() =~
             t("Queued: it starts when the current build finishes.")

    wait_for(fn -> render(lv) =~ t("Generation Complete") end)
    assert response(preview(conn, "plays/#{b.code}/index.html"), 200)
  end
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `mix test test/playcode/export/site_builder_test.exs test/playcode_web/live/admin/export_site_live_test.exs`
Expected: failures. The starters return `:ok` and refuse with `{:error, :busy}`, so `assert :started = …` and `assert :queued = …` fail. `status/0` has no `:queue`. The two new LiveView tests get the busy flash.

- [ ] **Step 4: Rewrite the builder**

Replace `lib/playcode/export/site_builder.ex` with:

```elixir
defmodule Playcode.Export.SiteBuilder do
  @moduledoc """
  The one process that writes and ships the admin's static site, `StaticSite.output_dir/0`.

  Adding or removing a play reads the search index on disk and writes it back, and a
  deploy pushes the whole directory, so the builder runs one job at a time. A request
  that arrives while a job runs is queued, not refused: each starter returns `:started`
  or `:queued`, and a request already waiting is not queued twice. When a job ends, the
  adds and removes at the front of the queue run as one batch, which publishes its pages
  first and rewrites the search index once (`StaticSite.apply_changes/2`); a generate or
  a deploy runs on its own, in its turn. Generate rebuilds the plays on disk when it runs.

  Jobs are `:generate`, `{:batch, [{:add, play_id} | {:remove, code}]}` and `:deploy`.
  It broadcasts on `"static_site"`, so every admin page shows the same state:
  `{:site_builder, :queued, request}` (`:generate`, `{:add, id}`, `{:remove, code}` or
  `:deploy`), `{:site_builder, :started, job}`, `{:site_builder, :progress, job, info}`,
  `{:site_builder, :published, job}` (a batch's pages are live, its search is next),
  `{:site_builder, :done, job, result}` and `{:site_builder, :failed, job, reason}`.
  """

  # ponytail: one builder for the app's one output_dir/0. Should a second site ever
  # appear, register one builder per directory in a Registry.

  use GenServer

  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.Deployer

  @topic "static_site"
  @tasks __MODULE__.Tasks

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Playcode.PubSub, @topic)

  @doc """
  A full build of the plays in the site when it runs, every complete play if the site is
  empty. `opts` as `StaticSite.generate/1` takes them, but for the directory and plays.
  """
  def generate(opts), do: request(:generate, opts)

  def add(play_id, opts), do: request({:add, play_id}, opts)
  def remove(code, opts), do: request({:remove, code}, opts)
  def deploy(repo), do: request(:deploy, repo)

  @doc "The running job and the requests waiting behind it, oldest first."
  def status, do: GenServer.call(__MODULE__, :status)

  defp request(request, args), do: GenServer.call(__MODULE__, {:request, request, args})

  @impl true
  def init(nil), do: {:ok, %{job: nil, ref: nil, queue: []}}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{job: state.job, queue: Enum.map(state.queue, &elem(&1, 0))}, state}
  end

  # Idle means the queue is empty: the request runs at once, as a job of its own.
  def handle_call({:request, request, args}, _from, %{job: nil} = state) do
    {:reply, :started, run_next(%{state | queue: [{request, args}]})}
  end

  def handle_call({:request, request, args}, _from, state) do
    if Enum.any?(state.queue, fn {queued, _} -> queued == request end) do
      {:reply, :queued, state}
    else
      broadcast({:site_builder, :queued, request})
      {:reply, :queued, %{state | queue: state.queue ++ [{request, args}]}}
    end
  end

  @impl true
  def handle_info({ref, result}, %{ref: ref, job: job} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    broadcast({:site_builder, :done, job, result})
    {:noreply, run_next(state)}
  end

  # The reply is flushed with the monitor, so a :DOWN means the task gave no result.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{ref: ref, job: job} = state) do
    broadcast({:site_builder, :failed, job, reason})
    {:noreply, run_next(state)}
  end

  # Crashing on a stray message would restart the builder idle while its job ran on.
  def handle_info(_message, state), do: {:noreply, state}

  # Starts what is at the front of the queue: every add and remove there as one batch,
  # or a generate or a deploy on its own.
  defp run_next(%{queue: []} = state), do: %{state | job: nil, ref: nil}

  defp run_next(%{queue: queue} = state) do
    {job, args, rest} = take(queue)
    # Announced before the task starts, so no page hears its progress before it.
    broadcast({:site_builder, :started, job})
    task = Task.Supervisor.async_nolink(@tasks, fn -> run(job, args) end)
    %{state | job: job, ref: task.ref, queue: rest}
  end

  defp take([{request, args} | rest]) when request in [:generate, :deploy],
    do: {request, args, rest}

  defp take(queue) do
    {changes, rest} = Enum.split_while(queue, fn {request, _} -> change?(request) end)
    # A batch takes the form values of its latest request.
    {_, args} = List.last(changes)
    {{:batch, Enum.map(changes, &elem(&1, 0))}, args, rest}
  end

  defp change?({:add, _}), do: true
  defp change?({:remove, _}), do: true
  defp change?(_request), do: false

  # Rebuilds the site as it stands when the generate runs, not when it was asked for:
  # an add or remove queued before it keeps its change.
  defp run(:generate, opts) do
    opts
    |> in_site()
    |> Keyword.put(:play_codes, codes_in_site())
    |> Keyword.put(:on_progress, progress(:generate))
    |> StaticSite.generate()
  end

  defp run({:batch, changes} = job, opts) do
    published = fn -> broadcast({:site_builder, :published, job}) end
    StaticSite.apply_changes(changes, opts |> in_site() |> Keyword.put(:on_published, published))
  end

  # The StaticSite entry points set English themselves; Deployer translates nothing.
  defp run(:deploy, repo) do
    Deployer.deploy_to_github_pages(StaticSite.output_dir(), repo, on_progress: progress(:deploy))
  end

  # An empty site gets every complete play: StaticSite drops a nil option.
  defp codes_in_site do
    case StaticSite.list_exported_codes(StaticSite.output_dir()) do
      [] -> nil
      codes -> codes
    end
  end

  defp in_site(opts), do: Keyword.put(opts, :output_dir, StaticSite.output_dir())
  defp progress(job), do: &broadcast({:site_builder, :progress, job, &1})

  defp broadcast(message), do: Phoenix.PubSub.broadcast(Playcode.PubSub, @topic, message)
end
```

- [ ] **Step 5: Make the admin page follow the queue**

In `lib/playcode_web/live/admin/export_site_live.ex`:

1. In `mount/3`:
   - Replace `|> assign(:exporting_play, nil)` and `|> assign(:removing_play, nil)` with:

```elixir
      |> assign(:pending, %{})
      |> assign(:busy, false)
      |> assign(:indexing, false)
```

   - Replace `{:ok, started(socket, SiteBuilder.status().job)}` with `{:ok, follow(socket, SiteBuilder.status())}`.

2. Replace the `"generate"`, `"deploy"`, `"toggle_play"` and `"download_zip"` handlers with:

```elixir
  def handle_event("generate", _params, socket) do
    [version: socket.assigns.version, base_url: socket.assigns.base_url]
    |> SiteBuilder.generate()
    |> queued_flash(socket)
  end

  def handle_event("deploy", _params, socket) do
    repo = String.trim(socket.assigns.github_repo)

    if repo == "" do
      {:noreply, put_flash(socket, :error, gettext("Please enter a GitHub repository."))}
    else
      repo |> SiteBuilder.deploy() |> queued_flash(socket)
    end
  end

  # A switch with a change on its way is disabled, so this decides by what is on disk.
  def handle_event("toggle_play", %{"id" => id, "code" => code}, socket) do
    opts = [version: socket.assigns.version, base_url: socket.assigns.base_url]

    if MapSet.member?(socket.assigns.exported_codes, code),
      do: SiteBuilder.remove(code, opts),
      else: SiteBuilder.add(id, opts)

    {:noreply, socket}
  end

  # The zip is read from the directory a job would be rewriting.
  def handle_event("download_zip", _params, socket) do
    case SiteBuilder.status() do
      %{job: nil, queue: []} ->
        # Create zip in temp dir and redirect to download
        zip_path = Path.join(System.tmp_dir!(), "emothe-static-site.zip")

        case create_zip(StaticSite.output_dir(), zip_path) do
          :ok ->
            {:noreply, redirect(socket, to: ~p"/admin/export/download-zip")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create zip: #{inspect(reason)}")}
        end

      _busy ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("The site is busy with another build. Try again when it finishes.")
         )}
    end
  end
```

3. Replace the `handle_info` clauses for `:started`, `:done` and `:failed` with the following. Keep the two `:progress` clauses as they are.

```elixir
  def handle_info({:site_builder, :queued, request}, socket),
    do: {:noreply, queued(socket, request)}

  def handle_info({:site_builder, :started, job}, socket), do: {:noreply, started(socket, job)}

  def handle_info({:site_builder, :published, {:batch, changes}}, socket),
    do: {:noreply, socket |> settle(changes) |> assign(:indexing, true)}

  def handle_info({:site_builder, :done, job, result}, socket),
    do: {:noreply, socket |> finished(job) |> done(job, result)}

  def handle_info({:site_builder, :failed, job, reason}, socket) do
    {:noreply, socket |> finished(job) |> put_flash(:error, failed(job, crash_reason(reason)))}
  end
```

   Move the `:queued`, `:started` and `:published` clauses so that they sit with the `:progress` clauses, before `render/1`; the `@impl true` stays on the first `handle_info`.

4. In the template:
   - The Generate button's `disabled={…}` becomes `disabled={@generating}`.
   - The play row's spinner `:if={play.id in [@exporting_play, @removing_play]}` becomes `:if={Map.has_key?(@pending, play.id)}`.
   - The switch's `checked` and `disabled` become:

```heex
                checked={
                  (MapSet.member?(@exported_codes, play.code) and @pending[play.id] != :remove) or
                    @pending[play.id] == :add
                }
                disabled={Map.has_key?(@pending, play.id)}
```

   - The Deploy button's `disabled={…}` becomes `disabled={@deploying}`.
   - The Download button's `disabled={…}` becomes `disabled={@busy}`.
   - Right after the "Open preview" link, inside the same container, add:

```heex
            <span :if={@indexing} class="badge badge-ghost gap-1">
              <span class="loading loading-spinner loading-xs"></span>
              {gettext("Updating search…")}
            </span>
```

5. Delete `reply/2`, every `started/2` clause, `idle/1`, the `done/3` clauses for `{:add, _}` and `{:remove, _}`, the `failed/2` clauses for `{:add, _}` and `{:remove, _}`, and `rebuild_codes/1`. Add the following:

```elixir
  defp queued_flash(:started, socket), do: {:noreply, socket}

  defp queued_flash(:queued, socket) do
    {:noreply,
     put_flash(socket, :info, gettext("Queued: it starts when the current build finishes."))}
  end

  # What the builder runs and what waits behind it, as a page opened now sees it.
  defp follow(socket, %{job: job, queue: queue}),
    do: Enum.reduce(queue, started(socket, job), &queued(&2, &1))

  # A change on its way: its switch shows where the play is going until it lands.
  defp queued(socket, {:add, id}), do: pending(socket, id, :add)
  defp queued(socket, {:remove, code}), do: pending(socket, play_id(socket, code), :remove)
  defp queued(socket, _generate_or_deploy), do: assign(socket, :busy, true)

  defp pending(socket, id, change) do
    socket
    |> update(:pending, &Map.put(&1, id, change))
    |> assign(:busy, true)
  end

  defp started(socket, nil), do: socket

  defp started(socket, :generate) do
    socket
    |> assign(:busy, true)
    |> assign(:generating, true)
    |> assign(:gen_current, 0)
    |> assign(:gen_total, 0)
    |> assign(:gen_detail, gettext("Starting..."))
    |> assign(:gen_result, nil)
    |> assign(:deploy_status, nil)
    |> assign(:deploy_url, nil)
  end

  defp started(socket, {:batch, changes}),
    do: Enum.reduce(changes, assign(socket, :indexing, false), &queued(&2, &1))

  defp started(socket, :deploy) do
    socket
    |> assign(:busy, true)
    |> assign(:deploying, true)
    |> assign(:deploy_status, gettext("Starting deploy..."))
  end

  # A batch's pages are published: its switches settle on what is on disk.
  defp settle(socket, changes) do
    ids = Enum.map(changes, &change_id(socket, &1))

    socket
    |> update(:pending, &Map.drop(&1, ids))
    |> assign(:exported_codes, on_disk())
  end

  # A job ended. If requests wait, the builder's next :started marks the page busy again.
  defp finished(socket, {:batch, changes}), do: socket |> settle(changes) |> idle()
  defp finished(socket, _job), do: socket |> assign(:exported_codes, on_disk()) |> idle()

  defp idle(socket),
    do: assign(socket, generating: false, deploying: false, indexing: false, busy: false)

  defp change_id(_socket, {:add, id}), do: id
  defp change_id(socket, {:remove, code}), do: play_id(socket, code)

  # The switches name plays by id; the builder names a removal by its code.
  defp play_id(socket, code),
    do: Enum.find_value(socket.assigns.plays, code, &(&1.code == code && &1.id))

  defp on_disk, do: MapSet.new(StaticSite.list_exported_codes(StaticSite.output_dir()))
```

   Then add these `done/3` clauses before the existing `done(socket, :deploy, {:ok, url})` clause:

```elixir
  defp done(socket, {:batch, [{:add, _}]}, {:ok, %{skipped: []}}),
    do: put_flash(socket, :info, gettext("Play exported to static site."))

  defp done(socket, {:batch, [{:remove, code}]}, {:ok, %{skipped: []}}),
    do: put_flash(socket, :info, gettext("Removed %{code} from static site.", code: code))

  defp done(socket, {:batch, changes}, {:ok, %{skipped: []}}) do
    put_flash(
      socket,
      :info,
      gettext("%{count} changes applied to the static site.", count: length(changes))
    )
  end

  defp done(socket, {:batch, _changes}, {:ok, %{skipped: skipped}}) do
    put_flash(
      socket,
      :error,
      ngettext(
        "A play that no longer exists was skipped.",
        "%{count} plays that no longer exist were skipped.",
        length(skipped)
      )
    )
  end
```

   Add these `failed/2` clauses after the existing `failed(:deploy, reason)`:

```elixir
  defp failed({:batch, [{:add, _}]}, reason),
    do: gettext("Could not add the play: %{reason}", reason: reason)

  defp failed({:batch, [{:remove, code}]}, reason),
    do: gettext("Could not remove %{code}: %{reason}", code: code, reason: reason)

  defp failed({:batch, changes}, reason) do
    gettext("Could not apply %{count} changes to the site: %{reason}",
      count: length(changes),
      reason: reason
    )
  end
```

- [ ] **Step 6: Translate**

Run: `mix gettext.extract --merge`

In `priv/gettext/es/LC_MESSAGES/default.po`, give each new msgid its Spanish from Global Constraints. The plural entry gets both `msgstr[0]` and `msgstr[1]`. Check every entry marked `#, fuzzy` that the merge created or changed: correct its msgstr and remove the flag. Leave fuzzy entries that existed before this task alone. Then confirm nothing new is untranslated:

```bash
grep -B3 'msgstr ""$' priv/gettext/es/LC_MESSAGES/default.po | grep -E 'Queued|Updating search|changes applied|Could not apply|no longer exist'
```

Expected: no output.

- [ ] **Step 7: Run the tests**

Run: `mix test test/playcode/export/site_builder_test.exs test/playcode_web/live/admin/export_site_live_test.exs`
Expected: PASS. That includes the unchanged LiveView tests (adding, removing, the second admin's page, the Download refusal, Generate) and the stray-message test.

- [ ] **Step 8: Prove each new test bites**

For each break below:
1. Make the break.
2. Run the file named.
3. Watch it go red.
4. Restore the code.
5. Record each red run in your report.

The breaks:
- Make the busy `handle_call` reply `:started` and start the request straight away instead of queueing it: `site_builder_test.exs` (the waits-its-turn and status tests).
- Make `take/1` take only the first change (`{changes, rest} = Enum.split_at(queue, 1)`): "the adds and removes that queue during a build run as one batch".
- In `run(:generate, opts)`, use `Keyword.put_new(:play_codes, codes_in_site())`: "a generate queued behind an add rebuilds the site as it stands when it runs".
- Drop the duplicate check in the busy `handle_call`: "a deploy asked for twice during a build is queued once and runs after it".
- Remove `published` from `run({:batch, …})` (pass `opts |> in_site()` only): "a batch announces its pages before its search index".
- In the LiveView, make `queued(socket, {:add, id})` return `socket` unchanged: "switches flipped during a build wait their turn and land together".

- [ ] **Step 9: Update the docs**

In `CLAUDE.md`, replace the bullet that begins "- `Playcode.Export.SiteBuilder` — the one process that writes and ships the admin's site" with:

```markdown
- `Playcode.Export.SiteBuilder` — the one process that writes and ships the admin's site (`StaticSite.output_dir/0`): generate, add a play, remove one, deploy. It runs one job at a time under `SiteBuilder.Tasks`, because two builds at once drop a play from the incremental index and a deploy during a build pushes half a site. A request that arrives meanwhile is queued (`:queued`), not refused. When the job ends, the adds and removes at the front of the queue run as one batch through `StaticSite.apply_changes/2`: pages and catalogue first, then one search-index write. Generate rebuilds the plays on disk when it runs. It broadcasts `:queued`, `:started`, `:progress`, `:published`, `:done` and `:failed` on `"static_site"`, so every admin's export page shows the same state. `mix playcode.export.site` runs in its own VM and calls `StaticSite.generate/1` directly, unserialised: its default `_site` is also the admin page's directory in dev, so pass `-o` while a server is building
```

In `docs/superpowers/specs/2026-10-02-static-site-followups-design.md`, Part B item 4, replace the sentence about `SiteBuilder` refusing a second job with:

```markdown
`SiteBuilder` owns the site directory and runs one job at a time; since
`2026-10-03-site-builder-queue-design.md` it queues the requests that arrive meanwhile and
runs queued adds and removes as one batch.
```

- [ ] **Step 10: Run everything and commit**

Run: `mix format && mix compile --warnings-as-errors && mix test && node --test test/js/search.test.mjs`
Expected: all pass.

```bash
git add lib/playcode/export/site_builder.ex lib/playcode_web/live/admin/export_site_live.ex priv/gettext/default.pot priv/gettext/en/LC_MESSAGES/default.po priv/gettext/es/LC_MESSAGES/default.po test/support/static_site_helpers.ex test/playcode/export/site_builder_test.exs test/playcode_web/live/admin/export_site_live_test.exs CLAUDE.md docs/superpowers/specs/2026-10-02-static-site-followups-design.md
git commit -m "feat: the site builder queues requests and batches adds and removes

A request that arrives during a build is queued, not refused; queued
adds and removes run as one batch with one search-index write, its pages
published first. Generate rebuilds the plays on disk when it runs, so a
play added just before it stays. The admin page shows each play's change
on its switch until it lands, and 'Updating search…' until the index is
written.

Replaces the tests 'a second job is refused while one runs, and the
first lands intact' and 'a deploy is refused while a build runs': the
behaviour is now queueing, covered by 'a request during a build waits
its turn, then lands' and 'a deploy asked for twice during a build is
queued once and runs after it'.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
