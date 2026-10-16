defmodule Playcode.PlayContent.InlineMarkup do
  @moduledoc """
  The importer stores `<emph>` and `<hi rend="italic">` as `<<…>>` inside element
  content, and a `<stage>` inside a verse line or a paragraph as `<stage>…</stage>`
  (`<stage type="delivery">…</stage>` with a type; the type is letters, digits and `_`).
  A stage is flat: no stage in a stage, and no stage inside italics, though italics may
  sit inside a stage. A line break is `\n`, kept as text; where a printed line of the
  source starts, its number is a marker, `<lb n="1320"/>`, and a prose paragraph's own
  number is that marker at its very start.

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

  # A printed line's number. Group: the number, letters, digits, "." and "-".
  @number ~r/<lb n="([A-Za-z0-9.\-]+)"\/>/

  @doc """
  Splits `text` into `%{text: binary, italic: boolean, stage: stage}` parts, in order.
  `stage` is nil outside a stage, else `%{type: binary | nil, run: integer}`, `run`
  counting the stages in the text, so two touching stages stay two. A printed line's
  number is `%{number: binary, text: "", italic: boolean, stage: stage}`.
  """
  def parts(nil), do: []

  def parts(text) do
    text = text |> String.replace("&lt;&lt;", "<<") |> String.replace("&gt;&gt;", ">>")

    if String.contains?(text, "<stage"),
      do: Enum.reject(with_stages(text), &empty?/1),
      else: Enum.reject(italics(text, nil), &empty?/1)
  end

  defp empty?(%{number: _}), do: false
  defp empty?(part), do: part.text == ""

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

  # A number marker is read whole inside the italics, so its "/>" cannot be taken for the
  # start of their closing ">>" (`<<sic <lb n="5"/>>>`).
  defp italics(text, stage) do
    ~r/<<((?:<lb n="[A-Za-z0-9.\-]+"\/>|.)*?)>>/s
    |> Regex.split(text, include_captures: true)
    |> Enum.flat_map(fn part ->
      case Regex.run(~r/\A<<(.*)>>\z/s, part) do
        [_, inner] -> numbers(inner, true, stage)
        nil -> numbers(part, false, stage)
      end
    end)
  end

  defp numbers(text, italic, stage) do
    if String.contains?(text, "<lb") do
      @number
      |> Regex.split(text, include_captures: true)
      |> Enum.map(fn piece ->
        case Regex.run(@number, piece) do
          [_, n] -> %{number: n, text: "", italic: italic, stage: stage}
          nil -> %{text: piece, italic: italic, stage: stage}
        end
      end)
    else
      [%{text: text, italic: italic, stage: stage}]
    end
  end

  @doc """
  As `parts/1`, with each of `notes` placed as a `%{note: note, stage: stage, italic:
  boolean}` part after the first `note.offset` graphemes of the plain text. A note at the
  end of a piece follows that piece; one inside an italic run splits it, and is `italic`. `notes` are placed by
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

    parts ++ Enum.map(rest, &%{note: &1, stage: nil, italic: false})
  end

  # Splits `part` (which starts `at` graphemes into the text) at every note that falls
  # inside it or at its end. `next` is the part after it, or nil. A number has no text to
  # split, and prepend_text/2 would drop it.
  defp place_notes([%{number: _} = part, _next], acc), do: {[part], acc}

  defp place_notes([part, next], {at, notes}) do
    length = String.length(part.text)
    {here, later} = Enum.split_while(notes, &(&1.offset <= at + length))

    {pieces, cut} =
      Enum.reduce(here, {[], 0}, fn note, {pieces, cut} ->
        k = max(note.offset - at, cut)
        piece = %{part | text: String.slice(part.text, cut, k - cut)}
        inside = if k > 0 and (k < length or same_stage?(part, next)), do: part.stage
        italic = part.italic and k > 0 and k < length
        {[%{note: note, stage: inside, italic: italic} | prepend_text(pieces, piece)], k}
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

  @doc "The marker the importer stores where printed line `n` of the source starts."
  def number_marker(n), do: ~s(<lb n="#{n}"/>)

  @doc """
  A prose paragraph's own number (TEI's `p@n`): the number of a marker at the very start
  of `text`, and the text after it. `{nil, text}` when it opens with none.
  """
  def paragraph_number(nil), do: {nil, nil}

  def paragraph_number(text) do
    case Regex.run(~r/\A<lb n="([A-Za-z0-9.\-]+)"\/>(.*)\z/s, text) do
      [_, n, rest] -> {n, rest}
      nil -> {nil, text}
    end
  end

  @doc "True when every `<lb` in `text` is a well-formed number marker."
  def numbers_well_formed?(nil), do: true
  def numbers_well_formed?(text), do: not Regex.match?(~r/<lb(?! n="[A-Za-z0-9.\-]+"\/>)/, text)

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
