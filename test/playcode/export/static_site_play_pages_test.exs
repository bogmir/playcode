defmodule Playcode.Export.StaticSitePlayPagesTest do
  @moduledoc "A play's other pages in the static site: statistics, notes, stage directions, the title page, textual variants."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers
  import Playcode.StaticSitePlayHelpers
  import Playcode.TestFixtures

  describe "the statistics page" do
    test "a verse play its curator calls prose measures its characters in words" do
      play = import_tei!(tei(body: two_acts()))
      {:ok, play} = Playcode.Catalogue.update_play(play, %{form: "prose"})
      dir = generate!([play], all: true)

      assert LazyHTML.text(page(dir, play, "statistics.html")) =~ "most words"
    end

    test "shows the metrical synopsis, the characters and who shares the stage" do
      {play, dir} = publish!(two_acts())
      stats = page(dir, play, "statistics.html")

      assert rows(stats, "#synopsis tbody tr") == [
               ["I", "Redondilla", "1–5", "5"],
               ["I", "Unmarked", "6", "1"]
             ]

      # Each form with its share, not a family of forms (removed 2026-10-19, question 16).
      assert stats |> LazyHTML.query("#synopsis li") |> Enum.map(&squish(LazyHTML.text(&1))) ==
               ["Redondilla 5 vv. · 83%", "Unmarked 1 vv. · 17%"]

      characters = rows(stats, "#characters tbody tr")
      assert Enum.map(characters, &hd/1) == ["Segismundo", "Criado 2", "Clarín", "Clotaldo"]
      assert ["Segismundo", "1", "5" | _] = hd(characters)
      assert "I, 1" in hd(characters)
      assert "Redondilla" in hd(characters)

      assert texts(stats, "#presence tbody th") == [
               "Segismundo",
               "Criado 2",
               "Clarín",
               "Clotaldo"
             ]

      assert stats |> LazyHTML.query("#presence td[title]") |> Enum.count() == 3
      assert LazyHTML.text(stats) =~ "metrical passages"

      # A filled cell states its line count in text, not only in a tooltip.
      assert stats
             |> LazyHTML.query("#presence td[title]")
             |> Enum.map(&squish(LazyHTML.text(&1)))
             |> Enum.sort() ==
               ["1 line", "1 line", "5 lines"]
    end

    test "a mixed play shows its scenes, shared verses, asides and prose, act by act and scene by scene" do
      {play, dir} = publish!(mixed_play())

      for {ui, labels} <- [
            {"en", ["scenes", "shared verses", "asides", "prose passages"]},
            {"es", ["escenas", "versos compartidos", "apartes", "pasajes en prosa"]}
          ] do
        stats = html!(dir, "plays/#{play.code}/statistics.html", ui)
        tiles = Map.new(Enum.zip(texts(stats, "#tiles dt"), texts(stats, "#tiles dd")))
        assert labels |> Enum.map(&tiles[&1]) == ["2", "1", "1", "1"], ui
      end

      stats = page(dir, play, "statistics.html")

      assert texts(stats, "#divisions thead th") ==
               ["Act or scene", "Verses", "Speeches", "Speaking characters", "Prose passages"]

      assert rows(stats, "#divisions tbody tr") == [
               ["Acto I", "2", "3", "2", "1"],
               ["Escena 1", "2", "2", "2", "0"],
               ["Escena 2", "0", "1", "1", "1"],
               ["Acto II", "1", "1", "1", "0"]
             ]

      assert html!(dir, "plays/#{play.code}/statistics.html", "es")
             |> texts("#divisions h2") == ["Por acto y escena"]
    end

    test "a verse play with no scenes has a row per act, named if untitled, and no prose column; one act, no table" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>
        <div1 type="acto" n="2">
          <sp><speaker>B</speaker><l n="2">dos</l><l n="3">tres</l></sp></div1>
        """)

      stats = page(dir, play, "statistics.html")

      assert texts(stats, "#divisions thead th") ==
               ["Act or scene", "Verses", "Speeches", "Speaking characters"]

      assert rows(stats, "#divisions tbody tr") == [
               ["Acto I", "1", "1", "1"],
               ["Acto 2", "2", "1", "1"]
             ]

      refute "scenes" in texts(stats, "#tiles dt")

      {play, dir} =
        publish!(~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>))

      assert dir |> page(play, "statistics.html") |> LazyHTML.query("#divisions") |> Enum.empty?()
    end

    # Regression: both tables stopped at 12; Arden has 18, and a reader counting words needs all.
    test "the characters table and who shares the stage list every speaking character" do
      speeches = for i <- 1..13, do: "<sp><speaker>P#{i}</speaker><p>Hola.</p></sp>"
      {play, dir} = publish!(~s(<div1 type="acto" n="1"><head>Acto I</head>#{speeches}</div1>))

      stats = page(dir, play, "statistics.html")

      assert length(rows(stats, "#characters tbody tr")) == 13
      assert length(rows(stats, "#presence tbody tr")) == 13
    end

    # Regression: King Lear showed Edgar's first speech as "I" (prose) and Lear's as
    # "I, 34" (which scene?) under "First words", and an empty "Main forms" column.
    test "says in which act, scene and line each character first speaks" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <div2 type="escena" n="1"><head>Escena 1</head>
            <sp><speaker>KENT</speaker><p n="1">I thought the King had more affected the Duke.</p></sp>
            <sp><speaker>LEAR</speaker><lg type="free"><l n="2">Attend the lords of France.</l></lg></sp>
          </div2>
          <div2 type="escena" n="2"><head>Escena 2</head>
            <sp><speaker>EDGAR</speaker><p n="144">How now, brother Edmund?</p></sp>
          </div2>
        </div1>
        """)

      stats = page(dir, play, "statistics.html")
      first = Map.new(rows(stats, "#characters tbody tr"), &{hd(&1), List.last(&1)})

      assert first == %{"KENT" => "I.1, 1", "LEAR" => "I.1, 2", "EDGAR" => "I.2, 144"}

      # No verse names its form, so no character has a main form to show.
      assert texts(stats, "#characters thead th") ==
               ["Character", "Speeches", "Lines", "Words", "Share of the play", "First speaks"]
    end

    test "a passage of verses with no number names no range" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>ANA</speaker>
            <lg type="redondilla"><l n="1">uno</l><l n="2">dos</l></lg>
            <lg type="romance"><l>canta</l><l>la niña</l></lg>
          </sp>
        </div1>
        """)

      stats = page(dir, play, "statistics.html")

      assert stats |> LazyHTML.query("#synopsis .pass") |> LazyHTML.attribute("title") ==
               ["Redondilla · vv. 1–2 · 2 verses", "Romance · 2 verses"]

      assert stats |> LazyHTML.query("#presence thead th[title]") |> LazyHTML.attribute("title") ==
               ["Redondilla · vv. 1–2", "Romance"]
    end

    test "a play in prose has no synopsis and measures its characters in words" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>ANA</speaker><p>Buenos días, señor.</p></sp>
          <sp><speaker>JUAN</speaker><p>Hola.</p></sp>
        </div1>
        """)

      stats = page(dir, play, "statistics.html")

      assert stats |> LazyHTML.query("#synopsis") |> Enum.empty?()

      assert [["ANA", "1", "0", "3" | _], ["JUAN", "1", "0", "1" | _]] =
               rows(stats, "#characters tbody tr")

      assert LazyHTML.text(stats) =~ "most words"
      refute "verses" in texts(stats, "#tiles dt")
      assert "prose passages" in texts(stats, "#tiles dt")
    end
  end

  describe "the Notes page" do
    setup do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I<note n="1" type="sin_tipo"><p>Del encabezado.</p></note></head>
          <sp><speaker>ANA<note n="2" type="editor"><p>La dama.</p></note></speaker>
            <l n="1">Nous voyent<note n="3" type="traductor"><term>voyent</term><p>Forma arcaica.</p><p>Dos sílabas.</p></note> dans la ville</l>
            <l n="2">Ni un ratón se ha movido.<note n="4" type="traductor"><p>Expresión de soldado.</p></note></l>
          </sp>
        </div1>
        """)

      %{play: play, dir: dir, notes: page(dir, play, "notes.html")}
    end

    test "lists every note: number, type, glossed word, where it is, and its text", %{
      notes: notes
    } do
      items = LazyHTML.query(notes, "ol[data-notes] > li")

      assert LazyHTML.attribute(items, "value") == ["1", "2", "3", "4"]

      # A type with no label of its own (sin_tipo here, or none) is a plain Note. It was
      # latinismo, then falta_tipo, which the import reads as the play's usual kind since
      # question 17's answer.
      assert LazyHTML.attribute(items, "data-type") == [
               "other",
               "editor",
               "traductor",
               "traductor"
             ]

      # The type, the word glossed (the term, else the word before the note), where.
      assert texts(notes, "ol[data-notes] > li > p:first-child") == [
               "Note I Acto I",
               "Editor's note ANA I, 1",
               "Translator's note voyent I, 1",
               "Translator's note movido I, 2"
             ]

      assert texts(notes, "ol[data-notes] > li > p + p") == [
               "Del encabezado.",
               "La dama.",
               "Forma arcaica.",
               "Dos sílabas.",
               "Expresión de soldado."
             ]
    end

    test "links each note to its marker on the page that shows it", %{
      play: play,
      dir: dir,
      notes: notes
    } do
      links = notes |> LazyHTML.query("ol[data-notes] a") |> LazyHTML.attribute("href")

      assert links == Enum.map(1..4, &"act-1.html#nref-#{&1}")

      for link <- links do
        [file, id] = String.split(link, "#")
        assert id in ids(page(dir, play, file))
      end
    end

    test "offers a filter by type, shown by site.js, when there are two types or more", %{
      notes: notes
    } do
      [filter] = notes |> LazyHTML.query("fieldset[data-note-filter]") |> Enum.to_list()

      assert LazyHTML.attribute(filter, "hidden") == [""]

      assert filter |> LazyHTML.query("input") |> LazyHTML.attribute("value") ==
               ["", "other", "editor", "traductor"]

      assert texts(filter, "label") == ["All", "Note", "Editor's note", "Translator's note"]
    end

    test "is linked from every page's contents", %{play: play, dir: dir} do
      for file <- ["index.html", "act-1.html", "statistics.html", "notes.html"] do
        rail = page(dir, play, file) |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
        assert "notes.html" in LazyHTML.attribute(rail, "href"), file
      end

      current = page(dir, play, "notes.html") |> LazyHTML.query(~s(a[aria-current="page"]))
      assert LazyHTML.attribute(current, "href") == ["notes.html"]
    end
  end

  # Question 52, C (task B5): the play's stage directions on a page of their own, each
  # linked to its place, with a filter by kind where the file gives kinds.
  describe "the Stage directions page" do
    setup do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <stage type="entrance">Sale ANA <emph>sola</emph>.</stage>
          <sp><speaker>ANA</speaker>
            <l n="1">Dulce <stage type="delivery">(Llora.)</stage> sueño</l>
            <l n="2">mío.</l>
          </sp>
          <stage>Vase.</stage>
        </div1>
        """)

      %{play: play, dir: dir, stages: page(dir, play, "stage-directions.html")}
    end

    test "lists each stage direction in reading order: its kind, where it is, its words", %{
      stages: stages
    } do
      items = LazyHTML.query(stages, "ol[data-notes] > li")

      assert LazyHTML.attribute(items, "data-type") == ["entrance", "delivery", "none"]

      assert texts(stages, "ol[data-notes] > li > p:first-child") == [
               "Entrance I",
               "Delivery I, 1",
               "Stage direction I, after 2"
             ]

      assert texts(stages, "ol[data-notes] > li > p + p") == [
               "Sale ANA sola.",
               "(Llora.)",
               "Vase."
             ]

      assert texts(stages, "ol[data-notes] em") == ["sola"]
    end

    test "links each to its place on the page that shows it", %{
      play: play,
      dir: dir,
      stages: stages
    } do
      links = stages |> LazyHTML.query("ol[data-notes] a") |> LazyHTML.attribute("href")

      assert length(links) == 3

      for link <- links do
        [file, id] = String.split(link, "#")
        assert file == "act-1.html"
        assert id in ids(page(dir, play, file))
      end
    end

    test "offers a filter by kind, shown by site.js", %{stages: stages} do
      [filter] = stages |> LazyHTML.query("fieldset[data-note-filter]") |> Enum.to_list()

      assert LazyHTML.attribute(filter, "hidden") == [""]

      assert filter |> LazyHTML.query("input") |> LazyHTML.attribute("value") ==
               ["", "entrance", "delivery", "none"]

      assert texts(filter, "label") == ["All", "Entrance", "Delivery", "No kind given"]
    end

    test "is linked from every page's contents", %{play: play, dir: dir} do
      for file <- ["index.html", "act-1.html", "statistics.html", "stage-directions.html"] do
        rail = page(dir, play, file) |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
        assert "stage-directions.html" in LazyHTML.attribute(rail, "href"), file
      end

      current =
        page(dir, play, "stage-directions.html") |> LazyHTML.query(~s(a[aria-current="page"]))

      assert LazyHTML.attribute(current, "href") == ["stage-directions.html"]
    end
  end

  test "stage directions with no kinds have no filter; a play without any, no page" do
    {plain, plain_dir} =
      publish!("""
      <div1 type="acto" n="1"><stage>Sale A.</stage><sp><speaker>A</speaker><l n="1">uno</l></sp><stage>Vase.</stage></div1>
      """)

    assert plain_dir
           |> page(plain, "stage-directions.html")
           |> LazyHTML.query("fieldset")
           |> Enum.empty?()

    {none, none_dir} =
      publish!(~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>))

    refute File.exists?(Path.join([none_dir, "plays", none.code, "stage-directions.html"]))

    rail = page(none_dir, none, "index.html") |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
    refute "stage-directions.html" in LazyHTML.attribute(rail, "href")
  end

  test "a play with one type of note has no filter; a play without notes, no Notes page" do
    {one, one_dir} =
      publish!("""
      <div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno<note n="1" type="editor"><p>A.</p></note> dos<note n="2" type="editor"><p>B.</p></note></l></sp></div1>
      """)

    assert one_dir |> page(one, "notes.html") |> LazyHTML.query("fieldset") |> Enum.empty?()

    {none, none_dir} =
      publish!(~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>))

    refute File.exists?(Path.join([none_dir, "plays", none.code, "notes.html"]))
    rail = page(none_dir, none, "index.html") |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
    refute "notes.html" in LazyHTML.attribute(rail, "href")
  end

  # Question 17 named every kind; falta_tipo is read as the play's usual kind
  # (tei_roundtrip_test.exs), so a kind no file names, sin_tipo, stands for a plain Note.
  test "each kind of note the project named is shown by its name and filtered by itself" do
    kinds =
      ~w(latinismo toponimo_aludido toponimo_accion atrezzo oficio vestuario espacio gesto_movimiento efectos_especiales variantes sin_tipo)

    lines =
      kinds
      |> Enum.with_index(1)
      |> Enum.map_join(
        "\n",
        fn {kind, n} ->
          ~s(<l n="#{n}">uno<note n="#{n}" type="#{kind}"><p>Glosa.</p></note></l>)
        end
      )

    {play, dir} =
      publish!(~s(<div1 type="acto" n="1"><sp><speaker>A</speaker>#{lines}</sp></div1>))

    notes = page(dir, play, "notes.html")

    assert texts(notes, "ol[data-notes] > li > p:first-child b") == [
             "Latinism",
             "Place mentioned",
             "Place of the action",
             "Props",
             "Trades and offices",
             "Costume",
             "Stage space",
             "Gesture and movement",
             "Special effects",
             "Textual variant",
             "Note"
           ]

    # variantes, an ordinary note, files with the critical apparatus's variants.
    assert notes
           |> LazyHTML.query("fieldset[data-note-filter] input")
           |> LazyHTML.attribute("value") ==
             ["" | Enum.take(kinds, 9)] ++ ["variante", "other"]
  end

  test "the title page lists the bibliography by kind, linked from the contents, without researchers' notes" do
    play = import_tei!(tei(body: two_acts()))

    bibliography_fixture(
      play,
      %{
        "kind" => "modern_edition",
        "monogr_editors" => "Thompson, Ann",
        "monogr_title" => "Hamlet",
        "note" => "Revisar"
      },
      %{"note" => "Préstamo"}
    )

    bibliography_fixture(play, %{
      "kind" => "translation",
      "language" => "fr",
      "monogr_title" => "Hamlet, prince de Danemark"
    })

    dir = generate!([play], all: true)
    title = page(dir, play, "index.html")

    assert texts(title, "#bibliography h3") == ["Modern editions", "Translations"]
    assert texts(title, "#bibliography h4") == ["French"]
    assert LazyHTML.text(title) =~ "Thompson, Ann, ed. Hamlet."
    refute LazyHTML.text(title) =~ "Revisar"
    refute LazyHTML.text(title) =~ "Préstamo"

    rail =
      dir
      |> page(play, "act-1.html")
      |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
      |> LazyHTML.attribute("href")

    assert "index.html#bibliography" in rail
  end

  # Question 26: the notes on the edition, after the sources, linked from the contents.
  test "the title page prints the notes on the edition, linked from the contents" do
    play = import_tei!(tei(body: two_acts()))

    {:ok, play} =
      Playcode.Catalogue.update_play(play, %{
        edition_notes: ["Con correcciones de <<Guillermo>> Carrascón.", "Texto base:\nQ1, 1604."]
      })

    dir = generate!([play], all: true)
    section = dir |> page(play, "index.html") |> LazyHTML.query("#edition-notes")

    assert texts(section, "h2") == ["Notes on the edition"]
    assert LazyHTML.to_html(section) =~ "Con correcciones de <em>Guillermo</em> Carrascón."

    assert LazyHTML.to_html(section) =~ ~r"Texto base:<br/?>Q1, 1604."

    rail =
      dir
      |> page(play, "act-1.html")
      |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
      |> LazyHTML.attribute("href")

    assert "index.html#edition-notes" in rail
  end

  test "the title page lists the witnesses in order, linked from the contents, without siglum or type" do
    play = import_tei!(tei(body: two_acts()))

    {:ok, _} =
      Playcode.Witnesses.create_witness(%{
        "play_id" => play.id,
        "siglum" => "Q1",
        "witness_type" => "loose",
        "title" => "THE Tragicall Historie of HAMLET",
        "date" => "1603"
      })

    {:ok, _} =
      Playcode.Witnesses.create_witness(%{
        "play_id" => play.id,
        "title" => "COMEDIES, HISTORIES, & TRAGEDIES",
        "date" => "1623"
      })

    dir = generate!([play], all: true)
    title = page(dir, play, "index.html")

    assert texts(title, "#witnesses li") == [
             "THE Tragicall Historie of HAMLET. 1603.",
             "COMEDIES, HISTORIES, & TRAGEDIES. 1623."
           ]

    refute LazyHTML.text(title) =~ "Q1"

    rail =
      dir
      |> page(play, "act-1.html")
      |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
      |> LazyHTML.attribute("href")

    assert "index.html#witnesses" in rail
  end

  test "the title page prints the performances as lines, their sources once below, linked from the contents" do
    play = import_tei!(tei(body: two_acts()))

    {:ok, company} =
      Playcode.Performances.find_or_create_company(
        "The King’s Men #{System.unique_integer([:positive])}"
      )

    # No year: FileMaker printed "{Falta año pub}" here.
    source =
      catalogue_fixture(%{"monogr_title" => "CATCOM", "public_note" => "Copyright DICAT."})

    place =
      place_fixture(%{
        "names" => [
          %{"name" => "Londres", "language" => "es", "is_preferred" => "true"},
          %{"name" => "London", "language" => "en", "is_preferred" => "true"}
        ]
      })

    for date <- ["1610", "1611"] do
      performance_fixture(play, %{
        "date_text" => date,
        "venue" => "Globe",
        "place_id" => place.id,
        "company_id" => company.id,
        "venue_type" => "commercial_theatre",
        "note" => "Hissed.",
        "source_entry_id" => source.id,
        "source_volume" => "6",
        "source_pages" => "83"
      })
    end

    dir = generate!([play], all: true)
    title = page(dir, play, "index.html")

    # The venue's kind in the interface's language, place names in Spanish, as the site's
    # Places section.
    assert [first, _second] = texts(title, "#performances .performance")

    assert first =~
             "1610 Globe · Londres · #{company.name} · commercial theatre [1] vol. 6, p. 83"

    assert [spanish, _second] =
             dir
             |> html!("plays/#{play.code}/index.html", "es")
             |> texts("#performances .performance")

    assert spanish =~ "1610 Globe · Londres · #{company.name} · teatro comercial [1]"

    assert first =~ "Hissed."

    # Both performances cite one source, which is printed once, with its public note.
    assert [source] = texts(title, "#performances .sources li")
    assert source =~ ~r/^\[1\] CATCOM.*Copyright DICAT\.$/
    refute LazyHTML.text(title) =~ "{Falta"

    assert "index.html#performances" in rail_links(dir, play)
  end

  # Every text the TEI importer reads holds <emph> as <<…>> (CLAUDE.md), a performance's too.
  test "the title page prints a performance's italics as italics, never as markers" do
    play = import_tei!(tei(body: two_acts()))

    {:ok, _} =
      Playcode.PlayContent.create_character(%{
        play_id: play.id,
        xml_id: "ARGAN",
        name: "<<Argan>>",
        actor: "Mr. <<Betterton>>"
      })

    performance_fixture(play, %{
      "venue" => "<<Globe>>",
      "note" => "Hissed <<twice>>.",
      "cast_from_cast_list" => "true",
      "cast" => [%{"surname" => "<<Mlle>> du Parc", "role" => "<<Toinette>>"}]
    })

    title = page(generate!([play], all: true), play, "index.html")

    assert texts(title, "#performances .performance em") ==
             ["Globe", "Betterton", "Argan", "Mlle", "Toinette", "twice"]

    refute LazyHTML.text(title) =~ "<<"
  end

  defp rail_links(dir, play) do
    dir
    |> page(play, "act-1.html")
    |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
    |> LazyHTML.attribute("href")
  end

  test "a play with no performances has no section and no link" do
    play = import_tei!(tei(body: two_acts()))
    dir = generate!([play], all: true)

    assert [] =
             dir |> page(play, "index.html") |> LazyHTML.query("#performances") |> Enum.to_list()

    refute "index.html#performances" in rail_links(dir, play)
  end

  describe "textual variants" do
    @variant """
    <div1 type="jornada" n="1"><head>Jornada I</head>
      <sp><speaker>FENISA</speaker>
        <l n="72">mucho la hermosura llama<app n="908"><lem wit="#H">llama</lem><rdg wit="#P3">falta</rdg><note>Por la rima.</note></app>,<note n="1" type="editor"><p>Glosa.</p></note></l>
      </sp>
    </div1>
    """

    defp opened_by(page, label),
      do:
        page
        |> LazyHTML.query(~s(button[aria-label="#{label}"]))
        |> LazyHTML.attribute("popovertarget")

    defp variant_play! do
      play = import_tei!(tei(body: @variant))

      bibliography_fixture(play, %{
        "kind" => "modern_edition",
        "siglum" => "H",
        "monogr_editors" => "Hartzenbusch, J. E.",
        "year_text" => "1860"
      })

      play
    end

    test "an asterisk opens the readings; the Notes page leaves them out" do
      play = variant_play!()
      dir = generate!([play], all: true)
      act = page(dir, play, "act-1.html")

      assert squish(LazyHTML.text(LazyHTML.query(act, "main"))) =~ "mucho la hermosura llama*,1"
      assert opened_by(act, "Textual variant 1") == ["var-1"]
      assert opened_by(act, "Editor's note 1") == ["note-1"]

      assert act |> LazyHTML.query("#var-1 p") |> Enum.map(&squish(LazyHTML.text(&1))) == [
               "H (Hartzenbusch, 1860) llama",
               "P3 falta",
               "Por la rima."
             ]

      assert act |> LazyHTML.query(~s(input[data-toggle="va"])) |> Enum.count() == 1

      # the Notes page prints a note's type and body, not a variant's readings: its own
      # trace of a listed variant is the entry's note, "Por la rima."
      notes_page = squish(LazyHTML.text(page(dir, play, "notes.html")))
      refute notes_page =~ "falta"
      refute notes_page =~ "Por la rima."
      assert notes_page =~ "Glosa."
    end

    test "a play whose variants readers do not see has no asterisk and no switch" do
      play = variant_play!()
      {:ok, play} = Playcode.Catalogue.update_play(play, %{show_variants: false})
      act = page(generate!([play], all: true), play, "act-1.html")

      assert opened_by(act, "Textual variant 1") == []
      assert act |> LazyHTML.query(~s(input[data-toggle="va"])) |> Enum.count() == 0
      assert opened_by(act, "Editor's note 1") == ["note-1"]
    end
  end

  # Question 63: the words an <rs> tags (229 in EMOTHE0551) carry its kind's name, and a
  # switch, off at first, underlines them.
  test "tagged names are named by their kind, underlined by a switch that starts off" do
    body = """
    <div1 type="acto" n="1"><head>ACT I</head>
      <sp><speaker>ANA</speaker>
        <l n="1">Como <rs n="5163" type="mitologia_antroponimo">Adonis</rs> en <rs type="toponimo_accion">Castilla</rs></l>
        <l n="2"><stage>(Coge <rs type="atrezzo">la adarga</rs>.)</stage> ¡Vamos!</l>
      </sp>
    </div1>
    """

    play = import_tei!(tei(body: body))
    dir = generate!([play], all: true)
    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query(~s(input[data-toggle="rs"])) |> Enum.count() == 1
    assert act |> LazyHTML.query(~s(input[data-toggle="rs"][checked])) |> Enum.count() == 0
    assert act |> LazyHTML.query(~s(body[data-rs="off"])) |> Enum.count() == 1

    tags = LazyHTML.query(act, "span.rs")
    assert Enum.map(tags, &LazyHTML.text/1) == ["Adonis", "Castilla", "la adarga"]

    assert LazyHTML.attribute(tags, "title") == [
             "Mythological figure",
             "Place of the action",
             "Props"
           ]

    # style.css underlines them while the switch is on; site.js remembers it.
    assert read!(dir, "assets/style.css") =~ ~s(body[data-rs="on"] .rs)
    assert read!(dir, "assets/site.js") =~ ~s('fo', 'rs'])

    # A play with none has no switch.
    other =
      import_tei!(
        tei(
          body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>)
        )
      )

    plain = page(generate!([other], all: true), other, "act-1.html")
    assert plain |> LazyHTML.query(~s(input[data-toggle="rs"])) |> Enum.count() == 0
  end

  # Questions 45, 52, 62 and 65: the rail's Highlight switches, each with arrows that step
  # through what it highlights (site.js, test/js/stepper.test.mjs). Offered per page, only
  # where there is one to step to.
  test "the shared lines and the stage directions are highlighted and stepped through" do
    {play, dir} = publish!(two_acts())
    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query(~s(body[data-sh="off"][data-sdm="off"])) |> Enum.count() == 1
    assert act |> LazyHTML.query(~s(input[data-toggle="sh"])) |> Enum.count() == 1
    assert act |> LazyHTML.query(~s(input[data-toggle="sh"][checked])) |> Enum.count() == 0
    assert act |> LazyHTML.query(~s(input[data-toggle="sdm"])) |> Enum.count() == 1

    for label <- ~w(Next Previous) do
      assert act |> LazyHTML.query(~s(button[aria-label="#{label} shared line"])) |> Enum.count() ==
               1

      assert act
             |> LazyHTML.query(~s(button[aria-label="#{label} stage direction"]))
             |> Enum.count() == 1
    end

    # The count shows; a live region says it with the words landed on (site.js). The
    # highlight's checkbox is named apart from the Show group's "Stage directions".
    assert act
           |> LazyHTML.query(~s([data-stepper] .sr-only[data-step-said][aria-live="polite"]))
           |> Enum.count() == 2

    assert act |> LazyHTML.query(~s([data-step-count][aria-live])) |> Enum.count() == 0

    assert act
           |> LazyHTML.query(
             ~s(input[data-toggle="sdm"][aria-label="Highlight stage directions"])
           )
           |> Enum.count() == 1

    assert act |> LazyHTML.query(".shared-legend li") |> Enum.map(&String.trim(LazyHTML.text(&1))) ==
             ["First part", "Middle part", "Last part"]

    assert act
           |> LazyHTML.query(~s(.l[data-part="I"]))
           |> Enum.map(&LazyHTML.text/1)
           |> Enum.map(&String.trim/1) ==
             ["6A mí."]

    assert act |> LazyHTML.query(~s(.l[data-part="F"])) |> Enum.count() == 1

    css = read!(dir, "assets/style.css")
    assert css =~ ~s(body[data-sh="on"] .l[data-part="I"] .t)
    assert css =~ ~s(body[data-sdm="on"] .sd)
    # The outline of the one the arrows landed on goes with its switch, and on a narrow
    # screen, where the rail scrolls away, the arrows stay at the foot of the window.
    assert css =~ ~s(body[data-sh="on"] .l[data-current])
    assert css =~ ~s(body[data-sdm="on"] :is(.sd, .sdi\)[data-current])
    refute css =~ ~r/^\[data-current\]/m
    assert css =~ ~r/@media print \{[^@]*\[data-current\] \{ outline: none/
    assert css =~ ~r/@media \(max-width: 959px\) \{[^}]*\[data-stepper\] \{ position: fixed/

    # A prose act with no stage direction offers neither.
    prose = page(dir, play, "act-2.html")
    assert prose |> LazyHTML.query(~s(input[data-toggle="sh"])) |> Enum.count() == 0
    assert prose |> LazyHTML.query(~s(input[data-toggle="sdm"])) |> Enum.count() == 0
    assert prose |> LazyHTML.query("[data-stepper]") |> Enum.count() == 0
  end

  describe "Hamlet's Folio passages" do
    @folio_open ~s(<code>&lt;span class="folio"&gt;</code>)
    @folio_close ~s(<code>&lt;/span&gt;</code>)
    @f ~s(<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>)

    # A passage in a line, a line all the Folio's, and a passage that opens at a speaker
    # label and closes at the end of the speech, so the whole speech is the Folio's.
    @folio_body """
    <div1 type="acto" n="1"><head>ACT I</head>
      <sp><speaker>HAMLET</speaker>
        <l n="316">O God, #{@folio_open}#{@f}O#{@f}#{@folio_close} God,</l>
        <l n="481">#{@folio_open}#{@f}For he himself is subject to his birth:#{@f}#{@folio_close}</l>
      </sp>
      <sp><speaker>#{@folio_open}#{@f}guildenstern#{@folio_close}</speaker>
        <p>#{@folio_open}Prison, my lord?#{@f}#{@folio_close}</p>
      </sp>
    </div1>
    """

    test "are hidden by default, with a switch that shows them in grey between their F's" do
      # Hamlet runs with its variant readings off, and that setting does not govern this switch.
      {:ok, play} =
        [body: @folio_body]
        |> tei()
        |> import_tei!()
        |> Playcode.Catalogue.update_play(%{show_variants: false})

      dir = generate!([play], all: true)
      act = page(dir, play, "act-1.html")

      assert act |> LazyHTML.query(~s(input[data-toggle="fo"])) |> Enum.count() == 1
      assert act |> LazyHTML.query(~s(input[data-toggle="fo"][checked])) |> Enum.count() == 0
      assert act |> LazyHTML.query(~s(body[data-fo="off"])) |> Enum.count() == 1
      assert act |> LazyHTML.query("sup.fl") |> Enum.map(&LazyHTML.text/1) == ~w(F F F F F F)
      assert act |> LazyHTML.query("span.fo") |> Enum.map(&LazyHTML.text/1) |> hd() == "O"
      assert act |> LazyHTML.query(".l.fo") |> Enum.count() == 1
      assert act |> LazyHTML.query("p.pr.fo") |> Enum.count() == 1
      assert act |> LazyHTML.query(".sp.fo") |> Enum.count() == 1
      assert act |> LazyHTML.query("p.spk.fo") |> Enum.count() == 1

      # style.css hides what the class marks while the switch is off; site.js remembers it.
      assert read!(dir, "assets/style.css") =~ ~s(body[data-fo="off"] .fo)
      # (The list of remembered switches goes on past 'fo' since the tagged names joined it.)
      assert read!(dir, "assets/site.js") =~ ~s('va', 'fo')
    end

    # Each kind of element that can be the Folio's wholly goes with its words; a group with
    # one line the Quarto shares keeps its wrapper.
    test "a stage direction and a line group that are all the Folio's go, a mixed group stays" do
      body = """
      <div1 type="acto" n="1">
        <stage type="entrance">#{@folio_open}#{@f}Sound a Flourish.#{@f}#{@folio_close}</stage>
        <sp><speaker>HAMLET</speaker>
          <lg>
            <l n="2">#{@folio_open}#{@f}One line,#{@f}#{@folio_close}</l>
            <l n="3">#{@folio_open}#{@f}and two.#{@f}#{@folio_close}</l>
          </lg>
          <lg>
            <l n="4">#{@folio_open}#{@f}A line#{@f}#{@folio_close} the Quarto has too.</l>
            <l n="5">#{@folio_open}#{@f}and two.#{@f}#{@folio_close}</l>
          </lg>
        </sp>
      </div1>
      """

      play = import_tei!(tei(body: body))
      act = page(generate!([play], all: true), play, "act-1.html")

      assert act |> LazyHTML.query("p.sd.fo") |> Enum.count() == 1
      assert act |> LazyHTML.query(".lg") |> Enum.count() == 2
      assert [group] = act |> LazyHTML.query(".lg.fo") |> Enum.map(&LazyHTML.text/1)
      assert group =~ "One line," and group =~ "and two."

      # no speech is the Folio's alone: the second group has words of the Quarto's
      assert act |> LazyHTML.query(".sp.fo") |> Enum.count() == 0
    end

    test "a passage inside an inline stage direction nests in it, so the stage switch hides its F's" do
      body = """
      <div1 type="acto" n="1">
        <sp><speaker>HAMLET</speaker>
          <l n="1">Go <stage type="delivery">#{@folio_open}#{@f}aside#{@f}#{@folio_close}</stage> on.</l>
        </sp>
      </div1>
      """

      play = import_tei!(tei(body: body))
      act = page(generate!([play], all: true), play, "act-1.html")

      assert act |> LazyHTML.query(".sdi > span.fo") |> Enum.count() == 1
      assert act |> LazyHTML.query(".sdi sup.fl") |> Enum.count() == 2
    end

    test "a play with none has no switch" do
      play =
        import_tei!(
          tei(
            body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>)
          )
        )

      act = page(generate!([play], all: true), play, "act-1.html")

      assert act |> LazyHTML.query(~s(input[data-toggle="fo"])) |> Enum.count() == 0
    end
  end
end
