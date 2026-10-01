defmodule Playcode.TeiRoundtripTest do
  @moduledoc """
  What a TEI file says survives import and comes back out of the export.

  Each test feeds a small TEI document through `TeiParser.import_file/1`, exports
  the play with `TeiXml.generate/1`, and asserts on the exported XML. How the
  importer stores things is free to change; what a TEI consumer reads is not.
  Real corpus files get the same treatment in test/playcode/roundtrip_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  @rich_header [
    title: "Ricardo III",
    title_stmt: """
    <title type="original">The Tragedy of Richard III</title>
    <title type="edicion">Edición crítica 2023</title>
    <editor role="translator"><persName>Sanderson, John D.</persName></editor>
    <author ana="fiable">William Shakespeare</author>
    <sponsor><orgName>Plan Nacional de I+D+i</orgName></sponsor>
    <funder><orgName>Ministerio de Ciencia e Innovación</orgName></funder>
    <respStmt><resp>Electronic edition</resp><persName>Amelang, David J.</persName></respStmt>
    <principal>Joan Oleza Simó</principal>
    """,
    file_desc: """
    <editionStmt>
      <respStmt>
        <resp>Edición crítica</resp>
        <persName>Edition Editor</persName>
        <orgName>University Lab</orgName>
      </respStmt>
    </editionStmt>
    """,
    publication_stmt: """
    <publisher><orgName>ARTELOPE/EMOTHE, Universitat de València</orgName></publisher>
    <authority><orgName>Universitat de València - Estudi General</orgName></authority>
    <idno type="EMOTHE">0703</idno>
    <availability>
      <p>Some general availability text.</p>
      <licence target="https://creativecommons.org/licenses/by-nc-nd/4.0/deed.es">CC BY-NC-ND 4.0</licence>
    </availability>
    <pubPlace>Valencia</pubPlace>
    <date>2023</date>
    """,
    source_desc: """
    <bibl>
      <title>La tragedia del rey Ricardo III</title>
      <author>Shakespeare, William</author>
      <editor role="traductor">Sanderson, John D.</editor>
      <publisher>Miguel Seguí</publisher>
      <pubPlace>Barcelona</pubPlace>
      <date>1908</date>
      <lang>Español</lang>
      <note>Notas de la fuente.</note>
    </bibl>
    """
  ]

  # {what, tag, within, attributes it must carry, text}
  @header_fields [
    {"main title", "title", "titleStmt", %{}, "Ricardo III"},
    {"original title", "title", "titleStmt", %{"type" => "original"},
     "The Tragedy of Richard III"},
    {"edition title", "title", "titleStmt", %{"type" => "edicion"}, "Edición crítica 2023"},
    {"author and attribution", "author", "titleStmt", %{"ana" => "fiable"},
     "William Shakespeare"},
    {"translator", "editor", "titleStmt", %{"role" => "translator"}, "Sanderson, John D."},
    {"sponsor", "sponsor", "titleStmt", %{}, "Plan Nacional de I+D+i"},
    {"funder", "funder", "titleStmt", %{}, "Ministerio de Ciencia e Innovación"},
    {"digital editor", "respStmt", "titleStmt", %{}, "Electronic edition Amelang, David J."},
    {"principal", "principal", "titleStmt", %{}, "Joan Oleza Simó"},
    {"edition editor and organisation", "respStmt", "editionStmt", %{},
     "Edición Edition Editor University Lab"},
    {"publisher", "publisher", "publicationStmt", %{},
     "ARTELOPE/EMOTHE, Universitat de València"},
    {"authority", "authority", "publicationStmt", %{},
     "Universitat de València - Estudi General"},
    {"EMOTHE id", "idno", "publicationStmt", %{"type" => "EMOTHE"}, "0703"},
    {"availability note", "p", "availability", %{}, "Some general availability text."},
    {"licence", "licence", "availability",
     %{"target" => "https://creativecommons.org/licenses/by-nc-nd/4.0/deed.es"},
     "CC BY-NC-ND 4.0"},
    {"publication place", "pubPlace", "publicationStmt", %{}, "Valencia"},
    {"publication date", "date", "publicationStmt", %{}, "2023"},
    {"source title", "title", "bibl", %{}, "La tragedia del rey Ricardo III"},
    {"source author", "author", "bibl", %{}, "Shakespeare, William"},
    {"source editor and role", "editor", "bibl", %{"role" => "traductor"}, "Sanderson, John D."},
    {"source publisher", "publisher", "bibl", %{}, "Miguel Seguí"},
    {"source place", "pubPlace", "bibl", %{}, "Barcelona"},
    {"source date", "date", "bibl", %{}, "1908"},
    {"source language", "lang", "bibl", %{}, "Español"},
    {"source note", "note", "bibl", %{}, "Notas de la fuente."}
  ]

  describe "the header" do
    setup do
      %{xml: roundtrip(tei(@rich_header))}
    end

    for {what, tag, within, attrs, text} <- @header_fields do
      @tag_name tag
      @within within
      @attrs attrs
      @text text

      test "keeps the #{what}", %{xml: xml} do
        found = xml_elements(xml, @tag_name, within: @within)

        assert Enum.any?(found, fn {attrs, text} ->
                 Map.take(attrs, Map.keys(@attrs)) == @attrs and text == @text
               end),
               "no <#{@tag_name}> #{inspect(@attrs)} #{inspect(@text)} in <#{@within}>: " <>
                 inspect(found)
      end
    end
  end

  describe "an <editor> in the title statement" do
    defp title_editors(title_stmt),
      do: xml_elements(roundtrip(tei(title_stmt: title_stmt)), "editor", within: "titleStmt")

    # 7 corpus translations (EMOTHE0050, 0053, 0059…) spell the role in Spanish.
    test "role=\"traductor\" is a translator" do
      assert [{%{"role" => "translator"}, "Leandro Fernández de Moratín"}] =
               title_editors(~s(<editor role="traductor">Leandro Fernández de Moratín</editor>))
    end

    # The editor of the critical edition the text is based on — the person the
    # FileMaker index credits as "ed.". 23 corpus files carry one.
    test "role=\"edicion_critica\" is the critical edition's editor, with their group" do
      assert [{%{"role" => "edicion_critica"}, "Durá Celma, Rosa Grupo DICAT"}] =
               title_editors(
                 ~s(<editor role="edicion_critica"><persName>Durá Celma, Rosa</persName><orgName>Grupo DICAT</orgName></editor>)
               )
    end

    test "an empty orgName is no group" do
      xml =
        roundtrip(
          tei(
            title_stmt:
              ~s(<editor role="edicion_critica"><persName>Creaser, John</persName><orgName></orgName></editor>)
          )
        )

      assert [{%{"role" => "edicion_critica"}, "Creaser, John"}] =
               xml_elements(xml, "editor", within: "titleStmt")

      assert xml_elements(xml, "orgName", within: "editor") == []
    end
  end

  test "an all-capitals title is title-cased, a mixed-case one is left alone" do
    for {given, expected} <- [
          {"LOS RAMILLETES DE MADRID", "Los Ramilletes de Madrid"},
          {"La Dama Boba", "La Dama Boba"}
        ] do
      xml = roundtrip(tei(title: given))
      assert expected in xml_texts(xml, "title", within: "titleStmt")
    end
  end

  test "the play's code is its archive key and identifier" do
    xml = roundtrip(tei(code: "AL0606"))

    assert {%{"key" => "archivo"}, "AL0606"} in xml_elements(xml, "title")
    assert {%{"type" => "code"}, "AL0606"} in xml_elements(xml, "idno")
  end

  test "several sources keep their order, with or without a listBibl wrapper" do
    for source_desc <- [
          "<bibl><title>First</title></bibl><bibl><title>Second</title></bibl>",
          "<listBibl><bibl><title>First</title></bibl><bibl><title>Second</title></bibl></listBibl>"
        ] do
      xml = roundtrip(tei(source_desc: source_desc))
      assert xml_texts(xml, "title", within: "bibl") == ["First", "Second"]
    end
  end

  describe "the play's language" do
    # The root's xml:lang is always "es" in EMOTHE files (the editorial platform's
    # language); the play's own language is langUsage.
    test "comes from langUsage" do
      for {ident, label} <- [{"it-IT", "Italiano"}, {"fr-FR", "Français"}, {"en-EN", "English"}] do
        xml =
          roundtrip(
            tei(profile_desc: ~s(<langUsage><language ident="#{ident}">x</language></langUsage>))
          )

        assert xml_elements(xml, "language") == [{%{"ident" => ident}, label}]
      end
    end

    test "is Spanish when the file does not say" do
      assert xml_elements(roundtrip(tei()), "language") == [{%{"ident" => "es-ES"}, "Español"}]
    end
  end

  describe "the composition date" do
    defp creation(date), do: tei(profile_desc: "<creation>#{date}</creation>")

    test "a single year" do
      xml = roundtrip(creation(~s(<date when="1614"/>)))
      assert [{%{"when" => "1614"}, ""}] = xml_elements(xml, "date", within: "creation")
    end

    test "a range, with the competing datings as its text" do
      xml = roundtrip(creation(~s(<date notBefore="1600" notAfter="1601">¿1600? y ¿1601?</date>)))

      assert [{%{"notBefore" => "1600", "notAfter" => "1601"}, "¿1600? y ¿1601?"}] =
               xml_elements(xml, "date", within: "creation")
    end

    # An unusable date is the file's problem, not an import failure: the play still
    # imports, only without a dating.
    test "an unusable date imports as no dating" do
      for date <- [
            "<date>c. 1600</date>",
            ~s(<date notAfter="1601"/>),
            ~s(<date notBefore="1607" notAfter="1606"/>),
            ~s(<date when="850"/>),
            ~s(<date when="-0044"/>)
          ] do
        assert xml_elements(roundtrip(creation(date)), "creation") == [], date
      end
    end

    test "no creation element, no dating" do
      assert xml_elements(roundtrip(tei()), "creation") == []
    end
  end

  describe "the cast list" do
    test "keeps ids, names, descriptions and hidden characters, in order" do
      xml =
        roundtrip(
          tei(
            front: """
            <div type="elenco">
              <castList>
                <castItem><role xml:id="DONA">Dona Ana</role><roleDesc>una dama</roleDesc></castItem>
                <castItem><role xml:id="DON">Don Juan</role></castItem>
                <castItem ana="oculto"><role xml:id="CRIADO">Criado</role></castItem>
              </castList>
            </div>
            """
          )
        )

      assert xml_elements(xml, "role") == [
               {%{"xml:id" => "DONA"}, "Dona Ana"},
               {%{"xml:id" => "DON"}, "Don Juan"},
               {%{"xml:id" => "CRIADO"}, "Criado"}
             ]

      assert xml_texts(xml, "roleDesc") == ["una dama"]

      assert [{%{}, _}, {%{}, _}, {%{"ana" => "oculto"}, "Criado"}] =
               xml_elements(xml, "castItem")
    end

    test "a repeated id with a different name is kept apart; an exact repeat is one character" do
      xml =
        roundtrip(
          tei(
            front: """
            <div type="elenco"><castList>
              <castItem><role xml:id="HERO">Hero Original</role></castItem>
              <castItem><role xml:id="HERO">Hero Duplicate</role></castItem>
              <castItem><role xml:id="HERO">Hero Original</role></castItem>
            </castList></div>
            """
          )
        )

      assert xml_elements(xml, "role") == [
               {%{"xml:id" => "HERO"}, "Hero Original"},
               {%{"xml:id" => "HERO_2"}, "Hero Duplicate"}
             ]
    end
  end

  test "every kind of front-matter note keeps its type" do
    for type <- ~w(introduccion_editor dedicatoria argumento prologo nota) do
      xml = roundtrip(tei(front: ~s(<div type="#{type}"><p>Texto.</p></div>)))
      assert [{%{"type" => ^type}, "Texto."}] = xml_elements(xml, "div", within: "front")
    end
  end

  test "a front-matter note keeps its type, heading and paragraphs" do
    xml =
      roundtrip(
        tei(
          front: """
          <div type="dedicatoria">
            <head>Dedicatoria</head>
            <p>Al muy ilustre señor...</p>
            <p>Con todo respeto...</p>
          </div>
          """
        )
      )

    assert [{%{"type" => "dedicatoria"}, _}] = xml_elements(xml, "div", within: "front")

    assert xml_texts(xml, "head", within: "front") == ["Dedicatoria"]

    assert xml_texts(xml, "p", within: "front") == [
             "Al muy ilustre señor...",
             "Con todo respeto..."
           ]
  end

  describe "the text" do
    defp scene(content) do
      ~s(<div1 type="acto" n="1"><head>ACTO</head><div2 type="escena" n="1">#{content}</div2></div1>)
    end

    defp cast(ids) do
      items = Enum.map_join(ids, &~s(<castItem><role xml:id="#{&1}">#{&1}</role></castItem>))
      ~s(<div type="elenco"><castList>#{items}</castList></div>)
    end

    test "acts and scenes keep their order, numbers and heads" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1">
              <head>ACTO PRIMERO</head>
              <div2 type="escena" n="1"><head>ESCENA I</head></div2>
              <div2 type="escena" n="2"><head>ESCENA II</head></div2>
            </div1>
            <div1 type="acto" n="2"><head>ACTO SEGUNDO</head></div1>
            """
          )
        )

      assert xml_elements(xml, "div1") |> Enum.map(&elem(&1, 0)) == [
               %{"type" => "acto", "n" => "1"},
               %{"type" => "acto", "n" => "2"}
             ]

      assert xml_elements(xml, "div2") |> Enum.map(&elem(&1, 0)) == [
               %{"type" => "escena", "n" => "1"},
               %{"type" => "escena", "n" => "2"}
             ]

      assert xml_texts(xml, "head", within: "body") ==
               ["ACTO PRIMERO", "ESCENA I", "ESCENA II", "ACTO SEGUNDO"]
    end

    # EMOTHE0346 (Bartholomew Fair) opens with an induction; the export used to drop
    # it, speeches and all, because its type was missing from the body whitelist.
    test "every kind of top-level division the corpus uses survives, with its content" do
      types = ~w(acto jornada act prologue induction epilogue play)

      body =
        Enum.map_join(types, fn type ->
          ~s(<div1 type="#{type}" n="1"><sp><speaker>X</speaker><p>#{type} text</p></sp></div1>)
        end)

      xml = roundtrip(tei(body: body))

      assert Enum.map(xml_elements(xml, "div1"), fn {attrs, _} -> attrs["type"] end) == types
      assert xml_texts(xml, "p", within: "div1") == Enum.map(types, &"#{&1} text")
    end

    test "a speech keeps its speaker, who it is, and its verse" do
      xml =
        roundtrip(
          tei(
            front: cast(["ANA"]),
            body:
              scene("""
              <sp who="#ANA">
                <speaker>ANA</speaker>
                <lg type="redondilla"><l n="1">First verse line</l><l n="2">Second verse line</l></lg>
              </sp>
              """)
          )
        )

      assert [{%{"who" => "#ANA"}, _}] = xml_elements(xml, "sp")
      assert xml_texts(xml, "speaker") == ["ANA"]
      assert [{%{"type" => "redondilla"}, _}] = xml_elements(xml, "lg")

      assert [{%{"n" => n1}, "First verse line"}, {%{"n" => n2}, "Second verse line"}] =
               xml_elements(xml, "l")

      assert {String.to_integer(n1), String.to_integer(n2)} == {1, 2}
    end

    test "a speech shared by several characters names them all" do
      xml =
        roundtrip(
          tei(
            front: cast(["ALB", "COR"]),
            body: scene(~s(<sp who="#ALB #COR"><speaker>LOS DOS</speaker><p>¡Ah!</p></sp>))
          )
        )

      assert [{%{"who" => who}, _}] = xml_elements(xml, "sp")
      assert who |> String.split() |> Enum.sort() == ["#ALB", "#COR"]
    end

    test "stage directions and prose keep their text and order" do
      xml =
        roundtrip(
          tei(
            body:
              scene("""
              <stage>Sale el REY por la puerta</stage>
              <sp><speaker>REY</speaker><p>A prose paragraph.</p><p>And a second.</p></sp>
              <stage>Se sienta en el trono</stage>
              """)
          )
        )

      assert xml_texts(xml, "stage") == ["Sale el REY por la puerta", "Se sienta en el trono"]
      assert xml_texts(xml, "p", within: "sp") == ["A prose paragraph.", "And a second."]
    end

    test "a stage direction stays where it was: in an act with no scenes, inside a speech" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1">
              <stage>Sale el coro</stage>
              <sp><speaker>CORO</speaker><stage>Cantando</stage><l n="1">Canta</l></sp>
            </div1>
            """
          )
        )

      assert xml_texts(xml, "stage") == ["Sale el coro", "Cantando"]
      assert xml_texts(xml, "stage", within: "sp") == ["Cantando"]
      assert xml_elements(xml, "div2") == []
    end

    # The export used to write every stage direction as a bare <stage>, dropping the
    # corpus's exit, entrance, business, location, setting, mixed and delivery types.
    test "a stage direction keeps its type" do
      xml =
        roundtrip(
          tei(
            body:
              scene("""
              <stage type="entrance">Sale el REY</stage>
              <sp><speaker>REY</speaker>
                <stage type="delivery">[En aparté]</stage>
                <lg><l n="1"><seg type="aside">Ay de mí</seg></l></lg>
                <stage type="business">Se sienta</stage>
              </sp>
              <stage>Suena música</stage>
              <stage type="exit">Vase</stage>
              """)
          )
        )

      assert xml_elements(xml, "stage") == [
               {%{"type" => "entrance"}, "Sale el REY"},
               {%{"type" => "delivery"}, "[En aparté]"},
               {%{"type" => "business"}, "Se sienta"},
               {%{}, "Suena música"},
               {%{"type" => "exit"}, "Vase"}
             ]
    end

    test "split verses keep their part, id and indentation" do
      xml =
        roundtrip(
          tei(
            front: cast(["ANA", "DON"]),
            body:
              scene("""
              <sp who="#ANA"><speaker>ANA</speaker>
                <lg type="redondilla" part="I"><l n="1" part="I" xml:id="v001">First part</l></lg>
              </sp>
              <sp who="#DON"><speaker>DON</speaker>
                <lg type="redondilla"><l n="1" part="F">Second part</l><l n="2" rend="indent">Full</l></lg>
              </sp>
              """)
          )
        )

      assert [
               {%{"part" => "I", "xml:id" => "v001"}, "First part"},
               {%{"part" => "F"} = second, "Second part"},
               {%{"rend" => "indent"} = full, "Full"}
             ] = xml_elements(xml, "l")

      refute Map.has_key?(second, "xml:id")
      refute Map.has_key?(full, "part")
      assert [{%{"part" => "I"}, _}, {lg2, _}] = xml_elements(xml, "lg")
      refute Map.has_key?(lg2, "part")
    end

    test "an aside, however the delivery is spelled, stays an aside" do
      xml =
        roundtrip(
          tei(
            body:
              scene("""
              <sp><speaker>ANA</speaker><lg type="decima">
                <l n="1">Normal verse line</l>
                <l n="2"><stage type="delivery">[Aparte.]</stage><seg type="aside">Square</seg></l>
                <l n="3"><stage type="delivery">(Aparte.)</stage><seg type="aside">Round</seg></l>
                <l n="4"><stage type="delivery">Aparte</stage><seg type="aside">Bare</seg></l>
              </lg></sp>
              <sp><speaker>REY</speaker>
                <p><seg type="aside">An aside in prose</seg></p>
                <p>Normal prose.</p>
              </sp>
              """)
          )
        )

      assert xml_texts(xml, "seg") == ["Square", "Round", "Bare", "An aside in prose"]
      assert Enum.all?(xml_elements(xml, "seg"), &match?({%{"type" => "aside"}, _}, &1))
      assert "Normal verse line" in xml_texts(xml, "l")
      assert "Normal prose." in xml_texts(xml, "p", within: "sp")
    end

    test "a stage direction that merely mentions an aside does not make the next line one" do
      xml =
        roundtrip(
          tei(
            body:
              scene("""
              <stage>Hablan los dos aparte.</stage>
              <sp><speaker>REY</speaker><lg type="redondilla"><l n="1">A normal line</l></lg></sp>
              """)
          )
        )

      assert xml_texts(xml, "stage") == ["Hablan los dos aparte."]
      assert xml_elements(xml, "seg") == []
    end

    test "emphasis survives in verse and in stage directions" do
      xml =
        roundtrip(
          tei(
            body:
              scene("""
              <sp><speaker>NIGHTINGALE</speaker><lg type="free">
                <l n="1"><emph>Hear for your love, and buy for your money</emph></l>
                <l n="2">Normal text here</l>
              </lg></sp>
              <stage><emph>Exit singing.</emph></stage>
              """)
          )
        )

      assert xml_texts(xml, "emph") == [
               "Hear for your love, and buy for your money",
               "Exit singing."
             ]

      refute xml =~ "&lt;&lt;"
    end

    test "the extent counts the verse lines actually imported" do
      xml =
        roundtrip(
          tei(
            file_desc: "<extent>3500 versos</extent>",
            body:
              scene(
                ~s(<sp><speaker>A</speaker><lg><l n="1">uno</l><l n="2" part="I">dos</l></lg></sp>) <>
                  ~s(<sp><speaker>B</speaker><lg><l n="2" part="F">dos</l></lg></sp>)
              )
          )
        )

      # Split halves share one line number, so they are one verse.
      assert xml_elements(xml, "extent") == [{%{"ana" => "verso"}, "2 versos"}]
    end
  end

  # Exporting used to write a titleStmt respStmt editor into editionStmt as well, and
  # re-importing that copy made a second editor: one more per round trip.
  test "exporting, re-importing and exporting again changes nothing" do
    body = """
    <div1 type="acto" n="1"><head>ACTO I</head><div2 type="escena" n="1"><head>ESCENA I</head>
      <stage>Salen</stage>
      <sp who="#ANA"><speaker>ANA</speaker>
        <lg type="redondilla"><l n="1" part="I" xml:id="v1">Uno</l></lg></sp>
      <sp who="#DON"><speaker>DON</speaker>
        <lg type="redondilla"><l n="1" part="F">dos</l><l n="2" rend="indent"><seg type="aside">tres</seg></l></lg>
        <p>Prosa con <emph>énfasis</emph>.</p></sp>
    </div2></div1>
    """

    front = """
    <div type="dedicatoria"><head>Dedicatoria</head><p>Al lector.</p></div>
    <div type="elenco"><castList>
      <castItem><role xml:id="ANA">Ana</role><roleDesc>dama</roleDesc></castItem>
      <castItem ana="oculto"><role xml:id="DON">Don</role></castItem>
    </castList></div>
    """

    profile =
      ~s(<langUsage><language ident="it-IT">Italiano</language></langUsage>) <>
        ~s(<creation><date notBefore="1605" notAfter="1607">hacia 1606</date></creation>)

    first =
      tei(@rich_header ++ [code: "FIX1", front: front, body: body, profile_desc: profile])
      |> roundtrip()

    second = first |> String.replace("FIX1", "FIX2") |> roundtrip()

    assert String.replace(second, "FIX2", "FIX1") == first
  end
end
