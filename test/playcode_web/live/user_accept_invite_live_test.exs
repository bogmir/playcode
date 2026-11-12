defmodule PlaycodeWeb.UserAcceptInviteLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Accounts

  test "given a valid token then setting a password signs the user in, on the play list, welcomed",
       %{conn: conn} do
    {user, token} = invited_user_fixture()

    {:ok, lv, _html} = live(conn, ~p"/users/accept-invite/#{token}")

    # The email comes from a hidden input in the real form; LiveViewTest only
    # posts values the test supplies, so it has to be named here too.
    form =
      form(lv, "#accept_invite_form",
        user: %{"email" => user.email, "password" => valid_user_password()}
      )

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    # Researchers hold :view_admin since the Authz task, so signed_in_path
    # sends them to the admin play list rather than the public home page.
    assert redirected_to(conn) == ~p"/admin/plays"
    assert Accounts.active?(Playcode.Repo.reload!(user))

    {:ok, _list, html} = live(recycle(conn), ~p"/admin/plays")
    assert html =~ t("Welcome to Playcode!")
  end

  test "the page says what Playcode is", %{conn: conn} do
    {_user, token} = invited_user_fixture()

    {:ok, _lv, html} = live(conn, ~p"/users/accept-invite/#{token}")

    assert html =~
             t(
               "Playcode is where the EMOTHE and ARTELOPE teams catalogue and edit the plays the public site is generated from."
             )
  end

  # Regression: the route sat behind redirect_if_user_is_authenticated, so an
  # admin clicking a fresh invite link was bounced to /admin/plays with no
  # explanation — the invitee could never set their password on a browser that
  # already held a session.
  test "given an existing session then the invite page still opens and switches account",
       %{conn: conn} do
    admin = admin_fixture()
    {invitee, token} = invited_user_fixture()

    conn = log_in_user(conn, admin)
    {:ok, lv, html} = live(conn, ~p"/users/accept-invite/#{token}")

    assert html =~ invitee.email

    form =
      form(lv, "#accept_invite_form",
        user: %{"email" => invitee.email, "password" => valid_user_password()}
      )

    render_submit(form)
    conn = follow_trigger_action(form, conn)

    assert Accounts.active?(Playcode.Repo.reload!(invitee))
    assert Accounts.get_user_by_session_token(get_session(conn, :user_token)).id == invitee.id
  end

  test "given an invalid token then an explanation and no form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/users/accept-invite/nonsense")

    # Asserted through gettext: the page renders in the session locale, which
    # is Spanish by default.
    assert html =~
             Gettext.gettext(PlaycodeWeb.Gettext, "This invitation is no longer valid")

    refute html =~ "accept_invite_form"
  end
end
