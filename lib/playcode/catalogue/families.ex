defmodule Playcode.Catalogue.Families do
  @moduledoc """
  A family is a root play and every play whose `parent_play_id` chain leads to it.
  On a cycle (hand-edited data) each play of it stands alone as its own root.
  """

  @doc """
  Every play's id mapped to the id of the play at the top of its chain within `plays`;
  a play whose parent is not among them is its own root.
  """
  def root_ids(plays) do
    by_id = Map.new(plays, &{&1.id, &1})
    Map.new(plays, &{&1.id, root_id(&1, by_id, MapSet.new([&1.id]), &1.id)})
  end

  defp root_id(play, by_id, seen, start) do
    case by_id[play.parent_play_id] do
      nil ->
        play.id

      parent ->
        if parent.id in seen,
          do: start,
          else: root_id(parent, by_id, MapSet.put(seen, parent.id), start)
    end
  end
end
