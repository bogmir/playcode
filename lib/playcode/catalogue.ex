defmodule Playcode.Catalogue do
  @moduledoc """
  The Catalogue context manages plays and their metadata.
  """

  import Ecto.Query
  alias Playcode.Repo
  alias Playcode.Catalogue.{Play, PlayEditor, PlaySource, PlayEditorialNote}
  alias Playcode.Places.{PlaceName, PlayPlace}

  # --- Plays ---

  @per_page 25

  @origins ~w(tei manual filemaker)

  @doc """
  Where a play's editors, sources and editorial notes came from.

  A TEI re-import replaces only the rows it created itself (`"tei"`); anything a
  researcher typed or a FileMaker slice wrote survives untouched.
  """
  def origins, do: @origins

  def list_plays(opts \\ []) do
    query =
      Play
      |> scope(opts)
      |> apply_complete(opts[:complete])
      |> apply_search(opts[:search])
      |> apply_sort(opts[:sort] || :title_sort)

    case opts[:page] do
      nil ->
        Repo.all(query)

      page ->
        per_page = opts[:per_page] || @per_page
        offset = (page - 1) * per_page

        query
        |> limit(^per_page)
        |> offset(^offset)
        |> Repo.all()
    end
  end

  def count_plays(opts \\ []) do
    Play
    |> scope(opts)
    |> apply_search(opts[:search])
    |> Repo.aggregate(:count, :id)
  end

  def get_play!(id, opts \\ []) do
    Play |> scope(opts) |> Repo.get!(id)
  end

  def get_play_by_code!(code, opts \\ []) do
    Play |> scope(opts) |> Repo.get_by!(code: code)
  end

  def get_play_with_all!(id, opts \\ []) do
    Play
    |> scope(opts)
    |> Repo.get!(id)
    |> with_all()
  end

  def get_play_by_code_with_all!(code, opts \\ []) do
    Play
    |> scope(opts)
    |> Repo.get_by!(code: code)
    |> with_all()
  end

  def create_play(attrs \\ %{}) do
    %Play{}
    |> Play.changeset(attrs)
    |> Repo.insert()
  end

  def update_play(%Play{} = play, attrs) do
    play
    |> Play.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Archives a play. The row, its content and its history stay; every read hides it
  unless asked for with `include_deleted: true`, and its code stays reserved so a
  re-import updates this row instead of creating a second one.
  """
  def delete_play(%Play{} = play) do
    play
    |> Ecto.Changeset.change(deleted_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  def restore_play(%Play{} = play) do
    play |> Ecto.Changeset.change(deleted_at: nil) |> Repo.update()
  end

  @doc "Destroys a play and every row that hangs off it. There is no undo."
  def purge_play(%Play{} = play), do: Repo.delete(play)

  @doc "Recomputes and updates play.verse_count from the actual verse_line elements."
  def update_verse_count(play_id) do
    alias Playcode.PlayContent.Element

    # Count distinct line numbers rather than raw elements,
    # because split verses (shared lines between characters) share the same number
    count =
      Element
      |> where(play_id: ^play_id)
      |> where(type: "verse_line")
      |> where([e], not is_nil(e.line_number))
      |> select([e], count(e.line_number, :distinct))
      |> Repo.one()

    Play
    |> Repo.get!(play_id)
    |> Ecto.Changeset.change(%{verse_count: count, is_verse: count > 0})
    |> Repo.update()
  end

  def change_play(%Play{} = play, attrs \\ %{}) do
    Play.changeset(play, attrs)
  end

  def change_play_form(%Play{} = play, attrs \\ %{}) do
    Play.form_changeset(play, attrs)
  end

  def create_play_from_form(attrs) do
    %Play{}
    |> Play.form_changeset(attrs)
    |> Repo.insert()
  end

  def update_play_from_form(%Play{} = play, attrs) do
    play
    |> Play.form_changeset(attrs)
    |> Repo.update()
  end

  def next_play_code do
    max_number =
      Play
      |> select([p], p.code)
      |> Repo.all()
      |> Enum.map(fn code ->
        case Regex.run(~r/^(?:EMOTHE|CTCE|AL)(\d+)/i, code || "") do
          [_, num_str] -> String.to_integer(num_str)
          _ -> 0
        end
      end)
      |> Enum.max(fn -> 0 end)

    next = max_number + 1
    "EMOTHE#{String.pad_leading(Integer.to_string(next), 4, "0")}"
  end

  # --- Editors ---

  def list_play_editors(play_id) do
    PlayEditor
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  def get_play_editor!(id), do: Repo.get!(PlayEditor, id)

  def create_play_editor(attrs) do
    %PlayEditor{}
    |> PlayEditor.changeset(attrs)
    |> Repo.insert()
  end

  def update_play_editor(%PlayEditor{} = editor, attrs) do
    editor
    |> PlayEditor.changeset(attrs)
    |> Repo.update()
  end

  def delete_play_editor(%PlayEditor{} = editor) do
    Repo.delete(editor)
  end

  def change_play_editor(%PlayEditor{} = editor, attrs \\ %{}) do
    PlayEditor.changeset(editor, attrs)
  end

  # --- Sources ---

  def list_play_sources(play_id) do
    PlaySource
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  def get_play_source!(id), do: Repo.get!(PlaySource, id)

  def create_play_source(attrs) do
    %PlaySource{}
    |> PlaySource.changeset(attrs)
    |> Repo.insert()
  end

  def update_play_source(%PlaySource{} = source, attrs) do
    source
    |> PlaySource.changeset(attrs)
    |> Repo.update()
  end

  def delete_play_source(%PlaySource{} = source) do
    Repo.delete(source)
  end

  def change_play_source(%PlaySource{} = source, attrs \\ %{}) do
    PlaySource.changeset(source, attrs)
  end

  # --- Editorial Notes ---

  def list_play_editorial_notes(play_id) do
    PlayEditorialNote
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  def get_play_editorial_note!(id), do: Repo.get!(PlayEditorialNote, id)

  def create_play_editorial_note(attrs) do
    %PlayEditorialNote{}
    |> PlayEditorialNote.changeset(attrs)
    |> Repo.insert()
  end

  def update_play_editorial_note(%PlayEditorialNote{} = note, attrs) do
    note
    |> PlayEditorialNote.changeset(attrs)
    |> Repo.update()
  end

  def delete_play_editorial_note(%PlayEditorialNote{} = note) do
    Repo.delete(note)
  end

  def change_play_editorial_note(%PlayEditorialNote{} = note, attrs \\ %{}) do
    PlayEditorialNote.changeset(note, attrs)
  end

  @doc """
  Lists root plays (no parent) with their derived plays preloaded.
  Search matches root or derived plays; if a derived play matches, its parent group is included.
  """
  def list_plays_grouped(opts \\ []) do
    query =
      Play
      |> scope(opts)
      |> where([p], is_nil(p.parent_play_id))
      |> where([p], p.is_complete == true)
      |> apply_search_grouped(opts[:search])
      |> apply_sort(opts[:sort] || :title_sort)

    plays =
      case opts[:page] do
        nil ->
          Repo.all(query)

        page ->
          per_page = opts[:per_page] || @per_page
          offset = (page - 1) * per_page

          query
          |> limit(^per_page)
          |> offset(^offset)
          |> Repo.all()
      end

    Repo.preload(plays,
      derived_plays:
        from(d in Play,
          where: is_nil(d.deleted_at),
          where: d.is_complete == true,
          order_by: [asc: d.title_sort, asc: d.title]
        )
    )
  end

  def count_plays_grouped(opts \\ []) do
    Play
    |> scope(opts)
    |> where([p], is_nil(p.parent_play_id))
    |> where([p], p.is_complete == true)
    |> apply_search_grouped(opts[:search])
    |> Repo.aggregate(:count, :id)
  end

  defp apply_search_grouped(query, nil), do: query
  defp apply_search_grouped(query, ""), do: query

  defp apply_search_grouped(query, search) do
    pattern = "%#{search}%"

    derived_match =
      from(d in Play,
        where: is_nil(d.deleted_at),
        where: not is_nil(d.parent_play_id),
        where: d.is_complete == true,
        where:
          ilike(d.title, ^pattern) or
            ilike(d.author_name, ^pattern) or
            ilike(d.code, ^pattern),
        select: d.parent_play_id
      )

    from p in query,
      where:
        ilike(p.title, ^pattern) or
          ilike(p.author_name, ^pattern) or
          ilike(p.code, ^pattern) or
          p.id in subquery(derived_match)
  end

  # --- Private ---

  # Everything a play's pages show, each list in a fixed order, so the same data always
  # renders the same page.
  defp with_all(play) do
    Repo.preload(play, [
      :statistic,
      :parent_play,
      derived_plays: from(d in Play, order_by: [asc: d.title_sort, asc: d.title]),
      editors: from(e in PlayEditor, order_by: e.position),
      sources: from(s in PlaySource, order_by: s.position),
      editorial_notes: from(n in PlayEditorialNote, order_by: n.position),
      play_places:
        {from(pp in PlayPlace, order_by: pp.position),
         [place: [names: from(n in PlaceName, order_by: [asc: n.position, asc: n.id])]]}
    ])
  end

  # Archived plays are invisible everywhere unless a caller explicitly asks for them:
  # `archived: true` for the archive listing, `include_deleted: true` for both at once.
  defp scope(query, opts) do
    cond do
      opts[:archived] -> where(query, [p], not is_nil(p.deleted_at))
      opts[:include_deleted] -> query
      true -> where(query, [p], is_nil(p.deleted_at))
    end
  end

  defp apply_complete(query, true), do: where(query, [p], p.is_complete == true)
  defp apply_complete(query, _), do: query

  defp apply_search(query, nil), do: query
  defp apply_search(query, ""), do: query

  defp apply_search(query, search) do
    pattern = "%#{search}%"

    from p in query,
      where:
        ilike(p.title, ^pattern) or
          ilike(p.author_name, ^pattern) or
          ilike(p.code, ^pattern)
  end

  defp apply_sort(query, :title_sort) do
    from p in query, order_by: [asc: p.title_sort, asc: p.title]
  end

  defp apply_sort(query, :author_sort) do
    from p in query, order_by: [asc: p.author_sort, asc: p.title_sort]
  end

  defp apply_sort(query, :code) do
    from p in query, order_by: [asc: p.code]
  end

  defp apply_sort(query, _), do: query
end
