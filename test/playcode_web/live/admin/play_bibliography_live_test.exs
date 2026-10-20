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

    # One other play is the commonest case, and reads in the singular.
    assert view |> element("#entry-editor [role=alert]") |> render() =~
             Gettext.dngettext(
               PlaycodeWeb.Gettext,
               "default",
               "Shared with %{count} other play (%{codes}): changes appear on both.",
               "Shared with %{count} other plays (%{codes}): changes appear on all of them.",
               1,
               codes: other.code
             )

    view
    |> form("#entry-form", entry: %{monogr_title: "The Complete Works"}, link: %{pages: "12"})
    |> render_submit()

    # The edit changed the entry and this play's link: both are logged.
    for type <- ["bibliography_entry", "play_bibliography"] do
      assert [_] = Playcode.ActivityLog.list_entries(resource_type: type, action: "update")
    end

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

    # The last removal took the entry with it, and the log says so.
    assert [_] =
             Playcode.ActivityLog.list_entries(
               resource_type: "bibliography_entry",
               action: "delete"
             )
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

  # Found by the final review: an event names its link by an id that came from the browser.
  # It used to do nothing silently; like every play tab, it now says the item is gone and
  # refreshes the list, which is what a stale tab needs.
  test "an edit or removal pushed for a link not in this play does nothing, and says so", %{
    conn: conn,
    play: play
  } do
    elsewhere = bibliography_fixture(play_fixture(), %{"monogr_title" => "Not this play's"})

    for event <- ["remove", "edit"], id <- [elsewhere.id, Ecto.UUID.generate(), "not-an-id"] do
      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

      assert render_click(view, event, %{"id" => id}) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"

      refute has_element?(view, "#entry-editor")
    end

    assert [_] = Bibliography.list_links(elsewhere.play_id)
  end

  # A catalogue is cited by performances alone (question 12); the shared entry changeset
  # accepts it for them, so this tab refuses it itself, whatever the browser sends.
  test "a catalogue is not a kind of this tab: a forged one is refused, new or edited", %{
    conn: conn,
    play: play
  } do
    link = bibliography_fixture(play, %{"monogr_title" => "Complete Works"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

    refute has_element?(view, ~s(option[value="catalogue"]))

    view |> element("#new-entry") |> render_click()

    html =
      view
      |> element("#entry-form")
      |> render_submit(%{"entry" => %{"kind" => "catalogue", "monogr_title" => "Forged"}})

    assert html =~ Gettext.dgettext(PlaycodeWeb.Gettext, "errors", "is invalid")
    assert [_] = Bibliography.list_links(play.id)

    view |> element("#entry-form button", t("Cancel")) |> render_click()
    view |> button(link, "Edit") |> render_click()

    view
    |> element("#entry-form")
    |> render_submit(%{"entry" => %{"kind" => "catalogue", "monogr_title" => "Forged"}})

    assert %{kind: "criticism", monogr_title: "Complete Works"} =
             Bibliography.get_entry(link.entry_id)
  end

  describe "an entry a performance of this play cites" do
    setup %{play: play} do
      link = bibliography_fixture(play, %{"monogr_title" => "Performed volume"})
      performance_fixture(play, %{"source_entry_id" => link.entry_id})
      %{link: link}
    end

    test "is not promised a deletion: removing the link keeps it, and says why", %{
      conn: conn,
      play: play,
      link: link
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

      assert view |> button(link, "Remove") |> render() =~
               t(
                 "Remove this entry from this play? A performance of this play cites it, so the entry stays."
               )

      html = view |> button(link, "Remove") |> render_click()

      assert html =~
               t("Removed from this play. A performance still cites it, so the entry stays.")

      refute html =~ t("Entry deleted: no other play used it.")
      assert Bibliography.list_links(play.id) == []
      assert Bibliography.get_entry(link.entry_id)
    end
  end

  test "an entry deleted under an open edit says so instead of crashing", %{
    conn: conn,
    play: play
  } do
    link = bibliography_fixture(play, %{"monogr_title" => "Complete Works"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> button(link, "Edit") |> render_click()

    # Another curator removes the only link: the entry goes with it.
    {:ok, :deleted} = Bibliography.unlink(link)

    html =
      view
      |> form("#entry-form", entry: %{monogr_title: "The Complete Works"})
      |> render_submit()

    assert html =~ t("That item no longer exists. The list has been refreshed.")
    refute has_element?(view, "#entry-editor")
    assert Bibliography.get_entry(link.entry_id) == nil
  end

  test "an edit leaves alone what another curator changed in a field it did not touch", %{
    conn: conn,
    play: play
  } do
    link = bibliography_fixture(play, %{"monogr_title" => "Complete Works"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")
    view |> button(link, "Edit") |> render_click()

    {:ok, _} = Bibliography.update_entry(link.entry, %{"public_note" => "Corrected meanwhile"})
    view |> form("#entry-form", entry: %{monogr_title: "The Complete Works"}) |> render_submit()

    assert %{monogr_title: "The Complete Works", public_note: "Corrected meanwhile"} =
             Bibliography.get_entry(link.entry_id)
  end

  # The search never offers a catalogue; a forged link event must not add one either.
  test "a catalogue cannot be linked to the play by a forged event", %{conn: conn, play: play} do
    catalogue = catalogue_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}/bibliography")

    assert render_click(view, "link", %{"entry" => catalogue.id}) =~
             t("That item no longer exists. The list has been refreshed.")

    assert Bibliography.list_links(play.id) == []
    assert %{kind: "catalogue"} = Bibliography.get_entry(catalogue.id)
  end
end
