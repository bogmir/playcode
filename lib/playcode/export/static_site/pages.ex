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

  # What catalogue.js says, `{spanish, english}` as JSON pairs: its count and a row's
  # passages. `more` keeps its `%{count}` for the script to fill.
  defp catalogue_words do
    words = %{
      of: tp("of"),
      play: tp("play"),
      plays: tp("plays"),
      passage: tp("passage"),
      passages: tp("passages"),
      searching: tp("Searching…"),
      open: tp("Show the passages"),
      more: tp("Show the other %{count}", count: "%{count}"),
      unavailable: tp("Text search is unavailable."),
      note: tp("note")
    }

    Jason.encode!(lists(words))
  end

  # The catalogue form's three kinds of control. Each is named by its label; a range's two
  # boxes by their aria-labels, its label pointing at the first.
  attr :name, :string, required: true
  attr :label, :any, required: true
  attr :hint, :any, default: nil
  attr :suggest, :boolean, default: false, doc: "a datalist, which catalogue.js fills"

  defp search_text(assigns) do
    ~H"""
    <label for={"c-" <> @name}>{@label} <small :if={@hint}>{@hint}</small></label>
    <input
      type="text"
      id={"c-" <> @name}
      name={@name}
      list={@suggest && "dl-" <> @name}
      autocomplete="off"
    />
    <datalist :if={@suggest} id={"dl-" <> @name}></datalist>
    """
  end

  attr :name, :string, required: true
  attr :label, :any, required: true
  attr :options, :list, required: true, doc: "`{value, {spanish, english}}`, the first \"All\""

  defp search_list(assigns) do
    ~H"""
    <label for={"c-" <> @name}>{@label}</label>
    <select id={"c-" <> @name} name={@name}>
      <option :for={{value, label} <- @options} value={value} {attrs(label, "label")}></option>
    </select>
    """
  end

  attr :name, :string, required: true
  attr :label, :any, required: true
  attr :from, :any, required: true, doc: "the first box's aria-label, `{spanish, english}`"
  attr :to, :any, required: true

  defp search_range(assigns) do
    ~H"""
    <label for={"c-" <> @name <> "-from"}>{@label}</label>
    <div class="range">
      <input
        type="number"
        id={"c-" <> @name <> "-from"}
        name={@name <> "-from"}
        {Enum.uniq(ta("placeholder", "from") ++ attrs(@from, "aria-label"))}
      />
      <span aria-hidden="true">–</span>
      <input
        type="number"
        name={@name <> "-to"}
        {Enum.uniq(ta("placeholder", "to") ++ attrs(@to, "aria-label"))}
      />
    </div>
    """
  end

  defp lists(%{} = map), do: Map.new(map, fn {key, value} -> {key, lists(value)} end)
  defp lists({es, en}), do: [es, en]

  @doc """
  Each page's division's own elements and each of its scenes', rendered once, by id: what
  its page and text.html both print (`Components.elements/1`).
  """
  def texts(edition) do
    for page <- edition.pages,
        is_nil(page.scene),
        of <- [page.division | page.division.children],
        of.type != "elenco",
        into: %{} do
      html =
        %{of: of, edition: edition, texts: %{}, __changed__: nil}
        |> Components.elements()
        |> Phoenix.HTML.Safe.to_iodata()
        |> IO.iodata_to_binary()
        |> strip_annotations()

      {of.id, {:safe, html}}
    end
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
