defmodule Playcode.Import.TeiPreviewTest do
  use Playcode.DataCase, async: true

  alias Playcode.Catalogue
  alias Playcode.Import.TeiParser

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
    assert {:ok, preview} = TeiParser.preview_import(path)

    assert preview.code == "EMOTHE9401_PreviewPlay"
    assert preview.title == "Preview Play"
    assert preview.existing == nil
    refute preview.archived

    assert preview.replaces == %{
             divisions: 0,
             elements: 0,
             characters: 0,
             editors: 0,
             sources: 0,
             notes: 0,
             places: 0
           }

    assert preview.preserves == %{editors: 0, sources: 0, notes: 0, places: 0}
  end

  test "an existing play reports what is replaced and what is kept", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)
    {:ok, _} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})
    {:ok, _} = Catalogue.update_play(play, %{language: "en", form: "mixed"})

    assert {:ok, preview} = TeiParser.preview_import(path)

    assert preview.existing.id == play.id
    refute preview.archived
    assert preview.replaces.sources == 1
    assert preview.replaces.divisions > 0
    assert preview.replaces.characters == 1
    assert preview.preserves.sources == 1
    assert :language in preview.preserves_fields
    assert :form in preview.preserves_fields
  end

  test "a hand-linked place counts as kept, a TEI one as replaced", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)

    # Unique names, not "Roma" — place_fixture derives the slug from the name, and the
    # slug index is global, so two async tests inserting the same slug inside their
    # transactions deadlock on it.
    hand = Playcode.TestFixtures.place_fixture()
    from_tei = Playcode.TestFixtures.place_fixture()
    {:ok, _} = Playcode.Places.link_place(play.id, hand.id, %{"origin" => "manual"})
    {:ok, _} = Playcode.Places.link_place(play.id, from_tei.id, %{"origin" => "tei"})

    assert {:ok, preview} = TeiParser.preview_import(path)

    assert preview.replaces.places == 1
    assert preview.preserves.places == 1
  end

  test "an archived play is flagged so the UI can say it will be restored", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)
    {:ok, _} = Catalogue.delete_play(play)

    assert {:ok, preview} = TeiParser.preview_import(path)
    assert preview.archived
    assert preview.existing.id == play.id
  end

  test "preview writes nothing", %{path: path} do
    {:ok, _} = TeiParser.preview_import(path)

    assert Catalogue.list_plays(include_deleted: true) == []
  end
end
