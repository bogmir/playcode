defmodule PlaycodeWeb.Admin.PlayBibliographyLive do
  @moduledoc """
  A play's bibliography: its links to the corpus-wide entries, grouped as the public page
  shows them. An entry shared with other plays is edited once for all of them, and the
  form says so before anyone saves. Spec: "Admin" in
  docs/superpowers/specs/2026-10-07-s4-bibliography-design.md.
  """
  use PlaycodeWeb, :live_view

  alias Playcode.ActivityLog
  alias Playcode.Bibliography
  alias Playcode.Bibliography.{Citation, Entry, Link}
  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias PlaycodeWeb.PlayLabels

  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :manage_bibliography}}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    play = Catalogue.get_play!(id)

    {:ok,
     socket
     |> assign(:page_title, "#{play.title} — #{gettext("Bibliography")}")
     |> assign(:play, play)
     |> assign(:play_context, %{play: play, active_tab: :bibliography})
     |> assign(q: "", adding: false, term: "", suggestions: [])
     |> close_form()
     |> load()}
  end

  @impl true
  def handle_event("new", _params, socket) do
    {:noreply,
     socket |> assign(:adding, false) |> open_form(:new, %Entry{kind: "criticism"}, %{}, [])}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Bibliography.get_link(socket.assigns.play.id, id) do
      nil ->
        {:noreply, socket}

      link ->
        others =
          link.entry_id
          |> Bibliography.plays_for_entry()
          |> Enum.reject(&(&1.id == link.play_id))

        params = %{"volume" => link.volume, "pages" => link.pages, "note" => link.note}

        {:noreply,
         socket |> assign(:adding, false) |> open_form(link, link.entry, params, others)}
    end
  end

  def handle_event("cancel", _params, socket), do: {:noreply, close_form(socket)}

  def handle_event("validate", params, socket) do
    link_params = params["link"] || %{}

    changeset =
      socket
      |> form_entry()
      |> Bibliography.change_entry(params["entry"] || %{})
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:form, to_form(changeset, as: "entry"))
     |> assign(:link_params, link_params)
     |> assign(:preview, preview(changeset, link_params))}
  end

  def handle_event("save", params, socket) do
    entry_params = params["entry"] || %{}
    link_params = params["link"] || %{}

    case save(socket.assigns.editing, socket.assigns.play.id, entry_params, link_params) do
      {:ok, link, action} ->
        log(socket, action, "bibliography_entry", link.entry_id)

        if link_changed?(socket.assigns.editing, link),
          do: log(socket, action, "play_bibliography", link.id)

        message =
          if action == "create", do: gettext("Entry added."), else: gettext("Entry saved.")

        {:noreply, socket |> close_form() |> load() |> put_flash(:info, message)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: "entry"))
         |> assign(:link_params, link_params)}
    end
  end

  def handle_event("remove", %{"id" => id}, socket) do
    # Nil for another play's link, or one a double click already removed.
    case Bibliography.get_link(socket.assigns.play.id, id) do
      nil ->
        {:noreply, load(socket)}

      link ->
        {:ok, outcome} = Bibliography.unlink(link)
        log(socket, "delete", "play_bibliography", link.id)
        if outcome == :deleted, do: log(socket, "delete", "bibliography_entry", link.entry_id)

        message =
          if outcome == :deleted,
            do: gettext("Entry deleted: no other play used it."),
            else: gettext("Removed from this play. The other plays keep it.")

        {:noreply, socket |> close_form() |> load() |> put_flash(:info, message)}
    end
  end

  def handle_event("open_add", _params, socket) do
    {:noreply, socket |> close_form() |> assign(adding: true, term: "", suggestions: [])}
  end

  def handle_event("close_add", _params, socket), do: {:noreply, assign(socket, :adding, false)}

  def handle_event("search", %{"term" => term}, socket) do
    entries = Bibliography.search_entries(term, socket.assigns.play.id)
    counts = Bibliography.link_counts(Enum.map(entries, & &1.id))

    {:noreply,
     assign(socket,
       term: term,
       suggestions: Enum.map(entries, &{&1, Map.get(counts, &1.id, 0)})
     )}
  end

  def handle_event("link", %{"entry" => entry_id}, socket) do
    case Bibliography.link_entry(socket.assigns.play.id, entry_id) do
      {:ok, link} ->
        log(socket, "create", "play_bibliography", link.id)

        {:noreply,
         socket
         |> assign(adding: false, term: "", suggestions: [])
         |> load()
         |> put_flash(:info, gettext("Entry added."))}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, gettext("That entry is already in this play's bibliography."))}
    end
  end

  def handle_event("filter", %{"q" => q}, socket), do: {:noreply, assign(socket, :q, q)}

  defp save(:new, play_id, entry_params, link_params) do
    with {:ok, link} <- Bibliography.create_entry_for_play(play_id, entry_params, link_params),
         do: {:ok, link, "create"}
  end

  defp save(%Link{} = link, _play_id, entry_params, link_params) do
    with {:ok, _entry} <- Bibliography.update_entry(link.entry, entry_params),
         {:ok, link} <- Bibliography.update_link(link, link_params),
         do: {:ok, link, "update"}
  end

  defp load(socket) do
    groups = Bibliography.list_for_play(socket.assigns.play.id)

    entry_ids =
      for {_kind, subgroups} <- groups,
          {_language, links} <- subgroups,
          link <- links,
          do: link.entry_id

    socket
    |> assign(:groups, groups)
    |> assign(:shared, Bibliography.link_counts(entry_ids))
  end

  defp open_form(socket, editing, entry, link_params, others) do
    changeset = Bibliography.change_entry(entry)

    assign(socket,
      editing: editing,
      form: to_form(changeset, as: "entry"),
      link_params: link_params,
      shared_with: others,
      preview: preview(changeset, link_params)
    )
  end

  defp close_form(socket) do
    assign(socket, editing: nil, form: nil, link_params: %{}, shared_with: [], preview: nil)
  end

  # A new entry's link is new too; an edit changed the link when one of its fields did.
  defp link_changed?(%Link{} = before, %Link{} = now),
    do: Map.take(before, [:volume, :pages, :note]) != Map.take(now, [:volume, :pages, :note])

  defp link_changed?(_new, _link), do: false

  defp form_entry(%{assigns: %{editing: %Link{entry: entry}}}), do: entry
  defp form_entry(_socket), do: %Entry{}

  defp preview(changeset, link_params) do
    entry = Ecto.Changeset.apply_changes(changeset)

    if Entry.named?(entry),
      do: Citation.html(entry, %Link{volume: link_params["volume"], pages: link_params["pages"]})
  end

  defp log(socket, action, resource_type, resource_id) do
    ActivityLog.log!(%{
      user_id: socket.assigns.current_user.id,
      play_id: socket.assigns.play.id,
      action: action,
      resource_type: resource_type,
      resource_id: resource_id
    })
  end

  # The groups with only the links whose printed citation contains the filter, compared
  # folded, like the sort.
  defp visible(groups, q) do
    case Bibliography.fold(q) do
      "" ->
        groups

      needle ->
        Enum.flat_map(groups, fn {kind, subgroups} ->
          kept =
            Enum.flat_map(subgroups, fn {language, links} ->
              case Enum.filter(links, &String.contains?(Bibliography.sort_key(&1), needle)) do
                [] -> []
                matching -> [{language, matching}]
              end
            end)

          if kept == [], do: [], else: [{kind, kept}]
        end)
    end
  end

  defp count(subgroups),
    do: subgroups |> Enum.map(fn {_l, links} -> length(links) end) |> Enum.sum()

  defp language_options, do: Enum.map(Entry.languages(), &{Play.language_name(&1), &1})

  defp internal_notes(link), do: Enum.filter([link.entry.note, link.note], &(&1 not in [nil, ""]))

  defp shared?(shared, link), do: Map.get(shared, link.entry_id, 1) > 1

  defp remove_confirm(shared, link) do
    if shared?(shared, link),
      do: gettext("Remove this entry from this play? The other plays keep it."),
      else: gettext("Delete this entry? No other play uses it.")
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :shown, visible(assigns.groups, assigns.q))

    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <header class="mb-6 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight text-base-content">
            {gettext("Bibliography")}
          </h1>
          <p class="mt-1 max-w-2xl text-sm text-base-content/60">
            {gettext(
              "Modern editions, criticism, translations and adaptations of this play. An entry shared with other plays is edited once for all of them."
            )}
          </p>
        </div>
        <div :if={is_nil(@editing) and not @adding} class="flex gap-2">
          <button
            id="add-existing-button"
            type="button"
            phx-click="open_add"
            class="btn btn-ghost btn-sm gap-1"
          >
            <.icon name="hero-link-mini" class="size-4" /> {gettext("Add existing")}
          </button>
          <button id="new-entry" type="button" phx-click="new" class="btn btn-primary btn-sm gap-1">
            <.icon name="hero-plus-mini" class="size-4" /> {gettext("New entry")}
          </button>
        </div>
      </header>

      <nav
        :if={@groups != []}
        aria-label={gettext("Bibliography sections")}
        class="z-10 -mx-4 mb-6 sm:sticky sm:top-10 flex flex-wrap items-center gap-2 border-b border-base-300 bg-base-100/90 px-4 py-2 backdrop-blur-sm"
      >
        <a
          :for={{kind, subgroups} <- @groups}
          href={"#kind-#{kind}"}
          class="badge badge-ghost gap-1.5 py-3 transition hover:badge-primary"
        >
          {PlayLabels.bibliography_kind_label(kind)}
          <span class="font-semibold tabular-nums">{count(subgroups)}</span>
        </a>
        <form
          id="bibliography-filter"
          phx-change="filter"
          phx-submit="filter"
          class="w-full sm:ml-auto sm:w-auto"
        >
          <label class="input input-sm input-bordered flex w-full items-center gap-2 sm:w-64">
            <.icon name="hero-magnifying-glass-mini" class="size-4 opacity-50" />
            <input
              type="search"
              name="q"
              value={@q}
              phx-debounce="200"
              placeholder={gettext("Filter")}
              aria-label={gettext("Filter the bibliography")}
              class="grow"
            />
          </label>
        </form>
      </nav>

      <section
        :if={@adding}
        id="add-existing"
        class="mb-6 rounded-box border border-primary/30 bg-base-100 p-5 shadow-md"
      >
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-sm font-semibold text-primary">
            {gettext("Add an entry another play already has")}
          </h2>
          <button
            type="button"
            phx-click="close_add"
            class="btn btn-ghost btn-xs btn-square"
            aria-label={gettext("Close")}
          >
            <.icon name="hero-x-mark-mini" class="size-4" />
          </button>
        </div>
        <form id="entry-search" phx-change="search" phx-submit="search">
          <input
            type="search"
            name="term"
            value={@term}
            phx-debounce="300"
            placeholder={gettext("Author, editor or title")}
            aria-label={gettext("Search the bibliography")}
            class="input input-bordered input-sm w-full"
            autofocus
          />
        </form>
        <ul class="mt-3 divide-y divide-base-300">
          <li :for={{entry, plays} <- @suggestions} class="flex items-start gap-3 py-3">
            <p class="flex-1 font-serif text-[15px] leading-relaxed">{Citation.html(entry)}</p>
            <span class="badge badge-ghost badge-sm whitespace-nowrap">
              {ngettext("1 play", "%{count} plays", plays)}
            </span>
            <button
              type="button"
              phx-click="link"
              phx-value-entry={entry.id}
              class="btn btn-primary btn-xs"
            >
              {gettext("Add")}
            </button>
          </li>
          <li :if={@term != "" and @suggestions == []} class="py-3 text-sm text-base-content/60">
            {gettext("Nothing matches.")}
          </li>
        </ul>
      </section>

      <section
        :if={@editing}
        id="entry-editor"
        class="mb-8 overflow-hidden rounded-box border border-primary/30 bg-base-100 shadow-md"
      >
        <div :if={@shared_with != []} role="alert" class="alert alert-warning rounded-none">
          <.icon name="hero-users-mini" class="size-5" />
          <span>
            {ngettext(
              "Shared with %{count} other play (%{codes}): changes appear on both.",
              "Shared with %{count} other plays (%{codes}): changes appear on all of them.",
              length(@shared_with),
              codes: Enum.map_join(@shared_with, ", ", & &1.code)
            )}
          </span>
        </div>
        <.form
          for={@form}
          id="entry-form"
          phx-change="validate"
          phx-submit="save"
          class="grid gap-6 p-5 lg:grid-cols-[minmax(0,1fr)_20rem]"
        >
          <div class="space-y-5">
            <div class="grid gap-4 sm:grid-cols-3">
              <.input
                field={@form[:kind]}
                type="select"
                label={gettext("Kind")}
                options={PlayLabels.bibliography_kind_options()}
              />
              <.input
                field={@form[:pub_type]}
                type="select"
                label={gettext("Type")}
                prompt={gettext("Not stated")}
                options={PlayLabels.pub_type_options()}
              />
              <.input
                field={@form[:language]}
                type="select"
                label={gettext("Language")}
                prompt={gettext("Not stated")}
                options={language_options()}
              />
            </div>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Article or chapter")}</legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <.input field={@form[:analytic_author]} label={gettext("Author")} />
                <.input field={@form[:analytic_title]} label={gettext("Title")} />
                <.input field={@form[:analytic_editors]} label={gettext("Editors")} />
                <.input field={@form[:analytic_translators]} label={gettext("Translators")} />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Book or journal")}</legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <.input field={@form[:monogr_author]} label={gettext("Author")} />
                <.input field={@form[:monogr_title]} label={gettext("Title")} />
                <.input field={@form[:monogr_editors]} label={gettext("Editors")} />
                <.input field={@form[:monogr_translators]} label={gettext("Translators")} />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Publication")}</legend>
              <div class="grid gap-3 sm:grid-cols-3">
                <.input field={@form[:pub_place]} label={gettext("Place")} />
                <.input field={@form[:publisher]} label={gettext("Publisher")} />
                <.input field={@form[:year_text]} label={gettext("Year")} />
                <.input field={@form[:edition]} label={gettext("Edition")} />
                <.input field={@form[:volume]} label={gettext("Volume")} />
                <.input field={@form[:volumes_total]} label={gettext("Number of volumes")} />
                <.input field={@form[:issue]} label={gettext("Issue")} />
                <.input field={@form[:pages]} label={gettext("Pages")} />
                <.input field={@form[:series]} label={gettext("Series")} />
                <.input field={@form[:original_title]} label={gettext("Original title")} />
                <.input field={@form[:url]} label={gettext("URL")} />
                <.input field={@form[:url_accessed_on]} label={gettext("Accessed on")} />
              </div>
              <div
                :if={Phoenix.HTML.Form.input_value(@form, :kind) == "modern_edition"}
                class="mt-3 grid gap-3 sm:grid-cols-3"
              >
                <.input field={@form[:siglum]} label={gettext("Siglum")} />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("In this play")}</legend>
              <div class="grid gap-3 sm:grid-cols-3">
                <.input
                  id="link_volume"
                  name="link[volume]"
                  value={@link_params["volume"]}
                  label={gettext("Volume")}
                />
                <.input
                  id="link_pages"
                  name="link[pages]"
                  value={@link_params["pages"]}
                  label={gettext("Pages")}
                />
                <.input
                  id="link_note"
                  name="link[note]"
                  value={@link_params["note"]}
                  label={gettext("Internal note")}
                />
              </div>
            </fieldset>

            <fieldset class="fieldset rounded-box border border-base-300 p-4">
              <legend class="fieldset-legend">{gettext("Notes")}</legend>
              <div class="grid gap-3 sm:grid-cols-2">
                <.input
                  field={@form[:public_note]}
                  type="textarea"
                  rows="2"
                  label={gettext("Printed note")}
                />
                <.input
                  field={@form[:note]}
                  type="textarea"
                  rows="2"
                  label={gettext("Internal note, for researchers only")}
                />
              </div>
            </fieldset>

            <div class="flex justify-end gap-2">
              <button type="button" phx-click="cancel" class="btn btn-ghost btn-sm">
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
            </div>
          </div>

          <aside class="self-start rounded-box bg-base-200/60 p-4 lg:sticky lg:top-24">
            <h3 class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/50">
              {gettext("As it will be printed")}
            </h3>
            <p id="citation-preview" class="font-serif text-[15px] leading-relaxed [&_a]:link">
              {@preview || gettext("Fill in an author, an editor or a title.")}
            </p>
          </aside>
        </.form>
      </section>

      <div
        :if={@groups == [] and is_nil(@editing)}
        class="rounded-box border border-dashed border-base-300 py-14 text-center text-base-content/60"
      >
        <.icon name="hero-book-open" class="mx-auto mb-3 size-12 opacity-30" />
        <p class="text-sm">{gettext("No bibliography for this play yet.")}</p>
      </div>

      <p :if={@groups != [] and @shown == []} class="py-10 text-center text-sm text-base-content/60">
        {gettext("Nothing matches the filter.")}
      </p>

      <section :for={{kind, subgroups} <- @shown} id={"kind-#{kind}"} class="mb-10 scroll-mt-24">
        <h2 class="mb-3 flex items-baseline gap-2 border-b border-base-300 pb-2 text-lg font-semibold">
          {PlayLabels.bibliography_kind_label(kind)}
          <span class="text-sm font-normal tabular-nums text-base-content/50">
            {count(subgroups)}
          </span>
        </h2>
        <div :for={{language, links} <- subgroups} class="mb-4">
          <h3
            :if={kind == "translation"}
            class="mb-1 mt-4 text-xs font-semibold uppercase tracking-wide text-base-content/50"
          >
            {PlayLabels.bibliography_language_label(language)}
          </h3>
          <ol class="space-y-1">
            <li
              :for={link <- links}
              id={"bib-#{link.id}"}
              class="group -mx-3 flex gap-3 rounded-lg px-3 py-2.5 transition hover:bg-base-200/60"
            >
              <div class="min-w-0 flex-1">
                <p class="font-serif text-[15px] leading-relaxed text-base-content [&_a]:link [&_a]:break-all">
                  {Citation.html(link.entry, link)}
                </p>
                <div class="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-base-content/55">
                  <span :if={link.entry.pub_type} class="badge badge-ghost badge-xs">
                    {PlayLabels.pub_type_label(link.entry.pub_type)}
                  </span>
                  <span
                    :if={shared?(@shared, link)}
                    class="badge badge-outline badge-primary badge-xs gap-1"
                  >
                    <.icon name="hero-link-micro" class="size-3" />
                    {gettext("Shared · %{count} plays", count: @shared[link.entry_id])}
                  </span>
                  <span :if={link.entry.siglum} class="badge badge-ghost badge-xs font-mono">
                    {link.entry.siglum}
                  </span>
                  <span
                    :for={note <- internal_notes(link)}
                    class="inline-flex items-center gap-1 italic"
                  >
                    <.icon name="hero-lock-closed-micro" class="size-3" />{note}
                  </span>
                </div>
              </div>
              <div class="flex shrink-0 items-start gap-0.5 opacity-60 transition group-hover:opacity-100 focus-within:opacity-100">
                <button
                  type="button"
                  phx-click="edit"
                  phx-value-id={link.id}
                  class="btn btn-ghost btn-xs btn-square"
                  aria-label={gettext("Edit")}
                >
                  <.icon name="hero-pencil-square-micro" class="size-4" />
                </button>
                <button
                  type="button"
                  phx-click="remove"
                  phx-value-id={link.id}
                  data-confirm={remove_confirm(@shared, link)}
                  class="btn btn-ghost btn-xs btn-square text-error"
                  aria-label={gettext("Remove")}
                >
                  <.icon name="hero-trash-micro" class="size-4" />
                </button>
              </div>
            </li>
          </ol>
        </div>
      </section>
    </div>
    """
  end
end
