defmodule Playcode.Import.WordParser do
  @moduledoc """
  Parses EMOTHE "premarcado" Word (.docx) files into play content structure.

  The premarcación system uses tags like {v}, {p}, {ac}, {pr} etc. at the start
  of each paragraph to annotate structural elements of a play text.
  """

  alias Playcode.{Catalogue, PlayContent}
  alias Playcode.Import.WordDraft
  alias Playcode.PlayContent.{Element, InlineMarkup}

  @doc "The paragraphs of the premarked .docx at `path`, in order, as plain text."
  def paragraphs(path) do
    with {:ok, zip_handle} <- open_zip(path),
         {:ok, document_xml} <- read_zip_entry(zip_handle, ~c"word/document.xml") do
      paragraphs = extract_paragraphs_from_xml(document_xml)
      {:ok, paragraphs}
    end
  end

  @doc """
  Pasted text as the paragraphs a .docx would give: one per line, a blank line kept as `""`,
  so a paragraph's index is its line in the text box.
  """
  def paragraphs_from_text(text), do: String.split(text, ~r/\r?\n/)

  defp unescape_xml(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&apos;", "'")
  end

  defp open_zip(path) do
    path_charlist = String.to_charlist(path)

    case :zip.unzip(path_charlist, [:memory]) do
      {:ok, entries} -> {:ok, entries}
      {:error, reason} -> {:error, {:zip_error, reason}}
    end
  end

  defp read_zip_entry(entries, entry_name) when is_list(entries) do
    case Enum.find(entries, fn {name, _data} -> name == entry_name end) do
      {_name, data} -> {:ok, data}
      nil -> {:error, {:missing_entry, entry_name}}
    end
  end

  defp extract_paragraphs_from_xml(xml_binary) do
    xml_string = to_string(xml_binary)

    Regex.scan(~r/<w:p\b[^>]*>.*?<\/w:p>/s, xml_string)
    |> Enum.map(fn [paragraph_xml] ->
      Regex.scan(~r/<w:t[^>]*>(.*?)<\/w:t>/s, paragraph_xml)
      |> Enum.map(fn [_full, text] -> unescape_xml(text) end)
      |> Enum.join("")
    end)
  end

  # Parses a single line of premarcado text into a list of tagged segments.
  #
  # Returns a list of `{tag, text}` tuples where tag is one of:
  # :scene, :stage_direction, :aside, :speaker, :verse, :verse_initial,
  # :verse_middle, :verse_final, :prose, :stanza, or :text (untagged).
  defp parse_line(line) do
    line
    |> split_into_tag_segments()
    |> Enum.map(fn {tag, text} -> {tag_to_atom(tag), String.trim(text)} end)
  end

  @tags "e|ac|ap|p|v|ti|tm|tf|pr|m|a"
  @tag_pattern ~r/\{\s*(#{@tags})\s*\}/i

  defp split_into_tag_segments(line) do
    parts = Regex.split(@tag_pattern, line, include_captures: true)

    parts
    |> chunk_tag_text([])
    |> Enum.reject(fn {_tag, text} -> tag_empty_filler?(text) end)
  end

  defp chunk_tag_text([], acc), do: Enum.reverse(acc)

  defp chunk_tag_text([head | rest], acc) do
    if Regex.match?(@tag_pattern, head) do
      [_, tag_name] = Regex.run(@tag_pattern, head)

      {text, remaining} =
        case rest do
          [next | more] ->
            if Regex.match?(@tag_pattern, next) do
              {"", rest}
            else
              {next, more}
            end

          [] ->
            {"", []}
        end

      chunk_tag_text(remaining, [{String.downcase(tag_name), text} | acc])
    else
      if String.trim(head) != "" do
        chunk_tag_text(rest, [{"text", head} | acc])
      else
        chunk_tag_text(rest, acc)
      end
    end
  end

  defp tag_empty_filler?(_text), do: false

  defp tag_to_atom("e"), do: :scene
  defp tag_to_atom("ac"), do: :stage_direction
  defp tag_to_atom("ap"), do: :aside
  defp tag_to_atom("p"), do: :speaker
  defp tag_to_atom("v"), do: :verse
  defp tag_to_atom("ti"), do: :verse_initial
  defp tag_to_atom("tm"), do: :verse_middle
  defp tag_to_atom("tf"), do: :verse_final
  defp tag_to_atom("pr"), do: :prose
  defp tag_to_atom("m"), do: :stanza
  defp tag_to_atom("a"), do: :act
  defp tag_to_atom("text"), do: :text

  # Parses a list of paragraph strings into a structured representation
  # of acts, scenes, and elements (without DB interaction).
  #
  # Returns `{:ok, %{acts: [...], warnings: [...]}}` or `{:error, reason}`.
  defp parse_content(paragraphs) do
    {lines, closings, continued} = paragraphs |> Enum.map(&parse_line/1) |> mend()
    parsed_lines = Enum.with_index(lines)

    {front_lines, content_lines} = split_front_matter(parsed_lines)

    state = %{current_speech: nil, line: nil, closings: closings, continued: continued}

    {acts, _state} =
      Enum.reduce(content_lines, {[], state}, fn {segments, line}, {acts, state} ->
        process_line(segments, acts, %{state | line: line})
      end)

    acts = finalize_structure(acts)

    acts =
      if acts == [] do
        [%{type: "acto", head: nil, scenes: []}]
      else
        acts
      end

    front_matter =
      front_lines
      |> Enum.map(fn {segments, _line} -> segments_to_text(segments) end)
      |> Enum.filter(&(&1 != ""))
      |> Enum.join("\n")

    front_matter = if front_matter == "", do: nil, else: front_matter

    text_starts = length(front_lines)

    warnings =
      for {segments, line} <- parsed_lines,
          kind <- paragraph_warnings(segments, line >= text_starts),
          do: %{line: line, kind: kind}

    {:ok, %{acts: acts, front_matter: front_matter, warnings: warnings}}
  end

  @spoken_tags [:verse, :verse_initial, :verse_middle, :verse_final, :prose]

  # What the text can mean only one way is read that way, each paragraph keeping its line: a
  # speaker's name under another tag, before the speech's own, is the speaker; an untagged
  # paragraph after a speech's prose is the rest of it (the .docx breaks prose, often
  # mid-sentence), joined onto it and left empty itself; an aside such a break cuts, closed
  # later in the speech, is closed at the break and goes on in the next spoken paragraph.
  defp mend(lines) do
    speakers =
      for segments <- lines,
          {:speaker, name} <- segments,
          into: MapSet.new(),
          do: String.upcase(name)

    lines = Enum.map(lines, &as_speaker(&1, speakers))
    closings = closing_lines(lines)
    {lines, continued} = lines |> join_prose(closings) |> carry_asides()
    {lines, closings, continued}
  end

  # Closing words ("FIN", "{e}THE END") are their act's trailer when nothing of the act
  # follows them, as TeiParser reads a last scene holding only them.
  defp closing_lines(lines) do
    {closings, _act_ends?} =
      lines
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.reduce({MapSet.new(), true}, fn {segments, line}, {closings, act_ends?} ->
        cond do
          segments == [] -> {closings, act_ends?}
          act_ends? and closing?(segments) -> {MapSet.put(closings, line), true}
          opens_act?(segments) -> {closings, true}
          true -> {closings, false}
        end
      end)

    closings
  end

  defp closing?([{:scene, text}]), do: Element.closing_words?(text)
  defp closing?([{:text, text}]), do: Element.closing_words?(text, alone: true)
  defp closing?(_segments), do: false

  defp opens_act?(segments), do: match?({:ok, _, _}, act_heading(segments))

  @braced_name ~r/^\{([^{}]+)\}/

  defp as_speaker(segments, speakers) do
    segments =
      Enum.map(segments, fn
        {:speaker, label} -> {:speaker, unbrace(label, speakers)}
        segment -> segment
      end)

    case segments do
      [{tag, text} | rest] when rest != [] and tag not in [:scene, :act, :speaker] ->
        name = if tag == :text, do: under_unknown_tag(text), else: text
        if name && String.upcase(name) in speakers, do: [{:speaker, name} | rest], else: segments

      _ ->
        segments
    end
  end

  defp under_unknown_tag(text) do
    case Regex.run(~r/^\{[a-z]{1,3}\}\s*([^{]+)$/i, text) do
      [_, name] -> name
      nil -> nil
    end
  end

  defp unbrace(label, speakers) do
    Regex.replace(@braced_name, label, fn whole, name ->
      if String.upcase(String.trim(name)) in speakers, do: String.trim(name), else: whole
    end)
  end

  defp join_prose(lines, closings) do
    {groups, _in_speech?} =
      lines
      |> Enum.with_index()
      |> Enum.reduce({[], false}, fn {segments, line}, {groups, in_speech?} ->
        if in_speech? and match?([{:text, _}], segments) and ends_in_prose?(groups) and
             line not in closings and not opens_act?(segments) do
          [group | rest] = groups
          {[[segments | group] | rest], true}
        else
          {[[segments] | groups], in_speech?(segments, in_speech?)}
        end
      end)

    groups
    |> Enum.reverse()
    |> Enum.flat_map(fn group ->
      [root | rest] = Enum.reverse(group)
      [join_onto_prose(root, rest) | Enum.map(rest, fn _ -> [] end)]
    end)
  end

  defp join_onto_prose(root, []), do: root

  defp join_onto_prose(root, rest) do
    {:prose, prose} = List.last(root)
    texts = for [{:text, text}] <- rest, do: text
    List.replace_at(root, -1, {:prose, Enum.join([prose | texts], " ")})
  end

  defp ends_in_prose?([group | _]), do: match?({:prose, _}, group |> List.last() |> List.last())
  defp ends_in_prose?([]), do: false

  defp in_speech?(segments, in_speech?) do
    cond do
      has_tag?(segments, :speaker) -> true
      has_tag?(segments, :scene) or has_tag?(segments, :act) -> false
      match?([{:text, _}], segments) -> false
      true -> in_speech?
    end
  end

  # `continued`: the lines whose first spoken words go on with the aside a break cut.
  defp carry_asides(lines), do: carry_asides(Enum.with_index(lines), false, [], MapSet.new())

  defp carry_asides([], _open?, done, continued), do: {Enum.reverse(done), continued}

  defp carry_asides([{segments, line} | rest], open?, done, continued) do
    {segments, open?, continued} =
      cond do
        open? and Enum.any?(segments, &spoken?/1) ->
          {reopen_aside(segments), false, MapSet.put(continued, line)}

        open? and String.contains?(segments_to_text(segments), "))") ->
          {close_stray(segments), false, continued}

        true ->
          {segments, open?, continued}
      end

    if not open? and unclosed_aside?(segments_to_text(segments)) and closed_later?(rest) do
      closed = List.update_at(segments, -1, fn {tag, text} -> {tag, text <> "))"} end)
      carry_asides(rest, true, [closed | done], continued)
    else
      carry_asides(rest, open?, [segments | done], continued)
    end
  end

  defp spoken?({tag, _text}), do: tag in @spoken_tags

  defp reopen_aside([{tag, text} = segment | rest]) do
    if spoken?(segment), do: [{tag, "((" <> text} | rest], else: [segment | reopen_aside(rest)]
  end

  defp close_stray([{tag, text} | rest]) do
    if String.contains?(text, "))"),
      do: [{tag, String.replace(text, "))", "", global: false)} | rest],
      else: [{tag, text} | close_stray(rest)]
  end

  defp closed_later?(rest) do
    speech =
      rest
      |> Enum.take_while(fn {segments, _line} ->
        not Enum.any?(segments, fn {tag, _} -> tag in [:speaker, :scene, :act] end)
      end)
      |> Enum.map_join(" ", fn {segments, _line} -> segments_to_text(segments) end)

    case {:binary.match(speech, "))"), :binary.match(speech, "((")} do
      {:nomatch, _} -> false
      {_close, :nomatch} -> true
      {{close, _}, {open, _}} -> close < open
    end
  end

  @unknown_tag ~r/\{(?!(?:#{@tags})\})[a-z]{1,3}\}/i

  defp paragraph_warnings(segments, in_text?) do
    text = segments_to_text(segments)

    [
      unknown_tag: Regex.match?(@unknown_tag, text),
      dropped_text: in_text? and match?([{:text, _}, _ | _], segments),
      unclosed_aside: in_text? and unclosed_aside?(text)
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp unclosed_aside?(text) do
    case String.split(text, "((", parts: 2) do
      [_, after_open] -> not String.contains?(after_open, "))")
      [_] -> false
    end
  end

  defp split_front_matter(parsed_lines) do
    boundary =
      Enum.find_index(parsed_lines, fn {segments, _line} ->
        has_tag?(segments, :scene) or has_tag?(segments, :act) or
          match?({:ok, _, _}, detect_act_heading(segments))
      end)

    case boundary do
      nil -> {[], parsed_lines}
      0 -> {[], parsed_lines}
      idx -> Enum.split(parsed_lines, idx)
    end
  end

  defp segments_to_text(segments) do
    segments
    |> Enum.map(fn {_tag, text} -> text end)
    |> Enum.join(" ")
    |> String.trim()
  end

  @division_heading ~r/^[\[⸢]?(?:\w+\s+)?(?:JORNADA|ACTO?|ACTE|ATTO|PR[OÓ]LOG(?:O|UE)|EP[IÍ]LOG(?:O|UE)|INDUCTION)\b/iu

  defp division_heading?(text), do: Regex.match?(@division_heading, String.trim(text))

  defp detect_act_type(text) do
    cond do
      Regex.match?(~r/\bJORNADA\b/iu, text) -> "jornada"
      Regex.match?(~r/\bPR[OÓ]LOG(O|UE)\b/iu, text) -> "prologo"
      Regex.match?(~r/\bEP[IÍ]LOG(O|UE)\b/iu, text) -> "epilogue"
      Regex.match?(~r/\bINDUCTION\b/iu, text) -> "induction"
      true -> "acto"
    end
  end

  defp detect_act_heading([{:text, text}]) do
    heading = String.trim(text)
    if division_heading?(heading), do: {:ok, detect_act_type(heading), heading}, else: :not_act
  end

  defp detect_act_heading(_segments), do: :not_act

  # An act's heading: {a}, an untagged "JORNADA I", or {e} naming a prologue, an epilogue
  # or an induction, which hold no scenes.
  defp act_heading(segments) do
    scene = get_tag_text(segments, :scene)

    cond do
      has_tag?(segments, :act) ->
        heading = get_tag_text(segments, :act)
        {:ok, detect_act_type(heading), heading}

      has_tag?(segments, :scene) and division_heading?(scene) and
          sceneless_type?(detect_act_type(scene)) ->
        {:ok, detect_act_type(scene), scene}

      true ->
        detect_act_heading(segments)
    end
  end

  defp is_untagged_text?(segments) do
    case segments do
      [{:text, _}] -> true
      [] -> true
      _ -> false
    end
  end

  defp process_line(segments, acts, state) do
    cond do
      state.line in state.closings ->
        trailer = %{
          type: "trailer",
          content: segments |> segments_to_text() |> String.trim(),
          line: state.line
        }

        {acts |> ensure_act(state) |> append_direct_element(trailer),
         %{state | current_speech: nil}}

      match?({:ok, _, _}, act_heading(segments)) ->
        {:ok, act_type, heading} = act_heading(segments)
        {acts ++ [new_act(act_type, heading, state.line)], %{state | current_speech: nil}}

      has_tag?(segments, :scene) ->
        scene_text = get_tag_text(segments, :scene)
        scene = %{head: scene_text, elements: [], line: state.line}

        acts =
          acts
          |> maybe_insert_act_from_scene_number(scene_text, state.line)
          |> ensure_act(state)
          |> append_scene(scene)

        {acts, %{state | current_speech: nil}}

      is_untagged_text?(segments) ->
        text = segments_to_text(segments)

        if String.trim(text) != "" and acts != [] do
          # Store unrecognized text as an element so admin can review
          el = %{type: "unrecognized", content: String.trim(text), line: state.line}
          {append_element_smart(acts, el), %{state | current_speech: nil}}
        else
          {acts, state}
        end

      true ->
        acts = ensure_act(acts, state)
        target = target(List.last(acts))
        acts = if target == :scene, do: ensure_scene(acts, state.line), else: acts
        process_content(segments, acts, state, target)
    end
  end

  defp target(act),
    do: if(sceneless_type?(act.type) and act.scenes == [], do: :direct, else: :scene)

  @doc false
  def sceneless_type?(type) do
    type in ["prologo", "epilogue", "induction"]
  end

  defp has_tag?(segments, tag), do: Enum.any?(segments, fn {t, _} -> t == tag end)

  defp get_tag_text(segments, tag) do
    case Enum.find(segments, fn {t, _} -> t == tag end) do
      {_, text} -> text
      nil -> ""
    end
  end

  defp new_act(type, head, line),
    do: %{type: type, head: head, scenes: [], _direct_elements: [], line: line}

  defp maybe_insert_act_from_scene_number(acts, scene_text, line) do
    case Regex.run(~r/^(\d+)\.(\d+)/, String.trim(scene_text)) do
      [_, act_num_str, _] ->
        act_num = String.to_integer(act_num_str)
        current = get_current_act_number(acts)

        if current == nil or act_num != current do
          acts ++ [Map.put(new_act("acto", "Act #{act_num}", line), :_act_num, act_num)]
        else
          acts
        end

      _ ->
        acts
    end
  end

  defp get_current_act_number([]), do: nil

  defp get_current_act_number(acts) do
    Map.get(List.last(acts), :_act_num)
  end

  defp ensure_act([], state), do: [new_act("acto", nil, state.line)]
  defp ensure_act(acts, _state), do: acts

  defp ensure_scene(acts, line) do
    act = List.last(acts)

    if act.scenes == [] do
      scene = %{head: nil, elements: [], line: line}
      List.replace_at(acts, -1, %{act | scenes: [scene]})
    else
      acts
    end
  end

  defp append_scene(acts, scene) do
    act = List.last(acts)
    List.replace_at(acts, -1, %{act | scenes: act.scenes ++ [scene]})
  end

  defp process_content(segments, acts, state, target) do
    if has_tag?(segments, :speaker) do
      speech = %{
        type: "speech",
        speaker_label: get_tag_text(segments, :speaker),
        children: build_children(segments, state),
        line: state.line
      }

      {append(acts, speech, target), %{state | current_speech: target}}
    else
      case Enum.reject(segments, &match?({:text, _}, &1)) do
        [{:stage_direction, text}] ->
          el = %{type: "stage_direction", content: text, line: state.line}
          {append(acts, el, target), state}

        [{:stanza, _}] ->
          stanza = %{type: "line_group", children: [], line: state.line}

          if state.current_speech == target do
            {continue_last_speech(acts, [stanza], target), state}
          else
            # No speech to hold it: the stanza sits in the scene and takes the verses
            # that follow, exactly as an open speech would.
            {append(acts, stanza, target), %{state | current_speech: target}}
          end

        _ ->
          children = build_children(segments, state)

          if state.current_speech == target and children != [] do
            {continue_last_speech(acts, children, target), state}
          else
            {Enum.reduce(children, acts, &append(&2, &1, target)), state}
          end
      end
    end
  end

  defp append(acts, element, :scene), do: append_element(acts, element)
  defp append(acts, element, :direct), do: append_direct_element(acts, element)

  defp continue_last_speech(acts, children, :scene),
    do: update_last_scene(acts, &%{&1 | elements: continue_speech(&1.elements, children)})

  defp continue_last_speech(acts, children, :direct) do
    act = List.last(acts)
    direct = continue_speech(act._direct_elements, children)
    List.replace_at(acts, -1, %{act | _direct_elements: direct})
  end

  @marked_aside ~r/\(\((.+?)\)\)/s

  # {ap} anywhere in the paragraph makes its verse and prose asides, unless ((…)) marks
  # the words said aside: then {ap}'s words are the delivery, before the first of them.
  defp build_children(segments, state) do
    partial? = Enum.any?(segments, fn {_tag, text} -> Regex.match?(@marked_aside, text) end)
    aside? = has_tag?(segments, :aside) and not partial?
    delivery = if partial?, do: get_tag_text(segments, :aside), else: ""

    segments
    |> Enum.reject(fn {tag, _} -> tag in [:speaker, :scene, :aside, :stanza, :text, :act] end)
    |> Enum.map_reduce(delivery, &mark_asides/2)
    |> elem(0)
    |> Enum.map(fn
      {:verse, text} -> %{type: "verse_line", content: text, part: nil, is_aside: aside?}
      {:verse_initial, text} -> %{type: "verse_line", content: text, part: "I", is_aside: aside?}
      {:verse_middle, text} -> %{type: "verse_line", content: text, part: "M", is_aside: aside?}
      {:verse_final, text} -> %{type: "verse_line", content: text, part: "F", is_aside: aside?}
      {:prose, text} -> %{type: "prose", content: text, is_aside: aside?}
      {:stage_direction, text} -> %{type: "stage_direction", content: text}
      {_other, text} -> %{type: "text", content: text}
    end)
    |> Enum.map(&Map.put(&1, :line, state.line))
    |> Enum.reduce([], &join_pieces_split_by_stage/2)
    |> Enum.reverse()
    |> continue_aside(state.line in state.continued)
  end

  defp continue_aside(children, false), do: children

  defp continue_aside(children, true) do
    index = Enum.find_index(children, &(&1.type in ~w(verse_line prose)))
    List.update_at(children, index, &Map.merge(&1, %{is_aside: true, aside_continues: true}))
  end

  defp mark_asides({tag, text}, delivery) when tag in @spoken_tags do
    {open, close} = InlineMarkup.aside_marker()

    marked =
      Regex.replace(@marked_aside, text, fn _whole, words ->
        open <> String.trim(words) <> close
      end)

    if delivery != "" and marked != text,
      do: {{tag, with_delivery(marked, delivery)}, ""},
      else: {{tag, marked}, delivery}
  end

  defp mark_asides(segment, delivery), do: {segment, delivery}

  defp with_delivery(text, delivery) do
    {open, _close} = InlineMarkup.aside_marker()
    {stage_open, stage_close} = InlineMarkup.stage_marker("delivery")
    String.replace(text, open, "#{stage_open}#{delivery}#{stage_close} #{open}", global: false)
  end

  defp join_pieces_split_by_stage(
         piece,
         [%{type: "stage_direction"} = stage, before | rest] = acc
       ) do
    if piece.type in ["verse_line", "prose"] and
         Map.delete(piece, :content) == Map.delete(before, :content) do
      {open, close} = InlineMarkup.stage_marker(nil)
      content = "#{before.content} #{open}#{stage.content}#{close} #{piece.content}"
      [%{before | content: content} | rest]
    else
      [piece | acc]
    end
  end

  defp join_pieces_split_by_stage(piece, acc), do: [piece | acc]

  defp append_element(acts, element) do
    update_last_scene(acts, fn scene ->
      %{scene | elements: scene.elements ++ [element]}
    end)
  end

  defp append_element_smart(acts, element) do
    case target(List.last(acts)) do
      :direct -> append_direct_element(acts, element)
      :scene -> acts |> ensure_scene(element.line) |> append_element(element)
    end
  end

  defp append_direct_element(acts, element) do
    act = List.last(acts)
    List.replace_at(acts, -1, %{act | _direct_elements: act._direct_elements ++ [element]})
  end

  # A speech goes on after the stage directions on their own lines that follow it: they
  # are its, as the premarking rules split a speech around one.
  defp continue_speech(elements, children) do
    {stages, before} =
      elements |> Enum.reverse() |> Enum.split_while(&(&1.type == "stage_direction"))

    case before do
      [%{type: type} = parent | rest] when type in ["speech", "line_group"] ->
        Enum.reverse([add_children(parent, Enum.reverse(stages) ++ children) | rest])

      _ ->
        elements ++ children
    end
  end

  # Verse and stage directions go into the parent's open stanza, when its last child is
  # a line group opened by {m}; anything else, including the next {m}, follows it.
  defp add_children(parent, children) do
    Enum.reduce(children, parent, fn child, acc ->
      case {child, List.last(acc.children)} do
        {%{type: type}, %{type: "line_group"} = stanza}
        when type in ["verse_line", "stage_direction"] ->
          stanza = %{stanza | children: stanza.children ++ [child]}
          %{acc | children: List.replace_at(acc.children, -1, stanza)}

        _ ->
          %{acc | children: acc.children ++ [child]}
      end
    end)
  end

  defp update_last_scene(acts, fun) do
    act = List.last(acts)
    scene = List.last(act.scenes)
    updated_scene = fun.(scene)
    updated_act = %{act | scenes: List.replace_at(act.scenes, -1, updated_scene)}
    List.replace_at(acts, -1, updated_act)
  end

  defp finalize_structure(acts) do
    acts
    |> Enum.map(fn act ->
      scenes = Enum.reject(act.scenes, &(&1.elements == [] and &1.head in [nil, ""]))
      act |> Map.delete(:_act_num) |> Map.put(:scenes, scenes)
    end)
    |> Enum.reject(fn act ->
      act.scenes == [] and Map.get(act, :_direct_elements, []) == []
    end)
  end

  @doc """
  The play `paragraphs` would make, as `WordDraft` builds it, without writing anything:
  `{:ok, %{divisions, paratexts, lines, warnings, summary}}`. `play` comes with its
  paratexts, the ones the import keeps printed beside the new ones.
  """
  def draft(paragraphs, play) do
    with {:ok, parsed} <- parse_content(paragraphs) do
      draft = WordDraft.build(parsed, play)
      texts = paragraphs |> Enum.map(&String.trim/1) |> List.to_tuple()

      with_text = fn notices -> Enum.map(notices, &Map.put(&1, :text, elem(texts, &1.line))) end
      {:ok, %{draft | warnings: with_text.(draft.warnings), errors: with_text.(draft.errors)}}
    end
  end

  @doc """
  Imports premarcado content, from a .docx at a path or from its paragraphs, into an
  existing play: its text, characters and front matter of origin `"word"` are replaced by
  the draft's rows (`draft/2`), as they are there, ids included.

  Returns `{:ok, play}` or `{:error, reason}`.
  """
  def import_content(play_id, path) when is_binary(path) do
    with {:ok, paragraphs} <- paragraphs(path), do: import_content(play_id, paragraphs)
  end

  def import_content(play_id, paragraphs) when is_list(paragraphs) do
    alias Playcode.Repo
    alias Playcode.Catalogue.Paratext
    alias Playcode.PlayContent.{Character, Division, Element}
    import Ecto.Query

    play = Catalogue.get_play_with_all!(play_id)

    with {:ok, draft} <- draft(paragraphs, play),
         [] <- draft.errors do
      Repo.transaction(fn ->
        Repo.delete_all(from e in Element, where: e.play_id == ^play_id)
        Repo.delete_all(from d in Division, where: d.play_id == ^play_id)
        Repo.delete_all(from c in Character, where: c.play_id == ^play_id)
        # Only the front matter an import wrote: a paratext typed by hand, the note on the
        # digital edition a new play starts with among them, stays.
        Repo.delete_all(from n in Paratext, where: n.play_id == ^play_id and n.origin == "word")

        for %Paratext{origin: "word"} = paratext <- draft.paratexts do
          {:ok, _} = Catalogue.create_paratext(row(paratext))
        end

        Enum.each(draft.divisions, &insert_division/1)

        # The text is new, so no number in it was typed by hand: it is counted by the rule.
        {:ok, play} = Catalogue.update_play(play, %{numbering_manual: false})
        PlayContent.refresh_derived(play_id)

        play
      end)
    else
      [_ | _] = errors -> {:error, {:refused, errors}}
      error -> error
    end
  end

  # The text is counted once, when it is all in (`refresh_derived/1` above), not per row.
  defp insert_division(division) do
    {:ok, _} = PlayContent.create_division(row(division), refresh: false)

    for entry <- division.entries do
      {:ok, _} =
        PlayContent.create_character(
          entry.character |> row() |> Map.merge(%{cast_list_id: division.id}),
          refresh: false
        )
    end

    Enum.each(division.loaded_elements, &insert_element/1)
    Enum.each(division.children, &insert_division/1)
  end

  defp insert_element(element) do
    {:ok, _} =
      PlayContent.create_element(row(element),
        characters: Enum.map(element.element_characters, & &1.character_id),
        refresh: false
      )

    Enum.each(element.children, &insert_element/1)
  end

  defp row(struct) do
    struct
    |> Map.from_struct()
    |> Map.reject(fn {_key, value} ->
      match?(%Ecto.Association.NotLoaded{}, value) or is_list(value)
    end)
    |> Map.drop([:__meta__])
  end
end
