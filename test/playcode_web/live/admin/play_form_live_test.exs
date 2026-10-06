defmodule PlaycodeWeb.Admin.PlayFormLiveTest do
  # form/3 fails when a field is missing from the page, so every test here also checks
  # that the inputs it fills are really on the form.
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

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

  test "half a composition date is refused", %{conn: conn} do
    play = play_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")

    html = save(view, %{"composition_date_from" => "1606"})

    assert html =~ error("must be given together with the end year")
    assert Catalogue.get_play!(play.id).composition_date_from == nil
  end
end
