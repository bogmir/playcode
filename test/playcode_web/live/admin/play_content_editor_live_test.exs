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
      [paratext] = Playcode.Catalogue.list_paratexts(other.id)
      [character] = Playcode.PlayContent.list_characters(other.id)
      act = row(other, &match?(%Division{type: "acto"}, &1))
      verse = row(other, &(&1.type == "verse_line"))

      events = [
        {"edit_paratext", paratext.id},
        {"delete_paratext", paratext.id},
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

    # Review focus 3: the offsets are carried for every play_notes row; this pins it.
    test "a line's variant follows its word through an edit, as a note does", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Buscad<app n="1"><rdg wit="#B">Mirad</rdg></app> por todas partes</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      lv = open_scene(conn, play)
      lv |> element("span[title='Buscad por todas partes']") |> render_click()

      lv
      |> element("form[id^='inline-edit-']")
      |> render_submit(%{"value" => "Ya buscad por todas partes"})

      assert [%{after: "Ya buscad"}] = xml_apps(export_tei(play))
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

  describe "inline stage directions" do
    defp refusal,
      do:
        Gettext.dgettext(
          PlaycodeWeb.Gettext,
          "errors",
          "has a stage marker that is not well formed"
        )

    defp span(lv, text), do: element(lv, "span[title*='#{text}']")

    defp edit(lv, from, to) do
      lv |> span(from) |> render_click()
      lv |> element("form[id^='inline-edit-']") |> render_submit(%{"value" => to})
    end

    test "the verse form says how to mark one", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
      |> render_click()

      assert has_element?(
               lv,
               "#element-form",
               t(~s|Stage direction in the text: <stage type="delivery">…</stage>|)
             )

      assert has_element?(lv, "#element-form", t("Words spoken aside: <aside>…</aside>"))
    end

    test "one typed into a line is a <stage> in the exported line", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      edit(lv, "Segunda línea", ~s|<stage type="exit">(Vase)</stage> Segunda línea|)

      assert [%{in: "l", type: "exit", text: "(Vase)", after: "Segunda línea"}] =
               play |> export_tei() |> xml_inline_stages()
    end

    test "two typed touching stay two", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      edit(lv, "Segunda línea", "<stage>(a)</stage><stage>(b)</stage> Segunda línea")

      assert [%{text: "(a)"}, %{text: "(b)"}] = play |> export_tei() |> xml_inline_stages()
    end

    test "a marker that is not closed is refused in place, and the line is unchanged",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      html = edit(lv, "Segunda línea", "<stage>sin cerrar")

      # The generic refusal, a colon, then the reason: its full stop does not stay in front
      # of a lower-case clause ("No se pudo guardar el elemento. tiene una marca…").
      assert html =~
               String.trim_trailing(t("Could not save element."), ".") <> ": " <> refusal()

      assert {"Segunda línea", 2} in lines(play)
    end

    test "a marker that is not closed is refused in the edit form, and the line is unchanged",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      html =
        lv
        |> form("#element-form", element: %{"content" => "<stage>sin cerrar"})
        |> render_submit()

      assert html =~ refusal()
      assert {"Segunda línea", 2} in lines(play)
    end

    test "a refused marker in a new line renumbers nothing", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
      |> render_click()

      html =
        lv
        |> form("#element-form", element: %{"content" => "<stage>sin cerrar"})
        |> render_submit()

      assert html =~ refusal()

      assert lines(play) == [
               {"Primera línea", 1},
               {"Segunda línea", 2},
               {"Tercera línea", 3}
             ]
    end
  end

  describe "line numbers in the text" do
    defp number_refusal,
      do:
        Gettext.dgettext(
          PlaycodeWeb.Gettext,
          "errors",
          "has a line number marker that is not well formed"
        )

    # A break is typed with Enter; a bare <lb/> would print as literal text.
    test "a bare <lb/> or a malformed number is refused, and the line is unchanged",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      assert edit(lv, "Segunda línea", "Segunda <lb/>línea") =~ number_refusal()

      # A refusal leaves the quick edit open, its field still in place.
      assert lv
             |> element("form[id^='inline-edit-']")
             |> render_submit(%{"value" => ~s(Segunda <lb n="1 2"/>línea)}) =~ number_refusal()

      assert {"Segunda línea", 2} in lines(play)
    end

    defp play_with_a_song do
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
            <div2 type="escena" n="1"><head>ESCENA I</head>
              <sp><speaker>ANA</speaker><p>Yo amé en mis primeros años, <lb/>dulce cosa lo juzgué.</p></sp>
            </div2>
          </div1>
          """
        )
      )
    end

    # A browser strips the newlines from an <input type="text">: saving the quick edit
    # would glue "años," to "dulce".
    test "a paragraph with a break opens in the form, never the one-line quick edit",
         %{conn: conn} do
      play = play_with_a_song()
      lv = open_scene(conn, play)

      lv |> span("dulce cosa") |> render_click()

      assert has_element?(lv, "#element-form textarea")
      refute has_element?(lv, "form[id^='inline-edit-']")
    end

    test "a break typed in the form is kept, and written back as <lb/>", %{conn: conn} do
      play = play_with_a_song()
      lv = open_scene(conn, play)

      lv |> span("dulce cosa") |> render_click()

      lv
      |> form("#element-form", element: %{"content" => "Yo amé,\ndulce cosa,\nlo juzgué."})
      |> render_submit()

      assert play |> export_tei() |> xml_lines("p") ==
               [{%{}, "Yo amé, | dulce cosa, | lo juzgué."}]
    end

    test "the prose form says how to type a printed line's number", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      # A scene-level card's insert menu: the toolbar and each such card offer "Prose".
      lv |> element("#{card(lv, "Sale el Rey")} button", t("Prose")) |> render_click()

      assert has_element?(
               lv,
               "#element-form",
               t(~s|Number of a printed line in the text: <lb n="1320"/>|)
             )
    end
  end

  describe "a stage direction's kind and a verse's identifier" do
    setup %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <stage type="exit">Sale don Pedro solo.</stage>
                <stage type="trick">Vuela.</stage>
                <sp><speaker>ANA</speaker><lg><l n="1" xml:id="es-0001">Primera línea</l></lg></sp>
              </div2>
            </div1>
            """
          )
        )

      %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
    end

    defp edit(lv, content) do
      lv |> element("#{card(lv, content)} button[aria-label='#{t("Edit")}']") |> render_click()
      lv
    end

    # "Sale" is an entrance in a Spanish stage direction: AL0731's file calls it an exit.
    test "is chosen in the stage direction's form", %{conn: conn, play: play} do
      conn
      |> open_scene(play)
      |> edit("Sale don Pedro solo.")
      |> form("#element-form", element: %{"stage_type" => "entrance"})
      |> render_submit()

      assert {%{"type" => "entrance"}, "Sale don Pedro solo."} in xml_elements(
               export_tei(play),
               "stage"
             )
    end

    test "a kind the list does not have survives an edit", %{conn: conn, play: play} do
      conn
      |> open_scene(play)
      |> edit("Vuela.")
      |> form("#element-form", element: %{"content" => "Vuela alto."})
      |> render_submit()

      assert {%{"type" => "trick"}, "Vuela alto."} in xml_elements(export_tei(play), "stage")
    end

    test "a verse's identifier is shown and kept, not edited", %{conn: conn, play: play} do
      lv = conn |> open_scene(play) |> edit("Primera línea")

      assert lv |> element("#element-form") |> render() =~ "es-0001"
      refute has_element?(lv, "#element-form [name='element[line_id]']")

      lv |> form("#element-form", element: %{"content" => "Línea primera"}) |> render_submit()

      assert [{%{"xml:id" => "es-0001"}, "Línea primera"}] = xml_elements(export_tei(play), "l")
    end
  end

  # The glossary's word (CONTEXT.md): a dedication, an epilogue or an editor's
  # introduction is a paratext, not an "editorial note".
  test "the paratexts tab adds a paratext", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form", paratext: %{"kind" => "dedicatoria", "content" => "Al duque."})
    |> render_submit()

    assert [%{kind: "dedicatoria", content: "Al duque."}] =
             Playcode.Catalogue.list_paratexts(play.id)
  end

  # As a stage direction's: the select offers the known kinds and keeps a file's other word.
  test "a paratext keeps a kind the admin does not offer", %{conn: conn} do
    play = import_tei!(tei(front: ~s(<div type="carta_al_lector"><p>Lector.</p></div>)))
    [paratext] = Playcode.Catalogue.list_paratexts(play.id)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("#paratext-#{paratext.id} button", t("Edit")) |> render_click()

    lv |> form("#paratext-form", paratext: %{"heading" => "Al lector"}) |> render_submit()

    assert [{%{"type" => "carta_al_lector"}, _}] =
             xml_elements(export_tei(play), "div", within: "front")
  end

  # Three groups, so the kinds can be found: what the early edition printed, what this
  # edition wrote, and the scene of the action.
  test "the kind select is grouped", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    assert has_element?(lv, "#paratext-form label", t("Kind"))

    assert has_element?(
             lv,
             ~s(optgroup[label="#{t("Editorial texts")}"] option[value="apendice"])
           )

    assert has_element?(
             lv,
             ~s(optgroup[label="#{t("Printed with the play")}"] option[value="licencia"]),
             t("Licence to print")
           )

    refute has_element?(lv, ~s(#paratext-form option[value="nota"]))
  end

  # A browser sends a textarea's line breaks as \r\n: kept so, a blank line was no
  # paragraph break and the file got one <p> with two <lb/>s. Squeezed as a witness's
  # fields are, it is what a file gives back.
  test "a paratext typed with a browser's line breaks keeps its paragraphs",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form",
      paratext: %{"kind" => "dedicatoria", "content" => "A \r\nB\r\n\r\n\r\nC "}
    )
    |> render_submit()

    xml = export_tei(play)
    assert xml_texts(xml, "p", within: "front") == ["A B", "C"]
    assert xml =~ ~r{<p>A<lb/>B</p>}
  end

  # A line break typed inside italics: TEI allows <lb/> in <emph>; split before the
  # italics were read, the file got the markers as text, "&lt;&lt;una".
  test "a line break inside italics is written inside the <emph>", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form",
      paratext: %{"kind" => "dedicatoria", "content" => "C <<una\ndos>> fin"}
    )
    |> render_submit()

    xml = export_tei(play)
    refute xml =~ "&lt;&lt;"
    assert xml =~ ~r{<emph>una\s*<lb/>\s*dos</emph>}
  end

  # Review focus 3: the scene of the action is written as the front's <set>, never in <back>.
  test "a paratext is placed after the text, but not the scene of the action",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form",
      paratext: %{"kind" => "lugar_accion", "content" => "A wood.", "back" => "true"}
    )
    |> render_submit()

    assert lv |> element("#paratext-form") |> render() =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "the scene of the action stands with the cast list"
             )

    lv
    |> form("#paratext-form",
      paratext: %{"kind" => "colofon", "content" => "Loado sea.", "back" => "true"}
    )
    |> render_submit()

    assert xml_texts(export_tei(play), "p", within: "back") == ["Loado sea."]
    assert has_element?(lv, "#paratext-list", t("After the text"))
  end

  describe "the paratexts' order" do
    setup do
      play =
        import_tei!(
          tei(
            front:
              ~s(<div type="dedicatoria"><p>A.</p></div><div type="argumento"><p>B.</p></div>)
          )
        )

      other =
        import_tei!(
          tei(
            front:
              ~s(<div type="dedicatoria"><p>X.</p></div><div type="argumento"><p>Y.</p></div>)
          )
        )

      %{play: play, other: other}
    end

    defp contents(play),
      do: play.id |> Playcode.Catalogue.list_paratexts() |> Enum.map(& &1.content)

    # As the cast list: a file's order may be wrong, and only an editor can fix it.
    test "is dragged", %{conn: conn, play: play} do
      [a, b] = Playcode.Catalogue.list_paratexts(play.id)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
      lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()

      lv
      |> element("#paratext-list")
      |> render_hook("reorder_paratexts", %{"ids" => [b.id, a.id]})

      assert contents(play) == ["B.", "A."]
    end

    # The ids came from the browser: another play's rows, or a malformed id, move nothing.
    test "moves none of another play's", %{conn: conn, play: play, other: other} do
      [a, b] = Playcode.Catalogue.list_paratexts(play.id)
      [x, y] = Playcode.Catalogue.list_paratexts(other.id)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
      lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()

      lv
      |> element("#paratext-list")
      |> render_hook("reorder_paratexts", %{"ids" => [b.id, a.id, y.id, x.id, "not-an-id"]})

      assert contents(play) == ["B.", "A."]
      assert contents(other) == ["X.", "Y."]
    end
  end

  # A new one took the count as its position, which falls among the file's: positions are
  # shared with the cast list division, and a div that gives nothing still takes one.
  test "a new paratext goes last", %{conn: conn} do
    play =
      import_tei!(
        tei(
          front: """
          <div type="dedicatoria"><p>A.</p></div>
          <div type="elenco"><castList><castItem><role xml:id="X">X</role></castItem></castList></div>
          <div type="prologo"></div>
          <div type="argumento"><p>B.</p></div>
          """
        )
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form", paratext: %{"kind" => "licencia", "content" => "C."})
    |> render_submit()

    assert play.id |> Playcode.Catalogue.list_paratexts() |> Enum.map(& &1.content) ==
             ["A.", "B.", "C."]
  end

  test "the scene of the action is entered in the paratexts tab", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    lv
    |> form("#paratext-form",
      paratext: %{
        "kind" => "lugar_accion",
        "heading" => "SCENE:",
        "content" => "An English wood."
      }
    )
    |> render_submit()

    assert render(lv) =~ t("Scene of the action")
    xml = export_tei(play)
    assert xml_texts(xml, "head", within: "set") == ["SCENE:"]
    assert xml_texts(xml, "p", within: "set") == ["An English wood."]
  end

  test "a character's actor in the original cast is edited and listed", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Cast list")) |> render_click()
    ana = Enum.find(Playcode.PlayContent.list_characters(play.id), &(&1.xml_id == "ANA"))

    lv |> element("#character-#{ana.id} button[aria-label='#{t("Edit")}']") |> render_click()

    lv
    |> form("#character-form", character: %{"actor" => " Mrs.  Bracegirdle "})
    |> render_submit()

    assert lv |> element("#character-#{ana.id}") |> render() =~ "Mrs. Bracegirdle"
    assert xml_texts(export_tei(play), "actor") == ["Mrs. Bracegirdle"]
  end

  describe "a stage direction's type, changed in a line that has a note" do
    setup %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Dijo <stage>(bajo)</stage> que sí<note n="1" type="editor"><p>Glosa.</p></note> ya</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play}
    end

    test "leaves the note where it was", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv |> element("span[title*='que sí ya']") |> render_click()

      lv
      |> element("form[id^='inline-edit-']")
      |> render_submit(%{"value" => ~s|Dijo <stage type="exit">(bajo)</stage> que sí ya|})

      assert [%{n: "1", after: "Dijo (bajo) que sí"}] = xml_notes(export_tei(play))
      assert [%{type: "exit"}] = xml_inline_stages(export_tei(play))
    end
  end

  describe "the note editor" do
    defp notes_section, do: "section[aria-label='#{t("Notes")}']"

    test "a note is added to a verse, changed and deleted, each logged",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add note")) |> render_click()

      lv
      |> form("#note-form",
        note: %{
          "type" => "traductor",
          "offset" => "7",
          "term" => "Segunda",
          "body" => "Primera glosa.\n\nSegundo párrafo."
        }
      )
      |> render_submit()

      assert [
               %{
                 in: "l",
                 after: "Segunda",
                 type: "traductor",
                 term: "Segunda",
                 paragraphs: ["Primera glosa.", "Segundo párrafo."]
               }
             ] = xml_notes(export_tei(play))

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()

      lv
      |> form("#note-form", note: %{"offset" => "13", "body" => "Glosa corregida."})
      |> render_submit()

      assert [%{after: "Segunda línea", paragraphs: ["Glosa corregida."]}] =
               xml_notes(export_tei(play))

      lv |> element("#{notes_section()} button", t("Delete")) |> render_click()
      assert xml_notes(export_tei(play)) == []

      actions =
        [resource_type: "note", play_id: play.id]
        |> Playcode.ActivityLog.list_entries()
        |> Enum.map(& &1.action)
        |> Enum.sort()

      assert actions == ["create", "delete", "update"]
    end

    test "a variant is added to a verse with its readings, changed and deleted",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add variant")) |> render_click()

      # A variant has no type to choose: it stays a variant.
      refute has_element?(lv, "#note-form label", t("Type"))

      # "Add reading": a second row.
      lv |> form("#note-form") |> render_change(%{note: %{"readings_order" => ["0", "new"]}})

      lv
      |> form("#note-form",
        note: %{
          "offset" => "7",
          "readings" => %{
            "0" => %{
              "lemma" => "true",
              "wit" => "#H",
              "text" => "Segunda",
              "note" => "Corrección."
            },
            "1" => %{"wit" => "#P3", "text" => "Primera"}
          }
        }
      )
      |> render_submit()

      assert [
               %{
                 in: "l",
                 after: "Segunda",
                 readings: [
                   {"lem", "#H", "Segunda", "Corrección."},
                   {"rdg", "#P3", "Primera", nil}
                 ],
                 note: nil
               }
             ] = xml_apps(export_tei(play))

      assert xml_notes(export_tei(play)) == []

      # Review focus 2: with no note of its own, its row in the list shows its readings.
      assert render(lv) =~ "#H Segunda · #P3 Primera"

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form") |> render_change(%{note: %{"readings_delete" => ["1"]}})
      lv |> form("#note-form", note: %{"body" => "Comentario."}) |> render_submit()

      assert [%{readings: [{"lem", "#H", "Segunda", "Corrección."}], note: "Comentario."}] =
               xml_apps(export_tei(play))

      lv |> element("#{notes_section()} button", t("Delete")) |> render_click()
      assert xml_apps(export_tei(play)) == []
    end

    # The Notes tab links a note's line or heading here; its modal opens on arrival.
    test "?division= opens a heading's modal, and a type the select does not list survives an edit",
         %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO<note n="1" type="latinismo"><p>Glosa.</p></note></head>
              <sp><speaker>ANA</speaker><l n="1">Una línea</l></sp>
            </div1>
            """
          )
        )

      [act] = Playcode.PlayContent.list_top_divisions(play.id)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content?division=#{act.id}")

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Glosa corregida."}) |> render_submit()

      assert [%{type: "latinismo", paragraphs: ["Glosa corregida."]}] =
               xml_notes(export_tei(play))

      # Another play's id, or none of the play's rows, opens nothing.
      {:ok, lv, _html} =
        live(conn, ~p"/admin/plays/#{play.id}/content?element=#{Ecto.UUID.generate()}")

      refute has_element?(lv, "#content-modal")
    end

    test "changing only an imported note's text leaves it where it was", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">con dos caras que tiene,<note n="5" type="editor"><p>Glosa.</p></note> ya</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "con dos caras que tiene, ya")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Glosa nueva."}) |> render_submit()

      assert [%{after: "con dos caras que tiene,", paragraphs: ["Glosa nueva."]}] =
               xml_notes(export_tei(play))
    end

    test "a note added after a word that has one comes second, and editing the first keeps that",
         %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Buscad por todas<note n="1" type="editor"><p>Importada.</p></note> partes</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      glosses = fn -> for %{paragraphs: [text]} <- xml_notes(export_tei(play)), do: text end

      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Buscad por todas partes")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add note")) |> render_click()

      lv
      |> form("#note-form", note: %{"offset" => "16", "body" => "Nueva."})
      |> render_submit()

      assert glosses.() == ["Importada.", "Nueva."]

      lv
      |> element("#{notes_section()} li:first-child button", t("Edit"))
      |> render_click()

      lv |> form("#note-form", note: %{"body" => "Importada, corregida."}) |> render_submit()
      assert glosses.() == ["Importada, corregida.", "Nueva."]
    end

    test "a speaker label and a heading take notes too", %{conn: conn, play: play} do
      lv = open_structure(conn, play)

      [act] =
        Regex.run(~r/id="(division-[^"]+)"[^>]*>(?:(?!id="division-).)*ACTO PRIMERO/s, render(lv),
          capture: :all_but_first
        )

      lv |> element("##{act} button[aria-label='#{t("Edit metadata")}']") |> render_click()
      lv |> element("button", t("Add note")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Del título."}) |> render_submit()
      lv |> element("button", t("Cancel")) |> render_click()

      lv |> element("button", "ESCENA I") |> render_click()
      speech = row(play, &(Map.get(&1, :speaker_label) == "ANA"))

      lv
      |> element("#element-#{speech.id} > div:first-child button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add note")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Del hablante."}) |> render_submit()

      assert [
               %{in: "head", after: "ACTO PRIMERO", paragraphs: ["Del título."]},
               %{in: "speaker", after: "ANA", paragraphs: ["Del hablante."]}
             ] = xml_notes(export_tei(play))
    end

    test "a repeated word is numbered, so a note can go after either", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg><l n="1">partes de partes</l></lg></sp>
              </div2>
            </div1>
            """
          )
        )

      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "partes de partes")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add note")) |> render_click()
      assert has_element?(lv, "#note-form option", "partes (2)")

      lv |> form("#note-form", note: %{"offset" => "16", "body" => "Glosa."}) |> render_submit()
      assert [%{after: "partes de partes"}] = xml_notes(export_tei(play))
    end

    test "a note id that is not this line's changes nothing and says so", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Una línea<note n="1" type="editor"><p>Glosa uno.</p></note></l>
                  <l n="2">Otra línea<note n="2" type="editor"><p>Glosa dos.</p></note></l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      before = xml_notes(export_tei(play))
      other_line = row(play, &(Map.get(&1, :content) == "Otra línea"))
      [%{id: other_id}] = other_line.notes

      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Una línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      for button <- [t("Edit"), t("Delete")] do
        lv
        |> element("#{notes_section()} button", button)
        |> render_click(%{"id" => other_id})

        assert render(lv) =~ gone(), button
        assert xml_notes(export_tei(play)) == before, button
      end
    end
  end

  describe "the note editor, when what it shows was deleted elsewhere" do
    # A play with one noted line, the note editor open on it. Returns the line too.
    defp open_noted_line(conn) do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1">Una línea<note n="1" type="editor"><p>Glosa.</p></note></l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      line = row(play, &(Map.get(&1, :content) == "Una línea"))
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Una línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      {lv, play, line}
    end

    # Another tab, or another curator, deletes the line's notes.
    defp delete_notes_behind_its_back(line) do
      for note <- Playcode.PlayContent.list_notes(line),
          do: {:ok, _} = Playcode.PlayContent.delete_note(note)
    end

    test "deleting a note that is already gone reloads the list and says so",
         %{conn: conn} do
      {lv, _play, line} = open_noted_line(conn)
      delete_notes_behind_its_back(line)

      lv |> element("#{notes_section()} button", t("Delete")) |> render_click()

      assert render(lv) =~ gone()
      refute has_element?(lv, "#{notes_section()} button", t("Delete"))
    end

    test "changing a note that is already gone reloads the list and says so",
         %{conn: conn} do
      {lv, _play, line} = open_noted_line(conn)

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      delete_notes_behind_its_back(line)

      lv |> form("#note-form", note: %{"body" => "Glosa nueva."}) |> render_submit()

      assert render(lv) =~ gone()
      refute has_element?(lv, "#{notes_section()} button", t("Edit"))
    end

    test "adding a note to a line that is already gone says so", %{conn: conn} do
      {lv, play, line} = open_noted_line(conn)

      lv |> element("#{notes_section()} button", t("Add note")) |> render_click()
      {:ok, _} = Playcode.PlayContent.delete_element(line)

      lv |> form("#note-form", note: %{"body" => "Glosa."}) |> render_submit()

      assert render(lv) =~ gone()
      assert xml_notes(export_tei(play)) == []
    end

    test "a second submit of a form already saved changes nothing", %{conn: conn} do
      {lv, play, _line} = open_noted_line(conn)

      lv |> element("#{notes_section()} button", t("Add note")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Nueva."}) |> render_submit()
      saved = xml_notes(export_tei(play))
      assert length(saved) == 2

      # What a double click, or a second tab, sends once the form has closed.
      lv
      |> with_target(notes_section())
      |> render_hook("save_note", %{"note" => %{"body" => "Otra vez."}})

      assert xml_notes(export_tei(play)) == saved
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
