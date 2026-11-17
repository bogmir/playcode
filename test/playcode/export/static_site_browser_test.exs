defmodule Playcode.Export.StaticSiteBrowserTest do
  @moduledoc """
  The catalogue's search as a reader's browser runs it: one site of five plays, built
  once, each test opening `index.html` with a search in its address, the way a shared
  link is opened, and reading which rows are left showing.
  """
  use ExUnit.Case, async: false

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers
  import Playcode.TestFixtures

  alias Playcode.{Browser, Catalogue, PlayContent, Repo}

  @moduletag :browser
  unless Browser.chrome(), do: @moduletag(skip: "no Chrome or Chromium on this machine")

  # The site is built in this process, outside any test's sandbox; its rows go when the
  # process does.
  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    english = complete_play(%{"language" => "en", "title" => "The Witch"})

    witness!(english, %{
      "witness_type" => "loose",
      "pub_place" => "London",
      "date" => "1604",
      "format" => "4º"
    })

    performance_fixture(english, %{"company_name" => "The King’s Men"})

    translation =
      complete_play(%{
        "language" => "es",
        "title" => "La bruja",
        "parent_play_id" => english.id,
        "relationship_type" => "traduccion"
      })

    french = play_without_text_fixture(%{"is_complete" => true, "language" => "fr"})

    prose =
      text_play(~s(<sp><speaker>A</speaker><p>Quiero soñar despierto.</p></sp>))

    verse =
      text_play(
        ~s(<sp><speaker>CLARÍN</speaker><lg><l n="1">es un sueño la vida<note n="1"><p>Un sueño, la vida.</p></note></l></lg></sp>)
      )

    {:ok, _} =
      PlayContent.create_character(%{
        "play_id" => verse.id,
        "xml_id" => "clarin",
        "name" => "CLARÍN"
      })

    plays = [english, translation, french, prose, verse]
    dir = site_dir!()

    {:ok, _} =
      Playcode.Export.StaticSite.generate(output_dir: dir, play_codes: Enum.map(plays, & &1.code))

    %{
      dir: dir,
      plays: plays,
      english: english,
      translation: translation,
      french: french,
      prose: prose,
      verse: verse
    }
  end

  defp text_play(speech) do
    play =
      import_tei!(
        tei(body: ~s(<div1 type="jornada" n="1"><head>Jornada I</head>#{speech}</div1>))
      )

    {:ok, play} = Catalogue.update_play(play, %{"is_complete" => true, "language" => "es"})
    play
  end

  defp shown(page),
    do:
      page
      |> LazyHTML.query("[data-play]:not([hidden])")
      |> LazyHTML.attribute("data-code")
      |> Enum.sort()

  test "with no filter every play shows and the form is visible", %{dir: dir, plays: plays} do
    page = Browser.dom!(dir, "index.html")
    assert shown(page) == Enum.sort(Enum.map(plays, & &1.code))
    assert LazyHTML.attribute(LazyHTML.query(page, "form[data-search]"), "hidden") == []
  end

  test "a list filter in the address hides the rest and fills its control", %{
    dir: dir,
    french: french
  } do
    page = Browser.dom!(dir, "index.html#x=0")
    assert shown(page) == [french.code]
    # --dump-dom prints attributes, not a select's value: the rows show the control was
    # filled, since the page filters on what the form holds, not on the address.
    assert texts(page, "[data-count]") == ["1 obra de 5"]
  end

  test "witness fields meet in one witness", %{dir: dir, english: english} do
    assert shown(Browser.dom!(dir, "index.html#wc=london&wy=1600-1610&wf=4%C2%BA")) == [
             english.code
           ]

    assert shown(Browser.dom!(dir, "index.html#wc=london&wf=2%C2%BA")) == []
  end

  test "a translation that passes shows under its lead, muted", %{
    dir: dir,
    english: english,
    translation: translation
  } do
    page = Browser.dom!(dir, "index.html#l=es&o=en")
    assert shown(page) == Enum.sort([english.code, translation.code])
    assert page |> LazyHTML.query(~s([data-code="#{english.code}"].muted)) |> Enum.count() == 1
  end

  test "suggestions are filled from the records", %{dir: dir} do
    page = Browser.dom!(dir, "index.html#rk=king")

    assert "The King’s Men" in (page
                                |> LazyHTML.query("#dl-rk option")
                                |> LazyHTML.attribute("value"))
  end

  test "a character is found without its accent", %{dir: dir, verse: verse} do
    assert shown(Browser.dom!(dir, "index.html#n=clarin")) == [verse.code]
  end

  test "words in q keep the plays that hold them, each with its count", %{dir: dir, verse: verse} do
    page = Browser.dom!(dir, "index.html#q=sue%C3%B1o")
    assert shown(page) == [verse.code]
    assert texts(page, ~s([data-code="#{verse.code}"] ~ [data-hits])) == ["2 pasajes"]
  end

  test "where narrows the hits", %{dir: dir} do
    assert texts(Browser.dom!(dir, "index.html#q=sue%C3%B1o&in=n"), "[data-hits]") == ["1 pasaje"]
    assert shown(Browser.dom!(dir, "index.html#q=sue%C3%B1o&in=d")) == []
  end

  # Review Focus 1 of the plan: a shared address opened cold loads both indexes at once.
  test "full text and record filters combine, from a cold address", %{dir: dir, verse: verse} do
    assert shown(Browser.dom!(dir, "index.html#f=verse&q=sue")) == [verse.code]
    assert shown(Browser.dom!(dir, "index.html#f=prose&q=sue%C3%B1o")) == []
  end

  test "a play without a text never has a hit", %{dir: dir, french: french} do
    refute french.code in shown(Browser.dom!(dir, "index.html#q=a&x=0"))
  end

  test "a text search whose engine is missing says so instead of searching for ever", %{dir: dir} do
    broken = dir <> "-no-engine"
    File.cp_r!(dir, broken)
    on_exit(fn -> File.rm_rf(broken) end)
    File.rm!(Path.join([broken, "assets", "search.js"]))

    assert texts(Browser.dom!(broken, "index.html#q=sue%C3%B1o"), "[data-count]") ==
             ["La búsqueda en los textos no está disponible."]
  end
end
