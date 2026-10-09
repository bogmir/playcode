defmodule Playcode.Import.TeiCorpus do
  @moduledoc """
  Bulk-imports the TEI files we hold locally, one per play code.

  The same file often exists in more than one fixture directory; `collect_files/1`
  keeps the first one it sees for each code so a re-run stays idempotent.
  """

  import Ecto.Query

  alias Playcode.Catalogue.Play
  alias Playcode.Import.TeiParser
  alias Playcode.Repo

  require Logger

  # doc/tei_corpus (git-ignored) is the production corpus and goes first, so its copies
  # win over the older ones some fixtures hold.
  @default_dirs ["doc/tei_corpus", "test/fixtures", "test/fixtures/tei_files"]

  def default_dirs, do: @default_dirs

  @doc "The FileMaker code hiding at the front of a play code or filename stem."
  def base_code(code), do: code |> String.split("_") |> List.first()

  @doc "Every .xml file under the given directories, one per code, sorted by code."
  def collect_files(dirs) do
    dirs
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*.xml")))
    |> Enum.reduce(%{}, fn path, acc ->
      Map.put_new(acc, path |> Path.basename(".xml") |> base_code(), path)
    end)
    |> Enum.sort()
  end

  @doc """
  Imports each file. Codes already in the database are skipped unless `force: true`.
  """
  def import_all(files, opts \\ []) do
    force = Keyword.get(opts, :force, false)
    existing = existing_codes()

    Enum.map(files, fn {code, path} ->
      if not force and MapSet.member?(existing, code) do
        {:skipped, code}
      else
        import_one(code, path)
      end
    end)
  end

  # The parser raises on some malformed files (over-long fields, Postgrex errors);
  # one bad file must not abort the whole corpus run.
  defp import_one(code, path) do
    case TeiParser.import_file(path) do
      {:ok, play} -> {:ok, code, play}
      {:error, reason} -> failure(code, reason)
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
    |> Enum.map(&base_code/1)
    |> MapSet.new()
  end
end
