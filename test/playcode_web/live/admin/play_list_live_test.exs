defmodule PlaycodeWeb.Admin.PlayListLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.ActivityLog
  alias Playcode.Catalogue

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher))}
  end

  defp restore(view, play),
    do: view |> element("#play-#{play.id} button[aria-label='#{t("Restore")}']") |> render_click()

  defp archive(conn, play) do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    view |> element("button", t("Archive play")) |> render_click()
  end

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

    assert has_element?(view, "th", t("Status"))
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

    archive(conn, play)
    {:ok, view, _html} = live(conn, ~p"/admin/plays")
    refute render(view) =~ "Archive Me"
    assert Catalogue.get_play!(play.id, include_deleted: true).deleted_at

    {:ok, archived, html} = live(conn, ~p"/admin/plays?archived=1")
    assert html =~ "Archive Me"

    restore(archived, play)
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

  test "the heading names what the page holds and how many, archived plays not counted",
       %{conn: conn} do
    play_fixture()
    play_fixture()
    {:ok, _} = Catalogue.delete_play(play_fixture())

    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert has_element?(view, "h1", "#{t("Plays")} · 2")
  end

  test "a row opens its play by the title and carries no other link", %{conn: conn} do
    play = play_fixture(%{"title" => "Open Me"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert has_element?(view, "#play-#{play.id} a[href='/admin/plays/#{play.id}']", "Open Me")
    refute has_element?(view, "#play-#{play.id} a[href='/admin/plays/#{play.id}/edit']")
    refute has_element?(view, "#play-#{play.id} a[href='/plays/#{play.code}']")
    refute has_element?(view, "#play-#{play.id} button[aria-label='#{t("Archive")}']")
  end

  describe "the status filter" do
    setup %{conn: conn} do
      draft = play_fixture(%{"title" => "A Draft Play"})
      done = play_fixture(%{"title" => "A Done Play"})
      {:ok, _} = Catalogue.update_play_from_form(done, %{"is_complete" => "true"})
      {:ok, view, _html} = live(conn, ~p"/admin/plays")
      %{view: view, draft: draft, done: done}
    end

    test "each choice carries its count", %{view: view} do
      assert has_element?(view, "nav[aria-label='#{t("Status")}'] a", "#{t("All")} · 2")
      assert has_element?(view, "nav[aria-label='#{t("Status")}'] a", "#{t("Drafts")} · 1")

      assert has_element?(
               view,
               "nav[aria-label='#{t("Status")}'] a",
               "#{t("Complete plays")} · 1"
             )
    end

    test "choosing one narrows the list and the address keeps it", %{
      view: view,
      draft: draft,
      done: done
    } do
      view |> element("nav[aria-label='#{t("Status")}'] a", t("Drafts")) |> render_click()
      assert_patch(view, ~p"/admin/plays?status=draft")
      assert has_element?(view, "#play-#{draft.id}")
      refute has_element?(view, "#play-#{done.id}")

      view |> element("nav[aria-label='#{t("Status")}'] a", t("Complete plays")) |> render_click()
      assert_patch(view, ~p"/admin/plays?status=complete")
      assert has_element?(view, "#play-#{done.id}")
      refute has_element?(view, "#play-#{draft.id}")
    end

    test "the search keeps the filter, and the filter keeps the search", %{
      conn: conn,
      draft: draft,
      done: done
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/plays?status=draft")
      view |> element("form[phx-change=search]") |> render_change(%{"search" => "Play"})
      assert_patch(view, ~p"/admin/plays?#{[search: "Play", status: "draft"]}")
      assert has_element?(view, "#play-#{draft.id}")
      refute has_element?(view, "#play-#{done.id}")
    end
  end

  describe "pick up where you left off" do
    setup %{conn: conn} do
      user = user_fixture(role: :researcher)
      %{conn: log_in_user(conn, user), user: user}
    end

    defp changed(user, play),
      do:
        {:ok, _} =
          ActivityLog.log(%{
            user_id: user.id,
            play_id: play.id,
            action: "update",
            resource_type: "play",
            resource_id: play.id
          })

    defp recent_titles(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("section[aria-label='#{t("Pick up where you left off")}'] a")
      |> Enum.map(&LazyHTML.text/1)
      |> Enum.map(&String.trim/1)
    end

    test "lists the last five plays the user changed, newest first, each once, archived ones left out",
         %{conn: conn, user: user} do
      plays = for n <- 1..7, do: play_fixture(%{"title" => "Recent #{n}"})
      [first, second | _] = plays

      for play <- plays, do: changed(user, play)
      changed(user, first)
      changed(user_fixture(), second)
      {:ok, _} = Catalogue.delete_play(Enum.at(plays, 6))

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert recent_titles(view) == ["Recent 1", "Recent 6", "Recent 5", "Recent 4", "Recent 3"]
    end

    test "a play saved through its form joins them", %{conn: conn} do
      play = play_fixture(%{"title" => "Edited Here"})
      {:ok, form, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
      form |> form("#play-form", play: %{"title" => "Edited There"}) |> render_submit()

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert recent_titles(view) == ["Edited There"]
    end

    test "nothing is shown to a user who changed nothing", %{conn: conn} do
      play_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      refute has_element?(view, "section[aria-label='#{t("Pick up where you left off")}']")
    end
  end

  describe "the first visit's card" do
    setup do
      %{user: user_fixture(role: :researcher)}
    end

    defp card, do: "section[aria-label='#{t("Getting started")}']"

    test "says how a play gets from here to the site", %{conn: conn, user: user} do
      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/admin/plays")

      assert has_element?(view, card(), t("Find a play in the list, or import one."))
      assert has_element?(view, card(), t("Edit its record and its text."))

      assert has_element?(
               view,
               card(),
               t("Mark it complete, and it reaches the site at the next Generate.")
             )
    end

    test "once closed, it stays closed, on this computer and on another",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/admin/plays")
      view |> element("#{card()} button", t("Got it")) |> render_click()
      refute has_element?(view, card())

      {:ok, view, _html} = live(log_in_user(build_conn(), user), ~p"/admin/plays")
      refute has_element?(view, card())
    end
  end

  test "the sidebar's checkbox is not restored by the browser", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert has_element?(view, "#admin-sidebar[autocomplete=off]")
  end
end
