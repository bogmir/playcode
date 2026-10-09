defmodule PlaycodeWeb.Admin.PlayContentEditorLive do
  @moduledoc """
  /admin/plays/:id/content: a play's text: editorial notes, characters, divisions and
  elements, a preview, and the character review that assigns speakers in bulk. Every id an
  event carries is resolved through a getter scoped to the play, and a miss reloads the
  lists with `LiveHelpers.put_gone_flash/1` (see *Access control* in CLAUDE.md).
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Components.PlayText

  alias Playcode.Catalogue
  alias Playcode.Catalogue.PlayEditorialNote
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Character, Division, Element}
  alias PlaycodeWeb.Admin.LiveHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)
    mount_editor(socket, play)
  end

  defp mount_editor(socket, play) do
    if connected?(socket) do
      PlayContent.subscribe(play.id)
    end

    editorial_notes = Catalogue.list_play_editorial_notes(play.id)
    characters = PlayContent.list_characters(play.id)

    divisions = PlayContent.list_top_divisions(play.id)
    speeches = list_speeches(play.id)
    speaker_labels = speeches |> Enum.map(& &1.speaker_label) |> Enum.uniq() |> Enum.sort()
    first_child_contents = load_first_child_contents(Enum.map(speeches, & &1.id))

    {:ok,
     socket
     |> assign(
       page_title: "#{gettext("Edit Content")}: #{play.title}",
       play: play,
       editorial_notes: editorial_notes,
       characters: characters,
       divisions: divisions,
       selected_division_id: nil,
       elements: [],
       modal: nil,
       form: nil,
       editing: nil,
       modal_parent_id: nil,
       modal_element_type: nil,
       editing_character_ids: [],
       cr_selected_character_ids: [],
       preview_divisions: [],
       speeches: speeches,
       speaker_labels: speaker_labels,
       first_child_contents: first_child_contents,
       selected_speeches: MapSet.new(),
       selected_elements: MapSet.new(),
       last_toggled_element: nil,
       filter_label: nil,
       filter_assigned: nil,
       cr_display_limit: 50,
       content_search: "",
       content_search_results: [],
       inline_editing_id: nil,
       editor_tab: :characters,
       play_context: %{play: play, active_tab: :content}
     )}
  end

  defp cast_list_division(divisions) when is_list(divisions) do
    Enum.find(divisions, &(&1.type == "elenco"))
  end

  defp cast_list_division(_), do: nil

  # --- All handle_event/3 clauses grouped together ---

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, assign(socket, modal: nil, form: nil, editing: nil, editing_character_ids: [])}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    tab = String.to_existing_atom(tab)

    socket =
      case tab do
        :preview ->
          preview = PlayContent.load_play_content(socket.assigns.play.id)
          scroll_target = preview_scroll_target(socket.assigns)

          socket
          |> assign(editor_tab: :preview, preview_divisions: preview)
          |> then(fn s ->
            if scroll_target,
              do: push_event(s, "scroll-to-preview", %{target: scroll_target}),
              else: s
          end)

        _ ->
          assign(socket, editor_tab: tab)
      end

    {:noreply, socket}
  end

  def handle_event("validate_form", params, socket) do
    form_params = extract_form_params(params, socket.assigns.modal)

    changeset =
      case socket.assigns.modal do
        :editorial_note ->
          Catalogue.change_play_editorial_note(
            socket.assigns.editing || %PlayEditorialNote{},
            form_params
          )

        :character ->
          PlayContent.change_character(socket.assigns.editing || %Character{}, form_params)

        :division ->
          PlayContent.change_division(socket.assigns.editing || %Division{}, form_params)

        :element ->
          PlayContent.change_element(socket.assigns.editing || %Element{}, form_params)
      end

    {:noreply,
     assign(socket,
       form: to_form(Map.put(changeset, :action, :validate), as: socket.assigns.modal)
     )}
  end

  def handle_event("save_form", params, socket) do
    case socket.assigns.modal do
      :editorial_note -> save_editorial_note(socket, params)
      :character -> save_character(socket, params)
      :division -> save_division(socket, params)
      :element -> save_element(socket, params)
    end
  end

  def handle_event("new_editorial_note", _, socket) do
    play = socket.assigns.play
    next_pos = length(socket.assigns.editorial_notes)

    changeset =
      Catalogue.change_play_editorial_note(%PlayEditorialNote{
        play_id: play.id,
        position: next_pos
      })

    {:noreply,
     assign(socket,
       modal: :editorial_note,
       editing: nil,
       form: to_form(changeset, as: :editorial_note)
     )}
  end

  def handle_event("edit_editorial_note", %{"id" => id}, socket) do
    with_row(socket, Catalogue.get_play_editorial_note(socket.assigns.play.id, id), fn note ->
      assign(socket,
        modal: :editorial_note,
        editing: note,
        form: to_form(Catalogue.change_play_editorial_note(note), as: :editorial_note)
      )
    end)
  end

  def handle_event("delete_editorial_note", %{"id" => id}, socket) do
    with_row(socket, Catalogue.get_play_editorial_note(socket.assigns.play.id, id), fn note ->
      {:ok, _} = Catalogue.delete_play_editorial_note(note)

      LiveHelpers.log_activity(socket, "delete", "editorial_note", note.id, %{
        section_type: note.section_type
      })

      socket
      |> put_flash(:info, gettext("Editorial note deleted."))
      |> reload_editorial_notes()
    end)
  end

  def handle_event("new_character", _, socket) do
    play = socket.assigns.play

    # Shift all existing characters down to make room at position 0
    PlayContent.shift_character_positions(play.id)

    changeset =
      PlayContent.change_character(%Character{}, %{play_id: play.id, position: 0})

    {:noreply,
     assign(socket,
       modal: :character,
       editing: nil,
       form: to_form(changeset)
     )}
  end

  def handle_event("edit_character", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_character(socket.assigns.play.id, id), fn character ->
      assign(socket,
        modal: :character,
        editing: character,
        form: to_form(PlayContent.change_character(character))
      )
    end)
  end

  def handle_event("delete_character", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_character(socket.assigns.play.id, id), fn character ->
      {:ok, _} = PlayContent.delete_character(character)
      PlayContent.refresh_derived(socket.assigns.play.id)

      LiveHelpers.log_activity(socket, "delete", "character", character.id, %{
        name: character.name,
        xml_id: character.xml_id
      })

      socket
      |> put_flash(:info, gettext("Character deleted."))
      |> reload_characters()
    end)
  end

  def handle_event("reorder_characters", %{"ids" => ids}, socket) do
    PlayContent.reorder_characters(socket.assigns.play.id, ids)
    {:noreply, reload_characters(socket)}
  end

  # --- Character Review handlers ---

  def handle_event("cr_filter", %{"label" => label, "assigned" => assigned}, socket) do
    filter_label =
      case label do
        "" -> nil
        "__none__" -> :none
        other -> other
      end

    filter_assigned =
      case assigned do
        "" -> nil
        "yes" -> true
        "no" -> false
      end

    {:noreply,
     assign(socket,
       filter_label: filter_label,
       filter_assigned: filter_assigned,
       selected_speeches: MapSet.new(),
       cr_display_limit: 50
     )}
  end

  def handle_event("cr_toggle_speech", %{"id" => id}, socket) do
    selected = socket.assigns.selected_speeches

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    # Update tag picker to reflect common characters of new selection
    common = cr_common_character_ids(selected, socket.assigns.speeches)

    {:noreply, assign(socket, selected_speeches: selected, cr_selected_character_ids: common)}
  end

  def handle_event("cr_select_all_visible", _, socket) do
    visible = cr_filtered_speeches(socket.assigns) |> Enum.map(& &1.id)
    selected = MapSet.new(visible)
    common = cr_common_character_ids(selected, socket.assigns.speeches)
    {:noreply, assign(socket, selected_speeches: selected, cr_selected_character_ids: common)}
  end

  def handle_event("cr_deselect_all", _, socket) do
    {:noreply, assign(socket, selected_speeches: MapSet.new(), cr_selected_character_ids: [])}
  end

  def handle_event("cr_add_character", %{"character_id" => ""}, socket), do: {:noreply, socket}

  def handle_event("cr_add_character", %{"character_id" => id}, socket) do
    current = socket.assigns.cr_selected_character_ids

    cond do
      own_character_ids(socket, [id]) == [] -> {:noreply, gone(socket)}
      id in current -> {:noreply, socket}
      true -> {:noreply, assign(socket, cr_selected_character_ids: current ++ [id])}
    end
  end

  def handle_event("cr_remove_character", %{"id" => id}, socket) do
    current = socket.assigns.cr_selected_character_ids
    {:noreply, assign(socket, cr_selected_character_ids: List.delete(current, id))}
  end

  def handle_event("cr_assign_characters", _params, socket) do
    character_ids = own_character_ids(socket, socket.assigns.cr_selected_character_ids)

    socket
    |> own_elements(socket.assigns.selected_speeches)
    |> Enum.each(&PlayContent.set_element_characters(&1.id, character_ids))

    PlayContent.refresh_derived(socket.assigns.play.id)

    LiveHelpers.log_activity(socket, "update", "element", nil, %{
      bulk: true,
      count: MapSet.size(socket.assigns.selected_speeches),
      action: "assign_characters"
    })

    {:noreply,
     socket
     |> reload_speeches()
     |> assign(selected_speeches: MapSet.new(), cr_selected_character_ids: [])
     |> put_flash(:info, gettext("Characters assigned."))}
  end

  def handle_event("cr_set_label", params, socket) do
    label =
      case params["speaker_label"] do
        "" -> nil
        val -> val
      end

    socket
    |> own_elements(socket.assigns.selected_speeches)
    |> Enum.each(&PlayContent.update_element(&1, %{speaker_label: label}))

    PlayContent.refresh_derived(socket.assigns.play.id)

    {:noreply,
     socket
     |> reload_speeches()
     |> assign(filter_label: label || :none)
     |> put_flash(:info, gettext("Label updated."))}
  end

  def handle_event("cr_clear_label", _params, socket) do
    socket
    |> own_elements(socket.assigns.selected_speeches)
    |> Enum.each(&PlayContent.update_element(&1, %{speaker_label: nil}))

    PlayContent.refresh_derived(socket.assigns.play.id)

    {:noreply,
     socket
     |> reload_speeches()
     |> assign(filter_label: :none)
     |> put_flash(:info, gettext("Label cleared."))}
  end

  def handle_event("cr_go_to_speech", %{"id" => id}, socket) do
    speech = Enum.find(socket.assigns.speeches, &(&1.id == id))

    if speech && speech.division_id do
      {:noreply,
       socket
       |> assign(
         selected_division_id: speech.division_id,
         editor_tab: :content,
         selected_elements: MapSet.new([speech.id]),
         last_toggled_element: nil
       )
       |> reload_elements()
       |> push_event("scroll-to-element", %{id: "element-#{id}"})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("cr_show_more", _, socket) do
    {:noreply, update(socket, :cr_display_limit, &(&1 + 50))}
  end

  # --- Content search handlers ---

  def handle_event("content_search", %{"query" => query}, socket) do
    query = String.trim(query)
    results = PlayContent.search_elements(socket.assigns.play.id, query)
    {:noreply, assign(socket, content_search: query, content_search_results: results)}
  end

  def handle_event("content_search_clear", _, socket) do
    {:noreply, assign(socket, content_search: "", content_search_results: [])}
  end

  def handle_event("content_search_go", params, socket) do
    div_id = params["division-id"]
    parent_id = params["parent-id"]
    id = params["id"]

    # Navigate to root element: if child (verse_line), select the parent speech
    target_id = if parent_id && parent_id != "", do: parent_id, else: id

    with_row(socket, PlayContent.get_division(socket.assigns.play.id, div_id), fn _division ->
      socket
      |> assign(
        selected_division_id: div_id,
        editor_tab: :content,
        content_search: "",
        content_search_results: [],
        selected_elements: MapSet.new([target_id]),
        last_toggled_element: nil
      )
      |> reload_elements()
      |> push_event("scroll-to-element", %{id: "element-#{target_id}"})
    end)
  end

  def handle_event("new_division", params, socket) do
    case params["parent-id"] do
      blank when blank in [nil, ""] ->
        {:noreply, open_new_division(socket, nil)}

      parent_id ->
        with_row(socket, PlayContent.get_division(socket.assigns.play.id, parent_id), fn _ ->
          open_new_division(socket, parent_id)
        end)
    end
  end

  def handle_event("edit_division", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_division(socket.assigns.play.id, id), fn division ->
      assign(socket,
        modal: :division,
        editing: division,
        form: to_form(PlayContent.change_division(division))
      )
    end)
  end

  def handle_event("delete_division", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_division(socket.assigns.play.id, id), fn division ->
      {:ok, _} = PlayContent.delete_division(division)
      PlayContent.refresh_derived(socket.assigns.play.id)

      LiveHelpers.log_activity(socket, "delete", "division", division.id, %{
        type: division.type,
        number: division.number
      })

      selected =
        if socket.assigns.selected_division_id == id,
          do: nil,
          else: socket.assigns.selected_division_id

      socket
      |> put_flash(:info, gettext("Division deleted."))
      |> assign(selected_division_id: selected)
      |> reload_divisions()
      |> reload_elements()
    end)
  end

  def handle_event("select_division", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_division(socket.assigns.play.id, id), fn _division ->
      show_division(socket, id)
    end)
  end

  def handle_event("select_division_auto", %{"id" => id}, socket) do
    case find_division(socket.assigns.divisions, id) do
      nil ->
        {:noreply, gone(socket)}

      %{type: "elenco"} ->
        {:noreply,
         assign(socket,
           editor_tab: :characters,
           selected_division_id: nil,
           selected_elements: MapSet.new(),
           last_toggled_element: nil
         )}

      %{children: [first_child | _]} ->
        {:noreply, show_division(socket, first_child.id)}

      _division ->
        {:noreply, show_division(socket, id)}
    end
  end

  def handle_event("new_element", params, socket) do
    with_parent(socket, params["parent-id"], fn parent_id ->
      play = socket.assigns.play
      div_id = socket.assigns.selected_division_id
      element_type = params["type"]
      pos = PlayContent.next_element_position(div_id, parent_id)

      attrs = %{
        play_id: play.id,
        division_id: div_id,
        parent_id: parent_id,
        type: element_type,
        position: pos
      }

      attrs = maybe_add_line_number(attrs, element_type, play.id)

      assign(socket,
        modal: :element,
        editing: nil,
        modal_element_type: element_type,
        editing_character_ids: [],
        form: to_form(PlayContent.change_element(%Element{}, attrs))
      )
    end)
  end

  def handle_event("new_element_before", params, socket) do
    case Integer.parse(params["position"] || "") do
      {before_pos, ""} ->
        with_parent(socket, params["parent-id"], fn parent_id ->
          new_element_before(socket, parent_id, params["type"], before_pos)
        end)

      _malformed ->
        {:noreply, gone(socket)}
    end
  end

  def handle_event("edit_element", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_element(socket.assigns.play.id, id), fn element ->
      assign(socket,
        modal: :element,
        editing: element,
        modal_element_type: element.type,
        editing_character_ids: Enum.map(element.element_characters, & &1.character_id),
        form: to_form(PlayContent.change_element(element))
      )
    end)
  end

  def handle_event("el_add_character", params, socket) do
    id = params["character_id"] || params["el_add_char"]
    current = socket.assigns.editing_character_ids

    cond do
      id in [nil, ""] -> {:noreply, socket}
      own_character_ids(socket, [id]) == [] -> {:noreply, gone(socket)}
      id in current -> {:noreply, socket}
      true -> {:noreply, assign(socket, editing_character_ids: current ++ [id])}
    end
  end

  def handle_event("el_remove_character", %{"id" => id}, socket) do
    updated = Enum.reject(socket.assigns.editing_character_ids, &(&1 == id))
    {:noreply, assign(socket, editing_character_ids: updated)}
  end

  def handle_event("inline_edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, inline_editing_id: id)}
  end

  def handle_event("inline_save", %{"element_id" => id, "value" => value}, socket) do
    if socket.assigns.inline_editing_id == nil do
      {:noreply, socket}
    else
      with_row(socket, PlayContent.get_element(socket.assigns.play.id, id), fn element ->
        case PlayContent.update_element(element, %{"content" => value}) do
          {:ok, _el} ->
            PlayContent.refresh_derived(socket.assigns.play.id)

            LiveHelpers.log_activity(socket, "update", "element", element.id, %{
              type: element.type,
              inline: true
            })

            socket
            |> assign(inline_editing_id: nil)
            |> reload_elements()

          {:error, _changeset} ->
            put_flash(socket, :error, gettext("Could not save element."))
        end
      end)
    end
  end

  def handle_event("inline_cancel", _params, socket) do
    {:noreply, assign(socket, inline_editing_id: nil)}
  end

  def handle_event("delete_element", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_element(socket.assigns.play.id, id), fn element ->
      delete_element(socket, element)
    end)
  end

  def handle_event("el_toggle_element", %{"id" => id, "shift" => true}, socket) do
    last = socket.assigns.last_toggled_element

    if last do
      ids = Enum.map(socket.assigns.elements, & &1.id)
      i1 = Enum.find_index(ids, &(&1 == last))
      i2 = Enum.find_index(ids, &(&1 == id))

      if i1 && i2 do
        range = Enum.slice(ids, min(i1, i2)..max(i1, i2)) |> MapSet.new()
        selected = MapSet.union(socket.assigns.selected_elements, range)
        {:noreply, assign(socket, selected_elements: selected, last_toggled_element: id)}
      else
        el_toggle_single(socket, id)
      end
    else
      el_toggle_single(socket, id)
    end
  end

  def handle_event("el_toggle_element", %{"id" => id}, socket) do
    el_toggle_single(socket, id)
  end

  def handle_event("el_select_all", _params, socket) do
    ids = socket.assigns.elements |> Enum.map(& &1.id) |> MapSet.new()
    {:noreply, assign(socket, selected_elements: ids)}
  end

  def handle_event("el_deselect_all", _params, socket) do
    {:noreply, assign(socket, selected_elements: MapSet.new())}
  end

  def handle_event("el_delete_selected", _params, socket) do
    play_id = socket.assigns.play.id
    elements = own_elements(socket, socket.assigns.selected_elements)
    count = length(elements)

    Enum.each(elements, fn element -> {:ok, _} = PlayContent.delete_element(element) end)

    PlayContent.refresh_derived(play_id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("%{count} elements deleted.", count: count))
     |> assign(selected_elements: MapSet.new())
     |> reload_elements()}
  end

  # --- Division helpers ---

  defp open_new_division(socket, parent_id) do
    play = socket.assigns.play
    pos = PlayContent.next_division_position(play.id, parent_id)
    default_type = if parent_id, do: "escena", else: "acto"

    changeset =
      PlayContent.change_division(%Division{}, %{
        play_id: play.id,
        parent_id: parent_id,
        position: pos,
        type: default_type
      })

    assign(socket,
      modal: :division,
      editing: nil,
      modal_parent_id: parent_id,
      form: to_form(changeset)
    )
  end

  defp new_element_before(socket, parent_id, element_type, before_pos) do
    play = socket.assigns.play
    div_id = socket.assigns.selected_division_id

    PlayContent.shift_element_positions(div_id, parent_id, before_pos)

    attrs = %{
      play_id: play.id,
      division_id: div_id,
      parent_id: parent_id,
      type: element_type,
      position: before_pos
    }

    attrs = maybe_add_line_number(attrs, element_type, play.id)

    socket
    |> reload_elements()
    |> assign(
      modal: :element,
      editing: nil,
      modal_element_type: element_type,
      editing_character_ids: [],
      form: to_form(PlayContent.change_element(%Element{}, attrs))
    )
  end

  defp delete_element(socket, element) do
    play_id = socket.assigns.play.id

    should_shift_down =
      element.type == "verse_line" &&
        element.line_number != nil &&
        !PlayContent.split_verse?(play_id, element.id, element.line_number)

    {:ok, _} = PlayContent.delete_element(element)

    if should_shift_down do
      PlayContent.shift_line_numbers_down(play_id, element.line_number)
    end

    PlayContent.refresh_derived(play_id)
    LiveHelpers.log_activity(socket, "delete", "element", element.id, %{type: element.type})

    socket
    |> put_flash(:info, gettext("Element deleted."))
    |> reload_elements()
  end

  defp show_division(socket, id) do
    socket
    |> assign(
      selected_division_id: id,
      editor_tab: :content,
      selected_elements: MapSet.new(),
      last_toggled_element: nil
    )
    |> reload_elements()
  end

  # --- Ids from the browser ---
  #
  # Every id an event carries came from the browser: another play's row, one a double
  # click or another tab already deleted, or no id at all. Each is looked up through a
  # getter scoped to this play, and nil changes nothing.

  # Runs `fun` on `row` (from a scoped getter) and replies with the socket it returns;
  # nil reloads the lists and says the item is gone.
  defp with_row(socket, nil, _fun), do: {:noreply, gone(socket)}
  defp with_row(_socket, row, fun), do: {:noreply, fun.(row)}

  # As `with_row/3` for an optional parent element: blank means none.
  defp with_parent(_socket, blank, fun) when blank in [nil, ""], do: {:noreply, fun.(nil)}

  defp with_parent(socket, parent_id, fun) do
    with_row(socket, PlayContent.get_element(socket.assigns.play.id, parent_id), fn _ ->
      fun.(parent_id)
    end)
  end

  defp gone(socket) do
    socket
    |> assign(inline_editing_id: nil)
    |> reload_editorial_notes()
    |> reload_characters()
    |> reload_divisions()
    |> reload_elements()
    |> reload_speeches()
    |> LiveHelpers.put_gone_flash()
  end

  # The play's own elements among `ids`; the rest are dropped.
  defp own_elements(socket, ids) do
    Enum.flat_map(ids, fn id ->
      List.wrap(PlayContent.get_element(socket.assigns.play.id, id))
    end)
  end

  # The play's own characters among `ids`, in the order given.
  defp own_character_ids(socket, ids) do
    own = socket.assigns.play.id |> PlayContent.list_characters() |> MapSet.new(& &1.id)
    Enum.filter(ids, &MapSet.member?(own, &1))
  end

  # --- Element selection helpers ---

  defp el_toggle_single(socket, id) do
    selected = socket.assigns.selected_elements

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, selected_elements: selected, last_toggled_element: id)}
  end

  # --- Save helpers ---

  defp save_editorial_note(socket, params) do
    note_params = params["editorial_note"] || %{}
    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          note_params = Map.put(note_params, "play_id", play.id)
          Catalogue.create_play_editorial_note(note_params)

        note ->
          Catalogue.update_play_editorial_note(note, note_params)
      end

    case result do
      {:ok, saved} ->
        action = if socket.assigns.editing, do: "update", else: "create"

        LiveHelpers.log_activity(socket, action, "editorial_note", saved.id, %{
          section_type: saved.section_type
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Editorial note saved."))
         |> assign(modal: nil, form: nil, editing: nil)
         |> reload_editorial_notes()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :editorial_note))}
    end
  end

  defp save_character(socket, params) do
    char_params = params["character"] || %{}
    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          char_params = Map.put(char_params, "play_id", play.id)
          PlayContent.create_character(char_params)

        character ->
          PlayContent.update_character(character, char_params)
      end

    case result do
      {:ok, saved} ->
        PlayContent.refresh_derived(play.id)
        action = if socket.assigns.editing, do: "update", else: "create"

        LiveHelpers.log_activity(socket, action, "character", saved.id, %{
          name: saved.name,
          xml_id: saved.xml_id
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Character saved."))
         |> assign(modal: nil, form: nil, editing: nil)
         |> reload_characters()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_division(socket, params) do
    div_params = params["division"] || %{}
    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          div_params =
            div_params
            |> Map.put("play_id", play.id)
            |> Map.put("parent_id", socket.assigns.modal_parent_id)

          PlayContent.create_division(div_params)

        division ->
          PlayContent.update_division(division, div_params)
      end

    case result do
      {:ok, saved} ->
        PlayContent.refresh_derived(play.id)
        action = if socket.assigns.editing, do: "update", else: "create"

        LiveHelpers.log_activity(socket, action, "division", saved.id, %{
          type: saved.type,
          number: saved.number
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Division saved."))
         |> assign(modal: nil, form: nil, editing: nil, modal_parent_id: nil)
         |> reload_divisions()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_element(socket, params) do
    el_params = params["element"] || %{}

    character_ids =
      own_character_ids(socket, List.wrap(params["character_ids"] || []))

    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          el_params =
            el_params
            |> Map.put("play_id", play.id)
            |> Map.put("division_id", socket.assigns.selected_division_id)

          changeset = PlayContent.change_element(%PlayContent.Element{}, el_params)

          if changeset.valid? do
            if el_params["type"] == "verse_line" do
              case el_params["line_number"] do
                nil ->
                  :ok

                "" ->
                  :ok

                ln ->
                  line_num = if is_binary(ln), do: String.to_integer(ln), else: ln
                  PlayContent.shift_line_numbers(play.id, line_num)
              end
            end

            PlayContent.create_element(el_params)
          else
            # A refusal comes back before any later line is renumbered for a line that
            # will not be saved.
            {:error, %{changeset | action: :insert}}
          end

        element ->
          PlayContent.update_element(element, el_params)
      end

    case result do
      {:ok, el} ->
        # Set character associations for speech elements
        if el.type == "speech" do
          PlayContent.set_element_characters(el.id, character_ids)
        end

        PlayContent.refresh_derived(play.id)
        action = if socket.assigns.editing, do: "update", else: "create"
        LiveHelpers.log_activity(socket, action, "element", el.id, %{type: el.type})

        {:noreply,
         socket
         |> put_flash(:info, gettext("Element saved."))
         |> assign(modal: nil, form: nil, editing: nil, modal_element_type: nil)
         |> reload_elements()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  # --- PubSub handler ---

  @impl true
  # Archiving notifies too, so the play may be archived by now.
  def handle_info({:play_content_changed, _play_id}, socket) do
    play = Catalogue.get_play!(socket.assigns.play.id, include_deleted: true)

    {:noreply,
     socket
     |> assign(:play, play)
     |> reload_editorial_notes()
     |> reload_characters()
     |> reload_divisions()
     |> reload_elements()
     |> reload_speeches()}
  end

  # The notes component's flash would stay in the component, so it asks for ours.
  def handle_info(:note_gone, socket), do: {:noreply, LiveHelpers.put_gone_flash(socket)}

  # --- Reload helpers ---

  defp reload_editorial_notes(socket) do
    assign(socket, editorial_notes: Catalogue.list_play_editorial_notes(socket.assigns.play.id))
  end

  defp reload_characters(socket) do
    assign(socket, characters: PlayContent.list_characters(socket.assigns.play.id))
  end

  defp reload_divisions(socket) do
    assign(socket, divisions: PlayContent.list_top_divisions(socket.assigns.play.id))
  end

  defp reload_elements(socket) do
    socket =
      case socket.assigns.selected_division_id do
        nil -> assign(socket, elements: [])
        div_id -> assign(socket, elements: PlayContent.list_elements_for_division(div_id))
      end

    reload_preview(socket)
  end

  defp reload_speeches(socket) do
    speeches = list_speeches(socket.assigns.play.id)
    speaker_labels = speeches |> Enum.map(& &1.speaker_label) |> Enum.uniq() |> Enum.sort()
    first_child_contents = load_first_child_contents(Enum.map(speeches, & &1.id))

    assign(socket,
      speeches: speeches,
      speaker_labels: speaker_labels,
      first_child_contents: first_child_contents
    )
  end

  defp list_speeches(play_id) do
    import Ecto.Query
    alias Playcode.PlayContent.ElementCharacter

    ec_preload = from(ec in ElementCharacter, order_by: ec.position, preload: :character)

    Playcode.Repo.all(
      from e in Element,
        where: e.play_id == ^play_id and e.type == "speech",
        left_join: d in assoc(e, :division),
        preload: [element_characters: ^ec_preload, division: d],
        order_by: [e.position]
    )
  end

  defp cr_filtered_speeches(assigns) do
    speeches = assigns.speeches

    speeches =
      case assigns.filter_label do
        nil -> speeches
        :none -> Enum.filter(speeches, &is_nil(&1.speaker_label))
        label -> Enum.filter(speeches, &(&1.speaker_label == label))
      end

    case assigns.filter_assigned do
      nil -> speeches
      true -> Enum.filter(speeches, &(&1.element_characters != []))
      false -> Enum.filter(speeches, &(&1.element_characters == []))
    end
  end

  defp cr_common_character_ids(selected_speeches, speeches) do
    selected =
      speeches
      |> Enum.filter(&MapSet.member?(selected_speeches, &1.id))

    case selected do
      [] ->
        []

      list ->
        id_sets =
          Enum.map(list, fn s ->
            s.element_characters |> Enum.map(& &1.character_id) |> MapSet.new()
          end)

        common = Enum.reduce(id_sets, List.first(id_sets), &MapSet.intersection/2)

        if Enum.all?(id_sets, &(&1 == common)),
          do: MapSet.to_list(common),
          else: []
    end
  end

  defp load_first_child_contents(speech_ids) when speech_ids == [], do: %{}

  defp load_first_child_contents(speech_ids) do
    import Ecto.Query

    Playcode.Repo.all(
      from e in Element,
        where: e.parent_id in ^speech_ids,
        distinct: e.parent_id,
        order_by: [e.parent_id, e.position],
        select: {e.parent_id, e.content}
    )
    |> Map.new()
  end

  defp reload_preview(socket) do
    if socket.assigns.editor_tab == :preview do
      assign(socket, preview_divisions: PlayContent.load_play_content(socket.assigns.play.id))
    else
      socket
    end
  end

  defp extract_form_params(params, :editorial_note), do: params["editorial_note"] || %{}
  defp extract_form_params(params, :character), do: params["character"] || %{}
  defp extract_form_params(params, :division), do: params["division"] || %{}
  defp extract_form_params(params, :element), do: params["element"] || %{}
  defp extract_form_params(_params, _), do: %{}

  defp editing_label(nil), do: gettext("Add")
  defp editing_label(_), do: gettext("Edit")

  defp find_division(divisions, id) do
    Enum.find_value(divisions, fn div ->
      if div.id == id do
        div
      else
        Enum.find(div.children || [], &(&1.id == id))
      end
    end)
  end

  defp maybe_add_line_number(attrs, "verse_line", play_id) do
    parent_id = attrs[:parent_id] || attrs["parent_id"]
    position = attrs[:position] || attrs["position"]

    line_number = PlayContent.auto_line_number(play_id, parent_id, position)
    Map.put(attrs, :line_number, line_number)
  end

  defp maybe_add_line_number(attrs, _type, _play_id), do: attrs

  defp section_type_options do
    [
      {gettext("Editor's Introduction"), "introduccion_editor"},
      {gettext("Dedication"), "dedicatoria"},
      {gettext("Argument"), "argumento"},
      {gettext("Prologue"), "prologo"},
      {gettext("Note"), "nota"}
    ]
  end

  defp section_type_label("introduccion_editor"), do: gettext("Editor's Introduction")
  defp section_type_label("dedicatoria"), do: gettext("Dedication")
  defp section_type_label("argumento"), do: gettext("Argument")
  defp section_type_label("prologo"), do: gettext("Prologue")
  defp section_type_label("nota"), do: gettext("Note")
  defp section_type_label(t), do: t

  defp division_types do
    [
      {gettext("Act (acto)"), "acto"},
      {gettext("Act (act)"), "act"},
      {gettext("Scene (escena)"), "escena"},
      {gettext("Scene (scene)"), "scene"},
      {gettext("Prologue"), "prologo"},
      {gettext("Epilogue"), "epilogue"},
      {gettext("Argument"), "argumento"},
      {gettext("Jornada"), "jornada"},
      {gettext("Dedication"), "dedicatoria"},
      {gettext("Cast list"), "elenco"},
      {gettext("Front matter"), "front"}
    ]
  end

  defp verse_types do
    [
      {"", ""},
      {"Redondilla", "redondilla"},
      {"Romance", "romance"},
      {"Romance tirada", "romance_tirada"},
      {"Octava real", "octava_real"},
      {"Soneto", "soneto"},
      {"Decima", "decima"},
      {"Terceto", "terceto"},
      {"Silva", "silva"},
      {"Quintilla", "quintilla"},
      {"Lira", "lira"},
      {"Cancion", "cancion"},
      {"Free", "free"},
      {"Otro", "otro"}
    ]
  end

  defp part_options do
    [
      {"(none)", ""},
      {"I - Inicio", "I"},
      {"M - Medio", "M"},
      {"F - Final", "F"}
    ]
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 py-8">
      <%!-- Header --%>
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("Edit Content")}: {@play.title}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">{@play.author_name} — {@play.code}</p>
      </div>

      <%!-- Tab Bar --%>
      <div class="border-b border-base-300 mb-6">
        <nav class="-mb-px flex gap-1" aria-label="Editor tabs">
          <.tab_button
            tab={:editorial_notes}
            label={gettext("Editorial Notes")}
            active={@editor_tab}
            icon="hero-document-text-mini"
            count={length(@editorial_notes)}
          />
          <.tab_button
            tab={:structure}
            active={@editor_tab}
            icon="hero-bars-3-bottom-left-mini"
            count={Enum.count(@divisions, &(&1.type != "elenco"))}
          />
          <.tab_button
            tab={:characters}
            label={gettext("Cast list")}
            active={@editor_tab}
            icon="hero-user-group-mini"
            count={length(@characters)}
          />
          <.tab_button
            tab={:character_review}
            label={gettext("Character Review")}
            active={@editor_tab}
            icon="hero-magnifying-glass-mini"
          />
          <.tab_button
            tab={:content}
            active={@editor_tab}
            icon="hero-document-text-mini"
            badge={
              if @selected_division_id,
                do: selected_division_short_label(@divisions, @selected_division_id)
            }
          />
          <.tab_button tab={:preview} active={@editor_tab} icon="hero-eye-mini" />
        </nav>
      </div>

      <%!-- Tab: Editorial Notes --%>
      <div :if={@editor_tab == :editorial_notes} class="animate-in fade-in">
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            {gettext("Editorial Notes")}
            <span class="text-base-content/50 font-normal">({length(@editorial_notes)})</span>
          </h2>
          <button phx-click="new_editorial_note" class="btn btn-sm btn-primary gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add Note")}
          </button>
        </div>
        <p class="mb-4 text-sm text-base-content/60">
          {gettext(
            "Front-matter sections: dedications, editor's introductions, prologues, arguments."
          )}
        </p>
        <div
          :if={@editorial_notes == []}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/60"
        >
          <.icon name="hero-document-text" class="mx-auto mb-2 size-8 text-base-content/30" />
          <p>{gettext("No editorial notes yet.")}</p>
        </div>
        <div class="space-y-3">
          <div
            :for={note <- @editorial_notes}
            id={"note-#{note.id}"}
            class="rounded-box border border-base-300 bg-base-100 shadow-sm"
          >
            <div class="flex items-start justify-between gap-4 p-4">
              <div class="min-w-0 flex-1">
                <div class="flex items-center gap-2 mb-1">
                  <span class="badge badge-outline badge-sm">
                    {section_type_label(note.section_type)}
                  </span>
                  <span :if={note.heading} class="font-medium text-sm">{note.heading}</span>
                </div>
                <p class="text-sm text-base-content/70 line-clamp-3 whitespace-pre-line">
                  {note.content}
                </p>
              </div>
              <span class="text-xs text-base-content/30 shrink-0">#{note.position}</span>
            </div>
            <div class="flex justify-end gap-1 border-t border-base-300 px-3 py-2">
              <button
                phx-click="edit_editorial_note"
                phx-value-id={note.id}
                class="btn btn-ghost btn-xs gap-1"
              >
                <.icon name="hero-pencil-square-micro" class="size-3.5" /> {gettext("Edit")}
              </button>
              <button
                phx-click="delete_editorial_note"
                phx-value-id={note.id}
                data-confirm={gettext("Delete this editorial note?")}
                class="btn btn-ghost btn-xs text-error gap-1"
              >
                <.icon name="hero-trash-micro" class="size-3.5" /> {gettext("Delete")}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Tab: Characters --%>
      <div :if={@editor_tab == :characters} class="animate-in fade-in">
        <div :if={cast_list_division(@divisions)} class="mb-4">
          <div class="rounded-box border border-base-300 bg-base-100 px-4 py-3 shadow-sm">
            <div class="flex items-center justify-between gap-3">
              <div class="min-w-0">
                <div class="text-xs font-medium text-base-content/50">
                  {gettext("Header")}
                </div>
                <div class="truncate text-sm font-semibold text-base-content">
                  {cast_list_division(@divisions).title ||
                    String.capitalize(cast_list_division(@divisions).type)}
                </div>
              </div>
              <button
                phx-click="edit_division"
                phx-value-id={cast_list_division(@divisions).id}
                class="btn btn-ghost btn-xs tooltip"
                data-tip={gettext("Edit header")}
              >
                <.icon name="hero-pencil-square-mini" class="size-4" />
              </button>
            </div>
          </div>
        </div>
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            {gettext("Cast list")}
            <span class="text-base-content/50 font-normal">({length(@characters)})</span>
          </h2>
          <button phx-click="new_character" class="btn btn-sm btn-primary gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add Character")}
          </button>
        </div>
        <div
          :if={@characters == []}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/60"
        >
          <.icon name="hero-user-group" class="mx-auto mb-2 size-8 text-base-content/30" />
          <p>{gettext("No characters yet. Add one to get started.")}</p>
        </div>
        <div
          :if={@characters != []}
          id="character-list"
          phx-hook=".DragSortList"
          class="rounded-box border border-base-300 bg-base-100 shadow-sm"
          data-event="reorder_characters"
        >
          <div
            :for={{char, idx} <- Enum.with_index(@characters)}
            data-id={char.id}
            class="drag-item group flex items-center gap-2 px-3 py-2.5 transition-all hover:bg-base-200/40 border-b border-base-300/60 last:border-b-0"
          >
            <%!-- Drag handle --%>
            <div class="drag-handle shrink-0 cursor-grab active:cursor-grabbing p-1 -ml-1 rounded text-base-content/25 hover:text-base-content/50 hover:bg-base-200/60 transition-colors">
              <.icon name="hero-bars-3-mini" class="size-4" />
            </div>

            <%!-- Position number --%>
            <span class="drag-position flex size-6 shrink-0 items-center justify-center rounded-full bg-base-200 text-[10px] font-semibold text-base-content/50 tabular-nums">
              {idx + 1}
            </span>

            <%!-- Avatar initial --%>
            <div class="flex size-8 shrink-0 items-center justify-center rounded-full bg-primary/10 text-xs font-bold text-primary">
              {String.first(char.name)}
            </div>

            <%!-- Character info --%>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="font-medium text-sm">{char.name}</span>
                <span class="text-[10px] text-base-content/35 font-mono">{char.xml_id}</span>
                <span
                  :if={char.is_hidden}
                  class="badge badge-ghost badge-xs text-[10px]"
                >
                  {gettext("hidden")}
                </span>
              </div>
              <p :if={char.description} class="text-xs text-base-content/50 truncate">
                {char.description}
              </p>
            </div>

            <%!-- Actions --%>
            <div class="flex gap-0.5 shrink-0 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                phx-click="edit_character"
                phx-value-id={char.id}
                class="btn btn-ghost btn-xs tooltip"
                data-tip={gettext("Edit")}
              >
                <.icon name="hero-pencil-mini" class="size-3.5" />
              </button>
              <button
                phx-click="delete_character"
                phx-value-id={char.id}
                data-confirm={
                  gettext("Delete this character? Speeches referencing it will lose their speaker.")
                }
                class="btn btn-ghost btn-xs text-error tooltip"
                data-tip={gettext("Delete")}
              >
                <.icon name="hero-trash-mini" class="size-3.5" />
              </button>
            </div>
          </div>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".DragSortList">
        export default {
          mounted() {
            this.dragEl = null
            this.placeholder = null
            this.eventName = this.el.dataset.event
            this.bindItems()
          },

          updated() {
            this.bindItems()
          },

          bindItems() {
            this.el.querySelectorAll(".drag-item").forEach(item => {
              if (!item._dragBound) {
                this.setupItem(item)
                item._dragBound = true
              }
            })
          },

          setupItem(item) {
            const handle = item.querySelector(".drag-handle")
            if (!handle) return

            handle.addEventListener("mousedown", (e) => {
              e.preventDefault()
              this.startDrag(item, e.clientY)
            })

            handle.addEventListener("touchstart", (e) => {
              e.preventDefault()
              this.startDrag(item, e.touches[0].clientY)
            }, { passive: false })
          },

          startDrag(item, startY) {
            this.dragEl = item
            const rect = item.getBoundingClientRect()
            const containerRect = this.el.getBoundingClientRect()

            // Create placeholder
            this.placeholder = document.createElement("div")
            this.placeholder.className = "border-2 border-dashed border-primary/30 rounded bg-primary/5 transition-all"
            this.placeholder.style.height = rect.height + "px"
            item.parentNode.insertBefore(this.placeholder, item)

            // Style dragged element
            item.style.position = "fixed"
            item.style.zIndex = "50"
            item.style.width = rect.width + "px"
            item.style.left = rect.left + "px"
            item.style.top = rect.top + "px"
            item.style.boxShadow = "0 8px 25px -5px rgba(0,0,0,0.15), 0 4px 10px -6px rgba(0,0,0,0.1)"
            item.style.opacity = "0.95"
            item.style.borderRadius = "0.5rem"
            item.style.background = "var(--color-base-100)"
            item.style.transition = "box-shadow 0.2s, opacity 0.2s"
            item.classList.add("ring-2", "ring-primary/30")

            this.offsetY = startY - rect.top

            this.moveHandler = (e) => {
              const clientY = e.touches ? e.touches[0].clientY : e.clientY
              this.onDragMove(clientY)
            }
            this.upHandler = () => this.endDrag()

            document.addEventListener("mousemove", this.moveHandler)
            document.addEventListener("mouseup", this.upHandler)
            document.addEventListener("touchmove", this.moveHandler, { passive: false })
            document.addEventListener("touchend", this.upHandler)
          },

          onDragMove(clientY) {
            if (!this.dragEl) return
            this.dragEl.style.top = (clientY - this.offsetY) + "px"

            // find the item we're hovering over
            const items = [...this.el.querySelectorAll(".drag-item")].filter(el => el !== this.dragEl)
            let after = null
            for (const item of items) {
              const box = item.getBoundingClientRect()
              const midY = box.top + box.height / 2
              if (clientY < midY) { after = item; break }
            }

            if (after) {
              this.el.insertBefore(this.placeholder, after)
            } else {
              this.el.appendChild(this.placeholder)
            }
          },

          endDrag() {
            if (!this.dragEl) return

            document.removeEventListener("mousemove", this.moveHandler)
            document.removeEventListener("mouseup", this.upHandler)
            document.removeEventListener("touchmove", this.moveHandler)
            document.removeEventListener("touchend", this.upHandler)

            // Insert the real element where the placeholder is
            this.el.insertBefore(this.dragEl, this.placeholder)
            this.placeholder.remove()

            // Reset styles
            this.dragEl.style.position = ""
            this.dragEl.style.zIndex = ""
            this.dragEl.style.width = ""
            this.dragEl.style.left = ""
            this.dragEl.style.top = ""
            this.dragEl.style.boxShadow = ""
            this.dragEl.style.opacity = ""
            this.dragEl.style.borderRadius = ""
            this.dragEl.style.background = ""
            this.dragEl.style.transition = ""
            this.dragEl.classList.remove("ring-2", "ring-primary/30")

            // Update position numbers
            this.el.querySelectorAll(".drag-item").forEach((item, i) => {
              const posEl = item.querySelector(".drag-position")
              if (posEl) posEl.textContent = i + 1
            })

            // Collect new order and push to server
            const ids = [...this.el.querySelectorAll(".drag-item")].map(el => el.dataset.id)
            this.pushEvent(this.eventName, { ids })

            // Brief highlight animation
            this.dragEl.style.transition = "background-color 0.3s"
            this.dragEl.style.backgroundColor = "oklch(from var(--color-primary) l c h / 0.08)"
            setTimeout(() => {
              if (this.dragEl) this.dragEl.style.backgroundColor = ""
            }, 400)

            this.dragEl = null
          }
        }
      </script>

      <%!-- Tab: Structure --%>
      <div :if={@editor_tab == :structure} class="animate-in fade-in">
        <div class="mb-4 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-base-content">
            {gettext("Play Structure")}
            <span class="text-base-content/50 font-normal">
              ({Enum.count(@divisions, &(&1.type != "elenco"))} {gettext("acts")})
            </span>
          </h2>
          <button phx-click="new_division" class="btn btn-sm btn-primary gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add Act")}
          </button>
        </div>
        <div
          :if={@divisions == []}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/60"
        >
          <.icon name="hero-bars-3-bottom-left" class="mx-auto mb-2 size-8 text-base-content/30" />
          <p>{gettext("No acts or scenes yet. Add an act to get started.")}</p>
        </div>
        <div :if={@divisions != []} class="space-y-3">
          <div
            :for={div <- @divisions}
            class="rounded-box border border-base-300 bg-base-100 shadow-sm overflow-hidden"
          >
            <div
              id={"division-#{div.id}"}
              class="flex items-center justify-between px-4 py-3 bg-base-200/30"
            >
              <div class="flex items-center gap-2">
                <.icon name="hero-folder-mini" class="size-4 text-base-content/40" />
                <span class="font-semibold">{division_label(div)}</span>
                <span class="badge badge-ghost badge-xs">
                  {div.type}{if div.number, do: " #{div.number}"}
                </span>
              </div>
              <div class="flex items-center gap-1">
                <button
                  phx-click="select_division_auto"
                  phx-value-id={div.id}
                  class="btn btn-xs btn-ghost btn-outline gap-1"
                >
                  <.icon name="hero-pencil-square-mini" class="size-3" /> {gettext("Edit Content")}
                </button>
                <button
                  phx-click="edit_division"
                  phx-value-id={div.id}
                  class="btn btn-ghost btn-xs tooltip"
                  aria-label={gettext("Edit metadata")}
                  data-tip={gettext("Edit metadata")}
                >
                  <.icon name="hero-cog-6-tooth-mini" class="size-4" />
                </button>
                <button
                  phx-click="delete_division"
                  phx-value-id={div.id}
                  data-confirm={gettext("Delete this division and all its content?")}
                  class="btn btn-ghost btn-xs text-error tooltip"
                  aria-label={gettext("Delete")}
                  data-tip={gettext("Delete")}
                >
                  <.icon name="hero-trash-mini" class="size-4" />
                </button>
              </div>
            </div>
            <%!-- Child divisions (scenes) --%>
            <div :if={div.children != []} class="divide-y divide-base-300/50">
              <div
                :for={child <- div.children}
                id={"division-#{child.id}"}
                class="flex items-center justify-between px-4 py-2 pl-8 transition-colors hover:bg-base-200/30"
              >
                <button
                  phx-click="select_division"
                  phx-value-id={child.id}
                  class={[
                    "flex items-center gap-2 text-sm transition-colors",
                    if(@selected_division_id == child.id,
                      do: "font-bold text-primary",
                      else: "text-base-content/70 hover:text-base-content"
                    )
                  ]}
                >
                  <.icon name="hero-document-mini" class="size-3.5" />
                  {division_label(child)}
                  <span
                    :if={@selected_division_id == child.id}
                    class="badge badge-primary badge-xs ml-1"
                  >
                    {gettext("editing")}
                  </span>
                </button>
                <div class="flex gap-1">
                  <button
                    phx-click="edit_division"
                    phx-value-id={child.id}
                    class="btn btn-ghost btn-xs tooltip"
                    aria-label={gettext("Edit metadata")}
                    data-tip={gettext("Edit metadata")}
                  >
                    <.icon name="hero-cog-6-tooth-mini" class="size-4" />
                  </button>
                  <button
                    phx-click="delete_division"
                    phx-value-id={child.id}
                    data-confirm={gettext("Delete this scene and all its content?")}
                    class="btn btn-ghost btn-xs text-error tooltip"
                    aria-label={gettext("Delete")}
                    data-tip={gettext("Delete")}
                  >
                    <.icon name="hero-trash-mini" class="size-4" />
                  </button>
                </div>
              </div>
            </div>
            <div class="border-t border-base-300 px-4 py-2 bg-base-200/20">
              <button
                phx-click="new_division"
                phx-value-parent-id={div.id}
                class="btn btn-xs btn-ghost gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Add Scene")}
              </button>
            </div>
          </div>
        </div>
      </div>

      <%!-- Tab: Character Review --%>
      <.cr_tab
        :if={@editor_tab == :character_review}
        characters={@characters}
        speeches={@speeches}
        speaker_labels={@speaker_labels}
        selected_speeches={@selected_speeches}
        filter_label={@filter_label}
        filter_assigned={@filter_assigned}
        first_child_contents={@first_child_contents}
        cr_selected_character_ids={@cr_selected_character_ids}
        cr_display_limit={@cr_display_limit}
      />

      <%!-- Tab: Content --%>
      <div
        :if={@editor_tab == :content}
        id="content-tab"
        phx-hook=".ScrollToElement"
        class="animate-in fade-in"
      >
        <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToElement">
          export default {
            mounted() {
              this.handleEvent("scroll-to-element", ({id}) => {
                requestAnimationFrame(() => {
                  const el = document.getElementById(id)
                  if (el) el.scrollIntoView({behavior: "smooth", block: "center"})
                })
              })
            }
          }
        </script>
        <%!-- Search bar --%>
        <div class="mb-4">
          <form phx-change="content_search" phx-submit="content_search">
            <div class="relative">
              <.icon
                name="hero-magnifying-glass-mini"
                class="absolute left-3 top-2.5 size-4 text-base-content/40 pointer-events-none"
              />
              <input
                type="text"
                name="query"
                value={@content_search}
                placeholder={gettext("Search text across all scenes...")}
                phx-debounce="300"
                class="input input-bordered input-sm w-full pl-9"
                autocomplete="off"
              />
              <button
                :if={@content_search != ""}
                type="button"
                phx-click="content_search_clear"
                class="absolute right-2 top-1.5 btn btn-ghost btn-xs btn-circle"
              >
                <.icon name="hero-x-mark-mini" class="size-3.5" />
              </button>
            </div>
          </form>
        </div>

        <%!-- Search results --%>
        <div :if={@content_search != ""} class="mb-4">
          <p class="text-xs text-base-content/50 mb-2">
            {ngettext(
              "1 result",
              "%{count} results",
              length(@content_search_results),
              count: length(@content_search_results)
            )}
          </p>
          <div class="rounded-box border border-base-300 bg-base-100 shadow-sm divide-y divide-base-200 max-h-64 overflow-y-auto">
            <div
              :for={result <- @content_search_results}
              class="px-4 py-2 cursor-pointer hover:bg-base-200/50"
              phx-click="content_search_go"
              phx-value-id={result.id}
              phx-value-division-id={result.division_id}
              phx-value-parent-id={result.parent_id || ""}
            >
              <div class="flex items-center gap-2">
                <span class="badge badge-xs badge-outline">
                  {element_type_label(result.type)}
                </span>
                <span :if={result.speaker_label} class="text-xs font-medium">
                  {result.speaker_label}
                </span>
                <span :if={result.division} class="text-xs text-base-content/40">
                  {result.division.title || result.division.type}
                </span>
              </div>
              <p class="text-sm text-base-content/70 truncate mt-0.5">
                {String.slice(result.content || result.speaker_label || "", 0..120)}
              </p>
            </div>
            <div
              :if={@content_search_results == []}
              class="px-4 py-6 text-center text-sm text-base-content/50"
            >
              {gettext("No results found.")}
            </div>
          </div>
        </div>

        <%!-- No division selected --%>
        <div
          :if={!@selected_division_id}
          class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-12 text-center"
        >
          <.icon name="hero-cursor-arrow-rays" class="mx-auto mb-3 size-10 text-base-content/30" />
          <p class="text-base-content/60 mb-3">
            {gettext("Select a scene or act from the Structure tab to edit its content.")}
          </p>
          <button
            phx-click="switch_tab"
            phx-value-tab="structure"
            class="btn btn-sm btn-outline gap-1"
          >
            <.icon name="hero-bars-3-bottom-left-mini" class="size-4" /> {gettext("Go to Structure")}
          </button>
        </div>

        <%!-- Division selected --%>
        <div :if={@selected_division_id}>
          <%!-- Content header with division selector --%>
          <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
            <div class="flex flex-col gap-1">
              <div
                :if={parent_division_label(@divisions, @selected_division_id)}
                class="flex items-center gap-1.5 text-sm text-base-content/50"
              >
                <.icon name="hero-folder-mini" class="size-3.5" />
                <span>{parent_division_label(@divisions, @selected_division_id)}</span>
                <.icon name="hero-chevron-right-mini" class="size-3" />
              </div>
              <div class="flex items-center gap-3">
                <h2 class="text-lg font-semibold text-base-content">
                  {current_division_label(@divisions, @selected_division_id)}
                </h2>
                <%!-- Quick division navigation --%>
                <div class="flex gap-1">
                  <button
                    :if={prev_division_id(@divisions, @selected_division_id)}
                    phx-click="select_division"
                    phx-value-id={prev_division_id(@divisions, @selected_division_id)}
                    class="btn btn-ghost btn-xs tooltip"
                    data-tip={gettext("Previous")}
                  >
                    <.icon name="hero-chevron-left-mini" class="size-4" />
                  </button>
                  <button
                    :if={next_division_id(@divisions, @selected_division_id)}
                    phx-click="select_division"
                    phx-value-id={next_division_id(@divisions, @selected_division_id)}
                    class="btn btn-ghost btn-xs tooltip"
                    data-tip={gettext("Next")}
                  >
                    <.icon name="hero-chevron-right-mini" class="size-4" />
                  </button>
                </div>
              </div>
            </div>
            <div class="flex gap-1">
              <button
                phx-click="new_element"
                phx-value-type="speech"
                class="btn btn-xs btn-primary gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Speech")}
              </button>
              <button
                phx-click="new_element"
                phx-value-type="stage_direction"
                class="btn btn-xs btn-outline gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Stage Dir.")}
              </button>
              <button
                phx-click="new_element"
                phx-value-type="prose"
                class="btn btn-xs btn-outline gap-1"
              >
                <.icon name="hero-plus-mini" class="size-3" /> {gettext("Prose")}
              </button>
            </div>
          </div>

          <div
            :if={@elements == []}
            class="rounded-box border border-dashed border-base-300 bg-base-200/30 p-8 text-center text-sm text-base-content/60"
          >
            <.icon name="hero-document-text" class="mx-auto mb-2 size-8 text-base-content/30" />
            <p>{gettext("No content yet. Add a speech, stage direction, or prose.")}</p>
          </div>

          <div :if={@elements != []} class="flex items-center gap-2 mb-2">
            <button phx-click="el_select_all" class="btn btn-ghost btn-xs">
              {gettext("Select all")}
            </button>
            <button
              :if={MapSet.size(@selected_elements) > 0}
              phx-click="el_deselect_all"
              class="btn btn-ghost btn-xs"
            >
              {gettext("Deselect")}
            </button>
          </div>

          <div
            :if={MapSet.size(@selected_elements) > 0}
            class="mb-3 flex items-center gap-3 rounded-box border border-error/30 bg-error/5 p-3"
          >
            <span class="text-sm font-medium">
              {gettext("%{count} selected", count: MapSet.size(@selected_elements))}
            </span>
            <button
              phx-click="el_delete_selected"
              data-confirm={
                gettext("Delete %{count} elements and their children?",
                  count: MapSet.size(@selected_elements)
                )
              }
              class="btn btn-error btn-sm"
            >
              <.icon name="hero-trash-mini" class="size-4" />
              {gettext("Delete selected")}
            </button>
            <button phx-click="el_deselect_all" class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </button>
          </div>

          <div :if={@elements != []} class="space-y-2">
            <.element_card
              :for={element <- @elements}
              element={element}
              characters={@characters}
              depth={0}
              selected_elements={@selected_elements}
              inline_editing_id={@inline_editing_id}
            />
          </div>
        </div>
      </div>

      <%!-- Tab: Preview --%>
      <div :if={@editor_tab == :preview} class="animate-in fade-in">
        <div class="mb-4">
          <h2 class="text-lg font-semibold text-base-content">{gettext("Play Text Preview")}</h2>
        </div>
        <div
          id="preview-scroll-container"
          phx-hook=".PreviewScroll"
          class="rounded-box border border-base-300 bg-base-100 p-6 shadow-sm max-h-[70vh] overflow-y-auto"
        >
          <script :type={Phoenix.LiveView.ColocatedHook} name=".PreviewScroll">
            export default {
              mounted() {
                this.handleEvent("scroll-to-preview", ({target}) => {
                  // Wait for LiveView DOM patch to complete
                  setTimeout(() => {
                    const el = document.getElementById(target)
                    if (el) {
                      const container = this.el
                      const elTop = el.offsetTop - container.offsetTop
                      container.scrollTo({top: elTop, behavior: "smooth"})
                    }
                  }, 100)
                })
              }
            }
          </script>
          <div :if={@preview_divisions == []} class="text-center py-8 text-base-content/60">
            <.icon name="hero-document" class="mx-auto mb-2 size-8 text-base-content/30" />
            <p>{gettext("No content to preview yet.")}</p>
          </div>
          <.play_body
            :if={@preview_divisions != []}
            divisions={@preview_divisions}
            show_line_numbers={true}
            show_stage_directions={true}
          />
        </div>
      </div>

      <%!-- Modal --%>
      <.modal :if={@modal} id="content-modal" on_cancel={JS.push("close_modal")}>
        <.modal_content
          modal={@modal}
          form={@form}
          editing={@editing}
          characters={@characters}
          modal_element_type={@modal_element_type}
          editing_character_ids={@editing_character_ids}
          play_id={@play.id}
          user={@current_user}
        />
      </.modal>
    </div>
    """
  end

  defp division_label(div) do
    if div.title do
      div.title
    else
      if div.number,
        do: "#{String.capitalize(div.type)} #{div.number}",
        else: String.capitalize(div.type)
    end
  end

  defp parent_division_label(divisions, id) do
    Enum.find_value(divisions, nil, fn div ->
      Enum.find_value(div.children || [], nil, fn child ->
        if child.id == id, do: division_label(div)
      end)
    end)
  end

  defp current_division_label(divisions, id) do
    Enum.find_value(divisions, "Unknown", fn div ->
      if div.id == id do
        division_label(div)
      else
        Enum.find_value(div.children || [], nil, fn child ->
          if child.id == id, do: division_label(child)
        end)
      end
    end)
  end

  defp selected_division_short_label(divisions, id) do
    Enum.find_value(divisions, nil, fn div ->
      if div.id == id do
        String.slice(division_label(div), 0..15)
      else
        Enum.find_value(div.children || [], nil, fn child ->
          if child.id == id do
            String.slice(division_label(div), 0..15)
          end
        end)
      end
    end)
  end

  defp all_leaf_divisions(divisions) do
    Enum.flat_map(divisions, fn div ->
      case div.children do
        [] -> [div.id]
        children -> Enum.map(children, & &1.id)
      end
    end)
  end

  defp prev_division_id(divisions, current_id) do
    leaves = all_leaf_divisions(divisions)
    idx = Enum.find_index(leaves, &(&1 == current_id))

    if idx && idx > 0, do: Enum.at(leaves, idx - 1)
  end

  defp next_division_id(divisions, current_id) do
    leaves = all_leaf_divisions(divisions)
    idx = Enum.find_index(leaves, &(&1 == current_id))

    if idx && idx < length(leaves) - 1, do: Enum.at(leaves, idx + 1)
  end

  defp preview_scroll_target(assigns) do
    case assigns.selected_division_id do
      nil -> nil
      id -> "div-#{id}"
    end
  end

  attr :characters, :list, required: true
  attr :speeches, :list, required: true
  attr :speaker_labels, :list, required: true
  attr :selected_speeches, :any, required: true
  attr :cr_selected_character_ids, :list, required: true
  attr :filter_label, :string, default: nil
  attr :filter_assigned, :any, default: nil
  attr :first_child_contents, :map, required: true
  attr :cr_display_limit, :integer, default: 50

  defp cr_tab(assigns) do
    all_filtered = cr_filtered_speeches(assigns)
    total = length(all_filtered)
    limited = Enum.take(all_filtered, assigns.cr_display_limit)
    assigns = assign(assigns, visible_speeches: limited, total_filtered: total)

    # Build lookup of selected character objects for tag display
    selected_chars =
      Enum.filter(assigns.characters, &(&1.id in assigns.cr_selected_character_ids))
      |> Enum.sort_by(fn c ->
        Enum.find_index(assigns.cr_selected_character_ids, &(&1 == c.id))
      end)

    available_chars =
      Enum.reject(assigns.characters, &(&1.id in assigns.cr_selected_character_ids))

    assigns = assign(assigns, selected_chars: selected_chars, available_chars: available_chars)

    ~H"""
    <div class="animate-in fade-in">
      <div class="mb-4 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h2 class="text-lg font-semibold text-base-content">{gettext("Character Review")}</h2>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext(
              "Assign characters to speeches. Create characters from speaker labels found in the text."
            )}
          </p>
        </div>
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-4">
        <%!-- Left: Characters & speaker labels --%>
        <div class="lg:col-span-1">
          <div class="rounded-box border border-base-300 bg-base-100 shadow-sm">
            <div class="border-b border-base-300 px-4 py-3">
              <h3 class="font-semibold text-sm">{gettext("Characters")} ({length(@characters)})</h3>
            </div>
            <div class="divide-y divide-base-200 max-h-96 overflow-y-auto">
              <div :for={char <- @characters} class="px-4 py-2 text-sm">
                <span class="font-medium">{char.name}</span>
                <span class="text-base-content/50 text-xs ml-1">{char.xml_id}</span>
              </div>
              <div :if={@characters == []} class="px-4 py-6 text-sm text-base-content/50 text-center">
                {gettext("No characters yet.")}
              </div>
            </div>
          </div>
        </div>

        <%!-- Right: Speeches list --%>
        <div class="lg:col-span-3">
          <div class="mb-4 flex flex-wrap items-center gap-3">
            <form phx-change="cr_filter" class="flex items-center gap-2 flex-1">
              <select name="label" class="select select-bordered select-sm">
                <option value="">{gettext("All speakers")}</option>
                <option value="__none__" selected={@filter_label == :none}>
                  {gettext("(No label)")}
                </option>
                <option
                  :for={label <- @speaker_labels}
                  :if={label && label != ""}
                  value={label}
                  selected={@filter_label == label}
                >
                  {label}
                </option>
              </select>
              <select name="assigned" class="select select-bordered select-sm">
                <option value="">{gettext("All")}</option>
                <option value="yes" selected={@filter_assigned == true}>{gettext("Assigned")}</option>
                <option value="no" selected={@filter_assigned == false}>
                  {gettext("Unassigned")}
                </option>
              </select>
            </form>
            <div class="flex items-center gap-1">
              <button phx-click="cr_select_all_visible" class="btn btn-ghost btn-xs">
                {gettext("Select all")}
              </button>
              <button phx-click="cr_deselect_all" class="btn btn-ghost btn-xs">
                {gettext("Deselect")}
              </button>
            </div>
          </div>

          <div
            :if={MapSet.size(@selected_speeches) > 0}
            class="mb-4 rounded-box border border-primary/30 bg-primary/5 p-4 space-y-3"
          >
            <span class="text-sm font-semibold">
              {gettext("%{count} selected", count: MapSet.size(@selected_speeches))}
            </span>

            <%!-- Character assignment section --%>
            <div class="flex flex-wrap items-center gap-2">
              <span class="text-sm text-base-content/60">{gettext("Characters:")}</span>
              <span
                :for={char <- @selected_chars}
                class="badge badge-sm badge-primary gap-1"
              >
                {char.name}
                <button
                  type="button"
                  phx-click="cr_remove_character"
                  phx-value-id={char.id}
                  class="hover:text-primary-content/60"
                  aria-label={gettext("Remove %{name}", name: char.name)}
                >
                  <.icon name="hero-x-mark-mini" class="size-3" />
                </button>
              </span>
              <span :if={@selected_chars == []} class="text-sm text-base-content/40 italic">
                {gettext("none")}
              </span>
              <form :if={@available_chars != []} phx-change="cr_add_character" class="inline">
                <select name="character_id" class="select select-bordered select-xs">
                  <option value="">{gettext("Add...")}</option>
                  <option :for={char <- @available_chars} value={char.id}>
                    {char.name}
                  </option>
                </select>
              </form>
              <form phx-submit="cr_assign_characters" class="inline">
                <button type="submit" class="btn btn-primary btn-xs">
                  {gettext("Assign Characters")}
                </button>
              </form>
            </div>

            <div class="divider my-0 h-0"></div>

            <%!-- Label editing section --%>
            <form phx-submit="cr_set_label" class="flex flex-wrap items-center gap-2">
              <span class="text-sm text-base-content/60">{gettext("Label:")}</span>
              <input
                type="text"
                name="speaker_label"
                placeholder={gettext("Leave empty to clear")}
                class="input input-bordered input-xs w-40"
              />
              <button type="submit" class="btn btn-secondary btn-xs">
                {gettext("Set Label")}
              </button>
              <button
                type="button"
                phx-click="cr_clear_label"
                class="btn btn-ghost btn-xs tooltip"
                data-tip={gettext("Clear label")}
              >
                <.icon name="hero-x-mark-mini" class="size-3.5" />
                {gettext("Clear")}
              </button>
            </form>
          </div>

          <div class="rounded-box border border-base-300 bg-base-100 shadow-sm divide-y divide-base-200">
            <div
              :for={speech <- @visible_speeches}
              class={[
                "flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-base-200/50",
                MapSet.member?(@selected_speeches, speech.id) && "bg-primary/5"
              ]}
              phx-click="cr_toggle_speech"
              phx-value-id={speech.id}
            >
              <input
                type="checkbox"
                class="checkbox checkbox-sm checkbox-primary"
                checked={MapSet.member?(@selected_speeches, speech.id)}
                readonly
              />
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2">
                  <span class="font-medium text-sm">
                    {speech.speaker_label || gettext("(no speaker)")}
                  </span>
                  <span :if={speech.division} class="text-xs text-base-content/40">
                    {speech.division.title || speech.division.type}
                  </span>
                </div>
                <p
                  :if={@first_child_contents[speech.id]}
                  class="text-xs text-base-content/50 truncate mt-0.5"
                >
                  {@first_child_contents[speech.id]}
                </p>
              </div>
              <div class="flex-shrink-0 flex gap-1 flex-wrap items-center">
                <span
                  :for={char <- Playcode.PlayContent.Element.characters(speech)}
                  class="badge badge-sm badge-outline badge-success"
                >
                  {char.name}
                </span>
                <span
                  :if={speech.element_characters == []}
                  class="badge badge-sm badge-ghost"
                >
                  {gettext("unassigned")}
                </span>
                <button
                  phx-click="cr_go_to_speech"
                  phx-value-id={speech.id}
                  class="btn btn-ghost btn-xs btn-square ml-1 tooltip"
                  data-tip={gettext("View in content")}
                  title={gettext("View in content")}
                >
                  <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
                </button>
              </div>
            </div>
            <div
              :if={@visible_speeches == []}
              class="px-4 py-8 text-center text-sm text-base-content/50"
            >
              {gettext("No speeches found.")}
            </div>
          </div>
          <div
            :if={length(@visible_speeches) < @total_filtered}
            class="mt-2 text-center"
          >
            <button phx-click="cr_show_more" class="btn btn-ghost btn-sm">
              {gettext("Show more (%{remaining} remaining)",
                remaining: @total_filtered - length(@visible_speeches)
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Tab button component ---

  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :icon, :string, required: true
  attr :label, :string, default: nil
  attr :count, :integer, default: nil
  attr :badge, :string, default: nil

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "flex items-center gap-2 px-4 py-2.5 text-sm font-medium border-b-2 transition-colors",
        if(@active == @tab,
          do: "border-primary text-primary",
          else:
            "border-transparent text-base-content/60 hover:text-base-content hover:border-base-300"
        )
      ]}
    >
      <.icon name={@icon} class="size-4" />
      <span class={unless @label, do: "capitalize"}>{@label || @tab}</span>
      <span :if={@count} class="badge badge-sm badge-ghost">{@count}</span>
      <span :if={@badge} class="badge badge-sm badge-primary">{@badge}</span>
    </button>
    """
  end

  # --- Element card component (recursive) ---

  attr :element, :map, required: true
  attr :characters, :list, required: true
  attr :depth, :integer, default: 0
  attr :selected_elements, :any, default: MapSet.new()
  attr :inline_editing_id, :string, default: nil

  defp element_card(assigns) do
    assigns = assign(assigns, :is_inline_editing, assigns.inline_editing_id == assigns.element.id)

    ~H"""
    <div
      id={"element-#{@element.id}"}
      class={[
        "rounded-box border border-base-300 bg-base-100 shadow-sm",
        @depth > 0 && "ml-4 mt-1",
        @depth == 0 && MapSet.member?(@selected_elements, @element.id) && "ring-2 ring-primary/30"
      ]}
    >
      <div class="flex items-center justify-between p-3">
        <div class="flex items-center flex-1 min-w-0">
          <input
            :if={@depth == 0}
            id={"el-chk-#{@element.id}"}
            phx-hook="ShiftClick"
            data-id={@element.id}
            type="checkbox"
            class="checkbox checkbox-sm checkbox-primary mr-2 shrink-0"
            checked={MapSet.member?(@selected_elements, @element.id)}
          />
          <span class="badge badge-sm badge-outline mr-2 shrink-0">
            {element_type_label(@element.type)}
          </span>
          <%!-- Speaker label: click opens modal --%>
          <span
            :if={@element.speaker_label}
            phx-click="edit_element"
            phx-value-id={@element.id}
            class="font-medium cursor-pointer hover:text-primary shrink-0"
          >
            {@element.speaker_label}
          </span>
          <%!-- Content: inline editing or click to edit --%>
          <span
            :if={@element.content && !@is_inline_editing}
            phx-click="inline_edit"
            phx-value-id={@element.id}
            class="text-sm text-base-content/80 cursor-pointer hover:text-base-content truncate"
            title={@element.content}
          >
            {String.slice(@element.content || "", 0..80)}{if String.length(@element.content || "") >
                                                               80,
                                                             do: "..."}
          </span>
          <form
            :if={@is_inline_editing}
            id={"inline-edit-#{@element.id}"}
            phx-hook=".InlineEdit"
            phx-submit="inline_save"
            class="flex-1 min-w-0 ml-1"
          >
            <input type="hidden" name="element_id" value={@element.id} />
            <input
              type="text"
              name="value"
              value={@element.content || ""}
              class="input input-sm input-bordered w-full"
              phx-key="Escape"
              phx-keydown="inline_cancel"
            />
          </form>
          <span :if={@element.verse_type} class="text-xs text-base-content/50 ml-2">
            ({@element.verse_type})
          </span>
          <span :if={@element.line_number} class="text-xs text-base-content/50 ml-1">
            L{@element.line_number}
          </span>
          <span :if={@element.is_aside} class="badge badge-ghost badge-xs ml-1">
            {gettext("aside")}
          </span>
        </div>
        <div class="flex gap-1">
          <%!-- Insert Above for top-level elements (speeches, stage dirs, prose) --%>
          <div :if={@depth == 0} class="dropdown dropdown-end">
            <label
              tabindex="0"
              class="btn btn-xs btn-ghost btn-outline tooltip"
              aria-label={gettext("Insert Above")}
              data-tip={gettext("Insert Above")}
            >
              <.icon name="hero-arrow-up-mini" class="size-4" />
            </label>
            <ul
              tabindex="0"
              class="dropdown-content z-[1] menu p-1 shadow bg-base-100 rounded-box w-40"
            >
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="speech"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Speech")}
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="stage_direction"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Stage Direction")}
                </button>
              </li>
              <li>
                <button
                  phx-click="new_element_before"
                  phx-value-type="prose"
                  phx-value-position={@element.position}
                  phx-value-parent-id=""
                >
                  {gettext("Prose")}
                </button>
              </li>
            </ul>
          </div>
          <%!-- Insert Above for verse lines inside line groups --%>
          <button
            :if={@element.type == "verse_line" && @element.parent_id}
            phx-click="new_element_before"
            phx-value-type="verse_line"
            phx-value-position={@element.position}
            phx-value-parent-id={@element.parent_id}
            class="btn btn-xs btn-ghost btn-outline tooltip"
            aria-label={gettext("Insert Above")}
            data-tip={gettext("Insert Above")}
          >
            <.icon name="hero-arrow-up-mini" class="size-4" />
          </button>
          <button
            phx-click="edit_element"
            phx-value-id={@element.id}
            class="btn btn-ghost btn-xs tooltip"
            aria-label={gettext("Edit")}
            data-tip={gettext("Edit")}
          >
            <.icon name="hero-pencil-mini" class="size-4" />
          </button>
          <button
            phx-click="delete_element"
            phx-value-id={@element.id}
            data-confirm={gettext("Delete this element and its children?")}
            class="btn btn-ghost btn-xs text-error tooltip"
            aria-label={gettext("Delete")}
            data-tip={gettext("Delete")}
          >
            <.icon name="hero-trash-mini" class="size-4" />
          </button>
        </div>
      </div>
      <%!-- Children --%>
      <div
        :if={match?([_ | _], Map.get(@element, :children, []))}
        class="border-t border-base-300 bg-base-200/30 px-3 py-2"
      >
        <.element_card
          :for={child <- @element.children}
          element={child}
          characters={@characters}
          depth={@depth + 1}
          selected_elements={@selected_elements}
          inline_editing_id={@inline_editing_id}
        />
      </div>
      <%!-- Add child buttons --%>
      <div :if={@element.type == "speech"} class="border-t border-base-300 px-3 py-2">
        <button
          phx-click="new_element"
          phx-value-type="line_group"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Line Group")}
        </button>
        <button
          phx-click="new_element"
          phx-value-type="stage_direction"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Stage Direction")}
        </button>
        <button
          phx-click="new_element"
          phx-value-type="prose"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Prose")}
        </button>
      </div>
      <div :if={@element.type == "line_group"} class="border-t border-base-300 px-3 py-2">
        <button
          phx-click="new_element"
          phx-value-type="verse_line"
          phx-value-parent-id={@element.id}
          class="btn btn-xs btn-ghost btn-outline"
        >
          {gettext("Add Verse Line")}
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".InlineEdit">
        export default {
          mounted() {
            this._cancelled = false
            const input = this.el.querySelector("input[name='value']")
            if (input) {
              input.focus()
              input.select()
              input.addEventListener("keydown", (e) => {
                if (e.key === "Escape") {
                  this._cancelled = true
                }
              })
              input.addEventListener("blur", () => {
                if (!this._cancelled) {
                  this.el.dispatchEvent(new Event("submit", {bubbles: true, cancelable: true}))
                }
              })
            }
          }
        }
      </script>
    </div>
    """
  end

  defp element_type_label("speech"), do: gettext("Speech")
  defp element_type_label("stage_direction"), do: gettext("Stage Dir.")
  defp element_type_label("verse_line"), do: gettext("Verse")
  defp element_type_label("prose"), do: gettext("Prose")
  defp element_type_label("line_group"), do: gettext("Line Group")
  defp element_type_label(type), do: type

  # --- Modal content ---

  attr :modal, :atom, required: true
  attr :form, :any, required: true
  attr :editing, :any, default: nil
  attr :characters, :list, default: []
  attr :modal_element_type, :string, default: nil
  attr :editing_character_ids, :list, default: []
  attr :play_id, :string, default: nil
  attr :user, :any, default: nil

  defp modal_content(%{modal: :editorial_note} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">
      {editing_label(@editing)} {gettext("Editorial Note")}
    </h3>
    <.form
      for={@form}
      as={:editorial_note}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label">
          <span class="label-text font-medium">{gettext("Section Type")} *</span>
        </label>
        <.input field={@form[:section_type]} type="select" options={section_type_options()} />
      </div>
      <div>
        <label class="label">
          <span class="label-text font-medium">{gettext("Heading")}</span>
        </label>
        <.input
          field={@form[:heading]}
          type="text"
          placeholder={gettext("Optional section heading")}
        />
      </div>
      <div>
        <label class="label">
          <span class="label-text font-medium">{gettext("Content")} *</span>
        </label>
        <.input
          field={@form[:content]}
          type="textarea"
          rows="8"
          placeholder={gettext("Note text...")}
        />
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    """
  end

  defp modal_content(%{modal: :character} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">{editing_label(@editing)} {gettext("Character")}</h3>
    <.form
      for={@form}
      as={:character}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label"><span class="label-text font-medium">XML ID *</span></label>
        <.input field={@form[:xml_id]} type="text" required placeholder={gettext("e.g. DONA_ANA")} />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Name")} *</span></label>
        <.input field={@form[:name]} type="text" required placeholder={gettext("e.g. Dona Ana")} />
      </div>
      <div>
        <label class="label">
          <span class="label-text font-medium">{gettext("Description")}</span>
        </label>
        <.input field={@form[:description]} type="text" placeholder={gettext("e.g. una dama")} />
      </div>
      <div>
        <label class="flex items-center gap-2">
          <.input field={@form[:is_hidden]} type="checkbox" />
          <span class="label-text">{gettext("Hidden character")}</span>
        </label>
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    """
  end

  defp modal_content(%{modal: :division} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">{editing_label(@editing)} {gettext("Division")}</h3>
    <.form
      id="division-form"
      for={@form}
      as={:division}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Type")} *</span></label>
        <.input field={@form[:type]} type="select" options={division_types()} />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Number")}</span></label>
        <.input field={@form[:number]} type="number" />
      </div>
      <div>
        <label class="label"><span class="label-text font-medium">{gettext("Title")}</span></label>
        <.input field={@form[:title]} type="text" placeholder={gettext("e.g. ACTO PRIMERO")} />
      </div>
      <.input field={@form[:position]} type="hidden" />
      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    <.live_component
      :if={@editing}
      module={PlaycodeWeb.Admin.NotesComponent}
      id={"notes-#{@editing.id}"}
      anchor={@editing}
      play_id={@play_id}
      user={@user}
    />
    """
  end

  defp modal_content(%{modal: :element} = assigns) do
    ~H"""
    <h3 class="text-lg font-bold mb-4">
      {editing_label(@editing)} {element_type_label(@modal_element_type)}
    </h3>
    <.form
      id="element-form"
      for={@form}
      as={:element}
      phx-change="validate_form"
      phx-submit="save_form"
      class="space-y-4"
    >
      <.input field={@form[:type]} type="hidden" />
      <.input field={@form[:position]} type="hidden" />
      <.input field={@form[:parent_id]} type="hidden" />

      <%!-- Speech fields --%>
      <div :if={@modal_element_type == "speech"}>
        <div class="mb-4">
          <label class="label">
            <span class="label-text font-medium">{gettext("Speaker Label")}</span>
          </label>
          <.input field={@form[:speaker_label]} type="text" placeholder={gettext("e.g. ANA")} />
        </div>
        <div class="mb-4">
          <label class="label">
            <span class="label-text font-medium">{gettext("Characters")}</span>
          </label>
          <% selected_chars = Enum.filter(@characters, &(&1.id in @editing_character_ids))
          available_chars = Enum.reject(@characters, &(&1.id in @editing_character_ids)) %>
          <input
            :for={cid <- @editing_character_ids}
            type="hidden"
            name="character_ids[]"
            value={cid}
          />
          <div class="flex flex-wrap gap-1 mb-2">
            <span
              :for={char <- selected_chars}
              class="badge badge-sm badge-primary gap-1"
            >
              {char.name}
              <button
                type="button"
                phx-click="el_remove_character"
                phx-value-id={char.id}
                class="hover:text-primary-content/60"
                aria-label={gettext("Remove %{name}", name: char.name)}
              >
                <.icon name="hero-x-mark-mini" class="size-3" />
              </button>
            </span>
            <span :if={selected_chars == []} class="text-sm text-base-content/40 italic">
              {gettext("none")}
            </span>
          </div>
          <select
            :if={available_chars != []}
            id="el-char-select"
            phx-hook=".ElCharSelect"
            class="select select-bordered select-sm w-full"
          >
            <option value="">{gettext("Add character...")}</option>
            <option :for={char <- available_chars} value={char.id}>
              {char.name} ({char.xml_id})
            </option>
          </select>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".ElCharSelect">
            export default {
              mounted() {
                this.el.addEventListener("change", () => {
                  if (this.el.value) {
                    this.pushEvent("el_add_character", {character_id: this.el.value})
                  }
                })
              }
            }
          </script>
          <div :if={@characters == []} class="text-sm text-base-content/50 text-center py-2">
            {gettext("No characters defined.")}
          </div>
        </div>
        <div>
          <label class="flex items-center gap-2">
            <.input field={@form[:is_aside]} type="checkbox" />
            <span class="label-text">{gettext("Aside")}</span>
          </label>
        </div>
      </div>

      <%!-- Stage direction fields --%>
      <div :if={@modal_element_type == "stage_direction"}>
        <div class="mb-4">
          <label class="label">
            <span class="label-text font-medium">{gettext("Content")}</span>
          </label>
          <.input
            field={@form[:content]}
            type="textarea"
            rows="3"
            placeholder={gettext("Stage direction text...")}
          />
        </div>
        <div>
          <label class="label"><span class="label-text font-medium">Rend</span></label>
          <.input field={@form[:rend]} type="text" placeholder={gettext("e.g. italics")} />
        </div>
      </div>

      <%!-- Prose fields --%>
      <div :if={@modal_element_type == "prose"}>
        <label class="label"><span class="label-text font-medium">{gettext("Content")}</span></label>
        <.input
          field={@form[:content]}
          type="textarea"
          rows="4"
          placeholder={gettext("Prose text...")}
        />
        <p class="mt-1 text-xs text-base-content/60">
          {gettext("Stage direction in the text: <stage type=\"delivery\">…</stage>")}
        </p>
      </div>

      <%!-- Line group fields --%>
      <div :if={@modal_element_type == "line_group"}>
        <label class="label">
          <span class="label-text font-medium">{gettext("Verse Type")}</span>
        </label>
        <.input field={@form[:verse_type]} type="select" options={verse_types()} />
      </div>

      <%!-- Verse line fields --%>
      <div :if={@modal_element_type == "verse_line"}>
        <div class="mb-4">
          <label class="label">
            <span class="label-text font-medium">{gettext("Content")} *</span>
          </label>
          <.input
            field={@form[:content]}
            type="text"
            required
            placeholder={gettext("Verse line text...")}
          />
          <p class="mt-1 text-xs text-base-content/60">
            {gettext("Stage direction in the text: <stage type=\"delivery\">…</stage>")}
          </p>
        </div>
        <div class="grid grid-cols-2 gap-4">
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Line Number")}</span>
            </label>
            <.input field={@form[:line_number]} type="number" />
          </div>
          <div>
            <label class="label">
              <span class="label-text font-medium">{gettext("Part (split line)")}</span>
            </label>
            <.input field={@form[:part]} type="select" options={part_options()} />
          </div>
        </div>
      </div>

      <div class="flex gap-2 pt-2">
        <button type="submit" class="btn btn-primary">{gettext("Save")}</button>
        <button type="button" phx-click="close_modal" class="btn btn-ghost">
          {gettext("Cancel")}
        </button>
      </div>
    </.form>
    <.live_component
      :if={@editing && @editing.type in ~w(verse_line prose stage_direction trailer speech)}
      module={PlaycodeWeb.Admin.NotesComponent}
      id={"notes-#{@editing.id}"}
      anchor={@editing}
      play_id={@play_id}
      user={@user}
    />
    """
  end
end
