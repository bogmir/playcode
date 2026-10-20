defmodule Playcode.Export.TeiValidatorTest do
  use Playcode.DataCase, async: true

  # Each xmllint compiles the TEI RelaxNG schema first, about 11 s of CPU, so the tests
  # here call it three times in all. Excluded by default, see test_helper.exs.
  @moduletag :slow

  # Building nine plays and validating them takes about 35 s alone, and the slow suite runs
  # it beside the corpus sweep, which keeps every core busy.
  @moduletag timeout: 180_000

  import Playcode.ImportHelpers, only: [export_tei: 1, import_tei!: 1, outline_xml: 0]

  alias Playcode.Export.TeiValidator
  alias Playcode.Catalogue

  @fixture_file Path.expand(
                  "../../fixtures/EMOTHE0759_AutoDeLaBarcaDelInfierno.xml",
                  __DIR__
                )

  @staged_fixture_file Path.expand(
                         "../../fixtures/EMOTHE0746_LesOccasionsPerdues.xml",
                         __DIR__
                       )

  describe "validate/1" do
    # Every shape below is built in this one test, so that one xmllint compiles the schema
    # (11 s of CPU) once for all of them; each shape's own checks stay in its builder.
    test "every shape of play exports as schema-valid TEI" do
      shapes = [
        {"a bibliography with every publication type", &bibliography/0},
        {"an imported corpus play", &corpus_play/0},
        {"stage directions inside the lines", &inline_stages/0},
        {"line breaks and prose line numbers", &line_breaks/0},
        {"witnesses of every type", &witnesses/0},
        {"a historical time", &historical_time/0},
        {"places with a historical state", &historical_state/0},
        {"an original cast", &original_cast/0},
        {"a scene of the action", &scene_of_the_action/0},
        {"a translation naming its original, after the edition's notes", &translation/0},
        {"performances", &performances/0},
        {"cast lists and paratexts before, inside, between and after the acts", &outline/0}
      ]

      xmls = Enum.map(shapes, fn {_shape, build} -> build.() end)

      invalid =
        for {{shape, _build}, result} <- Enum.zip(shapes, TeiValidator.validate_all(xmls)),
            result != {:ok, :valid},
            do: {shape, result}

      assert invalid == []
    end

    test "returns errors for malformed XML" do
      invalid_xml =
        ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"><bad></TEI>)

      assert {:error, errors} = TeiValidator.validate(invalid_xml)
      assert is_list(errors)
      assert length(errors) > 0
    end
  end

  describe "validate_all/1" do
    # One xmllint compiles the schema (11 s) once for every document.
    test "gives each document its own result, its errors its own" do
      valid = """
      <?xml version="1.0"?>
      <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc>
        <titleStmt><title>T</title></titleStmt><publicationStmt><p>P</p></publicationStmt>
        <sourceDesc><p>S</p></sourceDesc>
      </fileDesc></teiHeader><text><body><p>Texto.</p></body></text></TEI>
      """

      malformed = ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"><bad></TEI>)
      invalid = String.replace(valid, "<p>Texto.</p>", "<sp>Texto.</sp><bogus/>")

      assert [
               {:ok, :valid},
               {:error, [_ | _] = malformed_errors},
               {:ok, :valid},
               {:error, [_ | _] = invalid_errors}
             ] =
               TeiValidator.validate_all([valid, malformed, valid, invalid])

      assert Enum.any?(malformed_errors, &(&1 =~ "bad"))
      refute Enum.any?(malformed_errors, &(&1 =~ "bogus"))
      assert Enum.any?(invalid_errors, &(&1 =~ "bogus"))
      refute Enum.any?(invalid_errors, &(&1 =~ "bad"))
      # A line naming the document names it "TEI-XML", never xmllint's temporary file.
      assert ["TEI-XML:" <> _ | _] = malformed_errors
      assert ["TEI-XML:" <> _ | _] = invalid_errors
      refute Enum.any?(malformed_errors ++ invalid_errors, &(&1 =~ ".xml"))
    end
  end

  # --- The shapes ---

  # @fixture_file under a code of its own, as every shape here: the corpus sweep imports the
  # file as it is, and a play's code is unique, so two transactions holding it queue
  # behind each other (this one timed out the sweep's import).
  defp bibliography do
    play = own_copy(@fixture_file, "BIB")

    refute play.code =~ "0759"

    for type <- Playcode.Bibliography.Entry.pub_types() do
      Playcode.TestFixtures.bibliography_fixture(play, %{
        "pub_type" => type,
        "language" => "es",
        "analytic_author" => "Autor, A",
        "analytic_title" => "Capítulo <<en cursiva>>",
        "monogr_title" => "Libro",
        "monogr_editors" => "Editor, E",
        "monogr_translators" => "Traductor, T",
        "pub_place" => "Madrid",
        "publisher" => "Cátedra",
        "year_text" => "1957-75",
        "volume" => "2",
        "issue" => "3",
        "pages" => "1-20",
        "volumes_total" => "4",
        "edition" => "2nd",
        "original_title" => "Original",
        "series" => "Serie",
        "url" => "https://example.org",
        "url_accessed_on" => "2020-01-01",
        "public_note" => "Nota impresa"
      })
    end

    Playcode.TestFixtures.bibliography_fixture(
      play,
      %{
        "kind" => "modern_edition",
        "pub_type" => "book_section",
        "analytic_editors" => "Rowe, Nicholas",
        "analytic_title" => "Hamlet",
        "siglum" => "ROWE1"
      },
      %{"volume" => "5", "pages" => "1-9"}
    )

    Playcode.TestFixtures.bibliography_fixture(play, %{
      "kind" => "adaptation",
      "pub_type" => nil,
      "monogr_title" => "Solo un título"
    })

    # A paratext after the text stands before the bibliography's div, a line break in it
    # is an <lb/>, and one may be a heading alone. After the text is a place in the
    # outline, past the last division.
    for attrs <- [
          %{"kind" => "colofon", "content" => "Loado sea.\nEn Madrid", "position" => 10_000},
          %{"kind" => "head_title", "heading" => "LA BARCA"}
        ] do
      {:ok, _} = Catalogue.create_paratext(Map.put(attrs, "play_id", play.id))
    end

    xml = export_tei(play)

    assert xml =~ ~s(<citedRange unit="volume">5</citedRange>)
    assert xml =~ ~r{<div type="colofon">.*<lb/>.*<div type="bibliografia">}s
    xml
  end

  # The file as the corpus has it, but for its code (see `bibliography/0`).
  defp corpus_play, do: @fixture_file |> own_copy("CORP") |> export_tei()

  # 54 lines of this play hold a <stage> (a delivery, an exit): TEI allows it inside <l>
  # and <p>, and the export writes it back there. Under a code of its own, for the same
  # reason as the bibliography test.
  defp inline_stages do
    play = own_copy(@staged_fixture_file, "STG")

    refute play.code =~ "0746"

    xml = export_tei(play)

    assert xml =~ ~r/<l\b[^>]*>[^<]*<stage/
    xml
  end

  # TEI allows <lb> in <p>, <note>, <emph> and <stage>, and an n on <p>. @fixture_file
  # with one more act, under a code of its own, for the same reason as the bibliography
  # test.
  defp line_breaks do
    act =
      ~s(<div1 type="acto" n="9"><sp><speaker>A</speaker><p n="7">Uno, <lb/>dos <lb n="8"/><emph>tres <lb/>cuatro</emph><note n="1" type="editor"><p>Glosa <lb/>larga.</p></note>.</p></sp></div1>)

    play = own_copy(@fixture_file, "LB", &String.replace(&1, "</body>", act <> "</body>"))

    xml = export_tei(play)

    assert xml =~ ~s(<p n="7">)
    assert xml =~ ~s(<lb n="8"/>)
    xml
  end

  # Every witness type, a siglum that is no XML name, a witness with no siglum and line
  # breaks (<lb/>s), and no sources: the sourceDesc then holds the listWit alone. Under a code of its own, for the
  # same reason as the bibliography test.
  defp witnesses do
    play = own_copy(@fixture_file, "WIT")

    for source <- play.sources, do: {:ok, _} = Catalogue.delete_play_source(source)

    for {type, i} <- Enum.with_index(Playcode.Witnesses.Witness.types()) do
      {:ok, _} =
        Playcode.Witnesses.create_witness(%{
          "play_id" => play.id,
          "siglum" => "S#{i}",
          "title" => "Título",
          "normalized_title" => "Título normalizado",
          "attribution" => "Autor, Ana",
          "pub_place" => "Madrid",
          "publisher" => "Imprenta",
          "date" => "1603",
          "format" => "4º",
          "witness_type" => type,
          "shelfmark" => "BN 16630",
          "note" => "Nota"
        })
    end

    {:ok, _} =
      Playcode.Witnesses.create_witness(%{
        "play_id" => play.id,
        "siglum" => "1623b",
        "title" => "Œuvres",
        "date" => "s. a."
      })

    {:ok, _} =
      Playcode.Witnesses.create_witness(%{
        "play_id" => play.id,
        "title" => "ORBECCHE TRAGEDIA\rDI M. GIOVANBATTISTA",
        "note" => "Sin sigla\r\rBIBL.: ADAMS 1967"
      })

    xml = export_tei(play)

    assert xml =~ "<listWit>"
    assert xml =~ "<lb/>"
    xml
  end

  # A play with no places: its settingDesc holds a <setting> with the <time> alone. Under
  # a code of its own, for the same reason as the bibliography test.
  defp historical_time do
    play = own_copy(@fixture_file, "HT")

    {:ok, _} =
      Catalogue.update_play(play, %{
        "historical_time" => "siglo_xvi",
        "historical_time_note" => "reinado de Felipe II"
      })

    xml = export_tei(play)

    assert xml =~ ~s(<time type="siglo_xvi">)
    xml
  end

  # Two links with a historical state: a country, inside the link's <placeName>, and a
  # region, a nested <placeName>, both beside the link's note. Under a code of its own, for
  # the same reason as the bibliography test.
  defp historical_state do
    play = own_copy(@fixture_file, "HS")

    republic =
      Playcode.TestFixtures.place_fixture(%{"name" => "República romana", "type" => "country"})

    peninsula =
      Playcode.TestFixtures.place_fixture(%{"name" => "Península itálica", "type" => "region"})

    roma = Playcode.TestFixtures.place_fixture(%{"name" => "Roma"})
    verona = Playcode.TestFixtures.place_fixture(%{"name" => "Verona"})

    for {place, state, note} <- [{roma, republic, "Acto I."}, {verona, peninsula, nil}] do
      {:ok, _} =
        Playcode.Places.link_place(play.id, place.id, %{
          "historical_state_id" => state.id,
          "note" => note
        })
    end

    xml = export_tei(play)

    assert xml =~ ~s(<country ref="##{republic.slug}"/>)
    assert xml =~ ~s(<placeName ref="##{peninsula.slug}"/>)
    xml
  end

  # An actor of the original cast, after the role's description. Under a code of its own,
  # for the same reason as the bibliography test.
  defp original_cast do
    play = own_copy(@fixture_file, "ACT")

    [character | _] = Playcode.PlayContent.list_characters(play.id)
    {:ok, _} = Playcode.PlayContent.update_character(character, %{"actor" => "Mr. Betterton"})

    xml = export_tei(play)

    assert xml =~ "<actor>Mr. Betterton</actor>"
    xml
  end

  # The scene of the action as TEI's <set>, last in the front. Under a code of its own,
  # for the same reason as the bibliography test.
  # Every place a cast list, a paratext and the scene of the action can stand: a bare
  # castList and a div2 in an act, a div1 between the acts, a cast list in <back>.
  defp outline do
    xml = outline_xml() |> import_tei!() |> export_tei()

    assert xml =~ ~r{<div1 type="elenco">}
    xml
  end

  defp scene_of_the_action do
    play = own_copy(@fixture_file, "SET")

    {:ok, _} =
      Catalogue.create_paratext(%{
        "play_id" => play.id,
        "kind" => "lugar_accion",
        "heading" => "SCENE:",
        "content" => "An English wood."
      })

    xml = export_tei(play)

    assert xml =~ "<set>"
    xml
  end

  # The original a translation translates, as a notesStmt between publicationStmt and
  # sourceDesc, after the notes on the edition. Under a code of its own, for the same
  # reason as the bibliography test.
  defp translation do
    play = own_copy(@fixture_file, "TRA")

    n = System.unique_integer([:positive])
    original = Playcode.TestFixtures.play_fixture(%{"code" => "ORIG#{n}_Barca"})

    {:ok, _} =
      Catalogue.update_play(play, %{
        "parent_play_id" => original.id,
        "edition_notes" => ["Impresos\nMadrid, 1637."]
      })

    xml = export_tei(play)

    assert xml =~ "<note>Impresos<lb/>Madrid, 1637.</note>"
    assert xml =~ ~s(<relatedItem target="ORIG#{n}" type="original"/>)
    xml
  end

  # A play's performances (S5) with every part, and one with a note alone (its <p> empty): a
  # place and its state in a listPlace no <setting> names, the switch that points at the cast
  # list's castList, a source with the performance's own volume and pages, actors with a
  # nickname and a sex. Under a code of its own, for the same reason as the bibliography test.
  defp performances do
    play = own_copy(@fixture_file, "PERF")

    place = Playcode.TestFixtures.place_fixture(%{"name" => "Londres"})

    state =
      Playcode.TestFixtures.place_fixture(%{"name" => "Reino de Inglaterra", "type" => "country"})

    {:ok, _} =
      Playcode.Performances.create_performance(%{
        "play_id" => play.id,
        "date_text" => "1609-11",
        "venue" => "Globe or <<Blackfriars>>",
        "venue_type" => "commercial_theatre",
        "company_name" => "The King’s Men #{System.unique_integer([:positive])}",
        "place_id" => place.id,
        "historical_state_id" => state.id,
        "note" => "Hissed,\nnow and then.",
        "source_volume" => "6",
        "source_pages" => "83",
        "cast_from_cast_list" => true,
        "source_entry" => %{
          "kind" => "catalogue",
          "monogr_title" => "British Drama 1533–1642: A Catalogue",
          "publisher" => "Oxford University Press"
        },
        "cast" => [
          %{"surname" => "Poquelin", "nickname" => "Molière", "sex" => "man", "role" => "Argan"},
          %{"nickname" => "Mlle du Parc", "sex" => "woman"},
          %{"surname" => "Hart", "forename" => "Charles"}
        ]
      })

    {:ok, _} =
      Playcode.Performances.create_performance(%{"play_id" => play.id, "note" => "Sin fecha."})

    xml = export_tei(play)

    assert xml =~ ~s(<performance corresp="#castlist" xml:id="performance-1">)
    xml
  end

  # `file` imported under a code of its own, `prefix` and a number (see `bibliography/0`),
  # after `edit` has changed its text.
  defp own_copy(file, prefix, edit \\ & &1) do
    archivo = Path.basename(file, ".xml")

    file
    |> File.read!()
    |> String.replace(
      ~s(<title key="archivo">#{archivo}</title>),
      ~s(<title key="archivo">#{prefix}#{System.unique_integer([:positive])}</title>)
    )
    |> edit.()
    |> import_tei!()
  end
end
