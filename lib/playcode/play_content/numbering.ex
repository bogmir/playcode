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

  alias Playcode.{Catalogue, PlayContent, Repo}
  alias Playcode.PlayContent.InlineMarkup

  @whole [nil, "", "I"]
  @marker ~r/<lb n="[A-Za-z0-9.\-]+"\/>/

  # In the order a tie goes: the simpler rule first.
  @rules for type <- ~w(V VP VL S),
             restart <- ~w(never act scene),
             do: %{numbering_type: type, numbering_restart: restart}

  @doc """
  The rule a play's stored numbers follow. A rule they fit exactly is taken, not Manual;
  otherwise the closest (fewest rows differing), Manual. A play with no number at all is
  `unnumbered`: V when it has at least as many verses as prose paragraphs, otherwise S,
  never restarting, not Manual (the researcher, 2026-11-08). Returns the three columns plus
  `differ` and `unnumbered`.
  """
  def detect(rows) do
    if Enum.all?(rows, &unnumbered?/1) do
      verses = Enum.count(rows, &(&1.type == "verse_line" and &1.part in @whole))
      paragraphs = Enum.count(rows, &(&1.type == "prose"))

      %{
        numbering_type: if(paragraphs > verses, do: "S", else: "V"),
        numbering_restart: "never",
        numbering_manual: false,
        differ: 0,
        # A play without verse or prose has nothing to number.
        unnumbered: rows != []
      }
    else
      {rule, differ} =
        @rules
        |> Enum.map(&{&1, length(differences(rows, &1))})
        |> Enum.min_by(&elem(&1, 1))

      Map.merge(rule, %{numbering_manual: differ > 0, differ: differ, unnumbered: false})
    end
  end

  defp unnumbered?(%{type: "verse_line", line_number: n}), do: is_nil(n)
  defp unnumbered?(%{content: content}), do: not Regex.match?(@marker, content || "")

  @doc """
  Settles the numbering rule of a play just imported. `from_header?`: the file's header gave
  the rule, which stands, but a play that is not Manual and whose numbers break it is made
  Manual. Otherwise the rule is detected (`detect/1`). Then the play is recounted, which
  numbers an unnumbered one and changes nothing else. Returns the play and a report for
  `describe/1`.
  """
  def settle(play, true) do
    differ =
      if play.numbering_manual,
        do: 0,
        else: play.id |> PlayContent.reading_order() |> differences(play) |> length()

    play = if differ > 0, do: update!(play, %{numbering_manual: true}), else: play

    {play, Map.merge(rule(play), %{differ: differ, unnumbered: false, header_broken: differ > 0})}
  end

  def settle(play, false) do
    detected = play.id |> PlayContent.reading_order() |> detect()

    play =
      update!(play, Map.take(detected, [:numbering_type, :numbering_restart, :numbering_manual]))

    recount(play)
    {play, Map.put(detected, :header_broken, false)}
  end

  defp rule(play), do: Map.take(play, [:numbering_type, :numbering_restart, :numbering_manual])

  defp update!(play, attrs) do
    {:ok, play} = Catalogue.update_play(play, attrs)
    play
  end

  @doc """
  A `settle/2` report as the import preview and the corpus tools print it: "V per scene",
  "V never, Manual: 3 numbers differ", "S never, numbers added", "VP per act, Manual: the
  header's rule breaks on 2 numbers".
  """
  def describe(report) do
    rule = name(report)

    cond do
      report.header_broken ->
        "#{rule}, Manual: the header's rule breaks on #{count(report.differ)}"

      report.unnumbered ->
        "#{rule}, numbers added"

      report.differ > 0 ->
        "#{rule}, Manual: #{differ(report.differ)}"

      report.numbering_manual ->
        "#{rule}, Manual"

      true ->
        rule
    end
  end

  @doc ~s(A rule by name: "V never", "VP per act", "S per scene".)
  def name(rule), do: "#{rule.numbering_type} #{restart(rule.numbering_restart)}"

  defp restart("never"), do: "never"
  defp restart(unit), do: "per #{unit}"

  defp count(1), do: "1 number"
  defp count(n), do: "#{n} numbers"

  defp differ(1), do: "1 number differs"
  defp differ(n), do: "#{n} numbers differ"

  @doc """
  Counts the play's numbers by its rule and writes the rows whose number changed, in one
  statement. Returns how many it wrote. A Manual play is never touched.
  """
  def recount(%{numbering_manual: true}), do: 0

  def recount(play) do
    stored = PlayContent.reading_order(play.id)
    rows = differences(stored, play)
    write(rows, Map.new(stored, &{&1.id, &1.content}))
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
      new.line_number == unpadded(old.line_number) and new.content == unpadded(old.content)
    end)
    |> Enum.map(&elem(&1, 0))
  end

  # A padded number is the same number ("0001" is "1", as problem 1 stores a verse's): a
  # paragraph's markers may still be padded as their file wrote them, and stay so.
  defp unpadded(nil), do: nil
  defp unpadded(text), do: Regex.replace(~r/(?<=\A|n=")0+(?=\d+(?:\z|"))/, text, "")

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
    [first | rest] = Regex.split(@marker, text || "")

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

  defp write([], _read), do: :ok

  # A row whose text changed since it was read (another save in between) is left alone: its
  # stale text would undo that save, whose own recount numbers it.
  defp write(rows, read) do
    Repo.query!(
      """
      UPDATE play_elements AS e SET line_number = v.n, content = v.c
      FROM unnest($1::uuid[], $2::text[], $3::text[], $4::text[]) AS v(id, n, c, read)
      WHERE e.id = v.id AND e.content IS NOT DISTINCT FROM v.read
      """,
      [
        Enum.map(rows, &Ecto.UUID.dump!(&1.id)),
        Enum.map(rows, & &1.line_number),
        Enum.map(rows, & &1.content),
        Enum.map(rows, &read[&1.id])
      ]
    )
  end
end
