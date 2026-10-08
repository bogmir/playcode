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

  defp set_version(lv, version),
    do: lv |> element("form[phx-submit=generate]") |> render_change(%{"version" => version})

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

  # The dot's screen-reader text: the row says the play has unpublished changes.
  defp flagged?(lv, play), do: has_element?(lv, row(play), t("Unpublished changes"))

  # The green dot's screen-reader text: in the site and up to date.
  defp current?(lv, play), do: has_element?(lv, row(play), t("Published and up to date"))

  # The hollow dot's screen-reader text: in the site, but a draft or archived now.
  defp leaving?(lv, play),
    do:
      has_element?(
        lv,
        row(play),
        t("No longer published (a draft or archived); Generate takes it out.")
      )

  # ConnCase's t/2 is gettext/3, which cannot reach a plural entry.
  defp n(singular, plural, count),
    do: Gettext.ngettext(PlaycodeWeb.Gettext, singular, plural, count)

  # Nothing in the export reads a base URL: the site links relatively, so it works in any
  # folder and opened from disk.
  test "the form asks for no base URL", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/admin/export")
    refute html =~ t("Base URL")
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
    # The page starts from the site's own version, so the site is current and Generate
    # would only refresh. A new version takes it down the full build, where b was lost.
    set_version(lv, "2.0")

    lv |> element(switch(b)) |> render_click()

    assert lv |> element("form[phx-submit=generate]") |> render_submit() =~
             t("Queued: it starts when the current build finishes.")

    wait_for(fn -> render(lv) =~ t("Generation Complete") end)
    assert response(preview(conn, "plays/#{b.code}/index.html"), 200)
  end

  # The play is archived after the page drew it, and before the page heard of it: no
  # notification commits in the sandbox. This used to push the event for a made-up id,
  # which the page now refuses, since only a play it shows as published can be added.
  test "a play deleted since the page drew is skipped and says so", %{conn: conn} do
    gone = play_fixture(%{"title" => "Delta Gone", "is_complete" => true})
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    {:ok, _} = Catalogue.delete_play(gone)

    lv |> element(switch(gone)) |> render_click()

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
    # The page starts from the site's own version, so the site is current and Generate
    # would only refresh. A new version takes it down the full build, where b came back.
    set_version(lv, "2.0")
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

  # The zip is written file by file from disk (a site of 388 plays would not fit in the
  # machine's memory at once); what it holds is the site, by the same paths.
  test "Download .zip hands over the site", %{conn: conn, a: a} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert {:error, {:redirect, %{to: to}}} =
             lv |> element("button", t("Download .zip")) |> render_click()

    {:ok, files} = conn |> get(to) |> response(200) |> :zip.unzip([:memory])
    files = Map.new(files, fn {name, body} -> {List.to_string(name), body} end)

    assert files["plays/#{a.code}/index.html"] =~ "Alpha Tragedy"
    assert files["index.html"] =~ "Alpha Tragedy"
    assert Map.has_key?(files, "assets/style.css")
  end

  # Regression: the figures were the last Generate's, so a switch left them stale.
  test "the site's figures are the site on disk, and follow its switches",
       %{conn: conn, a: a, b: b} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    assert has_element?(lv, "#site-plays", "1")
    size = lv |> element("#site-size") |> render()

    lv |> element(switch(b)) |> render_click()
    wait_for(fn -> render(lv) =~ t("Play exported to static site.") end)

    assert has_element?(lv, "#site-plays", "2")
    refute lv |> element("#site-size") |> render() == size
  end

  # Generate already rebuilds every play when the site's code or settings changed, and
  # only the changed ones otherwise, so a second build button only raised the question
  # of which to press.
  test "Generate is the only build button", %{conn: conn, a: a} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "button", t("Generate Static Site"))
    refute has_element?(lv, "button", t("Rebuild everything"))
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
      refute flagged?(lv, a)

      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert flagged?(lv, a)
      refute flagged?(lv, b)

      assert render(lv) =~
               n(
                 "One published play has changed. Generate refreshes it.",
                 "%{count} published plays have changed. Generate refreshes them.",
                 1
               )

      lv |> element("#refresh-#{a.id}") |> render_click()
      wait_for(fn -> render(lv) =~ t("Play exported to static site.") end)

      refute flagged?(lv, a)
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
      assert flagged?(lv, a)

      assert has_element?(lv, "#{row(a)} label[for='switch-#{a.id}']")
      assert has_element?(lv, "#switch-#{a.id}")
      refute has_element?(lv, "#{row(a)} label button")
    end

    test "a play in the site and up to date has a green dot; one outside it has none",
         %{conn: conn, a: a, b: b} do
      build_site([a.code])
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert current?(lv, a)
      refute current?(lv, b)
      refute flagged?(lv, b)
    end

    test "a changed play shows a dot and an icon-only Refresh", %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert flagged?(lv, a)
      refute current?(lv, a)
      assert has_element?(lv, "#refresh-#{a.id}")
      refute has_element?(lv, "#refresh-#{a.id}", t("Refresh"))
    end

    # The banner and Generate already say every play will be rebuilt: a dot and a
    # Refresh on each row are noise.
    test "while the whole site is out of date, no row is flagged on its own",
         %{conn: conn, a: a, b: b} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      assert flagged?(lv, a)

      set_version(lv, "9.9")

      assert has_element?(lv, "#site-changed")
      refute flagged?(lv, a)
      refute current?(lv, b)
      refute has_element?(lv, "#refresh-#{a.id}")
    end

    test "a change announced while the page is open flags the play at once",
         %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      refute flagged?(lv, a)

      # What Playcode.Export.PlayChangeListener sends when the edit commits.
      Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, a.id})
      assert flagged?(lv, a)
    end

    # Broadcasts what the builder would: between a batch's :published and its :done,
    # build.json still records the play's old version, and clicks cannot stop there.
    test "a refreshed play loses its dot once its pages are published",
         %{conn: conn, a: a} do
      build_site([a.code])
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      assert flagged?(lv, a)

      Phoenix.PubSub.broadcast(
        Playcode.PubSub,
        "static_site",
        {:site_builder, :published, {:batch, [{:add, a.id}]}}
      )

      refute flagged?(lv, a)
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

      refute flagged?(lv, a)
    end

    test "Generate refreshes only the changed plays and says how many", %{conn: conn, a: a} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})

      lv |> element("form[phx-submit=generate]") |> render_submit()
      wait_for(fn -> render(lv) =~ n("One play refreshed.", "%{count} plays refreshed.", 1) end)

      assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "Alpha Revised"
      refute flagged?(lv, a)
    end

    # Regression: the hint counted only the changed plays, and a play no longer published
    # is not in the list either, so the page said the site was up to date.
    test "a play in the site that is no longer published is announced",
         %{conn: conn, a: a, b: b} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)
      {:ok, _} = Catalogue.delete_play(b)

      removed =
        n(
          "One play in the site is no longer published. Generate takes it out.",
          "%{count} plays in the site are no longer published. Generate takes them out.",
          1
        )

      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      assert render(lv) =~ removed
      refute render(lv) =~ t("Every play in the site is up to date.")

      {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      assert render(lv) =~ removed

      assert render(lv) =~
               n(
                 "One published play has changed. Generate refreshes it.",
                 "%{count} published plays have changed. Generate refreshes them.",
                 1
               )
    end

    test "assets changed since the build are announced, not as a full rebuild", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      path = Path.join(StaticSite.output_dir(), "build.json")
      json = path |> File.read!() |> Jason.decode!() |> Map.put("assets", "older")
      File.write!(path, Jason.encode!(json))

      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      assert render(lv) =~ t("The site's styles and scripts have changed. Generate updates them.")
      refute render(lv) =~ t("Every play in the site is up to date.")
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

      set_version(lv, "9.9")
      assert has_element?(lv, "#site-changed")
      assert render(lv) =~ t("Rebuilds the %{count} plays in the site.", count: 2)

      # "Generation Complete" shows only for a full build: starting one hides it first.
      generate(lv)
      refute has_element?(lv, "#site-changed")
    end

    # Regression: the field always started at the app's version, so a site built under
    # another said its design had changed on every visit, and Generate rebuilt it all.
    test "the next visit starts from the version the site was built with", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      set_version(lv, "2.0")
      generate(lv)

      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      refute has_element?(lv, "#site-changed")
      assert has_element?(lv, "input[name=version][value='2.0']")
    end

    # A build cannot be made to fail by clicks, so these are the broadcasts the builder
    # would send: its ending with an error, and its task crashing. It was written for
    # Rebuild everything, which is gone; Generate fails the same way.
    test "a failed Generate says why", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      broadcast = &Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", &1)

      broadcast.({:site_builder, :done, :generate, {:error, :disk_full}})
      assert render(lv) =~ t("Generation failed: %{reason}", reason: ":disk_full")

      broadcast.({:site_builder, :failed, :generate, :killed})
      assert render(lv) =~ t("Generation failed: %{reason}", reason: ":killed")
    end
  end

  describe "a play in the site that is no longer published" do
    test "stays in the list, marked, until its switch takes it out", %{conn: conn, a: a, b: b} do
      build_site([a.code, b.code])
      {:ok, _} = Catalogue.update_play(b, %{"is_complete" => false})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert leaving?(lv, b)
      refute current?(lv, b)

      assert render(lv) =~
               t("%{exported} of %{total} complete plays exported", exported: 1, total: 1)

      lv |> element(switch(b)) |> render_click()
      wait_for(fn -> render(lv) =~ t("Removed %{code} from static site.", code: b.code) end)

      refute has_element?(lv, row(b))
      assert StaticSite.list_exported_codes(StaticSite.output_dir()) == [a.code]
    end

    test "is marked as soon as it is set to draft", %{conn: conn, a: a, b: b} do
      build_site([a.code, b.code])
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      assert current?(lv, b)

      {:ok, _} = Catalogue.update_play(b, %{"is_complete" => false})
      # What Playcode.Export.PlayChangeListener sends when the edit commits.
      Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, b.id})

      assert leaving?(lv, b)
      refute current?(lv, b)
    end

    test "a play marked complete while the page is open joins the list at once",
         %{conn: conn} do
      delta = play_fixture(%{"title" => "Delta Draft"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      refute has_element?(lv, row(delta))

      {:ok, _} = Catalogue.update_play(delta, %{"is_complete" => true})
      Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, delta.id})

      assert has_element?(lv, switch(delta))
    end

    # The switch's event names any play; the page offers switching on only to
    # published ones, so a draft must not get in by a hand-made event.
    test "the switch event cannot put a draft in the site", %{conn: conn} do
      draft = play_fixture(%{"title" => "Delta Draft"})
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      render_hook(lv, "toggle_play", %{"id" => draft.id, "code" => draft.code})
      await_idle_builder()

      refute draft.code in StaticSite.list_exported_codes(StaticSite.output_dir())
    end
  end

  describe "deploy" do
    setup do
      previous = Application.get_env(:playcode, :static_site_deploy)
      on_exit(fn -> Application.put_env(:playcode, :static_site_deploy, previous) end)
    end

    defp deploy_settings(settings),
      do: Application.put_env(:playcode, :static_site_deploy, settings)

    defp bare_repo do
      dir = Path.join(System.tmp_dir!(), "page-deploy-#{System.unique_integer([:positive])}.git")
      {_, 0} = System.cmd("git", ["init", "--bare", "--quiet", dir])
      on_exit(fn -> File.rm_rf!(dir) end)
      dir
    end

    # The repository is server config, not typed in: the GitHub token goes only to it.
    test "goes to the configured repository, which the page names", %{conn: conn, a: a} do
      repo = bare_repo()
      deploy_settings(repo: "file://" <> repo)
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      assert render(lv) =~ t("Pushes the site to %{repo}.", repo: "file://" <> repo)
      size = lv |> element("#site-size") |> render()

      lv |> element("button", t("Deploy")) |> render_click()
      wait_for(fn -> render(lv) =~ t("Deployed!") end)

      # The push leaves a .git in the site directory; it is not part of the site.
      assert lv |> element("#site-size") |> render() == size

      assert {page, 0} =
               System.cmd("git", [
                 "--git-dir",
                 repo,
                 "show",
                 "gh-pages:plays/#{a.code}/index.html"
               ])

      assert page =~ "Alpha Tragedy"
    end

    test "names the server it publishes on", %{conn: conn} do
      deploy_settings(
        repo: "owner/site",
        publish_url: "https://publish.example/playcode-deploy.php"
      )

      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      assert render(lv) =~
               t("Pushes the site to %{repo}, then publishes it on %{host}.",
                 repo: "owner/site",
                 host: "publish.example"
               )
    end

    test "with no repository configured, offers no Deploy and says what to set",
         %{conn: conn} do
      deploy_settings([])
      {:ok, lv, _html} = live(conn, ~p"/admin/export")
      generate(lv)

      refute has_element?(lv, "button", t("Deploy"))
      # It used to say "on the server", which read wrong on a laptop running Playcode.
      assert render(lv) =~ t("To deploy, set STATIC_SITE_REPO where Playcode runs.")
    end
  end
end
