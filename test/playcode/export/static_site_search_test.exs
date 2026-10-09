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

  describe "notes in the index" do
    # Notes are entries of their own, numbered from Search.note_base/0 so the browser
    # tells them apart by number alone, their text in search/lines/<CODE>/n<k>.js.
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="jornada" n="1"><head>Jornada I</head>
              <sp><speaker>Rosaura<note n="1" type="editor"><p>Dama disfrazada.</p></note></speaker><l n="1">Hipogrifo violento<note n="2" type="traductor"><p>Animal <emph>fabuloso</emph> y</p><p>quimera.</p></note></l></sp>
            </div1>
            <div1 type="jornada" n="2"><head>Jornada II<note n="3"><p>Segunda parte.</p></note></head>
              <sp><speaker>Clarín</speaker><l n="2">¡Ñaque!</l></sp>
            </div1>
            """
          )
        )

      %{play: play, dir: generate!([play], all: true)}
    end

    test "a word found only in a note points past the play's lines, at the note", %{
      play: play,
      dir: dir
    } do
      base = Search.note_base()
      {"index", "qu", shard} = load_js!(dir, "search/index/qu.js")

      # The play's second note: entry base + 1, flag 0.
      assert shard["quimera"] == [0, 1, (base + 1) * 2]

      {"lines", key, %{"speakers" => speakers, "lines" => notes}} =
        load_js!(dir, "search/lines/#{play.code}/n0.js")

      assert key == "#{play.code}/n0"

      speaker = fn index -> index && Enum.at(speakers, index) end

      assert [
               ["act-1", "nref-1", "I, 1", rosaura, "n", "Dama disfrazada."],
               ["act-1", "nref-2", "I, 1", rosaura, "n", "Animal fabuloso y quimera."],
               ["act-2", "nref-3", "Jornada II", nil, "n", "Segunda parte."]
             ] = notes

      assert speaker.(rosaura) == "Rosaura"
    end

    test "the play's own lines files hold no note", %{play: play, dir: dir} do
      {"lines", _, %{"lines" => lines}} = load_js!(dir, "search/lines/#{play.code}/0.js")

      refute Enum.any?(lines, &(Enum.at(&1, 4) == "n"))
      refute File.exists?(Path.join([dir, "search", "lines", play.code, "n1.js"]))
    end

    test "each note's marker carries the id its search result links to", %{
      play: play,
      dir: dir
    } do
      ids = fn file ->
        dir
        |> html!("plays/#{play.code}/#{file}")
        |> LazyHTML.query("button.nref")
        |> LazyHTML.attribute("id")
      end

      assert ids.("act-1.html") == ["nref-1", "nref-2"]
      assert ids.("act-2.html") == ["nref-3"]
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

  # The build holds every play's postings until it writes the index. As lists of
  # {line, flag} tuples, 40 bytes each, the 6.3 million of 371 plays took 455 MB, and the
  # index written from them peaked at 1.7 GB on a 1 GB machine (2026-10-08).
  test "the build holds a play's postings compactly until it writes the index" do
    lines = Enum.map_join(1..2000, "", &~s(<l n="#{&1}">sueño vida honra amor muerte</l>))

    play =
      import_tei!(
        tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker>#{lines}</sp></div1>))
      )

    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    test = self()

    # What survives a full collection of the process running the build: exact, not the
    # heap's rounded-up size.
    live = fn ->
      :erlang.garbage_collect()
      {:garbage_collection_info, info} = Process.info(self(), :garbage_collection_info)
      info[:recent_size] * :erlang.system_info(:wordsize)
    end

    on_progress = fn
      %{step: :assets} -> Process.put(:live_before_plays, live.())
      %{step: :catalogue} -> send(test, {:held, live.() - Process.get(:live_before_plays)})
      _ -> :ok
    end

    assert {:ok, _} =
             Playcode.Export.StaticSite.generate(
               output_dir: dir,
               play_codes: [play.code],
               all: true,
               on_progress: on_progress
             )

    # 10,000 postings: 400 KB as tuples.
    assert_received {:held, held}
    assert held < 100_000
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

  # A play of one verse: "sueño" and `word`.
  defp one_verse_play(title, word) do
    import_tei!(
      tei(
        title: title,
        body:
          ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">sueño #{word}</l></sp></div1>)
      )
    )
  end

  defp rewrite_verse!(play, text) do
    [line] =
      for d <- Playcode.PlayContent.load_play_content(play.id),
          el <- d.loaded_elements,
          %{type: "verse_line"} = l <- el.children,
          do: l

    {:ok, _} = Playcode.PlayContent.update_element(line, %{content: text})
  end

  test "a word only an inline stage direction holds is a stage direction hit; a spoken word keeps its flag" do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="jornada" n="1"><head>Jornada I</head>
            <sp><speaker>Segismundo</speaker><l n="12">Decir que sueño es engaño <stage>(vase, sueño)</stage></l></sp>
          </div1>
          """
        )
      )

    dir = generate!([play], all: true)

    {"index", "va", va} = load_js!(dir, "search/index/va.js")
    {"index", "su", su} = load_js!(dir, "search/index/su.js")
    {"index", "en", en} = load_js!(dir, "search/index/en.js")

    # Play 0, one line (0), delta = line * 2 + flag.
    assert va["vase"] == [0, 1, 1]
    # In the stage and spoken in the same line: one posting, spoken.
    assert su["sueño"] == [0, 1, 0]
    assert en["engaño"] == [0, 1, 0]
  end

  describe "updating a generated site" do
    setup do
      # Distinct titles fix the catalogue order: "Alfa" (second) sorts before "Zeta"
      # (first), so adding or removing the second renumbers the first.
      %{first: one_verse_play("Zeta", "primero"), second: one_verse_play("Alfa", "segundo")}
    end

    test "adding a play leaves the others' search entries as they were last generated",
         %{first: first, second: second} do
      dir = generate!([first], all: true)

      # Change the first play after the site was built: adding the second must not
      # reload it, so its entries still say "primero".
      rewrite_verse!(first, "nada")

      :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

      {"index", "pr", shard} = load_js!(dir, "search/index/pr.js")
      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      first_index = Enum.find_index(plays, &(&1["code"] == first.code))

      # Added play first, so the carried one moved from index 0 to 1.
      assert first_index == 1
      assert [1, 1, _] = shard["primero"]
      refute File.exists?(Path.join([dir, "search", "index", "na.js"]))
    end

    test "a word on several lines keeps every line when it is carried over",
         %{second: second} do
      lines = Enum.map_join(1..3, "", &~s(<l n="#{&1}">sueño #{&1}</l>))

      three =
        import_tei!(
          tei(
            title: "Zeta",
            body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker>#{lines}</sp></div1>)
          )
        )

      dir = generate!([three], all: true)
      {"index", "su", before} = load_js!(dir, "search/index/su.js")
      assert before["sueño"] == [0, 3, 0, 2, 2]

      :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

      # "Alfa" (second) is play 0 now; Zeta's three lines follow, as they were.
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")
      assert shard["sueño"] == [0, 1, 0, 1, 3, 0, 2, 2]
    end

    test "a published play with no text does not switch the incremental index off",
         %{first: first, second: second} do
      empty = Playcode.TestFixtures.play_fixture(%{"is_complete" => true})
      dir = generate!([first, empty], all: true)
      rewrite_verse!(first, "nada")

      :ok = Playcode.Export.StaticSite.generate_single_play(second.id, output_dir: dir)

      {"index", "pr", shard} = load_js!(dir, "search/index/pr.js")
      assert Map.has_key?(shard, "primero")
      refute File.exists?(Path.join([dir, "search", "index", "na.js"]))
    end

    test "a play whose pages a batch wrote, but not its search, is indexed by the next one",
         %{first: first, second: second} do
      dir = generate!([first], all: true)

      # What a batch cut short after its pages leaves behind: the play's pages and
      # search lines are on disk, but the index (plays.js and the shards) lacks it.
      assert_raise RuntimeError, fn ->
        Playcode.Export.StaticSite.apply_changes([{:add, second.id}],
          output_dir: dir,
          on_published: fn -> raise "cut short" end
        )
      end

      third = one_verse_play("Mu", "tercero")

      {:ok, _} =
        Playcode.Export.StaticSite.apply_changes([{:add, third.id}], output_dir: dir)

      # Title order is Alfa (second), Mu (third), Zeta (first): second is play 0.
      {"index", "se", shard} = load_js!(dir, "search/index/se.js")
      assert [0, 1, _] = shard["segundo"]
    end

    test "removing a play takes its lines and its words out of the index",
         %{first: first, second: second} do
      dir = generate!([first, second], all: true)

      :ok = Playcode.Export.StaticSite.remove_single_play(second.code, output_dir: dir)

      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      {"index", "su", shard} = load_js!(dir, "search/index/su.js")

      # The removed play was index 0; the survivor was index 1 and is now 0.
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

      # What a build before chunked lines left: a lines file, not a folder, and shards of
      # [play, line, flag] triples. Read as [play, n, deltas…], a word once on line 0
      # leaves a stray element.
      File.rm_rf!(Path.join([dir, "search", "lines", first.code]))
      File.write!(Path.join([dir, "search", "lines", "#{first.code}.js"]), "old")

      File.write!(
        Path.join([dir, "search", "index", "su.js"]),
        ~s|EMOTHE.search.load("index","su",{"sueño":[0,0,0]});\n|
      )

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
