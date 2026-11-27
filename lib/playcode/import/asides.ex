defmodule Playcode.Import.Asides do
  @moduledoc """
  Where an aside starts, when nothing else says: a line or paragraph spoken aside continues
  the aside of the line or paragraph before it in its speech, when that one is aside too.
  Stage directions between them do not part them. The TEI import guesses so for a piece
  with no number, link or delivery stage to go by (`TeiParser`); the Word import, which
  marks each paragraph aside on its own, for every aside.
  """

  alias Playcode.PlayContent.InlineMarkup

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

  @doc """
  `elements` of the Word import, with each piece that a paragraph break cut from its aside
  continuing it: a line or paragraph that starts inside an aside, after one in its speech
  that ended inside one, with only stage directions between.
  """
  def across_breaks(elements), do: Enum.map(elements, &across_breaks_in/1)

  defp across_breaks_in(%{type: "speech"} = speech) do
    {children, _ended_aside?} =
      Enum.map_reduce(speech.children, false, fn
        %{type: type, content: content} = element, ended_aside?
        when type in ~w(verse_line prose) ->
          {open, close} = InlineMarkup.aside_marker()
          content = String.trim(content || "")
          continues? = ended_aside? and String.starts_with?(content, open)

          element =
            if continues?,
              do: Map.merge(element, %{is_aside: true, aside_continues: true}),
              else: element

          {element, String.ends_with?(content, close)}

        element, ended_aside? ->
          {element, ended_aside?}
      end)

    %{speech | children: children}
  end

  defp across_breaks_in(element), do: element

  # The TEI parser nests a speech's lines under :elements, the Word parser under :children.
  defp nested(element), do: if(Map.has_key?(element, :elements), do: :elements, else: :children)
end
