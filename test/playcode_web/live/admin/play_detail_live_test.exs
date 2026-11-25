defmodule PlaycodeWeb.Admin.PlayDetailLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp upload_docx(lv, path) do
    lv
    |> file_input("#docx-upload-form", :docx, [
      %{
        name: Path.basename(path),
        content: File.read!(path),
        type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      }
    ])
    |> render_upload(Path.basename(path))

    lv |> element("#docx-upload-form") |> render_submit()
  end

  describe "importing a premarcado Word file" do
    test "the file is chosen or dropped on a zone named in the page's language",
         %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

      assert has_element?(
               lv,
               "#docx-upload-form label",
               t("Drop the Word file here, or choose it")
             )

      lv
      |> file_input("#docx-upload-form", :docx, [%{name: "acto.docx", content: "x"}])
      |> render_upload("acto.docx")

      assert has_element?(lv, "#docx-upload-form", "acto.docx")
    end

    test "replaces the play's text, which the public page then shows with its cast list",
         %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

      assert upload_docx(lv, "test/fixtures/word_files/ejercicio.docx") =~
               t("Content imported successfully.")

      {:ok, public, html} = live(conn, ~p"/plays/#{play.code}")

      assert html =~ "Entran Febo y Ricardo."
      assert html =~ "Será remedio casarte."
      assert has_element?(public, ".cast-list", "FEBO")
      assert has_element?(public, ".cast-list", "RICARDO")
    end

    test "keeps text it cannot place, for review in the content editor",
         %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

      upload_docx(
        lv,
        docx(["PROLOGUE", "{e}Escena 1", "{p}FEBO  {v}Hello.", "THE SCENE: SMITHFIELD"])
      )

      {:ok, editor, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
      editor |> element("nav[aria-label='Editor tabs'] button", t("Structure")) |> render_click()

      assert editor |> element("button", "Escena 1") |> render_click() =~
               "THE SCENE: SMITHFIELD"
    end
  end

  # The status used to be a Draft/Complete pair of pressed buttons; the overview now says who
  # sees the play, with the one button that changes it.
  # It used to check Playcode's own catalogue too; the published site is the catalogue now,
  # and which plays it takes is static_site_catalogue_test.exs's.
  test "a play without a text offers its TEI file alone, and names no form", %{conn: conn} do
    play = play_without_text_fixture()
    {:ok, view, html} = live(conn, ~p"/admin/plays/#{play.id}")
    assert has_element?(view, ~s(a[href="/admin/plays/#{play.id}/export/tei"]))

    for format <- ~w(html pdf epub),
        do: refute(has_element?(view, ~s(a[href="/admin/plays/#{play.id}/export/#{format}"])))

    refute html =~ t("Prose")
  end

  test "marking a play complete, and back to draft", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    assert has_element?(lv, "#play-state", t("Draft"))

    assert has_element?(lv, "#play-state", t("Not published"))
    assert has_element?(lv, "#play-state", t("Only the team sees it."))

    assert lv |> element("#play-state button", t("Mark as complete")) |> render_click() =~
             t("Marked as complete.")

    assert has_element?(lv, "#play-state", t("Complete"))

    assert lv |> element("#play-state button", t("Back to draft")) |> render_click() =~
             t("Marked as draft.")

    assert has_element?(lv, "#play-state", t("Draft"))
  end

  test "names the play once, its downloads and actions in words", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "h1", play.title)
    assert has_element?(lv, "main p", play.code)

    for format <- ~w(tei html pdf epub),
        do:
          assert(
            has_element?(
              lv,
              "[role=group][aria-label='#{t("Download")}'] a[href='/admin/plays/#{play.id}/export/#{format}']",
              String.upcase(format)
            )
          )

    assert has_element?(lv, "button", t("Validate TEI-XML"))
    assert has_element?(lv, "a[href='/admin/plays/#{play.id}/edit']", t("Edit metadata"))
    refute has_element?(lv, "main a[href='/plays/#{play.code}']")
  end

  test "counts the play's parts, each a link to its section", %{conn: conn, play: play} do
    performance_fixture(play)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "#play-counts a[href='/admin/plays/#{play.id}/performances']", "1")
    assert has_element?(lv, "#play-counts a[href='/admin/plays/#{play.id}/witnesses']", t("add"))
  end

  test "the status message fades by itself; an error stays until it is dismissed",
       %{conn: conn, play: play} do
    # LiveViewTest cannot run the browser timer, so this pins the one thing the server
    # controls: only an info flash carries the hook that dismisses it.
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    refute has_element?(lv, "#flash-info")

    lv |> element("#play-state button", t("Mark as complete")) |> render_click()
    assert has_element?(lv, "#flash-info[phx-hook=AutoDismiss]", t("Marked as complete."))

    error =
      render_component(&PlaycodeWeb.CoreComponents.flash/1,
        kind: :error,
        flash: %{"error" => "Failed"}
      )

    assert error =~ "Failed"
    refute error =~ "AutoDismiss"
  end

  # The file's revision history (revisionDesc), for the people making the edition: readers
  # see none of it.
  test "the play's page says who revised its file and when", %{conn: conn} do
    play =
      import_tei!(
        tei(
          revision_desc: """
          <change><date>2021</date> <persName>Muñoz Pons, Carlos</persName>
            <persName>Tronch Pérez, Jesús</persName> Revisión de la obra en formato <emph>TEI-XML</emph></change>
          <change><note>Con correcciones a cargo de Guillermo Carrascón.</note><date>2025</date></change>
          """
        )
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(
             lv,
             "#revisions li",
             "2021 · Muñoz Pons, Carlos; Tronch Pérez, Jesús · Revisión de la obra en formato TEI-XML"
           )

    assert has_element?(
             lv,
             "#revisions li",
             "2025 · Con correcciones a cargo de Guillermo Carrascón."
           )
  end

  test "names the top divisions as the play does", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="jornada" n="1"><head>Jornada primera</head>
            <sp who="#a"><speaker>A</speaker><l n="1">Uno</l></sp></div1>
          <div1 type="jornada" n="2"><head>Jornada segunda</head>
            <sp who="#a"><speaker>A</speaker><l n="2">Dos</l></sp></div1>
          """
        )
      )

    Playcode.Statistics.recompute(play.id)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "#play-counts a", String.downcase(t("Jornadas")))
  end

  test "the structure gives each act its verses, its scenes' included", %{conn: conn} do
    play = import_tei!(tei(body: mixed_play()))
    Playcode.Statistics.recompute(play.id)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "li", "Acto I · " <> n("%{count} verse", "%{count} verses", 2))
    assert has_element?(lv, "li", "Acto II · " <> n("%{count} verse", "%{count} verses", 1))
  end

  test "the structure prints a heading's italics as italics, not as markers", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="act" n="1"><head>Acto de <emph>La Celestina</emph></head>
            <sp who="#a"><speaker>A</speaker><l n="1">Uno</l></sp></div1>
          """
        )
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "li em", "La Celestina")
    refute render(lv) =~ "&lt;&lt;La Celestina"
  end

  test "the structure names an act with no heading by its kind and number", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="act" n="2">
            <sp who="#a"><speaker>A</speaker><l n="1">Uno</l></sp></div1>
          """
        )
      )

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "li", t("Act") <> " 2")
  end

  test "folds the licence with the project's texts", %{conn: conn} do
    play = play_fixture(%{"licence_text" => "CC BY-NC 4.0", "funder" => "Ministerio"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "details", "CC BY-NC 4.0")
  end

  describe "the work relationship" do
    setup do
      original =
        play_fixture(%{
          "title" => "El burlador de Sevilla",
          "code" => "EMOTHE0201_Burlador",
          "author_name" => "Tirso de Molina"
        })

      kin = fn title, kind, language ->
        play_fixture(%{
          "title" => title,
          "title_sort" => title,
          "parent_play_id" => original.id,
          "relationship_type" => kind,
          "language" => language
        })
      end

      %{
        original: original,
        abuseur: kin.("L'abuseur de Sevilla", "traduccion", "fr"),
        trickster: kin.("Trickster of Seville", "traduccion", "en"),
        adaptation: kin.("A burlador adapted", "adaptacion", "es")
      }
    end

    defp family(lv),
      do:
        lv
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#work-relationship details li a")
        |> Enum.map(&LazyHTML.text/1)
        |> Enum.map(&String.trim/1)

    test "a translation names its original first, then folds the rest of its family",
         %{conn: conn, abuseur: abuseur, original: original} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{abuseur.id}")

      assert has_element?(lv, "#work-relationship .badge", t("Translation"))
      assert has_element?(lv, "#work-relationship", t("into French"))

      assert has_element?(
               lv,
               "#work-relationship a[href='/admin/plays/#{original.id}']",
               "El burlador de Sevilla"
             )

      assert has_element?(lv, "#work-relationship", "Tirso de Molina")

      assert has_element?(
               lv,
               "#work-relationship summary",
               t("The rest of its family (%{count})", count: 2)
             )

      assert family(lv) == ["Trickster of Seville", "A burlador adapted"]
    end

    test "a play in its original's language is not said to go into it",
         %{conn: conn, adaptation: adaptation} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{adaptation.id}")

      assert has_element?(lv, "#work-relationship", t("Adaptation"))
      refute has_element?(lv, "#work-relationship", t("into Spanish"))
    end

    test "an original counts its derived plays by kind and lists them by kind, then language",
         %{conn: conn, original: original} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{original.id}")

      kinds =
        n("%{count} translation", "%{count} translations", 2) <>
          " · " <> n("%{count} adaptation", "%{count} adaptations", 1)

      assert has_element?(
               lv,
               "#work-relationship",
               n(
                 "Original of %{count} play: %{kinds}.",
                 "Original of %{count} plays: %{kinds}.",
                 3,
                 kinds: kinds
               )
             )

      assert family(lv) == ["Trickster of Seville", "L'abuseur de Sevilla", "A burlador adapted"]
    end
  end

  test "archiving is the last thing on the overview, and sends the user to the list",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "main button[data-confirm]", t("Archive play"))

    lv |> element("button", t("Archive play")) |> render_click()
    assert_redirect(lv, ~p"/admin/plays")
    assert Playcode.Catalogue.get_play!(play.id, include_deleted: true).deleted_at
  end
end
