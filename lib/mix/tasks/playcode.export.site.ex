defmodule Mix.Tasks.Playcode.Export.Site do
  @shortdoc "Generate a static website archive of the EMOTHE catalogue"

  @moduledoc """
  Generates an Endings Project-compliant static website from the database.

  ## Usage

      mix playcode.export.site                              # complete plays → _site/
      mix playcode.export.site -o /tmp/archive              # custom output dir
      mix playcode.export.site --plays AL0001,AL0002        # specific plays only
      mix playcode.export.site --version 2.0
      mix playcode.export.site --all                          # include incomplete plays

  ## Options

    * `-o`, `--output` - Output directory (default: `_site`)
    * `--plays` - Comma-separated play codes to export (default: all complete)
    * `--version` - Version label for the site (default: app version)
    * `--all` - Include all plays, not just those marked as complete
  """

  use Mix.Task

  @switches [
    output: :string,
    plays: :string,
    version: :string,
    all: :boolean
  ]

  @aliases [o: :output]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: @aliases)

    Mix.Task.run("app.start")

    play_codes =
      case opts[:plays] do
        nil -> nil
        codes -> String.split(codes, ",", trim: true)
      end

    app_version =
      case :application.get_key(:playcode, :vsn) do
        {:ok, vsn} -> List.to_string(vsn)
        _ -> "1.0"
      end

    result =
      Playcode.Export.StaticSite.generate(
        output_dir: opts[:output] || "_site",
        play_codes: play_codes,
        version: opts[:version] || app_version,
        all: opts[:all] || false,
        on_progress: &print_progress/1
      )

    case result do
      {:ok, %{plays: count, size: size, output_dir: dir} = report} ->
        Mix.shell().info(
          "\n✓ Static site generated: #{count} plays → #{dir}/ (#{format_size(size)})"
        )

        Mix.shell().info(
          "  largest act page #{format_size(report.largest_page_gzip)} gzipped (budget 80 KB); " <>
            "search index #{format_size(report.index_bytes)}, largest shard #{format_size(report.largest_shard_bytes)}"
        )

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
    end
  end

  defp print_progress(%{step: :assets, detail: detail}), do: Mix.shell().info("  #{detail}")
  defp print_progress(%{step: :catalogue, detail: detail}), do: Mix.shell().info("  #{detail}")

  defp print_progress(%{step: :play, current: current, total: total, detail: code}) do
    Mix.shell().info("  [#{current}/#{total}] #{code}")
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"
end
