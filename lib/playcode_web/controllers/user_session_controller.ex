defmodule PlaycodeWeb.UserSessionController do
  @moduledoc false

  use PlaycodeWeb, :controller

  alias Playcode.Accounts
  alias PlaycodeWeb.UserAuth

  def create(conn, %{"_action" => "invited"} = params) do
    create(conn, params, gettext("Welcome to Playcode!"))
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, gettext("Password updated successfully!"))
  end

  def create(conn, params) do
    create(conn, params, gettext("Welcome back!"))
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    email_key = "login-email:#{String.downcase(email)}"

    # Two keys: a broad per-IP cap against bots, and a narrow per-email cap
    # against guessing one known account. Deliberately a rate limit rather
    # than an account lock — a lock would let a stranger shut a named admin
    # out of their own site.
    with :ok <- PlaycodeWeb.RateLimit.check_rate("login:#{ip}", 20, 60_000),
         :ok <- PlaycodeWeb.RateLimit.check_rate(email_key, 10, 900_000) do
      if user = Accounts.get_user_by_email_and_password(email, password) do
        PlaycodeWeb.RateLimit.reset(email_key)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)
      else
        # Don't disclose whether the email is registered.
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/users/log-in")
      end
    else
      {:error, :rate_limited} ->
        conn
        |> put_flash(
          :error,
          gettext("Too many login attempts. Please wait a few minutes and try again.")
        )
        |> redirect(to: ~p"/users/log-in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Logged out successfully."))
    |> UserAuth.log_out_user()
  end
end
