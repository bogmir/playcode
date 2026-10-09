defmodule Playcode.PlayContent.InlineMarkup do
  @moduledoc """
  The importer stores `<emph>` and `<hi rend="italic">` as `<<…>>` inside element
  content, and a `<stage>` inside a verse line or a paragraph as `<stage>…</stage>`
  (`<stage type="delivery">…</stage>` with a type; the type is letters, digits and `_`).
  A stage is flat: no stage in a stage, and no stage inside italics, though italics may
  sit inside a stage.

  `parts/1` turns that back into pieces a renderer can mark up; `plain/1` gives the
  text without the markers, stage words kept, for search and word counts; `spoken/1`
  and `staged/1` split the words by where they are said. `parts/2` also places a
  line's notes between the pieces. `well_formed?/1` says whether the markers are sound.
  """

  # The type and the text of one stage. Groups: type (empty when there is none), text.
  # The text stops at the next stage tag, so a stage is flat, an empty one is no stage,
  # and a run of stages that never close costs time in proportion to its length (a
  # lazy `.*?` read to the end of the text from every `<stage>`).
  @stage ~r/<stage(?: type="([A-Za-z0-9_]+)")?>((?:(?!<\/?stage[\s>]).)+?)<\/stage>/s

  @doc """
  Splits `text` into `%{text: binary, italic: boolean, stage: stage}` parts, in order.
  `stage` is nil outside a stage, else `%{type: binary | nil, run: integer}`, `run`
  counting the stages in the text, so two touching stages stay two.
  """
  def parts(nil), do: []

  def parts(text) do
    text = text |> String.replace("&lt;&lt;", "<<") |> String.replace("&gt;&gt;", ">>")

    if String.contains?(text, "<stage"),
      do: Enum.reject(with_stages(text), &(&1.text == "")),
      else: Enum.reject(italics(text, nil), &(&1.text == ""))
  end

  defp with_stages(text) do
    {parts, _runs} =
      @stage
      |> Regex.split(text, include_captures: true)
      |> Enum.flat_map_reduce(0, fn piece, run ->
        case Regex.run(@stage, piece) do
          [_whole, type, inner] ->
            {italics(inner, %{type: if(type == "", do: nil, else: type), run: run}), run + 1}

          nil ->
            {italics(piece, nil), run}
        end
      end)

    parts
  end

  defp italics(text, stage) do
    ~r/<<(.*?)>>/s
    |> Regex.split(text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(~r/\A<<(.*)>>\z/s, part) do
        [_, inner] -> %{text: inner, italic: true, stage: stage}
        nil -> %{text: part, italic: false, stage: stage}
      end
    end)
  end

  @doc """
  As `parts/1`, with each of `notes` placed as a `%{note: note, stage: stage}` part after
  the first `note.offset` graphemes of the plain text. A note at the end of a piece
  follows that piece; one inside an italic run splits it. `notes` are placed by
  `{offset, position}` whatever their order in the list, and a note past the end of the
  text goes last.

  A note strictly inside a stage, or between two pieces of one stage, carries that
  stage; one at the start or the end of a stage's text is outside it.
  """
  def parts(text, []), do: parts(text)

  def parts(text, notes) do
    notes = Enum.sort_by(notes, &{&1.offset, &1.position})

    {parts, {_at, rest}} =
      text
      |> parts()
      |> Enum.chunk_every(2, 1, [nil])
      |> Enum.flat_map_reduce({0, notes}, &place_notes/2)

    parts ++ Enum.map(rest, &%{note: &1, stage: nil})
  end

  # Splits `part` (which starts `at` graphemes into the text) at every note that falls
  # inside it or at its end. `next` is the part after it, or nil.
  defp place_notes([part, next], {at, notes}) do
    length = String.length(part.text)
    {here, later} = Enum.split_while(notes, &(&1.offset <= at + length))

    {pieces, cut} =
      Enum.reduce(here, {[], 0}, fn note, {pieces, cut} ->
        k = max(note.offset - at, cut)
        piece = %{part | text: String.slice(part.text, cut, k - cut)}
        inside = if k > 0 and (k < length or same_stage?(part, next)), do: part.stage
        {[%{note: note, stage: inside} | prepend_text(pieces, piece)], k}
      end)

    rest = %{part | text: String.slice(part.text, cut..-1//1)}
    {Enum.reverse(prepend_text(pieces, rest)), {at + length, later}}
  end

  defp same_stage?(%{stage: %{run: run}}, %{stage: %{run: run}}), do: true
  defp same_stage?(_part, _next), do: false

  defp prepend_text(pieces, %{text: ""}), do: pieces
  defp prepend_text(pieces, part), do: [part | pieces]

  @doc "`text` without the `<<` and `>>` markers and the stage tags."
  def plain(text), do: text |> parts() |> Enum.map_join(& &1.text)

  @doc "The text outside every stage, with a space where a stage was."
  def spoken(text),
    do: text |> parts() |> Enum.map_join(&if(&1.stage, do: " ", else: &1.text))

  @doc "The text of the stages only, one space between them."
  def staged(text),
    do: text |> parts() |> Enum.filter(& &1.stage) |> Enum.map_join(" ", & &1.text)

  @doc "How many stage markers `text` holds."
  def stage_count(nil), do: 0
  def stage_count(text), do: @stage |> Regex.scan(text) |> length()

  @doc """
  True when every `<stage` and `</stage>` in `text` belongs to a closed, flat marker with
  a valid type, and no stage sits inside italics.
  """
  def well_formed?(nil), do: true

  def well_formed?(text) do
    without_stages = Regex.replace(@stage, text, fn _all, _type, inner -> inner end)

    not (Regex.match?(~r/<\/?stage/, without_stages) or
           Regex.match?(~r/<<(?:(?!>>).)*?<\/?stage/s, text))
  end
end
