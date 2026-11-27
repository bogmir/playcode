defmodule Playcode.Import.WordParser do
  @moduledoc """
  Parses EMOTHE "premarcado" Word (.docx) files into play content structure.

  The premarcación system uses tags like {v}, {p}, {ac}, {pr} etc. at the start
  of each paragraph to annotate structural elements of a play text.
  """

  alias Playcode.{Catalogue, PlayContent}
  alias Playcode.Import.WordDraft

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

  @tag_pattern ~r/\{(e|ac|ap|p|v|ti|tm|tf|pr|m|a)\}/i

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
    parsed_lines = paragraphs |> Enum.map(&parse_line/1) |> Enum.with_index()

    {front_lines, content_lines} = split_front_matter(parsed_lines)

    {acts, _state} =
      content_lines
      |> Enum.reduce(
        {[], %{current_act: nil, current_scene: nil, current_speech: nil, line: nil}},
        fn {segments, line}, {acts, state} ->
          process_line(segments, acts, %{state | line: line})
        end
      )

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

    warnings =
      for {paragraph, line} <- Enum.with_index(paragraphs),
          kind <- paragraph_warnings(paragraph, line >= length(front_lines)),
          do: %{line: line, kind: kind}

    {:ok, %{acts: acts, front_matter: front_matter, warnings: warnings}}
  end

  @unknown_tag ~r/\{(?!(?:e|ac|ap|p|v|ti|tm|tf|pr|m|a)\})[a-z]{1,3}\}/i

  defp paragraph_warnings(paragraph, in_text?) do
    segments = parse_line(paragraph)

    [
      unknown_tag: Regex.match?(@unknown_tag, paragraph),
      dropped_text: in_text? and match?([{:text, _}, _ | _], segments),
      unclosed_aside: in_text? and unclosed_aside?(paragraph)
    ]
    |> Enum.filter(&elem(&1, 1))
    |> Enum.map(&elem(&1, 0))
  end

  defp unclosed_aside?(paragraph) do
    case String.split(paragraph, "((", parts: 2) do
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

  defp is_untagged_text?(segments) do
    case segments do
      [{:text, _}] -> true
      [] -> true
      _ -> false
    end
  end

  defp process_line(segments, acts, state) do
    cond do
      has_tag?(segments, :act) ->
        heading = get_tag_text(segments, :act)
        act_type = detect_act_type(heading)

        act = %{
          type: act_type,
          head: heading,
          scenes: [],
          _direct_elements: [],
          _open: true,
          line: state.line
        }

        {acts ++ [act],
         %{state | current_act: length(acts), current_scene: nil, current_speech: nil}}

      match?({:ok, _, _}, detect_act_heading(segments)) ->
        {:ok, act_type, heading} = detect_act_heading(segments)

        act = %{
          type: act_type,
          head: heading,
          scenes: [],
          _direct_elements: [],
          _open: true,
          line: state.line
        }

        {acts ++ [act],
         %{state | current_act: length(acts), current_scene: nil, current_speech: nil}}

      has_tag?(segments, :scene) ->
        scene_text = get_tag_text(segments, :scene)

        cond do
          is_act_level_scene?(scene_text) ->
            # {e}EPILOGUE or {e}Prologue or {e}Induction → treat as act-level division
            act_type = detect_act_type(scene_text)

            act = %{
              type: act_type,
              head: scene_text,
              scenes: [],
              _direct_elements: [],
              _open: true,
              line: state.line
            }

            {acts ++ [act],
             %{state | current_act: length(acts), current_scene: nil, current_speech: nil}}

          is_end_marker?(scene_text) ->
            # {e}THE END → store as unrecognized element, not as scene
            if acts != [] do
              el = %{type: "unrecognized", content: String.trim(scene_text), line: state.line}
              acts = append_element_smart(acts, el)
              {acts, %{state | current_speech: nil}}
            else
              {acts, state}
            end

          true ->
            scene = %{head: scene_text, elements: [], _open: true, line: state.line}
            acts = maybe_insert_act_from_scene_number(acts, scene_text, state.line)
            acts = ensure_act(acts, state)
            acts = append_scene(acts, scene)
            act_idx = length(acts) - 1
            scene_idx = length(List.last(acts).scenes) - 1
            {acts, %{state | current_act: act_idx, current_scene: scene_idx, current_speech: nil}}
        end

      is_untagged_text?(segments) ->
        text = segments_to_text(segments)

        if String.trim(text) != "" and acts != [] do
          # Store unrecognized text as an element so admin can review
          el = %{type: "unrecognized", content: String.trim(text), line: state.line}
          acts = append_element_smart(acts, el)
          {acts, %{state | current_speech: nil}}
        else
          {acts, state}
        end

      true ->
        acts = ensure_act(acts, state)
        current_act = List.last(acts)

        if is_sceneless_type?(current_act.type) and current_act.scenes == [] do
          process_direct_content(segments, acts, state)
        else
          acts = ensure_scene(acts, state.line)
          process_content_segments(segments, acts, state)
        end
    end
  end

  defp is_act_level_scene?(text) do
    division_heading?(text) and is_sceneless_type?(detect_act_type(text))
  end

  defp is_end_marker?(text) do
    Regex.match?(~r/^THE\s+END\b/i, String.trim(text))
  end

  defp is_sceneless_type?(type) do
    type in ["prologo", "epilogue", "induction"]
  end

  defp has_tag?(segments, tag), do: Enum.any?(segments, fn {t, _} -> t == tag end)

  defp get_tag_text(segments, tag) do
    case Enum.find(segments, fn {t, _} -> t == tag end) do
      {_, text} -> text
      nil -> ""
    end
  end

  defp maybe_insert_act_from_scene_number(acts, scene_text, line) do
    case Regex.run(~r/^(\d+)\.(\d+)/, String.trim(scene_text)) do
      [_, act_num_str, _] ->
        act_num = String.to_integer(act_num_str)
        current = get_current_act_number(acts)

        if current == nil or act_num != current do
          acts ++
            [
              %{
                type: "acto",
                head: "Act #{act_num}",
                scenes: [],
                _open: true,
                _act_num: act_num,
                line: line
              }
            ]
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

  defp ensure_act([], state) do
    [%{type: "acto", head: nil, scenes: [], _open: true, line: state.line}]
  end

  defp ensure_act(acts, _state), do: acts

  defp ensure_scene(acts, line) do
    act = List.last(acts)

    if act.scenes == [] do
      scene = %{head: nil, elements: [], _open: true, line: line}
      List.replace_at(acts, -1, %{act | scenes: [scene]})
    else
      acts
    end
  end

  defp append_scene(acts, scene) do
    act = List.last(acts)
    List.replace_at(acts, -1, %{act | scenes: act.scenes ++ [scene]})
  end

  defp process_content_segments(segments, acts, state) do
    has_speaker = has_tag?(segments, :speaker)

    if has_speaker do
      speaker_label = get_tag_text(segments, :speaker)
      children = build_children(segments, state.line)

      speech = %{
        type: "speech",
        speaker_label: speaker_label,
        children: children,
        _open: true,
        line: state.line
      }

      acts = append_element(acts, speech)
      {acts, %{state | current_speech: :open}}
    else
      # No speaker — add content to current speech or as standalone elements
      content_segments =
        Enum.reject(segments, fn {t, _} ->
          t in [:text] and String.trim(elem({t, ""}, 1)) == ""
        end)

      case content_segments do
        [{:stage_direction, text}] ->
          el = %{type: "stage_direction", content: text, line: state.line}
          acts = append_element(acts, el)
          {acts, state}

        [{:stanza, _}] ->
          stanza = %{type: "line_group", children: [], line: state.line}

          if state.current_speech == :open do
            {append_children_to_last_speech(acts, [stanza]), state}
          else
            # No speech to hold it: the stanza sits in the scene and takes the verses
            # that follow, exactly as an open speech would.
            {append_element(acts, stanza), %{state | current_speech: :open}}
          end

        _ ->
          children = build_children(segments, state.line)

          if state.current_speech == :open and children != [] do
            acts = append_children_to_last_speech(acts, children)
            {acts, state}
          else
            Enum.reduce(children, {acts, state}, fn child, {a, s} ->
              {append_element(a, child), s}
            end)
          end
      end
    end
  end

  # {ap} anywhere in the paragraph makes its verse and prose asides.
  defp build_children(segments, line) do
    aside? = has_tag?(segments, :aside)

    segments
    |> Enum.reject(fn {tag, _} -> tag in [:speaker, :scene, :aside, :stanza, :text, :act] end)
    |> Enum.map(fn
      {:verse, text} -> %{type: "verse_line", content: text, part: nil, is_aside: aside?}
      {:verse_initial, text} -> %{type: "verse_line", content: text, part: "I", is_aside: aside?}
      {:verse_middle, text} -> %{type: "verse_line", content: text, part: "M", is_aside: aside?}
      {:verse_final, text} -> %{type: "verse_line", content: text, part: "F", is_aside: aside?}
      {:prose, text} -> %{type: "prose", content: text, is_aside: aside?}
      {:stage_direction, text} -> %{type: "stage_direction", content: text}
      {_other, text} -> %{type: "text", content: text}
    end)
    |> Enum.map(&Map.put(&1, :line, line))
    |> Enum.reduce([], &join_pieces_split_by_stage/2)
    |> Enum.reverse()
  end

  defp join_pieces_split_by_stage(
         piece,
         [%{type: "stage_direction"} = stage, before | rest] = acc
       ) do
    if piece.type in ["verse_line", "prose"] and
         Map.delete(piece, :content) == Map.delete(before, :content) do
      {open, close} = Playcode.PlayContent.InlineMarkup.stage_marker(nil)
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

  # Appends element to either _direct_elements (for scene-less types) or scene
  defp append_element_smart(acts, element) do
    act = List.last(acts)

    if is_sceneless_type?(act.type) and act.scenes == [] do
      append_direct_element(acts, element)
    else
      acts = ensure_scene(acts, element.line)
      append_element(acts, element)
    end
  end

  defp append_direct_element(acts, element) do
    act = List.last(acts)
    direct = Map.get(act, :_direct_elements, [])
    updated = %{act | _direct_elements: direct ++ [element]}
    List.replace_at(acts, -1, updated)
  end

  defp process_direct_content(segments, acts, state) do
    has_speaker = has_tag?(segments, :speaker)

    if has_speaker do
      speaker_label = get_tag_text(segments, :speaker)
      children = build_children(segments, state.line)

      speech = %{
        type: "speech",
        speaker_label: speaker_label,
        children: children,
        _open: true,
        line: state.line
      }

      acts = append_direct_element(acts, speech)
      {acts, %{state | current_speech: :open_direct}}
    else
      content_segments =
        Enum.reject(segments, fn {t, _} ->
          t in [:text] and String.trim(elem({t, ""}, 1)) == ""
        end)

      case content_segments do
        [{:stage_direction, text}] ->
          el = %{type: "stage_direction", content: text, line: state.line}
          acts = append_direct_element(acts, el)
          {acts, state}

        [{:stanza, _}] ->
          stanza = %{type: "line_group", children: [], line: state.line}

          if state.current_speech == :open_direct do
            {append_children_to_last_direct_speech(acts, [stanza]), state}
          else
            {append_direct_element(acts, stanza), %{state | current_speech: :open_direct}}
          end

        _ ->
          children = build_children(segments, state.line)

          if state.current_speech in [:open_direct] and children != [] do
            acts = append_children_to_last_direct_speech(acts, children)
            {acts, state}
          else
            Enum.reduce(children, {acts, state}, fn child, {a, s} ->
              {append_direct_element(a, child), s}
            end)
          end
      end
    end
  end

  defp append_children_to_last_direct_speech(acts, children) do
    act = List.last(acts)
    direct = continue_speech(Map.get(act, :_direct_elements, []), children)
    List.replace_at(acts, -1, %{act | _direct_elements: direct})
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

  defp append_children_to_last_speech(acts, children) do
    update_last_scene(acts, &%{&1 | elements: continue_speech(&1.elements, children)})
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
      scenes =
        act.scenes
        |> Enum.map(&Map.drop(&1, [:_open]))
        |> Enum.reject(&(&1.elements == []))

      act |> Map.drop([:_open, :_act_num]) |> Map.put(:scenes, scenes)
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
