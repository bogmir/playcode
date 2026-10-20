defmodule Playcode.TeiRoundtripTest do
  @moduledoc """
  What a TEI file says survives import and comes back out of the export.

  Each test feeds a small TEI document through `TeiImport.import_file/1`, exports
  the play with `TeiXml.generate/1`, and asserts on the exported XML. How the
  importer stores things is free to change; what a TEI consumer reads is not.
  Real corpus files get the same treatment in test/playcode/roundtrip_test.exs.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  import Playcode.TestFixtures,
    only: [
      bibliography_fixture: 2,
      bibliography_fixture: 3,
      catalogue_fixture: 1,
      performance_fixture: 2,
      place_fixture: 1,
      play_fixture: 1
    ]

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

  # The credits are printed in their order, which a file written by Playcode gives as the
  # order of the title statement's editors and respStmts, interleaved; the corpus files
  # write the editors first.
  test "the title statement's credits keep their order, a respStmt before an editor too" do
    xml =
      roundtrip(
        tei(
          title_stmt: """
          <respStmt><resp>Electronic edition</resp><persName>Amelang, David J.</persName></respStmt>
          <editor role="translator"><persName>Sanderson, John D.</persName></editor>
          <respStmt><resp>Revisión</resp><persName>Revisor, Raúl</persName></respStmt>
          """
        )
      )

    assert xml_texts(xml, "persName", within: "titleStmt") ==
             ["Amelang, David J.", "Sanderson, John D.", "Revisor, Raúl"]
  end

  test "two principal investigators both come back" do
    xml =
      roundtrip(
        tei(title_stmt: "<principal>Oleza, Joan</principal><principal>Tronch, Jesús</principal>")
      )

    assert xml_texts(xml, "principal") == ["Oleza, Joan", "Tronch, Jesús"]
  end

  # The export writes a translator in the title statement only; one in the edition
  # statement (no corpus file has one) was never read, and reading it would move it on the
  # next round trip.
  test "an <editor> in the edition statement is not read" do
    xml =
      roundtrip(
        tei(
          file_desc: """
          <editionStmt><edition>Edición</edition>
            <editor role="translator"><persName>Sanderson, John D.</persName></editor>
          </editionStmt>
          """
        )
      )

    assert xml_texts(xml, "persName") == []
  end

  # 18 corpus files credit two people in one respStmt (EMOTHE0211, 0679, 0718…); the
  # second used to be dropped, though FileMaker's credits name them both.
  test "a respStmt naming two people credits both, in order" do
    xml =
      roundtrip(
        tei(
          title_stmt: """
          <respStmt>
            <resp>Electronic edition: text adapted, edited for XML and encoded by</resp>
            <persName>Tronch Pérez, Jesús</persName>
            <persName>Zafra Alarcón, Sonia</persName>
          </respStmt>
          """
        )
      )

    for xml <- [xml, roundtrip(xml)] do
      assert xml_texts(xml, "persName", within: "respStmt") ==
               ["Tronch Pérez, Jesús", "Zafra Alarcón, Sonia"]
    end
  end

  # The editionStmt wrote a digital editor as "Edición digital", which reads back as an
  # editor: 6 credits in 3 plays changed role on their first round trip.
  test "a digital editor of the edition stays one" do
    xml =
      roundtrip(
        tei(
          file_desc: """
          <editionStmt>
            <respStmt>
              <resp>Electronic edition: text adapted, edited for XML and encoded by</resp>
              <persName>Tronch Pérez, Jesús</persName>
            </respStmt>
          </editionStmt>
          """
        )
      )

    assert xml_texts(roundtrip(xml), "resp", within: "editionStmt") ==
             xml_texts(xml, "resp", within: "editionStmt")
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

  # Four files (EMOTHE0252, 0254, AL0590, AL0711) write their sort title in capitals too.
  # Each word takes its case from the title-cased title, so the article put last keeps its
  # capital, as in every other file's sort title ("Cid Le").
  test "an all-capitals sort title is cased as the title is" do
    for {title, sort_title, expected} <- [
          {"LA DISCRETA ENAMORADA", "DISCRETA ENAMORADA LA", "Discreta Enamorada La"},
          {"EL LLEGAR EN OCASIÓN", "LLEGAR EN OCASIÓN COMEDIA FAMOSA DE EL",
           "Llegar en Ocasión Comedia Famosa de El"},
          {"LA FUERZA DE LA SANGRE", "FUERZA DE LA SANGRE LA", "Fuerza de la Sangre La"},
          {"EL MEJOR ALCALDE, EL REY", "MEJOR ALCALDE EL REY EL", "Mejor Alcalde el Rey El"},
          {"DE FUERA VENDRÁ QUIEN DE CASA NOS ECHARÁ", "DE FUERA VENDRÁ QUIEN DE CASA NOS ECHARÁ",
           "De Fuera Vendrá Quien de Casa Nos Echará"},
          {"La fuerza de la sangre", "FUERZA DE LA SANGRE LA", "fuerza de la sangre La"},
          {"La verdad sospechosa", "verdad sospechosa La", "verdad sospechosa La"}
        ] do
      xml = roundtrip(tei(title: title, title_stmt: ~s(<title key="orden">#{sort_title}</title>)))
      assert {%{"key" => "orden"}, expected} in xml_elements(xml, "title")
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

  # Where the digital text came from (152 production files: Canon 60, Gallica…). The
  # placeholders "Texto base" (59) and "ProcedenciaFuente" (2) are kept, as the file's;
  # an empty one (EMOTHE0286) says nothing.
  test "a source's provenance comes back, a placeholder too, an empty one not" do
    xml =
      roundtrip(
        tei(
          source_desc: """
          <bibl><title>Aminta</title><note>Tasso, Torquato. Aminta.</note>
            <distributor>IntraText Digital Library</distributor></bibl>
          <bibl><title>Hamlet</title><distributor>Texto base</distributor></bibl>
          <bibl><title>Le berger fidelle</title><distributor></distributor></bibl>
          """
        )
      )

    for xml <- [xml, roundtrip(xml)] do
      assert xml_texts(xml, "distributor", within: "bibl") ==
               ["IntraText Digital Library", "Texto base"]
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

    # The library classification (CDU) of the source files follows the language one for
    # one, so it comes back from the language: Playcode does not store it.
    test "brings back the CDU number, which follows it" do
      for {ident, cdu} <- [
            {"es-ES", "821.134.2-2"},
            {"fr-FR", "821.133-2"},
            {"en-EN", "821.111-2"},
            {"it-IT", "821.131-2"}
          ] do
        xml =
          roundtrip(
            tei(
              profile_desc:
                ~s(<langUsage><language ident="#{ident}">x</language></langUsage>) <>
                  ~s(<textClass><classCode scheme="#CDU">#{cdu}</classCode></textClass>)
            )
          )

        assert xml_elements(xml, "classCode") == [{%{"scheme" => "#CDU"}, cdu}]
        assert [{%{"xml:id" => "CDU"}, _}] = xml_elements(xml, "taxonomy", within: "classDecl")
      end
    end

    test "has no CDU number in Portuguese, as the source files have none" do
      xml =
        roundtrip(
          tei(profile_desc: ~s(<langUsage><language ident="pt-PT">x</language></langUsage>))
        )

      assert xml_elements(xml, "classCode") == []
      assert xml_elements(xml, "classDecl") == []
    end
  end

  # A file says a play is a translation (<title type="traduccion">) but, before this, not of
  # which play. It names the original by its short code, the part of its code before the
  # first "_" (EMOTHE0530 of EMOTHE0530_LesAmoursTragiques…), and the import links the two
  # whichever arrives first.
  # 15 notes in 14 production files (EMOTHE0005, 0161…): the edition's own remarks, lists
  # of the witnesses used, editors' reminders. emothe.uv.es shows none of them.
  describe "the notes on the edition" do
    alias Playcode.Catalogue

    test "each comes back, its line breaks too, beside a translation's original" do
      n = System.unique_integer([:positive])

      play =
        import_tei!(
          tei(
            code: "NS#{n}",
            file_desc: """
            <notesStmt>
              <note>El epílogo figura en la edición
                de Ferrara de 1581.</note>
              <note>Impresos<lb/>Madrid, 1637.<lb/><lb/>Madrid, 1641.</note>
              <note> </note>
              <relatedItem type="original" target="EMOTHE0005"/>
            </notesStmt>
            """
          )
        )

      notes = [
        "El epílogo figura en la edición de Ferrara de 1581.",
        "Impresos\nMadrid, 1637.\n\nMadrid, 1641."
      ]

      assert Catalogue.get_play!(play.id).edition_notes == notes

      xml = export_tei(play)
      assert [{%{"target" => "EMOTHE0005"}, ""}] = xml_elements(xml, "relatedItem")

      copy = import_tei!(String.replace(xml, "NS#{n}", "NC#{n}"))
      assert Catalogue.get_play!(copy.id).edition_notes == notes
    end
  end

  # 103 production files describe the project in two paragraphs, FileMaker's blurb and
  # its programmer's credit; read as one, they came back as a single <p>.
  describe "the project description" do
    test "keeps its paragraphs" do
      xml =
        roundtrip(
          tei(
            encoding_desc: """
            <projectDesc>
              <p>La Biblioteca Digital EMOTHE supone la creación
                de una base de datos.</p>
              <p>Bogdan Mircea es responsable de Playcode.</p>
            </projectDesc>
            """
          )
        )

      assert xml_texts(xml, "p", within: "projectDesc") == [
               "La Biblioteca Digital EMOTHE supone la creación de una base de datos.",
               "Bogdan Mircea es responsable de Playcode."
             ]
    end

    test "the availability note and the editorial declaration keep theirs too" do
      xml =
        roundtrip(
          tei(
            publication_stmt: "<availability><p>Uno.</p><p>Dos.</p></availability>",
            encoding_desc: "<editorialDecl><p>Tres.</p><p>Cuatro.</p></editorialDecl>"
          )
        )

      assert xml_texts(xml, "p", within: "availability") == ["Uno.", "Dos."]
      assert xml_texts(xml, "p", within: "editorialDecl") == ["Tres.", "Cuatro."]
    end

    test "keeps its italics" do
      xml =
        roundtrip(
          tei(
            encoding_desc: "<projectDesc><p>La <emph>Biblioteca</emph> Digital</p></projectDesc>"
          )
        )

      assert xml_texts(xml, "emph", within: "projectDesc") == ["Biblioteca"]
    end

    # The TEI also nests the declaration's paragraphs in <normalization>, <correction>…;
    # no corpus file does, so their text is read as one paragraph.
    test "an editorial declaration whose paragraphs are nested is read whole" do
      xml =
        roundtrip(
          tei(
            encoding_desc:
              "<editorialDecl><normalization><p>Se moderniza la ortografía.</p></normalization></editorialDecl>"
          )
        )

      assert xml_texts(xml, "p", within: "editorialDecl") == ["Se moderniza la ortografía."]
    end

    # A textarea posts its line breaks as \r\n.
    test "typed in a form, keeps its paragraphs" do
      play = play_fixture(%{"project_description" => "Uno.\r\n\r\nDos."})

      assert xml_texts(export_tei(play), "p", within: "projectDesc") == ["Uno.", "Dos."]
    end
  end

  # <revisionDesc>: who revised the file and when. 351 of the production files have one
  # <change>, 267 of them "Revisión de la obra en formato TEI-XML" by Carlos Muñoz Pons;
  # EMOTHE0090 says what was done in a <note>, and 83 hold only a date, empty in 44. A
  # change with nothing in it is no change.
  describe "the revision history" do
    alias Playcode.Catalogue
    alias Playcode.PlayContent.InlineMarkup

    test "each change comes back: its date, its revisers, its words, italics too, and its note" do
      n = System.unique_integer([:positive])

      play =
        import_tei!(
          tei(
            code: "RV#{n}",
            revision_desc: """
            <change>
              <date>2021</date>
              <persName>Muñoz Pons, Carlos</persName>
              <persName>Tronch Pérez, Jesús</persName>
              <persName/>
              Revisión de la obra
                en formato <emph>TEI-XML</emph>
            </change>
            <change><note>Con correcciones a cargo de Guillermo Carrascón.</note><date>2025</date></change>
            <change><date></date> </change>
            <change><date/></change>
            """
          )
        )

      changes = [
        %{
          date: "2021",
          people: "Muñoz Pons, Carlos; Tronch Pérez, Jesús",
          description: "Revisión de la obra en formato TEI-XML",
          note: nil
        },
        %{
          date: "2025",
          people: nil,
          description: nil,
          note: "Con correcciones a cargo de Guillermo Carrascón."
        }
      ]

      # The italics are the file's to show (the emph below), not the stored text's.
      revisions = fn play ->
        for change <- Catalogue.get_play!(play.id).revisions do
          change
          |> Map.take([:date, :people, :description, :note])
          |> Map.update!(:description, &(&1 && InlineMarkup.plain(&1)))
        end
      end

      assert revisions.(play) == changes

      # Written back as the files write it: the date, the revisers, then the words.
      xml = export_tei(play)

      assert xml_texts(xml, "change") == [
               "2021 Muñoz Pons, Carlos Tronch Pérez, Jesús Revisión de la obra en formato TEI-XML",
               "2025 Con correcciones a cargo de Guillermo Carrascón."
             ]

      assert xml_texts(xml, "persName", within: "change") ==
               ["Muñoz Pons, Carlos", "Tronch Pérez, Jesús"]

      assert xml_texts(xml, "emph", within: "change") == ["TEI-XML"]

      copy = xml |> String.replace("RV#{n}", "RC#{n}") |> import_tei!()
      assert revisions.(copy) == changes
      assert copy |> export_tei() |> xml_texts("emph", within: "change") == ["TEI-XML"]
    end
  end

  # Question 15: each kind by its own name, as the files call them. 11 files call their play
  # an adaptation and 3 a version (question 40); only "traduccion" used to be read.
  describe "the kind of play a title names" do
    alias Playcode.Catalogue

    for kind <- ~w(adaptacion refundicion version) do
      test "a #{kind} is read from its title and written back there" do
        play =
          import_tei!(tei(title_stmt: ~s(<title type="#{unquote(kind)}">Le Menteur</title>)))

        assert %{relationship_type: unquote(kind), title: "Le Menteur"} =
                 Catalogue.get_play!(play.id)

        assert {%{"type" => unquote(kind)}, "Le Menteur"} in xml_elements(
                 export_tei(play),
                 "title"
               )
      end
    end
  end

  describe "the play a translation translates" do
    alias Playcode.Catalogue

    defp translation(code, original_code) do
      tei(
        code: code,
        title_stmt: ~s(<title type="traduccion">Los amores trágicos</title>),
        file_desc:
          ~s(<notesStmt><relatedItem type="original" target="#{original_code}"/></notesStmt>)
      )
    end

    defp original_of(play), do: Catalogue.get_play!(play.id).parent_play_id

    test "is named by its short code, and links a play imported after the original" do
      n = System.unique_integer([:positive])
      original = import_tei!(tei(code: "OR#{n}_Pyrame"))
      play = import_tei!(tei(code: "TR#{n}", title_stmt: ~s(<title type="traduccion">X</title>)))

      # as the FileMaker sync links them
      {:ok, _} = Catalogue.update_play(play, %{parent_play_id: original.id})

      xml = export_tei(play)

      assert xml_elements(xml, "relatedItem", within: "notesStmt") == [
               {%{"type" => "original", "target" => "OR#{n}"}, ""}
             ]

      copy = import_tei!(String.replace(xml, "TR#{n}", "TC#{n}"))
      assert original_of(copy) == original.id
    end

    test "imported before its original, waits for it, and is linked when it arrives" do
      n = System.unique_integer([:positive])
      play = import_tei!(translation("TR#{n}", "OR#{n}"))

      assert original_of(play) == nil

      assert xml_elements(export_tei(play), "relatedItem") == [
               {%{"type" => "original", "target" => "OR#{n}"}, ""}
             ]

      original = import_tei!(tei(code: "OR#{n}_Pyrame"))
      assert original_of(play) == original.id
    end

    test "is not guessed when two plays share the short code" do
      n = System.unique_integer([:positive])
      import_tei!(tei(code: "DU#{n}_Uno"))
      import_tei!(tei(code: "DU#{n}_Dos"))

      play = import_tei!(translation("TR#{n}", "DU#{n}"))

      assert original_of(play) == nil

      assert xml_elements(export_tei(play), "relatedItem") == [
               {%{"type" => "original", "target" => "DU#{n}"}, ""}
             ]
    end

    test "a re-import leaves the link alone" do
      n = System.unique_integer([:positive])
      original = import_tei!(tei(code: "OR#{n}"))
      other = import_tei!(tei(code: "OT#{n}"))
      play = import_tei!(translation("TR#{n}", "OR#{n}"))

      import_tei!(translation("TR#{n}", "OT#{n}"))

      assert original_of(play) == original.id
      refute original_of(play) == other.id
    end

    test "an original never imported leaves the play with none" do
      play = import_tei!(translation("TR#{System.unique_integer([:positive])}", "NOPE"))

      assert original_of(play) == nil
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

    # FileMaker gave 18 plays a dating only in words ("posterior 1590 y anterior 1595"),
    # and the file is where it is kept: the words come back with no year, and an
    # unusable year beside them is dropped, the words are not.
    test "a dating in words, with no usable year, keeps the words" do
      for {date, words} <- [
            {"<date>posterior 1590 y anterior 1595</date>", "posterior 1590 y anterior 1595"},
            {~s(<date notBefore="1607" notAfter="1606">entre 1606 y 1607</date>),
             "entre 1606 y 1607"}
          ] do
        assert xml_elements(roundtrip(creation(date)), "date", within: "creation") == [
                 {%{}, words}
               ],
               date
      end
    end

    # An unusable date is the file's problem, not an import failure: the play still
    # imports, only without a dating. "<date>c. 1600</date>" used to be here; words with
    # no year are now a dating in words (the test above).
    test "an unusable date imports as no dating" do
      for date <- [
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

  # FileMaker gave 108 plays a historical time. In the file it is settingDesc/setting/time,
  # the period as @type and its note as the text.
  describe "the historical time" do
    defp setting(content),
      do: tei(profile_desc: "<settingDesc><setting>#{content}</setting></settingDesc>")

    test "keeps the period, its note, or both" do
      for {time, expected} <- [
            {~s(<time type="siglo_xvi">reinado de Felipe II</time>),
             {%{"type" => "siglo_xvi"}, "reinado de Felipe II"}},
            {~s(<time type="edad_media"/>), {%{"type" => "edad_media"}, ""}},
            {"<time>tras la batalla de Lepanto</time>", {%{}, "tras la batalla de Lepanto"}}
          ] do
        assert xml_elements(roundtrip(setting(time)), "time", within: "setting") == [expected],
               time
      end
    end

    # A period Playcode does not know would fail the play's changeset and roll back the
    # whole import, so it is dropped; its words are kept.
    test "an unknown period is dropped, its words are not" do
      xml = roundtrip(setting(~s(<time type="siglo_xx">la guerra civil</time>)))
      assert xml_elements(xml, "time", within: "setting") == [{%{}, "la guerra civil"}]
    end

    test "sits beside the play's places" do
      xml =
        roundtrip(
          tei(
            profile_desc: """
            <settingDesc>
              <listPlace>
                <place xml:id="rt-ht-sevilla" type="city"><placeName>Sevilla</placeName></place>
              </listPlace>
              <setting><placeName ref="#rt-ht-sevilla" ana="setting"/><time type="siglo_xvii"/></setting>
            </settingDesc>
            """
          )
        )

      assert [{%{"ref" => "#rt-ht-sevilla"}, _}] =
               xml_elements(xml, "placeName", within: "setting")

      assert xml_elements(xml, "time", within: "setting") == [{%{"type" => "siglo_xvii"}, ""}]
    end

    test "no time, no setting" do
      assert xml_elements(roundtrip(tei()), "settingDesc") == []
    end
  end

  # A link's place as it was in this play (S9b): a place of the gazetteer, a country inside
  # the link's <placeName>, any other kind a nested <placeName>.
  describe "the historical state of a place" do
    defp state_file(state_type, link, opts \\ []) do
      tei(
        Keyword.take(opts, [:code]) ++
          [
            profile_desc: """
            <settingDesc>
              <listPlace>
                <place xml:id="rt-hs-europa" type="continent">
                  <placeName xml:lang="es">Europa</placeName>
                  <place xml:id="rt-hs-italia" type="country">
                    <placeName xml:lang="es">Italia</placeName>
                    <place xml:id="rt-hs-roma" type="city"><placeName xml:lang="es">Roma</placeName></place>
                  </place>
                  <place xml:id="rt-hs-republica-romana" type="#{state_type}">
                    <placeName xml:lang="es">República romana</placeName>
                  </place>
                </place>
              </listPlace>
              <setting>#{link}</setting>
            </settingDesc>
            """
          ]
      )
    end

    defp with_country,
      do:
        ~s(<placeName ref="#rt-hs-roma" ana="setting"><country ref="#rt-hs-republica-romana"/><note>Acto I.</note></placeName>)

    defp without_state,
      do: ~s(<placeName ref="#rt-hs-roma" ana="setting"><note>Acto I.</note></placeName>)

    defp place_ids(xml),
      do: for({%{"xml:id" => id}, _} <- xml_elements(xml, "place", within: "listPlace"), do: id)

    test "a country comes back inside the link's placeName, and the state in listPlace" do
      xml = roundtrip(state_file("country", with_country()))

      assert xml_elements(xml, "country", within: "setting") ==
               [{%{"ref" => "#rt-hs-republica-romana"}, ""}]

      assert xml_texts(xml, "note", within: "setting") == ["Acto I."]
      assert "rt-hs-republica-romana" in place_ids(xml)
    end

    test "a state that is not a country is a nested placeName" do
      link =
        ~s(<placeName ref="#rt-hs-roma" ana="setting"><placeName ref="#rt-hs-republica-romana"/></placeName>)

      xml = roundtrip(state_file("region", link))

      assert xml_elements(xml, "placeName", within: "setting") ==
               [
                 {%{"ref" => "#rt-hs-roma", "ana" => "setting"}, ""},
                 {%{"ref" => "#rt-hs-republica-romana"}, ""}
               ]

      assert xml_elements(xml, "country", within: "setting") == []
      assert "rt-hs-republica-romana" in place_ids(xml)
    end

    # The link is the file's, the state a guess: one nobody declared, or the place itself
    # (which the changeset refuses, and the link would go with it), is dropped alone.
    test "a state the file does not declare, or the place itself, is dropped, the link kept" do
      for state <- ["rt-hs-nowhere", "rt-hs-roma"] do
        link =
          ~s(<placeName ref="#rt-hs-roma" ana="setting"><country ref="##{state}"/></placeName>)

        xml = roundtrip(state_file("country", link))

        assert xml_elements(xml, "placeName", within: "setting") ==
                 [{%{"ref" => "#rt-hs-roma", "ana" => "setting"}, ""}],
               state

        assert xml_elements(xml, "country", within: "setting") == []
      end
    end

    # A place named twice is one link, the later naming refreshing the earlier (its role,
    # position and note already do), so a later one with no state clears the earlier's.
    test "a place named twice keeps what its last link says, the state too" do
      first =
        ~s(<placeName ref="#rt-hs-roma" ana="setting"><country ref="#rt-hs-republica-romana"/></placeName>)

      second = ~s(<placeName ref="#rt-hs-roma" ana="mentioned"/>)

      xml = roundtrip(state_file("country", first <> second))

      assert xml_elements(xml, "placeName", within: "setting") ==
               [{%{"ref" => "#rt-hs-roma", "ana" => "mentioned"}, ""}]

      assert xml_elements(xml, "country", within: "setting") == []
    end

    # The file is the truth for the links it wrote (every production file lacks the state):
    # a re-import clears theirs. A curator's link (origin "manual") is theirs to keep.
    test "a file without the state clears it from the file's own links, never from a curator's" do
      own = import_tei!(state_file("country", with_country(), code: "HSOWN"))
      assert [_] = xml_elements(export_tei(own), "country", within: "setting")

      own = import_tei!(state_file("country", without_state(), code: "HSOWN"))
      assert xml_elements(export_tei(own), "country", within: "setting") == []

      curated = import_tei!(state_file("country", with_country(), code: "HSCUR"))
      [link] = curated.play_places
      {:ok, _} = Playcode.Places.update_play_place(link, %{"origin" => "manual"})

      curated = import_tei!(state_file("country", without_state(), code: "HSCUR"))

      assert xml_elements(export_tei(curated), "country", within: "setting") ==
               [{%{"ref" => "#rt-hs-republica-romana"}, ""}]
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

    # The Way of the World names the actors of its first performance (1700). An empty
    # actor, as in A Midsummer Night's Dream's file, gives none.
    test "keeps the original cast's actors" do
      xml =
        roundtrip(
          tei(
            front: """
            <div type="elenco">
              <castList>
                <castItem><role xml:id="Fainall">Fainall</role><roleDesc>in love with Mrs. Marwood</roleDesc><actor>Mr.  Betterton </actor></castItem>
                <castItem><role xml:id="HIPPOLYTA">HIPPOLYTA</role><actor> </actor></castItem>
              </castList>
            </div>
            """
          )
        )

      assert xml_texts(xml, "actor") == ["Mr. Betterton"]
    end

    test "keeps its heading" do
      xml =
        roundtrip(
          tei(
            front: """
            <div type="elenco">
              <head>Hablan en ella las personas siguientes</head>
              <castList><castItem><role xml:id="DON">Don Juan</role></castItem></castList>
            </div>
            """
          )
        )

      assert xml_texts(xml, "head", within: "front") == [
               "Hablan en ella las personas siguientes"
             ]
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

  # Until 2026-10-15 any kind outside five became "nota": 285 paratexts on dev lost theirs.
  # "nota" itself, 0784's only, is a note on the digital edition, and so is a div with no
  # type (no file has one); the test that listed nota among the kept kinds said otherwise.
  test "a paratext keeps its kind, a new one included; nota is a note on the digital edition" do
    xml =
      roundtrip(
        tei(
          front: """
          <div type="nota_edicion_digital"><head>Nota a esta edición digital</head><p>Texto.</p></div>
          <div type="epistola"><head>Épître</head><p>Sire.</p></div>
          <div type="carta_al_lector"><p>Lector.</p></div>
          <div type="nota"><p>Note sur cette édition numérique.</p></div>
          <div><p>Sin tipo.</p></div>
          """
        )
      )

    assert xml |> xml_elements("div", within: "front") |> Enum.map(&elem(&1, 0)["type"]) ==
             ~w(nota_edicion_digital epistola carta_al_lector nota_edicion_digital nota_edicion_digital)
  end

  # 45 files give the scene of the action as a div; <set> is TEI's element for it.
  test "a circunstancia_accion div is the scene of the action, after the cast list" do
    xml =
      roundtrip(
        tei(
          front: """
          <div type="elenco"><castList><castItem><role xml:id="DON">Don</role></castItem></castList></div>
          <div type="circunstancia_accion"><head>The Scene:</head><p>London</p></div>
          """
        )
      )

    assert xml_texts(xml, "p", within: "set") == ["London"]
    assert xml_texts(xml, "head", within: "set") == ["The Scene:"]
    refute xml =~ "circunstancia_accion"
  end

  # The importer stores <emph> as <<…>> wherever it reads text; outside the play's lines
  # the export once wrote the markers back as characters, "&lt;&lt;Aminta&gt;&gt;".
  test "italics outside the text come back as italics" do
    xml =
      roundtrip(
        tei(
          file_desc: "<notesStmt><note>Basada en <emph>La venganza</emph>.</note></notesStmt>",
          source_desc:
            "<bibl><title><emph>Aminta</emph></title><note>Tasso. <emph>Aminta</emph>. Venezia.</note></bibl>",
          front: """
          <div type="dedicatoria"><head>A <emph>Damone</emph></head><p>Dedica <emph>Egle</emph>.</p></div>
          <div type="elenco"><head><emph>Dramatis Personae</emph></head><castList>
            <castItem><role xml:id="CORT"><emph>The courtiers</emph></role><roleDesc>(<emph>Spela</emph>), a servant</roleDesc></castItem>
          </castList></div>
          <set><p><emph>La Scena è in Atene.</emph></p></set>
          """
        )
      )

    refute xml =~ "&lt;&lt;"

    assert Enum.sort(xml_texts(xml, "emph")) ==
             Enum.sort([
               "La venganza",
               "Aminta",
               "Aminta",
               "Damone",
               "Egle",
               "Dramatis Personae",
               "The courtiers",
               "Spela",
               "La Scena è in Atene."
             ])
  end

  # The Old Wife's Tale's "SCENE: An English wood…". 15 of the 17 files that have one put it
  # right after the cast list, and emothe.uv.es prints it there; Egle's comes back there too.
  test "the scene of the action keeps its heading and paragraphs, after the cast list" do
    xml =
      roundtrip(
        tei(
          front: """
          <set><head>SCENE:</head><p>An English wood and Clunch's house on the edge of it.]<lb/></p><p>Otro.</p></set>
          <div type="elenco"><castList><castItem><role xml:id="DON">Don</role></castItem></castList></div>
          """
        )
      )

    assert xml_texts(xml, "head", within: "set") == ["SCENE:"]

    assert xml_texts(xml, "p", within: "set") == [
             "An English wood and Clunch's house on the edge of it.]",
             "Otro."
           ]

    assert xml =~ ~r{</castList>\s*</div>\s*<set>}
  end

  test "a paratext keeps its kind, heading and paragraphs" do
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

  # The Rover's epilogue and post-script, Everyman's appendices: after the text, before the
  # bibliography, as the files put them.
  test "a paratext after the text comes back after it, before the bibliography" do
    xml =
      roundtrip(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><head>ACT I</head><sp><speaker>A</speaker><p>Hola.</p></sp></div1>),
          back: """
          <div type="epilogo"><head>EPILOGUE</head><p>The banished <emph>cavaliers</emph>!</p></div>
          <div type="despedida"><head>POST-SCRIPT</head><p>This play had been sooner in print.</p></div>
          <div type="bibliografia"><listBibl type="ediciones_modernas"><biblStruct type="book"><monogr><title>T</title><imprint><date>1990</date></imprint></monogr></biblStruct></listBibl></div>
          """
        )
      )

    assert xml |> xml_elements("div", within: "back") |> Enum.map(&elem(&1, 0)["type"]) ==
             ~w(epilogo despedida bibliografia)

    assert xml_texts(xml, "head", within: "back") == ["EPILOGUE", "POST-SCRIPT"]
    assert xml_texts(xml, "emph", within: "back") == ["cavaliers"]
    refute "EPILOGUE" in xml_texts(xml, "head", within: "front")
  end

  # Two files' commendatory sonnet waits on question 30, and a cast list after the text
  # (0404, 0718) on question 29: neither is read.
  test "a sonnet or a cast list after the text is not read" do
    xml =
      roundtrip(
        tei(
          back: """
          <div type="epilogo"><head>SONNET</head><lg><l>Line one</l></lg><trailer>FIN</trailer></div>
          <div type="elenco"><castList><castItem><role xml:id="X">X</role></castItem></castList></div>
          """
        )
      )

    assert xml_elements(xml, "div", within: "back") == []
  end

  # 12 head titles and 4 notes on the digital edition are a heading alone.
  test "a paratext with a heading and no paragraphs comes back" do
    xml = roundtrip(tei(front: ~s(<div type="head_title"><head>THE MALCONTENT</head></div>)))

    assert [{%{"type" => "head_title"}, _}] = xml_elements(xml, "div", within: "front")
    assert xml_texts(xml, "head", within: "front") == ["THE MALCONTENT"]
  end

  # Question 10: every break shown. A double break, an empty line before a signature in 140
  # plays, is a new paragraph: the same gap for readers, and what a blank line means in the
  # admin's textbox.
  test "a paratext keeps its line breaks; a double break is a new paragraph" do
    xml =
      roundtrip(
        tei(
          front: """
          <div type="dedicatoria"><p>A Vuestra Excelencia<lb/>guarde Dios<lb/><lb/>Frey Lope Félix de Vega Carpio<lb/></p></div>
          """
        )
      )

    assert xml_texts(xml, "p", within: "front") ==
             ["A Vuestra Excelencia guarde Dios", "Frey Lope Félix de Vega Carpio"]

    assert xml =~ ~r{A Vuestra Excelencia\s*<lb/>\s*guarde Dios</p>}
  end

  # EMOTHE0113 (Tartuffe) heads its second placet with 302 characters.
  test "a paratext keeps a heading longer than 255 characters" do
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
                <l n="5"><stage type="delivery">[Aparte.]</stage>No seg</l>
                <l n="6"><stage type="delivery_">[Aparte.]</stage>Typo</l>
              </lg></sp>
              <sp><speaker>REY</speaker>
                <p><seg type="aside">An aside in prose</seg></p>
                <p>Normal prose.</p>
              </sp>
              """)
          )
        )

      assert xml_texts(xml, "seg") ==
               ["Square", "Round", "Bare", "No seg", "Typo", "An aside in prose"]

      assert Enum.all?(xml_elements(xml, "seg"), &match?({%{"type" => "aside"}, _}, &1))
      assert "Normal verse line" in xml_texts(xml, "l")
      assert "Normal prose." in xml_texts(xml, "p", within: "sp")
    end

    # 24 source files spell the delivery type "delivery_" (79 stage directions and 418
    # stages inside lines in dev); TEI's word is "delivery".
    test "a stage direction's kind comes back, delivery_ as delivery" do
      xml =
        roundtrip(
          tei(
            body:
              scene(~s(<stage type="exit">Vase.</stage><stage type="delivery_">A Juan.</stage>))
          )
        )

      assert xml_elements(xml, "stage") ==
               [{%{"type" => "exit"}, "Vase."}, {%{"type" => "delivery"}, "A Juan."}]
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

    # Everyman's readings (EMOTHE0460, four stages) are two italics with a note after the
    # first; the export merged them into one <emph> around the note, as it does for a
    # note inside one italic run.
    test "two italics with a note between them stay two" do
      xml =
        roundtrip(
          tei(
            body:
              scene(
                "<stage><emph>[Every man puts on the garment.]</emph><note>subst.</note>" <>
                  "<emph>[Takes the garment.]</emph></stage>"
              )
          )
        )

      for xml <- [xml, roundtrip(xml)] do
        assert xml_texts(xml, "emph") == [
                 "[Every man puts on the garment.]",
                 "[Takes the garment.]"
               ]
      end
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

    # La tragedia española's note on "Belona" is typed "video", Marta la piadosa's one
    # "nota_editor_digital": slips for a translator's and a digital editor's (question 17).
    test "a slip in a note's kind comes back as the kind it is" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><sp><speaker>A</speaker>
              <l n="1">Belona<note n="1" type="video"><p>Diosa.</p></note></l>
              <l n="2">Marta<note n="2" type="nota_editor_digital"><p>Errata.</p></note></l>
            </sp></div1>
            """
          )
        )

      assert Enum.map(xml_notes(xml), & &1.type) == ["traductor", "editor_digital"]
    end

    # Regression: EMOTHE0187's notes 2115 and 2320 open with an emphasis of nothing. It
    # was stored as "<<>>, if"; the first export wrote "<p> , if", the second "<p>, if",
    # so the export of the export differed from the first.
    test "an emphasis of nothing is dropped, and the export of the export is the same" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="1">and if<note n="2115" type="editor"><p><emph></emph>, if (OED conj. 2).</p></note> he come</l>
      </sp></div1>
      """

      first = tei(code: "EMPH1", body: body) |> roundtrip()
      second = first |> String.replace("EMPH1", "EMPH2") |> roundtrip()

      assert [%{paragraphs: [", if (OED conj. 2)."]}] = xml_notes(first)
      assert String.replace(second, "EMPH2", "EMPH1") == first
    end

    test "importing a file again replaces its notes, never doubles them" do
      path =
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<note n="1" type="editor"><p>Glosa.</p></note></l></sp></div1>)
        )
        |> write_tmp!()

      {:ok, _} = Playcode.Import.TeiImport.import_file(path)
      {:ok, play} = Playcode.Import.TeiImport.import_file(path)

      assert [%{after: "uno"}] = play |> export_tei() |> xml_notes()
    end
  end

  describe "the critical apparatus" do
    # A lemma with its own note, readings in italics, readings only with a range and the
    # entry's note, and an empty entry (Hamlet has four). No punctuation follows an </emph>:
    # the parser reads "<emph>x</emph>." as "<<x>> .", a matter of its own.
    @apparatus """
    <div1 type="jornada" n="1"><head>JORNADA PRIMERA</head>
      <sp><speaker>FENISA</speaker>
        <l n="72">mucho la hermosura llama<app type="substantive" n="908">
            <lem wit="#H">llama<note>Corrección de <emph>Hartzenbusch</emph> aceptada.</note></lem>
            <rdg wit="#P3">falta</rdg> <rdg wit="#MP">infama</rdg>
          </app>,</l>
        <l n="73">Barnardo.<app n="2"><lem wit="#Q2">Barnardo.</lem><rdg wit="#F1 #Q1"><emph>Barnardo?</emph></rdg></app> Bien</l>
        <l n="74">lovely<app type="orthographical" n="3" to="#l75"><rdg wit="#Dyce #Collier">lively</rdg><note>vv. 74-75 Faltan en <emph>Q1</emph> y Q2.</note></app> y más</l>
        <l n="75" xml:id="l75">sin nada<app n="4"/></l>
      </sp>
    </div1>
    """

    test "an entry leaves the line, which reads as the edition's text" do
      xml = roundtrip(tei(body: @apparatus))

      assert reading_texts(xml, "l") == [
               "mucho la hermosura llama,",
               "Barnardo. Bien",
               "lovely y más",
               "sin nada"
             ]

      # A reading's note is the reading's, not a note of the line.
      assert xml_notes(xml) == []
    end

    test "an entry comes back after the same word, with its readings, their notes and its own" do
      xml = roundtrip(tei(body: @apparatus))

      assert [
               %{
                 in: "l",
                 after: "mucho la hermosura llama",
                 n: "908",
                 type: "substantive",
                 to: nil,
                 readings: [
                   {"lem", "#H", "llama", "Corrección de Hartzenbusch aceptada."},
                   {"rdg", "#P3", "falta", nil},
                   {"rdg", "#MP", "infama", nil}
                 ],
                 note: nil
               },
               %{
                 after: "Barnardo.",
                 n: "2",
                 type: nil,
                 readings: [
                   {"lem", "#Q2", "Barnardo.", nil},
                   {"rdg", "#F1 #Q1", "Barnardo?", nil}
                 ]
               },
               %{
                 after: "lovely",
                 n: "3",
                 type: "orthographical",
                 to: "#l75",
                 readings: [{"rdg", "#Dyce #Collier", "lively", nil}],
                 note: "vv. 74-75 Faltan en Q1 y Q2."
               },
               %{after: "sin nada", n: "4", readings: [], note: nil}
             ] = xml_apps(xml)

      assert xml_texts(xml, "emph", within: "app") == ["Hartzenbusch", "Barnardo?", "Q1"]
    end

    test "importing a file again replaces its entries, never doubles them" do
      path = tei(body: @apparatus) |> write_tmp!()

      {:ok, _} = Playcode.Import.TeiImport.import_file(path)
      {:ok, play} = Playcode.Import.TeiImport.import_file(path)

      assert length(xml_apps(export_tei(play))) == 4
    end

    test "exporting, re-importing and exporting again changes nothing" do
      first = tei(code: "APP1", body: @apparatus) |> roundtrip()
      second = first |> String.replace("APP1", "APP2") |> roundtrip()

      assert String.replace(second, "APP2", "APP1") == first
    end

    @placed """
    <div1 type="acto" n="1"><head>ACTO<app n="1"><lem wit="#A">ACTO</lem><rdg wit="#B">JORNADA</rdg></app> I</head>
      <sp><speaker>ANA<app n="2"><rdg wit="#B">ANNA</rdg></app></speaker>
        <stage>Sale<app n="3"><rdg wit="#B">Entra</rdg></app> el rey</stage>
        <l n="1">Dijo <stage>(en voz<app n="4"><rdg wit="#B">a voces</rdg></app> baja)</stage> y calló.</l>
        <l n="2">un <emph>sueño<app n="5"><rdg wit="#B">cuento</rdg></app> breve</emph> fue</l>
        <l n="3"><stage type="delivery">(Aparte.)</stage><seg type="aside">¡Ay de mí!</seg><app n="6"><rdg wit="#B">¡Oh!</rdg></app></l>
        <l n="4">Calla, <seg type="aside">que viene<app n="7"><rdg wit="#B">llega</rdg></app></seg> el rey.</l>
        <p>Buscad<app n="8"><rdg wit="#B">Mirad</rdg></app> por todas partes.</p>
      </sp>
    </div1>
    """

    test "an entry comes back where it was: heading, speaker, stage direction, inline stage, italics, asides, prose" do
      xml = roundtrip(tei(body: @placed))

      assert reading_texts(xml, "head") == ["ACTO I"]
      assert reading_texts(xml, "speaker") == ["ANA"]
      assert reading_texts(xml, "p") == ["Buscad por todas partes."]

      # A line all aside stays so, its delivery stage dropped, though an entry follows the
      # seg: the entry is not spoken text.
      assert reading_texts(xml, "l") == [
               "Dijo (en voz baja) y calló.",
               "un sueño breve fue",
               "¡Ay de mí!",
               "Calla, que viene el rey."
             ]

      assert Enum.map(xml_apps(xml), &{&1.in, &1.after, &1.n}) == [
               {"head", "ACTO", "1"},
               {"speaker", "ANA", "2"},
               {"stage", "Sale", "3"},
               {"l", "Dijo (en voz", "4"},
               {"l", "un sueño", "5"},
               {"l", "¡Ay de mí!", "6"},
               {"l", "Calla, que viene", "7"},
               {"p", "Buscad", "8"}
             ]

      assert length(xml_elements(xml, "app", within: "emph")) == 1
      assert length(xml_elements(xml, "app", within: "seg")) == 2
    end

    # 62 of the corpus's 63 entries inside notes copy their line's (same n).
    test "a note that copies its line's entry keeps the line's words, and the entry is written once" do
      copy = ~s(<app n="388"><rdg wit="#Bevington">an</rdg><rdg wit="#Q1">and</rdg></app>)

      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="1">an#{copy} learn me that<note n="1" type="editor"><term>an#{copy} learn me that</term><p>an#{copy} learn me that: if you teach me; Q2 «ho! Who is#{copy}»</p></note></l>
      </sp></div1>
      """

      xml = roundtrip(tei(body: body))

      assert reading_texts(xml, "l") == ["an learn me that"]

      assert [
               %{
                 term: "an learn me that",
                 paragraphs: ["an learn me that: if you teach me; Q2 «ho! Who is»"]
               }
             ] =
               xml_notes(xml)

      assert [%{after: "an", n: "388"}] = xml_apps(xml)
      assert xml_elements(xml, "app", within: "note") == []
    end

    # EMOTHE0530, v. 141: n="496" is only in the note on "ne".
    test "an entry found only in a note moves into the line, just after the note" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="141">ne<note n="1" type="editor"><term>ne</term><p>1623: <emph>n’en veulent</emph>; 1632: <emph>ne veulent<app type="substantive" n="496"><lem wit="#1632">ne veulent</lem><rdg wit="#1623b #1626a">n’en veulent</rdg></app></emph>.</p></note> veulent point.</l>
      </sp></div1>
      """

      xml = roundtrip(tei(body: body))

      assert reading_texts(xml, "l") == ["ne veulent point."]
      assert [%{after: "ne", n: "1"}] = xml_notes(xml)

      assert [
               %{
                 after: "ne",
                 n: "496",
                 readings: [
                   {"lem", "#1632", "ne veulent", nil},
                   {"rdg", "#1623b #1626a", "n’en veulent", nil}
                 ]
               }
             ] = xml_apps(xml)

      # The note first, then the entry, as they were found.
      assert xml =~ ~r{<note n="1"[^>]*>.*?</note><app }s
    end

    test "every place, the copies and the moved entry: exporting, re-importing and exporting again changes nothing" do
      body = """
      #{@placed}
      <div1 type="acto" n="2"><sp><speaker>A</speaker>
        <l n="9">an<app n="388"><rdg wit="#B">an</rdg></app> learn<note n="1" type="editor"><term>an<app n="388"><rdg wit="#B">an</rdg></app> learn</term><p>Glosa.</p></note></l>
        <l n="141">ne<note n="2" type="editor"><p>Ver <emph>ne veulent<app n="496"><rdg wit="#1623b">n’en veulent</rdg></app></emph>.</p></note> veulent.</l>
      </sp></div1>
      """

      first = tei(code: "APP3", body: body) |> roundtrip()
      second = first |> String.replace("APP3", "APP4") |> roundtrip()

      assert String.replace(second, "APP4", "APP3") == first
    end

    # EMOTHE0187 n="481" and EMOTHE0560 n="1106": the entry sits in the "(Aparte)" stage that a
    # line all aside drops. The stage goes with its words; the entry is not dropped with it, it
    # stays at the line's start, where the stage was.
    test "an entry inside the delivery stage of a line all aside is kept, and comes back the same" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="1"><stage type="delivery">[Aside to Bungay<app type="substantive" n="481"><rdg wit="#Bevington">[Aside to Bungay]</rdg></app>]</stage><seg type="aside">I smell a tragedy.</seg></l>
      </sp></div1>
      """

      first = tei(code: "APP5", body: body) |> roundtrip()

      assert reading_texts(first, "l") == ["I smell a tragedy."]

      assert [
               %{
                 in: "l",
                 after: "",
                 n: "481",
                 type: "substantive",
                 readings: [{"rdg", "#Bevington", "[Aside to Bungay]", nil}]
               }
             ] =
               xml_apps(first)

      second = first |> String.replace("APP5", "APP6") |> roundtrip()
      assert String.replace(second, "APP6", "APP5") == first
    end

    # The reviewer's repro: a note inside the dropped stage copies the stage's entry. The note
    # goes with the stage; its copy is not a second entry.
    test "an entry in a dropped delivery stage is kept once when a note inside the stage copies it" do
      entry = ~s(<app n="10"><rdg wit="#B">Aparte</rdg></app>)

      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="1"><stage type="delivery">(Aparte.#{entry}<note n="1" type="editor"><p>glosa #{entry}</p></note>)</stage><seg type="aside">Adios.</seg></l>
      </sp></div1>
      """

      xml = roundtrip(tei(body: body))

      assert reading_texts(xml, "l") == ["Adios."]
      assert [%{n: "10", readings: [{"rdg", "#B", "Aparte", nil}]}] = xml_apps(xml)
    end

    # A line aside by its "(Aparte)" stage alone, no <seg>: the stage goes, the words stay.
    test "an entry in the delivery stage of a line aside with no seg is kept, and comes back the same" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>A</speaker>
        <l n="1"><stage type="delivery">(Aparte.<app n="9"><rdg wit="#B">Aparte</rdg></app>)</stage>Hola.</l>
      </sp></div1>
      """

      first = tei(code: "APP7", body: body) |> roundtrip()

      assert reading_texts(first, "l") == ["Hola."]
      assert [%{in: "l", n: "9", readings: [{"rdg", "#B", "Aparte", nil}]}] = xml_apps(first)

      second = first |> String.replace("APP7", "APP8") |> roundtrip()
      assert String.replace(second, "APP8", "APP7") == first
    end
  end

  describe "HTML typed into the text" do
    alias Playcode.PlayContent
    alias Playcode.PlayContent.{InlineMarkup, Note}

    @folio_open ~s(<code>&lt;span class="folio"&gt;</code>)
    @folio_close ~s(<code>&lt;/span&gt;</code>)
    @sup_open ~s(<code>&lt;sup&gt;</code>)
    @sup_close ~s(<code>&lt;/sup&gt;</code>)

    # The Rover wraps 40 stage directions, and the Spanish version of The Spanish Tragedy
    # the starts and ends of Additions 2-5 (across lines), in the class that hid Hamlet's
    # Folio text on the old site, and neither marks a Folio passage. The project decided
    # the words are shown (questions 6 and 7, docs/stakeholder/preguntas.html).
    test "a Folio wrapper in a file with no superscript F goes, its words stay" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACT I</head>
              <sp><speaker>BELVILE</speaker>
                <p>Who's there? <stage type="delivery">#{@folio_open}within#{@folio_close}</stage></p>
              </sp>
              <stage>#{@folio_open}Aside#{@folio_close}</stage>
              <sp><speaker>JERÓNIMO</speaker>
                <l n="80">#{@folio_open}#{@sup_open}Q4#{@sup_close}A vos, señor?</l>
                <l n="92">¡Mera nadería, señor! #{@sup_open}Q4#{@sup_close}#{@folio_close}</l>
              </sp>
            </div1>
            """
          )
        )

      refute xml =~ "folio"
      assert Enum.map(xml_inline_stages(xml), & &1.text) == ["within"]
      assert reading_texts(xml, "stage") == ["within", "Aside"]
      assert [first, last] = reading_texts(xml, "l")
      assert first =~ "A vos, señor?"
      assert last =~ "¡Mera nadería, señor!"
    end

    @f "#{@sup_open}F#{@sup_close}"

    # Hamlet's Folio passages (questions 5 and 36): the words only the 1623 Folio prints,
    # between two superscript F's. They used to stay as typed (this replaces "a file that
    # marks Folio passages with a superscript F keeps its wrappers"). A passage inside one
    # element is now the <app type="folio"> question 36 agreed, the spans gone, the words
    # spaced as the file spaces them.
    test "a passage inside one element goes back as an app the base text lacks" do
      body = """
      <div1 type="acto" n="1"><head>ACT I</head>
        <sp><speaker>HAMLET</speaker>
          <l n="316">O God, #{@folio_open}#{@f}O#{@f}#{@folio_close} God,</l>
          <l n="435">Very like#{@folio_open}#{@f}, very like#{@f}#{@folio_close}. Stayed it long?</l>
          <p n="1223">blessing, but #{@folio_open}#{@f}not#{@f}#{@folio_close} as your daughter
            <lb n="1224"/>may conceive. <seg type="aside">’A is far gone, #{@folio_open}#{@f}far gone,#{@f}#{@folio_close} and truly</seg></p>
        </sp>
        <stage type="business">Enter a king and a queen, #{@folio_open}#{@f}very lovingly,#{@f}#{@folio_close} the queen embracing</stage>
      </div1>
      """

      first = roundtrip(tei(code: "FOL1", body: body))

      refute first =~ "span"
      assert reading_texts(first, "l") == ["O God, God,", "Very like. Stayed it long?"]

      assert for(app <- xml_apps(first), do: {app.in, app.type, app.readings}) == [
               {"l", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "O", nil}]},
               {"l", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", ", very like", nil}]},
               {"p", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "not", nil}]},
               {"p", "folio", [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "far gone,", nil}]},
               {"stage", "folio",
                [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "very lovingly,", nil}]}
             ]

      # The aside keeps the Folio words inside it.
      assert [{_attrs, "’A is far gone, far gone, and truly"}] = xml_elements(first, "seg")

      second = first |> String.replace("FOL1", "FOL2") |> roundtrip()
      assert String.replace(second, "FOL2", "FOL1") == first
    end

    # 13 of Hamlet's 132 passages cross elements, the longest 14 speeches. Each element is a
    # piece with its part, written back in the file's own form until question 37 settles a
    # TEI one: one span per element, an F where the passage starts and where it ends.
    test "a passage across speeches and stage directions goes back in the file's form" do
      body = """
      <div1 type="acto" n="2"><head>ACT II</head>
        <sp><speaker>hamlet</speaker>
          <p n="1284">Then is doomsday near. #{@folio_open}#{@f}Let me question more: what have #{@folio_close}
            <lb n="1286"/>#{@folio_open}you deserved?#{@folio_close}</p>
        </sp>
        <sp><speaker>#{@folio_open}guildenstern#{@folio_close}</speaker>
          <p n="1288">#{@folio_open}Prison, my lord?#{@folio_close}</p>
        </sp>
        <sp><speaker>#{@folio_open}hamlet#{@folio_close}</speaker>
          <p n="1289">#{@folio_open}Denmark’s a prison.#{@f}#{@folio_close} But, in the beaten way</p>
        </sp>
        <stage type="entrance">Lords attendant.] #{@folio_open}#{@f}with #{@folio_close}</stage>
        <stage type="entrance">#{@folio_open}his Guard carrying torches.#{@folio_close}</stage>
        <stage type="entrance">#{@folio_open}Sound a Flourish.#{@f}#{@folio_close}</stage>
      </div1>
      """

      first = roundtrip(tei(code: "FOL7", body: body))
      span = ~s(<span class="folio">)

      assert reading_texts(first, "p") == [
               "Then is doomsday near. #{span}<sup>F</sup>Let me question more: what have you deserved?</span>",
               "#{span}Prison, my lord?</span>",
               "#{span}Denmark’s a prison.<sup>F</sup></span> But, in the beaten way"
             ]

      assert reading_texts(first, "speaker") == [
               "hamlet",
               "#{span}guildenstern</span>",
               "#{span}hamlet</span>"
             ]

      assert reading_texts(first, "stage") == [
               "Lords attendant.] #{span}<sup>F</sup>with</span>",
               "#{span}his Guard carrying torches.</span>",
               "#{span}Sound a Flourish.<sup>F</sup></span>"
             ]

      # A paragraph's own number stays its own.
      assert for({attrs, _} <- xml_elements(first, "p", within: "body"), do: attrs["n"]) ==
               ~w(1284 1288 1289)

      assert xml_apps(first) == []

      second = first |> String.replace("FOL7", "FOL8") |> roundtrip()
      assert String.replace(second, "FOL8", "FOL7") == first
    end

    # The lines of a passage are pieces like any other element, a note in one staying where
    # it was: the tags count nothing in its offset.
    test "a passage across verse lines goes back a span to a line" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>hamlet</speaker>
        <lg type="redondilla">
          <l n="10">As in a dream #{@folio_open}#{@f}that went</l>
          <l n="11">#{@folio_open}on through <note n="1"><p>A dream.</p></note>the night</l>
          <l n="12">#{@folio_open}till morning#{@f}#{@folio_close}, and so</l>
        </lg>
      </sp></div1>
      """

      first = roundtrip(tei(code: "FOL9", body: body))
      span = ~s(<span class="folio">)

      assert reading_texts(first, "l") == [
               "As in a dream #{span}<sup>F</sup>that went</span>",
               "#{span}on through the night</span>",
               "#{span}till morning<sup>F</sup></span>, and so"
             ]

      assert [%{in: "l", n: "1", after: ~s(<span class="folio">on through)}] = xml_notes(first)

      second = first |> String.replace("FOL9", "FOLA") |> roundtrip()
      assert String.replace(second, "FOLA", "FOL9") == first
    end

    # A passage may open at a speaker label and close inside the speech's own paragraph
    # (v. 3223 and 3224, the grave-diggers; the second pair below), so in the Q2 text the
    # rest of that paragraph carries no label. The speaker label is a piece like a line.
    test "a passage from a speaker label to the middle of a paragraph" do
      body = """
      <div1 type="acto" n="5"><sp><speaker>2 clown</speaker>
          <p n="3221">Was he a gentleman?</p>
        </sp>
        <sp><speaker>#{@folio_open}#{@f}2 clown#{@folio_close}</speaker>
          <p n="3223">#{@folio_open}Why, he had none.#{@folio_close}</p>
        </sp>
        <sp><speaker>#{@folio_open}1 clown#{@folio_close}</speaker>
          <p n="3224">#{@folio_open}What, art a heathen?#{@f}#{@folio_close} I’ll put another question to thee.</p>
        </sp>
        <sp><speaker>#{@folio_open}#{@f}2 clown#{@folio_close}</speaker>
          <p n="3226">#{@folio_open}Go to.#{@f}#{@folio_close} Say on.</p>
        </sp>
      </div1>
      """

      play = import_tei!(tei(code: "FOLF", body: body))
      folio = fn part, words -> ~s(<folio part="#{part}">#{words}</folio>) end

      assert [%{loaded_elements: [_, opens, middle, short]}] =
               PlayContent.load_play_content(play.id)

      assert opens.speaker_label == folio.("I", "2 clown")
      assert [%{content: ~s(<lb n="3223"/>) <> piece}] = opens.children
      assert piece == folio.("M", "Why, he had none.")

      assert middle.speaker_label == folio.("M", "1 clown")

      assert [%{content: ~s(<lb n="3224"/>) <> piece}] = middle.children
      assert piece == folio.("F", "What, art a heathen?") <> " I’ll put another question to thee."

      assert short.speaker_label == folio.("I", "2 clown")
      assert [%{content: ~s(<lb n="3226"/>) <> piece}] = short.children
      assert piece == folio.("F", "Go to.") <> " Say on."

      first = export_tei(play)
      span = ~s(<span class="folio">)

      assert reading_texts(first, "speaker") ==
               [
                 "2 clown",
                 "#{span}<sup>F</sup>2 clown</span>",
                 "#{span}1 clown</span>",
                 "#{span}<sup>F</sup>2 clown</span>"
               ]

      second = first |> String.replace("FOLF", "FOLG") |> roundtrip()
      assert String.replace(second, "FOLG", "FOLF") == first
    end

    # The texts of the play in the order a file reads them, speaker labels included.
    defp texts(play) do
      for division <- PlayContent.load_play_content(play.id),
          element <- division.loaded_elements,
          text <- element_texts(element),
          do: text
    end

    defp element_texts(%{type: "speech"} = speech),
      do: [speech | Enum.flat_map(speech.children, &element_texts/1)]

    defp element_texts(%{type: "line_group"} = group),
      do: Enum.flat_map(group.children, &element_texts/1)

    defp element_texts(element), do: [element]

    # A crossing passage is a piece in each text, and an edit may take away the piece
    # before or after one, or put a text between two. The export reads each piece's part
    # from its neighbours, so the file always closes what it opens, and the passages after
    # the edit come back as they were.
    test "a crossing passage whose last piece is deleted goes out closed where it now ends" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>hamlet</speaker>
        <l n="1">Q2 one #{@folio_open}#{@f}F open#{@folio_close}</l>
        <l n="2">#{@folio_open}F middle#{@folio_close}</l>
        <l n="3">#{@folio_open}F close#{@f}#{@folio_close} Q2 three</l>
        <l n="4">Q2 four</l>
        <l n="5">Q2 five #{@folio_open}#{@f}F2 open#{@folio_close}</l>
        <l n="6">#{@folio_open}F2 close#{@f}#{@folio_close} Q2 six</l>
      </sp></div1>
      """

      play = import_tei!(tei(code: "FOLL", body: body))
      {:ok, _} = play |> texts() |> Enum.at(3) |> PlayContent.delete_element()
      PlayContent.refresh_derived(play.id)

      first = export_tei(play)
      span = ~s(<span class="folio">)

      assert reading_texts(first, "l") == [
               "Q2 one #{span}<sup>F</sup>F open</span>",
               "#{span}F middle<sup>F</sup></span>",
               "Q2 four",
               "Q2 five #{span}<sup>F</sup>F2 open</span>",
               "#{span}F2 close<sup>F</sup></span> Q2 six"
             ]

      second = first |> String.replace("FOLL", "FOLM") |> roundtrip()
      assert String.replace(second, "FOLM", "FOLL") == first
    end

    test "a line put inside a crossing passage parts it in two" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>hamlet</speaker>
        <lg type="redondilla">
          <l n="10">As in a dream #{@folio_open}#{@f}that went</l>
          <l n="11">#{@folio_open}on through the night</l>
          <l n="12">#{@folio_open}till morning#{@f}#{@folio_close}, and so</l>
          <l n="13">Q2 #{@folio_open}#{@f}again#{@f}#{@folio_close} after</l>
        </lg>
      </sp></div1>
      """

      play = import_tei!(tei(code: "FOLN", body: body))
      [_speech, first_line | _] = texts(play)
      PlayContent.shift_element_positions(first_line.division_id, first_line.parent_id, 1)

      {:ok, _} =
        PlayContent.create_element(%{
          play_id: play.id,
          division_id: first_line.division_id,
          parent_id: first_line.parent_id,
          type: "verse_line",
          content: "A line put in",
          position: 1
        })

      PlayContent.refresh_derived(play.id)
      first = export_tei(play)
      span = ~s(<span class="folio">)

      assert reading_texts(first, "l") == [
               "As in a dream",
               "A line put in",
               "#{span}<sup>F</sup>on through the night</span>",
               "#{span}till morning<sup>F</sup></span>, and so",
               "Q2 after"
             ]

      assert for(app <- xml_apps(first), do: List.last(app.readings)) == [
               {"rdg", "#F1", "that went", nil},
               {"rdg", "#F1", "again", nil}
             ]

      second = first |> String.replace("FOLN", "FOLO") |> roundtrip()
      assert String.replace(second, "FOLO", "FOLN") == first
    end

    # A speaker label that is all of a passage's first piece (v. 3226), right after a piece
    # that goes on: deleting v. 3224 leaves "1 clown" open before "2 clown" opens again.
    test "a piece left open before a speaker label that opens a passage is closed" do
      body = """
      <div1 type="acto" n="5">
        <sp><speaker>#{@folio_open}#{@f}2 clown#{@folio_close}</speaker>
          <p n="3223">#{@folio_open}Why, he had none.#{@folio_close}</p>
        </sp>
        <sp><speaker>#{@folio_open}1 clown#{@folio_close}</speaker>
          <p n="3224">#{@folio_open}What, art a heathen?#{@f}#{@folio_close} I’ll put another question to thee.</p>
        </sp>
        <sp><speaker>#{@folio_open}#{@f}2 clown#{@folio_close}</speaker>
          <p n="3226">#{@folio_open}Go to.#{@f}#{@folio_close} Say on.</p>
        </sp>
        <sp><speaker>1 clown</speaker><p n="3227">Q2 words.</p></sp>
      </div1>
      """

      play = import_tei!(tei(code: "FOLP", body: body))
      {:ok, _} = play |> texts() |> Enum.at(3) |> PlayContent.delete_element()
      PlayContent.refresh_derived(play.id)

      first = export_tei(play)
      span = ~s(<span class="folio">)

      assert reading_texts(first, "speaker") == [
               "#{span}<sup>F</sup>2 clown</span>",
               "#{span}1 clown<sup>F</sup></span>",
               "#{span}<sup>F</sup>2 clown</span>",
               "1 clown"
             ]

      assert reading_texts(first, "p") == [
               "#{span}Why, he had none.</span>",
               "#{span}Go to.<sup>F</sup></span> Say on.",
               "Q2 words."
             ]

      second = first |> String.replace("FOLP", "FOLQ") |> roundtrip()
      assert String.replace(second, "FOLQ", "FOLP") == first
    end

    # The mirror: a stage direction that is all of a passage's last piece ("Sound a
    # Flourish."), right before a piece that closes one, once the piece opening that one
    # is deleted.
    test "a piece left closing after a stage direction that closes a passage is its own" do
      body = """
      <div1 type="acto" n="2">
        <stage type="entrance">Lords attendant.] #{@folio_open}#{@f}with #{@folio_close}</stage>
        <stage type="entrance">#{@folio_open}his Guard carrying torches.#{@folio_close}</stage>
        <stage type="entrance">#{@folio_open}Sound a Flourish.#{@f}#{@folio_close}</stage>
        <stage type="entrance">Q2 #{@folio_open}#{@f}opens#{@folio_close}</stage>
        <stage type="entrance">#{@folio_open}closes#{@f}#{@folio_close} Q2 again</stage>
        <stage type="entrance">Q2 last</stage>
      </div1>
      """

      play = import_tei!(tei(code: "FOLR", body: body))
      {:ok, _} = play |> texts() |> Enum.at(3) |> PlayContent.delete_element()
      PlayContent.refresh_derived(play.id)

      first = export_tei(play)
      span = ~s(<span class="folio">)

      assert reading_texts(first, "stage") == [
               "Lords attendant.] #{span}<sup>F</sup>with</span>",
               "#{span}his Guard carrying torches.</span>",
               "#{span}Sound a Flourish.<sup>F</sup></span>",
               "Q2 again",
               "Q2 last"
             ]

      assert for(app <- xml_apps(first), do: List.last(app.readings)) == [
               {"rdg", "#F1", "closes", nil}
             ]

      second = first |> String.replace("FOLR", "FOLS") |> roundtrip()
      assert String.replace(second, "FOLS", "FOLR") == first
    end

    # Hamlet's file has three slips in its marks: a </span> set before the passage's words
    # (v. 3057), a span opened twice (v. 1322) and a closing label typed "and" (v. 3315).
    # The labels say where each passage runs; the "and" is kept as the passage's last word
    # until the editor says otherwise (question 39).
    test "the labels, not the spans, say where a passage runs" do
      body = """
      <div1 type="acto" n="5"><sp><speaker>hamlet</speaker>
        <p n="3057">my sudden #{@folio_open}#{@f}#{@folio_close}and more strange#{@f}#{@folio_close} return.</p>
        <p n="3315">I do not lie in’t, #{@folio_open}#{@f}Oh!#{@sup_open}and#{@sup_close}#{@folio_close} yet it is mine.</p>
        <p n="1322">to th’court? #{@folio_open}#{@folio_open}#{@f}for, by my fay#{@f}#{@folio_close} I cannot</p>
      </sp></div1>
      """

      xml = roundtrip(tei(body: body))

      assert for(app <- xml_apps(xml), do: List.last(app.readings)) == [
               {"rdg", "#F1", "and more strange", nil},
               {"rdg", "#F1", "Oh! and", nil},
               {"rdg", "#F1", "for, by my fay", nil}
             ]

      assert reading_texts(xml, "p") == [
               "my sudden return.",
               "I do not lie in’t, yet it is mine.",
               "to th’court? I cannot"
             ]
    end

    # Hamlet v. 2632: a passage opened and closed inside a <stage> that sits in a paragraph.
    # A passage may hold a stage but a stage may not hold a passage, so the stage is cut
    # around the passage into three, each the stage's type again (ruling of 2026-10-17).
    # The file's spaces stay where it has them: the one after the label is the passage's,
    # the first paragraph has none before the "]".
    test "a passage inside an inline stage cuts the stage in three" do
      body = """
      <div1 type="acto" n="4"><sp><speaker>hamlet</speaker>
        <p n="2631">Safely stowed. <stage type="delivery_">[Calling within#{@folio_open}#{@f} “Hamlet, Lord Hamlet!”#{@f}#{@folio_close}]</stage>
          <lb n="2633"/>But soft.</p>
        <p n="2640"><stage type="delivery">[Calling within#{@folio_open}#{@f}“Hamlet!”#{@f}#{@folio_close}]</stage></p>
        <p n="2650">Who’s there? <stage type="delivery">#{@folio_open}#{@f}Within#{@f}#{@folio_close}</stage> Enter.</p>
      </sp></div1>
      """

      play = import_tei!(tei(code: "FOLB", body: body))
      stage = fn words -> ~s(<stage type="delivery">#{words}</stage>) end

      assert [%{loaded_elements: [%{children: [spaced, glued, whole]}]}] =
               PlayContent.load_play_content(play.id)

      assert spaced.content ==
               ~s(<lb n="2631"/>Safely stowed. ) <>
                 stage.("[Calling within") <>
                 "<folio> " <>
                 stage.("“Hamlet, Lord Hamlet!”") <>
                 "</folio>" <> stage.("]") <> ~s( <lb n="2633"/>But soft.)

      assert glued.content ==
               ~s(<lb n="2640"/>) <>
                 stage.("[Calling within") <>
                 "<folio>" <> stage.("“Hamlet!”") <> "</folio>" <> stage.("]")

      # A stage that is all passage leaves the spaces the stage had around it.
      assert whole.content ==
               ~s(<lb n="2650"/>Who’s there? <folio>) <> stage.("Within") <> "</folio> Enter."

      # The passage is an entry of the reading beside the stages it was cut from; the
      # stages say what they said.
      first = export_tei(play)

      assert for(app <- xml_apps(first), do: List.last(app.readings)) == [
               {"rdg", "#F1", "“Hamlet, Lord Hamlet!”", nil},
               {"rdg", "#F1", "“Hamlet!”", nil},
               {"rdg", "#F1", "Within", nil}
             ]

      assert for(
               {attrs, words} <- xml_elements(first, "stage", within: "body"),
               do: {attrs["type"], words}
             ) == [
               {"delivery", "[Calling within"},
               {"delivery", "“Hamlet, Lord Hamlet!”"},
               {"delivery", "]"},
               {"delivery", "[Calling within"},
               {"delivery", "“Hamlet!”"},
               {"delivery", "]"},
               {"delivery", "Within"}
             ]

      second = first |> String.replace("FOLB", "FOLC") |> roundtrip()
      assert String.replace(second, "FOLC", "FOLB") == first
    end

    # A reading that starts or ends with an element: the folio marker beside it gets no
    # space the file does not have ("tight"), and a space it has stays ("loose", and
    # "foo<folio> bar</folio>", which has no element beside it).
    test "a folio app beside an element gains no space, and keeps the one it has" do
      body = """
      <div1 type="acto" n="4"><sp><speaker>hamlet</speaker>
        <p n="1">tight <app type="folio"><lem wit="#Q2"/><rdg wit="#F1"><stage type="delivery">within</stage></rdg></app> after</p>
        <p n="2">loose <app type="folio"><lem wit="#Q2"/><rdg wit="#F1"> <stage type="delivery">within</stage> </rdg></app> after</p>
        <p n="3">foo<app type="folio"><lem wit="#Q2"/><rdg wit="#F1"> bar</rdg></app>.</p>
      </sp></div1>
      """

      play = import_tei!(tei(code: "FOLD", body: body))
      stage = ~s(<stage type="delivery">within</stage>)

      assert [%{loaded_elements: [%{children: [tight, loose, plain]}]}] =
               PlayContent.load_play_content(play.id)

      assert tight.content == ~s(<lb n="1"/>tight <folio>#{stage}</folio> after)
      assert loose.content == ~s(<lb n="2"/>loose <folio> #{stage} </folio> after)
      assert plain.content == ~s(<lb n="3"/>foo<folio> bar</folio>.)

      first = export_tei(play)
      second = first |> String.replace("FOLD", "FOLE") |> roundtrip()
      assert String.replace(second, "FOLE", "FOLD") == first
    end

    # Italics touching a passage that opens or closes in italics stay two <emph>s: merged
    # into one, the passage would be lost, its words read as the base text's.
    test "a passage in italics beside italics outside it stays a passage" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>HAMLET</speaker>
        <l n="1">O <emph>dear</emph><app type="folio"><lem wit="#Q2"/><rdg wit="#F1"><emph>mother</emph></rdg></app> mine</l>
        <l n="2">O <app type="folio"><lem wit="#Q2"/><rdg wit="#F1"><emph>mother</emph></rdg></app><emph>dear</emph> mine</l>
      </sp></div1>
      """

      first = roundtrip(tei(code: "FOLH", body: body))

      assert for(app <- xml_apps(first), do: List.last(app.readings)) == [
               {"rdg", "#F1", "mother", nil},
               {"rdg", "#F1", "mother", nil}
             ]

      assert xml_texts(first, "emph") == ["dear", "mother", "mother", "dear"]

      second = first |> String.replace("FOLH", "FOLI") |> roundtrip()
      assert String.replace(second, "FOLI", "FOLH") == first
    end

    # A note counts graphemes into the text without its markers, the Folio ones included:
    # the one after a passage stays after it.
    test "a note after a passage stays where it was" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>HAMLET</speaker>
        <l n="316">O God, #{@folio_open}#{@f}O#{@f}#{@folio_close} God,<note n="1"><p>An oath.</p></note> be</l>
      </sp></div1>
      """

      first = roundtrip(tei(code: "FOL5", body: body))

      assert [%{in: "l", after: "O God, God,", n: "1"}] = xml_notes(first)
      assert reading_texts(first, "l") == ["O God, God, be"]
    end

    # A note strictly inside a passage is one of the Folio's words' notes: it goes back
    # inside the reading, between the words it sat between.
    test "a note inside a passage stays inside its reading" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>HAMLET</speaker>
        <l n="316">O God, <app type="folio"><lem wit="#Q2"/><rdg wit="#F1">O<note n="1"><p>An oath.</p></note> O</rdg></app> God,</l>
      </sp></div1>
      """

      first = roundtrip(tei(code: "FOLJ", body: body))

      assert [%{readings: [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "O O", "An oath."}]}] =
               xml_apps(first)

      assert [{%{"wit" => "#F1"}, "O An oath. O"}] = xml_elements(first, "rdg")
      assert reading_texts(first, "l") == ["O God, God,"]

      second = first |> String.replace("FOLJ", "FOLK") |> roundtrip()
      assert String.replace(second, "FOLK", "FOLJ") == first
    end

    # The form a re-encoded file will use (question 36) reads as the same passage. An
    # <app type="folio"> of any other shape is an entry of the apparatus, kept as written:
    # read as a passage, its witness would be lost. Both come back as the same <app>, so
    # the stored lines say which was read as which: a passage is words in the line's text,
    # an entry a note of the line.
    test "the app form reads back as the passage; any other folio app stays an entry" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>HAMLET</speaker>
        <l n="316">O God, <app type="folio"><lem wit="#Q2"/><rdg wit="#F1">O</rdg></app> God,</l>
        <l n="319">Fie, <app type="folio"><lem wit="#Q2"/><rdg wit="#F2">fie,</rdg></app> ’tis</l>
      </sp></div1>
      """

      play = import_tei!(tei(code: "FOL3", body: body))
      first = export_tei(play)

      assert [
               %{type: "folio", readings: [{"lem", "#Q2", "", nil}, {"rdg", "#F1", "O", nil}]},
               %{type: "folio", readings: [{"lem", "#Q2", "", nil}, {"rdg", "#F2", "fie,", nil}]}
             ] = xml_apps(first)

      assert reading_texts(first, "l") == ["O God, God,", "Fie, ’tis"]

      assert [%{loaded_elements: [%{children: [passage, entry]}]}] =
               PlayContent.load_play_content(play.id)

      assert InlineMarkup.plain(passage.content) == "O God, O God,"
      assert passage.notes == []
      assert [%{} = variant] = entry.notes
      assert Note.variant?(variant)

      second = first |> String.replace("FOL3", "FOL4") |> roundtrip()
      assert String.replace(second, "FOL4", "FOL3") == first
    end

    # A reading with no word would be an empty passage, which the line refuses (and the
    # import with it): it stays the entry of the apparatus it was before.
    test "a folio app whose reading has no word stays an entry, and the import goes on" do
      body = """
      <div1 type="acto" n="1"><sp><speaker>HAMLET</speaker>
        <l n="316">One <app type="folio"><lem wit="#Q2"/><rdg wit="#F1"/></app> two</l>
        <l n="319">Three <app type="folio"><lem wit="#Q2"/><rdg wit="#F1"> </rdg></app> four</l>
      </sp></div1>
      """

      play = import_tei!(tei(code: "FOL6", body: body))

      assert [%{loaded_elements: [%{children: [first, second]}]}] =
               PlayContent.load_play_content(play.id)

      assert [%{type: "folio"}, %{type: "folio"}] = xml_apps(export_tei(play))
      assert InlineMarkup.plain(first.content) == "One two"
      assert InlineMarkup.plain(second.content) == "Three four"
      assert [%{}] = first.notes
      assert [%{}] = second.notes
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

    # "delivery_", a misspelling in 24 source files, used to come back as written; it is
    # read as TEI's "delivery" since 2026-10-13.
    test "a stage comes back inside its line, where it was, with its type" do
      xml = roundtrip(tei(body: @staged))

      assert Enum.map(xml_inline_stages(xml), &{&1.in, &1.type, &1.text, &1.before, &1.after}) ==
               [
                 {"l", nil, "(A Léonor.)", "", "Allez l'entretenir en cette galerie."},
                 {"l", "exit", "(Vase.)", "Je vous suis,", "adieu."},
                 {"l", "business", "(se lève)", "Il parle", "puis (sort)"},
                 {"l", nil, "(sort)", "Il parle (se lève) puis", ""},
                 {"p", nil, "Entra", "", "El rey dijo (bajo) y salió."},
                 {"p", "delivery", "(bajo)", "Entra El rey dijo", "y salió."}
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

      {:ok, _} = Playcode.Import.TeiImport.import_file(path)
      {:ok, play} = Playcode.Import.TeiImport.import_file(path)

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

  # Until 2026-10-16 a line or paragraph holding a <seg type="aside"> was read as that
  # seg's text alone: 1,092 paragraphs and 581 lines of the corpus lost every word, stage
  # and break outside it ("Sola mi basta. <seg>Basta.</seg>" read "Basta.").
  describe "a line or paragraph partly aside" do
    @partly """
    <div1 type="acto" n="1"><sp><speaker>A</speaker>
      <lg><l n="1">Sola mi basta. <seg type="aside">Basta.</seg></l></lg>
      <p>Me fouiller ? Soit. <stage type="delivery">(À part.)</stage><seg type="aside">Prends la coupe<note n="1" type="editor"><p>Dick.</p></note>, Dick.</seg><lb n="12"/>Allons ! <seg type="aside">Vite.</seg></p>
    </sp></div1>
    """

    test "keeps its other words, stages, breaks and notes, its asides marked" do
      xml = roundtrip(tei(body: @partly))

      assert xml_texts(xml, "l") == ["Sola mi basta. Basta."]

      assert xml_lines(xml, "p") ==
               [{%{}, "Me fouiller ? Soit. (À part.) Prends la coupe, Dick. [12] Allons ! Vite."}]

      assert xml_lines(xml, "seg") ==
               Enum.map(
                 ["Basta.", "Prends la coupe, Dick.", "Vite."],
                 &{%{"type" => "aside"}, &1}
               )

      assert [%{text: "(À part.)", type: "delivery"}] = xml_inline_stages(xml)
      assert xml_texts(xml, "note", within: "seg") == ["Dick."]
    end

    test "exporting, re-importing and exporting again changes nothing" do
      first = tei(code: "ASD1", body: @partly) |> roundtrip()
      second = first |> String.replace("ASD1", "ASD2") |> roundtrip()

      assert String.replace(second, "ASD2", "ASD1") == first
    end

    test "a paragraph all aside keeps the breaks between its asides" do
      xml =
        roundtrip(
          tei(
            body:
              ~s|<div1 type="acto" n="1"><sp><speaker>A</speaker><p n="51"><stage type="delivery">(Aside.)</stage><seg type="aside">Ay, marry, now there's</seg><lb n="52"/><seg type="aside">a wise man.</seg></p></sp></div1>|
          )
        )

      assert xml_lines(xml, "seg") == [
               {%{"type" => "aside"}, "Ay, marry, now there's [52] a wise man."}
             ]

      assert xml_inline_stages(xml) == []
    end
  end

  # A reference is matched on its description as the file carries it
  # (Bibliography.Entry.description/1), so a play's references must come back from its
  # file with exactly the description they went in with, and the play's own place in each.

  # Questions 9 and 10 (docs/stakeholder/preguntas.html): every break is shown, and a
  # printed line's number with it. Until 2026-10-16 each <lb/> was read as a space.
  describe "line breaks and prose line numbers" do
    defp speech(paragraphs, code \\ nil) do
      opts = [
        body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker>#{paragraphs}</sp></div1>)
      ]

      tei(if code, do: [{:code, code} | opts], else: opts)
    end

    test "a paragraph's line breaks come back where the file had them" do
      xml =
        roundtrip(
          speech(
            ~s(<p>Yo amé en mis primeros años, <lb/>dulce cosa lo juzgué; <lb/>pero casarme.</p>)
          )
        )

      assert xml_lines(xml, "p") ==
               [{%{}, "Yo amé en mis primeros años, | dulce cosa lo juzgué; | pero casarme."}]
    end

    test "a printed line's number and a paragraph's number come back as written" do
      xml =
        roundtrip(
          speech(
            ~s(<p n="1319">Beggar that I am, <lb n="1320"/>but I thank you, <lb n="1311-2"/>my thanks.</p>)
          )
        )

      assert xml_lines(xml, "p") ==
               [
                 {%{"n" => "1319"},
                  "Beggar that I am, [1320] but I thank you, [1311-2] my thanks."}
               ]
    end

    test "a number right after a paragraph's own stays a break inside it" do
      xml = roundtrip(speech(~s(<p n="5"><lb n="6"/>Uno.</p>)))

      assert xml_lines(xml, "p") == [{%{"n" => "5"}, "[6] Uno."}]
    end

    test "a break that opens a paragraph comes back" do
      xml = roundtrip(speech(~s(<p><lb/>Fausto maledetto!</p>)))

      assert xml_lines(xml, "p") == [{%{}, "| Fausto maledetto!"}]
    end

    test "a break inside italics, inside a stage and inside a note comes back there" do
      xml =
        roundtrip(
          speech(
            ~s|<p>Dijo <emph>sic <lb/>probo</emph> y <stage>(canta <lb/>bajo)</stage> fin<note n="1" type="editor"><p>Una glosa <lb/>en dos líneas.</p></note>.</p>|
          )
        )

      assert xml_lines(xml, "p") == [{%{}, "Dijo sic | probo y (canta | bajo) fin."}]
      assert xml_lines(xml, "emph") == [{%{}, "sic | probo"}]
      assert xml_lines(xml, "stage") == [{%{}, "(canta | bajo)"}]
      assert xml_lines(xml, "p", in_notes: true) == [{%{}, "Una glosa | en dos líneas."}]
    end

    test "a note just after a break keeps its place, and no space follows the break" do
      xml =
        roundtrip(
          # The space between the break and the note is what makes the note "spaced".
          speech(~s(<p>Uno, <lb/> <note n="1" type="editor"><p>Glosa.</p></note>dos.</p>))
        )

      assert [%{n: "1", after: "Uno,"}] = xml_notes(xml)
      assert xml_lines(xml, "p") == [{%{}, "Uno, | dos."}]
      # Stored "Uno,\ndos.", as many characters as "Uno, dos." before: no space after the
      # break, so none after the note either.
      assert xml =~ "<lb/><note"
      assert xml =~ "</note>dos."
    end

    # Regression: EMOTHE0299's note n=4171 is <p><lb/></p> and nothing else. Its body was
    # "\n", which Note.changeset refuses as blank, and the whole play failed to import.
    test "a note that holds nothing but a break is dropped, and the play still imports" do
      xml =
        roundtrip(speech(~s(<p>Uno<note n="1" type="editor"><p><lb/></p></note> dos.</p>)))

      assert xml_notes(xml) == []
      assert xml_lines(xml, "p") == [{%{}, "Uno dos."}]
    end

    test "exporting, re-importing and exporting again changes nothing" do
      body =
        ~s(<p n="7">Uno, <lb/>dos <lb n="8"/>tres<note n="1" type="editor"><p>Glosa <lb/>larga.</p></note>.</p><p><lb/>Cuatro <emph>cinco <lb/>seis</emph>.</p>)

      first = speech(body, "LBR1") |> roundtrip()
      second = first |> String.replace("LBR1", "LBR2") |> roundtrip()

      assert String.replace(second, "LBR2", "LBR1") == first
    end
  end

  describe "the bibliography" do
    alias Playcode.Bibliography
    alias Playcode.Bibliography.Entry
    alias Playcode.Import.TeiImport

    @every_field %{
      "language" => "es",
      "analytic_author" => "Autor, A",
      # A non-breaking space, as FileMaker left in titles ("The Alchemist : A…"), here and
      # in each monogr_title, so neither title finds the entry unless it is collapsed.
      "analytic_title" => "Capítulo\u00a0<<en cursiva>>",
      "analytic_editors" => "Editor, Analítico",
      # Italics with punctuation right after them, as FileMaker wrote "<<Adonis y Venus>>:
      # hacia la tragedia…": no space may come in between.
      "original_title" => "<<Adonis y Venus>>: hacia la tragedia",
      "series" => "Serie <<Clásicos>>, segunda",
      "public_note" => "Véase <<Fenisa>>.",
      "analytic_translators" => "Traductor, Analítico",
      "monogr_author" => "Autor, M",
      # Several people in one field, as FileMaker keeps them, with the separators it uses:
      # "; ", " ; " (9 fields in dev) and ";" (2).
      "monogr_editors" => "Morris, Brian ; Gill, Roma",
      "monogr_translators" => "Traductor, T;Otra, O",
      "edition" => "2nd",
      "volume" => "2",
      "volumes_total" => "4",
      "issue" => "3",
      "pages" => "1-20",
      "pub_place" => "Madrid",
      "publisher" => "Cátedra  Letras",
      "year_text" => "1957-75",
      "url" => "https://example.org",
      "url_accessed_on" => "2020-01-01",
      "note" => "Solo para investigadores"
    }

    # Every publication type with every field, the play's own volume and pages, and an
    # entry with no type and a URL that is no address: 11 references.
    defp fill_bibliography(play) do
      for {type, i} <- Enum.with_index(Entry.pub_types()) do
        bibliography_fixture(
          play,
          Map.merge(@every_field, %{
            "kind" => Enum.at(Entry.kinds(), rem(i, 4)),
            "pub_type" => type,
            "monogr_title" => "Libro\u00a0#{i}",
            "siglum" => "S#{i}"
          }),
          %{"volume" => "#{i + 1}", "pages" => "#{i}-#{i + 9}"}
        )
      end

      # Italics as a curator may type them: two runs touching, an empty one, a space
      # inside. The export merges, drops and keeps them as InlineMarkup reads them, and
      # the reference must still be recognised from its file.
      bibliography_fixture(play, %{
        "kind" => "adaptation",
        "pub_type" => nil,
        "monogr_title" => "<<Solo>><<un>> título<<>> y <<Foo >>bar",
        "url" => ". http://emothe.uv.es/x.php"
      })

      play
    end

    defp bibl_struct(title, cited \\ "") do
      ~s(<biblStruct type="libro"><monogr><author>Autor, Ana</author>) <>
        ~s(<title level="m">#{title}</title><imprint><date/></imprint></monogr>#{cited}</biblStruct>)
    end

    defp with_bibliography(code, lists) do
      lists =
        for {type, structs} <- lists,
            do: ~s(<listBibl type="#{type}">#{Enum.join(structs)}</listBibl>)

      tei(code: code, back: ~s(<div type="bibliografia">#{Enum.join(lists)}</div>))
    end

    defp references(play) do
      for link <- Bibliography.list_links(play.id),
          do: {Entry.description(link.entry), link.volume, link.pages, link.origin}
    end

    # Sorted: links made in the same second list in no fixed order.
    defp titles(play) do
      play.id
      |> Bibliography.list_links()
      |> Enum.map(&{&1.entry.monogr_title, &1.pages, &1.origin})
      |> Enum.sort()
    end

    test "a play rebuilt from its file gets every reference back, as the file's" do
      n = System.unique_integer([:positive])
      play = fill_bibliography(import_tei!(tei(code: "BIB#{n}")))
      xml = export_tei(play)

      before =
        for {description, volume, pages, _} <- references(play),
            do: {description, volume, pages, "tei"}

      # The entries go with their last link, as in an installation that never had them.
      for link <- Bibliography.list_links(play.id), do: {:ok, _} = Bibliography.unlink(link)

      copy = import_tei!(String.replace(xml, "BIB#{n}", "BIC#{n}"))

      assert Enum.sort(references(copy)) == Enum.sort(before)

      assert Enum.all?(
               Bibliography.list_links(copy.id),
               &(is_nil(&1.note) and is_nil(&1.entry.note))
             )
    end

    test "importing a play's own export again adds nothing" do
      play = fill_bibliography(import_tei!(tei(code: "BIB#{System.unique_integer([:positive])}")))
      xml = export_tei(play)

      assert {:ok, %{bibliography_adds: []}} = TeiImport.preview_import(write_tmp!(xml))

      import_tei!(xml)
      assert length(Bibliography.list_links(play.id)) == 11
    end

    # A curator's Enter in the printed note: the export writes it as <lb/>, which the
    # reader took for nothing, so "Véase\nFenisa." came back "VéaseFenisa." and the
    # reference no longer matched its entry.
    test "a printed note with a line break is still recognised on re-import" do
      play = import_tei!(tei(code: "BIB#{System.unique_integer([:positive])}"))

      bibliography_fixture(
        play,
        Map.merge(@every_field, %{
          "kind" => "criticism",
          "monogr_title" => "Libro",
          "public_note" => "Véase\n<<Fenisa>>."
        })
      )

      xml = export_tei(play)

      assert xml =~ "Véase<lb/><emph>Fenisa</emph>."
      assert {:ok, %{bibliography_adds: []}} = TeiImport.preview_import(write_tmp!(xml))
    end

    # FileMaker keeps several people in one field; TEI gives each person an element.
    test "several people in one field are one element each, and one field again" do
      play =
        import_tei!(tei(code: "BIP#{System.unique_integer([:positive])}"))
        |> bibliography_fixture(%{
          "monogr_author" => "Uno, Ana; Dos, Berta",
          "monogr_editors" => "Morris, Brian ; Gill, Roma",
          "monogr_translators" => "Tres, C;Cuatro, D"
        })
        |> then(&Playcode.Catalogue.get_play!(&1.play_id))

      xml = export_tei(play)

      assert xml_texts(xml, "author", within: "monogr") == ["Uno, Ana", "Dos, Berta"]

      assert xml_elements(xml, "editor", within: "monogr") == [
               {%{}, "Morris, Brian"},
               {%{}, "Gill, Roma"},
               {%{"role" => "translator"}, "Tres, C"},
               {%{"role" => "translator"}, "Cuatro, D"}
             ]

      # Rebuilt from the file: the original entry gone, so the copy's is read from it.
      for link <- Bibliography.list_links(play.id), do: {:ok, _} = Bibliography.unlink(link)

      copy =
        import_tei!(String.replace(xml, play.code, "BIQ#{System.unique_integer([:positive])}"))

      assert [%{entry: entry}] = Bibliography.list_links(copy.id)

      assert {entry.monogr_author, entry.monogr_editors, entry.monogr_translators} ==
               {"Uno, Ana; Dos, Berta", "Morris, Brian; Gill, Roma", "Tres, C; Cuatro, D"}
    end

    # Seven source files (EMOTHE0310, 0451, 0488…) give their bibliography as prose: those
    # paragraphs must not become references.
    test "a bibliography in prose gives no references" do
      play =
        import_tei!(
          tei(
            back:
              ~s(<div type="bibliografia"><p><emph>Autoridades</emph>: Real Academia Española. ) <>
                ~s(<emph>Diccionario de Autoridades</emph>. Madrid: Gredos, 1963.</p></div>)
          )
        )

      assert Bibliography.list_links(play.id) == []
    end

    test "one reference in two plays' files is one entry with two links" do
      n = System.unique_integer([:positive])
      play = fill_bibliography(import_tei!(tei(code: "BIB#{n}")))

      copy = import_tei!(String.replace(export_tei(play), "BIB#{n}", "BIC#{n}"))

      entry_ids =
        &(&1.id
          |> Bibliography.list_links()
          |> Enum.map(fn link -> link.entry_id end)
          |> Enum.sort())

      assert entry_ids.(copy) == entry_ids.(play)
    end

    test "a re-import adds a reference new to its file and changes nothing else" do
      code = "BIR#{System.unique_integer([:positive])}"
      play = import_tei!(with_bibliography(code, critica: [bibl_struct("Uno")]))
      bibliography_fixture(play, %{"monogr_title" => "A mano"})

      import_tei!(
        with_bibliography(code,
          critica: [
            bibl_struct("Uno"),
            bibl_struct("Dos", ~s(<citedRange unit="page">3-4</citedRange>))
          ]
        )
      )

      assert titles(play) == [
               {"A mano", nil, "manual"},
               {"Dos", "3-4", "tei"},
               {"Uno", nil, "tei"}
             ]
    end

    # The one way a duplicate gets in: the file's old version no longer matches the
    # corrected entry. The import preview lists it before the import is confirmed.
    test "an older file brings back the old version of a corrected reference, beside it" do
      code = "BIR#{System.unique_integer([:positive])}"
      file = with_bibliography(code, critica: [bibl_struct("Uno")])
      play = import_tei!(file)
      [link] = Bibliography.list_links(play.id)
      {:ok, _} = Bibliography.update_entry(link.entry, %{"monogr_title" => "Uno, corregido"})

      import_tei!(file)

      assert titles(play) == [{"Uno", nil, "tei"}, {"Uno, corregido", nil, "tei"}]
    end

    test "a reference that cannot be an entry, or comes twice, does not stop the import" do
      play =
        import_tei!(
          with_bibliography("BIR#{System.unique_integer([:positive])}",
            desconocida: [bibl_struct("Sin tipo")],
            critica: [
              bibl_struct("Uno"),
              bibl_struct("Uno"),
              ~s(<biblStruct><monogr><imprint><date/></imprint></monogr></biblStruct>)
            ]
          )
        )

      assert titles(play) == [{"Uno", nil, "tei"}]
    end
  end

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

    # This test used to assert the opposite: the export wrote the FileMaker record number
    # as <idno type="filemaker"> and the import made the witness FileMaker's again. A TEI
    # file names no FileMaker or Playcode identifier (decided 2026-10-13): the record
    # number stays in the installation FileMaker was imported into.
    test "a FileMaker witness's file names no FileMaker record, and comes back as the file's" do
      play = import_tei!(tei(code: "WIT#{System.unique_integer([:positive])}"))

      {:ok, _} =
        Playcode.Witnesses.create_witness(
          %{"play_id" => play.id, "title" => "Octava parte", "origin" => "filemaker"},
          %Playcode.Witnesses.Witness{filemaker_id: "T03:36"}
        )

      xml = export_tei(play)

      refute xml =~ "T03:36"
      assert xml_elements(xml, "idno", within: "witness") == []

      copy =
        import_tei!(String.replace(xml, play.code, "WIT#{System.unique_integer([:positive])}"))

      assert [%{title: "Octava parte", filemaker_id: nil, origin: "tei"}] =
               Playcode.Witnesses.list_for_play(copy.id)
    end

    # FileMaker's line breaks, kept as \r: the lines of a title page, a note's paragraphs.
    # Stored as \n with no spaces around them, and a run of spaces or a tab as one space
    # (which is all any page prints), so the file gives back what it was given.
    test "a witness's line breaks come back, its runs of spaces as one" do
      play = import_tei!(tei(code: "WIT#{System.unique_integer([:positive])}"))

      {:ok, _} =
        Playcode.Witnesses.create_witness(%{
          "play_id" => play.id,
          "title" => "ORBECCHE TRAGEDIA \rDI M. GIOVANBATTISTA",
          "note" => "Esemplare\tconsultato.\r\n\r\nBIBL.:  ADAMS 1967"
        })

      expected = %{
        title: "ORBECCHE TRAGEDIA\nDI M. GIOVANBATTISTA",
        note: "Esemplare consultato.\n\nBIBL.: ADAMS 1967"
      }

      xml = export_tei(play)
      assert length(xml_elements(xml, "lb", within: "witness")) == 3

      copy =
        import_tei!(String.replace(xml, play.code, "WIT#{System.unique_integer([:positive])}"))

      for p <- [play, copy] do
        assert [witness] = Playcode.Witnesses.list_for_play(p.id)
        assert Map.take(witness, [:title, :note]) == expected
      end
    end

    test "exporting, re-importing and exporting again changes nothing" do
      first =
        tei(code: "WIT1", source_desc: "<bibl><title>Base</title></bibl>" <> @list_wit)
        |> roundtrip()

      second = first |> String.replace("WIT1", "WIT2") |> roundtrip()

      assert String.replace(second, "WIT2", "WIT1") == first
    end
  end

  # A play's performances (S5) are in the file as <performance>s of the front, after the
  # cast list and the scene. They name their company, actors and source by what they are,
  # never by an id; a re-import replaces the file's own and leaves the rest.
  describe "performances" do
    alias Playcode.Performances

    @performance_places """
    <settingDesc>
      <listPlace>
        <place xml:id="rt-perf-europa" type="continent">
          <placeName xml:lang="es">Europa</placeName>
          <place xml:id="rt-perf-inglaterra" type="country">
            <placeName xml:lang="es">Inglaterra</placeName>
            <place xml:id="rt-perf-londres" type="city"><placeName xml:lang="es">Londres</placeName></place>
          </place>
          <place xml:id="rt-perf-reino" type="country"><placeName xml:lang="es">Reino de Inglaterra</placeName></place>
        </place>
      </listPlace>
    </settingDesc>
    """

    @cast_list ~s(<div type="elenco"><castList><castItem><role xml:id="BLAS">Blas</role><actor>Mr. Betterton</actor></castItem></castList></div>)

    # A company's name is unique across the corpus, so two async tests naming one queue
    # behind each other: every name here is made unique.
    defp unique_company, do: "The King’s Men #{System.unique_integer([:positive])}"

    # The performance as the export writes it, so that the file and its round trip compare
    # element for element.
    defp performance_xml(company, corresp \\ "") do
      """
      <performance xml:id="performance-1"#{corresp}>
        <p>
          <date notAfter="1611" notBefore="1609">1609-11</date>
          <rs subtype="commercial_theatre" type="venue">Globe or <emph>Blackfriars</emph></rs>
          <placeName ref="#rt-perf-londres"><country ref="#rt-perf-reino"/></placeName>
          <orgName>#{company}</orgName>
        </p>
        <castList>
          <castItem><role><emph>Argan</emph></role><actor sex="M"><persName><forename>Jean François</forename><surname>Poquelin</surname><addName type="nickname">Molière</addName></persName></actor></castItem>
        </castList>
        <note>The play was <emph>hissed</emph> occasionally.</note>
        <biblStruct ana="catalogos">
          <monogr>
            <title level="m">British Drama 1533–1642: A Catalogue</title>
            <imprint><pubPlace>Oxford</pubPlace><publisher>Oxford University Press</publisher><date>2012–</date></imprint>
          </monogr>
          <citedRange unit="volume">6</citedRange>
          <citedRange unit="page">83</citedRange>
        </biblStruct>
      </performance>
      """
    end

    defp performance_file(front, opts \\ []),
      do: tei(Keyword.merge([front: front, profile_desc: @performance_places], opts))

    defp performances(play), do: Performances.list_for_play(play.id)

    test "a performance comes back with every field" do
      company = unique_company()
      file = performance_file(performance_xml(company))
      play = import_tei!(file)

      assert [performance] = performances(play)

      assert %{
               date_text: "1609-11",
               year_from: 1609,
               year_to: 1611,
               venue: "Globe or <<Blackfriars>>",
               venue_type: "commercial_theatre",
               note: "The play was <<hissed>> occasionally.",
               source_volume: "6",
               source_pages: "83",
               cast_from_cast_list: false,
               origin: "tei",
               filemaker_id: nil
             } = performance

      assert performance.company.name == company

      assert {performance.place.slug,
              Playcode.Places.get_place(performance.historical_state_id).slug} ==
               {"rt-perf-londres", "rt-perf-reino"}

      assert [
               %{
                 role: "<<Argan>>",
                 actor: %{
                   surname: "Poquelin",
                   forename: "Jean François",
                   nickname: "Molière",
                   sex: "man"
                 }
               }
             ] = performance.cast

      assert %{
               kind: "catalogue",
               monogr_title: "British Drama 1533–1642: A Catalogue",
               pub_place: "Oxford",
               publisher: "Oxford University Press",
               year_text: "2012–"
             } = performance.source

      xml = export_tei(play)

      assert xml_elements(xml, "performance") == xml_elements(file, "performance")
      assert xml_texts(xml, "orgName", within: "performance") == [company]

      # The date of the performance, and the one in its source's imprint.
      assert xml_elements(xml, "date", within: "performance") ==
               [{%{"notBefore" => "1609", "notAfter" => "1611"}, "1609-11"}, {%{}, "2012–"}]

      assert xml_elements(xml, "rs", within: "performance") ==
               [
                 {%{"type" => "venue", "subtype" => "commercial_theatre"}, "Globe or Blackfriars"}
               ]

      assert xml_elements(xml, "placeName", within: "performance") ==
               [{%{"ref" => "#rt-perf-londres"}, ""}]

      assert xml_elements(xml, "country", within: "performance") ==
               [{%{"ref" => "#rt-perf-reino"}, ""}]

      assert xml_texts(xml, "emph", within: "performance") == ["Blackfriars", "Argan", "hissed"]
      assert [{%{"sex" => "M"}, _}] = xml_elements(xml, "actor", within: "performance")

      assert xml_elements(xml, "citedRange", within: "performance") ==
               [{%{"unit" => "volume"}, "6"}, {%{"unit" => "page"}, "83"}]

      assert [{%{"ana" => "catalogos"}, _}] =
               xml_elements(xml, "biblStruct", within: "performance")

      # The place and its state are in the file's gazetteer, though no <setting> names them.
      assert {"rt-perf-londres" in place_ids(xml), "rt-perf-reino" in place_ids(xml)} ==
               {true, true}

      assert xml_elements(xml, "setting") == []
    end

    test "exporting, re-importing and exporting again changes nothing" do
      first =
        performance_file(performance_xml(unique_company()), code: "RTP1")
        |> roundtrip()

      assert [_] = xml_elements(first, "performance")

      second = first |> String.replace("RTP1", "RTP2") |> roundtrip()

      assert String.replace(second, "RTP2", "RTP1") == first
    end

    test "a company, an actor and a source already in Playcode are reused, not copied" do
      name = unique_company()
      {:ok, company} = Performances.find_or_create_company(name)

      {:ok, actor} =
        Performances.find_or_create_actor(%{
          "surname" => "Poquelin",
          "forename" => "Jean François",
          "nickname" => "Molière",
          "sex" => "man"
        })

      source =
        catalogue_fixture(%{
          "monogr_title" => "British Drama 1533–1642: A Catalogue",
          "pub_place" => "Oxford",
          "publisher" => "Oxford University Press",
          "year_text" => "2012–"
        })

      play = import_tei!(performance_file(performance_xml(name)))

      assert [performance] = performances(play)
      assert performance.company_id == company.id
      assert [%{actor_id: actor_id}] = performance.cast
      assert actor_id == actor.id
      assert performance.source_entry_id == source.id

      assert Enum.count(Performances.list_companies(), &(&1.name == name)) == 1
      assert length(Performances.list_actors()) == 1
    end

    test "the cast-list switch comes back, and the cast list it names is marked" do
      file =
        performance_file(
          @cast_list <> performance_xml(unique_company(), ~s( corresp="#castlist"))
        )

      play = import_tei!(file)

      assert [%{cast_from_cast_list: true}] = performances(play)

      xml = export_tei(play)

      assert [{%{"corresp" => "#castlist"}, _}] = xml_elements(xml, "performance")
      assert [{%{"xml:id" => "castlist"}, _}] = xml_elements(xml, "castList", within: "div")
    end

    test "a cast list no performance names is left as it was" do
      play = import_tei!(performance_file(@cast_list <> performance_xml(unique_company())))

      assert [%{cast_from_cast_list: false}] = performances(play)

      xml = export_tei(play)

      assert [{%{} = list, _}] = xml_elements(xml, "castList", within: "div")
      assert [{%{} = performance, _}] = xml_elements(xml, "performance")
      refute Map.has_key?(list, "xml:id")
      refute Map.has_key?(performance, "corresp")

      # A play with no performance at all has the cast list as before.
      xml = roundtrip(tei(front: @cast_list))
      assert [{list, _}] = xml_elements(xml, "castList", within: "div")
      assert list == %{}
    end

    test "a source cited by a performance stays out of the play's bibliography" do
      play = import_tei!(performance_file(performance_xml(unique_company())))

      assert [%{source_entry_id: id}] = performances(play)
      assert id
      assert Playcode.Bibliography.list_for_play(play.id) == []
    end

    test "a source keeps its kind, and a file that names none cites a criticism" do
      for {ana, kind} <- [
            {"catalogos", "catalogue"},
            {"ediciones_modernas", "modern_edition"},
            {"critica", "criticism"},
            {"traducciones", "translation"},
            {"adaptaciones", "adaptation"},
            {nil, "criticism"}
          ] do
        written = if ana, do: ~s( ana="#{ana}"), else: ""
        source = String.replace(performance_xml(unique_company()), ~s( ana="catalogos"), written)
        play = import_tei!(performance_file(source))

        assert [%{source: %{kind: ^kind}}] = performances(play), inspect(ana)

        expected = ana || "critica"
        assert [{%{"ana" => ^expected}, _}] = xml_elements(export_tei(play), "biblStruct")
      end
    end

    test "a performance of a note alone is valid TEI shape and comes back" do
      xml =
        roundtrip(
          tei(
            front:
              ~s(<performance xml:id="performance-1"><p/><note>Solo una nota.</note></performance>)
          )
        )

      assert [{%{"xml:id" => "performance-1"}, "Solo una nota."}] =
               xml_elements(xml, "performance")

      assert xml_elements(xml, "p", within: "performance") == [{%{}, ""}]
    end

    test "a venue type alone is an empty rs, and a date as words is a date with no years" do
      play =
        import_tei!(
          tei(
            front: """
            <performance xml:id="performance-1">
              <p><date>desconocida</date><rs type="venue" subtype="palace"/></p>
            </performance>
            """
          )
        )

      assert [
               %{
                 date_text: "desconocida",
                 year_from: nil,
                 year_to: nil,
                 venue: nil,
                 venue_type: "palace"
               }
             ] =
               performances(play)

      xml = export_tei(play)

      assert xml_elements(xml, "rs", within: "performance") ==
               [{%{"type" => "venue", "subtype" => "palace"}, ""}]

      assert xml_elements(xml, "date", within: "performance") == [{%{}, "desconocida"}]
    end

    test "a venue type that is not one of the eight is dropped, the venue kept" do
      play =
        import_tei!(
          tei(
            front:
              ~s(<performance xml:id="performance-1"><p><rs type="venue" subtype="mansion">Casa de campo</rs></p></performance>)
          )
        )

      assert [%{venue: "Casa de campo", venue_type: nil}] = performances(play)
    end

    test "the years come from the date's attributes, else from its words" do
      for {date, years, attrs} <- [
            {~s(<date when="1610">1610</date>), {1610, 1610}, %{"when" => "1610"}},
            {~s(<date notAfter="1642">Before 1642</date>), {nil, 1642}, %{"notAfter" => "1642"}},
            {~s(<date notBefore="1608" notAfter="1612">c. 1610</date>), {1608, 1612},
             %{"notBefore" => "1608", "notAfter" => "1612"}},
            {"<date>c. 1620</date>", {1620, 1620}, %{"when" => "1620"}}
          ] do
        play =
          import_tei!(
            tei(front: ~s(<performance xml:id="performance-1"><p>#{date}</p></performance>))
          )

        assert [%{year_from: from, year_to: to}] = performances(play)
        assert {from, to} == years, date

        assert [{^attrs, _}] = xml_elements(export_tei(play), "date", within: "performance")
      end
    end

    test "a place or a state the file does not declare is dropped, the performance kept" do
      play =
        import_tei!(
          tei(
            front: """
            <performance xml:id="performance-1">
              <p><date when="1610">1610</date><placeName ref="#rt-perf-nowhere"><country ref="#rt-perf-nowhere-either"/></placeName></p>
            </performance>
            """
          )
        )

      assert [%{date_text: "1610", place_id: nil, historical_state_id: nil}] = performances(play)
    end

    test "a state with no town comes back as a state with no town" do
      play =
        import_tei!(
          performance_file(
            ~s(<performance xml:id="performance-1"><p><date when="1610">1610</date><placeName><country ref="#rt-perf-reino"/></placeName></p></performance>)
          )
        )

      assert [%{place_id: nil, historical_state_id: state_id}] = performances(play)
      assert Playcode.Places.get_place(state_id).slug == "rt-perf-reino"

      xml = export_tei(play)

      assert xml_elements(xml, "placeName", within: "performance") == [{%{}, ""}]

      assert xml_elements(xml, "country", within: "performance") ==
               [{%{"ref" => "#rt-perf-reino"}, ""}]
    end

    # The performance is the file's, the source a guess: one that names nothing is no entry,
    # and the pages in it go with it.
    test "a source that names nothing is left out, the performance kept" do
      play =
        import_tei!(
          tei(
            front: """
            <performance xml:id="performance-1">
              <p><date when="1610">1610</date></p>
              <biblStruct ana="catalogos"><monogr><title level="m"/></monogr><citedRange unit="page">83</citedRange></biblStruct>
            </performance>
            """
          )
        )

      assert [%{date_text: "1610", source_entry_id: nil, source_pages: nil}] = performances(play)
    end

    test "a cast row that names no actor is dropped, the performance kept" do
      play =
        import_tei!(
          tei(
            front: """
            <performance xml:id="performance-1">
              <p><date when="1610">1610</date></p>
              <castList>
                <castItem><role>Sin actor</role></castItem>
                <castItem><role>Solo nombre</role><actor><persName><forename>Jean</forename></persName></actor></castItem>
                <castItem><role>Con apodo</role><actor><persName><addName type="nickname">Molière</addName></persName></actor></castItem>
              </castList>
            </performance>
            """
          )
        )

      assert [%{cast: [%{role: "Con apodo", actor: %{nickname: "Molière", sex: nil}}]}] =
               performances(play)
    end

    # Review Focus 2 of the spec: the file replaces what it wrote, never what a curator or
    # FileMaker did.
    test "a re-import replaces the file's performances and keeps the others" do
      code = "RTP#{System.unique_integer([:positive])}"
      play = import_tei!(tei(code: code))

      filemaker =
        performance_fixture(play, %{
          "date_text" => "1600",
          "venue" => "Corral del Príncipe",
          "origin" => "filemaker"
        })

      company = unique_company()

      # The same company as the file's, written in another case: companies are found
      # ignoring it, so the two performances are one to a reader.
      manual =
        performance_fixture(play, %{
          "date_text" => "1605",
          "venue" => "Corral de la Cruz",
          "venue_type" => "public_theatre",
          "company_name" => String.downcase(company)
        })

      identical =
        ~s(<performance xml:id="performance-1"><p><date when="1605">1605</date><rs type="venue" subtype="public_theatre">Corral de la Cruz</rs><orgName>#{company}</orgName></p></performance>)

      other = unique_company()

      new =
        ~s(<performance xml:id="performance-2"><p><date when="1610">1610</date><orgName>#{other}</orgName></p></performance>)

      play = import_tei!(tei(code: code, front: identical <> new))

      assert [
               %{origin: "filemaker", id: filemaker_id},
               %{origin: "manual", id: manual_id},
               %{origin: "tei", date_text: "1610"}
             ] = performances(play)

      assert {filemaker_id, manual_id} == {filemaker.id, manual.id}
      assert Enum.any?(Performances.list_companies(), &(&1.name == other))

      # A file with none: the file's own is gone, with the company only it named.
      play = import_tei!(tei(code: code))

      assert [%{origin: "filemaker"}, %{origin: "manual"}] = performances(play)
      refute Enum.any?(Performances.list_companies(), &(&1.name == other))
    end

    # The file the export writes holds the play's every performance, FileMaker's among them:
    # read back into the same play, those the play keeps must be told from their copies in it,
    # whatever they hold (a place with its state, a cast, a source with its pages).
    test "re-importing its own export keeps a play's performances, once" do
      play = import_tei!(tei(code: "RTP#{System.unique_integer([:positive])}"))
      place = place_fixture(%{"name" => "Londres"})
      state = place_fixture(%{"name" => "Reino de Inglaterra", "type" => "country"})

      kept =
        performance_fixture(play, %{
          "date_text" => "1609-11",
          "venue" => "Globe or <<Blackfriars>>",
          "venue_type" => "commercial_theatre",
          "company_name" => unique_company(),
          "place_id" => place.id,
          "historical_state_id" => state.id,
          "note" => "Hissed,\ncomplete with <<italics>>.",
          "source_volume" => "6",
          "source_pages" => "83",
          "origin" => "filemaker",
          "source_entry" => %{
            "kind" => "catalogue",
            "monogr_title" => "British Drama 1533–1642: A <<Catalogue>>",
            "public_note" => "Copyright DICAT."
          },
          "cast" => [
            %{
              "surname" => "Poquelin",
              "nickname" => "Molière",
              "sex" => "man",
              "role" => "Argan"
            },
            %{"nickname" => "Mlle du Parc"}
          ]
        })

      file = export_tei(play)
      assert [_] = xml_elements(file, "performance")

      for _ <- 1..2 do
        play = file |> import_tei!()
        assert [%{id: id, origin: "filemaker"}] = performances(play)
        assert id == kept.id
      end
    end

    test "a file's performance that differs from one the play keeps in its source alone is kept too" do
      code = "RTP#{System.unique_integer([:positive])}"
      play = import_tei!(tei(code: code))

      performance_fixture(play, %{
        "date_text" => "1605",
        "source_volume" => "6",
        "source_entry" => %{"kind" => "catalogue", "monogr_title" => "Wiggins"}
      })

      same_date = fn title ->
        ~s(<performance xml:id="performance-1"><p><date when="1605">1605</date></p><biblStruct ana="catalogos"><monogr><title level="m">#{title}</title></monogr><citedRange unit="volume">6</citedRange></biblStruct></performance>)
      end

      assert [_] = performances(import_tei!(tei(code: code, front: same_date.("Wiggins"))))
      assert [_, _] = performances(import_tei!(tei(code: code, front: same_date.("CATCOM"))))
    end

    test "a file's cast-list switch yields to one a performance the play keeps already has" do
      code = "RTP#{System.unique_integer([:positive])}"
      play = import_tei!(tei(code: code))

      kept =
        performance_fixture(play, %{
          "date_text" => "1600",
          "cast_from_cast_list" => true,
          "origin" => "manual"
        })

      file =
        ~s(<performance xml:id="performance-1" corresp="#castlist"><p><date when="1610">1610</date></p></performance>)

      play = import_tei!(tei(code: code, front: file))

      assert [%{id: id, cast_from_cast_list: true}, %{origin: "tei", cast_from_cast_list: false}] =
               performances(play)

      assert id == kept.id
    end
  end

  # An aside or a stage is set apart from the words beside it, and the punctuation after it
  # was too: "Dimmi (ti priego) , dimmi", in 302 production texts (found 2026-10-18).
  describe "punctuation right after an aside or a stage" do
    test "keeps close, the words before still set apart" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><head>I</head><sp><speaker>A</speaker>
              <l n="1">Dimmi <seg type="aside">(ti priego)</seg>, dimmi</l>
              <l n="2">Señor <stage>(Dentro)</stage>, acudid</l>
              <l n="3">Ya<stage>(Vase.)</stage>.</l>
            </sp></div1>
            """
          )
        )

      assert reading_texts(xml, "l") == [
               "Dimmi (ti priego), dimmi",
               "Señor (Dentro), acudid",
               "Ya (Vase.)."
             ]
    end
  end

  # The importer joined the pieces of a text with a space, so `un <emph>sueño</emph>, fue`
  # read "un sueño , fue": 4,470 times in 271 production files (found 2026-10-18).
  describe "italics right before punctuation" do
    test "keep the punctuation close, in a line, a paragraph and a dedication" do
      xml =
        roundtrip(
          tei(
            front:
              ~s(<div type="dedicatoria"><head>D</head><p>Al <emph>lector</emph>, con afecto.</p></div>),
            body: """
            <div1 type="acto" n="1"><head>I</head><sp><speaker>A</speaker>
              <l n="1">un <emph>sueño</emph>, fue</l>
              <p>Prosa <emph>cursiva</emph>; y más.</p>
            </sp></div1>
            """
          )
        )

      assert reading_texts(xml, "l") == ["un sueño, fue"]
      assert reading_texts(xml, "p") == ["Prosa cursiva; y más."]
      assert xml =~ "<emph>lector</emph>, con afecto."
    end

    test "a space at an italic's own edge stays, and none appears where the file has none" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><head>I</head><sp><speaker>A</speaker>
              <l n="1">Uno<emph> dos</emph></l>
              <l n="2">tres<emph>cuatro</emph></l>
            </sp></div1>
            """
          )
        )

      assert reading_texts(xml, "l") == ["Uno dos", "trescuatro"]
    end

    # Glued to a stage or a printed line's number, an italic is still set apart from it:
    # only words and other italics are glued (found by the branch's review).
    test "an italic beside an inline stage or a line number is still set apart" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><head>I</head><sp><speaker>A</speaker>
              <l n="1"><stage>(Cantan:)</stage><emph>A pescar salió</emph></l>
              <l n="2"><emph>dos</emph><lb n="5"/>tres</l>
            </sp></div1>
            """
          )
        )

      assert reading_texts(xml, "l") == ["(Cantan:) A pescar salió", "dos tres"]
    end

    # The export merged adjacent italic runs, the importer having parted them with a space;
    # glued, they now come back as two, the same each time.
    test "two italics side by side stay two, and a second round trip changes nothing" do
      body =
        ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1"><emph>a</emph><emph>b</emph>, c</l></sp></div1>)

      first = tei(code: "GLU1", body: body) |> roundtrip()
      second = first |> String.replace("GLU1", "GLU2") |> roundtrip()

      assert first =~ "<emph>a</emph><emph>b</emph>, c"
      assert String.replace(second, "GLU2", "GLU1") == first
    end

    # EMOTHE0488 glues italics that end in a break: its export was no XML at all (found by
    # the branch's review), and so was a note after a break inside one italic.
    test "an italic ending in a break, glued to the next, exports as well-formed XML" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><sp><speaker>A</speaker>
              <p><emph>a<lb/></emph><emph>b</emph></p>
              <p><emph>c<lb/>d<note n="1" type="editor"><p>N.</p></note> e</emph></p>
            </sp></div1>
            """
          )
        )

      assert xml_lines(xml, "p") == [{%{}, "a | b"}, {%{}, "c | d e"}]
    end

    test "a note inside an italic right before punctuation keeps its place" do
      xml =
        roundtrip(
          tei(
            body: """
            <div1 type="acto" n="1"><sp><speaker>A</speaker>
              <l n="1">un <emph>sueño<note n="1" type="editor"><p>Nota.</p></note></emph>, fue</l>
            </sp></div1>
            """
          )
        )

      assert reading_texts(xml, "l") == ["un sueño, fue"]
      assert [%{after: "un sueño", in: "l"}] = xml_notes(xml)
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
