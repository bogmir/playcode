defmodule Playcode.Export.PdfCacheTest do
  @moduledoc """
  The PDF cache's key: a PDF is rendered again when its play or the code it is rendered
  with changes. A module the key leaves out serves every cached PDF unchanged after a
  change to it: `Division`, `Text` and `Bibliography.Entry` were missed when `Download`
  joined the key (found by the review, 2026-11-04).
  """
  use ExUnit.Case, async: true

  import Playcode.ModuleReach

  alias Playcode.Export.PdfCache

  test "every module the PDF is rendered with is in its cache key, or only reads play data" do
    hashed = PdfCache.code_modules()

    assert [Playcode.Export.Pdf]
           |> reach(hashed)
           |> Enum.reject(&(&1 in hashed or data_access?(&1))) == []
  end

  test "a schema the PDF export calls a function of is in its cache key" do
    assert schema_functions_called(PdfCache.code_modules()) == []
  end
end
