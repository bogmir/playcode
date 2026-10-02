defmodule Playcode.StatisticsTest do
  use Playcode.DataCase, async: true

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
