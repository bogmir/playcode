defmodule Playcode.ReleaseSiteTest do
  @moduledoc """
  Generate and Deploy from the console (`bin/playcode rpc`), as `mix playcode.fly.reimport
  generate` and `deploy` run them on Fly: each asks the app's one site builder and waits
  for the job to end, printing what it did.
  """
  # Not async: the builder runs in the app's tree, so its tasks reach the database only
  # in the shared sandbox, and it writes the one site directory the admin page also uses.
  use Playcode.DataCase, async: false

  import ExUnit.CaptureIO
  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Export.StaticSite
  alias Playcode.Release

  setup do
    File.rm_rf!(StaticSite.output_dir())

    on_exit(fn ->
      await_idle_builder()
      File.rm_rf!(StaticSite.output_dir())
    end)
  end

  test "generate_site builds the site, waits for it, and says it is done" do
    play = mark_complete!(play_fixture())

    out = capture_io(fn -> assert :ok = Release.generate_site() end)

    assert out =~ "site generated"
    assert play.code in StaticSite.list_exported_codes(StaticSite.output_dir())
  end

  # The site is not built, so Deployer refuses before it pushes anything, and the repository
  # is invalid on purpose (no "/"): this test can never reach GitHub.
  test "deploy_site waits for the deploy and reports its failure" do
    deploy = Application.get_env(:playcode, :static_site_deploy, [])
    on_exit(fn -> Application.put_env(:playcode, :static_site_deploy, deploy) end)
    Application.put_env(:playcode, :static_site_deploy, Keyword.put(deploy, :repo, "not a repo"))

    out = capture_io(fn -> assert {:error, _reason} = Release.deploy_site() end)

    assert out =~ "deploy failed"
    assert out =~ "Generate the site first"
  end

  test "deploy_site with no repository says where to set one" do
    deploy = Application.get_env(:playcode, :static_site_deploy, [])
    on_exit(fn -> Application.put_env(:playcode, :static_site_deploy, deploy) end)
    Application.put_env(:playcode, :static_site_deploy, Keyword.delete(deploy, :repo))

    out = capture_io(fn -> assert {:error, :no_repo} = Release.deploy_site() end)

    assert out =~ "STATIC_SITE_REPO"
  end
end
