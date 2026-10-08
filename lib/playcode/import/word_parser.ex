defmodule Playcode.Import.WordParser do
  @moduledoc """
  Parses EMOTHE "premarcado" Word (.docx) files into play content structure.

  The premarcación system uses tags like {v}, {p}, {ac}, {pr} etc. at the start
  of each paragraph to annotate structural elements of a play text.
  """

  # Extracts paragraphs from a .docx file as a list of strings.
  defp extract_paragraphs(path) do
    with {:ok, zip_handle} <- open_zip(path),
         {:ok, document_xml} <- read_zip_entry(zip_handle, ~c"word/document.xml") do
      paragraphs = extract_paragraphs_from_xml(document_xml)
      {:ok, paragraphs}
    end
  end

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

    # Parse <w:p> paragraphs, each containing <w:r><w:t> text runs
    # Using regex-based extraction since the XML namespace handling
    # with Saxy.SimpleForm would require namespace awareness
    Regex.scan(~r/<w:p\b[^>]*>.*?<\/w:p>/s, xml_string)
    |> Enum.map(fn [paragraph_xml] ->
      # Extract all <w:t> text content within this paragraph
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

  # Tag name regex - case-insensitive
  @tag_pattern ~r/\{(e|ac|ap|p|v|ti|tm|tf|pr|m|a)\}/i

  defp split_into_tag_segments(line) do
    # Split line by tags, keeping the tag names
    parts = Regex.split(@tag_pattern, line, include_captures: true)

    parts
    |> chunk_tag_text([])
    |> Enum.reject(fn {_tag, text} -> tag_empty_filler?(text) end)
  end

  # Recursively pair tags with their following text
  defp chunk_tag_text([], acc), do: Enum.reverse(acc)

  defp chunk_tag_text([head | rest], acc) do
    if Regex.match?(@tag_pattern, head) do
      # Extract the tag name
      [_, tag_name] = Regex.run(@tag_pattern, head)
      # Next element (if any) is the text content
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
      # Text before any tag — untagged content
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
    parsed_lines = Enum.map(paragraphs, &parse_line/1)

    # Split front matter (before first {e} or {A} tag) from play content
    {front_lines, content_lines} = split_front_matter(parsed_lines)

    {acts, _state} =
      content_lines
      |> Enum.reduce({[], %{current_act: nil, current_scene: nil, current_speech: nil}}, fn
        segments, {acts, state} ->
          process_line(segments, acts, state)
      end)

    # Finalize: close any open speech/scene/act
    acts = finalize_structure(acts)

    # If no acts were created, wrap everything in a default act
    acts =
      if acts == [] do
        [%{type: "acto", head: nil, scenes: []}]
      else
        acts
      end

    # Build front matter text from non-empty lines
    front_matter =
      front_lines
      |> Enum.map(&segments_to_text/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.join("\n")

    front_matter = if front_matter == "", do: nil, else: front_matter

    {:ok, %{acts: acts, front_matter: front_matter, warnings: []}}
  end

  defp split_front_matter(parsed_lines) do
    boundary =
      Enum.find_index(parsed_lines, fn segments ->
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

  # Detect act type from heading text (used by both {A} tag and auto-detection)
  defp detect_act_type(text) do
    trimmed = String.trim(text)

    cond do
      Regex.match?(~r/^JORNADA\b/iu, trimmed) -> "jornada"
      Regex.match?(~r/^(THE\s+)?PR[OÓ]LOG(O|UE)\b/iu, trimmed) -> "prologo"
      Regex.match?(~r/^(THE\s+)?EP[IÍ]LOG(O|UE)\b/iu, trimmed) -> "epilogue"
      Regex.match?(~r/^(THE\s+)?INDUCTION\b/iu, trimmed) -> "induction"
      true -> "acto"
    end
  end

  # Detect act-level headings from plain untagged text (fallback when no {A} tag)
  defp detect_act_heading(segments) do
    case segments do
      [{:text, text}] ->
        trimmed = String.trim(text)

        cond do
          Regex.match?(~r/^JORNADA\s/i, trimmed) -> {:ok, "jornada", trimmed}
          Regex.match?(~r/^ACTO\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^ACT\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^ACTE\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^ATTO\s/i, trimmed) -> {:ok, "acto", trimmed}
          Regex.match?(~r/^(THE\s+)?PR[OÓ]LOG(O|UE)\b/iu, trimmed) -> {:ok, "prologo", trimmed}
          Regex.match?(~r/^(THE\s+)?EP[IÍ]LOG(O|UE)\b/iu, trimmed) -> {:ok, "epilogue", trimmed}
          Regex.match?(~r/^(THE\s+)?INDUCTION\b/iu, trimmed) -> {:ok, "induction", trimmed}
          true -> :not_act
        end

      _ ->
        :not_act
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
      # Explicit {A} act tag
      has_tag?(segments, :act) ->
        heading = get_tag_text(segments, :act)
        act_type = detect_act_type(heading)
        act = %{type: act_type, head: heading, scenes: [], _direct_elements: [], _open: true}

        {acts ++ [act],
         %{state | current_act: length(acts), current_scene: nil, current_speech: nil}}

      # Auto-detected act heading from plain text (fallback)
      match?({:ok, _, _}, detect_act_heading(segments)) ->
        {:ok, act_type, heading} = detect_act_heading(segments)
        act = %{type: act_type, head: heading, scenes: [], _direct_elements: [], _open: true}

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
              _open: true
            }

            {acts ++ [act],
             %{state | current_act: length(acts), current_scene: nil, current_speech: nil}}

          is_end_marker?(scene_text) ->
            # {e}THE END → store as unrecognized element, not as scene
            if acts != [] do
              el = %{type: "unrecognized", content: String.trim(scene_text)}
              acts = append_element_smart(acts, el)
              {acts, %{state | current_speech: nil}}
            else
              {acts, state}
            end

          true ->
            scene = %{head: scene_text, elements: [], _open: true}
            # Auto-detect act boundary from M.N scene numbering
            acts = maybe_insert_act_from_scene_number(acts, scene_text)
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
          el = %{type: "unrecognized", content: String.trim(text)}
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
          acts = ensure_scene(acts)
          process_content_segments(segments, acts, state)
        end
    end
  end

  defp is_act_level_scene?(text) do
    trimmed = String.trim(text)

    Regex.match?(~r/^(THE\s+)?PR[OÓ]LOG(O|UE)\b/iu, trimmed) or
      Regex.match?(~r/^(THE\s+)?EP[IÍ]LOG(O|UE)\b/iu, trimmed) or
      Regex.match?(~r/^(THE\s+)?INDUCTION\b/iu, trimmed)
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

  defp maybe_insert_act_from_scene_number(acts, scene_text) do
    case Regex.run(~r/^(\d+)\.(\d+)/, String.trim(scene_text)) do
      [_, act_num_str, _] ->
        act_num = String.to_integer(act_num_str)
        current = get_current_act_number(acts)

        if current == nil or act_num != current do
          acts ++
            [%{type: "acto", head: "Act #{act_num}", scenes: [], _open: true, _act_num: act_num}]
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

  defp ensure_act([], _state) do
    [%{type: "acto", head: nil, scenes: [], _open: true}]
  end

  defp ensure_act(acts, _state), do: acts

  defp ensure_scene(acts) do
    act = List.last(acts)

    if act.scenes == [] do
      scene = %{head: nil, elements: [], _open: true}
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
      # Collect content elements from this line
      children = build_children(segments)
      speech = %{type: "speech", speaker_label: speaker_label, children: children, _open: true}
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
          el = %{type: "stage_direction", content: text}
          acts = append_element(acts, el)
          {acts, state}

        [{:stanza, _}] ->
          stanza = %{type: "line_group", children: []}

          if state.current_speech == :open do
            {append_children_to_last_speech(acts, [stanza]), state}
          else
            # No speech to hold it: the stanza sits in the scene and takes the verses
            # that follow, exactly as an open speech would.
            {append_element(acts, stanza), %{state | current_speech: :open}}
          end

        _ ->
          # Add as children to current speech if one is open
          children = build_children(segments)

          if state.current_speech == :open and children != [] do
            acts = append_children_to_last_speech(acts, children)
            {acts, state}
          else
            # Standalone elements
            Enum.reduce(children, {acts, state}, fn child, {a, s} ->
              {append_element(a, child), s}
            end)
          end
      end
    end
  end

  # {ap} anywhere in the paragraph makes its verse and prose asides.
  defp build_children(segments) do
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
  end

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
      acts = ensure_scene(acts)
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
      children = build_children(segments)
      speech = %{type: "speech", speaker_label: speaker_label, children: children, _open: true}
      acts = append_direct_element(acts, speech)
      {acts, %{state | current_speech: :open_direct}}
    else
      content_segments =
        Enum.reject(segments, fn {t, _} ->
          t in [:text] and String.trim(elem({t, ""}, 1)) == ""
        end)

      case content_segments do
        [{:stage_direction, text}] ->
          el = %{type: "stage_direction", content: text}
          acts = append_direct_element(acts, el)
          {acts, state}

        [{:stanza, _}] ->
          stanza = %{type: "line_group", children: []}

          if state.current_speech == :open_direct do
            {append_children_to_last_direct_speech(acts, [stanza]), state}
          else
            {append_direct_element(acts, stanza), %{state | current_speech: :open_direct}}
          end

        _ ->
          children = build_children(segments)

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
    direct = Map.get(act, :_direct_elements, [])

    case List.last(direct) do
      %{type: type} = parent when type in ["speech", "line_group"] ->
        updated_direct = List.replace_at(direct, -1, add_children(parent, children))
        List.replace_at(acts, -1, %{act | _direct_elements: updated_direct})

      _ ->
        acts
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
    update_last_scene(acts, fn scene ->
      elements = scene.elements

      case List.last(elements) do
        %{type: type} = parent when type in ["speech", "line_group"] ->
          %{scene | elements: List.replace_at(elements, -1, add_children(parent, children))}

        _ ->
          scene
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
  Imports premarcado content from a .docx file into an existing play.
  Deletes any existing content (divisions, elements, characters) first.

  Returns `{:ok, play}` or `{:error, reason}`.
  """
  def import_content(play_id, path) do
    alias Playcode.{Repo, Catalogue, PlayContent}
    alias Playcode.Catalogue.PlayEditorialNote
    alias Playcode.PlayContent.{Character, Division, Element}
    import Ecto.Query

    with {:ok, paragraphs} <- extract_paragraphs(path),
         {:ok, %{acts: acts, front_matter: front_matter}} <- parse_content(paragraphs) do
      Repo.transaction(fn ->
        play = Catalogue.get_play!(play_id)

        # Delete existing content
        Repo.delete_all(from e in Element, where: e.play_id == ^play_id)
        Repo.delete_all(from d in Division, where: d.play_id == ^play_id)
        Repo.delete_all(from c in Character, where: c.play_id == ^play_id)
        Repo.delete_all(from n in PlayEditorialNote, where: n.play_id == ^play_id)

        # Store front matter as editorial note
        if front_matter do
          Catalogue.create_play_editorial_note(%{
            play_id: play_id,
            section_type: "nota",
            heading: "Front matter",
            content: front_matter,
            position: 0
          })
        end

        # Auto-create characters from unique speaker labels
        character_map = create_characters_from_acts(acts, play_id)

        # Auto-create elenco division if characters were found
        elenco_offset =
          if character_map != %{} do
            PlayContent.create_division(%{
              play_id: play_id,
              type: "elenco",
              title: "Dramatis Personae",
              position: 0
            })

            1
          else
            0
          end

        # Create structure in DB
        verse_counter_ref = :counters.new(1, [:atomics])

        # Use reduce to track act numbering (skip prologo/epilogue)
        Enum.with_index(acts, elenco_offset)
        |> Enum.reduce(1, fn {act, act_pos}, act_number ->
          is_numbered = act.type not in ["prologo", "epilogue", "induction"]

          {:ok, act_div} =
            PlayContent.create_division(%{
              play_id: play_id,
              type: act.type,
              title: act.head,
              number: if(is_numbered, do: act_number, else: nil),
              position: act_pos
            })

          # Create elements directly on act division (for scene-less types)
          direct_elements = Map.get(act, :_direct_elements, [])

          if direct_elements != [] do
            create_elements(
              direct_elements,
              play_id,
              act_div.id,
              nil,
              verse_counter_ref,
              character_map
            )
          end

          Enum.with_index(act.scenes)
          |> Enum.each(fn {scene, scene_pos} ->
            {:ok, scene_div} =
              PlayContent.create_division(%{
                play_id: play_id,
                parent_id: act_div.id,
                type: "escena",
                title: scene.head,
                number: scene_pos + 1,
                position: scene_pos
              })

            create_elements(
              scene.elements,
              play_id,
              scene_div.id,
              nil,
              verse_counter_ref,
              character_map
            )
          end)

          if is_numbered, do: act_number + 1, else: act_number
        end)

        Catalogue.update_verse_count(play_id)

        play
      end)
    end
  end

  defp create_characters_from_acts(acts, play_id) do
    alias Playcode.PlayContent

    scene_elements =
      acts
      |> Enum.flat_map(& &1.scenes)
      |> Enum.flat_map(& &1.elements)

    direct_elements =
      acts
      |> Enum.flat_map(&Map.get(&1, :_direct_elements, []))

    speaker_labels =
      (scene_elements ++ direct_elements)
      |> Enum.filter(&(&1.type == "speech" && &1[:speaker_label] && &1.speaker_label != ""))
      |> Enum.map(& &1.speaker_label)
      |> Enum.uniq()

    speaker_labels
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {label, idx}, acc ->
      {:ok, char} =
        PlayContent.create_character_unless_exists(%{
          play_id: play_id,
          xml_id: character_xml_id(label, idx),
          name: label,
          position: idx
        })

      Map.put(acc, label, char.id)
    end)
  end

  # The xml:id every <sp who> of this speaker cites: the label's letters and digits without
  # their accents ("ABSALÓN" is absalon), a leading number moved last as the corpus's
  # editors write it ("1ª Dama" is dama_1), since an XML id may not start with a digit.
  # A label with neither letter nor digit is numbered by its place among the speakers.
  defp character_xml_id(label, idx) do
    id =
      label
      |> :unicode.characters_to_nfkd_binary()
      |> String.replace(~r/\p{Mn}/u, "")
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")
      |> then(
        &Regex.replace(~r/^(\d+)(?:_?(?:st|nd|rd|th|er|em|me|e|a|o))?_(.+)$/, &1, "\\2_\\1")
      )

    if id =~ ~r/^[a-z]/, do: id, else: "character_#{idx + 1}"
  end

  defp create_elements(elements, play_id, division_id, parent_id, verse_counter, character_map) do
    alias Playcode.PlayContent

    elements
    |> Enum.with_index()
    |> Enum.each(fn {element, pos} ->
      case element do
        %{type: "speech"} ->
          character_id = Map.get(character_map, element.speaker_label)

          {:ok, speech} =
            PlayContent.create_element(%{
              play_id: play_id,
              division_id: division_id,
              parent_id: parent_id,
              type: "speech",
              speaker_label: element.speaker_label,
              position: pos
            })

          if character_id do
            PlayContent.set_element_characters(speech.id, [character_id])
          end

          children = Map.get(element, :children, [])
          create_children(children, play_id, division_id, speech.id, verse_counter)

        %{type: "stage_direction"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "stage_direction",
            content: element.content,
            position: pos
          })

        %{type: "line_group"} ->
          create_stanza(element, play_id, division_id, parent_id, pos, verse_counter)

        %{type: "unrecognized"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "unrecognized",
            content: element.content,
            position: pos
          })

        %{type: "verse_line"} ->
          :counters.add(verse_counter, 1, 1)
          line_num = :counters.get(verse_counter, 1)

          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "verse_line",
            content: element.content,
            part: element[:part],
            line_number: line_num,
            is_aside: element[:is_aside] || false,
            position: pos
          })

        %{type: "prose"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "prose",
            content: element.content,
            is_aside: element[:is_aside] || false,
            position: pos
          })

        _ ->
          :ok
      end
    end)
  end

  defp create_children(children, play_id, division_id, parent_id, verse_counter) do
    alias Playcode.PlayContent

    children
    |> Enum.with_index()
    |> Enum.each(fn {element, pos} ->
      case element do
        %{type: "verse_line"} ->
          :counters.add(verse_counter, 1, 1)
          line_num = :counters.get(verse_counter, 1)

          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "verse_line",
            content: element.content,
            part: element[:part],
            line_number: line_num,
            is_aside: element[:is_aside] || false,
            position: pos
          })

        %{type: "prose"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "prose",
            content: element.content,
            is_aside: element[:is_aside] || false,
            position: pos
          })

        %{type: "stage_direction"} ->
          PlayContent.create_element(%{
            play_id: play_id,
            division_id: division_id,
            parent_id: parent_id,
            type: "stage_direction",
            content: element.content,
            position: pos
          })

        %{type: "line_group"} ->
          create_stanza(element, play_id, division_id, parent_id, pos, verse_counter)

        _ ->
          :ok
      end
    end)
  end

  defp create_stanza(stanza, play_id, division_id, parent_id, pos, verse_counter) do
    {:ok, group} =
      Playcode.PlayContent.create_element(%{
        play_id: play_id,
        division_id: division_id,
        parent_id: parent_id,
        type: "line_group",
        position: pos
      })

    create_children(Map.get(stanza, :children, []), play_id, division_id, group.id, verse_counter)
  end
end
