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
