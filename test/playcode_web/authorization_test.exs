defmodule PlaycodeWeb.AuthorizationTest do
  @moduledoc """
  Who may open which page, asked of the router rather than of `Authz.can?/3`.

  Each row names a gated route and who may pass its gate. The expectations are
  written out by hand: deriving them from `Authz.can?/3` would only prove the
  policy agrees with itself. A page that passes the gate may still redirect (the
  zip download without a generated zip, the dashboard's own home page), so
  passing means "not sent to the log-in page or home".
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  # `:active` = any active researcher or admin; `:admin` = admins only.
  @routes [
    {"/users/settings", :active},
    {"/admin/plays", :active},
    {"/admin/plays/new", :active},
    {"/admin/plays/import", :active},
    {"/admin/plays/:id", :active},
    {"/admin/plays/:id/edit", :active},
    {"/admin/plays/:id/editors", :active},
    {"/admin/plays/:id/sources", :active},
    {"/admin/plays/:id/places", :active},
    {"/admin/plays/:id/bibliography", :active},
    {"/admin/plays/:id/content", :active},
    {"/admin/plays/:id/compare", :active},
    {"/admin/places", :active},
    {"/admin/plays/:id/export/tei", :active},
    {"/admin/plays/:id/export/html", :active},
    {"/admin/plays/:id/export/epub", :active},
    {"/admin/plays/:id/export/pdf", :active},
    {"/admin/plays/compare/export/html?plays=:id", :active},
    {"/admin/users", :admin},
    {"/admin/activity-log", :admin},
    {"/admin/export", :admin},
    {"/admin/export/download-zip", :admin},
    {"/admin/export/preview/index.html", :admin},
    {"/admin/filemaker", :admin},
    {"/admin/dashboard", :admin}
  ]

  setup do
    %{
      play: play_fixture(),
      personas: %{
        anonymous: nil,
        researcher: user_fixture(role: :researcher),
        admin: admin_fixture(),
        deactivated_admin: admin_fixture(deactivated_at: DateTime.utc_now(:second)),
        unconfirmed_admin: admin_fixture(confirmed_at: nil)
      }
    }
  end

  for {path, who} <- @routes do
    @path path
    @who who

    test "#{path} is open to #{if who == :admin, do: "admins only", else: "active accounts"}",
         %{play: play, personas: personas} do
      path = String.replace(@path, ":id", play.id)

      expected = %{
        anonymous: :login,
        researcher: if(@who == :admin, do: :home, else: :passes),
        admin: :passes,
        deactivated_admin: :login,
        unconfirmed_admin: :login
      }

      actual =
        Map.new(personas, fn {name, user} -> {name, outcome(get(conn_for(user), path))} end)

      assert actual == expected
    end
  end

  describe "navigating inside the admin area" do
    # A live navigation stays in the :admin live_session, so no router plug runs:
    # only each LiveView's own on_mount stands between a researcher and the page.
    test "a researcher cannot live-navigate to an admin-only page", %{personas: personas} do
      for path <- ~w(/admin/users /admin/activity-log /admin/export /admin/filemaker) do
        {:ok, lv, _html} = live(conn_for(personas.researcher), ~p"/admin/plays")

        assert {:error, {:redirect, %{to: "/"}}} = live_redirect(lv, to: path),
               "expected #{path} to refuse a researcher"
      end
    end
  end

  describe "the reason you are sent away" do
    test "a researcher refused an admin page is told so", %{personas: personas} do
      conn = get(conn_for(personas.researcher), ~p"/admin/users")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               t("You do not have access to that page.")
    end

    test "a deactivated account is logged out and told why", %{personas: personas} do
      token = Playcode.Accounts.generate_user_session_token(personas.deactivated_admin)

      conn =
        build_conn()
        |> init_test_session(%{user_token: token})
        |> get(~p"/admin/plays")

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               t("Your account is not active. Please contact an administrator.")

      refute Playcode.Accounts.get_user_by_session_token(token)
    end
  end

  defp conn_for(nil), do: build_conn()
  defp conn_for(user), do: log_in_user(build_conn(), user)

  defp outcome(%Plug.Conn{status: status} = conn) when status in [301, 302] do
    case redirected_to(conn, status) do
      "/users/log-in" -> :login
      "/" -> :home
      _elsewhere -> :passes
    end
  end

  defp outcome(%Plug.Conn{status: 200}), do: :passes
  defp outcome(%Plug.Conn{status: status}), do: {:unexpected_status, status}
end
