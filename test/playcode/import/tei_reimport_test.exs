defmodule Playcode.Import.TeiReimportTest do
  @moduledoc """
  Importing a file whose code already exists updates that play in place: the
  file owns the text, the platform owns what was curated or typed by hand.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Catalogue
  alias Playcode.Import.TeiParser

  @tei tei(
         code: "EMOTHE9301",
         title: "Reimport Play",
         title_stmt: "<principal>Teresa Ferrer</principal>",
         source_desc: "<bibl><title>Primera parte</title><author>Lope de Vega</author></bibl>",
         front: """
         <div type="dedicatoria"><head>Dedicatoria</head><p>Al lector.</p></div>
         <div type="elenco">
           <castList><castItem><role xml:id="REY">EL REY</role></castItem></castList>
         </div>
         """,
         body: """
         <div1 type="acto" n="1">
           <head>Acto primero</head>
           <sp who="#REY"><speaker>EL REY</speaker><l n="1">Conde, entregad la espada.</l></sp>
         </div1>
         """
       )

  setup do
    %{path: write_tmp!(@tei)}
  end

  test "re-importing updates the same play, and brings an archived one back", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)
    {:ok, _} = Catalogue.delete_play(play)

    assert {:ok, reimported} = TeiParser.import_file(path)
    assert reimported.id == play.id
    refute Catalogue.get_play!(play.id).deleted_at
  end

  test "re-importing the same file changes nothing a reader can see", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)
    before = export_tei(play)

    {:ok, _} = TeiParser.import_file(path)

    assert export_tei(play) == before
  end

  # The platform-owned columns in lib/playcode/import/tei_parser.ex (@platform_owned).
  test "curated columns survive a re-import", %{path: path} do
    {:ok, play} = TeiParser.import_file(path)

    curated = %{
      language: "en",
      form: "mixed",
      relationship_type: "traduccion",
      historical_time: "edad_media",
      historical_time_note: "Reinado de Juan I de Portugal (1385-1433)",
      composition_date_from: 1606,
      composition_date_to: 1607,
      composition_date_note: "typed by a curator"
    }

    {:ok, _} = Catalogue.update_play(play, curated)
    {:ok, _} = TeiParser.import_file(path)

    assert Map.take(Catalogue.get_play!(play.id), Map.keys(curated)) == curated
  end

  test "hand-entered sources, editors and notes survive; the file's own are replaced",
       %{path: path} do
    {:ok, play} = TeiParser.import_file(path)

    {:ok, _} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})

    {:ok, _} =
      Catalogue.create_play_editor(%{
        play_id: play.id,
        person_name: "A Researcher",
        role: "researcher"
      })

    {:ok, _} =
      Catalogue.create_play_editorial_note(%{
        play_id: play.id,
        section_type: "nota",
        content: "Typed"
      })

    {:ok, _} = TeiParser.import_file(path)
    play = Catalogue.get_play_with_all!(play.id)

    assert Enum.map(play.sources, & &1.title) |> Enum.sort() == ["Primera parte", "Typed by hand"]

    assert Enum.map(play.editors, & &1.person_name) |> Enum.sort() == [
             "A Researcher",
             "Teresa Ferrer"
           ]

    assert Enum.map(play.editorial_notes, &{&1.section_type, &1.content}) |> Enum.sort() ==
             [{"dedicatoria", "Al lector."}, {"nota", "Typed"}]
  end
end
