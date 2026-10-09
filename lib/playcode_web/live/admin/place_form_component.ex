defmodule PlaycodeWeb.Admin.PlaceFormComponent do
  @moduledoc """
  The one place-editing surface, used by the gazetteer page and the per-play page.

  A `LiveComponent` rather than this repo's usual inline form because two pages need
  the identical form *and* its events; the alternative is duplicating create, update,
  authority-search and name-row handlers in both LiveViews.
  """

  use PlaycodeWeb, :live_component

  alias Playcode.Places
  alias Playcode.Places.Authority
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @impl true
  def update(%{place: place} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:form, to_form(Places.change_place(place)))
     # Seeded, not assigned: the per-play picker can open this form with the authority
     # already searched for the name the curator typed. `assign_new` runs on mount only,
     # so the component owns `candidates` from then on and a parent re-render cannot
     # clobber a search the curator ran here.
     |> assign_new(:candidates, fn -> Map.get(assigns, :initial_candidates, []) end)
     |> assign_new(:authority_error, fn -> nil end)
     |> assign_new(:duplicate, fn -> nil end)
     |> assign_new(:duplicate_chain, fn -> nil end)
     |> assign(:parent_options, parent_options(place))}
  end

  @impl true
  def handle_event("validate", %{"place" => params}, socket) do
    changeset =
      socket.assigns.place
      |> Places.change_place(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:form, to_form(changeset)) |> assign_duplicate(params)}
  end

  def handle_event("save", %{"place" => params}, socket) do
    save(socket, socket.assigns.place.id, params)
  end

  def handle_event("authority_search", %{"term" => term}, socket) do
    case Authority.impl().search(term, locale: Gettext.get_locale(PlaycodeWeb.Gettext)) do
      {:ok, candidates} ->
        {:noreply, socket |> assign(:candidates, candidates) |> assign(:authority_error, nil)}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:candidates, [])
         |> assign(
           :authority_error,
           gettext("The authority is unavailable. Enter the details by hand.")
         )}
    end
  end

  def handle_event("authority_select", %{"authority-id" => id}, socket) do
    case Authority.impl().fetch(id) do
      {:ok, details} ->
        params = merge_authority(socket.assigns.form.params, id, details)

        changeset =
          socket.assigns.place
          |> Places.change_place(params)
          |> Map.put(:action, :validate)

        {:noreply, socket |> assign(:form, to_form(changeset)) |> assign(:candidates, [])}

      {:error, _reason} ->
        {:noreply,
         assign(
           socket,
           :authority_error,
           gettext("The authority is unavailable. Enter the details by hand.")
         )}
    end
  end

  defp save(socket, nil, params) do
    case Places.create_place(params) do
      {:ok, place} ->
        log(socket, "create", place)
        socket.assigns.on_saved.(place)
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save(socket, _id, params) do
    case Places.update_place(socket.assigns.place, params) do
      {:ok, place} ->
        log(socket, "update", place)
        socket.assigns.on_saved.(place)
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp log(socket, action, place) do
    LiveHelpers.log_activity(socket, action, "place", place.id, %{slug: place.slug})
  end

  # One Wikidata click seeds a name row per language it knows, which is the whole point
  # of a names layer the curator would otherwise fill in four submissions.
  defp merge_authority(params, id, details) do
    names =
      details.labels
      |> Enum.sort_by(fn {language, _} -> language end)
      |> Enum.with_index()
      |> Map.new(fn {{language, value}, index} ->
        {to_string(index),
         %{
           "name" => value,
           "language" => language,
           "is_preferred" => "true",
           "position" => to_string(index)
         }}
      end)

    params
    |> Map.merge(%{
      "authority" => "wikidata",
      "authority_id" => id,
      "names" => names
    })
    |> maybe_put("latitude", details.latitude)
    |> maybe_put("longitude", details.longitude)
    |> maybe_put("type", details.type_hint)
  end

  defp maybe_put(params, _key, nil), do: params
  defp maybe_put(params, key, value), do: Map.put(params, key, to_string(value))

  # Toledo (Spain) and Toledo (Ohio) are both real, so the warning has to let a curator
  # tell a legitimate namesake from the same place entered twice — which means naming the
  # container, not just the place. The chain is resolved only when the matched place
  # *changes*, so holding a duplicate name on screen does not re-read the gazetteer on
  # every keystroke.
  defp assign_duplicate(socket, params) do
    case duplicate_for(params, socket.assigns.place) do
      nil ->
        assign(socket, duplicate: nil, duplicate_chain: nil)

      found ->
        if socket.assigns.duplicate && socket.assigns.duplicate.id == found.id do
          socket
        else
          assign(socket,
            duplicate: found,
            duplicate_chain: Places.breadcrumb(found, Places.gazetteer(), "es")
          )
        end
    end
  end

  # ponytail: one indexed find_by_name query per name field per keystroke. Fine at
  # gazetteer scale (hundreds of places, two or three name fields); debounce the
  # validate event or move the lookup to blur if the form ever feels slow.
  defp duplicate_for(%{"names" => names}, place) when is_map(names) do
    names
    |> Map.values()
    |> Enum.map(& &1["name"])
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.find_value(fn name ->
      case Places.find_by_name(name) do
        nil -> nil
        %{id: id} when id == place.id -> nil
        found -> found
      end
    end)
  end

  defp duplicate_for(_params, _place), do: nil

  defp parent_options(place) do
    [{gettext("— none —"), nil}] ++
      (Places.list_places()
       |> Enum.reject(&(&1.id == place.id))
       |> Enum.map(&{Places.display_name(&1, "es"), &1.id}))
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="rounded-box border border-primary/30 bg-base-100 p-5 shadow-md">
      <h3 class="mb-4 text-sm font-semibold text-primary">
        {if @place.id, do: gettext("Edit place"), else: gettext("New place")}
      </h3>

      <%!-- Authority search: the only remote lookup, so the only typeahead --%>
      <div class="mb-4 rounded-box bg-base-200 p-3">
        <form phx-change="authority_search" phx-target={@myself} phx-debounce="300">
          <label class="label" for="place-form-component-term">
            <span class="label-text font-medium">{gettext("Search Wikidata")}</span>
          </label>
          <input
            id="place-form-component-term"
            type="text"
            name="term"
            value=""
            class="input input-bordered input-sm w-full"
          />
        </form>
        <p :if={@authority_error} class="mt-2 text-xs text-warning">{@authority_error}</p>
        <ul class="mt-2 space-y-1">
          <li :for={candidate <- @candidates}>
            <button
              type="button"
              phx-click="authority_select"
              phx-target={@myself}
              phx-value-authority-id={candidate.id}
              class="btn btn-ghost btn-xs justify-start w-full"
            >
              <span class="font-medium">{candidate.label}</span>
              <span class="text-base-content/70">{candidate.description}</span>
            </button>
          </li>
        </ul>
      </div>

      <.form
        for={@form}
        id="place-form"
        phx-change="validate"
        phx-submit="save"
        phx-target={@myself}
      >
        <div :if={@duplicate} class="alert alert-warning mb-4 text-sm">
          {gettext("A place with this name already exists.")}
          <span class="font-medium">{@duplicate_chain}</span>
        </div>

        <fieldset class="mb-4">
          <legend class="label-text font-medium">{gettext("Names")}</legend>
          <.inputs_for :let={name} field={@form[:names]}>
            <input type="hidden" name="place[names_order][]" value={name.index} />
            <div class="mb-2 flex flex-wrap items-end gap-2">
              <div class="grow">
                <.input field={name[:name]} type="text" placeholder={gettext("Name")} />
              </div>
              <div class="w-28">
                <.input
                  field={name[:language]}
                  type="select"
                  aria-label={gettext("Language")}
                  options={[
                    {"", nil},
                    {"es", "es"},
                    {"en", "en"},
                    {"fr", "fr"},
                    {"it", "it"},
                    {"pt", "pt"},
                    {"ca", "ca"}
                  ]}
                />
              </div>
              <div class="text-xs">
                <.input field={name[:is_preferred]} type="checkbox" label={gettext("Preferred")} />
              </div>
              <div class="text-xs">
                <.input field={name[:is_historical]} type="checkbox" label={gettext("Historical")} />
              </div>
              <button
                type="button"
                name="place[names_delete][]"
                value={name.index}
                phx-click={JS.dispatch("change")}
                class="btn btn-ghost btn-xs text-error"
              >
                {gettext("Remove")}
              </button>
            </div>
          </.inputs_for>

          <input type="hidden" name="place[names_delete][]" />
          <button
            type="button"
            name="place[names_order][]"
            value="new"
            phx-click={JS.dispatch("change")}
            class="btn btn-ghost btn-xs mt-1"
          >
            {gettext("Add name")}
          </button>
        </fieldset>

        <div class="grid grid-cols-1 gap-4 md:grid-cols-2">
          <div>
            <.input
              field={@form[:type]}
              type="select"
              label={gettext("Type")}
              options={PlayLabels.place_type_options()}
            />
          </div>
          <div>
            <.input
              field={@form[:parent_place_id]}
              type="select"
              label={gettext("Contained in")}
              options={@parent_options}
            />
          </div>
          <div>
            <.input field={@form[:latitude]} type="text" label={gettext("Latitude")} />
          </div>
          <div>
            <.input field={@form[:longitude]} type="text" label={gettext("Longitude")} />
          </div>
          <div>
            <.input field={@form[:slug]} type="text" label={gettext("Slug")} />
          </div>
          <div>
            <.input field={@form[:authority_id]} type="text" label={gettext("Wikidata id")} />
            <.input field={@form[:authority]} type="hidden" />
          </div>
        </div>

        <div class="mt-2">
          <.input field={@form[:is_fictional]} type="checkbox" label={gettext("Fictional place")} />
        </div>

        <div class="mt-2">
          <.input field={@form[:note]} type="textarea" rows="2" label={gettext("Note")} />
        </div>

        <p class="mt-2 text-xs text-base-content/70">
          {gettext("Leave the coordinates empty for a place that cannot be located.")}
        </p>

        <div class="mt-4 flex justify-end gap-2">
          <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-sm">
            {gettext("Cancel")}
          </button>
          <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
        </div>
      </.form>
    </div>
    """
  end
end
