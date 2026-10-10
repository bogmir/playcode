defmodule Playcode.Import.TeiParserTest do
  @moduledoc """
  Reading a TEI file, on its own. These tests check out no database connection, so a
  reader that reached for the database would fail them: reading is pure, and
  `TeiImport` does all the writing. What the reading means for a stored play is asserted
  through the import, in tei_import_test.exs and tei_roundtrip_test.exs.
  """
  use ExUnit.Case, async: true

  import Playcode.ImportHelpers, only: [tei: 1, write_tmp!: 1]

  alias Playcode.Import.TeiParser

  test "a play is read without the database" do
    xml =
      tei(
        code: "PURE01",
        front:
          ~s(<div type="elenco"><castList><castItem><role xml:id="ALB">Albano</role></castItem></castList></div>),
        body:
          ~s(<div1 type="acto" n="1"><head>Acto I</head><sp who="#ALB #ALB"><speaker>Albano</speaker><l n="1">Uno<note n="1">Glosa.</note> dos</l></sp></div1>)
      )

    assert {:ok, tei} = TeiParser.parse_file(write_tmp!(xml))

    assert %{code: "PURE01", title: "Test Play"} = tei.play
    assert [%{xml_id: "ALB", name: "Albano"}] = tei.characters

    assert [%{type: "elenco"}, %{type: "acto", title: "Acto I", elements: [speech]}] =
             tei.divisions

    assert %{type: "speech", speaker_label: "Albano", who: ["ALB", "ALB"], elements: [line]} =
             speech

    assert %{
             type: "verse_line",
             content: "Uno dos",
             line_number: 1,
             notes: [%{offset: 3, n: "1", body: "Glosa."}]
           } = line
  end
end
