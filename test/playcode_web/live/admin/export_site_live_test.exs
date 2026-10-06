defmodule PlaycodeWeb.Admin.ExportSiteLiveTest do
  # Not async: Generate runs in a task that reads the database, which only works in the
  # shared sandbox, and every test builds into the same temporary site directory.
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers, only: [await_idle_builder: 0]

  alias Playcode.Catalogue
  alias Playcode.Export.StaticSite

  setup %{conn: conn} do
    File.rm_rf!(StaticSite.output_dir())

    on_exit(fn ->
      await_idle_builder()
      File.rm_rf!(StaticSite.output_dir())
    end)

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

  defp row(play), do: "#play-#{play.id}"

  # ConnCase's t/2 is gettext/3, which cannot reach a plural entry.
  defp n(singular, plural, count),
    do: Gettext.ngettext(PlaycodeWeb.Gettext, singular, plural, count)

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

  test "a second admin's page follows a build started on the first", %{conn: conn, a: a} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    {:ok, other, _html} = live(log_in_user(build_conn(), admin_fixture()), ~p"/admin/export")

    lv |> element(switch(a)) |> render_click()

    # No event goes to the other page: it hears the build from the site builder.
    wait_for(fn ->
      has_element?(other, "#{switch(a)}[checked]") and
        render(other) =~ t("Play exported to static site.")
    end)
  end

  test "Download is refused while a build runs", %{conn: conn, a: a, b: b} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    lv |> element(switch(b)) |> render_click()

    # Not a race: adding a play loads it and writes files, milliseconds, while the click
    # follows within microseconds, and the builder is busy before the switch returns.
    # The button is disabled once this page has drawn the build, so the event is pushed
    # as a page that has not caught up would send it: the server must refuse anyway.
    assert render_click(lv, "download_zip", %{}) =~
             t("The site is busy with another build. Try again when it finishes.")

    wait_for(fn -> render(lv) =~ t("Play exported to static site.") end)
  end

  test "switches flipped during a build wait their turn and land together",
       %{conn: conn, a: a, b: b} do
    c = play_fixture(%{"is_complete" => true, "title" => "Delta Farce"})
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    # Not a race: adding a loads a play and writes files, tens of milliseconds, while the
    # next clicks each take a round trip of well under that, so they reach a busy builder
    # and queue.
    lv |> element(switch(a)) |> render_click()
    lv |> element(switch(b)) |> render_click()
    lv |> element(switch(c)) |> render_click()

    # On its way in: shown on, and not clickable until it lands.
    assert has_element?(lv, "#{switch(b)}[checked][disabled]")

    wait_for(fn -> render(lv) =~ t("%{count} changes applied to the static site.", count: 2) end)

    assert has_element?(lv, "#{switch(b)}[checked]")
    assert has_element?(lv, "#{switch(c)}[checked]")
    refute has_element?(lv, "#{switch(c)}[disabled]")
    assert response(preview(conn, "plays/#{c.code}/index.html"), 200)
  end

  test "Generate pressed while a play is being added keeps that play",
       %{conn: conn, a: a, b: b} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    lv |> element(switch(b)) |> render_click()

    assert lv |> element("form[phx-submit=generate]") |> render_submit() =~
             t("Queued: it starts when the current build finishes.")

    wait_for(fn -> render(lv) =~ t("Generation Complete") end)
    assert response(preview(conn, "plays/#{b.code}/index.html"), 200)
  end

  test "a play deleted since the page drew is skipped and says so", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    render_click(lv, "toggle_play", %{"id" => Ecto.UUID.generate(), "code" => "NOPE"})

    # ConnCase's t/2 is gettext/3, which cannot reach a plural entry: ask for its singular.
    skipped =
      Gettext.ngettext(
        PlaycodeWeb.Gettext,
        "A play that no longer exists was skipped.",
        "%{count} plays that no longer exist were skipped.",
        1
      )

    wait_for(fn -> render(lv) =~ skipped end)
  end

  # Broadcasts what the builder would: the window between :published and :done cannot be
  # hit by clicks deterministically, and the broadcasts are the page's interface to it.
  test "a change queued while a batch was landing keeps its switch pending",
       %{conn: conn, a: a} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    assert has_element?(lv, "#{switch(a)}[checked]")
    refute has_element?(lv, "#{switch(a)}[disabled]")

    broadcast = &Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", &1)
    broadcast.({:site_builder, :queued, {:remove, a.code}})
    broadcast.({:site_builder, :done, {:batch, [{:add, a.id}]}, {:ok, %{skipped: []}}})

    # render/1 is answered after the two broadcasts, which reached the page before it.
    render(lv)
    assert has_element?(lv, "#{switch(a)}[disabled]")
    refute has_element?(lv, "#{switch(a)}[checked]")
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

  describe "changes since the last build" do
    test "a published play edited since is flagged, and Refresh publishes it again",
         %{conn: conn, a: a, b: b} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      refute has_element?(lv, row(a), t("Changed"))

      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert has_element?(lv, row(a), t("Changed"))
      refute has_element?(lv, row(b), t("Changed"))

      assert render(lv) =~
               n(
                 "One published play has changed. Generate refreshes it.",
                 "%{count} published plays have changed. Generate refreshes them.",
                 1
               )

      lv |> element("#{row(a)} button", t("Refresh")) |> render_click()
      wait_for(fn -> render(lv) =~ t("Play exported to static site.") end)

      refute has_element?(lv, row(a), t("Changed"))
      assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "Alpha Revised"
    end

    # Looks at markup because LiveViewTest cannot click a label, and the bug is what the
    # label's control is: a label with no `for` is tied to its first labelable descendant,
    # and a button is one. Refresh before the switch took over the row's label, so a click
    # on the play's title pressed Refresh instead of flipping the switch.
    test "on a changed row the label targets the switch, and Refresh is outside it",
         %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      assert has_element?(lv, row(a), t("Changed"))

      assert has_element?(lv, "#{row(a)} label[for='switch-#{a.id}']")
      assert has_element?(lv, "#switch-#{a.id}")
      refute has_element?(lv, "#{row(a)} label button")
    end

    test "a change announced while the page is open flags the play at once",
         %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      refute has_element?(lv, row(a), t("Changed"))

      # What Playcode.Export.PlayChangeListener sends when the edit commits.
      Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, a.id})
      assert has_element?(lv, row(a), t("Changed"))
    end

    # Review Focus 5.
    test "a change to a play that no longer exists flags nothing", %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      Phoenix.PubSub.broadcast(
        Playcode.PubSub,
        "static_site",
        {:play_changed, Ecto.UUID.generate()}
      )

      refute has_element?(lv, row(a), t("Changed"))
    end

    test "Generate refreshes only the changed plays and says how many", %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})

      lv |> element("form[phx-submit=generate]") |> render_submit()
      wait_for(fn -> render(lv) =~ n("One play refreshed.", "%{count} plays refreshed.", 1) end)

      assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "Alpha Revised"
      refute has_element?(lv, row(a), t("Changed"))
    end

    test "Generate with nothing changed says so", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      assert render(lv) =~ t("Every play in the site is up to date.")

      lv |> element("form[phx-submit=generate]") |> render_submit()
      wait_for(fn -> render(lv) =~ t("Nothing has changed since the last build.") end)
    end

    # Review Focus 4: every page's footer shows the version.
    test "a new version is a change to the whole site: Generate rebuilds every play",
         %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      refute has_element?(lv, "#site-changed")

      lv |> element("form[phx-submit=generate]") |> render_change(%{"version" => "9.9"})
      assert has_element?(lv, "#site-changed")
      assert render(lv) =~ t("Rebuilds the %{count} plays in the site.", count: 2)

      # "Generation Complete" shows only for a full build: starting one hides it first.
      generate(lv)
      refute has_element?(lv, "#site-changed")
    end

    test "Rebuild everything rebuilds the site though nothing changed", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      lv |> element("button", t("Rebuild everything")) |> render_click()
      wait_for(fn -> render(lv) =~ t("Generation Complete") end)
    end

    # A build cannot be made to fail by clicks, so these are the broadcasts the builder
    # would send: its ending with an error, and its task crashing.
    test "a failed Rebuild everything says why", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      broadcast = &Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", &1)

      broadcast.({:site_builder, :done, :rebuild, {:error, :disk_full}})
      assert render(lv) =~ t("Generation failed: %{reason}", reason: ":disk_full")

      broadcast.({:site_builder, :failed, :rebuild, :killed})
      assert render(lv) =~ t("Generation failed: %{reason}", reason: ":killed")
    end
  end
end
