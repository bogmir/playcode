defmodule Mix.Tasks.Playcode.Import.Bibliography do
  @shortdoc "Move the FileMaker bibliography into the plays we hold"

  @moduledoc """
  Reads FileMaker's bibliography tables (`T12`, `T12.1`, `T04`, `T04.1`, `T13.1`,
  `T13.2`) and links their records to the plays in the database: S4's one-time import.
  Spec: docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.

      mix playcode.import.bibliography --dry-run       # print the plan, write nothing
      mix playcode.import.bibliography                 # write it
      mix playcode.import.bibliography --path other/dir

  Re-running is safe: a play already imported is skipped whole, so a curator's edits and
  removals stay. On Fly, use `Playcode.Release.import_bibliography/2`.
  """

  use Mix.Task

  alias Playcode.Import.{Bibliography, FilemakerSync}

  @switches [dry_run: :boolean, path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dir = opts[:path] || Bibliography.default_dir()

    case Bibliography.load(dir) do
      {:ok, data} ->
        plan = Bibliography.plan(data, FilemakerSync.all_plays())
        Enum.each(Bibliography.report(plan), fn line -> Mix.shell().info(line) end)

        if opts[:dry_run] do
          Mix.shell().info("\ndry run, nothing written")
        else
          {:ok, written} = Bibliography.apply_plan(plan)
          Mix.shell().info("\ncreated #{written.entries} entries and #{written.links} links")
        end

      {:error, {file, reason}} ->
        Mix.raise("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end
end
