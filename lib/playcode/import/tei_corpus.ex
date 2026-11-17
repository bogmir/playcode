defmodule Playcode.Import.TeiCorpus do
  @moduledoc """
  Bulk-imports the TEI files we hold locally, one per play code.

  The same file often exists in more than one fixture directory; `collect_files/1`
  keeps the first one it sees for each code so a re-run stays idempotent.
  """

  import Ecto.Query

  alias Playcode.ActivityLog
  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.Export.{StaticSite, TeiXml}
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
  Under `resume: true` a play imported since its file was written is skipped too, so a
  forced run that stopped part way carries on where it stopped when run again. A play
  with rows from its file edited since their import (`TeiImport.preview_import/2`'s
  `edited`) is kept as it is, `{:kept, code, count}`, unless `overwrite_edits: true`.
  `on_result` is called with each file's result as it is reached, so a long run can
  report as it goes.
  """
  def import_all(files, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    overwrite_edits = Keyword.get(opts, :overwrite_edits, false)
    on_result = Keyword.get(opts, :on_result, fn _result -> :ok end)
    existing = existing_codes()
    imported_at = if Keyword.get(opts, :resume, false), do: last_import_by_code(), else: %{}

    Enum.map(files, fn {code, path} ->
      exists = MapSet.member?(existing, code)

      result =
        cond do
          (not force and exists) or imported_since_written?(imported_at[code], path) ->
            {:skipped, code}

          count = exists and not overwrite_edits and rows_edited(path) ->
            {:kept, code, count}

          true ->
            import_one(code, path)
        end

      on_result.(result)
      result
    end)
  end

  # The file's rows edited by hand since their import, nil for none or an unreadable file
  # (which the import then reports).
  defp rows_edited(path) do
    case TeiImport.preview_import(path, numbering: false) do
      {:ok, %{edited: count}} when count > 0 -> count
      _none -> nil
    end
  end

  @doc """
  What importing `files` would do, reported as `{:info | :error, line}`s as each file is
  read, then a summary. Writes nothing. Under `force: true` a play already imported
  would be re-imported, and its line says what that replaces and keeps, and how many hand
  edits to its text since its last import it would undo, unless rows from its file were
  edited since their import: `import_all/2` keeps such a play without
  `overwrite_edits: true`, and its line says so. A play that would be imported
  lists the references it would gain and those it would skip, one line each.
  """
  def dry_run(files, opts, report) do
    counts =
      Enum.reduce(files, %{}, fn {code, path}, counts ->
        {outcome, lines} = preview_lines(code, TeiImport.preview_import(path), opts)
        Enum.each(lines, report)
        Map.update(counts, outcome, 1, &(&1 + 1))
      end)

    count = &Map.get(counts, &1, 0)
    edited = count.(:edited)
    kept = count.(:kept)

    report.(
      {:info,
       "\ndry run, nothing written — #{count.(:new)} new, " <>
         "#{count.(:existing) + edited + kept} already imported" <>
         if(edited > 0, do: " (#{edited} with hand edits since their last import)", else: "") <>
         if(kept > 0, do: ", #{kept} kept for their edits", else: "") <>
         ", #{count.(:unreadable)} unreadable"}
    )
  end

  defp preview_lines(code, {:ok, %{existing: nil} = preview}, _opts),
    do:
      {:new,
       [
         {:info, "  #{code}  new" <> same_number(preview) <> adds(preview) <> numbering(preview)}
         | added(preview)
       ]}

  defp preview_lines(code, {:ok, preview}, opts) do
    cond do
      not Keyword.get(opts, :force, false) ->
        {:existing, [{:info, "  #{code}  already imported, would be skipped"}]}

      preview.edited > 0 and not Keyword.get(opts, :overwrite_edits, false) ->
        {:kept, [{:info, "  #{code}  would be skipped" <> kept(preview.edited)}]}

      true ->
        replace_lines(code, preview)
    end
  end

  defp preview_lines(code, {:error, reason}, _opts),
    do: {:unreadable, [{:error, "  #{code}: #{inspect(reason)}"}]}

  # Matches the fly reimport task's `@needs_a_look`.
  defp same_number(%{same_number: nil}), do: ""
  defp same_number(%{same_number: code}), do: ", but #{code} holds its number"

  # Matches the fly reimport task's `@needs_a_look`, as `edited/1` does.
  defp kept(count), do: edited(count) <> " (--overwrite-edits replaces them)"

  defp replace_lines(code, preview) do
    undone = hand_edits(preview.existing.id)
    outcome = if undone > 0, do: :edited, else: :existing

    line =
      "  #{code}  " <>
        replaces(preview, undone) <> adds(preview) <> numbering(preview) <> removes_text(preview)

    {outcome, [{:info, line} | added(preview)]}
  end

  defp removes_text(%{removes_text: nil}), do: ""
  defp removes_text(%{removes_text: 1}), do: "; no text: its only line would be removed"
  defp removes_text(%{removes_text: n}), do: "; no text: #{n} lines would be removed"

  # The numbering rule the import would settle (`Numbering.describe/1`).
  defp numbering(preview), do: ", numbering #{preview.numbering}"

  @doc """
  Writes each play's TEI (`TeiXml.generate/1`, its download) to `dir/CODE.xml`, the
  corpus's naming, or only the play `code` names (its full or short code). Archived plays
  are left out. `{:ok, count}`, or `{:error, :no_play}` for a code no play has.
  """
  def export(dir, code \\ nil) do
    plays =
      Enum.filter(
        Catalogue.list_plays(),
        &(is_nil(code) or Play.short_code(&1.code) == Play.short_code(code))
      )

    if code && plays == [] do
      {:error, :no_play}
    else
      File.mkdir_p!(dir)

      for play <- plays do
        xml = play.id |> Catalogue.get_play_with_all!() |> TeiXml.generate()
        File.write!(Path.join(dir, StaticSite.safe_code!(play.code) <> ".xml"), xml)
      end

      {:ok, length(plays)}
    end
  end

  @doc """
  Imports `files` as `import_all/2` does, calling `report` with an `{:info | :error,
  line}` for each failure as it happens and for the summary at the end.
  """
  def run(files, opts, report) do
    on_result = fn
      {:error, code, reason} -> report.({:error, "  #{code}: #{inspect(reason)}"})
      {:kept, code, count} -> report.({:info, "  #{code}  skipped" <> kept(count)})
      _other -> :ok
    end

    results = import_all(files, Keyword.put(opts, :on_result, on_result))
    count = fn pattern -> Enum.count(results, pattern) end

    report.(
      {:info,
       "imported #{count.(&match?({:ok, _, _}, &1))}, " <>
         "skipped #{count.(&(match?({:skipped, _}, &1) or match?({:kept, _, _}, &1)))}, " <>
         "failed #{count.(&match?({:error, _, _}, &1))}"}
    )
  end

  defp adds(preview) do
    [adds: preview.bibliography_adds, skips: preview.bibliography_skips]
    |> Enum.reject(&(elem(&1, 1) == []))
    |> Enum.map_join(fn {verb, refs} -> ", #{verb} #{length(refs)} reference(s)" end)
    |> Kernel.<>(split_verses(preview.split_verses))
  end

  defp split_verses([]), do: ""
  defp split_verses(parts), do: ", #{length(parts)} split-verse part(s) out of order"

  defp added(preview) do
    for(citation <- preview.bibliography_adds, do: {:info, "      + #{citation}"}) ++
      for(citation <- preview.bibliography_skips, do: {:info, "      - #{citation}"}) ++
      for(part <- preview.split_verses, do: {:info, "      ! " <> split_verse(part)})
  end

  defp split_verse(%{line_id: id, part: part, text: text, problem: problem}) do
    what = Map.fetch!(%{"I" => "first", "M" => "middle", "F" => "last"}, part)
    why = if problem == :never_completed, do: "never completed", else: "completes no verse"
    "#{id || "?"} #{what} part, #{why}: #{text}"
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

  defp imported_since_written?(nil, _path), do: false

  defp imported_since_written?(imported_at, path),
    do: DateTime.to_unix(imported_at) >= File.stat!(path, time: :posix).mtime

  defp last_import_by_code do
    from(p in Play, join: i in subquery(last_imports()), on: i.play_id == p.id)
    |> select([p, i], {p.code, i.at})
    |> Repo.all()
    |> Map.new(fn {code, at} -> {Play.short_code(code), at} end)
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
