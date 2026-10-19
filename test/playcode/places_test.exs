defmodule Playcode.PlacesTest do
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures

  alias Playcode.Places

  describe "slugify/1" do
    test "strips accents and punctuation" do
      assert Places.slugify("Atlántida") == "atlantida"
      assert Places.slugify("La Cortigiana (1525)") == "la-cortigiana-1525"
      assert Places.slugify("İstanbul") == "istanbul"
    end

    test "a name with no latin characters still yields a usable slug" do
      assert Places.slugify("……") == "place"
    end
  end

  describe "create_place/1" do
    test "requires at least one name" do
      assert {:error, changeset} = Places.create_place(%{"type" => "city", "names" => []})
      assert errors_on(changeset).names != []
    end

    test "a colliding slug is suffixed rather than rejected" do
      # Straight through create_place/1, not place_fixture/1 — the fixture pins a unique
      # slug of its own to keep async tests off the same index lock, which is exactly the
      # derivation this test is about.
      # The name is unique to this test on purpose: it claims two slugs, and a second
      # test claiming the same two in the other order would deadlock on the index.
      attrs = fn ->
        %{
          "type" => "forest",
          "names" => %{
            "0" => %{"name" => "Sotobosque", "language" => "es", "is_preferred" => "true"}
          }
        }
      end

      {:ok, first} = Places.create_place(attrs.())
      {:ok, second} = Places.create_place(attrs.())

      assert first.slug == "sotobosque"
      assert second.slug == "sotobosque-2"
    end

    test "an explicit slug is respected" do
      place = place_fixture(%{"name" => "Roma", "slug" => "roma-antica"})
      assert place.slug == "roma-antica"
    end
  end

  describe "display_name/2" do
    setup do
      place =
        place_fixture(%{
          "name" => "Roma",
          "names" => [
            %{"name" => "Roma", "language" => "es", "is_preferred" => "true"},
            %{"name" => "Rome", "language" => "en", "is_preferred" => "true"},
            %{"name" => "Roma antica", "language" => "it"}
          ]
        })

      %{place: Places.get_place!(place.id)}
    end

    test "prefers the preferred name in the requested locale", %{place: place} do
      assert Places.display_name(place, "es") == "Roma"
      assert Places.display_name(place, "en") == "Rome"
    end

    test "falls back to a non-preferred name in the locale", %{place: place} do
      assert Places.display_name(place, "it") == "Roma antica"
    end

    test "falls back to any preferred name for an unknown locale", %{place: place} do
      assert Places.display_name(place, "de") in ["Roma", "Rome"]
    end
  end

  describe "update_place/2" do
    test "a place cannot become its own parent" do
      place = place_fixture(%{"name" => "Roma"})

      assert {:error, changeset} =
               Places.update_place(place, %{"parent_place_id" => place.id})

      assert errors_on(changeset).parent_place_id != []
    end

    test "a parent cycle is refused" do
      europe = place_fixture(%{"name" => "Europa", "type" => "continent"})

      italy =
        place_fixture(%{"name" => "Italia", "type" => "country", "parent_place_id" => europe.id})

      assert {:error, changeset} = Places.update_place(europe, %{"parent_place_id" => italy.id})
      assert errors_on(changeset).parent_place_id != []
    end
  end

  describe "delete_place/1" do
    test "a place that is a parent is refused" do
      parent = place_fixture(%{"name" => "Italia", "type" => "country"})
      _child = place_fixture(%{"name" => "Roma", "parent_place_id" => parent.id})

      assert {:error, changeset} = Places.delete_place(parent)
      assert "is the parent of other places" in errors_on(changeset).children
    end
  end

  describe "list_places/1" do
    test "sorts by display name, ignoring accents, and carries the play count" do
      play = play_fixture()
      zaragoza = place_fixture(%{"name" => "Zaragoza"})
      alava = place_fixture(%{"name" => "Álava"})
      {:ok, _} = Places.link_place(play.id, alava.id, %{})

      names = Places.list_places() |> Enum.map(&Places.display_name(&1, "es"))
      assert names == ["Álava", "Zaragoza"]

      counts = Map.new(Places.list_places(), &{&1.id, &1.play_count})
      assert counts[alava.id] == 1
      assert counts[zaragoza.id] == 0
    end
  end

  describe "hierarchy" do
    setup do
      europe = place_fixture(%{"name" => "Europa", "type" => "continent"})

      romania =
        place_fixture(%{"name" => "Rumanía", "type" => "country", "parent_place_id" => europe.id})

      transylvania =
        place_fixture(%{
          "name" => "Transilvania",
          "type" => "region",
          "parent_place_id" => romania.id
        })

      woods =
        place_fixture(%{
          "name" => "Bosque",
          "type" => "forest",
          "parent_place_id" => transylvania.id
        })

      %{europe: europe, woods: woods}
    end

    test "a breadcrumb reads outward from the place", %{woods: woods} do
      gazetteer = Places.gazetteer()

      assert Places.breadcrumb(gazetteer[woods.id], gazetteer, "es") ==
               "Bosque, Transilvania, Rumanía, Europa"
    end

    test "a place with no parent is its own breadcrumb", %{europe: europe} do
      gazetteer = Places.gazetteer()
      assert Places.breadcrumb(gazetteer[europe.id], gazetteer, "es") == "Europa"
    end
  end

  describe "search_names/2" do
    test "is case insensitive and matches a fragment" do
      place = place_fixture(%{"name" => "Alexandría"})
      assert [found] = Places.search_names("ALEX")
      assert found.id == place.id
    end

    test "an empty term returns nothing" do
      place_fixture(%{"name" => "Roma"})
      assert Places.search_names("") == []
    end

    test "carries the play count, same as list_places/1" do
      play = play_fixture()
      place = place_fixture(%{"name" => "Cartagena"})
      {:ok, _} = Places.link_place(play.id, place.id, %{})

      assert [found] = Places.search_names("cartagena")
      assert found.play_count == 1
    end
  end

  describe "play links" do
    setup do
      play = play_fixture()
      roma = place_fixture(%{"name" => "Roma"})
      miseno = place_fixture(%{"name" => "Miseno"})
      %{play: play, roma: roma, miseno: miseno}
    end

    test "a new link goes at the end, hand-entered unless it says otherwise", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      {:ok, _} = Places.link_place(play.id, roma.id, %{})
      {:ok, _} = Places.link_place(play.id, miseno.id, %{"role" => "mentioned"})

      assert Enum.map(
               Places.list_play_places(play.id),
               &{Places.display_name(&1.place, "es"), &1.role, &1.origin}
             ) ==
               [{"Roma", "setting", "manual"}, {"Miseno", "mentioned", "manual"}]
    end

    test "a place cannot be linked to the same play twice", %{play: play, roma: roma} do
      {:ok, _} = Places.link_place(play.id, roma.id, %{})

      assert {:error, changeset} = Places.link_place(play.id, roma.id, %{})
      assert "is already linked to this play" in errors_on(changeset).place_id
    end

    test "moving the first link up is a no-op", %{play: play, roma: roma} do
      {:ok, first} = Places.link_place(play.id, roma.id, %{})
      assert :ok = Places.move_play_place(first, :up)
      assert [%{place_id: place_id}] = Places.list_play_places(play.id)
      assert place_id == roma.id
    end

    test "a link created after an unlink does not collide with a surviving position", %{
      play: play,
      roma: roma,
      miseno: miseno
    } do
      cartagena = place_fixture(%{"name" => "Cartagena"})
      alejandria = place_fixture(%{"name" => "Alejandria"})

      {:ok, _a} = Places.link_place(play.id, roma.id, %{})
      {:ok, b} = Places.link_place(play.id, miseno.id, %{})
      {:ok, _c} = Places.link_place(play.id, cartagena.id, %{})

      {:ok, _} = Places.unlink_place(b)
      {:ok, d} = Places.link_place(play.id, alejandria.id, %{})

      :ok = Places.move_play_place(d, :up)

      assert Places.list_play_places(play.id)
             |> Enum.map(&Places.display_name(&1.place, "es")) == [
               "Roma",
               "Alejandria",
               "Cartagena"
             ]
    end
  end

  describe "historical state" do
    setup do
      play = play_fixture()
      roma = place_fixture(%{"name" => "Roma"})
      republica = place_fixture(%{"name" => "República romana", "type" => "country"})
      %{play: play, roma: roma, republica: republica}
    end

    test "a link may name the historical state its place belonged to", %{
      play: play,
      roma: roma,
      republica: republica
    } do
      {:ok, _} = Places.link_place(play.id, roma.id, %{"historical_state_id" => republica.id})

      assert [link] = Places.list_play_places(play.id)
      assert link.historical_state_id == republica.id
    end

    test "a place cannot be its own historical state", %{play: play, roma: roma} do
      assert {:error, changeset} =
               Places.link_place(play.id, roma.id, %{"historical_state_id" => roma.id})

      assert errors_on(changeset).historical_state_id == ["cannot be the place itself"]
    end

    test "a state in use cannot be deleted", %{play: play, roma: roma, republica: republica} do
      {:ok, _} = Places.link_place(play.id, roma.id, %{"historical_state_id" => republica.id})

      assert {:error, changeset} = Places.delete_place(republica)

      assert errors_on(changeset).state_links == ["is the historical state of a play's place"]
    end

    test "the play count counts the plays whose links name a place as their state", %{
      play: play,
      roma: roma,
      republica: republica
    } do
      castilla = place_fixture(%{"name" => "Castilla", "type" => "country"})
      miseno = place_fixture(%{"name" => "Miseno"})
      other_play = play_fixture()

      # Two links of one play under one state are one play.
      {:ok, _} = Places.link_place(play.id, roma.id, %{"historical_state_id" => republica.id})
      {:ok, _} = Places.link_place(play.id, miseno.id, %{"historical_state_id" => republica.id})
      {:ok, _} = Places.link_place(other_play.id, castilla.id, %{})

      counts = Map.new(Places.list_places(), &{&1.id, &1.play_count})

      assert counts[republica.id] == 1
      assert counts[castilla.id] == 1
      assert counts[roma.id] == 1
    end
  end

  describe "what a place may hold" do
    defp names(list), do: Map.new(Enum.with_index(list), fn {n, i} -> {"#{i}", n} end)

    # A unique slug unless the test passes one: slugs are corpus-wide, and a name like
    # "Roma" derived to the same slug in another async file deadlocks (see
    # place_fixture/1).
    defp create(attrs) do
      %{
        "type" => "city",
        "slug" => "sch-#{System.unique_integer([:positive])}",
        "names" => names([%{"name" => "Sch Lugar", "language" => "es"}])
      }
      |> Map.merge(attrs)
      |> Places.create_place()
    end

    test "an explicit slug already in use is refused" do
      place_fixture(%{"name" => "Roma", "slug" => "sch-roma"})

      assert {:error, changeset} = create(%{"slug" => "sch-roma"})
      assert "has already been taken" in errors_on(changeset).slug
    end

    test "an unknown type or coordinates off the globe are refused" do
      assert {:error, changeset} = create(%{"type" => "planet"})
      assert "is invalid" in errors_on(changeset).type

      assert {:error, changeset} = create(%{"latitude" => "91.0", "longitude" => "0.0"})
      assert errors_on(changeset).latitude != []
    end

    test "one authority entity cannot become two places" do
      {:ok, _} = create(%{"authority" => "wikidata", "authority_id" => "Q220"})

      assert {:error, changeset} = create(%{"authority" => "wikidata", "authority_id" => "Q220"})
      assert errors_on(changeset).authority_id != []
    end

    test "one preferred name per language" do
      preferred = fn name, lang ->
        %{"name" => name, "language" => lang, "is_preferred" => "true"}
      end

      assert {:ok, _} =
               create(%{"names" => names([preferred.("Roma", "es"), preferred.("Rome", "en")])})

      assert {:error, _} =
               create(%{"names" => names([preferred.("Roma", "es"), preferred.("Rroma", "es")])})

      assert {:error, _} =
               create(%{
                 "names" => names([preferred.("Miseno", nil), preferred.("Misenum", nil)])
               })
    end

    test "deleting a place deletes its names" do
      {:ok, place} = create(%{"names" => names([%{"name" => "Sch Borrada", "language" => "es"}])})

      {:ok, _} = Places.delete_place(place)
      assert Places.search_names("Sch Borrada") == []
    end

    test "a link needs a known role and origin" do
      play = play_fixture()

      for {field, attrs} <- [role: %{"role" => "birthplace"}, origin: %{"origin" => "guesswork"}] do
        place = place_fixture()
        assert {:error, changeset} = Places.link_place(play.id, place.id, attrs)
        assert "is invalid" in Map.fetch!(errors_on(changeset), field)
      end
    end
  end
end
