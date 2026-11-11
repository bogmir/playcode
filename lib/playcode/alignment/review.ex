defmodule Playcode.Alignment.Review do
  @moduledoc """
  The admin comparison's pair review (problem 5, step 5): `Playcode.Alignment`'s pairing of
  a translation's speeches with its original's, as rows for a person to check. Kept out of
  `Alignment`, which the static site fingerprints, so that tuning the review rebuilds no
  page.
  """

  alias Playcode.Alignment
  alias Playcode.Statistics.Metrics

  # Tuned on dev (2026-11-11): marks 0084's rows 89 and 91 (5 words against 19, 18 against
  # 3) and 1,182 (1.15%) of the 102,351 same-speaker rows of 145 translations.
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
    speeches = Map.merge(speech_places(original_divisions), speech_places(translation_divisions))
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
    {o, place} = original || {nil, []}
    {t, _} = translation || {nil, []}
    %{kind: kind, place: place, original: o, translation: t, long: kind == :same and long?(o, t)}
  end

  defp long?(o, t) do
    [short, long] = Enum.sort([words(o), words(t)])
    long > @long_floor and long > @long_ratio * short
  end

  defp words(speech), do: speech |> spoken_text() |> Metrics.words()

  # Each speech by id, with the act and scene it stands in.
  defp speech_places(divisions) do
    for top <- divisions,
        {division, place} <- [
          {top, [top]} | Enum.map(Map.get(top, :children, []), &{&1, [top, &1]})
        ],
        %{type: "speech"} = el <- Map.get(division, :loaded_elements, []),
        into: %{},
        do: {el.id, {el, place}}
  end

  @doc "A speech's spoken text: its verse lines and paragraphs, not its stage directions."
  def spoken_text(speech), do: speech |> spoken_lines() |> Enum.map_join(" ", & &1.content)

  @doc "The speech's first verse line or paragraph, or nil."
  def first_line(speech), do: speech |> spoken_lines() |> List.first()

  defp spoken_lines(%{type: type} = el) when type in ~w(verse_line prose), do: [el]

  defp spoken_lines(%{children: children}) when is_list(children),
    do: Enum.flat_map(children, &spoken_lines/1)

  defp spoken_lines(_), do: []
end
