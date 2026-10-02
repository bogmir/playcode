defmodule Playcode.Export.StaticSiteSearchTest do
  @moduledoc """
  Full-text search in the static site. The normaliser is tested directly because the
  browser's copy in `site.js` must agree with it word for word; both run the cases in
  `test/fixtures/search_normalisation.json` (the JS side: `test/js/search.test.mjs`).
  """
  use Playcode.DataCase, async: true

  alias Playcode.Export.StaticSite.Search

  defp cases, do: "test/fixtures/search_normalisation.json" |> File.read!() |> Jason.decode!()

  test "the build-time normaliser splits words as the browser does" do
    for %{"text" => text, "words" => words} <- cases()["words"] do
      assert Search.words(text) == words, text
    end
  end
end
