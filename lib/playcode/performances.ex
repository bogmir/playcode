defmodule Playcode.Performances do
  @moduledoc """
  A play's historical performances (S5): who staged it, when, where, with which cast, and
  the source that says so. Owns `play_performances` and its `performance_cast`, as
  `Playcode.Witnesses` owns witnesses, and the corpus-wide companies and actors they name.
  Spec: docs/superpowers/specs/2026-10-19-s5-performances-design.md.

  A company or an actor is one record for every performance that names it, found by name
  or created (`find_or_create_company/1`, `find_or_create_actor/1`), renamed in place
  (`update_company/2`, `update_actor/2`), and deleted with the last performance that names
  it: a write that lets one go deletes it in its own transaction (`delete_unused/1`). The
  performance's source is a bibliography entry, deleted with its last citation the same way
  (`Playcode.Bibliography.delete_if_unused/1`).
  """

  import Ecto.Query
  import Ecto.Changeset, only: [add_error: 4, get_field: 2, put_change: 3]

  alias Playcode.Bibliography
  alias Playcode.PlayContent.InlineMarkup
  alias Playcode.Performances.{Actor, CastMember, Company, Performance}
  alias Playcode.Places
  alias Playcode.Repo
  alias Playcode.Text

  defp preloads,
    do: [:company, :source, place: [names: Places.names_query()], cast: :actor]

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
    |> preload(^preloads())
    |> Repo.all()
  end

  @doc """
  The play's performance `id`, or nil. Scoped to the play because the id arrives from the
  browser: another play's performance, a deleted one or a malformed id is nil.
  """
  def get_performance(play_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Performance |> Repo.get_by(id: id, play_id: play_id) |> Repo.preload(preloads())

      :error ->
        nil
    end
  end

  @doc """
  The performances as readers see them (layout B): `lines`, one per performance in the order
  given, and the `sources` they cite, `{number, entry}`, numbered in order of first citation.
  `performances` come from `list_for_play/1`, `characters` from
  `Playcode.PlayContent.list_characters/1` and `gazetteer` from `Playcode.Places.gazetteer/0`.

  A line is the `date` as written; its `parts`, those present of the venue, the place line
  (`Places.place_line/3`), the company and the venue type's label, to be joined by the page;
  the number of its `source` and the performance's own volume and pages, its `range`
  (`"vol. 6, p. 83"`); its `cast`, each `"Actor (role)"`; and its `note`. A performance that
  takes its cast from the cast list prints first the characters' actors, as the cast list
  prints its characters (a hidden one left out), then the cast rows of its own.

  `locale` is the page's language, for the venue types; the place names follow `place_locale`
  when the page's language is not theirs (the static site is in English, its places Spanish).
  """
  def listing(performances, characters, gazetteer, locale, place_locale \\ nil) do
    place_locale = place_locale || locale

    {lines, sources} =
      Enum.map_reduce(performances, [], fn performance, sources ->
        {number, sources} = number_source(performance.source, sources)

        line = %{
          id: performance.id,
          date: performance.date_text,
          parts: parts(performance, gazetteer, locale, place_locale),
          source: number,
          range: range(performance),
          cast: cast(performance, characters),
          note: performance.note
        }

        {line, sources}
      end)

    %{lines: lines, sources: sources}
  end

  @doc """
  Where a line says it comes from: its source's number and its own volume and pages
  (`"[1] vol. 6, p. 83"`), those present, or nil.
  """
  def reference(line), do: join_present([line.source && "[#{line.source}]", line.range], " ")

  defp number_source(nil, sources), do: {nil, sources}

  defp number_source(entry, sources) do
    case Enum.find(sources, fn {_number, cited} -> cited.id == entry.id end) do
      {number, _entry} ->
        {number, sources}

      nil ->
        number = length(sources) + 1
        {number, sources ++ [{number, entry}]}
    end
  end

  defp parts(performance, gazetteer, locale, place_locale) do
    [
      performance.venue,
      performance.place && Places.place_line(performance, gazetteer, place_locale),
      performance.company && performance.company.name,
      performance.venue_type && Performance.venue_type_label(performance.venue_type, locale)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
  end

  # ponytail: "p." even for a span of pages ("83-85"); the pages are free text.
  defp range(performance) do
    join_present(
      [
        performance.source_volume && "vol. #{performance.source_volume}",
        performance.source_pages && "p. #{performance.source_pages}"
      ],
      ", "
    )
  end

  defp join_present(parts, separator) do
    case Enum.reject(parts, &is_nil/1) do
      [] -> nil
      present -> Enum.join(present, separator)
    end
  end

  defp cast(performance, characters) do
    own =
      for member <- performance.cast, do: cast_line(Actor.display_name(member.actor), member.role)

    if performance.cast_from_cast_list, do: cast_list_actors(characters) ++ own, else: own
  end

  # Each character with an actor, in cast-list order, as the printed cast list leaves out
  # the hidden ones.
  defp cast_list_actors(characters) do
    for %{actor: actor} = character <- characters,
        not character.is_hidden,
        actor not in [nil, ""],
        do: cast_line(InlineMarkup.plain(actor), InlineMarkup.plain(character.name))
  end

  defp cast_line(actor, nil), do: actor
  defp cast_line(actor, role), do: "#{actor} (#{role})"

  def change_performance(%Performance{} = performance, attrs \\ %{}),
    do: Performance.changeset(performance, attrs)

  @doc """
  Adds a performance after the play's last. `attrs` carry its `play_id`; `base` is the
  struct to start from, so the FileMaker import can set `filemaker_id`. See
  `update_performance/2` for a `"company_name"`.
  """
  def create_performance(attrs, %Performance{} = base \\ %Performance{}) do
    with_company(base, attrs, fn attrs ->
      changeset = Performance.changeset(base, attrs)

      changeset
      |> put_change(:position, next_position(get_field(changeset, :play_id)))
      |> Repo.insert()
    end)
  end

  @doc """
  Corrects a performance. A `"company_name"` among `attrs` stands for the company: found by
  name or created (blank, none), in the same transaction as the write, so a refused write
  leaves no company behind. The company it had, if no performance names it now, is deleted.
  The `updated` performance keeps the associations it came with: read it again
  (`get_performance/2`) before showing its company.
  """
  def update_performance(%Performance{} = performance, attrs) do
    with_company(performance, attrs, fn attrs ->
      with {:ok, updated} <- performance |> Performance.changeset(attrs) |> Repo.update() do
        delete_unused(
          companies: [performance.company_id],
          entries: [performance.source_entry_id]
        )

        {:ok, updated}
      end
    end)
  end

  # Runs `write` with the `company_id` for the "company_name" in `attrs`, if there is one.
  defp with_company(base, attrs, write) do
    Repo.transact(fn ->
      case put_company(attrs) do
        {:ok, attrs} -> write.(attrs)
        {:error, company} -> {:error, company_error(base, attrs, company)}
      end
    end)
  end

  defp put_company(%{"company_name" => name} = attrs) do
    case Text.squeeze(name) do
      nil ->
        {:ok, Map.put(attrs, "company_id", nil)}

      name ->
        with {:ok, company} <- find_or_create_company(name),
             do: {:ok, Map.put(attrs, "company_id", company.id)}
    end
  end

  defp put_company(attrs), do: {:ok, attrs}

  # The refused company's errors (only a rival writer's unique name can refuse one), on the
  # performance's own changeset under the field the form calls it.
  defp company_error(base, attrs, company) do
    changeset = Performance.changeset(base, attrs)

    company.errors
    |> Enum.reduce(changeset, fn {_field, {message, opts}}, changeset ->
      add_error(changeset, :company_name, message, opts)
    end)
    |> Map.put(:action, :validate)
  end

  def delete_performance(%Performance{} = performance) do
    Repo.transact(fn ->
      # Read before the delete: the cast goes with the performance.
      actor_ids =
        Repo.all(
          from m in CastMember, where: m.performance_id == ^performance.id, select: m.actor_id
        )

      with {:ok, deleted} <- Repo.delete(performance) do
        delete_unused(
          companies: [performance.company_id],
          actors: actor_ids,
          entries: [performance.source_entry_id]
        )

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
  The actor with these `surname`, `forename` and `nickname`, ignoring case, whatever `sex`
  it was given (the sex is not who they are); an actor with none takes the one given. Else a
  new one.
  """
  def find_or_create_actor(attrs) do
    changeset = Actor.changeset(%Actor{}, attrs)

    case Actor.twin(changeset) do
      nil ->
        Repo.insert(changeset)

      %Actor{sex: nil} = actor ->
        actor |> Actor.changeset(%{"sex" => get_field(changeset, :sex)}) |> Repo.update()

      %Actor{} = actor ->
        {:ok, actor}
    end
  end

  @doc """
  Renames a company, for every performance that names it. A name another company has is
  refused.
  """
  def update_company(%Company{} = company, attrs),
    do: company |> Company.changeset(attrs) |> Repo.update()

  @doc """
  Corrects an actor, for every performance that names them. Another actor's surname,
  forename and nickname are refused.
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
  # names any more, and the source entries nothing cites, are deleted. `freed` is a keyword of
  # id lists, `companies:`, `actors:` and `entries:`.
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

    Enum.each(ids(freed, :entries), &Bibliography.delete_if_unused/1)
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
