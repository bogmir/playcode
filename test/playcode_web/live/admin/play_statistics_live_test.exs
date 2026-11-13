defmodule PlaycodeWeb.Admin.PlayStatisticsLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers
  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers, only: [rows: 2, texts: 2]

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher))}
  end

  defp play_with_forms do
    import_tei!(
      tei(
        body: """
        <div1 type="acto" n="1"><head>Acto I</head>
          <div2 type="escena" n="1"><head>Escena 1</head>
            <sp who="#ana"><speaker>ANA</speaker>
              <lg type="redondilla"><l n="1">uno dos</l><l n="2">tres</l></lg></sp>
            <sp who="#bea"><speaker>BEA</speaker>
              <lg type="romance"><l n="3">cuatro</l></lg></sp>
          </div2>
        </div1>
        """
      )
    )
  end

  test "the section draws the site's four parts, in one language", %{conn: conn} do
    play = play_with_forms()
    {:ok, lv, html} = live(conn, ~p"/admin/plays/#{play.id}/statistics")

    assert has_element?(lv, "#tiles")
    assert has_element?(lv, "#synopsis", t("Metrical synopsis"))
    assert has_element?(lv, "#synopsis details table")
    assert has_element?(lv, "#characters th[scope=row]", "ANA")
    assert has_element?(lv, "#presence")
    assert has_element?(lv, "[aria-current=page]", t("Statistics"))
    refute html =~ "<x-en"
  end

  test "a mixed play shows its scenes, shared verses, asides and prose, act by act and scene by scene",
       %{conn: conn} do
    play = import_tei!(tei(body: mixed_play()))
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/statistics")
    page = LazyHTML.from_fragment(render(lv))

    tiles = Map.new(Enum.zip(texts(page, "#tiles dt"), texts(page, "#tiles dd")))

    assert Enum.map(["scenes", "shared verses", "asides", "prose passages"], &tiles[t(&1)]) ==
             ["2", "1", "1", "1"]

    assert has_element?(lv, "#divisions [role=region][aria-label]")

    assert texts(page, "#divisions thead th") ==
             [t("Act or scene"), t("Verses"), t("Speeches"), t("Speaking characters")] ++
               [t("Prose passages")]

    assert rows(page, "#divisions tbody tr") == [
             ["Acto I", "2", "3", "2", "1"],
             ["Escena 1", "2", "2", "2", "0"],
             ["Escena 2", "0", "1", "1", "1"],
             ["Acto II", "1", "1", "1", "0"]
           ]
  end

  test "a verse play has no prose column, and a play of one division no table", %{conn: conn} do
    play = play_with_forms()
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/statistics")
    page = LazyHTML.from_fragment(render(lv))

    refute t("Prose passages") in texts(page, "#divisions thead th")

    assert rows(page, "#divisions tbody tr") == [
             ["Acto I", "3", "2", "2"],
             ["Escena 1", "3", "2", "2"]
           ]

    play =
      import_tei!(
        tei(
          body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>)
        )
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/statistics")
    refute has_element?(lv, "#divisions")
  end

  test "Recalcular recomputes and the page keeps the date", %{conn: conn} do
    play = play_with_forms()
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/statistics")

    assert has_element?(lv, "#computed-at")

    lv |> element("button", t("Recompute")) |> render_click()
    assert render(lv) =~ t("Statistics recomputed.")
  end

  test "a play with no verse form tagged has no synopsis", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <sp who="#ana"><speaker>ANA</speaker><l n="1">uno</l></sp></div1>
          """
        )
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/statistics")

    assert has_element?(lv, "#tiles")
    refute has_element?(lv, "#synopsis")
  end

  test "a play with no scenes has a matrix column per metrical passage", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <sp who="#ana"><speaker>ANA</speaker>
              <lg type="redondilla"><l n="1">uno</l></lg>
              <lg type="romance"><l n="2">dos</l></lg></sp></div1>
          """
        )
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/statistics")

    assert has_element?(lv, "#presence th[scope=col]", "Redondilla")
    assert has_element?(lv, "#presence th[scope=col]", "Romance")
  end

  test "the overview's card links to the section and the full panel is gone", %{conn: conn} do
    play = play_with_forms()
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, ~s(a[href="/admin/plays/#{play.id}/statistics"]), t("See all"))
    refute has_element?(lv, "#synopsis")
    refute has_element?(lv, "button", t("Recompute"))
  end
end
