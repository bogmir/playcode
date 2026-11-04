defmodule Playcode.PlayContent.InlineMarkup do
  @moduledoc """
  The importer stores `<emph>` and `<hi rend="italic">` as `<<…>>` inside element
  content, and a `<stage>` inside a verse line or a paragraph as `<stage>…</stage>`
  (`<stage type="delivery">…</stage>` with a type; the type is letters, digits and `_`).
  A stage is flat: no stage in a stage, and no stage inside italics, though italics may
  sit inside a stage. A line break is `\n`, kept as text; where a printed line of the
  source starts, its number is a marker, `<lb n="1320"/>`, and a prose paragraph's own
  number is that marker at its very start. In a line or paragraph partly spoken aside,
  each aside is `<aside>…</aside>`, flat, outside any stage or italics (a whole aside is
  the element's `is_aside` alone, `Element.whole_aside?/1`); the pieces below leave it out.

  A Folio passage (Hamlet's words only the 1623 Folio prints) is `<folio>…</folio>`, flat,
  outside any stage or italics and holding no aside, though it may sit inside an aside; a
  passage that crosses elements is a marker in each, with `part="I"` (its start, ending the
  text), `"M"` (all of it) or `"F"` (its end, starting the text). Its parts carry `:folio`.

  The words of a name, a place or a phrase the edition tags (TEI's `<rs>`) are
  `<rs type="…" n="…">…</rs>`, both attributes optional: flat, inside or outside a stage
  but never holding one, and outside italics, though italics may sit inside it. Its parts
  carry `:rs`.

  `parts/1` turns that back into pieces a renderer can mark up; `plain/1` gives the
  text without the markers, stage words kept, for search and word counts; `spoken/1`
  and `staged/1` split the words by where they are said. `parts/2` also places a
  line's notes between the pieces. `well_formed?/1`, `asides_well_formed?/1`,
  `numbers_well_formed?/1`, `folios_well_formed?/1` and `rs_well_formed?/1` say whether the
  markers are sound.
  """

  # The type and the text of one stage. Groups: type (empty when there is none), text.
  # The text stops at the next stage tag, so a stage is flat, an empty one is no stage,
  # and a run of stages that never close costs time in proportion to its length (a
  # lazy `.*?` read to the end of the text from every `<stage>`).
  @stage ~r/<stage(?: type="([A-Za-z0-9_]+)")?>((?:(?!<\/?stage[\s>]).)+?)<\/stage>/s

  # One Folio passage. Groups: the part ("I", "M", "F", or empty for a passage inside one
  # text), the words. Flat, like a stage; one with nothing but white space is no passage.
  @folio ~r/<folio(?: part="([IMF])")?>(\s*(?:(?!<\/?folio[\s>])\S)(?:(?!<\/?folio[\s>]).)*?)<\/folio>/s

  # One tagged name, place or phrase. Groups: its type, its number (each empty when
  # absent), its words. Flat, like a stage.
  @rs ~r/<rs(?: type="([A-Za-z0-9_.\-]+)")?(?: n="([A-Za-z0-9_.\-]+)")?>((?:(?!<\/?rs[\s>]).)+?)<\/rs>/s

  # A printed line's number. Group: the number, letters, digits, "." and "-".
  @number ~r/<lb n="([A-Za-z0-9.\-]+)"\/>/

  @doc """
  Splits `text` into `%{text: binary, italic: boolean, stage: stage}` parts, in order.
  `stage` is nil outside a stage, else `%{type: binary | nil, run: integer}`, `run`
  counting the stages in the text, so two touching stages stay two. A printed line's
  number is `%{number: binary, text: "", italic: boolean, stage: stage}`.

  A part inside an `<rs>` also has `rs: %{type: binary | nil, n: binary | nil, run:
  integer}`; `run` tells two touching tags apart within one stage or passage (it starts
  again in each, as no tag crosses one). Outside one the key is absent.

  A part inside a Folio passage also has `folio: %{part: nil | "I" | "M" | "F", run:
  integer}`, `run` counting the passages in the text; outside one the key is absent.
  Stages are counted through the whole text, so a stage inside a passage and one outside
  never share a run.
  """
  def parts(nil), do: []

  def parts(text) do
    text =
      text
      |> String.replace("&lt;&lt;", "<<")
      |> String.replace("&gt;&gt;", ">>")
      |> String.replace(["<aside>", "</aside>"], "")

    if String.contains?(text, "<folio") do
      with_folios(text)
    else
      {parts, _stages} = unmarked(text, 0)
      parts
    end
  end

  # The parts of each passage carry it; stages are counted through the whole text.
  defp with_folios(text) do
    {parts, _counts} =
      @folio
      |> Regex.split(text, include_captures: true)
      |> Enum.flat_map_reduce({0, 0}, fn piece, {folios, stages} ->
        case Regex.run(@folio, piece) do
          [_whole, part, inner] ->
            folio = %{part: if(part == "", do: nil, else: part), run: folios}
            {parts, stages} = unmarked(inner, stages)
            {Enum.map(parts, &Map.put(&1, :folio, folio)), {folios + 1, stages}}

          nil ->
            {parts, stages} = unmarked(piece, stages)
            {parts, {folios, stages}}
        end
      end)

    parts
  end

  # The parts of a text with no passage in it, and the number of stage runs after it.
  defp unmarked(text, stages) do
    {parts, stages} =
      if String.contains?(text, "<stage"),
        do: with_stages(text, stages),
        else: {italics(text, nil), stages}

    {Enum.reject(parts, &empty?/1), stages}
  end

  defp empty?(%{number: _}), do: false
  defp empty?(part), do: part.text == ""

  defp with_stages(text, runs) do
    @stage
    |> Regex.split(text, include_captures: true)
    |> Enum.flat_map_reduce(runs, fn piece, run ->
      case Regex.run(@stage, piece) do
        [_whole, type, inner] ->
          {italics(inner, %{type: if(type == "", do: nil, else: type), run: run}), run + 1}

        nil ->
          {italics(piece, nil), run}
      end
    end)
  end

  # The tagged words of a text are its italics' parts, each carrying its tag.
  defp italics(text, stage) do
    if String.contains?(text, "<rs") do
      @rs
      |> Regex.split(text, include_captures: true)
      |> Enum.with_index()
      |> Enum.flat_map(fn {piece, run} ->
        case Regex.run(@rs, piece) do
          [_whole, type, n, words] ->
            rs = %{type: blank_to_nil(type), n: blank_to_nil(n), run: run}
            words |> plain_italics(stage) |> Enum.map(&Map.put(&1, :rs, rs))

          nil ->
            plain_italics(piece, stage)
        end
      end)
    else
      plain_italics(text, stage)
    end
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  # A number marker is read whole inside the italics, so its "/>" cannot be taken for the
  # start of their closing ">>" (`<<sic <lb n="5"/>>>`).
  defp plain_italics(text, stage) do
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
  stage; one at the start or the end of a stage's text is outside it. A note takes a
  Folio passage the same way, as `:folio`. A note at the end of an `<rs>`'s words takes
  its tag, `:rs`, unless the tag ends a stage the note is outside: it is taken to be about
  those words, the form question 63 chose (EMOTHE0551 puts 19 such notes inside, 22 after).
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
        inside = if k > 0 and (k < length or same_run?(part, next, :stage)), do: part.stage

        folio =
          if k > 0 and (k < length or same_run?(part, next, :folio)), do: Map.get(part, :folio)

        rs = if k > 0 and (is_nil(part.stage) or inside), do: Map.get(part, :rs)
        italic = part.italic and k > 0 and k < length
        note = %{note: note, stage: inside, italic: italic}
        note = if folio, do: Map.put(note, :folio, folio), else: note
        note = if rs, do: Map.put(note, :rs, rs), else: note
        {[note | prepend_text(pieces, piece)], k}
      end)

    rest = %{part | text: String.slice(part.text, cut..-1//1)}
    {Enum.reverse(prepend_text(pieces, rest)), {at + length, later}}
  end

  # Two touching parts of one stage, or of one passage.
  defp same_run?(part, next, key) do
    case {Map.get(part, key), next && Map.get(next, key)} do
      {%{run: run}, %{run: run}} -> true
      _ -> false
    end
  end

  defp prepend_text(pieces, %{text: ""}), do: pieces
  defp prepend_text(pieces, part), do: [part | pieces]

  @doc "`text` without the `<<` and `>>` markers and the stage and Folio passage tags."
  def plain(text), do: text |> parts() |> Enum.map_join(& &1.text)

  @doc "The text outside every stage, with a space where a stage was."
  def spoken(text),
    do: text |> parts() |> Enum.map_join(&if(&1.stage, do: " ", else: &1.text))

  @doc "The text of the stages only, one space between them."
  def staged(text),
    do: text |> parts() |> Enum.filter(& &1.stage) |> Enum.map_join(" ", & &1.text)

  @doc """
  `parts` with an F where each Folio passage starts and where it ends, as readers see it:
  `%{label: "F", text: "", italic: false, stage: stage, folio: folio}`. A piece with part
  "M" or "F" opens no passage and one with "M" or "I" closes none: the passage goes on in
  the element before or after.

  A label is in the stage direction its passage's first (opening) or last (closing) word
  is in, a space aside, and has no stage when that word has none: hiding the stage
  directions then hides the F's with the words they bracket.
  """
  def folio_labels(parts) do
    parts
    |> Enum.chunk_by(&folio_run/1)
    |> Enum.flat_map(fn
      [%{folio: folio} | _] = run ->
        open = if folio.part in ["M", "F"], do: [], else: [folio_label(folio, run)]
        close = if folio.part in ["M", "I"], do: [], else: [folio_label(folio, Enum.reverse(run))]
        open ++ run ++ close

      outside ->
        outside
    end)
  end

  # `words`: the passage's parts, from the label's side inwards.
  defp folio_label(folio, words) do
    word = Enum.find(words, &(String.trim(Map.get(&1, :text, "")) != "")) || hd(words)
    %{label: "F", text: "", italic: false, stage: word.stage, folio: folio}
  end

  defp folio_run(part) do
    case Map.get(part, :folio) do
      %{run: run} -> run
      nil -> nil
    end
  end

  @doc "True when every word of `text` is in a Folio passage, a printed line's number aside."
  def whole_folio?(nil), do: false

  def whole_folio?(text) do
    String.contains?(text, "<folio") and
      @folio |> Regex.replace(text, "") |> String.replace(@number, "") |> String.trim() == ""
  end

  @doc """
  The stages `text` holds, in order: `%{type: binary | nil, text: binary}`, the text with
  its markers (italics, tagged names) as stored.
  """
  def stages(nil), do: []

  def stages(text) do
    for [type, words] <- Regex.scan(@stage, text, capture: :all_but_first),
        do: %{type: if(type != "", do: type), text: words}
  end

  @doc "How many stage markers `text` holds."
  def stage_count(nil), do: 0
  def stage_count(text), do: @stage |> Regex.scan(text) |> length()

  @doc """
  The marker the importer stores where printed line `n` of the source starts, or `""` when
  `n` is absent or not a number the marker can hold (letters, digits, `.` and `-`).
  """
  def number_marker(nil), do: ""
  def number_marker(n), do: if(n =~ ~r/\A[A-Za-z0-9.\-]+\z/, do: ~s(<lb n="#{n}"/>), else: "")

  @doc """
  A stage's opening and closing markers, `{open, close}`, its `type` in the opening one
  when it is the plain word the marker allows (letters, digits and `_`).
  """
  def stage_marker(type) do
    open =
      if type && type =~ ~r/\A[A-Za-z0-9_]+\z/, do: ~s(<stage type="#{type}">), else: "<stage>"

    {open, "</stage>"}
  end

  @doc """
  A tagged name, place or phrase's markers, `{open, close}`, its `type` and `n` each in the
  opening one when it is a plain word the marker allows (letters, digits, `_`, `.`, `-`).
  """
  def rs_marker(type, n) do
    pairs =
      for {key, value} <- [type: type, n: n],
          value && value =~ ~r/\A[A-Za-z0-9_.\-]+\z/,
          do: ~s( #{key}="#{value}")

    {"<rs#{pairs}>", "</rs>"}
  end

  # Any one marker, opening or closing, whether or not its partner is in the text.
  @any_marker ~r/<<|>>|<stage(?: type="[A-Za-z0-9_]+")?>|<\/stage>|<\/?aside>|<folio(?: part="[IMF]")?>|<\/folio>|<rs(?: type="[A-Za-z0-9_.\-]+")?(?: n="[A-Za-z0-9_.\-]+")?>|<\/rs>|<lb n="[A-Za-z0-9.\-]+"\/>/

  @doc """
  `text` with every marker taken out, one at a time, its words kept: a text cut inside an
  italic run or a stage, its closing marker still to come, loses its opening one too,
  which `plain/1`, reading whole markers, leaves.
  """
  def strip(text), do: String.replace(text, @any_marker, "")

  @doc "An aside's markers, `{open, close}`."
  def aside_marker, do: {"<aside>", "</aside>"}

  @doc """
  `text` in the order it is read, cut where each aside starts and ends: `{:aside, words}`
  for the words inside an `<aside>` marker, `{:spoken, words}` for those around them,
  each with its other markers; no empty piece.
  """
  def asides(nil), do: []

  def asides(text) do
    ~r{<aside>.*?</aside>}s
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(fn
      "<aside>" <> rest -> {:aside, String.replace_suffix(rest, "</aside>", "")}
      words -> {:spoken, words}
    end)
  end

  @doc """
  A Folio passage's markers, `{open, close}`: `part` nil for a passage inside one text, else
  `"I"`, `"M"` or `"F"` for the piece of one that crosses texts.
  """
  def folio_marker(nil), do: {"<folio>", "</folio>"}
  def folio_marker(part) when part in ~w(I M F), do: {~s(<folio part="#{part}">), "</folio>"}

  @folio_part ~r/<folio part="([IMF])">/

  @doc "The parts of the crossing Folio pieces in `text`, in order (`folio_marker/1`)."
  def folio_parts(text), do: for([_, part] <- Regex.scan(@folio_part, text || ""), do: part)

  @doc """
  `text` with each crossing Folio piece's part given by `fun`, which takes its part and
  returns the new one, or nil to make it a passage inside the text.
  """
  def map_folio_parts(text, fun),
    do:
      Regex.replace(@folio_part, text, fn _tag, part ->
        part |> fun.() |> folio_marker() |> elem(0)
      end)

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

  @doc """
  True when every `<aside>` and `</aside>` in `text` belongs to a closed, flat marker with
  words in it, and none sits inside a stage or italics.
  """
  def asides_well_formed?(nil), do: true

  def asides_well_formed?(text) do
    without_asides = Regex.replace(~r{<aside>((?:(?!</?aside>).)+?)</aside>}s, text, "\\1")

    not (String.contains?(without_asides, ["<aside>", "</aside>"]) or
           Regex.match?(~r{<<(?:(?!>>).)*?</?aside>}s, text) or
           Regex.match?(~r{<stage[^>]*>(?:(?!</stage>).)*?</?aside>}s, text))
  end

  @doc """
  True when every `<folio` and `</folio>` in `text` belongs to a closed, flat marker with
  words in it and a valid part, none sits inside italics or a stage, none holds an aside,
  and each part is where its passage meets the text's edge: "I" ends it, "F" starts it,
  "M" is all of it (a paragraph's own number before them aside).
  """
  def folios_well_formed?(nil), do: true

  def folios_well_formed?(text) do
    without_folios = Regex.replace(@folio, text, "")
    {_number, edges} = text |> String.trim() |> paragraph_number()
    edges = String.trim(edges)

    not (String.contains?(without_folios, ["<folio", "</folio>"]) or
           Enum.any?(Regex.scan(@folio, text), &wordless?/1) or
           Regex.match?(~r/<<(?:(?!>>).)*?<\/?folio/s, text) or
           Regex.match?(~r/<stage[^>]*>(?:(?!<\/stage>).)*?<\/?folio/s, text) or
           Regex.match?(~r/<folio[^>]*>(?:(?!<\/folio>).)*?<\/?aside>/s, text) or
           Regex.match?(~r/<folio part="[IM]">(?:(?!<\/folio>).)*<\/folio>\s*\S/s, edges) or
           Regex.match?(~r/\S\s*<folio part="[MF]">/s, edges))
  end

  # A passage whose markers hold nothing but tags: a printed line's number, empty italics.
  defp wordless?([_whole, _part, words]), do: words |> plain() |> String.trim() == ""

  @doc """
  True when every `<rs` and `</rs>` in `text` belongs to a closed, flat marker with words
  in it and plain-word attributes, none sits inside italics, and none holds or crosses a
  stage or a Folio passage.
  """
  def rs_well_formed?(nil), do: true

  def rs_well_formed?(text) do
    without_rs = Regex.replace(@rs, text, "")

    not (Regex.match?(~r/<\/?rs[\s>]/, without_rs) or
           Regex.match?(~r/<<(?:(?!>>).)*?<\/?rs[\s>]/s, text) or
           Regex.match?(~r/<rs[^>]*>(?:(?!<\/rs>).)*?<\/?(?:stage|folio)/s, text))
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
