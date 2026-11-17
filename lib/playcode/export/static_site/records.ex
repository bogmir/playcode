defmodule Playcode.Export.StaticSite.Records do
  @moduledoc """
  The record index, `search/records.js`: one entry per published play holding the record
  fields the catalogue's search filters on, under one-letter keys (spec 2026-11-17,
  section 7.4). Values are as displayed; the browser normalises them when the file loads.

  Written whole from the database by `StaticSite.write_catalogue/3` on every build.
  """

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.Components
  alias Playcode.PlayContent.InlineMarkup

  @doc """
  Writes `dir/search/records.js` with an entry per play of `plays`, in their order.
  `roots` maps each play's id to the published play at the root of its family. Returns
  the bytes written.
  """
  def write(dir, plays, roots) do
    path = Path.join([dir, "search", "records.js"])
    File.mkdir_p!(Path.dirname(path))

    entries = Enum.map(plays, &entry(&1, roots))
    js = ["EMOTHE.records.load(", Jason.encode!(entries, escape: :javascript_safe), ");\n"]

    File.write!(path, js)
    IO.iodata_length(js)
  end

  defp entry(play, roots) do
    [
      c: play.code,
      t: titles(play),
      a: play.author_name,
      l: play.language,
      o: roots[play.id].language,
      k: Components.kind(play),
      s: Components.collection(play),
      f: Play.form(play),
      x: if(Play.has_text?(play), do: 1),
      d: dating(play),
      h: play.historical_time
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp titles(play) do
    [play.title, play.original_title]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&InlineMarkup.plain/1)
    |> Enum.uniq()
  end

  defp dating(%{composition_date_from: nil}), do: nil
  defp dating(%{composition_date_from: from, composition_date_to: to}), do: [from, to || from]
end
