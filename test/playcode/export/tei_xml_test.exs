defmodule Playcode.Export.TeiXmlTest do
  @moduledoc """
  Exports of data no TEI import produces: places curated in the gazetteer, a
  dating note with no years, and the bibliography. Everything a TEI file can carry is asserted as a
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

  describe "bibliography" do
    setup do
      play = import_tei!(tei([]))

      bibliography_fixture(
        play,
        %{
          "kind" => "criticism",
          "pub_type" => "article",
          "language" => "en",
          "analytic_author" => "Barnett, Timothy Brian",
          "analytic_title" => "Lope and <<Tasso>>",
          "monogr_title" => "Bulletin of the Comediantes",
          "year_text" => "2005",
          "volume" => "57",
          "issue" => "2",
          "pages" => "238-294",
          "note" => "Revisar"
        },
        %{"note" => "doi en la nota"}
      )

      bibliography_fixture(
        play,
        %{
          "kind" => "modern_edition",
          "pub_type" => "book_section",
          "analytic_editors" => "Rowe, Nicholas",
          "analytic_title" => "Hamlet",
          "monogr_title" => "The Works",
          "year_text" => "1957-75",
          "volumes_total" => "6",
          "volume" => "1",
          "siglum" => "ROWE1",
          "public_note" => "Printed by Tonson",
          "url" => "https://example.org/rowe"
        },
        %{"volume" => "5", "pages" => "2366-2466"}
      )

      bibliography_fixture(play, %{
        "kind" => "adaptation",
        "pub_type" => nil,
        "monogr_author" => nil,
        "monogr_title" => "Solo un título",
        "url" => ". http://emothe.uv.es/x.php"
      })

      %{play: Playcode.Catalogue.get_play!(play.id), xml: export_tei(play)}
    end

    test "each kind is a listBibl in back, in display order", %{xml: xml} do
      assert [{%{"type" => "bibliografia"}, _text}] = xml_elements(xml, "div", within: "back")

      assert xml |> xml_elements("listBibl") |> Enum.map(&elem(&1, 0)) == [
               %{"type" => "ediciones_modernas"},
               %{"type" => "critica"},
               %{"type" => "adaptaciones"}
             ]
    end

    test "an article: analytic level, journal title, issue and a dated imprint", %{xml: xml} do
      assert [
               %{"type" => "seccion_libro"},
               %{"type" => "articulo_revista", "xml:lang" => "en"},
               %{}
             ] = xml |> xml_elements("biblStruct") |> Enum.map(&elem(&1, 0))

      assert {%{"level" => "a"}, "Lope and Tasso"} in xml_elements(xml, "title",
               within: "analytic"
             )

      assert "Tasso" in xml_texts(xml, "emph", within: "analytic")

      assert {%{"level" => "j"}, "Bulletin of the Comediantes"} in xml_elements(xml, "title",
               within: "monogr"
             )

      assert {%{"unit" => "issue"}, "2"} in xml_elements(xml, "biblScope")
      assert {%{"when" => "2005"}, "2005"} in xml_elements(xml, "date", within: "imprint")
    end

    test "a modern edition: the play's own volume and pages, siglum, volumes, note and URL", %{
      xml: xml
    } do
      scopes = xml_elements(xml, "biblScope")
      assert {%{"unit" => "volume"}, "5"} in scopes
      assert {%{"unit" => "page"}, "2366-2466"} in scopes
      refute {%{"unit" => "volume"}, "1"} in scopes

      assert {%{"type" => "siglum"}, "ROWE1"} in xml_elements(xml, "idno", within: "back")
      assert xml_texts(xml, "extent", within: "back") == ["6 vols."]
      assert {%{"target" => "https://example.org/rowe"}, ""} in xml_elements(xml, "ptr")
      assert xml_texts(xml, "note", within: "back") == ["Printed by Tonson"]

      # A range of years is no single date: the text stays, @when does not.
      assert {%{}, "1957-75"} in xml_elements(xml, "date", within: "imprint")
    end

    # Review focus 5.
    test "an imprint with nothing known is still schema-shaped, and a stray URL gives no ptr", %{
      xml: xml
    } do
      assert {%{}, ""} in xml_elements(xml, "date", within: "imprint")

      refute Enum.any?(xml_elements(xml, "ptr"), fn {attrs, _} ->
               attrs["target"] =~ "emothe.uv.es"
             end)
    end

    test "researchers' notes stay out of the file", %{xml: xml} do
      refute xml =~ "Revisar"
      refute xml =~ "doi en la nota"
    end

    # The fixpoint test in tei_roundtrip_test.exs re-imports under a new code, which makes
    # a new play. This one re-imports in place, as a curator would.
    test "re-importing the export in place keeps the bibliography and exports the same file", %{
      play: play,
      xml: xml
    } do
      reimported = import_tei!(xml)

      assert reimported.id == play.id
      assert export_tei(reimported) == xml
    end
  end
end
