defmodule PlaycodeWeb.Admin.PlayContentEditorLiveTest do
  @moduledoc """
  Editing a play's text at /admin/plays/:id/content: its verses and their numbers,
  the Structure tab, and what a save or an event naming another play's rows does. Checked
  the way readers get it: the play's exported TEI, or its public page. Two controls are
  JavaScript hooks the test cannot run (inline editing and the character picker); for those
  the test pushes the event the hook would push.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers
  import PlaycodeWeb.PlayContentEditorHelpers

  alias Playcode.PlayContent
  alias Playcode.PlayContent.Division

  setup :open_editor

  test "the editor's tabs are named in Spanish", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")

    for name <- [t("Structure"), t("Content"), t("Preview")],
        do: assert(has_element?(lv, "nav[aria-label='Editor tabs'] button", name))

    refute has_element?(lv, "nav[aria-label='Editor tabs'] button", "structure")
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

  # The Broken Heart's "A Song": a stanza's heading, written to the file as its <head>.
  test "a heading given to a stanza goes into the file, before its lines", %{
    conn: conn,
    play: play
  } do
    lv = open_scene(conn, play)

    [stanza_id] =
      Regex.run(
        ~r/phx-value-parent-id="([^"]+)"/,
        lv |> element("button", t("Add Verse Line")) |> render(),
        capture: :all_but_first
      )

    render_click(lv, "edit_element", %{"id" => stanza_id})
    lv |> form("#element-form", element: %{"content" => "A <<Song>>"}) |> render_submit()

    xml = export_tei(play)
    assert xml_texts(xml, "head", within: "lg") == ["A Song"]
    assert xml =~ ~r{<lg type="redondilla">\s*<head>A <emph>Song</emph></head>\s*<l}
  end

  # Every save recounts a play that is not Manual by its numbering rule (numbering spec,
  # 2026-11-08); a Manual play's numbers are the edition's, typed by hand, and adding or
  # deleting a verse renumbers no other there (decided 2026-10-22, when every play was so).
  defp manual!(play) do
    {:ok, play} = Playcode.Catalogue.update_play(play, %{numbering_manual: true})
    play
  end

  defp delete_first_line(conn, play) do
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Primera línea")} button[aria-label='#{t("Delete")}']")
    |> render_click()
  end

  defp insert_above_third(conn, play, fields) do
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Tercera línea")} button[aria-label='#{t("Insert Above")}']")
    |> render_click()

    lv |> form("#element-form", element: fields) |> render_submit()
  end

  test "deleting a verse recounts the others", %{conn: conn, play: play} do
    delete_first_line(conn, play)

    assert lines(play) == [{"Segunda línea", 1}, {"Tercera línea", 2}]
  end

  test "deleting a verse in a Manual play leaves the others' numbers", %{conn: conn, play: play} do
    delete_first_line(conn, manual!(play))

    assert lines(play) == [{"Segunda línea", 2}, {"Tercera línea", 3}]
  end

  test "a verse inserted above another takes its number, and the later ones move",
       %{conn: conn, play: play} do
    insert_above_third(conn, play, %{"content" => "Línea nueva"})

    assert lines(play) == [
             {"Primera línea", 1},
             {"Segunda línea", 2},
             {"Línea nueva", 3},
             {"Tercera línea", 4}
           ]
  end

  # A number filled in was a guess, and a wrong one for a middle or last part of a split verse.
  test "a verse inserted in a Manual play comes with no number", %{conn: conn, play: play} do
    insert_above_third(conn, manual!(play), %{"content" => "Línea nueva"})

    assert lines(play) == [
             {"Primera línea", 1},
             {"Segunda línea", 2},
             {"Línea nueva", nil},
             {"Tercera línea", 3}
           ]
  end

  defp two_scenes do
    import_tei!(
      tei(
        body: """
        <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
          <div2 type="escena" n="1"><head>ESCENA I</head>
            <sp><speaker>ANA</speaker><l n="1">Uno</l><l n="2">Dos</l></sp></div2>
          <div2 type="escena" n="2"><head>ESCENA II</head>
            <sp><speaker>ANA</speaker><l n="1">Tres</l><l n="2">Cuatro</l></sp></div2>
        </div1>
        """
      )
    )
  end

  test "a verse inserted in scene 2 of a V-per-scene play moves the later numbers of scene 2 only",
       %{conn: conn} do
    play = two_scenes()
    lv = open_structure(conn, play)
    lv |> element("button", "ESCENA II") |> render_click()

    lv
    |> element("#{card(lv, "Cuatro")} button[aria-label='#{t("Insert Above")}']")
    |> render_click()

    lv |> form("#element-form", element: %{"content" => "Nueva"}) |> render_submit()

    assert lines(play) == [
             {"Uno", 1},
             {"Dos", 2},
             {"Tres", 1},
             {"Nueva", 2},
             {"Cuatro", 3}
           ]
  end

  test "reordering scenes recounts a play numbered through", %{conn: conn} do
    play = two_scenes()
    {:ok, _} = Playcode.Catalogue.update_play(play, %{numbering_restart: "never"})
    PlayContent.refresh_derived(play.id)
    [act] = PlayContent.list_top_divisions(play.id)
    [first, second] = Enum.map(act.children, & &1.id)

    conn
    |> open_structure(play)
    |> element("#children-#{act.id}")
    |> render_hook("reorder_children", %{"parent" => act.id, "ids" => [second, first]})

    assert lines(play) == [{"Tres", 1}, {"Cuatro", 2}, {"Uno", 3}, {"Dos", 4}]
  end

  test "the number field shows only on a Manual play", %{conn: conn, play: play} do
    lv = open_scene(conn, play)
    edit = fn -> element(lv, "#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']") end

    edit.() |> render_click()
    refute has_element?(lv, "#element-form input#element_line_number")

    manual!(play)
    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']")
    |> render_click()

    assert has_element?(lv, "#element-form input#element_line_number")
  end

  test "the number typed for a new verse in a Manual play renumbers no other",
       %{conn: conn, play: play} do
    insert_above_third(conn, manual!(play), %{"content" => "Línea nueva", "line_number" => "3"})

    assert lines(play) == [
             {"Primera línea", 1},
             {"Segunda línea", 2},
             {"Línea nueva", 3},
             {"Tercera línea", 3}
           ]
  end

  # Hamlet numbers a verse "3-4": the form takes a number as the files write it, and a number
  # cleared is no number. The field was a number input until 2026-11-08.
  test "a verse's number is typed as the files write it, and cleared", %{conn: conn, play: play} do
    lv = open_scene(conn, manual!(play))
    edit = fn -> element(lv, "#{card(lv, "Segunda línea")} button[aria-label='#{t("Edit")}']") end

    edit.() |> render_click()
    assert has_element?(lv, "#element-form input#element_line_number[type=text]")
    lv |> form("#element-form", element: %{"line_number" => "3-4"}) |> render_submit()

    assert numbers(play) == ["1", "3-4", "3"]

    edit.() |> render_click()
    lv |> form("#element-form", element: %{"line_number" => ""}) |> render_submit()

    assert numbers(play) == ["1", nil, "3"]
  end

  defp numbers(play),
    do: for({attrs, _} <- play |> export_tei() |> xml_elements("l"), do: attrs["n"])

  # The form takes any part anywhere, as TEI's schema does, and a correction passes through
  # disorder, so the editor lists the parts out of order, as the import preview does, and
  # refuses nothing.
  # Two asides of ANA's in a row, numbered as the files number them: es-0003's seg01
  # starts the second.
  defp import_asides!(lines) do
    import_tei!(
      tei(
        body: """
        <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
          <div2 type="escena" n="1"><head>ESCENA I</head>
            <sp><speaker>ANA</speaker><lg>#{lines}</lg></sp>
          </div2>
        </div1>
        """
      )
    )
  end

  # Each aside piece's xml:id in the play's TEI file: its number says where an aside starts.
  # (Not the statistics: they are cached by content_version, which moves once a transaction,
  # and a test is one.)
  defp seg_ids(play),
    do: for({attrs, _} <- xml_elements(export_tei(play), "seg"), do: attrs["xml:id"])

  test "a verse ticked as continuing the aside before it joins that aside", %{conn: conn} do
    play =
      import_asides!("""
      <l xml:id="as-0001"><seg type="aside" xml:id="as-0001-seg01">Primer aparte</seg></l>
      <l xml:id="as-0002"><seg type="aside" xml:id="as-0002-seg01">Segundo aparte</seg></l>
      """)

    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Segundo aparte")} button[aria-label='#{t("Edit")}']")
    |> render_click()

    lv |> form("#element-form", element: %{"aside_continues" => "true"}) |> render_submit()

    assert seg_ids(play) == ["es-1-seg1", "es-2-seg2"]
  end

  test "deleting the verse an aside starts on leaves the rest an aside of their own",
       %{conn: conn} do
    play =
      import_asides!("""
      <l xml:id="as-0001"><seg type="aside" xml:id="as-0001-seg01">Uno aparte</seg></l>
      <l xml:id="as-0002">En voz alta</l>
      <l xml:id="as-0003"><seg type="aside" xml:id="as-0003-seg01">Tres aparte</seg></l>
      <l xml:id="as-0004"><seg type="aside" xml:id="as-0004-seg02">Cuatro aparte</seg></l>
      """)

    assert seg_ids(play) == ["es-1-seg1", "es-3-seg1", "es-4-seg2"]

    lv = open_scene(conn, play)

    lv
    |> element("#{card(lv, "Tres aparte")} button[aria-label='#{t("Delete")}']")
    |> render_click()

    # Not seg2: left as it was, Cuatro would continue the first aside, across the verse
    # spoken aloud. Its line's identifier is counted again: the third line now.
    assert seg_ids(play) == ["es-1-seg1", "es-3-seg1"]
  end

  # "Delete selected" reads every selected row, then deletes them in its selection's order,
  # which a test cannot choose: called directly, in the order that once lost the start.
  # Deleting Tres hands the start to Cuatro, whose row, read before, no longer says so.
  test "deleting an aside's first two verses, read before either goes, leaves the rest an aside of their own",
       %{conn: conn} do
    play =
      import_asides!("""
      <l xml:id="as-0001"><seg type="aside" xml:id="as-0001-seg01">Uno aparte</seg></l>
      <l xml:id="as-0002">En voz alta</l>
      <l xml:id="as-0003"><seg type="aside" xml:id="as-0003-seg01">Tres aparte</seg></l>
      <l xml:id="as-0004"><seg type="aside" xml:id="as-0004-seg02">Cuatro aparte</seg></l>
      <l xml:id="as-0005"><seg type="aside" xml:id="as-0005-seg03">Cinco aparte</seg></l>
      """)

    lv = open_scene(conn, play)

    selected =
      for text <- ["Tres aparte", "Cuatro aparte"] do
        "#element-" <> id = card(lv, text)
        PlayContent.get_element(play.id, id)
      end

    for element <- selected, do: {:ok, _} = PlayContent.delete_element(element)

    assert seg_ids(play) == ["es-1-seg1", "es-3-seg1"]
  end

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
    lv |> element("button", "O molto") |> render_click()
    html = lv |> form("#element-form", element: %{"part" => ""}) |> render_submit()

    # At once, not when the relay of the commit arrives: the tests' sandbox never commits.
    refute html =~
             n(
               "%{count} part of a split verse out of order:",
               "%{count} parts of split verses out of order:",
               1
             )

    assert [{line, "O molto"}] = xml_elements(export_tei(play), "l")
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

      # Counted by the play's rule, as every save is (numbering spec).
      assert {"Intrusa", 3} in lines(play)
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
end
