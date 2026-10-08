defmodule PlaycodeWeb.Admin.PlayEditorsLive do
  @moduledoc """
  /admin/plays/:id/editors: the play's credited editors and translators.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Catalogue.PlayEditor
  alias Playcode.ActivityLog
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)
    editors = Catalogue.list_play_editors(play.id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Editors")}")
     |> assign(:play, play)
     |> assign(:editors, editors)
     |> assign(:editing_editor, nil)
     |> assign(:editor_form, nil)
     |> assign(:play_context, %{play: play, active_tab: :editors})}
  end

  @impl true
  def handle_event("new_editor", _, socket) do
    play = socket.assigns.play
    next_pos = length(socket.assigns.editors)

    changeset =
      Catalogue.change_play_editor(%PlayEditor{play_id: play.id, position: next_pos})

    {:noreply,
     socket
     |> assign(:editing_editor, :new)
     |> assign(:editor_form, to_form(changeset))}
  end

  def handle_event("edit_editor", %{"id" => id}, socket) do
    case Catalogue.get_play_editor(socket.assigns.play.id, id) do
      nil ->
        {:noreply, gone(socket)}

      editor ->
        {:noreply,
         socket
         |> assign(:editing_editor, editor)
         |> assign(:editor_form, to_form(Catalogue.change_play_editor(editor)))}
    end
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_editor, nil)
     |> assign(:editor_form, nil)}
  end

  def handle_event("validate_editor", %{"play_editor" => params}, socket) do
    changeset =
      case socket.assigns.editing_editor do
        :new ->
          %PlayEditor{play_id: socket.assigns.play.id}
          |> Catalogue.change_play_editor(params)
          |> Map.put(:action, :validate)

        editor ->
          editor
          |> Catalogue.change_play_editor(params)
          |> Map.put(:action, :validate)
      end

    {:noreply, assign(socket, :editor_form, to_form(changeset))}
  end

  def handle_event("save_editor", %{"play_editor" => params}, socket) do
    case socket.assigns.editing_editor do
      :new ->
        params = Map.put(params, "play_id", socket.assigns.play.id)

        case Catalogue.create_play_editor(params) do
          {:ok, editor} ->
            ActivityLog.log!(%{
              user_id: socket.assigns.current_user.id,
              play_id: socket.assigns.play.id,
              action: "create",
              resource_type: "editor",
              resource_id: editor.id,
              metadata: %{person_name: editor.person_name, role: editor.role}
            })

            editors = Catalogue.list_play_editors(socket.assigns.play.id)

            {:noreply,
             socket
             |> assign(:editors, editors)
             |> assign(:editing_editor, nil)
             |> assign(:editor_form, nil)
             |> put_flash(:info, gettext("Editor added."))}

          {:error, changeset} ->
            {:noreply, assign(socket, :editor_form, to_form(changeset))}
        end

      editor ->
        case Catalogue.update_play_editor(editor, params) do
          {:ok, updated} ->
            ActivityLog.log!(%{
              user_id: socket.assigns.current_user.id,
              play_id: socket.assigns.play.id,
              action: "update",
              resource_type: "editor",
              resource_id: updated.id,
              metadata: %{person_name: updated.person_name, role: updated.role}
            })

            editors = Catalogue.list_play_editors(socket.assigns.play.id)

            {:noreply,
             socket
             |> assign(:editors, editors)
             |> assign(:editing_editor, nil)
             |> assign(:editor_form, nil)
             |> put_flash(:info, gettext("Editor updated."))}

          {:error, changeset} ->
            {:noreply, assign(socket, :editor_form, to_form(changeset))}
        end
    end
  end

  def handle_event("delete_editor", %{"id" => id}, socket) do
    case Catalogue.get_play_editor(socket.assigns.play.id, id) do
      nil -> {:noreply, gone(socket)}
      editor -> {:noreply, delete_editor(socket, editor)}
    end
  end

  defp delete_editor(socket, editor) do
    {:ok, _} = Catalogue.delete_play_editor(editor)

    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      play_id: socket.assigns.play.id,
      action: "delete",
      resource_type: "editor",
      resource_id: editor.id,
      metadata: %{person_name: editor.person_name, role: editor.role}
    })

    socket
    |> assign(:editors, Catalogue.list_play_editors(socket.assigns.play.id))
    |> put_flash(:info, gettext("Editor deleted."))
  end

  # The editor the event named is not this play's: see LiveHelpers.put_gone_flash/1.
  defp gone(socket) do
    socket
    |> assign(:editors, Catalogue.list_play_editors(socket.assigns.play.id))
    |> LiveHelpers.put_gone_flash()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Editors & Researchers")}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("Manage the editorial team for this play.")}
          </p>
        </div>
        <button
          :if={@editing_editor == nil}
          phx-click="new_editor"
          class="btn btn-primary btn-sm gap-1"
        >
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add editor")}
        </button>
      </div>

      <%!-- Editor form (inline, shown when editing or adding) --%>
      <div
        :if={@editor_form}
        class="mb-6 rounded-box border border-primary/30 bg-base-100 p-5 shadow-md"
      >
        <h3 class="mb-4 text-sm font-semibold text-primary">
          {if @editing_editor == :new, do: gettext("New editor"), else: gettext("Edit editor")}
        </h3>
        <.form
          for={@editor_form}
          id="editor-form"
          phx-change="validate_editor"
          phx-submit="save_editor"
        >
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Name")} *</span>
              </label>
              <.input field={@editor_form[:person_name]} type="text" required />
            </div>
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Role")} *</span>
              </label>
              <.input
                field={@editor_form[:role]}
                type="select"
                options={PlayLabels.editor_role_options()}
                required
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Organization")}</span>
              </label>
              <.input
                field={@editor_form[:organization]}
                type="text"
                placeholder={gettext("University or institution")}
              />
            </div>
            <div>
              <label class="label">
                <span class="label-text font-medium">{gettext("Position")}</span>
              </label>
              <.input
                field={@editor_form[:position]}
                type="number"
                placeholder="0"
              />
            </div>
          </div>
          <div class="mt-4 flex gap-2 justify-end">
            <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">
              {gettext("Save")}
            </button>
          </div>
        </.form>
      </div>

      <%!-- Empty state --%>
      <div
        :if={@editors == [] && @editor_form == nil}
        class="text-center py-12 text-base-content/50"
      >
        <.icon name="hero-users" class="size-12 mx-auto mb-3 opacity-30" />
        <p class="text-sm">{gettext("No editors listed yet.")}</p>
        <button phx-click="new_editor" class="btn btn-ghost btn-sm mt-3">
          {gettext("Add the first editor")}
        </button>
      </div>

      <%!-- Editor cards --%>
      <div class="space-y-3">
        <div
          :for={editor <- @editors}
          id={"editor-#{editor.id}"}
          class="rounded-box border border-base-300 bg-base-100 shadow-sm"
        >
          <div class="flex items-center gap-4 p-4">
            <div class="flex-1 min-w-0">
              <p class="font-medium text-base-content truncate">{editor.person_name}</p>
              <p class="text-sm text-base-content/60">
                {PlayLabels.editor_role_label(editor.role)}
                <span :if={editor.organization} class="text-base-content/40">
                  — {editor.organization}
                </span>
              </p>
            </div>
            <span class="text-xs text-base-content/30 shrink-0">#{editor.position}</span>
          </div>
          <div class="flex justify-end gap-1 border-t border-base-300 px-3 py-2">
            <button
              phx-click="edit_editor"
              phx-value-id={editor.id}
              class="btn btn-ghost btn-xs gap-1"
            >
              <.icon name="hero-pencil-square-micro" class="size-3.5" /> {gettext("Edit")}
            </button>
            <button
              phx-click="delete_editor"
              phx-value-id={editor.id}
              data-confirm={gettext("Delete this editor?")}
              class="btn btn-ghost btn-xs text-error gap-1"
            >
              <.icon name="hero-trash-micro" class="size-3.5" /> {gettext("Delete")}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
