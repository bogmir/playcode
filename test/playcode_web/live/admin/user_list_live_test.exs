defmodule PlaycodeWeb.Admin.UserListLiveTest do
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Playcode.TestFixtures

  alias Playcode.Accounts

  setup %{conn: conn} do
    %{conn: log_in_user(conn, admin_fixture())}
  end

  defp click(lv, user, label),
    do: lv |> element("#user-#{user.id} button", label) |> render_click()

  test "given the invite form then the invitee is emailed a link to set a password",
       %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    html =
      lv
      |> form("#invite_form", invite: %{"email" => "nueva@uv.es", "role" => "researcher"})
      |> render_submit()

    assert html =~ "nueva@uv.es"
    user = Accounts.get_user_by_email("nueva@uv.es")
    assert user.role == :researcher
    refute Accounts.active?(user)

    # The mail names the platform and what it is for (it used to read EMOTHE).
    assert_email_sent(fn email ->
      assert email.to == [{"", "nueva@uv.es"}]
      assert email.subject == "You have been invited to Playcode"
      assert {"Playcode", _address} = email.from
      assert email.text_body =~ "You have been invited to Playcode, the editorial platform"
      assert email.text_body =~ "EMOTHE and ARTELOPE digital libraries"
      assert email.text_body =~ ~r{/users/accept-invite/\S+}
    end)
  end

  test "given an invitee who lost the mail then it can be sent again", %{conn: conn} do
    {invitee, _token} = invited_user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    click(lv, invitee, t("Resend invitation"))

    assert_email_sent(to: invitee.email)
  end

  # Promoting used to confirm the account: an invitee with no password showed as active,
  # with no invitation left to resend.
  test "given an invitee promoted before accepting then the invitation can still be resent",
       %{conn: conn} do
    {invitee, _token} = invited_user_fixture()
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    click(lv, invitee, t("Make admin"))

    assert has_element?(lv, "#user-#{invitee.id}", t("Invited"))
    click(lv, invitee, t("Resend invitation"))
    assert_email_sent(to: invitee.email)
  end

  test "given an active user then deactivating them ends their sessions", %{conn: conn} do
    victim = user_fixture()
    Accounts.generate_user_session_token(victim)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")
    click(lv, victim, t("Deactivate"))

    refute Accounts.active?(Accounts.get_user!(victim.id))
    assert Accounts.list_user_sessions(victim) == []
  end

  test "given a deactivated user then they can be reactivated", %{conn: conn} do
    {:ok, user} = Accounts.deactivate_user(user_fixture())
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    click(lv, user, t("Reactivate"))

    assert Accounts.active?(Accounts.get_user!(user.id))
  end

  test "given a user with open sessions then forcing a logout ends them all", %{conn: conn} do
    user = user_fixture()
    for _ <- 1..2, do: Accounts.generate_user_session_token(user)
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    click(lv, user, t("Log out everywhere"))

    assert Accounts.list_user_sessions(user) == []
  end

  test "given a researcher then they can be promoted to admin", %{conn: conn} do
    user = user_fixture(role: :researcher)
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    click(lv, user, t("Make admin"))

    assert Accounts.get_user!(user.id).role == :admin
  end

  # The pages check a permission when they open: an admin demoted with /admin/users open
  # went on inviting admins from it.
  test "given an admin with open sessions then demoting them ends their sessions",
       %{conn: conn} do
    admin = admin_fixture()
    Accounts.generate_user_session_token(admin)
    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    click(lv, admin, t("Make researcher"))

    assert Accounts.get_user!(admin.id).role == :researcher
    assert Accounts.list_user_sessions(admin) == []
  end

  test "given a protected admin then demotion is refused", %{conn: conn} do
    # Configured in different case from the account: ADMIN_EMAILS is matched
    # case-insensitively.
    Application.put_env(:playcode, :admin_emails, ["Jefa@UV.es"])
    on_exit(fn -> Application.put_env(:playcode, :admin_emails, []) end)

    protected = user_fixture(email: "jefa@uv.es", role: :admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    # The page used to offer the demotion and then refuse it.
    refute has_element?(lv, "#user-#{protected.id} button", t("Make researcher"))
    render_change(lv, "set_role", %{"id" => protected.id, "role" => "researcher"})

    assert Accounts.get_user!(protected.id).role == :admin
  end

  test "given a protected admin then deactivation is refused", %{conn: conn} do
    Application.put_env(:playcode, :admin_emails, ["jefa@uv.es"])
    on_exit(fn -> Application.put_env(:playcode, :admin_emails, []) end)

    protected = user_fixture(email: "jefa@uv.es", role: :admin)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    # The button is hidden for a protected admin; the handler must refuse anyway.
    refute has_element?(lv, "#user-#{protected.id} button", t("Deactivate"))
    render_click(lv, "deactivate", %{"id" => protected.id})

    assert Accounts.active?(Accounts.get_user!(protected.id))
  end

  # Regression: the result of deliver_invite/3 was discarded, so an SMTP relay
  # that refused the mail still flashed "Invitation sent" and the invitee was
  # left waiting for a link that was never delivered.
  test "given a mailer that cannot deliver then the flash says so", %{conn: conn} do
    Application.put_env(:playcode, Playcode.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: "127.0.0.1",
      port: 1,
      retries: 0,
      no_mx_lookups: true
    )

    on_exit(fn ->
      Application.put_env(:playcode, Playcode.Mailer, adapter: Swoosh.Adapters.Test)
    end)

    {:ok, lv, _html} = live(conn, ~p"/admin/users")

    html =
      lv
      |> form("#invite_form", invite: %{"email" => "sinmail@uv.es", "role" => "researcher"})
      |> render_submit()

    assert html =~
             Gettext.gettext(
               PlaycodeWeb.Gettext,
               "Invitation created, but the email could not be sent to %{email}. Resend it once mail delivery works.",
               email: "sinmail@uv.es"
             )

    # The account still exists, so the invitation can be resent.
    assert Accounts.get_user_by_email("sinmail@uv.es")
  end
end
