defmodule Playcode.PlayContent.Numbering do
  @moduledoc """
  Counts a play's numbers by its numbering rule (`Playcode.Catalogue.Play`: type, restart,
  Manual) and writes the ones that differ from what is stored.

  The numbers live where the importer puts them: a verse's `line_number`, and a prose
  paragraph's own number as the `<lb n="…"/>` marker that opens its `content`; a printed
  line's number inside a paragraph is an inner marker, which only `VL` counts (the other
  types leave inner markers as they are). A bare line break is never a number.

    * `V`: each verse once, on its first piece; prose none.
    * `VP`: as `V`, and each prose paragraph, in the same series.
    * `VL`: as `V`, and each printed prose line: the paragraph's own number, then each
      inner marker.
    * `S`: one number per speech, on its first verse line or paragraph; nothing outside a
      speech.

  The count starts again at each top-level division (`act`), at each division and each
  top-level division's own text (`scene`), or never.
  """

  alias Playcode.PlayContent
  alias Playcode.PlayContent.InlineMarkup
  alias Playcode.Repo

  @whole [nil, "", "I"]
  @marker ~r/<lb n="[A-Za-z0-9.\-]+"\/>/

  @doc """
  Counts the play's numbers by its rule and writes the rows whose number changed, in one
  statement. Returns how many it wrote. A Manual play is never touched.
  """
  def recount(%{numbering_manual: true}), do: 0

  def recount(play) do
    rows = play.id |> PlayContent.reading_order() |> differences(play)
    write(rows)
    length(rows)
  end

  @doc "How many rows a recount of `play` under `setting` (its type and restart) would write."
  def changes(play, setting),
    do: play.id |> PlayContent.reading_order() |> differences(setting) |> length()

  @doc """
  The rows of `rows` (`PlayContent.reading_order/1`) whose number the rule of `setting`
  (`numbering_type`, `numbering_restart`) gives otherwise, as the rule gives them.
  """
  def differences(rows, %{numbering_type: type, numbering_restart: restart}) do
    rows
    |> expected(type, restart)
    |> Enum.zip(rows)
    |> Enum.reject(fn {new, old} ->
      new.line_number == old.line_number and new.content == old.content
    end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "`rows` with their numbers as the rule of `type` and `restart` counts them."
  def expected(rows, type, restart) do
    rows
    |> Enum.chunk_by(&unit(&1, restart))
    |> Enum.flat_map(fn unit ->
      {rows, _state} = Enum.map_reduce(unit, {0, nil}, &count(type, &1, &2))
      rows
    end)
  end

  defp unit(_row, "never"), do: :play
  defp unit(row, "act"), do: row.act_id
  defp unit(row, "scene"), do: {row.act_id, row.scene_id}

  # The state is the last number given and the speech of the row before.
  defp count("S", row, {n, previous}) do
    first? = row.speech_id != nil and row.speech_id != previous
    n = if first?, do: n + 1, else: n
    {number(row, first? && n), {n, row.speech_id}}
  end

  defp count(_type, %{type: "verse_line", part: part} = row, {n, _previous})
       when part in @whole,
       do: {number(row, n + 1), {n + 1, row.speech_id}}

  defp count(_type, %{type: "verse_line"} = row, {n, _previous}),
    do: {number(row, false), {n, row.speech_id}}

  defp count("VP", row, {n, _previous}), do: {number(row, n + 1), {n + 1, row.speech_id}}

  defp count("VL", row, {n, _previous}) do
    {_own, text} = InlineMarkup.paragraph_number(row.content)
    [first | rest] = Regex.split(@marker, text)

    lines =
      rest
      |> Enum.with_index(n + 2)
      |> Enum.map_join(fn {part, k} -> InlineMarkup.number_marker("#{k}") <> part end)

    row = number(%{row | content: first <> lines}, n + 1)
    {row, {n + 1 + length(rest), row.speech_id}}
  end

  defp count("V", row, {n, _previous}), do: {number(row, false), {n, row.speech_id}}

  defp number(%{type: "verse_line"} = row, n), do: %{row | line_number: if(n, do: "#{n}")}

  defp number(%{content: content} = row, n) do
    {_own, text} = InlineMarkup.paragraph_number(content)
    %{row | content: if(n, do: InlineMarkup.number_marker("#{n}") <> (text || ""), else: text)}
  end

  defp write([]), do: :ok

  defp write(rows) do
    Repo.query!(
      """
      UPDATE play_elements AS e SET line_number = v.n, content = v.c
      FROM unnest($1::uuid[], $2::text[], $3::text[]) AS v(id, n, c)
      WHERE e.id = v.id
      """,
      [
        Enum.map(rows, &Ecto.UUID.dump!(&1.id)),
        Enum.map(rows, & &1.line_number),
        Enum.map(rows, & &1.content)
      ]
    )
  end
end
