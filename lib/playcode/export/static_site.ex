defmodule Playcode.Export.StaticSite do
  @moduledoc """
  Generates the published EMOTHE archive: HTML, CSS and JS that work from any web host
  and from the unzipped archive opened as `file://`, following the Endings Project
  principles. Design: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`.

  Only plays marked complete are published unless `all: true`. The archive is in
  English whatever locale the admin generating it uses.

  `generate/1` and `apply_changes/2` (and its one-change wrappers `generate_single_play/2`
  and `remove_single_play/2`) must not run concurrently on one directory: each rewrites
  the shared search index, so two at once drop a play from it.
  The admin page's builds go through `Playcode.Export.SiteBuilder`, which runs one at a
  time and batches the adds and removes that queue meanwhile. `mix playcode.export.site`
  runs in its own VM and calls `generate/1` directly; its default `_site` is also the
  admin page's directory in dev, so give it `-o` while a server is building.

  Every build records itself in `build.json` at the site root: the fingerprint of what
  built it (`StaticSite.Fingerprint`) and each play's `content_version`. From it
  `changed_plays/1`, `site_changed?/2` and `outdated/1` say what changed since.
  """

  alias Playcode.Catalogue
  alias Playcode.Export.TeiXml
  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.{Components, Edition, Fingerprint, Pages, Search}

  @type progress_info :: %{
          step: :assets | :catalogue | :play,
          current: non_neg_integer(),
          total: non_neg_integer(),
          detail: String.t()
        }

  @doc "Where the admin export page builds the site. Tests point it at a temporary directory."
  def output_dir, do: Application.get_env(:playcode, :static_site_dir, "_site")

  @doc """
  Generates the site.

  Options: `:output_dir` (default `"_site"`), `:play_codes` (default all), `:all`
  (include incomplete plays), `:version` (default `"1.0"`), `:build_date` (ISO date,
  default today), `:on_progress` (`fun(progress_info) -> any`).
  """
  def generate(opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      plays = load_plays(opts[:play_codes], opts[:all])
      total = length(plays)

      if plays == [] do
        {:error, "no plays to export (none marked as complete)"}
      else
        Enum.each(plays, &safe_code!(&1.code))
        dir = opts[:output_dir]
        File.rm_rf!(dir)
        File.mkdir_p!(Path.join(dir, "plays"))

        opts[:on_progress].(%{
          step: :assets,
          current: 0,
          total: total,
          detail: "Writing assets..."
        })

        write_assets(dir)
        site = site(opts, MapSet.new(plays, & &1.code))

        results =
          plays
          |> Task.async_stream(&build_play(&1.id, dir, site),
            max_concurrency: concurrency(),
            timeout: :infinity
          )
          |> Enum.with_index(1)
          |> Enum.map(fn {{:ok, result}, n} ->
            opts[:on_progress].(%{step: :play, current: n, total: total, detail: result.code})
            result
          end)

        opts[:on_progress].(%{
          step: :catalogue,
          current: total,
          total: total,
          detail: "Generating catalogue..."
        })

        write_catalogue(plays, dir, opts)
        report = write_search(plays, Map.new(results, &{&1.code, &1.postings}), dir)
        # Last: a build cut short leaves no record, so the next Generate rebuilds it all.
        write_build(dir, Fingerprint.current(opts), Map.new(results, &{&1.code, &1.version}))

        {:ok,
         Map.merge(report, %{
           plays: total,
           size: dir_size(dir),
           output_dir: dir,
           largest_page_gzip: results |> Enum.map(& &1.largest_page_gzip) |> Enum.max(fn -> 0 end)
         })}
      end
    end)
  end

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
      built = read_build(dir)

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
      # Before the removes: a batch with an unusable code must leave the site as it was.
      Enum.each(adds, &safe_code!(&1.code))
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
      written = added ++ refreshed
      write_search(plays, Map.new(written, &{&1.code, &1.postings}), dir)

      # Last, as in generate/1. A batch that began on an empty site wrote every page
      # there is, so it records what built them; otherwise the site's record stands.
      fingerprint = if MapSet.size(on_disk) == 0, do: Fingerprint.current(opts), else: built.site
      versions = Map.new(written, &{&1.code, &1.version})
      write_build(dir, fingerprint, built.plays |> Map.drop(removes) |> Map.merge(versions))
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

  @doc "Codes of the plays the site holds: folders under `plays/` with an `index.html`."
  def list_exported_codes(output_dir \\ "_site") do
    plays_dir = Path.join(output_dir, "plays")

    if File.dir?(plays_dir) do
      plays_dir
      |> File.ls!()
      |> Enum.filter(&File.regular?(Path.join([plays_dir, &1, "index.html"])))
      |> Enum.sort()
    else
      []
    end
  end

  @doc """
  Codes of the plays in the site at `dir` that changed since they were written: the
  published plays whose `content_version` is not the one `build.json` records for them.
  A play it records nothing for counts as changed. Archived and incomplete plays are
  `outdated/1`'s to remove.
  """
  def changed_plays(dir),
    do: for(play <- changed(dir, Catalogue.list_plays(complete: true)), do: play.code)

  @doc """
  Whether the site at `dir` may be out of date as a whole: `build.json` records no
  fingerprint, or another than `Fingerprint.current/1` gives for `opts` (`:version`).
  """
  def site_changed?(dir, opts \\ []),
    do: read_build(dir).site != Fingerprint.current(defaults(opts))

  @doc """
  The batch that brings the site at `dir` up to date through `apply_changes/2`: each
  changed play added again, each play on disk no longer published (archived, deleted or
  no longer complete) removed.
  """
  def outdated(dir) do
    published = Catalogue.list_plays(complete: true)
    live = MapSet.new(published, & &1.code)

    adds = for play <- changed(dir, published), do: {:add, play.id}

    removes =
      for code <- list_exported_codes(dir), not MapSet.member?(live, code), do: {:remove, code}

    adds ++ removes
  end

  # Play codes become folder names that are deleted and rewritten; Play does not
  # validate them, so anything but a plain name ("..", "", "a/b") is refused here.
  @doc false
  def safe_code!(code) do
    if is_binary(code) and Regex.match?(~r/\A[A-Za-z0-9_-]+\z/, code) do
      code
    else
      raise ArgumentError, "play code #{inspect(code)} cannot be used as a folder name"
    end
  end

  defp in_english(fun), do: Gettext.with_locale(PlaycodeWeb.Gettext, "en", fun)

  defp defaults(opts) do
    defaults = [
      output_dir: "_site",
      version: "1.0",
      build_date: Date.to_iso8601(Date.utc_today()),
      on_progress: fn _ -> :ok end,
      on_published: fn -> :ok end,
      all: false
    ]

    Keyword.merge(defaults, Enum.reject(opts, fn {_key, value} -> is_nil(value) end))
  end

  defp site(opts, published) do
    %{
      version: opts[:version],
      build_date: opts[:build_date],
      published: published,
      play_count: MapSet.size(published)
    }
  end

  defp load_plays(nil, all?), do: Catalogue.list_plays(sort: :title_sort, complete: !all?)

  defp load_plays(codes, all?) when is_list(codes),
    do: load_plays(nil, all?) |> Enum.filter(&(&1.code in codes))

  defp write_assets(dir) do
    assets = Path.join(dir, "assets")
    File.rm_rf!(assets)
    File.cp_r!(Application.app_dir(:playcode, "priv/static_site"), assets)
  end

  # Prepares, writes and indexes one play; generate/1 runs several at once. The locale
  # lives in the process dictionary, so each worker sets English itself.
  defp build_play(play_id, dir, site) do
    in_english(fn ->
      edition = Edition.load(play_id)

      edition
      |> write_play(dir, site)
      |> Map.merge(%{
        code: edition.play.code,
        version: edition.play.content_version,
        postings: Search.write_play(dir, edition)
      })
    end)
  end

  # Plays load in parallel, each worker checking connections out per query: bound the
  # workers by the cores and by the pool, minus two so the app is not starved outright.
  defp concurrency do
    pool = Playcode.Repo.config()[:pool_size] || 10
    max(1, min(System.schedulers_online(), pool - 2))
  end

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

  # The `published` plays that are in the site at `dir` with a version other than the
  # one build.json records for them.
  defp changed(dir, published) do
    built = read_build(dir).plays
    on_disk = MapSet.new(list_exported_codes(dir))

    for play <- published,
        MapSet.member?(on_disk, play.code),
        built[play.code] != play.content_version,
        do: play
  end

  @build "build.json"

  # What build.json records: the fingerprint the site was built with (nil if unknown)
  # and each play's content_version. No file, or one that cannot be read, records
  # nothing, so the site and every play in it count as changed.
  defp read_build(dir) do
    with {:ok, json} <- File.read(Path.join(dir, @build)),
         {:ok, %{"plays" => %{} = plays} = build} <- Jason.decode(json) do
      %{site: build["site"], plays: plays}
    else
      _ -> %{site: nil, plays: %{}}
    end
  end

  defp write_build(dir, fingerprint, plays) do
    json = Jason.encode!(%{site: fingerprint, plays: plays}, pretty: true)
    File.write!(Path.join(dir, @build), json)
  end

  defp remove_play_files(dir, code) do
    safe_code!(code)
    File.rm_rf!(Path.join([dir, "plays", code]))
    File.rm(Path.join([dir, "plays", "#{code}.html"]))
  end

  # Writes one play's pages and TEI; returns what the index pages need from it.
  defp write_play(%Edition{play: play} = edition, dir, site) do
    code = safe_code!(play.code)
    play_dir = Path.join([dir, "plays", code])
    File.rm_rf!(play_dir)
    File.mkdir_p!(play_dir)
    assigns = %{edition: edition, site: site}

    File.write!(Path.join(play_dir, "index.html"), Pages.render(:title, assigns))
    File.write!(Path.join(play_dir, "#{code}.xml"), TeiXml.generate(play))

    largest =
      edition.pages
      |> Edition.neighbours()
      |> Enum.map(fn {page, prev, next} ->
        html = Pages.render(:division, Map.merge(assigns, %{page: page, prev: prev, next: next}))
        File.write!(Path.join(play_dir, "#{page.slug}.html"), html)
        byte_size(:zlib.gzip(html))
      end)
      |> Enum.max(fn -> 0 end)

    File.write!(Path.join(play_dir, "text.html"), Pages.render(:text, assigns))
    File.write!(Path.join(play_dir, "statistics.html"), Pages.render(:statistics, assigns))

    File.write!(
      Path.join([dir, "plays", "#{code}.html"]),
      Pages.render(:redirect, %{code: code, title: play.title})
    )

    %{largest_page_gzip: largest}
  end

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

  # One entry per work: each published play under the published play at the root of
  # its translation chain.
  defp works(plays) do
    by_id = Map.new(plays, &{&1.id, &1})

    plays
    |> Enum.group_by(&root_id(&1, by_id))
    |> Enum.map(fn {root, members} ->
      lead = by_id[root]

      %{
        play: lead,
        translations:
          members
          |> Enum.reject(&(&1.id == root))
          |> Enum.sort_by(&Search.normalise(&1.title_sort || &1.title)),
        sort_author: Search.normalise(lead.author_sort || lead.author_name),
        sort_title: Search.normalise(lead.title_sort || lead.title),
        date: lead.composition_date_from
      }
    end)
    |> Enum.sort_by(&{&1.sort_author, &1.sort_title})
  end

  # Follows parent_play_id to the root; on a cycle (hand-edited data) the play stands
  # alone as its own root.
  defp root_id(play, by_id), do: root_id(play, by_id, MapSet.new([play.id]), play.id)

  defp root_id(play, by_id, seen, start) do
    case by_id[play.parent_play_id] do
      nil ->
        play.id

      parent ->
        if parent.id in seen,
          do: start,
          else: root_id(parent, by_id, MapSet.put(seen, parent.id), start)
    end
  end

  defp facets(plays) do
    [
      {"lang", "Language",
       plays
       |> Enum.frequencies_by(& &1.language)
       |> Enum.sort_by(&(-elem(&1, 1)))
       |> Enum.map(fn {code, n} -> {code, Play.language_name(code), n} end)},
      {"form", "Form",
       options(plays, &Play.form/1, %{
         "verse" => "Verse",
         "prose" => "Prose",
         "mixed" => "Verse and prose"
       })},
      {"kind", "Kind",
       options(plays, &Components.kind/1, %{
         "original" => "Originals",
         "translation" => "Translations"
       })},
      {"coll", "Collection",
       options(plays, &Components.collection/1, %{"EMOTHE" => "EMOTHE", "ARTELOPE" => "ARTELOPE"})}
    ]
  end

  defp options(plays, value_of, labels) do
    plays
    |> Enum.frequencies_by(value_of)
    |> Enum.sort_by(&(-elem(&1, 1)))
    |> Enum.map(fn {value, n} -> {value, labels[value], n} end)
  end

  defp dir_size(path) do
    path
    |> File.ls!()
    |> Enum.reduce(0, fn entry, acc ->
      full = Path.join(path, entry)

      case File.stat(full) do
        {:ok, %{type: :regular, size: size}} -> acc + size
        {:ok, %{type: :directory}} -> acc + dir_size(full)
        _ -> acc
      end
    end)
  end
end
