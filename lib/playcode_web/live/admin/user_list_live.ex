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

  attr :user, :map, required: true

  defp state_badge(assigns) do
    ~H"""
    <span :if={Playcode.Accounts.protected_admin?(@user)} class="badge badge-sm badge-neutral">
      {gettext("Protected")}
    </span>
    <span :if={@user.deactivated_at} class="badge badge-sm badge-error">
      {gettext("Deactivated")}
    </span>
    <span
      :if={is_nil(@user.deactivated_at) and is_nil(@user.confirmed_at)}
      class="badge badge-sm badge-warning"
    >
      {gettext("Invited")}
    </span>
    <span :if={Playcode.Accounts.active?(@user)} class="badge badge-sm badge-success">
      {gettext("Active")}
    </span>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl px-4 py-8">
      <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 class="text-3xl font-semibold tracking-tight text-base-content">
            {gettext("User Management")}
          </h1>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext("Manage user roles and email confirmations.")}
          </p>
        </div>
      </div>

      <.form
        for={@invite_form}
        id="invite_form"
        phx-submit="invite"
        class="flex gap-2 items-end mb-6"
      >
        <div class="flex-1">
          <.input
            field={@invite_form[:email]}
            type="email"
            label={gettext("Invite by email")}
            placeholder="persona@uv.es"
            required
          />
        </div>
        <div>
          <.input
            field={@invite_form[:role]}
            type="select"
            label={gettext("Role")}
            options={[{gettext("Researcher"), "researcher"}, {gettext("Admin"), "admin"}]}
          />
        </div>
        <.button phx-disable-with={gettext("Inviting...")}>{gettext("Send invitation")}</.button>
      </.form>

      <form phx-change="search" phx-submit="search" class="mb-5">
        <input
          type="text"
          name="search"
          value={@search}
          placeholder={gettext("Search by email...")}
          phx-debounce="300"
          class="input input-bordered w-full md:max-w-md"
        />
      </form>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100 shadow-sm">
        <table class="table table-zebra">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/60">
              <th>{gettext("Email")}</th>
              <th class="w-28">{gettext("Role")}</th>
              <th class="w-40">{gettext("State")}</th>
              <th class="w-32">{gettext("Created")}</th>
              <th class="w-64 text-right">{gettext("Actions")}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={user <- @users} id={"user-#{user.id}"} class="hover">
              <td class="font-mono text-sm">
                {user.email}
                <span
                  :if={user.id == @current_user.id}
                  class="ml-1 badge badge-ghost badge-xs"
                >
                  {gettext("you")}
                </span>
              </td>
              <td>
                <%!-- Renders the listed user's role. Not an access decision:
                      those all go through Playcode.Authz.can?/3. --%>
                <span class={[
                  "badge badge-sm",
                  if(user.role == :admin, do: "badge-primary", else: "badge-ghost")
                ]}>
                  {user.role}
                </span>
              </td>
              <td class="space-x-1">
                <.state_badge user={user} />
              </td>
              <td class="text-sm text-base-content/60">
                {Calendar.strftime(user.inserted_at, "%Y-%m-%d")}
              </td>
              <td>
                <div class="flex items-center justify-end gap-1">
                  <%= if user.id != @current_user.id do %>
                    <%= if user.role == :admin do %>
                      <button
                        phx-click="set_role"
                        phx-value-id={user.id}
                        phx-value-role="researcher"
                        data-confirm={gettext("Demote %{email} to researcher?", email: user.email)}
                        class="btn btn-ghost btn-xs tooltip tooltip-left"
                        data-tip={gettext("Demote to researcher")}
                      >
                        <.icon name="hero-arrow-down-mini" class="size-4" />
                      </button>
                    <% else %>
                      <button
                        phx-click="set_role"
                        phx-value-id={user.id}
                        phx-value-role="admin"
                        data-confirm={gettext("Promote %{email} to admin?", email: user.email)}
                        class="btn btn-ghost btn-xs tooltip tooltip-left"
                        data-tip={gettext("Promote to admin")}
                      >
                        <.icon name="hero-arrow-up-mini" class="size-4" />
                      </button>
                    <% end %>
                  <% end %>
                  <button
                    :if={is_nil(user.confirmed_at) and is_nil(user.deactivated_at)}
                    class="btn btn-xs btn-ghost"
                    phx-click="resend_invite"
                    phx-value-id={user.id}
                  >
                    {gettext("Resend invitation")}
                  </button>
                  <button
                    :if={Playcode.Accounts.active?(user)}
                    class="btn btn-xs btn-ghost"
                    phx-click="force_logout"
                    phx-value-id={user.id}
                  >
                    {gettext("Force logout")}
                  </button>
                  <button
                    :if={is_nil(user.deactivated_at) and not Playcode.Accounts.protected_admin?(user)}
                    class="btn btn-xs btn-ghost text-error"
                    phx-click="deactivate"
                    phx-value-id={user.id}
                  >
                    {gettext("Deactivate")}
                  </button>
                  <button
                    :if={user.deactivated_at}
                    class="btn btn-xs btn-ghost"
                    phx-click="reactivate"
                    phx-value-id={user.id}
                  >
                    {gettext("Reactivate")}
                  </button>
                  <span
                    :if={Playcode.Accounts.protected_admin?(user)}
                    class="tooltip"
                    data-tip={gettext("Defined in ADMIN_EMAILS")}
                  >
                    <.icon name="hero-lock-closed-micro" class="size-4 text-base-content/40" />
                  </span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p
        :if={@users == []}
        class="mt-8 rounded-box border border-dashed border-base-300 py-10 text-center text-base-content/60"
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
        <span class="text-sm text-base-content/60">
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
    </div>
    """
  end
end
