defmodule Playcode.Performances do
  @moduledoc """
  A play's historical performances (S5): who staged it, when, where, with which cast, and
  the source that says so. Owns `play_performances` and its `performance_cast`, as
  `Playcode.Witnesses` owns witnesses. Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.
  """

  import Ecto.Query
  import Ecto.Changeset, only: [get_field: 2, put_change: 3]

  alias Playcode.Performances.Performance
  alias Playcode.Repo

  @preloads [:company, :source, place: :names, cast: :actor]

  @doc """
  The play's performances, in order of year (`year_from`, else `year_to`; the undated last),
  then as entered.
  """
  def list_for_play(play_id) do
    Performance
    |> where([p], p.play_id == ^play_id)
    |> order_by([p],
      asc: fragment("coalesce(?, ?)", p.year_from, p.year_to),
      asc: p.position,
      asc: p.inserted_at
    )
    |> preload(^@preloads)
    |> Repo.all()
  end

  @doc """
  The play's performance `id`, or nil. Scoped to the play because the id arrives from the
  browser: another play's performance, a deleted one or a malformed id is nil.
  """
  def get_performance(play_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Performance |> Repo.get_by(id: id, play_id: play_id) |> Repo.preload(@preloads)
      :error -> nil
    end
  end

  def change_performance(%Performance{} = performance, attrs \\ %{}),
    do: Performance.changeset(performance, attrs)

  @doc """
  Adds a performance after the play's last. `attrs` carry its `play_id`; `base` is the
  struct to start from, so the FileMaker import can set `filemaker_id`.
  """
  def create_performance(attrs, %Performance{} = base \\ %Performance{}) do
    changeset = Performance.changeset(base, attrs)

    changeset
    |> put_change(:position, next_position(get_field(changeset, :play_id)))
    |> Repo.insert()
  end

  def update_performance(%Performance{} = performance, attrs),
    do: performance |> Performance.changeset(attrs) |> Repo.update()

  def delete_performance(%Performance{} = performance), do: Repo.delete(performance)

  # max + 1, not a count: a deletion leaves a gap, and a count would tie the next
  # performance with the one after the gap.
  defp next_position(nil), do: 0

  defp next_position(play_id) do
    case Repo.aggregate(from(p in Performance, where: p.play_id == ^play_id), :max, :position) do
      nil -> 0
      max -> max + 1
    end
  end
end
