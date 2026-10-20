defmodule PlaycodeWeb.Admin.PlayPerformancesLive do
  @moduledoc """
  /admin/plays/:id/performances: the play's historical performances (S5), in order of year,
  each as readers see it (`Playcode.Performances.listing/4`). Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.
  """

  use PlaycodeWeb, :live_view

  import PlaycodeWeb.Admin.EntryFields
  import PlaycodeWeb.Admin.PlacePicker

  alias Playcode.Bibliography
  alias Playcode.Bibliography.{Citation, Entry}
  alias Playcode.Catalogue
  alias Playcode.Performances
  alias Playcode.Performances.{Actor, Company, Performance}
  alias Playcode.PlayContent
  alias Playcode.PlayContent.InlineMarkup
  alias Playcode.Places
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.Components.PlayText

  # What the form edits. The play comes from the page, the place from the picker, and the
  # origin is "manual" or what an import set, never from the browser: see form_params/2.
  @editable ~w(date_text year_from year_to venue venue_type company_name historical_state_id
               note source_volume source_pages cast_from_cast_list)

  # A performance's source may be a catalogue, which no play's bibliography holds.
  @source_kinds Entry.kinds() ++ ["catalogue"]

  # What a row of the cast holds: an existing actor by name, or the names of a new one, and
  # the role. See Playcode.Performances.update_performance/2.
  @cast_fields ~w(actor_id actor_name surname forename nickname sex role)

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Performances")}")
     |> assign(:play, play)
     |> assign(:play_context, %{play: play, active_tab: :performances})
     |> assign(editing: nil, form: nil, cast: [], companies: [], actors: [])
     |> assign(renaming: nil, rename_form: nil, usage: nil)
     |> assign(picked: nil, term: "", suggestions: [], source_kinds: @source_kinds)
     |> choose_source(nil)
     |> reload()}
  end

  @impl true
  def handle_event("new", _, socket) do
    {:noreply,
     edit(socket, :new, %Performance{
       play_id: socket.assigns.play.id,
       company: nil,
       place: nil,
       source: nil,
       cast: []
     })}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    with_performance(socket, id, &edit(socket, &1, &1))
  end

  def handle_event("cancel", _, socket), do: {:noreply, close_form(socket)}

  # Events for a form that is not open come from a stale or forged page.
  def handle_event(event, _, %{assigns: %{editing: nil}} = socket)
      when event in ~w(validate save),
      do: {:noreply, socket}

  def handle_event("validate", %{"performance" => params}, socket) do
    changeset =
      socket
      |> editing_base()
      |> Performances.change_performance(form_params(params, socket.assigns))
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:cast, cast_params(params)) |> show_form(changeset)}
  end

  def handle_event("save", %{"performance" => params}, socket) do
    cast = cast_params(params)
    socket = assign(socket, :cast, cast)
    params = params |> form_params(socket.assigns) |> Map.put("cast", cast)

    cond do
      known_performance(socket) == :gone ->
        {:noreply, socket |> close_form() |> reload() |> LiveHelpers.put_gone_flash()}

      known_state(params) == :gone ->
        {:noreply, socket |> reload() |> LiveHelpers.put_gone_flash()}

      known_source(socket) == :gone ->
        {:noreply, forget_source(socket)}

      true ->
        save(socket, params)
    end
  end

  def handle_event("add_cast", _, socket), do: {:noreply, update(socket, :cast, &(&1 ++ [%{}]))}

  def handle_event("remove_cast", %{"index" => index}, socket) do
    case Integer.parse(index) do
      {index, ""} when index >= 0 ->
        {:noreply, update(socket, :cast, &List.delete_at(&1, index))}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("search_source", %{"term" => term}, socket) do
    entries = Bibliography.search_entries(term, socket.assigns.play.id, 10, kinds: :all)
    {:noreply, assign(socket, source_term: term, source_suggestions: entries)}
  end

  def handle_event("pick_source", %{"entry" => id}, socket) do
    with_entry(socket, id, &choose_source(socket, &1))
  end

  def handle_event("new_source", _, socket) do
    changeset = Bibliography.change_entry(%Entry{kind: "catalogue"})
    {:noreply, open_source_form(socket, :new, changeset, [])}
  end

  def handle_event("edit_source", %{"entry" => id}, socket) do
    with_entry(socket, id, fn entry ->
      others = Enum.reject(Bibliography.plays_for_entry(id), &(&1.id == socket.assigns.play.id))
      open_source_form(socket, entry, Bibliography.change_entry(entry), others)
    end)
  end

  # Nothing was entered in the form to edit again.
  def handle_event("edit_source", _, %{assigns: %{source_params: nil}} = socket),
    do: {:noreply, socket}

  # A source entered in the form and not written yet.
  def handle_event("edit_source", _, socket) do
    changeset = Bibliography.change_entry(%Entry{}, socket.assigns.source_params)
    {:noreply, open_source_form(socket, :new, changeset, [])}
  end

  def handle_event(event, _, %{assigns: %{source_edit: nil}} = socket)
      when event in ~w(validate_source save_source),
      do: {:noreply, socket}

  def handle_event("validate_source", %{"entry" => params}, socket) do
    changeset =
      socket.assigns.source_edit
      |> source_base()
      |> Bibliography.change_entry(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :source_form, to_form(changeset, as: "entry"))}
  end

  def handle_event("save_source", %{"entry" => params}, socket),
    do: save_source(socket, socket.assigns.source_edit, params)

  def handle_event("cancel_source", _, socket), do: {:noreply, close_source_form(socket)}
  def handle_event("clear_source", _, socket), do: {:noreply, choose_source(socket, nil)}

  def handle_event("rename_company", %{"id" => id}, socket),
    do: rename(socket, Performances.get_company(id))

  def handle_event("rename_actor", %{"id" => id}, socket),
    do: rename(socket, Performances.get_actor(id))

  def handle_event("cancel_rename", _, socket), do: {:noreply, close_rename(socket)}

  # The record is read again: it may be gone, or renamed by someone else, since the panel
  # opened.
  def handle_event("save_rename", %{"rename" => params}, socket) do
    case reread(socket.assigns.renaming) do
      nil -> {:noreply, socket |> close_rename() |> reload() |> LiveHelpers.put_gone_flash()}
      record -> save_rename(socket, record, params)
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    with_performance(socket, id, fn performance ->
      {:ok, _} = Performances.delete_performance(performance)
      log(socket, "delete", performance)

      socket
      |> close_form_editing(performance)
      |> reload()
      |> put_flash(:info, gettext("Performance deleted."))
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

        log_new_source(socket, performance)

        message =
          if action == "create",
            do: gettext("Performance added."),
            else: gettext("Performance updated.")

        {:noreply, socket |> reload() |> close_form() |> put_flash(:info, message)}

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

  # A form open on the performance just deleted has nothing left to save.
  defp close_form_editing(%{assigns: %{editing: %Performance{id: id}}} = socket, %{id: id}),
    do: close_form(socket)

  defp close_form_editing(socket, _performance), do: socket

  defp close_form(socket) do
    socket |> assign(editing: nil, form: nil, cast: []) |> choose_source(nil) |> close_rename()
  end

  # The form's own fields; the place and the source come from the pickers. A performance with
  # no place has no historical state either, and one with no source no volume or pages in it.
  defp form_params(params, %{picked: place, source: source, source_params: source_params}) do
    params
    |> Map.take(@editable)
    |> put_place(place)
    |> put_source(source, source_params)
  end

  defp put_place(params, nil),
    do: Map.merge(params, %{"place_id" => nil, "historical_state_id" => nil})

  defp put_place(params, place), do: Map.put(params, "place_id", place.id)

  defp put_source(params, nil, _source_params) do
    Map.merge(params, %{"source_entry_id" => nil, "source_volume" => nil, "source_pages" => nil})
  end

  # A new source is written with the performance, from the fields the form kept.
  defp put_source(params, %Entry{id: nil}, source_params),
    do: Map.merge(params, %{"source_entry_id" => nil, "source_entry" => source_params})

  defp put_source(params, %Entry{id: id}, _source_params),
    do: Map.put(params, "source_entry_id", id)

  # The source of the form: `source` is an entry, or a new one with no id yet, kept as the
  # `source_params` that will make it. Choosing one closes the search and the entry form.
  defp choose_source(socket, source, source_params \\ nil) do
    socket
    |> assign(source: source, source_params: source_params, source_term: "")
    |> assign(:source_suggestions, [])
    |> close_source_form()
  end

  defp open_source_form(socket, editing, changeset, others) do
    assign(socket,
      source_edit: editing,
      source_form: to_form(changeset, as: "entry"),
      source_kinds: source_kinds(editing),
      source_shared_with: others
    )
  end

  defp close_source_form(socket),
    do: assign(socket, source_edit: nil, source_form: nil, source_shared_with: [])

  # An entry some play's bibliography lists stays one of the four kinds.
  defp source_kinds(%Entry{id: id}),
    do: if(Bibliography.linked?(id), do: Entry.kinds(), else: @source_kinds)

  defp source_kinds(:new), do: @source_kinds

  defp source_base(:new), do: %Entry{}
  defp source_base(%Entry{} = entry), do: entry

  # A new source is kept for the performance to write: nothing is saved here, so a form that
  # is cancelled leaves no entry. An existing one is corrected now, for every play.
  defp save_source(socket, :new, params) do
    changeset = Bibliography.change_entry(%Entry{}, params)

    if changeset.valid? do
      {:noreply, choose_source(socket, Ecto.Changeset.apply_changes(changeset), params)}
    else
      {:noreply,
       assign(socket, :source_form, to_form(%{changeset | action: :validate}, as: "entry"))}
    end
  end

  # The entry is read again only to see that it is still there. The form's own copy takes
  # the update, so a field another curator changed and this form left alone is not put back.
  defp save_source(socket, %Entry{id: id} = entry, params) do
    with %Entry{} <- Bibliography.get_entry(id),
         {:ok, updated} <- Bibliography.update_entry(entry, params) do
      LiveHelpers.log_activity(socket, "update", "bibliography_entry", id)
      {:noreply, socket |> choose_source(updated) |> put_flash(:info, gettext("Entry saved."))}
    else
      nil ->
        {:noreply, forget_source(socket)}

      {:error, changeset} ->
        {:noreply, assign(socket, :source_form, to_form(changeset, as: "entry"))}
    end
  end

  # The entry the event named, or the source forgotten when it is gone: see
  # LiveHelpers.put_gone_flash/1.
  defp with_entry(socket, id, fun) do
    case Bibliography.get_entry(id) do
      nil -> {:noreply, forget_source(socket)}
      entry -> {:noreply, fun.(entry)}
    end
  end

  defp forget_source(socket),
    do: socket |> choose_source(nil) |> reload() |> LiveHelpers.put_gone_flash()

  # The performance the form edits, deleted since: by another curator, say.
  defp known_performance(%{assigns: %{editing: %Performance{id: id}, play: play}}),
    do: if(Performances.get_performance(play.id, id), do: :ok, else: :gone)

  defp known_performance(_socket), do: :ok

  # A source chosen and deleted since: by its last citation going, say.
  defp known_source(%{assigns: %{source: %Entry{id: id}}}) when is_binary(id),
    do: if(Bibliography.get_entry(id), do: :ok, else: :gone)

  defp known_source(_socket), do: :ok

  # What went wrong with the source.
  defp source_errors(%{source: changeset}),
    do: for({:source_entry_id, error} <- changeset.errors, do: translate_error(error))

  # The rows of the cast in the form, in the order of their indexes: the browser sends them
  # as a map keyed "0", "1", ... "10", and "10" is before "2" as text.
  defp cast_params(%{"cast" => rows}) when is_map(rows) do
    rows
    |> Enum.sort_by(fn {index, _row} -> row_number(index) end)
    |> Enum.flat_map(fn
      {_index, row} when is_map(row) ->
        [row |> Map.take(@cast_fields) |> Map.filter(fn {_field, value} -> is_binary(value) end)]

      _ ->
        []
    end)
  end

  defp cast_params(_params), do: []

  defp row_number(index) do
    case Integer.parse(index) do
      {number, _} -> number
      :error -> 0
    end
  end

  # The cast as saved, as the form's rows: the actor picked by name.
  defp saved_cast(performance) do
    for member <- performance.cast,
        do: %{
          "actor_id" => member.actor_id,
          "actor_name" => Actor.display_name(member.actor),
          "role" => member.role
        }
  end

  # Each row with its number and the actor it picks, if any: the one "Rename" is for.
  defp cast_view(cast, actors) do
    for {row, index} <- Enum.with_index(cast),
        do: {index, row, Performances.picked_actor(row, actors)}
  end

  # What went wrong in each row of the cast, by its number.
  defp cast_errors(%{source: changeset}) do
    for({:cast, error} <- changeset.errors, do: {error_row(error), translate_error(error)})
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp error_row({_message, opts}), do: opts[:row]

  # Rename, for every performance that names the company or the actor: a panel of its own,
  # because the performance's form has no room for a form inside it.
  defp rename(socket, nil),
    do: {:noreply, socket |> close_rename() |> reload() |> LiveHelpers.put_gone_flash()}

  defp rename(%{assigns: %{form: nil}} = socket, _record), do: {:noreply, socket}

  defp rename(socket, record) do
    {:noreply,
     assign(socket,
       renaming: record,
       rename_form: rename_form(record),
       usage: Performances.usage(record)
     )}
  end

  defp save_rename(socket, record, params) do
    case update_named(record, params) do
      {:ok, renamed} ->
        LiveHelpers.log_activity(socket, "update", resource_type(renamed), renamed.id, %{
          from: name(record),
          to: name(renamed)
        })

        {:noreply,
         socket
         |> follow_rename(record, renamed)
         |> close_rename()
         |> assign_names()
         |> reload()
         |> put_flash(:info, gettext("Renamed for every performance."))}

      {:error, changeset} ->
        {:noreply, assign(socket, :rename_form, to_form(changeset, as: :rename))}
    end
  end

  defp close_rename(socket), do: assign(socket, renaming: nil, rename_form: nil, usage: nil)

  defp rename_form(%Company{} = company),
    do: to_form(Performances.change_company(company), as: :rename)

  defp rename_form(%Actor{} = actor), do: to_form(Performances.change_actor(actor), as: :rename)

  defp reread(%Company{id: id}), do: Performances.get_company(id)
  defp reread(%Actor{id: id}), do: Performances.get_actor(id)
  defp reread(nil), do: nil

  defp update_named(%Company{} = company, params),
    do: Performances.update_company(company, Map.take(params, ["name"]))

  defp update_named(%Actor{} = actor, params),
    do: Performances.update_actor(actor, Map.take(params, ~w(surname forename nickname sex)))

  defp resource_type(%Company{}), do: "performance_company"
  defp resource_type(%Actor{}), do: "performance_actor"

  defp name(%Company{name: name}), do: name
  defp name(%Actor{} = actor), do: Actor.display_name(actor)

  # A name where markup cannot go (an aria-label), or is not worth the trouble (a heading
  # built from a translation): an actor's names may hold italics as <<…>>.
  defp plain_name(record), do: record |> name() |> InlineMarkup.plain()

  # The open form names the record by its old name; it must name it by the new, else saving
  # it would make a company of the old name, or leave a row naming no one.
  defp follow_rename(socket, %Company{} = old, %Company{} = renamed) do
    %{params: params, source: %{action: action}} = socket.assigns.form

    if Company.named([old], params["company_name"]) do
      changeset =
        socket
        |> editing_base()
        |> Performances.change_performance(Map.put(params, "company_name", renamed.name))

      show_form(socket, %{changeset | action: action})
    else
      socket
    end
  end

  defp follow_rename(socket, %Actor{} = old, %Actor{} = renamed) do
    update(socket, :cast, fn rows ->
      for row <- rows do
        if Performances.picked_actor(row, [old]),
          do: Map.put(row, "actor_name", name(renamed)),
          else: row
      end
    end)
  end

  # A blank state clears it; any other must still be in the gazetteer.
  defp known_state(%{"historical_state_id" => state_id}) when state_id not in ["", nil] do
    if Places.get_place(state_id), do: :ok, else: :gone
  end

  defp known_state(_params), do: :ok

  defp edit(socket, editing, performance) do
    socket
    |> assign(
      editing: editing,
      form: to_form(Performances.change_performance(performance, company_params(performance))),
      cast: saved_cast(performance),
      picked: performance.place,
      term: "",
      suggestions: [],
      states:
        Places.historical_states(socket.assigns.gazetteer, [performance.historical_state_id])
    )
    |> choose_source(performance.source)
    |> close_rename()
    |> assign_names()
  end

  # The year inputs: `{value, placeholder}` each. The value is a year the curator typed; the
  # placeholder the year the date gives, which the save writes when the input is blank. A year
  # the date gave is shown as the placeholder alone, so it follows the date as it is edited,
  # and the browser does not send it back as the curator's own.
  defp years(form) do
    {from, to} = Performance.years(form[:date_text].value)
    %{year_from: {own_year(form, :year_from), from}, year_to: {own_year(form, :year_to), to}}
  end

  # The rule of `Performance.changeset/2`: a year follows the date when it is blank, or is the
  # one the stored date gave and the form leaves unchanged.
  defp own_year(%{source: %{data: data}} = form, field) do
    {was_from, was_to} = Performance.years(data.date_text)
    was = if field == :year_from, do: was_from, else: was_to
    stored = Map.fetch!(data, field)
    year = form.params |> Map.get(Atom.to_string(field), stored) |> to_year()

    if year == nil or (year == stored and stored == was), do: nil, else: year
  end

  defp to_year(year) when is_integer(year), do: year

  defp to_year(year) when is_binary(year) do
    case Integer.parse(year) do
      {year, ""} -> year
      _ -> nil
    end
  end

  defp to_year(nil), do: nil

  # What the form's datalists offer.
  defp assign_names(socket),
    do:
      assign(socket, companies: Performances.list_companies(), actors: Performances.list_actors())

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

    listing =
      play_id
      |> Performances.list_for_play()
      |> Performances.listing(characters, gazetteer, locale())

    assign(socket, gazetteer: gazetteer, lines: listing.lines, sources: listing.sources)
  end

  defp locale, do: Gettext.get_locale(PlaycodeWeb.Gettext)

  defp state_options(states, place),
    do:
      for(state <- states, state.id != place.id, do: {Places.display_name(state, "es"), state.id})

  defp venue_type_options do
    for type <- Performance.venue_types(),
        do: {Performance.venue_type_label(type, locale()), type}
  end

  # What a button of a line is about: its date and parts, else its note. An aria-label has no
  # markup to print italics with, so the italics' markers go.
  defp label(line) do
    about =
      case Enum.reject([line.date | line.parts], &is_nil/1) do
        [] -> line.note
        present -> Enum.join(present, ", ")
      end

    InlineMarkup.plain(about)
  end

  # The entry the performance's save wrote, if its source was a new one.
  defp log_new_source(%{assigns: %{source_params: nil}}, _performance), do: :ok

  defp log_new_source(socket, performance),
    do:
      LiveHelpers.log_activity(
        socket,
        "create",
        "bibliography_entry",
        performance.source_entry_id
      )

  defp log(socket, action, performance) do
    LiveHelpers.log_activity(socket, action, "play_performance", performance.id, %{
      date: performance.date_text,
      venue: performance.venue
    })
  end

  # The company the form names, if it exists: the one "Rename" is for.
  defp named_company(%{form: nil}), do: nil

  defp named_company(%{form: form, companies: companies}),
    do: Company.named(companies, form[:company_name].value)

  defp usage_text(%{performances: performances, plays: plays}) do
    gettext("%{performances} in %{plays}",
      performances: ngettext("1 performance", "%{count} performances", performances),
      plays: ngettext("1 play", "%{count} plays", plays)
    )
  end

  defp sex_options, do: [{gettext("Man"), "man"}, {gettext("Woman"), "woman"}]

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        company: named_company(assigns),
        cast_errors: assigns.form && cast_errors(assigns.form),
        years: assigns.form && years(assigns.form)
      )

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
        <%!-- The source's search and its entry form are forms too. --%>
        <div id="source" class="mb-4">
          <div :if={@source}>
            <span class="label label-text font-medium">{gettext("Source")}</span>
            <div class="flex items-start justify-between gap-2 rounded-box border border-base-300 px-3 py-2">
              <p class="min-w-0 font-serif text-sm [&_a]:link [&_a]:break-all">
                {Citation.html(@source)}
              </p>
              <div class="flex shrink-0 gap-1">
                <button
                  type="button"
                  phx-click="edit_source"
                  phx-value-entry={@source.id}
                  class="btn btn-ghost btn-xs"
                >
                  {gettext("Edit source")}
                </button>
                <button
                  type="button"
                  phx-click="clear_source"
                  class="btn btn-circle btn-ghost btn-xs"
                  aria-label={gettext("Clear source")}
                >
                  <.icon name="hero-x-mark-mini" class="size-3.5" />
                </button>
              </div>
            </div>
          </div>
          <div :if={is_nil(@source)} class="relative">
            <label class="label" for="source-search-term">
              <span class="label-text font-medium">{gettext("Source")}</span>
            </label>
            <form id="source-search" phx-change="search_source" phx-submit="search_source">
              <input
                type="text"
                id="source-search-term"
                name="term"
                value={@source_term}
                phx-debounce="300"
                placeholder={gettext("Author, editor or title")}
                class="input input-bordered input-sm w-full"
                autocomplete="off"
              />
            </form>
            <ul
              :if={@source_suggestions != []}
              id="source-results"
              class="rounded-box mt-1 max-h-64 divide-y divide-base-300 overflow-y-auto border border-base-300 bg-base-100 shadow-lg"
            >
              <li :for={entry <- @source_suggestions}>
                <button
                  type="button"
                  phx-click="pick_source"
                  phx-value-entry={entry.id}
                  class="w-full px-3 py-2 text-left font-serif text-sm transition-colors hover:bg-base-200"
                >
                  {Citation.plain(entry)}
                </button>
              </li>
            </ul>
            <p
              :if={@source_term != "" and @source_suggestions == []}
              class="mt-2 text-xs text-base-content/70"
            >
              {gettext("Nothing matches.")}
            </p>
            <button
              :if={is_nil(@source_form)}
              type="button"
              phx-click="new_source"
              class="btn btn-ghost btn-xs mt-2 gap-1"
            >
              <.icon name="hero-plus-mini" class="size-3.5" /> {gettext("New source")}
            </button>
          </div>
          <.error :for={message <- source_errors(@form)}>{message}</.error>
          <div
            :if={@source_form}
            id="source-panel"
            class="mt-3 overflow-hidden rounded-box border border-base-300 bg-base-200/50"
          >
            <.shared_warning plays={@source_shared_with} />
            <.form
              for={@source_form}
              id="source-form"
              phx-change="validate_source"
              phx-submit="save_source"
              class="p-4"
            >
              <h3 class="mb-3 text-sm font-semibold">
                {if @source_edit == :new, do: gettext("New source"), else: gettext("Edit source")}
              </h3>
              <.entry_fields form={@source_form} kinds={@source_kinds} />
              <div class="mt-3 flex justify-end gap-2">
                <button type="button" phx-click="cancel_source" class="btn btn-ghost btn-sm">
                  {gettext("Cancel")}
                </button>
                <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
              </div>
            </.form>
          </div>
        </div>
        <%!-- Nor can a rename's form sit inside the performance's. --%>
        <div
          :if={@renaming}
          id="rename-panel"
          class="mb-4 rounded-box border border-base-300 bg-base-200/50 p-4"
        >
          <h3 class="text-sm font-semibold">
            {gettext("Rename %{name}", name: plain_name(@renaming))}
          </h3>
          <p class="mb-3 text-xs text-base-content/70">{usage_text(@usage)}</p>
          <.form for={@rename_form} id="rename-form" phx-submit="save_rename">
            <.rename_fields record={@renaming} form={@rename_form} />
            <div class="mt-2 flex justify-end gap-2">
              <button type="button" phx-click="cancel_rename" class="btn btn-ghost btn-sm">
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
            </div>
          </.form>
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
            <div>
              <div class="grid grid-cols-2 gap-x-4">
                <.input
                  id="performance_year_from"
                  name="performance[year_from]"
                  type="number"
                  value={elem(@years.year_from, 0)}
                  placeholder={elem(@years.year_from, 1)}
                  label={gettext("Year from")}
                  aria-describedby="years-help"
                />
                <.input
                  id="performance_year_to"
                  name="performance[year_to]"
                  type="number"
                  value={elem(@years.year_to, 0)}
                  placeholder={elem(@years.year_to, 1)}
                  label={gettext("Year to")}
                  aria-describedby="years-help"
                />
              </div>
              <p id="years-help" class="-mt-1 mb-2 text-xs text-base-content/70">
                {gettext("Left blank, the years follow the date.")}
              </p>
            </div>
            <.input field={@form[:venue]} type="text" label={gettext("Venue")} />
            <.input
              field={@form[:venue_type]}
              type="select"
              label={gettext("Venue type")}
              prompt={gettext("Not stated")}
              options={venue_type_options()}
            />
            <div>
              <div class="flex items-end gap-2">
                <div class="grow">
                  <.input
                    field={@form[:company_name]}
                    type="text"
                    label={gettext("Company")}
                    list="performance-companies"
                    autocomplete="off"
                    aria-describedby="company-help"
                  />
                </div>
                <.rename_button :if={@company} event="rename_company" record={@company} />
              </div>
              <p id="company-help" class="-mt-1 mb-2 text-xs text-base-content/70">
                {gettext("Rename corrects the company for every performance that names it.")}
              </p>
            </div>
          </div>
          <div :if={@source} class="grid grid-cols-2 gap-x-4">
            <.input field={@form[:source_volume]} type="text" label={gettext("Volume")} />
            <.input field={@form[:source_pages]} type="text" label={gettext("Pages")} />
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
          <div class="mt-2">
            <div class="flex items-center justify-between">
              <h3 class="text-sm font-semibold">{gettext("Cast")}</h3>
              <button type="button" phx-click="add_cast" class="btn btn-ghost btn-xs gap-1">
                <.icon name="hero-plus-mini" class="size-3.5" /> {gettext("Add actor")}
              </button>
            </div>
            <datalist id="performance-actors">
              <option :for={actor <- @actors} value={Actor.display_name(actor)} />
            </datalist>
            <fieldset
              :for={{index, row, actor} <- cast_view(@cast, @actors)}
              id={"cast-row-#{index}"}
              class="mt-3 rounded-box border border-base-300 p-3"
            >
              <legend class="sr-only">{gettext("Cast row %{number}", number: index + 1)}</legend>
              <%!-- A saved row keeps its actor by id: two actors can read the same. --%>
              <input
                :if={row["actor_id"]}
                type="hidden"
                name={"performance[cast][#{index}][actor_id]"}
                value={row["actor_id"]}
              />
              <div class="flex items-end gap-2">
                <div class="grid grow grid-cols-1 gap-x-3 md:grid-cols-2">
                  <.cast_input
                    index={index}
                    field="actor_name"
                    row={row}
                    label={gettext("Actor")}
                    list="performance-actors"
                    autocomplete="off"
                  />
                  <.cast_input index={index} field="role" row={row} label={pgettext("cast", "Role")} />
                </div>
                <.rename_button :if={actor} event="rename_actor" record={actor} />
                <button
                  type="button"
                  phx-click="remove_cast"
                  phx-value-index={index}
                  class="btn btn-ghost btn-xs mb-2 text-error"
                  aria-label={gettext("Remove cast row %{number}", number: index + 1)}
                >
                  <.icon name="hero-trash-micro" class="size-3.5" />
                </button>
              </div>
              <p class="text-xs text-base-content/70">{gettext("Or a new actor")}</p>
              <div class="grid grid-cols-2 gap-x-3 md:grid-cols-4">
                <.cast_input index={index} field="surname" row={row} label={gettext("Surname")} />
                <.cast_input index={index} field="forename" row={row} label={gettext("Forename")} />
                <.cast_input index={index} field="nickname" row={row} label={gettext("Nickname")} />
                <.input
                  type="select"
                  id={"cast-#{index}-sex"}
                  name={"performance[cast][#{index}][sex]"}
                  value={row["sex"]}
                  label={gettext("Sex")}
                  prompt={gettext("Not stated")}
                  options={sex_options()}
                />
              </div>
              <.error :for={message <- Map.get(@cast_errors, index, [])}>{message}</.error>
            </fieldset>
          </div>
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
              <span :if={line.date} class="font-semibold">
                <PlayText.inline_content text={line.date} />
              </span>
              <PlayText.inline_content :if={line.parts != []} text={Enum.join(line.parts, " · ")} />
              <span :if={line.reference} class="whitespace-nowrap text-xs text-base-content/70">
                {line.reference}
              </span>
              <p :if={line.cast != []} class="text-xs">
                {gettext("Cast")}: <PlayText.inline_content text={Enum.join(line.cast, "; ")} />
              </p>
              <p :if={line.note} class="text-xs"><PlayText.inline_content text={line.note} /></p>
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
      <ul
        :if={@sources != []}
        id="performance-sources"
        class="mt-4 space-y-1 border-t border-base-300 pt-3 font-serif text-sm"
      >
        <li :for={{number, entry} <- @sources} class="pl-6 -indent-6 [&_a]:link [&_a]:break-all">
          [{number}] {Citation.html(entry)}
        </li>
      </ul>
    </div>
    """
  end

  attr :index, :integer, required: true
  attr :field, :string, required: true
  attr :row, :map, required: true
  attr :label, :string, required: true
  attr :rest, :global, include: ~w(list autocomplete)

  # A text field of a cast row, `performance[cast][index][field]`.
  defp cast_input(assigns) do
    ~H"""
    <.input
      id={"cast-#{@index}-#{String.replace(@field, "_", "-")}"}
      name={"performance[cast][#{@index}][#{@field}]"}
      value={@row[@field]}
      label={@label}
      {@rest}
    />
    """
  end

  attr :event, :string, required: true
  attr :record, :any, required: true

  defp rename_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-id={@record.id}
      class="btn btn-ghost btn-xs mb-2 gap-1"
      aria-label={gettext("Rename %{name}", name: plain_name(@record))}
    >
      <.icon name="hero-pencil-micro" class="size-3.5" /> {gettext("Rename")}
    </button>
    """
  end

  attr :record, :any, required: true
  attr :form, :any, required: true

  defp rename_fields(%{record: %Company{}} = assigns) do
    ~H"""
    <.input field={@form[:name]} type="text" label={gettext("Company")} />
    """
  end

  defp rename_fields(%{record: %Actor{}} = assigns) do
    ~H"""
    <div class="grid grid-cols-2 gap-x-3 md:grid-cols-4">
      <.input field={@form[:surname]} type="text" label={gettext("Surname")} />
      <.input field={@form[:forename]} type="text" label={gettext("Forename")} />
      <.input field={@form[:nickname]} type="text" label={gettext("Nickname")} />
      <.input
        field={@form[:sex]}
        type="select"
        label={gettext("Sex")}
        prompt={gettext("Not stated")}
        options={sex_options()}
      />
    </div>
    """
  end
end
