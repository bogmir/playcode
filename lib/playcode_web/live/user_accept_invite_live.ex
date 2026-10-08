defmodule PlaycodeWeb.UserAcceptInviteLive do
  @moduledoc """
  /users/accept-invite/:token: the invited user sets a password, which also confirms the
  account, since following the mailed link proves the mailbox, and is logged in.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Accounts

  def render(%{user: nil} = assigns) do
    ~H"""
    <div class="mx-auto max-w-sm text-center">
      <.header>{gettext("This invitation is no longer valid")}</.header>
      <p class="mt-4 text-sm text-base-content/70">
        {gettext("Ask an administrator to send you a new one.")}
      </p>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        {gettext("Welcome to Playcode")}
        <:subtitle>{gettext("Choose a password for %{email}", email: @user.email)}</:subtitle>
      </.header>

      <div
        :if={@current_user && @current_user.id != @user.id}
        class="alert alert-warning mt-4 text-sm"
      >
        <.icon name="hero-exclamation-triangle-micro" class="size-4 shrink-0" />
        <span>
          {gettext("You are signed in as %{email}. Continuing will sign you out of that account.",
            email: @current_user.email
          )}
        </span>
      </div>

      <.simple_form
        for={@form}
        id="accept_invite_form"
        phx-submit="save"
        phx-change="validate"
        phx-trigger-action={@trigger_submit}
        action={~p"/users/log-in?_action=invited"}
        method="post"
      >
        <input type="hidden" name="user[email]" value={@user.email} />
        <.input
          field={@form[:password]}
          type="password"
          label={gettext("Password")}
          required
          autocomplete="new-password"
        />
        <:actions>
          <.button phx-disable-with={gettext("Saving...")} class="w-full">
            {gettext("Set password and sign in")}
          </.button>
        </:actions>
      </.simple_form>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    case Accounts.get_user_by_invite_token(token) do
      nil ->
        {:ok, assign(socket, user: nil, form: nil, trigger_submit: false)}

      user ->
        changeset = Accounts.change_user_invite_acceptance(user)

        {:ok,
         socket
         |> assign(user: user, trigger_submit: false)
         |> assign_form(changeset)}
    end
  end

  def handle_event("validate", %{"user" => params}, socket) do
    changeset = Accounts.change_user_invite_acceptance(socket.assigns.user, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    case Accounts.accept_invite(socket.assigns.user, params) do
      {:ok, user} ->
        changeset = Accounts.change_user_invite_acceptance(user)
        {:noreply, socket |> assign(trigger_submit: true) |> assign_form(changeset)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, Map.put(changeset, :action, :insert))}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
