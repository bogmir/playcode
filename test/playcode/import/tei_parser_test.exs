defmodule Playcode.Import.TeiParserTest do
  @moduledoc """
  Reading a TEI file, on its own. Reading is pure, and `TeiImport` does all the writing:
  these tests check out no database connection, and the compiled reader may call nothing
  of the app but a few pure helpers, so a database call on any of its paths fails them.
  What the reading means for a stored play is asserted through the import, in
  tei_import_test.exs and tei_roundtrip_test.exs.
  """
  use ExUnit.Case, async: true

  import Playcode.ImportHelpers, only: [tei: 1, write_tmp!: 1]

  alias Playcode.Import.TeiParser

  # The app functions the reader may call: none of them reads a row. A new one is a
  # decision, made here.
  @pure_helpers [
    {Playcode.Catalogue.Play, :composition_year_range, 0},
    {Playcode.Catalogue.Play, :historical_times, 0},
    {Playcode.Catalogue.Play, :short_code, 1},
    {Playcode.Catalogue.Play, :valid_languages, 0},
    {Playcode.Places, :slugify, 1},
    {Playcode.Places.Place, :authorities, 0},
    {Playcode.Witnesses, :type_from_tei, 2}
  ]

  test "the reader calls nothing of the app but pure helpers, on any of its paths" do
    {:ok, {TeiParser, [imports: imports]}} =
      :beam_lib.chunks(:code.which(TeiParser), [:imports])

    app_calls =
      Enum.filter(imports, fn {module, _function, _arity} ->
        module
        |> Atom.to_string()
        |> String.starts_with?(
          ~w(Elixir.Playcode. Elixir.Ecto Elixir.DBConnection Elixir.Postgrex)
        )
      end)

    assert app_calls -- @pure_helpers == []
  end

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
