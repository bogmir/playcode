defmodule Playcode.Outline do
  @moduledoc """
  A play's outline: one ordered sequence of its top-level items, its paratexts (the scene
  of the action among them) and its divisions (acts, prologues, interludes, cast lists…).
  Paratexts and divisions share one `position` sequence per play; nothing is ordered by
  kind. An act's scenes and cast lists are its own sequence, its `children`.
  """

  @doc "The top-level items of `paratexts` and `divisions`, in outline order."
  def items(paratexts, divisions) do
    (paratexts ++ Enum.filter(divisions, &is_nil(&1.parent_id)))
    |> Enum.sort_by(&{&1.position, &1.id})
  end
end
