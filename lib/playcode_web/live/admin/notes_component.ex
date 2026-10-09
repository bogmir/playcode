defmodule PlaycodeWeb.Admin.NotesComponent do
  @moduledoc """
  The notes on one line, speaker label or heading, in the content editor's modal for it:
  a list with Edit and Delete, and a form to add a note or change one. Each change is
  saved and logged at once, apart from the modal's own form, which a note's form cannot
  sit inside.
  """
  use PlaycodeWeb, :live_component

  alias Playcode.{ActivityLog, PlayContent}
  alias Playcode.PlayContent.{Division, Note}
  alias PlaycodeWeb.PlayLabels

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:editing, fn -> nil end)
     |> assign_new(:form, fn -> nil end)
     |> assign(:notes, PlayContent.list_notes(assigns.anchor))}
  end

  @impl true
  def handle_event("new_note", _params, socket) do
    note = %Note{offset: default_offset(socket.assigns.anchor)}
    {:noreply, assign(socket, editing: note, form: to_form(PlayContent.change_note(note)))}
  end

  def handle_event("edit_note", %{"id" => id}, socket) do
    case own_note(socket, id) do
      nil ->
        {:noreply, gone(socket)}

      note ->
        {:noreply, assign(socket, editing: note, form: to_form(PlayContent.change_note(note)))}
    end
  end

  def handle_event("cancel_note", _params, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  # A second submit (a double click, a second tab) of a form that has closed.
  def handle_event("save_note", _params, %{assigns: %{editing: nil}} = socket),
    do: {:noreply, socket}

  def handle_event("save_note", %{"note" => params}, socket) do
    %{editing: note, anchor: anchor, play_id: play_id} = socket.assigns
    params = Map.take(params, ~w(offset type term body))

    {action, result} =
      if note.id,
        do: {"update", PlayContent.update_note(note, params)},
        else:
          {"create", PlayContent.create_note(Map.merge(params, anchor_attrs(anchor, play_id)))}

    case result do
      {:ok, saved} ->
        log(socket, action, saved)
        {:noreply, assign(socket, editing: nil, form: nil, notes: PlayContent.list_notes(anchor))}

      {:error, changeset} ->
        if gone?(changeset),
          do: {:noreply, socket |> gone() |> assign(editing: nil, form: nil)},
          else: {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  def handle_event("delete_note", %{"id" => id}, socket) do
    case own_note(socket, id) do
      nil ->
        {:noreply, gone(socket)}

      note ->
        case PlayContent.delete_note(note) do
          {:ok, _} ->
            log(socket, "delete", note)
            {:noreply, assign(socket, notes: PlayContent.list_notes(socket.assigns.anchor))}

          {:error, _stale} ->
            {:noreply, gone(socket)}
        end
    end
  end

  # One of this anchor's notes: the id comes from the browser, and the list in the socket
  # may be stale, so it is read afresh.
  defp own_note(socket, id),
    do: socket.assigns.anchor |> PlayContent.list_notes() |> Enum.find(&(&1.id == id))

  # The note, or the line it hangs on, was deleted meanwhile (another tab, another
  # curator): Repo.update/delete's stale error, or the insert's foreign key.
  defp gone?(changeset) do
    Enum.any?(changeset.errors, fn {_field, {_message, opts}} ->
      opts[:stale] == true or opts[:constraint] == :foreign
    end)
  end

  # The note the event named is not this anchor's: the list reloads, and the editor says so
  # (LiveHelpers.put_gone_flash/1; a component's own flash would never be shown).
  defp gone(socket) do
    send(self(), :note_gone)
    assign(socket, notes: PlayContent.list_notes(socket.assigns.anchor))
  end

  # The anchor and the play are the server's, never the form's.
  defp anchor_attrs(%Division{id: id}, play_id), do: %{"play_id" => play_id, "division_id" => id}
  defp anchor_attrs(element, play_id), do: %{"play_id" => play_id, "element_id" => element.id}

  # A new note goes after the last word.
  defp default_offset(anchor) do
    case anchor |> PlayContent.anchor_text() |> Note.word_ends() do
      [] -> 0
      ends -> ends |> List.last() |> elem(1)
    end
  end

  @doc """
  Where `note` can go in `anchor`'s text, for a select: after each word; plus where the
  note is now when that is not after a word (an imported note after punctuation), so
  saving its text alone does not move it; or the end of an empty text. The admin's Notes
  tab offers the same choice.
  """
  def offset_options(anchor, %Note{offset: offset}) do
    ends = anchor |> PlayContent.anchor_text() |> Note.word_ends()

    cond do
      Enum.any?(ends, fn {_word, at} -> at == offset end) -> ends
      ends == [] -> [{gettext("At the end"), offset}]
      true -> Enum.sort_by([{gettext("Where it is now"), offset} | ends], &elem(&1, 1))
    end
  end

  defp log(socket, action, note) do
    ActivityLog.log!(%{
      user_id: socket.assigns.user.id,
      play_id: socket.assigns.play_id,
      action: action,
      resource_type: "note",
      resource_id: note.id,
      metadata: %{offset: note.offset, type: note.type}
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="mt-6 border-t border-base-300 pt-4" aria-label={gettext("Notes")}>
      <h4 class="font-semibold mb-2">{gettext("Notes")}</h4>
      <ul :if={@notes != []} class="space-y-2 mb-3">
        <li :for={note <- @notes} class="flex items-start gap-2 text-sm">
          <div class="flex-1">
            <span class="font-medium">{PlayLabels.note_type_label(note.type)}</span>
            <em :if={note.term}>{note.term}</em>
            <span class="text-base-content/60">{String.slice(note.body, 0, 80)}</span>
          </div>
          <button
            type="button"
            phx-click="edit_note"
            phx-value-id={note.id}
            phx-target={@myself}
            class="btn btn-ghost btn-xs"
          >
            {gettext("Edit")}
          </button>
          <button
            type="button"
            phx-click="delete_note"
            phx-value-id={note.id}
            phx-target={@myself}
            data-confirm={gettext("Delete this note?")}
            class="btn btn-ghost btn-xs text-error"
          >
            {gettext("Delete")}
          </button>
        </li>
      </ul>
      <p :if={@notes == [] and is_nil(@form)} class="text-sm text-base-content/50 mb-3">
        {gettext("No notes.")}
      </p>
      <button
        :if={is_nil(@form)}
        type="button"
        phx-click="new_note"
        phx-target={@myself}
        class="btn btn-sm"
      >
        {gettext("Add note")}
      </button>

      <.form
        :if={@form}
        for={@form}
        id="note-form"
        phx-submit="save_note"
        phx-target={@myself}
        class="space-y-3"
      >
        <.input
          field={@form[:type]}
          type="select"
          label={gettext("Type")}
          options={PlayLabels.note_type_options(@editing.type)}
        />
        <.input
          field={@form[:offset]}
          type="select"
          label={gettext("After")}
          options={offset_options(@anchor, @editing)}
        />
        <.input field={@form[:term]} type="text" label={gettext("Term")} />
        <.input field={@form[:body]} type="textarea" rows="4" label={gettext("Text")} />
        <div class="flex gap-2">
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
          <button
            type="button"
            phx-click="cancel_note"
            phx-target={@myself}
            class="btn btn-ghost btn-sm"
          >
            {gettext("Cancel")}
          </button>
        </div>
      </.form>
    </section>
    """
  end
end
