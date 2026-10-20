defmodule Playcode.CastListsTest do
  @moduledoc """
  A play's cast lists and their entries, read back through `PlayContent`. A character is
  the person the speeches point at; each list prints its own entry for them, and the
  character's name, description and place are its first entry's, in outline order.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.PlayContent

  defp division!(play, attrs) do
    {:ok, division} = PlayContent.create_division(Map.put(attrs, :play_id, play.id))
    division
  end

  defp entry_names(play),
    do: for(list <- PlayContent.list_cast_lists(play.id), do: Enum.map(list.entries, & &1.name))

  test "a character takes its name, description and place from its first entry in outline order" do
    # The act's list is made first; the list before the acts still comes first.
    play = play_fixture()
    act = division!(play, %{type: "acto", number: 1, position: 1})
    inner = division!(play, %{type: "elenco", parent_id: act.id, position: 0})

    {:ok, ana} =
      PlayContent.create_character(%{
        play_id: play.id,
        xml_id: "ANA",
        name: "ANA, disfrazada",
        cast_list_id: inner.id
      })

    front = division!(play, %{type: "elenco", title: "PERSONAS", position: 0})

    {:ok, _entry} =
      PlayContent.create_entry(%{
        play_id: play.id,
        cast_list_id: front.id,
        character_id: ana.id,
        name: "ANA",
        description: "dama"
      })

    assert [%{name: "ANA", description: "dama"}] = PlayContent.list_characters(play.id)
    assert entry_names(play) == [["ANA"], ["ANA, disfrazada"]]
  end

  test "a new character in a play with no cast list arrives in one made at the head of the outline" do
    play = play_fixture()
    division!(play, %{type: "acto", number: 1, position: 0})

    {:ok, _blas} = PlayContent.create_character(%{play_id: play.id, xml_id: "BLAS", name: "BLAS"})

    assert [%{type: "elenco", position: -1, parent_id: nil}] =
             PlayContent.list_cast_lists(play.id)

    assert entry_names(play) == [["BLAS"]]
  end

  test "characters keep the order of their entries across the lists" do
    play = play_fixture()
    list = division!(play, %{type: "elenco", position: 0})

    for {name, position} <- Enum.with_index(~w(CARLOS ANA BLAS)) do
      {:ok, _} =
        PlayContent.create_character(%{
          play_id: play.id,
          xml_id: name,
          name: name,
          position: position,
          cast_list_id: list.id
        })
    end

    assert Enum.map(PlayContent.list_characters(play.id), & &1.name) == ~w(CARLOS ANA BLAS)
    assert entry_names(play) == [~w(CARLOS ANA BLAS)]
  end
end
