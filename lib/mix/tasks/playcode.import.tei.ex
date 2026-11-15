defmodule Mix.Tasks.Playcode.Import.Tei do
  @shortdoc "Import the local TEI corpus into the database"

  @moduledoc """
  Imports every .xml file under `doc/tei_corpus` (the production corpus, git-ignored)
  and the fixture directories, one play per code; a code in `doc/tei_corpus` wins.

      mix playcode.import.tei                  # skip codes already imported
      mix playcode.import.tei --force          # re-import everything not edited by hand
      mix playcode.import.tei --force --resume # ...except plays imported since their file was written
      mix playcode.import.tei --force --overwrite-edits # ...edited by hand too
      mix playcode.import.tei --dry-run        # report what would happen, write nothing
      mix playcode.import.tei --dir some/path  # use another directory (repeatable)

  A re-import replaces a play's text and the records the importer created; anything
  entered by hand is kept, as are language, relationship, parent play and completeness.
  `--force` skips a play with rows from its file edited since their import, and names it,
  unless `--overwrite-edits`. `--dry-run` prints all that per file before anything is
  written, and with `--force` it counts the hand edits to each play's text that the
  re-import would undo. On Fly, use `Playcode.Release.import_tei/2`.
  """

  use Mix.Task

  alias Playcode.Import.TeiCorpus

  @switches [
    force: :boolean,
    resume: :boolean,
    overwrite_edits: :boolean,
    dry_run: :boolean,
    dir: :keep
  ]

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
      TeiCorpus.dry_run(files, opts, report)
    else
      TeiCorpus.run(files, opts, report)
    end
  end
end
