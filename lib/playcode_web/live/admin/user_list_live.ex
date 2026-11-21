defmodule PlaycodeWeb.Admin.UserListLive do
  @moduledoc """
  /admin/users: invite, resend an invitation, deactivate, reactivate, force logout and
  change a role. The accounts in `ADMIN_EMAILS` are protected from all of it. Admins only.
  """

  use PlaycodeWeb, :live_view

  # Stricter than the live_session's :view_admin, declared here so admin
  # sections still navigate without a full page reload.
  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :manage_users}}

  require Logger

  alias Playcode.Accounts
  alias Playcode.Accounts.AdminBootstrap
  alias Playcode.ActivityLog

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Admin - Users"))
     |> assign(:users, [])
     |> assign(:search, "")
     |> assign(:page, 1)
     |> assign(:total_pages, 1)
     |> assign(:invite_form, to_form(%{"email" => "", "role" => "researcher"}, as: :invite))}
  end

  @impl true
  def handle_params(params, _url, socket) do
    search = params["search"] || ""
    page = parse_page(params["page"])

    total = Accounts.count_users(search: search)
    total_pages = max(1, ceil(total / @per_page))
    page = min(page, total_pages)

    {:noreply,
     socket
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)
     |> load_users()}
  end

  defp load_users(socket) do
    users =
      Accounts.list_users(
        search: socket.assigns.search,
        page: socket.assigns.page,
        per_page: @per_page
      )

    assign(socket, :users, users)
  end

  @impl true
  def handle_event("search", %{"search" => search}, socket) do
    params = if search == "", do: [], else: [search: search]
    {:noreply, push_patch(socket, to: ~p"/admin/users?#{params}")}
  end

  def handle_event("set_role", %{"id" => id, "role" => role}, socket) do
    user = Accounts.get_user!(id)

    cond do
      Accounts.protected_admin?(user) ->
        {:noreply, put_flash(socket, :error, protected_message())}

      user.id == socket.assigns.current_user.id ->
        {:noreply, put_flash(socket, :error, gettext("You cannot change your own role."))}

      true ->
        old_role = user.role

        case Accounts.update_user_role(user, role) do
          {:ok, _user} ->
            ActivityLog.log!(%{
              user_id: socket.assigns.current_user.id,
              action: "role_change",
              resource_type: "user",
              resource_id: user.id,
              changes: %{"role" => [to_string(old_role), role]},
              metadata: %{email: user.email}
            })

            {:noreply, load_users(socket)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, gettext("Failed to update role."))}
        end
    end
  end

  def handle_event("invite", %{"invite" => %{"email" => email, "role" => role}}, socket) do
    role = String.to_existing_atom(role)

    case Accounts.invite_user(email, role, socket.assigns.current_user) do
      {:ok, user, token} ->
        {:noreply, socket |> load_users() |> flash_delivery(user, token)}

      {:error, :already_active} ->
        {:noreply, put_flash(socket, :error, gettext("That account already exists."))}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("That email address is not valid."))}
    end
  end

  def handle_event("resend_invite", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    case Accounts.invite_user(user.email, user.role, socket.assigns.current_user) do
      {:ok, user, token} ->
        {:noreply, flash_delivery(socket, user, token)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Could not resend that invitation."))}
    end
  end

  def handle_event("deactivate", %{"id" => id}, socket) do
    user = Accounts.get_user!(id)

    if Accounts.protected_admin?(user) do
      {:noreply, put_flash(socket, :error, protected_message())}
    else
      {:ok, _} = Accounts.deactivate_user(user)

      {:noreply, socket |> put_flash(:info, gettext("Account deactivated.")) |> load_users()}
    end
  end

  def handle_event("reactivate", %{"id" => id}, socket) do
    {:ok, _} = id |> Accounts.get_user!() |> Accounts.reactivate_user()

    {:noreply, socket |> put_flash(:info, gettext("Account reactivated.")) |> load_users()}
  end

  def handle_event("force_logout", %{"id" => id}, socket) do
    :ok = id |> Accounts.get_user!() |> Accounts.force_logout()

    {:noreply, put_flash(socket, :info, gettext("All sessions ended."))}
  end

  # The invitation row is written before the mail goes out, so a relay that
  # refuses it must not be reported as a sent invitation: the invitee would be
  # waiting for a link nobody can produce. The account survives, so the fix is
  # to repair delivery and resend.
  defp flash_delivery(socket, user, token) do
    case Accounts.deliver_invite(user, token, &AdminBootstrap.invite_url/1) do
      {:ok, _email} ->
        put_flash(socket, :info, gettext("Invitation sent to %{email}.", email: user.email))

      {:error, reason} ->
        Logger.error("invitation to #{user.email} was not delivered: #{inspect(reason)}")

        put_flash(
          socket,
          :error,
          gettext(
            "Invitation created, but the email could not be sent to %{email}. Resend it once mail delivery works.",
            email: user.email
          )
        )
    end
  end

  defp protected_message do
    gettext("This administrator is defined in ADMIN_EMAILS and cannot be changed here.")
  end

  defp parse_page(nil), do: 1

  defp parse_page(s) do
    case Integer.parse(s) do
      {n, ""} -> max(1, n)
      _ -> 1
    end
  end

  defp page_params("", page), do: [page: page]
  defp page_params(search, page), do: [search: search, page: page]

  defp role_options, do: [{role_label(:researcher), "researcher"}, {role_label(:admin), "admin"}]

  defp role_label(:admin), do: pgettext("role", "Admin")
  defp role_label(:researcher), do: pgettext("role", "Researcher")

  attr :user, :map, required: true
  attr :current_user, :map, required: true

  defp user_row(assigns) do
    status = Accounts.status(assigns.user)
    protected? = Accounts.protected_admin?(assigns.user)

    assigns =
      assign(assigns,
        status: status,
        protected?: protected?,
        can_change_role?:
          assigns.user.id != assigns.current_user.id and not protected? and status != :deactivated,
        can_log_out?: status == :active,
        can_deactivate?: status != :deactivated and not protected?
      )

    ~H"""
    <li
      id={"user-#{@user.id}"}
      class="flex flex-wrap items-center gap-x-3 gap-y-2 px-4 py-3 first:rounded-t-box last:rounded-b-box hover:bg-base-200"
    >
      <span
        aria-hidden="true"
        class={[
          "grid size-8 shrink-0 place-items-center rounded-full text-sm font-semibold",
          if(@user.role == :admin, do: "bg-primary/20 text-primary", else: "bg-base-300"),
          @status == :deactivated && "opacity-50"
        ]}
      >
        {@user.email |> String.first() |> String.upcase()}
      </span>
      <div class="min-w-48 flex-1">
        <p class={["break-all font-medium", @status == :deactivated && "text-base-content/70"]}>
          {@user.email}
          <span
            :if={@user.id == @current_user.id}
            class="ml-1 rounded-full border border-base-300 px-1.5 text-xs font-normal text-base-content/70"
          >
            {gettext("you")}
          </span>
        </p>
        <p class="flex flex-wrap items-center gap-x-1.5 text-xs text-base-content/70">
          <span>{role_label(@user.role)}</span>
          <span :if={@protected?} class="tooltip" data-tip={gettext("Defined in ADMIN_EMAILS")}>
            <.icon name="hero-lock-closed-micro" class="size-3.5" />
            <span class="sr-only">{gettext("Defined in ADMIN_EMAILS")}</span>
          </span>
          <span aria-hidden="true">·</span>
          <span :if={@status == :active} class="text-success">{gettext("Active")}</span>
          <span :if={@status == :invited} class="text-warning">{gettext("Invited")}</span>
          <span :if={@status == :deactivated}>{gettext("Deactivated")}</span>
          <span aria-hidden="true">·</span>
          <span class="tabular-nums">{Calendar.strftime(@user.inserted_at, "%Y-%m-%d")}</span>
        </p>
      </div>
      <div class="ml-auto flex shrink-0 items-center gap-1">
        <button
          :if={@can_change_role? and @user.role == :researcher}
          phx-click="set_role"
          phx-value-id={@user.id}
          phx-value-role="admin"
          data-confirm={gettext("Promote %{email} to admin?", email: @user.email)}
          class="btn btn-ghost btn-xs"
        >
          {gettext("Make admin")}
        </button>
        <button
          :if={@can_change_role? and @user.role == :admin}
          phx-click="set_role"
          phx-value-id={@user.id}
          phx-value-role="researcher"
          data-confirm={gettext("Demote %{email} to researcher?", email: @user.email)}
          class="btn btn-ghost btn-xs"
        >
          {gettext("Make researcher")}
        </button>
        <button
          :if={@status == :invited}
          phx-click="resend_invite"
          phx-value-id={@user.id}
          class="btn btn-primary btn-soft btn-xs"
        >
          {gettext("Resend invitation")}
        </button>
        <button
          :if={@status == :deactivated}
          phx-click="reactivate"
          phx-value-id={@user.id}
          class="btn btn-primary btn-soft btn-xs"
        >
          {gettext("Reactivate")}
        </button>
        <div :if={@can_log_out? or @can_deactivate?} class="dropdown dropdown-end">
          <div
            tabindex="0"
            role="button"
            class="btn btn-ghost btn-xs btn-square"
            aria-label={gettext("More actions for %{email}", email: @user.email)}
          >
            <.icon name="hero-ellipsis-horizontal-mini" class="size-4" />
          </div>
          <ul
            tabindex="0"
            class="dropdown-content menu z-10 mt-1 w-52 rounded-box border border-base-300 bg-base-100 p-1 shadow-lg"
          >
            <li :if={@can_log_out?}>
              <button phx-click="force_logout" phx-value-id={@user.id}>
                <.icon name="hero-arrow-right-start-on-rectangle-micro" class="size-4" />
                {gettext("Log out everywhere")}
              </button>
            </li>
            <li :if={@can_deactivate?}>
              <button phx-click="deactivate" phx-value-id={@user.id} class="text-error">
                <.icon name="hero-no-symbol-micro" class="size-4" />
                {gettext("Deactivate")}
              </button>
            </li>
          </ul>
        </div>
      </div>
    </li>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page width={:form}>
      <.page_header>
        {gettext("Users")}
        <:subtitle>{gettext("Who can open Playcode, and what they may do.")}</:subtitle>
      </.page_header>

      <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
        <.form
          for={@invite_form}
          id="invite_form"
          phx-submit="invite"
          class="join w-full sm:w-auto sm:flex-1 sm:max-w-xl"
        >
          <input
            type="email"
            id={@invite_form[:email].id}
            name={@invite_form[:email].name}
            value={@invite_form[:email].value}
            placeholder="persona@uv.es"
            aria-label={gettext("Invite by email")}
            required
            class="input join-item min-w-0 flex-1"
          />
          <select
            id={@invite_form[:role].id}
            name={@invite_form[:role].name}
            aria-label={gettext("Role")}
            class="select join-item w-36"
          >
            {Phoenix.HTML.Form.options_for_select(role_options(), @invite_form[:role].value)}
          </select>
          <button class="btn btn-primary join-item" phx-disable-with={gettext("Inviting...")}>
            {gettext("Invite")}
          </button>
        </.form>

        <form phx-change="search" phx-submit="search" role="search" class="w-full sm:w-60">
          <label class="input w-full">
            <.icon name="hero-magnifying-glass-mini" class="size-4 text-base-content/70" />
            <input
              type="search"
              name="search"
              value={@search}
              placeholder={gettext("Search by email...")}
              aria-label={gettext("Search by email...")}
              phx-debounce="300"
            />
          </label>
        </form>
      </div>

      <ul
        :if={@users != []}
        aria-label={gettext("Users")}
        class="divide-y divide-base-300 rounded-box border border-base-300 bg-base-100 shadow-sm"
      >
        <.user_row :for={user <- @users} user={user} current_user={@current_user} />
      </ul>

      <p
        :if={@users == []}
        class="mt-8 rounded-box border border-dashed border-base-300 py-10 text-center text-base-content/70"
      >
        {gettext("No users found.")}
      </p>

      <div :if={@total_pages > 1} class="mt-6 flex items-center justify-center gap-4">
        <.link
          :if={@page > 1}
          patch={~p"/admin/users?#{page_params(@search, @page - 1)}"}
          class="btn btn-sm btn-ghost"
        >
          <.icon name="hero-chevron-left-mini" class="size-4" />{gettext("Previous")}
        </.link>
        <span class="text-sm text-base-content/70">
          {gettext("Page %{page} of %{total}", page: @page, total: @total_pages)}
        </span>
        <.link
          :if={@page < @total_pages}
          patch={~p"/admin/users?#{page_params(@search, @page + 1)}"}
          class="btn btn-sm btn-ghost"
        >
          {gettext("Next")}<.icon name="hero-chevron-right-mini" class="size-4" />
        </.link>
      </div>
    </.page>
    """
  end
end
