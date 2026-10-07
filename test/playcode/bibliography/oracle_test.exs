defmodule Playcode.Bibliography.OracleTest do
  @moduledoc """
  Every word FileMaker printed in a citation is in ours. The sample is committed; the
  whole dump is git-ignored, so its sweep runs only where it is present.
  """
  use ExUnit.Case, async: true

  alias Playcode.CitationOracle

  test "the committed sample: 30 records and 16 modern-edition links" do
    assert CitationOracle.misses("test/fixtures/filemaker/oracle") == %{}
  end

  @tag :slow
  test "the whole FileMaker dump, where present" do
    if File.dir?("doc/ctce_dades") do
      # 2095's URL access date is a page range typed into the wrong field, with no URL
      # beside it, so it prints nowhere. Curators fix it in admin.
      assert CitationOracle.misses("doc/ctce_dades") == %{"T12:2095" => ["853", "960"]}
    end
  end
end
