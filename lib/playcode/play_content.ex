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
  alias Playcode.Catalogue.Paratext

  alias Playcode.PlayContent.{
    CastListEntry,
    Character,
    Division,
    Element,
    ElementCharacter,
    InlineMarkup,
    Note
  }

  alias Playcode.Witnesses

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
  Creates a character with its entry in a cast list; `attrs` carry its `play_id`, and may
  carry the list's `cast_list_id`, the entry's `group_heading` and `position`. With no list
  named, the entry goes in the play's first, made at the head of the outline when the play
  has none. Its `xml_id` must be unique in the play.
  """
  def create_character(attrs) do
    Repo.transaction(fn ->
      with {:ok, character} <- %Character{} |> Character.changeset(attrs) |> Repo.insert(),
           {:ok, _entry} <-
             create_entry(%{
               play_id: character.play_id,
               cast_list_id: attr(attrs, :cast_list_id) || first_cast_list_id(character.play_id),
               character_id: character.id,
               name: character.name,
               description: character.description,
               group_heading: attr(attrs, :group_heading),
               position: attr(attrs, :position)
             }) do
        Repo.get!(Character, character.id)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp attr(attrs, key), do: Map.get(attrs, key) || Map.get(attrs, to_string(key))

  defp first_cast_list_id(play_id) do
    case list_cast_lists(play_id) do
      [list | _] ->
        list.id

      [] ->
        {:ok, list} =
          create_division(%{play_id: play_id, type: "elenco", position: head_position(play_id)})

        list.id
    end
  end

  # A position before every top-level item of the play: its divisions and its paratexts.
  defp head_position(play_id) do
    first =
      Enum.min(
        [
          Repo.one(
            from d in Division,
              where: d.play_id == ^play_id and is_nil(d.parent_id),
              select: min(d.position)
          ),
          Repo.one(from p in Paratext, where: p.play_id == ^play_id, select: min(p.position))
        ]
        |> Enum.reject(&is_nil/1),
        fn -> 1 end
      )

    first - 1
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
    Repo.transaction(fn ->
      with {:ok, character} <- character |> Character.changeset(attrs) |> Repo.update() do
        case first_entry(character) do
          nil ->
            :ok

          entry ->
            entry
            |> CastListEntry.changeset(%{
              name: character.name,
              description: character.description
            })
            |> Repo.update!()
        end

        sync_characters(character.play_id)
        Repo.get!(Character, character.id)
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp first_entry(%Character{id: id, play_id: play_id}) do
    play_id
    |> list_cast_lists()
    |> Enum.flat_map(& &1.entries)
    |> Enum.find(&(&1.character_id == id))
  end

  @doc """
  Deletes a character, and with it every speech's assignment to it.
  """
  def delete_character(%Character{} = character) do
    Repo.delete(character)
  end

  # --- Cast lists ---

  @doc """
  The play's cast lists (its `elenco` divisions) in outline order: a list before, between
  or after the acts by its own position, a list inside an act at its act's place, then by
  its own. Each with its entries in order, their characters loaded.
  """
  def list_cast_lists(play_id) do
    Division
    |> where(play_id: ^play_id, type: "elenco")
    |> join(:left, [d], act in Division, on: act.id == d.parent_id)
    |> order_by([d, act],
      asc: coalesce(act.position, d.position),
      asc: fragment("? IS NOT NULL", d.parent_id),
      asc: d.position,
      asc: d.id
    )
    |> preload(entries: :character)
    |> Repo.all()
  end

  @doc "As `get_character/2`, for a cast list: nil for any division that is not one."
  def get_cast_list(play_id, id) do
    case get_division(play_id, id) do
      %Division{type: "elenco"} = list -> list
      _other -> nil
    end
  end

  @doc "As `get_character/2`, for a cast list entry."
  def get_entry(play_id, id), do: get_play_row(CastListEntry, play_id, id)

  @doc """
  Creates an entry; `attrs` carry its `play_id` and `cast_list_id`, and its `character_id`
  unless it names no one. With no `position` it stands last in its list.
  """
  def create_entry(attrs) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    attrs =
      if attrs["position"] in [nil, ""],
        do: Map.put(attrs, "position", next_entry_position(attrs["cast_list_id"])),
        else: attrs

    with {:ok, entry} <- %CastListEntry{} |> CastListEntry.changeset(attrs) |> Repo.insert() do
      sync_characters(entry.play_id)
      {:ok, entry}
    end
  end

  defp next_entry_position(cast_list_id) do
    CastListEntry
    |> where(cast_list_id: ^cast_list_id)
    |> select([e], coalesce(max(e.position), -1) + 1)
    |> Repo.one()
  end

  @doc """
  Puts the play's entries in the order of `keys`, the Characters tab's rows: `"list:<id>"`
  for a list's heading, `"entry:<id>"` for an entry, which goes in the list whose key is
  before it. A key not of this play's is dropped, and an entry after one; an entry the keys
  leave out keeps its turn in its list after those named. The characters follow their
  first entries.
  """
  def reorder_entries(play_id, keys) do
    lists = list_cast_lists(play_id)
    entries = lists |> Enum.flat_map(& &1.entries) |> Map.new(&{"entry:#{&1.id}", &1})
    list_ids = MapSet.new(lists, &"list:#{&1.id}")

    {named, _list} =
      Enum.flat_map_reduce(keys, nil, fn key, list ->
        cond do
          key in list_ids -> {[], String.replace_prefix(key, "list:", "")}
          list && entries[key] -> {[{list, entries[key]}], list}
          true -> {[], nil}
        end
      end)

    named = Enum.uniq_by(named, fn {_list, entry} -> entry.id end)
    moved = MapSet.new(named, fn {_list, entry} -> entry.id end)
    named_in = Enum.group_by(named, &elem(&1, 0), &elem(&1, 1))
    now = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      for list <- lists,
          entries = Map.get(named_in, list.id, []) ++ Enum.reject(list.entries, &(&1.id in moved)),
          {entry, position} <- Enum.with_index(entries),
          {entry.cast_list_id, entry.position} != {list.id, position} do
        CastListEntry
        |> where(id: ^entry.id)
        |> Repo.update_all(set: [cast_list_id: list.id, position: position, updated_at: now])
      end

      sync_characters(play_id)
    end)

    :ok
  end

  @doc """
  Removes an entry from its list. A character's last entry takes the character with it,
  unless the character speaks: then it is refused, `{:error, {:speaking, [name]}}`, as its
  speeches would point at no one listed.
  """
  def delete_entry(%CastListEntry{} = entry) do
    # The character this entry is the last of, if any.
    last =
      entry.character_id &&
        not Repo.exists?(
          where(CastListEntry, [e], e.character_id == ^entry.character_id and e.id != ^entry.id)
        ) && Repo.get(Character, entry.character_id)

    if last && Repo.exists?(where(ElementCharacter, character_id: ^last.id)) do
      {:error, {:speaking, [last.name]}}
    else
      Repo.transaction(fn ->
        Repo.delete!(entry)
        if last, do: Repo.delete!(last)
        sync_characters(entry.play_id)
        entry
      end)
    end
  end

  @doc "An entry's changeset, for a form."
  def change_entry(%CastListEntry{} = entry, attrs \\ %{}),
    do: CastListEntry.changeset(entry, attrs)

  @doc "Updates an entry; its character follows when it is the character's first."
  def update_entry(%CastListEntry{} = entry, attrs) do
    with {:ok, entry} <- entry |> CastListEntry.changeset(attrs) |> Repo.update() do
      sync_characters(entry.play_id)
      {:ok, entry}
    end
  end

  @doc """
  Copies each character's name, description and place from its first entry in outline
  order: the name the speaker pickers and the statistics give, the description the API
  gives, the order the characters are listed in. Only a character that differs is written.
  """
  def sync_characters(play_id) do
    firsts =
      play_id
      |> list_cast_lists()
      |> Enum.flat_map(& &1.entries)
      |> Enum.filter(& &1.character_id)
      |> Enum.uniq_by(& &1.character_id)
      |> Enum.with_index()

    for {entry, position} <- firsts,
        character = entry.character,
        {character.name, character.description, character.position} !=
          {entry.name, entry.description, position} do
      Character
      |> where(id: ^character.id)
      |> Repo.update_all(
        set: [
          name: entry.name,
          description: entry.description,
          position: position,
          updated_at: DateTime.utc_now(:second)
        ]
      )
    end

    :ok
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
  Deletes a division with its scenes, its cast lists and every element in them, and the
  characters left with no entry in any list. Refused, `{:error, {:speaking, names}}`, while
  one of those characters speaks: its speeches would point at no one listed.
  """
  def delete_division(%Division{} = division) do
    case stranded(division) do
      {[], silent} ->
        Repo.transaction(fn ->
          Repo.delete!(division)
          Character |> where([c], c.id in ^silent) |> Repo.delete_all()
          sync_characters(division.play_id)
          division
        end)

      {speaking, _silent} ->
        {:error, {:speaking, Enum.map(speaking, & &1.name)}}
    end
  end

  @doc """
  What deleting `division` does to the cast: the characters whose every entry is in it or
  in its own lists, the names of those who speak (`delete_division/1` refuses then), and
  how many of the rest go with it.
  """
  def deletion_effect(%Division{} = division) do
    {speaking, silent} = stranded(division)
    %{speaking: Enum.map(speaking, & &1.name), removed: length(silent)}
  end

  # The characters `division` holds every entry of: `{speaking, silent ids}`.
  defp stranded(division) do
    lists =
      Division
      |> where(play_id: ^division.play_id, type: "elenco")
      |> where([d], d.id == ^division.id or d.parent_id == ^division.id)
      |> select([d], d.id)
      |> Repo.all()

    ids =
      CastListEntry
      |> where([e], e.play_id == ^division.play_id and not is_nil(e.character_id))
      |> group_by([e], e.character_id)
      |> having([e], fragment("bool_and(?)", e.cast_list_id in ^lists))
      |> select([e], e.character_id)
      |> Repo.all()

    speaking =
      Character
      |> where([c], c.id in ^ids)
      |> where([c], c.id in subquery(ElementCharacter |> select([ec], ec.character_id)))
      |> order_by(:position)
      |> Repo.all()

    {speaking, ids -- Enum.map(speaking, & &1.id)}
  end

  @doc """
  Puts an act's scenes and cast lists in the order of `ids`. An id that is not one of the
  act's children is dropped; a child the ids leave out keeps its turn after them.
  """
  def reorder_children(%Division{} = act, ids) do
    children = Division |> where(parent_id: ^act.id) |> order_by([:position, :id]) |> Repo.all()
    renumber(children, ids, & &1.id)
    sync_characters(act.play_id)
    :ok
  end

  @doc false
  # `rows` (of one table or several) renumbered 0.. in the order `keys` name them by
  # `key_of`, those not named after, in their order; only a row whose place moves is written.
  def renumber(rows, keys, key_of) do
    by_key = Map.new(rows, &{key_of.(&1), &1})
    named = keys |> Enum.map(&by_key[&1]) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    now = DateTime.utc_now(:second)

    Repo.transaction(fn ->
      for {row, position} <- Enum.with_index(named ++ (rows -- named)),
          row.position != position do
        row.__struct__
        |> where(id: ^row.id)
        |> Repo.update_all(set: [position: position, updated_at: now])
      end
    end)
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
  Creates an element; `attrs` carry its `play_id`, `division_id` and `parent_id`. A verse
  line given no identifier takes the play's next one.
  """
  def create_element(attrs) do
    %Element{}
    |> Element.changeset(attrs)
    |> put_next_line_id()
    |> Repo.insert()
  end

  # Question 25: a verse line added in the editor or from Word takes one past the play's
  # highest identifier, in its shape (`em0010-en-4002`, `es-3679`), and no line is
  # renumbered, so no link to a line breaks. A play with none starts at `es-0001`, or
  # `em0771-es-0001` for an EMOTHE code.
  # ponytail: two curators adding a verse to one play in the same instant can still tie;
  # a unique index on play_id and line_id if that ever happens.
  defp put_next_line_id(%{valid?: true} = changeset) do
    with "verse_line" <- Ecto.Changeset.get_field(changeset, :type),
         nil <- Ecto.Changeset.get_field(changeset, :line_id),
         play_id when is_binary(play_id) <- Ecto.Changeset.get_field(changeset, :play_id) do
      Ecto.Changeset.put_change(changeset, :line_id, next_line_id(play_id))
    else
      _ -> changeset
    end
  end

  defp put_next_line_id(changeset), do: changeset

  defp next_line_id(play_id) do
    highest =
      Repo.one(
        from e in Element,
          where: e.play_id == ^play_id and fragment("? ~ '[0-9]$'", e.line_id),
          order_by: [desc: fragment("substring(? from '[0-9]+$')::bigint", e.line_id)],
          limit: 1,
          select: e.line_id
      )

    case highest do
      nil ->
        Playcode.Catalogue.Play |> Repo.get!(play_id) |> line_id(1)

      line_id ->
        [prefix, digits] = Regex.run(~r/^(.*?)(\d+)$/, line_id, capture: :all_but_first)
        next = Integer.to_string(String.to_integer(digits) + 1)
        prefix <> String.pad_leading(next, String.length(digits), "0")
    end
  end

  @doc """
  The `n`th verse line's identifier in a play that has none yet: the language and the
  number, `es-0001`, after the play's own number for an EMOTHE code, `em0771-es-0001`.
  """
  def line_id(%{code: code, language: language}, n) do
    shape = "#{language || "es"}-#{String.pad_leading(Integer.to_string(n), 4, "0")}"

    case Regex.run(~r/^EMOTHE(\d+)$/, code, capture: :all_but_first) do
      [number] -> "em#{number}-#{shape}"
      nil -> shape
    end
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

  @doc """
  As `get_character/2`, for a note: nil for another play's note, a deleted one or a
  malformed id.
  """
  def get_note(play_id, id), do: get_play_row(Note, play_id, id)

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
  other change leaves it where it is among them. A note deleted meanwhile comes back as
  `{:error, changeset}` with a stale error on `:id`.
  """
  def update_note(%Note{} = note, attrs) do
    changeset = Note.changeset(note, attrs)

    changeset =
      if Map.has_key?(changeset.changes, :offset),
        do: put_next_position(changeset),
        else: changeset

    Repo.update(changeset, stale_error_field: :id)
  end

  @doc "Deletes a note; one already deleted comes back as `{:error, changeset}`, not a raise."
  def delete_note(%Note{} = note), do: Repo.delete(note, stale_error_field: :id)

  # `position` orders the notes at one offset of one anchor, and the public numbering, the
  # pop-ups and the TEI export follow it, so a note must not tie with another.
  # ponytail: two curators adding at one word in the same instant can still tie; lock the
  # anchor's row if that ever happens.
  # TeiImport.collect_notes/5 numbers an imported play's notes by the same rule.
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
  Loads the full play content tree: divisions with nested elements, their notes and variants
  (`Note.variant?/1`) numbered in reading order, each kind in its own sequence, and each
  variant reading's sigla named (`Note.Reading`). Used for rendering the play text.

  `variants: false` leaves the variants out, as readers of a play whose `show_variants` is off
  see it.
  """
  def load_play_content(play_id, opts \\ []) do
    divisions =
      Division
      |> where(play_id: ^play_id)
      |> where([d], is_nil(d.parent_id))
      |> order_by(:position)
      |> Repo.all()
      |> Repo.preload([
        :notes,
        entries: :character,
        children:
          from(d in Division, order_by: d.position, preload: [:notes, entries: :character])
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

    divisions
    |> attach_elements(elements_by_division)
    |> without_variants(Keyword.get(opts, :variants, true))
    |> number_notes()
    |> name_witnesses(play_id)
  end

  # A play whose readers do not see its variants (Play.show_variants).
  defp without_variants(divisions, true), do: divisions

  defp without_variants(divisions, false),
    do: update_notes(divisions, &Enum.reject(&1, fn note -> Note.variant?(note) end))

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

  # Gives each note its `number`, its place in Note.reading_order/1 from 1, the variants
  # numbered apart: readers count the notes, and a variant's number is only its marker's id.
  defp number_notes(divisions) do
    {variants, notes} = divisions |> Note.reading_order() |> Enum.split_with(&Note.variant?/1)

    numbers =
      Map.new(Enum.with_index(notes, 1) ++ Enum.with_index(variants, 1), fn {note, number} ->
        {note.id, number}
      end)

    update_notes(divisions, fn notes -> Enum.map(notes, &%{&1 | number: numbers[&1.id]}) end)
  end

  # Each variant reading's sigla with what they name; the witnesses are read only for a
  # play that has variants.
  defp name_witnesses(divisions, play_id) do
    if divisions |> Note.reading_order() |> Enum.any?(&Note.variant?/1) do
      names = Witnesses.short_names(play_id)
      update_notes(divisions, fn notes -> Enum.map(notes, &Note.name_witnesses(&1, names)) end)
    else
      divisions
    end
  end

  # Each anchor's list of notes, through `fun`.
  defp update_notes(divisions, fun), do: Enum.map(divisions, &update_division_notes(&1, fun))

  defp update_division_notes(division, fun) do
    %{
      division
      | notes: fun.(division.notes),
        loaded_elements: Enum.map(division.loaded_elements, &update_element_notes(&1, fun)),
        children: Enum.map(division.children, &update_division_notes(&1, fun))
    }
  end

  defp update_element_notes(element, fun) do
    children =
      case element.children do
        %Ecto.Association.NotLoaded{} = not_loaded -> not_loaded
        children -> Enum.map(children, &update_element_notes(&1, fun))
      end

    %{element | notes: fun.(element.notes), children: children}
  end
end
