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

  test "the HEEx annotations dev compiles in never reach the archive" do
    # config/dev.exs turns them on; the test env cannot, so the function is tested directly.
    html =
      ~s[<!-- <Playcode.X.y> lib/x.ex:3 (playcode) --><p data-phx-loc="12">Hi</p>] <>
        ~s[<!-- </Playcode.X.y> --><!-- @caller lib/y.ex:9 (playcode) -->]

    assert Pages.strip_annotations(html) == "<p>Hi</p>"
  end
end
