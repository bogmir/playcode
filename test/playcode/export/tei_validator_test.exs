defmodule Playcode.Export.TeiValidatorTest do
  use Playcode.DataCase, async: true

  # Each test shells out to xmllint with the TEI RelaxNG schema: ~15s apiece,
  # 60% of the whole suite's wall clock. Excluded by default, see test_helper.exs.
  @moduletag :slow

  alias Playcode.Export.TeiValidator
  alias Playcode.Import.TeiImport
  alias Playcode.Export.TeiXml
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
    # @fixture_file under a code of its own: each test importing the file as it is holds
    # the same unique play code in its own sandbox transaction, so they queue behind each
    # other, and this test holds it longest (it timed out the corpus sweep's import).
    test "a bibliography with every publication type exports as schema-valid TEI" do
      play =
        @fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0759_AutoDeLaBarcaDelInfierno</title>),
          ~s(<title key="archivo">BIB#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

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
      # is an <lb/>, and one may be a heading alone.
      for attrs <- [
            %{"kind" => "colofon", "content" => "Loado sea.\nEn Madrid", "back" => true},
            %{"kind" => "head_title", "heading" => "LA BARCA"}
          ] do
        {:ok, _} = Catalogue.create_paratext(Map.put(attrs, "play_id", play.id))
      end

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ ~s(<citedRange unit="volume">5</citedRange>)
      assert xml =~ ~r{<div type="colofon">.*<lb/>.*<div type="bibliografia">}s
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    test "an imported corpus play exports as schema-valid TEI" do
      {:ok, play} = TeiImport.import_file(@fixture_file)

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    # 54 lines of this play hold a <stage> (a delivery, an exit): TEI allows it inside <l>
    # and <p>, and the export writes it back there. Under a code of its own, for the same
    # reason as the bibliography test.
    test "a play with stage directions inside its lines exports as schema-valid TEI" do
      play =
        @staged_fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0746_LesOccasionsPerdues</title>),
          ~s(<title key="archivo">STG#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

      refute play.code =~ "0746"

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ ~r/<l\b[^>]*>[^<]*<stage/
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    # Every witness type, a siglum that is no XML name, a witness with no siglum and line
    # breaks (<lb/>s), and no sources: the sourceDesc then holds the listWit alone. Under a code of its own, for the
    # same reason as the bibliography test.
    test "witnesses of every type export as schema-valid TEI" do
      play =
        @fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0759_AutoDeLaBarcaDelInfierno</title>),
          ~s(<title key="archivo">WIT#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

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

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ "<listWit>"
      assert xml =~ "<lb/>"
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    # A play with no places: its settingDesc holds a <setting> with the <time> alone. Under
    # a code of its own, for the same reason as the bibliography test.
    test "a historical time exports as schema-valid TEI" do
      play =
        @fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0759_AutoDeLaBarcaDelInfierno</title>),
          ~s(<title key="archivo">HT#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

      {:ok, _} =
        Catalogue.update_play(play, %{
          "historical_time" => "siglo_xvi",
          "historical_time_note" => "reinado de Felipe II"
        })

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ ~s(<time type="siglo_xvi">)
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    # An actor of the original cast, after the role's description. Under a code of its own,
    # for the same reason as the bibliography test.
    test "an original cast exports as schema-valid TEI" do
      play =
        @fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0759_AutoDeLaBarcaDelInfierno</title>),
          ~s(<title key="archivo">ACT#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

      [character | _] = Playcode.PlayContent.list_characters(play.id)
      {:ok, _} = Playcode.PlayContent.update_character(character, %{"actor" => "Mr. Betterton"})

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ "<actor>Mr. Betterton</actor>"
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    # The scene of the action as TEI's <set>, last in the front. Under a code of its own,
    # for the same reason as the bibliography test.
    test "a scene of the action exports as schema-valid TEI" do
      play =
        @fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0759_AutoDeLaBarcaDelInfierno</title>),
          ~s(<title key="archivo">SET#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

      {:ok, _} =
        Catalogue.create_paratext(%{
          "play_id" => play.id,
          "kind" => "lugar_accion",
          "heading" => "SCENE:",
          "content" => "An English wood."
        })

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ "<set>"
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    # The original a translation translates, as a notesStmt between publicationStmt and
    # sourceDesc, after the notes on the edition. Under a code of its own, for the same
    # reason as the bibliography test.
    test "a translation names its original in schema-valid TEI, after the edition's notes" do
      play =
        @fixture_file
        |> File.read!()
        |> String.replace(
          ~s(<title key="archivo">EMOTHE0759_AutoDeLaBarcaDelInfierno</title>),
          ~s(<title key="archivo">TRA#{System.unique_integer([:positive])}</title>)
        )
        |> Playcode.ImportHelpers.import_tei!()

      n = System.unique_integer([:positive])
      original = Playcode.TestFixtures.play_fixture(%{"code" => "ORIG#{n}_Barca"})

      {:ok, _} =
        Catalogue.update_play(play, %{
          "parent_play_id" => original.id,
          "edition_notes" => ["Impresos\nMadrid, 1637."]
        })

      xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()

      assert xml =~ "<note>Impresos<lb/>Madrid, 1637.</note>"
      assert xml =~ ~s(<relatedItem target="ORIG#{n}" type="original"/>)
      assert TeiValidator.validate(xml) == {:ok, :valid}
    end

    test "returns errors for malformed XML" do
      invalid_xml =
        ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"><bad></TEI>)

      assert {:error, errors} = TeiValidator.validate(invalid_xml)
      assert is_list(errors)
      assert length(errors) > 0
    end
  end
end
