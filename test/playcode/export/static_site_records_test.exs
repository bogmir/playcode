defmodule Playcode.Export.StaticSiteRecordsTest do
  @moduledoc """
  The record index, `search/records.js`: one entry per published play with the record
  fields the catalogue's search filters on (spec 2026-11-17, section 7.4). Read back as
  the visitor's browser gets it, through `records!/1`.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.PlayContent
  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.Records

  defp entry(dir, play), do: Enum.find(records!(dir), &(&1["c"] == play.code))

  test "a play's entry holds its own fields, under their keys" do
    play =
      complete_play(%{
        "title" => "La <<Celestina>>",
        "original_title" => "Tragicomedia de Calisto y Melibea",
        "author_name" => "Fernando de <<Rojas>>",
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
    play = complete_play(%{"title" => "Hamlet", "original_title" => "Hamlet"})
    assert entry(generate!([play]), play)["t"] == ["Hamlet"]
  end

  test "a translation's original language is its published root's" do
    original = complete_play(%{"language" => "en"})

    translation =
      complete_play(%{
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
      complete_play(%{
        "language" => "fr",
        "parent_play_id" => original.id,
        "relationship_type" => "traduccion"
      })

    assert entry(generate!([translation]), translation)["o"] == "fr"
  end

  test "the entries are in the catalogue's order, and a draft has none" do
    [b, a] = [
      complete_play(%{"title" => "B", "title_sort" => "b"}),
      complete_play(%{"title" => "A", "title_sort" => "a"})
    ]

    draft = play_fixture()
    codes = generate!([a, b, draft]) |> records!() |> Enum.map(& &1["c"])
    assert codes == [a.code, b.code]
  end

  test "a bare play's entry is under 200 bytes" do
    play = complete_play(%{"title" => "Hamlet", "author_name" => "William Shakespeare"})
    assert generate!([play]) |> entry(play) |> Jason.encode!() |> byte_size() < 200
  end

  test "Generate reports the index's size" do
    play = complete_play(%{})
    dir = site_dir!()

    assert {:ok, %{records_bytes: bytes}} =
             StaticSite.generate(output_dir: dir, play_codes: [play.code])

    assert bytes == File.stat!(Path.join(dir, "search/records.js")).size
  end

  test "a witness is its support, city, years and format" do
    play = complete_play(%{})

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
    play = complete_play(%{})

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
    play = complete_play(%{})
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

  test "a name a place has in several languages is listed once" do
    play = complete_play(%{})

    madrid =
      place_fixture(%{
        "names" => [
          %{"name" => "Madrid", "language" => "es"},
          %{"name" => "Madrid", "language" => "en"}
        ]
      })

    play_place_fixture(play, madrid)
    assert entry(generate!([play]), play)["p"] == [["Madrid"]]
  end

  test "its characters are named plain, the hidden ones left out" do
    play = complete_play(%{})

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
      counted(fn -> Records.write(dir, Records.entries(plays, Map.new(plays, &{&1.id, &1}))) end)
    end

    two = for _ <- 1..2, do: complete_play(%{})
    six = two ++ for _ <- 1..4, do: complete_play(%{})
    queries = count.(two)
    assert queries > 0
    assert count.(six) == queries
  end

  defp counted(fun) do
    ref = make_ref()
    me = self()
    handler = "records-query-count-#{inspect(ref)}"

    # Handlers are global: count this test's own queries only.
    :telemetry.attach(
      handler,
      [:playcode, :repo, :query],
      fn _, _, _, _ -> if self() == me, do: send(me, ref) end,
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
