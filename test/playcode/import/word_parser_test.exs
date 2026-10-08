defmodule Playcode.Import.WordParserTest do
  @moduledoc """
  The "premarcado" Word importer, driven the way the play detail page drives it:
  `WordParser.import_content/2` on a .docx, then read back as the play's TEI.
  Each paragraph of the document is one string in these tests. The upload
  itself, and the text the export does not carry, are asserted in
  test/playcode_web/live/admin/play_detail_live_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.TestFixtures

  alias Playcode.Import.WordParser

  defp import_word(paragraphs, play \\ play_fixture()) do
    assert {:ok, _} = WordParser.import_content(play.id, docx(paragraphs))
    export_tei(play)
  end

  defp speeches(xml) do
    xml
    |> xml_elements("sp")
    |> Enum.map(fn {_attrs, text} -> text end)
  end

  describe "a file that is not a premarcado document" do
    test "is refused, whether missing or not a .docx" do
      play = play_fixture()

      assert {:error, _} = WordParser.import_content(play.id, "/nonexistent/file.docx")
      assert {:error, _} = WordParser.import_content(play.id, write_tmp!("not a zip", ".docx"))
    end
  end

  describe "the tags" do
    test "speaker, verse, prose and stage direction, in any case" do
      xml =
        import_word([
          "{e}Escena 1",
          "{ac}Sale el Rey.",
          "{p}FEBO  {v}Será remedio casarte.",
          "{v}pon a esta puerta el oído.",
          "{P}JOHN {PR} To be or not to be.",
          "{p}DUKE {ac}Aparte. {v}My lord.",
          "{AC}Vanse."
        ])

      assert xml_texts(xml, "speaker") == ["FEBO", "JOHN", "DUKE"]

      assert xml_texts(xml, "l") == [
               "Será remedio casarte.",
               "pon a esta puerta el oído.",
               "My lord."
             ]

      assert xml_texts(xml, "p", within: "sp") == ["To be or not to be."]
      assert xml_texts(xml, "stage") == ["Sale el Rey.", "Aparte.", "Vanse."]
      assert xml_texts(xml, "stage", within: "sp") == ["Aparte."]
    end

    test "a verse split between speakers keeps its parts" do
      xml =
        import_word([
          "{e}Escena 1",
          "{p}DUQUE  {ti}¿Cantan?",
          "{p}RICARDO  {tm}¿No lo ves?",
          "{p}DUQUE  {tf}¿Pues quién"
        ])

      assert Enum.map(xml_elements(xml, "l"), fn {attrs, _} -> attrs["part"] end) ==
               ["I", "M", "F"]
    end

    # {m} used to create an empty line group and then drop every verse after it.
    test "{m} opens a new stanza that holds the verses after it" do
      xml =
        import_word([
          "{e}Escena 1",
          "{p}FEBO  {v}uno",
          "{v}dos",
          "{m}",
          "{v}tres",
          "{v}cuatro",
          "{p}ANA  {v}cinco",
          "{m}",
          "{v}seis"
        ])

      assert xml_texts(xml, "l") == ~w(uno dos tres cuatro cinco seis)
      assert xml_texts(xml, "lg") == ["tres cuatro", "seis"]
      assert speeches(xml) == ["FEBO uno dos tres cuatro", "ANA cinco seis"]
    end

    test "{m} with no speaker open still keeps its verses" do
      xml = import_word(["{e}Escena 1", "{m}", "{v}sin hablante", "{v}todavía"])

      assert xml_texts(xml, "l", within: "lg") == ["sin hablante", "todavía"]
    end

    # {ap} used to be parsed and then ignored.
    test "{ap} marks that paragraph's verse or prose as an aside" do
      xml =
        import_word([
          "{e}Escena 1",
          "{p}ANA {ap} {pr} aparte en prosa",
          "{p}REY  {v}en voz alta",
          "{ap} {v}aparte en verso"
        ])

      assert xml_texts(xml, "seg") == ["aparte en prosa", "aparte en verso"]
      assert Enum.all?(xml_elements(xml, "seg"), &match?({%{"type" => "aside"}, _}, &1))
      assert "en voz alta" in xml_texts(xml, "l")
    end

    test "verse lines are numbered in order" do
      xml = import_word(["{e}Escena 1", "{p}FEBO  {v}Uno.", "{v}Dos.", "{p}ANA {v}Tres."])

      numbers =
        Enum.map(xml_elements(xml, "l"), fn {attrs, _} -> String.to_integer(attrs["n"]) end)

      assert numbers == [1, 2, 3]
    end
  end

  describe "the speakers" do
    test "each new {p} opens a new speech, and each speaker becomes a character" do
      xml = import_word(["{e}Escena 1", "{p}FEBO  {v}Hello.", "{p}RICARDO  {v}Goodbye."])

      assert speeches(xml) == ["FEBO Hello.", "RICARDO Goodbye."]
      assert xml_texts(xml, "role") == ["FEBO", "RICARDO"]

      ids = Map.new(xml_elements(xml, "role"), fn {attrs, name} -> {name, attrs["xml:id"]} end)

      assert Enum.map(xml_elements(xml, "sp"), fn {attrs, _} -> attrs["who"] end) ==
               ["##{ids["FEBO"]}", "##{ids["RICARDO"]}"]
    end

    # A character's xml:id is what every <sp who> cites. It keeps the name's letters
    # without their accents and puts a leading number last, as the corpus's editors do
    # ("1º Senatore" is senatore_1): an XML id may not start with a digit. A name with
    # neither letter nor digit gets a numbered id; an empty one stopped the import.
    test "a speaker's id keeps its letters, puts a number last, and is never empty" do
      xml =
        import_word([
          "{e}Escena 1",
          "{p}ABSALÓN  {v}Uno.",
          "{p}Alcibíades  {v}Dos.",
          "{p}1ª Dama  {v}Tres.",
          "{p}1.º HOMBRE  {v}Cuatro.",
          "{p}2me CITOYEN  {v}Cinco.",
          "{p}¿?  {v}Seis."
        ])

      assert Enum.map(xml_elements(xml, "role"), fn {attrs, _} -> attrs["xml:id"] end) ==
               ["absalon", "alcibiades", "dama_1", "hombre_1", "citoyen_2", "character_6"]
    end
  end

  describe "the divisions" do
    # {what, paragraphs, expected outline: [{div1 type, n, head, [scene heads]}]}
    @outlines [
      {"content with no act heading goes into a single act",
       ["{e}Escena 1", "{p}FEBO  {v}Hello."], [{"acto", "1", nil, ["Escena 1"]}]},
      {"{e} starts a scene", ["{e}Escena 1", "{p}FEBO  {v}Hi.", "{e}Escena 2", "{p}ANA  {v}Bye."],
       [{"acto", "1", nil, ["Escena 1", "Escena 2"]}]},
      {"plain-text act headings start acts",
       ["ACTO PRIMERO", "{e}Escena 1", "{p}A {v}x", "ACTO SEGUNDO", "{e}Escena 1", "{p}B {v}y"],
       [{"acto", "1", "ACTO PRIMERO", ["Escena 1"]}, {"acto", "2", "ACTO SEGUNDO", ["Escena 1"]}]},
      {"{A} starts an act, a jornada or a prologue by its wording",
       [
         "{A}PRÓLOGO",
         "{e}Escena 1",
         "{p}A {v}x",
         "{A}JORNADA PRIMERA",
         "{e}Escena 1",
         "{p}B {v}y"
       ],
       [
         {"prologo", nil, "PRÓLOGO", ["Escena 1"]},
         {"jornada", "1", "JORNADA PRIMERA", ["Escena 1"]}
       ]},
      {"prologues and epilogues are recognised in plain text, with or without 'The'",
       [
         "The Prologue to the King's Majesty",
         "{e}Escena 1",
         "{p}A {v}x",
         "{A}ACTO PRIMERO",
         "{e}Escena 1",
         "{p}B {v}y",
         "THE EPILOGUE",
         "{e}Escena 1",
         "{p}C {v}z"
       ],
       [
         {"prologo", nil, "The Prologue to the King's Majesty", ["Escena 1"]},
         {"acto", "1", "ACTO PRIMERO", ["Escena 1"]},
         {"epilogue", nil, "THE EPILOGUE", ["Escena 1"]}
       ]},
      {"{e} naming a prologue, epilogue or induction makes a top-level division, not a scene",
       [
         "{e}The Induction on the Stage",
         "{p}STAGE-KEEPER  {v}Welcome.",
         "{e}1.1",
         "{p}JOHN  {v}Hello.",
         "{e}EPILOGUE",
         "{p}NARRATOR  {v}Goodbye."
       ],
       [
         {"induction", nil, "The Induction on the Stage", []},
         {"acto", "1", "Act 1", ["1.1"]},
         {"epilogue", nil, "EPILOGUE", []}
       ]},
      {"M.N scene numbers start a new act at each new M",
       [
         "{e}1.1",
         "{p}A {v}a",
         "{e}1.2",
         "{p}B {v}b",
         "{e}2.1",
         "{p}C {v}c",
         "{e}3.1",
         "{p}D {v}d"
       ],
       [
         {"acto", "1", "Act 1", ["1.1", "1.2"]},
         {"acto", "2", "Act 2", ["2.1"]},
         {"acto", "3", "Act 3", ["3.1"]}
       ]},
      {"a prologue before M.N scenes leaves act numbering starting at 1",
       [
         "The Prologue",
         "{e}Prol.1",
         "{p}N {v}Welcome.",
         "{e}1.1",
         "{p}J {v}One.",
         "{e}2.1",
         "{p}J {v}Two."
       ],
       [
         {"prologo", nil, "The Prologue", ["Prol.1"]},
         {"acto", "1", "Act 1", ["1.1"]},
         {"acto", "2", "Act 2", ["2.1"]}
       ]},
      {"untagged text before the first act is not a division",
       ["EJERCICIO", "", "JORNADA I", "{e}Escena 1", "{p}FEBO  {v}Hello."],
       [{"jornada", "1", "JORNADA I", ["Escena 1"]}]},
      {"{e}THE END closes the play instead of opening a scene",
       ["{e}1.1", "{p}JOHN  {v}Hello.", "{e}THE END"], [{"acto", "1", "Act 1", ["1.1"]}]}
    ]

    for {what, paragraphs, expected} <- @outlines do
      @paragraphs paragraphs
      @expected expected

      test what do
        outline =
          @paragraphs
          |> import_word()
          |> outline()
          |> Enum.map(fn {attrs, head, scenes} ->
            {attrs["type"], attrs["n"], head, Enum.map(scenes, &elem(&1, 1))}
          end)

        assert outline == @expected
      end
    end

    test "a division with no scenes holds its speeches, stage directions and verse directly" do
      xml =
        import_word([
          "{e}Prologue",
          "{p}NARRATOR  {v}Welcome",
          "{v}to the fair.",
          "{ac}Exit Narrator.",
          "THE SCENE: SMITHFIELD",
          "{V}A line with no speaker.",
          "{e}1.1",
          "{p}JOHN  {v}Hello."
        ])

      assert [{%{"type" => "prologo"}, "Prologue", []}, {%{"type" => "acto"}, _, [_]}] =
               outline(xml)

      assert xml_texts(xml, "sp") |> hd() == "NARRATOR Welcome to the fair."
      assert xml_texts(xml, "stage") == ["Exit Narrator."]
      refute "Exit Narrator." in xml_texts(xml, "stage", within: "div2")

      assert xml_texts(xml, "l") == [
               "Welcome",
               "to the fair.",
               "A line with no speaker.",
               "Hello."
             ]
    end
  end

  test "text before the first scene becomes the front matter note" do
    xml =
      import_word([
        "BARTHOLOMEW FAIR",
        "Ben Jonson",
        "{PR}THE PROLOGUE TO THE KING",
        "{e}1.1",
        "{p}FEBO  {v}Hello."
      ])

    assert [{_, text}] =
             Enum.filter(
               xml_elements(xml, "div", within: "front"),
               &match?({%{"type" => "nota"}, _}, &1)
             )

    assert text =~ "Front matter"
    assert text =~ "BARTHOLOMEW FAIR"
    assert text =~ "Ben Jonson"
    assert text =~ "THE PROLOGUE TO THE KING"
  end

  test "a document that opens with a scene has no front matter" do
    xml = import_word(["{e}Escena 1", "{p}FEBO  {v}Hello."])

    assert Enum.map(xml_elements(xml, "div", within: "front"), fn {a, _} -> a["type"] end) ==
             ["elenco"]
  end

  test "importing again replaces the text and the characters" do
    play = play_fixture()
    import_word(["{e}Escena 1", "{p}FEBO  {v}Hello."], play)
    xml = import_word(["{e}Escena 1", "{p}RICARDO  {v}Goodbye.", "{v}See you."], play)

    assert speeches(xml) == ["RICARDO Goodbye. See you."]
    assert xml_texts(xml, "role") == ["RICARDO"]
  end

  test "statistics count each character's speeches" do
    play = play_fixture()

    import_word(
      ["{e}Escena 1", "{p}FEBO  {v}Hello.", "{p}FEBO  {v}Again.", "{p}ANA  {v}Bye."],
      play
    )

    appearances = Playcode.Statistics.get_statistics(play.id).data["character_appearances"]

    assert Map.new(appearances, &{&1["name"], &1["speeches"]}) == %{"FEBO" => 2, "ANA" => 1}
  end
end
