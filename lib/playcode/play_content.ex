defmodule Playcode.PlayContent do
  @moduledoc """
  The PlayContent context manages the structured content of plays:
  characters, divisions (acts/scenes), elements (speeches, verses, stage directions) and
  their notes. A note sits at a grapheme offset into its anchor's text (`anchor_text/1`);
  editing that text moves the note with its word.

  Every change to a play reaches `{:play_content_changed, play_id}` on its topic
  (`subscribe/1`) once it commits, whoever made it: Postgres notifies `play_changed`
  and `Playcode.Export.PlayChangeListener` calls `notify_changed/1`.
  """

  import Ecto.Query
  alias Playcode.Repo
  alias Playcode.PlayContent.{Character, Division, Element, ElementCharacter, InlineMarkup, Note}

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

  defp get_play_row(schema, play_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get_by(schema, id: id, play_id: play_id)
      :error -> nil
    end
  end

  # --- Characters ---

  @doc """
  The play's cast, in cast-list order.
  """
  def list_characters(play_id) do
    Character
    |> where(play_id: ^play_id)
    |> order_by(:position)
    |> Repo.all()
  end

  @doc """
  The play's character `id`, or nil. Scoped to the play because the id arrives from the
  browser: another play's character, a deleted one or a malformed id is nil.
  """
  def get_character(play_id, id), do: get_play_row(Character, play_id, id)

  @doc """
  Creates a character; `attrs` carry its `play_id`. Its `xml_id` must be unique in the play.
  """
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

  @doc """
  The play's character with this `xml_id`, the id `<sp who>` cites, or nil.
  """
  def find_character_by_xml_id(play_id, xml_id) do
    Repo.get_by(Character, play_id: play_id, xml_id: xml_id)
  end

  @doc """
  A character's changeset, for a form.
  """
  def change_character(%Character{} = character, attrs \\ %{}) do
    Character.changeset(character, attrs)
  end

  @doc """
  Updates a character.
  """
  def update_character(%Character{} = character, attrs) do
    character |> Character.changeset(attrs) |> Repo.update()
  end

  @doc """
  Deletes a character, and with it every speech's assignment to it.
  """
  def delete_character(%Character{} = character) do
    Repo.delete(character)
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

  @doc """
  The play's top-level divisions in order, each with its children in order.
  """
  def list_top_divisions(play_id) do
    Division
    |> where(play_id: ^play_id)
    |> where([d], is_nil(d.parent_id))
    |> order_by(:position)
    |> Repo.all()
    |> Repo.preload(children: from(d in Division, order_by: d.position))
  end

  @doc """
  As `get_character/2`, for a division.
  """
  def get_division(play_id, id), do: get_play_row(Division, play_id, id)

  @doc """
  Creates a division; `attrs` carry its `play_id`, and its `parent_id` for a scene.
  """
  def create_division(attrs) do
    %Division{}
    |> Division.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  A division's changeset, for a form.
  """
  def change_division(%Division{} = division, attrs \\ %{}) do
    Division.changeset(division, attrs)
  end

  @doc """
  Updates a division. Its notes keep their place in its title (`carry_notes/3`).
  """
  def update_division(%Division{} = division, attrs),
    do: division |> Division.changeset(attrs) |> update_anchor(division_id: division.id)

  @doc """
  Deletes a division with its scenes and every element in them.
  """
  def delete_division(%Division{} = division) do
    Repo.delete(division)
  end

  @doc """
  The position after the last division under `parent_id`, or at the top level when nil.
  """
  def next_division_position(play_id, parent_id \\ nil) do
    query = Division |> where(play_id: ^play_id)

    query =
      if parent_id,
        do: where(query, parent_id: ^parent_id),
        else: where(query, [d], is_nil(d.parent_id))

    query |> select([d], coalesce(max(d.position), -1) + 1) |> Repo.one()
  end

  # --- Elements ---

  @doc """
  The division's top-level elements in order, three levels deep (speech, line group,
  verse), each with its speakers in order.
  """
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

  @doc """
  Up to 50 of the play's elements whose text or speaker label contains `query`,
  case-insensitively, with their division. A query shorter than two bytes finds nothing.
  """
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

  @doc """
  The element `id` with its speakers in order. Raises when there is none.
  """
  def get_element!(id) do
    Repo.get!(Element, id)
    |> Repo.preload(
      element_characters: from(ec in ElementCharacter, order_by: ec.position, preload: :character)
    )
  end

  @doc """
  As `get_character/2`, for an element, with its speakers in order.
  """
  def get_element(play_id, id) do
    case get_play_row(Element, play_id, id) do
      nil ->
        nil

      element ->
        Repo.preload(element,
          element_characters:
            from(ec in ElementCharacter, order_by: ec.position, preload: :character)
        )
    end
  end

  @doc """
  Creates an element; `attrs` carry its `play_id`, `division_id` and `parent_id`.
  """
  def create_element(attrs) do
    %Element{}
    |> Element.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  An element's changeset, for a form.
  """
  def change_element(%Element{} = element, attrs \\ %{}) do
    Element.changeset(element, attrs)
  end

  @doc """
  Updates an element. Its notes keep their place in its text (`carry_notes/3`).
  """
  def update_element(%Element{} = element, attrs),
    do: element |> Element.changeset(attrs) |> update_anchor(element_id: element.id)

  @doc """
  Deletes an element and the elements under it.
  """
  def delete_element(%Element{} = element) do
    Repo.delete(element)
  end

  # --- Notes ---

  @doc "The notes on an element or a division, in text order."
  def list_notes(%Element{id: id}), do: notes_query() |> where(element_id: ^id) |> Repo.all()
  def list_notes(%Division{id: id}), do: notes_query() |> where(division_id: ^id) |> Repo.all()

  defp notes_query, do: from(n in Note, order_by: [n.offset, n.position])

  @doc """
  Creates a note; `attrs` carry its `play_id` and its `element_id` or `division_id`. It goes
  after the notes already at its offset, whatever `position` says.
  """
  def create_note(attrs),
    do: %Note{} |> Note.changeset(attrs) |> put_next_position() |> Repo.insert()

  @doc "A note's changeset, for a form."
  def change_note(%Note{} = note, attrs \\ %{}), do: Note.changeset(note, attrs)

  @doc """
  Updates a note. One moved to another offset goes after the notes already there; any
  other change leaves it where it is among them.
  """
  def update_note(%Note{} = note, attrs) do
    changeset = Note.changeset(note, attrs)

    changeset =
      if Map.has_key?(changeset.changes, :offset),
        do: put_next_position(changeset),
        else: changeset

    Repo.update(changeset)
  end

  @doc "Deletes a note."
  def delete_note(%Note{} = note), do: Repo.delete(note)

  # `position` orders the notes at one offset of one anchor, and the public numbering, the
  # pop-ups and the TEI export follow it, so a note must not tie with another.
  # ponytail: two curators adding at one word in the same instant can still tie; lock the
  # anchor's row if that ever happens.
  defp put_next_position(%{valid?: true} = changeset) do
    offset = Ecto.Changeset.get_field(changeset, :offset)

    anchor =
      case {Ecto.Changeset.get_field(changeset, :element_id),
            Ecto.Changeset.get_field(changeset, :division_id)} do
        {nil, nil} -> nil
        {nil, division_id} -> {:division_id, division_id}
        {element_id, _} -> {:element_id, element_id}
      end

    case anchor do
      nil ->
        changeset

      {key, id} ->
        last =
          Repo.one(
            from n in Note,
              where: n.offset == ^offset and field(n, ^key) == ^id,
              select: max(n.position)
          )

        Ecto.Changeset.put_change(changeset, :position, (last || -1) + 1)
    end
  end

  defp put_next_position(changeset), do: changeset

  @doc """
  The text a note on `anchor` counts its offset in: a division's title, a speech's
  speaker label, any other element's content.
  """
  def anchor_text(%Division{title: title}), do: title
  def anchor_text(%Element{type: "speech", speaker_label: label}), do: label
  def anchor_text(%Element{content: content}), do: content

  # Saves an element's or a division's changeset and, in the same transaction, moves its
  # notes through the change to its text.
  defp update_anchor(changeset, where) do
    Repo.transaction(fn ->
      case Repo.update(changeset) do
        {:ok, updated} ->
          carry_notes(where, anchor_text(changeset.data), anchor_text(updated))
          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp carry_notes(_where, same, same), do: :ok

  defp carry_notes(where, old, new) do
    diff = String.myers_difference(InlineMarkup.plain(old), InlineMarkup.plain(new))

    Note
    |> where(^where)
    |> Repo.all()
    |> Enum.each(fn note ->
      case carry(note.offset, diff) do
        offset when offset == note.offset -> :ok
        offset -> note |> Ecto.Changeset.change(offset: offset) |> Repo.update!()
      end
    end)
  end

  # Where offset `k` of the old text lands in the new one, through
  # String.myers_difference/2's script: a kept run carries it along (a note at the end of
  # a run stays after it), an insertion before it pushes it right, and a deletion holding
  # it leaves it where the deletion was.
  defp carry(k, diff) do
    {_old, new, landed} =
      Enum.reduce(diff, {0, 0, nil}, fn
        _step, {_old, _new, landed} = done when landed != nil ->
          done

        {:eq, run}, {old, new, nil} ->
          length = String.length(run)

          if k <= old + length,
            do: {old, new, new + k - old},
            else: {old + length, new + length, nil}

        {:ins, run}, {old, new, nil} ->
          {old, new + String.length(run), nil}

        {:del, run}, {old, new, nil} ->
          length = String.length(run)
          if k < old + length, do: {old, new, new}, else: {old + length, new, nil}
      end)

    landed || new
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

  @doc """
  The position after the last element under `parent_id` in the division, or at its top level when nil.
  """
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
      |> Repo.preload([
        :notes,
        children: from(d in Division, order_by: d.position, preload: :notes)
      ])

    # Load elements per division (including sub-divisions)
    all_division_ids = collect_division_ids(divisions)

    ec_preload = from(ec in ElementCharacter, order_by: ec.position, preload: :character)

    elements =
      Element
      |> where([e], e.division_id in ^all_division_ids)
      |> where([e], is_nil(e.parent_id))
      |> order_by(:position)
      |> Repo.all()
      |> Repo.preload([
        :notes,
        element_characters: ec_preload,
        children:
          from(e in Element,
            order_by: e.position,
            preload: [
              :notes,
              element_characters: ^ec_preload,
              children:
                ^from(c in Element,
                  order_by: c.position,
                  preload: [:notes, element_characters: ^ec_preload]
                )
            ]
          )
      ])

    elements_by_division = Enum.group_by(elements, & &1.division_id)

    divisions |> attach_elements(elements_by_division) |> number_notes()
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

  # Gives each note its `number`: its place in Note.reading_order/1, from 1.
  defp number_notes(divisions) do
    numbers =
      divisions
      |> Note.reading_order()
      |> Enum.with_index(1)
      |> Map.new(fn {note, number} -> {note.id, number} end)

    Enum.map(divisions, &number_division(&1, numbers))
  end

  defp number_division(division, numbers) do
    %{
      division
      | notes: number(division.notes, numbers),
        loaded_elements: Enum.map(division.loaded_elements, &number_element(&1, numbers)),
        children: Enum.map(division.children, &number_division(&1, numbers))
    }
  end

  defp number_element(element, numbers) do
    children =
      case element.children do
        %Ecto.Association.NotLoaded{} = not_loaded -> not_loaded
        children -> Enum.map(children, &number_element(&1, numbers))
      end

    %{element | notes: number(element.notes, numbers), children: children}
  end

  defp number(notes, numbers), do: Enum.map(notes, &%{&1 | number: numbers[&1.id]})
end
