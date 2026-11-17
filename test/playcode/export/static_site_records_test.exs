defmodule Playcode.Export.StaticSiteRecordsTest do
  @moduledoc """
  The record index, `search/records.js`: one entry per published play with the record
  fields the catalogue's search filters on (spec 2026-11-17, section 7.4). Read back as
  the visitor's browser gets it, through `records!/1`.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.{PlayContent, Witnesses}
  alias Playcode.Export.StaticSite.Records

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

  defp witness!(play, attrs) do
    {:ok, witness} =
      Witnesses.create_witness(Map.merge(%{"play_id" => play.id, "title" => "Comedia"}, attrs))

    witness
  end

  test "a witness is its support, city, years and format" do
    play = complete(%{})

    witness!(play, %{
      "witness_type" => "loose",
      "pub_place" => "London",
      "date" => "1733-1737",
      "format" => "4º"
    })

    witness!(play, %{"witness_type" => "manuscript", "date" => "s.a."})

    witness!(play, %{"witness_type" => "early_edition", "pub_place" => "Madrid", "date" => "1612"})

    assert entry(generate!([play]), play)["w"] == [
             ["loose", "London", 1733, 1737, "4º"],
             ["manuscript", nil, nil, nil, nil],
             ["early_edition", "Madrid", 1612, 1612, nil]
           ]
  end

  test "a performance is its place and the places around it, its venue, years, company and actors" do
    play = complete(%{})

    england =
      place_fixture(%{
        "names" => [
          %{"name" => "England", "language" => "en"},
          %{"name" => "Inglaterra", "language" => "es"}
        ]
      })

    london =
      place_fixture(%{
        "parent_place_id" => england.id,
        "names" => [%{"name" => "London", "language" => "en"}]
      })

    performance_fixture(play, %{
      "place_id" => london.id,
      "venue" => "The Globe",
      "venue_type" => "public_theatre",
      "date_text" => "1601",
      "company_name" => "The King’s Men",
      "cast" => [%{"forename" => "Richard", "surname" => "Burbage", "role" => "Hamlet"}]
    })

    performance_fixture(play, %{"date_text" => nil, "note" => "Sin datos"})

    assert entry(generate!([play]), play)["r"] == [
             [
               ["London", "England", "Inglaterra"],
               "The Globe",
               "public_theatre",
               1601,
               1601,
               "The King’s Men",
               ["Richard Burbage"]
             ],
             [[], nil, nil, nil, nil, nil, []]
           ]
  end

  test "a place of action is listed with the places containing it" do
    play = complete(%{})
    spain = place_fixture(%{"names" => [%{"name" => "España", "language" => "es"}]})

    andalusia =
      place_fixture(%{
        "parent_place_id" => spain.id,
        "names" => [%{"name" => "Andalucía", "language" => "es"}]
      })

    seville =
      place_fixture(%{
        "parent_place_id" => andalusia.id,
        "names" => [
          %{"name" => "Sevilla", "language" => "es"},
          %{"name" => "Seville", "language" => "en"}
        ]
      })

    play_place_fixture(play, seville)
    assert entry(generate!([play]), play)["p"] == [["Sevilla", "Seville", "Andalucía", "España"]]
  end

  test "its characters are named plain, the hidden ones left out" do
    play = complete(%{})

    for {id, name, hidden} <- [
          {"juan", "DON <<JUAN>>", false},
          {"catalinon", "CATALINÓN", false},
          {"todos", "TODOS", true}
        ] do
      {:ok, _} =
        PlayContent.create_character(%{
          "play_id" => play.id,
          "xml_id" => id,
          "name" => name,
          "is_hidden" => hidden
        })
    end

    assert entry(generate!([play]), play)["n"] == ["DON JUAN", "CATALINÓN"]
  end

  # The one test that reaches the module: a query count is not visible in the file.
  test "the queries do not grow with the plays" do
    count = fn plays ->
      dir = site_dir!()
      counted(fn -> Records.write(dir, plays, Map.new(plays, &{&1.id, &1})) end)
    end

    two = for _ <- 1..2, do: complete(%{})
    six = two ++ for _ <- 1..4, do: complete(%{})
    assert count.(two) == count.(six)
  end

  defp counted(fun) do
    ref = make_ref()
    me = self()
    handler = "records-query-count-#{inspect(ref)}"

    :telemetry.attach(
      handler,
      [:playcode, :repo, :query],
      fn _, _, _, _ -> send(me, ref) end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end

    count_messages(ref, 0)
  end

  defp count_messages(ref, n) do
    receive do
      ^ref -> count_messages(ref, n + 1)
    after
      0 -> n
    end
  end
end
