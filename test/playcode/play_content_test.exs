defmodule Playcode.PlayContentTest do
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.PlayContent
  alias Playcode.TestFixtures

  # Edge cases of the editor's renumbering, much simpler to set up here than through
  # the editor. The plain cases (insert above, delete) are asserted through the
  # editor in test/playcode_web/live/admin/play_content_editor_live_test.exs.
  describe "shift_element_positions/3" do
    test "only shifts elements within the same parent" do
      %{play: play, scene: scene, speech: speech} = TestFixtures.play_with_structure_fixture()

      # Create child elements under speech
      {:ok, c1} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 5
        })

      {:ok, c2} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 10
        })

      # Shift children of speech at position >= 5
      PlayContent.shift_element_positions(scene.id, speech.id, 5)

      assert PlayContent.get_element!(c1.id).position == 6
      assert PlayContent.get_element!(c2.id).position == 11
    end
  end

  describe "shift_line_numbers/2" do
    test "preserves split verse groupings (same line_number shifted together)" do
      %{play: play, scene: scene, line_group: line_group} =
        TestFixtures.play_with_structure_fixture()

      # Create a split verse pair at line 5
      {:ok, v5i} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "start",
          line_number: 5,
          part: "I",
          position: 10
        })

      {:ok, v5f} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "end",
          line_number: 5,
          part: "F",
          position: 11
        })

      # Shift all >= 5
      PlayContent.shift_line_numbers(play.id, 5)

      assert PlayContent.get_element!(v5i.id).line_number == 6
      assert PlayContent.get_element!(v5f.id).line_number == 6
    end
  end

  describe "auto_line_number/3" do
    test "returns previous sibling line_number + 1" do
      %{play: play, scene: scene, line_group: line_group} =
        TestFixtures.play_with_structure_fixture()

      # Fixture has verse_line at position 1, line_number 1
      {:ok, _v2} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: line_group.id,
          type: "verse_line",
          content: "v2",
          line_number: 2,
          position: 2
        })

      # New verse at position 3 (end) should get line_number 3
      assert PlayContent.auto_line_number(play.id, line_group.id, 3) == 3
    end

    test "returns next sibling line_number when inserting at start of group" do
      %{play: play, scene: scene, speech: speech} = TestFixtures.play_with_structure_fixture()

      # Create a new empty line_group
      {:ok, lg} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 50
        })

      {:ok, _v1} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: lg.id,
          type: "verse_line",
          content: "existing",
          line_number: 10,
          position: 1
        })

      # Inserting at position 0 (before the existing verse) should get line_number 10
      assert PlayContent.auto_line_number(play.id, lg.id, 0) == 10
    end

    test "returns global max + 1 for empty line_group" do
      %{play: play, scene: scene, speech: speech} = TestFixtures.play_with_structure_fixture()

      # Fixture has verse_line with line_number 1. Create empty line_group.
      {:ok, lg} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: scene.id,
          parent_id: speech.id,
          type: "line_group",
          position: 50
        })

      # Empty group, global max is 1, so should return 2
      assert PlayContent.auto_line_number(play.id, lg.id, 0) == 2
    end
  end

  describe "in-text notes" do
    test "a note hangs on an element or a division, never on both or neither" do
      %{play: play, act: act, verse_line: line} = play_with_structure_fixture()
      note = %{play_id: play.id, offset: 0, body: "Glosa"}

      assert {:ok, _} = PlayContent.create_note(Map.put(note, :element_id, line.id))
      assert {:ok, _} = PlayContent.create_note(Map.put(note, :division_id, act.id))
      assert {:error, _} = PlayContent.create_note(note)

      assert {:error, _} =
               PlayContent.create_note(
                 Map.merge(note, %{element_id: line.id, division_id: act.id})
               )
    end

    test "a line's notes list in text order, and go when the line goes" do
      %{play: play, verse_line: line} = play_with_structure_fixture()

      for {offset, body} <- [{5, "Segunda"}, {1, "Primera"}] do
        {:ok, _} =
          PlayContent.create_note(%{
            play_id: play.id,
            element_id: line.id,
            offset: offset,
            body: body
          })
      end

      assert Enum.map(PlayContent.list_notes(line), & &1.body) == ["Primera", "Segunda"]

      {:ok, _} = PlayContent.delete_element(line)
      assert PlayContent.list_notes(line) == []
    end

    test "notes at one offset keep the order they were added in, through edits" do
      %{play: play, verse_line: line} = play_with_structure_fixture()

      note = fn offset, body ->
        %{play_id: play.id, element_id: line.id, offset: offset, body: body}
      end

      bodies = fn -> PlayContent.list_notes(line) |> Enum.map(& &1.body) end

      {:ok, first} = PlayContent.create_note(note.(3, "Primera"))
      {:ok, _second} = PlayContent.create_note(note.(3, "Segunda"))
      {:ok, _} = PlayContent.create_note(note.(7, "Tercera"))
      {:ok, _} = PlayContent.create_note(note.(7, "Cuarta"))
      assert bodies.() == ["Primera", "Segunda", "Tercera", "Cuarta"]

      # Changing a note's text does not move it among its neighbours.
      {:ok, first} = PlayContent.update_note(first, %{"body" => "Primera, corregida"})
      assert bodies.() == ["Primera, corregida", "Segunda", "Tercera", "Cuarta"]

      # Moving a note to a word that has one puts it after that one.
      {:ok, _} = PlayContent.update_note(first, %{"offset" => "7"})
      assert bodies.() == ["Segunda", "Tercera", "Cuarta", "Primera, corregida"]
    end
  end
end
