defmodule PlaycodeWeb.Admin.PlayContentEditorOutlineLiveTest do
  @moduledoc """
  The content editor's outline, character review, cast lists and a translation's original
  characters. Split from `PlayContentEditorLiveTest`, which says how the tests read their results.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers
  import PlaycodeWeb.PlayContentEditorHelpers

  alias Playcode.PlayContent
  alias Playcode.PlayContent.Division

  setup :open_editor

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

    # The line before a cast list and the note after it, as 78 corpus files have them; the
    # form asks for them only once the division is a cast list.
    test "a cast list takes the line before it and the note after it", %{conn: conn, play: play} do
      lv = open_structure(conn, play)
      lv |> element("button", t("Add division")) |> render_click()
      refute has_element?(lv, "#division-form textarea")

      lv |> form("#division-form", division: %{"type" => "elenco"}) |> render_change()

      lv
      |> form("#division-form",
        division: %{
          "type" => "elenco",
          "title" => "Personas",
          "intro" => "Hablan en ella:",
          "note" => "Criados.\n\nLa escena es en Madrid."
        }
      )
      |> render_submit()

      xml = export_tei(play)
      assert xml =~ ~r{<head>Personas</head>\s*<p>Hablan en ella:</p>}
      assert xml =~ ~r{<note>\s*<p>Criados.</p>\s*<p>La escena es en Madrid.</p>\s*</note>}
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
    lv |> element("nav[aria-label='Editor tabs'] button", t("Structure")) |> render_click()
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

  # Problem 5, step 3: which original character a translation's character goes with, the
  # rule's pick unless a researcher corrects it, on its cast entry.
  describe "a translation's original characters" do
    setup do
      split_speech_editions()
    end

    defp open_entry(conn, play, xml_id) do
      entry =
        play.id
        |> PlayContent.list_cast_lists()
        |> Enum.flat_map(& &1.entries)
        |> Enum.find(&(&1.character && &1.character.xml_id == xml_id))

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
      lv |> element("#entry-#{entry.id} button[aria-label='#{t("Edit")}']") |> render_click()
      {lv, entry}
    end

    defp choose(lv, value),
      do: lv |> form("#entry-form", %{"character" => %{"original" => value}}) |> render_submit()

    defp correction(play, xml_id) do
      character = Enum.find(PlayContent.list_characters(play.id), &(&1.xml_id == xml_id))
      {character.original_xml_id, character.no_original}
    end

    defp options(lv),
      do:
        lv
        |> element("#entry-form select[name='character[original]']")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("option")
        |> Enum.map(&LazyHTML.text/1)
        |> Enum.map(&String.trim/1)

    test "offers the rule's pick, the original's characters and none, and stores the choice",
         %{conn: conn, french: french} do
      {lv, _} = open_entry(conn, french, "antoine")

      assert options(lv) == [
               t("Automatic (%{name})", name: "ANTONY"),
               "ANTONY",
               "CLEOPATRA",
               t("No original")
             ]

      choose(lv, "CLEO")
      assert correction(french, "antoine") == {"CLEO", false}

      {lv, _} = open_entry(conn, french, "antoine")
      assert hd(options(lv)) == t("Automatic (%{name})", name: "ANTONY")
      choose(lv, "-")
      assert correction(french, "antoine") == {nil, true}

      {lv, _} = open_entry(conn, french, "antoine")
      choose(lv, "")
      assert correction(french, "antoine") == {nil, false}
    end

    defp pair(lv, play, xml_id) do
      entry =
        play.id
        |> PlayContent.list_cast_lists()
        |> Enum.flat_map(& &1.entries)
        |> Enum.find(&(&1.character && &1.character.xml_id == xml_id))

      if has_element?(lv, "#pair-#{entry.id}"),
        do:
          lv
          |> element("#pair-#{entry.id}")
          |> render()
          |> LazyHTML.from_fragment()
          |> LazyHTML.text()
          |> String.split()
          |> Enum.join(" ")
    end

    test "the list names each character's original, and says which are corrected or unpaired",
         %{conn: conn, french: french} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{french.id}/content")
      assert pair(lv, french, "antoine") == "#{t("Original:")} ANTONY"
      assert pair(lv, french, "cleopatre") == "#{t("Original:")} CLEOPATRA"

      {lv, _} = open_entry(conn, french, "antoine")
      choose(lv, "CLEO")

      assert pair(lv, french, "antoine") == "#{t("Original:")} CLEOPATRA #{t("corrected")}"
      assert pair(lv, french, "cleopatre") == t("No original found")

      {lv, _} = open_entry(conn, french, "cleopatre")
      choose(lv, "-")
      assert pair(lv, french, "cleopatre") == "#{t("No original")} #{t("corrected")}"
    end

    test "an original's list names no pairs", %{conn: conn, original: original} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{original.id}/content")
      assert pair(lv, original, "ANT") == nil
    end

    test "the rule's pick keeps the other characters' corrections", %{conn: conn, french: french} do
      antoine = Enum.find(PlayContent.list_characters(french.id), &(&1.xml_id == "antoine"))
      {:ok, _} = PlayContent.update_character(antoine, %{original_xml_id: "CLEO"})
      {lv, _} = open_entry(conn, french, "cleopatre")

      # Antoine holds CLEOPATRA; ANTONY, all the rule is left, is no match for Cléopâtre.
      assert hd(options(lv)) == t("Automatic (none found)")
    end

    test "offers only the original's characters who speak, the ones a comparison pairs",
         %{conn: conn, original: original, french: french} do
      {:ok, _} =
        PlayContent.create_character(%{play_id: original.id, xml_id: "MUTE", name: "A MUTE"})

      {lv, _} = open_entry(conn, french, "antoine")

      refute "A MUTE" in options(lv)
    end

    test "refuses a character the original does not have", %{conn: conn, french: french} do
      {lv, _} = open_entry(conn, french, "antoine")

      # Posted by hand: the select offers no such value.
      html =
        render_submit(lv, "save_form", %{
          "entry" => %{"name" => "ANTOINE"},
          "character" => %{"original" => "GONE"}
        })

      assert html =~ t("is no character of the original")
      assert correction(french, "antoine") == {nil, false}
    end

    test "shows a pointer the original no longer has as missing", %{conn: conn, french: french} do
      character = Enum.find(PlayContent.list_characters(french.id), &(&1.xml_id == "antoine"))
      {:ok, _} = PlayContent.update_character(character, %{original_xml_id: "GONE"})
      {lv, _} = open_entry(conn, french, "antoine")

      assert lv
             |> element("#entry-form select[name='character[original]'] option[selected]")
             |> render() =~ t("Missing: %{id}", id: "GONE")
    end

    test "an original and an adaptation have no such choice",
         %{conn: conn, original: original} do
      %{french: adaptation} = split_speech_editions("adaptacion")

      for {play, xml_id} <- [{original, "ANT"}, {adaptation, "antoine"}] do
        {lv, _} = open_entry(conn, play, xml_id)
        refute has_element?(lv, "#entry-form select[name='character[original]']")
      end
    end
  end
end
