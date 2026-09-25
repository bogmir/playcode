defmodule PlaycodeWeb.UserSettingsLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Accounts

  describe "email address card" do
    test "given a researcher then the who-set-it hint is shown", %{conn: conn} do
      {:ok, _lv, html} =
        live(log_in_user(conn, user_fixture(role: :researcher)), ~p"/users/settings")

      assert html =~
               Gettext.gettext(
                 PlaycodeWeb.Gettext,
                 "Your address is set by the administrator who invited you."
               )
    end

    test "given an admin then the hint is omitted", %{conn: conn} do
      {:ok, _lv, html} = live(log_in_user(conn, admin_fixture()), ~p"/users/settings")

      refute html =~
               Gettext.gettext(
                 PlaycodeWeb.Gettext,
                 "Your address is set by the administrator who invited you."
               )
    end
  end

  describe "active sessions panel" do
    test "given two sessions then both are listed and only one is this device", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)
      Accounts.generate_user_session_token(user, %{user_agent: "Firefox/141"})

      {:ok, lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "Firefox/141"
      assert length(Accounts.list_user_sessions(user)) == 2

      lv |> element("button[phx-click='revoke_other_sessions']") |> render_click()

      assert [only] = Accounts.list_user_sessions(user)
      assert only.token == get_session(conn, :user_token)
    end

    test "given another user's session id then revoking it does nothing", %{conn: conn} do
      theirs = user_fixture()
      Accounts.generate_user_session_token(theirs)
      [their_session] = Accounts.list_user_sessions(theirs)

      {:ok, lv, _html} = live(log_in_user(conn, user_fixture()), ~p"/users/settings")

      render_click(lv, "revoke_session", %{"id" => their_session.id})

      assert length(Accounts.list_user_sessions(theirs)) == 1
    end
  end

  describe "changing the password" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    # The page posts the address from a hidden field; form/3 replaces the whole
    # "user" map, so the test sends it the same way.
    defp submit_password(lv, email, current, new) do
      assert has_element?(lv, "#password_form input[type=hidden][name='user[email]']")

      lv
      |> form("#password_form", %{
        "current_password" => current,
        "user" => %{"email" => email, "password" => new, "password_confirmation" => new}
      })
    end

    test "logs you back in with the new password, and the old one stops working",
         %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form = submit_password(lv, user.email, valid_user_password(), "a brand new password")
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == t("Password updated successfully!")
      assert get_session(conn, :user_token)

      assert Accounts.get_user_by_email_and_password(user.email, "a brand new password")
      refute Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end

    test "is refused with the wrong current password", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      html =
        lv
        |> submit_password(user.email, "not my password", "a brand new password")
        |> render_submit()

      # Changeset messages live in the errors domain. This read `t/2` (the default
      # domain) and passed only while the message had no Spanish translation.
      assert html =~ Gettext.dgettext(PlaycodeWeb.Gettext, "errors", "is not valid")
      assert Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end
end
