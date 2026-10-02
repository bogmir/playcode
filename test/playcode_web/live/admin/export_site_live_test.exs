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

  defp switch(play), do: "#play-#{play.id} input[role=switch]"

  defp build_site(codes),
    do: {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: codes)

  defp preview(conn, path), do: get(conn, "/admin/export/preview/" <> path)

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

  test "lists the complete plays, each switched off while no site exists",
       %{conn: conn, a: a, b: b} do
    {:ok, lv, html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, switch(a))
    refute has_element?(lv, "#{switch(a)}[checked]")
    refute has_element?(lv, "#{switch(b)}[checked]")
    refute html =~ "Gamma Draft"
  end

  test "switching a play on puts it in the site straight away; off takes it out",
       %{conn: conn, a: a} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    lv |> element(switch(a)) |> render_click()
    wait_for(fn -> render(lv) =~ t("Play exported to static site.") end)

    assert has_element?(lv, "#{switch(a)}[checked]")
    assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "Alpha Tragedy"
    assert html_response(preview(conn, "index.html"), 200) =~ "Alpha Tragedy"

    # Removing rebuilds the index, so it runs in a task like adding does.
    lv |> element(switch(a)) |> render_click()
    wait_for(fn -> render(lv) =~ t("Removed %{code} from static site.", code: a.code) end)

    refute has_element?(lv, "#{switch(a)}[checked]")
    assert response(preview(conn, "plays/#{a.code}/index.html"), 404)
    refute html_response(preview(conn, "index.html"), 200) =~ "Alpha Tragedy"
    refute has_element?(lv, "#{switch(a)}[disabled]")
  end

  test "with no site yet, Generate builds every complete play", %{conn: conn, a: a, b: b} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    generate(lv)

    assert response(preview(conn, "plays/#{a.code}/index.html"), 200)
    assert response(preview(conn, "plays/#{b.code}/index.html"), 200)
  end

  # Regression: Generate rebuilt every complete play, so a play switched off came back.
  test "Generate rebuilds only the plays in the site, so a removed play stays out",
       %{conn: conn, a: a, b: b} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    generate(lv)

    assert response(preview(conn, "plays/#{a.code}/index.html"), 200)
    assert response(preview(conn, "plays/#{b.code}/index.html"), 404)
  end

  test "an existing site can be previewed and downloaded without generating again",
       %{conn: conn, a: a} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "#{switch(a)}[checked]")
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
      build_site([a.code])
      :ok
    end

    # Each file of the site is its own request; none of them is a page to return to.
    test "is not remembered as the last page visited", %{conn: conn} do
      conn = get(conn, ~p"/admin/export")
      conn = preview(conn, "assets/style.css")

      assert get_session(conn, :last_path) == "/admin/export"
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
