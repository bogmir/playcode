defmodule Playcode.Export.TeiValidatorAllTest do
  use ExUnit.Case, async: true

  # One xmllint, so 11 s of CPU compiling the TEI RelaxNG schema, once for every document. A
  # module of its own runs beside the other validator tests: the tests of one module run one
  # after the other. Excluded by default, see test_helper.exs.
  @moduletag :slow

  alias Playcode.Export.TeiValidator

  test "validate_all/1 gives each document its own result, its errors its own" do
    valid = """
    <?xml version="1.0"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0"><teiHeader><fileDesc>
      <titleStmt><title>T</title></titleStmt><publicationStmt><p>P</p></publicationStmt>
      <sourceDesc><p>S</p></sourceDesc>
    </fileDesc></teiHeader><text><body><p>Texto.</p></body></text></TEI>
    """

    malformed = ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"><bad></TEI>)
    invalid = String.replace(valid, "<p>Texto.</p>", "<sp>Texto.</sp><bogus/>")

    assert [
             {:ok, :valid},
             {:error, [_ | _] = malformed_errors},
             {:ok, :valid},
             {:error, [_ | _] = invalid_errors}
           ] =
             TeiValidator.validate_all([valid, malformed, valid, invalid])

    assert Enum.any?(malformed_errors, &(&1 =~ "bad"))
    refute Enum.any?(malformed_errors, &(&1 =~ "bogus"))
    assert Enum.any?(invalid_errors, &(&1 =~ "bogus"))
    refute Enum.any?(invalid_errors, &(&1 =~ "bad"))
    # A line naming the document names it "TEI-XML", never xmllint's temporary file.
    assert ["TEI-XML:" <> _ | _] = malformed_errors
    assert ["TEI-XML:" <> _ | _] = invalid_errors
    refute Enum.any?(malformed_errors ++ invalid_errors, &(&1 =~ ".xml"))
  end
end
