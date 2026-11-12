defmodule PlaycodeWeb.Admin.PublicPageTest do
  @moduledoc """
  A play's link to its page on the published site, and what its overview says about it.
  The link is there only once a deploy published the play and the site's public address
  is set; until then the staff read it through "Vista previa", Playcode's own page.
  """
  # Not async: the builder is the app's one process, and the settings are app config.
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Export.{SiteBuilder, StaticSite}

  @public "https://teatro.example/biblioteca"

  setup %{conn: conn} do
    dir = StaticSite.output_dir()
    File.rm_rf!(dir)
    play = play_fixture() |> mark_complete!()
    {:ok, _} = StaticSite.generate(output_dir: dir, play_codes: [play.code])

    deploy_settings = Application.get_env(:playcode, :static_site_deploy)
    public_url = Application.get_env(:playcode, :static_site_public_url)
    Application.put_env(:playcode, :static_site_deploy, [])
    Application.put_env(:playcode, :static_site_public_url, @public)

    on_exit(fn ->
      await_idle_builder()
      File.rm_rf!(dir)
      File.rm(Path.expand(dir) <> ".deployed.json")
      Application.put_env(:playcode, :static_site_deploy, deploy_settings)
      Application.put_env(:playcode, :static_site_public_url, public_url)
    end)

    SiteBuilder.subscribe()
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
  end

  defp deploy(repo) do
    SiteBuilder.deploy(repo)
    assert_receive {:site_builder, :done, :deploy, result}, 30_000
    result
  end

  defp bare_repo do
    dir = Path.join(System.tmp_dir!(), "public-#{System.unique_integer([:positive])}.git")
    {_, 0} = System.cmd("git", ["init", "--bare", "--quiet", dir])
    on_exit(fn -> File.rm_rf!(dir) end)
    "file://" <> dir
  end

  defp public_link(play), do: "a[href='#{@public}/plays/#{play.code}/']"

  test "a play the last deploy published links its page there", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    refute has_element?(lv, public_link(play))

    assert has_element?(
             lv,
             "#play-state",
             t(
               "Everyone sees it here. The next Generate and Deploy put it on the published site."
             )
           )

    assert {:ok, _url} = deploy(bare_repo())

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    assert has_element?(lv, "nav[aria-label='#{t("Play sections")}'] " <> public_link(play))
    assert has_element?(lv, "#play-state", t("Published on the site."))
  end

  test "a play changed since the deploy says so", %{conn: conn, play: play} do
    assert {:ok, _url} = deploy(bare_repo())
    {:ok, _} = Playcode.Catalogue.update_play(play, %{title: "Retitled"})

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    assert has_element?(lv, public_link(play))

    assert has_element?(
             lv,
             "#play-state",
             t("Published on the site; changed since the last deploy.")
           )
  end

  test "a draft the site still holds says until when", %{conn: conn, play: play} do
    assert {:ok, _url} = deploy(bare_repo())
    {:ok, _} = Playcode.Catalogue.update_play(play, %{is_complete: false})

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(
             lv,
             "#play-state",
             t(
               "Only the team sees it here. The published site keeps it until the next Generate and Deploy."
             )
           )
  end

  test "without the site's public address there is no link", %{conn: conn, play: play} do
    assert {:ok, _url} = deploy(bare_repo())
    Application.put_env(:playcode, :static_site_public_url, nil)

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    refute has_element?(lv, public_link(play))
  end

  test "a failed deploy publishes nothing", %{conn: conn, play: play} do
    assert {:error, _reason} = deploy("not a repo")

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    refute has_element?(lv, public_link(play))
  end
end
