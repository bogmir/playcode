defmodule Playcode.StatisticsTest do
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.PlayContent
  alias Playcode.Statistics
  alias Playcode.TestFixtures

  test "get_statistics/1 computes and stores aggregate public metrics" do
    %{play: play, line_group: line_group, scene: scene} =
      TestFixtures.play_with_structure_fixture()

    {:ok, _aside_verse} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        type: "verse_line",
        content: "Aside line",
        line_number: 2,
        is_aside: true,
        part: "F",
        position: 4
      })

    stat = Statistics.get_statistics(play.id)

    assert stat.data["num_acts"] == 1
    assert get_in(stat.data, ["scenes", "total"]) == 1
    assert stat.data["total_verses"] == 2
    assert stat.data["split_verses"] == 2
    assert stat.data["total_prose_fragments"] == 1
    assert stat.data["total_stage_directions"] == 1
    assert stat.data["total_asides"] == 1
    assert stat.data["aside_verses"] == 1

    assert [%{"name" => "ALFA", "speeches" => 1}] = stat.data["character_appearances"]
  end

  test "a row cached by an older version is recomputed on read" do
    %{play: play} = TestFixtures.play_with_structure_fixture()
    stat = Statistics.get_statistics(play.id)

    # No public function writes a stale row, by design, so the test ages it directly.
    alias Playcode.Repo
    stale = stat.data |> Map.delete("version") |> Map.put("total_verses", 999)
    stat |> Ecto.Changeset.change(data: stale) |> Repo.update!()

    assert Statistics.get_statistics(play.id).data["total_verses"] == 1
  end

  describe "metrical passages" do
    test "fragments inherit the open passage's form, a new act closes it, same forms merge" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp><speaker>A</speaker>
                <lg type="redondilla"><l n="1">uno</l><l n="2">dos</l><l n="3">tres</l><l n="4">cuatro</l></lg>
                <lg type="redondilla" part="I"><l n="5">cinco</l><l n="6" part="I">seis</l></lg>
              </sp>
              <sp><speaker>B</speaker>
                <lg type="free" part="M"><l part="F">y medio</l><l n="7">siete</l></lg>
              </sp>
              <sp><speaker>A</speaker>
                <lg type="free" part="F"><l n="8">ocho</l></lg>
                <lg type="romance_tirada"><l n="9">nueve</l><l n="10">diez</l></lg>
              </sp>
            </div1>
            <div1 type="jornada" n="2"><head>Jornada II</head>
              <sp><speaker>B</speaker>
                <lg type="romance_tirada"><l n="11">once</l></lg>
                <lg type="nil"><l n="12">doce</l></lg>
              </sp>
            </div1>
            """
          )
        )

      assert Statistics.get_statistics(play.id).data["metrical_passages"] == [
               %{
                 "act" => 1,
                 "form" => "redondilla",
                 "family" => "spanish",
                 "from" => 1,
                 "to" => 8,
                 "verses" => 8
               },
               %{
                 "act" => 1,
                 "form" => "romance_tirada",
                 "family" => "romance",
                 "from" => 9,
                 "to" => 10,
                 "verses" => 2
               },
               %{
                 "act" => 2,
                 "form" => "romance_tirada",
                 "family" => "romance",
                 "from" => 11,
                 "to" => 11,
                 "verses" => 1
               },
               %{
                 "act" => 2,
                 "form" => "unmarked",
                 "family" => "other",
                 "from" => 12,
                 "to" => 12,
                 "verses" => 1
               }
             ]
    end

    test "a play whose verse carries no form has no synopsis" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acte" n="1"><head>Acte I</head>
              <sp><speaker>A</speaker><lg type="free"><l n="1">un</l></lg><lg><l n="2">deux</l></lg></sp>
            </div1>
            """
          )
        )

      assert Statistics.get_statistics(play.id).data["metrical_passages"] == []
    end
  end

  describe "characters" do
    test "speeches, lines, words, first words, asides, longest speech and forms" do
      play =
        import_tei!(
          tei(
            front: """
            <div type="elenco"><castList>
              <castItem><role xml:id="ANA">Ana</role></castItem>
              <castItem><role xml:id="JUAN">Juan</role></castItem>
            </castList></div>
            """,
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp who="#ANA"><speaker>ANA</speaker>
                <lg type="redondilla"><l n="1">Dulce <emph>sueño</emph> mío</l><l n="2">ven a mí</l><l n="3" part="I">ya</l></lg>
              </sp>
              <sp who="#JUAN"><speaker>JUAN</speaker>
                <lg type="free" part="F"><l part="F">no puedo</l><l n="4"><seg type="aside">qué haré</seg></l></lg>
              </sp>
              <sp who="#ANA #JUAN"><speaker>LOS DOS</speaker>
                <lg type="redondilla"><l n="5">juntos</l></lg>
              </sp>
              <sp><speaker>CRIADO</speaker><p>Señor, la cena.</p></sp>
            </div1>
            """
          )
        )

      data = Statistics.get_statistics(play.id).data
      characters = Map.new(data["characters"], &{&1["name"], &1})

      assert Enum.map(data["characters"], & &1["name"]) == ["Ana", "Juan", "CRIADO"]

      assert %{
               "speeches" => 2,
               "lines" => 4,
               "words" => 8,
               "first" => %{"act" => 1, "line" => 1},
               "aside_verses" => 0,
               "longest_speech" => %{"lines" => 3, "words" => 7},
               "forms" => %{"redondilla" => 4}
             } = characters["Ana"]

      # Juan's first words complete verse 3; the shared verse 5 counts for both.
      assert %{
               "speeches" => 2,
               "lines" => 3,
               "words" => 5,
               "first" => %{"line" => 3},
               "aside_verses" => 1
             } =
               characters["Juan"]

      assert %{"speeches" => 1, "lines" => 0, "words" => 3, "first" => %{"line" => nil}} =
               characters["CRIADO"]

      assert %{"verses" => 5, "speeches" => 4, "words" => 15} = data
    end
  end

  describe "presence" do
    test "columns are the scenes when the play has them" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>Acto I</head>
              <div2 type="escena" n="1"><head>Escena 1</head>
                <sp><speaker>A</speaker><l n="1">uno</l></sp>
              </div2>
              <div2 type="escena" n="2"><head>Escena 2</head>
                <sp><speaker>B</speaker><l n="2">dos</l></sp>
                <sp><speaker>A</speaker><l n="3">tres</l></sp>
              </div2>
            </div1>
            """
          )
        )

      data = Statistics.get_statistics(play.id).data

      assert %{
               "basis" => "scene",
               "columns" => [
                 %{"act" => 1, "label" => "Escena 1"},
                 %{"act" => 1, "label" => "Escena 2"}
               ]
             } =
               data["presence"]

      assert %{"A" => [[0, 1], [1, 1]], "B" => [[1, 1]]} =
               Map.new(data["characters"], &{&1["name"], &1["columns"]})

      assert [
               %{"scene" => "Escena 1", "verses" => 1, "speeches" => 1, "speakers" => 1},
               %{"scene" => "Escena 2", "verses" => 2, "speeches" => 2, "speakers" => 2}
             ] = data["divisions"]
    end

    test "with no scenes, columns are the metrical passages" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp><speaker>A</speaker><lg type="redondilla"><l n="1">uno</l></lg><lg type="decima"><l n="2">dos</l></lg></sp>
              <sp><speaker>B</speaker><lg type="decima"><l n="3">tres</l></lg></sp>
            </div1>
            """
          )
        )

      data = Statistics.get_statistics(play.id).data

      assert %{
               "basis" => "passage",
               "columns" => [
                 %{"form" => "redondilla", "from" => 1, "to" => 1},
                 %{"form" => "decima", "from" => 2, "to" => 3}
               ]
             } = data["presence"]

      assert %{"A" => [[0, 1], [1, 1]], "B" => [[1, 1]]} =
               Map.new(data["characters"], &{&1["name"], &1["columns"]})
    end
  end

  test "recompute/1 refreshes cached statistics after content changes" do
    %{play: play, line_group: line_group, scene: scene} =
      TestFixtures.play_with_structure_fixture()

    first = Statistics.get_statistics(play.id)

    {:ok, _new_verse} =
      PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        type: "verse_line",
        content: "New line",
        line_number: 10,
        position: 10
      })

    refreshed = Statistics.recompute(play.id)

    assert refreshed.data["total_verses"] == first.data["total_verses"] + 1
  end
end
