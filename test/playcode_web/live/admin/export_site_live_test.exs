defmodule PlaycodeWeb.Admin.ExportSiteLiveTest do
  # Not async: Generate runs in a task that reads the database, which only works in the
  # shared sandbox, and every test builds into the same temporary site directory.
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Export.StaticSite

  setup %{conn: conn} do
    File.rm_rf!(StaticSite.output_dir())
    on_exit(fn -> File.rm_rf!(StaticSite.output_dir()) end)

    complete = %{"is_complete" => true}
    a = play_fixture(Map.put(complete, "title", "Alpha Tragedy"))
    b = play_fixture(Map.put(complete, "title", "Beta Comedy"))
    _draft = play_fixture(%{"title" => "Gamma Draft"})

    %{conn: log_in_user(conn, admin_fixture()), a: a, b: b}
  end

  defp box(a), do: "#play-#{a.id} input[type=checkbox]"

  # Generate runs in a task; the result card appears when it finishes.
  defp generate(lv) do
    lv |> element("form[phx-submit=generate]") |> render_submit()
    wait_for(fn -> render(lv) =~ t("Generation Complete") end)
  end

  defp wait_for(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("timed out waiting for the build")
      true -> Process.sleep(50) && wait_for(fun, tries - 1)
    end
  end

  test "lists the complete plays, all ticked while no site exists", %{conn: conn, a: a, b: b} do
    {:ok, lv, html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "#{box(a)}[checked]")
    assert has_element?(lv, "#{box(b)}[checked]")
    refute html =~ "Gamma Draft"
    assert html =~ t("%{selected} of %{total} plays selected", selected: 2, total: 2)
  end

  test "the header checkbox ticks or clears every play", %{conn: conn, a: a, b: b} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    lv |> element("input[aria-label='#{t("Select all plays")}']") |> render_click()
    refute has_element?(lv, "#{box(a)}[checked]")
    refute has_element?(lv, "#{box(b)}[checked]")
    assert has_element?(lv, "button[type=submit][disabled]", t("Generate Static Site"))

    lv |> element("input[aria-label='#{t("Select all plays")}']") |> render_click()
    assert has_element?(lv, "#{box(a)}[checked]")
    assert has_element?(lv, "#{box(b)}[checked]")
  end

  test "Generate builds exactly the ticked plays, which the preview then serves",
       %{conn: conn, a: a, b: b} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    lv |> element(box(b)) |> render_click()
    generate(lv)

    page = get(conn, ~p"/admin/export/preview/plays/#{a.code}/index.html")
    assert html_response(page, 200) =~ "Alpha Tragedy"
    assert response(get(conn, ~p"/admin/export/preview/plays/#{b.code}/index.html"), 404)

    catalogue = get(conn, ~p"/admin/export/preview/index.html")
    assert html_response(catalogue, 200) =~ "Alpha Tragedy"
    refute html_response(catalogue, 200) =~ "Beta Comedy"
  end

  test "plays already in the site start ticked, the others do not", %{conn: conn, a: a, b: b} do
    {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [a.code])

    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "#play-#{a.id}", t("In site"))
    assert has_element?(lv, "#{box(a)}[checked]")
    assert has_element?(lv, "#play-#{b.id}", t("Not built"))
    refute has_element?(lv, "#{box(b)}[checked]")
  end

  test "an existing site can be previewed and downloaded without generating again",
       %{conn: conn, a: a} do
    {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [a.code])

    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "a[href='/admin/export/preview/index.html']", t("Open preview"))
    assert has_element?(lv, "button", t("Download .zip"))
  end

  test "previewing before anything is built sends you back to the page", %{conn: conn} do
    conn = get(conn, ~p"/admin/export/preview/index.html")

    assert redirected_to(conn) == ~p"/admin/export"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
             t("No site built yet. Generate the static site first.")
  end

  describe "the preview" do
    setup %{a: a} do
      {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [a.code])
      :ok
    end

    test "serves the site's own files with their types", %{conn: conn} do
      css = get(conn, ~p"/admin/export/preview/assets/style.css")
      assert response(css, 200)
      assert [type] = get_resp_header(css, "content-type")
      assert type =~ "text/css"
    end

    test "never reads outside the site directory", %{conn: conn} do
      # A real file one level above the site, so a missing guard would serve it.
      secret = Path.join(Path.dirname(StaticSite.output_dir()), "playcode-test-secret.txt")
      File.write!(secret, "secret")
      on_exit(fn -> File.rm(secret) end)

      assert response(get(conn, "/admin/export/preview/..%2fplaycode-test-secret.txt"), 404)
      assert response(get(conn, "/admin/export/preview/%2e%2e/playcode-test-secret.txt"), 404)
    end
  end
end
