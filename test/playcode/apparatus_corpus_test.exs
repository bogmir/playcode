defmodule Playcode.ApparatusCorpusTest do
  @moduledoc """
  The six plays of the production corpus that carry a critical apparatus, read from
  doc/tei_corpus/ (git-ignored; without it nothing runs): every entry outside a note comes
  back as an entry, with EMOTHE0530's one found only in a note; none is left inside a note
  or pasted into a line; and the export, imported again, gives the same entries and lines.
  `mix test --include slow`.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Import.TeiImport

  @moduletag :slow

  # The entries outside notes (604 in all, 63 inside notes, 62 of those copies), plus
  # EMOTHE0530's moved one. 542 in all.
  @entries %{
    "EMOTHE0010" => 90,
    "EMOTHE0187" => 64,
    "EMOTHE0435" => 10,
    "EMOTHE0460" => 127,
    "EMOTHE0530" => 62,
    "EMOTHE0560" => 189
  }

  # What the old import made of a line (docs/tei-apparatus-and-code.md).
  @pasted %{"EMOTHE0560" => "llamafalta", "EMOTHE0010" => "Barnardo. Barnardo."}

  for path <- Path.wildcard("doc/tei_corpus/EMOTHE0{010,187,435,460,530,560}_*.xml") do
    @path path
    @code path |> Path.basename() |> String.slice(0, 10)

    test "#{@code}: every entry comes back once, out of the text, and stays so" do
      {:ok, play} = TeiImport.import_file(@path)
      first = export_tei(play)

      assert length(xml_apps(first)) == @entries[@code]
      assert xml_elements(first, "app", within: "note") == []

      if pasted = @pasted[@code],
        do: refute(Enum.any?(reading_texts(first, "l"), &String.contains?(&1, pasted)))

      {:ok, again} = first |> write_tmp!() |> TeiImport.import_file()
      second = export_tei(again)

      assert xml_apps(second) == xml_apps(first)
      assert reading_texts(second, "l") == reading_texts(first, "l")
    end
  end
end
