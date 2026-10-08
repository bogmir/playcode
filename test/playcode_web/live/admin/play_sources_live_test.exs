defmodule PlaycodeWeb.Admin.PlaySourcesLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp bibl(play, tag), do: xml_texts(export_tei(play), tag, within: "bibl")

  test "a source added, corrected and removed here is what the play's TEI cites",
       %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/sources")

    lv |> element("button", t("Add source")) |> render_click()

    lv
    |> form("#source-form",
      play_source: %{
        "title" => "El Rey Lear",
        "author" => "Shakespeare, William",
        "pub_place" => "Barcelona"
      }
    )
    |> render_submit()

    assert {bibl(play, "title"), bibl(play, "author"), bibl(play, "pubPlace")} ==
             {["El Rey Lear"], ["Shakespeare, William"], ["Barcelona"]}

    [source] = Playcode.Catalogue.list_play_sources(play.id)
    lv |> element("#source-#{source.id} button", t("Edit")) |> render_click()
    lv |> form("#source-form", play_source: %{"pub_date" => "1908"}) |> render_submit()

    assert bibl(play, "date") == ["1908"]

    lv |> element("#source-#{source.id} button", t("Delete")) |> render_click()
    assert bibl(play, "title") == []
  end

  # As for editors: an id from the browser that is not this play's source changes
  # nothing, crashes nothing, and says so.
  test "a source that is not this play's is neither edited nor deleted",
       %{conn: conn, play: play} do
    {:ok, theirs} =
      Playcode.Catalogue.create_play_source(%{"play_id" => play_fixture().id, "title" => "Ajena"})

    for event <- ["edit_source", "delete_source"],
        id <- [theirs.id, Ecto.UUID.generate(), "not-an-id"] do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/sources")

      assert render_click(lv, event, %{"id" => id}) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"

      refute has_element?(lv, "#source-form")
    end

    assert [%{title: "Ajena"}] = Playcode.Catalogue.list_play_sources(theirs.play_id)
  end
end
