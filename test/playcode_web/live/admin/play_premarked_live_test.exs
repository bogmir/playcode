defmodule PlaycodeWeb.Admin.PlayPremarkedLiveTest do
  @moduledoc """
  /admin/plays/:id/premarked: a premarked text pasted or dropped as a .docx, the play it
  would make shown beside it, and the import. The draft itself is word_draft_test.exs's.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.{Catalogue, PlayContent}
  alias Playcode.Import.WordParser

  @ejercicio "test/fixtures/word_files/ejercicio.docx"

  @every_kind [
    "{e}Escena 1",
    "{p}FEBO {v}Uno.",
    "{R}Vase.",
    "{pr} FEBO {pr}¡Qué pronto!",
    "{p}RICARDO {tf}¿No lo ves?",
    "Nota {p}FEBO {v}Dos.",
    "{p}FEBO {pr}Hola ((aparte sin cerrar",
    "OBSERVACIONES:",
    "{p}RICARDO {ti}pues ¿qué te aflige?",
    "{e}THE END"
  ]

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp ejercicio_text do
    {:ok, paragraphs} = WordParser.paragraphs(@ejercicio)
    Enum.join(paragraphs, "\n")
  end

  defp paste(lv, text), do: lv |> form("#premarked-form", text: text) |> render_change()

  defp stored(play), do: PlayContent.load_play_content(play.id)

  test "pasting text shows the play as it would be stored, and stores nothing",
       %{conn: conn, play: play} do
    before = stored(play)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")

    paste(lv, ejercicio_text())

    assert has_element?(lv, "#premarked-preview", "Será remedio casarte.")
    assert has_element?(lv, "#premarked-preview .speaker", "FEBO")
    assert has_element?(lv, "#premarked-summary", "RICARDO")
    assert stored(play) == before
  end

  test "a clean text shows no warnings", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    paste(lv, ejercicio_text())

    refute has_element?(lv, "#premarked-warnings button")
    assert has_element?(lv, "#premarked-warnings", t("No warnings."))
  end

  test "a text with every kind of warning shows each, tied to its line", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    paste(lv, Enum.join(@every_kind, "\n"))

    for line <- [2, 3, 4, 5, 6, 7, 8, 9] do
      assert has_element?(lv, "#premarked-warnings button[data-line='#{line}']")
    end

    assert has_element?(lv, "#premarked-preview [data-line='7'][data-warn]")
    refute has_element?(lv, "#premarked-preview [data-line='1'][data-warn]")
  end

  test "dropping the .docx fills the text box and the preview", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")

    lv
    |> file_input("#premarked-upload", :docx, [
      %{
        name: "ejercicio.docx",
        content: File.read!(@ejercicio),
        type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      }
    ])
    |> render_upload("ejercicio.docx")

    assert has_element?(lv, "#premarked-text", "{e}Escena 1")
    assert has_element?(lv, "#premarked-preview", "Será remedio casarte.")
  end

  test "import replaces the text and returns to the play", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    paste(lv, ejercicio_text())

    lv |> form("#premarked-form", text: ejercicio_text()) |> render_submit()
    assert_push_event(lv, "premarked:clear", %{})

    flash = assert_redirect(lv, ~p"/admin/plays/#{play.id}")
    assert flash["info"] == t("Content imported successfully.")

    {:ok, public, html} = live(conn, ~p"/plays/#{play.code}")
    assert html =~ "Entran Febo y Ricardo."
    assert has_element?(public, ".cast-list", "FEBO")
    assert has_element?(public, ".cast-list", "RICARDO")
  end

  test "an unrecognised line is imported, for review in the content editor",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    text = "PROLOGUE\n{e}Escena 1\n{p}FEBO  {v}Hello.\nTHE SCENE: SMITHFIELD"
    paste(lv, text)
    lv |> form("#premarked-form", text: text) |> render_submit()

    {:ok, editor, _html} = live(conn, ~p"/admin/plays/#{play.id}/content")
    editor |> element("nav[aria-label='Editor tabs'] button", t("Structure")) |> render_click()

    assert editor |> element("button", "Escena 1") |> render_click() =~ "THE SCENE: SMITHFIELD"
  end

  test "the .docx is dropped on a zone named in the page's language", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    assert has_element?(lv, "#premarked-upload label", t("Or drop the premarked .docx here"))
  end

  test "a submitted text is read again on the server", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    paste(lv, "{e}Escena 1\n{p}FEBO {v}Lo que se previó.")

    lv
    |> form("#premarked-form", text: "{e}Escena 1\n{p}FEBO {v}Lo que se envió.")
    |> render_submit()

    {:ok, _public, html} = live(conn, ~p"/plays/#{play.code}")
    assert html =~ "Lo que se envió."
    refute html =~ "Lo que se previó."
  end

  test "a line the database refuses is an error and disables the import",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    paste(lv, "{e}Escena 1\n{p}FEBO {v}Uno <stage>dos.")

    assert has_element?(lv, "#premarked-errors button[data-line='1']")
    assert has_element?(lv, "#premarked-import[disabled]")
  end

  test "an empty text shows no preview and cannot be imported", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/premarked")
    paste(lv, "  \n\n ")

    refute has_element?(lv, "#premarked-preview .speaker")
    assert has_element?(lv, "#premarked-import[disabled]")
  end

  test "a complete play is sent back to its page", %{conn: conn, play: play} do
    {:ok, play} = Catalogue.update_play(play, %{is_complete: true})

    assert {:error, {:live_redirect, %{to: to, flash: flash}}} =
             live(conn, ~p"/admin/plays/#{play.id}/premarked")

    assert to == ~p"/admin/plays/#{play.id}"
    assert flash["error"]
  end

  describe "the play's page" do
    test "links to the premarked page while the play is a draft", %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
      assert has_element?(lv, ~s(a[href="/admin/plays/#{play.id}/premarked"]))
    end

    test "offers no link once the play is complete", %{conn: conn, play: play} do
      {:ok, play} = Catalogue.update_play(play, %{is_complete: true})
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}")
      refute has_element?(lv, ~s(a[href="/admin/plays/#{play.id}/premarked"]))
    end
  end
end
