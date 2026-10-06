defmodule Playcode.Export.TeiXmlTest do
  @moduledoc """
  Exports of data no TEI import produces: places curated in the gazetteer, and
  a dating note with no years. Everything a TEI file can carry is asserted as a
  round trip in test/playcode/tei_roundtrip_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  describe "places" do
    # Every slug here carries a "tx-" prefix. `places.slug` is globally unique and these
    # tests run async alongside others that use the same toponyms, so two transactions
    # inserting the same chain in different orders deadlock on the index. The prefix is
    # a per-file namespace; it is uniform, so the alphabetical-sibling assertion below
    # still means what it says.
    setup do
      play = play_fixture()

      europe = place_fixture(%{"name" => "Europa", "type" => "continent", "slug" => "tx-europa"})

      italy =
        place_fixture(%{
          "names" => [
            %{"name" => "Italia", "language" => "es", "is_preferred" => "true"},
            %{"name" => "Italy", "language" => "en", "is_preferred" => "true"}
          ],
          "type" => "country",
          "slug" => "tx-italia",
          "parent_place_id" => europe.id
        })

      roma =
        place_fixture(%{
          "name" => "Roma",
          "type" => "city",
          "slug" => "tx-roma",
          "parent_place_id" => italy.id,
          "latitude" => "41.9028",
          "longitude" => "12.4964",
          "authority" => "wikidata",
          "authority_id" => "Q220"
        })

      miseno =
        place_fixture(%{
          "name" => "Miseno",
          "type" => "town",
          "slug" => "tx-miseno",
          "parent_place_id" => italy.id
        })

      play_place_fixture(play, roma, %{"role" => "setting"})
      play_place_fixture(play, miseno, %{"role" => "mentioned", "note" => "Named, not staged."})

      %{xml: export_tei(play)}
    end

    test "listPlace nests each place under its container, siblings alphabetical by slug, " <>
           "each ancestor once",
         %{xml: xml} do
      ids = xml |> xml_elements("place") |> Enum.map(fn {attrs, _} -> attrs["xml:id"] end)

      # Document order of nested elements is a depth-first walk: europa contains italia,
      # which contains miseno then roma.
      assert ids == ["tx-europa", "tx-italia", "tx-miseno", "tx-roma"]

      assert [{%{"type" => "continent"}, _} | _] = xml_elements(xml, "place")
    end

    test "a place carries its names, coordinates and authority id", %{xml: xml} do
      assert {%{"xml:lang" => "es"}, "Italia"} in xml_elements(xml, "placeName", within: "place")
      assert {%{"xml:lang" => "en"}, "Italy"} in xml_elements(xml, "placeName", within: "place")
      assert xml_texts(xml, "geo") == ["41.9028 12.4964"]
      assert xml_elements(xml, "idno", within: "place") == [{%{"type" => "wikidata"}, "Q220"}]
    end

    test "the play's own links live in setting, with role and note", %{xml: xml} do
      assert xml_elements(xml, "placeName", within: "setting") == [
               {%{"ref" => "#tx-roma", "ana" => "setting"}, ""},
               {%{"ref" => "#tx-miseno", "ana" => "mentioned"}, "Named, not staged."}
             ]
    end

    test "a place's own note is marked type=\"place\", unambiguous against a link note" do
      play = play_fixture()

      noted =
        place_fixture(%{
          "name" => "Bosque",
          "type" => "forest",
          "slug" => "tx-bosque",
          "note" => "Ubicación aproximada."
        })

      play_place_fixture(play, noted)

      assert {%{"type" => "place"}, "Ubicación aproximada."} in xml_elements(
               export_tei(play),
               "note"
             )
    end

    test "a play with no places emits no settingDesc" do
      assert xml_elements(export_tei(play_fixture()), "settingDesc") == []
    end

    test "a fictional place is marked with a subtype and has no location" do
      play = play_fixture()

      atlantis =
        place_fixture(%{
          "name" => "Atlántida",
          "type" => "island",
          "slug" => "tx-atlantida",
          "is_fictional" => "true"
        })

      play_place_fixture(play, atlantis)
      xml = export_tei(play)

      assert [{%{"xml:id" => "tx-atlantida", "type" => "island", "subtype" => "fictional"}, _}] =
               xml_elements(xml, "place")

      assert xml_elements(xml, "geo") == []
    end

    test "a half-populated authority pair emits no idno" do
      play = play_fixture()

      for attrs <- [
            %{"name" => "Solo autoridad", "slug" => "solo-autoridad", "authority" => "wikidata"},
            %{"name" => "Solo id", "slug" => "solo-id", "authority_id" => "Q1"}
          ] do
        play_place_fixture(play, place_fixture(Map.put(attrs, "type", "city")))
      end

      assert xml_elements(export_tei(play), "idno", within: "settingDesc") == []
    end
  end

  test "a dating note with no years does not produce a creation element" do
    play = play_fixture(%{"composition_date_note" => "sin fecha"})

    assert xml_elements(export_tei(play), "creation") == []
  end

  test "a place's names are exported in their order" do
    place =
      place_fixture(%{
        "names" => [
          %{"name" => "Valentia", "language" => "la", "position" => 2},
          %{"name" => "Valencia", "language" => "es", "is_preferred" => "true", "position" => 1}
        ]
      })

    play = play_fixture()
    play_place_fixture(play, place)
    names = xml_texts(export_tei(play), "placeName")

    assert Enum.find_index(names, &(&1 == "Valencia")) <
             Enum.find_index(names, &(&1 == "Valentia"))
  end
end
