defmodule PlaycodeWeb.Admin.PlayFormLiveTest do
  # form/3 fails when a field is missing from the page, so every test here also checks
  # that the inputs it fills are really on the form.
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  import Playcode.ImportHelpers,
    only: [
      export_tei: 1,
      import_tei!: 1,
      tei: 1,
      write_tmp!: 1,
      xml_apps: 1,
      xml_texts: 2,
      xml_texts: 3
    ]

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher))}
  end

  defp error(msg), do: Gettext.dgettext(PlaycodeWeb.Gettext, "errors", msg)

  defp save(view, fields), do: view |> form("#play-form", play: fields) |> render_submit()

  test "a new play is saved and opens on its detail page", %{conn: conn} do
    code = "FORM#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

    save(view, %{"title" => "BDD Play", "code" => code, "author_name" => "Behavior Author"})

    created = Catalogue.get_play_by_code!(code)
    assert created.author_name == "Behavior Author"
    assert_redirect(view, ~p"/admin/plays/#{created.id}")
  end

  # The header FileMaker writes into every file, with today's funding project first
  # (EMOTHE0753 was corrected by hand the same way) and Playcode credited for the files.
  test "a new play starts with the project's header texts", %{conn: conn} do
    code = "EMOTHE#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")
    save(view, %{"title" => "Sémiramis", "code" => code})

    xml = code |> Catalogue.get_play_by_code!() |> export_tei()

    assert [blurb, credit] = xml_texts(xml, "p", within: "projectDesc")
    assert blurb =~ "La Biblioteca Digital EMOTHE (antes denominada Colección de Textos"
    assert credit =~ ~r/^Bogdan Mircea .* Playcode, .* paralelo/
    assert [funder] = xml_texts(xml, "funder")
    assert funder =~ ~r/^Ministerio .* PID2022-136431NB-C65; .* FFI2009-12730/

    assert xml_texts(xml, "sponsor") == [
             "Plan Nacional de Investigación Científica, Desarrollo e Innovación Tecnológica (Plan Nacional de I+D+i)"
           ]

    assert xml_texts(xml, "publisher") == ["ARTELOPE/EMOTHE Universitat de València"]

    assert xml_texts(xml, "authority") == [
             "Universitat de València - Estudi General. http://www.uv.es"
           ]

    assert xml_texts(xml, "pubPlace", within: "publicationStmt") == ["Valencia"]
  end

  # The header texts fill a new play's form once; a researcher who empties one means it.
  test "a header text emptied in a new play's form stays empty", %{conn: conn} do
    code = "EMOTHE#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")
    view |> form("#play-form", play: %{"funder" => ""}) |> render_change()
    save(view, %{"title" => "Sémiramis", "code" => code})

    assert code |> Catalogue.get_play_by_code!() |> export_tei() |> xml_texts("funder") == []
  end

  test "a code typed in a new play's form fills the header texts left blank", %{conn: conn} do
    code = "AL#{System.unique_integer([:positive])}"
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")
    view |> form("#play-form", play: %{"project_description" => ""}) |> render_change()

    view
    |> form("#play-form", play: %{"code" => code})
    |> render_change(%{"_target" => ["play", "code"]})

    save(view, %{"title" => "La discreta enamorada"})

    assert [description] =
             code
             |> Catalogue.get_play_by_code!()
             |> export_tei()
             |> xml_texts("p", within: "projectDesc")

    assert description =~ "El proyecto Artelope"
  end

  # A TEI file names a translation's original by its short code; a play imported before
  # its original waits for it, and the original may well be typed in by hand.
  defp waiting_translation(original_code) do
    import_tei!(
      tei(
        title_stmt: ~s(<title type="traduccion">Los amores</title>),
        file_desc:
          ~s(<notesStmt><relatedItem type="original" target="#{original_code}"/></notesStmt>)
      )
    )
  end

  test "a new play is the original a waiting translation named", %{conn: conn} do
    n = System.unique_integer([:positive])
    translation = waiting_translation("FO#{n}")
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

    save(view, %{"title" => "Pyrame", "code" => "FO#{n}_Pyrame"})

    original = Catalogue.get_play_by_code!("FO#{n}_Pyrame")
    assert Catalogue.get_play!(translation.id).parent_play_id == original.id
  end

  test "an original picked by hand stays when the one the file named arrives",
       %{conn: conn} do
    n = System.unique_integer([:positive])
    translation = waiting_translation("FO#{n}")
    chosen = play_fixture(%{"title" => "Chosen"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{translation.id}/edit")

    render_click(view, "pick_parent", %{"id" => chosen.id, "label" => chosen.title})
    save(view, %{"title" => translation.title})
    import_tei!(tei(code: "FO#{n}_Pyrame"))

    assert Catalogue.get_play!(translation.id).parent_play_id == chosen.id
  end

  test "a play without a title is not saved, and the form says why", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")

    html = save(view, %{"title" => "", "code" => ""})

    assert html =~ error("can't be blank")
    assert Catalogue.list_plays() == []
  end

  test "an edit is saved", %{conn: conn} do
    play = play_fixture(%{"title" => "Original Title"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{"title" => "Updated Title"})

    assert_redirect(view, ~p"/admin/plays/#{play.id}")
    assert Catalogue.get_play!(play.id).title == "Updated Title"
  end

  # Question 40: what three files call a version is kept as a kind until the project says
  # what it is; then a curator changes it here.
  test "a play's kind can be set to a version", %{conn: conn} do
    play = play_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{"relationship_type" => "version"})

    assert Catalogue.get_play!(play.id).relationship_type == "version"
  end

  test "a play's form can be set by hand, and later edits to its text keep it",
       %{conn: conn} do
    %{play: play, line_group: line_group, scene: scene} = play_with_structure_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{"form" => "prose"})
    assert play.id |> Catalogue.get_play!() |> Play.form() == "prose"

    # The content editor calls refresh_derived/1 after every edit, which recomputes
    # is_verse from the verse lines (this play has some, so automatic says "verse");
    # the curator's choice stands.
    {:ok, _} =
      Playcode.PlayContent.create_element(%{
        play_id: play.id,
        division_id: scene.id,
        parent_id: line_group.id,
        type: "verse_line",
        content: "otro verso",
        line_number: 99,
        position: 99
      })

    Playcode.PlayContent.refresh_derived(play.id)

    recomputed = Catalogue.get_play!(play.id)
    assert recomputed.is_verse
    assert Play.form(recomputed) == "prose"
  end

  test "left automatic, the form follows the text", %{conn: conn} do
    %{play: play} = play_with_structure_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{"form" => "prose"})
    assert play.id |> Catalogue.get_play!() |> Play.form() == "prose"

    # A save redirects away from the form, so open it again. "" is the select's Automatic
    # option: it clears the earlier override.
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
    save(view, %{"form" => ""})

    saved = Catalogue.get_play!(play.id)
    assert saved.form == nil
    assert Play.form(saved) == "verse"
  end

  test "the research metadata is saved: historical time and composition date",
       %{conn: conn} do
    play = play_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{
      "historical_time" => "siglo_xvii",
      "historical_time_note" => "Contemporary. Reign of Philip IV.",
      "composition_date_from" => "1606",
      "composition_date_to" => "1607",
      "composition_date_note" => "1606; 1607"
    })

    saved = Catalogue.get_play!(play.id)

    assert {saved.historical_time, saved.historical_time_note} ==
             {"siglo_xvii", "Contemporary. Reign of Philip IV."}

    assert {saved.composition_date_from, saved.composition_date_to, saved.composition_date_note} ==
             {1606, 1607, "1606; 1607"}
  end

  # One box per note and an empty one for a new note; a note emptied is removed.
  test "the notes on the edition are changed, removed and added", %{conn: conn} do
    play =
      import_tei!(
        tei(file_desc: "<notesStmt><note>Primera.</note><note>Segunda.</note></notesStmt>")
      )

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    save(view, %{"edition_notes" => ["Primera, corregida.", "", "Tercera.\r\nOtra línea."]})

    assert Catalogue.get_play!(play.id).edition_notes ==
             ["Primera, corregida.", "Tercera.\nOtra línea."]
  end

  test "while typing, a new note adds one empty box and an emptied one keeps its box",
       %{conn: conn} do
    play = import_tei!(tei(file_desc: "<notesStmt><note>Primera.</note></notesStmt>"))
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
    boxes = fn -> Enum.count(0..3, &has_element?(view, "#play_edition_notes_#{&1}")) end

    assert boxes.() == 2

    # The browser sends every box, the new empty one too.
    for typed <- ["N", "Nu", "Nueva"] do
      view
      |> form("#play-form", play: %{"edition_notes" => ["Primera.", typed, ""]})
      |> render_change()

      assert boxes.() == 3
    end

    view |> form("#play-form", play: %{"edition_notes" => ["", ""]}) |> render_change()
    assert boxes.() == 2

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play_fixture().id}/edit")
    assert has_element?(view, "#play_edition_notes_0")
    refute has_element?(view, "#play_edition_notes_1")
  end

  defp revisions(play) do
    play.id
    |> Catalogue.get_play!()
    |> Map.fetch!(:revisions)
    |> Enum.map(&{&1.date, &1.people, &1.description, &1.note})
  end

  defp history_play do
    import_tei!(
      tei(
        revision_desc: """
        <change><date>2021</date> <persName>Muñoz Pons, Carlos</persName> Revisión</change>
        <change><date>2016</date></change>
        """
      )
    )
  end

  # A row per change, "Add change" for a new one and Remove for one to go, as a variant's
  # readings are edited; a row left empty is no change.
  test "the revision history is changed, a change removed and one added", %{conn: conn} do
    play = history_play()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    view |> form("#play-form") |> render_change(%{play: %{"revisions_delete" => ["0"]}})
    view |> form("#play-form") |> render_change(%{play: %{"revisions_order" => ["0", "new"]}})

    view
    |> form("#play-form")
    |> render_change(%{play: %{"revisions_order" => ["0", "1", "new"]}})

    save(view, %{
      "revisions" => %{
        "0" => %{"people" => "Muñoz Pons, Carlos; Tronch Pérez, Jesús"},
        "1" => %{"date" => "2026", "people" => "Mircea, Bogdan", "note" => "Acotaciones."}
      }
    })

    assert revisions(play) == [
             {"2016", "Muñoz Pons, Carlos; Tronch Pérez, Jesús", nil, nil},
             {"2026", "Mircea, Bogdan", nil, "Acotaciones."}
           ]
  end

  # Found by the review of 2026-10-18: blank rows were dropped while typing, so the rows
  # after one being emptied moved up under the editor's cursor.
  test "a change emptied while typing keeps the rows where they are, and goes on saving",
       %{conn: conn} do
    play = history_play()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
    blank = %{"date" => "", "people" => "", "description" => "", "note" => ""}

    view |> form("#play-form", play: %{"revisions" => %{"0" => blank}}) |> render_change()
    assert has_element?(view, ~s(#play_revisions_1_date[value="2016"]))

    save(view, %{"revisions" => %{"0" => blank}})
    assert revisions(play) == [{"2016", nil, nil, nil}]
  end

  # Found by the review of 2026-10-18: a copy button rebuilt the form from the changeset,
  # the revision history with it, and crashed the page.
  test "a copy button keeps the revision history", %{conn: conn} do
    play = history_play()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    render_click(view, "copy_field", %{"source" => "title", "target" => "original_title"})
    save(view, %{})

    assert Catalogue.get_play!(play.id).original_title == play.title

    assert revisions(play) == [
             {"2021", "Muñoz Pons, Carlos", "Revisión", nil},
             {"2016", nil, nil, nil}
           ]

    {:ok, view, _html} = live(conn, ~p"/admin/plays/new")
    assert render_click(view, "copy_field", %{"source" => "title", "target" => "title_sort"})
  end

  test "half a composition date is refused", %{conn: conn} do
    play = play_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    html = save(view, %{"composition_date_from" => "1606"})

    assert html =~ error("must be given together with the end year")
    assert Catalogue.get_play!(play.id).composition_date_from == nil
  end

  # Hamlet's apparatus is unfinished (question 2): its variants are hidden from readers
  # until its editor has finished, and the file still carries them.
  test "Show variant readings off hides the variants from readers, never from the file",
       %{conn: conn} do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<app n="1"><rdg wit="#B">dos</rdg></app> tres</l></sp></div1>)
      )
      |> import_tei!()
      |> Playcode.TestFixtures.mark_complete!()

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
    save(view, %{"show_variants" => "false"})

    hidden? = fn ->
      {:ok, page, _html} = live(build_conn(), ~p"/plays/#{play.code}")

      not has_element?(page, ~s(button[aria-label^="#{t("Textual variant")}"])) and
        not has_element?(page, "label", t("Variants"))
    end

    assert hidden?.()
    assert [%{n: "1"}] = xml_apps(export_tei(play))

    # A re-import of its file leaves the setting as the curator left it.
    {:ok, _} = play |> export_tei() |> write_tmp!() |> Playcode.Import.TeiImport.import_file()
    assert hidden?.()
  end
end
