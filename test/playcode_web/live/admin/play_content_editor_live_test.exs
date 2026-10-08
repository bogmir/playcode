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

  alias Playcode.PlayContent.Division

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

  describe "events naming rows that are not this play's" do
    # Every id in an event comes from the browser: another play's row, one already gone, or
    # not an id at all. None may change either play, crash the page or open a form on it,
    # and each says so. The other play's exported TEI is the evidence it did not change.
    setup do
      other =
        import_tei!(
          tei(
            front: """
            <div type="elenco"><castList>
              <castItem><role xml:id="OTRO">OTRO</role></castItem>
            </castList></div>
            <div type="dedicatoria"><p>Dedicatoria ajena</p></div>
            """,
            body: """
            <div1 type="acto" n="1"><head>ACTO AJENO</head>
              <sp who="#OTRO"><speaker>OTRO</speaker><lg><l n="1">Verso ajeno</l></lg></sp>
            </div1>
            """
          )
        )

      %{other: other}
    end

    test "editing, deleting or opening one changes nothing and says so",
         %{conn: conn, play: play, other: other} do
      before = export_tei(other)
      [note] = Playcode.Catalogue.list_play_editorial_notes(other.id)
      [character] = Playcode.PlayContent.list_characters(other.id)
      act = row(other, &match?(%Division{type: "acto"}, &1))
      verse = row(other, &(&1.type == "verse_line"))

      events = [
        {"edit_editorial_note", note.id},
        {"delete_editorial_note", note.id},
        {"edit_character", character.id},
        {"delete_character", character.id},
        {"edit_division", act.id},
        {"delete_division", act.id},
        {"select_division", act.id},
        {"select_division_auto", act.id},
        {"edit_element", verse.id},
        {"delete_element", verse.id}
      ]

      for {event, theirs} <- events, id <- [theirs, Ecto.UUID.generate(), "not-an-id"] do
        {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
        assert render_click(lv, event, %{"id" => id}) =~ gone(), "#{event} #{id}"
        refute has_element?(lv, "#content-modal"), "#{event} #{id}"
      end

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
      render_click(lv, "inline_edit", %{"id" => verse.id})

      assert render_click(lv, "inline_save", %{"element_id" => verse.id, "value" => "Cambiado"}) =~
               gone()

      search_hit = %{"division-id" => act.id, "parent-id" => "", "id" => verse.id}
      assert render_click(lv, "content_search_go", search_hit) =~ gone()

      assert export_tei(other) == before
    end

    test "a selection holding one acts on this play's rows only",
         %{conn: conn, play: play, other: other} do
      before = export_tei(other)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")

      render_click(lv, "el_toggle_element", %{"id" => row(other, &(&1.type == "verse_line")).id})
      render_click(lv, "el_delete_selected", %{})
      render_click(lv, "cr_toggle_speech", %{"id" => row(other, &(&1.type == "speech")).id})
      render_click(lv, "cr_set_label", %{"speaker_label" => "CAMBIADO"})
      render_click(lv, "cr_clear_label", %{})
      render_click(lv, "cr_assign_characters", %{})

      assert export_tei(other) == before
    end

    test "a speech here is never given another play's character",
         %{conn: conn, play: play, other: other} do
      [theirs] = Playcode.PlayContent.list_characters(other.id)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")

      render_click(lv, "cr_toggle_speech", %{"id" => row(play, &(&1.type == "speech")).id})
      assert render_click(lv, "cr_add_character", %{"character_id" => theirs.id}) =~ gone()
      render_click(lv, "cr_assign_characters", %{})
      assert speakers(play) == ["#ANA"]

      lv = open_scene(conn, play)
      lv |> element("span", "ANA") |> render_click()

      assert lv
             |> element("#el-char-select")
             |> render_hook("el_add_character", %{"character_id" => theirs.id}) =~ gone()

      # A hand-made save naming the character anyway.
      lv |> form("#element-form") |> render_submit(%{"character_ids" => [theirs.id]})
      assert speakers(play) == [nil]
    end

    test "a new row is never hung under one, nor placed at no position",
         %{conn: conn, play: play, other: other} do
      lv = open_scene(conn, play)

      events = [
        {"new_division", %{"parent-id" => row(other, &match?(%Division{type: "acto"}, &1)).id}},
        {"new_element",
         %{"parent-id" => row(other, &(&1.type == "speech")).id, "type" => "verse_line"}},
        {"new_element_before",
         %{"parent-id" => "", "type" => "stage_direction", "position" => "primero"}}
      ]

      for {event, params} <- events do
        assert render_click(lv, event, params) =~ gone(), event
        refute has_element?(lv, "#content-modal"), event
      end
    end
  end

  describe "notes when their text is edited" do
    setup %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO<note n="2" type="editor"><p>Glosa del título.</p></note></head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Buscad por todas partes<note n="1" type="traductor"><p>Glosa.</p></note> ya</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
    end

    defp note_after(play, tag) do
      for %{in: ^tag, after: text} <- xml_notes(export_tei(play)), do: text
    end

    test "a line's note follows its word through edits, and stays in the line when the word goes",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      edit = fn from, to ->
        lv |> element("span[title='#{from}']") |> render_click()
        lv |> element("form[id^='inline-edit-']") |> render_submit(%{"value" => to})
      end

      edit.("Buscad por todas partes ya", "Ya buscad por todas partes ya")
      assert note_after(play, "l") == ["Ya buscad por todas partes"]

      edit.("Ya buscad por todas partes ya", "Ya buscad por todas ya")
      assert note_after(play, "l") == ["Ya buscad por todas"]
      assert reading_texts(export_tei(play), "l") == ["Ya buscad por todas ya"]
    end

    test "a heading's note follows its word when the heading is renamed",
         %{conn: conn, play: play} do
      lv = open_structure(conn, play)

      [act] =
        Regex.run(~r/id="(division-[^"]+)"[^>]*>(?:(?!id="division-).)*ACTO PRIMERO/s, render(lv),
          capture: :all_but_first
        )

      lv |> element("##{act} button[aria-label='#{t("Edit metadata")}']") |> render_click()
      lv |> form("#division-form", division: %{"title" => "EL ACTO PRIMERO"}) |> render_submit()

      assert note_after(play, "head") == ["EL ACTO PRIMERO"]
    end
  end

  defp gone, do: t("That item no longer exists. The list has been refreshed.")

  defp speakers(play) do
    play |> export_tei() |> xml_elements("sp") |> Enum.map(fn {attrs, _} -> attrs["who"] end)
  end

  defp loaded(item, key) do
    case Map.get(item, key) do
      list when is_list(list) -> list
      _not_loaded -> []
    end
  end

  # The first division or element of `play`, depth first, for which `fun` is true.
  defp row(play, fun) do
    walk = fn walk, items ->
      Enum.flat_map(items, fn item ->
        nested = Enum.flat_map([:children, :loaded_elements], &List.wrap(loaded(item, &1)))
        [item | walk.(walk, nested)]
      end)
    end

    play.id
    |> Playcode.PlayContent.load_play_content()
    |> then(&walk.(walk, &1))
    |> Enum.find(fun)
  end
end
