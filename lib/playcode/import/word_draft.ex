defmodule Playcode.Import.WordDraft do
  @moduledoc """
  The rows a premarked text becomes, built in memory from `WordParser`'s acts: the
  divisions, elements, characters and front matter the Word import inserts as they are
  here, ids included, and the premarked page prints before anything is stored. The
  numbers are the play's rule's (`Numbering.expected/3`), as the import's recount gives
  them; `lines` maps each row's id to the paragraph it came from.

  A character's `xml_id`, the id every `<sp who>` of its speaker cites, is the label's
  letters and digits without their accents ("ABSALÓN" is absalon), a leading number moved
  last as the corpus's editors write it ("1ª Dama" is dama_1), since an XML id may not start
  with a digit; a label with neither letter nor digit is numbered by its place among the
  speakers, and a taken id gets `_2`, `_3`.
  """

  alias Playcode.Catalogue.Paratext
  alias Playcode.Import.Asides
  alias Playcode.Statistics.Metrics

  alias Playcode.PlayContent.{
    CastListEntry,
    Character,
    Division,
    Element,
    ElementCharacter,
    Numbering,
    SplitVerses
  }

  def build(%{acts: acts, front_matter: front_matter, warnings: warnings}, play) do
    {acts, lines} = identify(acts, play.id)
    characters = characters(acts, play.id)
    cast_list = cast_list(characters, play.id)
    first_act_position = if cast_list, do: 2, else: 1

    {act_divisions, refused} = act_divisions(acts, play.id, first_act_position, characters)
    divisions = List.wrap(cast_list) ++ act_divisions

    divisions = number(divisions, play)
    labels = MapSet.new(characters, fn {label, _character} -> String.upcase(label) end)

    %{
      divisions: divisions,
      paratexts: kept_paratexts(play) ++ front_matter(front_matter, play.id),
      lines: lines,
      errors:
        refused
        |> Enum.map(&%{line: Map.fetch!(lines, &1), kind: :refused})
        |> Enum.sort_by(& &1.line),
      warnings: warnings(warnings, row_warnings(divisions, lines, labels)),
      summary: summary(divisions)
    }
  end

  defp warnings(paragraph_warnings, row_warnings) do
    unknown =
      for %{kind: :unknown_tag, line: line} <- paragraph_warnings, into: MapSet.new(), do: line

    (paragraph_warnings ++
       Enum.reject(row_warnings, &(&1.kind == :untagged and &1.line in unknown)))
    |> Enum.sort_by(& &1.line)
  end

  defp row_warnings(divisions, lines, labels) do
    elements = Enum.flat_map(divisions, &all_elements/1)

    rows =
      for element <- elements, kind = row_warning(element, labels), do: {element.id, kind}

    rows = rows ++ split_verse_warnings(reading_order(divisions))
    for {id, kind} <- rows, do: %{line: Map.fetch!(lines, id), kind: kind}
  end

  defp row_warning(%{type: "unrecognized", content: content}, _labels),
    do: if(content =~ ~r/^THE\s+END\b/i, do: :end_marker, else: :untagged)

  defp row_warning(%{type: type, content: content}, labels) when type in ~w(verse_line prose) do
    if String.upcase(String.trim(content || "")) in labels, do: :speaker_as_words
  end

  defp row_warning(_element, _labels), do: nil

  defp split_verse_warnings(rows) do
    rows
    |> Enum.filter(&(&1.type == "verse_line"))
    |> Enum.chunk_by(& &1.act_id)
    |> SplitVerses.out_of_order()
    |> Enum.map(fn {row, problem} -> {row.id, split_warning(problem)} end)
  end

  defp split_warning(:completes_nothing), do: :part_without_initial
  defp split_warning(:never_completed), do: :initial_unfinished

  defp identify(acts, play_id) do
    {acts, {lines, _seen, _play_id}} = Enum.map_reduce(acts, {%{}, %{}, play_id}, &identify_act/2)
    {acts, lines}
  end

  defp identify_act(act, ids) do
    {act, ids} = with_id(act, ids)
    {direct, ids} = identify_elements(Asides.guess(Map.get(act, :_direct_elements, [])), ids)

    {scenes, ids} =
      Enum.map_reduce(act.scenes, ids, fn scene, ids ->
        {scene, ids} = with_id(scene, ids)
        {elements, ids} = identify_elements(Asides.guess(scene.elements), ids)
        {%{scene | elements: elements}, ids}
      end)

    {%{act | scenes: scenes} |> Map.put(:_direct_elements, direct), ids}
  end

  defp identify_elements(elements, ids) do
    Enum.map_reduce(elements, ids, fn element, ids ->
      {element, ids} = with_id(element, ids)
      {children, ids} = identify_elements(Map.get(element, :children, []), ids)
      {Map.put(element, :children, children), ids}
    end)
  end

  defp with_id(row, {lines, seen, play_id}) do
    line = Map.get(row, :line)
    nth = Map.get(seen, line, 0)
    id = stable_id(play_id, {line, nth})
    lines = if line, do: Map.put(lines, id, line), else: lines
    {Map.put(row, :id, id), {lines, Map.put(seen, line, nth + 1), play_id}}
  end

  defp stable_id(play_id, key) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(:sha256, :erlang.term_to_binary({play_id, key}))

    Ecto.UUID.cast!(<<a::48, 8::4, b::12, 2::2, c::62>>)
  end

  defp characters(acts, play_id) do
    acts
    |> Enum.flat_map(
      &(Map.get(&1, :_direct_elements, []) ++ Enum.flat_map(&1.scenes, fn s -> s.elements end))
    )
    |> Enum.filter(&(&1.type == "speech" and &1[:speaker_label] not in [nil, ""]))
    |> Enum.map(&character_name(&1.speaker_label))
    |> Enum.uniq()
    |> Enum.with_index()
    |> Enum.map_reduce(MapSet.new(), fn {label, index}, taken ->
      xml_id = unique_xml_id(character_xml_id(label, index), taken)

      character = %Character{
        id: stable_id(play_id, {:character, xml_id}),
        play_id: play_id,
        xml_id: xml_id,
        name: label,
        position: index
      }

      {{label, character}, MapSet.put(taken, xml_id)}
    end)
    |> elem(0)
  end

  # "[MÉNON]" is MÉNON, named by the editor: TEI's <sp who="#menon"><speaker>[MÉNON]</speaker>.
  defp character_name(label), do: String.replace(label, ~r/^\[(.+)\]$/u, "\\1")

  defp unique_xml_id(xml_id, taken) do
    if xml_id in taken,
      do:
        Stream.iterate(2, &(&1 + 1))
        |> Stream.map(&"#{xml_id}_#{&1}")
        |> Enum.find(&(&1 not in taken)),
      else: xml_id
  end

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

  defp cast_list([], _play_id), do: nil

  defp cast_list(characters, play_id) do
    id = stable_id(play_id, :cast_list)

    entries =
      for {_label, character} <- characters do
        %CastListEntry{
          play_id: play_id,
          cast_list_id: id,
          character_id: character.id,
          character: character,
          name: character.name,
          position: character.position
        }
      end

    %Division{
      id: id,
      play_id: play_id,
      type: "elenco",
      title: "Dramatis Personae",
      position: 1,
      children: [],
      notes: [],
      entries: entries
    }
  end

  defp act_divisions(acts, play_id, first_position, characters) do
    characters = Map.new(characters)

    {divisions, {_act_number, refused}} =
      acts
      |> Enum.with_index(first_position)
      |> Enum.map_reduce({1, []}, fn {act, position}, {act_number, refused} ->
        numbered? = act.type not in ["prologo", "epilogue", "induction"]

        {scenes, refused} =
          act.scenes
          |> Enum.with_index()
          |> Enum.map_reduce(refused, fn {scene, index}, refused ->
            division(scene.id, play_id, act.id, "escena", scene.head, index + 1, index)
            |> with_elements(scene.elements, characters, refused)
          end)

        {division, refused} =
          division(act.id, play_id, nil, act.type, act.head, numbered? && act_number, position)
          |> with_elements(Map.get(act, :_direct_elements, []), characters, refused)

        act_number = if numbered?, do: act_number + 1, else: act_number
        {%{division | children: scenes}, {act_number, refused}}
      end)

    {divisions, refused}
  end

  defp division(id, play_id, parent_id, type, title, number, position) do
    %Division{id: id, children: [], notes: [], entries: []}
    |> Division.changeset(%{
      play_id: play_id,
      parent_id: parent_id,
      type: type,
      title: title,
      number: number || nil,
      position: position
    })
    |> Ecto.Changeset.apply_changes()
  end

  defp with_elements(division, elements, characters, refused) do
    {elements, refused} = elements(elements, division, nil, characters, refused)
    {%{division | loaded_elements: elements}, refused}
  end

  defp elements(elements, division, parent_id, characters, refused) do
    elements
    |> Enum.filter(
      &(&1.type in ~w(speech stage_direction line_group unrecognized verse_line prose))
    )
    |> Enum.with_index()
    |> Enum.map_reduce(refused, fn {element, position}, refused ->
      changeset =
        Element.changeset(%Element{id: element.id, notes: []}, %{
          play_id: division.play_id,
          division_id: division.id,
          parent_id: parent_id,
          type: element.type,
          content: element[:content],
          speaker_label: element[:speaker_label],
          part: element[:part],
          is_aside: element[:is_aside] || false,
          aside_continues: element[:aside_continues] || false,
          position: position
        })

      refused = if changeset.valid?, do: refused, else: [element.id | refused]
      {children, refused} = elements(element.children, division, element.id, characters, refused)

      element =
        changeset
        |> Ecto.Changeset.apply_changes()
        |> Map.merge(%{element_characters: speakers(element, characters), children: children})

      {element, refused}
    end)
  end

  defp speakers(%{type: "speech", speaker_label: label}, characters) do
    case Map.fetch(characters, character_name(label)) do
      {:ok, character} ->
        [%ElementCharacter{character_id: character.id, character: character, position: 0}]

      :error ->
        []
    end
  end

  defp speakers(_element, _characters), do: []

  defp kept_paratexts(play), do: Enum.reject(play.paratexts, &(&1.origin == "word"))

  defp front_matter(nil, _play_id), do: []

  defp front_matter(content, play_id) do
    [
      %Paratext{
        id: stable_id(play_id, :front_matter),
        play_id: play_id,
        kind: "nota_edicion_digital",
        heading: "Front matter",
        content: content,
        position: 0,
        origin: "word"
      }
    ]
  end

  defp number(divisions, play) do
    numbered =
      divisions
      |> reading_order()
      |> Numbering.expected(play.numbering_type, play.numbering_restart)
      |> Map.new(&{&1.id, &1})

    Enum.map(divisions, &number_division(&1, numbered))
  end

  defp number_division(division, numbered) do
    %{
      division
      | loaded_elements: Enum.map(division.loaded_elements, &number_element(&1, numbered)),
        children: Enum.map(division.children, &number_division(&1, numbered))
    }
  end

  defp number_element(element, numbered) do
    element =
      case Map.fetch(numbered, element.id) do
        {:ok, row} -> %{element | line_number: row.line_number, content: row.content}
        :error -> element
      end

    %{element | children: Enum.map(element.children, &number_element(&1, numbered))}
  end

  defp reading_order(divisions) do
    for act <- divisions,
        {division, scene_id} <- [{act, nil} | Enum.map(act.children, &{&1, &1.id})],
        element <- division.loaded_elements,
        row <- leaves(element, nil, %{act_id: act.id, scene_id: scene_id}),
        do: row
  end

  defp leaves(%{type: type} = element, speech_id, where) when type in ~w(verse_line prose) do
    [
      element
      |> Map.take([:id, :type, :part, :line_number, :content])
      |> Map.merge(where)
      |> Map.put(:speech_id, speech_id)
    ]
  end

  defp leaves(element, speech_id, where) do
    speech_id = if element.type == "speech", do: element.id, else: speech_id
    Enum.flat_map(element.children, &leaves(&1, speech_id, where))
  end

  defp summary(divisions) do
    texts = Enum.reject(divisions, &(&1.type == "elenco"))
    acts = Enum.filter(texts, &(&1.type in Metrics.act_types()))
    elements = Enum.flat_map(texts, &all_elements/1)

    speakers =
      elements
      |> Enum.filter(&(&1.type == "speech" and &1.speaker_label not in [nil, ""]))
      |> Enum.frequencies_by(&character_name(&1.speaker_label))
      |> Enum.sort_by(fn {label, count} -> {-count, label} end)

    %{
      acts: length(acts),
      scenes: acts |> Enum.flat_map(& &1.children) |> length(),
      verses: Enum.count(elements, &(&1.type == "verse_line" and &1.part in [nil, "", "I"])),
      speakers: speakers
    }
  end

  defp all_elements(division) do
    (division.loaded_elements ++ Enum.flat_map(division.children, & &1.loaded_elements))
    |> Enum.flat_map(&with_descendants/1)
  end

  defp with_descendants(element),
    do: [element | Enum.flat_map(element.children, &with_descendants/1)]
end
