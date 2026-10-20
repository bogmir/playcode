defmodule Playcode.Outline do
  @moduledoc """
  A play's outline: one ordered sequence of its top-level items, its paratexts (the scene
  of the action among them) and its divisions (acts, prologues, interludes, cast lists…).
  Paratexts and divisions share one `position` sequence per play; nothing is ordered by
  kind. An act's scenes and cast lists are its own sequence, its `children`.
  """

  import Ecto.Query

  alias Playcode.{Catalogue, PlayContent, Repo}
  alias Playcode.Catalogue.Paratext
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

  @doc """
  Puts the play's top-level items in the order of `keys`, each `"paratext:<id>"` or
  `"division:<id>"` as the Structure tab's rows carry them. A key that is not one of the
  play's top-level items is dropped; an item the keys leave out keeps its turn after them.
  The characters follow their first entries.
  """
  def reorder(play_id, keys) do
    play_id
    |> Catalogue.list_paratexts()
    |> items(PlayContent.list_top_divisions(play_id))
    |> PlayContent.renumber(keys, &key/1)

    PlayContent.sync_characters(play_id)
    :ok
  end

  @doc "An outline item's key, as `reorder/2` takes it."
  def key(%Paratext{id: id}), do: "paratext:#{id}"
  def key(%Division{id: id}), do: "division:#{id}"

  @doc "The position after the play's last top-level item, paratexts and divisions alike."
  def next_position(play_id) do
    paratexts = Paratext |> where(play_id: ^play_id) |> select([p], max(p.position))

    divisions =
      Division
      |> where([d], d.play_id == ^play_id and is_nil(d.parent_id))
      |> select([d], max(d.position))

    [Repo.one(paratexts), Repo.one(divisions)]
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> -1 end)
    |> Kernel.+(1)
  end

  defp text_division?(%Division{type: type}), do: type != "elenco"
  defp text_division?(_paratext), do: false
end
