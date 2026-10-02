defmodule Playcode.Export.StaticSitePlayTest do
  @moduledoc "A play's reading pages in the static site: one per act, the full text, statistics."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers

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
end
