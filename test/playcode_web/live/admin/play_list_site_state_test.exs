defmodule PlaycodeWeb.Admin.PlayListSiteStateTest do
  @moduledoc """
  The play list's site column and filter: where each play stands on the live site, the
  plays the last deploy published.
  """
  # Not async: the live site is the one site directory and the deploy settings app config.
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Catalogue
  alias Playcode.Export.StaticSite

  setup %{conn: conn} do
    dir = StaticSite.output_dir()
    File.rm_rf!(dir)
    previous = Application.get_env(:playcode, :static_site_deploy)
    Application.put_env(:playcode, :static_site_deploy, repo: "file:///not-pushed-to")

    on_exit(fn ->
      File.rm_rf!(dir)
      File.rm(Path.expand(dir) <> ".deployed.json")
      Application.put_env(:playcode, :static_site_deploy, previous)
    end)

    %{conn: log_in_user(conn, user_fixture(role: :researcher))}
  end

  defp complete(title), do: play_fixture(%{"title" => title, "is_complete" => true})

  defp deployed(plays) do
    {:ok, _} =
      StaticSite.generate(
        output_dir: StaticSite.output_dir(),
        play_codes: Enum.map(plays, & &1.code)
      )

    StaticSite.record_deploy(StaticSite.output_dir())
  end

  defp site_links, do: "nav[aria-label='#{t("Site")}'] a"

  defp waiting_label(count),
    do: n("%{count} play waits to be published", "%{count} plays wait to be published", count)

  defp site_link_texts(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(site_links())
    |> Enum.map(&String.trim(LazyHTML.text(&1)))
  end

  test "each play shows where it stands on the site", %{conn: conn} do
    draft = play_fixture(%{"title" => "Draft Play"})
    waiting = complete("Waiting Play")
    live = complete("Live Play")
    changed = complete("Changed Play")
    leaving = complete("Leaving Play")
    deployed([live, changed, leaving])
    {:ok, _} = Catalogue.update_play(changed, %{"title" => "Changed Play Revised"})
    {:ok, _} = Catalogue.update_play(leaving, %{"is_complete" => false})

    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    # A draft's site cell is empty: "Draft" in the status column already says it, on
    # most rows of the list (decided 2026-11-25).
    refute has_element?(view, "#play-#{draft.id}", t("Not published"))
    assert has_element?(view, "#play-#{waiting.id}", t("Waiting to be published"))
    assert has_element?(view, "#play-#{live.id}", t("On the site"))
    assert has_element?(view, "#play-#{changed.id}", t("Unpublished changes"))
    assert has_element?(view, "#play-#{leaving.id}", t("Leaving the site"))
  end

  test "the site filter lists only the plays waiting, its count following the search",
       %{conn: conn} do
    waiting = complete("Waiting Play")
    live = complete("Live Play")
    deployed([live])

    {:ok, view, _html} = live(conn, ~p"/admin/plays")
    view |> element(site_links(), waiting_label(1)) |> render_click()

    assert has_element?(view, "#play-#{waiting.id}")
    refute has_element?(view, "#play-#{live.id}")

    view |> element("form[phx-change=search]") |> render_change(%{"search" => "Live"})

    assert has_element?(view, "#{site_links()}[aria-current=page]", waiting_label(0))
  end

  test "the site line names only the states some play is in, and the plays on the site are no filter",
       %{conn: conn} do
    complete("Waiting Play")
    live = complete("Live Play")
    deployed([live])

    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert site_link_texts(view) == [waiting_label(1)]
  end

  test "with nothing to publish there is no site line", %{conn: conn} do
    live = complete("Live Play")
    deployed([live])

    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    refute has_element?(view, site_links())
  end

  test "a Publish that ends moves the list's site states without a reload", %{conn: conn} do
    waiting = complete("Waiting Play")
    {:ok, view, _html} = live(conn, ~p"/admin/plays")
    assert has_element?(view, "#play-#{waiting.id}", t("Waiting to be published"))

    deployed([waiting])

    Phoenix.PubSub.broadcast(
      Playcode.PubSub,
      "static_site",
      {:site_builder, :done, :publish, {:ok, "https://example.test"}}
    )

    assert has_element?(view, "#play-#{waiting.id}", t("On the site"))
  end

  test "a translation waiting under an original on the site is listed under it",
       %{conn: conn} do
    original = complete("Original Play")
    deployed([original])

    translation =
      play_fixture(%{
        "title" => "Translated Play",
        "is_complete" => true,
        "parent_play_id" => original.id,
        "relationship_type" => "traduccion"
      })

    {:ok, view, _html} = live(conn, ~p"/admin/plays?status=waiting")

    assert has_element?(view, "#play-#{original.id}")
    assert has_element?(view, "#play-#{translation.id}", t("Waiting to be published"))
  end
end
