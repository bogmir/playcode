defmodule PlaycodeWeb.Admin.PlayWitnessesLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.Witnesses

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp sigla(play),
    do: for({attrs, _} <- xml_elements(export_tei(play), "witness"), do: attrs["n"])

  defp button(lv, witness, label),
    do: element(lv, "#witness-#{witness.id} button[aria-label='#{t(label)}']")

  defp add(lv, attrs) do
    lv |> element("button", t("Add witness")) |> render_click()
    lv |> form("#witness-form", witness: attrs) |> render_submit()
  end

  test "a witness added, moved, corrected and deleted here is what the play's TEI lists",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/witnesses")

    add(lv, %{"siglum" => "M", "title" => "El conde de Sex", "witness_type" => "copy"})
    add(lv, %{"siglum" => "S", "title" => "Parte treynta y una", "date" => "1638"})
    assert sigla(play) == ["M", "S"]

    [m, s] = Witnesses.list_for_play(play.id)
    lv |> button(s, "Move up") |> render_click()
    assert sigla(play) == ["S", "M"]

    lv |> button(m, "Edit") |> render_click()
    lv |> form("#witness-form", witness: %{"date" => "s. a."}) |> render_submit()
    assert xml_texts(export_tei(play), "date", within: "witness") == ["1638", "s. a."]

    lv |> button(s, "Delete") |> render_click()
    assert sigla(play) == ["M"]
  end

  test "the form shows the line as it will print, and says what is missing",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/witnesses")
    lv |> element("button", t("Add witness")) |> render_click()

    lv
    |> form("#witness-form", witness: %{"title" => "El conde de Sex", "shelfmark" => "16722"})
    |> render_change()

    assert lv |> element("#witness-preview") |> render() =~
             "<em>El conde de Sex</em>. Archivo: 16722."

    html =
      lv
      |> form("#witness-form", witness: %{"title" => "", "shelfmark" => "16722"})
      |> render_submit()

    assert html =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "needs a title, a normalised title or a note"
             )

    assert Witnesses.list_for_play(play.id) == []
  end

  # As for sources: an id from the browser that is not this play's witness changes
  # nothing, crashes nothing, and says so.
  test "a witness that is not this play's is neither edited, moved nor deleted",
       %{conn: conn, play: play} do
    {:ok, theirs} =
      Witnesses.create_witness(%{"play_id" => play_fixture().id, "title" => "Ajeno"})

    for event <- ~w(edit_witness move_up move_down delete_witness),
        id <- [theirs.id, Ecto.UUID.generate(), "not-an-id"] do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/witnesses")

      assert render_click(lv, event, %{"id" => id}) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"

      refute has_element?(lv, "#witness-form")
    end

    assert [%{title: "Ajeno"}] = Witnesses.list_for_play(theirs.play_id)
  end
end
