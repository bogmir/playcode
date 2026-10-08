defmodule Playcode.PlayContent.InlineMarkupTest do
  # Text in, parts out: a unit test says it better than a round trip would. The round
  # trips in tei_roundtrip_test.exs prove the same pieces end to end.
  use ExUnit.Case, async: true

  alias Playcode.PlayContent.InlineMarkup

  defp at(offset, position \\ 0), do: %{offset: offset, position: position}

  describe "parts/1" do
    test "a stage is a part of its own, with its type and its run" do
      assert InlineMarkup.parts(~s|<stage type="exit">(Vase)</stage> Allez|) == [
               %{text: "(Vase)", italic: false, stage: %{type: "exit", run: 0}},
               %{text: " Allez", italic: false, stage: nil}
             ]
    end

    test "a stage with no type has a nil type" do
      assert [%{text: "(Vase)", stage: %{type: nil, run: 0}}] =
               InlineMarkup.parts("<stage>(Vase)</stage>")
    end

    test "touching stages are two runs; text between two stages belongs to neither" do
      assert [%{stage: %{run: 0}}, %{stage: %{run: 1}}] =
               InlineMarkup.parts("<stage>a</stage><stage>b</stage>")

      assert [%{stage: %{run: 0}}, %{stage: nil}, %{stage: %{run: 1}}] =
               InlineMarkup.parts("<stage>a</stage> y <stage>b</stage>")
    end

    test "italics inside a stage are italic parts of the same run" do
      assert InlineMarkup.parts("<stage>a <<b>> c</stage>") == [
               %{text: "a ", italic: false, stage: %{type: nil, run: 0}},
               %{text: "b", italic: true, stage: %{type: nil, run: 0}},
               %{text: " c", italic: false, stage: %{type: nil, run: 0}}
             ]
    end

    test "text with no marker has no stage" do
      assert InlineMarkup.parts("Dulce <<sueño>> mío") == [
               %{text: "Dulce ", italic: false, stage: nil},
               %{text: "sueño", italic: true, stage: nil},
               %{text: " mío", italic: false, stage: nil}
             ]
    end

    test "nil has no parts" do
      assert InlineMarkup.parts(nil) == []
    end
  end

  describe "plain/1, spoken/1, staged/1, stage_count/1" do
    @line ~s|Allez <stage type="exit">(Vase.)</stage> adieu, <stage>(bas)</stage> ami.|

    test "plain keeps a stage's words and drops its tags" do
      assert InlineMarkup.plain(@line) == "Allez (Vase.) adieu, (bas) ami."
    end

    test "spoken is the words outside every stage; staged is the stages' words" do
      assert @line |> InlineMarkup.spoken() |> String.split() == ["Allez", "adieu,", "ami."]
      assert InlineMarkup.staged(@line) == "(Vase.) (bas)"
    end

    test "stage_count counts the markers" do
      assert InlineMarkup.stage_count(@line) == 2
      assert InlineMarkup.stage_count("Dulce <<sueño>>") == 0
      assert InlineMarkup.stage_count(nil) == 0
    end

    test "nil is empty text" do
      assert {InlineMarkup.spoken(nil), InlineMarkup.staged(nil)} == {"", ""}
    end
  end

  describe "parts/2, where a note falls around a stage" do
    test "a note inside a stage splits it and goes inside" do
      assert [
               %{text: "(Ap", stage: %{run: 0}},
               %{note: %{offset: 3}, stage: %{run: 0}},
               %{text: "arte)", stage: %{run: 0}}
             ] = InlineMarkup.parts("<stage>(Aparte)</stage>", [at(3)])
    end

    test "a note at the end of a stage follows it, outside" do
      assert [
               %{text: "(Vase)", stage: %{run: 0}},
               %{note: _, stage: nil},
               %{text: " y", stage: nil}
             ] = InlineMarkup.parts("<stage>(Vase)</stage> y", [at(6)])
    end

    test "a note before a stage that opens the text is outside it" do
      assert [%{note: _, stage: nil}, %{text: "(Vase)", stage: %{run: 0}}] =
               InlineMarkup.parts("<stage>(Vase)</stage>", [at(0)])
    end

    test "a note between two pieces of one stage is inside it" do
      # "a " ends where the italic run starts, at offset 2.
      assert [
               %{text: "a ", stage: %{run: 0}},
               %{note: _, stage: %{run: 0}},
               %{text: "b", italic: true, stage: %{run: 0}}
             ] = InlineMarkup.parts("<stage>a <<b>></stage>", [at(2)])
    end

    test "a note past the end goes last, outside" do
      assert [%{text: "x", stage: %{run: 0}}, %{note: _, stage: nil}] =
               InlineMarkup.parts("<stage>x</stage>", [at(9)])
    end
  end

  describe "well_formed?/1" do
    test "accepts text with no stage, and stages that are closed and flat" do
      for text <- [
            nil,
            "",
            "Dulce <<sueño>> mío",
            "<stage>(Vase)</stage> Allez",
            ~s|a <stage type="delivery_">(bas)</stage> b <stage>(c)</stage>|,
            "<stage>a <<b>> c</stage>",
            "<<a>> <stage>b</stage>"
          ] do
        assert InlineMarkup.well_formed?(text), inspect(text)
      end
    end

    test "refuses a stage that is not closed, not opened, nested, or has another attribute" do
      for text <- [
            "<stage>sin cerrar",
            "sin abrir</stage>",
            "<stage>a<stage>b</stage>c</stage>",
            ~s(<stage rend="x">y</stage>),
            ~s(<stage type="">y</stage>),
            ~s(<stage type="a b">y</stage>),
            "<<a <stage>b</stage> c>>"
          ] do
        refute InlineMarkup.well_formed?(text), inspect(text)
      end
    end
  end
end
