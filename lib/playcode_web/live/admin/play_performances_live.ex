defmodule PlaycodeWeb.Admin.PlayPerformancesLive do
  @moduledoc """
  /admin/plays/:id/performances: the play's historical performances (S5), in order of year,
  each as readers see it (`Playcode.Performances.listing/4`). Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Admin.PlacePicker

  alias Playcode.Catalogue
  alias Playcode.Performances
  alias Playcode.Performances.Performance
  alias Playcode.PlayContent
  alias Playcode.Places
  alias PlaycodeWeb.Admin.LiveHelpers

  # What the form edits. The play comes from the page, the place from the picker, and the
  # origin is "manual" or what an import set, never from the browser: see form_params/2.
  @editable ~w(date_text year_from year_to venue venue_type company_name historical_state_id
               note cast_from_cast_list)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Performances")}")
     |> assign(:play, play)
     |> assign(:play_context, %{play: play, active_tab: :performances})
     |> assign(editing: nil, form: nil)
     |> assign(picked: nil, term: "", suggestions: [])
     |> reload()}
  end

  @impl true
  def handle_event("new", _, socket) do
    {:noreply,
     edit(socket, :new, %Performance{play_id: socket.assigns.play.id, company: nil, place: nil})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with_performance(socket, id, &edit(socket, &1, &1))
  end

  def handle_event("cancel", _, socket),
    do: {:noreply, assign(socket, editing: nil, form: nil)}

  def handle_event("validate", %{"performance" => params}, socket) do
    changeset =
      socket
      |> editing_base()
      |> Performances.change_performance(form_params(params, socket.assigns.picked))
      |> Map.put(:action, :validate)

    {:noreply, show_form(socket, changeset)}
  end

  def handle_event("save", %{"performance" => params}, socket) do
    params = form_params(params, socket.assigns.picked)

    case known_state(params) do
      :ok -> save(socket, params)
      :gone -> {:noreply, socket |> reload() |> LiveHelpers.put_gone_flash()}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with_performance(socket, id, fn performance ->
      {:ok, _} = Performances.delete_performance(performance)
      log(socket, "delete", performance)
      socket |> reload() |> put_flash(:info, gettext("Performance deleted."))
    end)
  end

  def handle_event("search_places", %{"term" => term}, socket) do
    {:noreply, assign(socket, term: term, suggestions: Places.search_names(term, limit: 10))}
  end

  # A suggestion deleted from the gazetteer since the search clears the picker instead.
  def handle_event("pick_place", %{"id" => id}, socket) do
    socket = assign(socket, term: "", suggestions: [])

    case Places.get_place(id) do
      nil -> {:noreply, socket |> reload() |> LiveHelpers.put_gone_flash()}
      place -> {:noreply, assign(socket, :picked, place)}
    end
  end

  def handle_event("clear_pick", _, socket), do: {:noreply, assign(socket, :picked, nil)}

  defp save(socket, params) do
    {action, result} =
      case socket.assigns.editing do
        :new ->
          {"create",
           Performances.create_performance(Map.put(params, "play_id", socket.assigns.play.id))}

        performance ->
          {"update", Performances.update_performance(performance, params)}
      end

    case result do
      {:ok, performance} ->
        log(socket, action, performance)

        message =
          if action == "create",
            do: gettext("Performance added."),
            else: gettext("Performance updated.")

        {:noreply,
         socket |> reload() |> assign(editing: nil, form: nil) |> put_flash(:info, message)}

      {:error, changeset} ->
        {:noreply, show_form(socket, changeset)}
    end
  end

  # The form for `changeset`, without the years its date gave: the browser would send them
  # back as the curator's own, and they would stop following the date. They are filled in
  # on save.
  defp show_form(socket, changeset) do
    changeset = Map.update!(changeset, :changes, &Map.drop(&1, [:year_from, :year_to]))
    assign(socket, :form, to_form(changeset))
  end

  # The form's own fields. A performance with no place has no historical state either.
  defp form_params(params, nil) do
    params |> Map.take(@editable) |> Map.merge(%{"place_id" => nil, "historical_state_id" => nil})
  end

  defp form_params(params, place),
    do: params |> Map.take(@editable) |> Map.put("place_id", place.id)

  # A blank state clears it; any other must still be in the gazetteer.
  defp known_state(%{"historical_state_id" => state_id}) when state_id not in ["", nil] do
    if Places.get_place(state_id), do: :ok, else: :gone
  end

  defp known_state(_params), do: :ok

  defp edit(socket, editing, performance) do
    assign(socket,
      editing: editing,
      form: to_form(Performances.change_performance(performance, company_params(performance))),
      picked: performance.place,
      term: "",
      suggestions: [],
      companies: Performances.list_companies(),
      states:
        Places.historical_states(socket.assigns.gazetteer, [performance.historical_state_id])
    )
  end

  defp company_params(performance),
    do: %{"company_name" => performance.company && performance.company.name}

  defp editing_base(%{assigns: %{editing: :new, play: play}}), do: %Performance{play_id: play.id}
  defp editing_base(%{assigns: %{editing: performance}}), do: performance

  # The performance the event named, or the list reloaded with a flash when it is not this
  # play's: see LiveHelpers.put_gone_flash/1.
  defp with_performance(socket, id, fun) do
    case Performances.get_performance(socket.assigns.play.id, id) do
      nil -> {:noreply, socket |> reload() |> LiveHelpers.put_gone_flash()}
      performance -> {:noreply, fun.(performance)}
    end
  end

  # The list as readers see it, in this page's language.
  defp reload(socket) do
    play_id = socket.assigns.play.id
    gazetteer = Places.gazetteer()
    characters = PlayContent.list_characters(play_id)

    lines =
      play_id
      |> Performances.list_for_play()
      |> Performances.listing(characters, gazetteer, locale())
      |> Map.fetch!(:lines)

    assign(socket, gazetteer: gazetteer, lines: lines)
  end

  defp locale, do: Gettext.get_locale(PlaycodeWeb.Gettext)

  defp state_options(states, place),
    do:
      for(state <- states, state.id != place.id, do: {Places.display_name(state, "es"), state.id})

  defp venue_type_options do
    for type <- Performance.venue_types(),
        do: {Performance.venue_type_label(type, locale()), type}
  end

  # What a button of a line is about: its date and parts, else its note.
  defp label(line) do
    case Enum.reject([line.date | line.parts], &is_nil/1) do
      [] -> line.note
      present -> Enum.join(present, ", ")
    end
  end

  defp log(socket, action, performance) do
    LiveHelpers.log_activity(socket, action, "play_performance", performance.id, %{
      date: performance.date_text,
      venue: performance.venue
    })
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-4xl px-4 py-8">
      <div class="mb-6 flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Performances")}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("When, where and by whom the play was staged, and what says so.")}
          </p>
        </div>
        <button :if={@editing == nil} phx-click="new" class="btn btn-primary btn-sm gap-1">
          <.icon name="hero-plus-mini" class="size-4" /> {gettext("Add performance")}
        </button>
      </div>

      <div :if={@form} class="mb-6 rounded-box border border-primary/30 bg-base-100 p-5 shadow-md">
        <h2 class="mb-4 text-sm font-semibold text-primary">
          {if @editing == :new, do: gettext("New performance"), else: gettext("Edit performance")}
        </h2>
        <%!-- The picker is a form of its own, so it sits above this one. --%>
        <div class="mb-4">
          <label class="label" for="place-search-term">
            <span class="label-text font-medium">{gettext("Place")}</span>
          </label>
          <div class="flex">
            <.place_picker
              id="place-search"
              picked={@picked}
              term={@term}
              suggestions={@suggestions}
              gazetteer={@gazetteer}
            />
          </div>
          <p
            :if={is_nil(@picked) and @term != "" and @suggestions == []}
            class="mt-2 text-xs text-base-content/70"
          >
            {gettext("No places found")}
          </p>
        </div>
        <.form for={@form} id="performance-form" phx-change="validate" phx-submit="save">
          <.input
            :if={@picked}
            field={@form[:historical_state_id]}
            type="select"
            label={gettext("Historical state")}
            prompt={gettext("Not stated")}
            options={state_options(@states, @picked)}
          />
          <div class="grid grid-cols-1 gap-x-4 md:grid-cols-2">
            <.input field={@form[:date_text]} type="text" label={gettext("Date")} />
            <div class="grid grid-cols-2 gap-x-4">
              <.input field={@form[:year_from]} type="number" label={gettext("Year from")} />
              <.input field={@form[:year_to]} type="number" label={gettext("Year to")} />
            </div>
            <.input field={@form[:venue]} type="text" label={gettext("Venue")} />
            <.input
              field={@form[:venue_type]}
              type="select"
              label={gettext("Venue type")}
              prompt={gettext("Not stated")}
              options={venue_type_options()}
            />
            <.input
              field={@form[:company_name]}
              type="text"
              label={gettext("Company")}
              list="performance-companies"
              autocomplete="off"
            />
          </div>
          <datalist id="performance-companies">
            <option :for={company <- @companies} value={company.name} />
          </datalist>
          <.input field={@form[:note]} type="textarea" rows="3" label={gettext("Note")} />
          <.input
            field={@form[:cast_from_cast_list]}
            type="checkbox"
            label={gettext("Cast as in the cast list")}
          />
          <div class="mt-4 flex justify-end gap-2">
            <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">
              {gettext("Cancel")}
            </button>
            <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
          </div>
        </.form>
      </div>

      <div :if={@lines == [] && @form == nil} class="py-12 text-center text-base-content/70">
        <.icon name="hero-ticket" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No performances yet.")}</p>
      </div>

      <ul class="space-y-3">
        <li
          :for={line <- @lines}
          id={"performance-#{line.id}"}
          class="rounded-box border border-base-300 bg-base-100 p-4 shadow-sm"
        >
          <div class="flex items-start justify-between gap-3">
            <div class="min-w-0 text-sm">
              <span :if={line.date} class="font-semibold">{line.date}</span>
              {Enum.join(line.parts, " · ")}
              <p :if={line.cast != []} class="text-xs">
                {gettext("Cast")}: {Enum.join(line.cast, "; ")}
              </p>
              <p :if={line.note} class="text-xs">{line.note}</p>
            </div>
            <div class="flex shrink-0 gap-1">
              <button
                phx-click="edit"
                phx-value-id={line.id}
                class="btn btn-ghost btn-xs"
                aria-label={gettext("Edit %{performance}", performance: label(line))}
              >
                <.icon name="hero-pencil-square-micro" class="size-3.5" />
              </button>
              <button
                phx-click="delete"
                phx-value-id={line.id}
                data-confirm={gettext("Delete this performance?")}
                class="btn btn-ghost btn-xs text-error"
                aria-label={gettext("Delete %{performance}", performance: label(line))}
              >
                <.icon name="hero-trash-micro" class="size-3.5" />
              </button>
            </div>
          </div>
        </li>
      </ul>
    </div>
    """
  end
end
