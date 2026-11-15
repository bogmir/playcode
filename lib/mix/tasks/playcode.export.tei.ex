defmodule Mix.Tasks.Playcode.Export.Tei do
  @shortdoc "Write every play's TEI to a corpus directory"

  @moduledoc """
  Writes each play's TEI, as its download, to `DIR/CODE.xml`, the corpus's naming; archived
  plays are left out. On Fly, use `Playcode.Release.export_tei/2`.

      mix playcode.export.tei --dir DIR
      mix playcode.export.tei --dir DIR --code EMOTHE0010
  """

  use Mix.Task

  alias Playcode.Import.TeiCorpus

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string, code: :string])
    dir = opts[:dir] || Mix.raise("usage: mix playcode.export.tei --dir DIR [--code CODE]")
    Mix.Task.run("app.start")

    case TeiCorpus.export(dir, opts[:code]) do
      {:ok, count} -> Mix.shell().info("wrote #{count} file(s) to #{dir}")
      {:error, :no_play} -> Mix.raise("no play #{opts[:code]}")
    end
  end
end
