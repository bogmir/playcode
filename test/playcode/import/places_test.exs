defmodule Playcode.Import.PlacesTest do
  @moduledoc """
  What the places import would write, from a sample of FileMaker's T10 tables with one play
  per rule (test/fixtures/filemaker/places/regenerate.exs). A planned place is named here
  by its Spanish preferred name.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Import.Places, as: Import

  @dump "test/fixtures/filemaker/places"

  setup do
    plays =
      for code <- ~w(
            EMOTHE0005_LAminta EMOTHE0006_IlPastorFido EMOTHE0007_LaCalandria
            EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark EMOTHE0038_AntonyAndCleopatra
            EMOTHE0151_AsYouLikeIt EMOTHE0153_TheTragedyOfRomeoAndJuliet
            EMOTHE0262_TheShoemakersHoliday EMOTHE0337_TheTragedyOfMariam
            EMOTHE0354_TheBrokenHeart EMOTHE0367_Endymion EMOTHE0394_EntreBobosAndaElJuego
            EMOTHE0545_LaTraicionEnLaAmistad EMOTHE0653_TheShyCourtier
            EMOTHE0697_TheTragedyOfOthelloTheMoorOfVenice
          ),
          do: play_fixture(%{"code" => code})

    {:ok, data} = Import.load(@dump)
    %{plays: plays, data: data}
  end

  defp plan(%{plays: plays, data: data}), do: Import.plan(data, plays)

  defp es(plan, key) do
    %{attrs: %{"names" => names}} = Enum.find(plan.places, &(&1.key == key))
    Enum.find_value(names, &(&1["language"] == "es" and &1["is_preferred"] and &1["name"]))
  end

  defp named(plan, es_name), do: Enum.filter(plan.places, &(es(plan, &1.key) == es_name))

  defp place(plan, es_name) do
    [place] = named(plan, es_name)
    place
  end

  defp parent(plan, es_name) do
    case place(plan, es_name).parent do
      nil -> nil
      key -> es(plan, key)
    end
  end

  defp names(place) do
    for name <- place.attrs["names"],
        do: {name["language"], name["name"], name["is_preferred"], name["is_historical"]}
  end

  test "one Rome, whatever state FileMaker filed it under", ctx do
    assert [_rome] = named(plan(ctx), "Roma")
  end

  test "a place comes after its parent, which is planned too", ctx do
    places = plan(ctx).places
    keys = Enum.map(places, & &1.key)

    for %{parent: parent, key: key} <- places, parent do
      assert Enum.find_index(keys, &(&1 == parent)) < Enum.find_index(keys, &(&1 == key))
    end
  end

  test "a renamed place keeps its old names as historical ones", ctx do
    plan = plan(ctx)
    elsinor = place(plan, "Elsinor")

    assert names(elsinor) == [
             {"es", "Elsinor", true, false},
             {"en", "Helsingør", true, false},
             {"fr", "Elseneur", true, false},
             {"it", "Helsingør", true, false},
             {"pt", "Helsingor", true, false},
             {"en", "Elsinore", false, true},
             {"it", "Elsinora", false, true},
             {"pt", "Elsenor", false, true}
           ]

    assert Enum.map(elsinor.attrs["names"], & &1["position"]) == Enum.to_list(0..7)
    assert parent(plan, "Elsinor") == "Dinamarca"
    assert "Elsinore → Helsingør" in plan.merged
  end

  test "a place inside another is not merged into it", ctx do
    plan = plan(ctx)

    assert place(plan, "Old Ford").attrs["type"] == "district"
    assert parent(plan, "Old Ford") == "Londres"
    assert parent(plan, "Londres") == "Reino Unido"
  end

  test "a historical state is a place under its continent; one named like today's country is that country",
       ctx do
    plan = plan(ctx)

    assert place(plan, "Reino de Dinamarca").attrs["type"] == "country"
    assert parent(plan, "Reino de Dinamarca") == "Europa"
    assert [_france] = named(plan, "Francia")
    assert parent(plan, "Ardenas") == "Francia"
  end

  test "a state filed on two continents has none", ctx do
    plan = plan(ctx)

    assert parent(plan, "República romana") == nil
    assert parent(plan, "Egipto ptolemaico") == "África"
  end

  test "today's geography wins over FileMaker's missing country", ctx do
    plan = plan(ctx)

    assert parent(plan, "Verona") == "Italia"
    assert parent(plan, "Mantua") == "Italia"
    assert parent(plan, "Esparta") == "Grecia"
    assert {"es", "Lacedemonia", false, true} in names(place(plan, "Esparta"))
    assert parent(plan, "Península itálica") == "Europa"
  end

  test "vague places are typed, the generic ones fictional and shared", ctx do
    plan = plan(ctx)

    assert place(plan, "Ardenas").attrs["type"] == "forest"
    assert place(plan, "Miseno").attrs["type"] == "town"

    assert %{attrs: %{"type" => "forest", "is_fictional" => true}} =
             place(plan, "bosque pastoril")

    assert place(plan, "Ardenas").attrs["is_fictional"] == false
    assert named(plan, "sin especificar") == []
  end

  test "a place the gazetteer has under any of its names is reused, never changed", ctx do
    rome =
      place_fixture(%{
        "names" => [%{"name" => "Rome", "language" => "en", "is_preferred" => "true"}]
      })

    plan = plan(ctx)

    assert %{existing: %{id: id}, parent: nil} = place(plan, "Roma")
    assert id == rome.id
    assert %{existing: nil} = place(plan, "Atenas")
    assert plan.reused == ["Rome (T10.4:130) → #{rome.slug}"]
  end

  test "the dry run lists what a person must check: twinless records, places with no country",
       ctx do
    plan = plan(ctx)

    assert plan.twinless == []
    assert plan.no_country == ["Italian Peninsula (T10.3:116)", "Ancient Greece (T10.3:134)"]

    # Without its T10.X pair, Mariam's Jerusalem is a record of its own, under its continent.
    plan =
      ctx
      |> update_in([:data, :pairs], fn pairs ->
        Enum.reject(pairs, &(&1["_k_IdToponimoHistorico"] == "156"))
      end)
      |> plan()

    assert plan.twinless == ["Jerusalem (T10.4:156)"]
    assert parent(plan, "Jerusalén") == "Asia"
    assert "Jerusalem (T10.4:156)" in plan.no_country
  end

  test "a modern record filed under a historical state goes under the state's modern twin", ctx do
    # FileMaker's modern Miseno is under Italia; put it under Castilla, whose twin is España.
    plan =
      ctx
      |> update_in([:data, :vague], fn rows ->
        Enum.map(rows, fn
          %{"_kp_IdLocvaga" => "87"} = row -> %{row | "_k_IdPais" => "1367"}
          row -> row
        end)
      end)
      |> plan()

    assert parent(plan, "Miseno") == "España"
  end
end
