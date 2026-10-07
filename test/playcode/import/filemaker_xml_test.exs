defmodule Playcode.Import.FilemakerXmlTest do
  @moduledoc "The FMPXMLRESULT export FileMaker writes for one table."
  use ExUnit.Case, async: true

  alias Playcode.Import.FilemakerXml

  @dump "test/fixtures/filemaker/ctce_dades"

  test "one map per row, keyed by the METADATA field names, an empty column as \"\"" do
    assert {:ok, rows} = FilemakerXml.read(Path.join(@dump, "T13.1_Ciudad.xml"))

    assert rows == [
             %{"_kp_IdCiudad" => "1", "Ciu_Ciudad" => "Madrid"},
             %{"_kp_IdCiudad" => "2", "Ciu_Ciudad" => "London"},
             %{"_kp_IdCiudad" => "3", "Ciu_Ciudad" => "Weinheim"},
             %{"_kp_IdCiudad" => "4", "Ciu_Ciudad" => ""}
           ]
  end

  test "entities are decoded, so FileMaker's <<…>> italics survive" do
    {:ok, rows} = FilemakerXml.read(Path.join(@dump, "T12.1_BibliografiaSelecta.xml"))
    grilli = Enum.find(rows, &(&1["_kp_IdBiblioSelecta"] == "2"))
    assert grilli["BibSel_Titulo"] == "Lope y su fábula de <<Adonis y Venus>>"
  end

  @tag :tmp_dir
  test "anything else is refused", %{tmp_dir: dir} do
    other = Path.join(dir, "other.xml")
    File.write!(other, "<root/>")

    assert {:error, :not_fmpxmlresult} = FilemakerXml.read(other)
    assert {:error, _reason} = FilemakerXml.read("test/fixtures/filemaker/export_sample.ndjson")
    assert {:error, :enoent} = FilemakerXml.read(Path.join(dir, "missing.xml"))
  end
end
