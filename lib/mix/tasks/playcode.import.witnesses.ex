defmodule Mix.Tasks.Playcode.Import.Witnesses do
  @shortdoc "Move FileMaker's witnesses into the plays we hold"

  @moduledoc """
  Reads FileMaker's witness tables (`T03`, `T03.2`) and gives the plays in the database
  their witnesses: S3's one-time import. Spec:
  docs/superpowers/specs/2026-10-10-s3-witnesses-design.md.

      mix playcode.import.witnesses --dry-run       # print the plan, write nothing
      mix playcode.import.witnesses                 # write it
      mix playcode.import.witnesses --path other/dir

  Re-running is safe: a play already imported is skipped whole, so a curator's edits and
  deletions stay. On Fly, use `Playcode.Release.import_witnesses/2`.
  """

  use Mix.Task

  alias Playcode.Import.{FilemakerSync, Witnesses}

  @switches [dry_run: :boolean, path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dir = opts[:path] || Witnesses.default_dir()

    case Witnesses.load(dir) do
      {:ok, data} ->
        plan = Witnesses.plan(data, FilemakerSync.all_plays())
        Enum.each(Witnesses.report(plan), fn line -> Mix.shell().info(line) end)

        if opts[:dry_run] do
          Mix.shell().info("\ndry run, nothing written")
        else
          {:ok, written} = Witnesses.apply_plan(plan)
          Mix.shell().info("\ncreated #{written.witnesses} witnesses")
        end

      {:error, {file, reason}} ->
        Mix.raise("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end
end
