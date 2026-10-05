defmodule Playcode.Export.StaticSiteTest do
  @moduledoc """
  The published site as a whole: which plays it publishes, where each file goes, and
  each play's title page. Generated with `StaticSite.generate/1` into a temp
  directory and read back as the files a visitor gets.
  """
  use Playcode.DataCase, async: true

  import Playcode.TestFixtures
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

  test "an original's title page links its published translations, and only those" do
    %{original: original, translation: translation} = translation_family_fixture()

    unpublished =
      play_fixture(%{"parent_play_id" => original.id, "relationship_type" => "traduccion"})

    page = title_page(generate!([original, translation]), original)

    assert "../#{translation.code}/index.html" in hrefs(page)
    refute "../#{unpublished.code}/index.html" in hrefs(page)
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

  test "a generated site reports its largest page and its index sizes" do
    %{play: play} = play_with_structure_fixture()
    dir = Path.join(System.tmp_dir!(), "site-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:ok, %{largest_page_gzip: page, index_bytes: index, largest_shard_bytes: shard}} =
             StaticSite.generate(output_dir: dir, play_codes: [play.code], all: true)

    assert page > 0 and index > 0 and shard > 0
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
end
