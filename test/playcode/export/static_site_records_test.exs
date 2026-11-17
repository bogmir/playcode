defmodule Playcode.Export.StaticSiteRecordsTest do
  @moduledoc """
  The record index, `search/records.js`: one entry per published play with the record
  fields the catalogue's search filters on (spec 2026-11-17, section 7.4). Read back as
  the visitor's browser gets it, through `records!/1`.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  defp complete(attrs), do: play_fixture(Map.put(attrs, "is_complete", true))
  defp entry(dir, play), do: Enum.find(records!(dir), &(&1["c"] == play.code))

  test "a play's entry holds its own fields, under their keys" do
    play =
      complete(%{
        "title" => "La <<Celestina>>",
        "original_title" => "Tragicomedia de Calisto y Melibea",
        "author_name" => "Fernando de Rojas",
        "language" => "es",
        "form" => "prose",
        "composition_date_from" => 1499,
        "composition_date_to" => 1502,
        "historical_time" => "siglo_xv"
      })

    assert entry(generate!([play]), play) == %{
             "c" => play.code,
             "t" => ["La Celestina", "Tragicomedia de Calisto y Melibea"],
             "a" => "Fernando de Rojas",
             "l" => "es",
             "o" => "es",
             "k" => "original",
             "s" => "EMOTHE",
             "f" => "prose",
             "x" => 1,
             "d" => [1499, 1502],
             "h" => "siglo_xv"
           }
  end

  test "what a play lacks is left out" do
    play =
      play_without_text_fixture(%{
        "is_complete" => true,
        "title" => "El Adonis",
        "author_name" => nil,
        "composition_date_from" => 1632,
        "composition_date_to" => 1632
      })

    assert entry(generate!([play]), play) == %{
             "c" => play.code,
             "t" => ["El Adonis"],
             "l" => "es",
             "o" => "es",
             "k" => "original",
             "s" => "EMOTHE",
             "d" => [1632, 1632]
           }
  end

  test "an original title the same as the title is not listed twice" do
    play = complete(%{"title" => "Hamlet", "original_title" => "Hamlet"})
    assert entry(generate!([play]), play)["t"] == ["Hamlet"]
  end

  test "a translation's original language is its published root's" do
    original = complete(%{"language" => "en"})

    translation =
      complete(%{
        "language" => "fr",
        "parent_play_id" => original.id,
        "relationship_type" => "traduccion"
      })

    dir = generate!([original, translation])
    assert entry(dir, translation)["o"] == "en"
    assert entry(dir, translation)["k"] == "translation"
  end

  test "with its original a draft, a translation is its own root" do
    original = play_fixture(%{"language" => "en"})

    translation =
      complete(%{
        "language" => "fr",
        "parent_play_id" => original.id,
        "relationship_type" => "traduccion"
      })

    assert entry(generate!([translation]), translation)["o"] == "fr"
  end

  test "the entries are in the catalogue's order, and a draft has none" do
    [b, a] = [
      complete(%{"title" => "B", "title_sort" => "b"}),
      complete(%{"title" => "A", "title_sort" => "a"})
    ]

    draft = play_fixture()
    codes = generate!([a, b, draft]) |> records!() |> Enum.map(& &1["c"])
    assert codes == [a.code, b.code]
  end

  test "a bare play's entry is under 200 bytes" do
    play = complete(%{"title" => "Hamlet", "author_name" => "William Shakespeare"})
    assert generate!([play]) |> entry(play) |> Jason.encode!() |> byte_size() < 200
  end
end
