defmodule Playcode.Witnesses do
  @moduledoc """
  A play's witnesses (S3): the manuscripts and early printings its text survives in.
  Spec: docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.
  """

  import Ecto.Query
  import Ecto.Changeset, only: [change: 2, get_field: 2, put_change: 3]

  alias Playcode.Bibliography.{Entry, Link}
  alias Playcode.Repo
  alias Playcode.Witnesses.Witness

  @doc "The play's witnesses, in order."
  def list_for_play(play_id) do
    Witness
    |> where([w], w.play_id == ^play_id)
    |> order_by([w], asc: w.position, asc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  The play's witness `id`, or nil. Scoped to the play because the id arrives from the
  browser: another play's witness, a deleted one or a malformed id is nil.
  """
  def get_witness(play_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(Witness, id: id, play_id: play_id)
      :error -> nil
    end
  end

  def change_witness(%Witness{} = witness, attrs \\ %{}), do: Witness.changeset(witness, attrs)

  @doc """
  Adds a witness after the play's last. `attrs` carry its `play_id`; `base` is the struct
  to start from, so the FileMaker import can set `filemaker_id`.
  """
  def create_witness(attrs, %Witness{} = base \\ %Witness{}) do
    changeset = Witness.changeset(base, attrs)

    changeset
    |> put_change(:position, next_position(get_field(changeset, :play_id)))
    |> Repo.insert()
  end

  def update_witness(%Witness{} = witness, attrs),
    do: witness |> Witness.changeset(attrs) |> Repo.update()

  def delete_witness(%Witness{} = witness), do: Repo.delete(witness)

  @doc "Swaps a witness with its neighbour and renumbers the play's. A move past either end is a no-op."
  def move_witness(%Witness{} = witness, direction) when direction in [:up, :down] do
    witnesses = list_for_play(witness.play_id)
    index = Enum.find_index(witnesses, &(&1.id == witness.id))
    target = if direction == :up, do: index && index - 1, else: index && index + 1

    if is_nil(index) or target < 0 or target >= length(witnesses) do
      :ok
    else
      {:ok, :ok} =
        Repo.transaction(fn ->
          witnesses
          |> List.replace_at(index, Enum.at(witnesses, target))
          |> List.replace_at(target, Enum.at(witnesses, index))
          |> Enum.with_index()
          |> Enum.each(fn {w, i} ->
            if w.position != i, do: Repo.update!(change(w, position: i))
          end)
        end)

      :ok
    end
  end

  @doc """
  The sigla a TEI import must not bring in for the play: its witnesses' (the file's own
  are removed before a re-import reads them) and its modern editions', which live in the
  bibliography.
  """
  def taken_sigla(play_id) do
    witnesses =
      from(w in Witness, where: w.play_id == ^play_id and not is_nil(w.siglum), select: w.siglum)

    editions =
      from(l in Link,
        join: e in Entry,
        on: e.id == l.entry_id,
        where: l.play_id == ^play_id and not is_nil(e.siglum),
        select: e.siglum
      )

    MapSet.new(Repo.all(witnesses) ++ Repo.all(editions))
  end

  # max + 1, not a count: a deletion leaves a gap, and a count would tie the next witness
  # with the one after the gap.
  defp next_position(nil), do: 0

  defp next_position(play_id) do
    case Repo.aggregate(from(w in Witness, where: w.play_id == ^play_id), :max, :position) do
      nil -> 0
      max -> max + 1
    end
  end
end
