defmodule Playcode.Export.StaticSiteCompareTest do
  @moduledoc """
  The site's comparison page (problem 5, step 2): a published play beside its published
  original, `plays/<CODE>/compare.html`, its speeches paired as Playcode's comparison pairs
  them (`Playcode.Alignment`). Built with `generate/1` into a temp directory.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers

  alias Playcode.Catalogue

  defp attribute(page, selector, name),
    do: page |> LazyHTML.query(selector) |> LazyHTML.attribute(name)

  defp count(page, selector), do: page |> LazyHTML.query(selector) |> Enum.count()

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
        "globalThis.document = {addEventListener() {}};\n" <>
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
end
