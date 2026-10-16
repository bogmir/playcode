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

    test "refuses an empty stage, which has no words to show" do
      refute InlineMarkup.well_formed?("<stage></stage>x")
      refute InlineMarkup.well_formed?(~s|<stage type="exit"></stage>|)
    end
  end

  describe "line numbers and breaks" do
    test "a number is a part of its own, with no text, where its marker stood" do
      assert InlineMarkup.parts(~s(thanks, <lb n="1320"/>but)) == [
               %{text: "thanks, ", italic: false, stage: nil},
               %{number: "1320", text: "", italic: false, stage: nil},
               %{text: "but", italic: false, stage: nil}
             ]
    end

    test "a number inside italics or a stage belongs to them" do
      assert [_, %{number: "5", italic: true}, _] = InlineMarkup.parts(~s(<<a <lb n="5"/>b>>))

      assert [_, %{number: "6", stage: %{run: 0}}, _] =
               InlineMarkup.parts(~s(<stage>a <lb n="6"/>b</stage>))
    end

    # The marker's "/>" runs into the italics' closing ">>": the closing must not be read
    # from inside the marker, or the tag shows as text.
    test "a number that ends an italic run stays a number inside it" do
      assert InlineMarkup.parts(~s(<<sic <lb n="5"/>>>tail)) == [
               %{text: "sic ", italic: true, stage: nil},
               %{number: "5", text: "", italic: true, stage: nil},
               %{text: "tail", italic: false, stage: nil}
             ]
    end

    test "plain drops the marker and keeps a line break" do
      assert InlineMarkup.plain(~s(<lb n="1319"/>Beggar, <lb n="1320"/>but\nthanks)) ==
               "Beggar, but\nthanks"
    end

    test "a note placed around a number keeps the number" do
      assert [%{text: "a "}, %{note: _}, %{number: "2"}, %{text: "b"}] =
               InlineMarkup.parts(~s(a <lb n="2"/>b), [at(2)])
    end

    test "a paragraph's number is the marker at its very start" do
      assert InlineMarkup.paragraph_number(~s(<lb n="1319"/>Beggar <lb n="1320"/>but)) ==
               {"1319", ~s(Beggar <lb n="1320"/>but)}

      assert InlineMarkup.paragraph_number(~s(Beggar <lb n="1320"/>but)) ==
               {nil, ~s(Beggar <lb n="1320"/>but)}

      assert InlineMarkup.paragraph_number(nil) == {nil, nil}
    end

    test "the marker is built as the importer stores it" do
      assert InlineMarkup.number_marker("1311-2") == ~s(<lb n="1311-2"/>)
    end

    test "numbers_well_formed? accepts numbers and refuses any other <lb" do
      assert InlineMarkup.numbers_well_formed?(nil)
      assert InlineMarkup.numbers_well_formed?("no marker\nat all")
      assert InlineMarkup.numbers_well_formed?(~s(a <lb n="1311-2"/>b <lb n="3610.01"/>c))
      refute InlineMarkup.numbers_well_formed?("a <lb/>b")
      refute InlineMarkup.numbers_well_formed?(~s(a <lb n="1 2"/>b))
      refute InlineMarkup.numbers_well_formed?(~s(a <lb n="12">b))
    end
  end

  describe "a Folio passage" do
    test "is a run of parts of its own, with its part; the text around it has none" do
      assert [%{text: "O God, "} = before, %{text: "O", folio: %{part: nil, run: 0}}, following] =
               InlineMarkup.parts("O God, <folio>O</folio> God,")

      refute Map.has_key?(before, :folio)
      assert %{text: " God,"} = following
      refute Map.has_key?(following, :folio)

      assert [%{text: "unto", folio: %{part: "I", run: 0}}] =
               InlineMarkup.parts(~s(<folio part="I">unto</folio>))
    end

    test "holds italics, stages and printed lines' numbers" do
      assert [
               %{text: "Within", stage: %{type: "delivery"}, folio: %{part: "F", run: 0}},
               %{text: "Mother", italic: true, folio: %{run: 0}},
               %{number: "12", folio: %{run: 0}}
             ] =
               InlineMarkup.parts(
                 ~s(<folio part="F"><stage type="delivery">Within</stage><<Mother>><lb n="12"/></folio>)
               )
    end

    test "a stage inside it and one outside are two runs" do
      assert [%{stage: %{run: 0}}, %{stage: %{run: 1}, folio: %{run: 0}}] =
               InlineMarkup.parts("<stage>a</stage><folio><stage>b</stage></folio>")
    end

    test "a note inside it goes with it; one at either edge stays outside" do
      notes = for offset <- [7, 8, 10], do: %{id: offset, offset: offset, position: 0}
      placed = InlineMarkup.parts("O God, <folio>O O</folio> God,", notes)

      folio_of = fn id ->
        placed |> Enum.find(&match?(%{note: %{id: ^id}}, &1)) |> Map.get(:folio)
      end

      assert folio_of.(7) == nil
      assert %{run: 0} = folio_of.(8)
      assert folio_of.(10) == nil
    end

    test "a note between two pieces of one passage goes with it" do
      notes = [%{id: 1, offset: 2, position: 0}]

      assert [
               %{text: "a ", folio: %{run: 0}},
               %{note: %{id: 1}, folio: %{run: 0}},
               %{text: "b", italic: true, folio: %{run: 0}},
               %{text: " c", folio: %{run: 0}}
             ] = InlineMarkup.parts("<folio>a <<b>> c</folio>", notes)
    end

    test "folio_labels/1 marks where a passage starts and ends, not a part's inner edge" do
      labelled = fn text ->
        text
        |> InlineMarkup.parts()
        |> InlineMarkup.folio_labels()
        |> Enum.map_join(fn
          %{label: label} -> "[#{label}]"
          %{text: text} -> text
        end)
      end

      assert labelled.("O God, <folio>O</folio> God,") == "O God, [F]O[F] God,"
      assert labelled.(~s(her. <folio part="I">She kneels</folio>)) == "her. [F]She kneels"
      assert labelled.(~s(<folio part="M">Prison, my lord?</folio>)) == "Prison, my lord?"
      assert labelled.(~s(<folio part="F">him.</folio> He takes)) == "him.[F] He takes"
      assert labelled.("<folio>a</folio><folio>b</folio>") == "[F]a[F][F]b[F]"
    end

    test "folio_labels/1 keeps its labels at a passage's two ends when a note sits inside it" do
      notes = [%{id: 1, offset: 3, position: 0}]

      assert "a <folio>O O</folio> b"
             |> InlineMarkup.parts(notes)
             |> InlineMarkup.folio_labels()
             |> Enum.map(fn
               %{label: label} -> label
               %{note: %{id: id}} -> {:note, id}
               %{text: text} -> text
             end) == ["a ", "F", "O", {:note, 1}, " O", "F", " b"]
    end

    test "plain and spoken keep its words and drop its tags" do
      text = "Very like<folio>, very like</folio>. Stayed it long?"
      assert InlineMarkup.plain(text) == "Very like, very like. Stayed it long?"
      assert InlineMarkup.spoken(text) == "Very like, very like. Stayed it long?"
    end

    test "whole_folio?/1: every word in a passage, a paragraph's own number aside" do
      assert InlineMarkup.whole_folio?(~s(<folio part="M">Prison, my lord?</folio>))
      assert InlineMarkup.whole_folio?(~s(<lb n="1288"/><folio part="M">Prison?</folio>))
      assert InlineMarkup.whole_folio?("<folio>For he himself is subject to his birth:</folio>")
      refute InlineMarkup.whole_folio?("O God, <folio>O</folio> God,")
      refute InlineMarkup.whole_folio?("no passage")
      refute InlineMarkup.whole_folio?("<folio> </folio>")
      refute InlineMarkup.whole_folio?(nil)
    end
  end

  describe "junk text" do
    # A researcher can paste anything into the editor: a run of stages that never close
    # must cost time in proportion to its length, not its square (32 KB took 1.7 s).
    test "a long run of unclosed stages is read in well under a second" do
      junk = String.duplicate("<stage>a", 5_000)

      for {name, fun} <- [
            well_formed?: &InlineMarkup.well_formed?/1,
            parts: &InlineMarkup.parts/1,
            stage_count: &InlineMarkup.stage_count/1
          ] do
        {microseconds, _} = :timer.tc(fn -> fun.(junk) end)
        assert microseconds < 500_000, "#{name} took #{div(microseconds, 1000)} ms"
      end

      refute InlineMarkup.well_formed?(junk)
    end

    test "a very long stage is still one stage" do
      words = String.duplicate("a ", 100_000)

      assert [%{text: ^words, stage: %{run: 0}}] = InlineMarkup.parts("<stage>#{words}</stage>")
      assert InlineMarkup.stage_count("<stage>#{words}</stage>") == 1
      assert InlineMarkup.well_formed?("<stage>#{words}</stage>")
    end
  end
end
