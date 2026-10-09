defmodule PlaycodeWeb.Admin.PlaySourcesLive do
  @moduledoc """
  /admin/plays/:id/sources: the printed sources the edition was made from.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Catalogue.PlaySource
  alias PlaycodeWeb.Admin.LiveHelpers

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)
    sources = Catalogue.list_play_sources(play.id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Sources")}")
     |> assign(:play, play)
     |> assign(:sources, sources)
     |> assign(:editing_source, nil)
     |> assign(:source_form, nil)
     |> assign(:play_context, %{play: play, active_tab: :sources})}
  end

  @impl true
  def handle_event("new_source", _, socket) do
    play = socket.assigns.play
    next_pos = length(socket.assigns.sources)

    changeset =
      Catalogue.change_play_source(%PlaySource{play_id: play.id, position: next_pos})

    {:noreply,
     socket
     |> assign(:editing_source, :new)
     |> assign(:source_form, to_form(changeset))}
  end

  def handle_event("edit_source", %{"id" => id}, socket) do
    case Catalogue.get_play_source(socket.assigns.play.id, id) do
      nil ->
        {:noreply, gone(socket)}

      source ->
        {:noreply,
         socket
         |> assign(:editing_source, source)
         |> assign(:source_form, to_form(Catalogue.change_play_source(source)))}
    end
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_source, nil)
     |> assign(:source_form, nil)}
  end

  def handle_event("validate_source", %{"play_source" => params}, socket) do
    changeset =
      case socket.assigns.editing_source do
        :new ->
          %PlaySource{play_id: socket.assigns.play.id}
          |> Catalogue.change_play_source(params)
          |> Map.put(:action, :validate)

        source ->
          source
          |> Catalogue.change_play_source(params)
          |> Map.put(:action, :validate)
      end

    {:noreply, assign(socket, :source_form, to_form(changeset))}
  end

  def handle_event("save_source", %{"play_source" => params}, socket) do
    case socket.assigns.editing_source do
      :new ->
        params = Map.put(params, "play_id", socket.assigns.play.id)

        case Catalogue.create_play_source(params) do
          {:ok, source} ->
            LiveHelpers.log_activity(socket, "create", "source", source.id, %{title: source.title})

            sources = Catalogue.list_play_sources(socket.assigns.play.id)

            {:noreply,
             socket
             |> assign(:sources, sources)
             |> assign(:editing_source, nil)
             |> assign(:source_form, nil)
             |> put_flash(:info, gettext("Source added."))}

          {:error, changeset} ->
            {:noreply, assign(socket, :source_form, to_form(changeset))}
        end

      source ->
        case Catalogue.update_play_source(source, params) do
          {:ok, updated} ->
            LiveHelpers.log_activity(socket, "update", "source", updated.id, %{
              title: updated.title
            })

            sources = Catalogue.list_play_sources(socket.assigns.play.id)

            {:noreply,
             socket
             |> assign(:sources, sources)
             |> assign(:editing_source, nil)
             |> assign(:source_form, nil)
             |> put_flash(:info, gettext("Source updated."))}

          {:error, changeset} ->
            {:noreply, assign(socket, :source_form, to_form(changeset))}
        end
    end
  end

  def handle_event("delete_source", %{"id" => id}, socket) do
    case Catalogue.get_play_source(socket.assigns.play.id, id) do
      nil -> {:noreply, gone(socket)}
      source -> {:noreply, delete_source(socket, source)}
    end
  end

  defp delete_source(socket, source) do
    {:ok, _} = Catalogue.delete_play_source(source)

    LiveHelpers.log_activity(socket, "delete", "source", source.id, %{title: source.title})

    socket
    |> assign(:sources, Catalogue.list_play_sources(socket.assigns.play.id))
    |> put_flash(:info, gettext("Source deleted."))
  end

  # The source the event named is not this play's: see LiveHelpers.put_gone_flash/1.
  defp gone(socket) do
    socket
    |> assign(:sources, Catalogue.list_play_sources(socket.assigns.play.id))
    |> LiveHelpers.put_gone_flash()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Bibliographic Sources")}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("Manage the bibliographic sources for this play.")}
          </p>
        </div>
        <button
          :if={@editing_source == nil}
          phx-click="new_source"
          class="btn btn-primary btn-sm gap-1"
        >
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add source")}
        </button>
      </div>

      <%!-- Source form (inline, shown when editing or adding) --%>
      <div
        :if={@source_form}
        class="mb-6 rounded-box border border-primary/30 bg-base-100 p-5 shadow-md"
      >
        <h3 class="mb-4 text-sm font-semibold text-primary">
          {if @editing_source == :new, do: gettext("New source"), else: gettext("Edit source")}
        </h3>
        <.form
          for={@source_form}
          id="source-form"
          phx-change="validate_source"
          phx-submit="save_source"
        >
          <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
            <div>
              <label class="label" for={@source_form[:title].id}>
                <span class="label-text font-medium">{gettext("Title")}</span>
              </label>
              <.input field={@source_form[:title]} type="text" />
            </div>
            <div>
              <label class="label" for={@source_form[:author].id}>
                <span class="label-text font-medium">{gettext("Author")}</span>
              </label>
              <.input field={@source_form[:author]} type="text" />
            </div>
            <div>
              <label class="label" for={@source_form[:editor].id}>
                <span class="label-text font-medium">{gettext("Editor")}</span>
              </label>
              <.input field={@source_form[:editor]} type="text" />
            </div>
            <div>
              <label class="label" for={@source_form[:editor_role].id}>
                <span class="label-text font-medium">{gettext("Editor role")}</span>
              </label>
              <.input
                field={@source_form[:editor_role]}
                type="text"
                placeholder={gettext("e.g. traductor")}
              />
            </div>
            <div>
              <label class="label" for={@source_form[:language].id}>
                <span class="label-text font-medium">{gettext("Language")}</span>
              </label>
              <.input field={@source_form[:language]} type="text" />
            </div>
            <div>
              <label class="label" for={@source_form[:publisher].id}>
                <span class="label-text font-medium">{gettext("Publisher")}</span>
              </label>
              <.input field={@source_form[:publisher]} type="text" />
            </div>
            <div>
              <label class="label" for={@source_form[:pub_place].id}>
                <span class="label-text font-medium">{gettext("Place")}</span>
              </label>
              <.input field={@source_form[:pub_place]} type="text" />
            </div>
            <div>
              <label class="label" for={@source_form[:pub_date].id}>
                <span class="label-text font-medium">{gettext("Date")}</span>
              </label>
              <.input field={@source_form[:pub_date]} type="text" />
            </div>
          </div>
          <div class="mt-4">
            <label class="label" for={@source_form[:note].id}>
              <span class="label-text font-medium">{gettext("Reference / citation")}</span>
            </label>
            <.input field={@source_form[:note]} type="textarea" rows="3" />
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
        :if={@sources == [] && @source_form == nil}
        class="text-center py-12 text-base-content/70"
      >
        <.icon name="hero-book-open" class="size-12 mx-auto mb-3 opacity-30" />
        <p class="text-sm">{gettext("No bibliographic sources yet.")}</p>
        <button phx-click="new_source" class="btn btn-ghost btn-sm mt-3">
          {gettext("Add the first source")}
        </button>
      </div>

      <%!-- Source cards --%>
      <div class="space-y-4">
        <div
          :for={source <- @sources}
          id={"source-#{source.id}"}
          class="rounded-box border border-base-300 bg-base-100 shadow-sm"
        >
          <div class="p-4">
            <div class="grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
              <span :if={source.title} class="font-medium text-base-content/70 text-right">
                {gettext("Title")}
              </span>
              <span :if={source.title}>{source.title}</span>

              <span :if={source.author} class="font-medium text-base-content/70 text-right">
                {gettext("Author")}
              </span>
              <span :if={source.author}>{source.author}</span>

              <span :if={source.editor} class="font-medium text-base-content/70 text-right">
                {gettext("Editor")}
              </span>
              <span :if={source.editor}>
                {source.editor}
                <span :if={source.editor_role} class="text-xs text-base-content/70">
                  ({source.editor_role})
                </span>
              </span>

              <span :if={source.publisher} class="font-medium text-base-content/70 text-right">
                {gettext("Publisher")}
              </span>
              <span :if={source.publisher}>{source.publisher}</span>

              <span :if={source.pub_place} class="font-medium text-base-content/70 text-right">
                {gettext("Place")}
              </span>
              <span :if={source.pub_place}>{source.pub_place}</span>

              <span :if={source.pub_date} class="font-medium text-base-content/70 text-right">
                {gettext("Date")}
              </span>
              <span :if={source.pub_date}>{source.pub_date}</span>

              <span :if={source.language} class="font-medium text-base-content/70 text-right">
                {gettext("Language")}
              </span>
              <span :if={source.language}>{source.language}</span>

              <span :if={source.note} class="font-medium text-base-content/70 text-right">
                {gettext("Reference")}
              </span>
              <span :if={source.note} class="text-xs text-base-content/80">{source.note}</span>
            </div>
          </div>
          <div class="flex justify-end gap-1 border-t border-base-300 px-3 py-2">
            <button
              phx-click="edit_source"
              phx-value-id={source.id}
              class="btn btn-ghost btn-xs gap-1"
            >
              <.icon name="hero-pencil-square-micro" class="size-3.5" /> {gettext("Edit")}
            </button>
            <button
              phx-click="delete_source"
              phx-value-id={source.id}
              data-confirm={gettext("Delete this source?")}
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
