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
    # deploy_test.exs leaves its deploy record behind.
    File.rm(Path.expand(StaticSite.output_dir()) <> ".deployed.json")
    previous = Application.get_env(:playcode, :static_site_deploy)

    on_exit(fn ->
      await_idle_builder()
      File.rm_rf!(StaticSite.output_dir())
      File.rm(Path.expand(StaticSite.output_dir()) <> ".deployed.json")
      Application.put_env(:playcode, :static_site_deploy, previous)
    end)

    complete = %{"is_complete" => true}
    a = play_fixture(Map.put(complete, "title", "Alpha Tragedy"))
    b = play_fixture(Map.put(complete, "title", "Beta Comedy"))
    _draft = play_fixture(%{"title" => "Gamma Draft"})

    %{conn: log_in_user(conn, admin_fixture()), a: a, b: b}
  end

  defp build_site(codes),
    do: {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: codes)

  # What a deploy leaves behind, without pushing anywhere.
  defp deployed(codes) do
    build_site(codes)
    StaticSite.record_deploy(StaticSite.output_dir())
  end

  defp deploy_settings(settings),
    do: Application.put_env(:playcode, :static_site_deploy, settings)

  defp bare_repo do
    dir = Path.join(System.tmp_dir!(), "page-deploy-#{System.unique_integer([:positive])}.git")
    {_, 0} = System.cmd("git", ["init", "--bare", "--quiet", dir])
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp preview(conn, path), do: get(conn, "/admin/export/preview/" <> path)

  defp set_version(lv, version),
    do: lv |> element("#edition-version form") |> render_change(%{"version" => version})

  defp generate(lv) do
    lv |> element("button", t("Generate preview")) |> render_click()
    wait_for(fn -> not has_element?(lv, "#build-progress") end)
  end

  defp wait_for(fun, tries \\ 500) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("timed out waiting for the build")
      true -> Process.sleep(10) && wait_for(fun, tries - 1)
    end
  end

  defp in_group?(lv, group, play), do: has_element?(lv, "#group-#{group} #play-#{play.code}")

  test "a complete play not on the live site is listed as new", %{conn: conn, a: a, b: b} do
    {:ok, lv, html} = live(conn, ~p"/admin/export")

    assert in_group?(lv, "new", a)
    assert in_group?(lv, "new", b)
    refute html =~ "Gamma Draft"

    assert has_element?(
             lv,
             "#publish-card",
             n("One play to publish", "%{count} plays to publish", 2)
           )
  end

  test "with every play live, nothing waits", %{conn: conn, a: a, b: b} do
    build_site([a.code, b.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    refute has_element?(lv, "#group-new")
    assert has_element?(lv, "#publish-card", t("Everything is published."))
    assert in_group?(lv, "live", a)
  end

  test "a deployed play edited since is listed as changed, with the day it was edited",
       %{conn: conn, a: a, b: b} do
    deploy_settings(repo: "file:///not-pushed-to")
    deployed([a.code, b.code])
    {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert in_group?(lv, "changed", a)
    edited = Calendar.strftime(Catalogue.get_play!(a.id).content_changed_at, "%Y-%m-%d")
    assert has_element?(lv, "#play-#{a.code}", t("edited %{date}", date: edited))
    assert in_group?(lv, "live", b)
  end

  test "a deployed play set back to draft or archived is listed as leaving",
       %{conn: conn, a: a, b: b} do
    deploy_settings(repo: "file:///not-pushed-to")
    deployed([a.code, b.code])
    {:ok, _} = Catalogue.update_play(a, %{"is_complete" => false})
    {:ok, _} = Catalogue.delete_play(b)
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "#group-leaving #play-#{a.code}", t("back to draft"))
    assert has_element?(lv, "#group-leaving #play-#{b.code}", t("archived"))
  end

  test "a purged play still on the site is listed by its code as deleted",
       %{conn: conn, a: a, b: b} do
    deploy_settings(repo: "file:///not-pushed-to")
    deployed([a.code, b.code])
    {:ok, archived} = Catalogue.delete_play(b)
    {:ok, _} = Catalogue.purge_play(archived)
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    # It said "deleted", also of a draft whose code was changed: the play is still there.
    assert has_element?(lv, "#group-leaving #play-#{b.code}", t("no longer in Playcode"))
  end

  test "a site built but not deployed is not live while a repository is configured",
       %{conn: conn, a: a} do
    deploy_settings(repo: "file:///not-pushed-to")
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert in_group?(lv, "new", a)
  end

  test "Publish puts every waiting play online and empties the groups",
       %{conn: conn, a: a, b: b} do
    repo = bare_repo()
    deploy_settings(repo: "file://" <> repo)
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    {:ok, other, _html} = live(log_in_user(build_conn(), admin_fixture()), ~p"/admin/export")

    lv
    |> element("#publish-card button", n("Publish one play", "Publish %{count} plays", 2))
    |> render_click()

    wait_for(fn -> render(lv) =~ String.trim(t("Published at %{url}", url: "")) end)

    refute has_element?(lv, "#group-new")
    assert in_group?(lv, "live", a)
    assert in_group?(lv, "live", b)
    assert StaticSite.deployed_plays(StaticSite.output_dir()) |> Map.has_key?(a.code)
    # A second admin's page follows the job it did not start.
    wait_for(fn -> render(other) =~ String.trim(t("Published at %{url}", url: "")) end)
    refute has_element?(other, "#group-new")
  end

  test "Generate preview builds without deploying", %{conn: conn, a: a} do
    deploy_settings(repo: "file:///not-pushed-to")
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    generate(lv)

    assert in_group?(lv, "new", a)
    assert StaticSite.deployed_plays(StaticSite.output_dir()) == %{}
    assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "Alpha Tragedy"
    assert has_element?(lv, "a[href='/admin/export/preview/index.html']", t("Open preview"))
  end

  test "without a repository there is no Publish, and the hint says what to set",
       %{conn: conn} do
    deploy_settings([])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    refute has_element?(lv, "#publish-card button", t("Publish"))

    refute has_element?(
             lv,
             "#publish-card button",
             n("Publish one play", "Publish %{count} plays", 2)
           )

    # It used to say "on the server", which read wrong on a laptop running Playcode.
    assert render(lv) =~ t("To deploy, set STATIC_SITE_REPO where Playcode runs.")
    refute has_element?(lv, "#deploy-hint a")
  end

  test "a new version is a change to the whole site, named as Playcode's",
       %{conn: conn, a: a} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    refute has_element?(lv, "#site-changed")

    set_version(lv, "9.9")
    assert has_element?(lv, "#site-changed")
    # Over two hours from this page on production (2026-10-17); the command takes minutes.
    assert render(lv) =~ "mix playcode.fly.reimport generate"

    generate(lv)
    refute has_element?(lv, "#site-changed")
    assert html_response(preview(conn, "plays/#{a.code}/index.html"), 200) =~ "9.9"
  end

  # Regression: the field always started at the app's version, so a site built under
  # another said its design had changed on every visit, and Generate rebuilt it all.
  test "the next visit starts from the version the site was built with", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    set_version(lv, "2.0")
    generate(lv)

    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    refute has_element?(lv, "#site-changed")
    assert has_element?(lv, "#edition-version input[name=version][value='2.0']")
  end

  test "Up to date is searchable and 50 to a page", %{conn: conn, a: a, b: b} do
    more =
      for i <- 1..49,
          do:
            play_fixture(%{
              "is_complete" => true,
              "title" => "Zeta #{String.pad_leading("#{i}", 2, "0")}"
            })

    build_site(Enum.map([a, b | more], & &1.code))
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(
             lv,
             "#group-live",
             t("Up to date (%{count})", count: 51)
           )

    refute in_group?(lv, "live", List.last(more))
    lv |> element("#group-live button", t("Next")) |> render_click()
    assert in_group?(lv, "live", List.last(more))

    # One play edited while page 2 shows: 50 left, one page, and the list shows it.
    {:ok, _} = Catalogue.update_play(b, %{"title" => "Beta Revised"})
    # What Playcode.Export.PlayChangeListener sends when the edit commits.
    Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, b.id})
    assert in_group?(lv, "changed", b)
    assert in_group?(lv, "live", a)

    lv |> element("#group-live form") |> render_change(%{"search" => "alpha"})
    assert in_group?(lv, "live", a)
    refute in_group?(lv, "live", List.last(more))
  end

  # Regression: every play_changed walked the whole site again, seconds on production,
  # in a task nothing cancelled, so a run of edits piled the walks up.
  test "a play edit regroups the plays without counting the site again", %{conn: conn, a: a} do
    build_site([a.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    render_async(lv)
    size = lv |> element("#site-size") |> render()

    File.write!(Path.join(StaticSite.output_dir(), "padding.bin"), :binary.copy("x", 2_000_000))
    {:ok, _} = Catalogue.update_play(a, %{"title" => "Alpha Revised"})
    Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", {:play_changed, a.id})

    assert in_group?(lv, "changed", a)
    render_async(lv)
    assert lv |> element("#site-size") |> render() == size
  end

  test "a Generate that rewrote only the styles or the catalogue says so",
       %{conn: conn, a: a, b: b} do
    build_site([a.code, b.code])
    path = Path.join(StaticSite.output_dir(), "build.json")
    json = path |> File.read!() |> Jason.decode!() |> Map.merge(%{"assets" => "older"})
    File.write!(path, Jason.encode!(json))
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    generate(lv)
    assert render(lv) =~ t("The site's styles and scripts are updated.")
    refute render(lv) =~ t("Nothing has changed since the last build.")
  end

  test "with nothing waiting but the whole site changed, the headline does not say all is published",
       %{conn: conn, a: a, b: b} do
    build_site([a.code, b.code])
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    set_version(lv, "9.9")

    assert has_element?(lv, "#site-changed")
    refute has_element?(lv, "#publish-card", t("Everything is published."))
  end

  test "a failed Publish names the step that failed", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    broadcast = &Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", &1)

    broadcast.({:site_builder, :started, :publish})
    broadcast.({:site_builder, :done, :publish, {:error, "no plays"}})
    assert render(lv) =~ t("Generation failed: %{reason}", reason: "no plays")

    broadcast.({:site_builder, :started, :publish})
    broadcast.({:site_builder, :progress, :deploy, {:push, "gh-pages"}})
    broadcast.({:site_builder, :done, :publish, {:error, "rejected"}})
    assert render(lv) =~ t("Deploy failed: %{reason}", reason: "rejected")
  end

  test "a page opened while a Publish deploys shows its second step, in the page's language",
       %{conn: conn} do
    test = self()
    repo = "file://" <> bare_repo()

    deploy_settings(
      repo: repo,
      publish_url: "https://publish.example/playcode-deploy.php",
      publish_token: "key"
    )

    Req.Test.set_req_test_to_shared()

    Req.Test.stub(Playcode.Export.StaticSite.Deployer, fn conn ->
      send(test, {:holding, self()})
      receive do: (:go -> :ok), after: (10_000 -> :ok)
      Req.Test.json(conn, %{ok: true, target: "edicion", commit: "abc123"})
    end)

    Playcode.Export.SiteBuilder.publish([], repo)
    assert_receive {:holding, server}, 30_000

    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "#build-progress", t("Step 2 of 2"))

    assert has_element?(
             lv,
             "#build-progress",
             t("Publishing on %{host}...", host: "publish.example")
           )

    refute has_element?(lv, "#build-progress", "Publishing on publish.example")
    send(server, :go)
  end

  test "a build's progress reads in the page's language", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    broadcast = &Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", &1)

    broadcast.({:site_builder, :started, :generate})

    broadcast.(
      {:site_builder, :progress, :generate,
       %{step: :assets, current: 0, total: 2, detail: "Writing assets..."}}
    )

    assert has_element?(lv, "#build-progress", t("Writing assets..."))
    refute has_element?(lv, "#build-progress", "Writing assets...")
  end

  test "a page number that is not one shows the first page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    render_hook(lv, "live_page", %{"page" => "two"})

    assert has_element?(lv, "#publish-card")
  end

  test "the last deploy's time names its zone", %{conn: conn, a: a} do
    deployed([a.code])
    deploy_settings(repo: "file:///not-pushed-to")

    {:ok, lv, _html} = live(conn, ~p"/admin/export")

    assert has_element?(lv, "#publish-card", "UTC")
  end

  # The size walks every file, seconds on production's volume: counted after connecting.
  test "the page opens before the site's size is counted, and the size follows",
       %{conn: conn, a: a} do
    build_site([a.code])

    static = conn |> get(~p"/admin/export") |> html_response(200)

    assert static |> LazyHTML.from_document() |> LazyHTML.query("#site-size") |> LazyHTML.text() =~
             "…"

    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    render_async(lv)
    refute lv |> element("#site-size") |> render() =~ "…"
  end

  # A build cannot be made to fail by clicks, so these are the broadcasts the builder
  # would send: its ending with an error, and its task crashing.
  test "a failed Publish or Generate says why", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/export")
    broadcast = &Phoenix.PubSub.broadcast(Playcode.PubSub, "static_site", &1)

    broadcast.({:site_builder, :done, :publish, {:error, "rejected"}})
    assert render(lv) =~ t("Publishing failed: %{reason}", reason: "rejected")

    broadcast.({:site_builder, :failed, :generate, :killed})
    assert render(lv) =~ t("Generation failed: %{reason}", reason: ":killed")
  end

  test "previewing before anything is built sends you back to the page", %{conn: conn} do
    conn = get(conn, ~p"/admin/export/preview/index.html")

    assert redirected_to(conn) == ~p"/admin/export"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
             t("No site built yet. Generate a preview first.")
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

  describe "the deploy hint" do
    test "names the server it publishes on", %{conn: conn} do
      deploy_settings(
        repo: "owner/site",
        publish_url: "https://publish.example/playcode-deploy.php"
      )

      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      # The repository is a link inside the sentence, so the text is asserted, not the markup.
      assert has_element?(
               lv,
               "#deploy-hint",
               t("Pushes the site to %{repo}, then publishes it on %{host}.",
                 repo: "owner/site",
                 host: "publish.example"
               )
             )
    end

    test "links the repository the site is pushed to", %{conn: conn} do
      deploy_settings(repo: "owner/site")
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert has_element?(
               lv,
               "#deploy-hint a[href='https://github.com/owner/site']",
               "owner/site"
             )

      deploy_settings(repo: "https://github.com/owner/other.git")
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert has_element?(lv, "#deploy-hint a[href='https://github.com/owner/other']")
    end

    test "a repository with no page to open is named without a link", %{conn: conn} do
      deploy_settings(repo: "file:///srv/site.git")
      {:ok, lv, _html} = live(conn, ~p"/admin/export")

      assert lv |> element("#deploy-hint") |> render() =~ "file:///srv/site.git"
      refute has_element?(lv, "#deploy-hint a")
    end
  end
end
