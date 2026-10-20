defmodule Playcode.Import.TeiPreviewTest do
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers, only: [write_tmp!: 1, tei: 1]

  alias Playcode.Catalogue
  alias Playcode.Import.TeiImport

  @tei """
  <?xml version="1.0" encoding="UTF-8"?>
  <TEI>
    <teiHeader>
      <fileDesc>
        <titleStmt>
          <title key="archivo">EMOTHE9401_PreviewPlay</title>
          <title>Preview Play</title>
        </titleStmt>
        <publicationStmt><idno>EMOTHE9401</idno></publicationStmt>
        <sourceDesc>
          <bibl><title>Primera parte</title><author>Lope de Vega</author></bibl>
        </sourceDesc>
      </fileDesc>
    </teiHeader>
    <text>
      <front>
        <div type="elenco">
          <castList><castItem><role xml:id="REY">EL REY</role></castItem></castList>
        </div>
      </front>
      <body>
        <div1 type="acto" n="1">
          <head>Acto primero</head>
          <sp who="#REY"><speaker>EL REY</speaker><l>Conde, entregad la espada.</l></sp>
        </div1>
      </body>
    </text>
  </TEI>
  """

  setup do
    path = Path.join(System.tmp_dir!(), "preview-#{System.unique_integer([:positive])}.xml")
    File.write!(path, @tei)
    on_exit(fn -> File.rm(path) end)
    %{path: path}
  end

  test "an unknown code previews as a new play", %{path: path} do
    assert {:ok, preview} = TeiImport.preview_import(path)

    assert preview.code == "EMOTHE9401_PreviewPlay"
    assert preview.title == "Preview Play"
    assert preview.existing == nil
    refute preview.archived

    # Witnesses (S3) and performances (S5) are tables of mixed ownership too, so the preview
    # counts them.
    assert preview.replaces == %{
             divisions: 0,
             elements: 0,
             characters: 0,
             editors: 0,
             sources: 0,
             paratexts: 0,
             places: 0,
             witnesses: 0,
             performances: 0
           }

    assert preview.preserves == %{
             editors: 0,
             sources: 0,
             paratexts: 0,
             places: 0,
             witnesses: 0,
             performances: 0
           }
  end

  test "an existing play reports what is replaced and what is kept", %{path: path} do
    {:ok, play} = TeiImport.import_file(path)
    {:ok, _} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})
    {:ok, _} = Catalogue.update_play(play, %{language: "en", form: "mixed"})

    assert {:ok, preview} = TeiImport.preview_import(path)

    assert preview.existing.id == play.id
    refute preview.archived
    assert preview.replaces.sources == 1
    assert preview.replaces.divisions > 0
    assert preview.replaces.characters == 1
    assert preview.preserves.sources == 1
    assert :language in preview.preserves_fields
    assert :form in preview.preserves_fields
  end

  # Kept by every re-import; reported only when a curator has turned it off.
  test "Show variant readings is reported as kept only when it is off", %{path: path} do
    {:ok, play} = TeiImport.import_file(path)

    assert {:ok, preview} = TeiImport.preview_import(path)
    refute :show_variants in preview.preserves_fields

    {:ok, _} = Catalogue.update_play(play, %{show_variants: false})

    assert {:ok, preview} = TeiImport.preview_import(path)
    assert :show_variants in preview.preserves_fields
  end

  # A re-import replaces the file's rows, and an editor's fixes to them with them; the
  # preview says how many. A fresh import edits nothing (review focus 7), and a row typed
  # by hand is kept, so its edits do not count.
  test "counts the file's rows edited since their import" do
    path =
      write_tmp!(
        tei(
          code: "TEDIT1",
          source_desc: "<bibl><title>Primera parte</title></bibl>",
          front: """
          <div type="licencia"><p>Privilège.</p></div>
          <div type="elenco"><castList><castItem><role xml:id="REY">EL REY</role></castItem></castList></div>
          """
        )
      )

    {:ok, play} = TeiImport.import_file(path)
    assert {:ok, %{edited: 0}} = TeiImport.preview_import(path)

    {:ok, typed} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})
    Playcode.TestFixtures.age_rows!(play)

    [paratext] = Catalogue.list_paratexts(play.id)
    {:ok, _} = Catalogue.update_paratext(paratext, %{kind: "noticia_representacion"})
    [character] = Playcode.PlayContent.list_characters(play.id)
    {:ok, _} = Playcode.PlayContent.update_character(character, %{"actor" => "Mr. Betterton"})
    {:ok, _} = Catalogue.update_play_source(typed, %{title: "Typed again"})

    assert {:ok, %{edited: 2}} = TeiImport.preview_import(path)
  end

  test "a hand-linked place counts as kept, a TEI one as replaced", %{path: path} do
    {:ok, play} = TeiImport.import_file(path)

    # Unique names, not "Roma" — place_fixture derives the slug from the name, and the
    # slug index is global, so two async tests inserting the same slug inside their
    # transactions deadlock on it.
    hand = Playcode.TestFixtures.place_fixture()
    from_tei = Playcode.TestFixtures.place_fixture()
    {:ok, _} = Playcode.Places.link_place(play.id, hand.id, %{"origin" => "manual"})
    {:ok, _} = Playcode.Places.link_place(play.id, from_tei.id, %{"origin" => "tei"})

    assert {:ok, preview} = TeiImport.preview_import(path)

    assert preview.replaces.places == 1
    assert preview.preserves.places == 1
  end

  # The file's performances (S5) are replaced by a re-import; those a curator typed or
  # FileMaker supplied are kept, and an edit to one of the file's counts as lost.
  describe "performances" do
    setup do
      path =
        write_tmp!(
          tei(
            code: "PRVP#{System.unique_integer([:positive])}",
            front:
              ~s(<performance xml:id="performance-1"><p><date when="1610">1610</date></p></performance>)
          )
        )

      {:ok, play} = TeiImport.import_file(path)
      %{path: path, play: play}
    end

    test "a performance from the file counts as replaced, one by hand or from FileMaker as kept",
         %{path: path, play: play} do
      Playcode.TestFixtures.performance_fixture(play, %{"date_text" => "1600"})

      Playcode.TestFixtures.performance_fixture(play, %{
        "date_text" => "1605",
        "origin" => "filemaker"
      })

      assert {:ok, preview} = TeiImport.preview_import(path)

      assert preview.replaces.performances == 1
      assert preview.preserves.performances == 2

      # The totals the import page and --dry-run print count them.
      assert TeiImport.mixed_ownership_total(preview.replaces) == 1
      assert TeiImport.mixed_ownership_total(preview.preserves) == 2
    end

    test "counts the file's performance edited since its import", %{path: path, play: play} do
      assert {:ok, %{edited: 0}} = TeiImport.preview_import(path)

      [performance] = Playcode.Performances.list_for_play(play.id)
      Playcode.TestFixtures.age_rows!(play)
      {:ok, _} = Playcode.Performances.update_performance(performance, %{"venue" => "Globe"})

      assert {:ok, %{edited: 1}} = TeiImport.preview_import(path)
    end
  end

  test "an archived play is flagged so the UI can say it will be restored", %{path: path} do
    {:ok, play} = TeiImport.import_file(path)
    {:ok, _} = Catalogue.delete_play(play)

    assert {:ok, preview} = TeiImport.preview_import(path)
    assert preview.archived
    assert preview.existing.id == play.id
  end

  # An import adds the file's references Playcode has no identical entry for. Listing them
  # is how a stale one (an older file's version of a corrected reference) is seen first.
  test "lists the references an import would add, as they print" do
    code = "PRV#{System.unique_integer([:positive])}"

    file = fn titles ->
      structs =
        Enum.map_join(titles, fn title ->
          ~s(<biblStruct type="libro"><monogr><author>Autor, Ana</author>) <>
            ~s(<title level="m">#{title}</title><imprint><date/></imprint></monogr></biblStruct>)
        end)

      write_tmp!(
        tei(
          code: code,
          back: ~s(<div type="bibliografia"><listBibl type="critica">#{structs}</listBibl></div>)
        )
      )
    end

    assert {:ok, %{bibliography_adds: [uno]}} = TeiImport.preview_import(file.(["Uno"]))
    assert uno =~ "Autor, Ana" and uno =~ "Uno"

    {:ok, _} = TeiImport.import_file(file.(["Uno"]))

    assert {:ok, %{bibliography_adds: [dos]}} =
             TeiImport.preview_import(file.(["Uno", "Dos", "Dos"]))

    assert dos =~ "Dos"
  end

  # A reference Playcode cannot store (here a language it does not list) is skipped by the
  # import; the preview says so rather than let it vanish.
  test "lists the references an import would skip" do
    xml =
      tei(
        back:
          ~s(<div type="bibliografia"><listBibl type="critica">) <>
            ~s(<biblStruct type="libro" xml:lang="la"><monogr><author>Autor, Ana</author>) <>
            ~s(<title level="m">Liber</title><imprint><date/></imprint></monogr></biblStruct>) <>
            ~s(</listBibl></div>)
      )

    assert {:ok, %{bibliography_adds: [], bibliography_skips: [skipped]}} =
             TeiImport.preview_import(write_tmp!(xml))

    assert skipped =~ "Liber"
  end

  test "preview writes nothing", %{path: path} do
    {:ok, _} = TeiImport.preview_import(path)

    assert Catalogue.list_plays(include_deleted: true) == []
  end

  test "a file the import would refuse, the preview refuses the same way" do
    assert {:error, :missing_tei_header} =
             TeiImport.preview_import(write_tmp!("<TEI><text><body/></text></TEI>"))

    assert {:error, {:xml_parse_error, _}} = TeiImport.preview_import(write_tmp!("<not valid>>>"))
  end
end
