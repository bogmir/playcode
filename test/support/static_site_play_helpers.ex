defmodule Playcode.StaticSitePlayHelpers do
  @moduledoc "What the static site's play tests share: a two-act play and readers of its pages."

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers

  def two_acts do
    """
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
  end

  # Manual: the pages show the snippet's numbers as written, none added at import; `rule`
  # (`:type`, `:restart`) is the play's numbering rule, which the site reads.
  def publish!(body, rule \\ []) do
    play = import_tei!(tei(encoding_desc: manual_numbering(rule), body: body))
    {play, generate!([play], all: true)}
  end

  def page(dir, play, file), do: html!(dir, "plays/#{play.code}/#{file}")
  def ids(html), do: html |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")

  def line_ids(html),
    do: html |> LazyHTML.query("div.l, p.sd, p.pr") |> LazyHTML.attribute("id")

  def next(html),
    do: html |> LazyHTML.query(~s(a[rel="next"])) |> LazyHTML.attribute("href") |> Enum.uniq()

  def links(html), do: html |> LazyHTML.query("main a") |> LazyHTML.attribute("href")
end
