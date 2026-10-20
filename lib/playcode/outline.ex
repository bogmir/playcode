defmodule Playcode.Outline do
  @moduledoc """
  A play's outline: one ordered sequence of its top-level items, its paratexts (the scene
  of the action among them) and its divisions (acts, prologues, interludes, cast lists…).
  Paratexts and divisions share one `position` sequence per play; nothing is ordered by
  kind. An act's scenes and cast lists are its own sequence, its `children`.
  """

  alias Playcode.PlayContent.Division

  @doc "The top-level items of `paratexts` and `divisions`, in outline order."
  def items(paratexts, divisions) do
    (paratexts ++ Enum.filter(divisions, &is_nil(&1.parent_id)))
    |> Enum.sort_by(&{&1.position, &1.id})
  end

  @doc """
  Where each of `items` (in outline order) stands in the file: `:front` before the first
  division of the text, `:back` after the last, `:body` between them. A cast list is not a
  division of the text. With none, every item is `:front`.
  """
  def placement(items) do
    indexed = Enum.with_index(items)
    body = for {item, index} <- indexed, text_division?(item), do: index

    for {item, index} <- indexed do
      cond do
        body == [] or index < hd(body) -> {:front, item}
        index > List.last(body) -> {:back, item}
        true -> {:body, item}
      end
    end
  end

  defp text_division?(%Division{type: type}), do: type != "elenco"
  defp text_division?(_paratext), do: false
end
