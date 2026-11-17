defmodule Playcode.Export.StaticSiteCatalogueTest do
  @moduledoc "The static site's catalogue page: one entry per work, and the search form."
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  defp works(index), do: index |> LazyHTML.query("[data-works] > li") |> Enum.to_list()

  test "a play without a text is in the catalogue, tagged, with its years and no form" do
    play =
      play_without_text_fixture(%{
        "is_complete" => true,
        "title" => "El Adonis",
        "composition_date_from" => 1632,
        "composition_date_to" => 1632
      })

    index = html!(generate!([play]), "index.html", "es")
    assert "sin texto" in texts(index, "[data-play] .tag")
    assert texts(index, "[data-play] .meta") == ["1632"]
  end

  test "a one-play site says \"1 play · 1 author\"" do
    play = play_fixture(%{"is_complete" => true, "author_name" => "Lope de Vega"})

    assert "1 play · 1 author" in texts(html!(generate!([play]), "index.html"), ".lede")
  end

  # S6, the portal's sentence on what the library holds.
  test "the catalogue says under its title what the library holds" do
    play = play_fixture(%{"is_complete" => true})

    assert html!(generate!([play]), "index.html") |> texts("main > p") |> hd() =~
             "five basic traditions of early modern European theatre"
  end

  test "a translation is listed under its original, one entry per work" do
    %{original: original, translation: translation} = translation_family_fixture()

    assert [work] = works(html!(generate!([original, translation]), "index.html"))

    # Since problem 5's step 2 the original's line also links the comparison with its
    # translation (`static_site_compare_test.exs`), so the entries' title links are read.
    assert work |> LazyHTML.query("a.entry-title") |> LazyHTML.attribute("href") ==
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

  @names ~w(t a l o k s f x q m in d-from d-to wt wc wy-from wy-to wf rp rv rc ry-from ry-to rk ra h p n sort)

  # The controls of the catalogue's form: inside it, or tied to it by `form=` from above the list.
  defp controls(page, selector) do
    [id] = page |> LazyHTML.query("form[data-search]") |> LazyHTML.attribute("id")
    LazyHTML.query(page, "form[data-search] #{selector}, #{selector}[form=#{id}]")
  end

  # A control is named by a label for it, a label around it, or an aria-label.
  defp labelled?(page, control) do
    [name] = LazyHTML.attribute(control, "name")
    ids = page |> LazyHTML.query("label[for]") |> LazyHTML.attribute("for")
    wrapped = page |> LazyHTML.query("label input, label select") |> LazyHTML.attribute("name")

    LazyHTML.attribute(control, "aria-label") != [] or
      LazyHTML.attribute(control, "id") |> Enum.any?(&(&1 in ids)) or name in wrapped
  end

  # A select's options as {value, label}; the label is the attribute, the option's text empty.
  defp options(page, name) do
    for option <- LazyHTML.query(page, ~s(select[name="#{name}"] option)) do
      {option |> LazyHTML.attribute("value") |> hd(),
       option |> LazyHTML.attribute("label") |> hd()}
    end
  end

  test "the form holds every control, named, labelled, and hidden until the script shows it" do
    page = html!(generate!([complete_play()]), "index.html", "es")
    assert page |> LazyHTML.query("form[data-search]") |> LazyHTML.attribute("hidden") == [""]

    for name <- @names,
        do:
          assert({name, page |> controls(~s([name="#{name}"])) |> Enum.empty?()} == {name, false})

    for control <-
          controls(page, "input:not([type=radio])") |> Enum.concat(controls(page, "select")),
        do: assert(labelled?(page, control), inspect(LazyHTML.attribute(control, "name")))

    assert page
           |> LazyHTML.query("form[data-search] details > summary")
           |> Enum.map(&(&1 |> LazyHTML.text() |> squish() |> String.split(" (") |> hd())) ==
             [
               "Obra",
               "Datación",
               "Testimonios",
               "Representaciones",
               "Tiempo y lugar",
               "Personajes"
             ]
  end

  test "a list offers the values the published plays hold, the first four with their counts" do
    plays = [
      complete_play(%{"language" => "es"}),
      complete_play(%{"language" => "es"}),
      complete_play(%{"language" => "en", "form" => "prose"})
    ]

    page = html!(generate!(plays), "index.html", "es")
    assert options(page, "l") == [{"", "Todos"}, {"es", "Español (2)"}, {"en", "Inglés (1)"}]
    assert {"prose", "Prosa (1)"} in options(page, "f")
    assert options(page, "x") == [{"", "Todas"}, {"1", "Con texto"}, {"0", "Sin texto"}]
  end

  # Review Focus 5 of the plan: a small site, a test site.
  test "a site with no witness, performance or place offers only the first option there" do
    page = html!(generate!([complete_play()]), "index.html", "es")
    for name <- ~w(wt wf rc h), do: assert([{"", _all}] = options(page, name))
  end

  test "a list's options follow the interface's language" do
    play = complete_play()
    witness!(play, %{"witness_type" => "manuscript"})
    dir = generate!([play])
    assert {"manuscript", "Manuscrito"} in options(html!(dir, "index.html", "es"), "wt")
    assert {"manuscript", "Manuscript"} in options(html!(dir, "index.html", "en"), "wt")
  end

  # The filter reads search/records.js alone (static_site_records_test.exs), so the
  # attributes the old filter and facets matched on are gone.
  test "a row names its play by code and carries no filter data" do
    play = complete_play()
    row = html!(generate!([play]), "index.html") |> LazyHTML.query("[data-play]")
    assert LazyHTML.attribute(row, "data-code") == [play.code]

    for gone <- ~w(data-lang data-form data-kind data-coll data-text),
        do: assert(LazyHTML.attribute(row, gone) == [])
  end

  test "the page links its own stylesheet and script, stamped, and the site has no Search entry" do
    page = html!(generate!([complete_play()]), "index.html")

    assert [href] =
             page
             |> LazyHTML.query(~s(link[href^="assets/catalogue.css"]))
             |> LazyHTML.attribute("href")

    assert href =~ ~r/\?v=[0-9a-f]{12}\z/

    assert [_src] =
             page
             |> LazyHTML.query(~s(script[src^="assets/catalogue.js?v="]))
             |> LazyHTML.attribute("src")

    refute "search.html" in (page |> LazyHTML.query("nav.site a") |> LazyHTML.attribute("href"))
  end

  test "the old search page sends its reader, and their words, to the catalogue" do
    page = read!(generate!([complete_play()]), "search.html")
    assert page =~ ~s(http-equiv="refresh")
    assert page =~ "index.html"
    # The inline script that carries ?q= over.
    assert page =~ "#q="
  end

  # Question 15: each kind by its own name. Every non-original used to be a translation.
  test "an adaptation is called one in its entry, its tag and the Kind list" do
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

    # The kinds themselves are in search/records.js since the record search
    # (static_site_records_test.exs); the page's Kind list counts them.
    assert {"adaptation", "Adaptations (2)"} in options(index, "k")
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
