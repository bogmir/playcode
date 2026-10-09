defmodule PlaycodeWeb.UserSettingsLive do
  @moduledoc """
  /users/settings: change the password, and see or revoke active sessions. The email
  address is read-only: only an admin changes it.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-2xl px-4 py-10 space-y-6">
      <div>
        <h1 class="text-2xl font-semibold tracking-tight text-base-content">
          {gettext("Account Settings")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext("Manage your password and the devices where you are signed in.")}
        </p>
      </div>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-2">
          <h2 class="text-base font-semibold">{gettext("Email address")}</h2>
          <p class="font-mono text-sm">{@current_email}</p>
          <%!-- Only useful to someone who cannot change it themselves. --%>
          <p
            :if={not Playcode.Authz.can?(@current_user, :manage_users)}
            class="text-sm text-base-content/70"
          >
            {gettext("Your address is set by the administrator who invited you.")}
          </p>
        </div>
      </section>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-4">
          <div>
            <h2 class="text-base font-semibold">{gettext("Password")}</h2>
            <p class="text-sm text-base-content/70">
              {gettext("At least 12 characters. Changing it signs out your other sessions.")}
            </p>
          </div>

          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/log-in?_action=password_updated"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
            class="space-y-4"
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label={gettext("New password")}
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label={gettext("Confirm new password")}
            />
            <.input
              field={@password_form[:current_password]}
              name="current_password"
              type="password"
              label={gettext("Current password")}
              id="current_password_for_password"
              value={@current_password}
              required
            />
            <div class="flex justify-end">
              <.button phx-disable-with={gettext("Changing...")}>
                {gettext("Change Password")}
              </.button>
            </div>
          </.form>
        </div>
      </section>

      <section class="card border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body gap-4">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 class="text-base font-semibold">{gettext("Active sessions")}</h2>
              <p class="text-sm text-base-content/70">
                {gettext("Where your account is currently signed in.")}
              </p>
            </div>
            <button
              :if={length(@sessions) > 1}
              class="btn btn-sm btn-outline btn-error"
              phx-click="revoke_other_sessions"
            >
              {gettext("Sign out everywhere else")}
            </button>
          </div>

          <div
            class="overflow-x-auto"
            tabindex="0"
            role="region"
            aria-label={gettext("Active sessions")}
          >
            <table class="table table-sm">
              <thead>
                <tr class="text-xs uppercase tracking-wide text-base-content/70">
                  <th>{gettext("Signed in")}</th>
                  <th>{gettext("Address")}</th>
                  <th>{gettext("Browser")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={session <- @sessions} class="hover">
                  <td class="whitespace-nowrap">
                    {Calendar.strftime(session.inserted_at, "%Y-%m-%d %H:%M")}
                  </td>
                  <td class="font-mono text-xs">{session.ip_address || "—"}</td>
                  <td class="max-w-[16rem] truncate text-xs" title={session.user_agent}>
                    {session.user_agent || "—"}
                  </td>
                  <td class="whitespace-nowrap text-right">
                    <span
                      :if={session.token == @current_token}
                      class="badge badge-sm badge-primary whitespace-nowrap"
                    >
                      {gettext("This device")}
                    </span>
                    <button
                      :if={session.token != @current_token}
                      class="btn btn-xs btn-ghost text-error"
                      phx-click="revoke_session"
                      phx-value-id={session.id}
                    >
                      {gettext("Revoke")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </div>
    """
  end

  def mount(_params, session, socket) do
    user = socket.assigns.current_user
    password_changeset = Accounts.change_user_password(user)

    socket =
      socket
      |> assign(:current_password, nil)
      |> assign(:current_email, user.email)
      |> assign(:password_form, to_form(password_changeset, as: "user"))
      |> assign(:trigger_submit, false)
      |> assign(:current_token, session["user_token"])
      |> assign_sessions()

    {:ok, socket}
  end

  defp assign_sessions(socket) do
    assign(socket, :sessions, Accounts.list_user_sessions(socket.assigns.current_user))
  end

  def handle_event("validate_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params

    password_form =
      socket.assigns.current_user
      |> Accounts.change_user_password(user_params)
      |> Map.put(:action, :validate)
      |> to_form(as: "user")

    {:noreply, assign(socket, password_form: password_form, current_password: password)}
  end

  def handle_event("update_password", params, socket) do
    %{"current_password" => password, "user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.update_user_password(user, password, user_params) do
      {:ok, user} ->
        password_form =
          user
          |> Accounts.change_user_password(user_params)
          |> to_form(as: "user")

        {:noreply, assign(socket, trigger_submit: true, password_form: password_form)}

      {:error, changeset} ->
        {:noreply, assign(socket, password_form: to_form(changeset, as: "user"))}
    end
  end

  def handle_event("revoke_session", %{"id" => id}, socket) do
    :ok = Accounts.delete_user_session(socket.assigns.current_user, id)

    {:noreply,
     socket
     |> put_flash(:info, gettext("Session revoked."))
     |> assign_sessions()}
  end

  def handle_event("revoke_other_sessions", _params, socket) do
    :ok =
      Accounts.delete_other_user_sessions(
        socket.assigns.current_user,
        socket.assigns.current_token
      )

    {:noreply,
     socket
     |> put_flash(:info, gettext("Signed out of all other sessions."))
     |> assign_sessions()}
  end
end
