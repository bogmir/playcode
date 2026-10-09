defmodule PlaycodeWeb.Admin.PlayNotesLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers
  import Playcode.TestFixtures

  alias Playcode.PlayContent

  setup %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <div2 type="escena" n="1"><head>Escena 1</head>
              <sp><speaker>ANA<note n="1" type="falta_tipo"><p>La dama.</p></note></speaker>
                <l n="12">Nous voyent<note n="2" type="traductor"><term>voyent</term><p>Forma arcaica.</p><p>Dos sílabas.</p></note> dans la ville</l>
                <l n="13">Ni un ratón se ha movido.<note n="3" type="editor"><p>Expresión de soldado, según Moratín.</p></note></l>
              </sp>
            </div2>
          </div1>
          """
        )
      )

    {:ok, view, _html} =
      conn
      |> log_in_user(user_fixture(role: :researcher))
      |> live(~p"/admin/plays/#{play.id}/notes")

    [ana, voyent, movido] = notes(play)
    %{play: play, view: view, ana: ana, voyent: voyent, movido: movido}
  end

  # The play's notes in reading order, as the public page numbers them.
  defp notes(play) do
    play.id
    |> PlayContent.load_play_content()
    |> Playcode.PlayContent.Note.reading_order()
  end

  defp doc(view), do: view |> render() |> LazyHTML.from_fragment()

  defp texts(view, selector),
    do:
      view
      |> doc()
      |> LazyHTML.query(selector)
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()))

  defp rows(view), do: view |> doc() |> LazyHTML.query("#notes li") |> LazyHTML.attribute("id")

  defp row(note), do: "note-#{note.id}"

  test "the play has a Notes tab beside Content", %{conn: conn, play: play} do
    {:ok, view, _html} =
      conn
      |> log_in_user(user_fixture(role: :researcher))
      |> live(~p"/admin/plays/#{play.id}/content")

    assert has_element?(view, ~s(a[href="/admin/plays/#{play.id}/notes"]), t("Notes"))
  end

  test "lists each note in reading order: number, type, word, place, context and text", %{
    view: view,
    ana: ana,
    voyent: voyent,
    movido: movido
  } do
    assert rows(view) == [row(ana), row(voyent), row(movido)]

    assert texts(view, "##{row(voyent)} .note-number") == ["2"]
    assert texts(view, "##{row(voyent)} .note-type") == [t("Translator's note")]
    assert texts(view, "##{row(voyent)} .note-glossed") == ["voyent"]

    assert texts(view, "##{row(voyent)} .note-where") == [
             "Acto I, Escena 1, #{t("line %{n}", n: 12)}"
           ]

    # The text it hangs on, the note's number where the note is.
    assert texts(view, "##{row(voyent)} .note-context") == ["Nous voyent2 dans la ville"]
    assert texts(view, "##{row(voyent)} .note-body p") == ["Forma arcaica.", "Dos sílabas."]

    # A type with no label of its own reads as a plain note.
    assert texts(view, "##{row(ana)} .note-type") == [t("Note")]
  end

  test "filters by type, by words of the text or term, and to notes without a term", %{
    view: view,
    ana: ana,
    voyent: voyent,
    movido: movido
  } do
    view |> form("#notes-filter", filter: %{type: "traductor"}) |> render_change()
    assert rows(view) == [row(voyent)]
    assert texts(view, "#notes-count") == [t("%{shown} of %{total} notes", shown: 1, total: 3)]

    # Accents and case do not matter.
    view |> form("#notes-filter", filter: %{type: "", q: "MORATIN"}) |> render_change()
    assert rows(view) == [row(movido)]

    view |> form("#notes-filter", filter: %{q: "", no_term: "true"}) |> render_change()
    assert rows(view) == [row(ana), row(movido)]

    view |> form("#notes-filter", filter: %{no_term: "false"}) |> render_change()
    assert rows(view) == [row(ana), row(voyent), row(movido)]
  end

  test "edits a note where it is listed: its type, word, term and text", %{
    view: view,
    play: play,
    movido: movido
  } do
    view |> element("##{row(movido)} button", t("Edit")) |> render_click()

    view
    |> form("#note-form",
      note: %{
        type: "autor",
        offset: String.length("Ni un ratón"),
        term: "ratón",
        body: "Nuevo texto.\n\nSegundo párrafo."
      }
    )
    |> render_submit()

    saved = PlayContent.get_note(play.id, movido.id)
    assert {saved.type, saved.offset, saved.term} == {"autor", 11, "ratón"}
    assert saved.body == "Nuevo texto.\n\nSegundo párrafo."

    refute has_element?(view, "#note-form")
    assert texts(view, "##{row(movido)} .note-body p") == ["Nuevo texto.", "Segundo párrafo."]
    assert texts(view, "##{row(movido)} .note-context") == ["Ni un ratón3 se ha movido."]
    assert render(view) =~ t("Note saved.")
  end

  test "keeps a type the select does not list when only the text changes", %{
    view: view,
    play: play,
    ana: ana
  } do
    view |> element("##{row(ana)} button", t("Edit")) |> render_click()
    view |> form("#note-form", note: %{body: "Otra glosa."}) |> render_submit()

    saved = PlayContent.get_note(play.id, ana.id)
    assert {saved.type, saved.body} == {"falta_tipo", "Otra glosa."}
  end

  test "cancelling leaves the note as it was", %{view: view, play: play, voyent: voyent} do
    view |> element("##{row(voyent)} button", t("Edit")) |> render_click()
    view |> element("#note-form button", t("Cancel")) |> render_click()

    refute has_element?(view, "#note-form")
    assert PlayContent.get_note(play.id, voyent.id).body == voyent.body
  end

  test "deletes a note", %{view: view, play: play, voyent: voyent} do
    view |> element("##{row(voyent)} button", t("Delete")) |> render_click()

    refute has_element?(view, "##{row(voyent)}")
    assert PlayContent.get_note(play.id, voyent.id) == nil
  end

  test "an id that is not one of the play's notes changes nothing and says so", %{
    view: view,
    voyent: voyent
  } do
    other =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>B</speaker><l n="1">otro<note n="1"><p>Ajena.</p></note></l></sp></div1>)
        )
      )

    [foreign] = notes(other)

    for id <- [foreign.id, Ecto.UUID.generate(), "not-a-uuid"] do
      render_click(view, "edit", %{"id" => id})
      refute has_element?(view, "#note-form")
      assert render(view) =~ t("That item no longer exists. The list has been refreshed.")

      render_click(view, "delete", %{"id" => id})
    end

    assert PlayContent.get_note(other.id, foreign.id).body == foreign.body
    assert has_element?(view, "##{row(voyent)}")
  end

  test "follows edits made elsewhere, keeping an open form", %{
    view: view,
    play: play,
    voyent: voyent,
    movido: movido
  } do
    view |> element("##{row(voyent)} button", t("Edit")) |> render_click()

    {:ok, _} = PlayContent.update_note(movido, %{body: "Cambiada en otra pestaña."})
    send(view.pid, {:play_content_changed, play.id})

    assert texts(view, "##{row(movido)} .note-body p") == ["Cambiada en otra pestaña."]
    assert has_element?(view, "#note-form")
  end

  test "opens the line in Content, where notes are added", %{
    conn: conn,
    view: view,
    play: play,
    movido: movido
  } do
    [href] =
      view
      |> doc()
      |> LazyHTML.query("##{row(movido)} a")
      |> Enum.filter(&(LazyHTML.text(&1) =~ t("Open in Content")))
      |> Enum.flat_map(&LazyHTML.attribute(&1, "href"))

    assert href == "/admin/plays/#{play.id}/content?element=#{movido.element_id}"

    {:ok, content, _html} =
      conn |> log_in_user(user_fixture(role: :researcher)) |> live(href)

    assert content
           |> element(~s(#content-modal section[aria-label="#{t("Notes")}"]))
           |> render() =~ "Moratín"
  end

  test "a play without notes says where to add them", %{conn: conn} do
    play = play_fixture()

    {:ok, _view, html} =
      conn
      |> log_in_user(user_fixture(role: :researcher))
      |> live(~p"/admin/plays/#{play.id}/notes")

    assert html =~ t("No notes yet. Add them to a line in Content.")
  end
end
