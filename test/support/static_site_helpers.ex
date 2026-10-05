defmodule Playcode.StaticSiteHelpers do
  @moduledoc """
  Generate the static site into a temp directory and read it back as a visitor gets
  it: files, HTML documents, table rows and the search index's `.js` files.
  """

  import ExUnit.Assertions
  import ExUnit.Callbacks, only: [on_exit: 1]

  alias Playcode.Export.{SiteBuilder, StaticSite}

  @doc "Generates the site for `plays` (by code) into a fresh temp dir and returns it."
  def generate!(plays, opts \\ []) do
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    opts = Keyword.merge([output_dir: dir, play_codes: Enum.map(plays, & &1.code)], opts)
    assert {:ok, %{output_dir: ^dir}} = StaticSite.generate(opts)
    dir
  end

  @doc """
  Waits, at most five seconds, until the site builder has no job. Run on exit by tests
  that start one, so a test that fails mid-build does not leave its job running into the
  next test, which would be refused as busy while the job used that test's sandbox.
  """
  def await_idle_builder(tries \\ 100) do
    cond do
      SiteBuilder.status() == %{job: nil, queue: []} -> :ok
      tries == 0 -> flunk("the site builder is still busy")
      true -> Process.sleep(50) && await_idle_builder(tries - 1)
    end
  end

  def read!(dir, path), do: File.read!(Path.join(dir, path))
  def html!(dir, path), do: dir |> read!(path) |> LazyHTML.from_document()

  @doc "The text of every node matching `selector`, whitespace collapsed."
  def texts(html, selector),
    do: html |> LazyHTML.query(selector) |> Enum.map(&squish(LazyHTML.text(&1)))

  @doc "Each row matching `selector` as the list of its cell texts."
  def rows(html, selector) do
    html
    |> LazyHTML.query(selector)
    |> Enum.map(fn row -> texts(row, "th, td") end)
  end

  def squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  @doc "Decodes a search file: `{kind, key, data}` from `EMOTHE.search.load(kind, key, data);`."
  def load_js!(dir, path) do
    [_, kind, key, json] =
      Regex.run(~r/\AEMOTHE\.search\.load\((".*?"),(".*?"),(.*)\);\n\z/s, read!(dir, path))

    {Jason.decode!(kind), Jason.decode!(key), Jason.decode!(json)}
  end
end
