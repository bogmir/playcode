defmodule PlaycodeWeb.UserLoginLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Accounts
  alias PlaycodeWeb.RateLimit

  # Login is rate limited per IP across the whole suite; each test gets its own, and so does
  # every Fly-Client-IP below.
  setup %{conn: conn} do
    %{conn: %{conn | remote_ip: {10, 9, rem(System.unique_integer([:positive]), 250), 1}}}
  end

  defp log_in(conn, email, password) do
    post(conn, ~p"/users/log-in", user: %{"email" => email, "password" => password})
  end

  defp from(conn, ip), do: put_req_header(conn, "fly-client-ip", ip)

  # An address in a /64 of its own, ending in ::1.
  defp unique_ip do
    n = System.unique_integer([:positive])

    {0x2001, 0xDB8, rem(div(n, 0x10000), 0x10000), rem(n, 0x10000), 0, 0, 0, 1}
    |> :inet.ntoa()
    |> to_string()
  end

  defp session_addresses(conn) do
    {:ok, lv, _html} = conn |> recycle() |> live(~p"/users/settings")
    lv |> element("[role=region][aria-label='#{t("Active sessions")}']") |> render()
  end

  defp flash(conn, key), do: Phoenix.Flash.get(conn.assigns.flash, key)

  test "the log-in page offers the form and the way back from a lost password", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/log-in")

    assert has_element?(lv, "#login_form input[name='user[email]']")
    assert has_element?(lv, "#login_form input[name='user[password]']")
    assert has_element?(lv, "a[href='/users/reset-password']")
  end

  test "a researcher logs in and lands on the admin play list", %{conn: conn} do
    user = user_fixture(role: :researcher)

    conn = log_in(conn, user.email, valid_user_password())

    assert redirected_to(conn) == ~p"/admin/plays"
    assert flash(conn, :info) == t("Welcome back!")
    assert html_response(get(recycle(conn), ~p"/admin/plays"), 200)
  end

  test "a wrong password gets the same answer as an unknown address", %{conn: conn} do
    user = user_fixture()

    for {email, password} <- [{user.email, "wrong password!"}, {"nobody@uv.es", "whatever123"}] do
      conn = log_in(conn, email, password)

      assert redirected_to(conn) == ~p"/users/log-in"
      assert flash(conn, :error) == t("Invalid email or password")
      refute get_session(conn, :user_token)
    end
  end

  test "a deactivated account can authenticate but gets no further", %{conn: conn} do
    {:ok, user} = Accounts.deactivate_user(user_fixture())

    conn = log_in(conn, user.email, valid_user_password()) |> recycle() |> get(~p"/admin/plays")

    assert redirected_to(conn) == ~p"/users/log-in"

    assert flash(conn, :error) ==
             t("Your account is not active. Please contact an administrator.")
  end

  test "guessing one account's password is stopped after ten tries", %{conn: conn} do
    user = user_fixture()

    for _ <- 1..10, do: log_in(conn, user.email, "wrong password!")
    conn = log_in(conn, user.email, valid_user_password())

    assert flash(conn, :error) ==
             t("Too many login attempts. Please wait a few minutes and try again.")

    refute get_session(conn, :user_token)
  end

  test "twenty failed logins stop the address they came from, and no other", %{conn: conn} do
    user = user_fixture()
    {bot, visitor} = {unique_ip(), unique_ip()}

    for i <- 1..20, do: conn |> from(bot) |> log_in("nobody#{i}@uv.es", "whatever123")

    refused = conn |> from(bot) |> log_in(user.email, valid_user_password())

    assert flash(refused, :error) ==
             t("Too many login attempts. Please wait a few minutes and try again.")

    welcomed = conn |> from(visitor) |> log_in(user.email, valid_user_password())
    assert flash(welcomed, :info) == t("Welcome back!")
  end

  test "an IPv6 client's whole /64 shares one budget", %{conn: conn} do
    ip = unique_ip()
    neighbour = String.replace_suffix(ip, "::1", "::2")

    for i <- 1..20, do: conn |> from(ip) |> log_in("nobody#{i}@uv.es", "whatever123")
    conn = conn |> from(neighbour) |> log_in(user_fixture().email, valid_user_password())

    assert flash(conn, :error) ==
             t("Too many login attempts. Please wait a few minutes and try again.")
  end

  test "IPv4 visitors seen through an IPv6 socket keep a budget each", %{conn: conn} do
    mapped = fn ->
      {0, 0, 0, 0, 0, 0xFFFF, 0x0A07, rem(System.unique_integer([:positive]), 0x10000)}
    end

    {bot, visitor} = {mapped.(), mapped.()}

    for i <- 1..20, do: log_in(%{conn | remote_ip: bot}, "nobody#{i}@uv.es", "whatever123")
    conn = log_in(%{conn | remote_ip: visitor}, user_fixture().email, valid_user_password())

    assert flash(conn, :info) == t("Welcome back!")
  end

  test "a session records the address Fly-Client-IP names", %{conn: conn} do
    user = user_fixture()
    ip = unique_ip()

    conn = conn |> from(ip) |> log_in(user.email, valid_user_password())

    assert session_addresses(conn) =~ ip
  end

  test "without a usable Fly-Client-IP the connection's own address stands", %{conn: conn} do
    own = conn.remote_ip |> :inet.ntoa() |> to_string()

    for conn <- [conn, from(conn, "not-an-address")] do
      conn = log_in(conn, user_fixture().email, valid_user_password())

      assert flash(conn, :info) == t("Welcome back!")
      assert session_addresses(conn) =~ own
    end
  end

  test "an address too long to be an account's gets no counter of its own", %{conn: conn} do
    too_many_characters = String.duplicate("a", 155) <> "@uv.es"
    # Seven characters, ten thousand bytes: a letter carrying five thousand accents.
    too_many_bytes = "a" <> String.duplicate("\u0301", 5_000) <> "@uv.es"

    for email <- [too_many_characters, too_many_bytes] do
      conn = from(conn, unique_ip())

      for _ <- 1..10, do: log_in(conn, email, "whatever123")
      conn = log_in(conn, email, "whatever123")

      assert flash(conn, :error) == t("Invalid email or password")
    end
  end

  test "a counter whose window has passed is swept, a live one is kept" do
    {spent, live} = {"sweep-#{unique_ip()}", "sweep-#{unique_ip()}"}
    RateLimit.sweep()

    :ok = RateLimit.check_rate(spent, 1, 1)
    :ok = RateLimit.check_rate(live, 1, 60_000)
    Process.sleep(2)

    assert RateLimit.sweep() >= 1
    assert RateLimit.check_rate(live, 1, 60_000) == {:error, :rate_limited}
  end

  test "logging out ends the session", %{conn: conn} do
    user = user_fixture()
    conn = log_in(conn, user.email, valid_user_password())
    token = get_session(conn, :user_token)

    conn = conn |> recycle() |> delete(~p"/users/log-out")

    assert redirected_to(conn) == ~p"/"
    assert flash(conn, :info) == t("Logged out successfully.")
    refute Accounts.get_user_by_session_token(token)
  end
end
