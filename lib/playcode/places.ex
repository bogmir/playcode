defmodule Playcode.Places do
  @moduledoc """
  The corpus-global gazetteer: places, their names, and the plays that reference them.

  Places are shared across every play, which is what makes "every play set in Italy"
  answerable — and also why a delete is constrained rather than cascading. See
  `docs/superpowers/specs/2026-08-04-s9-places-design.md`.
  """

  import Ecto.Query

  alias Ecto.Changeset
  alias Playcode.Places.{Place, PlaceName, PlayPlace}
  alias Playcode.Repo

  @name_order [desc: :is_preferred, asc: :position, asc: :name]

  # --- Places ---

  def change_place(%Place{} = place, attrs \\ %{}) do
    place
    |> Place.changeset(attrs)
    |> Changeset.cast_assoc(:names,
      required: true,
      required_message: "at least one name is required",
      sort_param: :names_order,
      drop_param: :names_delete
    )
  end

  def create_place(attrs) do
    %Place{}
    |> change_place(ensure_slug(attrs, nil))
    |> Repo.insert()
  end

  def update_place(%Place{} = place, attrs) do
    place
    |> Repo.preload(:names)
    |> change_place(ensure_slug(attrs, place))
    |> reject_parent_cycle(place)
    |> Repo.update()
  end

  def delete_place(%Place{} = place) do
    place
    |> Changeset.change()
    |> Changeset.no_assoc_constraint(:play_places,
      message: "is still used by one or more plays"
    )
    |> Changeset.no_assoc_constraint(:children, message: "is the parent of other places")
    |> Repo.delete()
  end

  def get_place!(id) do
    Place
    |> Repo.get!(id)
    |> Repo.preload([:parent, names: from(n in PlaceName, order_by: ^@name_order)])
  end

  def list_places(opts \\ []) do
    locale = opts[:locale] || "es"

    Place
    |> Repo.all()
    |> Repo.preload(names: from(n in PlaceName, order_by: ^@name_order))
    |> with_play_counts()
    |> Enum.sort_by(&slugify(display_name(&1, locale)))
  end

  # Shared by list_places/1 and search_names/2 so the "Plays" column never blanks out
  # depending on which one loaded the place.
  defp with_play_counts(places) do
    counts =
      PlayPlace
      |> group_by([pp], pp.place_id)
      |> select([pp], {pp.place_id, count(pp.id)})
      |> Repo.all()
      |> Map.new()

    Enum.map(places, &%{&1 | play_count: Map.get(counts, &1.id, 0)})
  end

  @doc """
  The name to print. A fallback chain, which is what the per-language `is_preferred`
  index makes possible: preferred-in-locale, any-in-locale, preferred-anywhere, first.
  """
  def display_name(%Place{names: names}, locale \\ "es") when is_list(names) do
    find = fn fun -> Enum.find(names, fun) end

    name =
      find.(&(&1.is_preferred and &1.language == locale)) ||
        find.(&(&1.language == locale)) ||
        find.(& &1.is_preferred) ||
        List.first(names)

    if name, do: name.name, else: ""
  end

  @doc """
  A URL- and `xml:id`-safe form of a name. Latin letters and digits only, so it is a
  legal TEI `xml:id` in any language the corpus uses.
  """
  def slugify(name) do
    slug =
      name
      |> to_string()
      |> :unicode.characters_to_nfd_binary()
      |> String.replace(~r/[^\x00-\x7F]/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")

    if slug == "", do: "place", else: slug
  end

  # A blank slug is derived from the first name; a taken one gets -2, -3, … The suffix
  # is a last resort, not a way to hide a duplicate — the form warns before it is used.
  defp ensure_slug(attrs, place) do
    case attrs["slug"] do
      slug when is_binary(slug) and slug != "" ->
        attrs

      _ ->
        case first_name(attrs["names"]) do
          nil -> attrs
          name -> Map.put(attrs, "slug", unique_slug(slugify(name), place))
        end
    end
  end

  defp first_name(names) when is_list(names), do: names |> List.first() |> extract_name()

  defp first_name(names) when is_map(names) do
    names
    |> Enum.sort_by(fn {k, _} -> k end)
    |> List.first()
    |> then(&elem(&1 || {nil, nil}, 1))
    |> extract_name()
  end

  defp first_name(_), do: nil

  defp extract_name(%{"name" => name}) when is_binary(name) and name != "", do: name
  defp extract_name(_), do: nil

  defp unique_slug(base, place) do
    taken =
      Place
      |> where([p], like(p.slug, ^"#{base}%"))
      |> then(fn q -> if place, do: where(q, [p], p.id != ^place.id), else: q end)
      |> select([p], p.slug)
      |> Repo.all()
      |> MapSet.new()

    if MapSet.member?(taken, base) do
      Enum.find_value(2..100, "#{base}-#{System.unique_integer([:positive])}", fn n ->
        candidate = "#{base}-#{n}"
        if MapSet.member?(taken, candidate), do: nil, else: candidate
      end)
    else
      base
    end
  end

  @doc """
  True when `place` already exists under a name matching `name`. The form calls this to
  warn about a probable duplicate before the slug gets silently suffixed.
  """
  def find_by_name(name) do
    slug = slugify(name)

    PlaceName
    |> join(:inner, [n], p in assoc(n, :place))
    |> where([n], fragment("lower(?) = lower(?)", n.name, ^name))
    |> or_where([n, p], p.slug == ^slug)
    |> select([n, p], p)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> nil
      place -> get_place!(place.id)
    end
  end

  # Setting a parent that is a descendant would make `ancestors/2` walk forever. The
  # walk is bounded anyway, but a refused write is better than a truncated breadcrumb.
  defp reject_parent_cycle(changeset, %Place{id: id}) do
    case Changeset.get_change(changeset, :parent_place_id) do
      nil ->
        changeset

      parent_id ->
        if id in ancestor_ids(parent_id) do
          Changeset.add_error(changeset, :parent_place_id, "would create a loop")
        else
          changeset
        end
    end
  end

  defp ancestor_ids(nil), do: []

  defp ancestor_ids(id) do
    Enum.reduce_while(1..10, {id, []}, fn _, {current, acc} ->
      case Repo.one(from p in Place, where: p.id == ^current, select: p.parent_place_id) do
        nil -> {:halt, {nil, [current | acc]}}
        parent -> {:cont, {parent, [current | acc]}}
      end
    end)
    |> elem(1)
  end

  @doc """
  Every place, keyed by id, with names preloaded. Feeds `ancestors/2` and
  `breadcrumb/3` so a page walks the tree in memory instead of issuing a query per
  level.

  ponytail: one full load is right at a hundred places. Past a few thousand, replace
  with a recursive CTE returning only the requested place's chain.
  """
  def gazetteer do
    Place
    |> Repo.all()
    |> Repo.preload(names: from(n in PlaceName, order_by: ^@name_order))
    |> Map.new(&{&1.id, &1})
  end

  @doc "The containing places, outermost first. Bounded, so a data loop cannot hang a page."
  def ancestors(%Place{} = place, gazetteer) do
    Enum.reduce_while(1..10, {place.parent_place_id, []}, fn _, {id, acc} ->
      case id && Map.get(gazetteer, id) do
        nil -> {:halt, {nil, acc}}
        parent -> {:cont, {parent.parent_place_id, [parent | acc]}}
      end
    end)
    |> elem(1)
  end

  @doc ~S(The place and its containers, `"Bosque, Transilvania, Rumanía, Europa"`.)
  def breadcrumb(%Place{} = place, gazetteer, locale \\ "es") do
    [place | Enum.reverse(ancestors(place, gazetteer))]
    |> Enum.map(&display_name(&1, locale))
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(", ")
  end

  @doc """
  Places with any name matching `term`, in any language. Searching every variant is why
  the names are normalised: typing `Istanbul` has to find the place whose preferred
  form is `Constantinopla`, or two curators will each create one.
  """
  def search_names(term, opts \\ [])
  def search_names(term, _opts) when term in [nil, ""], do: []

  def search_names(term, opts) do
    pattern = "%#{String.replace(term, ~r/[%_]/, "")}%"

    PlaceName
    |> join(:inner, [n], p in assoc(n, :place))
    |> where([n], ilike(n.name, ^pattern))
    |> select([n, p], p)
    |> distinct(true)
    |> limit(^(opts[:limit] || 20))
    |> Repo.all()
    |> Repo.preload(names: from(n in PlaceName, order_by: ^@name_order))
    |> with_play_counts()
  end

  @doc """
  For importers. An existing slug is returned untouched — the gazetteer is curated and
  the file may be stale — so the caller can report what it left alone.
  """
  def find_or_create_by_slug(%{"slug" => slug} = attrs) do
    case Repo.get_by(Place, slug: slug) do
      nil ->
        case create_place(attrs) do
          {:ok, place} -> {:ok, get_place!(place.id), :created}
          {:error, changeset} -> {:error, changeset}
        end

      %Place{id: id} ->
        {:ok, get_place!(id), :existing}
    end
  end

  # --- Play links ---

  def list_play_places(play_id) do
    PlayPlace
    |> where([pp], pp.play_id == ^play_id)
    |> order_by([pp], asc: pp.position, asc: pp.inserted_at)
    |> Repo.all()
    |> Repo.preload(place: [names: from(n in PlaceName, order_by: ^@name_order)])
  end

  @doc """
  The play's place link `id`, place and names loaded, or nil. Scoped to the play because
  the id arrives from the browser: another play's link, a removed one or a malformed id
  is nil.
  """
  def get_play_place(play_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %PlayPlace{} = link <- Repo.get_by(PlayPlace, id: id, play_id: play_id) do
      Repo.preload(link, place: [names: from(n in PlaceName, order_by: ^@name_order)])
    else
      _ -> nil
    end
  end

  # A count would collide after an unlink: unlink leaves a gap instead of renumbering
  # (deliberately — see `renumber/1`), so a play with links at 0 and 2 has a count of 2,
  # and a naive count-based next position would tie the surviving 2. max + 1 always
  # lands past every existing position, gap or no gap.
  def link_place(play_id, place_id, attrs) do
    max_position =
      Repo.aggregate(from(pp in PlayPlace, where: pp.play_id == ^play_id), :max, :position)

    next = if is_nil(max_position), do: 0, else: max_position + 1

    attrs
    |> Map.merge(%{"play_id" => play_id, "place_id" => place_id})
    |> Map.put_new("position", next)
    |> then(&PlayPlace.changeset(%PlayPlace{}, &1))
    |> Repo.insert()
  end

  def update_play_place(%PlayPlace{} = play_place, attrs) do
    play_place
    |> PlayPlace.changeset(attrs)
    |> Repo.update()
  end

  def unlink_place(%PlayPlace{} = play_place), do: Repo.delete(play_place)

  @doc "Swaps a link with its neighbour. A move past either end is a no-op."
  def move_play_place(%PlayPlace{} = play_place, direction) when direction in [:up, :down] do
    links = list_play_places(play_place.play_id)
    index = Enum.find_index(links, &(&1.id == play_place.id))
    target = if direction == :up, do: index - 1, else: index + 1

    if is_nil(index) or target < 0 or target >= length(links) do
      :ok
    else
      neighbour = Enum.at(links, target)

      Repo.transaction(fn ->
        Repo.update!(PlayPlace.changeset(play_place, %{"position" => neighbour.position}))
        Repo.update!(PlayPlace.changeset(neighbour, %{"position" => play_place.position}))
      end)

      renumber(play_place.play_id)
      :ok
    end
  end

  @doc """
  Deletes only the links a TEI import created. Place rows are never deleted by an
  import: the gazetteer is authority data, and an orphan shows with a play count of 0.
  """
  def delete_tei_play_places(play_id) do
    Repo.delete_all(from pp in PlayPlace, where: pp.play_id == ^play_id and pp.origin == "tei")
  end

  defp renumber(play_id) do
    play_id
    |> list_play_places()
    |> Enum.with_index()
    |> Enum.each(fn {link, index} ->
      if link.position != index do
        Repo.update!(PlayPlace.changeset(link, %{"position" => index}))
      end
    end)
  end
end
