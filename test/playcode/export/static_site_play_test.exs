defmodule Playcode.Export.StaticSitePlayTest do
  @moduledoc "A play's reading pages in the static site: one per act, the full text, statistics."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers
  import Playcode.TestFixtures

  @two_acts """
  <div1 type="jornada" n="1"><head>Jornada I</head>
    <stage>Salen músicos cantando</stage>
    <sp><speaker>Segismundo</speaker>
      <lg type="redondilla">
        <l n="1">¡Válgame el cielo!, ¿qué veo?</l>
        <l n="2">Dulce <emph>sueño</emph> mío</l>
        <l n="3">uno &amp; &lt;script&gt;alert(1)&lt;/script&gt;</l>
        <l n="4">con mucha duda lo creo.</l>
      </lg>
      <lg type="redondilla"><l n="5">¿Yo en palacios suntuosos?</l></lg>
    </sp>
    <sp><speaker>Clarín</speaker><lg type="free" part="I"><l n="6" part="I">A mí.</l></lg></sp>
    <sp><speaker>Criado 2</speaker><lg type="free" part="F"><l part="F">Llega a hablarle ya.</l></lg></sp>
  </div1>
  <div1 type="jornada" n="2"><head>Jornada II</head>
    <sp><speaker>Clotaldo</speaker><p>Señor, despierta.</p></sp>
  </div1>
  """

  defp publish!(body) do
    play = import_tei!(tei(body: body))
    {play, generate!([play], all: true)}
  end

  defp page(dir, play, file), do: html!(dir, "plays/#{play.code}/#{file}")
  defp ids(html), do: html |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")

  # Regression: WordParser puts a stanza straight under the division when {m} opens
  # with no speaker; its verses used to get no item, no anchor, and the build raised.
  test "a Word-imported stanza with no speaker is published, and counted" do
    play = play_fixture(%{"is_complete" => true})

    assert {:ok, _} =
             Playcode.Import.WordParser.import_content(
               play.id,
               docx(["{e}Escena 1", "{m}", "{v}uno", "{v}dos"])
             )

    dir = generate!([play], all: true)
    act = Path.wildcard(Path.join([dir, "plays", play.code, "act-*.html"])) |> hd()
    html = LazyHTML.from_document(File.read!(act))

    assert texts(html, "#l1") |> Enum.join() =~ "uno"
    assert Playcode.Statistics.get_statistics(play.id).data["verses"] == 2
  end

  test "each act has its own page, linked to the acts before and after it" do
    {play, dir} = publish!(@two_acts)
    first = page(dir, play, "act-1.html")
    second = page(dir, play, "act-2.html")

    assert first |> LazyHTML.query(~s(a[rel="next"])) |> LazyHTML.attribute("href") |> Enum.uniq() ==
             ["act-2.html"]

    assert second
           |> LazyHTML.query(~s(a[rel="prev"]))
           |> LazyHTML.attribute("href")
           |> Enum.uniq() == ["act-1.html"]

    assert LazyHTML.text(first) =~ "Salen músicos cantando"
    refute LazyHTML.text(first) =~ "Señor, despierta."
    assert LazyHTML.text(second) =~ "Señor, despierta."
  end

  test "a verse is anchored by its number and keeps its italics, escaped" do
    {play, dir} = publish!(@two_acts)
    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query("#l2 em") |> LazyHTML.text() == "sueño"
    assert act |> LazyHTML.query("#l2") |> LazyHTML.text() =~ "Dulce sueño mío"
    refute read!(dir, "plays/#{play.code}/act-1.html") =~ "&lt;&lt;"
    assert act |> LazyHTML.query("#l3") |> LazyHTML.text() =~ "uno & <script>alert(1)</script>"

    assert act |> LazyHTML.query("script") |> LazyHTML.attribute("src") == [
             "../../assets/site.js"
           ]

    assert act |> LazyHTML.query("#l3 script") |> Enum.empty?()
    assert read!(dir, "plays/#{play.code}/act-1.html") =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "the second half of a split verse starts where the first half ended" do
    {play, dir} = publish!(@two_acts)

    assert texts(page(dir, play, "act-1.html"), ~s([aria-hidden="true"])) == ["A mí."]
  end

  test "a verse form is named once, where its passage starts" do
    {play, dir} = publish!(@two_acts)
    text = LazyHTML.text(page(dir, play, "act-1.html"))

    assert length(String.split(text, "Redondilla")) == 2
  end

  test "the full text carries every act on one page" do
    {play, dir} = publish!(@two_acts)
    full = page(dir, play, "text.html")

    assert Enum.filter(texts(full, "h2"), &String.starts_with?(&1, "Jornada")) == [
             "Jornada I",
             "Jornada II"
           ]

    assert LazyHTML.text(full) =~ "Señor, despierta."
  end

  test "a play that numbers each scene from 1 still gives every line its own anchor" do
    {play, dir} =
      publish!("""
      <div1 type="act" n="1"><head>Act I</head>
        <div2 type="scene" n="1"><head>Scene 1</head><sp><speaker>A</speaker><l n="1">one</l><l n="2">two</l></sp></div2>
        <div2 type="scene" n="2"><head>Scene 2</head><sp><speaker>B</speaker><l n="1">uno</l><l n="2">dos</l></sp></div2>
      </div1>
      """)

    anchors = ids(page(dir, play, "text.html"))

    assert anchors == Enum.uniq(anchors)
    assert "l1-2-1" in anchors
  end

  test "a play with no acts has no act pages; its prologue gets one named after it" do
    {play, dir} =
      publish!(
        ~s(<div1 type="prologue"><head>Prologue</head><sp><speaker>A</speaker><l n="1">one</l></sp></div1>)
      )

    assert File.exists?(Path.join([dir, "plays", play.code, "text.html"]))
    assert File.exists?(Path.join([dir, "plays", play.code, "prologue.html"]))
    refute File.exists?(Path.join([dir, "plays", play.code, "act-1.html"]))
  end

  describe "the statistics page" do
    test "shows the metrical synopsis, the characters and who shares the stage" do
      {play, dir} = publish!(@two_acts)
      stats = page(dir, play, "statistics.html")

      assert rows(stats, "#synopsis tbody tr") == [
               ["I", "Redondilla", "1–5", "5"],
               ["I", "Unmarked", "6", "1"]
             ]

      characters = rows(stats, "#characters tbody tr")
      assert Enum.map(characters, &hd/1) == ["Segismundo", "Criado 2", "Clarín", "Clotaldo"]
      assert ["Segismundo", "1", "5" | _] = hd(characters)
      assert "I, 1" in hd(characters)

      assert texts(stats, "#presence tbody th") == [
               "Segismundo",
               "Criado 2",
               "Clarín",
               "Clotaldo"
             ]

      assert stats |> LazyHTML.query("#presence td[title]") |> Enum.count() == 3
      assert LazyHTML.text(stats) =~ "metrical passages"

      # A filled cell states its line count in text, not only in a tooltip.
      assert stats
             |> LazyHTML.query("#presence td[title]")
             |> Enum.map(&squish(LazyHTML.text(&1)))
             |> Enum.sort() ==
               ["1 line", "1 line", "5 lines"]
    end

    test "a play in prose has no synopsis and measures its characters in words" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>ANA</speaker><p>Buenos días, señor.</p></sp>
          <sp><speaker>JUAN</speaker><p>Hola.</p></sp>
        </div1>
        """)

      stats = page(dir, play, "statistics.html")

      assert stats |> LazyHTML.query("#synopsis") |> Enum.empty?()

      assert [["ANA", "1", "0", "3" | _], ["JUAN", "1", "0", "1" | _]] =
               rows(stats, "#characters tbody tr")

      assert LazyHTML.text(stats) =~ "most words"
      refute "verses" in texts(stats, "#tiles dt")
    end
  end

  test "reading tools ship hidden, ready for JS, with the cast to highlight" do
    %{play: play} = play_with_structure_fixture()
    act = html!(generate!([play], all: true), "plays/#{play.code}/act-1.html")

    assert act |> LazyHTML.query("[data-tools][hidden]") |> Enum.count() == 1

    assert act |> LazyHTML.query("[data-highlight] option") |> LazyHTML.attribute("value") ==
             ["", "ALFA"]

    assert act |> LazyHTML.query("body") |> LazyHTML.attribute("data-ln") == ["5"]

    assert act |> LazyHTML.query("[data-cite]") |> LazyHTML.attribute("data-cite") ==
             ["Tester, Structured Play, ACT I"]
  end
end
