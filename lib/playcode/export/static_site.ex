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
  alias Playcode.Export.StaticSite.{Edition, Pages, Renderer, Search}

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
            play.id |> Edition.load() |> write_play(dir, site)
          end)

        opts[:on_progress].(%{
          step: :catalogue,
          current: 0,
          total: total,
          detail: "Generating catalogue..."
        })

        write_index_pages(plays, results, dir, opts)

        {:ok, %{plays: total, size: dir_size(dir), output_dir: dir}}
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
    File.rm_rf!(Path.join([dir, "plays", code]))
    File.rm(Path.join([dir, "plays", "#{code}.html"]))
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

      File.mkdir_p!(dir)
      write_assets(dir)
      write_index_pages(plays, Enum.map(plays, fn _ -> %{} end), dir, opts)
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
    play_dir = Path.join([dir, "plays", play.code])
    File.rm_rf!(play_dir)
    File.mkdir_p!(play_dir)
    assigns = %{edition: edition, site: site}

    File.write!(Path.join(play_dir, "index.html"), Pages.render(:title, assigns))
    File.write!(Path.join(play_dir, "#{play.code}.xml"), TeiXml.generate(play))

    File.write!(
      Path.join([dir, "plays", "#{play.code}.html"]),
      Pages.render(:redirect, %{code: play.code, title: play.title})
    )

    %{}
  end

  # The catalogue is still the old renderer's until Task 6.
  defp write_index_pages(plays, _results, dir, opts) do
    File.write!(Path.join(dir, "index.html"), Renderer.catalogue_page(plays, opts))
    File.write!(Path.join(dir, "style.css"), Renderer.site_css())
    File.write!(Path.join(dir, "search.js"), Search.search_js())
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
