defmodule Mix.Tasks.Playcode.Import.Tei do
  @shortdoc "Import the local TEI corpus into the database"

  @moduledoc """
  Imports every .xml file under `doc/tei_corpus` (the production corpus, git-ignored)
  and the fixture directories, one play per code; a code in `doc/tei_corpus` wins.

      mix playcode.import.tei                  # skip codes already imported
      mix playcode.import.tei --force          # re-import everything
      mix playcode.import.tei --dry-run        # report what would happen, write nothing
      mix playcode.import.tei --dir some/path  # use another directory (repeatable)

  A re-import replaces a play's text and the records the importer created; anything
  entered by hand is kept, as are language, relationship, parent play and completeness.
  `--dry-run` prints that per file before anything is written, and with `--force` it
  counts the hand edits to each play's text that the re-import would undo. On Fly, use
  `Playcode.Release.import_tei/2`.
  """

  use Mix.Task

  alias Playcode.Import.TeiCorpus

  @switches [force: :boolean, dry_run: :boolean, dir: :keep]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dirs =
      case Keyword.get_values(opts, :dir) do
        [] -> TeiCorpus.default_dirs()
        dirs -> dirs
      end

    files = TeiCorpus.collect_files(dirs)
    Mix.shell().info("#{length(files)} file(s) in #{Enum.join(dirs, ", ")}")

    report = fn
      {:info, line} -> Mix.shell().info(line)
      {:error, line} -> Mix.shell().error(line)
    end

    if opts[:dry_run] do
      files |> TeiCorpus.dry_run(force: opts[:force] || false) |> Enum.each(report)
    else
      TeiCorpus.run(files, [force: opts[:force] || false], report)
    end
  end
end
