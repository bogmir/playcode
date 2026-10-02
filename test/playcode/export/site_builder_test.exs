defmodule Playcode.Export.SiteBuilderTest do
  @moduledoc """
  The one process that writes and ships the admin's static site. Driven through its
  public functions and read back from the files it writes and the broadcasts it sends.
  """
  # Not async: the builder runs in the app's tree, so its tasks reach the database only
  # in the shared sandbox, and it writes the one site directory the admin page also uses.
  use Playcode.DataCase, async: false

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Export.{SiteBuilder, StaticSite}

  setup do
    File.rm_rf!(StaticSite.output_dir())
    on_exit(fn -> File.rm_rf!(StaticSite.output_dir()) end)
    SiteBuilder.subscribe()
    :ok
  end

  defp in_site, do: StaticSite.list_exported_codes(StaticSite.output_dir())

  defp in_search do
    {"plays", "all", plays} = load_js!(StaticSite.output_dir(), "search/plays.js")
    Enum.map(plays, & &1["code"])
  end

  test "a second job is refused while one runs, and the first lands intact" do
    a = play_fixture()
    b = play_fixture()

    # Not a race: a build loads from the database and writes files, milliseconds, while
    # the second call follows within microseconds, and the builder marks itself busy
    # before it replies to the first.
    assert :ok = SiteBuilder.add(a.id, [])
    assert {:error, :busy} = SiteBuilder.add(b.id, [])
    assert_receive {:site_builder, :done, {:add, _}, :ok}, 5_000
    assert in_site() == [a.code]

    assert :ok = SiteBuilder.add(b.id, [])
    assert_receive {:site_builder, :done, {:add, _}, :ok}, 5_000
    assert in_site() == Enum.sort([a.code, b.code])
    assert Enum.sort(in_search()) == Enum.sort([a.code, b.code])
  end

  @tag :capture_log
  test "a job that crashes is reported, and the builder carries on" do
    missing = Ecto.UUID.generate()
    play = play_fixture()

    assert :ok = SiteBuilder.add(missing, [])
    assert_receive {:site_builder, :failed, {:add, ^missing}, _reason}, 5_000
    assert SiteBuilder.status() == %{job: nil}

    assert :ok = SiteBuilder.add(play.id, [])
    assert_receive {:site_builder, :done, {:add, _}, :ok}, 5_000
    assert in_site() == [play.code]
  end

  test "status names the running job" do
    play = play_fixture()

    assert :ok = SiteBuilder.add(play.id, [])
    assert SiteBuilder.status() == %{job: {:add, play.id}}
    assert_receive {:site_builder, :done, {:add, _}, :ok}, 5_000
    assert SiteBuilder.status() == %{job: nil}
  end

  # A deploy pushes the whole directory, so one during a build would publish half a site.
  # No real deploy runs here: the refusal is the behaviour.
  test "a deploy is refused while a build runs" do
    play = play_fixture()

    assert :ok = SiteBuilder.add(play.id, [])
    assert {:error, :busy} = SiteBuilder.deploy("owner/repo")
    assert_receive {:site_builder, :done, {:add, _}, :ok}, 5_000
  end
end
