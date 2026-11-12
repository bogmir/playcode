defmodule Playcode.Export.StaticSite.Pages do
  @moduledoc """
  The static site's page templates (`pages/*.html.heex`), rendered to strings. HEEx
  escapes every interpolation, which is why the site is no longer built by string
  concatenation.
  """
  use Phoenix.Component

  import Playcode.Export.StaticSite.Bilingual

  alias Playcode.Catalogue.Play
  alias Playcode.Export.StaticSite.{Comparison, Components, Edition}
  alias Playcode.PlayContent.{Element, InlineMarkup, Note}
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
    if type in Element.stage_types(),
      do: both(fn -> PlayLabels.stage_type_label(type) end),
      else: type
  end

  # What search.js says, `{spanish, english}` as JSON pairs: its facets' legends and values
  # (each kind by its own name, question 15), its counts and its buttons.
  defp search_words do
    words = %{
      legends: %{
        language: tp("Language"),
        author: tp("Author"),
        kind: tp("Kind"),
        type: tp("Text")
      },
      kinds:
        Map.new(~w(original translation adaptation version), &{&1, Components.kind_label(&1)}),
      kind_words: %{
        translation: tp("translation"),
        adaptation: tp("adaptation"),
        version: tp("version")
      },
      types: %{spoken: tp("Spoken"), stage: tp("Stage directions"), note: tp("Notes")},
      all: tp("All"),
      searching: tp("Searching…"),
      line: tp("line"),
      lines: tp("lines"),
      play: tp("play"),
      plays: tp("plays"),
      in: tp("in"),
      show_all: tp("Show all")
    }

    Jason.encode!(lists(words))
  end

  defp lists(%{} = map), do: Map.new(map, fn {key, value} -> {key, lists(value)} end)
  defp lists({es, en}), do: [es, en]

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
