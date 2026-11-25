defmodule Playcode.Import.FilemakerTest do
  use ExUnit.Case, async: true

  alias Playcode.Import.Filemaker

  @sample "test/fixtures/filemaker/index_sample.ndjson"

  setup do
    {:ok, index} = Filemaker.load_index(@sample)
    %{index: index}
  end

  test "reads the language tag", %{index: index} do
    assert index["EMOTHE0038"].lang == "en"
    assert index["EMOTHE0052"].lang == "es"
  end

  test "an \"ed.\" credit is the original, a \"tra.\" credit a translation", %{index: index} do
    assert index["EMOTHE0038"].role == :editor
    assert index["EMOTHE0052"].role == :translator
  end

  test "every version knows its whole family", %{index: index} do
    assert Enum.map(index["EMOTHE0052"].family, & &1.code) == ["EMOTHE0038", "EMOTHE0052"]
    assert Enum.map(index["EMOTHE0038"].family, & &1.role) == [:editor, :translator]
  end

  test "reads the work dating from the index header", %{index: index} do
    assert index["EMOTHE0038"].composition_date_from == 1606
    assert index["EMOTHE0038"].composition_date_to == 1607
    assert index["EMOTHE0038"].composition_date_note == "=1606 - =1607"
  end

  test "the dating goes to the original, never to a translation", %{index: index} do
    refute Map.has_key?(index["EMOTHE0052"], :composition_date_from)
    refute Map.has_key?(index["EMOTHE0052"], :composition_date_note)
  end

  test "a work with no header dating gains no dating keys", %{index: index} do
    refute Map.has_key?(index["HIE0393"], :composition_date_from)
  end

  describe "dating forms" do
    defp dating(header) do
      html =
        ~s(<div><i>T</i>. A<span style="x">#{header}</span></div>\n<ul>\n) <>
          ~s(<li><span style="font-size: x-small">[EN] </span>) <>
          ~s(<a href="textosEMOTHE/EMOTHE9001_T.php"><i>T</i></a>) <>
          ~s(<span>Someone, ed.</span></li>\n</ul>)

      line =
        Jason.encode!(%{
          "fields" => %{
            "_kp_IdIndiceEM" => ["1"],
            "_IdIndiceCtce" => ["1"],
            "pub_listaObras" => [html]
          }
        })

      meta = Jason.encode!(%{"_meta" => %{"layout" => "T00_indiceEM"}})
      path = Path.join(System.tmp_dir!(), "fm-#{System.unique_integer([:positive])}.ndjson")
      File.write!(path, meta <> "\n" <> line <> "\n")
      on_exit(fn -> File.rm(path) end)

      {:ok, index} = Filemaker.load_index(path)
      index["EMOTHE9001"]
    end

    test "exact range" do
      assert %{composition_date_from: 1606, composition_date_to: 1607} = dating("=1606 - =1607")
    end

    test "single year" do
      assert %{composition_date_from: 1610, composition_date_to: 1610} = dating("=1610")
    end

    test "open-ended range" do
      assert %{composition_date_from: 1598, composition_date_to: 1600} = dating("≥1598 - ≤1600")
    end

    test "conjectural" do
      assert %{composition_date_from: 1600, composition_date_to: 1601} = dating("1600? - 1601?")
    end

    test "circa" do
      assert %{composition_date_from: 1562, composition_date_to: 1562} = dating("≈1562")
    end

    test "two-digit tail collapses to the start year, and the note keeps the truth" do
      assert %{
               composition_date_from: 1587,
               composition_date_to: 1587,
               composition_date_note: "=1587 - =92"
             } = dating("=1587 - =92")
    end

    test "a header with no year is skipped, not guessed" do
      assert %{composition_date_skipped: {:unparseable, "="}} = dating("=")
      refute Map.has_key?(dating("="), :composition_date_from)
    end

    test "an implausibly wide span is skipped" do
      assert %{composition_date_skipped: {:span, "¿1694? y ¿1605?"}} = dating("¿1694? y ¿1605?")
      refute Map.has_key?(dating("¿1694? y ¿1605?"), :composition_date_from)
    end
  end

  test "returns an error for a missing file" do
    assert {:error, :enoent} = Filemaker.load_index("test/fixtures/filemaker/nope.ndjson")
  end

  # The admin page uploads one file carrying both layouts, the way the real
  # export does. Both readers must find their own records in it.
  test "given one file with both layouts then each reader finds its own records" do
    path = "test/fixtures/filemaker/export_sample.ndjson"

    assert {:ok, index} = Filemaker.load_index(path)
    assert {:ok, versions} = Filemaker.load_versions(path)

    assert Enum.sort(Map.keys(index)) == ["EMOTHE0038", "EMOTHE0052", "HIE0393"]
    assert Enum.sort(Map.keys(versions)) == ["EMOTHE0038", "EMOTHE0211", "HIE0393"]
  end

  describe "load_versions/1" do
    @versions "test/fixtures/filemaker/versions_sample.ndjson"

    setup do
      {:ok, versions} = Filemaker.load_versions(@versions)
      %{versions: versions}
    end

    test "decodes the historical time code into a slug", %{versions: versions} do
      assert versions["EMOTHE0038"].historical_time == "antiguedad_clasica"
      assert versions["EMOTHE0211"].historical_time == "siglo_xvii"
    end

    test "reads the note out of the rendered label", %{versions: versions} do
      assert versions["EMOTHE0038"].historical_time_note ==
               "First century BC. The play dramatizes events taking place between 40 and 30 BC."
    end

    test "a code with no rendered label still yields a slug and no note", %{versions: versions} do
      assert versions["EMOTHE0211"].historical_time == "siglo_xvii"
      assert versions["EMOTHE0211"].historical_time_note == nil
    end

    test "takes the first of several periods", %{versions: versions} do
      assert versions["HIE0393"].historical_time == "siglo_xvi"
      assert versions["HIE0393"].historical_time_note == "After the Battle of Pavia (1525)."
    end

    test "joins the competing datings into the note", %{versions: versions} do
      assert versions["EMOTHE0038"].composition_date_note ==
               "desde o posterior 1605 y anterior o hasta 1607; 1606"
    end

    test "no pub_datacion means no note", %{versions: versions} do
      assert versions["EMOTHE0211"].composition_date_note == nil
    end
  end
end
