defmodule Playcode.ApparatusCorpusTest do
  @moduledoc """
  The six plays of the production corpus that carry a critical apparatus, read from
  doc/tei_corpus/ (git-ignored; without it nothing runs): every entry outside a note comes
  back as an entry, with EMOTHE0530's one found only in a note; none is left inside a note
  or pasted into a line; and the export, imported again, gives the same file.
  `mix test --include slow`.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Import.TeiImport

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

  # The file under a code of its own, in UTF-8: the corpus sweep imports Hamlet's fixture
  # under the same code, and a play's code is unique, so two transactions holding it queue
  # behind each other (the sweep's Hamlet passed the 60-second timeout).
  defp own_copy(path) do
    <<0xFF, 0xFE, utf16::binary>> = File.read!(path)

    utf16
    |> :unicode.characters_to_binary({:utf16, :little})
    |> String.replace(
      ~r/<title key="archivo">[^_<]+/,
      ~s(<title key="archivo">APP#{System.unique_integer([:positive])})
    )
  end

  @doc "The checks of one play's file, run by its own module below."
  def assert_entries(path) do
    code = path |> Path.basename() |> String.slice(0, 10)

    {:ok, play} = path |> own_copy() |> write_tmp!() |> TeiImport.import_file()
    refute play.code =~ "EMOTHE"
    first = export_tei(play)

    assert first |> xml_apps() |> Enum.reject(&(&1.type == "folio")) |> length() ==
             @entries[code]

    assert xml_elements(first, "app", within: "note") == []

    if pasted = @pasted[code],
      do: refute(Enum.any?(reading_texts(first, "l"), &String.contains?(&1, pasted)))

    {:ok, again} = first |> write_tmp!() |> TeiImport.import_file()
    second = export_tei(again)

    assert second == first

    # Hamlet's 132 Folio passages: 119 inside one element, 13 across elements, each of
    # those with an F at its start and its end.
    if code == "EMOTHE0010" do
      assert Enum.count(xml_apps(first), &(&1.type == "folio")) == 119
      assert first |> xml_texts("code") |> Enum.count(&(&1 == "<sup>")) == 26
      assert xml_texts(second, "code") == xml_texts(first, "code")
    end
  end
end

# A module per play, so the six run side by side: in one module they ran one after
# another, 35 s, the slow suite's longest module.
for path <- Path.wildcard("doc/tei_corpus/EMOTHE0{010,187,435,460,530,560}_*.xml") do
  code = path |> Path.basename() |> String.slice(0, 10)

  defmodule Module.concat(Playcode.ApparatusCorpusTest, code) do
    use Playcode.DataCase, async: true

    @moduletag :slow
    @moduletag timeout: 120_000
    @path path

    test "#{code}: every entry comes back once, out of the text, and stays so",
      do: Playcode.ApparatusCorpusTest.assert_entries(@path)
  end
end
