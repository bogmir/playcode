defmodule PlaycodeWeb.Admin.PlayContentEditorLive do
  @moduledoc """
  /admin/plays/:id/content: a play's text: paratexts, characters, divisions and
  elements, a preview, and the character review that assigns speakers in bulk. Every id an
  event carries is resolved through a getter scoped to the play, and a miss reloads the
  lists with `LiveHelpers.put_gone_flash/1` (see *Access control* in CLAUDE.md).
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Admin.ContentEditor.Components, only: [division_label: 1]

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Paratext
  alias Playcode.Outline
  alias Playcode.Alignment
  alias Playcode.PlayContent
  alias Playcode.PlayContent.{Character, Division, Element, InlineMarkup}

  alias PlaycodeWeb.Admin.ContentEditor.{
    Characters,
    CharacterReview,
    Content,
    Paratexts,
    Preview,
    Structure
  }

  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"id" => id} = params, _session, socket) do
    play = Catalogue.get_play!(id)
    {:ok, socket} = mount_editor(socket, play)
    {:ok, open_requested(socket, params)}
  end

  # ?element=<id> or ?division=<id>, the Notes tab's "Open in Content": that line's or
  # heading's modal, its notes included. An id that is not one of the play's opens nothing.
  defp open_requested(socket, %{"element" => id}) do
    case PlayContent.get_element(socket.assigns.play.id, id) do
      nil -> socket
      element -> element_modal(socket, element)
    end
  end

  defp open_requested(socket, %{"division" => id}) do
    case PlayContent.get_division(socket.assigns.play.id, id) do
      nil -> socket
      division -> division_modal(socket, division)
    end
  end

  defp open_requested(socket, _params), do: socket

  defp mount_editor(socket, play) do
    if connected?(socket) do
      PlayContent.subscribe(play.id)
    end

    paratexts = Catalogue.list_paratexts(play.id)
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
       paratexts: paratexts,
       characters: characters,
       cast_lists: PlayContent.list_cast_lists(play.id),
       original_pairs: if(connected?(socket), do: original_pairs(play)),
       modal_list_id: nil,
       character_form: nil,
       entry_character: nil,
       original_choice: nil,
       existing_options: [],
       divisions: divisions,
       removals: removals(divisions),
       split_verses: PlayContent.split_verses_out_of_order(play.id),
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

  def handle_event("validate_form", params, %{assigns: %{modal: :existing_entry}} = socket),
    do: {:noreply, assign(socket, form: to_form(params["existing"] || %{}, as: :existing))}

  def handle_event("validate_form", params, %{assigns: %{modal: :entry}} = socket) do
    %{editing: entry, entry_character: character} = socket.assigns

    {:noreply,
     assign(socket,
       form: validated(PlayContent.change_entry(entry, params["entry"] || %{}), :entry),
       character_form:
         character &&
           validated(
             PlayContent.change_character(character, params["character"] || %{}),
             :character
           )
     )}
  end

  def handle_event("validate_form", params, socket) do
    form_params = extract_form_params(params, socket.assigns.modal)

    changeset =
      case socket.assigns.modal do
        :paratext ->
          Catalogue.change_paratext(
            socket.assigns.editing || %Paratext{},
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
      :paratext -> save_paratext(socket, params)
      :character -> save_character(socket, params)
      :entry -> save_entry(socket, params)
      :existing_entry -> save_existing_entry(socket, params)
      :division -> save_division(socket, params)
      :element -> save_element(socket, params)
    end
  end

  def handle_event("new_paratext", _, socket) do
    play = socket.assigns.play

    # Last in the outline, whose positions the divisions share.
    changeset =
      Catalogue.change_paratext(%Paratext{
        play_id: play.id,
        position: Outline.next_position(play.id)
      })

    {:noreply,
     assign(socket,
       modal: :paratext,
       editing: nil,
       form: to_form(changeset, as: :paratext)
     )}
  end

  def handle_event("edit_paratext", %{"id" => id}, socket) do
    with_row(socket, Catalogue.get_paratext(socket.assigns.play.id, id), fn paratext ->
      assign(socket,
        modal: :paratext,
        editing: paratext,
        form: to_form(Catalogue.change_paratext(paratext), as: :paratext)
      )
    end)
  end

  def handle_event("delete_paratext", %{"id" => id}, socket) do
    with_row(socket, Catalogue.get_paratext(socket.assigns.play.id, id), fn paratext ->
      {:ok, _} = Catalogue.delete_paratext(paratext)

      LiveHelpers.log_activity(socket, "delete", "paratext", paratext.id, %{
        kind: paratext.kind
      })

      socket
      |> put_flash(:info, gettext("Paratext deleted."))
      |> reload_paratexts()
    end)
  end

  # A character and its entry, in the list named, or the play's first.
  def handle_event("new_character", params, socket) do
    case params["list-id"] do
      blank when blank in [nil, ""] ->
        {:noreply, character_modal(socket, nil)}

      list_id ->
        with_row(socket, PlayContent.get_cast_list(socket.assigns.play.id, list_id), fn list ->
          character_modal(socket, list.id)
        end)
    end
  end

  # An entry in this list for a character listed elsewhere: those not in it yet are offered.
  def handle_event("add_existing_entry", %{"list-id" => list_id}, socket) do
    with_row(socket, PlayContent.get_cast_list(socket.assigns.play.id, list_id), fn list ->
      listed =
        for entry <- cast_list_entries(socket, list.id),
            entry.character_id,
            do: entry.character_id

      assign(socket,
        modal: :existing_entry,
        editing: nil,
        modal_list_id: list.id,
        existing_options:
          for(c <- socket.assigns.characters, c.id not in listed, do: {c.name, c.id}),
        form: to_form(%{"character_id" => nil}, as: :existing)
      )
    end)
  end

  def handle_event("edit_entry", %{"id" => id}, socket) do
    play_id = socket.assigns.play.id

    with_row(socket, PlayContent.get_entry(play_id, id), fn entry ->
      character = entry.character_id && PlayContent.get_character(play_id, entry.character_id)

      assign(socket,
        modal: :entry,
        editing: entry,
        entry_character: character,
        original_choice: original_choice(socket.assigns.play, character),
        form: to_form(PlayContent.change_entry(entry), as: :entry),
        character_form:
          character && to_form(PlayContent.change_character(character), as: :character)
      )
    end)
  end

  def handle_event("delete_entry", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_entry(socket.assigns.play.id, id), fn entry ->
      case PlayContent.delete_entry(entry) do
        {:ok, _} ->
          LiveHelpers.log_activity(socket, "delete", "cast_list_entry", entry.id, %{
            name: entry.name
          })

          socket
          |> put_flash(:info, gettext("Removed from the list."))
          |> reload_characters()

        {:error, {:speaking, [name]}} ->
          put_flash(
            socket,
            :error,
            gettext("Not removed: %{name} speaks in the play and is listed nowhere else.",
              name: name
            )
          )
      end
    end)
  end

  def handle_event("reorder_entries", %{"ids" => keys}, socket) do
    PlayContent.reorder_entries(socket.assigns.play.id, keys)
    {:noreply, reload_characters(socket)}
  end

  def handle_event("reorder_outline", %{"ids" => keys}, socket) do
    Outline.reorder(socket.assigns.play.id, keys)
    {:noreply, socket |> reload_paratexts() |> reload_divisions() |> reload_characters()}
  end

  def handle_event("reorder_children", %{"parent" => parent_id, "ids" => ids}, socket) do
    with_row(socket, PlayContent.get_division(socket.assigns.play.id, parent_id), fn act ->
      PlayContent.reorder_children(act, ids)
      socket |> reload_divisions() |> reload_characters()
    end)
  end

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

    {:ok, _} =
      socket
      |> own_elements(socket.assigns.selected_speeches)
      |> PlayContent.set_elements_characters(character_ids)

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

    {:ok, _} =
      PlayContent.set_speaker_labels(
        own_elements(socket, socket.assigns.selected_speeches),
        label
      )

    {:noreply,
     socket
     |> reload_speeches()
     |> assign(filter_label: label || :none)
     |> put_flash(:info, gettext("Label updated."))}
  end

  def handle_event("cr_clear_label", _params, socket) do
    {:ok, _} =
      PlayContent.set_speaker_labels(own_elements(socket, socket.assigns.selected_speeches), nil)

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
    with_row(
      socket,
      PlayContent.get_division(socket.assigns.play.id, id),
      &division_modal(socket, &1)
    )
  end

  def handle_event("delete_division", %{"id" => id}, socket) do
    with_row(socket, PlayContent.get_division(socket.assigns.play.id, id), fn division ->
      case PlayContent.delete_division(division) do
        {:ok, _} -> division_deleted(socket, division)
        {:error, {:speaking, names}} -> put_flash(socket, :error, speaking_refusal(names))
      end
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
        "play_id" => play.id,
        "division_id" => div_id,
        "parent_id" => parent_id,
        "type" => element_type,
        "position" => pos
      }

      assign(socket,
        modal: :element,
        editing: nil,
        new_element: attrs,
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
    with_row(
      socket,
      PlayContent.get_element(socket.assigns.play.id, id),
      &element_modal(socket, &1)
    )
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
        case PlayContent.update_element(element, inline_attrs(element, value)) do
          {:ok, _el} ->
            LiveHelpers.log_activity(socket, "update", "element", element.id, %{
              type: element.type,
              inline: true
            })

            socket
            |> assign(inline_editing_id: nil)
            |> reload_elements()

          {:error, changeset} ->
            put_flash(socket, :error, save_error(changeset))
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
    elements = own_elements(socket, socket.assigns.selected_elements)
    count = length(elements)

    {:ok, _} = PlayContent.delete_elements(elements)

    {:noreply,
     socket
     |> put_flash(:info, gettext("%{count} elements deleted.", count: count))
     |> assign(selected_elements: MapSet.new())
     |> reload_elements()}
  end

  defp division_deleted(socket, division) do
    LiveHelpers.log_activity(socket, "delete", "division", division.id, %{
      type: division.type,
      number: division.number
    })

    # The selected scene may have gone with its act.
    selected =
      if socket.assigns.selected_division_id in [
           division.id | Enum.map(division_children(socket, division), & &1.id)
         ],
         do: nil,
         else: socket.assigns.selected_division_id

    socket
    |> put_flash(:info, gettext("Division deleted."))
    |> assign(selected_division_id: selected)
    |> reload_divisions()
    |> reload_characters()
    |> reload_elements()
  end

  defp division_children(socket, division) do
    case find_division(socket.assigns.divisions, division.id) do
      %{children: children} when is_list(children) -> children
      _scene -> []
    end
  end

  defp speaking_refusal(names) do
    gettext(
      "Not deleted: %{names} speak in the play and are listed nowhere else. List them elsewhere first.",
      names: Enum.join(names, ", ")
    )
  end

  defp open_new_division(socket, parent_id) do
    play = socket.assigns.play

    # Last at its level, the outline's paratexts included at the top.
    pos =
      if parent_id,
        do: PlayContent.next_division_position(play.id, parent_id),
        else: Outline.next_position(play.id)

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
      "play_id" => play.id,
      "division_id" => div_id,
      "parent_id" => parent_id,
      "type" => element_type,
      "position" => before_pos
    }

    socket
    |> reload_elements()
    |> assign(
      modal: :element,
      editing: nil,
      new_element: attrs,
      modal_element_type: element_type,
      editing_character_ids: [],
      form: to_form(PlayContent.change_element(%Element{}, attrs))
    )
  end

  defp delete_element(socket, element) do
    {:ok, _} = PlayContent.delete_element(element)
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
  # The modal that edits a division or an element, opened from its row or from the
  # Notes tab's link.
  defp division_modal(socket, division) do
    assign(socket,
      modal: :division,
      editing: division,
      form: to_form(PlayContent.change_division(division))
    )
  end

  # A paragraph's quick edit holds its words only; its own number stays.
  defp inline_attrs(%{type: "prose", content: content}, value),
    do: %{"content" => value, "number" => content |> InlineMarkup.paragraph_number() |> elem(0)}

  defp inline_attrs(_element, value), do: %{"content" => value}

  defp element_modal(socket, element) do
    assign(socket,
      modal: :element,
      editing: element,
      modal_element_type: element.type,
      editing_character_ids: Enum.map(element.element_characters, & &1.character_id),
      form: to_form(PlayContent.change_element(element))
    )
  end

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
    |> reload_paratexts()
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

  defp el_toggle_single(socket, id) do
    selected = socket.assigns.selected_elements

    selected =
      if MapSet.member?(selected, id),
        do: MapSet.delete(selected, id),
        else: MapSet.put(selected, id)

    {:noreply, assign(socket, selected_elements: selected, last_toggled_element: id)}
  end

  # A form posts back, as hidden fields, the ids that place its row, and the browser can
  # change them: they come from the server, the row's own when it is edited, its opener's
  # when it is new (CLAUDE.md, *Access control*).
  @placing ~w(play_id division_id parent_id cast_list_id character_id)
  defp form_params(params, form), do: Map.drop(params[form] || %{}, @placing)

  defp save_paratext(socket, params) do
    paratext_params = form_params(params, "paratext")
    play = socket.assigns.play

    result =
      case socket.assigns.editing do
        nil ->
          paratext_params = Map.put(paratext_params, "play_id", play.id)
          Catalogue.create_paratext(paratext_params)

        paratext ->
          Catalogue.update_paratext(paratext, paratext_params)
      end

    case result do
      {:ok, saved} ->
        action = if socket.assigns.editing, do: "update", else: "create"

        LiveHelpers.log_activity(socket, action, "paratext", saved.id, %{
          kind: saved.kind
        })

        {:noreply,
         socket
         |> put_flash(:info, gettext("Paratext saved."))
         |> assign(modal: nil, form: nil, editing: nil)
         |> reload_paratexts()}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :paratext))}
    end
  end

  defp character_modal(socket, list_id) do
    changeset = PlayContent.change_character(%Character{}, %{play_id: socket.assigns.play.id})

    assign(socket,
      modal: :character,
      editing: nil,
      modal_list_id: list_id,
      form: to_form(changeset)
    )
  end

  defp cast_list_entries(socket, list_id) do
    case Enum.find(socket.assigns.cast_lists, &(&1.id == list_id)) do
      nil -> []
      list -> list.entries
    end
  end

  defp validated(changeset, as), do: changeset |> Map.put(:action, :validate) |> to_form(as: as)

  # A new character, with its entry in the list it was added from.
  defp save_character(socket, params) do
    play = socket.assigns.play

    char_params =
      params
      |> form_params("character")
      |> Map.put("play_id", play.id)
      |> Map.put("cast_list_id", socket.assigns.modal_list_id)

    case PlayContent.create_character(char_params) do
      {:ok, saved} ->
        LiveHelpers.log_activity(socket, "create", "character", saved.id, %{
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

  # An entry's line, and the character it names: its id, its actor, whether it is hidden.
  defp save_entry(socket, params) do
    %{editing: entry, entry_character: character} = socket.assigns

    with {:ok, character_attrs} <-
           character_changes(
             character,
             form_params(params, "character"),
             socket.assigns.original_choice
           ),
         {:ok, saved} <-
           PlayContent.update_entry(entry, form_params(params, "entry"),
             character: character && {character, character_attrs}
           ) do
      LiveHelpers.log_activity(socket, "update", "cast_list_entry", saved.id, %{name: saved.name})

      {:noreply,
       socket
       |> put_flash(:info, gettext("Character saved."))
       |> assign(modal: nil, form: nil, editing: nil, character_form: nil)
       |> reload_characters()}
    else
      {:error, %Ecto.Changeset{data: %Character{}} = changeset} ->
        {:noreply, assign(socket, character_form: to_form(changeset, as: :character))}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset, as: :entry))}
    end
  end

  defp character_changes(nil, _params, _choice), do: {:ok, nil}

  # The choice the form was opened with bounds what the select may send.
  defp character_changes(character, %{"original" => value} = params, choice) do
    case choice && correction(value, choice) do
      nil ->
        changeset =
          character
          |> PlayContent.change_character(params)
          |> Ecto.Changeset.add_error(:original, gettext("is no character of the original"))

        {:error, %{changeset | action: :update}}

      fields ->
        {:ok, Map.merge(Map.delete(params, "original"), fields)}
    end
  end

  defp character_changes(_character, params, _choice), do: {:ok, params}

  # Problem 5, step 3: which original character a translation's character goes with, for
  # the entry form's select: the rule's pick (`Alignment`), each character of the original
  # who speaks (a silent one is never paired), none, and a stored pointer the original no longer has, shown as missing. Only for a
  # translation or version with an original.
  defp original_choice(play, %Character{} = character) do
    if play.parent_play_id && Alignment.paired?(play) do
      original = PlayContent.load_play_content(play.parent_play_id)
      speakers = Alignment.speakers(original)

      originals =
        Enum.filter(PlayContent.list_characters(play.parent_play_id), &(&1.id in speakers))

      known = MapSet.new(originals, & &1.xml_id)

      automatic =
        original
        |> Alignment.character_pairs(PlayContent.load_play_content(play.id),
          automatic_for: character.id
        )
        |> Map.get(character.id)

      pick = automatic && Enum.find(originals, &(&1.id == automatic))
      stored = character.original_xml_id

      %{
        selected: if(character.no_original, do: "-", else: stored || ""),
        valid: MapSet.union(known, MapSet.new(["", "-", stored || ""])),
        options:
          [{automatic_label(pick), ""}] ++
            Enum.map(originals, &{InlineMarkup.plain(&1.name), &1.xml_id}) ++
            [{gettext("No original"), "-"}] ++
            if(stored && stored not in known,
              do: [{gettext("Missing: %{id}", id: stored), stored}],
              else: []
            )
      }
    end
  end

  defp original_choice(_play, nil), do: nil

  # The original character each speaking character goes with (nil: none), as the
  # comparison pairs them, for the list; nil for a play not paired with an original.
  defp original_pairs(play) do
    if play.parent_play_id && Alignment.paired?(play) do
      translation = PlayContent.load_play_content(play.id)

      pairs =
        PlayContent.load_play_content(play.parent_play_id)
        |> Alignment.character_pairs(translation)

      originals = Map.new(PlayContent.list_characters(play.parent_play_id), &{&1.id, &1})
      Map.new(Alignment.speakers(translation), &{&1, originals[pairs[&1]]})
    end
  end

  defp automatic_label(nil), do: gettext("Automatic (none found)")

  defp automatic_label(pick),
    do: gettext("Automatic (%{name})", name: InlineMarkup.plain(pick.name))

  defp correction(value, %{valid: valid}) do
    cond do
      not MapSet.member?(valid, value) -> nil
      value == "" -> %{"original_xml_id" => nil, "no_original" => false}
      value == "-" -> %{"original_xml_id" => nil, "no_original" => true}
      true -> %{"original_xml_id" => value, "no_original" => false}
    end
  end

  defp save_existing_entry(socket, params) do
    play_id = socket.assigns.play.id
    character = PlayContent.get_character(play_id, get_in(params, ["existing", "character_id"]))
    list = PlayContent.get_cast_list(play_id, socket.assigns.modal_list_id)

    if character && list do
      {:ok, entry} =
        PlayContent.create_entry(%{
          play_id: play_id,
          cast_list_id: list.id,
          character_id: character.id,
          name: character.name
        })

      LiveHelpers.log_activity(socket, "create", "cast_list_entry", entry.id, %{name: entry.name})

      {:noreply,
       socket
       |> put_flash(:info, gettext("Added to the list."))
       |> assign(modal: nil, form: nil)
       |> reload_characters()}
    else
      {:noreply, gone(socket)}
    end
  end

  defp save_division(socket, params) do
    div_params = form_params(params, "division")
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

  # The generic refusal, then the changeset's first error as the form would show it, a
  # colon between (the generic text's full stop would leave a lower-case clause after it).
  defp save_error(%{errors: errors}) do
    case List.last(errors) do
      nil ->
        gettext("Could not save element.")

      {_field, error} ->
        String.trim_trailing(gettext("Could not save element."), ".") <>
          ": " <> translate_error(error)
    end
  end

  defp save_element(socket, params) do
    el_params = form_params(params, "element")

    character_ids =
      own_character_ids(socket, List.wrap(params["character_ids"] || []))

    result =
      case socket.assigns.editing do
        nil ->
          el_params
          |> Map.merge(socket.assigns.new_element)
          |> PlayContent.create_element(characters: character_ids)

        element ->
          PlayContent.update_element(element, el_params, characters: character_ids)
      end

    case result do
      {:ok, el} ->
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

  @impl true
  # Archiving notifies too, so the play may be archived by now.
  def handle_info({:play_content_changed, _play_id}, socket) do
    play = Catalogue.get_play!(socket.assigns.play.id, include_deleted: true)

    {:noreply,
     socket
     |> assign(play: play)
     |> reload_paratexts()
     |> reload_characters()
     |> reload_divisions()
     |> reload_elements()
     |> reload_speeches()}
  end

  # The notes component's flash would stay in the component, so it asks for ours.
  def handle_info(:note_gone, socket), do: {:noreply, LiveHelpers.put_gone_flash(socket)}

  defp reload_paratexts(socket) do
    assign(socket, paratexts: Catalogue.list_paratexts(socket.assigns.play.id))
  end

  defp reload_characters(socket) do
    play_id = socket.assigns.play.id

    assign(socket,
      characters: PlayContent.list_characters(play_id),
      cast_lists: PlayContent.list_cast_lists(play_id),
      original_pairs: original_pairs(socket.assigns.play)
    )
  end

  defp reload_divisions(socket) do
    divisions = PlayContent.list_top_divisions(socket.assigns.play.id)
    assign(socket, divisions: divisions, removals: removals(divisions))
  end

  # How many characters deleting each cast list, or each division holding one, takes with
  # it: the count its confirmation gives.
  defp removals(divisions) do
    lists =
      for division <- divisions,
          row <- [division | division.children],
          row.type == "elenco",
          do: row

    holders =
      for division <- divisions,
          Enum.any?(division.children, &(&1.type == "elenco")),
          do: division

    Map.new(lists ++ holders, &{&1.id, PlayContent.deletion_effect(&1).removed})
  end

  # Every write to the text ends here, so the split verses' warning follows each at once.
  defp reload_elements(socket) do
    socket =
      case socket.assigns.selected_division_id do
        nil -> assign(socket, elements: [])
        div_id -> assign(socket, elements: PlayContent.list_elements_for_division(div_id))
      end

    socket
    |> assign(split_verses: PlayContent.split_verses_out_of_order(socket.assigns.play.id))
    |> reload_preview()
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

  # The speeches in reading order: act by act, an act's own before its scenes'. A position
  # counts within its division, so by itself it interleaves the acts.
  defp list_speeches(play_id) do
    import Ecto.Query
    alias Playcode.PlayContent.ElementCharacter

    ec_preload = from(ec in ElementCharacter, order_by: ec.position, preload: :character)

    rank =
      for {act, i} <- Enum.with_index(PlayContent.list_top_divisions(play_id)),
          {division, j} <- Enum.with_index([act | act.children]),
          into: %{},
          do: {division.id, {i, j}}

    Playcode.Repo.all(
      from e in Element,
        where: e.play_id == ^play_id and e.type == "speech",
        left_join: d in assoc(e, :division),
        preload: [element_characters: ^ec_preload, division: d]
    )
    |> Enum.sort_by(&{rank[&1.division_id], &1.position})
  end

  @doc "The character review's speeches, as its label and assignment filters leave them."
  def cr_filtered_speeches(assigns) do
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

  # Each speech's first words, plain: its first child's text or, when that is a line
  # group, which has none, the group's first line.
  defp load_first_child_contents(speech_ids) do
    first = first_children(speech_ids)

    lines =
      Map.new(first_children(for {_speech, id, nil} <- first, do: id), &Tuple.delete_at(&1, 1))

    Map.new(first, fn {speech, id, content} ->
      text = content || lines[id]
      {speech, text && InlineMarkup.plain(text)}
    end)
  end

  defp first_children(parent_ids) do
    import Ecto.Query

    Playcode.Repo.all(
      from e in Element,
        where: e.parent_id in ^parent_ids,
        distinct: e.parent_id,
        order_by: [e.parent_id, e.position],
        select: {e.parent_id, e.id, e.content}
    )
  end

  defp reload_preview(socket) do
    if socket.assigns.editor_tab == :preview do
      assign(socket, preview_divisions: PlayContent.load_play_content(socket.assigns.play.id))
    else
      socket
    end
  end

  defp extract_form_params(params, :paratext), do: params["paratext"] || %{}
  defp extract_form_params(params, :character), do: params["character"] || %{}
  defp extract_form_params(params, :division), do: params["division"] || %{}
  defp extract_form_params(params, :element), do: params["element"] || %{}
  defp extract_form_params(_params, _), do: %{}

  defp find_division(divisions, id) do
    Enum.find_value(divisions, fn div ->
      if div.id == id do
        div
      else
        Enum.find(div.children || [], &(&1.id == id))
      end
    end)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_header>{gettext("Content")}</.page_header>

      <div :if={@split_verses != []} class="alert alert-warning mb-6">
        <div>
          <p>
            {ngettext(
              "%{count} part of a split verse out of order:",
              "%{count} parts of split verses out of order:",
              length(@split_verses)
            )}
          </p>
          <ul class="ml-4 list-disc">
            <li :for={{line, problem} <- @split_verses}>
              <button type="button" class="link" phx-click="edit_element" phx-value-id={line.id}>
                <span :if={
                  line.line_number
                }>{gettext("v. %{number}", number: line.line_number)}</span>
                “{InlineMarkup.plain(line.content)}”
              </button>, {PlayLabels.split_verse_problem(
                problem,
                line.part
              )}
            </li>
          </ul>
        </div>
      </div>

      <div class="border-b border-base-300 mb-6">
        <nav class="-mb-px flex gap-1 overflow-x-auto" aria-label="Editor tabs">
          <.tab_button
            tab={:paratexts}
            label={gettext("Paratexts")}
            active={@editor_tab}
            icon="hero-document-text-mini"
            count={length(@paratexts)}
          />
          <.tab_button
            tab={:structure}
            label={gettext("Structure")}
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
            label={gettext("Content")}
            active={@editor_tab}
            icon="hero-document-text-mini"
            badge={
              if @selected_division_id,
                do: selected_division_short_label(@divisions, @selected_division_id)
            }
          />
          <.tab_button
            tab={:preview}
            label={gettext("Preview")}
            active={@editor_tab}
            icon="hero-eye-mini"
          />
        </nav>
      </div>

      <Paratexts.tab :if={@editor_tab == :paratexts} paratexts={@paratexts} />

      <Characters.tab
        :if={@editor_tab == :characters}
        characters={@characters}
        cast_lists={@cast_lists}
        divisions={@divisions}
        original_pairs={@original_pairs}
      />

      <Structure.tab
        :if={@editor_tab == :structure}
        paratexts={@paratexts}
        divisions={@divisions}
        removals={@removals}
        selected_division_id={@selected_division_id}
      />

      <CharacterReview.tab
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

      <Content.tab
        :if={@editor_tab == :content}
        content_search={@content_search}
        content_search_results={@content_search_results}
        selected_division_id={@selected_division_id}
        divisions={@divisions}
        elements={@elements}
        selected_elements={@selected_elements}
        characters={@characters}
        inline_editing_id={@inline_editing_id}
      />

      <Preview.tab :if={@editor_tab == :preview} preview_divisions={@preview_divisions} />

      <.modal :if={@modal} id="content-modal" on_cancel={JS.push("close_modal")}>
        <Paratexts.modal :if={@modal == :paratext} form={@form} editing={@editing} />
        <Structure.modal
          :if={@modal == :division}
          form={@form}
          editing={@editing}
          subdivision={if @editing, do: Map.get(@editing, :parent_id), else: @modal_parent_id}
          play_id={@play.id}
          user={@current_user}
        />
        <Characters.character_modal :if={@modal == :character} form={@form} editing={@editing} />
        <Characters.entry_modal
          :if={@modal == :entry}
          form={@form}
          character_form={@character_form}
          original_choice={@original_choice}
        />
        <Characters.existing_entry_modal
          :if={@modal == :existing_entry}
          form={@form}
          existing_options={@existing_options}
        />
        <Content.modal
          :if={@modal == :element}
          form={@form}
          editing={@editing}
          characters={@characters}
          modal_element_type={@modal_element_type}
          editing_character_ids={@editing_character_ids}
          manual_numbers={@play.numbering_manual}
          play_id={@play.id}
          user={@current_user}
        />
      </.modal>
    </.page>
    """
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

  defp preview_scroll_target(assigns) do
    case assigns.selected_division_id do
      nil -> nil
      id -> "div-#{id}"
    end
  end

  attr :tab, :atom, required: true
  attr :active, :atom, required: true
  attr :icon, :string, required: true
  attr :label, :string, required: true
  attr :count, :integer, default: nil
  attr :badge, :string, default: nil

  defp tab_button(assigns) do
    ~H"""
    <button
      phx-click="switch_tab"
      phx-value-tab={@tab}
      class={[
        "flex shrink-0 items-center gap-2 whitespace-nowrap px-4 py-2.5 text-sm font-medium border-b-2 transition-colors",
        if(@active == @tab,
          do: "border-primary text-primary",
          else:
            "border-transparent text-base-content/70 hover:text-base-content hover:border-base-300"
        )
      ]}
    >
      <.icon name={@icon} class="size-4" />
      <span>{@label}</span>
      <span :if={@count} class="badge badge-sm badge-ghost">{@count}</span>
      <span :if={@badge} class="badge badge-sm badge-primary">{@badge}</span>
    </button>
    """
  end
end
