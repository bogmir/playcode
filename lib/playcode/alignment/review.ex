defmodule Playcode.Alignment.Review do
  @moduledoc """
  The admin comparison's pair review (problem 5, step 5): `Playcode.Alignment`'s pairing of
  a translation's speeches with its original's, as rows for a person to check. Kept out of
  `Alignment`, which the static site fingerprints, so that tuning the review rebuilds no
  page.
  """

  alias Playcode.Alignment
  alias Playcode.PlayContent.{Element, InlineMarkup}

  # Tuned on dev (2026-11-11): marks 0084's rows 89 and 91 (5 words against 19, 18 against
  # 3) and 1,172 (1.15%) of the 102,351 same-speaker rows of 145 translations. A word is
  # what lies between spaces, so "N’est-ce" is one and a lone dash is one.
  @long_ratio 3.5
  @long_floor 15

  @doc """
  The pairing of `translation_divisions`' speeches with `original_divisions`', as rows, in
  the original's reading order: each original speech followed by the translation speeches
  that go with it, a cut as a row with no translation, an addition before the first
  original speech at the start. Each row has its `kind`, the original speech's act and
  scene (`place`), both speech elements and `long`: one speaker on both sides, but one
  speech over #{@long_ratio} times the other's words and over #{@long_floor} words, which
  is how a stretch paired one speech off shows (the researcher's rows 89 and 91 of 0084).
  """
  def rows(original_divisions, translation_divisions) do
    {original_ids, pairs} = Alignment.speech_pairs(original_divisions, translation_divisions)
    speeches = Map.merge(speeches(original_divisions), speeches(translation_divisions))
    by_original = Enum.group_by(pairs, & &1.original)
    row = fn kind, o, t -> row(kind, speeches[o], speeches[t]) end

    Enum.map(Map.get(by_original, nil, []), &row.(&1.kind, nil, &1.id)) ++
      Enum.flat_map(original_ids, fn id ->
        case by_original[id] do
          nil -> [row.(:cut, id, nil)]
          pairs -> Enum.map(pairs, &row.(&1.kind, id, &1.id))
        end
      end)
  end

  defp row(kind, original, translation) do
    %{
      kind: kind,
      place: if(original, do: original.place, else: ""),
      original: original && original.view,
      translation: translation && translation.view,
      long: kind == :same and long?(original.words, translation.words)
    }
  end

  defp long?(a, b) do
    [short, long] = Enum.sort([a, b])
    long > @long_floor and long > @long_ratio * short
  end

  # Each speech by id, with its act and scene, prepared once however many rows it is in.
  defp speeches(divisions) do
    for top <- divisions,
        {division, place} <- [
          {top, place([top])} | Enum.map(Map.get(top, :children, []), &{&1, place([top, &1])})
        ],
        %{type: "speech"} = el <- Map.get(division, :loaded_elements, []),
        into: %{},
        do: {el.id, Map.put(speech(el), :place, place)}
  end

  defp place(divisions), do: Enum.map_join(divisions, ", ", &place_label/1)

  defp place_label(division),
    do:
      InlineMarkup.plain(
        division.title ||
          String.capitalize("#{division.type}#{division.number && " #{division.number}"}")
      )

  # Plain data only: the rows are sent from a background task to the page, and a message
  # copies each term in full, so an element here would copy its whole speech once per row.
  # The view is what the page prints: the speaker, the first line's number, the opening
  # words, the first 120 characters on hover, and the character the speaker links to.
  defp speech(el) do
    lines = spoken_lines(el)
    text = lines |> Enum.map_join(" ", & &1.content) |> InlineMarkup.plain()
    words = String.split(text)
    first = List.first(lines)

    %{
      words: length(words),
      view: %{
        id: el.id,
        speaker: InlineMarkup.plain(el.speaker_label || ""),
        n: first && first.line_number,
        opening: words |> Enum.take(8) |> Enum.join(" "),
        hover: if(String.length(text) > 120, do: String.slice(text, 0, 120) <> "…", else: text),
        character_id: el |> Element.characters() |> Enum.map(& &1.id) |> List.first()
      }
    }
  end

  # A speech's verse lines and paragraphs, not its stage directions.
  defp spoken_lines(%{type: type} = el) when type in ~w(verse_line prose), do: [el]

  defp spoken_lines(%{children: children}) when is_list(children),
    do: Enum.flat_map(children, &spoken_lines/1)

  defp spoken_lines(_), do: []
end
