defmodule Mix.Tasks.Playcode.Import.Performances do
  @shortdoc "Move FileMaker's historical performances into the plays we hold"

  @moduledoc """
  Reads FileMaker's performance tables (`T11`, `T11.1`, `T11.11`, `T11.12`, `T11.22`, `T11.3`),
  the source tables they cite (`T13`, `T13.1`, `T13.2`) and the places of action naming them
  (`T10*`), and gives the plays in the database their performances, with the cast, the
  company, the place and the source of each: S5's one-time import. Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.

      mix playcode.import.performances --dry-run       # print the plan, write nothing
      mix playcode.import.performances                 # write it
      mix playcode.import.performances --path other/dir

  Re-running is safe: a play already imported is skipped whole, so a curator's edits and
  deletions stay. On Fly, use `Playcode.Release.import_performances/2`.
  """

  use Mix.Task

  alias Playcode.Import.{FilemakerSync, Performances}

  @switches [dry_run: :boolean, path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dir = opts[:path] || Performances.default_dir()

    case Performances.load(dir) do
      {:ok, data} ->
        plan = Performances.plan(data, FilemakerSync.all_plays())
        Enum.each(Performances.report(plan), fn line -> Mix.shell().info(line) end)

        if opts[:dry_run] do
          Mix.shell().info("\ndry run, nothing written")
        else
          write(plan)
        end

      {:error, {file, reason}} ->
        Mix.raise("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end

  defp write(plan) do
    case Performances.apply_plan(plan) do
      {:ok, written} ->
        Mix.shell().info(
          "\ncreated #{written.performances} performances, #{written.companies} companies, " <>
            "#{written.actors} actors, #{written.entries} entries and #{written.places} places"
        )

      {:error, refused} ->
        Mix.raise("nothing written, #{Performances.error_message(refused)}")
    end
  end
end
