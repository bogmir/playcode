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
  import Playcode.TestFixtures, only: [bibliography_fixture: 2]

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

  # EMOTHE0113 (Tartuffe) heads its second placet with 302 characters.
  test "a front-matter note keeps a heading longer than 255 characters" do
    heading = String.duplicate("PLACET PRÉSENTÉ AU ROI ", 14)

    xml =
      roundtrip(tei(front: ~s(<div type="epistola"><head>#{heading}</head><p>Sire,</p></div>)))

    assert xml_texts(xml, "head", within: "front") == [String.trim(heading)]
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
    # interlude (EMOTHE0343, 0444, 0714), dumb_show (0329) and auto (0383) failed the
    # import outright.
    test "every kind of top-level division the corpus uses survives, with its content" do
      types = ~w(acto jornada act prologue induction epilogue play interlude dumb_show auto)

      body =
        Enum.map_join(types, fn type ->
          ~s(<div1 type="#{type}" n="1"><sp><speaker>X</speaker><p>#{type} text</p></sp></div1>)
        end)

      xml = roundtrip(tei(body: body))

      assert Enum.map(xml_elements(xml, "div1"), fn {attrs, _} -> attrs["type"] end) == types
      assert xml_texts(xml, "p", within: "div1") == Enum.map(types, &"#{&1} text")
    end

    # Gorboduc's dumb shows (EMOTHE0329) and the act summaries of EMOTHE0709 are
    # paragraphs nobody speaks; they used to be dropped.
    test "a paragraph outside any speech stays in its division" do
      xml =
        roundtrip(
          tei(body: ~s(<div1 type="dumb_show" n="1"><p>First the music of violins</p></div1>))
        )

      assert xml_texts(xml, "p", within: "div1") == ["First the music of violins"]
      assert xml_elements(xml, "sp") == []
    end

    # EMOTHE0354 and EMOTHE0510 open with a stanza nobody speaks.
    test "a stanza outside any speech keeps its verse" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="prologue" n="1">
              <lg type="free"><l n="1">Io, qual vedete</l><l n="2">A questo scettro</l></lg>
            </div1>
            """
          )
        )

      assert [{%{"type" => "free"}, _}] = xml_elements(xml, "lg", within: "div1")
      assert xml_texts(xml, "l") == ["Io, qual vedete", "A questo scettro"]
      assert xml_elements(xml, "sp") == []
    end

    # 226 trailers in 132 plays ("FIN DEL PRIMER ACTO") used to be dropped. TEI only
    # allows one at the end of its division, so the act's comes after its scenes.
    test "a trailer closes its scene and its act" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1">
              <div2 type="escena" n="1">
                <sp><speaker>X</speaker><l>Verso.</l></sp>
                <trailer>FIN</trailer>
              </div2>
              <trailer>FIN DEL <emph>PRIMER</emph> ACTO</trailer>
            </div1>
            """
          )
        )

      assert xml_texts(xml, "trailer", within: "div2") == ["FIN"]
      assert xml_texts(xml, "trailer") == ["FIN", "FIN DEL PRIMER ACTO"]
      assert xml_texts(xml, "emph", within: "trailer") == ["PRIMER"]
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

  describe "in-text notes" do
    @noted """
    <div1 type="acto" n="1"><head>ACTO I</head>
      <div2 type="escena" n="1"><head>ESCENA PRIMERA<note n="1" type="traductor"><term>PRIMERA</term><p>Argumento.</p></note></head>
        <sp><speaker>AMINTAS<note n="2" type="editor"><term>AMINTAS</term><p>Corregimos «Andromire».</p></note></speaker>
          <l n="1">Nous voyent<note n="3" type="editor"><term>voyent</term><p>Forme archaïque.</p><p>Deux syllabes &amp; plus.</p></note> dans la ville</l>
          <l n="2">de Grecia y de Iliria<note n="4" type="traductor"><term>Iliria</term><p>Región de los Balcanes.</p></note>.</l>
          <l n="3">con dos caras que tiene,<note n="5" type="editor_digital">
              <term>tiene,</term>
              <p>Este verso aparece <emph>erróneamente</emph> aquí.</p>
            </note>
          </l>
          <l n="4">un <emph>sueño<note n="6" type="editor"><p>En cursiva.</p></note> breve</emph> fue</l>
          <l n="5">sin glosa<note type="lines"/></l>
          <p>Buscad por todas partes …<note n="7" type="traductor"><p><emph>"partes …"</emph></p><p>(14) De aquí en adelante.</p></note></p>
          <stage>Sale<note n="8" type="editor"><p>Una.</p></note><note n="9" type="editor"><p>Dos.</p></note> el rey</stage>
        </sp>
      </div2>
    </div1>
    """

    test "a note leaves the text it glosses, and comes back after the same word" do
      xml = roundtrip(tei(body: @noted))

      assert reading_texts(xml, "l") == [
               "Nous voyent dans la ville",
               "de Grecia y de Iliria.",
               "con dos caras que tiene,",
               "un sueño breve fue",
               "sin glosa"
             ]

      assert reading_texts(xml, "p") == ["Buscad por todas partes …"]
      assert reading_texts(xml, "stage") == ["Sale el rey"]
      assert reading_texts(xml, "speaker") == ["AMINTAS"]
      assert reading_texts(xml, "head") == ["ACTO I", "ESCENA PRIMERA"]

      assert Enum.map(xml_notes(xml), &{&1.in, &1.after, &1.n}) == [
               {"head", "ESCENA PRIMERA", "1"},
               {"speaker", "AMINTAS", "2"},
               {"l", "Nous voyent", "3"},
               {"l", "de Grecia y de Iliria", "4"},
               {"l", "con dos caras que tiene,", "5"},
               {"l", "un sueño", "6"},
               {"p", "Buscad por todas partes …", "7"},
               {"stage", "Sale", "8"},
               {"stage", "Sale", "9"}
             ]
    end

    test "a note keeps its type, term and paragraphs, italics and all" do
      xml = roundtrip(tei(body: @noted))
      notes = xml_notes(xml)

      assert %{
               type: "editor",
               term: "voyent",
               paragraphs: ["Forme archaïque.", "Deux syllabes & plus."]
             } =
               Enum.at(notes, 2)

      assert %{
               type: "traductor",
               term: nil,
               paragraphs: ["\"partes …\"", "(14) De aquí en adelante."]
             } =
               Enum.at(notes, 6)

      assert %{
               type: "editor_digital",
               term: "tiene,",
               paragraphs: ["Este verso aparece erróneamente aquí."]
             } =
               Enum.at(notes, 4)

      assert xml_texts(xml, "emph", within: "note") == ["erróneamente", "\"partes …\""]
    end

    test "importing a file again replaces its notes, never doubles them" do
      path =
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<note n="1" type="editor"><p>Glosa.</p></note></l></sp></div1>)
        )
        |> write_tmp!()

      {:ok, _} = Playcode.Import.TeiParser.import_file(path)
      {:ok, play} = Playcode.Import.TeiParser.import_file(path)

      assert [%{after: "uno"}] = play |> export_tei() |> xml_notes()
    end
  end

  describe "inline stage directions" do
    @staged """
    <div1 type="acto" n="1"><head>ACTO I</head>
      <div2 type="escena" n="1"><head>ESCENA I</head>
        <sp><speaker>CHIMÈNE</speaker>
          <l n="1"><stage xml:id="st1">(A Léonor.)</stage>Allez l'entretenir en cette galerie.</l>
          <l n="2">Je vous suis,<stage type="exit">(Vase.)</stage> adieu.</l>
          <l n="3">Il parle <stage type="business">(se lève)</stage>puis <stage>(sort)</stage></l>
          <p><stage>Entra</stage>El rey dijo<stage type="delivery_">(bajo)</stage> y salió.</p>
        </sp>
      </div2>
    </div1>
    """

    test "a stage comes back inside its line, where it was, with its type" do
      xml = roundtrip(tei(body: @staged))

      assert Enum.map(xml_inline_stages(xml), &{&1.in, &1.type, &1.text, &1.before, &1.after}) ==
               [
                 {"l", nil, "(A Léonor.)", "", "Allez l'entretenir en cette galerie."},
                 {"l", "exit", "(Vase.)", "Je vous suis,", "adieu."},
                 {"l", "business", "(se lève)", "Il parle", "puis (sort)"},
                 {"l", nil, "(sort)", "Il parle (se lève) puis", ""},
                 {"p", nil, "Entra", "", "El rey dijo (bajo) y salió."},
                 {"p", "delivery_", "(bajo)", "Entra El rey dijo", "y salió."}
               ]

      # The words are the ones the line had when the stage was plain text of it.
      assert reading_texts(xml, "l") == [
               "(A Léonor.) Allez l'entretenir en cette galerie.",
               "Je vous suis, (Vase.) adieu.",
               "Il parle (se lève) puis (sort)"
             ]
    end

    test "a stage is written out escaped" do
      xml =
        roundtrip(
          tei(
            body:
              ~s|<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno <stage>(Tom &amp; Jerry &lt;bajo&gt;)</stage> dos</l></sp></div1>|
          )
        )

      assert [%{text: "(Tom & Jerry <bajo>)"}] = xml_inline_stages(xml)
      assert xml =~ "(Tom &amp; Jerry &lt;bajo&gt;)"
    end

    test "a stage type that is not a plain word is dropped, and the import goes on" do
      xml =
        roundtrip(
          tei(
            body:
              ~s|<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno <stage type="a b">(x)</stage> dos</l></sp></div1>|
          )
        )

      assert [%{type: nil, text: "(x)"}] = xml_inline_stages(xml)
    end

    test "a note inside a stage stays inside it, and one at its end comes out after it" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><sp><speaker>A</speaker>
              <l n="1">Dijo <stage>(en voz <note n="1" type="editor"><p>Dentro.</p></note>baja)</stage> y calló.</l>
              <l n="2"><stage>(Vase)<note n="2" type="editor"><p>Fuera.</p></note></stage> Adiós</l>
            </sp></div1>
            """
          )
        )

      assert [{%{"n" => "1"}, "Dentro."}] = xml_elements(xml, "note", within: "stage")
      assert [%{n: "2", after: "(Vase)"}] = xml_notes(xml) |> Enum.filter(&(&1.n == "2"))
      assert length(xml_elements(xml, "note")) == 2
    end

    test "a stage that opens in italics stays a stage, even right after an italic piece" do
      # The note between them takes away the space the importer puts between pieces, so
      # "uno" and the stage's italic "dos" touch: the export must not merge them into one
      # <emph>, which would lose the stage.
      xml =
        roundtrip(
          tei(
            body:
              ~s|<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1"><emph>uno</emph><note n="1" type="editor"><p>Glosa.</p></note><stage><emph>dos</emph></stage></l></sp></div1>|
          )
        )

      assert [%{in: "l", text: "dos", after: ""}] = xml_inline_stages(xml)
      assert xml_texts(xml, "emph") == ["uno", "dos"]
    end

    test "a note at the start of a stage comes out before it, and stays there" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="1">Dijo <stage><note n="1" type="editor"><p>X.</p></note>(Vase)</stage> y calló.</l>
        <p>Dijo<stage><note n="2" type="editor"><p>Y.</p></note>(Vase)</stage> y calló.</p>
      </sp></div1>
      """

      xml = roundtrip(tei(code: "STG3", body: body))

      # Written out again and read back, the notes do not move.
      again =
        xml |> String.replace("STG3", "STG4") |> roundtrip() |> String.replace("STG4", "STG3")

      assert again == xml

      # The words either side of the stage stay apart.
      assert reading_texts(xml, "l") == ["Dijo (Vase) y calló."]
      assert reading_texts(xml, "p") == ["Dijo (Vase) y calló."]

      assert xml_elements(xml, "note", within: "stage") == []

      assert [%{in: "l", n: "1", after: "Dijo"}, %{in: "p", n: "2", after: "Dijo"}] =
               xml_notes(xml)

      # The note is among the words before the stage, so the stage reads "(Vase)" after it.
      assert [
               %{in: "l", text: "(Vase)", before: "Dijo X.", after: "y calló."},
               %{in: "p", text: "(Vase)", before: "Dijo Y.", after: "y calló."}
             ] = xml_inline_stages(xml)
    end

    test "a stage with no words is no stage, and a note in it stays in the line" do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><sp><speaker>A</speaker>
              <l n="1">uno <stage><note n="1" type="editor"><p>Sola.</p></note></stage> dos</l>
              <l n="2">tres <stage></stage> cuatro</l>
            </sp></div1>
            """
          )
        )

      xml = export_tei(play)

      assert xml_inline_stages(xml) == []
      assert [%{in: "l", n: "1", after: "uno"}] = xml_notes(xml)
      assert reading_texts(xml, "l") == ["uno dos", "tres cuatro"]

      # And the lines are stored with no marker at all, not an empty one.
      lines =
        for d <- Playcode.PlayContent.load_play_content(play.id),
            el <- d.loaded_elements,
            %{type: "verse_line"} = l <- el.children,
            do: l

      assert length(lines) == 2
      assert Enum.all?(lines, &(Playcode.PlayContent.InlineMarkup.stage_count(&1.content) == 0))
    end

    test "only a stage in a line or paragraph is kept as a stage" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><sp><speaker>ANA <stage>(aparte)</stage></speaker>
              <stage>Entra <stage>(solo)</stage></stage>
              <l n="1">uno</l>
            </sp></div1>
            """
          )
        )

      # A speaker label and a standalone stage direction paste a stage's words as their own.
      assert xml_texts(xml, "speaker") == ["ANA (aparte)"]
      assert xml_elements(xml, "stage", within: "speaker") == []
      assert xml_texts(xml, "stage") == ["Entra (solo)"]
    end

    test "a stage in an aside line is dropped with the aside's delivery, as before" do
      xml =
        roundtrip(
          tei(
            body:
              ~s|<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1"><stage type="delivery">Aparte</stage><seg type="aside">qué haré</seg></l></sp></div1>|
          )
        )

      assert xml_inline_stages(xml) == []
      assert xml_texts(xml, "seg") == ["qué haré"]
    end

    test "importing a file again replaces its stages, never doubles them" do
      path =
        tei(
          body:
            ~s|<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno <stage>(x)</stage> dos</l></sp></div1>|
        )
        |> write_tmp!()

      {:ok, _} = Playcode.Import.TeiParser.import_file(path)
      {:ok, play} = Playcode.Import.TeiParser.import_file(path)

      assert [%{text: "(x)"}] = play |> export_tei() |> xml_inline_stages()
    end

    test "exporting, re-importing and exporting again changes nothing" do
      body = """
      #{@staged}
      <div1 type="acto" n="2"><sp><speaker>A</speaker>
        <l n="9">Dijo <stage>(en voz <note n="1" type="editor"><p>Dentro.</p></note>baja)</stage> y calló.</l>
        <l n="10"><stage>(Vase)<note n="2" type="editor"><p>Fuera.</p></note></stage> Adiós</l>
        <l n="11">Dijo <stage><note n="3" type="editor"><p>X.</p></note>(Vase)</stage> y calló.</l>
        <p>Dijo<stage><note n="4" type="editor"><p>Y.</p></note>(Vase)</stage> y calló.</p>
        <p>Prosa <stage>(con <emph>énfasis</emph>)</stage> final.</p>
      </sp></div1>
      """

      first = tei(code: "STG1", body: body) |> roundtrip()
      second = first |> String.replace("STG1", "STG2") |> roundtrip()

      assert String.replace(second, "STG2", "STG1") == first
    end
  end

  # Exporting used to write a titleStmt respStmt editor into editionStmt as well, and
  # re-importing that copy made a second editor: one more per round trip.
  describe "witnesses" do
    @list_wit """
    <listWit>
      <witness xml:id="Q1" n="Q1">
        <bibl type="edicion_antigua" subtype="suelta">
          <title>THE Tragicall Historie of HAMLET</title>
          <title type="normalized">The Tragical History of Hamlet</title>
          <author>Shakespeare, William</author>
          <pubPlace>London</pubPlace>
          <publisher>Ling, Nicholas</publisher>
          <date when="1603">1603</date>
          <extent>4º</extent>
          <idno type="shelfmark">C.34.k.1</idno>
          <note>Usual abbreviation: Q1.</note>
        </bibl>
      </witness>
      <listWit>
        <witness xml:id="wit-1623b" n="1623b">
          <bibl type="edicion_antigua" subtype="coleccion"><title>Œuvres</title></bibl>
        </witness>
      </listWit>
      <witness><bibl type="manuscrito" subtype="autografo"><title>El bastardo Mudarra</title></bibl></witness>
    </listWit>
    """

    test "every field of a witness comes back, in order, with no empty paragraph before them" do
      xml = roundtrip(tei(source_desc: @list_wit))

      assert [
               {%{"n" => "Q1", "xml:id" => "Q1"}, _},
               {%{"n" => "1623b", "xml:id" => "wit-1623b"}, _},
               {unnamed, _}
             ] = xml_elements(xml, "witness")

      refute Map.has_key?(unnamed, "xml:id")
      assert xml_texts(xml, "p", within: "sourceDesc") == []

      assert xml_elements(xml, "title", within: "witness") == [
               {%{}, "THE Tragicall Historie of HAMLET"},
               {%{"type" => "normalized"}, "The Tragical History of Hamlet"},
               {%{}, "Œuvres"},
               {%{}, "El bastardo Mudarra"}
             ]

      for {tag, text} <- [
            {"author", "Shakespeare, William"},
            {"pubPlace", "London"},
            {"publisher", "Ling, Nicholas"},
            {"extent", "4º"},
            {"note", "Usual abbreviation: Q1."}
          ] do
        assert xml_texts(xml, tag, within: "witness") == [text], tag
      end

      assert xml_elements(xml, "date", within: "witness") == [{%{"when" => "1603"}, "1603"}]

      assert xml_elements(xml, "idno", within: "witness") == [
               {%{"type" => "shelfmark"}, "C.34.k.1"}
             ]

      assert for(
               {attrs, _} <- xml_elements(xml, "bibl", within: "witness"),
               do: {attrs["type"], attrs["subtype"]}
             ) == [
               {"edicion_antigua", "suelta"},
               {"edicion_antigua", "coleccion"},
               {"manuscrito", "autografo"}
             ]
    end

    test "a witness described in plain words keeps its words, as its note" do
      words = "anon. [no title page]. London: printed by Richard Pynson, [1518-19?]. STC 10604."

      xml =
        roundtrip(
          tei(
            source_desc:
              ~s(<listWit><witness xml:id="Q1"><bibl>#{words}</bibl></witness></listWit>)
          )
        )

      assert xml_elements(xml, "witness") == [{%{"n" => "Q1", "xml:id" => "Q1"}, words}]
      assert xml_texts(xml, "note", within: "witness") == [words]
    end

    test "a siglum repeated in the file comes in once" do
      xml =
        roundtrip(
          tei(
            source_desc:
              ~s(<listWit><witness xml:id="Q1"><bibl>Uno</bibl></witness>) <>
                ~s(<witness n="Q1"><bibl>Otro</bibl></witness></listWit>)
          )
        )

      assert xml_elements(xml, "witness") == [{%{"n" => "Q1", "xml:id" => "Q1"}, "Uno"}]
    end

    # EMOTHE0460's listWit lists its early quartos and the modern editions its apparatus
    # cites; the editions live in the bibliography, with their siglum.
    test "a re-import keeps hand-typed witnesses and skips a siglum one of them or an edition holds" do
      code = "WIT#{System.unique_integer([:positive])}"
      play = import_tei!(tei(code: code))

      bibliography_fixture(play, %{
        "kind" => "modern_edition",
        "monogr_title" => "Chief Pre-Shakespearean Dramas",
        "siglum" => "ADA"
      })

      {:ok, _} =
        Playcode.Witnesses.create_witness(%{
          "play_id" => play.id,
          "siglum" => "Q2",
          "title" => "Typed by hand"
        })

      file =
        tei(
          code: code,
          source_desc: """
          <listWit>
            <witness xml:id="ADA"><bibl>Adams, Joseph Quincy, ed. Chief Pre-Shakespearean Dramas. 1924.</bibl></witness>
            <witness xml:id="Q1"><bibl>anon. London: Pynson, [1518-19?].</bibl></witness>
            <witness xml:id="Q2"><bibl>anon. London: Pynson, [1526-28?].</bibl></witness>
          </listWit>
          """
        )

      expected = [{"Q2", "Typed by hand"}, {"Q1", "anon. London: Pynson, [1518-19?]."}]

      listed = fn xml ->
        for {%{"n" => n}, text} <- xml_elements(xml, "witness"), do: {n, text}
      end

      assert listed.(roundtrip(file)) == expected
      assert listed.(roundtrip(file)) == expected
    end

    # Most FileMaker witnesses have no siglum, and they are not the file's own rows, so the
    # re-import keeps them: the file's copy of each must not come in beside it.
    test "re-importing its own export keeps a play's witnesses without siglum, once" do
      play = import_tei!(tei(code: "WIT#{System.unique_integer([:positive])}"))

      {:ok, _} =
        Playcode.Witnesses.create_witness(
          %{
            "play_id" => play.id,
            "title" => "COMEDIES, HISTORIES, & TRAGEDIES",
            "origin" => "filemaker"
          },
          %Playcode.Witnesses.Witness{filemaker_id: "T03:36"}
        )

      {:ok, _} =
        Playcode.Witnesses.create_witness(%{"play_id" => play.id, "note" => "Typed by hand"})

      first = export_tei(play)
      listed = fn xml -> for {_, text} <- xml_elements(xml, "witness"), do: text end

      assert listed.(roundtrip(first)) == listed.(first)
      assert listed.(roundtrip(first)) == listed.(first)
    end

    test "exporting, re-importing and exporting again changes nothing" do
      first =
        tei(code: "WIT1", source_desc: "<bibl><title>Base</title></bibl>" <> @list_wit)
        |> roundtrip()

      second = first |> String.replace("WIT1", "WIT2") |> roundtrip()

      assert String.replace(second, "WIT2", "WIT1") == first
    end
  end

  test "exporting, re-importing and exporting again changes nothing" do
    body = """
    <div1 type="acto" n="1"><head>ACTO I</head><div2 type="escena" n="1"><head>ESCENA I</head>
      <stage>Salen</stage>
      <sp who="#ANA"><speaker>ANA</speaker>
        <lg type="redondilla"><l n="1" part="I" xml:id="v1">Uno</l></lg></sp>
      <sp who="#DON"><speaker>DON</speaker>
        <lg type="redondilla"><l n="1" part="F">dos</l><l n="2" rend="indent"><seg type="aside">tres</seg></l>
          <l n="3">cuatro<note n="1" type="editor"><term>cuatro</term><p>Una <emph>glosa</emph>.</p></note>.</l>
          <l n="4">un <emph>sueño<note n="2" type="editor"><p>En cursiva.</p></note> breve</emph> fue</l></lg>
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
