defmodule PlaycodeWeb.UserForgotPasswordLive do
  @moduledoc false

  use PlaycodeWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        {gettext("Forgot your password?")}
        <:subtitle>{gettext("We'll send a password reset link to your inbox")}</:subtitle>
      </.header>

      <.simple_form
        for={@form}
        id="reset_password_form"
        action={~p"/users/reset-password"}
        phx-update="ignore"
      >
        <.input field={@form[:email]} type="email" placeholder={gettext("Email")} required />
        <:actions>
          <.button phx-disable-with={gettext("Sending...")} class="w-full">
            {gettext("Send password reset instructions")}
          </.button>
        </:actions>
      </.simple_form>
      <p class="text-center text-sm mt-4">
        <.link href={~p"/users/log-in"}>{gettext("Log in")}</.link>
      </p>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    {:ok, assign(socket, form: to_form(%{}, as: "user"))}
  end
end
