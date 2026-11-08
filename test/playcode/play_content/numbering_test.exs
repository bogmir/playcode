defmodule Playcode.PlayContent.NumberingTest do
  @moduledoc """
  The numbering rule a play follows, counted on every save (`PlayContent.refresh_derived/1`)
  and read back from the play's TEI export: each type and restart of the spec,
  `docs/superpowers/specs/2026-11-08-numbering-setting-design.md`.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.{Catalogue, PlayContent}
  alias Playcode.PlayContent.Numbering

  defp numbered(body, type, restart, manual \\ false) do
    play = import_tei!(tei(body: body))

    {:ok, play} =
      Catalogue.update_play(play, %{
        numbering_type: type,
        numbering_restart: restart,
        numbering_manual: manual
      })

    PlayContent.refresh_derived(play.id)
    play
  end

  defp numbers(play, tag), do: for({attrs, _} <- xml_lines(export_tei(play), tag), do: attrs["n"])

  defp act(content), do: ~s(<div1 type="acto" n="1"><head>Acto I</head>#{content}</div1>)

  # An empty paragraph holds no text to number lines in; it takes its own number.
  test "VL: an empty paragraph takes a number and does not stop the count" do
    play =
      numbered(
        act(~s(<sp><speaker>ANA</speaker><p>Uno</p><p></p><p>Tres</p></sp>)),
        "VL",
        "never"
      )

    assert numbers(play, "p") == ["1", "2", "3"]
  end

  test "V never: a split verse takes one number, on its first piece; prose none" do
    play =
      numbered(
        act("""
        <sp><speaker>ANA</speaker><l>Uno</l><l part="I">Dos</l></sp>
        <sp><speaker>BLAS</speaker><l part="F">y dos</l><l>Tres</l><p n="9">Prosa.</p></sp>
        """),
        "V",
        "never"
      )

    assert numbers(play, "l") == ["1", "2", nil, "3"]
    assert numbers(play, "p") == [nil]
  end

  test "V per scene: each scene starts at 1" do
    play =
      numbered(
        act("""
        <div2 type="escena" n="1"><head>Escena I</head>
          <sp><speaker>ANA</speaker><l>Uno</l><l>Dos</l></sp></div2>
        <div2 type="escena" n="2"><head>Escena II</head>
          <sp><speaker>ANA</speaker><l>Tres</l></sp></div2>
        """),
        "V",
        "scene"
      )

    assert numbers(play, "l") == ["1", "2", "1"]
  end

  # The researcher: a prologue or epilogue starts again "like a scene" (Q21).
  @prologue """
  <div1 type="prologo"><head>Prólogo</head>
    <sp><speaker>ANA</speaker><l>P uno</l><l>P dos</l></sp></div1>
  <div1 type="acto" n="1"><head>Acto I</head>
    <sp><speaker>ANA</speaker><l>A uno</l></sp>
    <div2 type="escena" n="1"><head>Escena I</head>
      <sp><speaker>ANA</speaker><l>E uno</l><l>E dos</l></sp></div2>
  </div1>
  """

  test "prologue: never continues, per act restarts at each div1, per scene at every division" do
    assert numbers(numbered(@prologue, "V", "never"), "l") == ["1", "2", "3", "4", "5"]
    assert numbers(numbered(@prologue, "V", "act"), "l") == ["1", "2", "1", "2", "3"]
    assert numbers(numbered(@prologue, "V", "scene"), "l") == ["1", "2", "1", "1", "2"]
  end

  test "VP never: a paragraph between verses takes the next number" do
    play =
      numbered(
        act("""
        <sp><speaker>ANA</speaker><l>Uno</l><l>Dos</l></sp>
        <sp><speaker>BLAS</speaker><p>Prosa.</p></sp>
        <sp><speaker>ANA</speaker><l>Cuatro</l></sp>
        """),
        "VP",
        "never"
      )

    assert numbers(play, "l") == ["1", "2", "4"]
    assert numbers(play, "p") == ["3"]
  end

  test ~s(VL: a paragraph's printed lines take a number each, a typed <lb n="0"/> included) do
    play =
      numbered(
        act("""
        <sp><speaker>ANA</speaker><l>Uno</l></sp>
        <sp><speaker>BLAS</speaker><p>Primera <lb n="0"/>segunda <lb n="7"/>tercera</p></sp>
        <sp><speaker>ANA</speaker><l>Cinco</l></sp>
        """),
        "VL",
        "never"
      )

    assert numbers(play, "l") == ["1", "5"]
    assert [{%{"n" => "2"}, "Primera [3] segunda [4] tercera"}] = xml_lines(export_tei(play), "p")
  end

  test "S: one number per speech, on its first line or paragraph" do
    play =
      numbered(
        act("""
        <sp><speaker>ANA</speaker><l>a</l><l>b</l><l part="I">c</l></sp>
        <sp><speaker>BLAS</speaker><l part="F">y c</l><p>Prosa.</p></sp>
        <sp><speaker>ANA</speaker><stage>Se va.</stage></sp>
        <sp><speaker>BLAS</speaker><p>Otra.</p></sp>
        <sp><speaker>ANA</speaker><l>e</l></sp>
        """),
        "S",
        "never"
      )

    assert numbers(play, "l") == ["1", nil, nil, "2", "4"]
    assert numbers(play, "p") == [nil, "3"]
  end

  test "a Manual play is never recounted" do
    play =
      numbered(
        act(~s(<sp><speaker>ANA</speaker><l n="5">Uno</l><l n="9">Dos</l></sp>)),
        "V",
        "never",
        true
      )

    assert numbers(play, "l") == ["5", "9"]
    assert Numbering.recount(Catalogue.get_play!(play.id)) == 0
  end

  test "a recount writes only the rows whose number changed" do
    play =
      numbered(
        act(~s(<sp><speaker>ANA</speaker><l>Uno</l><l>Dos</l><l>Tres</l></sp>)),
        "V",
        "never"
      )

    assert numbers(play, "l") == ["1", "2", "3"]
    assert Numbering.recount(Catalogue.get_play!(play.id)) == 0
  end
end
