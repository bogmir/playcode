defmodule Playcode.Export.StaticSiteChangesTest do
  @moduledoc """
  What a site records about its own build (`build.json`), and what it says has changed
  since: `changed_plays/1`, `site_changed?/2` and `outdated/1`. Built with `generate/1`
  and `apply_changes/2` into a temp directory; plays edited through the Catalogue.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.{Catalogue, Performances, PlayContent}
  alias Playcode.Export.StaticSite

  test "a play edited since the site was built is changed until it is written again" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a, b])
    assert StaticSite.changed_plays(dir) == []

    {:ok, _} = Catalogue.update_play(a, %{"title" => "Revised"})
    assert StaticSite.changed_plays(dir) == [a.code]

    {:ok, _} = StaticSite.apply_changes([{:add, a.id}], output_dir: dir)
    assert StaticSite.changed_plays(dir) == []
  end

  test "a site is current for the version it was built with, and changed for any other" do
    dir = generate!([complete_play()], version: "2.0")

    refute StaticSite.site_changed?(dir, version: "2.0")
    assert StaticSite.site_changed?(dir, version: "2.1")
  end

  # Its other pages still show the version they were built with.
  test "adding a play under other settings does not make the site look built with them" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a], version: "2.0")

    {:ok, _} = StaticSite.apply_changes([{:add, b.id}], output_dir: dir, version: "3.0")

    refute StaticSite.site_changed?(dir, version: "2.0")
    assert StaticSite.changed_plays(dir) == []
  end

  # Review Focus 1: a site built before build.json existed was written by unknown code.
  test "a site with no build record has changed, and so has every play in it" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a, b])
    File.rm!(Path.join(dir, "build.json"))

    assert StaticSite.site_changed?(dir)
    assert Enum.sort(StaticSite.changed_plays(dir)) == Enum.sort([a.code, b.code])

    {:ok, _} = StaticSite.apply_changes([{:add, a.id}], output_dir: dir)

    assert StaticSite.changed_plays(dir) == [b.code]
    assert StaticSite.site_changed?(dir)
  end

  # Review Focus 2.
  test "an unreadable build record counts as none" do
    a = complete_play()
    dir = generate!([a])
    File.write!(Path.join(dir, "build.json"), ~s({"site": "abc", "pla))

    assert StaticSite.site_changed?(dir)
    assert StaticSite.changed_plays(dir) == [a.code]
  end

  # Review Focus 3: the batch wrote every page there is, so it knows what built them.
  test "a site begun by adding plays one at a time is current" do
    a = complete_play()
    dir = site_dir!()

    {:ok, _} = StaticSite.apply_changes([{:add, a.id}], output_dir: dir)

    refute StaticSite.site_changed?(dir)
    assert StaticSite.changed_plays(dir) == []
  end

  # The export page prefills its Version field with it, so the site reads as current.
  test "a site records the version it was built with, and adding a play keeps it" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a], version: "2.0")
    assert StaticSite.built_version(dir) == "2.0"

    {:ok, _} = StaticSite.apply_changes([{:add, b.id}], output_dir: dir, version: "3.0")
    assert StaticSite.built_version(dir) == "2.0"
  end

  test "a site begun by a batch records the batch's version" do
    dir = site_dir!()

    {:ok, _} =
      StaticSite.apply_changes([{:add, complete_play().id}], output_dir: dir, version: "3.0")

    assert StaticSite.built_version(dir) == "3.0"
  end

  test "a build record from before versions were recorded names none, and keeps naming none" do
    [a, b] = [complete_play(), complete_play()]
    dir = generate!([a])
    build = Path.join(dir, "build.json")

    File.write!(
      build,
      build |> File.read!() |> Jason.decode!() |> Map.delete("version") |> Jason.encode!()
    )

    assert StaticSite.built_version(dir) == nil
    refute StaticSite.site_changed?(dir)
    assert StaticSite.changed_plays(dir) == []

    {:ok, _} = StaticSite.apply_changes([{:add, b.id}], output_dir: dir, version: "3.0")
    assert StaticSite.built_version(dir) == nil
  end

  test "outdated adds each changed play and removes each one no longer published" do
    [changed, same, archived, draft] = for _ <- 1..4, do: complete_play()
    dir = generate!([changed, same, archived, draft])

    {:ok, _} = Catalogue.update_play(changed, %{"title" => "Revised"})
    {:ok, _} = Catalogue.delete_play(archived)
    {:ok, _} = Catalogue.update_play(draft, %{"is_complete" => false})

    assert Enum.sort(StaticSite.outdated(dir)) ==
             Enum.sort([{:add, changed.id}, {:remove, archived.code}, {:remove, draft.code}])
  end

  test "a play taken off the site takes its EPUB with it" do
    [goes, stays] = [complete_play(), complete_play()]
    dir = generate!([goes, stays])
    epub = Path.join(dir, "plays/#{goes.code}/#{goes.code}.epub")
    assert File.exists?(epub)

    {:ok, _} = StaticSite.apply_changes([{:remove, goes.code}], output_dir: dir)
    refute File.exists?(epub)
  end

  test "a published play that loses its text keeps its record alone" do
    import Playcode.ImportHelpers

    original =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><head>ACTO I</head><sp><speaker>A</speaker><l n="1">Uno.</l><l n="2">Dos.</l></sp></div1>)
      )
      |> import_tei!()
      |> mark_complete!()

    translation =
      complete_play(%{"parent_play_id" => original.id, "relationship_type" => "traduccion"})

    dir = generate!([original, translation])
    files = &(dir |> Path.join("plays/#{&1.code}") |> File.ls!() |> Enum.sort())
    assert "text.html" in files.(original)
    assert "#{original.code}.epub" in files.(original)
    assert "compare.html" in files.(translation)

    {:ok, _} =
      original.id
      |> Playcode.PlayContent.list_top_divisions()
      |> Enum.flat_map(&Playcode.PlayContent.list_elements_for_division(&1.id))
      |> Enum.filter(&is_nil(&1.parent_id))
      |> Playcode.PlayContent.delete_elements()

    {:ok, _} = StaticSite.apply_changes([{:add, original.id}], output_dir: dir)

    assert files.(original) == ["#{original.code}.xml", "index.html"]
    refute "compare.html" in files.(translation)
  end

  describe "the record index" do
    test "a renamed company reaches every play it staged, on the next Generate" do
      [one, two] = [complete_play(), complete_play()]

      for play <- [one, two],
          do: performance_fixture(play, %{"company_name" => "Lady Elizabeth's Men"})

      dir = generate!([one, two])

      company = Enum.find(Performances.list_companies(), &(&1.name == "Lady Elizabeth's Men"))
      {:ok, _} = Performances.update_company(company, %{"name" => "Lady Elizabeth’s Men"})

      {:ok, _} = StaticSite.apply_changes(StaticSite.outdated(dir), output_dir: dir)

      for entry <- records!(dir),
          do: assert([[_, _, _, _, _, "Lady Elizabeth’s Men", _]] = entry["r"])
    end

    test "a play taken off the site leaves the index, and one added joins it" do
      [stays, goes] = [complete_play(), complete_play()]
      dir = generate!([stays, goes])
      joins = complete_play()

      {:ok, _} =
        StaticSite.apply_changes([{:remove, goes.code}, {:add, joins.id}], output_dir: dir)

      assert records!(dir) |> Enum.map(& &1["c"]) |> Enum.sort() ==
               Enum.sort([stays.code, joins.code])
    end

    test "a new character is in the index after its play alone is built again" do
      [play, other] = [complete_play(), complete_play()]
      dir = generate!([play, other])

      {:ok, _} =
        PlayContent.create_character(%{
          "play_id" => play.id,
          "xml_id" => "nuevo",
          "name" => "NUEVO"
        })

      assert StaticSite.outdated(dir) == [{:add, play.id}]
      {:ok, _} = StaticSite.apply_changes(StaticSite.outdated(dir), output_dir: dir)
      assert "NUEVO" in Enum.find(records!(dir), &(&1["c"] == play.code))["n"]
    end
  end
end
