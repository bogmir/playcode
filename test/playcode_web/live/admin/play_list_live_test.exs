defmodule PlaycodeWeb.Admin.PlayListLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers
  import Playcode.TestFixtures

  alias Playcode.ActivityLog
  alias Playcode.Catalogue

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher))}
  end

  defp restore(view, play),
    do: view |> element("#play-#{play.id} button[aria-label='#{t("Restore")}']") |> render_click()

  defp archive(conn, play) do
    {:ok, view, _html} = live(conn, ~p"/admin/plays/#{play.id}")
    view |> element("button", t("Archive play")) |> render_click()
  end

  test "searching narrows the list", %{conn: conn} do
    alpha = play_fixture(%{"title" => "Alpha Tragedy"})
    beta = play_fixture(%{"title" => "Beta Comedy"})

    {:ok, view, html} = live(conn, ~p"/admin/plays")
    assert html =~ alpha.title and html =~ beta.title

    html = view |> element("form[phx-change=search]") |> render_change(%{"search" => "Alpha"})

    assert html =~ alpha.title
    refute html =~ beta.title
  end

  # A TEST play is an admin's trial run, never published and never a researcher's concern.
  test "only an admin's list shows the plays of the TEST library", %{conn: conn} do
    trial = play_fixture(%{"code" => "TEST0001_Prueba", "title" => "Obra de prueba"})
    real = play_fixture(%{"title" => "Obra de verdad"})

    {:ok, _view, html} = live(conn, ~p"/admin/plays")
    assert html =~ real.title
    refute html =~ trial.title

    {:ok, _view, html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/plays")
    assert html =~ trial.title
  end

  # Reads PubSub's registry, past the page: how often the list listens to a play does not
  # show on it, but each extra subscription reloaded the whole list once more per edit,
  # and every page change or search added one.
  test "the list listens once to each play it shows, and stops for plays it no longer shows",
       %{conn: conn} do
    alpha = play_fixture(%{"title" => "Alpha Tragedy"})
    beta = play_fixture(%{"title" => "Beta Comedy"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    search = fn term ->
      view |> element("form[phx-change=search]") |> render_change(%{"search" => term})
    end

    subscriptions = fn play ->
      Playcode.PubSub
      |> Registry.lookup("play_content:#{play.id}")
      |> Enum.count(fn {pid, _} -> pid == view.pid end)
    end

    search.("Alpha")
    search.("")
    assert subscriptions.(alpha) == 1
    assert subscriptions.(beta) == 1

    search.("Alpha")
    assert subscriptions.(beta) == 0
  end

  test "each row says whether the play is a draft or complete, and follows a status change",
       %{conn: conn} do
    play = play_fixture()
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert has_element?(view, "th", t("Status"))
    assert has_element?(view, "#play-#{play.id} td", t("Draft"))
    refute has_element?(view, "#play-#{play.id} td", t("Complete"))

    {:ok, _} = Catalogue.update_play_from_form(play, %{"is_complete" => "true"})

    {:ok, view, _html} = live(conn, ~p"/admin/plays")
    assert has_element?(view, "#play-#{play.id} td", t("Complete"))
    refute has_element?(view, "#play-#{play.id} td", t("Draft"))
  end

  test "an archived play shows no status, which no longer applies to it", %{conn: conn} do
    play = play_fixture()
    {:ok, _} = Catalogue.delete_play(play)

    {:ok, view, _html} = live(conn, ~p"/admin/plays?archived=1")

    refute has_element?(view, "#play-#{play.id} td", t("Draft"))
    refute has_element?(view, "#play-#{play.id} td", t("Complete"))
  end

  test "an archived play leaves the list, waits under the archived filter, and can be restored",
       %{conn: conn} do
    play = play_fixture(%{"title" => "Archive Me"})

    archive(conn, play)
    {:ok, view, _html} = live(conn, ~p"/admin/plays")
    refute render(view) =~ "Archive Me"
    assert Catalogue.get_play!(play.id, include_deleted: true).deleted_at

    {:ok, archived, html} = live(conn, ~p"/admin/plays?archived=1")
    assert html =~ "Archive Me"

    restore(archived, play)
    refute render(archived) =~ "Archive Me"

    {:ok, _view, html} = live(conn, ~p"/admin/plays")
    assert html =~ "Archive Me"
  end

  # Regression: the archived list offered Edit, the title link and the public
  # page, all of which load through readers that hide archived plays — every
  # one of them raised Ecto.NoResultsError.
  test "an archived play offers no link to a page that cannot load it", %{conn: conn} do
    play = play_fixture(%{"title" => "Archived Play"})
    {:ok, _} = Catalogue.delete_play(play)

    {:ok, view, _html} = live(conn, ~p"/admin/plays?archived=1")

    for href <- [
          ~p"/admin/plays/#{play.id}/edit",
          ~p"/admin/plays/#{play.id}",
          ~p"/plays/#{play.code}"
        ] do
      refute has_element?(view, "#play-#{play.id} a[href='#{href}']"), href
    end

    assert has_element?(view, "#play-#{play.id} button[aria-label='#{t("Restore")}']")
  end

  describe "deleting an archived play" do
    setup %{conn: conn} do
      play = play_fixture(%{"title" => "Doomed Play", "code" => "EMOTHE9990_Doomed"})
      {:ok, _} = Catalogue.delete_play(play)
      %{play: play, admin: log_in_user(conn, admin_fixture())}
    end

    defp open_delete(view, play),
      do:
        view
        |> element("#play-#{play.id} button[aria-label='#{t("Delete permanently")}']")
        |> render_click()

    defp confirm_delete(view, code),
      do: view |> form("#purge-modal form", %{"code" => code}) |> render_submit()

    test "an admin deletes it for good by typing its code", %{admin: conn, play: play} do
      {:ok, view, _html} = live(conn, ~p"/admin/plays?archived=1")

      open_delete(view, play)
      assert has_element?(view, "#purge-modal", play.code)
      confirm_delete(view, "EMOTHE9990_Doomed")

      refute has_element?(view, "#play-#{play.id}")
      assert has_element?(view, "#flash-info", t("%{title} was deleted.", title: "Doomed Play"))
      refute Enum.any?(Catalogue.list_plays(include_deleted: true), &(&1.id == play.id))

      assert [%{metadata: %{"code" => "EMOTHE9990_Doomed", "purged" => true}}] =
               ActivityLog.list_entries(resource_type: "play", action: "delete")
               |> Enum.filter(&(&1.resource_id == play.id))
    end

    test "a code typed wrong deletes nothing", %{admin: conn, play: play} do
      {:ok, view, _html} = live(conn, ~p"/admin/plays?archived=1")

      open_delete(view, play)
      assert has_element?(view, "#purge-modal button[type=submit][disabled]")

      view |> form("#purge-modal form", %{"code" => "EMOTHE9990"}) |> render_change()
      assert has_element?(view, "#purge-modal button[type=submit][disabled]")

      view |> form("#purge-modal form", %{"code" => "EMOTHE9990_Doomed"}) |> render_change()
      refute has_element?(view, "#purge-modal button[type=submit][disabled]")

      confirm_delete(view, "Doomed Play")

      assert has_element?(view, "#purge-modal")
      assert Catalogue.get_play!(play.id, archived: true)
    end

    test "a researcher is offered no delete, and one sent by hand is refused",
         %{conn: conn, play: play} do
      {:ok, view, _html} = live(conn, ~p"/admin/plays?archived=1")

      refute has_element?(view, "button[aria-label='#{t("Delete permanently")}']")
      render_click(view, "open_purge", %{"id" => play.id})
      render_click(view, "purge", %{"code" => play.code})

      assert Catalogue.get_play!(play.id, archived: true)
    end
  end

  test "the heading names what the page holds and how many, archived plays not counted",
       %{conn: conn} do
    play_fixture()
    play_fixture()
    {:ok, _} = Catalogue.delete_play(play_fixture())

    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert has_element?(view, "h1", "#{t("Plays")} · 2")
  end

  test "a row opens its play by the title and carries no other link", %{conn: conn} do
    play = play_fixture(%{"title" => "Open Me"})
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert has_element?(view, "#play-#{play.id} a[href='/admin/plays/#{play.id}']", "Open Me")
    refute has_element?(view, "#play-#{play.id} a[href='/admin/plays/#{play.id}/edit']")
    refute has_element?(view, "#play-#{play.id} a[href='/plays/#{play.code}']")
    refute has_element?(view, "#play-#{play.id} button[aria-label='#{t("Archive")}']")
  end

  describe "the status filter" do
    setup %{conn: conn} do
      draft = play_fixture(%{"title" => "A Draft Play"})
      done = play_fixture(%{"title" => "A Done Play"})
      {:ok, _} = Catalogue.update_play_from_form(done, %{"is_complete" => "true"})
      {:ok, view, _html} = live(conn, ~p"/admin/plays")
      %{view: view, draft: draft, done: done}
    end

    test "each choice carries its count", %{view: view} do
      assert has_element?(view, "nav[aria-label='#{t("Status")}'] a", "#{t("All")} · 2")
      assert has_element?(view, "nav[aria-label='#{t("Status")}'] a", "#{t("Drafts")} · 1")

      assert has_element?(
               view,
               "nav[aria-label='#{t("Status")}'] a",
               "#{t("Complete plays")} · 1"
             )
    end

    test "choosing one narrows the list and the address keeps it", %{
      view: view,
      draft: draft,
      done: done
    } do
      view |> element("nav[aria-label='#{t("Status")}'] a", t("Drafts")) |> render_click()
      assert_patch(view, ~p"/admin/plays?status=draft")
      assert has_element?(view, "#play-#{draft.id}")
      refute has_element?(view, "#play-#{done.id}")

      view |> element("nav[aria-label='#{t("Status")}'] a", t("Complete plays")) |> render_click()
      assert_patch(view, ~p"/admin/plays?status=complete")
      assert has_element?(view, "#play-#{done.id}")
      refute has_element?(view, "#play-#{draft.id}")
    end

    test "the search keeps the filter, and the filter keeps the search", %{
      conn: conn,
      draft: draft,
      done: done
    } do
      {:ok, view, _html} = live(conn, ~p"/admin/plays?status=draft")
      view |> element("form[phx-change=search]") |> render_change(%{"search" => "Play"})
      assert_patch(view, ~p"/admin/plays?#{[search: "Play", status: "draft"]}")
      assert has_element?(view, "#play-#{draft.id}")
      refute has_element?(view, "#play-#{done.id}")
    end
  end

  describe "pick up where you left off" do
    setup %{conn: conn} do
      user = user_fixture(role: :researcher)
      %{conn: log_in_user(conn, user), user: user}
    end

    defp changed(user, play),
      do:
        {:ok, _} =
          ActivityLog.log(%{
            user_id: user.id,
            play_id: play.id,
            action: "update",
            resource_type: "play",
            resource_id: play.id
          })

    defp recent_titles(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("section[aria-label='#{t("Pick up where you left off")}'] a")
      |> Enum.map(&LazyHTML.text/1)
      |> Enum.map(&String.trim/1)
    end

    test "lists the last five plays the user changed, newest first, each once, archived ones left out",
         %{conn: conn, user: user} do
      plays = for n <- 1..7, do: play_fixture(%{"title" => "Recent #{n}"})
      [first, second | _] = plays

      for play <- plays, do: changed(user, play)
      changed(user, first)
      changed(user_fixture(), second)
      {:ok, _} = Catalogue.delete_play(Enum.at(plays, 6))

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert recent_titles(view) == ["Recent 1", "Recent 6", "Recent 5", "Recent 4", "Recent 3"]
    end

    test "a play saved through its form joins them", %{conn: conn} do
      play = play_fixture(%{"title" => "Edited Here"})
      {:ok, form, _html} = live(conn, ~p"/admin/plays/#{play.id}/edit")
      form |> form("#play-form", play: %{"title" => "Edited There"}) |> render_submit()

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert recent_titles(view) == ["Edited There"]
    end

    test "nothing is shown to a user who changed nothing", %{conn: conn} do
      play_fixture()
      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      refute has_element?(view, "section[aria-label='#{t("Pick up where you left off")}']")
    end
  end

  describe "a play whose text did not arrive" do
    setup %{conn: conn} do
      empty = play_without_text_fixture(%{"title" => "Empty Play"})

      prose =
        import_tei!(
          tei(
            title: "Prose Play",
            body: """
            <div1 type="acto" n="1"><head>ACTO I</head>
              <sp><speaker>ANA</speaker><p>Todo en prosa.</p></sp>
            </div1>
            """
          )
        )

      verse =
        import_tei!(
          tei(
            title: "Verse Play",
            body: """
            <div1 type="acto" n="1"><head>ACTO I</head>
              <sp><speaker>ANA</speaker><l n="1">uno</l><l n="2">dos</l></sp>
            </div1>
            """
          )
        )

      {:ok, view, _html} = live(conn, ~p"/admin/plays")
      %{view: view, empty: empty, prose: prose, verse: verse}
    end

    test "is marked; a prose play is not, and says prose where its verses go",
         %{view: view, empty: empty, prose: prose, verse: verse} do
      assert has_element?(view, "#play-#{empty.id} td", t("No text"))
      refute has_element?(view, "#play-#{prose.id} td", t("No text"))
      refute has_element?(view, "#play-#{verse.id} td", t("No text"))

      assert has_element?(view, "#play-#{prose.id} td", t("prose"))
      assert has_element?(view, "#play-#{verse.id} td", "2")
    end

    test "has a filter of its own", %{view: view, empty: empty, prose: prose, verse: verse} do
      assert has_element?(view, "nav[aria-label='#{t("Status")}'] a", "#{t("No text")} · 1")

      view |> element("nav[aria-label='#{t("Status")}'] a", t("No text")) |> render_click()
      assert_patch(view, ~p"/admin/plays?status=no_text")
      assert has_element?(view, "#play-#{empty.id}")
      refute has_element?(view, "#play-#{prose.id}")
      refute has_element?(view, "#play-#{verse.id}")
    end
  end

  describe "the first visit's card" do
    setup do
      %{user: user_fixture(role: :researcher)}
    end

    defp card, do: "section[aria-label='#{t("Getting started")}']"

    test "says how a play gets from here to the site", %{conn: conn, user: user} do
      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/admin/plays")

      assert has_element?(view, card(), t("Find a play in the list, or import one."))
      assert has_element?(view, card(), t("Edit its record and its text."))

      assert has_element?(
               view,
               card(),
               t("Mark it complete, and it goes online with the next Publish.")
             )
    end

    test "once closed, it stays closed, on this computer and on another",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(log_in_user(conn, user), ~p"/admin/plays")
      view |> element("#{card()} button", t("Got it")) |> render_click()
      refute has_element?(view, card())

      {:ok, view, _html} = live(log_in_user(build_conn(), user), ~p"/admin/plays")
      refute has_element?(view, card())
    end
  end

  describe "families" do
    defp row_ids(view),
      do:
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("tbody tr[id]")
        |> LazyHTML.attribute("id")

    defp derived(original, attrs) do
      %{"parent_play_id" => original.id, "relationship_type" => "traduccion"}
      |> Map.merge(attrs)
      |> play_fixture()
    end

    defp search(view, term),
      do: view |> element("form[phx-change=search]") |> render_change(%{"search" => term})

    # Between 2026-11-17 and 2026-11-18 the kind was a heading row over its group; the
    # owner chose a chip on each row instead, kind and language, and no rows of headings.
    test "a derived play is listed under its original, its chip naming its kind and language",
         %{conn: conn} do
      middle = play_fixture(%{"title_sort" => "Middle"})
      original = play_fixture(%{"title_sort" => "Zeta"})
      translation = derived(original, %{"title_sort" => "Alpha"})

      adaptation =
        derived(original, %{"title_sort" => "Beta", "relationship_type" => "adaptacion"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert row_ids(view) == [
               "play-#{middle.id}",
               "play-#{original.id}",
               "play-#{translation.id}",
               "play-#{adaptation.id}"
             ]

      assert has_element?(view, "#play-#{translation.id} td", "#{t("Translation")} · ES")
      assert has_element?(view, "#play-#{adaptation.id} td", "#{t("Adaptation")} · ES")
      refute has_element?(view, "#play-#{original.id} td", t("Translation"))
      refute has_element?(view, "tbody tr:not([id])")
    end

    test "a family's derived plays go by kind, then language, then title",
         %{conn: conn} do
      original = play_fixture(%{"title_sort" => "Original"})
      version = derived(original, %{"title_sort" => "A", "relationship_type" => "version"})
      adaptation = derived(original, %{"title_sort" => "B", "relationship_type" => "adaptacion"})
      french = derived(original, %{"title_sort" => "C", "language" => "fr"})
      english_b = derived(original, %{"title_sort" => "E", "language" => "en"})
      english_a = derived(original, %{"title_sort" => "D", "language" => "en"})
      untyped = derived(original, %{"title_sort" => "0", "relationship_type" => nil})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert row_ids(view) ==
               Enum.map(
                 [original, english_a, english_b, french, adaptation, version, untyped],
                 &"play-#{&1.id}"
               )

      assert has_element?(view, "#play-#{french.id} td", "#{t("Translation")} · FR")
      assert has_element?(view, "#play-#{version.id} td", "#{t("Version")} · ES")
    end

    test "a search that finds one member shows the whole family, the original first",
         %{conn: conn} do
      original =
        play_fixture(%{"title" => "El burlador de Sevilla", "title_sort" => "Burlador"})

      trickster =
        derived(original, %{"title" => "The Trickster of Seville", "title_sort" => "Trickster"})

      other = play_fixture(%{"title" => "Alpha Tragedy"})
      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      search(view, "Trickster")
      assert row_ids(view) == ["play-#{original.id}", "play-#{trickster.id}"]

      search(view, "burlador")
      assert row_ids(view) == ["play-#{original.id}", "play-#{trickster.id}"]
      refute has_element?(view, "#play-#{other.id}")
    end

    test "a status filter keeps the original as the heading of the derived plays it lets through",
         %{conn: conn} do
      original = play_fixture(%{"title_sort" => "A", "is_complete" => true})
      draft = derived(original, %{"title_sort" => "B"})
      done = derived(original, %{"title_sort" => "C", "is_complete" => true})

      {:ok, view, _html} = live(conn, ~p"/admin/plays?status=draft")

      assert row_ids(view) == ["play-#{original.id}", "play-#{draft.id}"]
      refute has_element?(view, "#play-#{done.id}")
      assert has_element?(view, "nav[aria-label='#{t("Status")}'] a", "#{t("Drafts")} · 1")
    end

    test "a derived play whose kind was never set is listed under its original, unnamed",
         %{conn: conn} do
      original = play_fixture(%{"title_sort" => "Alpha"})
      untyped = derived(original, %{"title_sort" => "Beta", "relationship_type" => nil})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert row_ids(view) == ["play-#{original.id}", "play-#{untyped.id}"]
      refute has_element?(view, "#play-#{untyped.id} td", t("Translation"))
    end

    test "a translation of a translation is listed under the original of the chain",
         %{conn: conn} do
      middle = play_fixture(%{"title_sort" => "Middle"})
      original = play_fixture(%{"title_sort" => "Zeta"})
      first = derived(original, %{"title_sort" => "Beta"})
      second = derived(first, %{"title_sort" => "Alpha"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert row_ids(view) == [
               "play-#{middle.id}",
               "play-#{original.id}",
               "play-#{second.id}",
               "play-#{first.id}"
             ]
    end

    test "a derived play whose original is archived heads its own family", %{conn: conn} do
      original = play_fixture(%{"title_sort" => "Alpha"})
      translation = derived(original, %{"title_sort" => "Beta"})
      archive(conn, original)

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert row_ids(view) == ["play-#{translation.id}"]
      refute has_element?(view, "#play-#{translation.id} td", t("Translation"))
    end

    test "plays that name each other as parent are each listed once", %{conn: conn} do
      a = play_fixture(%{"title_sort" => "Alpha"})
      b = play_fixture(%{"title_sort" => "Beta"})

      {:ok, a} =
        Catalogue.update_play(a, %{"parent_play_id" => b.id, "relationship_type" => "traduccion"})

      {:ok, b} =
        Catalogue.update_play(b, %{"parent_play_id" => a.id, "relationship_type" => "traduccion"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert row_ids(view) == ["play-#{a.id}", "play-#{b.id}"]
    end

    test "a page holds 50 families, however many derived plays they have", %{conn: conn} do
      original = play_fixture(%{"title_sort" => "Alpha"})
      for n <- 1..50, do: derived(original, %{"title_sort" => "Alpha #{n}"})
      play_fixture(%{"title_sort" => "Beta"})

      {:ok, view, _html} = live(conn, ~p"/admin/plays")

      assert length(row_ids(view)) == 52
      refute has_element?(view, "a", t("Next"))
    end
  end

  test "the sidebar's checkbox is not restored by the browser", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/plays")

    assert has_element?(view, "#admin-sidebar[autocomplete=off]")
  end
end
