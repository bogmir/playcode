defmodule PlaycodeWeb.Admin.ActivityLogLive do
  @moduledoc """
  /admin/activity-log: the audit log, newest first, filtered by action, resource, user and
  date, 50 to a page. Admins only.
  """

  use PlaycodeWeb, :live_view

  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :view_activity_log}}

  alias Playcode.ActivityLog
  alias Playcode.ActivityLog.Entry
  alias Playcode.Accounts

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    users = Accounts.list_users(per_page: 1000)

    {:ok,
     socket
     |> assign(:page_title, gettext("Activity Log"))
     |> assign(:entries, [])
     |> assign(:users, users)
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:filters, %{})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    filters = %{
      action: params["action"],
      resource_type: params["resource_type"],
      user_id: params["user_id"],
      from: params["from"],
      to: params["to"]
    }

    page = parse_page(params["page"])
    opts = build_opts(filters, page)

    total = ActivityLog.count_entries(opts)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)

    entries = ActivityLog.list_entries([{:page, page}, {:per_page, @per_page} | opts])

    {:noreply,
     socket
     |> assign(:entries, entries)
     |> assign(:filters, filters)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    query_params =
      %{
        action: params["action"],
        resource_type: params["resource_type"],
        user_id: params["user_id"],
        from: params["from"],
        to: params["to"]
      }
      |> Enum.reject(fn {_k, v} -> v == "" or is_nil(v) end)

    {:noreply, push_patch(socket, to: ~p"/admin/activity-log?#{query_params}")}
  end

  def handle_event("clear_filters", _params, socket) do
    {:noreply, push_patch(socket, to: ~p"/admin/activity-log")}
  end

  defp build_opts(filters, _page) do
    filters
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
    |> Enum.map(fn {k, v} -> {k, v} end)
  end

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(s) do
      {n, ""} -> max(1, n)
      _ -> 1
    end
  end

  defp page_params(filters, page) do
    filters
    |> Map.put(:page, page)
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
  end

  defp action_badge_class(action) do
    case action do
      "create" -> "badge-success"
      "update" -> "badge-info"
      "delete" -> "badge-error"
      "import" -> "badge-accent"
      "export" -> "badge-ghost"
      "role_change" -> "badge-warning"
      _ -> "badge-ghost"
    end
  end

  defp translate_action(action) do
    case action do
      "create" -> gettext("create")
      "update" -> gettext("update")
      "delete" -> gettext("delete")
      "import" -> gettext("import")
      "export" -> gettext("export")
      "role_change" -> gettext("role change")
      other -> other
    end
  end

  defp translate_resource_type(rt) do
    case rt do
      "play" -> gettext("play")
      "character" -> gettext("character")
      "division" -> gettext("division")
      "element" -> gettext("element")
      "note" -> gettext("note")
      "editor" -> gettext("editor")
      "source" -> gettext("source")
      "editorial_note" -> gettext("editorial note")
      "user" -> gettext("user")
      "bibliography_entry" -> gettext("bibliography entry")
      "play_bibliography" -> gettext("bibliography link")
      "play_witness" -> gettext("witness")
      other -> other
    end
  end

  defp format_datetime(nil), do: ""

  defp format_datetime(dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  end

  defp detail_summary(entry) do
    parts = []

    parts =
      if entry.metadata["format"] do
        parts ++ [entry.metadata["format"]]
      else
        parts
      end

    parts =
      if entry.metadata["filename"] do
        parts ++ [entry.metadata["filename"]]
      else
        parts
      end

    parts =
      if entry.metadata["title"] do
        parts ++ [entry.metadata["title"]]
      else
        parts
      end

    parts =
      if entry.metadata["name"] do
        parts ++ [entry.metadata["name"]]
      else
        parts
      end

    parts =
      if entry.metadata["person_name"] do
        parts ++ [entry.metadata["person_name"]]
      else
        parts
      end

    parts =
      if entry.changes && map_size(entry.changes) > 0 do
        keys =
          entry.changes
          |> Map.keys()
          |> Enum.join(", ")

        parts ++ [keys]
      else
        parts
      end

    Enum.join(parts, " · ")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("Activity Log")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Track who imported, edited, or exported plays.")}
        </p>
      </div>

      <form id="activity-filters" phx-change="filter" phx-submit="filter" class="mb-5">
        <div class="flex flex-wrap gap-3 items-end">
          <div class="form-control">
            <label class="label" for="activity-log-action">
              <span class="label-text text-xs">{gettext("Action")}</span>
            </label>
            <select id="activity-log-action" name="action" class="select select-bordered select-sm">
              <option value="">{gettext("All actions")}</option>
              <option :for={a <- Entry.actions()} value={a} selected={@filters[:action] == a}>
                {translate_action(a)}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label" for="activity-log-resource_type">
              <span class="label-text text-xs">{gettext("Resource")}</span>
            </label>
            <select
              id="activity-log-resource_type"
              name="resource_type"
              class="select select-bordered select-sm"
            >
              <option value="">{gettext("All resources")}</option>
              <option
                :for={rt <- Entry.resource_types()}
                value={rt}
                selected={@filters[:resource_type] == rt}
              >
                {translate_resource_type(rt)}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label" for="activity-log-user_id">
              <span class="label-text text-xs">{gettext("User")}</span>
            </label>
            <select id="activity-log-user_id" name="user_id" class="select select-bordered select-sm">
              <option value="">{gettext("All users")}</option>
              <option :for={u <- @users} value={u.id} selected={@filters[:user_id] == u.id}>
                {u.email}
              </option>
            </select>
          </div>

          <div class="form-control">
            <label class="label" for="activity-log-from">
              <span class="label-text text-xs">{gettext("From")}</span>
            </label>
            <input
              id="activity-log-from"
              type="date"
              name="from"
              value={@filters[:from]}
              class="input input-bordered input-sm"
            />
          </div>

          <div class="form-control">
            <label class="label" for="activity-log-to">
              <span class="label-text text-xs">{gettext("To")}</span>
            </label>
            <input
              id="activity-log-to"
              type="date"
              name="to"
              value={@filters[:to]}
              class="input input-bordered input-sm"
            />
          </div>

          <button type="button" phx-click="clear_filters" class="btn btn-ghost btn-sm">
            {gettext("Clear")}
          </button>
        </div>
      </form>

      <div
        class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm"
        tabindex="0"
        role="region"
        aria-label={gettext("Activity Log")}
      >
        <table class="table table-zebra">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/70">
              <th class="w-36">{gettext("When")}</th>
              <th>{gettext("User")}</th>
              <th class="w-24">{gettext("Action")}</th>
              <th class="w-28">{gettext("Resource")}</th>
              <th>{gettext("Play")}</th>
              <th>{gettext("Details")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :if={@entries == []}>
              <td colspan="6" class="text-center text-base-content/70 py-8">
                {gettext("No activity logged yet.")}
              </td>
            </tr>
            <tr :for={entry <- @entries} class="hover">
              <td class="text-xs text-base-content/70 whitespace-nowrap">
                {format_datetime(entry.inserted_at)}
              </td>
              <td class="text-sm">
                {if entry.user, do: entry.user.email, else: "—"}
              </td>
              <td>
                <span class={["badge badge-sm", action_badge_class(entry.action)]}>
                  {translate_action(entry.action)}
                </span>
              </td>
              <td class="text-sm">{translate_resource_type(entry.resource_type)}</td>
              <td class="text-sm">
                <.link
                  :if={entry.play}
                  navigate={~p"/admin/plays/#{entry.play_id}"}
                  class="link link-primary"
                >
                  {entry.play.code}
                </.link>
                <span :if={!entry.play && entry.metadata["code"]} class="text-base-content/70">
                  {entry.metadata["code"]}
                </span>
              </td>
              <td class="text-xs text-base-content/70 max-w-xs truncate">
                {detail_summary(entry)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@total_pages > 1} class="mt-4 flex items-center justify-center gap-2">
        <.link
          :if={@page > 1}
          patch={~p"/admin/activity-log?#{page_params(@filters, @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Previous")}
        </.link>
        <span class="text-sm text-base-content/70">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={~p"/admin/activity-log?#{page_params(@filters, @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Next")}
        </.link>
      </div>
    </div>
    """
  end
end
