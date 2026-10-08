defmodule PlaycodeWeb.Admin.PlayPlacesLive do
  @moduledoc """
  /admin/plays/:id/places: the play's place index: which gazetteer places, in what role and
  order, with a note each.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Catalogue
  alias Playcode.Places
  alias Playcode.Places.Authority
  alias Playcode.Places.Place
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Places")}")
     |> assign(:play, play)
     |> assign(:editing, nil)
     |> assign(:term, "")
     |> assign(:suggestions, [])
     |> assign(:picked, nil)
     |> assign(:initial_candidates, [])
     |> assign(:play_context, %{play: play, active_tab: :places})
     |> load_links()}
  end

  @impl true
  def handle_event("link", %{"place_id" => ""}, socket) do
    {:noreply, put_flash(socket, :error, gettext("Search for a place first."))}
  end

  def handle_event("link", %{"place_id" => place_id} = params, socket) do
    case Places.link_place(socket.assigns.play.id, place_id, %{
           "role" => params["role"] || "setting"
         }) do
      {:ok, link} ->
        log(socket, "create", link)

        {:noreply,
         socket
         |> assign(:picked, nil)
         |> assign(:term, "")
         |> assign(:suggestions, [])
         |> load_links()
         |> put_flash(:info, gettext("Place added."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("That place is already linked to this play."))}
    end
  end

  def handle_event("update_link", %{"link_id" => id, "play_place" => params}, socket) do
    with_link(socket, id, fn link ->
      case Places.update_play_place(link, params) do
        {:ok, updated} ->
          log(socket, "update", updated)
          socket |> load_links() |> put_flash(:info, gettext("Place updated."))

        {:error, _changeset} ->
          put_flash(socket, :error, gettext("That change could not be saved."))
      end
    end)
  end

  def handle_event("move_up", %{"id" => id}, socket) do
    with_link(socket, id, fn link ->
      :ok = Places.move_play_place(link, :up)
      load_links(socket)
    end)
  end

  def handle_event("move_down", %{"id" => id}, socket) do
    with_link(socket, id, fn link ->
      :ok = Places.move_play_place(link, :down)
      load_links(socket)
    end)
  end

  def handle_event("unlink", %{"id" => id}, socket) do
    with_link(socket, id, fn link ->
      {:ok, _} = Places.unlink_place(link)
      log(socket, "delete", link)
      socket |> load_links() |> put_flash(:info, gettext("Place removed."))
    end)
  end

  # The gazetteer is corpus-global, so listing every place in a <select> stops being
  # usable long before the corpus is fully imported. Search instead, and never offer a
  # place this play already has.
  def handle_event("search_places", %{"term" => term}, socket) do
    linked = MapSet.new(socket.assigns.links, & &1.place_id)

    suggestions =
      term
      |> Places.search_names(limit: 10)
      |> Enum.reject(&MapSet.member?(linked, &1.id))

    {:noreply, socket |> assign(:term, term) |> assign(:suggestions, suggestions)}
  end

  # A suggestion deleted from the gazetteer since the search clears the picker instead.
  def handle_event("pick_place", %{"id" => id}, socket) do
    socket = socket |> assign(:term, "") |> assign(:suggestions, [])

    case Places.get_place(id) do
      nil -> {:noreply, socket |> load_links() |> LiveHelpers.put_gone_flash()}
      place -> {:noreply, assign(socket, :picked, place)}
    end
  end

  def handle_event("clear_pick", _params, socket) do
    {:noreply, assign(socket, :picked, nil)}
  end

  def handle_event("new", _params, socket) do
    open_form(socket, %Place{names: [%Places.PlaceName{}]}, [])
  end

  # Opened from the picker's "create" row, so the name is already known. Running the
  # authority lookup here is what keeps a hand-added place from landing with no type and
  # no coordinates — the state that had London offering "continent".
  def handle_event("new_from_search", %{"name" => name}, socket) do
    place = %Place{
      names: [%Places.PlaceName{name: name, language: "es", is_preferred: true}]
    }

    open_form(socket, place, authority_candidates(name))
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  defp open_form(socket, place, candidates) do
    {:noreply,
     socket
     |> assign(:editing, place)
     |> assign(:initial_candidates, candidates)
     |> assign(:term, "")
     |> assign(:suggestions, [])}
  end

  defp authority_candidates(name) do
    case Authority.impl().search(name, locale: Gettext.get_locale(PlaycodeWeb.Gettext)) do
      {:ok, candidates} -> candidates
      {:error, _reason} -> []
    end
  end

  @impl true
  def handle_info({:place_saved, place}, socket) do
    {:ok, link} = Places.link_place(socket.assigns.play.id, place.id, %{})
    log(socket, "create", link)

    {:noreply,
     socket
     |> assign(:editing, nil)
     |> load_links()
     |> put_flash(:info, gettext("Place created and added."))}
  end

  defp log(socket, action, link) do
    LiveHelpers.log_activity(socket, action, "play_place", link.id, %{
      place_id: link.place_id,
      role: link.role
    })
  end

  # Runs `fun` on the play's link `id`. Another play's link, a removed one or a malformed id
  # changes nothing: the list reloads and says so (LiveHelpers.put_gone_flash/1).
  defp with_link(socket, id, fun) do
    case Places.get_play_place(socket.assigns.play.id, id) do
      nil -> {:noreply, socket |> load_links() |> LiveHelpers.put_gone_flash()}
      link -> {:noreply, fun.(link)}
    end
  end

  defp load_links(socket) do
    socket
    |> assign(:links, Places.list_play_places(socket.assigns.play.id))
    |> assign(:gazetteer, Places.gazetteer())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Places")}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("Where this play is set, and the places it names.")}
          </p>
        </div>
        <button :if={is_nil(@editing)} phx-click="new" class="btn btn-ghost btn-sm gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("New place")}
        </button>
      </div>

      <.live_component
        :if={@editing}
        module={PlaycodeWeb.Admin.PlaceFormComponent}
        id="place-form-component"
        place={@editing}
        current_user={@current_user}
        initial_candidates={@initial_candidates}
        on_saved={fn place -> send(self(), {:place_saved, place}) end}
      />

      <div :if={is_nil(@editing)} class="mb-6 mt-4">
        <label class="label">
          <span class="label-text font-medium">{gettext("Add an existing place")}</span>
        </label>
        <div class="flex items-end gap-2">
          <div class="relative grow">
            <%!-- Picked state: the place is chosen, only the role is left to set. --%>
            <div
              :if={@picked}
              class="input input-bordered input-sm flex h-auto min-h-8 items-center justify-between gap-2"
            >
              <span class="truncate text-sm">
                {Places.breadcrumb(@picked, @gazetteer, "es")}
              </span>
              <button
                type="button"
                phx-click="clear_pick"
                class="btn btn-circle btn-ghost btn-xs shrink-0"
                title={gettext("Clear")}
              >
                <.icon name="hero-x-mark-mini" class="size-3.5" />
              </button>
            </div>
            <%!-- Search state. A <select> of every place stops scaling well before the
                 corpus is fully imported, so this searches names in any language. --%>
            <form :if={is_nil(@picked)} phx-change="search_places">
              <input
                type="text"
                name="term"
                value={@term}
                phx-debounce="200"
                placeholder={gettext("Search any name, in any language")}
                class="input input-bordered input-sm w-full"
                autocomplete="off"
              />
            </form>
            <ul
              :if={@suggestions != []}
              class="rounded-box absolute z-20 mt-1 max-h-64 w-full overflow-y-auto border border-base-300 bg-base-100 shadow-lg"
            >
              <li :for={place <- @suggestions}>
                <button
                  type="button"
                  phx-click="pick_place"
                  phx-value-id={place.id}
                  class="w-full px-3 py-2 text-left transition-colors hover:bg-base-200"
                >
                  <div class="truncate text-sm font-medium">
                    {Places.display_name(place, "es")}
                  </div>
                  <div class="mt-0.5 truncate text-xs text-base-content/50">
                    {Places.breadcrumb(place, @gazetteer, "es")}
                  </div>
                </button>
              </li>
            </ul>
          </div>
          <form phx-submit="link" class="flex items-end gap-2">
            <input type="hidden" name="place_id" value={(@picked && @picked.id) || ""} />
            <div class="w-40">
              <label class="label">
                <span class="label-text font-medium">{gettext("Role")}</span>
              </label>
              <select name="role" class="select select-bordered select-sm w-full">
                <option :for={{label, value} <- PlayLabels.place_role_options()} value={value}>
                  {label}
                </option>
              </select>
            </div>
            <button type="submit" disabled={is_nil(@picked)} class="btn btn-primary btn-sm">
              {gettext("Add")}
            </button>
          </form>
        </div>
        <%!-- Nothing matched: offer to create it rather than making the curator leave,
             carrying the term across so the name is already typed. --%>
        <div
          :if={is_nil(@picked) and @term != "" and @suggestions == []}
          class="mt-2 flex items-center gap-2 text-xs text-base-content/60"
        >
          <span>{gettext("No places found")}</span>
          <button
            type="button"
            phx-click="new_from_search"
            phx-value-name={@term}
            class="btn btn-outline btn-xs gap-1"
          >
            <.icon name="hero-plus-mini" class="size-3.5" />
            {gettext("Create %{name}", name: @term)}
          </button>
        </div>
      </div>

      <div :if={@links == []} class="py-12 text-center text-base-content/50">
        <.icon name="hero-map-pin" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No places recorded for this play.")}</p>
      </div>

      <div class="space-y-3">
        <div
          :for={link <- @links}
          id={"link-#{link.id}"}
          class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm"
        >
          <div class="mb-2 flex items-start justify-between gap-3">
            <div>
              <span class="font-medium">{Places.display_name(link.place, "es")}</span>
              <span class="block text-xs text-base-content/50">
                {Places.breadcrumb(link.place, @gazetteer, "es")}
              </span>
            </div>
            <div class="flex gap-1">
              <button phx-click="move_up" phx-value-id={link.id} class="btn btn-ghost btn-xs">
                <.icon name="hero-arrow-up-micro" class="size-3.5" />
              </button>
              <button phx-click="move_down" phx-value-id={link.id} class="btn btn-ghost btn-xs">
                <.icon name="hero-arrow-down-micro" class="size-3.5" />
              </button>
              <button
                phx-click="unlink"
                phx-value-id={link.id}
                data-confirm={gettext("Remove this place from the play?")}
                class="btn btn-ghost btn-xs text-error"
              >
                {gettext("Remove")}
              </button>
            </div>
          </div>

          <form
            phx-submit="update_link"
            id={"link-form-#{link.id}"}
            class="flex flex-wrap items-end gap-2"
          >
            <input type="hidden" name="link_id" value={link.id} />
            <div class="w-40">
              <select name="play_place[role]" class="select select-bordered select-sm w-full">
                <option
                  :for={{label, value} <- PlayLabels.place_role_options()}
                  value={value}
                  selected={link.role == value}
                >
                  {label}
                </option>
              </select>
            </div>
            <div class="grow">
              <input
                type="text"
                name="play_place[note]"
                value={link.note}
                placeholder={gettext("Note, e.g. Act III only")}
                class="input input-bordered input-sm w-full"
              />
            </div>
            <button type="submit" class="btn btn-ghost btn-sm">{gettext("Save")}</button>
          </form>
        </div>
      </div>
    </div>
    """
  end
end
