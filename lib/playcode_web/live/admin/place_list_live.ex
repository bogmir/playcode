defmodule PlaycodeWeb.Admin.PlaceListLive do
  @moduledoc """
  /admin/places: the corpus-wide gazetteer: places, their names, what contains them and
  their authority links.
  """

  use PlaycodeWeb, :live_view

  # Stricter than the live_session's :view_admin, declared here so admin
  # sections still navigate without a full page reload.
  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :manage_places}}

  alias Playcode.ActivityLog
  alias Playcode.Places
  alias Playcode.Places.{Authority, Place}
  alias PlaycodeWeb.PlayLabels

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Places"))
     |> assign(:search, "")
     |> assign(:editing, nil)
     |> load_places()}
  end

  @impl true
  def handle_event("search", %{"search" => term}, socket) do
    {:noreply, socket |> assign(:search, term) |> load_places()}
  end

  def handle_event("new", _params, socket) do
    # One blank row so the form has a name input to fill in immediately, rather
    # than an empty fieldset with only an "Add name" button.
    {:noreply, assign(socket, :editing, %Place{names: [%Places.PlaceName{}]})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing, Places.get_place!(id))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :editing, nil)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    place = Places.get_place!(id)

    case Places.delete_place(place) do
      {:ok, _} ->
        ActivityLog.log!(%{
          user_id: socket.assigns.current_user.id,
          action: "delete",
          resource_type: "place",
          resource_id: place.id,
          metadata: %{slug: place.slug}
        })

        {:noreply, socket |> load_places() |> put_flash(:info, gettext("Place deleted."))}

      {:error, changeset} ->
        {:noreply, put_flash(socket, :error, delete_error(changeset))}
    end
  end

  defp delete_error(changeset) do
    cond do
      changeset.errors[:play_places] ->
        gettext("This place is still used by a play. Unlink it there first.")

      changeset.errors[:children] ->
        gettext("This place contains other places. Move them out first.")

      true ->
        gettext("This place could not be deleted.")
    end
  end

  defp load_places(socket) do
    gazetteer = Places.gazetteer()

    places =
      case socket.assigns.search do
        term when term in [nil, ""] -> Places.list_places()
        term -> Places.search_names(term)
      end

    socket |> assign(:places, places) |> assign(:gazetteer, gazetteer)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Places")}
          </h1>
          <p class="mt-1 text-sm text-base-content/60">
            {gettext("One record per place, shared by every play that references it.")}
          </p>
        </div>
        <button :if={is_nil(@editing)} phx-click="new" class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("New place")}
        </button>
      </div>

      <.live_component
        :if={@editing}
        module={PlaycodeWeb.Admin.PlaceFormComponent}
        id="place-form-component"
        place={@editing}
        current_user={@current_user}
        on_saved={fn _place -> send(self(), :place_saved) end}
      />

      <form phx-change="search" class="mb-4 mt-6">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search any name, in any language")}
          class="input input-bordered input-sm w-full max-w-md"
        />
      </form>

      <div :if={@places == []} class="py-12 text-center text-base-content/50">
        <.icon name="hero-map-pin" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No places yet.")}</p>
      </div>

      <table :if={@places != []} class="table table-sm">
        <thead>
          <tr>
            <th>{gettext("Place")}</th>
            <th>{gettext("Type")}</th>
            <th>{gettext("Authority")}</th>
            <th>{gettext("Plays")}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={place <- @places} id={"place-#{place.id}"}>
            <td>
              <span class="font-medium">{Places.display_name(place, "es")}</span>
              <span class="block text-xs text-base-content/50">
                {Places.breadcrumb(place, @gazetteer, "es")}
              </span>
            </td>
            <td>
              <span class="badge badge-ghost badge-sm">
                {PlayLabels.place_type_label(place.type)}
              </span>
              <span :if={place.is_fictional} class="badge badge-outline badge-sm">
                {gettext("Fictional")}
              </span>
            </td>
            <td class="text-xs">
              <a
                :if={Authority.url(place.authority, place.authority_id)}
                href={Authority.url(place.authority, place.authority_id)}
                target="_blank"
                class="link"
              >
                {place.authority_id}
              </a>
              <span :if={place.latitude} class="block text-base-content/50">
                {place.latitude}, {place.longitude}
              </span>
            </td>
            <td class="text-xs">{place.play_count}</td>
            <td class="text-right">
              <button phx-click="edit" phx-value-id={place.id} class="btn btn-ghost btn-xs">
                {gettext("Edit")}
              </button>
              <button
                phx-click="delete"
                phx-value-id={place.id}
                data-confirm={gettext("Delete this place?")}
                class="btn btn-ghost btn-xs text-error"
              >
                {gettext("Delete")}
              </button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @impl true
  def handle_info(:place_saved, socket) do
    {:noreply,
     socket
     |> assign(:editing, nil)
     |> load_places()
     |> put_flash(:info, gettext("Place saved."))}
  end
end
