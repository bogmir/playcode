defmodule Playcode.PerformancesTest do
  @moduledoc """
  A play's historical performances through `Playcode.Performances`: the years read from a
  date as FileMaker wrote it, order, validation and scoping. Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Performances
  alias Playcode.Performances.{Actor, Performance}

  defp dates(play), do: play.id |> Performances.list_for_play() |> Enum.map(& &1.date_text)

  # Company names are unique across the corpus, so two async tests naming the same company
  # would queue on the index: every name here is made unique.
  defp unique(name), do: "#{name} #{System.unique_integer([:positive])}"

  defp company!(name) do
    {:ok, company} = Performances.find_or_create_company(unique(name))
    company
  end

  defp actor!(attrs) do
    {:ok, actor} = Performances.find_or_create_actor(attrs)
    actor
  end

  defp company_names, do: Enum.map(Performances.list_companies(), & &1.name)

  defp cast(performance, actors) do
    rows = for {actor, role} <- actors, do: %{"actor_id" => actor.id, "role" => role}
    {:ok, performance} = Performances.put_cast(performance, rows)
    performance
  end

  defp roles(play) do
    [performance] = Performances.list_for_play(play.id)
    Enum.map(performance.cast, & &1.role)
  end

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

    test "carry their place's names preferred first, as the Places section loads them" do
      place =
        place_fixture(%{
          "names" => [
            %{"name" => "Londinium", "language" => "es"},
            %{"name" => "Londres", "language" => "es", "is_preferred" => "true"}
          ]
        })

      play = play_fixture()
      performance_fixture(play, %{"place_id" => place.id})

      assert [%{place: %{names: names}}] = Performances.list_for_play(play.id)
      assert Enum.map(names, & &1.name) == ["Londres", "Londinium"]
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

      # Setting it on a second, existing performance is refused the same way.
      second = performance_fixture(play, %{"note" => "Otra"})

      assert {:error, changeset} =
               Performances.update_performance(second, %{"cast_from_cast_list" => "true"})

      assert errors_on(changeset).cast_from_cast_list ==
               ["is already set on another performance of this play"]

      # Another play has its own, and the first may be edited and unset.
      assert performance_fixture(play_fixture(), %{"cast_from_cast_list" => "true"})
      assert {:ok, _} = Performances.update_performance(first, %{"note" => "Nota"})

      assert {:ok, _} =
               Performances.update_performance(first, %{"cast_from_cast_list" => "false"})
    end
  end

  describe "companies" do
    test "a company is found by its name whatever the case, else created" do
      name = unique("The Duke’s Company")
      {:ok, company} = Performances.find_or_create_company(name)

      for same <- [name, String.downcase(name), "  #{name}  "] do
        assert {:ok, %{id: id}} = Performances.find_or_create_company(same)
        assert id == company.id
      end

      assert {:ok, other} = Performances.find_or_create_company(unique("The King’s Men"))
      refute other.id == company.id
      assert company_names() == Enum.sort([name, other.name])

      assert {:error, changeset} = Performances.find_or_create_company("  ")
      assert errors_on(changeset).name == ["can't be blank"]
    end

    test "are listed by name" do
      for name <- ~w(Zeta Alfa Omega), do: company!(name)

      assert company_names() |> Enum.map(&(&1 |> String.split() |> hd())) ==
               ~w(Alfa Omega Zeta)
    end

    test "renaming one renames it for every performance that names it" do
      company = company!("The Duke’s Company")
      first = performance_fixture(play_fixture(), %{"company_id" => company.id})
      second = performance_fixture(play_fixture(), %{"company_id" => company.id})
      name = unique("The King’s Men")

      assert {:ok, renamed} = Performances.update_company(company, %{"name" => name})
      assert renamed.name == name

      for performance <- [first, second],
          do:
            assert([%{company: %{name: ^name}}] = Performances.list_for_play(performance.play_id))

      assert Performances.usage(renamed) == %{performances: 2, plays: 2}
    end

    test "usage counts a play once however many of its performances name the company" do
      company = company!("Company")
      play = play_fixture()
      performance_fixture(play, %{"company_id" => company.id})
      performance_fixture(play, %{"company_id" => company.id, "date_text" => "1611"})
      performance_fixture(play_fixture(), %{"company_id" => company.id})

      assert Performances.usage(company) == %{performances: 3, plays: 2}
    end

    test "a rename onto a name another company has is refused, a change of case on its own is not" do
      company = company!("Company")
      other = company!("Other")

      assert {:error, changeset} =
               Performances.update_company(company, %{"name" => String.upcase(other.name)})

      assert errors_on(changeset).name == ["is already the name of another company"]

      assert {:ok, renamed} =
               Performances.update_company(company, %{"name" => String.upcase(company.name)})

      assert renamed.name == String.upcase(company.name)
    end

    test "get_company/1 is nil for a malformed or missing id" do
      company = company!("Company")

      assert Performances.get_company(company.id).name == company.name
      assert Performances.get_company("no-uuid") == nil
      assert Performances.get_company(Ecto.UUID.generate()) == nil
      assert Performances.get_company(nil) == nil
    end
  end

  describe "actors" do
    test "an actor is found by surname, forename and nickname, else created" do
      burbage = %{"surname" => "Burbage", "forename" => "Richard"}
      actor = actor!(burbage)

      assert actor!(burbage).id == actor.id
      assert actor!(%{"surname" => "BURBAGE", "forename" => " richard "}).id == actor.id

      with_nickname = actor!(Map.put(burbage, "nickname", "Dick"))
      other_forename = actor!(%{burbage | "forename" => "Cuthbert"})
      assert length(Enum.uniq([actor.id, with_nickname.id, other_forename.id])) == 3
    end

    test "the sex is not part of who an actor is: the same names are one actor, whose sex is filled in" do
      names = %{"surname" => "Du Parc", "forename" => "Marquise-Thérèse", "nickname" => "Mlle"}
      actor = actor!(names)
      assert actor.sex == nil

      woman = actor!(Map.put(names, "sex", "woman"))
      assert woman.id == actor.id
      assert woman.sex == "woman"

      # Found again with none, or with the other sex: the actor is not changed.
      assert %{id: id, sex: "woman"} = actor!(names)
      assert id == actor.id
      assert %{id: ^id, sex: "woman"} = actor!(Map.put(names, "sex", "man"))
      assert [%{sex: "woman"}] = Performances.list_actors()

      # A sex that is no sex is refused whether the actor exists without one or not.
      actor!(%{"surname" => "Lowin"})

      for surname <- ["Lowin", "Taylor"] do
        assert {:error, changeset} =
                 Performances.find_or_create_actor(%{"surname" => surname, "sex" => "other"})

        assert errors_on(changeset).sex == ["is invalid"]
      end
    end

    test "an actor needs a surname or a nickname" do
      assert {:error, changeset} = Performances.find_or_create_actor(%{"forename" => "Jean"})
      assert errors_on(changeset).surname == ["needs a surname or a nickname"]

      assert {:error, changeset} = Performances.find_or_create_actor(%{"surname" => "  "})
      assert errors_on(changeset).surname == ["needs a surname or a nickname"]

      assert {:ok, _} = Performances.find_or_create_actor(%{"nickname" => "Rosimond"})
    end

    test "a sex is a man, a woman or none" do
      assert {:error, changeset} =
               Performances.find_or_create_actor(%{"surname" => "Lowin", "sex" => "other"})

      assert errors_on(changeset).sex == ["is invalid"]

      assert %{sex: nil} = actor!(%{"surname" => "Lowin", "sex" => ""})
      assert %{sex: "woman"} = actor!(%{"surname" => "Betterton", "sex" => "woman"})
    end

    test "an actor reads as forename, surname, then the nickname in quotes" do
      moliere =
        actor!(%{"surname" => "Poquelin", "forename" => "Jean François", "nickname" => "Molière"})

      assert Actor.display_name(moliere) == "Jean François Poquelin, “Molière”"
      assert Actor.display_name(actor!(%{"nickname" => "Rosimond"})) == "Rosimond"
      assert Actor.display_name(actor!(%{"surname" => "Lowin"})) == "Lowin"
    end

    test "are listed by surname, forename, then nickname, a nickname alone standing for the surname" do
      for attrs <- [
            %{"surname" => "Taylor", "forename" => "Joseph"},
            %{"surname" => "Burbage", "forename" => "Richard", "nickname" => "Young Dick"},
            %{"surname" => "Burbage", "forename" => "Richard"},
            %{"surname" => "Taylor", "forename" => "John"},
            %{"nickname" => "Gros-René"}
          ],
          do: actor!(attrs)

      assert Performances.list_actors() |> Enum.map(&Actor.display_name/1) ==
               [
                 "Richard Burbage",
                 "Richard Burbage, “Young Dick”",
                 "Gros-René",
                 "John Taylor",
                 "Joseph Taylor"
               ]
    end

    test "renaming one renames it for every performance that names it" do
      actor = actor!(%{"surname" => "Hart", "forename" => "Charles Hart"})
      first = cast(performance_fixture(play_fixture()), [{actor, "Otelo"}])
      second = cast(performance_fixture(play_fixture()), [{actor, nil}])

      assert {:ok, renamed} =
               Performances.update_actor(actor, %{"surname" => "Hart", "forename" => "Charles"})

      for performance <- [first, second] do
        assert [%{cast: [%{actor: listed}]}] = Performances.list_for_play(performance.play_id)
        assert Actor.display_name(listed) == "Charles Hart"
      end

      assert Performances.usage(renamed) == %{performances: 2, plays: 2}
    end

    test "a rename onto another actor's names is refused, one that changes only the case or the sex is not" do
      actor = actor!(%{"surname" => "Taylor", "forename" => "John"})
      other = actor!(%{"surname" => "John", "forename" => "Taylor"})

      assert {:error, changeset} =
               Performances.update_actor(other, %{"surname" => "taylor", "forename" => "JOHN"})

      assert errors_on(changeset).surname == ["is already another actor"]

      assert {:ok, _} = Performances.update_actor(actor, %{"surname" => "TAYLOR"})
      assert {:ok, %{sex: "man"}} = Performances.update_actor(actor, %{"sex" => "man"})
    end

    test "get_actor/1 is nil for a malformed or missing id" do
      actor = actor!(%{"surname" => "Burbage"})

      assert Performances.get_actor(actor.id).surname == "Burbage"
      assert Performances.get_actor("no-uuid") == nil
      assert Performances.get_actor(Ecto.UUID.generate()) == nil
      assert Performances.get_actor(nil) == nil
    end
  end

  describe "a performance's cast" do
    test "keeps the order it is given, and a new list replaces the old" do
      [burbage, lowin, taylor] = for s <- ~w(Burbage Lowin Taylor), do: actor!(%{"surname" => s})
      play = play_fixture()
      performance = performance_fixture(play)

      cast(performance, [{taylor, "Laertes"}, {burbage, "Hamlet"}, {lowin, "  "}])
      assert [%{cast: cast}] = Performances.list_for_play(play.id)
      assert Enum.map(cast, & &1.role) == ["Laertes", "Hamlet", nil]
      assert Enum.map(cast, & &1.actor_id) == [taylor.id, burbage.id, lowin.id]

      # Rows that share a position come back in no promised order, so check it is distinct.
      assert Enum.map(cast, & &1.position) == [0, 1, 2]

      cast(performance, [{lowin, "Polonius"}, {burbage, "Hamlet"}])
      assert [%{cast: cast}] = Performances.list_for_play(play.id)
      assert Enum.map(cast, & &1.role) == ["Polonius", "Hamlet"]

      assert {:ok, %{cast: []}} = Performances.put_cast(performance, [])
      assert [%{cast: []}] = Performances.list_for_play(play.id)
    end

    test "squeezes a role's spaces and line breaks" do
      actor = actor!(%{"surname" => "Burbage"})

      assert %{cast: [%{role: "Don Juan\nTenorio"}]} =
               cast(performance_fixture(play_fixture()), [{actor, " Don  Juan\r\n Tenorio "}])
    end

    test "returns the performance with its cast and the actors" do
      actor = actor!(%{"surname" => "Burbage"})
      performance = performance_fixture(play_fixture())

      assert {:ok, %{cast: [%{role: "Hamlet", actor: %{surname: "Burbage"}}]}} =
               Performances.put_cast(performance, [
                 %{"actor_id" => actor.id, "role" => "Hamlet"}
               ])
    end

    test "refuses a row without an actor, with a malformed or missing one, and keeps the cast" do
      actor = actor!(%{"surname" => "Burbage"})
      play = play_fixture()
      performance = cast(performance_fixture(play), [{actor, "Hamlet"}])

      for row <- [
            %{"role" => "Hamlet"},
            %{"actor_id" => "no-uuid", "role" => "Hamlet"},
            %{"actor_id" => Ecto.UUID.generate(), "role" => "Hamlet"}
          ] do
        assert {:error, changeset} =
                 Performances.put_cast(performance, [%{"actor_id" => actor.id}, row])

        refute changeset.valid?
      end

      assert roles(play) == ["Hamlet"]
    end
  end

  describe "a performance written with its cast" do
    test "a cast of rows replaces the cast; no cast leaves it as it is" do
      betterton = actor!(%{"surname" => "Betterton", "forename" => "Thomas"})
      play = play_fixture()
      performance = performance_fixture(play, %{"company_name" => unique("Company")})

      rows = [
        %{"actor_name" => " thomas  BETTERTON ", "role" => "Mirabell"},
        %{
          "actor_name" => "",
          "surname" => "Bracegirdle",
          "sex" => "woman",
          "role" => "Millamant"
        },
        %{"actor_name" => "", "role" => ""},
        # Names win over a name: the row is a new actor, not Betterton.
        %{"actor_name" => "Thomas Betterton", "surname" => "Mohun", "role" => "Fainall"}
      ]

      assert {:ok, %{cast: cast}} =
               Performances.update_performance(performance, %{"cast" => rows})

      assert Enum.map(cast, & &1.role) == ["Mirabell", "Millamant", "Fainall"]
      assert hd(cast).actor_id == betterton.id
      assert [%{sex: "woman"}, %{surname: "Mohun"}] = Enum.map(tl(cast), & &1.actor)

      assert {:ok, _} = Performances.update_performance(performance, %{"venue" => "Globe"})
      assert [%{venue: "Globe", cast: [_, _, _]}] = Performances.list_for_play(play.id)

      assert {:ok, %{cast: []}} = Performances.update_performance(performance, %{"cast" => []})
      assert Performances.list_actors() == []
    end

    test "every row that names no actor is refused with its number, and nothing is written" do
      play = play_fixture()
      company = unique("Company")

      rows = [
        %{"surname" => "Nuevo"},
        %{"role" => "Sin actor"},
        %{},
        %{"actor_name" => "Nadie"},
        %{"forename" => "Solo"}
      ]

      assert {:error, changeset} =
               Performances.create_performance(%{
                 "play_id" => play.id,
                 "company_name" => company,
                 "date_text" => "1700",
                 "cast" => rows
               })

      assert [
               {1, "needs an actor"},
               {3, "names no actor that exists: add one with a surname or a nickname"},
               {4, "needs a surname or a nickname"}
             ] ==
               for({:cast, {message, opts}} <- changeset.errors, do: {opts[:row], message})

      assert Performances.list_for_play(play.id) == []
      assert Performances.list_actors() == []
      refute company in company_names()
    end
  end

  describe "a company or actor no performance names" do
    test "is deleted with the last performance that names it, and kept while another does" do
      company = company!("Company")
      actor = actor!(%{"surname" => "Burbage"})

      first =
        cast(performance_fixture(play_fixture(), %{"company_id" => company.id}), [{actor, nil}])

      second =
        cast(performance_fixture(play_fixture(), %{"company_id" => company.id}), [{actor, nil}])

      assert {:ok, _} = Performances.delete_performance(first)
      assert company_names() == [company.name]
      assert [%{surname: "Burbage"}] = Performances.list_actors()

      assert {:ok, _} = Performances.delete_performance(second)
      assert Performances.list_companies() == []
      assert Performances.list_actors() == []
    end

    test "is deleted when the performance is pointed at another company" do
      first = company!("First")
      second = company!("Second")
      performance = performance_fixture(play_fixture(), %{"company_id" => first.id})
      other = performance_fixture(play_fixture(), %{"company_id" => second.id})

      assert {:ok, _} = Performances.update_performance(performance, %{"company_id" => second.id})
      assert company_names() == [second.name]

      # A change that fails deletes nothing, and one that leaves the company alone keeps it.
      assert {:error, _} =
               Performances.update_performance(other, %{
                 "company_id" => first.id,
                 "venue_type" => "theatre"
               })

      assert {:ok, _} = Performances.update_performance(other, %{"note" => "Nota"})
      assert company_names() == [second.name]
    end

    test "an actor is deleted when the cast drops its last row, and kept while another names it" do
      [burbage, lowin] = for s <- ~w(Burbage Lowin), do: actor!(%{"surname" => s})
      performance = cast(performance_fixture(play_fixture()), [{burbage, "Hamlet"}, {lowin, nil}])
      other = cast(performance_fixture(play_fixture()), [{burbage, "Otelo"}])

      cast(performance, [{lowin, nil}])
      assert Enum.map(Performances.list_actors(), & &1.surname) == ["Burbage", "Lowin"]

      cast(performance, [])
      assert Enum.map(Performances.list_actors(), & &1.surname) == ["Burbage"]

      cast(other, [])
      assert Performances.list_actors() == []
    end

    test "one a cast row still names stays when the cast is replaced by a list that keeps it" do
      actor = actor!(%{"surname" => "Burbage"})
      performance = cast(performance_fixture(play_fixture()), [{actor, "Hamlet"}])

      cast(performance, [{actor, "Otelo"}])
      assert Enum.map(Performances.list_actors(), & &1.id) == [actor.id]
    end
  end

  describe "a performance's source" do
    defp source?(entry), do: Playcode.Bibliography.get_entry(entry.id) != nil

    test "is kept beside the performance's own volume and pages" do
      source = catalogue_fixture(%{"volume" => "1", "pages" => "1-10"})

      performance =
        performance_fixture(play_fixture(), %{
          "source_entry_id" => source.id,
          "source_volume" => "6",
          "source_pages" => "83"
        })

      assert %{source: %{volume: "1", pages: "1-10"}, source_volume: "6", source_pages: "83"} =
               Performances.get_performance(performance.play_id, performance.id)
    end

    test "goes with the last performance that cites it" do
      source = catalogue_fixture()
      first = performance_fixture(play_fixture(), %{"source_entry_id" => source.id})
      second = performance_fixture(play_fixture(), %{"source_entry_id" => source.id})

      assert {:ok, _} = Performances.delete_performance(first)
      assert source?(source)

      assert {:ok, _} = Performances.delete_performance(second)
      refute source?(source)
    end

    test "goes when the performance is pointed at another source or none" do
      [first, second] = for _ <- 1..2, do: catalogue_fixture()
      performance = performance_fixture(play_fixture(), %{"source_entry_id" => first.id})

      assert {:ok, _} =
               Performances.update_performance(performance, %{"source_entry_id" => second.id})

      refute source?(first)
      assert source?(second)

      performance = Performances.get_performance(performance.play_id, performance.id)
      assert {:ok, _} = Performances.update_performance(performance, %{"source_entry_id" => nil})
      refute source?(second)
    end

    test "stays when a change fails or leaves it alone" do
      [first, second] = for _ <- 1..2, do: catalogue_fixture()
      performance = performance_fixture(play_fixture(), %{"source_entry_id" => first.id})

      assert {:error, _} =
               Performances.update_performance(performance, %{
                 "source_entry_id" => second.id,
                 "venue_type" => "theatre"
               })

      assert {:ok, _} = Performances.update_performance(performance, %{"note" => "Nota"})
      assert source?(first)
    end

    test "stays when a play's bibliography links it" do
      play = play_fixture()
      link = bibliography_fixture(play)
      performance = performance_fixture(play, %{"source_entry_id" => link.entry_id})

      assert {:ok, _} = Performances.delete_performance(performance)
      assert Playcode.Bibliography.get_entry(link.entry_id)
    end
  end

  describe "listing/4" do
    defp listing(play, locale \\ "en") do
      Performances.listing(
        Performances.list_for_play(play.id),
        Playcode.PlayContent.list_characters(play.id),
        Playcode.Places.gazetteer(),
        locale
      )
    end

    defp wiggins, do: catalogue_fixture(%{"monogr_title" => "British Drama 1533–1642"})

    defp character!(play, name, attrs \\ %{}) do
      {:ok, character} =
        Playcode.PlayContent.create_character(
          Map.merge(%{play_id: play.id, xml_id: String.upcase(name), name: name}, attrs)
        )

      character
    end

    test "a line is the date, then venue, place, company and venue type, the source's number and the performance's pages" do
      play = play_fixture()
      company = company!("The King’s Men")

      performance_fixture(play, %{
        "date_text" => "1610",
        "venue" => "Globe or Blackfriars",
        "company_id" => company.id,
        "venue_type" => "commercial_theatre",
        "source_entry_id" => wiggins().id,
        "source_volume" => "6",
        "source_pages" => "83"
      })

      assert %{lines: [line]} = listing(play)
      assert line.date == "1610"
      assert line.parts == ["Globe or Blackfriars", company.name, "commercial theatre"]
      assert line.source == 1
      assert line.range == "vol. 6, p. 83"
      assert line.reference == "[1] vol. 6, p. 83"

      assert %{lines: [%{parts: [_, _, "teatro comercial"]}]} = listing(play, "es")
    end

    test "the place line sits between the venue and the company, in the page's language" do
      play = play_fixture()
      company = company!("Troupe du Roi")

      place =
        place_fixture(%{
          "names" => [
            %{"name" => "Londres", "language" => "es", "is_preferred" => "true"},
            %{"name" => "London", "language" => "en", "is_preferred" => "true"}
          ]
        })

      performance_fixture(play, %{
        "venue" => "Whitehall",
        "place_id" => place.id,
        "company_id" => company.id
      })

      assert %{lines: [%{parts: ["Whitehall", "London", _]}]} = listing(play, "en")
      assert %{lines: [%{parts: ["Whitehall", "Londres", _]}]} = listing(play, "es")
    end

    test "a part that is missing is left out, and so is the range of a performance with no pages" do
      play = play_fixture()
      performance_fixture(play, %{"date_text" => "1611", "source_pages" => "5"})
      performance_fixture(play, %{"date_text" => "1612", "source_volume" => "2", "note" => "N"})
      performance_fixture(play, %{"date_text" => "1613", "note" => "Nota"})

      assert %{lines: [one, two, three]} = listing(play)
      assert {one.range, two.range, three.range} == {"p. 5", "vol. 2", nil}
      assert {one.parts, one.source, one.note} == {[], nil, nil}
      assert three.note == "Nota"
    end

    test "one source cited by several performances is numbered once" do
      play = play_fixture()
      chambers = catalogue_fixture(%{"monogr_title" => "The Elizabethan Stage"})
      wiggins = wiggins()

      for {date, source} <- [{"1612", chambers}, {"1610", wiggins}, {"1611", wiggins}],
          do: performance_fixture(play, %{"date_text" => date, "source_entry_id" => source.id})

      assert %{lines: lines, sources: sources} = listing(play)
      assert Enum.map(lines, & &1.source) == [1, 1, 2]

      assert Enum.map(sources, fn {n, entry} -> {n, entry.id} end) == [
               {1, wiggins.id},
               {2, chambers.id}
             ]
    end

    test "the cast reads actor (role)" do
      play = play_fixture()

      moliere =
        actor!(%{"forename" => "Jean François", "surname" => "Poquelin", "nickname" => "Molière"})

      rosimond = actor!(%{"nickname" => "Rosimond"})
      cast(performance_fixture(play), [{moliere, "Argan"}, {rosimond, " "}])

      assert %{lines: [%{cast: ["Jean François Poquelin, “Molière” (Argan)", "Rosimond"]}]} =
               listing(play)
    end

    test "the cast-list switch prints the characters' actors" do
      play = play_fixture()

      for {name, actor, position} <- [
            {"Fainall", "Mr. Betterton", 0},
            {"Waitwell", nil, 1},
            {"Mirabell", "Mr. Verbruggen", 2},
            {"Footman", "Mr. Hidden", 3}
          ] do
        character!(play, name, %{actor: actor, position: position, is_hidden: name == "Footman"})
      end

      performance_fixture(play, %{"cast_from_cast_list" => "true"})

      assert %{lines: [%{cast: ["Mr. Betterton (Fainall)", "Mr. Verbruggen (Mirabell)"]}]} =
               listing(play)
    end

    test "the cast-list switch with no actor in the cast list prints no cast, and the performance's own rows follow" do
      play = play_fixture()
      performance = performance_fixture(play, %{"cast_from_cast_list" => "true"})
      character!(play, "Fainall")

      assert %{lines: [%{cast: []}]} = listing(play)

      cast(performance, [{actor!(%{"surname" => "Bowen"}), "Witwoud"}])
      assert %{lines: [%{cast: ["Bowen (Witwoud)"]}]} = listing(play)

      character!(play, "Mirabell", %{actor: "Mr. Verbruggen"})

      assert %{lines: [%{cast: ["Mr. Verbruggen (Mirabell)", "Bowen (Witwoud)"]}]} = listing(play)
    end

    # Every text the TEI importer reads holds <emph> as <<…>> (CLAUDE.md): the listing hands it
    # on whole, for the page to print through the text renderers, and the cast list's
    # actors and roles are no exception.
    test "a venue, a cast name, a role and a note keep their italics markers" do
      play = play_fixture()
      character!(play, "<<Mirabell>>", %{actor: "Mr. <<Verbruggen>>"})

      performance =
        performance_fixture(play, %{
          "venue" => "<<Globe>>",
          "note" => "Hissed <<twice>>.",
          "cast_from_cast_list" => "true"
        })

      cast(performance, [{actor!(%{"surname" => "<<Mlle>> du Parc"}), "<<Argan>>"}])

      assert %{
               lines: [
                 %{
                   parts: ["<<Globe>>"],
                   note: "Hissed <<twice>>.",
                   cast: ["Mr. <<Verbruggen>> (<<Mirabell>>)", "<<Mlle>> du Parc (<<Argan>>)"]
                 }
               ]
             } = listing(play)
    end

    test "a performance with only a venue type prints that" do
      play = play_fixture()
      performance_fixture(play, %{"date_text" => nil, "venue_type" => "street"})

      assert %{lines: [%{date: nil, parts: ["street, square"]}], sources: []} = listing(play)
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
