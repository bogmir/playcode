defmodule PlaycodeWeb.Admin.PlayTabsTest do
  @moduledoc """
  The play's tabs share the overview's parts: a tab's rows sit in one card headed by what
  they are and how many, and an empty tab says so the same way on every tab.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.{Catalogue, Witnesses}

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  # The card a row sits in, read as its heading's text.
  defp card_heading(lv, row) do
    lv
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("section:has(##{row}) > header h2")
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  test "a tab's rows sit in one card headed by their name and count",
       %{conn: conn, play: play} do
    {:ok, editor} =
      Catalogue.create_play_editor(%{
        play_id: play.id,
        person_name: "Editora",
        role: "editor",
        position: 1
      })

    {:ok, witness} =
      Witnesses.create_witness(%{"play_id" => play.id, "siglum" => "A", "title" => "Ms."})

    link = play_place_fixture(play, place_fixture())
    performance = performance_fixture(play, %{"venue" => "Globe"})

    for {tab, row, name} <- [
          {"editors", "editor-#{editor.id}", t("Editors")},
          {"witnesses", "witness-#{witness.id}", t("Witnesses")},
          {"places", "link-#{link.id}", t("Places")},
          {"performances", "performance-#{performance.id}", t("Performances")}
        ] do
      {:ok, lv, _html} = live(conn, "/admin/plays/#{play.id}/#{tab}")
      assert {tab, card_heading(lv, row)} == {tab, "#{name} 1"}
    end
  end

  test "an empty tab says what it lacks in the same place on every tab",
       %{conn: conn, play: play} do
    for {tab, text} <- [
          {"editors", t("No editors listed yet.")},
          {"sources", t("No bibliographic sources yet.")},
          {"witnesses", t("No witnesses yet.")},
          {"performances", t("No performances yet.")},
          {"bibliography", t("No bibliography for this play yet.")},
          {"places", t("No places recorded for this play.")},
          {"notes", t("No notes yet. Add them to a line in Content.")}
        ] do
      {:ok, lv, _html} = live(conn, "/admin/plays/#{play.id}/#{tab}")
      assert {tab, has_element?(lv, "#empty-state", text)} == {tab, true}
    end
  end
end
