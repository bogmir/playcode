defmodule Mix.Tasks.Playcode.Import.Filemaker.Plays do
  @shortdoc "Create FileMaker's records Playcode does not hold, as plays without a text"

  @moduledoc """
  Reads FileMaker's `T01_ObraTitulo` and `T00_ObraIndice` and creates a draft play
  without a text for each record Playcode does not hold (`Playcode.Import.FilemakerPlays`).

      mix playcode.import.filemaker.plays --texts DIR   # FileMaker's texts to DIR, nothing created
      mix playcode.import.filemaker.plays --dry-run     # print the plan, write nothing
      mix playcode.import.filemaker.plays               # create them
      mix playcode.import.tei --dir DIR --force         # then fill in the texts that read
      mix playcode.import.filemaker.plays --path other/dir

  Re-running creates nothing: every code is then held. On Fly, use
  `Playcode.Release.import_filemaker_plays/2`; the texts go up with
  `mix playcode.fly.reimport files --dir DIR`.
  """

  use Mix.Task

  alias Playcode.Catalogue
  alias Playcode.Import.FilemakerPlays

  @switches [dry_run: :boolean, path: :string, texts: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.start")

    dir = opts[:path] || FilemakerPlays.default_dir()

    case FilemakerPlays.load(dir, texts: Keyword.has_key?(opts, :texts)) do
      {:ok, data} ->
        plan = FilemakerPlays.plan(data, Catalogue.list_plays(include_deleted: true))
        run(plan, opts)

      {:error, {file, reason}} ->
        Mix.raise("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end

  defp run(plan, opts) do
    cond do
      texts = opts[:texts] ->
        written = FilemakerPlays.write_texts(plan, texts)
        Mix.shell().info("wrote #{written} text#{if written != 1, do: "s"} to #{texts}")

      opts[:dry_run] ->
        Enum.each(FilemakerPlays.report(plan), fn line -> Mix.shell().info(line) end)
        Mix.shell().info("\ndry run, nothing written")

      true ->
        Enum.each(FilemakerPlays.report(plan), fn line -> Mix.shell().info(line) end)

        case FilemakerPlays.apply_plan(plan) do
          {:ok, created} ->
            Mix.shell().info("\ncreated #{created} plays")

          {:error, {code, changeset}} ->
            Mix.raise("#{code} refused: #{inspect(changeset.errors)}")
        end
    end
  end
end
