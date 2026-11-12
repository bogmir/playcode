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
  test "marking a play complete publishes it in the catalogue, and back to draft withdraws it",
       %{conn: conn, play: play} do
    {:ok, catalogue, _html} = live(conn, ~p"/plays")
    refute render(catalogue) =~ play.title

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    assert has_element?(lv, "#play-state", t("Draft"))

    assert has_element?(
             lv,
             "#play-state",
             t("Only the team sees it. It is not on the published site.")
           )

    assert lv |> element("#play-state button", t("Mark as complete")) |> render_click() =~
             t("Marked as complete.")

    assert has_element?(lv, "#play-state", t("Complete"))

    {:ok, _catalogue, html} = live(conn, ~p"/plays")
    assert html =~ play.title

    assert lv |> element("#play-state button", t("Back to draft")) |> render_click() =~
             t("Marked as draft.")

    {:ok, _catalogue, html} = live(conn, ~p"/plays")
    refute html =~ play.title
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

  test "folds the licence with the project's texts", %{conn: conn} do
    play = play_fixture(%{"licence_text" => "CC BY-NC 4.0", "funder" => "Ministerio"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")

    assert has_element?(lv, "details", "CC BY-NC 4.0")
  end
end
