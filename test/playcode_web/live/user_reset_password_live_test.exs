defmodule PlaycodeWeb.UserResetPasswordLiveTest do
  @moduledoc """
  Forgot password, as the user lives it: ask for a link, read the email, follow
  it, set a password, log in with it.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Playcode.TestFixtures

  alias Playcode.Accounts

  @new_password "newverysecure123"

  # Requests are capped per visitor across the whole suite; each test gets its own.
  setup %{conn: conn} do
    %{conn: from(conn, unique_ip())}
  end

  # The page's form posts to a controller, where Fly-Client-IP names the visitor.
  defp request_link(conn, email) do
    {:ok, lv, _html} = live(conn, ~p"/users/reset-password")

    lv
    |> form("#reset_password_form", user: %{"email" => email})
    |> submit_form(conn)
  end

  defp from(conn, ip), do: put_req_header(conn, "fly-client-ip", ip)

  defp unique_ip do
    n = System.unique_integer([:positive])
    "10.8.#{rem(div(n, 250), 250)}.#{rem(n, 250)}"
  end

  defp flash(conn, key), do: Phoenix.Flash.get(conn.assigns.flash, key)

  defp neutral_answer do
    t(
      "If your email is in our system, you will receive instructions to reset your password shortly."
    )
  end

  defp emailed_path(email_address) do
    assert_email_sent(fn email ->
      assert email.to == [{"", email_address}]
      assert [url] = Regex.run(~r{https?://\S+/users/reset-password/\S+}, email.text_body)
      send(self(), {:reset_path, URI.parse(url).path})
    end)

    assert_received {:reset_path, path}
    path
  end

  defp set_password(conn, path) do
    {:ok, lv, _html} = live(conn, path)

    lv
    |> form("#reset_password_form",
      user: %{"password" => @new_password, "password_confirmation" => @new_password}
    )
    |> render_submit()
  end

  test "the emailed link sets a new password that then logs in", %{conn: conn} do
    user = user_fixture()

    assert redirected_to(request_link(conn, user.email)) == ~p"/"
    path = emailed_path(user.email)

    assert {:error, {:redirect, %{to: "/users/log-in"}}} = set_password(conn, path)

    conn =
      post(conn, ~p"/users/log-in", user: %{"email" => user.email, "password" => @new_password})

    assert get_session(conn, :user_token)
  end

  test "an unknown address gets the same answer as a known one, and no email", %{conn: conn} do
    known = user_fixture()

    for email <- [known.email, "nobody@uv.es"] do
      conn = request_link(conn, email)

      assert redirected_to(conn) == ~p"/"
      assert flash(conn, :info) == neutral_answer()
    end

    assert_email_sent(to: known.email)

    refute_email_sent()
  end

  test "a fourth request for one address in a quarter of an hour sends nothing, and says the same",
       %{conn: conn} do
    user = user_fixture()

    for _ <- 1..3, do: request_link(conn, String.upcase(user.email))
    for _ <- 1..3, do: assert_email_sent(to: user.email)

    conn = request_link(conn, user.email)

    assert redirected_to(conn) == ~p"/"
    assert flash(conn, :info) == neutral_answer()
    refute_email_sent()
  end

  test "ten requests stop the visitor they came from, and no other", %{conn: conn} do
    user = user_fixture()
    {bot, visitor} = {unique_ip(), unique_ip()}

    for i <- 1..10, do: conn |> from(bot) |> request_link("nobody#{i}@uv.es")

    refused = conn |> from(bot) |> request_link(user.email)

    assert redirected_to(refused) == ~p"/users/reset-password"
    assert flash(refused, :error) == t("Too many attempts. Please wait a while and try again.")
    refute_email_sent()

    welcomed = conn |> from(visitor) |> request_link(user.email)

    assert flash(welcomed, :info) == neutral_answer()
    assert_email_sent(to: user.email)
  end

  test "an address too long to be an account's gets no counter", %{conn: conn} do
    email = String.duplicate("a", 155) <> "#{System.unique_integer([:positive])}@uv.es"

    conn = request_link(conn, email)

    assert flash(conn, :info) == neutral_answer()
    # Nothing a visitor sees tells a counter from none: the table is read directly.
    refute Enum.any?(:ets.tab2list(:playcode_rate_limit), fn {key, _, _} ->
             String.contains?(key, email)
           end)
  end

  test "a link that was never sent opens no form", %{conn: conn} do
    assert {:error, {:redirect, %{to: to}}} = live(conn, ~p"/users/reset-password/not-a-token")
    assert to == ~p"/"
  end

  # Regression: the route sat behind redirect_if_user_is_authenticated, so a
  # user who still held a session was bounced to the catalogue with no
  # explanation. An unconfirmed account can log in but is refused everywhere
  # else, so the reset link was the only way out — and holding a session was
  # exactly what swallowed it.
  test "the link works for an account still holding a session, and activates it",
       %{conn: conn} do
    user = user_fixture(confirmed_at: nil)

    request_link(conn, user.email)
    path = emailed_path(user.email)

    set_password(log_in_user(conn, user), path)

    assert Accounts.active?(Accounts.get_user!(user.id))
  end
end
