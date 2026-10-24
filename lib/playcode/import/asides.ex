defmodule Playcode.Import.Asides do
  @moduledoc """
  Where an aside starts, when nothing else says: a line or paragraph spoken aside continues
  the aside of the line or paragraph before it in its speech, when that one is aside too.
  Stage directions between them do not part them. The TEI import guesses so for a piece
  with no number, link or delivery stage to go by (`TeiParser`); the Word import, which
  marks each paragraph aside on its own, for every aside.
  """

  @doc "`elements`, with `aside_continues` guessed on each aside that has none yet."
  def guess(elements) do
    {elements, _previous_aside} = Enum.map_reduce(elements, false, &guess/2)
    elements
  end

  defp guess(%{type: "speech"} = speech, _previous),
    do: {Map.update(speech, nested(speech), [], &guess/1), false}

  defp guess(%{type: "line_group"} = group, previous) do
    {lines, previous} = Enum.map_reduce(Map.get(group, nested(group), []), previous, &guess/2)
    {Map.put(group, nested(group), lines), previous}
  end

  defp guess(%{type: type, is_aside: true} = element, previous)
       when type in ~w(verse_line prose),
       do: {Map.put_new(element, :aside_continues, previous), true}

  defp guess(%{type: type} = element, _previous) when type in ~w(verse_line prose),
    do: {element, false}

  defp guess(element, previous), do: {element, previous}

  # The TEI parser nests a speech's lines under :elements, the Word parser under :children.
  defp nested(element), do: if(Map.has_key?(element, :elements), do: :elements, else: :children)
end
