defmodule PlaycodeWeb.Admin.PlayListLive do
  @moduledoc """
  /admin/plays: every play, searchable, 50 to a page, with archiving, and the archived
  plays behind a filter, restorable, and deletable for good by an admin who types the
  play's code.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Accounts
  alias Playcode.ActivityLog
  alias Playcode.Authz
  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.Export.{SiteBuilder, SiteStatus}
  alias Playcode.PlayContent
  alias PlaycodeWeb.Admin.LiveHelpers
  alias PlaycodeWeb.PlayLabels

  @per_page 50
  @site_states [:waiting, :changed, :leaving]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: SiteBuilder.subscribe()

    {:ok,
     socket
     |> assign(:page_title, gettext("Admin - Plays"))
     |> assign(:recent_plays, ActivityLog.recent_plays(socket.assigns.current_user.id))
     |> assign(:rows, [])
     |> assign(:search, "")
     |> assign(:status, nil)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:purging, nil)
     |> assign(:can_purge, Authz.can?(socket.assigns.current_user, :purge_play))
     |> assign(:scope, hide_test: not Authz.can?(socket.assigns.current_user, :see_test_plays))
     |> assign(:listening, MapSet.new())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_page(params["page"])
    archived = params["archived"] == "1"
    status = if archived, do: nil, else: parse_status(params["status"])

    {:noreply,
     socket
     |> assign(search: search, status: status, page: page, archived: archived)
     |> reload()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/plays?#{list_params(search, socket.assigns.status)}")}
  end

  def handle_event("close_welcome", _params, socket) do
    {:ok, user} = Accounts.close_welcome(socket.assigns.current_user)
    {:noreply, assign(socket, :current_user, user)}
  end

  def handle_event("restore", %{"id" => id}, socket) do
    play = Catalogue.get_play!(id, include_deleted: true)

    {:ok, _} = Catalogue.restore_play(play)

    LiveHelpers.log_activity(socket, "update", "play", play.id, %{
      title: play.title,
      code: play.code,
      restored: true
    })

    {:noreply, reload(socket)}
  end

  def handle_event("open_purge", %{"id" => id}, socket) do
    play = Enum.find(Catalogue.list_plays(archived: true), &(&1.id == id))
    {:noreply, assign(socket, purging: play, purge_code: "")}
  end

  def handle_event("purge_typed", %{"code" => code}, socket),
    do: {:noreply, assign(socket, :purge_code, code)}

  def handle_event("close_purge", _params, socket), do: {:noreply, assign(socket, :purging, nil)}

  def handle_event("purge", %{"code" => code}, socket) do
    %{purging: play, can_purge: can_purge} = socket.assigns

    if can_purge and play != nil and code == play.code do
      LiveHelpers.log_activity(socket, "delete", "play", play.id, %{
        title: play.title,
        code: play.code,
        purged: true
      })

      {:ok, _} = Catalogue.purge_play(play)

      {:noreply,
       socket
       |> assign(:purging, nil)
       |> put_flash(:info, gettext("%{title} was deleted.", title: play.title))
       |> reload()}
    else
      {:noreply, socket}
    end
  end

  defp reload(socket) do
    %{search: search, status: status, archived: archived, page: page} = socket.assigns
    live = SiteStatus.live()
    site_codes = site_codes(live)

    {rows, page, total_pages} =
      rows(search, filter(status, site_codes), archived, page, socket.assigns.scope)

    socket = if connected?(socket), do: listen_to(socket, Enum.map(rows, & &1.play)), else: socket

    socket
    |> assign(rows: rows, page: page, total_pages: total_pages, live: live)
    |> assign_counts(site_codes)
  end

  defp site_codes(live) do
    grouped = Enum.group_by(Catalogue.list_plays(), &SiteStatus.state(&1, live), & &1.code)
    Map.new(@site_states, &{&1, Map.get(grouped, &1, [])})
  end

  defp filter(status, site_codes) when status in @site_states, do: {:codes, site_codes[status]}
  defp filter(status, _site_codes), do: status

  # Archived plays stay a flat list; the rest are listed by family, a page per 50 families.
  defp rows(search, _status, true, page, scope) do
    total_pages = total_pages(Catalogue.count_plays([search: search, archived: true] ++ scope))
    page = min(page, total_pages)

    plays =
      Catalogue.list_plays(
        [search: search, archived: true, page: page, per_page: @per_page] ++ scope
      )

    {for(play <- plays, do: %{play: play, derived?: false, match?: true}), page, total_pages}
  end

  defp rows(search, status, false, page, scope) do
    {families, total} =
      Catalogue.list_families(
        [search: search, status: status, page: page, per_page: @per_page] ++ scope
      )

    total_pages = total_pages(total)

    if page > total_pages do
      rows(search, status, false, total_pages, scope)
    else
      rows =
        Enum.flat_map(families, fn family ->
          [Map.put(Map.delete(family, :derived), :derived?, false)] ++
            for(row <- family.derived, do: Map.put(row, :derived?, true))
        end)

      {rows, page, total_pages}
    end
  end

  defp total_pages(count), do: max(1, ceil(count / @per_page))

  # The filter's counts follow the search; the heading's is the whole corpus.
  defp assign_counts(socket, site_codes) do
    search = socket.assigns.search
    scope = socket.assigns.scope
    count = &Catalogue.count_plays([search: search, status: &1] ++ scope)

    assign(socket,
      plays_total: Catalogue.count_plays(scope),
      status_counts: %{
        all: count.(nil),
        draft: count.(:draft),
        complete: count.(:complete),
        no_text: count.(:no_text)
      },
      archived_count: Catalogue.count_plays([archived: true] ++ scope),
      site_counts: Map.new(@site_states, &{&1, count.({:codes, site_codes[&1]})})
    )
  end

  defp parse_status("draft"), do: :draft
  defp parse_status("complete"), do: :complete
  defp parse_status("no_text"), do: :no_text

  defp parse_status(state) when state in ~w(waiting changed leaving),
    do: String.to_existing_atom(state)

  defp parse_status(_), do: nil

  defp list_params(search, status, page \\ nil) do
    [search: search, status: status, page: page]
    |> Enum.reject(fn {_key, value} -> value in [nil, "", 1] end)
  end

  @impl true
  def handle_info({:play_content_changed, _play_id}, socket) do
    {:noreply, reload(socket)}
  end

  def handle_info({:site_builder, :done, _job, _result}, socket), do: {:noreply, reload(socket)}

  # The rest of the site's topic: a shown play's edit already arrives on its own topic.
  def handle_info(message, socket) when elem(message, 0) in [:site_builder, :play_changed],
    do: {:noreply, socket}

  # Listens once to each play shown, and stops for the ones no longer shown. Subscribing
  # again on every params change stacked subscriptions, and each copy reloaded the list
  # once more per edit.
  defp listen_to(socket, plays) do
    shown = MapSet.new(plays, & &1.id)
    listening = socket.assigns.listening

    for id <- MapSet.difference(listening, shown), do: PlayContent.unsubscribe(id)
    for id <- MapSet.difference(shown, listening), do: PlayContent.subscribe(id)

    assign(socket, :listening, shown)
  end

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(s) do
      {n, ""} -> max(1, n)
      _ -> 1
    end
  end

  defp status_choices(counts) do
    [
      {nil, gettext("All"), counts.all},
      {:draft, gettext("Drafts"), counts.draft},
      {:complete, pgettext("plays", "Complete"), counts.complete},
      {:no_text, gettext("No text"), counts.no_text}
    ]
  end

  # A site state is named only while a play is in it, or while it is the chosen filter.
  defp site_notices(counts, status) do
    for state <- @site_states, counts[state] > 0 or state == status, do: {state, counts[state]}
  end

  defp site_notice(:waiting, count),
    do:
      ngettext(
        "%{count} play waits to be published",
        "%{count} plays wait to be published",
        count
      )

  defp site_notice(:changed, count),
    do:
      ngettext(
        "%{count} play has unpublished changes",
        "%{count} plays have unpublished changes",
        count
      )

  defp site_notice(:leaving, count),
    do:
      ngettext(
        "%{count} play leaves the site with the next Publish",
        "%{count} plays leave the site with the next Publish",
        count
      )

  defp status_label(%{deleted_at: deleted_at}) when not is_nil(deleted_at),
    do: gettext("Archived")

  defp status_label(%{is_complete: true}), do: gettext("Complete")
  defp status_label(_play), do: gettext("Draft")

  defp status_badge(%{deleted_at: deleted_at}) when not is_nil(deleted_at), do: "badge-ghost"
  defp status_badge(%{is_complete: true}), do: "badge-success badge-soft"
  defp status_badge(_play), do: "badge-outline"

  defp kind_and_language(%{relationship_type: kind, language: language}) do
    [kind && PlayLabels.relationship_type_label(kind), language && String.upcase(language)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" · ")
  end

  defp verses(play) do
    cond do
      not Play.has_text?(play) -> "—"
      Play.form(play) == "prose" -> gettext("prose")
      true -> play.verse_count
    end
  end

  attr :row, :map, required: true
  attr :archived, :boolean, required: true
  attr :can_purge, :boolean, required: true
  attr :live, :map, required: true

  defp play_row(assigns) do
    assigns = assign(assigns, assigns.row)

    ~H"""
    <tr id={"play-#{@play.id}"} class="hover:bg-base-200">
      <%!-- Some codes run to 90 characters; cut, they leave the title its room. --%>
      <td class="font-mono text-xs text-base-content/70 max-sm:hidden">
        <span class="block max-w-56 truncate" title={@play.code}>{@play.code}</span>
      </td>
      <td>
        <div class={@derived? && "ml-2 border-l-2 border-base-300 pl-4"}>
          <%!-- Archived plays are hidden from every Catalogue reader, so
                linking to their pages raises. Restore and delete are the only actions. --%>
          <span :if={@derived?} class="badge badge-sm border-0 bg-base-300 mr-1.5 align-[1px]">
            {kind_and_language(@play)}
          </span>
          <.link
            :if={is_nil(@play.deleted_at)}
            navigate={~p"/admin/plays/#{@play.id}"}
            class={[
              "link link-hover font-medium",
              if(@match?, do: "text-primary", else: "text-base-content/70")
            ]}
          >
            {@play.title}
          </.link>
          <span :if={@play.deleted_at} class="font-medium text-base-content/70">
            {@play.title}
          </span>
          <p class="mt-0.5 text-xs text-base-content/70">
            {@play.author_name}
          </p>
          <%!-- On a phone the code's column is left out; the code goes under the title. --%>
          <p class="sm:hidden font-mono text-xs text-base-content/70 break-all">
            {@play.code}
          </p>
        </div>
      </td>
      <td>
        <div class="flex flex-wrap gap-1">
          <span class={["badge badge-sm whitespace-nowrap", status_badge(@play)]}>
            {status_label(@play)}
          </span>
          <span
            :if={not Play.has_text?(@play)}
            class="badge badge-sm badge-soft badge-warning whitespace-nowrap"
          >
            {gettext("No text")}
          </span>
        </div>
      </td>
      <td class="max-sm:hidden">
        <.site_badge
          :if={SiteStatus.state(@play, @live) != :draft}
          state={SiteStatus.state(@play, @live)}
        />
      </td>
      <td class="text-sm text-right tabular-nums text-base-content/70 max-sm:hidden">
        {verses(@play)}
      </td>
      <td :if={@archived}>
        <div class="flex items-center justify-end gap-1">
          <button
            :if={@play.deleted_at}
            phx-click="restore"
            phx-value-id={@play.id}
            class="btn btn-ghost btn-xs text-success tooltip tooltip-left"
            aria-label={gettext("Restore")}
            data-tip={gettext("Restore")}
          >
            <.icon name="hero-arrow-uturn-left-mini" class="size-4" />
          </button>
          <button
            :if={@can_purge && @play.deleted_at}
            phx-click="open_purge"
            phx-value-id={@play.id}
            class="btn btn-ghost btn-xs text-error tooltip tooltip-left"
            aria-label={gettext("Delete permanently")}
            data-tip={gettext("Delete permanently")}
          >
            <.icon name="hero-trash-mini" class="size-4" />
          </button>
        </div>
      </td>
    </tr>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page>
      <.page_header>
        {gettext("Plays")} · {@plays_total}
        <:actions>
          <div class="flex gap-2">
            <.link
              navigate={~p"/admin/plays/import"}
              class="btn btn-sm btn-outline btn-primary"
            >
              {gettext("Import TEI-XML")}
            </.link>
            <.link
              navigate={~p"/admin/plays/new"}
              class="btn btn-sm btn-primary"
            >
              {gettext("New Play")}
            </.link>
          </div>
        </:actions>
      </.page_header>

      <section
        :if={is_nil(@current_user.welcome_closed_at)}
        aria-label={gettext("Getting started")}
        class="mb-5 flex items-start gap-4 rounded-box border border-primary/30 bg-primary/5 p-4"
      >
        <ol class="flex-1 list-inside list-decimal space-y-1 text-sm">
          <li>{gettext("Find a play in the list, or import one.")}</li>
          <li>{gettext("Edit its record and its text.")}</li>
          <li>{gettext("Mark it complete, and it goes online with the next Publish.")}</li>
        </ol>
        <button phx-click="close_welcome" class="btn btn-sm btn-ghost">{gettext("Got it")}</button>
      </section>

      <section
        :if={@recent_plays != []}
        aria-label={gettext("Recent plays")}
        class="mb-4 flex flex-wrap items-baseline gap-x-4 gap-y-1 text-sm"
      >
        <h2 class="font-semibold text-base-content/70">{gettext("Recent")}</h2>
        <ul class="contents">
          <li :for={play <- @recent_plays}>
            <.link navigate={~p"/admin/plays/#{play.id}"} class="link link-hover link-primary">
              {play.title}
            </.link>
          </li>
        </ul>
      </section>

      <form phx-change="search" phx-submit="search" class="mb-4 max-w-md">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search plays...")}
          phx-debounce="300"
          class="input input-bordered w-full"
        />
      </form>

      <nav
        aria-label={gettext("Status")}
        class="tabs tabs-border mb-4 flex-nowrap overflow-x-auto overflow-y-hidden border-b border-base-300"
      >
        <.link
          :for={{value, label, count} <- status_choices(@status_counts)}
          patch={~p"/admin/plays?#{list_params(@search, value)}"}
          class={["tab shrink-0 gap-1.5", !@archived && @status == value && "tab-active"]}
          aria-current={!@archived && @status == value && "page"}
        >
          {label} <span class="text-base-content/70">{count}</span>
        </.link>
        <.link
          :if={@archived_count > 0 or @archived}
          patch={if @archived, do: ~p"/admin/plays", else: ~p"/admin/plays?archived=1"}
          class={["tab ml-auto shrink-0 gap-1.5", @archived && "tab-active"]}
          aria-current={@archived && "page"}
        >
          {pgettext("plays", "Archived")} <span class="text-base-content/70">{@archived_count}</span>
        </.link>
      </nav>

      <nav
        :if={!@archived and site_notices(@site_counts, @status) != []}
        aria-label={gettext("Site")}
        class="mb-4 flex flex-wrap gap-x-4 gap-y-1 rounded-box bg-warning/10 px-3 py-2 text-sm"
      >
        <.link
          :for={{state, count} <- site_notices(@site_counts, @status)}
          patch={~p"/admin/plays?#{list_params(@search, state)}"}
          class={["link text-warning", @status == state && "font-semibold"]}
          aria-current={@status == state && "page"}
        >
          {site_notice(state, count)}
        </.link>
      </nav>

      <div
        class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm"
        tabindex="0"
        role="region"
        aria-label={gettext("Plays")}
      >
        <table class="table">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/70">
              <th class="max-sm:hidden">{gettext("Code")}</th>
              <%!-- The title takes the width the others leave. --%>
              <th class="w-full">{gettext("Title")}</th>
              <th>{gettext("Status")}</th>
              <th class="max-sm:hidden">{gettext("Site")}</th>
              <th class="text-right max-sm:hidden">{gettext("Verses")}</th>
              <th :if={@archived} class="text-right">{gettext("Actions")}</th>
            </tr>
          </thead>
          <tbody>
            <.play_row
              :for={row <- @rows}
              row={row}
              archived={@archived}
              can_purge={@can_purge}
              live={@live}
            />
          </tbody>
        </table>
      </div>

      <.modal :if={@purging} id="purge-modal" on_cancel={JS.push("close_purge")}>
        <h3 id="purge-modal-title" class="text-lg font-semibold">
          {gettext("Delete %{title} permanently?", title: @purging.title)}
        </h3>
        <p class="mt-3 text-sm">
          {gettext(
            "Its text, notes, records and history go, and cannot be brought back. Its translations, adaptations and versions stay, without their original."
          )}
        </p>
        <.form for={%{}} phx-change="purge_typed" phx-submit="purge" class="mt-4 space-y-3">
          <label for="purge-code" class="block text-sm">
            {gettext("To confirm, type the play's code:")}
            <span class="font-mono font-semibold break-all">{@purging.code}</span>
          </label>
          <input
            id="purge-code"
            type="text"
            name="code"
            value={@purge_code}
            autocomplete="off"
            spellcheck="false"
            class="input input-bordered w-full font-mono"
          />
          <button
            type="submit"
            class="btn btn-error w-full"
            disabled={@purge_code != @purging.code}
          >
            {gettext("Delete this play")}
          </button>
        </.form>
      </.modal>

      <p
        :if={@rows == []}
        class="mt-8 rounded-box border border-dashed border-base-300 py-10 text-center text-base-content/70"
      >
        {gettext("No plays yet. Import a TEI-XML file or create a new play.")}
      </p>

      <div :if={@total_pages > 1} class="mt-6 flex items-center justify-center gap-4">
        <.link
          :if={@page > 1}
          patch={~p"/admin/plays?#{list_params(@search, @status, @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" />{gettext("Previous")}
        </.link>
        <span class="text-sm text-base-content/70">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={~p"/admin/plays?#{list_params(@search, @status, @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Next")}<.icon name="hero-chevron-right-mini" class="size-4" />
        </.link>
      </div>
    </.page>
    """
  end
end
