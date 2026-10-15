defmodule Playcode.Import.TeiCorpus do
  @moduledoc """
  Bulk-imports the TEI files we hold locally, one per play code.

  The same file often exists in more than one fixture directory; `collect_files/1`
  keeps the first one it sees for each code so a re-run stays idempotent.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Catalogue.Play
  alias Playcode.Import.TeiImport
  alias Playcode.Repo

  require Logger

  # doc/tei_corpus (git-ignored) is the production corpus and goes first, so its copies
  # win over the older ones some fixtures hold.
  @default_dirs ["doc/tei_corpus", "test/fixtures", "test/fixtures/tei_files"]

  def default_dirs, do: @default_dirs

  @doc """
  Every .xml file in the given directories, one per code, sorted by code. Their
  subdirectories are not read: `test/fixtures/filemaker/` holds FileMaker's exports.
  """
  def collect_files(dirs) do
    dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "*.xml")))
    |> Enum.reduce(%{}, fn path, acc ->
      Map.put_new(acc, path |> Path.basename(".xml") |> Play.short_code(), path)
    end)
    |> Enum.sort()
  end

  # Edits to a play's text by hand, as the content editor and the Notes tab log them. A
  # forced re-import replaces all of these.
  @text_edits ~w(element division character note)

  @doc """
  Imports each file. Codes already in the database are skipped unless `force: true`.
  `on_result` is called with each file's result as it is reached, so a long run can
  report as it goes.
  """
  def import_all(files, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    on_result = Keyword.get(opts, :on_result, fn _result -> :ok end)
    existing = existing_codes()

    Enum.map(files, fn {code, path} ->
      result =
        if not force and MapSet.member?(existing, code),
          do: {:skipped, code},
          else: import_one(code, path)

      on_result.(result)
      result
    end)
  end

  @doc """
  What importing `files` would do, reported as `{:info | :error, line}`s as each file is
  read, then a summary. Writes nothing. Under `force: true` a play already imported
  would be re-imported, and its line says what that replaces and keeps, and how many hand
  edits to its text since its last import it would undo. A play that would be imported
  lists the references it would gain and those it would skip, one line each.
  """
  def dry_run(files, opts, report) do
    force = Keyword.get(opts, :force, false)

    counts =
      Enum.reduce(files, %{}, fn {code, path}, counts ->
        {outcome, lines} = preview_lines(code, TeiImport.preview_import(path), force)
        Enum.each(lines, report)
        Map.update(counts, outcome, 1, &(&1 + 1))
      end)

    count = &Map.get(counts, &1, 0)
    edited = count.(:edited)

    report.(
      {:info,
       "\ndry run, nothing written — #{count.(:new)} new, " <>
         "#{count.(:existing) + edited} already imported" <>
         if(edited > 0, do: " (#{edited} with hand edits since their last import)", else: "") <>
         ", #{count.(:unreadable)} unreadable"}
    )
  end

  defp preview_lines(code, {:ok, %{existing: nil} = preview}, _force),
    do: {:new, [{:info, "  #{code}  new" <> adds(preview)} | added(preview)]}

  defp preview_lines(code, {:ok, _preview}, false),
    do: {:existing, [{:info, "  #{code}  already imported, would be skipped"}]}

  defp preview_lines(code, {:ok, preview}, true) do
    undone = hand_edits(preview.existing.id)
    outcome = if undone > 0, do: :edited, else: :existing
    line = "  #{code}  " <> replaces(preview, undone) <> adds(preview)
    {outcome, [{:info, line} | added(preview)]}
  end

  defp preview_lines(code, {:error, reason}, _force),
    do: {:unreadable, [{:error, "  #{code}: #{inspect(reason)}"}]}

  @doc """
  Imports `files` as `import_all/2` does, calling `report` with an `{:info | :error,
  line}` for each failure as it happens and for the summary at the end.
  """
  def run(files, opts, report) do
    on_result = fn
      {:error, code, reason} -> report.({:error, "  #{code}: #{inspect(reason)}"})
      _other -> :ok
    end

    results = import_all(files, Keyword.put(opts, :on_result, on_result))
    count = fn pattern -> Enum.count(results, pattern) end

    report.(
      {:info,
       "imported #{count.(&match?({:ok, _, _}, &1))}, " <>
         "skipped #{count.(&match?({:skipped, _}, &1))}, " <>
         "failed #{count.(&match?({:error, _, _}, &1))}"}
    )
  end

  defp adds(preview) do
    [adds: preview.bibliography_adds, skips: preview.bibliography_skips]
    |> Enum.reject(&(elem(&1, 1) == []))
    |> Enum.map_join(fn {verb, refs} -> ", #{verb} #{length(refs)} reference(s)" end)
  end

  defp added(preview) do
    for(citation <- preview.bibliography_adds, do: {:info, "      + #{citation}"}) ++
      for(citation <- preview.bibliography_skips, do: {:info, "      - #{citation}"})
  end

  defp replaces(preview, undone) do
    "replaces #{preview.replaces.divisions} division(s), " <>
      "#{preview.replaces.elements} element(s), " <>
      "#{preview.replaces.characters} character(s), " <>
      "#{TeiImport.mixed_ownership_total(preview.replaces)} TEI record(s)" <>
      edited(preview.edited) <> keeps(preview) <> undoes(undone)
  end

  defp edited(0), do: ""
  defp edited(n), do: ", #{n} row(s) from the file edited since their import"

  defp keeps(preview) do
    kept = TeiImport.mixed_ownership_total(preview.preserves)
    restored = if preview.archived, do: ", restores it from the archive", else: ""

    case kept do
      0 -> restored
      n -> ", keeps #{n} hand-entered record(s)" <> restored
    end
  end

  defp undoes(0), do: ""
  defp undoes(n), do: ", undoes #{n} hand edit(s) to its text"

  # The logged edits to a play's text after its last logged import, or ever, for a play
  # with no import logged. See @text_edits.
  defp hand_edits(play_id) do
    from(a in ActivityLog.Entry,
      left_join: i in subquery(last_imports()),
      on: i.play_id == a.play_id,
      where: a.play_id == ^play_id and a.resource_type in ^@text_edits,
      where: is_nil(i.at) or a.inserted_at > i.at
    )
    |> Repo.aggregate(:count)
  end

  # Each play's last logged import (import_one/2 logs it).
  defp last_imports do
    from a in ActivityLog.Entry,
      where: a.action == "import" and a.resource_type == "play",
      group_by: a.play_id,
      select: %{play_id: a.play_id, at: max(a.inserted_at)}
  end

  # The parser raises on some malformed files (over-long fields, Postgrex errors);
  # one bad file must not abort the whole corpus run.
  defp import_one(code, path) do
    case TeiImport.import_file(path) do
      {:ok, play} ->
        # The mark hand_edits/1 counts from, as the admin import page leaves one too.
        ActivityLog.log!(%{
          play_id: play.id,
          action: "import",
          resource_type: "play",
          resource_id: play.id,
          metadata: %{"file" => Path.basename(path)}
        })

        {:ok, code, play}

      {:error, reason} ->
        failure(code, reason)
    end
  rescue
    error -> failure(code, error)
  end

  defp failure(code, reason) do
    Logger.warning("TEI import failed for #{code}: #{inspect(reason)}")
    {:error, code, reason}
  end

  defp existing_codes do
    Play
    |> select([p], p.code)
    |> Repo.all()
    |> Enum.map(&Play.short_code/1)
    |> MapSet.new()
  end
end
