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

  # A play's planned links as `{place, state}`, each by its Spanish name, in plan order.
  defp links(plan, code) do
    for %{code: ^code} = link <- plan.links,
        do: {es(plan, link.place), link.state && es(plan, link.state)}
  end

  defp note(plan, ref), do: Enum.find(plan.links, &(&1.ref == ref)).note

  defp with_link(ctx, id, fun) do
    update_in(ctx, [:data, :links], fn rows ->
      Enum.map(rows, &if(&1["_kp_IdObraAccionLugar"] == id, do: fun.(&1), else: &1))
    end)
  end

  defp play(ctx, code), do: Enum.find(ctx.plays, &(&1.code == code))

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

  describe "links" do
    test "each link names its place and, where FileMaker gives one, its state, in FileMaker's order",
         ctx do
      plan = plan(ctx)

      assert links(plan, "EMOTHE0038_AntonyAndCleopatra") == [
               {"Roma", "República romana"},
               {"Alejandría", "Egipto ptolemaico"},
               {"Atenas", "República romana"},
               {"Miseno", "República romana"}
             ]

      assert links(plan, "EMOTHE0007_LaCalandria") == [{"Roma", "Estados Pontificios"}]

      assert links(plan, "EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark") == [
               {"Elsinor", "Reino de Dinamarca"}
             ]

      assert links(plan, "EMOTHE0262_TheShoemakersHoliday") == [
               {"Old Ford", "Reino de Inglaterra"},
               {"Londres", "Reino de Inglaterra"}
             ]

      antony = play(ctx, "EMOTHE0038_AntonyAndCleopatra")
      assert %{play_id: id, ref: "T10:882"} = Enum.find(plan.links, &(&1.code == antony.code))
      assert id == antony.id
    end

    test "a link to a whole state is a link to the state", ctx do
      assert links(plan(ctx), "EMOTHE0394_EntreBobosAndaElJuego") == [
               {"Madrid", "Castilla"},
               {"Castilla", nil}
             ]
    end

    test "a country that is today's has no state", ctx do
      assert links(plan(ctx), "EMOTHE0151_AsYouLikeIt") == [{"Ardenas", nil}]
    end

    test "the editors' area stands in for a state", ctx do
      plan = plan(ctx)

      assert links(plan, "EMOTHE0153_TheTragedyOfRomeoAndJuliet") == [
               {"Mantua", "Península itálica"},
               {"Verona", "Península itálica"}
             ]

      assert links(plan, "EMOTHE0354_TheBrokenHeart") == [{"Esparta", "Antigua Grecia"}]
    end

    test "the area counts when only the place's record names it", ctx do
      # As Philaster's link to Sicily does, the link leaves out the region its record names.
      plan =
        ctx
        |> with_link("1012", &%{&1 | "_k_IdRegion" => ""})
        |> plan()

      assert links(plan, "EMOTHE0153_TheTragedyOfRomeoAndJuliet") == [
               {"Mantua", "Península itálica"},
               {"Verona", "Península itálica"}
             ]
    end

    test "FileMaker's free text is the note, as written", ctx do
      plan = plan(ctx)

      assert note(plan, "T10:799") =~ ~r/^Madrid, escenarios urbanos y ambiente cortesano;/

      assert note(plan, "T10:821") ==
               "Espacios exteriores y abiertos  (ventas, etc.) en el camino de Madrid a Toledo."

      assert note(plan, "T10:882") == nil
    end

    test "Othello's Venetian Cyprus is one link", ctx do
      plan = plan(ctx)

      assert links(plan, "EMOTHE0697_TheTragedyOfOthelloTheMoorOfVenice") == [
               {"Europa", nil},
               {"Chipre", "República de Venecia"},
               {"Venecia", "República de Venecia"}
             ]

      assert [label] = plan.skipped.duplicate
      assert label =~ ~r/^EMOTHE0697 T10:1200: \[Republic of Venice\]\. Europe/

      # The second link's note joins the first's.
      plan =
        ctx
        |> with_link("1198", &%{&1 | "espacio" => "Chipre. "})
        |> with_link("1200", &%{&1 | "espacio" => " Un puerto."})
        |> plan()

      assert note(plan, "T10:1198") == "Chipre.\n\nUn puerto."
    end

    test "a place the play already links is not linked again", ctx do
      rome =
        place_fixture(%{
          "names" => [%{"name" => "Rome", "language" => "en", "is_preferred" => "true"}]
        })

      play_place_fixture(play(ctx, "EMOTHE0038_AntonyAndCleopatra"), rome)
      plan = plan(ctx)

      assert links(plan, "EMOTHE0038_AntonyAndCleopatra") == [
               {"Alejandría", "Egipto ptolemaico"},
               {"Atenas", "República romana"},
               {"Miseno", "República romana"}
             ]

      assert links(plan, "EMOTHE0007_LaCalandria") == [{"Roma", "Estados Pontificios"}]
      assert Enum.any?(plan.skipped.duplicate, &String.starts_with?(&1, "EMOTHE0038 T10:882: "))
    end

    test "a link left out as a duplicate brings no place of its own", ctx do
      # Only Hamlet's link reaches the Kingdom of Denmark.
      elsinore =
        place_fixture(%{
          "names" => [%{"name" => "Elsinore", "language" => "en", "is_preferred" => "true"}]
        })

      play_place_fixture(play(ctx, "EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark"), elsinore)
      plan = plan(ctx)

      assert links(plan, "EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark") == []
      assert named(plan, "Reino de Dinamarca") == []
    end

    test "no place, no link", ctx do
      plan = plan(ctx)

      assert [no_place] = plan.skipped.no_place
      assert no_place =~ ~r/^EMOTHE0367 T10:1083: \( unspecified \) The play is .*Wiggins/
      assert [empty] = plan.skipped.empty
      assert empty =~ ~r/^EMOTHE0653 T10:1150: /
      assert links(plan, "EMOTHE0367_Endymion") == []
      assert links(plan, "EMOTHE0653_TheShyCourtier") == []
    end

    test "a place with no name in any language is no link", ctx do
      plan =
        ctx
        |> update_in([:data, :names], fn names ->
          Enum.reject(names, &(&1["_k_IdTipoToponimo"] == "4" and &1["_k_IdToponimo"] == "143"))
        end)
        |> plan()

      assert links(plan, "EMOTHE0038_AntonyAndCleopatra") == [
               {"Roma", "República romana"},
               {"Alejandría", "Egipto ptolemaico"},
               {"Miseno", "República romana"}
             ]

      assert [label] = plan.skipped.nameless
      assert label =~ ~r/^EMOTHE0038 T10:884: Athens/
    end

    test "a version we do not hold is counted, not planned", ctx do
      plan = plan(ctx)

      assert plan.not_held == 1
      assert named(plan, "Tesalia") == []

      # A performance's link is no version's: the performances are another slice.
      plan =
        ctx
        |> with_link("1063", &%{&1 | "_k_IdObraTitulo" => "", "_k_IdObraRepresentacion" => "7"})
        |> plan()

      assert plan.not_held == 0
    end

    test "a play the import has written to is skipped whole", ctx do
      hamlet = play(ctx, "EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark")
      othello = play(ctx, "EMOTHE0697_TheTragedyOfOthelloTheMoorOfVenice")
      play_place_fixture(hamlet, place_fixture(), %{"origin" => "filemaker"})

      # A curator removed Othello's links since; the import's log entry outlives them.
      {:ok, _} =
        Playcode.ActivityLog.log(%{
          play_id: othello.id,
          action: "import",
          resource_type: "play_place",
          resource_id: othello.id,
          metadata: %{"source" => "filemaker"}
        })

      plan = plan(ctx)

      assert plan.already_imported == [hamlet.code, othello.code]
      assert links(plan, hamlet.code) == []
      assert links(plan, othello.code) == []
      assert named(plan, "Reino de Dinamarca") == []
      assert named(plan, "Chipre") == []
    end

    test "a curator's own link, or another source's import, does not mark a play imported",
         ctx do
      hamlet = play(ctx, "EMOTHE0010_TheTragedyOfHamletPrinceOfDenmark")
      play_place_fixture(hamlet, place_fixture())

      {:ok, _} =
        Playcode.ActivityLog.log(%{
          play_id: hamlet.id,
          action: "import",
          resource_type: "play_place",
          resource_id: hamlet.id,
          metadata: %{"source" => "tei"}
        })

      assert plan(ctx).already_imported == []
    end

    test "the report says what it would write and what it left out", ctx do
      report = ctx |> plan() |> Import.report()

      assert "EMOTHE0038_AntonyAndCleopatra  Roma — República romana" in report
      assert "EMOTHE0151_AsYouLikeIt  Ardenas" in report
      assert Enum.any?(report, &(&1 =~ "Elsinore → Helsingør"))
      assert Enum.any?(report, &String.starts_with?(&1, "skipped, no_place:"))
      assert "links on versions not held: 1" in report
    end
  end
end
