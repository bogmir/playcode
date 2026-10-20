defmodule PlaycodeWeb.Admin.PlayPerformancesLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.ActivityLog
  alias Playcode.Performances

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp add(lv, attrs) do
    lv |> element("button", t("Add performance")) |> render_click()
    lv |> form("#performance-form", performance: attrs) |> render_submit()
  end

  defp button(lv, label, performance_label),
    do:
      element(
        lv,
        "button[aria-label='#{t(label <> " %{performance}", performance: performance_label)}']"
      )

  test "a researcher adds a performance and sees it as readers will", %{conn: conn, play: play} do
    {:ok, lv, html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    assert html =~ t("No performances yet.")

    add(lv, %{
      "date_text" => "1610",
      "venue" => "Globe",
      "venue_type" => "public_theatre",
      "company_name" => "The King’s Men"
    })

    assert [performance] = Performances.list_for_play(play.id)
    assert %{origin: "manual", year_from: 1610, company: %{name: "The King’s Men"}} = performance
    assert [%{name: "The King’s Men"}] = Performances.list_companies()

    html = lv |> element("#performance-#{performance.id}") |> render()
    assert html =~ "1610"
    assert html =~ "Globe · The King’s Men · teatro público"
  end

  test "a company is picked from those that exist", %{conn: conn, play: play} do
    {:ok, company} = Performances.find_or_create_company("The King’s Men")
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    lv |> element("button", t("Add performance")) |> render_click()
    assert has_element?(lv, "datalist option[value='The King’s Men']")

    lv
    |> form("#performance-form",
      performance: %{"date_text" => "1610", "company_name" => "the king’s men"}
    )
    |> render_submit()

    assert [%{company_id: company_id}] = Performances.list_for_play(play.id)
    assert company_id == company.id
    assert [%{name: "The King’s Men"}] = Performances.list_companies()
  end

  test "the place is found by name, and a state chosen", %{conn: conn, play: play} do
    place_fixture(%{"name" => "Londres"})
    place_fixture(%{"name" => "Zaragoza"})
    england = place_fixture(%{"name" => "Inglaterra", "type" => "country"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    lv |> element("button", t("Add performance")) |> render_click()
    refute render(lv) =~ "Zaragoza"

    html = lv |> element("#place-search") |> render_change(%{"term" => "Lond"})
    assert html =~ "Londres"
    refute html =~ "Zaragoza"

    lv |> element("button", "Londres") |> render_click()

    lv
    |> form("#performance-form",
      performance: %{"date_text" => "1610", "historical_state_id" => england.id}
    )
    |> render_submit()

    assert [%{id: id, place: %{id: place_id}, historical_state_id: state_id}] =
             Performances.list_for_play(play.id)

    assert state_id == england.id
    assert place_id != nil
    assert lv |> element("#performance-#{id}") |> render() =~ "Londres, Inglaterra"
  end

  test "a place can be unpicked, and its state goes with it", %{conn: conn, play: play} do
    england = place_fixture(%{"name" => "Inglaterra", "type" => "country"})

    performance =
      performance_fixture(play, %{
        "place_id" => place_fixture(%{"name" => "Oxford"}).id,
        "historical_state_id" => england.id
      })

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> button("Edit", "1610, Oxford, Inglaterra") |> render_click()

    lv |> element("button[title='#{t("Clear")}']") |> render_click()
    lv |> form("#performance-form") |> render_submit()

    assert %{place_id: nil, historical_state_id: nil} =
             Performances.get_performance(play.id, performance.id)
  end

  test "a performance is edited and deleted, and each is logged", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    add(lv, %{"date_text" => "1610", "venue" => "Globe"})
    [performance] = Performances.list_for_play(play.id)

    lv |> button("Edit", "1610, Globe") |> render_click()
    lv |> form("#performance-form", performance: %{"venue" => "Blackfriars"}) |> render_submit()

    assert %{venue: "Blackfriars", origin: "manual"} =
             Performances.get_performance(play.id, performance.id)

    lv |> button("Delete", "1610, Blackfriars") |> render_click()
    assert Performances.list_for_play(play.id) == []

    assert ~w(create delete update) ==
             [resource_type: "play_performance"]
             |> ActivityLog.list_entries()
             |> Enum.map(& &1.action)
             |> Enum.sort()
  end

  test "a company changed or cleared here frees the old one", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    add(lv, %{"date_text" => "1610", "company_name" => "The King’s Men"})
    [performance] = Performances.list_for_play(play.id)

    lv |> button("Edit", "1610, The King’s Men") |> render_click()

    lv
    |> form("#performance-form", performance: %{"company_name" => "Lady Elizabeth’s"})
    |> render_submit()

    assert [%{name: "Lady Elizabeth’s"}] = Performances.list_companies()

    lv |> button("Edit", "1610, Lady Elizabeth’s") |> render_click()
    lv |> form("#performance-form", performance: %{"company_name" => ""}) |> render_submit()

    assert %{company: nil} = Performances.get_performance(play.id, performance.id)
    assert Performances.list_companies() == []
  end

  # The years a date gives are filled in when the form is saved. If the form echoed them
  # while the date is typed, the browser would send them back as the curator's own, and a
  # corrected date would leave them behind.
  test "the years follow the date as it was saved, however it was typed", %{
    conn: conn,
    play: play
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> element("button", t("Add performance")) |> render_click()
    lv |> form("#performance-form", performance: %{"date_text" => "1597-9"}) |> render_change()
    lv |> form("#performance-form", performance: %{"date_text" => "1600"}) |> render_submit()
    assert [%{id: id, year_from: 1600, year_to: 1600}] = Performances.list_for_play(play.id)

    lv |> button("Edit", "1600") |> render_click()
    lv |> form("#performance-form", performance: %{"date_text" => "1615"}) |> render_change()
    lv |> form("#performance-form", performance: %{"date_text" => "1620"}) |> render_submit()

    assert %{year_from: 1620, year_to: 1620} = Performances.get_performance(play.id, id)
  end

  test "the form says what is missing", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> element("button", t("Add performance")) |> render_click()

    html = lv |> form("#performance-form", performance: %{"date_text" => ""}) |> render_submit()

    assert html =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "needs a date, a venue, a company or a note"
             )

    assert Performances.list_for_play(play.id) == []
  end

  # Review focus 3: the switch is one per play, and a refused save writes nothing, a new
  # company among it.
  test "a second cast-list switch is refused with a message and leaves no company behind",
       %{conn: conn, play: play} do
    performance_fixture(play, %{"cast_from_cast_list" => "true"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    add(lv, %{
      "date_text" => "1611",
      "cast_from_cast_list" => "true",
      "company_name" => "Nueva Compañía"
    })

    assert render(lv) =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "is already set on another performance of this play"
             )

    assert [_one] = Performances.list_for_play(play.id)
    assert Performances.list_companies() == []

    # Corrected, it saves: the company then, and the years of the date it now has.
    lv
    |> form("#performance-form",
      performance: %{"date_text" => "1612", "cast_from_cast_list" => "false"}
    )
    |> render_submit()

    assert [_, %{year_from: 1612, company: %{name: "Nueva Compañía"}}] =
             Performances.list_for_play(play.id)
  end

  # The form's own fields only: a play_id sent with it would move the performance to
  # another play, an origin mark it for an import to replace.
  test "a saved form cannot move a performance to another play or change its origin",
       %{conn: conn, play: play} do
    other = play_fixture()
    performance = performance_fixture(play)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    lv |> button("Edit", "1610") |> render_click()

    lv
    |> form("#performance-form", performance: %{"venue" => "Globe"})
    |> render_submit(%{"performance" => %{"play_id" => other.id, "origin" => "filemaker"}})

    assert %{venue: "Globe", origin: "manual"} =
             Performances.get_performance(play.id, performance.id)

    assert Performances.list_for_play(other.id) == []
  end

  test "a performance that is gone says so", %{conn: conn, play: play} do
    theirs = performance_fixture(play_fixture())

    for event <- ~w(edit delete), id <- [theirs.id, Ecto.UUID.generate(), "not-a-uuid"] do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

      assert render_click(lv, event, %{"id" => id}) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"

      refute has_element?(lv, "#performance-form")
    end

    assert [_theirs] = Performances.list_for_play(theirs.play_id)
  end

  test "a state that is gone is refused, not saved", %{conn: conn, play: play} do
    place_fixture(%{"name" => "Londres"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> element("button", t("Add performance")) |> render_click()
    lv |> element("#place-search") |> render_change(%{"term" => "Lond"})
    lv |> element("button", "Londres") |> render_click()

    html =
      lv
      |> form("#performance-form", performance: %{"date_text" => "1610"})
      |> render_submit(%{"performance" => %{"historical_state_id" => Ecto.UUID.generate()}})

    assert html =~ t("That item no longer exists. The list has been refreshed.")
    assert Performances.list_for_play(play.id) == []
  end
end
