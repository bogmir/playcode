defmodule Playcode.Export.StaticSiteTest do
  @moduledoc """
  The published site as a whole: which plays it publishes, where each file goes, and
  each play's title page. Generated with `StaticSite.generate/1` into a temp
  directory and read back as the files a visitor gets.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers

  alias Playcode.Catalogue
  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.Pages

  defp complete_play(attrs \\ %{}), do: play_fixture(Map.put(attrs, "is_complete", true))
  defp title_page(dir, play), do: html!(dir, "plays/#{play.code}/index.html")
  defp hrefs(html), do: html |> LazyHTML.query("a") |> LazyHTML.attribute("href")

  test "only complete plays are published, and only they are in the catalogue" do
    complete = complete_play(%{"title" => "Obra terminada"})
    draft = play_fixture(%{"title" => "Obra en curso"})

    dir = generate!([complete, draft])

    assert File.exists?(Path.join([dir, "plays", complete.code, "index.html"]))
    assert File.exists?(Path.join([dir, "plays", complete.code, "#{complete.code}.xml"]))
    refute File.exists?(Path.join([dir, "plays", draft.code]))

    index = read!(dir, "index.html")
    assert index =~ "Obra terminada"
    refute index =~ "Obra en curso"
  end

  test "with nothing complete to publish, nothing is generated" do
    assert {:error, _} =
             StaticSite.generate(output_dir: "/nonexistent", play_codes: [play_fixture().code])
  end

  test "the address of the previous layout redirects to the play's folder" do
    play = complete_play()
    stub = html!(generate!([play]), "plays/#{play.code}.html")

    assert stub |> LazyHTML.query(~s(meta[http-equiv="refresh"])) |> LazyHTML.attribute("content") ==
             ["0; url=#{play.code}/index.html"]

    assert hrefs(stub) == ["#{play.code}/index.html"]
  end

  test "the stylesheet, script and fonts are published under assets/, with the font licences" do
    dir = generate!([complete_play()])

    assert File.exists?(Path.join([dir, "assets", "style.css"]))
    assert File.exists?(Path.join([dir, "assets", "site.js"]))
    assert Path.wildcard(Path.join([dir, "assets", "fonts", "*.woff2"])) != []
    assert Path.wildcard(Path.join([dir, "assets", "fonts", "OFL-*.txt"])) != []
  end

  test "the title page carries the play's metadata, edition, sources and front notes" do
    {:ok, play} =
      Catalogue.update_play(play_with_metadata_fixture(), %{
        "is_complete" => true,
        "author_name" => "Pedro Calderón de la Barca"
      })

    page = title_page(generate!([play]), play)
    text = LazyHTML.text(page)

    assert texts(page, "h1") == [play.title]
    assert text =~ "Pedro Calderón de la Barca"
    assert text =~ "Editor One"
    assert text =~ "Source note"
    assert "Editorial heading" in texts(page, "h2")
    assert text =~ "Editorial content"
    assert text =~ "ed. Editor One"
    assert "#{play.code}.xml" in hrefs(page)
  end

  test "the title page lists the cast and the contents, linking each act's page" do
    %{play: play} = play_with_structure_fixture()
    page = title_page(generate!([play], all: true), play)

    assert "ALFA" in texts(page, "dt")
    assert "act-1.html" in hrefs(page)
    assert "text.html" in hrefs(page)
    assert "statistics.html" in hrefs(page)
  end

  # The play's own heading, as the TEI file, the play page and the downloads carry it.
  test "the cast list carries the play's own heading" do
    play =
      tei(
        front: """
        <div type="elenco">
          <head>Hablan en ella las personas siguientes</head>
          <castList><castItem><role xml:id="DON">Don Juan</role></castItem></castList>
        </div>
        """
      )
      |> import_tei!()

    {:ok, play} = Catalogue.update_play(play, %{"is_complete" => true})
    page = title_page(generate!([play]), play)

    assert "Hablan en ella las personas siguientes" in texts(page, "h2")
    refute "Dramatis personae" in texts(page, "h2")
  end

  # Stored as <<…>>, printed as italics; a heading in a link or a page's title, as plain text.
  test "italics outside the text are printed as italics, and never as the markers" do
    play =
      tei(
        source_desc:
          "<bibl><title><emph>Aminta</emph></title><note>Tasso. <emph>Aminta</emph>. Venezia.</note></bibl>",
        front: """
        <div type="dedicatoria"><head>A <emph>Damone</emph></head><p>Dedica <emph>Egle</emph>.</p></div>
        <div type="elenco"><head><emph>Dramatis Personae</emph></head><castList>
          <castItem><role xml:id="CORT"><emph>The courtiers</emph></role><roleDesc>(<emph>Spela</emph>), a servant</roleDesc></castItem>
        </castList></div>
        <set><p><emph>La Scena è in Atene.</emph></p></set>
        """,
        body:
          ~s(<div1 type="acto" n="1"><head><emph>Actus Primus</emph></head><sp><speaker>CORT</speaker><p>Texto.</p></sp></div1>)
      )
      |> import_tei!()

    {:ok, play} = Catalogue.update_play(play, %{"is_complete" => true})
    dir = generate!([play])

    for page <- ["index.html", "act-1.html", "statistics.html"],
        do: refute(read!(dir, "plays/#{play.code}/#{page}") =~ "&lt;&lt;", page)

    ems = dir |> title_page(play) |> texts("em")

    for italic <-
          ~w(Aminta Damone Egle Spela) ++
            ["The courtiers", "La Scena è in Atene.", "Dramatis Personae"],
        do: assert(italic in ems, italic)
  end

  # Under the cast list, as on emothe.uv.es, and not among the front matter above it.
  test "the scene of the action follows the cast list" do
    play =
      tei(
        front: """
        <div type="elenco"><castList><castItem><role xml:id="DON">Don Juan</role></castItem></castList></div>
        <set><head>SCENE:</head><p>An English wood.</p></set>
        """
      )
      |> import_tei!()

    {:ok, play} = Catalogue.update_play(play, %{"is_complete" => true})
    page = title_page(generate!([play]), play)

    assert texts(page, "dl.cast ~ h3") == ["SCENE:"]
    assert texts(page, "dl.cast ~ p") == ["An English wood."]
    refute "SCENE:" in texts(page, "h2")
  end

  # "Procedencia" on emothe.uv.es. A placeholder ("Texto base", 59 plays) stays in the
  # file but is not printed; question 27 asks the project what it means.
  test "a source says where its digital text came from, unless that is a placeholder" do
    play =
      tei(
        source_desc: """
          <bibl><title>Aminta</title><note>Tasso, Torquato. Aminta.</note>
            <distributor>IntraText Digital Library</distributor></bibl>
          <bibl><title>Hamlet</title><distributor>Texto base</distributor></bibl>
          <bibl><title>El pastor fido</title><distributor>ProcedenciaFuente</distributor></bibl>
        """
      )
      |> import_tei!()

    {:ok, play} = Catalogue.update_play(play, %{"is_complete" => true})
    sources = play |> then(&title_page(generate!([&1]), &1)) |> texts("li")

    # The note's own period ends its sentence: no "Aminta.. Provenance".
    assert "Aminta. Tasso, Torquato. Aminta. Provenance: IntraText Digital Library" in sources
    assert "Hamlet" in sources
    assert "El pastor fido" in sources
  end

  test "a cast list with no heading of its own is the Dramatis personae" do
    %{play: play} = play_with_structure_fixture()
    page = title_page(generate!([play], all: true), play)

    assert "Dramatis personae" in texts(page, "h2")
  end

  test "an original's title page links its published translations, and only those" do
    %{original: original, translation: translation} = translation_family_fixture()

    unpublished =
      play_fixture(%{"parent_play_id" => original.id, "relationship_type" => "traduccion"})

    page = title_page(generate!([original, translation]), original)

    assert "../#{translation.code}/index.html" in hrefs(page)
    refute "../#{unpublished.code}/index.html" in hrefs(page)
  end

  # Question 15: an adaptation says so; every derived play used to say "Translation of".
  test "a derived play's title page names its kind and the play it comes from" do
    %{original: original, translation: translation} = translation_family_fixture()

    adaptation =
      play_fixture(%{
        "is_complete" => true,
        "parent_play_id" => original.id,
        "relationship_type" => "adaptacion"
      })

    dir = generate!([original, translation, adaptation])

    assert "Adaptation of #{original.title}" in texts(title_page(dir, adaptation), "p")
    assert "Translation of #{original.title}" in texts(title_page(dir, translation), "p")
  end

  # The family list said only each play's language: an adaptation read as a translation.
  test "an original's title page says what kind of play each of its family is" do
    %{original: original, translation: translation} = translation_family_fixture()

    adaptation =
      play_fixture(%{
        "is_complete" => true,
        "title" => "Le Menteur",
        "parent_play_id" => original.id,
        "relationship_type" => "adaptacion"
      })

    roles = texts(title_page(generate!([original, translation, adaptation]), original), ".role")

    assert Enum.any?(roles, &(&1 =~ "adaptation"))
    assert Enum.any?(roles, &(&1 =~ "translation"))
  end

  # A kind added to Play.relationship_types/0 needs a word on the site, or kind/1 raises.
  test "every kind a play can have has the site's word for it" do
    for type <- Playcode.Catalogue.Play.relationship_types() do
      refute StaticSite.Components.kind(%{relationship_type: type}) == "original", type
    end
  end

  # FileMaker linked some plays with no kind (the Faustus B-text under the A-text): the
  # play page names no relation for them, and "Original of" would be false.
  test "a play linked with no kind names no relation to the other" do
    original = play_fixture(%{"is_complete" => true})
    linked = play_fixture(%{"is_complete" => true, "parent_play_id" => original.id})

    refute Enum.any?(
             texts(title_page(generate!([original, linked]), linked), "p"),
             &String.ends_with?(&1, " of #{original.title}")
           )
  end

  test "adding or removing a translation updates its original's title page" do
    %{original: original, translation: translation} = translation_family_fixture()
    dir = generate!([original])
    link = "../#{translation.code}/index.html"

    :ok = StaticSite.generate_single_play(translation.id, output_dir: dir)
    assert link in hrefs(title_page(dir, original))

    :ok = StaticSite.remove_single_play(translation.code, output_dir: dir)
    refute link in hrefs(title_page(dir, original))
  end

  test "adding or removing an original updates its published translation's title page" do
    %{original: original, translation: translation} = translation_family_fixture()
    dir = generate!([translation])
    link = "../#{original.code}/index.html"

    :ok = StaticSite.generate_single_play(original.id, output_dir: dir)
    assert link in hrefs(title_page(dir, translation))

    :ok = StaticSite.remove_single_play(original.code, output_dir: dir)
    refute link in hrefs(title_page(dir, translation))
  end

  describe "a relative edited since it was last exported" do
    defp add_act(play, n, text) do
      {:ok, act} =
        Playcode.PlayContent.create_division(%{
          play_id: play.id,
          type: "acto",
          number: n,
          title: "ACT #{n}",
          position: n
        })

      {:ok, _} =
        Playcode.PlayContent.create_element(%{
          play_id: play.id,
          division_id: act.id,
          type: "stage_direction",
          content: text,
          position: 1
        })
    end

    # Every act its title page links is on disk, and `word` finds `text` in its lines.
    defp assert_published_as_it_stands(dir, play, word, text) do
      acts = dir |> title_page(play) |> hrefs() |> Enum.filter(&(&1 =~ ~r/^act-/))
      assert acts != []

      for href <- acts do
        file = href |> String.split("#") |> hd()
        assert File.exists?(Path.join([dir, "plays", play.code, file])), "#{href} is dead"
      end

      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      {"index", key, shard} = load_js!(dir, "search/index/#{String.slice(word, 0, 2)}.js")
      assert key == String.slice(word, 0, 2)
      [p, 1, delta] = shard[word]
      assert Enum.at(plays, p)["code"] == play.code

      {"lines", _, %{"lines" => lines}} = load_js!(dir, "search/lines/#{play.code}/0.js")
      assert lines |> Enum.at(div(delta, 2)) |> Enum.at(5) == text
    end

    test "is re-exported in full when a play of its family is added or removed" do
      %{original: original, translation: translation} = translation_family_fixture()
      add_act(original, 1, "Sale Gaspar")
      dir = generate!([original])

      add_act(original, 2, "Sale Tisbea")
      :ok = StaticSite.generate_single_play(translation.id, output_dir: dir)
      assert_published_as_it_stands(dir, original, "tisbea", "Sale Tisbea")

      add_act(original, 3, "Sale Anfriso")
      :ok = StaticSite.remove_single_play(translation.code, output_dir: dir)
      assert_published_as_it_stands(dir, original, "anfriso", "Sale Anfriso")
    end
  end

  test "a play page carries its places and its historical time, in English whatever the locale" do
    play = complete_play(%{"historical_time" => "siglo_xvii"})
    play_place_fixture(play, place_fixture(%{"name" => "Roma"}))

    dir = Gettext.with_locale(PlaycodeWeb.Gettext, "es", fn -> generate!([play]) end)
    html = read!(dir, "plays/#{play.code}/index.html")

    assert html =~ "Roma"
    assert html =~ "17th century"
    refute html =~ "Siglo XVII"
  end

  test "a play with no places has no places section" do
    play = complete_play()

    refute "Places" in texts(title_page(generate!([play]), play), "h2")
  end

  test "a composition date shows as a range, a single year, or the note alone" do
    range =
      complete_play(%{
        "composition_date_from" => 1606,
        "composition_date_to" => 1607,
        "composition_date_note" => "1606; 1607"
      })

    single = complete_play(%{"composition_date_from" => 1614, "composition_date_to" => 1614})
    note_only = complete_play(%{"composition_date_note" => "¿1694? y ¿1605?"})

    dir = generate!([range, single, note_only])
    page = fn play -> read!(dir, "plays/#{play.code}/index.html") end

    assert page.(range) =~ "1606–1607"
    assert page.(range) =~ "1606; 1607"
    assert page.(single) =~ "1614"
    refute page.(single) =~ "1614–1614"
    assert page.(note_only) =~ "¿1694? y ¿1605?"
  end

  test "one play can be added to or removed from a generated site" do
    first = complete_play(%{"title" => "Primera"})
    dir = generate!([first])
    second = complete_play(%{"title" => "Segunda"})

    :ok = StaticSite.generate_single_play(second.id, output_dir: dir)
    assert StaticSite.list_exported_codes(dir) == Enum.sort([first.code, second.code])

    :ok = StaticSite.remove_single_play(first.code, output_dir: dir)
    assert StaticSite.list_exported_codes(dir) == [second.code]
    refute File.exists?(Path.join([dir, "plays", "#{first.code}.html"]))
    assert read!(dir, "index.html") =~ "Segunda"
    refute read!(dir, "index.html") =~ "Primera"
  end

  test "removing a play only ever touches that play's own folder" do
    play = complete_play()
    dir = generate!([play])

    for bad <- ["..", "", ".", "../..", "no-such-play"] do
      assert :ok = StaticSite.remove_single_play(bad, output_dir: dir)
    end

    assert StaticSite.list_exported_codes(dir) == [play.code]
    assert File.exists?(Path.join([dir, "plays", play.code, "index.html"]))
  end

  test "a play code that is not a plain name is refused before anything is deleted" do
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    sentinel = Path.join(Path.dirname(dir), "sentinel-#{System.unique_integer([:positive])}")
    File.mkdir_p!(sentinel)
    File.write!(Path.join(sentinel, "keep.txt"), "keep")
    on_exit(fn -> File.rm_rf(sentinel) end)

    evil = complete_play(%{"code" => "../../#{Path.basename(sentinel)}"})

    assert_raise ArgumentError, fn ->
      StaticSite.generate(output_dir: dir, play_codes: [evil.code])
    end

    assert File.read!(Path.join(sentinel, "keep.txt")) == "keep"
    File.rm_rf(dir)
  end

  test "the footer carries the play's licence, linked only when it is a web address" do
    web =
      complete_play(%{"licence_url" => "https://example.org/licence", "licence_text" => "CC BY"})

    evil = complete_play(%{"licence_url" => "javascript:alert(1)"})

    dir = generate!([web, evil])
    footer = fn play -> dir |> title_page(play) |> LazyHTML.query("footer") end

    assert "https://example.org/licence" in hrefs(footer.(web))
    assert LazyHTML.text(footer.(web)) =~ "CC BY"

    assert LazyHTML.text(footer.(evil)) =~ "javascript:alert(1)"
    refute Enum.any?(hrefs(title_page(dir, evil)), &String.starts_with?(&1, "javascript:"))
  end

  test "the HEEx annotations dev compiles in never reach the archive" do
    # config/dev.exs turns them on; the test env cannot, so the function is tested directly.
    html =
      ~s[<!-- <Playcode.X.y> lib/x.ex:3 (playcode) --><p data-phx-loc="12">Hi</p>] <>
        ~s[<!-- </Playcode.X.y> --><!-- @caller lib/y.ex:9 (playcode) -->]

    assert Pages.strip_annotations(html) == "<p>Hi</p>"
  end

  test "the about page says what the archive holds and how to cite it" do
    dir = generate!([complete_play(), complete_play()], version: "2.1")
    about = html!(dir, "about.html")

    assert texts(about, "h1") == ["About this edition"]
    assert LazyHTML.text(about) =~ "2 plays"
    assert LazyHTML.text(about) =~ "version 2.1"
  end

  test "the shared assets stay inside the size budget and nothing loads from another host" do
    %{play: play} = play_with_structure_fixture()
    dir = generate!([play], all: true)
    size = fn file -> File.stat!(Path.join([dir, "assets", file])).size end

    assert size.("style.css") <= 25_000
    assert size.("site.js") <= 15_000
    assert size.("search.js") <= 15_000

    fonts =
      dir
      |> Path.join("assets/fonts/*.woff2")
      |> Path.wildcard()
      |> Enum.map(&File.stat!(&1).size)

    assert Enum.sum(fonts) <= 300_000

    for page <- Path.wildcard(Path.join(dir, "**/*.html")) do
      refute File.read!(page) =~ ~r/<(?:script|link|img)[^>]+(?:src|href)="https?:/,
             "#{page} loads from another host"
    end

    refute File.read!(Path.join([dir, "assets", "style.css"])) =~ ~r/url\(\s*["']?https?:/
  end

  # The muted grey prints the Folio passages, the notes' heads and every caption: WCAG AA
  # asks 4.5:1 for text, in the light theme and the dark one.
  test "the muted grey reads at 4.5:1 on the paper in both themes" do
    dir = generate!([complete_play()])
    css = File.read!(Path.join([dir, "assets", "style.css"]))
    tokens = fn name -> for [_, hex] <- Regex.scan(~r/--#{name}: #(\w{6})/, css), do: hex end
    themes = Enum.zip(tokens.("muted"), tokens.("paper"))

    assert length(themes) == 2

    for {muted, paper} <- themes do
      assert contrast(muted, paper) >= 4.5, "##{muted} on ##{paper}"
    end
  end

  # WCAG 2's contrast ratio of two sRGB colours, as six hex digits.
  defp contrast(a, b) do
    [light, dark] = Enum.sort([luminance(a), luminance(b)], :desc)
    (light + 0.05) / (dark + 0.05)
  end

  defp luminance(hex) do
    [r, g, b] =
      for <<channel::binary-size(2) <- hex>> do
        c = String.to_integer(channel, 16) / 255
        if c <= 0.04045, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
      end

    0.2126 * r + 0.7152 * g + 0.0722 * b
  end

  test "a generated site reports its largest page and its index sizes" do
    %{play: play} = play_with_structure_fixture()
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, %{largest_page_gzip: page, index_bytes: index, largest_shard_bytes: shard}} =
             StaticSite.generate(output_dir: dir, play_codes: [play.code], all: true)

    assert page > 0 and index > 0 and shard > 0
  end

  # A Generate cut short (out of memory, a restart) used to leave whatever it had written
  # after deleting the site: some plays, no catalogue, no search, no build.json.
  test "a build cut short leaves the site it was replacing as it was" do
    play = complete_play()
    dir = generate!([play])

    before =
      for path <- Path.wildcard(Path.join(dir, "**")),
          into: %{},
          do: {path, File.stat!(path).size}

    assert_raise RuntimeError, fn ->
      StaticSite.generate(
        output_dir: dir,
        play_codes: [play.code],
        on_progress: fn
          %{step: :play} -> raise "cut short"
          _ -> :ok
        end
      )
    end

    after_ =
      for path <- Path.wildcard(Path.join(dir, "**")),
          into: %{},
          do: {path, File.stat!(path).size}

    assert after_ == before
  end

  test "the next build clears what a cut-short one left beside the site" do
    play = complete_play()
    dir = generate!([play])

    for leftover <- [dir <> ".new", dir <> ".old"] do
      File.mkdir_p!(leftover)
      File.write!(Path.join(leftover, "stray.html"), "")
    end

    assert {:ok, _} = StaticSite.generate(output_dir: dir, play_codes: [play.code])

    assert File.exists?(Path.join(dir, "build.json"))
    refute File.exists?(Path.join(dir, "stray.html"))
    refute File.exists?(dir <> ".new")
    refute File.exists?(dir <> ".old")
  end

  # The export page's progress bar moves on these. Reported only once the last play was
  # built, it sat at "Writing assets..." for the whole of a 372-play Generate.
  test "each play is reported as it is built, while the plays after it wait" do
    workers = min(System.schedulers_online(), Playcode.Repo.config()[:pool_size] - 2)
    plays = for _ <- 1..(workers + 2), do: complete_play()
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    test = self()

    on_progress = fn
      %{step: :play, current: 1} ->
        send(test, {:written, length(StaticSite.list_exported_codes(dir))})

      _ ->
        :ok
    end

    assert {:ok, _} =
             StaticSite.generate(
               output_dir: dir,
               play_codes: Enum.map(plays, & &1.code),
               on_progress: on_progress
             )

    assert_received {:written, written}
    assert written < length(plays)
  end

  test "the title page names the curator's form" do
    prose = complete_play(%{"form" => "prose"})
    mixed = complete_play(%{"form" => "mixed"})
    bare_verse = complete_play(%{"form" => "verse"})
    dir = generate!([prose, mixed, bare_verse])

    form = fn play ->
      title_page(dir, play) |> LazyHTML.query("dd") |> Enum.map(&squish(LazyHTML.text(&1)))
    end

    assert "Prose" in form.(prose)
    assert Enum.any?(form.(mixed), &String.starts_with?(&1, "Verse and prose"))
    # A fixture play has no verse lines: no "· 0 verses".
    assert "Verse" in form.(bare_verse)
  end

  describe "a batch of changes" do
    test "adds and removes several plays in one go" do
      a = complete_play(%{"title" => "Alfa Batch Tragedy"})
      b = complete_play(%{"title" => "Beta Batch Comedy"})
      c = complete_play(%{"title" => "Gamma Batch Farce"})
      dir = generate!([a])

      assert {:ok, %{skipped: []}} =
               StaticSite.apply_changes([{:add, b.id}, {:remove, a.code}, {:add, c.id}],
                 output_dir: dir
               )

      assert StaticSite.list_exported_codes(dir) == Enum.sort([b.code, c.code])
      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      assert Enum.sort(Enum.map(plays, & &1["code"])) == Enum.sort([b.code, c.code])
      assert read!(dir, "index.html") =~ "Gamma Batch Farce"
      refute read!(dir, "index.html") =~ "Alfa Batch Tragedy"
    end

    # Regression: the removes ran before safe_code! rejected an added play, so a batch with
    # one unusable code left the site half-applied.
    test "a batch with an unusable code raises before it writes anything" do
      a = complete_play(%{"title" => "Alfa Untouched Tragedy"})
      b = complete_play()
      bad = complete_play(%{"code" => "bad/code"})
      dir = generate!([a])

      assert_raise ArgumentError, fn ->
        StaticSite.apply_changes([{:remove, a.code}, {:add, bad.id}, {:add, b.id}],
          output_dir: dir
        )
      end

      assert StaticSite.list_exported_codes(dir) == [a.code]
      assert read!(dir, "index.html") =~ "Alfa Untouched Tragedy"
    end

    test "only a play's last change counts" do
      kept_out = complete_play(%{"title" => "Kept Out"})
      put_back = complete_play(%{"title" => "Put Back"})
      dir = generate!([put_back])

      assert {:ok, _} =
               StaticSite.apply_changes(
                 [
                   {:add, kept_out.id},
                   {:remove, kept_out.code},
                   {:remove, put_back.code},
                   {:add, put_back.id}
                 ],
                 output_dir: dir
               )

      assert StaticSite.list_exported_codes(dir) == [put_back.code]
    end

    # The callback runs in the caller, between the pages and the index, so what the site
    # holds at that moment can be read without a race.
    test "pages and the catalogue are in place before the search index is written" do
      first = complete_play(%{"title" => "Published First"})
      later = complete_play(%{"title" => "Indexed Later"})
      dir = generate!([first])
      test = self()

      at_publish = fn ->
        {"plays", "all", plays} = load_js!(dir, "search/plays.js")

        send(
          test,
          {:published, StaticSite.list_exported_codes(dir), read!(dir, "index.html"),
           Enum.map(plays, & &1["code"])}
        )
      end

      {:ok, _} =
        StaticSite.apply_changes([{:add, later.id}], output_dir: dir, on_published: at_publish)

      assert_received {:published, on_disk, catalogue, searchable}
      assert later.code in on_disk
      assert catalogue =~ "Indexed Later"
      refute later.code in searchable

      {"plays", "all", plays} = load_js!(dir, "search/plays.js")
      assert later.code in Enum.map(plays, & &1["code"])
    end

    test "a play that no longer exists is skipped and the rest lands" do
      a = complete_play()
      dir = generate!([a])
      b = complete_play()
      missing = Ecto.UUID.generate()

      assert {:ok, %{skipped: [^missing]}} =
               StaticSite.apply_changes([{:add, missing}, {:add, b.id}], output_dir: dir)

      assert StaticSite.list_exported_codes(dir) == Enum.sort([a.code, b.code])
    end

    test "a translation and its original added together link each other" do
      %{original: original, translation: translation} = translation_family_fixture()
      dir = generate!([complete_play()])

      {:ok, _} =
        StaticSite.apply_changes([{:add, translation.id}, {:add, original.id}],
          output_dir: dir
        )

      assert "../#{translation.code}/index.html" in hrefs(title_page(dir, original))
      assert "../#{original.code}/index.html" in hrefs(title_page(dir, translation))
    end
  end

  test "a title page lists the published translations by title, and its notes in their order" do
    original = complete_play(%{"title" => "Original"})

    [zeta, alfa] =
      for title <- ["Zeta", "Alfa"] do
        complete_play(%{
          "title" => title,
          "title_sort" => title,
          "parent_play_id" => original.id,
          "relationship_type" => "traduccion"
        })
      end

    for {heading, position} <- [{"Second note", 2}, {"First note", 1}] do
      {:ok, _} =
        Catalogue.create_paratext(%{
          play_id: original.id,
          kind: "nota_edicion_digital",
          heading: heading,
          content: "Text",
          position: position
        })
    end

    page = title_page(generate!([original, zeta, alfa]), original)

    assert texts(page, "li a cite") == ["Alfa", "Zeta"]

    assert Enum.filter(texts(page, "h2"), &(&1 in ["First note", "Second note"])) ==
             ["First note", "Second note"]
  end

  test "the notes page prints a glossed word in italics as italics" do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><sp><speaker>ANA</speaker><l n="1">Nous voyent<note n="2" type="editor"><term><emph>voyent</emph></term><p>Forma arcaica.</p></note> dans la ville</l></sp></div1>)
      )
      |> import_tei!()
      |> mark_complete!()

    dir = generate!([play])

    refute read!(dir, "plays/#{play.code}/notes.html") =~ "&lt;&lt;"
    assert texts(html!(dir, "plays/#{play.code}/notes.html"), ".note-head em") == ["voyent"]
  end

  describe "in-text notes" do
    defp noted_play do
      tei(
        body: """
        <div1 type="acto" n="1"><head>ACTO I</head>
          <sp><speaker>ANA</speaker>
            <l n="1">Nous voyent<note n="6089" type="editor"><term>voyent</term><p>Forme archaïque.</p><p>Deux syllabes.</p></note> dans la ville</l>
            <l n="2">sin nota</l>
          </sp>
        </div1>
        <div1 type="acto" n="2"><head>ACTO II</head>
          <sp><speaker>BLAS</speaker><p>Buscad por todas partes …<note n="121" type="traductor"><p><emph>"partes …"</emph></p><p>(14) De aquí en adelante.</p></note></p></sp>
        </div1>
        """
      )
      |> import_tei!()
      |> mark_complete!()
    end

    defp marker_target(page, label) do
      page
      |> LazyHTML.query(~s(button[aria-label="#{label}"]))
      |> LazyHTML.attribute("popovertarget")
    end

    test "a note is a number after its word, opening the note, listed on its own page" do
      play = noted_play()
      dir = generate!([play])
      act1 = html!(dir, "plays/#{play.code}/act-1.html")
      act2 = html!(dir, "plays/#{play.code}/act-2.html")

      assert squish(LazyHTML.text(act1)) =~ "Nous voyent1 dans la ville"
      assert marker_target(act1, "Editor's note 1") == ["note-1"]
      assert act1 |> LazyHTML.query("#note-1") |> LazyHTML.attribute("popover") == [""]
      assert texts(act1, "#note-1 b") == ["Editor's note"]
      assert texts(act1, "#note-1 i") == ["voyent"]
      assert texts(act1, "#note-1 p") == ["Forme archaïque.", "Deux syllabes."]
      assert act1 |> LazyHTML.query("#note-2") |> Enum.count() == 0

      assert squish(LazyHTML.text(act2)) =~ "Buscad por todas partes …2"
      assert marker_target(act2, "Translator's note 2") == ["note-2"]
      assert texts(act2, "#note-2 p") == ["\"partes …\"", "(14) De aquí en adelante."]
      assert act2 |> LazyHTML.text() |> String.split("(14) De aquí") |> length() == 2
    end

    test "the full text lists every note, numbered through the play" do
      play = noted_play()
      text_page = html!(generate!([play]), "plays/#{play.code}/text.html")

      assert marker_target(text_page, "Editor's note 1") == ["note-1"]
      assert marker_target(text_page, "Translator's note 2") == ["note-2"]
      assert text_page |> LazyHTML.query("li[popover]") |> Enum.count() == 2
    end
  end

  # Question 10: readers see every break of a paratext.
  test "a paratext's line breaks are printed on the title page" do
    play =
      tei(
        front:
          ~s(<div type="dedicatoria"><p>The banished cavaliers!<lb/>A roving blade!</p></div>)
      )
      |> import_tei!()
      |> mark_complete!()

    page = read!(generate!([play]), "plays/#{play.code}/index.html")

    assert page =~ ~r{The banished cavaliers!<br/?>\s*A roving blade!}
  end

  test "a line break inside a paratext's italics is printed inside them" do
    play = play_fixture() |> mark_complete!()

    {:ok, _} =
      Catalogue.create_paratext(%{
        play_id: play.id,
        kind: "dedicatoria",
        content: "C <<una\ndos>> fin"
      })

    page = read!(generate!([play]), "plays/#{play.code}/index.html")

    refute page =~ "&lt;&lt;"
    assert page =~ ~r{<em>una<br/?>dos</em>}
  end

  # After the text on the full-text page and on the last page of the text, as emothe.uv.es
  # prints them, each in the Contents; an untitled one by its kind.
  test "the paratexts after the text are printed after it and listed in the Contents" do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><head>ACTO I</head><sp><speaker>A</speaker><p>Verso final.</p></sp></div1>),
        back: """
        <div type="epilogo"><head>EPILOGUE</head><p>The banished <emph>cavaliers</emph>!</p></div>
        <div type="colofon"><p>Loado sea.</p></div>
        """
      )
      |> import_tei!()
      |> mark_complete!()

    dir = generate!([play])

    for path <- ["text.html", "act-1.html"] do
      page = read!(dir, "plays/#{play.code}/#{path}")
      assert [_text, after_text] = String.split(page, "Verso final.")

      assert after_text =~
               ~r{<h2[^>]*>\s*EPILOGUE\s*</h2>.*<em>cavaliers</em>.*Colophon.*Loado sea\.}s
    end

    title = title_page(dir, play)

    assert [epilogue, colophon] =
             title
             |> LazyHTML.query("article a[href^='act-1.html#']")
             |> Enum.map(&{LazyHTML.text(&1), LazyHTML.attribute(&1, "href")})

    assert {"EPILOGUE", ["act-1.html#" <> _]} = epilogue
    assert {"Colophon", ["act-1.html#" <> _]} = colophon
    refute LazyHTML.text(title) =~ "Loado sea."
  end
end
