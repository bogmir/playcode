defmodule Playcode.PlayContent do
  @moduledoc """
  The PlayContent context manages the structured content of plays:
  characters, divisions (acts/scenes), and elements (speeches, verses, stage directions).

  Every change to a play reaches `{:play_content_changed, play_id}` on its topic
  (`subscribe/1`) once it commits, whoever made it: Postgres notifies `play_changed`
  and `Playcode.Export.PlayChangeListener` calls `notify_changed/1`.
  """

  import Ecto.Query
  alias Playcode.Repo
  alias Playcode.PlayContent.{Character, Division, Element, ElementCharacter}

  @pubsub Playcode.PubSub

  @doc "Subscribe the calling process to content-change events for this play."
  def subscribe(play_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(play_id))
  end

  @doc "Stop the calling process's content-change events for this play."
  def unsubscribe(play_id), do: Phoenix.PubSub.unsubscribe(@pubsub, topic(play_id))

  @doc """
  Tells the play's subscribers that it changed. `Playcode.Export.PlayChangeListener`
  calls it for every `play_changed` notification from Postgres, so every writer reaches
  them, once its transaction commits.
  """
  def notify_changed(play_id) do
    Phoenix.PubSub.broadcast(@pubsub, topic(play_id), {:play_content_changed, play_id})
  end

  @doc """
  Refreshes what is derived from the content and stored on the play: its verse count.
  Call it after a content edit. Subscribers hear of the edit from Postgres, on commit;
  the cached statistics go stale by themselves, with the play's `content_version`.
  """
  def refresh_derived(play_id), do: Playcode.Catalogue.update_verse_count(play_id)

  defp topic(play_id), do: "play_content:#{play_id}"

  # --- Characters ---

  def list_characters(play_id) do
    Character
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  def get_character!(id), do: Repo.get!(Character, id)

  def create_character(attrs) do
    %Character{}
    |> Character.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Creates a character, silently skipping if the xml_id already exists for this play.
  Used during TEI import where malformed files may contain duplicate xml:id entries.
  Returns the existing character when a conflict is detected.
  """
  def create_character_unless_exists(attrs) do
    play_id = attrs[:play_id] || attrs["play_id"]
    xml_id = attrs[:xml_id] || attrs["xml_id"]
    name = attrs[:name] || attrs["name"]

    case find_character_by_xml_id(play_id, xml_id) do
      nil ->
        create_character(attrs)

      %Character{name: existing_name} = existing when existing_name == name ->
        {:ok, existing}

      _different_name ->
        # Same xml_id but different name — generate a unique suffix
        unique_id = generate_unique_xml_id(play_id, xml_id, 2)
        create_character(Map.put(attrs, :xml_id, unique_id))
    end
  end

  defp generate_unique_xml_id(play_id, base_id, n) do
    candidate = "#{base_id}_#{n}"

    case find_character_by_xml_id(play_id, candidate) do
      nil -> candidate
      _ -> generate_unique_xml_id(play_id, base_id, n + 1)
    end
  end

  def find_character_by_xml_id(play_id, xml_id) do
    Repo.get_by(Character, play_id: play_id, xml_id: xml_id)
  end

  def change_character(%Character{} = character, attrs \\ %{}) do
    Character.changeset(character, attrs)
  end

  def update_character(%Character{} = character, attrs) do
    character |> Character.changeset(attrs) |> Repo.update()
  end

  def delete_character(%Character{} = character) do
    Repo.delete(character)
  end

  def next_character_position(play_id) do
    Character
    |> where(play_id: ^play_id)
    |> select([c], coalesce(max(c.position), -1) + 1)
    |> Repo.one()
  end

  @doc """
  Shifts all character positions up by 1 to make room at position 0.
  """
  def shift_character_positions(play_id) do
    Character
    |> where(play_id: ^play_id)
    |> Repo.update_all(inc: [position: 1])
  end

  @doc """
  Moves a character up or down in the list by swapping positions with its neighbor.
  Direction is :up or :down.
  """
  def reorder_character(play_id, character_id, direction) do
    characters = list_characters(play_id)
    index = Enum.find_index(characters, &(&1.id == character_id))

    target_index =
      case direction do
        :up -> index - 1
        :down -> index + 1
      end

    if index && target_index >= 0 && target_index < length(characters) do
      current = Enum.at(characters, index)
      target = Enum.at(characters, target_index)

      Repo.transaction(fn ->
        current |> Character.changeset(%{position: target.position}) |> Repo.update!()
        target |> Character.changeset(%{position: current.position}) |> Repo.update!()
      end)
    else
      {:ok, :noop}
    end
  end

  @doc """
  Reorders characters by assigning positions based on the given list of IDs.
  The first ID gets position 0, the second gets position 1, etc.
  """
  def reorder_characters(play_id, ordered_ids) when is_list(ordered_ids) do
    Repo.transaction(fn ->
      ordered_ids
      |> Enum.with_index()
      |> Enum.each(fn {id, position} ->
        Character
        |> where(id: ^id, play_id: ^play_id)
        |> Repo.update_all(set: [position: position, updated_at: DateTime.utc_now()])
      end)
    end)
  end

  # --- Divisions ---

  def list_top_divisions(play_id) do
    Division
    |> where(play_id: ^play_id)
    |> where([d], is_nil(d.parent_id))
    |> order_by(:position)
    |> Repo.all()
    |> Repo.preload(children: from(d in Division, order_by: d.position))
  end

  def get_division!(id), do: Repo.get!(Division, id)

  def create_division(attrs) do
    %Division{}
    |> Division.changeset(attrs)
    |> Repo.insert()
  end

  def change_division(%Division{} = division, attrs \\ %{}) do
    Division.changeset(division, attrs)
  end

  def update_division(%Division{} = division, attrs) do
    division |> Division.changeset(attrs) |> Repo.update()
  end

  def delete_division(%Division{} = division) do
    Repo.delete(division)
  end

  def next_division_position(play_id, parent_id \\ nil) do
    query = Division |> where(play_id: ^play_id)

    query =
      if parent_id,
        do: where(query, parent_id: ^parent_id),
        else: where(query, [d], is_nil(d.parent_id))

    query |> select([d], coalesce(max(d.position), -1) + 1) |> Repo.one()
  end

  # --- Elements ---

  def list_elements_for_division(division_id) do
    ec_preload = from(ec in ElementCharacter, order_by: ec.position, preload: :character)

    Element
    |> where(division_id: ^division_id)
    |> where([e], is_nil(e.parent_id))
    |> order_by(:position)
    |> Repo.all()
    |> Repo.preload(
      element_characters: ec_preload,
      children:
        from(e in Element,
          order_by: e.position,
          preload: [
            element_characters: ^ec_preload,
            children:
              ^from(c in Element,
                order_by: c.position,
                preload: [
                  element_characters: ^ec_preload,
                  children:
                    ^from(v in Element,
                      order_by: v.position,
                      preload: [element_characters: ^ec_preload]
                    )
                ]
              )
          ]
        )
    )
  end

  def search_elements(play_id, query) when is_binary(query) and byte_size(query) >= 2 do
    pattern = "%#{query}%"

    from(e in Element,
      where: e.play_id == ^play_id,
      where: ilike(e.content, ^pattern) or ilike(e.speaker_label, ^pattern),
      left_join: d in assoc(e, :division),
      preload: [division: d],
      order_by: [e.position],
      limit: 50
    )
    |> Repo.all()
  end

  def search_elements(_play_id, _query), do: []

  def list_all_elements(play_id) do
    Element
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  def get_element!(id) do
    Repo.get!(Element, id)
    |> Repo.preload(
      element_characters: from(ec in ElementCharacter, order_by: ec.position, preload: :character)
    )
  end

  def create_element(attrs) do
    %Element{}
    |> Element.changeset(attrs)
    |> Repo.insert()
  end

  def change_element(%Element{} = element, attrs \\ %{}) do
    Element.changeset(element, attrs)
  end

  def update_element(%Element{} = element, attrs) do
    element |> Element.changeset(attrs) |> Repo.update()
  end

  def delete_element(%Element{} = element) do
    Repo.delete(element)
  end

  @doc """
  Shifts positions of elements at or after `from_position` up by 1,
  making room to insert a new element at `from_position`.
  """
  def shift_element_positions(division_id, parent_id, from_position) do
    query =
      Element
      |> where(division_id: ^division_id)
      |> where([e], e.position >= ^from_position)

    query =
      if parent_id,
        do: where(query, parent_id: ^parent_id),
        else: where(query, [e], is_nil(e.parent_id))

    Repo.update_all(query, inc: [position: 1])
  end

  @doc """
  Calculates the line number for a new verse line being inserted at `position`
  within the given `parent_id` (line_group). Does NOT shift existing numbers —
  call `shift_line_numbers/2` separately at save time.
  """
  def auto_line_number(play_id, parent_id, position) do
    # Find the previous verse line in the same line_group (by position)
    prev_number =
      Element
      |> where(parent_id: ^parent_id)
      |> where(type: "verse_line")
      |> where([e], e.position < ^position)
      |> where([e], not is_nil(e.line_number))
      |> order_by(desc: :position)
      |> limit(1)
      |> select([e], e.line_number)
      |> Repo.one()

    case prev_number do
      nil ->
        # First verse in group — check if there's a next sibling
        next_number =
          Element
          |> where(parent_id: ^parent_id)
          |> where(type: "verse_line")
          |> where([e], e.position >= ^position)
          |> where([e], not is_nil(e.line_number))
          |> order_by(:position)
          |> limit(1)
          |> select([e], e.line_number)
          |> Repo.one()

        case next_number do
          nil -> global_max_line_number(play_id) + 1
          n -> n
        end

      n ->
        n + 1
    end
  end

  @doc """
  Shifts all verse_line line_numbers >= `from_number` up by 1 in the given play.
  Preserves split verse groupings since all parts share the same number.
  """
  def shift_line_numbers(play_id, from_number) do
    Element
    |> where(play_id: ^play_id)
    |> where(type: "verse_line")
    |> where([e], e.line_number >= ^from_number)
    |> Repo.update_all(inc: [line_number: 1])
  end

  @doc """
  Shifts all verse_line line_numbers > `deleted_number` down by 1 in the given play.
  Only call this when the deleted verse was not part of a split verse.
  """
  def shift_line_numbers_down(play_id, deleted_number) do
    Element
    |> where(play_id: ^play_id)
    |> where(type: "verse_line")
    |> where([e], e.line_number > ^deleted_number)
    |> Repo.update_all(inc: [line_number: -1])
  end

  @doc """
  Returns true if there are other verse_lines in the play with the same line_number
  (i.e. split verse partners).
  """
  def split_verse?(play_id, element_id, line_number) do
    Element
    |> where(play_id: ^play_id)
    |> where(type: "verse_line")
    |> where([e], e.line_number == ^line_number)
    |> where([e], e.id != ^element_id)
    |> Repo.exists?()
  end

  defp global_max_line_number(play_id) do
    Element
    |> where(play_id: ^play_id)
    |> where(type: "verse_line")
    |> where([e], not is_nil(e.line_number))
    |> select([e], max(e.line_number))
    |> Repo.one() || 0
  end

  def next_element_position(division_id, parent_id \\ nil) do
    query = Element |> where(division_id: ^division_id)

    query =
      if parent_id,
        do: where(query, parent_id: ^parent_id),
        else: where(query, [e], is_nil(e.parent_id))

    query |> select([e], coalesce(max(e.position), -1) + 1) |> Repo.one()
  end

  @doc """
  Loads the full play content tree: divisions with nested elements.
  Used for rendering the play text.
  """
  def load_play_content(play_id) do
    divisions =
      Division
      |> where(play_id: ^play_id)
      |> where([d], is_nil(d.parent_id))
      |> order_by(:position)
      |> Repo.all()
      |> Repo.preload(children: from(d in Division, order_by: d.position))

    # Load elements per division (including sub-divisions)
    all_division_ids = collect_division_ids(divisions)

    ec_preload = from(ec in ElementCharacter, order_by: ec.position, preload: :character)

    elements =
      Element
      |> where([e], e.division_id in ^all_division_ids)
      |> where([e], is_nil(e.parent_id))
      |> order_by(:position)
      |> Repo.all()
      |> Repo.preload(
        element_characters: ec_preload,
        children:
          from(e in Element,
            order_by: e.position,
            preload: [
              element_characters: ^ec_preload,
              children:
                ^from(c in Element,
                  order_by: c.position,
                  preload: [element_characters: ^ec_preload]
                )
            ]
          )
      )

    elements_by_division = Enum.group_by(elements, & &1.division_id)

    attach_elements(divisions, elements_by_division)
  end

  # --- Element-Character associations ---

  @doc """
  Replaces all character associations for an element with the given character_ids.
  Position is assigned based on list order (0, 1, 2, ...).
  """
  def set_element_characters(element_id, character_ids) when is_list(character_ids) do
    Repo.transaction(fn ->
      # Delete existing associations
      ElementCharacter
      |> where(element_id: ^element_id)
      |> Repo.delete_all()

      # Insert new associations with position
      character_ids
      |> Enum.with_index()
      |> Enum.each(fn {character_id, position} ->
        %ElementCharacter{}
        |> ElementCharacter.changeset(%{
          element_id: element_id,
          character_id: character_id,
          position: position
        })
        |> Repo.insert!()
      end)

      :ok
    end)
  end

  @doc """
  Returns ordered character_ids for an element.
  """
  def get_element_character_ids(element_id) do
    ElementCharacter
    |> where(element_id: ^element_id)
    |> order_by(:position)
    |> select([ec], ec.character_id)
    |> Repo.all()
  end

  defp collect_division_ids(divisions) do
    Enum.flat_map(divisions, fn div ->
      children = Map.get(div, :children, [])
      children = if is_list(children), do: children, else: []
      [div.id | collect_division_ids(children)]
    end)
  end

  defp attach_elements(divisions, elements_by_division) do
    Enum.map(divisions, fn div ->
      children =
        case div.children do
          %Ecto.Association.NotLoaded{} -> []
          children -> attach_elements(children, elements_by_division)
        end

      elements = Map.get(elements_by_division, div.id, [])
      %{div | children: children, loaded_elements: elements}
    end)
  end
end
