defmodule PlaycodeWeb.Admin.PlayRowOwnerTest do
  @moduledoc """
  A tab's save posts the form's params, and the browser can add `play_id`: the row's
  changeset casts it, so a crafted save moved an editor, a source, a witness, a performance
  or a place link into another play. A row stays in its play (CLAUDE.md, *Access control*);
  the Content tab's forms are in play_content_editor_live_test.exs.
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.{Catalogue, Performances, Places, Witnesses}

  setup %{conn: conn} do
    %{
      conn: log_in_user(conn, user_fixture(role: :researcher)),
      play: play_fixture(),
      other: play_fixture()
    }
  end

  defp open(conn, play, tab) do
    {:ok, lv, _html} = live(conn, "/admin/plays/#{play.id}/#{tab}")
    lv
  end

  test "an edited editor stays in its play", %{conn: conn, play: play, other: other} do
    {:ok, editor} =
      Catalogue.create_play_editor(%{play_id: play.id, person_name: "Ana Ruiz", role: "editor"})

    lv = open(conn, play, "editors")
    render_click(lv, "edit_editor", %{"id" => editor.id})

    render_submit(lv, "save_editor", %{
      "play_editor" => %{
        "play_id" => other.id,
        "person_name" => "Ana Ruiz Díaz",
        "role" => "editor"
      }
    })

    assert %{person_name: "Ana Ruiz Díaz"} = Catalogue.get_play_editor(play.id, editor.id)
  end

  test "an edited source stays in its play", %{conn: conn, play: play, other: other} do
    {:ok, source} = Catalogue.create_play_source(%{play_id: play.id, title: "Comedias"})

    lv = open(conn, play, "sources")
    render_click(lv, "edit_source", %{"id" => source.id})

    render_submit(lv, "save_source", %{
      "play_source" => %{"play_id" => other.id, "title" => "Comedias nuevas"}
    })

    assert %{title: "Comedias nuevas"} = Catalogue.get_play_source(play.id, source.id)
  end

  test "an edited witness stays in its play", %{conn: conn, play: play, other: other} do
    {:ok, witness} =
      Witnesses.create_witness(%{play_id: play.id, siglum: "A", title: "Primera edición"})

    lv = open(conn, play, "witnesses")
    render_click(lv, "edit_witness", %{"id" => witness.id})

    render_submit(lv, "save_witness", %{
      "witness" => %{"play_id" => other.id, "siglum" => "B", "title" => "Primera edición"}
    })

    assert %{siglum: "B"} = Witnesses.get_witness(play.id, witness.id)
  end

  test "an edited performance stays in its play", %{conn: conn, play: play, other: other} do
    {:ok, performance} = Performances.create_performance(%{play_id: play.id, date_text: "1610"})

    lv = open(conn, play, "performances")
    render_click(lv, "edit", %{"id" => performance.id})

    render_submit(lv, "save", %{
      "performance" => %{"play_id" => other.id, "date_text" => "1611"}
    })

    assert %{date_text: "1611"} = Performances.get_performance(play.id, performance.id)
  end

  test "an edited place link stays in its play, on its place",
       %{conn: conn, play: play, other: other} do
    place = place_fixture(%{"name" => "Owner Tolosa"})
    elsewhere = place_fixture(%{"name" => "Owner Lugo"})
    {:ok, link} = Places.link_place(play.id, place.id, %{"role" => "setting"})

    lv = open(conn, play, "places")

    render_submit(lv, "update_link", %{
      "link_id" => link.id,
      "play_place" => %{
        "play_id" => other.id,
        "place_id" => elsewhere.id,
        "role" => "setting",
        "note" => "Al fondo"
      }
    })

    assert %{place_id: place_id, note: "Al fondo"} = Places.get_play_place(play.id, link.id)
    assert place_id == place.id
  end
end
