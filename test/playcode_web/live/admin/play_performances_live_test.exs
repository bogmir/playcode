defmodule PlaycodeWeb.Admin.PlayPerformancesLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.ActivityLog
  alias Playcode.Performances
  alias Playcode.Performances.Actor

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: play_fixture()}
  end

  defp add(lv, attrs) do
    lv |> element("button", t("Add performance")) |> render_click()
    lv |> form("#performance-form", performance: attrs) |> render_submit()
  end

  # Company names are unique across the corpus, so two async tests naming the same company
  # would queue on the index, and two pairs in opposite orders would deadlock: every name
  # a test makes up is made unique.
  defp unique(name), do: "#{name} #{System.unique_integer([:positive])}"

  defp error(message), do: Gettext.dgettext(PlaycodeWeb.Gettext, "errors", message)

  defp rename_button(lv, name),
    do: element(lv, "button[aria-label='#{t("Rename %{name}", name: name)}']")

  defp add_cast_row(lv), do: lv |> element("button", t("Add actor")) |> render_click()

  # The cast as the page prints it: each actor as it reads, and the role.
  defp cast_of(performance),
    do: for(member <- performance.cast, do: {Actor.display_name(member.actor), member.role})

  defp button(lv, label, performance_label),
    do:
      element(
        lv,
        "button[aria-label='#{t(label <> " %{performance}", performance: performance_label)}']"
      )

  test "a researcher adds a performance and sees it as readers will", %{conn: conn, play: play} do
    {:ok, lv, html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    assert html =~ t("No performances yet.")

    add(lv, %{
      "date_text" => "1610",
      "venue" => "Globe",
      "venue_type" => "public_theatre",
      "company_name" => "The King’s Men"
    })

    assert [performance] = Performances.list_for_play(play.id)
    assert %{origin: "manual", year_from: 1610, company: %{name: "The King’s Men"}} = performance
    assert [%{name: "The King’s Men"}] = Performances.list_companies()

    html = lv |> element("#performance-#{performance.id}") |> render()
    assert html =~ "1610"
    assert html =~ "Globe · The King’s Men · teatro público"
  end

  test "a company is picked from those that exist", %{conn: conn, play: play} do
    {:ok, company} = Performances.find_or_create_company("The King’s Men")
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    lv |> element("button", t("Add performance")) |> render_click()
    assert has_element?(lv, "datalist option[value='The King’s Men']")

    lv
    |> form("#performance-form",
      performance: %{"date_text" => "1610", "company_name" => "the king’s men"}
    )
    |> render_submit()

    assert [%{company_id: company_id}] = Performances.list_for_play(play.id)
    assert company_id == company.id
    assert [%{name: "The King’s Men"}] = Performances.list_companies()
  end

  test "the place is found by name, and a state chosen", %{conn: conn, play: play} do
    place_fixture(%{"name" => "Londres"})
    place_fixture(%{"name" => "Zaragoza"})
    england = place_fixture(%{"name" => "Inglaterra", "type" => "country"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    lv |> element("button", t("Add performance")) |> render_click()
    refute render(lv) =~ "Zaragoza"

    html = lv |> element("#place-search") |> render_change(%{"term" => "Lond"})
    assert html =~ "Londres"
    refute html =~ "Zaragoza"

    lv |> element("button", "Londres") |> render_click()

    lv
    |> form("#performance-form",
      performance: %{"date_text" => "1610", "historical_state_id" => england.id}
    )
    |> render_submit()

    assert [%{id: id, place: %{id: place_id}, historical_state_id: state_id}] =
             Performances.list_for_play(play.id)

    assert state_id == england.id
    assert place_id != nil
    assert lv |> element("#performance-#{id}") |> render() =~ "Londres, Inglaterra"
  end

  test "a place can be unpicked, and its state goes with it", %{conn: conn, play: play} do
    england = place_fixture(%{"name" => "Inglaterra", "type" => "country"})

    performance =
      performance_fixture(play, %{
        "place_id" => place_fixture(%{"name" => "Oxford"}).id,
        "historical_state_id" => england.id
      })

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> button("Edit", "1610, Oxford, Inglaterra") |> render_click()

    lv |> element("button[title='#{t("Clear")}']") |> render_click()
    lv |> form("#performance-form") |> render_submit()

    assert %{place_id: nil, historical_state_id: nil} =
             Performances.get_performance(play.id, performance.id)
  end

  test "a performance is edited and deleted, and each is logged", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    add(lv, %{"date_text" => "1610", "venue" => "Globe"})
    [performance] = Performances.list_for_play(play.id)

    lv |> button("Edit", "1610, Globe") |> render_click()
    lv |> form("#performance-form", performance: %{"venue" => "Blackfriars"}) |> render_submit()

    assert %{venue: "Blackfriars", origin: "manual"} =
             Performances.get_performance(play.id, performance.id)

    lv |> button("Delete", "1610, Blackfriars") |> render_click()
    assert Performances.list_for_play(play.id) == []

    assert ~w(create delete update) ==
             [resource_type: "play_performance"]
             |> ActivityLog.list_entries()
             |> Enum.map(& &1.action)
             |> Enum.sort()
  end

  test "a company changed or cleared here frees the old one", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    add(lv, %{"date_text" => "1610", "company_name" => "The King’s Men"})
    [performance] = Performances.list_for_play(play.id)

    lv |> button("Edit", "1610, The King’s Men") |> render_click()

    lv
    |> form("#performance-form", performance: %{"company_name" => "Lady Elizabeth’s"})
    |> render_submit()

    assert [%{name: "Lady Elizabeth’s"}] = Performances.list_companies()

    lv |> button("Edit", "1610, Lady Elizabeth’s") |> render_click()
    lv |> form("#performance-form", performance: %{"company_name" => ""}) |> render_submit()

    assert %{company: nil} = Performances.get_performance(play.id, performance.id)
    assert Performances.list_companies() == []
  end

  # The years a date gives are filled in when the form is saved. If the form echoed them
  # while the date is typed, the browser would send them back as the curator's own, and a
  # corrected date would leave them behind.
  test "the years follow the date as it was saved, however it was typed", %{
    conn: conn,
    play: play
  } do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> element("button", t("Add performance")) |> render_click()
    lv |> form("#performance-form", performance: %{"date_text" => "1597-9"}) |> render_change()
    lv |> form("#performance-form", performance: %{"date_text" => "1600"}) |> render_submit()
    assert [%{id: id, year_from: 1600, year_to: 1600}] = Performances.list_for_play(play.id)

    lv |> button("Edit", "1600") |> render_click()
    lv |> form("#performance-form", performance: %{"date_text" => "1615"}) |> render_change()
    lv |> form("#performance-form", performance: %{"date_text" => "1620"}) |> render_submit()

    assert %{year_from: 1620, year_to: 1620} = Performances.get_performance(play.id, id)
  end

  test "the form says what is missing", %{conn: conn, play: play} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> element("button", t("Add performance")) |> render_click()

    html = lv |> form("#performance-form", performance: %{"date_text" => ""}) |> render_submit()

    assert html =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "needs a date, a venue, a company or a note"
             )

    assert Performances.list_for_play(play.id) == []
  end

  # Review focus 3: the switch is one per play, and a refused save writes nothing, a new
  # company among it.
  test "a second cast-list switch is refused with a message and leaves no company behind",
       %{conn: conn, play: play} do
    performance_fixture(play, %{"cast_from_cast_list" => "true"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    add(lv, %{
      "date_text" => "1611",
      "cast_from_cast_list" => "true",
      "company_name" => "Nueva Compañía"
    })

    assert render(lv) =~
             Gettext.dgettext(
               PlaycodeWeb.Gettext,
               "errors",
               "is already set on another performance of this play"
             )

    assert [_one] = Performances.list_for_play(play.id)
    assert Performances.list_companies() == []

    # Corrected, it saves: the company then, and the years of the date it now has.
    lv
    |> form("#performance-form",
      performance: %{"date_text" => "1612", "cast_from_cast_list" => "false"}
    )
    |> render_submit()

    assert [_, %{year_from: 1612, company: %{name: "Nueva Compañía"}}] =
             Performances.list_for_play(play.id)
  end

  # The form's own fields only: a play_id sent with it would move the performance to
  # another play, an origin mark it for an import to replace.
  test "a saved form cannot move a performance to another play or change its origin",
       %{conn: conn, play: play} do
    other = play_fixture()
    performance = performance_fixture(play)
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

    lv |> button("Edit", "1610") |> render_click()

    lv
    |> form("#performance-form", performance: %{"venue" => "Globe"})
    |> render_submit(%{"performance" => %{"play_id" => other.id, "origin" => "filemaker"}})

    assert %{venue: "Globe", origin: "manual"} =
             Performances.get_performance(play.id, performance.id)

    assert Performances.list_for_play(other.id) == []
  end

  test "a performance that is gone says so", %{conn: conn, play: play} do
    theirs = performance_fixture(play_fixture())

    for event <- ~w(edit delete), id <- [theirs.id, Ecto.UUID.generate(), "not-a-uuid"] do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

      assert render_click(lv, event, %{"id" => id}) =~
               t("That item no longer exists. The list has been refreshed."),
             "#{event} #{id}"

      refute has_element?(lv, "#performance-form")
    end

    assert [_theirs] = Performances.list_for_play(theirs.play_id)
  end

  test "a state that is gone is refused, not saved", %{conn: conn, play: play} do
    place_fixture(%{"name" => "Londres"})
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
    lv |> element("button", t("Add performance")) |> render_click()
    lv |> element("#place-search") |> render_change(%{"term" => "Lond"})
    lv |> element("button", "Londres") |> render_click()

    html =
      lv
      |> form("#performance-form", performance: %{"date_text" => "1610"})
      |> render_submit(%{"performance" => %{"historical_state_id" => Ecto.UUID.generate()}})

    assert html =~ t("That item no longer exists. The list has been refreshed.")
    assert Performances.list_for_play(play.id) == []
  end

  describe "the cast" do
    test "the cast is added, ordered and removed in the form", %{conn: conn, play: play} do
      {:ok, _} =
        Performances.find_or_create_actor(%{
          "surname" => "Betterton",
          "forename" => "Thomas",
          "sex" => "man"
        })

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> element("button", t("Add performance")) |> render_click()
      add_cast_row(lv)
      add_cast_row(lv)

      lv
      |> form("#performance-form",
        performance: %{
          "date_text" => "1700",
          "cast" => %{
            "0" => %{"actor_name" => "thomas betterton", "role" => "Mirabell"},
            "1" => %{
              "surname" => "Bracegirdle",
              "forename" => "Anne",
              "nickname" => "Bracey",
              "sex" => "woman",
              "role" => "Millamant"
            }
          }
        }
      )
      |> render_submit()

      assert [performance] = Performances.list_for_play(play.id)

      assert cast_of(performance) == [
               {"Thomas Betterton", "Mirabell"},
               {"Anne Bracegirdle, “Bracey”", "Millamant"}
             ]

      assert [%{sex: "man"}, %{sex: "woman"}] = Enum.map(performance.cast, & &1.actor)

      assert lv |> element("#performance-#{performance.id}") |> render() =~
               "#{t("Cast")}: Thomas Betterton (Mirabell); Anne Bracegirdle, “Bracey” (Millamant)"

      # Edited, the rows come back as saved; the first is removed, and its actor with it.
      lv |> button("Edit", "1700") |> render_click()
      assert has_element?(lv, "#cast-0-actor-name[value='Thomas Betterton']")
      assert has_element?(lv, "#cast-1-actor-name[value='Anne Bracegirdle, “Bracey”']")

      lv
      |> element("button[aria-label='#{t("Remove cast row %{number}", number: 1)}']")
      |> render_click()

      lv |> form("#performance-form") |> render_submit()

      assert [performance] = Performances.list_for_play(play.id)
      assert cast_of(performance) == [{"Anne Bracegirdle, “Bracey”", "Millamant"}]
      assert [%{surname: "Bracegirdle"}] = Performances.list_actors()
    end

    # The browser sends the rows as a map keyed "0", "1", ... "10": by text, "10" is before "2".
    test "the rows keep their order past ten", %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> element("button", t("Add performance")) |> render_click()
      for _ <- 0..11, do: add_cast_row(lv)

      rows = Map.new(0..11, &{"#{&1}", %{"surname" => "Actor #{&1}", "role" => "Role #{&1}"}})

      lv
      |> form("#performance-form", performance: %{"date_text" => "1700", "cast" => rows})
      |> render_submit()

      assert [performance] = Performances.list_for_play(play.id)
      assert Enum.map(performance.cast, & &1.role) == for(n <- 0..11, do: "Role #{n}")
    end

    test "a row left empty is dropped, and removing the last row empties the cast",
         %{conn: conn, play: play} do
      performance = performance_fixture(play)
      {:ok, actor} = Performances.find_or_create_actor(%{"surname" => "Hart"})

      {:ok, _} =
        Performances.put_cast(performance, [%{"actor_id" => actor.id, "role" => "Othello"}])

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> button("Edit", "1610") |> render_click()
      add_cast_row(lv)
      lv |> form("#performance-form") |> render_submit()
      assert [%{cast: [_one]}] = Performances.list_for_play(play.id)

      lv |> button("Edit", "1610") |> render_click()

      lv
      |> element("button[aria-label='#{t("Remove cast row %{number}", number: 1)}']")
      |> render_click()

      lv |> form("#performance-form") |> render_submit()
      assert [%{cast: []}] = Performances.list_for_play(play.id)
      assert Performances.list_actors() == []
    end

    test "a row that names no actor is refused where it stands, and nothing is written",
         %{conn: conn, play: play} do
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> element("button", t("Add performance")) |> render_click()
      for _ <- 1..4, do: add_cast_row(lv)

      html =
        lv
        |> form("#performance-form",
          performance: %{
            "date_text" => "1700",
            "cast" => %{
              "0" => %{"surname" => "Nuevo Actor", "role" => "Primero"},
              "1" => %{"role" => "Sin actor"},
              "2" => %{"actor_name" => "Nadie Conocido"},
              "3" => %{"forename" => "Solo Nombre"}
            }
          }
        )
        |> render_submit()

      for message <- [
            "needs an actor",
            "names no actor that exists: add one with a surname or a nickname",
            "needs a surname or a nickname"
          ] do
        assert html =~ error(message), message
      end

      # The error is on its row: the second.
      assert lv |> element("#cast-row-1") |> render() =~ error("needs an actor")
      refute lv |> element("#cast-row-0") |> render() =~ error("needs an actor")

      assert Performances.list_for_play(play.id) == []
      assert Performances.list_actors() == []
    end

    test "a refused save with a new actor in the cast leaves no actor of that name",
         %{conn: conn, play: play} do
      performance_fixture(play, %{"cast_from_cast_list" => "true"})
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> element("button", t("Add performance")) |> render_click()
      add_cast_row(lv)

      lv
      |> form("#performance-form",
        performance: %{
          "date_text" => "1611",
          "cast_from_cast_list" => "true",
          "cast" => %{"0" => %{"surname" => "Fantasma", "role" => "Nadie"}}
        }
      )
      |> render_submit()

      assert render(lv) =~
               error("is already set on another performance of this play")

      assert [_one] = Performances.list_for_play(play.id)
      assert Performances.list_actors() == []

      # The row is still on the form: corrected, the save writes it.
      lv
      |> form("#performance-form", performance: %{"cast_from_cast_list" => "false"})
      |> render_submit()

      assert [_, %{cast: [member]}] = Performances.list_for_play(play.id)
      assert {"Fantasma", "Nadie"} = hd(cast_of(%{cast: [member]}))
    end
  end

  describe "Rename" do
    setup %{play: play} do
      %{other: play_fixture(), name: unique("The King’s Men"), play: play}
    end

    test "corrects a company for every performance, and says how many",
         %{conn: conn, play: play, other: other, name: name} do
      performance_fixture(play, %{"company_name" => name})
      performance_fixture(other, %{"company_name" => String.downcase(name)})
      new_name = unique("The King’s Company")

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> button("Edit", "1610, #{name}") |> render_click()
      assert has_element?(lv, "#performance_company_name[value='#{name}']")

      rename_button(lv, name) |> render_click()
      assert lv |> element("#rename-panel") |> render() =~ "2 representaciones en 2 obras"
      lv |> form("#rename-form", rename: %{"name" => new_name}) |> render_submit()

      assert [%{name: ^new_name}] = Performances.list_companies()
      assert [%{company: %{name: ^new_name}}] = Performances.list_for_play(other.id)
      refute has_element?(lv, "#rename-panel")

      # The open form follows the company: saving it keeps the one company.
      assert has_element?(lv, "#performance_company_name[value='#{new_name}']")
      lv |> form("#performance-form") |> render_submit()

      assert [%{name: ^new_name}] = Performances.list_companies()
      assert [%{company: %{name: ^new_name}}] = Performances.list_for_play(play.id)
    end

    test "is offered only beside a company that exists", %{conn: conn, play: play, name: name} do
      performance_fixture(play, %{"company_name" => name})
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> element("button", t("Add performance")) |> render_click()

      refute has_element?(lv, "button", t("Rename"))
      assert render(lv) =~ t("Rename corrects the company for every performance that names it.")

      lv |> form("#performance-form", performance: %{"company_name" => name}) |> render_change()
      assert has_element?(lv, "button[aria-label='#{t("Rename %{name}", name: name)}']")

      lv
      |> form("#performance-form", performance: %{"company_name" => "Nadie"})
      |> render_change()

      refute has_element?(lv, "button", t("Rename"))
    end

    test "corrects an actor's four fields", %{conn: conn, play: play} do
      performance = performance_fixture(play)
      {:ok, actor} = Performances.find_or_create_actor(%{"surname" => "Hart, Charles Hart"})

      {:ok, _} =
        Performances.put_cast(performance, [%{"actor_id" => actor.id, "role" => "Othello"}])

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> button("Edit", "1610") |> render_click()
      rename_button(lv, "Hart, Charles Hart") |> render_click()
      assert lv |> element("#rename-panel") |> render() =~ "1 representación en 1 obra"

      lv
      |> form("#rename-form",
        rename: %{"surname" => "Hart", "forename" => "Charles", "nickname" => "", "sex" => "man"}
      )
      |> render_submit()

      assert %{surname: "Hart", forename: "Charles", sex: "man"} =
               Performances.get_actor(actor.id)

      assert lv |> element("#performance-#{performance.id}") |> render() =~
               "Charles Hart (Othello)"

      # The open form follows the actor: saving it keeps the one actor.
      assert has_element?(lv, "#cast-0-actor-name[value='Charles Hart']")
      lv |> form("#performance-form") |> render_submit()
      assert [%{id: id}] = Performances.list_actors()
      assert id == actor.id
    end

    test "onto a taken name is refused, and the page still answers",
         %{conn: conn, play: play, name: name} do
      duke = unique("The Duke’s Company")
      performance_fixture(play, %{"date_text" => "1609", "company_name" => duke})
      performance_fixture(play, %{"company_name" => name})

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> button("Edit", "1610, #{name}") |> render_click()
      rename_button(lv, name) |> render_click()

      html =
        lv |> form("#rename-form", rename: %{"name" => String.upcase(duke)}) |> render_submit()

      assert html =~ error("is already the name of another company")

      assert lv |> element("#rename-form") |> render() =~
               error("is already the name of another company")

      assert Enum.sort(Enum.map(Performances.list_companies(), & &1.name)) ==
               Enum.sort([duke, name])

      # Still alive: the same panel takes a free name.
      new_name = unique("The Queen’s Men")
      lv |> form("#rename-form", rename: %{"name" => new_name}) |> render_submit()

      assert Enum.sort(Enum.map(Performances.list_companies(), & &1.name)) ==
               Enum.sort([duke, new_name])
    end

    test "an actor onto the names of another is refused, and the page still answers",
         %{conn: conn, play: play} do
      performance = performance_fixture(play)

      {:ok, hart} =
        Performances.find_or_create_actor(%{"surname" => "Hart", "forename" => "Charles"})

      {:ok, wrong} = Performances.find_or_create_actor(%{"surname" => "Hart, Charles"})

      {:ok, _} =
        Performances.put_cast(performance, [
          %{"actor_id" => hart.id},
          %{"actor_id" => wrong.id}
        ])

      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> button("Edit", "1610") |> render_click()
      rename_button(lv, "Hart, Charles") |> render_click()

      html =
        lv
        |> form("#rename-form", rename: %{"surname" => "HART", "forename" => "charles"})
        |> render_submit()

      assert html =~ error("is already another actor")
      assert %{surname: "Hart, Charles"} = Performances.get_actor(wrong.id)

      lv
      |> form("#rename-form", rename: %{"surname" => "Hart", "forename" => "Michael"})
      |> render_submit()

      assert %{forename: "Michael"} = Performances.get_actor(wrong.id)
    end

    test "is logged, as an update of the company", %{conn: conn, play: play, name: name} do
      performance_fixture(play, %{"company_name" => name})
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")
      lv |> button("Edit", "1610, #{name}") |> render_click()
      rename_button(lv, name) |> render_click()
      lv |> form("#rename-form", rename: %{"name" => unique("Nuevo nombre")}) |> render_submit()

      assert [%{action: "update", metadata: %{"from" => ^name}}] =
               ActivityLog.list_entries(resource_type: "performance_company")
    end

    test "a company or actor that is gone says so", %{conn: conn, play: play, name: name} do
      performance = performance_fixture(play, %{"company_name" => name})
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/#{play.id}/performances")

      for event <- ~w(rename_company rename_actor), id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert render_click(lv, event, %{"id" => id}) =~
                 t("That item no longer exists. The list has been refreshed."),
               "#{event} #{id}"

        refute has_element?(lv, "#rename-panel")
      end

      # Deleted under an open panel.
      lv |> button("Edit", "1610, #{name}") |> render_click()
      rename_button(lv, name) |> render_click()
      {:ok, _} = Performances.delete_performance(performance)

      html = lv |> form("#rename-form", rename: %{"name" => unique("Otro")}) |> render_submit()
      assert html =~ t("That item no longer exists. The list has been refreshed.")
      refute has_element?(lv, "#rename-panel")
    end
  end
end
