defmodule Playcode.Export.DeployTest do
  @moduledoc """
  Deploy, through `SiteBuilder.deploy/1`: the built site is pushed to a git repository's
  gh-pages branch, with the GitHub token when one is set, and then, when a publish URL is
  set, the server behind it is told to fetch it (deploy/playcode-deploy.php on
  emothe.uv.es). The repository here is a bare one on disk; the server is a Req.Test stub,
  or a local HTTP listener when what matters is what git itself sends.
  """
  # Not async: the builder is the app's one process, and the settings are app config.
  use Playcode.DataCase, async: false

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Export.{SiteBuilder, StaticSite}
  alias Playcode.Export.StaticSite.Deployer

  setup do
    File.rm_rf!(StaticSite.output_dir())
    play = play_fixture(%{"title" => "Deployed Play", "is_complete" => true})
    {:ok, _} = StaticSite.generate(output_dir: StaticSite.output_dir(), play_codes: [play.code])

    previous = Application.get_env(:playcode, :static_site_deploy)

    on_exit(fn ->
      await_idle_builder()
      File.rm_rf!(StaticSite.output_dir())
      Application.put_env(:playcode, :static_site_deploy, previous)
    end)

    SiteBuilder.subscribe()
    Req.Test.set_req_test_to_shared()
    %{play: play}
  end

  defp settings(settings), do: Application.put_env(:playcode, :static_site_deploy, settings)

  defp bare_repo do
    dir = Path.join(System.tmp_dir!(), "deploy-#{System.unique_integer([:positive])}.git")
    {_, 0} = System.cmd("git", ["init", "--bare", "--quiet", dir])
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp gh_pages(repo, path),
    do: System.cmd("git", ["--git-dir", repo, "show", "gh-pages:#{path}"], stderr_to_stdout: true)

  defp deploy(repo) do
    SiteBuilder.deploy(repo)
    assert_receive {:site_builder, :done, :deploy, result}, 30_000
    result
  end

  test "a deploy pushes the site to the repository's gh-pages branch", %{play: play} do
    settings([])
    repo = bare_repo()

    assert {:ok, _url} = deploy("file://" <> repo)

    assert {page, 0} = gh_pages(repo, "plays/#{play.code}/index.html")
    assert page =~ "Deployed Play"
  end

  # Regression: the site's .git outlives a deploy (on the volume), so a second deploy with
  # nothing new failed on "nothing to commit", though a retry after a failed push or
  # publish must still push the site and have it published.
  test "a deploy with nothing new since the last still pushes and publishes", %{play: play} do
    settings(publish_url: "https://publish.example/playcode-deploy.php", publish_token: "key")
    test = self()

    Req.Test.stub(Deployer, fn conn ->
      send(test, :published)
      Req.Test.json(conn, %{ok: true, target: "edicion", commit: "abc123"})
    end)

    repo = bare_repo()
    assert {:ok, _url} = deploy("file://" <> repo)
    assert {:ok, _url} = deploy("file://" <> repo)

    assert_received :published
    assert_received :published
    assert {_page, 0} = gh_pages(repo, "plays/#{play.code}/index.html")
  end

  test "with a publish URL, the server is told to fetch the site, and its address is the answer" do
    settings(publish_url: "https://publish.example/playcode-deploy.php", publish_token: "key")
    test = self()

    Req.Test.stub(Deployer, fn conn ->
      send(test, {:published, conn.method, Plug.Conn.get_req_header(conn, "x-deploy-token")})
      Req.Test.json(conn, %{ok: true, target: "edicion", commit: "abc123"})
    end)

    assert {:ok, "https://publish.example/edicion/"} = deploy("file://" <> bare_repo())
    assert_received {:published, "POST", ["key"]}
  end

  test "a refusal from the server fails the deploy with its reason" do
    settings(publish_url: "https://publish.example/playcode-deploy.php", publish_token: "old")

    Req.Test.stub(Deployer, fn conn ->
      conn
      |> Plug.Conn.put_status(403)
      |> Req.Test.json(%{ok: false, error: "wrong token"})
    end)

    assert {:error, reason} = deploy("file://" <> bare_repo())
    assert reason =~ "wrong token"
  end

  # What git sends on the wire, so a local HTTP listener stands in for GitHub. It refuses
  # the push; the token must have been offered, and must not show in the error.
  test "the push carries the GitHub token, which never shows in an error" do
    settings(github_token: "s3cret-token")
    test = self()

    listener =
      start_supervised!(
        {Bandit,
         plug: fn conn, _opts ->
           send(test, {:auth, Plug.Conn.get_req_header(conn, "authorization")})
           Plug.Conn.send_resp(conn, 403, "no")
         end,
         ip: :loopback,
         port: 0,
         startup_log: false}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(listener)

    assert {:error, reason} = deploy("http://127.0.0.1:#{port}/owner/site.git")

    assert_received {:auth, ["Basic " <> credentials]}
    assert Base.decode64!(credentials) == "x-access-token:s3cret-token"
    refute reason =~ "s3cret-token"
  end
end
