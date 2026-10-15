defmodule Playcode.Import.TeiReimportTest do
  @moduledoc """
  Importing a file whose code already exists updates that play in place: the
  file owns the text, the platform owns what was curated or typed by hand.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Catalogue
  alias Playcode.Import.TeiImport

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
    {:ok, play} = TeiImport.import_file(path)
    {:ok, _} = Catalogue.delete_play(play)

    assert {:ok, reimported} = TeiImport.import_file(path)
    assert reimported.id == play.id
    refute Catalogue.get_play!(play.id).deleted_at
  end

  test "re-importing the same file changes nothing a reader can see", %{path: path} do
    {:ok, play} = TeiImport.import_file(path)
    before = export_tei(play)

    {:ok, _} = TeiImport.import_file(path)

    assert export_tei(play) == before
  end

  # The platform-owned columns in lib/playcode/import/tei_import.ex (@platform_owned).
  test "curated columns survive a re-import", %{path: path} do
    {:ok, play} = TeiImport.import_file(path)

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
    {:ok, _} = TeiImport.import_file(path)

    assert Map.take(Catalogue.get_play!(play.id), Map.keys(curated)) == curated
  end

  test "hand-entered sources, editors and notes survive; the file's own are replaced",
       %{path: path} do
    {:ok, play} = TeiImport.import_file(path)

    {:ok, _} = Catalogue.create_play_source(%{play_id: play.id, title: "Typed by hand"})

    {:ok, _} =
      Catalogue.create_play_editor(%{
        play_id: play.id,
        person_name: "A Researcher",
        role: "researcher"
      })

    {:ok, _} =
      Catalogue.create_paratext(%{
        play_id: play.id,
        kind: "nota_edicion_digital",
        content: "Typed"
      })

    {:ok, _} = TeiImport.import_file(path)
    play = Catalogue.get_play_with_all!(play.id)

    assert Enum.map(play.sources, & &1.title) |> Enum.sort() == ["Primera parte", "Typed by hand"]

    assert Enum.map(play.editors, & &1.person_name) |> Enum.sort() == [
             "A Researcher",
             "Teresa Ferrer"
           ]

    assert Enum.map(play.paratexts, &{&1.kind, &1.content}) |> Enum.sort() ==
             [{"dedicatoria", "Al lector."}, {"nota_edicion_digital", "Typed"}]
  end

  # Review focus 1: only the file's own paratexts are replaced; one typed by hand keeps
  # its place before the text.
  test "a re-import adds the file's paratexts after the text and keeps a hand-entered one" do
    path = write_tmp!(tei(code: "TBACK1", back: ~s(<div type="colofon"><p>Loado sea.</p></div>)))
    {:ok, play} = TeiImport.import_file(path)

    {:ok, _} =
      Catalogue.create_paratext(%{play_id: play.id, kind: "dedicatoria", content: "A mano."})

    {:ok, _} = TeiImport.import_file(path)

    paratexts = Catalogue.list_paratexts(play.id)
    assert [%{content: "A mano.", back: false}] = Enum.filter(paratexts, &(&1.origin == "manual"))
    assert [%{kind: "colofon", back: true}] = Enum.filter(paratexts, &(&1.origin == "tei"))
  end

  # Review focus 1: a hand-entered paratext keeps its place and its side of the text. A
  # re-import gives the file's paratexts the file's positions, which can equal one an
  # editor dragged; the older row then goes first, whatever Postgres reads first (here the
  # hand-entered one, edited after the re-import, lies last on disk).
  test "a hand-entered paratext keeps its dragged place and its side through a re-import" do
    path =
      write_tmp!(
        tei(
          code: "TBACK2",
          front:
            ~s(<div type="dedicatoria"><p>Ded.</p></div><div type="argumento"><p>Arg.</p></div>)
        )
      )

    {:ok, play} = TeiImport.import_file(path)

    {:ok, typed} =
      Catalogue.create_paratext(%{play_id: play.id, kind: "prologo", content: "A mano."})

    {:ok, _} =
      Catalogue.create_paratext(%{play_id: play.id, kind: "colofon", content: "Fin.", back: true})

    ids = play.id |> Catalogue.list_paratexts() |> Enum.map(& &1.id)
    Catalogue.reorder_paratexts(play.id, [typed.id | List.delete(ids, typed.id)])
    Playcode.TestFixtures.age_rows!(play)

    {:ok, _} = TeiImport.import_file(path)

    {:ok, _} =
      Catalogue.update_paratext(Catalogue.get_paratext(play.id, typed.id), %{
        content: "A mano, corregido."
      })

    # The two sides are printed apart, so only the order within each is the play's.
    {back, front} = play.id |> Catalogue.list_paratexts() |> Enum.split_with(& &1.back)
    assert Enum.map(front, & &1.content) == ["A mano, corregido.", "Ded.", "Arg."]
    assert Enum.map(back, & &1.content) == ["Fin."]
  end
end
