defmodule Playcode.Export.StaticSiteCompareTest do
  @moduledoc """
  The site's comparison page (problem 5, step 2): a published play beside its published
  original, `plays/<CODE>/compare.html`, its speeches paired as Playcode's comparison pairs
  them (`Playcode.Alignment`). Built with `generate/1` into a temp directory.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.TestFixtures
  import Playcode.StaticSiteHelpers

  alias Playcode.Catalogue

  defp attribute(page, selector, name),
    do: page |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp count(page, selector), do: page |> LazyHTML.query(selector) |> Enum.count()

  defp correct!(play, xml_id, to) do
    character = Enum.find(Playcode.PlayContent.list_characters(play.id), &(&1.xml_id == xml_id))
    {:ok, _} = Playcode.PlayContent.update_character(character, %{original_xml_id: to})
  end

  test "a published translation beside its published original gets a comparison page" do
    %{original: original, french: french} = split_speech_editions()
    dir = generate!([original, french])
    page = html!(dir, "plays/#{french.code}/compare.html")

    assert attribute(page, "[data-panel='panel-0'] [data-pair]", "data-pair") == ["0", "1", "2"]

    assert attribute(page, "[data-panel='panel-1'] [data-pair]", "data-pair") ==
             ["0", "1", "1", "2"]

    assert texts(page, "[data-panel='panel-0'] .spk") == ["ANTONY", "CLEOPATRA", "ANTONY"]
    refute File.exists?(Path.join(dir, "plays/#{original.code}/compare.html"))
  end

  # Step 3: Antoine corrected to Cleopatra and Cléopâtre to Antony; read through the
  # corrections the French speakers run CLEO, ANT, ANT, CLEO against ANT, CLEO, ANT, so
  # Antoine's first speech goes with Cleopatra's (the rule alone gave 0, 1, 1, 2).
  test "a corrected character pairs its speeches with its correction's" do
    %{original: original, french: french} = split_speech_editions()

    correct!(french, "antoine", "CLEO")
    correct!(french, "cleopatre", "ANT")

    page = [original, french] |> generate!() |> html!("plays/#{french.code}/compare.html")

    assert [first | _] = attribute(page, "[data-panel='panel-1'] [data-pair]", "data-pair")
    assert first == "1"
  end

  # Re-importing the original recreates its characters, with new rows: a correction names
  # the original character by its xml:id, so it still holds.
  test "the original re-imported keeps its translations' corrections" do
    %{original: original, french: french} = split_speech_editions()
    correct!(french, "antoine", "CLEO")
    correct!(french, "cleopatre", "ANT")
    original = original |> export_tei() |> import_tei!()

    page = [original, french] |> generate!() |> html!("plays/#{french.code}/compare.html")

    assert [first | _] = attribute(page, "[data-panel='panel-1'] [data-pair]", "data-pair")
    assert first == "1"
  end

  test "no page when the original is a draft" do
    %{original: original, french: french} = split_speech_editions()
    {:ok, _} = Catalogue.update_play(original, %{is_complete: false})
    dir = generate!([french])

    refute File.exists?(Path.join(dir, "plays/#{french.code}/compare.html"))
  end

  # The proof of concept: an adaptation's speakers do not follow its original's, so it
  # keeps the proportion; the original's speeches still carry their places, for the menu.
  test "an adaptation scrolls by proportion, its original keeping its places" do
    %{original: original, french: french} = split_speech_editions("adaptacion")
    page = [original, french] |> generate!() |> html!("plays/#{french.code}/compare.html")

    assert count(page, "[data-panel='panel-0'] [data-pair]") == 3
    assert count(page, "[data-panel='panel-1'] [data-pair]") == 0
    assert count(page, "[data-panel='panel-1'] [data-sync-act]") == 4
  end

  test "the page runs alone and asks no other site for anything" do
    %{original: original, french: french} = split_speech_editions()
    html = [original, french] |> generate!() |> read!("plays/#{french.code}/compare.html")
    page = LazyHTML.from_document(html)

    # A link elsewhere is not a request (the footer names the Endings principles); what
    # the page loads is.
    refute html =~ ~r/src="(https?:)?\/\//
    refute html =~ ~r/<link[^>]+href="(https?:)?\/\//
    script = page |> LazyHTML.query("script:not([src])") |> LazyHTML.text()

    # A classic script, as a browser runs it: Node would otherwise accept `export`.
    {out, 0} =
      System.cmd("node", [
        "--input-type=commonjs",
        "-e",
        # The head's line picks light or dark from the page's root and the system.
        "globalThis.document = {addEventListener() {}, documentElement: {dataset: {}}};\n" <>
          "globalThis.matchMedia = () => ({matches: false});\n" <>
          script <> "\nconsole.log(matchPair([0, 1, 1, 3], 2), typeof syncPanels)"
      ])

    assert String.trim(out) == "3 function"
  end

  # A speech Hamlet's hidden Folio passages leave without words has no box to scroll to,
  # so it carries neither key, as on Playcode's comparison.
  test "a speech that is all the Folio's is not paired" do
    folio = ~s(<code>&lt;span class="folio"&gt;</code>)
    folio_end = ~s(<code>&lt;/span&gt;</code>)
    f = ~s(<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>)

    body = """
    <div1 type="acto" n="1"><head>ACT I</head>
      <sp><speaker>HAMLET</speaker><l n="1">uno</l></sp>
      <sp><speaker>#{folio}#{f}GUILDENSTERN#{folio_end}</speaker><p n="2">#{folio}Solo el Folio.#{f}#{folio_end}</p></sp>
      <sp><speaker>CLAUDIO</speaker><l n="3">tres</l></sp>
    </div1>
    """

    original = [body: body] |> tei() |> import_tei!()
    translation = [body: body] |> tei() |> import_tei!()
    {:ok, original} = Catalogue.update_play(original, %{is_complete: true})

    {:ok, translation} =
      Catalogue.update_play(translation, %{
        is_complete: true,
        parent_play_id: original.id,
        relationship_type: "traduccion"
      })

    page =
      [original, translation] |> generate!() |> html!("plays/#{translation.code}/compare.html")

    for panel <- ["panel-0", "panel-1"] do
      assert count(page, "[data-panel='#{panel}'] .sp.fo") == 1
      assert count(page, "[data-panel='#{panel}'] .sp.fo[data-sync-act]") == 0
      assert count(page, "[data-panel='#{panel}'] .sp.fo[data-pair]") == 0
      assert count(page, "[data-panel='#{panel}'] .sp[data-sync-act][data-pair]") == 2
    end
  end

  # Both texts number their ids per play: the translation's are its own, so a note's
  # button opens its own play's note and a line's link scrolls its own panel.
  test "each panel's ids are its own" do
    line = fn word ->
      ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">#{word}<note n="1" type="editor"><p>Nota de #{word}.</p></note></l></sp></div1>)
    end

    original = [body: line.("uno"), title: "Uno"] |> tei() |> import_tei!()
    translation = [body: line.("one"), title: "One"] |> tei() |> import_tei!()
    {:ok, original} = Catalogue.update_play(original, %{is_complete: true})

    {:ok, translation} =
      Catalogue.update_play(translation, %{
        is_complete: true,
        parent_play_id: original.id,
        relationship_type: "traduccion"
      })

    page =
      [original, translation] |> generate!() |> html!("plays/#{translation.code}/compare.html")

    ids = attribute(page, "[id]", "id")
    assert ids -- Enum.uniq(ids) == []

    for panel <- ["panel-0", "panel-1"] do
      [target] = attribute(page, "[data-panel='#{panel}'] .nref", "popovertarget")
      assert count(page, "[data-panel='#{panel}'] li[id='#{target}']") == 1
      [href] = attribute(page, "[data-panel='#{panel}'] .l a.n", "href")
      assert count(page, "[data-panel='#{panel}'] #{href}") == 1
    end

    assert page |> LazyHTML.query("[data-panel='panel-1'] li[popover]") |> LazyHTML.text() =~
             "Nota de one."

    assert attribute(page, "[role='doc-endnotes']", "aria-label") |> Enum.uniq() |> length() == 2
  end

  describe "the way in" do
    # Another translation of the split-speech original: published unless told, first in
    # the catalogue's order ("Antonio…" before the French's "Test Play").
    defp spanish(original, attrs \\ %{}) do
      play_fixture(
        Map.merge(
          %{
            "title" => "Antonio y Cleopatra",
            "title_sort" => "Antonio y Cleopatra",
            "parent_play_id" => original.id,
            "relationship_type" => "traduccion",
            "is_complete" => true
          },
          attrs
        )
      )
    end

    defp compare_links(page),
      do: attribute(page, "a.compare", "href")

    test "the original's catalogue line links its first translation's comparison" do
      %{original: original, french: french} = split_speech_editions()
      spanish = spanish(original)
      lonely = play_fixture(%{"is_complete" => true})
      catalogue = [original, french, spanish, lonely] |> generate!() |> html!("index.html")

      assert compare_links(catalogue) == ["plays/#{spanish.code}/compare.html"]
      # Playcode's catalogue icon: named for a screen reader, its title the tooltip.
      assert attribute(catalogue, "a.compare", "aria-label") == ["Compare"]
      assert attribute(catalogue, "a.compare", "title") == ["Compare"]
      assert count(catalogue, "a.compare svg[aria-hidden='true']") == 1
    end

    # A chain: a translation of the Spanish, first in the catalogue's order under the
    # original. Its page is beside the Spanish, so the original's link is not to it.
    test "the original's link skips a translation of a translation" do
      %{original: original, french: french} = split_speech_editions()
      spanish = spanish(original)

      catalan =
        play_fixture(%{
          "title" => "Antoni i Cleòpatra",
          "title_sort" => "Antoni i Cleopatra",
          "parent_play_id" => spanish.id,
          "relationship_type" => "traduccion",
          "is_complete" => true
        })

      dir = generate!([original, french, spanish, catalan])

      assert compare_links(html!(dir, "index.html")) == ["plays/#{spanish.code}/compare.html"]
      assert File.exists?(Path.join(dir, "plays/#{catalan.code}/compare.html"))
    end

    test "a draft translation is never linked" do
      %{original: original, french: french} = split_speech_editions()
      spanish = spanish(original, %{"is_complete" => false})
      dir = generate!([original, french, spanish])

      assert compare_links(html!(dir, "index.html")) == ["plays/#{french.code}/compare.html"]

      assert attribute(
               html!(dir, "plays/#{french.code}/compare.html"),
               "[data-compare-menu] option",
               "value"
             ) ==
               ["../#{french.code}/compare.html"]
    end

    test "the menu lists the original's published translations, the shown one selected" do
      %{original: original, french: french} = split_speech_editions()
      spanish = spanish(original)

      page =
        [original, french, spanish] |> generate!() |> html!("plays/#{french.code}/compare.html")

      links = ["../#{spanish.code}/compare.html", "../#{french.code}/compare.html"]

      assert attribute(page, "[data-compare-menu] option", "value") == links

      assert attribute(page, "[data-compare-menu] option[selected]", "value") == [
               Enum.at(links, 1)
             ]

      # Without a script the menu cannot open a page: the same links, as links.
      assert page |> LazyHTML.query("noscript") |> LazyHTML.text() =~ "Antonio y Cleopatra"
    end
  end

  describe "the switches" do
    test "the comparison offers the site's switches, not the single-column ones" do
      %{original: original, french: french} = split_speech_editions()
      page = [original, french] |> generate!() |> html!("plays/#{french.code}/compare.html")

      assert count(page, "[data-tools] input[data-toggle='sd']") == 1
      assert count(page, "[data-tools] input[data-toggle='vf']") == 1
      assert count(page, "[data-tools] [data-ln-set]") == 3
      # The character select names one cast, and the arrows walk one column.
      assert count(page, "select[data-highlight]") == 0
      assert count(page, "[data-stepper]") == 0
    end

    test "a switch shows when either play has what it switches" do
      plain =
        ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno dos tres</l></sp></div1>)

      varied =
        ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<app n="1"><rdg wit="#B">dos</rdg></app> tres</l></sp></div1>)

      original = [body: plain] |> tei() |> import_tei!()
      translation = [body: varied] |> tei() |> import_tei!()
      {:ok, original} = Catalogue.update_play(original, %{is_complete: true})

      {:ok, translation} =
        Catalogue.update_play(translation, %{
          is_complete: true,
          parent_play_id: original.id,
          relationship_type: "traduccion"
        })

      page =
        [original, translation] |> generate!() |> html!("plays/#{translation.code}/compare.html")

      assert count(page, "[data-tools] input[data-toggle='va']") == 1
    end
  end

  describe "kept current" do
    alias Playcode.Export.StaticSite

    test "an edited original reaches its translation's comparison" do
      %{original: original, french: french} = split_speech_editions()
      dir = generate!([original, french])

      {:ok, act} =
        Playcode.PlayContent.create_division(%{
          play_id: original.id,
          type: "act",
          number: 2,
          title: "ACT II",
          position: 9
        })

      {:ok, _} =
        Playcode.PlayContent.create_element(%{
          play_id: original.id,
          division_id: act.id,
          type: "stage_direction",
          content: "Enter a messenger, late.",
          position: 1
        })

      {:ok, _} = StaticSite.apply_changes([{:add, original.id}], output_dir: dir)

      assert read!(dir, "plays/#{french.code}/compare.html") =~ "Enter a messenger, late."
    end

    # The original turned draft, its old pages not yet taken off: a translation written
    # meanwhile must not print the draft, which is the database's text, not the site's.
    test "a draft original's text never reaches the comparison" do
      %{original: original, french: french} = split_speech_editions()
      dir = generate!([original, french])
      {:ok, _} = Catalogue.update_play(original, %{is_complete: false})
      {:ok, _} = StaticSite.apply_changes([{:add, french.id}], output_dir: dir)

      refute File.exists?(Path.join(dir, "plays/#{french.code}/compare.html"))
    end

    test "a translation taken off the site leaves no link to it" do
      %{original: original, french: french} = split_speech_editions()

      spanish =
        play_fixture(%{
          "title" => "Antonio y Cleopatra",
          "title_sort" => "Antonio y Cleopatra",
          "parent_play_id" => original.id,
          "relationship_type" => "traduccion",
          "is_complete" => true
        })

      dir = generate!([original, french, spanish])
      {:ok, _} = Catalogue.update_play(spanish, %{is_complete: false})
      {:ok, _} = StaticSite.apply_changes([{:remove, spanish.code}], output_dir: dir)

      refute read!(dir, "plays/#{french.code}/compare.html") =~ spanish.code

      assert attribute(html!(dir, "index.html"), "a.compare", "href") == [
               "plays/#{french.code}/compare.html"
             ]
    end
  end

  describe "names and footers" do
    alias Playcode.Export.StaticSite

    # A version often keeps its original's title, and two translations into one language
    # can share theirs: each panel is named by its part, each option by its language, and
    # by its code too where two would read alike.
    test "plays with one title are told apart" do
      %{original: original, french: french} = split_speech_editions()

      twin = fn ->
        play_fixture(%{
          "title" => "Antonio y Cleopatra",
          "title_sort" => "Antonio y Cleopatra",
          "language" => "es",
          "parent_play_id" => original.id,
          "relationship_type" => "traduccion",
          "is_complete" => true
        })
      end

      [a, b] = [twin.(), twin.()]

      untold =
        play_fixture(%{
          "title" => "Sin lengua",
          "title_sort" => "Sin lengua",
          "language" => nil,
          "parent_play_id" => original.id,
          "relationship_type" => "version",
          "is_complete" => true
        })

      page =
        [original, french, a, b, untold]
        |> generate!()
        |> html!("plays/#{french.code}/compare.html")

      assert attribute(page, "[data-panel]", "aria-label") ==
               ["Original: Test Play", "Translation: Test Play"]

      assert page |> texts("[data-compare-menu] option") |> Enum.sort() ==
               Enum.sort([
                 "Antonio y Cleopatra (Spanish) — #{a.code}",
                 "Antonio y Cleopatra (Spanish) — #{b.code}",
                 "Sin lengua",
                 "Test Play (Spanish)"
               ])
    end

    test "an original taken off the site takes its comparisons with it" do
      %{original: original, french: french} = split_speech_editions()
      dir = generate!([original, french])
      {:ok, _} = Catalogue.update_play(original, %{is_complete: false})
      {:ok, _} = StaticSite.apply_changes([{:remove, original.code}], output_dir: dir)

      assert File.exists?(Path.join(dir, "plays/#{french.code}/index.html"))
      refute File.exists?(Path.join(dir, "plays/#{french.code}/compare.html"))
      assert attribute(html!(dir, "index.html"), "a.compare", "href") == []
    end

    test "the build reports its largest comparison page" do
      %{original: original, french: french} = split_speech_editions()
      dir = site_dir!()
      codes = [original.code, french.code]

      assert {:ok, %{largest_compare_gzip: size}} =
               StaticSite.generate(output_dir: dir, play_codes: codes)

      assert size > 0

      assert {:ok, %{largest_compare_gzip: 0}} =
               StaticSite.generate(output_dir: site_dir!(), play_codes: [original.code])
    end

    # Both texts are on the page, so both licences are: once when they are one.
    test "the footer states both plays' licences" do
      %{original: original, french: french} = split_speech_editions()

      {:ok, original} =
        Catalogue.update_play(original, %{licence_text: "Licence of the original"})

      {:ok, french} = Catalogue.update_play(french, %{licence_text: "Licence of the translation"})
      dir = generate!([original, french])
      footer = fn -> dir |> html!("plays/#{french.code}/compare.html") |> texts("footer p") end

      assert "Licence of the original" in footer.()
      assert "Licence of the translation" in footer.()

      {:ok, french} = Catalogue.update_play(french, %{licence_text: "Licence of the original"})
      {:ok, _} = StaticSite.apply_changes([{:add, french.id}], output_dir: dir)

      assert Enum.count(footer.(), &(&1 == "Licence of the original")) == 1
    end
  end
end
