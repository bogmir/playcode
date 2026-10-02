defmodule Playcode.Export.StaticSite do
  @moduledoc """
  Generates the published EMOTHE archive: HTML, CSS and JS that work from any web host
  and from the unzipped archive opened as `file://`, following the Endings Project
  principles. Design: `docs/superpowers/specs/2026-10-02-static-site-redesign-design.md`.

  Only plays marked complete are published unless `all: true`. The archive is in
  English whatever locale the admin generating it uses.
  """

  alias Playcode.Catalogue
  alias Playcode.Export.TeiXml
  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.{Components, Edition, Pages, Search}

  @type progress_info :: %{
          step: :assets | :catalogue | :play,
          current: non_neg_integer(),
          total: non_neg_integer(),
          detail: String.t()
        }

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
          |> Enum.with_index(1)
          |> Enum.map(fn {play, n} ->
            opts[:on_progress].(%{step: :play, current: n, total: total, detail: play.code})
            edition = Edition.load(play.id)

            Map.put(
              write_play(edition, dir, site),
              :postings,
              Search.write_play(dir, edition, n - 1)
            )
          end)

        opts[:on_progress].(%{
          step: :catalogue,
          current: 0,
          total: total,
          detail: "Generating catalogue..."
        })

        report = write_index_pages(plays, results, dir, opts)

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

  @doc "Exports one play into an existing site, then rebuilds the catalogue and index."
  def generate_single_play(play_id, opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      File.mkdir_p!(Path.join(dir, "plays"))

      edition = Edition.load(play_id)
      published = MapSet.new([edition.play.code | list_exported_codes(dir)])
      write_play(edition, dir, site(opts, published))
      rebuild_index(opts)
      :ok
    end)
  end

  @doc "Removes one play from an existing site, then rebuilds the catalogue and index."
  def remove_single_play(code, opts \\ []) do
    dir = Keyword.get(opts, :output_dir, "_site")

    if code in list_exported_codes(dir) do
      safe_code!(code)
      File.rm_rf!(Path.join([dir, "plays", code]))
      File.rm(Path.join([dir, "plays", "#{code}.html"]))
    end

    rebuild_index(opts)
    :ok
  end

  @doc "Rebuilds the catalogue, about, search pages and search index from the plays on disk."
  def rebuild_index(opts \\ []) do
    in_english(fn ->
      opts = defaults(opts)
      dir = opts[:output_dir]
      codes = list_exported_codes(dir)
      plays = Catalogue.list_plays(sort: :title_sort) |> Enum.filter(&(&1.code in codes))

      File.rm_rf!(Path.join(dir, "search"))
      File.mkdir_p!(dir)
      write_assets(dir)

      results =
        plays
        |> Enum.with_index()
        |> Enum.map(fn {play, i} ->
          %{postings: Search.write_play(dir, Edition.load(play.id), i)}
        end)

      write_index_pages(plays, results, dir, opts)
    end)
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

  defp write_index_pages(plays, results, dir, opts) do
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
    Search.write_index(dir, plays, Enum.map(results, & &1.postings))
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
       options(plays, &if(&1.is_verse, do: "verse", else: "prose"), %{
         "verse" => "Verse",
         "prose" => "Prose"
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
