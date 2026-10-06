defmodule PlaycodeWeb.Admin.PlayContentEditorLiveTest do
  @moduledoc """
  Editing a play's text at /admin/plays/:id/content, checked the way readers get
  it: the play's exported TEI, or its public page. Two controls are JavaScript
  hooks the test cannot run (inline editing and the character picker); for those
  the test pushes the event the hook would push.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    cast =
      ~w(ANA DON)
      |> Enum.map_join(&~s(<castItem><role xml:id="#{&1}">#{&1}</role></castItem>))

    play =
      import_tei!(
        tei(
          front: ~s(<div type="elenco"><castList>#{cast}</castList></div>),
          body: """
          <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
            <div2 type="escena" n="1"><head>ESCENA I</head>
              <stage>Sale el Rey</stage>
              <sp who="#ANA"><speaker>ANA</speaker><lg type="redondilla">
                <l n="1">Primera línea</l><l n="2">Segunda línea</l><l n="3">Tercera línea</l>
              </lg></sp>
            </div2>
          </div1>
          """
        )
      )

    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
  end

  defp open_structure(conn, play) do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", "structure") |> render_click()
    lv
  end

  defp open_scene(conn, play) do
    lv = open_structure(conn, play)
    lv |> element("button", "ESCENA I") |> render_click()
    lv
  end

  # The element card whose text is `content`, as its DOM id.
  defp card(lv, content) do
    [id] =
      Regex.run(~r/phx-value-id="([^"]+)"/, lv |> element("span[title='#{content}']") |> render(),
        capture: :all_but_first
      )

    "#element-#{id}"
  end

  defp lines(play) do
    play
    |> export_tei()
    |> xml_elements("l")
    |> Enum.map(fn {attrs, text} -> {text, String.to_integer(attrs["n"])} end)
  end

  # Regression: archiving a play notifies its topic, and the editor reloaded it through
  # a read that hides archived plays, so it crashed.
  test "an open editor stays up when its play is archived", %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    {:ok, _} = Playcode.Catalogue.delete_play(play)
    # What Playcode.Export.PlayChangeListener relays when the archiving commits.
    Playcode.PlayContent.notify_changed(play.id)

    assert has_element?(lv, "span[title='Segunda línea']")
  end

  test "a verse edited in place is what the public page shows", %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    lv |> element("span[title='Segunda línea']") |> render_click()
    lv |> element("form[id^='inline-edit-']") |> render_submit(%{"value" => "Línea corregida"})

    {:ok, _public, html} = live(conn, ~p"/plays/#{play.code}")
    assert html =~ "Línea corregida"
    refute html =~ "Segunda línea"
  end

  test "a stage direction added to the scene becomes part of the play", %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    lv |> element("button", t("Stage Dir.")) |> render_click()
    lv |> form("#element-form", element: %{"content" => "Entra un criado"}) |> render_submit()

    assert xml_texts(export_tei(play), "stage") == ["Sale el Rey", "Entra un criado"]
  end

  test "deleting a verse renumbers the verses after it", %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Primera línea")} button[aria-label='#{t("Delete")}']")
    |> render_click()

    assert lines(play) == [{"Segunda línea", 1}, {"Tercera línea", 2}]
  end

  test "a verse inserted above another takes its number and pushes the rest down",
       %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
    |> render_click()

    lv |> form("#element-form", element: %{"content" => "Línea nueva"}) |> render_submit()

    assert lines(play) == [
             {"Primera línea", 1},
             {"Segunda línea", 2},
             {"Línea nueva", 3},
             {"Tercera línea", 4}
           ]
  end

  test "a speech is given to the characters chosen in its form", %{conn: conn, play: play} do
    lv = open_scene(conn, play)
    don = Enum.find(Playcode.PlayContent.list_characters(play.id), &(&1.xml_id == "DON"))

    lv |> element("span", "ANA") |> render_click()

    lv
    |> element("#el-char-select")
    |> render_hook("el_add_character", %{"character_id" => don.id})

    lv |> form("#element-form") |> render_submit()

    assert [{%{"who" => who}, _}] = xml_elements(export_tei(play), "sp")
    assert who |> String.split() |> Enum.sort() == ["#ANA", "#DON"]
  end

  describe "the play's structure" do
    test "an act is added, retitled and deleted", %{conn: conn, play: play} do
      lv = open_structure(conn, play)

      lv |> element("button", t("Add Act")) |> render_click()

      lv
      |> form("#division-form",
        division: %{"type" => "acto", "number" => "2", "title" => "ACTO SEGUNDO"}
      )
      |> render_submit()

      assert Enum.map(outline(export_tei(play)), &elem(&1, 1)) == ["ACTO PRIMERO", "ACTO SEGUNDO"]

      [act_two] =
        Regex.run(~r/id="(division-[^"]+)"[^>]*>(?:(?!id="division-).)*ACTO SEGUNDO/s, render(lv),
          capture: :all_but_first
        )

      lv |> element("##{act_two} button[aria-label='#{t("Edit metadata")}']") |> render_click()
      lv |> form("#division-form", division: %{"title" => "ACTO II"}) |> render_submit()
      assert Enum.map(outline(export_tei(play)), &elem(&1, 1)) == ["ACTO PRIMERO", "ACTO II"]

      lv |> element("##{act_two} button[aria-label='#{t("Delete")}']") |> render_click()
      assert Enum.map(outline(export_tei(play)), &elem(&1, 1)) == ["ACTO PRIMERO"]
    end

    test "deleting a scene takes its text with it", %{conn: conn, play: play} do
      lv = open_structure(conn, play)

      [scene] =
        Regex.run(~r/id="(division-[^"]+)"[^>]*>(?:(?!id="division-).)*ESCENA I/s, render(lv),
          capture: :all_but_first
        )

      lv |> element("##{scene} button[aria-label='#{t("Delete")}']") |> render_click()

      xml = export_tei(play)
      assert [{_, "ACTO PRIMERO", []}] = outline(xml)
      assert xml_elements(xml, "l") == []
    end
  end
end
