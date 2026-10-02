defmodule Playcode.Export.StaticSiteSearchTest do
  @moduledoc """
  Full-text search in the static site. The normaliser is tested directly because the
  browser's copy in `site.js` must agree with it word for word; both run the cases in
  `test/fixtures/search_normalisation.json` (the JS side: `test/js/search.test.mjs`).
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers

  alias Playcode.Export.StaticSite.Search

  defp cases, do: "test/fixtures/search_normalisation.json" |> File.read!() |> Jason.decode!()

  test "the build-time normaliser splits words as the browser does" do
    for %{"text" => text, "words" => words} <- cases()["words"] do
      assert Search.words(text) == words, text
    end
  end

  test "shard keys and file names match the browser's" do
    for %{"word" => word, "key" => key, "file" => file} <- cases()["shards"] do
      assert Search.shard_key(word) == key
      assert Search.shard_file(key) == file
    end
  end

  describe "the index files" do
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp><speaker>Rosaura</speaker><l n="1">Hipogrifo violento</l></sp>
            </div1>
            <div1 type="jornada" n="2"><head>Jornada II</head>
              <sp><speaker>Segismundo</speaker><l n="12">Decir que sueño es engaño</l></sp>
              <stage>Vase Segismundo</stage>
              <sp><speaker>Clarín</speaker><l n="13">¡Ñaque!</l></sp>
            </div1>
            """
          )
        )

      %{play: play, dir: generate!([play], all: true)}
    end

    test "a word's shard points at its line, and the lines file holds the line as printed", %{
      play: play,
      dir: dir
    } do
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")

      {"lines", code, %{"speakers" => speakers, "lines" => lines}} =
        load_js!(dir, "search/lines/#{play.code}.js")

      assert code == play.code
      line = Enum.find_index(lines, &(Enum.at(&1, 1) == "l12"))
      assert shard["sueño"] == [0, line, 0]

      assert ["act-2", "l12", "II, 12", speaker, "v", "Decir que sueño es engaño"] =
               Enum.at(lines, line)

      assert Enum.at(speakers, speaker) == "Segismundo"
    end

    test "a stage direction is marked as one", %{dir: dir} do
      {"index", "va", shard} = load_js!(dir, "search/index/va.js")

      assert [0, _line, 1] = shard["vase"]
    end

    test "a word that starts with ñ lives in a shard named by its code point", %{dir: dir} do
      {"index", "ña", shard} = load_js!(dir, "search/index/u00f1a.js")

      assert Map.has_key?(shard, "ñaque")
    end

    test "the play list is in index order, with what the facets need", %{play: play, dir: dir} do
      assert {"plays", "all",
              [%{"code" => code, "kind" => "original", "language_name" => "Español"}]} =
               load_js!(dir, "search/plays.js")

      assert code == play.code
    end
  end

  test "adding a play to a generated site adds it to the index" do
    first =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">sueño primero</l></sp></div1>)
        )
      )

    second =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>B</speaker><l n="1">sueño segundo</l></sp></div1>)
        )
      )

    dir = generate!([first], all: true)

    :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

    {"plays", "all", plays} = load_js!(dir, "search/plays.js")
    {"index", "su", shard} = load_js!(dir, "search/index/su.js")
    assert length(plays) == 2
    assert length(shard["sueño"]) == 6
  end

  test "the search page works only with JavaScript, and says so without it" do
    dir = generate!([Playcode.TestFixtures.play_fixture(%{"is_complete" => true})])
    page = html!(dir, "search.html")

    assert page |> LazyHTML.query(~s(form[hidden][role="search"])) |> Enum.count() == 1
    assert page |> LazyHTML.query("noscript") |> LazyHTML.text() =~ "Search needs JavaScript"
    assert "assets/search.js" in (page |> LazyHTML.query("script") |> LazyHTML.attribute("src"))
  end
end
