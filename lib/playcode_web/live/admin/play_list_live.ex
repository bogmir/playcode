defmodule PlaycodeWeb.Admin.PlayListLive do
  @moduledoc """
  /admin/plays: every play, searchable, 50 to a page, with archiving, and the archived
  plays behind a filter, restorable.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.ActivityLog
  alias Playcode.Catalogue
  alias Playcode.PlayContent
  alias PlaycodeWeb.Admin.LiveHelpers

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Admin - Plays"))
     |> assign(:recent_plays, ActivityLog.recent_plays(socket.assigns.current_user.id))
     |> assign(:plays, [])
     |> assign(:search, "")
     |> assign(:status, nil)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:listening, MapSet.new())}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_page(params["page"])
    archived = params["archived"] == "1"
    status = if archived, do: nil, else: parse_status(params["status"])

    total = Catalogue.count_plays(search: search, archived: archived, status: status)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)

    plays =
      Catalogue.list_plays(
        search: search,
        page: page,
        per_page: @per_page,
        archived: archived,
        status: status
      )

    socket = if connected?(socket), do: listen_to(socket, plays), else: socket

    {:noreply,
     socket
     |> assign(:plays, plays)
     |> assign(:search, search)
     |> assign(:status, status)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)
     |> assign(:archived, archived)
     |> assign_counts()}
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    {:noreply,
     push_patch(socket, to: ~p"/admin/plays?#{list_params(search, socket.assigns.status)}")}
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

  defp reload(socket) do
    opts = [
      search: socket.assigns.search,
      archived: socket.assigns.archived,
      status: socket.assigns.status
    ]

    total = Catalogue.count_plays(opts)
    total_pages = max(1, ceil(total / @per_page))
    page = min(socket.assigns.page, total_pages)
    plays = Catalogue.list_plays(opts ++ [page: page, per_page: @per_page])

    assign(socket,
      plays: plays,
      page: page,
      total_pages: total_pages
    )
    |> assign_counts()
  end

  # The filter's counts follow the search; the heading's is the whole corpus.
  defp assign_counts(socket) do
    search = socket.assigns.search
    count = &Catalogue.count_plays(search: search, status: &1)

    assign(socket,
      plays_total: Catalogue.count_plays(),
      status_counts: %{all: count.(nil), draft: count.(:draft), complete: count.(:complete)},
      archived_count: Catalogue.count_plays(archived: true)
    )
  end

  defp parse_status("draft"), do: :draft
  defp parse_status("complete"), do: :complete
  defp parse_status(_), do: nil

  defp list_params(search, status, page \\ nil) do
    [search: search, status: status, page: page]
    |> Enum.reject(fn {_key, value} -> value in [nil, "", 1] end)
  end

  @impl true
  def handle_info({:play_content_changed, _play_id}, socket) do
    {:noreply, reload(socket)}
  end

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
      {:complete, gettext("Complete plays"), counts.complete}
    ]
  end

  defp status_label(%{deleted_at: deleted_at}) when not is_nil(deleted_at),
    do: gettext("Archived")

  defp status_label(%{is_complete: true}), do: gettext("Complete")
  defp status_label(_play), do: gettext("Draft")

  defp status_badge(%{deleted_at: deleted_at}) when not is_nil(deleted_at), do: "badge-outline"
  defp status_badge(%{is_complete: true}), do: "badge-success badge-soft"
  defp status_badge(_play), do: "badge-ghost"

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
        :if={@recent_plays != []}
        aria-label={gettext("Pick up where you left off")}
        class="mb-5"
      >
        <h2 class="mb-2 text-sm font-semibold text-base-content/70">
          {gettext("Pick up where you left off")}
        </h2>
        <ul class="flex flex-wrap gap-2">
          <li :for={play <- @recent_plays}>
            <.link navigate={~p"/admin/plays/#{play.id}"} class="btn btn-sm btn-ghost">
              {play.title}
            </.link>
          </li>
        </ul>
      </section>

      <div class="mb-5 flex flex-wrap items-center gap-3">
        <form phx-change="search" phx-submit="search" class="flex-1 md:max-w-md">
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
          :if={!@archived}
          aria-label={gettext("Status")}
          class="join"
        >
          <.link
            :for={{value, label, count} <- status_choices(@status_counts)}
            patch={~p"/admin/plays?#{list_params(@search, value)}"}
            class={["btn btn-sm join-item", @status == value && "btn-active"]}
            aria-current={@status == value && "page"}
          >
            {label} · {count}
          </.link>
        </nav>

        <.link
          :if={@archived_count > 0 or @archived}
          patch={if @archived, do: ~p"/admin/plays", else: ~p"/admin/plays?archived=1"}
          class={["btn btn-sm", @archived && "btn-active"]}
        >
          <.icon name="hero-archive-box-mini" class="size-4" />
          {gettext("Archived plays")}
          <span class="badge badge-sm">{@archived_count}</span>
        </.link>
      </div>

      <div
        class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm"
        tabindex="0"
        role="region"
        aria-label={gettext("Plays")}
      >
        <table class="table table-zebra">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/70">
              <th class="w-28 max-sm:hidden">{gettext("Code")}</th>
              <th>{gettext("Title")}</th>
              <th class="w-24">{gettext("Status")}</th>
              <th class="w-20 text-right max-sm:hidden">{gettext("Verses")}</th>
              <th :if={@archived} class="w-32 text-right">{gettext("Actions")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={play <- @plays} id={"play-#{play.id}"} class="hover">
              <td class="font-mono text-xs text-base-content/70 max-sm:hidden">{play.code}</td>
              <td>
                <%!-- Archived plays are hidden from every Catalogue reader, so
                      linking to their pages raises. Restore is the only action. --%>
                <.link
                  :if={is_nil(play.deleted_at)}
                  navigate={~p"/admin/plays/#{play.id}"}
                  class="link link-hover font-medium text-primary"
                >
                  {play.title}
                </.link>
                <span :if={play.deleted_at} class="font-medium text-base-content/70">
                  {play.title}
                </span>
                <p :if={play.author_name} class="text-xs text-base-content/70 mt-0.5">
                  {play.author_name}
                </p>
                <%!-- On a phone the code's column is left out; the code goes under the title. --%>
                <p class="sm:hidden font-mono text-xs text-base-content/70 break-all">
                  {play.code}
                </p>
              </td>
              <td>
                <span class={["badge badge-sm", status_badge(play)]}>
                  {status_label(play)}
                </span>
              </td>
              <td class="text-sm text-right tabular-nums text-base-content/70 max-sm:hidden">
                {play.verse_count || "—"}
              </td>
              <td :if={@archived}>
                <div class="flex items-center justify-end gap-1">
                  <button
                    :if={play.deleted_at}
                    phx-click="restore"
                    phx-value-id={play.id}
                    class="btn btn-ghost btn-xs text-success tooltip tooltip-left"
                    aria-label={gettext("Restore")}
                    data-tip={gettext("Restore")}
                  >
                    <.icon name="hero-arrow-uturn-left-mini" class="size-4" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@plays == []}
        class="mt-8 rounded-box border border-dashed border-base-300 py-10 text-center text-base-content/70"
      >
        {gettext("No plays yet. Import a TEI-XML file or create a new play.")}
      </p>

      <%!-- Pagination --%>
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
