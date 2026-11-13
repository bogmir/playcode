defmodule Playcode.Export.TeiValidatorErrorsTest do
  use ExUnit.Case, async: true

  # One xmllint, so 11 s of CPU compiling the TEI RelaxNG schema. A module of its own runs
  # beside the other validator tests: the tests of one module run one after the other.
  # Excluded by default, see test_helper.exs.
  @moduletag :slow

  alias Playcode.Export.TeiValidator

  test "validate/1 returns errors for malformed XML" do
    invalid_xml =
      ~s(<?xml version="1.0"?>\n<TEI xmlns="http://www.tei-c.org/ns/1.0"><bad></TEI>)

    assert {:error, errors} = TeiValidator.validate(invalid_xml)
    assert is_list(errors)
    assert length(errors) > 0
  end
end
