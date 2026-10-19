defmodule Playcode.PerformancesTest do
  @moduledoc """
  A play's historical performances through `Playcode.Performances`: the years read from a
  date as FileMaker wrote it, order, validation and scoping. Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Performances
  alias Playcode.Performances.Performance

  defp dates(play), do: play.id |> Performances.list_for_play() |> Enum.map(& &1.date_text)

  describe "years/1" do
    test "reads FileMaker's dates" do
      for {date, years} <- [
            {"1610", {1610, 1610}},
            {"1597-9", {1597, 1599}},
            {"1610-11", {1610, 1611}},
            {"1612 - 1613", {1612, 1613}},
            {"c. 1622-5", {1622, 1625}},
            {"1590s", {1590, 1599}},
            {"c. 1620", {1620, 1620}},
            {"Before 1642", {nil, 1642}},
            {"before 1642", {nil, 1642}},
            {"04/05//1674", {1674, 1674}},
            {"1603, 1609-1642", {1603, 1642}},
            {"30 y 31 de marzo de 1682", {1682, 1682}},
            {"1701-1702: 1 Oct, 21 Oct", {1701, 1702}},
            {"¿1683?¿1684?", {1683, 1684}},
            {"desconocida", {nil, nil}},
            {nil, {nil, nil}}
          ],
          do: assert(Performance.years(date) == years, inspect(date))
    end
  end

  describe "venue types" do
    test "are FileMaker's eight, with its Spanish and English labels" do
      assert Performance.venue_types() ==
               ~w(public_theatre palace street other private_theatre unknown university
                  commercial_theatre)

      assert Performance.venue_type_label("public_theatre", "es") == "teatro público"
      assert Performance.venue_type_label("palace", "en") == "palace / court"
      assert Performance.venue_type_label("university", "es") == "universidad / “inns of court”"
      assert Performance.venue_type_label("commercial_theatre", "en") == "commercial theatre"
    end

    test "a performance's type is one of the eight" do
      play = play_fixture()

      assert {:error, changeset} =
               Performances.create_performance(%{"play_id" => play.id, "venue_type" => "theatre"})

      assert errors_on(changeset).venue_type == ["is invalid"]

      for type <- Performance.venue_types() do
        assert {:ok, _} =
                 Performances.create_performance(%{"play_id" => play.id, "venue_type" => type})
      end
    end
  end

  describe "a play's performances" do
    test "come in order of year, the undated last, then as entered" do
      play = play_fixture()

      for date <- ["1623", "Before 1610", nil, "1610"] do
        performance_fixture(play, %{"date_text" => date, "note" => "Nota"})
      end

      assert dates(play) == ["Before 1610", "1610", "1623", nil]
    end

    test "are listed with their company, place, source and cast" do
      play = play_fixture()
      place = place_fixture(%{"name" => "Londres"})
      source = bibliography_fixture(play_fixture(), %{"monogr_title" => "Wiggins"})
      company = Playcode.Repo.insert!(%Performances.Company{name: "King's Men"})
      actor = Playcode.Repo.insert!(%Performances.Actor{surname: "Burbage"})

      performance =
        performance_fixture(play, %{
          "company_id" => company.id,
          "place_id" => place.id,
          "source_entry_id" => source.entry_id
        })

      Playcode.Repo.insert!(%Performances.CastMember{
        performance_id: performance.id,
        actor_id: actor.id,
        role: "Hamlet",
        position: 0
      })

      assert [listed] = Performances.list_for_play(play.id)
      assert listed.company.name == "King's Men"
      assert Playcode.Places.display_name(listed.place) == "Londres"
      assert listed.source.id == source.entry_id
      assert [%{role: "Hamlet", actor: %{surname: "Burbage"}}] = listed.cast
    end

    test "a new one goes last, whatever position it is given, and a deleted one leaves no tie" do
      play = play_fixture()

      [_first, second, _third] =
        for note <- ~w(Uno Dos Tres), do: performance_fixture(play, %{"note" => note})

      {:ok, _} = Performances.delete_performance(second)
      performance_fixture(play, %{"note" => "Cuatro", "position" => 0})

      listed = Performances.list_for_play(play.id)
      assert Enum.map(listed, & &1.note) == ~w(Uno Tres Cuatro)

      # Same year, same second: only the positions tell them apart.
      positions = Enum.map(listed, & &1.position)
      assert positions == positions |> Enum.uniq() |> Enum.sort()
    end

    test "the years are filled from the date when left blank, and a curator's are kept" do
      play = play_fixture()

      performance = performance_fixture(play, %{"date_text" => "1597-9"})
      assert {performance.year_from, performance.year_to} == {1597, 1599}

      {:ok, performance} =
        Performances.update_performance(performance, %{
          "date_text" => "c. 1598",
          "year_from" => "1590"
        })

      assert {performance.year_from, performance.year_to} == {1590, 1598}

      {:ok, performance} = Performances.update_performance(performance, %{"note" => "Nota"})
      assert {performance.year_from, performance.year_to} == {1590, 1598}

      # The form sends every field back: a year the date gave follows the new date, one
      # a curator set stays.
      {:ok, performance} =
        Performances.update_performance(performance, %{
          "date_text" => "1601",
          "year_from" => "1590",
          "year_to" => "1598"
        })

      assert {performance.year_from, performance.year_to} == {1590, 1601}
    end

    test "a year typed along with a new date is a curator's, even when the old date gave it" do
      performance = performance_fixture(play_fixture(), %{"date_text" => "1620"})
      {:ok, performance} = Performances.update_performance(performance, %{"year_from" => "1615"})

      {:ok, performance} =
        Performances.update_performance(performance, %{
          "date_text" => "1630",
          "year_from" => "1620"
        })

      assert {performance.year_from, performance.year_to} == {1620, 1630}
    end

    test "a date with no year leaves the years blank" do
      performance = performance_fixture(play_fixture(), %{"date_text" => "desconocida"})
      assert {performance.year_from, performance.year_to} == {nil, nil}
    end

    test "need a date, a venue, a company or a note" do
      play = play_fixture()

      assert {:error, changeset} =
               Performances.create_performance(%{"play_id" => play.id, "venue" => "  "})

      assert errors_on(changeset).date_text == ["needs a date, a venue, a company or a note"]
    end

    test "only one of a play's takes its cast from the cast list" do
      play = play_fixture()
      first = performance_fixture(play, %{"cast_from_cast_list" => "true"})

      assert {:error, changeset} =
               Performances.create_performance(%{
                 "play_id" => play.id,
                 "date_text" => "1611",
                 "cast_from_cast_list" => "true"
               })

      assert errors_on(changeset).cast_from_cast_list ==
               ["is already set on another performance of this play"]

      # Another play has its own, and the first may be edited and unset.
      assert performance_fixture(play_fixture(), %{"cast_from_cast_list" => "true"})
      assert {:ok, _} = Performances.update_performance(first, %{"note" => "Nota"})

      assert {:ok, _} =
               Performances.update_performance(first, %{"cast_from_cast_list" => "false"})
    end
  end

  describe "get_performance/2" do
    test "finds a play's own performance" do
      play = play_fixture()
      performance = performance_fixture(play)

      assert Performances.get_performance(play.id, performance.id).id == performance.id
    end

    test "a performance of another play, a deleted one or a malformed id is nil" do
      play = play_fixture()
      performance = performance_fixture(play)

      assert Performances.get_performance(play_fixture().id, performance.id) == nil
      assert Performances.get_performance(play.id, "no-uuid") == nil
      assert Performances.get_performance(play.id, nil) == nil

      assert {:ok, _} = Performances.delete_performance(performance)
      assert Performances.get_performance(play.id, performance.id) == nil
    end
  end
end
