defmodule PlaycodeWeb.UserSessionController do
  @moduledoc false

  use PlaycodeWeb, :controller

  alias Playcode.Accounts
  alias Playcode.Accounts.User
  alias PlaycodeWeb.RateLimit
  alias PlaycodeWeb.UserAuth

  # No account's address is longer: 160 characters, a code point being four bytes at most.
  @max_email_bytes User.max_email_length() * 4

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
    ip = conn.remote_ip |> network() |> :inet.ntoa() |> to_string()
    email_key = if account_email?(email), do: "login-email:#{String.downcase(email)}"

    # Two keys: a broad per-IP cap against bots, and a narrow per-email cap
    # against guessing one known account. Deliberately a rate limit rather
    # than an account lock — a lock would let a stranger shut a named admin
    # out of their own site.
    with :ok <- RateLimit.check_rate("login:#{ip}", 20, 60_000),
         :ok <- check_email_rate(email_key) do
      if user = Accounts.get_user_by_email_and_password(email, password) do
        RateLimit.reset(email_key)

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)
      else
        # Don't disclose whether the email is registered.
        conn
        |> put_flash(:error, gettext("Invalid email or password"))
        |> put_flash(:email, if(email_key, do: email, else: ""))
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

  # An address no account can have gets no counter, whose key would be as long as the
  # request body allows, and is not written back into the session cookie.
  defp account_email?(email) do
    byte_size(email) <= @max_email_bytes and String.length(email) <= User.max_email_length()
  end

  # An IPv6 client commonly holds a whole /64, so the /64 counts as one address.
  defp network({0, 0, 0, 0, 0, 0xFFFF, _, _} = ipv4_mapped), do: ipv4_mapped
  defp network({a, b, c, d, _, _, _, _}), do: {a, b, c, d, 0, 0, 0, 0}
  defp network(ipv4), do: ipv4

  defp check_email_rate(nil), do: :ok
  defp check_email_rate(email_key), do: RateLimit.check_rate(email_key, 10, 900_000)
end
