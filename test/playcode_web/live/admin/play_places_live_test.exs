defmodule PlaycodeWeb.Admin.PlayPlacesLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Playcode.Places
  alias Playcode.TestFixtures

  defp setup_play(conn) do
    conn = log_in_user(conn, TestFixtures.user_fixture(role: :researcher))
    play = TestFixtures.play_fixture()
    {conn, play}
  end

  test "the context bar offers Places beside Sources and Content", %{conn: conn} do
    {conn, play} = setup_play(conn)
    {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    assert html =~ ~p"/admin/plays/#{play.id}/sources"
    assert html =~ ~p"/admin/plays/#{play.id}/content"
    assert html =~ t("Places")
  end

  test "an existing place is linked from the picker", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Roma"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    html =
      view
      |> element("form[phx-submit=link]")
      |> render_submit(%{"place_id" => place.id, "role" => "setting"})

    assert html =~ "Roma"
    assert [link] = Places.list_play_places(play.id)
    assert link.role == "setting"
    assert link.origin == "manual"

    # Regression: "play_place" was missing from the log's resource types.
    assert [%{play_id: play_id}] = Playcode.ActivityLog.list_entries(resource_type: "play_place")
    assert play_id == play.id
  end

  test "role and note are editable in place", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Miseno"})
    link = TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view
    |> element("form[phx-submit=update_link][id='link-form-#{link.id}']")
    |> render_submit(%{"play_place" => %{"role" => "mentioned", "note" => "Named, not staged."}})

    assert [updated] = Places.list_play_places(play.id)
    assert updated.role == "mentioned"
    assert updated.note == "Named, not staged."
  end

  test "links reorder", %{conn: conn} do
    {conn, play} = setup_play(conn)
    roma = TestFixtures.place_fixture(%{"name" => "Roma"})
    miseno = TestFixtures.place_fixture(%{"name" => "Miseno"})
    first = TestFixtures.play_place_fixture(play, roma)
    _second = TestFixtures.play_place_fixture(play, miseno)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button[phx-click=move_down][phx-value-id='#{first.id}']") |> render_click()

    assert Places.list_play_places(play.id)
           |> Enum.map(&Places.display_name(&1.place, "es")) == ["Miseno", "Roma"]
  end

  test "unlinking keeps the place in the gazetteer", %{conn: conn} do
    {conn, play} = setup_play(conn)
    place = TestFixtures.place_fixture(%{"name" => "Roma"})
    link = TestFixtures.play_place_fixture(play, place)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button[phx-click=unlink][phx-value-id='#{link.id}']") |> render_click()

    assert Places.list_play_places(play.id) == []
    assert Places.list_places() != []
  end

  describe "the place picker" do
    test "searches by name rather than listing the whole gazetteer", %{conn: conn} do
      {conn, play} = setup_play(conn)
      TestFixtures.place_fixture(%{"name" => "Londres", "slug" => "ppl-londres"})
      TestFixtures.place_fixture(%{"name" => "Zaragoza", "slug" => "ppl-zaragoza"})

      {:ok, view, html} = live(conn, ~p"/admin/plays/#{play.id}/places")

      # Nothing is offered before a term is typed — that is the whole point.
      refute html =~ "Zaragoza"

      html =
        view
        |> element("form[phx-change=search_places]")
        |> render_change(%{"term" => "Lond"})

      assert html =~ "Londres"
      refute html =~ "Zaragoza"
    end

    test "a place already linked to this play is not offered again", %{conn: conn} do
      {conn, play} = setup_play(conn)
      place = TestFixtures.place_fixture(%{"name" => "Atenas", "slug" => "ppl-atenas"})
      TestFixtures.play_place_fixture(play, place)

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

      html =
        view
        |> element("form[phx-change=search_places]")
        |> render_change(%{"term" => "Atenas"})

      assert html =~ t("No places found")
    end

    test "picking a suggestion then submitting links it with the chosen role", %{conn: conn} do
      {conn, play} = setup_play(conn)
      place = TestFixtures.place_fixture(%{"name" => "Venecia", "slug" => "ppl-venecia"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

      view
      |> element("form[phx-change=search_places]")
      |> render_change(%{"term" => "Vene"})

      view |> element("button[phx-value-id='#{place.id}']") |> render_click()

      view
      |> element("form[phx-submit=link]")
      |> render_submit(%{"role" => "mentioned"})

      assert [link] = Places.list_play_places(play.id)
      assert link.place_id == place.id
      assert link.role == "mentioned"
    end

    test "a term matching nothing offers to create it, pre-filled", %{conn: conn} do
      {conn, play} = setup_play(conn)
      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

      html =
        view
        |> element("form[phx-change=search_places]")
        |> render_change(%{"term" => "Helsingør"})

      assert html =~ t("No places found")

      # The create row carries the term, so the form opens with the name already typed
      # and the curator only has to confirm the type and coordinates.
      html = view |> element("button[phx-click=new_from_search]") |> render_click()

      assert html =~ "place-form"
      assert html =~ "Helsingør"
    end
  end

  test "a new place is created and linked in one pass", %{conn: conn} do
    {conn, play} = setup_play(conn)
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

    view |> element("button", t("New place")) |> render_click()

    view
    |> form("#place-form",
      place: %{
        "type" => "city",
        "names" => %{
          "0" => %{"name" => "Alexandría", "language" => "es", "is_preferred" => "true"}
        }
      }
    )
    |> render_submit()

    # PlaceFormComponent notifies the parent via send(self(), {:place_saved, place}),
    # which this LiveView processes in its own handle_info — a second, separate round
    # trip from render_submit's own reply. render/1 re-reads the view after that
    # message has landed. Same mechanism as PlaceListLiveTest's "a place is created…".
    render(view)

    assert [link] = Places.list_play_places(play.id)
    assert Places.display_name(link.place, "es") == "Alexandría"
  end

  # An event names its link by an id from the browser: another play's, one already
  # removed, or not an id at all. None may change anything or crash the page.
  test "a link that is not this play's is neither changed, moved nor removed", %{conn: conn} do
    {conn, play} = setup_play(conn)
    other = TestFixtures.play_fixture()

    theirs =
      TestFixtures.play_place_fixture(other, TestFixtures.place_fixture(), %{"note" => "suya"})

    events = [
      {"update_link", fn id -> %{"link_id" => id, "play_place" => %{"note" => "cambiada"}} end},
      {"move_up", &%{"id" => &1}},
      {"move_down", &%{"id" => &1}},
      {"unlink", &%{"id" => &1}}
    ]

    for {event, params} <- events, id <- [theirs.id, Ecto.UUID.generate(), "not-an-id"] do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/places")

      assert render_click(lv, event, params.(id)) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"
    end

    assert [%{note: "suya"}] = Places.list_play_places(other.id)
  end
end
