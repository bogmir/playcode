defmodule PlaycodeWeb.Admin.LayoutTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  @admin_only ~w(/admin/export /admin/activity-log /admin/users /admin/dashboard)

  defp sidebar_links?(lv, paths), do: Enum.map(paths, &has_element?(lv, "aside a[href='#{&1}']"))

  describe "admin sidebar" do
    test "an admin is offered every section", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays")

      assert Enum.all?(sidebar_links?(lv, ["/admin/plays/import" | @admin_only]))
    end

    # The same sections the authorization matrix refuses a researcher.
    test "a researcher is offered the content sections only", %{conn: conn} do
      {:ok, lv, _html} =
        live(log_in_user(conn, user_fixture(role: :researcher)), ~p"/admin/plays")

      assert has_element?(lv, "aside a[href='/admin/plays/import']")
      refute Enum.any?(sidebar_links?(lv, @admin_only))
    end

    test "only the current page's entry is marked as current", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays/import")

      assert has_element?(lv, "aside a[href='/admin/plays/import'][aria-current=page]")
      refute has_element?(lv, "aside a[href='/admin/plays'][aria-current=page]")
    end

    test "starts collapsed on a play's pages and open elsewhere", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())

      {:ok, play_page, _html} = live(conn, ~p"/admin/plays/#{play_fixture().id}")
      assert has_element?(play_page, "#admin-sidebar[checked]")

      {:ok, list_page, _html} = live(conn, ~p"/admin/plays")
      refute has_element?(list_page, "#admin-sidebar[checked]")
    end
  end
end
