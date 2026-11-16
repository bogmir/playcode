defmodule PlaycodeWeb.UserResetPasswordController do
  @moduledoc false

  use PlaycodeWeb, :controller

  alias Playcode.Accounts
  alias PlaycodeWeb.RateLimit

  # Two caps: per visitor, against one client working through many addresses, and per
  # address, against flooding one inbox. The second counts every address, known or
  # not, and answers like any other request, so it reveals nothing about accounts.
  def create(conn, %{"user" => %{"email" => email}}) do
    case RateLimit.check_rate(RateLimit.ip_key("reset", conn.remote_ip), 10, 3_600_000) do
      :ok ->
        with :ok <- RateLimit.check_rate(RateLimit.email_key("reset-email", email), 3, 900_000),
             %{} = user <- Accounts.get_user_by_email(email) do
          Accounts.deliver_user_reset_password_instructions(
            user,
            &url(~p"/users/reset-password/#{&1}")
          )
        end

        info =
          gettext(
            "If your email is in our system, you will receive instructions to reset your password shortly."
          )

        conn
        |> put_flash(:info, info)
        |> redirect(to: ~p"/")

      {:error, :rate_limited} ->
        conn
        |> put_flash(:error, gettext("Too many attempts. Please wait a while and try again."))
        |> redirect(to: ~p"/users/reset-password")
    end
  end
end
