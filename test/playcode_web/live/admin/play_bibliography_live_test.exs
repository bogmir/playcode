defmodule PlaycodeWeb.Admin.PlayBibliographyLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.Bibliography

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp button(view, link, label),
    do: element(view, ~s(#bib-#{link.id} button[aria-label="#{t(label)}"]))

  test "the play has its own Bibliography tab beside Sources", %{conn: conn, play: play} do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/sources")

    assert view
           |> element(~s(a[href="/admin/plays/#{play.id}/bibliography"]), t("Bibliography"))
           |> has_element?()

    {:ok, _view, html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    assert html =~ t("No bibliography for this play yet.")
  end

  test "a new entry is previewed as printed and saved with this play's own pages", %{
    conn: conn,
    play: play
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> element("#new-entry") |> render_click()

    entry = %{
      kind: "modern_edition",
      pub_type: "book",
      monogr_editors: "Thompson, Ann",
      monogr_title: "Hamlet"
    }

    view |> form("#entry-form", entry: entry, link: %{pages: "1-50"}) |> render_change()

    assert view |> element("#citation-preview") |> render() =~
             "Thompson, Ann, ed. <em>Hamlet</em>."

    view |> form("#entry-form", entry: entry, link: %{pages: "1-50"}) |> render_submit()

    assert [{"modern_edition", [{nil, [link]}]}] = Bibliography.list_for_play(play.id)
    assert link.pages == "1-50"
    assert render(view) =~ t("Entry added.")

    assert [%{resource_type: "bibliography_entry"}] =
             Playcode.ActivityLog.list_entries(resource_type: "bibliography_entry")
  end

  test "an entry with no author, editor or title is refused, saying why", %{
    conn: conn,
    play: play
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> element("#new-entry") |> render_click()

    html =
      view
      |> form("#entry-form", entry: %{kind: "criticism", year_text: "2005"})
      |> render_submit()

    assert html =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "needs an author, an editor or a title"
             )

    assert Bibliography.list_links(play.id) == []
  end

  test "editing a shared entry warns first, and the edit reaches the other play", %{
    conn: conn,
    play: play
  } do
    other = play_fixture()
    link = bibliography_fixture(play, %{"monogr_title" => "Complete Works"})
    {:ok, _} = Bibliography.link_entry(other.id, link.entry_id)

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> button(link, "Edit") |> render_click()

    assert view |> element("#entry-editor [role=alert]") |> render() =~ other.code

    view |> form("#entry-form", entry: %{monogr_title: "The Complete Works"}) |> render_submit()

    assert [{"criticism", [{nil, [shared]}]}] = Bibliography.list_for_play(other.id)
    assert shared.entry.monogr_title == "The Complete Works"
  end

  test "an entry another play has is found and added", %{conn: conn, play: play} do
    bibliography_fixture(play_fixture(), %{
      "kind" => "modern_edition",
      "monogr_title" => "The Riverside Shakespeare",
      "monogr_editors" => "Evans, G. Blakemore"
    })

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> element("#add-existing-button") |> render_click()
    view |> form("#entry-search", term: "riverside") |> render_change()
    view |> element("#add-existing li button", t("Add")) |> render_click()

    assert [{"modern_edition", [{nil, [link]}]}] = Bibliography.list_for_play(play.id)
    assert link.entry.monogr_title == "The Riverside Shakespeare"
  end

  test "removing a shared entry keeps it for the other play; removing the last deletes it", %{
    conn: conn,
    play: play
  } do
    other = play_fixture()
    shared = bibliography_fixture(play, %{"monogr_title" => "Shared volume"})
    {:ok, _} = Bibliography.link_entry(other.id, shared.entry_id)
    own = bibliography_fixture(play, %{"monogr_title" => "Own volume"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

    assert view |> button(shared, "Remove") |> render_click() =~
             t("Removed from this play. The other plays keep it.")

    assert [_] = Bibliography.list_links(other.id)

    assert view |> button(own, "Remove") |> render_click() =~
             t("Entry deleted: no other play used it.")

    assert Bibliography.search_entries("Own volume", other.id) == []
  end

  # Review focus 2.
  test "the filter ignores accents and case, and says when nothing matches", %{
    conn: conn,
    play: play
  } do
    bibliography_fixture(play, %{"monogr_author" => "Zúñiga, Ana", "monogr_title" => "Teatro"})
    bibliography_fixture(play, %{"monogr_author" => "Oleza, Joan", "monogr_title" => "Prácticas"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

    # Folding both sides: the citation (zuniga finds Zúñiga) and the query (ZÚÑIGA too).
    for q <- ["zuniga", "ZÚÑIGA"] do
      html = view |> form("#bibliography-filter", q: q) |> render_change()
      assert html =~ "Zúñiga, Ana"
      refute html =~ "Oleza, Joan"
    end

    assert view |> form("#bibliography-filter", q: "nadie") |> render_change() =~
             t("Nothing matches the filter.")
  end
end
