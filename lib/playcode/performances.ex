defmodule Playcode.Performances do
  @moduledoc """
  A play's historical performances (S5): who staged it, when, where, with which cast, and
  the source that says so. Owns `play_performances` and its `performance_cast`, as
  `Playcode.Witnesses` owns witnesses, and the corpus-wide companies and actors they name.
  Spec: docs/superpowers/specs/2026-10-19-s5-performances-design.md.

  A company or an actor is one record for every performance that names it, found by name
  or created (`find_or_create_company/1`, `find_or_create_actor/1`), renamed in place
  (`update_company/2`, `update_actor/2`), and deleted with the last performance that names
  it: a write that lets one go deletes it in its own transaction (`delete_unused/1`).
  """

  import Ecto.Query
  import Ecto.Changeset, only: [get_field: 2, put_change: 3]

  alias Playcode.Performances.{Actor, CastMember, Company, Performance}
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

  def update_performance(%Performance{} = performance, attrs) do
    Repo.transact(fn ->
      with {:ok, updated} <- performance |> Performance.changeset(attrs) |> Repo.update() do
        delete_unused(companies: [performance.company_id])
        {:ok, updated}
      end
    end)
  end

  def delete_performance(%Performance{} = performance) do
    Repo.transact(fn ->
      # Read before the delete: the cast goes with the performance.
      actor_ids =
        Repo.all(
          from m in CastMember, where: m.performance_id == ^performance.id, select: m.actor_id
        )

      with {:ok, deleted} <- Repo.delete(performance) do
        delete_unused(companies: [performance.company_id], actors: actor_ids)
        {:ok, deleted}
      end
    end)
  end

  @doc """
  Replaces the performance's cast with `rows`, `%{"actor_id" => id, "role" => role}`, in the
  order given. A row needs an actor that exists; the cast is unchanged when one is refused.
  """
  def put_cast(%Performance{} = performance, rows) do
    Repo.transact(fn ->
      performance = Repo.preload(performance, :cast, force: true)

      with {:ok, updated} <- performance |> Performance.cast_changeset(rows) |> Repo.update() do
        delete_unused(actors: Enum.map(performance.cast, & &1.actor_id))
        {:ok, Repo.preload(updated, [cast: :actor], force: true)}
      end
    end)
  end

  @doc "Every company, by name."
  def list_companies, do: Repo.all(from c in Company, order_by: c.name)

  @doc """
  Every actor, by surname (a nickname alone stands for it), forename, then nickname.
  """
  def list_actors do
    Repo.all(
      from a in Actor,
        order_by: [
          coalesce(a.surname, a.nickname),
          coalesce(a.forename, ""),
          coalesce(a.nickname, "")
        ]
    )
  end

  @doc "The company `id`, or nil: the id arrives from the browser, so a malformed one is nil too."
  def get_company(id), do: get(Company, id)

  @doc "The actor `id`, or nil, as `get_company/1`."
  def get_actor(id), do: get(Actor, id)

  defp get(schema, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(schema, id)
      :error -> nil
    end
  end

  @doc "The company named `name`, ignoring case, else a new one."
  def find_or_create_company(name) do
    changeset = Company.changeset(%Company{}, %{"name" => name})

    # ponytail: two curators adding the same new company in the same instant make the
    # second fail on the unique index; they save again and find it.
    case company_named(get_field(changeset, :name)) do
      nil -> Repo.insert(changeset)
      company -> {:ok, company}
    end
  end

  defp company_named(nil), do: nil

  defp company_named(name) do
    Repo.one(
      from c in Company, where: fragment("lower(?)", c.name) == fragment("lower(?)", ^name)
    )
  end

  @doc """
  The actor with these `surname`, `forename`, `nickname` and `sex`, ignoring case, else a
  new one.
  """
  def find_or_create_actor(attrs) do
    changeset = Actor.changeset(%Actor{}, attrs)

    case Actor.twin(changeset) do
      %Actor{} = actor -> {:ok, actor}
      nil -> Repo.insert(changeset)
    end
  end

  @doc """
  Renames a company, for every performance that names it. A name another company has is
  refused.
  """
  def update_company(%Company{} = company, attrs),
    do: company |> Company.changeset(attrs) |> Repo.update()

  @doc """
  Corrects an actor, for every performance that names them. Another actor's four fields
  are refused.
  """
  def update_actor(%Actor{} = actor, attrs),
    do: actor |> Actor.changeset(attrs) |> Repo.update()

  @doc "How many performances, in how many plays, name a company or an actor."
  def usage(%Company{id: id}), do: count_usage(from(p in Performance, where: p.company_id == ^id))

  def usage(%Actor{id: id}) do
    cast = from(m in CastMember, where: m.actor_id == ^id, select: m.performance_id)
    count_usage(from(p in Performance, where: p.id in subquery(cast)))
  end

  defp count_usage(performances) do
    Repo.one(
      from p in performances,
        select: %{performances: count(p.id), plays: count(p.play_id, :distinct)}
    )
  end

  # What a write let go of, in its own transaction: the companies and actors no performance
  # names any more are deleted. `freed` is a keyword of id lists, `companies:` and `actors:`.
  defp delete_unused(freed) do
    company_ids = ids(freed, :companies)
    actor_ids = ids(freed, :actors)

    Repo.delete_all(
      from c in Company,
        as: :company,
        where: c.id in ^company_ids,
        where: not exists(from p in Performance, where: p.company_id == parent_as(:company).id)
    )

    Repo.delete_all(
      from a in Actor,
        as: :actor,
        where: a.id in ^actor_ids,
        where: not exists(from m in CastMember, where: m.actor_id == parent_as(:actor).id)
    )
  end

  defp ids(freed, key), do: freed |> Keyword.get(key, []) |> Enum.reject(&is_nil/1)

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
