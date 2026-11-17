defmodule Playcode.Export.StaticSite.Records do
  @moduledoc """
  The record index, `search/records.js`: one entry per published play holding the record
  fields the catalogue's search filters on, under one-letter keys (spec 2026-11-17,
  section 7.4). Values are as displayed; the browser normalises them when the file loads.

  Written whole from the database by `StaticSite.write_catalogue/3` on every build.
  """

  alias Playcode.{Catalogue, Places}
  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.Components
  alias Playcode.Performances.Actor
  alias Playcode.PlayContent.InlineMarkup

  @doc """
  An entry per play of `plays`, in their order. `roots` maps each play's id to the
  published play at the root of its family.
  """
  def entries(plays, roots) do
    gazetteer = Places.gazetteer()
    plays |> Catalogue.preload_record() |> Enum.map(&entry(&1, roots, gazetteer))
  end

  @doc "Writes `entries` to `dir/search/records.js`; returns the bytes written."
  def write(dir, entries) do
    path = Path.join([dir, "search", "records.js"])
    File.mkdir_p!(Path.dirname(path))

    js = ["EMOTHE.records.load(", Jason.encode!(entries, escape: :javascript_safe), ");\n"]

    File.write!(path, js)
    IO.iodata_length(js)
  end

  defp entry(play, roots, gazetteer) do
    [
      c: play.code,
      t: titles(play),
      a: plain(play.author_name),
      l: play.language,
      o: roots[play.id].language,
      k: Components.kind(play),
      s: Components.collection(play),
      f: Play.form(play),
      x: if(Play.has_text?(play), do: 1),
      d: dating(play),
      h: play.historical_time,
      w: witnesses(play.witnesses),
      r: performances(play.performances, gazetteer),
      p: places(play.play_places, gazetteer),
      n: characters(play.characters)
    ]
    |> Enum.reject(fn {_key, value} -> value in [nil, []] end)
    |> Map.new()
  end

  defp witnesses(witnesses) do
    for w <- witnesses do
      {from, to} = years(w.date)
      [w.witness_type, plain(w.pub_place), from, to, plain(w.format)]
    end
  end

  # The first and last four-digit numbers: "1733-1737" is 1733 to 1737, "s.a." neither.
  defp years(nil), do: {nil, nil}

  defp years(date) do
    case Regex.scan(~r/\b\d{4}\b/, date) do
      [] -> {nil, nil}
      found -> {found |> hd() |> year(), found |> List.last() |> year()}
    end
  end

  defp year([digits]), do: String.to_integer(digits)

  defp performances(performances, gazetteer) do
    for p <- performances do
      [
        names_around(gazetteer[p.place_id], gazetteer),
        plain(p.venue),
        p.venue_type,
        p.year_from,
        p.year_to || p.year_from,
        p.company && plain(p.company.name),
        Enum.map(p.cast, &plain(Actor.display_name(&1.actor)))
      ]
    end
  end

  defp places(play_places, gazetteer),
    do: Enum.map(play_places, &names_around(gazetteer[&1.place_id], gazetteer))

  # Every name of the place, then of each place containing it, nearest first.
  defp names_around(nil, _gazetteer), do: []

  defp names_around(place, gazetteer) do
    [place | Enum.reverse(Places.ancestors(place, gazetteer))]
    |> Enum.flat_map(fn place -> Enum.map(place.names, & &1.name) end)
    |> Enum.uniq()
  end

  defp characters(characters),
    do: for(c <- characters, not c.is_hidden, do: InlineMarkup.plain(c.name))

  defp plain(nil), do: nil
  defp plain(text), do: InlineMarkup.plain(text)

  defp titles(play) do
    [play.title, play.original_title]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&InlineMarkup.plain/1)
    |> Enum.uniq()
  end

  defp dating(%{composition_date_from: nil}), do: nil
  defp dating(%{composition_date_from: from, composition_date_to: to}), do: [from, to || from]
end
