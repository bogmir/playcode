defmodule PlaycodeWeb.Admin.PlayEditorsLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp translators(play), do: xml_texts(export_tei(play), "editor", within: "titleStmt")

  test "an editor added, renamed and removed here is what the play's TEI credits",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/editors")

    lv |> element("button", t("Add editor")) |> render_click()

    lv
    |> form("#editor-form",
      play_editor: %{"person_name" => "Sanderson, John D.", "role" => "translator"}
    )
    |> render_submit()

    assert translators(play) == ["Sanderson, John D."]

    [editor] = Playcode.Catalogue.get_play_with_all!(play.id).editors
    lv |> element("#editor-#{editor.id} button", t("Edit")) |> render_click()

    lv
    |> form("#editor-form", play_editor: %{"person_name" => "Sanderson, J. D."})
    |> render_submit()

    assert translators(play) == ["Sanderson, J. D."]

    lv |> element("#editor-#{editor.id} button", t("Delete")) |> render_click()
    assert translators(play) == []
  end

  test "a critical edition's editor added here is credited as edicion_critica",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/editors")
    lv |> element("button", t("Add editor")) |> render_click()

    lv
    |> form("#editor-form",
      play_editor: %{
        "person_name" => "Durá Celma, Rosa",
        "role" => "critical_editor",
        "organization" => "Grupo DICAT"
      }
    )
    |> render_submit()

    [editor] = Playcode.Catalogue.get_play_with_all!(play.id).editors
    assert lv |> element("#editor-#{editor.id}") |> render() =~ t("Critical edition editor")

    assert [{%{"role" => "edicion_critica"}, "Durá Celma, Rosa Grupo DICAT"}] =
             xml_elements(export_tei(play), "editor", within: "titleStmt")
  end

  test "a nameless editor is refused", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/editors")
    lv |> element("button", t("Add editor")) |> render_click()

    html =
      lv
      |> form("#editor-form", play_editor: %{"person_name" => "", "role" => "translator"})
      |> render_submit()

    assert html =~ Gettext.dgettext(PlaycodeWeb.Gettext, "errors", "can't be blank")
    assert Playcode.Catalogue.get_play_with_all!(play.id).editors == []
  end

  # An event names its editor by an id from the browser: another play's, one already
  # deleted, or not an id at all. None may change anything or crash the page; each says
  # so and refreshes the list.
  test "an editor that is not this play's is neither edited nor deleted",
       %{conn: conn, play: play} do
    {:ok, theirs} =
      Playcode.Catalogue.create_play_editor(%{
        "play_id" => play_fixture().id,
        "person_name" => "Ajeno, A.",
        "role" => "translator"
      })

    for event <- ["edit_editor", "delete_editor"],
        id <- [theirs.id, Ecto.UUID.generate(), "not-an-id"] do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/editors")

      assert render_click(lv, event, %{"id" => id}) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"

      refute has_element?(lv, "#editor-form")
    end

    assert [%{person_name: "Ajeno, A."}] = Playcode.Catalogue.list_play_editors(theirs.play_id)
  end
end
