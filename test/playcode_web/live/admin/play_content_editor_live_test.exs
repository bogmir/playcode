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

  alias Playcode.PlayContent
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
    |> Enum.map(fn {attrs, text} -> {text, attrs["n"] && String.to_integer(attrs["n"])} end)
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

  # A verse's number is the edition's, the one readers cite (TEI's `n`, a reference system),
  # so adding or deleting a verse renumbers no other (decided 2026-10-22). These tests asserted
  # the renumbering until then; it renumbered other acts' verses in a play whose numbering
  # starts again in each act, and the whole play's after a deleted first part of a split verse.
  test "deleting a verse leaves the others' numbers as they are", %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Primera línea")} button[aria-label='#{t("Delete")}']")
    |> render_click()

    assert lines(play) == [{"Segunda línea", 2}, {"Tercera línea", 3}]
  end

  # A number filled in was a guess, and a wrong one for a middle or last part of a split verse.
  test "a verse inserted above another comes with no number", %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
    |> render_click()

    lv |> form("#element-form", element: %{"content" => "Línea nueva"}) |> render_submit()

    assert lines(play) == [
             {"Primera línea", 1},
             {"Segunda línea", 2},
             {"Línea nueva", nil},
             {"Tercera línea", 3}
           ]
  end

  test "the number typed for a new verse renumbers no other", %{conn: conn, play: play} do
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
    |> render_click()

    lv
    |> form("#element-form", element: %{"content" => "Línea nueva", "line_number" => "3"})
    |> render_submit()

    assert lines(play) == [
             {"Primera línea", 1},
             {"Segunda línea", 2},
             {"Línea nueva", 3},
             {"Tercera línea", 3}
           ]
  end

  # The form takes any part anywhere, as TEI's schema does, and a correction passes through
  # disorder, so the editor lists the parts out of order, as the import preview does, and
  # refuses nothing.
  test "a split verse's part out of order is listed, opening its line, until corrected",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
            <sp><speaker>ANA</speaker><p>Prosa.</p></sp>
            <sp><speaker>DON</speaker><lg><l xml:id="sv-0001" part="F">O molto</l></lg></sp>
          </div1>
          """
        )
      )

    [{part, :completes_nothing}] = PlayContent.split_verses_out_of_order(play.id)
    {:ok, lv, html} = live(conn, ~p"/admin/plays/#{play.id}/content")

    assert html =~
             n(
               "%{count} part of a split verse out of order:",
               "%{count} parts of split verses out of order:",
               1
             )

    assert html =~ t("a last part that completes no verse")

    # The line's form opens in place: the tab, the scene and the selections stay.
    lv |> element("button", "sv-0001") |> render_click()
    html = lv |> form("#element-form", element: %{"part" => ""}) |> render_submit()

    # At once, not when the relay of the commit arrives: the tests' sandbox never commits.
    refute html =~
             n(
               "%{count} part of a split verse out of order:",
               "%{count} parts of split verses out of order:",
               1
             )

    assert [{%{"xml:id" => "sv-0001"} = line, "O molto"}] = xml_elements(export_tei(play), "l")
    refute Map.has_key?(line, "part")

    # An edit made elsewhere arrives through what Playcode.Export.PlayChangeListener relays.
    {:ok, _} =
      PlayContent.update_element(PlayContent.get_element(play.id, part.id), %{"part" => "F"})

    PlayContent.notify_changed(play.id)

    assert render(lv) =~
             n(
               "%{count} part of a split verse out of order:",
               "%{count} parts of split verses out of order:",
               1
             )
  end

  # The tab adds lines in an act's cast list, and Word nests a stanza in a stanza: the
  # check walks every line the play stores, where it is.
  test "a part in a nested stanza or in an act's cast list is checked too", %{conn: conn} do
    %{play: play, act: act, scene: scene, line_group: group} = play_with_structure_fixture()

    add = fn attrs ->
      {:ok, element} = PlayContent.create_element(Map.put(attrs, :play_id, play.id))
      element
    end

    # Completes the fixture's first part, "A verse line".
    nested = add.(%{division_id: scene.id, parent_id: group.id, type: "line_group", position: 2})

    add.(%{
      division_id: scene.id,
      parent_id: nested.id,
      type: "verse_line",
      part: "F",
      content: "anidado",
      position: 1
    })

    {:ok, list} =
      PlayContent.create_division(%{
        play_id: play.id,
        parent_id: act.id,
        type: "elenco",
        position: 2
      })

    speech = add.(%{division_id: list.id, type: "speech", position: 1})
    stanza = add.(%{division_id: list.id, parent_id: speech.id, type: "line_group", position: 1})

    add.(%{
      division_id: list.id,
      parent_id: stanza.id,
      type: "verse_line",
      part: "I",
      content: "en el elenco",
      position: 1
    })

    {:ok, _lv, html} = live(conn, ~p"/admin/plays/#{play.id}/content")

    assert html =~
             n(
               "%{count} part of a split verse out of order:",
               "%{count} parts of split verses out of order:",
               1
             )

    assert html =~ "en el elenco"
    assert html =~ t("a first part that nothing completes")
  end

  # Each form posts back, as hidden fields, the ids that place its row, and the browser can
  # change them: a crafted save put a line into another play's text, or moved a row into
  # another play. The ids come from the server (CLAUDE.md, *Access control*).
  describe "a save naming another play's ids" do
    setup %{play: play} do
      %{play: other, act: act, scene: scene, line_group: group} = play_with_structure_fixture()

      %{
        foreign: %{
          "play_id" => other.id,
          "division_id" => scene.id,
          "parent_id" => group.id,
          "cast_list_id" => act.id
        },
        other: other,
        divisions: PlayContent.list_top_divisions(play.id)
      }
    end

    test "adds a new line where its form opened, in this play",
         %{conn: conn, play: play, other: other, foreign: foreign} do
      lv = open_scene(conn, play)

      lv
      |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
      |> render_click()

      render_submit(lv, "save_form", %{"element" => Map.put(foreign, "content", "Intrusa")})

      assert {"Intrusa", nil} in lines(play)
      refute "Intrusa" in xml_texts(export_tei(other), "l")
    end

    test "leaves an edited line in this play", %{conn: conn, play: play, foreign: foreign} do
      lv = open_scene(conn, play)
      "#element-" <> id = card(lv, "Segunda línea")

      render_click(lv, "edit_element", %{"id" => id})
      render_submit(lv, "save_form", %{"element" => Map.put(foreign, "content", "Movida")})

      assert {"Movida", 2} in lines(play)
    end

    test "leaves an edited division in this play",
         %{conn: conn, play: play, foreign: foreign, divisions: divisions} do
      lv = open_structure(conn, play)
      act = Enum.find(divisions, &(&1.type == "acto"))
      [scene] = Enum.reject(act.children, &(&1.type == "elenco"))

      render_click(lv, "edit_division", %{"id" => scene.id})
      render_submit(lv, "save_form", %{"division" => Map.put(foreign, "title", "ESCENA I")})

      assert %{parent_id: parent_id} = PlayContent.get_division(play.id, scene.id)
      assert parent_id == act.id
    end

    test "leaves an edited paratext in this play", %{conn: conn, play: play, foreign: foreign} do
      {:ok, paratext} =
        Playcode.Catalogue.create_paratext(%{
          play_id: play.id,
          kind: "dedicatoria",
          content: "Al lector"
        })

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
      render_click(lv, "edit_paratext", %{"id" => paratext.id})
      render_submit(lv, "save_form", %{"paratext" => Map.put(foreign, "content", "Al lector")})

      assert Playcode.Catalogue.get_paratext(play.id, paratext.id)
    end

    test "leaves an edited cast-list entry and its character in this play",
         %{conn: conn, play: play, foreign: foreign} do
      [%{entries: [entry | _]}] = PlayContent.list_cast_lists(play.id)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")

      render_click(lv, "edit_entry", %{"id" => entry.id})

      render_submit(lv, "save_form", %{
        "entry" => Map.put(foreign, "name", "ANA"),
        "character" => Map.put(foreign, "name", "ANA")
      })

      assert %{cast_list_id: list_id} = PlayContent.get_entry(play.id, entry.id)
      assert list_id == entry.cast_list_id
      assert PlayContent.get_character(play.id, entry.character_id)
    end
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

      # "Add Act" was this button before the tab became the outline.
      lv |> element("button", t("Add division")) |> render_click()

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
      [%{entries: [their_entry]} = their_list] = Playcode.PlayContent.list_cast_lists(other.id)
      act = row(other, &match?(%Division{type: "acto"}, &1))
      verse = row(other, &(&1.type == "verse_line"))

      events = [
        {"edit_paratext", paratext.id},
        {"delete_paratext", paratext.id},
        {"edit_entry", their_entry.id},
        {"delete_entry", their_entry.id},
        {"edit_division", act.id},
        {"delete_division", act.id},
        {"delete_division", row(other, &match?(%Division{type: "elenco"}, &1)).id},
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

      for event <- ~w(new_character add_existing_entry),
          id <- [their_list.id, Ecto.UUID.generate(), "not-an-id"] do
        {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
        assert render_click(lv, event, %{"list-id" => id}) =~ gone(), "#{event} #{id}"
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
      assert has_element?(lv, "#element-form", t("Words only the Folio prints: <folio>…</folio>"))
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

  # Question 25: a verse added in Playcode takes the next free number in the play's shape,
  # one past its highest, and no line is renumbered, so no link to a line breaks.
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

    # Hamlet's numbers skip: 2,943 lines, the highest 4001.
    test "is one past the play's highest, wherever the verse goes", %{conn: conn} do
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
               {"Primera línea", "em0010-en-0136"},
               {"Línea nueva", "em0010-en-4002"},
               {"Segunda línea", "em0010-en-4001"}
             ]
    end

    test "in a play with none is the language's first", %{conn: conn, play: play} do
      conn |> open_scene(play) |> insert_above("Primera línea")

      assert {"Línea nueva", "es-0001"} in ids(play)
    end

    test "in an EMOTHE play with none takes the play's number too", %{conn: conn} do
      number = System.unique_integer([:positive])

      play =
        import_tei!(
          tei(
            code: "EMOTHE#{number}",
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head>
                <sp><speaker>ANA</speaker><lg><l n="1">Primera línea</l></lg></sp>
              </div2>
            </div1>
            """
          )
        )

      conn |> open_scene(play) |> insert_above("Primera línea")

      assert {"Línea nueva", "em#{number}-#{play.language}-0001"} in ids(play)
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

    lv
    |> form("#paratext-form",
      paratext: %{
        "kind" => "epilogo",
        "heading" => "SONETO",
        "content" => "Alégrate, París,\nuno de tus vecinos\n\nTerencio no hacía",
        "verse" => "true",
        "trailer" => "FIN"
      }
    )
    |> render_submit()

    xml = export_tei(play)

    assert xml_texts(xml, "l", within: "back") ==
             ["Alégrate, París,", "uno de tus vecinos", "Terencio no hacía"]

    assert length(xml_elements(xml, "lg", within: "back")) == 2
    assert xml_texts(xml, "trailer", within: "back") == ["FIN"]
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
  # order, an act's scenes and lists nested under it. test/fixtures/outline.xml holds one
  # of each where it can stand.
  describe "the outline" do
    setup do
      %{play: import_tei!(outline_xml()), other: import_tei!(outline_xml())}
    end

    defp outline_keys(play), do: play.id |> outline_items() |> Enum.map(&key/1)

    defp paratext_key(play, heading),
      do: key(Enum.find(Playcode.Catalogue.list_paratexts(play.id), &(&1.heading == heading)))

    defp division(play, title),
      do: row(play, &match?(%Division{title: ^title}, &1))

    test "dragging moves a paratext, a list or an act anywhere among the others",
         %{conn: conn, play: play} do
      lv = open_structure(conn, play)
      loa = paratext_key(play, "LOA")

      lv
      |> element("#outline")
      |> render_hook("reorder_outline", %{"ids" => [loa | List.delete(outline_keys(play), loa)]})

      assert hd(outline_keys(play)) == loa
      assert ["front/titlePage", "front/div[loa]" | _] = text_order(export_tei(play))

      act = key(division(play, "ACTO SEGUNDO"))

      lv
      |> element("#outline")
      |> render_hook("reorder_outline", %{"ids" => [act | List.delete(outline_keys(play), act)]})

      assert ["front/titlePage", "body/div1[acto]" | _] = text_order(export_tei(play))
    end

    # The ids came from the browser: another play's rows, or a malformed key, move nothing.
    test "a reorder naming another play's rows moves neither play",
         %{conn: conn, play: play, other: other} do
      ours = outline_keys(play)
      theirs = outline_keys(other)
      lv = open_structure(conn, play)

      lv
      |> element("#outline")
      |> render_hook("reorder_outline", %{
        "ids" => [paratext_key(other, "LOA"), "paratext:not-an-id" | ours]
      })

      assert outline_keys(play) == ours
      assert outline_keys(other) == theirs
    end

    test "an act's scenes and lists are dragged within the act", %{
      conn: conn,
      play: play,
      other: other
    } do
      act = division(play, "ACTO PRIMERO")
      [first, scene_1, again, scene_2] = Enum.map(act.children, & &1.id)
      foreign = division(other, "Sale de nuevo").id
      lv = open_structure(conn, play)

      lv
      |> element("#children-#{act.id}")
      |> render_hook("reorder_children", %{
        "parent" => act.id,
        "ids" => [foreign, again, first, scene_1, scene_2]
      })

      assert in_order?(export_tei(play), [
               "Sale de nuevo",
               "Personas del acto primero",
               "ESCENA I",
               "ESCENA II"
             ])

      assert in_order?(export_tei(other), [
               "Personas del acto primero",
               "ESCENA I",
               "Sale de nuevo",
               "ESCENA II"
             ])
    end

    test "Add division offers Cast list, which stands last in the outline", %{
      conn: conn,
      play: play
    } do
      lv = open_structure(conn, play)
      lv |> element("button", t("Add division")) |> render_click()

      assert has_element?(lv, "#division-form option", t("Cast list"))
      refute has_element?(lv, "#division-form option", t("Scene (escena)"))

      lv
      |> form("#division-form", division: %{"type" => "elenco", "title" => "Personas añadidas"})
      |> render_submit()

      assert List.last(text_order(export_tei(play))) == "back/div[elenco]"
      assert List.last(Playcode.PlayContent.list_cast_lists(play.id)).title == "Personas añadidas"
    end

    test "Add subdivision offers Scene and Cast list", %{conn: conn, play: play} do
      act = division(play, "ACTO SEGUNDO")
      lv = open_structure(conn, play)
      lv |> element("#division-#{act.id} button", t("Add subdivision")) |> render_click()

      assert has_element?(lv, "#division-form option", t("Scene (escena)"))
      assert has_element?(lv, "#division-form option", t("Cast list"))
      refute has_element?(lv, "#division-form option", t("Act (acto)"))

      lv
      |> form("#division-form", division: %{"type" => "elenco", "title" => "Salen al final"})
      |> render_submit()

      assert in_order?(export_tei(play), ["ACTO SEGUNDO", "ESCENA I", "Salen al final", "EPÍLOGO"])
    end

    test "a cast list offers neither Add subdivision nor Edit content", %{conn: conn, play: play} do
      list = division(play, "Personas del acto segundo")
      act = division(play, "ACTO SEGUNDO")
      lv = open_structure(conn, play)

      assert has_element?(lv, "#division-#{act.id} button", t("Add subdivision"))
      refute has_element?(lv, "#division-#{list.id} button", t("Add subdivision"))
      refute has_element?(lv, "#division-#{list.id} button", t("Edit Content"))
    end

    # Its one entry declares DIEGO, who speaks: a speech would point at no one listed.
    test "deleting a list holding a speaking character's only entry is refused, naming them",
         %{conn: conn, play: play} do
      before = export_tei(play)
      list = division(play, "Sale de nuevo")
      lv = open_structure(conn, play)

      lv |> element("#division-#{list.id} button[aria-label='#{t("Delete")}']") |> render_click()

      assert render(lv) =~ "DIEGO"
      assert export_tei(play) == before
    end

    # Review focus 4: an act's own lists go with it.
    test "deleting an act whose list holds a speaking character's only entry is refused",
         %{conn: conn, play: play} do
      before = export_tei(play)
      act = division(play, "ACTO PRIMERO")
      lv = open_structure(conn, play)

      lv |> element("#division-#{act.id} button[aria-label='#{t("Delete")}']") |> render_click()

      assert render(lv) =~ "DIEGO"
      assert export_tei(play) == before
    end

    # BLAS has his entry before the acts, and the musicians are no one who speaks.
    test "deleting a list whose characters are elsewhere removes it and no character",
         %{conn: conn, play: play} do
      list = division(play, "Personas del acto segundo")
      lv = open_structure(conn, play)

      lv |> element("#division-#{list.id} button[aria-label='#{t("Delete")}']") |> render_click()

      refute export_tei(play) =~ "Personas del acto segundo"
      assert length(Playcode.PlayContent.list_characters(play.id)) == 4
    end
  end

  # The Characters tab has a section per cast list, in outline order, each with its own
  # entries; an entry is dragged within its list or into another.
  # El galán Castrucho's 985 speeches all open with a line group, which has no text of
  # its own, and their positions count within each act: every row looked alike, the three
  # acts interleaved.
  describe "the character review" do
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO I</head>
              <sp><speaker>ANA</speaker><lg><l n="1">Abre el <emph>acto</emph> primero</l></lg></sp>
              <sp><speaker>BLAS</speaker><lg><l n="2">Cierra el acto primero</l></lg></sp>
            </div1>
            <div1 type="acto" n="2"><head>ACTO II</head>
              <sp><speaker>CELIA</speaker><lg><l n="3">Abre el acto segundo</l></lg></sp>
            </div1>
            """
          )
        )

      %{reviewed: play}
    end

    defp open_review(conn, play) do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")

      lv
      |> element("nav[aria-label='Editor tabs'] button", t("Character Review"))
      |> render_click()
    end

    test "a speech opening with a line group shows its first line, as readers read it",
         %{conn: conn, reviewed: play} do
      html = open_review(conn, play)

      assert html =~ "Abre el acto primero"
      refute html =~ "<<"
    end

    test "the speeches are listed in reading order", %{conn: conn, reviewed: play} do
      assert conn
             |> open_review(play)
             |> in_order?([
               "Abre el acto primero",
               "Cierra el acto primero",
               "Abre el acto segundo"
             ])
    end
  end

  describe "the cast lists" do
    setup do
      %{play: import_tei!(outline_xml()), other: import_tei!(outline_xml())}
    end

    defp list_keys(play) do
      for list <- Playcode.PlayContent.list_cast_lists(play.id),
          key <- ["list:#{list.id}" | Enum.map(list.entries, &"entry:#{&1.id}")],
          do: key
    end

    defp entry_names(play),
      do:
        for(
          list <- Playcode.PlayContent.list_cast_lists(play.id),
          do: Enum.map(list.entries, & &1.name)
        )

    defp cast_list(play, title),
      do: Enum.find(Playcode.PlayContent.list_cast_lists(play.id), &(&1.title == title))

    test "each list has its own section, in outline order, with its own entries",
         %{conn: conn, play: play} do
      html = conn |> open_cast(play) |> element("#cast-lists") |> render()

      assert in_order?(
               html,
               ["PERSONAS", "ANA", "dama", "BLAS", "Criados", "CRISPÍN", "Músicos"] ++
                 ["ACTO PRIMERO", "Personas del acto primero", "ANA, disfrazada", "de hombre"] ++
                 ["Sale de nuevo", "DIEGO", "Personas del acto segundo", "BLAS"] ++
                 ["Personas que no hablan", "CRISPÍN"]
             )

      assert occurrences(html, t("Names no character")) == 1
    end

    test "dragging an entry into another list moves it there", %{conn: conn, play: play} do
      diego = "entry:#{entry(play, "DIEGO").id}"
      [first | rest] = List.delete(list_keys(play), diego)

      conn
      |> open_cast(play)
      |> element("#cast-lists")
      |> render_hook("reorder_entries", %{"ids" => [first, diego | rest]})

      assert [
               ["DIEGO", "ANA", "BLAS", "CRISPÍN", "Músicos"],
               ["ANA, disfrazada"],
               [],
               ["BLAS"],
               ["CRISPÍN"]
             ] =
               entry_names(play)
    end

    # Review focus 5: the keys came from the browser.
    test "a drag carrying another play's entry changes neither play",
         %{conn: conn, play: play, other: other} do
      [first | rest] = list_keys(play)
      ours = entry_names(play)
      theirs = entry_names(other)

      conn
      |> open_cast(play)
      |> element("#cast-lists")
      |> render_hook("reorder_entries", %{
        "ids" => [first, "entry:#{entry(other, "DIEGO").id}", "entry:not-an-id" | rest]
      })

      assert entry_names(play) == ours
      assert entry_names(other) == theirs
    end

    test "Add an existing character puts one already listed into this list, and offers none already in it",
         %{conn: conn, play: play} do
      list = cast_list(play, "Personas del acto segundo")
      lv = open_cast(conn, play)
      lv |> element("#list-#{list.id} button", t("Add an existing character")) |> render_click()

      assert has_element?(lv, "#existing-entry-form option", "DIEGO")
      refute has_element?(lv, "#existing-entry-form option", "BLAS")

      diego = Enum.find(Playcode.PlayContent.list_characters(play.id), &(&1.xml_id == "DIEGO"))

      lv
      |> form("#existing-entry-form", existing: %{"character_id" => diego.id})
      |> render_submit()

      assert Enum.map(cast_list(play, "Personas del acto segundo").entries, & &1.name) == [
               "BLAS",
               "DIEGO"
             ]
    end

    test "Add character in a section makes the character and its entry there", %{
      conn: conn,
      play: play
    } do
      list = cast_list(play, "Personas que no hablan")
      lv = open_cast(conn, play)
      lv |> element("#list-#{list.id} button", t("Add character")) |> render_click()

      lv
      |> form("#character-form", character: %{"xml_id" => "PAJE", "name" => "PAJE"})
      |> render_submit()

      assert Enum.map(cast_list(play, "Personas que no hablan").entries, & &1.name) == [
               "CRISPÍN",
               "PAJE"
             ]
    end

    test "editing an entry's description changes that list's line only", %{conn: conn, play: play} do
      disguised =
        Enum.find(
          cast_list(play, "Personas del acto primero").entries,
          &(&1.name == "ANA, disfrazada")
        )

      lv = open_cast(conn, play)

      lv |> element("#entry-#{disguised.id} button[aria-label='#{t("Edit")}']") |> render_click()
      lv |> form("#entry-form", entry: %{"description" => "vestida de hombre"}) |> render_submit()

      assert [%{description: "dama"} | _] = cast_list(play, "PERSONAS").entries

      assert [%{description: "vestida de hombre"}] =
               cast_list(play, "Personas del acto primero").entries

      assert %{description: "dama"} =
               Enum.find(Playcode.PlayContent.list_characters(play.id), &(&1.xml_id == "ANA"))
    end

    test "removing a speaking character's last entry is refused, naming them", %{
      conn: conn,
      play: play
    } do
      diego = entry(play, "DIEGO")
      lv = open_cast(conn, play)

      lv |> element("#entry-#{diego.id} button[aria-label='#{t("Remove")}']") |> render_click()

      assert render(lv) =~
               t("Not removed: %{name} speaks in the play and is listed nowhere else.",
                 name: "DIEGO"
               )

      assert [["DIEGO"]] =
               for(
                 %{title: "Sale de nuevo"} = l <- Playcode.PlayContent.list_cast_lists(play.id),
                 do: Enum.map(l.entries, & &1.name)
               )
    end

    test "an entry naming no character is removed", %{conn: conn, play: play} do
      musicians = Enum.find(cast_list(play, "PERSONAS").entries, &(&1.name == "Músicos"))
      lv = open_cast(conn, play)

      lv
      |> element("#entry-#{musicians.id} button[aria-label='#{t("Remove")}']")
      |> render_click()

      assert Enum.map(cast_list(play, "PERSONAS").entries, & &1.name) == [
               "ANA",
               "BLAS",
               "CRISPÍN"
             ]
    end

    test "removing an entry whose character is listed elsewhere keeps the character", %{
      conn: conn,
      play: play
    } do
      [crispin] = cast_list(play, "Personas que no hablan").entries
      lv = open_cast(conn, play)

      lv |> element("#entry-#{crispin.id} button[aria-label='#{t("Remove")}']") |> render_click()

      assert cast_list(play, "Personas que no hablan").entries == []
      assert Enum.any?(Playcode.PlayContent.list_characters(play.id), &(&1.xml_id == "CRISPIN"))
    end
  end

  # DON is silent and listed only in the first list; ANA has her entry in the act too.
  test "deleting a list removes the silent characters it leaves in no list, and says how many first",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          front: """
          <div type="elenco"><head>PRIMERA</head><castList>
            <castItem><role xml:id="ANA">ANA</role></castItem>
            <castItem><role xml:id="DON">DON</role></castItem>
          </castList></div>
          """,
          body: """
          <div1 type="acto" n="1"><head>ACTO I</head>
            <castList><head>SEGUNDA</head><castItem><role corresp="#ANA">ANA</role></castItem></castList>
            <sp who="#ANA"><speaker>ANA</speaker><l n="1">Verso.</l></sp>
          </div1>
          """
        )
      )

    list = row(play, &match?(%Division{title: "PRIMERA"}, &1))
    lv = open_structure(conn, play)

    confirm =
      Gettext.ngettext(
        PlaycodeWeb.Gettext,
        "Delete this cast list? One character listed nowhere else goes with it.",
        "Delete this cast list? %{count} characters listed nowhere else go with it.",
        1
      )

    delete = "#division-#{list.id} button[aria-label='#{t("Delete")}']"
    assert lv |> element(delete) |> render() =~ confirm

    lv |> element(delete) |> render_click()

    assert ["ANA"] = Enum.map(Playcode.PlayContent.list_characters(play.id), & &1.name)
    refute export_tei(play) =~ "PRIMERA"
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

    # It stands last, after the act, until it is dragged before the text: a <set> there.
    lv |> element("nav[aria-label='Editor tabs'] button", "structure") |> render_click()
    [scene | rest] = play.id |> outline_items() |> Enum.reverse()

    lv
    |> element("#outline")
    |> render_hook("reorder_outline", %{"ids" => Enum.map([scene | Enum.reverse(rest)], &key/1)})

    xml = export_tei(play)
    assert xml_texts(xml, "head", within: "set") == ["SCENE:"]
    assert xml_texts(xml, "p", within: "set") == ["An English wood."]
  end

  # Edited in the form of her entry, which carries her character's fields too.
  test "a character's actor in the original cast is edited and listed", %{conn: conn, play: play} do
    lv = open_cast(conn, play)
    ana = entry(play, "ANA")

    lv |> element("#entry-#{ana.id} button[aria-label='#{t("Edit")}']") |> render_click()

    lv
    |> form("#entry-form", character: %{"actor" => " Mrs.  Bracegirdle "})
    |> render_submit()

    assert lv |> element("#entry-#{ana.id}") |> render() =~ "Mrs. Bracegirdle"
    assert xml_texts(export_tei(play), "actor") == ["Mrs. Bracegirdle"]
  end

  test "a character marked a group goes into the file as one", %{conn: conn, play: play} do
    lv = open_cast(conn, play)
    ana = entry(play, "ANA")

    lv |> element("#entry-#{ana.id} button[aria-label='#{t("Edit")}']") |> render_click()
    lv |> form("#entry-form", character: %{"is_group" => "true"}) |> render_submit()

    assert {%{"ana" => "grupo"}, _} =
             export_tei(play)
             |> xml_elements("castItem")
             |> Enum.find(fn {_attrs, text} -> text =~ "ANA" end)
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
    # falta_tipo, the one kind question 17 left unnamed; it was latinismo, named since.
    test "?division= opens a heading's modal, and a type the select does not list survives an edit",
         %{conn: conn} do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO PRIMERO<note n="1" type="falta_tipo"><p>Glosa.</p></note></head>
              <sp><speaker>ANA</speaker><l n="1">Una línea</l></sp>
            </div1>
            """
          )
        )

      [act] = Playcode.PlayContent.list_top_divisions(play.id)
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content?division=#{act.id}")

      lv |> element("#{notes_section()} button", t("Edit")) |> render_click()
      lv |> form("#note-form", note: %{"body" => "Glosa corregida."}) |> render_submit()

      assert [%{type: "falta_tipo", paragraphs: ["Glosa corregida."]}] =
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

  # The play's outline, read back through the contexts, and each item's key as the
  # Structure tab's rows carry it.
  defp outline_items(play_id) do
    play_id
    |> Playcode.Catalogue.list_paratexts()
    |> Playcode.Outline.items(Playcode.PlayContent.list_top_divisions(play_id))
  end

  defp key(item), do: Playcode.Outline.key(item)

  defp open_cast(conn, play) do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    lv |> element("nav[aria-label='Editor tabs'] button", t("Cast list")) |> render_click()
    lv
  end

  # A character's first entry, the line its name is first given in.
  defp entry(play, xml_id) do
    play.id
    |> Playcode.PlayContent.list_cast_lists()
    |> Enum.flat_map(& &1.entries)
    |> Enum.find(&(&1.character && &1.character.xml_id == xml_id))
  end

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
