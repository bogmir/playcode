defmodule Playcode.Import.TeiImportTest do
  @moduledoc """
  What the TEI importer does that its export cannot show: how it fails, which
  encodings it reads, and the rules it applies to the gazetteer and to editor
  roles. Everything a TEI file says that survives into the export is asserted in
  test/playcode/tei_roundtrip_test.exs instead.
  """
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers

  alias Playcode.Catalogue
  alias Playcode.Import.TeiImport
  alias Playcode.Outline
  alias Playcode.Places
  alias Playcode.PlayContent
  alias Playcode.Statistics

  describe "a file that cannot become a play" do
    test "a missing file is reported as such" do
      assert {:error, :enoent} = TeiImport.import_file("/nonexistent/file.xml")
    end

    test "malformed XML is a parse error" do
      assert {:error, {:xml_parse_error, _}} = TeiImport.import_file(write_tmp!("<not valid>>>"))
    end

    test "XML without a teiHeader is refused" do
      for xml <- ["<TEI><text><body></body></text></TEI>", "<html><body><p>Hi</p></body></html>"] do
        assert {:error, :missing_tei_header} = TeiImport.import_file(write_tmp!(xml))
      end
    end

    test "a teiHeader with no title fails validation" do
      xml = "<TEI><teiHeader></teiHeader><text><body></body></text></TEI>"

      assert {:error, %Ecto.Changeset{} = changeset} = TeiImport.import_file(write_tmp!(xml))
      assert "can't be blank" in errors_on(changeset).title
    end

    # Nothing of a file is kept when one of its rows is refused: not the play, not the
    # rows written before it. A stage direction is a stage already, so the changeset
    # refuses a <stage> marker in one.
    test "a row the database refuses rolls the whole import back" do
      code = "TROLLBACK#{System.unique_integer([:positive])}"

      body =
        ~s(<div1 type="acto" n="1"><head>I</head><stage>&lt;stage&gt;Sale.&lt;/stage&gt;</stage></div1>)

      assert {:error, {:element_create_failed, :stage_direction, %Ecto.Changeset{}}} =
               TeiImport.import_file(write_tmp!(tei(code: code, body: body)))

      assert_raise Ecto.NoResultsError, fn -> Catalogue.get_play_by_code!(code) end
    end
  end

  # One statement per row made a big play's import thousands of round trips (7,565 for
  # AL0788), all inside the one transaction production's 60-second timeout covers.
  describe "the outline" do
    # A paratext by its kind, a division by its type, in outline order.
    defp outline_kinds(play) do
      play.id
      |> Catalogue.list_paratexts()
      |> Outline.items(PlayContent.list_top_divisions(play.id))
      |> Enum.map(&(Map.get(&1, :kind) || &1.type))
    end

    test "every cast list comes in where its file has it, each with its own entries" do
      play = import_tei!(outline_xml())
      lists = PlayContent.list_cast_lists(play.id)

      assert Enum.map(lists, fn list -> Enum.map(list.entries, & &1.name) end) == [
               ["ANA", "BLAS", "CRISPÍN", "Músicos"],
               ["ANA, disfrazada"],
               ["DIEGO"],
               ["BLAS"],
               ["CRISPÍN"]
             ]

      assert Enum.map(lists, & &1.title) == [
               "PERSONAS",
               "Personas del acto primero",
               "Sale de nuevo",
               "Personas del acto segundo",
               "Personas que no hablan"
             ]

      [first | _] = lists
      assert Enum.map(first.entries, & &1.group_heading) == [nil, "Criados", "Criados", nil]
      assert List.last(first.entries).character_id == nil

      [act | _] = Enum.filter(PlayContent.list_top_divisions(play.id), &(&1.type == "acto"))

      assert Enum.map(act.children, &{&1.type, &1.position}) ==
               [{"elenco", 0}, {"escena", 1}, {"elenco", 2}, {"escena", 3}]

      assert [{"ANA", "dama"}, {"BLAS", nil}, {"CRISPÍN", nil}, {"DIEGO", nil}] =
               for(c <- PlayContent.list_characters(play.id), do: {c.name, c.description})
    end

    test "paratexts, the scene, lists and divisions take one order, the file's" do
      play = import_tei!(outline_xml())

      assert outline_kinds(play) ==
               ~w(dedicatoria lugar_accion elenco head_title acto elenco loa acto epilogo elenco)
    end

    test "a re-import leaves a hand-added paratext where it stood" do
      xml = outline_xml()
      play = import_tei!(xml)

      # The loa's number: the paratext stands between the list and the loa once the loa
      # moves on.
      {:ok, _} =
        Catalogue.create_paratext(%{
          play_id: play.id,
          kind: "nota_edicion_digital",
          heading: "A mano",
          origin: "manual",
          position: 6
        })

      play = import_tei!(xml)

      assert outline_kinds(play) ==
               ~w(dedicatoria lugar_accion elenco head_title acto elenco nota_edicion_digital
                  loa acto epilogo elenco)
    end

    test "a re-import of a file with an empty front div keeps a hand-added paratext" do
      xml =
        tei(
          front: """
          <div type="dedicatoria"></div>
          <div type="dedicatoria"></div>
          """,
          body: ~s(<div1 type="acto" n="1"><head>ACTO</head></div1>)
        )

      play = import_tei!(xml)

      {:ok, _} =
        Catalogue.create_paratext(%{
          play_id: play.id,
          kind: "nota_edicion_digital",
          heading: "A mano",
          origin: "manual",
          position: 0
        })

      assert outline_kinds(import_tei!(xml)) == ~w(nota_edicion_digital acto)
    end

    test "a role whose xml:id the file already gave is an entry for that character" do
      play =
        import_tei!(
          tei(
            front: """
            <div type="elenco"><castList>
              <castItem><role xml:id="ANA">ANA</role></castItem>
            </castList></div>
            <div type="elenco"><castList>
              <castItem><role xml:id="ANA">ANA, otra vez</role></castItem>
            </castList></div>
            """
          )
        )

      assert [%{name: "ANA"}] = PlayContent.list_characters(play.id)

      assert [[{"ANA", id}], [{"ANA, otra vez", id}]] =
               for(
                 list <- PlayContent.list_cast_lists(play.id),
                 do: Enum.map(list.entries, &{&1.name, &1.character_id})
               )
    end
  end

  test "the queries an import makes do not grow with the length of its text" do
    front = """
    <div type="elenco"><castList>
      <castItem><role xml:id="ANA">Ana</role></castItem>
      <castItem><role xml:id="BLAS">Blas</role></castItem>
    </castList></div>
    """

    block = """
    <sp who="#ANA #BLAS"><speaker>ANA Y BLAS</speaker>
      <lg type="redondilla"><l n="1">Uno<note n="1" type="editor"><p>Nota.</p></note></l><l n="2">dos</l></lg>
      <p>Prosa.</p></sp>
    <stage>Sale.</stage>
    """

    queries = fn copies ->
      body =
        ~s(<div1 type="acto" n="1"><head>I</head><div2 type="escena" n="1"><head>1</head>) <>
          String.duplicate(block, copies) <> "</div2></div1>"

      xml = tei(front: front, body: body)
      count_queries(fn -> {:ok, _play} = TeiImport.import_file(write_tmp!(xml)) end)
    end

    assert queries.(1) == queries.(20)
  end

  test "a UTF-16 LE file with a BOM imports" do
    xml = tei(title: "UTF16 Test", code: "UTF16LE")
    utf16 = <<0xFF, 0xFE>> <> :unicode.characters_to_binary(xml, :utf8, {:utf16, :little})

    assert {:ok, play} = TeiImport.import_file(write_tmp!(utf16))
    assert Catalogue.get_play!(play.id).title == "UTF16 Test"
  end

  test "a header-only file, with no <text>, imports as a play without content" do
    xml = """
    <TEI>
      <teiHeader>
        <fileDesc>
          <titleStmt><title>Header Only</title></titleStmt>
          <publicationStmt><idno>HEADERONLY01</idno></publicationStmt>
        </fileDesc>
      </teiHeader>
    </TEI>
    """

    assert {:ok, play} = TeiImport.import_file(write_tmp!(xml))
    assert Catalogue.get_play_by_code!("HEADERONLY01").title == "Header Only"
    assert play.id == Catalogue.get_play_by_code!("HEADERONLY01").id
  end

  # import_file/1 used to return the play as it stood before the verse count was
  # recomputed from the imported lines, so its caller saw the header's <extent>
  # (3500) while the database held the real count (0).
  test "the play it returns is the play as stored" do
    xml = tei(file_desc: "<extent>3500 versos</extent>")

    assert {:ok, returned} = TeiImport.import_file(write_tmp!(xml))
    stored = Catalogue.get_play!(returned.id)

    assert {returned.verse_count, returned.is_verse} == {stored.verse_count, stored.is_verse}
    assert {stored.verse_count, stored.is_verse} == {0, false}
  end

  test "respStmt wording decides the editor's role, in titleStmt and editionStmt alike" do
    xml =
      tei(
        title_stmt: """
        <respStmt><resp>Edición electrónica</resp><persName>Editor Person</persName></respStmt>
        <respStmt><resp>Revisión del texto</resp><persName>Reviewer Person</persName></respStmt>
        <respStmt><resp>Electronic edition</resp><persName>Digital Person</persName></respStmt>
        """,
        file_desc: """
        <editionStmt>
          <respStmt><resp>Edición crítica</resp><persName>Edition Editor</persName></respStmt>
          <respStmt><resp>Revisión</resp><persName>Edition Reviewer</persName></respStmt>
          <respStmt><resp>Codificación</resp><persName>Edition Encoder</persName></respStmt>
        </editionStmt>
        """
      )

    roles = xml |> import_tei!() |> Map.fetch!(:editors) |> Map.new(&{&1.person_name, &1.role})

    assert roles == %{
             "Editor Person" => "editor",
             "Reviewer Person" => "reviewer",
             "Digital Person" => "digital_editor",
             "Edition Editor" => "editor",
             "Edition Reviewer" => "reviewer",
             "Edition Encoder" => "digital_editor"
           }
  end

  describe "places" do
    @places_tei """
    <?xml version="1.0" encoding="UTF-8"?>
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xml:lang="es">
      <teiHeader>
        <fileDesc>
          <titleStmt><title>Play With Places</title><title key="archivo">PLACES0001</title></titleStmt>
          <publicationStmt><p/></publicationStmt>
          <sourceDesc><p/></sourceDesc>
        </fileDesc>
        <profileDesc>
          <langUsage><language ident="es-ES">Español</language></langUsage>
          <settingDesc>
            <listPlace>
              <place xml:id="europa" type="continent">
                <placeName xml:lang="es">Europa</placeName>
                <place xml:id="italia" type="country">
                  <placeName xml:lang="es">Italia</placeName>
                  <place xml:id="roma" type="city">
                    <placeName xml:lang="es">Roma</placeName>
                    <placeName xml:lang="en">Rome</placeName>
                    <placeName xml:lang="la" type="historical">Roma Aeterna</placeName>
                    <location><geo>41.9028 12.4964</geo></location>
                    <idno type="wikidata">Q220</idno>
                  </place>
                  <place xml:id="miseno" type="town">
                    <placeName xml:lang="it">Miseno</placeName>
                  </place>
                </place>
              </place>
            </listPlace>
            <setting>
              <placeName ref="#roma" ana="setting"/>
              <placeName ref="#miseno" ana="mentioned"><note>Named, not staged.</note></placeName>
            </setting>
          </settingDesc>
        </profileDesc>
      </teiHeader>
      <text><body><div1 type="acto" n="1"><head>Acto I</head></div1></body></text>
    </TEI>
    """

    defp import_places! do
      {:ok, play} = TeiImport.import_file(write_tmp!(@places_tei))
      play
    end

    defp place(slug), do: Enum.find(Places.list_places(), &(&1.slug == slug))

    test "every place in listPlace enters the gazetteer, with names and containment" do
      import_places!()

      roma = Places.get_place!(place("roma").id)

      assert {roma.type, roma.latitude, roma.longitude} == {"city", 41.9028, 12.4964}
      assert {roma.authority, roma.authority_id} == {"wikidata", "Q220"}

      names = Map.new(roma.names, &{&1.language, &1})
      assert {names["es"].name, names["en"].name} == {"Roma", "Rome"}
      assert names["la"].is_historical

      assert Places.ancestors(roma, Places.gazetteer()) |> Enum.map(& &1.slug) ==
               ["europa", "italia"]
    end

    test "only the places named in <setting> become the play's places" do
      play = import_places!()

      links = Places.list_play_places(play.id)

      assert Enum.map(links, &{&1.place.slug, &1.role, &1.note}) == [
               {"roma", "setting", nil},
               {"miseno", "mentioned", "Named, not staged."}
             ]
    end

    test "a place already in the gazetteer is used, not overwritten" do
      curated =
        Playcode.TestFixtures.place_fixture(%{
          "name" => "Roma",
          "slug" => "roma",
          "type" => "region",
          "note" => "Curated"
        })

      import_places!()

      reloaded = Places.get_place!(curated.id)
      assert {reloaded.type, reloaded.note} == {"region", "Curated"}
    end

    test "a re-import replaces its own links and leaves hand-entered ones alone" do
      play = import_places!()

      # One hand-entered link to a place the file does not name, and one to a place
      # it does: the second takes the collision branch rather than a blind insert.
      atenas = Playcode.TestFixtures.place_fixture(%{"name" => "Atenas"})
      Playcode.TestFixtures.play_place_fixture(play, atenas, %{"origin" => "manual"})

      [roma_link | _] = Places.list_play_places(play.id)
      {:ok, _} = Places.unlink_place(roma_link)

      {:ok, _} =
        Places.link_place(play.id, place("roma").id, %{
          "role" => "mentioned",
          "note" => "Hand-entered.",
          "origin" => "manual"
        })

      # Twice: an origin flipped to "tei" by the first re-import would be swept away
      # by the second.
      import_places!()
      import_places!()

      links = Map.new(Places.list_play_places(play.id), &{&1.place.slug, {&1.origin, &1.note}})

      assert links[atenas.slug] == {"manual", nil}
      assert links["roma"] == {"manual", "Hand-entered."}
      assert links["miseno"] == {"tei", "Named, not staged."}
    end
  end

  # The statistics cache outlived a re-import, so the play's statistics kept the old
  # text's numbers.
  test "a re-import replaces the play's statistics" do
    code = "TSTATS#{System.unique_integer([:positive])}"

    body = fn lines ->
      ~s(<div1 type="acto" n="1"><head>ACTO</head><div2 type="escena" n="1"><sp><speaker>A</speaker><lg>#{lines}</lg></sp></div2></div1>)
    end

    {:ok, play} =
      TeiImport.import_file(write_tmp!(tei(code: code, body: body.(~s(<l n="1">Uno</l>)))))

    assert Statistics.get_statistics(play.id).data["total_verses"] == 1

    {:ok, _} =
      TeiImport.import_file(
        write_tmp!(tei(code: code, body: body.(~s(<l n="1">Uno</l><l n="2">Dos</l>))))
      )

    assert Statistics.get_statistics(play.id).data["total_verses"] == 2
  end

  # The queries `fun` makes from this process, counted through the repo's telemetry.
  defp count_queries(fun) do
    id = make_ref()
    counter = :counters.new(1, [])

    :telemetry.attach(
      id,
      [:playcode, :repo, :query],
      &__MODULE__.count_query/4,
      {self(), counter}
    )

    try do
      fun.()
    after
      :telemetry.detach(id)
    end

    :counters.get(counter, 1)
  end

  @doc false
  def count_query(_event, _measurements, _metadata, {pid, counter}),
    do: if(self() == pid, do: :counters.add(counter, 1, 1))
end
