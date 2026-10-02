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

  test "lines are chunked in the size the browser expects" do
    assert Search.lines_per_chunk() == cases()["lines_per_chunk"]
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

    test "a word's shard points at its line, and the line's chunk holds it as printed", %{
      play: play,
      dir: dir
    } do
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")

      {"lines", key, %{"speakers" => speakers, "lines" => lines}} =
        load_js!(dir, "search/lines/#{play.code}/0.js")

      assert key == "#{play.code}/0"
      line = Enum.find_index(lines, &(Enum.at(&1, 1) == "l12"))

      # Play 0, one line, delta line * 2 + flag 0.
      assert shard["sueño"] == [0, 1, line * 2]

      assert ["act-2", "l12", "II, 12", speaker, "v", "Decir que sueño es engaño"] =
               Enum.at(lines, line)

      assert Enum.at(speakers, speaker) == "Segismundo"
    end

    test "a stage direction is marked as one", %{dir: dir} do
      {"index", "va", shard} = load_js!(dir, "search/index/va.js")

      assert [0, 1, delta] = shard["vase"]
      assert rem(delta, 2) == 1
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

  test "a long play's lines are written in chunks of 100, each naming its own speakers" do
    verses = fn speaker, from, to ->
      lines = Enum.map_join(from..to, "", &~s(<l n="#{&1}">verso #{&1}</l>))
      "<sp><speaker>#{speaker}</speaker>#{lines}</sp>"
    end

    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            #{verses.("ANA", 1, 100)}#{verses.("JUAN", 101, 150)}
          </div1>
          """
        )
      )

    dir = generate!([play], all: true)

    {"lines", _, first} = load_js!(dir, "search/lines/#{play.code}/0.js")
    {"lines", _, second} = load_js!(dir, "search/lines/#{play.code}/1.js")
    refute File.exists?(Path.join([dir, "search", "lines", play.code, "2.js"]))

    assert {length(first["lines"]), first["speakers"]} == {100, ["ANA"]}
    assert {length(second["lines"]), second["speakers"]} == {50, ["JUAN"]}
    assert Enum.at(second["lines"], 0) |> Enum.at(1) == "l101"

    # "120" occurs only in verse 120, the 120th line (index 119): delta 119 * 2.
    {"index", "12", shard} = load_js!(dir, "search/index/12.js")
    assert shard["120"] == [0, 1, 238]
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
    # One line in play 0 and one in play 1.
    assert [0, 1, _, 1, 1, _] = shard["sueño"]
  end

  describe "updating a generated site" do
    setup do
      play = fn word ->
        import_tei!(
          tei(
            body:
              ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">sueño #{word}</l></sp></div1>)
          )
        )
      end

      %{first: play.("primero"), second: play.("segundo")}
    end

    test "adding a play leaves the others' search entries as they were last generated",
         %{first: first, second: second} do
      dir = generate!([first], all: true)

      # Change the first play after the site was built: adding the second must not
      # reload it, so its entries still say "primero".
      [line] =
        for d <- Playcode.PlayContent.load_play_content(first.id),
            el <- d.loaded_elements,
            %{type: "verse_line"} = l <- el.children,
            do: l

      {:ok, _} = Playcode.PlayContent.update_element(line, %{content: "nada"})

      :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

      {"index", "pr", shard} = load_js!(dir, "search/index/pr.js")
      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      first_index = Enum.find_index(plays, &(&1["code"] == first.code))

      assert [^first_index, 1, _] = shard["primero"]
      refute File.exists?(Path.join([dir, "search", "index", "na.js"]))
    end

    test "removing a play takes its lines and its words out of the index",
         %{first: first, second: second} do
      dir = generate!([first, second], all: true)

      :ok = Playcode.Export.StaticSite.remove_single_play(second.code, output_dir: dir)

      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")

      assert Enum.map(plays, & &1["code"]) == [first.code]
      assert shard["sueño"] == [0, 1, 0]
      refute File.exists?(Path.join([dir, "search", "index", "se.js"]))
      refute File.exists?(Path.join([dir, "search", "lines", second.code]))
    end

    test "removing the last play leaves an empty site that still builds", %{first: first} do
      dir = generate!([first], all: true)

      :ok = Playcode.Export.StaticSite.remove_single_play(first.code, output_dir: dir)

      assert {"plays", "all", []} = load_js!(dir, "search/plays.js")
      assert Path.wildcard(Path.join([dir, "search", "index", "*.js"])) == []
      assert read!(dir, "index.html") =~ "0 plays"
    end

    test "a site whose index predates chunked lines is re-indexed in full",
         %{first: first, second: second} do
      dir = generate!([first], all: true)

      # What a build before chunked lines left: a lines file, not a folder.
      File.rm_rf!(Path.join([dir, "search", "lines", first.code]))
      File.write!(Path.join([dir, "search", "lines", "#{first.code}.js"]), "old")

      :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

      {"index", "su", shard} = load_js!(dir, "search/index/su.js")
      assert [0, 1, 0, 1, 1, 0] = shard["sueño"]
      assert File.exists?(Path.join([dir, "search", "lines", first.code, "0.js"]))
      refute File.exists?(Path.join([dir, "search", "lines", "#{first.code}.js"]))
    end
  end

  test "the search page works only with JavaScript, and says so without it" do
    dir = generate!([Playcode.TestFixtures.play_fixture(%{"is_complete" => true})])
    page = html!(dir, "search.html")

    assert page |> LazyHTML.query(~s(form[hidden][role="search"])) |> Enum.count() == 1
    assert page |> LazyHTML.query("noscript") |> LazyHTML.text() =~ "Search needs JavaScript"
    assert "assets/search.js" in (page |> LazyHTML.query("script") |> LazyHTML.attribute("src"))
  end
end
