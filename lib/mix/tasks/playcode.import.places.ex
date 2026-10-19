defmodule Mix.Tasks.Playcode.Import.Places do
  @shortdoc "Move FileMaker's places of action into the plays we hold"

  @moduledoc """
  Reads FileMaker's place tables (`T10`, `T10.1` to `T10.5`, `T10.11`, `T10.X`) and gives the
  plays in the database their places of action, with the historical state each link names:
  S9b's one-time import. Spec: docs/superpowers/specs/2026-10-19-s9b-places-import-design.md.

      mix playcode.import.places --dry-run       # print the plan, write nothing
      mix playcode.import.places                 # write it
      mix playcode.import.places --path other/dir

  Re-running is safe: a play already imported is skipped whole, so a curator's edits and
  deletions stay. On Fly, use `Playcode.Release.import_places/2`.
  """

  use Mix.Task

  alias Playcode.Import.{FilemakerSync, Places}

  @switches [dry_run: :boolean, path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dir = opts[:path] || Places.default_dir()

    case Places.load(dir) do
      {:ok, data} ->
        plan = Places.plan(data, FilemakerSync.all_plays())
        Enum.each(Places.report(plan), fn line -> Mix.shell().info(line) end)

        if opts[:dry_run] do
          Mix.shell().info("\ndry run, nothing written")
        else
          {:ok, written} = Places.apply_plan(plan)
          Mix.shell().info("\ncreated #{written.places} places and #{written.links} links")
        end

      {:error, {file, reason}} ->
        Mix.raise("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end
end
