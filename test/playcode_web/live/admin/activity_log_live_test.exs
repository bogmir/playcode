defmodule PlaycodeWeb.Admin.ActivityLogLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  test "an admin sees who changed what, and can narrow the log by action", %{conn: conn} do
    researcher = user_fixture(role: :researcher)
    play = play_fixture()

    # The researcher adds an editor through the page, which is what writes the entry.
    {:ok, editors, _html} =
      live(log_in_user(conn, researcher), ~p"/admin/plays/#{play.id}/editors")

    editors |> element("button", t("Add editor")) |> render_click()

    editors
    |> form("#editor-form",
      play_editor: %{"person_name" => "Ana Editora", "role" => "translator"}
    )
    |> render_submit()

    {:ok, log, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/activity-log")

    assert has_element?(log, "tbody tr", researcher.email)
    assert has_element?(log, "tbody tr a", play.code)

    log |> element("#activity-filters") |> render_change(%{"action" => "delete"})
    refute has_element?(log, "tbody tr", researcher.email)

    log |> element("#activity-filters") |> render_change(%{"action" => "create"})
    assert has_element?(log, "tbody tr", researcher.email)
  end

  test "a paratext's change is logged under the glossary's word", %{conn: conn} do
    play = play_fixture()

    {:ok, editor, _html} =
      live(log_in_user(conn, user_fixture()), ~p"/admin/plays/#{play.id}/content")

    editor |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    editor |> element("button", t("Add Paratext")) |> render_click()

    editor
    |> form("#paratext-form", paratext: %{"kind" => "dedicatoria", "content" => "Al duque."})
    |> render_submit()

    {:ok, log, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/activity-log")

    assert has_element?(log, "tbody tr", t("paratext"))
  end
end
