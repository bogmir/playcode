defmodule Playcode.Export.StaticSite.Pages do
  @moduledoc """
  The static site's page templates (`pages/*.html.heex`), rendered to strings. HEEx
  escapes every interpolation, which is why the site is no longer built by string
  concatenation.
  """
  use Phoenix.Component

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.Components
  alias PlaycodeWeb.PlayLabels

  embed_templates "pages/*"

  # Characters are measured in lines in a verse play, in words in anything else.
  defp words_unit?(edition),
    do: Play.form(edition.play) != "verse" or (edition.stats["verses"] || 0) == 0

  @doc "Renders page template `name` (`:title`, `:division`, …) with `assigns` to HTML."
  def render(name, assigns) do
    __MODULE__
    |> apply(name, [Map.put(assigns, :__changed__, nil)])
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
    |> strip_annotations()
  end

  @doc """
  Removes the source-path comments and `data-phx-loc` attributes that dev compiles
  into HEEx (`config/dev.exs`), so an archive generated on a laptop carries no paths.
  """
  def strip_annotations(html) do
    html
    |> String.replace(~r/<!-- (?:<\/?[^>]+>|@caller)[^>]*-->/, "")
    |> String.replace(~r/ data-phx-loc="\d+"/, "")
  end
end
