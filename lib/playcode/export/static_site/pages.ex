defmodule Playcode.Export.StaticSite.Pages do
  @moduledoc """
  The static site's page templates (`pages/*.html.heex`), rendered to strings. HEEx
  escapes every interpolation, which is why the site is no longer built by string
  concatenation.
  """
  use Phoenix.Component

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.{Comparison, Components, Edition}
  alias Playcode.PlayContent.{Element, Note}
  alias PlaycodeWeb.PlayLabels

  embed_templates "pages/*"

  # Characters are measured in lines in a verse play, in words in anything else.
  defp words_unit?(edition),
    do: Play.form(edition.play) != "verse" or (edition.stats["verses"] || 0) == 0

  defp note_type(note), do: PlayLabels.note_type_key(note.type)

  # The note types a play uses, in the order they first appear.
  defp note_types(edition), do: edition.notes |> Enum.map(&note_type(&1.note)) |> Enum.uniq()

  # A stage direction's kind for the filter: the file's, or "none".
  defp stage_type(entry), do: entry.type || "none"

  # The kinds a play's stage directions use, in the order they first appear.
  defp stage_types(edition),
    do: edition.stage_directions |> Enum.map(&stage_type/1) |> Enum.uniq()

  # A kind's name: TEI's kinds by their label, a file's other word as itself.
  defp stage_label("none", none), do: none

  defp stage_label(type, _none) do
    if type in Element.stage_types(), do: PlayLabels.stage_type_label(type), else: type
  end

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
