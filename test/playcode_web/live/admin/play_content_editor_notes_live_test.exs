defmodule PlaycodeWeb.Admin.PlayContentEditorNotesLiveTest do
  @moduledoc """
  The content editor's notes and the text they hang on: a note when its line is edited,
  stage directions, line numbers, verse identifiers, the paratexts tab and the note editor.
  Split from `PlayContentEditorLiveTest`, which says how the tests read their results.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers
  import PlaycodeWeb.PlayContentEditorHelpers

  setup :open_editor

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
      assert has_element?(lv, "#element-form", t("Words only the Folio prints: <folio>…</folio>"))

      # Question 63: a tagged name, with the kinds a tag may take.
      assert has_element?(lv, "#element-form", ~s(<rs type="atrezzo">))
      assert has_element?(lv, "#element-form", "toponimo_aludido, toponimo_accion")
      assert has_element?(lv, "#element-form", "mitologia_toponimo")
    end

    # A Folio passage may also be a stage direction's words or a speaker label.
    test "the stage direction and speech forms say how to type a Folio passage",
         %{conn: conn, play: play} do
      lv = open_scene(conn, play)
      hint = t("Words only the Folio prints: <folio>…</folio>")

      lv
      |> element("#{card(lv, "Sale el Rey")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      assert has_element?(lv, "#element-form", hint)

      lv |> element("[id^='el-speaker-']", "ANA") |> render_click()
      assert has_element?(lv, "#element-form label", t("Speaker Label"))
      assert has_element?(lv, "#element-form", hint)
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

    test "a new line with a refused marker is not saved", %{conn: conn, play: play} do
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
          # Manual, so the paragraph is not numbered at import.
          encoding_desc: manual_numbering(),
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

      assert {"entrance", "Sale don Pedro solo."} in stages(play)
    end

    test "a kind the list does not have survives an edit", %{conn: conn, play: play} do
      conn
      |> open_scene(play)
      |> edit("Vuela.")
      |> form("#element-form", element: %{"content" => "Vuela alto."})
      |> render_submit()

      assert {"trick", "Vuela alto."} in stages(play)
    end

    defp stages(play),
      do: for({attrs, text} <- xml_elements(export_tei(play), "stage"), do: {attrs["type"], text})

    # Problem 2 (docs/superpowers/specs/2026-11-08-identifiers-on-export-design.md): an
    # identifier is counted on export, so the form has none to show or edit. This test used
    # to assert the stored one was shown and kept.
    test "a verse's identifier is counted, not edited", %{conn: conn, play: play} do
      lv = conn |> open_scene(play) |> edit("Primera línea")

      refute lv |> element("#element-form") |> render() =~ "es-0001"
      refute has_element?(lv, "#element-form [name='element[line_id]']")

      lv |> form("#element-form", element: %{"content" => "Línea primera"}) |> render_submit()

      assert [{%{"xml:id" => "es-1"}, "Línea primera"}] = xml_elements(export_tei(play), "l")
    end
  end

  # Problem 2 retires question 25's next free identifier: every export counts the lines
  # again, so a verse added in Playcode takes its place's identifier and moves the ones
  # after it. What points at a line (an aside, a variant) moves along, and the EMOTHE
  # prefix and the language are covered there too: tei_roundtrip_test.exs, "identifiers".
  describe "a new verse's identifier" do
    defp insert_above(lv, content) do
      lv
      |> element("#{card(lv, content)} button[aria-label='#{t("Insert Above")}']")
      |> render_click()

      lv |> form("#element-form", element: %{"content" => "Línea nueva"}) |> render_submit()
    end

    defp ids(play) do
      play
      |> export_tei()
      |> xml_elements("l")
      |> Enum.map(fn {attrs, text} -> {text, attrs["xml:id"]} end)
    end

    # Hamlet's file skips: 0136, then 4001. The export counts them again, from 1.
    test "is its place's, and the ones after it move", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg>
                  <l n="1" xml:id="em0010-en-0136">Primera línea</l>
                  <l n="2" xml:id="em0010-en-4001">Segunda línea</l>
                </lg></sp>
              </div2>
            </div1>
            """
          )
        )

      conn |> open_scene(play) |> insert_above("Segunda línea")

      assert ids(play) == [
               {"Primera línea", "es-1"},
               {"Línea nueva", "es-2"},
               {"Segunda línea", "es-3"}
             ]
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

  # Question 30: a paratext in verse, a line to a line and a blank line between stanzas,
  # written as verse, with its closing formula.
  test "a paratext is marked as verse and given a closing formula", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Paratexts")) |> render_click()
    lv |> element("button", t("Add Paratext")) |> render_click()

    assert has_element?(lv, "#paratext-form label", t("In verse"))
    assert has_element?(lv, "#paratext-form label", t("Closing formula"))
    assert has_element?(lv, "#paratext-form label", t("Closing note"))

    lv
    |> form("#paratext-form",
      paratext: %{
        "kind" => "epilogo",
        "heading" => "SONETO",
        "content" => "Alégrate, París,\nuno de tus vecinos\n\nTerencio no hacía",
        "verse" => "true",
        "trailer" => "FIN",
        "note" => "Nota."
      }
    )
    |> render_submit()

    xml = export_tei(play)

    assert xml_texts(xml, "l", within: "back") ==
             ["Alégrate, París,", "uno de tus vecinos", "Terencio no hacía"]

    assert length(xml_elements(xml, "lg", within: "back")) == 2
    assert xml_texts(xml, "trailer", within: "back") == ["FIN"]
    assert xml_texts(xml, "note", within: "back") == ["Nota."]
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

    # A new paratext stands last in the outline, after the act.
    xml = export_tei(play)
    assert xml_texts(xml, "p", within: "back") == ["A B", "C"]
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

  # The Structure tab is the play's outline: every paratext, cast list and division in one

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

    # An imported term or text keeps its tags and italics (EMOTHE0551's notes tag names):
    # the list shows their words, not the markers.
    test "lists a note's term and text without their markers", %{conn: conn, play: play} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add note")) |> render_click()

      lv
      |> form("#note-form",
        note: %{
          "offset" => "7",
          "term" => ~s(<rs type="toponimo_aludido">Segunda</rs>),
          "body" => "Una <<glosa>> en <rs>Toledo</rs>."
        }
      )
      |> render_submit()

      listed = lv |> element(notes_section()) |> render()
      assert listed =~ "Segunda"
      assert listed =~ "Una glosa en Toledo."
      refute listed =~ "&lt;"
    end

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

      # A siglum is typed with its #, as the file writes it: the field shows how.
      assert has_element?(lv, ~s(#note-form input[placeholder="#H #P3"]))

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

    # TEI's <app> has at most one <lem>, and it comes first: the form's "Edition's reading"
    # checkbox sits on every row, so the note refuses two and puts the one it has first.
    test "a variant with two readings the edition follows is refused, and nothing is saved",
         %{conn: conn, play: play} do
      lv = open_variant_form(conn, play)

      html =
        lv
        |> form("#note-form",
          note: %{
            "offset" => "7",
            "readings" => %{
              "0" => %{"lemma" => "true", "wit" => "#H", "text" => "Segunda"},
              "1" => %{"lemma" => "true", "wit" => "#P3", "text" => "Primera"}
            }
          }
        )
        |> render_submit()

      assert html =~
               Gettext.dgettext(
                 PlaycodeWeb.Gettext,
                 "errors",
                 "Only one reading can be the edition's"
               )

      assert xml_apps(export_tei(play)) == []
    end

    test "the reading the edition follows is exported first, whichever row it is on",
         %{conn: conn, play: play} do
      lv = open_variant_form(conn, play)

      lv
      |> form("#note-form",
        note: %{
          "offset" => "7",
          "readings" => %{
            "0" => %{"lemma" => "false", "wit" => "#P3", "text" => "Primera"},
            "1" => %{"lemma" => "true", "wit" => "#H", "text" => "Segunda"}
          }
        }
      )
      |> render_submit()

      assert [%{readings: [{"lem", "#H", "Segunda", nil}, {"rdg", "#P3", "Primera", nil}]}] =
               xml_apps(export_tei(play))
    end

    test "an \"Add reading\" row left empty is not saved", %{conn: conn, play: play} do
      lv = open_variant_form(conn, play)

      lv
      |> form("#note-form",
        note: %{
          "offset" => "7",
          "readings" => %{"0" => %{"lemma" => "true", "wit" => "#H", "text" => "Segunda"}}
        }
      )
      |> render_submit()

      assert [%{readings: [{"lem", "#H", "Segunda", nil}]}] = xml_apps(export_tei(play))
      html = render(lv)
      assert html =~ "#H Segunda"
      refute html =~ "#H Segunda ·"
    end

    # A variant's form, with a second (empty) reading row added.
    defp open_variant_form(conn, play) do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']")
      |> render_click()

      lv |> element("button", t("Add variant")) |> render_click()
      lv |> form("#note-form") |> render_change(%{note: %{"readings_order" => ["0", "new"]}})
      lv
    end

    # The Notes tab links a note's line or heading here; its modal opens on arrival.
    # sin_tipo, a kind with no name; it was latinismo, then falta_tipo, both named since.
    test "?division= opens a heading's modal, and a type the select does not list survives an edit",
         %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO<note n="1" type="sin_tipo"><p>Glosa.</p></note></head>
              <sp><speaker>ANA</speaker><l n="1">Una línea</l></sp>
            </div1>
            """
          )
        )

      [act] = Playcode.PlayContent.list_top_divisions(play.id)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content?division=#{act.id}")

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Glosa corregida."}) |> render_submit()

      assert [%{type: "sin_tipo", paragraphs: ["Glosa corregida."]}] =
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
end
