defmodule Playcode.Statistics.Metrics do
  @moduledoc """
  Dramatic and metrical figures computed from a play's content tree, as
  `Playcode.PlayContent.load_play_content/1` returns it.

  Pure functions. `Playcode.Statistics` stores what they return; the static site
  reads `items/1` and `passages/1` directly to place lines on pages and verse-form
  labels in the margin, so the pages and the statistics follow the same rules.
  """

  alias Playcode.PlayContent.Element

  @act_types ~w(acto act acte jornada)
  @unmarked [nil, "", "free", "nil"]
  @whole_verse [nil, "", "I"]

  # ponytail: the grouping awaits review by the project's philologists (spec, open
  # question 1). A form not listed here is "other".
  @families %{
    "romance" => ~w(romance romance_tirada romancillo_o_endecha),
    "spanish" => ~w(redondilla quintilla decima copla_arte_mayor copla_estructura_abierta),
    "italianate" => ~w(terceto octava_real soneto lira sexteto_lira silva silva_tirada
                       cancion cancion_canzone endecasilabos_sueltos_tirada
                       pareados_endecasilabos cuarteto verso_suelto)
  }

  @doc "Division types that are acts."
  def act_types, do: @act_types

  @doc ~S'The family of a verse form: "romance", "spanish", "italianate" or "other".'
  def family(form) do
    Enum.find_value(@families, "other", fn {family, forms} -> if form in forms, do: family end)
  end

  @doc """
  The play's text as a flat list in reading order: a division's own elements, then
  its scenes'. Each item is a map with

    * `:kind` — `:verse`, `:prose` or `:stage`
    * `:element`, `:line_group` (or nil), `:speech` (or nil)
    * `:speakers` — `{key, name}` per speaker: the character id, or
      `"label:" <> label` when the speech names no character
    * `:number` — the verse number; for a split verse's `M`/`F` fragment, the number
      of the verse it completes; nil for prose and stage directions
    * `:act` — 1-based ordinal among the act divisions, nil outside them
    * `:division` (top level) and `:scene` (child division or nil)
  """
  def items(divisions) do
    {items, _acts} =
      Enum.flat_map_reduce(divisions, 0, fn division, previous ->
        act = if division.type in @act_types, do: previous + 1
        context = %{act: act, division: division, scene: nil}

        own = Enum.flat_map(division.loaded_elements, &element_items(&1, context))

        scenes =
          Enum.flat_map(division.children, fn scene ->
            Enum.flat_map(scene.loaded_elements, &element_items(&1, %{context | scene: scene}))
          end)

        {own ++ scenes, act || previous}
      end)

    number_fragments(items)
  end

  defp element_items(%{type: "speech"} = speech, context) do
    context = Map.merge(context, %{speech: speech, speakers: speakers(speech)})

    Enum.flat_map(speech.children, fn
      %{type: "line_group"} = group ->
        Enum.flat_map(group.children, &leaf(&1, Map.put(context, :line_group, group)))

      child ->
        leaf(child, Map.put(context, :line_group, nil))
    end)
  end

  # WordParser puts a stanza straight under the division when {m} has no speaker open.
  defp element_items(%{type: "line_group"} = group, context),
    do:
      Enum.flat_map(
        group.children,
        &leaf(&1, Map.merge(context, %{speech: nil, speakers: [], line_group: group}))
      )

  defp element_items(element, context),
    do: leaf(element, Map.merge(context, %{speech: nil, speakers: [], line_group: nil}))

  defp leaf(%{type: "verse_line"} = el, context),
    do: [Map.merge(context, %{kind: :verse, element: el})]

  defp leaf(%{type: "prose"} = el, context),
    do: [Map.merge(context, %{kind: :prose, element: el})]

  defp leaf(%{type: "stage_direction"} = el, context),
    do: [Map.merge(context, %{kind: :stage, element: el})]

  defp leaf(_element, _context), do: []

  defp speakers(speech) do
    label = speech.speaker_label

    case Element.characters(speech) do
      [] when label in [nil, ""] -> []
      [] -> [{"label:" <> label, label}]
      characters -> Enum.map(characters, &{&1.id, &1.name})
    end
  end

  # A fragment that continues a split verse has no number of its own; it belongs to
  # the verse its first fragment opened.
  defp number_fragments(items) do
    {items, _last} =
      Enum.map_reduce(items, nil, fn
        %{kind: :verse, element: %{line_number: n}} = item, _last when is_integer(n) ->
          {Map.put(item, :number, n), n}

        %{kind: :verse, element: %{part: part}} = item, last when part in ["M", "F"] ->
          {Map.put(item, :number, last), last}

        item, last ->
          {Map.put(item, :number, nil), last}
      end)

    items
  end

  @doc "True for a verse line that is a whole verse or a split verse's first fragment."
  def whole_verse?(%{kind: :verse, element: %{part: part}}), do: part in @whole_verse
  def whole_verse?(_item), do: false

  @doc """
  The metrical passages in order. Each is a map with `:act`, `:form` (a verse-type
  slug, or `"unmarked"`), `:from` and `:to` (first and last verse number), `:verses`
  (a split verse counts once) and `:element_ids` (its verse lines, in order).

  A line group with a real form and no `part`, or `part="I"`, opens a passage unless
  the open one has the same form. `M`/`F` fragments and lines outside any group
  continue the open passage. A new top-level division (an act, a prologue) closes it.
  Returns `[]` when every passage is unmarked.
  """
  def passages(items) do
    {passages, _seen} =
      items
      |> Enum.filter(&(&1.kind == :verse))
      |> Enum.reduce({[], nil}, fn item, {passages, seen} ->
        group = {item.division.id, item.line_group && item.line_group.id}
        passages = if group == seen, do: passages, else: place(item, passages, seen)
        {add_verse(passages, item), group}
      end)

    passages =
      passages
      |> Enum.reverse()
      |> Enum.map(&Map.update!(&1, :element_ids, fn ids -> Enum.reverse(ids) end))

    if Enum.all?(passages, &(&1.form == "unmarked")), do: [], else: passages
  end

  defp place(item, passages, seen) do
    group = item.line_group
    division = item.division.id

    open =
      case {passages, seen} do
        {[current | _], {^division, _}} -> current
        _ -> nil
      end

    cond do
      open == nil -> [new_passage(item, form(group)) | passages]
      group == nil or group.part in ["M", "F"] -> passages
      open.form == form(group) -> passages
      true -> [new_passage(item, form(group)) | passages]
    end
  end

  defp form(nil), do: "unmarked"
  defp form(%{verse_type: type}) when type in @unmarked, do: "unmarked"
  defp form(%{verse_type: type}), do: type

  defp new_passage(item, form),
    do: %{act: item.act, form: form, from: nil, to: nil, verses: 0, element_ids: []}

  defp add_verse([current | rest], %{element: element} = item) do
    n = element.line_number
    whole = if whole_verse?(item), do: 1, else: 0

    current = %{
      current
      | from: current.from || n,
        to: n || current.to,
        verses: current.verses + whole,
        element_ids: [element.id | current.element_ids]
    }

    [current | rest]
  end

  @doc "Number of words in element content; the `<<`/`>>` markers are not words."
  def words(nil), do: 0
  def words(text), do: length(Regex.scan(~r/[\p{L}\p{N}]+/u, text))

  @doc """
  Presence columns: the play's scenes if it has any, else its metrical passages, else
  its top-level divisions. Returns `{basis, columns, column_of}`, where `column_of`
  maps an item to its column index, or nil.
  """
  def columns(items, passages) do
    cond do
      Enum.any?(items, & &1.scene) ->
        # One column per {division, scene or nil} holding spoken text: a division's own
        # scene-less text (a prologue's, an act without scenes) is a column of its own.
        units =
          items
          |> Enum.filter(&(&1.kind in [:verse, :prose] and &1.speech != nil))
          |> Enum.uniq_by(&unit_key/1)

        index = units |> Enum.with_index() |> Map.new(fn {item, i} -> {unit_key(item), i} end)
        columns = Enum.map(units, &%{"act" => &1.act, "label" => unit_label(&1)})

        {"scene", columns, fn item -> index[unit_key(item)] end}

      passages != [] ->
        index =
          passages
          |> Enum.with_index()
          |> Enum.flat_map(fn {passage, i} -> Enum.map(passage.element_ids, &{&1, i}) end)
          |> Map.new()

        columns =
          Enum.map(passages, fn p ->
            %{
              "act" => p.act,
              "form" => p.form,
              "family" => family(p.form),
              "from" => p.from,
              "to" => p.to
            }
          end)

        {"passage", columns, fn item -> index[item.element.id] end}

      true ->
        divisions = Enum.uniq_by(items, & &1.division.id)

        index =
          divisions |> Enum.with_index() |> Map.new(fn {item, i} -> {item.division.id, i} end)

        columns = Enum.map(divisions, &%{"act" => &1.act, "label" => &1.division.title})
        {"division", columns, fn item -> index[item.division.id] end}
    end
  end

  defp unit_key(item), do: {item.division.id, item.scene && item.scene.id}

  defp unit_label(%{scene: nil, division: division}),
    do: division.title || String.capitalize(division.type)

  defp unit_label(%{scene: scene, act: act}) do
    scene.title ||
      if(act,
        do: "#{act}.#{scene.position + 1}",
        else: "#{String.capitalize(scene.type)} #{scene.position + 1}"
      )
  end

  @doc "Per-character figures, most lines first, then most words."
  def characters(items, passages, column_of) do
    form_of =
      passages
      |> Enum.flat_map(fn passage -> Enum.map(passage.element_ids, &{&1, passage.form}) end)
      |> Map.new()

    items
    |> Enum.filter(&(&1.kind in [:verse, :prose] and &1.speech != nil))
    |> Enum.flat_map(fn item -> Enum.map(item.speakers, &{&1, item}) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {{key, name}, spoken} -> character(key, name, spoken, form_of, column_of) end)
    |> Enum.sort_by(&{-&1["lines"], -&1["words"], &1["name"]})
  end

  defp character(key, name, spoken, form_of, column_of) do
    verses = Enum.filter(spoken, &(&1.kind == :verse))
    speeches = spoken |> Enum.group_by(& &1.speech.id) |> Map.values()
    first = hd(spoken)

    %{
      "key" => key,
      "name" => name,
      "speeches" => length(speeches),
      "lines" => length(verses),
      "words" => sum_words(spoken),
      "first" => %{"act" => first.act, "line" => first.number},
      "aside_verses" => Enum.count(verses, & &1.element.is_aside),
      "longest_speech" => %{
        "lines" =>
          speeches |> Enum.map(&Enum.count(&1, fn item -> item.kind == :verse end)) |> Enum.max(),
        "words" => speeches |> Enum.map(&sum_words/1) |> Enum.max()
      },
      "forms" =>
        verses
        |> Enum.map(&form_of[&1.element.id])
        |> Enum.reject(&is_nil/1)
        |> Enum.frequencies(),
      "columns" =>
        spoken
        |> Enum.map(column_of)
        |> Enum.reject(&is_nil/1)
        |> Enum.frequencies()
        |> Enum.sort()
        |> Enum.map(&Tuple.to_list/1)
    }
  end

  defp sum_words(items), do: items |> Enum.map(&words(&1.element.content)) |> Enum.sum()

  @doc "Verses, speeches and speakers per top-level division and per scene, in order."
  def divisions(items) do
    items
    |> Enum.chunk_by(&{&1.division.id, &1.scene && &1.scene.id})
    |> Enum.map(fn [first | _] = chunk ->
      spoken = Enum.filter(chunk, &(&1.kind in [:verse, :prose] and &1.speech != nil))

      %{
        "act" => first.act,
        "division" => first.division.title,
        "scene" => first.scene && first.scene.title,
        "verses" => Enum.count(chunk, &whole_verse?/1),
        "speeches" => spoken |> Enum.uniq_by(& &1.speech.id) |> length(),
        "speakers" => spoken |> Enum.flat_map(& &1.speakers) |> Enum.uniq() |> length()
      }
    end)
  end
end
