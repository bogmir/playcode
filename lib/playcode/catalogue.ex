defmodule Playcode.Catalogue do
  @moduledoc """
  Plays and their metadata: the play row, its editors, sources and editorial notes.
  The text lives in `Playcode.PlayContent`.

  Every play read takes the same options. Archived plays are hidden unless the caller
  passes `archived: true` (only them) or `include_deleted: true` (both), and
  `complete: true` hides drafts too, for a reader who may not see them. The `*_with_all!`
  reads also preload what a play's pages show, each list in a fixed order, with the
  parent and derived plays under the same options.
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

  @doc """
  The plays under the read options, sorted by `:sort`: `:title_sort` (the default),
  `:author_sort` or `:code`. `:search` matches title, author or code, case-insensitively;
  `:page` returns that page of `:per_page` plays (25 by default).
  """
  def list_plays(opts \\ []) do
    query =
      Play
      |> scope(opts)
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

  @doc """
  How many plays `list_plays/1` finds for the same options, all pages together.
  """
  def count_plays(opts \\ []) do
    Play
    |> scope(opts)
    |> apply_search(opts[:search])
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  The play `id` under the read options. Raises `Ecto.NoResultsError`, which a page or a
  controller answers with a 404, when there is none.
  """
  def get_play!(id, opts \\ []) do
    Play |> scope(opts) |> Repo.get!(id)
  end

  @doc """
  As `get_play!/2`, by code.
  """
  def get_play_by_code!(code, opts \\ []) do
    Play |> scope(opts) |> Repo.get_by!(code: code)
  end

  @doc """
  As `get_play!/2`, with what the play's pages show preloaded.
  """
  def get_play_with_all!(id, opts \\ []) do
    Play
    |> scope(opts)
    |> Repo.get!(id)
    |> with_all(opts)
  end

  @doc """
  As `get_play_with_all!/2`, by code.
  """
  def get_play_by_code_with_all!(code, opts \\ []) do
    Play
    |> scope(opts)
    |> Repo.get_by!(code: code)
    |> with_all(opts)
  end

  @doc """
  Creates a play from every metadata column `Play.changeset/2` casts. The TEI importer
  uses it; the admin form uses `create_play_from_form/1`.
  """
  def create_play(attrs \\ %{}) do
    %Play{}
    |> Play.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a play's metadata. `deleted_at` and `content_version` are not cast: archiving
  goes through `delete_play/1`, and Postgres moves the version.
  """
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

  @doc """
  Undoes `delete_play/1`: every read shows the play again.
  """
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

  @doc """
  The admin form's changeset (`Play.form_changeset/2`).
  """
  def change_play_form(%Play{} = play, attrs \\ %{}) do
    Play.form_changeset(play, attrs)
  end

  @doc """
  Creates a play from the admin form.
  """
  def create_play_from_form(attrs) do
    %Play{}
    |> Play.form_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a play from the admin form.
  """
  def update_play_from_form(%Play{} = play, attrs) do
    play
    |> Play.form_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  The code the new-play form offers: `EMOTHE` and one more than the highest number any
  `EMOTHE`, `CTCE` or `AL` code carries, archived plays included, padded to four digits.
  """
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

  @doc """
  The play's editors, in their order.
  """
  def list_play_editors(play_id) do
    PlayEditor
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc """
  The play's editor `id`, or nil. Scoped to the play because the id arrives from the
  browser: another play's editor, a deleted one or a malformed id is nil.
  """
  def get_play_editor(play_id, id), do: get_play_row(PlayEditor, play_id, id)

  @doc """
  Creates an editor; `attrs` carry its `play_id`.
  """
  def create_play_editor(attrs) do
    %PlayEditor{}
    |> PlayEditor.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an editor.
  """
  def update_play_editor(%PlayEditor{} = editor, attrs) do
    editor
    |> PlayEditor.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an editor.
  """
  def delete_play_editor(%PlayEditor{} = editor) do
    Repo.delete(editor)
  end

  @doc """
  An editor's changeset, for a form.
  """
  def change_play_editor(%PlayEditor{} = editor, attrs \\ %{}) do
    PlayEditor.changeset(editor, attrs)
  end

  # --- Sources ---

  @doc """
  The play's bibliographic sources, in their order.
  """
  def list_play_sources(play_id) do
    PlaySource
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc """
  As `get_play_editor/2`, for a source.
  """
  def get_play_source(play_id, id), do: get_play_row(PlaySource, play_id, id)

  @doc """
  Creates a source; `attrs` carry its `play_id`.
  """
  def create_play_source(attrs) do
    %PlaySource{}
    |> PlaySource.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a source.
  """
  def update_play_source(%PlaySource{} = source, attrs) do
    source
    |> PlaySource.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a source.
  """
  def delete_play_source(%PlaySource{} = source) do
    Repo.delete(source)
  end

  @doc """
  A source's changeset, for a form.
  """
  def change_play_source(%PlaySource{} = source, attrs \\ %{}) do
    PlaySource.changeset(source, attrs)
  end

  # --- Editorial Notes ---

  @doc """
  The play's front-matter notes, in their order.
  """
  def list_play_editorial_notes(play_id) do
    PlayEditorialNote
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc """
  As `get_play_editor/2`, for an editorial note.
  """
  def get_play_editorial_note(play_id, id), do: get_play_row(PlayEditorialNote, play_id, id)

  @doc """
  Creates an editorial note; `attrs` carry its `play_id`.
  """
  def create_play_editorial_note(attrs) do
    %PlayEditorialNote{}
    |> PlayEditorialNote.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an editorial note.
  """
  def update_play_editorial_note(%PlayEditorialNote{} = note, attrs) do
    note
    |> PlayEditorialNote.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an editorial note.
  """
  def delete_play_editorial_note(%PlayEditorialNote{} = note) do
    Repo.delete(note)
  end

  @doc """
  An editorial note's changeset, for a form.
  """
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

  @doc """
  How many groups `list_plays_grouped/1` finds for the same options, all pages together.
  """
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

  defp get_play_row(schema, play_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(schema, id: id, play_id: play_id)
      :error -> nil
    end
  end

  # Everything a play's pages show, each list in a fixed order, so the same data always
  # renders the same page. Related plays follow the same `opts` as the play itself, so a
  # page never links to a relative its reader could not open.
  defp with_all(play, opts) do
    Repo.preload(play, [
      :statistic,
      parent_play: scope(Play, opts),
      derived_plays: Play |> scope(opts) |> order_by([d], asc: d.title_sort, asc: d.title),
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
  # `complete: true` hides drafts too, for readers who may not see them.
  defp scope(query, opts) do
    query =
      cond do
        opts[:archived] -> where(query, [p], not is_nil(p.deleted_at))
        opts[:include_deleted] -> query
        true -> where(query, [p], is_nil(p.deleted_at))
      end

    apply_complete(query, opts[:complete])
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
