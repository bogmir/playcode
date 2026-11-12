defmodule PlaycodeWeb.Admin.LayoutTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  @admin_only ~w(/admin/export /admin/activity-log /admin/users /admin/dashboard)

  defp sidebar_links?(lv, paths), do: Enum.map(paths, &has_element?(lv, "aside a[href='#{&1}']"))

  # The keyboard reaches the page past the header and the sidebar's links in one press.
  test "the admin and the public pages open with a link that skips to the content",
       %{conn: conn} do
    conn = log_in_user(conn, admin_fixture())

    for path <- ~w(/admin/plays /plays) do
      {:ok, lv, _html} = live(conn, path)
      assert {path, has_element?(lv, "a[href='#main']", t("Skip to content"))} == {path, true}
      assert {path, has_element?(lv, "main#main")} == {path, true}
    end
  end

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

    # It used to start collapsed on every play page, to give the text the width the context
    # bar's tabs did not take; the play's sections now live in it, so it starts open, except
    # on the two pages that need the width.
    test "starts open, folded only on a play's Content and Comparison", %{conn: conn} do
      conn = log_in_user(conn, admin_fixture())
      %{original: play} = translation_family_fixture()

      for path <- ["", "/editors", "/notes"] do
        {:ok, lv, _html} = live(conn, "/admin/plays/#{play.id}#{path}")
        refute has_element?(lv, "#admin-sidebar[checked]"), path
      end

      for path <- ["/content", "/compare"] do
        {:ok, lv, _html} = live(conn, "/admin/plays/#{play.id}#{path}")
        assert has_element?(lv, "#admin-sidebar[checked]"), path
      end

      {:ok, list_page, _html} = live(conn, ~p"/admin/plays")
      refute has_element?(list_page, "#admin-sidebar[checked]")
    end
  end

  describe "a play's sections" do
    setup %{conn: conn} do
      %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
    end

    defp section(_play, path), do: "nav[aria-label='#{t("Play sections")}'] a[href='#{path}']"

    # Below lg the sidebar is folded behind the header's bare icon; a phone user saw only the
    # overview's "Edit metadata" and took the other sections for missing.
    test "a narrow screen opens them from a button named after them", %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
      assert has_element?(lv, "main label[for='admin-sidebar']", t("Play sections"))

      {:ok, list_page, _html} = live(conn, ~p"/admin/plays")
      refute has_element?(list_page, "main label[for='admin-sidebar']")
    end

    test "are in the sidebar, grouped, each with its count", %{conn: conn, play: play} do
      performance_fixture(play)
      performance_fixture(play, %{"date_text" => "1611"})

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

      for group <- [t("Record"), t("Tradition"), t("Text"), t("View")],
          do: assert(has_element?(lv, "nav[aria-label='#{t("Play sections")}'] h2", group))

      assert has_element?(lv, section(play, ~p"/admin/plays/#{play.id}/performances"), "2")
      assert has_element?(lv, section(play, ~p"/admin/plays/#{play.id}/editors"), "0")

      assert has_element?(
               lv,
               section(play, ~p"/admin/plays/#{play.id}/performances") <> "[aria-current=page]"
             )

      refute has_element?(lv, "aside a[href='/admin/places']")
    end

    test "count what a tab adds without a reload", %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/editors")

      lv |> element("button", t("Add editor")) |> render_click()

      lv
      |> form("#editor-form", play_editor: %{"person_name" => "Oleza, Joan", "role" => "editor"})
      |> render_submit()

      assert has_element?(lv, section(play, ~p"/admin/plays/#{play.id}/editors"), "1")
    end

    test "open the play's preview, Playcode's own page", %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

      assert has_element?(lv, section(play, ~p"/plays/#{play.code}"), t("Preview"))
    end

    test "lead back to the list of plays", %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/sources")

      lv
      |> element("nav[aria-label='#{t("Play sections")}'] a", t("All plays"))
      |> render_click()
      |> follow_redirect(conn, ~p"/admin/plays")
    end

    # The play's title is in the sidebar, once; a tab's heading names the tab.
    test "each tab's heading names the section, not the play", %{conn: conn, play: play} do
      for {path, heading} <- [
            {"/edit", t("Metadata")},
            {"/editors", t("Editors")},
            {"/content", t("Content")},
            {"/notes", t("Notes")}
          ] do
        {:ok, lv, _html} = live(conn, "/admin/plays/#{play.id}#{path}")

        assert has_element?(lv, "h1", heading)
        refute has_element?(lv, "main", play.title)
        assert has_element?(lv, "nav[aria-label='#{t("Play sections")}']", play.title)
      end
    end
  end
end
