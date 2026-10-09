defmodule PlaycodeWeb.Admin.PlayNotesLive do
  @moduledoc """
  A play's in-text notes, listed in reading order and edited where they are listed: type,
  the word each follows, term and text. Adding a note stays in the content editor, where
  its line is chosen; each note links there. Spec:
  docs/superpowers/specs/2026-10-10-admin-notes-tab-design.md.
  """
  use PlaycodeWeb, :live_view

  alias Playcode.{Bibliography, Catalogue, PlayContent}
  alias Playcode.PlayContent.{Division, InlineMarkup, Note}
  alias PlaycodeWeb.Admin.{LiveHelpers, NotesComponent}
  alias PlaycodeWeb.Components.PlayText
  alias Phoenix.LiveView.JS
  alias PlaycodeWeb.PlayLabels

  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :edit_content}}

  # How much of the text a note hangs on its row shows, before and after the note.
  @context_before 60
  @context_after 40

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)
    if connected?(socket), do: PlayContent.subscribe(play.id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Notes")}")
     |> assign(:play, play)
     |> assign(:play_context, %{play: play, active_tab: :notes})
     |> assign(filter: %{"type" => "", "q" => "", "no_term" => "false"}, editing: nil, form: nil)
     |> load()}
  end

  @impl true
  def handle_event("filter", %{"filter" => filter}, socket),
    do: {:noreply, assign(socket, :filter, Map.merge(socket.assigns.filter, filter))}

  def handle_event("edit", %{"id" => id}, socket) do
    case PlayContent.get_note(socket.assigns.play.id, id) do
      nil -> {:noreply, gone(socket)}
      note -> {:noreply, open_form(socket, note)}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, close_form(socket)}

  # A second submit (a double click) of a form that has closed.
  def handle_event("save", _params, %{assigns: %{editing: nil}} = socket), do: {:noreply, socket}

  def handle_event("save", %{"note" => params}, socket) do
    note = socket.assigns.editing

    case PlayContent.update_note(note, Map.take(params, ~w(offset type term body))) do
      {:ok, saved} ->
        log(socket, "update", saved)

        {:noreply, socket |> close_form() |> load() |> put_flash(:info, gettext("Note saved."))}

      {:error, changeset} ->
        if stale?(changeset),
          do: {:noreply, socket |> close_form() |> gone()},
          else: {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with %Note{} = note <- PlayContent.get_note(socket.assigns.play.id, id),
         {:ok, _} <- PlayContent.delete_note(note) do
      log(socket, "delete", note)
      {:noreply, socket |> close_form() |> load() |> put_flash(:info, gettext("Note deleted."))}
    else
      _gone -> {:noreply, gone(socket)}
    end
  end

  # Someone changed the play (here, in another tab, in the content editor): an open form
  # stays open while its note is still there.
  @impl true
  def handle_info({:play_content_changed, _play_id}, socket) do
    socket = load(socket)

    case socket.assigns.editing do
      %Note{id: id} ->
        if Enum.any?(socket.assigns.entries, &(&1.note.id == id)),
          do: {:noreply, socket},
          else: {:noreply, close_form(socket)}

      nil ->
        {:noreply, socket}
    end
  end

  defp load(socket) do
    entries = socket.assigns.play.id |> PlayContent.load_play_content() |> PlayText.note_entries()
    assign(socket, :entries, entries)
  end

  defp open_form(socket, note) do
    anchor = Enum.find_value(socket.assigns.entries, &(&1.note.id == note.id && &1.anchor))
    assign(socket, editing: note, anchor: anchor, form: to_form(PlayContent.change_note(note)))
  end

  defp close_form(socket), do: assign(socket, editing: nil, anchor: nil, form: nil)

  defp gone(socket), do: socket |> load() |> LiveHelpers.put_gone_flash()

  defp stale?(changeset),
    do: Enum.any?(changeset.errors, fn {_field, {_message, opts}} -> opts[:stale] == true end)

  defp log(socket, action, note),
    do:
      LiveHelpers.log_activity(socket, action, "note", note.id, %{
        offset: note.offset,
        type: note.type
      })

  defp shown(entries, %{"type" => type, "q" => q, "no_term" => no_term}) do
    q = Bibliography.fold(q)

    Enum.filter(entries, fn %{note: note} ->
      (type == "" or PlayLabels.note_type_key(note.type) == type) and
        (q == "" or String.contains?(Bibliography.fold("#{note.body} #{note.term}"), q)) and
        (no_term != "true" or note.term in [nil, ""])
    end)
  end

  defp type_options(entries) do
    entries
    |> Enum.map(&PlayLabels.note_type_key(&1.note.type))
    |> Enum.uniq()
    |> Enum.map(&{type_label(&1), &1})
  end

  defp type_label("other"), do: PlayLabels.note_type_label(nil)
  defp type_label(type), do: PlayLabels.note_type_label(type)

  # The plain text the note hangs on, cut around the note: {before, after}.
  defp context(%{note: note, anchor: anchor}) do
    text = anchor |> PlayContent.anchor_text() |> InlineMarkup.plain()
    {before, after_note} = String.split_at(text, note.offset)

    before =
      if String.length(before) > @context_before,
        do: "…" <> String.slice(before, -@context_before, @context_before),
        else: before

    after_note =
      if String.length(after_note) > @context_after,
        do: String.slice(after_note, 0, @context_after) <> "…",
        else: after_note

    {before, after_note}
  end

  defp content_path(play, %Division{id: id}),
    do: ~p"/admin/plays/#{play.id}/content?division=#{id}"

  defp content_path(play, anchor), do: ~p"/admin/plays/#{play.id}/content?element=#{anchor.id}"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, shown(assigns.entries, assigns.filter))

    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <header class="mb-6">
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">{gettext("Notes")}</h1>
        <p class="mt-1 max-w-2xl text-sm text-base-content/60">
          {gettext(
            "Every note in the play's text, in reading order. Edit a note where it is listed; add notes to a line in Content."
          )}
        </p>
      </header>

      <div
        :if={@entries == []}
        class="rounded-box border border-dashed border-base-300 py-14 text-center text-base-content/60"
      >
        <.icon name="hero-chat-bubble-bottom-center-text" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No notes yet. Add them to a line in Content.")}</p>
        <.link navigate={~p"/admin/plays/#{@play.id}/content"} class="btn btn-ghost btn-sm mt-3">
          {gettext("Open Content")}
        </.link>
      </div>

      <form
        :if={@entries != []}
        id="notes-filter"
        phx-change="filter"
        phx-submit="filter"
        class="z-10 -mx-4 mb-6 flex flex-wrap items-center gap-3 border-b border-base-300 bg-base-100/90 px-4 py-2 backdrop-blur-sm sm:sticky sm:top-10"
      >
        <select
          name="filter[type]"
          aria-label={gettext("Note type")}
          class="select select-sm select-bordered w-auto"
        >
          <option value="" selected={@filter["type"] == ""}>{gettext("All types")}</option>
          <option
            :for={{label, key} <- type_options(@entries)}
            value={key}
            selected={@filter["type"] == key}
          >
            {label}
          </option>
        </select>
        <label class="input input-sm input-bordered flex items-center gap-2 sm:w-64">
          <.icon name="hero-magnifying-glass-mini" class="size-4 opacity-50" />
          <input
            type="search"
            name="filter[q]"
            value={@filter["q"]}
            phx-debounce="200"
            placeholder={gettext("Search the notes")}
            aria-label={gettext("Search the notes")}
            class="grow"
          />
        </label>
        <label class="label cursor-pointer gap-2 text-sm">
          <input type="hidden" name="filter[no_term]" value="false" />
          <input
            type="checkbox"
            name="filter[no_term]"
            value="true"
            checked={@filter["no_term"] == "true"}
            class="checkbox checkbox-sm"
          />
          {gettext("Without a term")}
        </label>
        <span id="notes-count" class="ml-auto text-sm tabular-nums text-base-content/60">
          {if length(@shown) == length(@entries),
            do: ngettext("1 note", "%{count} notes", length(@entries)),
            else:
              gettext("%{shown} of %{total} notes", shown: length(@shown), total: length(@entries))}
        </span>
      </form>

      <p :if={@entries != [] and @shown == []} class="py-10 text-center text-sm text-base-content/60">
        {gettext("Nothing matches the filter.")}
      </p>

      <ol id="notes" class="space-y-1">
        <li
          :for={entry <- @shown}
          id={"note-#{entry.note.id}"}
          class={[
            "group -mx-3 flex gap-4 rounded-lg px-3 py-3 transition",
            if(@editing && @editing.id == entry.note.id,
              do: "bg-base-100 ring-1 ring-primary/30 shadow-md",
              else: "hover:bg-base-200/60"
            )
          ]}
        >
          <span class="note-number w-8 shrink-0 pt-0.5 text-right text-sm font-semibold tabular-nums text-primary">
            {entry.note.number}
          </span>
          <div class="min-w-0 flex-1">
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
              <span class="note-type badge badge-ghost badge-sm">
                {PlayLabels.note_type_label(entry.note.type)}
              </span>
              <i :if={entry.glossed} class="note-glossed font-serif text-sm text-base-content">
                {entry.glossed}
              </i>
              <span class="note-where text-base-content/55">{entry.where}</span>
            </div>
            <% {before, after_note} = context(entry) %>
            <p
              class="note-context mt-1.5 border-l-2 border-base-300 pl-3 font-serif text-sm text-base-content/60"
              phx-no-format
            >{before}<sup class="px-0.5 font-sans font-semibold text-primary">{entry.note.number}</sup>{after_note}</p>

            <.form
              :if={@editing && @editing.id == entry.note.id}
              for={@form}
              id="note-form"
              phx-submit="save"
              class="mt-3 space-y-3"
            >
              <div class="grid gap-3 sm:grid-cols-3">
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
                  options={NotesComponent.offset_options(@anchor, @editing)}
                />
                <.input field={@form[:term]} type="text" label={gettext("Term")} />
              </div>
              <.input field={@form[:body]} type="textarea" rows="8" label={gettext("Text")} />
              <p class="text-xs text-base-content/50">
                {gettext("A blank line starts a new paragraph; <<…>> marks italics.")}
              </p>
              <div class="flex justify-end gap-2">
                <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">
                  {gettext("Cancel")}
                </button>
                <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
              </div>
            </.form>

            <div
              :if={is_nil(@editing) or @editing.id != entry.note.id}
              id={"note-body-#{entry.note.id}"}
              phx-click={JS.toggle_class("line-clamp-4", to: "#note-body-#{entry.note.id}")}
              title={gettext("Click to show or hide the whole note")}
              class="note-body line-clamp-4 mt-2 cursor-pointer space-y-1.5 text-[15px] leading-relaxed text-base-content"
            >
              <p :for={paragraph <- Note.paragraphs(entry.note)}><.marked text={paragraph} /></p>
            </div>
          </div>
          <div
            :if={is_nil(@editing) or @editing.id != entry.note.id}
            class="flex shrink-0 items-start gap-1 opacity-70 transition group-hover:opacity-100"
          >
            <.link
              navigate={content_path(@play, entry.anchor)}
              class="btn btn-ghost btn-xs gap-1"
              title={gettext("Open in Content")}
            >
              <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" />
              <span class="hidden sm:inline">{gettext("Open in Content")}</span>
            </.link>
            <button
              type="button"
              phx-click="edit"
              phx-value-id={entry.note.id}
              class="btn btn-ghost btn-xs gap-1"
            >
              <.icon name="hero-pencil-square-mini" class="size-3.5" /> {gettext("Edit")}
            </button>
            <button
              type="button"
              phx-click="delete"
              phx-value-id={entry.note.id}
              data-confirm={gettext("Delete this note?")}
              class="btn btn-ghost btn-xs gap-1 text-error"
            >
              <.icon name="hero-trash-mini" class="size-3.5" /> {gettext("Delete")}
            </button>
          </div>
        </li>
      </ol>
    </div>
    """
  end

  attr :text, :string, required: true

  # A paragraph with its <<…>> italics as emphasis; one line, so no space slips in.
  defp marked(assigns) do
    assigns = assign(assigns, :parts, InlineMarkup.parts(assigns.text))

    ~H"""
    <%= for part <- @parts do %>
      <%= if part.italic do %>
        <em>{part.text}</em>
      <% else %>
        {part.text}
      <% end %>
    <% end %>
    """
  end
end
