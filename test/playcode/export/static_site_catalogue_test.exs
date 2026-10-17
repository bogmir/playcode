defmodule Playcode.Export.StaticSiteCatalogueTest do
  @moduledoc "The static site's catalogue page: one entry per work, facets, filter hooks."
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  defp works(index), do: index |> LazyHTML.query("[data-works] > li") |> Enum.to_list()

  test "a one-play site says \"1 play · 1 author\"" do
    play = play_fixture(%{"is_complete" => true, "author_name" => "Lope de Vega"})

    assert "1 play · 1 author" in texts(html!(generate!([play]), "index.html"), ".lede")
  end

  test "a translation is listed under its original, one entry per work" do
    %{original: original, translation: translation} = translation_family_fixture()

    assert [work] = works(html!(generate!([original, translation]), "index.html"))

    assert work |> LazyHTML.query("a") |> LazyHTML.attribute("href") ==
             ["plays/#{original.code}/index.html", "plays/#{translation.code}/index.html"]
  end

  test "a translation whose original is not published stands on its own, marked as a translation" do
    %{translation: translation} = translation_family_fixture()

    assert [work] = works(html!(generate!([translation]), "index.html"))
    assert LazyHTML.text(work) =~ "translation"
  end

  test "a translation of a translation is listed under the original of the chain" do
    %{original: original, translation: translation} = translation_family_fixture()

    second =
      play_fixture(%{
        "title" => "Second-hand",
        "parent_play_id" => translation.id,
        "relationship_type" => "traduccion",
        "is_complete" => true
      })

    assert [work] = works(html!(generate!([original, translation, second]), "index.html"))
    assert LazyHTML.text(work) =~ "Second-hand"
  end

  test "facets count the plays by language, form, kind and collection" do
    es = play_fixture(%{"is_complete" => true, "language" => "es"})
    fr = play_fixture(%{"is_complete" => true, "language" => "fr", "is_verse" => false})

    al =
      play_fixture(%{"is_complete" => true, "code" => "AL#{System.unique_integer([:positive])}"})

    labels = texts(html!(generate!([es, fr, al]), "index.html"), "[data-facets] label")

    assert "Español 2" in labels
    assert "Français 1" in labels
    assert "Prose 1" in labels
    assert "Originals 3" in labels
    assert "ARTELOPE 1" in labels
  end

  test "the Form facet follows a curator's choice over the automatic one" do
    verse = play_fixture(%{"is_complete" => true})
    prose = play_fixture(%{"is_complete" => true, "form" => "prose"})
    mixed = play_fixture(%{"is_complete" => true, "form" => "mixed"})

    index = html!(generate!([verse, prose, mixed]), "index.html")
    labels = texts(index, "[data-facets] label")

    assert "Verse 1" in labels
    assert "Prose 1" in labels
    assert "Verse and prose 1" in labels

    assert index
           |> LazyHTML.query("[data-play]")
           |> LazyHTML.attribute("data-form")
           |> Enum.sort() ==
             ["mixed", "prose", "verse"]
  end

  test "each entry carries what the filter and facets match on" do
    play = play_fixture(%{"is_complete" => true, "title" => "La Vida es Sueño"})
    entry = html!(generate!([play]), "index.html") |> LazyHTML.query("[data-play]")

    assert LazyHTML.attribute(entry, "data-lang") == ["es"]
    assert LazyHTML.attribute(entry, "data-kind") == ["original"]
    assert [text] = LazyHTML.attribute(entry, "data-text")
    assert text =~ "la vida es sueño"
  end

  # Question 15: each kind by its own name. Every non-original used to be a translation.
  test "an adaptation is called one in its entry, its tag and the Kind facet" do
    original = play_fixture(%{"is_complete" => true, "title" => "La verdad sospechosa"})

    adaptation =
      play_fixture(%{
        "is_complete" => true,
        "title" => "Le Menteur",
        "parent_play_id" => original.id,
        "relationship_type" => "adaptacion"
      })

    # With no original in the site, it heads an entry of its own, which carries the tag.
    alone = play_fixture(%{"is_complete" => true, "relationship_type" => "adaptacion"})
    index = html!(generate!([original, adaptation, alone]), "index.html")

    kinds = index |> LazyHTML.query("[data-play]") |> LazyHTML.attribute("data-kind")
    assert Enum.sort(kinds) == ["adaptation", "adaptation", "original"]
    assert "Adaptations 2" in texts(index, "[data-facets] label")
    assert "adaptation" in texts(index, "[data-play] .tag")
  end

  # Under its original, an entry used to say only its language: an adaptation read as one
  # more translation.
  test "an entry under its original says what kind of play it is" do
    %{original: original, translation: translation} = translation_family_fixture()

    adaptation =
      play_fixture(%{
        "is_complete" => true,
        "parent_play_id" => original.id,
        "relationship_type" => "adaptacion"
      })

    index = html!(generate!([original, translation, adaptation]), "index.html")
    # Each entry's tags, by the play its title links.
    entries =
      for entry <- LazyHTML.query(index, "[data-play]"),
          do:
            {entry |> LazyHTML.query("a") |> LazyHTML.attribute("href") |> hd(),
             texts(entry, ".tag")}

    tags = fn play ->
      Enum.find_value(entries, fn {href, tags} ->
        String.contains?(href, "#{play.code}/") && tags
      end)
    end

    assert "adaptation" in tags.(adaptation)
    assert "translation" in tags.(translation)
    refute "translation" in tags.(original)
  end

  test "titles and authors are escaped" do
    play = play_fixture(%{"is_complete" => true, "title" => "Tom & <Jerry>"})

    assert read!(generate!([play]), "index.html") =~ "Tom &amp; &lt;Jerry&gt;"
  end

  @tag timeout: 10_000
  test "plays that are each other's parent do not hang the build; each stands alone" do
    a = play_fixture(%{"title" => "Alfa", "is_complete" => true})
    b = play_fixture(%{"title" => "Beta", "is_complete" => true})

    {:ok, a} =
      Playcode.Catalogue.update_play(a, %{
        "parent_play_id" => b.id,
        "relationship_type" => "traduccion"
      })

    {:ok, b} =
      Playcode.Catalogue.update_play(b, %{
        "parent_play_id" => a.id,
        "relationship_type" => "traduccion"
      })

    text = html!(generate!([a, b]), "index.html") |> LazyHTML.text()
    assert text =~ "Alfa"
    assert text =~ "Beta"
  end
end
