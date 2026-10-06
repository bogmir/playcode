defmodule PlaycodeWeb.Admin.PlayListLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Catalogue

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher))}
  end

  defp click(view, play, label),
    do: view |> element("#play-#{play.id} button[aria-label='#{t(label)}']") |> render_click()

  test "searching narrows the list", %{conn: conn} do
    alpha = play_fixture(%{"title" => "Alpha Tragedy"})
    beta = play_fixture(%{"title" => "Beta Comedy"})

    {:ok, view, html} = live(conn, ~p"/admin/plays")
    assert html =~ alpha.title and html =~ beta.title

    html = view |> element("form[phx-change=search]") |> render_change(%{"search" => "Alpha"})

    assert html =~ alpha.title
    refute html =~ beta.title
  end

  # Reads PubSub's registry, past the page: how often the list listens to a play does not
  # show on it, but each extra subscription reloaded the whole list once more per edit,
  # and every page change or search added one.
  test "the list listens once to each play it shows, and stops for plays it no longer shows",
       %{conn: conn} do
    alpha = play_fixture(%{"title" => "Alpha Tragedy"})
    beta = play_fixture(%{"title" => "Beta Comedy"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    search = fn term ->
      view |> element("form[phx-change=search]") |> render_change(%{"search" => term})
    end

    subscriptions = fn play ->
      Playcode.PubSub
      |> Registry.lookup("play_content:#{play.id}")
      |> Enum.count(fn {pid, _} -> pid == view.pid end)
    end

    search.("Alpha")
    search.("")
    assert subscriptions.(alpha) == 1
    assert subscriptions.(beta) == 1

    search.("Alpha")
    assert subscriptions.(beta) == 0
  end

  test "each row says whether the play is a draft or complete, and follows a status change",
       %{conn: conn} do
    play = play_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    # The status is a coloured bar on the row; its text is what a screen reader and the
    # tooltip say, which is what these assertions read.
    assert has_element?(view, "#play-#{play.id} td", t("Draft"))
    refute has_element?(view, "#play-#{play.id} td", t("Complete"))

    {:ok, _} = Catalogue.update_play_from_form(play, %{"is_complete" => "true"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays")
    assert has_element?(view, "#play-#{play.id} td", t("Complete"))
    refute has_element?(view, "#play-#{play.id} td", t("Draft"))
  end

  test "an archived play shows no status, which no longer applies to it", %{conn: conn} do
    play = play_fixture()
    {:ok, _} = Catalogue.delete_play(play)

    {:ok, view, _html} = live(conn, ~p"/admin/plays?archived=1")

    refute has_element?(view, "#play-#{play.id} td", t("Draft"))
    refute has_element?(view, "#play-#{play.id} td", t("Complete"))
  end

  test "an archived play leaves the list, waits under the archived filter, and can be restored",
       %{conn: conn} do
    play = play_fixture(%{"title" => "Archive Me"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    click(view, play, "Archive")
    refute render(view) =~ "Archive Me"
    assert Catalogue.get_play!(play.id, include_deleted: true).deleted_at

    {:ok, archived, html} = live(conn, ~p"/admin/plays?archived=1")
    assert html =~ "Archive Me"

    click(archived, play, "Restore")
    refute render(archived) =~ "Archive Me"

    {:ok, _view, html} = live(conn, ~p"/admin/plays")
    assert html =~ "Archive Me"
  end

  # Regression: the archived list offered Edit, the title link and the public
  # page, all of which load through readers that hide archived plays — every
  # one of them raised Ecto.NoResultsError.
  test "an archived play offers no link to a page that cannot load it", %{conn: conn} do
    play = play_fixture(%{"title" => "Archived Play"})
    {:ok, _} = Catalogue.delete_play(play)

    {:ok, view, _html} = live(conn, ~p"/admin/plays?archived=1")

    for href <- [
          ~p"/admin/plays/#{play.id}/edit",
          ~p"/admin/plays/#{play.id}",
          ~p"/plays/#{play.code}"
        ] do
      refute has_element?(view, "#play-#{play.id} a[href='#{href}']"), href
    end

    assert has_element?(view, "#play-#{play.id} button[aria-label='#{t("Restore")}']")
  end
end
