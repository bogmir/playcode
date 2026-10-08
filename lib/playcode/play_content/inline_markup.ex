defmodule Playcode.PlayContent.InlineMarkup do
  @moduledoc """
  The importer stores `<emph>` and `<hi rend="italic">` as `<<…>>` inside element
  content. `parts/1` turns that back into pieces a renderer can mark up; `plain/1`
  gives the text without the markers, for search and word counts. `parts/2` also places
  a line's notes between the pieces.
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

  @doc """
  As `parts/1`, with each of `notes` placed as a `%{note: note}` part after the first
  `note.offset` graphemes of the plain text. A note at the end of a piece follows that
  piece; one inside an italic run splits it. `notes` are placed by `{offset, position}`
  whatever their order in the list, and a note past the end of the text goes last.
  """
  def parts(text, []), do: parts(text)

  def parts(text, notes) do
    notes = Enum.sort_by(notes, &{&1.offset, &1.position})
    {parts, {_at, rest}} = Enum.flat_map_reduce(parts(text), {0, notes}, &place_notes/2)
    parts ++ Enum.map(rest, &%{note: &1})
  end

  # Splits `part` (which starts `at` graphemes into the text) at every note that falls
  # inside it or at its end.
  defp place_notes(part, {at, notes}) do
    length = String.length(part.text)
    {here, later} = Enum.split_while(notes, &(&1.offset <= at + length))

    {pieces, cut} =
      Enum.reduce(here, {[], 0}, fn note, {pieces, cut} ->
        k = max(note.offset - at, cut)
        piece = %{part | text: String.slice(part.text, cut, k - cut)}
        {[%{note: note} | prepend_text(pieces, piece)], k}
      end)

    rest = %{part | text: String.slice(part.text, cut..-1//1)}
    {Enum.reverse(prepend_text(pieces, rest)), {at + length, later}}
  end

  defp prepend_text(pieces, %{text: ""}), do: pieces
  defp prepend_text(pieces, part), do: [part | pieces]

  @doc "`text` without the `<<` and `>>` markers."
  def plain(text), do: text |> parts() |> Enum.map_join(& &1.text)
end
