defmodule Playcode.Bibliography do
  @moduledoc """
  The corpus-wide bibliography (S4): entries shared by every play that cites them, and
  each play's links to them. Spec: docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

  An entry lives as long as some play links to it: `unlink/1` deletes it with its last
  link, so there are never orphans to find.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Playcode.Bibliography.{Citation, Entry, Link}
  alias Playcode.Catalogue.Play
  alias Playcode.Repo

  @searched [
    :analytic_author,
    :analytic_title,
    :analytic_editors,
    :monogr_author,
    :monogr_title,
    :monogr_editors
  ]

  def change_entry(%Entry{} = entry, attrs \\ %{}), do: Entry.changeset(entry, attrs)

  def get_entry!(id), do: Repo.get!(Entry, id)

  @doc """
  The play's link `id`, entry loaded, or nil. Scoped to the play because the id arrives
  from the browser: a link of another play, or no link at all, is nil.
  """
  def get_link(play_id, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Link{} = link <- Repo.get_by(Link, id: id, play_id: play_id) do
      Repo.preload(link, :entry)
    else
      _ -> nil
    end
  end

  @doc "The play's links with their entries, in the order they were added."
  def list_links(play_id) do
    Link
    |> where([l], l.play_id == ^play_id)
    |> order_by([l], asc: l.inserted_at, asc: l.id)
    |> preload(:entry)
    |> Repo.all()
  end

  @language_order ~w(es en fr it pt de)

  @doc """
  The play's bibliography as every surface shows it: `[{kind, [{language, [link]}]}]`.
  Kinds come in `Entry.kinds/0` order, only those with entries. Translations are
  subgrouped by language (`es en fr it pt de`, unknown last); every other kind has one
  group, `nil`. Within a group, links sort by their printed citation (`sort_key/1`).
  """
  def list_for_play(play_id) do
    by_kind =
      play_id
      |> list_links()
      |> Enum.sort_by(&{sort_key(&1), &1.entry_id})
      |> Enum.group_by(& &1.entry.kind)

    for kind <- Entry.kinds(), Map.has_key?(by_kind, kind) do
      {kind, subgroups(kind, by_kind[kind])}
    end
  end

  defp subgroups("translation", links) do
    by_language = Enum.group_by(links, & &1.entry.language)

    for language <- @language_order ++ [nil], Map.has_key?(by_language, language) do
      {language, by_language[language]}
    end
  end

  defp subgroups(_kind, links), do: [{nil, links}]

  @doc """
  How a link sorts: its printed citation, folded, without leading quotes or punctuation.
  A citation starts with the first name printed, so this is "alphabetical by author".
  """
  def sort_key(%Link{entry: %Entry{} = entry} = link) do
    entry
    |> Citation.plain(link)
    |> fold()
    |> String.replace(~r/^[^\p{L}\p{N}]+/u, "")
  end

  @doc "Lower case, accents removed, trimmed: how the bibliography compares text."
  def fold(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.trim()
  end

  @doc """
  A new entry and the play's link to it, in one transaction. Returns the link, entry
  loaded. `origin` is the link's: `"manual"` from a form, `"tei"` from a file.
  """
  def create_entry_for_play(play_id, entry_attrs, link_attrs \\ %{}, origin \\ "manual") do
    Multi.new()
    |> Multi.insert(:entry, Entry.changeset(%Entry{}, entry_attrs))
    |> Multi.insert(:link, fn %{entry: entry} ->
      Link.changeset(%Link{play_id: play_id, entry_id: entry.id, origin: origin}, link_attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{entry: entry, link: link}} -> {:ok, %{link | entry: entry}}
      {:error, _step, changeset, _done} -> {:error, changeset}
    end
  end

  @doc "Links an entry another play already has; `origin` as for `create_entry_for_play/4`."
  def link_entry(play_id, entry_id, attrs \\ %{}, origin \\ "manual") do
    %Link{play_id: play_id, entry_id: entry_id, origin: origin}
    |> Link.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  The entries Playcode already has for a TEI file's references, as
  `%{description => entry_id}`: an entry whose `Entry.description/1` is identical to one of
  `descriptions`. Of identical entries, the one `play_id` links wins, else the oldest.
  Candidates are the entries with one of the descriptions' titles, as `Entry.collapse/1`
  writes them, compared in Elixir: Postgres's `\\s` misses the non-breaking spaces FileMaker
  left in titles. Then they are compared in full; an entry with no title at all is always a
  candidate. `play_id` is nil for a play not imported yet.
  """
  def identical_entries([], _play_id), do: %{}

  def identical_entries(descriptions, play_id) do
    wanted = MapSet.new(descriptions)

    titles =
      descriptions
      |> Enum.flat_map(&[&1.monogr_title, &1.analytic_title])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    candidates =
      for {id, monogr, analytic} <-
            Repo.all(from e in Entry, select: {e.id, e.monogr_title, e.analytic_title}),
          own = [Entry.collapse(monogr), Entry.collapse(analytic)],
          own == [nil, nil] or Enum.any?(own, &(&1 in titles)),
          do: id

    linked = linked_entry_ids(play_id)

    from(e in Entry, where: e.id in ^candidates, order_by: [asc: e.inserted_at, asc: e.id])
    |> Repo.all()
    |> Enum.map(&{Entry.description(&1), &1.id})
    |> Enum.filter(&MapSet.member?(wanted, elem(&1, 0)))
    |> Enum.sort_by(&(elem(&1, 1) not in linked))
    |> Enum.reduce(%{}, fn {description, id}, found -> Map.put_new(found, description, id) end)
  end

  def update_entry(%Entry{} = entry, attrs), do: entry |> Entry.changeset(attrs) |> Repo.update()
  def update_link(%Link{} = link, attrs), do: link |> Link.changeset(attrs) |> Repo.update()

  @doc "The ids of the entries a play links; none for nil, a play not imported yet."
  def linked_entry_ids(nil), do: []

  def linked_entry_ids(play_id),
    do: from(l in Link, where: l.play_id == ^play_id, select: l.entry_id) |> Repo.all()

  @doc """
  Removes a play's link. `{:ok, :deleted}` when it was the entry's last, which goes with
  it; `{:ok, :unlinked}` otherwise.
  """
  # ponytail: two curators removing an entry's last two links in the same instant can each
  # still see the other's and leave an orphan; lock the entry row if that ever happens.
  def unlink(%Link{} = link) do
    Repo.transaction(fn ->
      Repo.delete!(link)

      if Repo.exists?(from l in Link, where: l.entry_id == ^link.entry_id) do
        :unlinked
      else
        Repo.delete_all(from e in Entry, where: e.id == ^link.entry_id)
        :deleted
      end
    end)
  end

  @doc "Every play linked to an entry, archived ones included, by code."
  def plays_for_entry(entry_id) do
    Play
    |> join(:inner, [p], l in Link, on: l.play_id == p.id)
    |> where([_p, l], l.entry_id == ^entry_id)
    |> order_by([p], p.code)
    |> select([p], %{id: p.id, code: p.code, title: p.title})
    |> Repo.all()
  end

  @doc "How many plays link each entry: `%{entry_id => count}`."
  def link_counts([]), do: %{}

  def link_counts(entry_ids) do
    Link
    |> where([l], l.entry_id in ^entry_ids)
    |> group_by([l], l.entry_id)
    |> select([l], {l.entry_id, count(l.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Entries whose authors, editors or titles contain `term`, leaving out those `play_id`
  already has. `%` and `_` match themselves; a blank term finds nothing.
  """
  def search_entries(term, play_id, limit \\ 10) do
    case term |> to_string() |> String.trim() |> String.replace(["%", "_"], "") do
      "" -> []
      _ -> do_search(String.trim(term), play_id, limit)
    end
  end

  defp do_search(term, play_id, limit) do
    pattern = "%" <> String.replace(term, ~r/([\\%_])/, "\\\\\\1") <> "%"
    on_play = from l in Link, where: l.play_id == ^play_id, select: l.entry_id

    matches =
      Enum.reduce(@searched, dynamic(false), fn field, acc ->
        dynamic([e], ^acc or ilike(field(e, ^field), ^pattern))
      end)

    Entry
    |> where([e], e.id not in subquery(on_play))
    |> where(^matches)
    |> order_by([e], asc: e.monogr_title, asc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end
end
