defmodule Playcode.PlayContent.InlineMarkup do
  @moduledoc """
  The importer stores `<emph>` and `<hi rend="italic">` as `<<…>>` inside element
  content. `parts/1` turns that back into pieces a renderer can mark up; `plain/1`
  gives the text without the markers, for search and word counts.
  """

  @doc "Splits `text` into `%{text: binary, italic: boolean}` parts, in order."
  def parts(nil), do: []

  def parts(text) do
    text
    |> String.replace("&lt;&lt;", "<<")
    |> String.replace("&gt;&gt;", ">>")
    |> then(&Regex.split(~r/<<(.*?)>>/s, &1, include_captures: true))
    |> Enum.map(fn part ->
      case Regex.run(~r/\A<<(.*)>>\z/s, part) do
        [_, inner] -> %{text: inner, italic: true}
        nil -> %{text: part, italic: false}
      end
    end)
    |> Enum.reject(&(&1.text == ""))
  end

  @doc "`text` without the `<<` and `>>` markers."
  def plain(text), do: text |> parts() |> Enum.map_join(& &1.text)
end
