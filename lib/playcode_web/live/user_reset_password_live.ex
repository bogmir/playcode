defmodule PlaycodeWeb.UserResetPasswordLive do
  @moduledoc """
  /users/reset-password/:token: sets a new password. Following the mailed link proves the
  mailbox, so it also confirms an unconfirmed account; it never reactivates a deactivated
  one.
  """

  use PlaycodeWeb, :live_view

  alias Playcode.Accounts

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">{gettext("Reset Password")}</.header>

      <.simple_form
        for={@form}
        id="reset_password_form"
        phx-submit="reset_password"
        phx-change="validate"
      >
        <.error :if={@form.errors != []}>
          {gettext("Oops, something went wrong! Please check the errors below.")}
        </.error>

        <.input field={@form[:password]} type="password" label={gettext("New password")} required />
        <.input
          field={@form[:password_confirmation]}
          type="password"
          label={gettext("Confirm new password")}
          required
        />
        <:actions>
          <.button phx-disable-with={gettext("Resetting...")} class="w-full">
            {gettext("Reset Password")}
          </.button>
        </:actions>
      </.simple_form>

      <p class="text-center text-sm mt-4">
        <.link href={~p"/users/log-in"}>{gettext("Log in")}</.link>
      </p>
    </div>
    """
  end

  def mount(params, _session, socket) do
    socket = assign_user_and_token(socket, params)

    form_source =
      case socket.assigns do
        %{user: user} ->
          Accounts.change_user_password(user)

        _ ->
          %{}
      end

    {:ok, assign_form(socket, form_source), temporary_assigns: [form: nil]}
  end

  def handle_event("reset_password", %{"user" => user_params}, socket) do
    case Accounts.reset_user_password(socket.assigns.user, user_params) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Password reset successfully."))
         |> redirect(to: ~p"/users/log-in")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_password(socket.assigns.user, user_params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  defp assign_user_and_token(socket, %{"token" => token}) do
    if user = Accounts.get_user_by_reset_password_token(token) do
      assign(socket, user: user, token: token)
    else
      socket
      |> put_flash(:error, gettext("Reset password link is invalid or it has expired."))
      |> redirect(to: ~p"/")
    end
  end

  defp assign_form(socket, %{} = source) do
    assign(socket, form: to_form(source, as: "user"))
  end
end
