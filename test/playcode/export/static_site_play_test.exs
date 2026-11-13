defmodule Playcode.Export.StaticSitePlayTest do
  @moduledoc "A play's reading pages in the static site: one per act, the full text, anchors, line breaks and split verses. Its other pages are in `StaticSitePlayPagesTest`, its long divisions in `StaticSitePlayLongDivisionsTest`."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers
  import Playcode.StaticSitePlayHelpers
  import Playcode.TestFixtures

  test "an act's closing formula ends its page and its part of the full text" do
    {play, dir} =
      publish!(
        ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso de prueba</l></sp><trailer>FIN DEL PRIMER ACTO</trailer></div1>)
      )

    for file <- ["act-1.html", "text.html"] do
      assert dir |> page(play, file) |> LazyHTML.text() =~ "FIN DEL PRIMER ACTO", file
    end
  end

  test "a verse group's heading stands before its lines" do
    {play, dir} =
      publish!(
        ~s(<div1 type="acto" n="1"><sp><speaker>ITHOCLES</speaker><lg type="free"><head>A <emph>Song</emph></head><l n="1">Can you paint a thought?</l></lg></sp></div1>)
      )

    for file <- ["act-1.html", "text.html"] do
      assert dir |> page(play, file) |> LazyHTML.text() =~ ~r/A Song\s*1?\s*Can you paint/, file
    end
  end

  # Regression: WordParser puts a stanza straight under the division when {m} opens
  # with no speaker; its verses used to get no item, no anchor, and the build raised.
  test "a Word-imported stanza with no speaker is published, and counted" do
    play = play_fixture(%{"is_complete" => true})

    assert {:ok, _} =
             Playcode.Import.WordParser.import_content(
               play.id,
               docx(["{e}Escena 1", "{m}", "{v}uno", "{v}dos"])
             )

    dir = generate!([play], all: true)
    act = Path.wildcard(Path.join([dir, "plays", play.code, "act-*.html"])) |> hd()
    html = LazyHTML.from_document(File.read!(act))

    assert texts(html, "#l1") |> Enum.join() =~ "uno"
    assert Playcode.Statistics.get_statistics(play.id).data["verses"] == 2
  end

  # The site writes the TEI from the text it already loaded for the pages, not a second
  # load: the file must still be the one the TEI download gives.
  test "a play's TEI file in the site is its TEI export" do
    play = import_tei!(tei(body: two_acts()))
    dir = generate!([play], all: true)

    assert read!(dir, "plays/#{play.code}/#{play.code}.xml") ==
             Playcode.Export.TeiXml.generate(Playcode.Catalogue.get_play!(play.id))
  end

  test "each act has its own page, linked to the acts before and after it" do
    {play, dir} = publish!(two_acts())
    first = page(dir, play, "act-1.html")
    second = page(dir, play, "act-2.html")

    assert first |> LazyHTML.query(~s(a[rel="next"])) |> LazyHTML.attribute("href") |> Enum.uniq() ==
             ["act-2.html"]

    assert second
           |> LazyHTML.query(~s(a[rel="prev"]))
           |> LazyHTML.attribute("href")
           |> Enum.uniq() == ["act-1.html"]

    assert LazyHTML.text(first) =~ "Salen músicos cantando"
    refute LazyHTML.text(first) =~ "Señor, despierta."
    assert LazyHTML.text(second) =~ "Señor, despierta."
  end

  test "a verse is anchored by its number and keeps its italics, escaped" do
    {play, dir} = publish!(two_acts())
    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query("#l2 em") |> LazyHTML.text() == "sueño"
    assert act |> LazyHTML.query("#l2") |> LazyHTML.text() =~ "Dulce sueño mío"
    refute read!(dir, "plays/#{play.code}/act-1.html") =~ "&lt;&lt;"
    assert act |> LazyHTML.query("#l3") |> LazyHTML.text() =~ "uno & <script>alert(1)</script>"

    # The link carries the assets' stamp, `?v=` (site_builder_test.exs); the path is the point here.
    assert [src] = act |> LazyHTML.query("script") |> LazyHTML.attribute("src")
    assert String.starts_with?(src, "../../assets/site.js?v=")

    assert act |> LazyHTML.query("#l3 script") |> Enum.empty?()
    assert read!(dir, "plays/#{play.code}/act-1.html") =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  describe "the cite button's word" do
    @speeches """
    <div1 type="acto" n="1"><head>Acto I</head>
      <sp><speaker>A</speaker><l n="1">Uno.</l></sp>
      <sp><speaker>B</speaker><p n="2">Dos.</p></sp>
    </div1>
    """

    defp cite(dir, play, attr),
      do:
        page(dir, play, "act-1.html") |> LazyHTML.query("[data-cite]") |> LazyHTML.attribute(attr)

    test "a play numbered by speech cites int. for a verse and a paragraph" do
      {play, dir} = publish!(@speeches, type: "S")

      assert cite(dir, play, "data-cite-verse") == ["int."]
      assert cite(dir, play, "data-cite-prose") == ["int."]
    end

    test "a play numbering verse and prose cites v. for a verse, l. for prose" do
      {play, dir} = publish!(@speeches, type: "VP")

      assert cite(dir, play, "data-cite-verse") == ["v."]
      assert cite(dir, play, "data-cite-prose") == ["l."]
    end
  end

  # Problem 3 gives an unnumbered verse a counter of its own: a paragraph before it no
  # longer moves its anchor, as it did while every unnumbered line shared one counter.
  test "a verse with no number counts apart from the paragraphs" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><p>En prosa.</p><l xml:id="es-0007">Sin número.</l></sp>
      </div1>
      """)

    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query("#v1") |> LazyHTML.text() =~ "Sin número."
    assert act |> LazyHTML.query("#p1") |> LazyHTML.text() =~ "En prosa."
  end

  # A line's anchor is the nearest number before it plus a counter of its own kind
  # (docs/superpowers/specs/2026-11-08-site-anchors-design.md), so it moves when the
  # citation moves, or when a line of its kind is put between it and that number.
  describe "a line's anchor, from the nearest number" do
    test "a continuous page: numbers, a later piece, directions and paragraphs after a number" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <stage>Sale el REY.</stage>
          <sp><speaker>REY</speaker><l n="1">¿Quién va?</l><l n="2" part="I">Ya el sol se esconde.</l></sp>
          <sp><speaker>CRIADO</speaker><l part="F">Yo, señor.</l></sp>
          <sp><speaker>REY</speaker><l n="3">Mal me sirve este criado.</l><stage>Vase el criado.</stage></sp>
          <stage>Sale la REINA.</stage>
          <sp><speaker>REINA</speaker><p n="4">Señor, os traigo nuevas.</p><p>Y así lo cuentan todos.</p></sp>
        </div1>
        """)

      assert line_ids(page(dir, play, "act-1.html")) ==
               ~w(sd1 l1 l2 l2b l3 l3-sd1 l3-sd2 l4 l4-p1)
    end

    test "a play numbered per scene keeps the act-scene prefix and looks only inside the scene" do
      {play, dir} =
        publish!(
          """
          <div1 type="acto" n="1"><head>Acto I</head>
            <stage>Antes de la escena.</stage>
            <div2 type="scene" n="1"><head>Scene 1</head><stage>Salen.</stage>
              <sp><speaker>A</speaker><l n="1">one</l><l n="2">two</l></sp></div2>
            <div2 type="scene" n="2"><head>Scene 2</head><stage>Vanse.</stage>
              <sp><speaker>B</speaker><l n="1">uno</l></sp><stage>Sale C.</stage></div2>
          </div1>
          """,
          # The numbering rule, not the numbers, says the count starts again (numbering spec).
          restart: "scene"
        )

      assert line_ids(page(dir, play, "act-1.html")) ==
               ~w(l1-0-sd1 l1-1-sd1 l1-1-1 l1-1-2 l1-2-sd1 l1-2-1 l1-2-1-sd1)
    end

    test "unnumbered verses count apart, as in a play numbered by speech" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>A</speaker><l>Primero sin número.</l></sp>
          <sp><speaker>B</speaker><l n="12">Doce.</l><l>Sigue.</l><l part="I">Parte uno.</l></sp>
          <sp><speaker>C</speaker><l part="F">Parte dos.</l></sp>
        </div1>
        """)

      assert line_ids(page(dir, play, "act-1.html")) == ~w(v1 l12 l12-v1 l12-v2 l12-v2b)
    end

    test "a piece with a number of its own is anchored by it; a clash takes a suffix" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>A</speaker><l n="961" part="I">a</l></sp>
          <sp><speaker>B</speaker><l n="962" part="M">b</l></sp>
          <sp><speaker>C</speaker><l part="F">c</l></sp>
          <sp><speaker>A</speaker><l n="3153" part="I">d</l></sp>
          <sp><speaker>B</speaker><l part="M">e</l></sp>
          <sp><speaker>C</speaker><l part="F">f</l></sp>
          <sp><speaker>A</speaker><l n="3153c">g</l></sp>
        </div1>
        """)

      assert line_ids(page(dir, play, "act-1.html")) ==
               ~w(l961 l962 l962b l3153 l3153b l3153c l3153c-2)
    end

    test "a numbered paragraph's number links to it, as a verse's does; its inner line numbers do not" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>KENT</speaker><p n="4">I thought<note n="1" type="editor"><p>Glosa.</p></note> the King<lb n="5"/>had more affected the Duke.</p></sp>
        </div1>
        """)

      para = page(dir, play, "act-1.html") |> LazyHTML.query("p#l4")

      assert para |> LazyHTML.query(~s(a.pn[href="#l4"])) |> LazyHTML.text() == "4"
      assert para |> LazyHTML.query("span.pn.m5") |> LazyHTML.text() == "5"
      assert LazyHTML.text(para) =~ "I thought1 the King"
    end

    # Timon of Athens numbers straight through but repeats prose 425 in I.2 and II.2: a
    # number met again later is a data error, not a count starting again, which only a
    # scene opening below where the last one ended shows.
    test "a number repeated in a later scene does not make a continuous play restart" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <div2 type="scene" n="1"><head>Scene 1</head>
            <sp><speaker>A</speaker><l n="1">uno</l><p n="2">dos</p><l n="3">tres</l></sp></div2>
          <div2 type="scene" n="2"><head>Scene 2</head>
            <sp><speaker>B</speaker><l n="4">cuatro</l><p n="2">otra vez dos</p><l n="5">cinco</l></sp></div2>
        </div1>
        """)

      assert line_ids(page(dir, play, "act-1.html")) == ~w(l1 l2 l3 l4 l2-2 l5)
    end

    # In a play numbered per scene a prologue and an epilogue are units of their own, named
    # by their page: both took `l0-0-`, so a direction added to the prologue suffixed the
    # epilogue's.
    test "a prologue and an epilogue in a play numbered per scene are prefixed by their page" do
      {play, dir} =
        publish!(
          """
          <div1 type="prologue"><head>Prologue</head><stage>Entra el Prólogo.</stage>
            <sp><speaker>P</speaker><l n="1">uno</l><l n="2">dos</l></sp></div1>
          <div1 type="acto" n="1"><head>Acto I</head>
            <div2 type="scene" n="1"><head>Scene 1</head><sp><speaker>A</speaker><l n="1">uno</l><l n="2">dos</l></sp></div2>
            <div2 type="scene" n="2"><head>Scene 2</head><sp><speaker>B</speaker><l n="1">uno</l><l n="2">dos</l></sp></div2>
          </div1>
          <div1 type="epilogue"><head>Epilogue</head><stage>Entra el Epílogo.</stage>
            <sp><speaker>E</speaker><l n="1">uno</l><l n="2">dos</l></sp></div1>
          """,
          # The numbering rule, not the numbers, says the count starts again (numbering spec).
          restart: "scene"
        )

      assert line_ids(page(dir, play, "prologue.html")) ==
               ~w(lprologue-0-sd1 lprologue-0-1 lprologue-0-2)

      assert line_ids(page(dir, play, "epilogue.html")) ==
               ~w(lepilogue-0-sd1 lepilogue-0-1 lepilogue-0-2)
    end

    # Counters start again after each number, so a direction added in act 1 moves only the
    # directions after the same verse, and act 2 not at all. Act 2 opens after verse 2.
    test "a direction added in act 1 moves no anchor in act 2" do
      act_2 = """
      <div1 type="acto" n="2"><head>Acto II</head>
        <stage>Salen.</stage><sp><speaker>A</speaker><l n="3">tres</l></sp><stage>Vase.</stage>
      </div1>
      """

      act_1 = fn extra ->
        """
        <div1 type="acto" n="1"><head>Acto I</head>
          <stage>Sale.</stage><sp><speaker>A</speaker><l n="1">uno</l></sp>#{extra}
          <stage>Otra.</stage><sp><speaker>A</speaker><l n="2">dos</l></sp>
        </div1>
        """
      end

      {before, before_dir} = publish!(act_1.("") <> act_2)
      {added, added_dir} = publish!(act_1.("<stage>Nueva.</stage>") <> act_2)

      assert line_ids(page(before_dir, before, "act-1.html")) == ~w(sd1 l1 l1-sd1 l2)
      assert line_ids(page(added_dir, added, "act-1.html")) == ~w(sd1 l1 l1-sd1 l1-sd2 l2)
      assert line_ids(page(before_dir, before, "act-2.html")) == ~w(l2-sd1 l3 l3-sd1)
      assert line_ids(page(added_dir, added, "act-2.html")) == ~w(l2-sd1 l3 l3-sd1)
    end
  end

  # Regression: the files cut an aside over several verses into one piece per verse, and
  # the margin said "aparte" on each, 74 times down Clotaldo's in La vida es sueño.
  test "an aside over several verses is named once, where it starts" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><lg>
          <l n="1"><seg type="aside">uno</seg></l>
          <l n="2"><seg type="aside">dos</seg></l>
          <l n="3">tres</l>
          <l n="4"><seg type="aside">cuatro</seg></l>
        </lg></sp>
        <sp><speaker>B</speaker><lg><l n="5"><seg type="aside">cinco</seg></l></lg></sp>
      </div1>
      """)

    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query(".aparte") |> Enum.count() == 3

    for n <- [1, 4, 5] do
      assert act |> LazyHTML.query("#l#{n} .aparte") |> Enum.count() == 1, "verse #{n}"
    end
  end

  # The files number each piece within its aside: es-0003-seg01 starts a second aside right
  # after the first, and es-0004-seg02 carries the first into B's speech.
  test "two asides back to back are named twice; an aside carried to another speaker is named again" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><lg>
          <l n="1"><seg type="aside" xml:id="es-0001-seg01">uno</seg></l>
          <l n="2"><seg type="aside" xml:id="es-0002-seg02">dos</seg></l>
          <l n="3"><seg type="aside" xml:id="es-0003-seg01">tres</seg></l>
        </lg></sp>
        <sp><speaker>B</speaker><lg><l n="4"><seg type="aside" xml:id="es-0004-seg02">cuatro</seg></l></lg></sp>
      </div1>
      """)

    act = page(dir, play, "act-1.html")

    assert for(n <- 1..4, act |> LazyHTML.query("#l#{n} .aparte") |> Enum.any?(), do: n) ==
             [1, 3, 4]
  end

  test "the second half of a split verse starts where the first half ended" do
    {play, dir} = publish!(two_acts())

    assert texts(page(dir, play, "act-1.html"), ~s([aria-hidden="true"])) == ["A mí."]
  end

  test "a verse form is named once, where its passage starts" do
    {play, dir} = publish!(two_acts())
    text = LazyHTML.text(page(dir, play, "act-1.html"))

    assert length(String.split(text, "Redondilla")) == 2
  end

  test "the full text carries every act on one page" do
    {play, dir} = publish!(two_acts())
    full = page(dir, play, "text.html")

    assert Enum.filter(texts(full, "h2"), &String.starts_with?(&1, "Jornada")) == [
             "Jornada I",
             "Jornada II"
           ]

    assert LazyHTML.text(full) =~ "Señor, despierta."
  end

  # Regression: Hamlet and 47 other files leave every act's head empty and number it in
  # `n`; the contents, the page titles and the links between pages all said just "Act".
  test "an act with no heading is named by its type and its number" do
    {play, dir} =
      publish!("""
      <div1 type="Act" n="1"><head/><sp><speaker>A</speaker><l n="1">one</l></sp></div1>
      <div1 type="Act" n="2"><head/><sp><speaker>B</speaker><l n="2">two</l></sp></div1>
      <div1 type="prologue"><head/><sp><speaker>C</speaker><l n="3">three</l></sp></div1>
      """)

    second = page(dir, play, "act-2.html")

    assert texts(second, ~s(nav[aria-label="Contents"] a)) ==
             ["Title page", "Act I", "Act II", "Prologue", "Full text", "Statistics"]

    assert texts(second, ~s(a[rel="prev"])) |> Enum.uniq() == ["← Act I"]
    assert texts(second, "title") |> hd() =~ "Act II"
  end

  test "a play that numbers each scene from 1 still gives every line its own anchor" do
    {play, dir} =
      publish!(
        """
        <div1 type="act" n="1"><head>Act I</head>
          <div2 type="scene" n="1"><head>Scene 1</head><sp><speaker>A</speaker><l n="1">one</l><l n="2">two</l></sp></div2>
          <div2 type="scene" n="2"><head>Scene 2</head><sp><speaker>B</speaker><l n="1">uno</l><l n="2">dos</l></sp></div2>
        </div1>
        """,
        # The numbering rule, not the numbers, says the count starts again (numbering spec).
        restart: "scene"
      )

    anchors = ids(page(dir, play, "text.html"))

    assert anchors == Enum.uniq(anchors)
    assert "l1-2-1" in anchors
  end

  test "a play with no acts has no act pages; its prologue gets one named after it" do
    {play, dir} =
      publish!(
        ~s(<div1 type="prologue"><head>Prologue</head><sp><speaker>A</speaker><l n="1">one</l></sp></div1>)
      )

    assert File.exists?(Path.join([dir, "plays", play.code, "text.html"]))
    assert File.exists?(Path.join([dir, "plays", play.code, "prologue.html"]))
    refute File.exists?(Path.join([dir, "plays", play.code, "act-1.html"]))
  end

  test "reading tools ship hidden, ready for JS, with the cast to highlight" do
    %{play: play} = play_with_structure_fixture()
    act = html!(generate!([play], all: true), "plays/#{play.code}/act-1.html")

    assert act |> LazyHTML.query("[data-tools][hidden]") |> Enum.count() == 1

    assert act |> LazyHTML.query("[data-highlight] option") |> LazyHTML.attribute("value") ==
             ["", "ALFA"]

    assert act |> LazyHTML.query("body") |> LazyHTML.attribute("data-ln") == ["5"]

    assert act |> LazyHTML.query("[data-cite]") |> LazyHTML.attribute("data-cite") ==
             ["Tester, Structured Play, ACT I"]
  end

  describe "an inline stage direction" do
    setup do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>CHIMÈNE</speaker>
            <l n="1"><stage type="exit">(A Léonor.)</stage>Allez l'entretenir.</l>
            <p>Dijo <stage>(bajo<note n="1" type="editor"><p>Glosa.</p></note> y rápido)</stage> y salió.</p>
          </sp>
        </div1>
        """)

      %{act: page(dir, play, "act-1.html"), dir: dir}
    end

    # The class is the contract between the template and style.css; the last test here
    # holds the stylesheet to it.
    test "is set apart from the spoken words and stays in its line", %{act: act} do
      line = LazyHTML.query(act, "#l1")

      assert line |> LazyHTML.query(".sdi") |> Enum.map(&LazyHTML.text/1) == ["(A Léonor.)"]
      assert squish(LazyHTML.text(line)) =~ "(A Léonor.) Allez l'entretenir."
      refute LazyHTML.text(act) =~ "<stage"
    end

    test "is wrapped piece by piece when a note splits it, the note's number inside", %{act: act} do
      prose = LazyHTML.query(act, "p.pr")

      assert prose |> LazyHTML.query(".sdi") |> Enum.map(&LazyHTML.text/1) |> Enum.join() ==
               "(bajo1 y rápido)"

      assert prose |> LazyHTML.query(".sdi button.nref") |> Enum.count() == 1
    end

    test "is hidden by the rule the stage directions toggle sets", %{dir: dir} do
      assert read!(dir, "assets/style.css") =~ ~s(body[data-sd="off"] .sdi)
    end
  end

  describe "line breaks and prose line numbers" do
    setup do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>LUCRECIA</speaker>
            <p>Yo amé en mis primeros años, <lb/>dulce cosa lo juzgué.</p>
            <p n="1319">Beggar that I am, <lb n="1320"/>but I thank you, <lb n="1311-2"/>my thanks.</p>
          </sp>
        </div1>
        """)

      %{act: page(dir, play, "act-1.html"), dir: dir}
    end

    test "a break is a new line in its paragraph", %{act: act} do
      [song, _hamlet] = act |> LazyHTML.query("p.pr") |> Enum.to_list()

      assert song |> LazyHTML.query("br") |> Enum.count() == 1
      assert squish(LazyHTML.text(song)) == "Yo amé en mis primeros años,dulce cosa lo juzgué."
    end

    test "a number shows where its printed line starts, every fifth marked", %{act: act} do
      [_song, hamlet] = act |> LazyHTML.query("p.pr") |> Enum.to_list()

      assert hamlet |> LazyHTML.query(".pn") |> Enum.map(&LazyHTML.text/1) ==
               ["1319", "1320", "1311-2"]

      assert hamlet |> LazyHTML.query(".pn.m5") |> Enum.map(&LazyHTML.text/1) == ["1320"]
      refute LazyHTML.text(act) =~ "<lb"
    end

    test "the line-number control and print hide the numbers", %{dir: dir} do
      css = read!(dir, "assets/style.css")

      assert css =~ ~s(body[data-ln="off"] .pn)
      assert css =~ ~s|body[data-ln="5"] .pn:not(.m5)|
      assert css =~ ".pn:not(.m5) { display: none !important; }"
    end

    # As emothe.uv.es printed its prose (`.prosa`), and the play page and downloads do.
    test "prose is justified", %{dir: dir} do
      assert read!(dir, "assets/style.css") =~ ~r/^\.pr \{[^}]*text-align: justify/m
    end

    # A prose paragraph's number is a link since problem 3; a verse's (`.l .n`) never
    # showed a link's underline, and neither does it.
    test "a paragraph's number is not underlined", %{dir: dir} do
      assert read!(dir, "assets/style.css") =~ ~r/^\.pn \{[^}]*text-decoration: none/m
    end
  end

  # Hamlet numbers a verse "3-4" beside its verse 3. Until 2026-11-08 both were 3, the second
  # anchored `l3-2`, and the margin's every-fifth test could only take a whole number.
  test "a verse's number as the file writes it is its label and its anchor" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><l n="3">Tres</l><l n="3-4">Tres y cuatro</l><l n="5">Cinco</l></sp>
      </div1>
      """)

    lines = page(dir, play, "act-1.html") |> LazyHTML.query("div.l")

    assert LazyHTML.attribute(lines, "id") == ["l3", "l3-4", "l5"]
    assert lines |> LazyHTML.query("a.n") |> Enum.map(&LazyHTML.text/1) == ["3", "3-4", "5"]
    assert lines |> LazyHTML.query("a.n.m5") |> Enum.map(&LazyHTML.text/1) == ["5"]
  end

  # Components.lines/1, the paratexts' renderer, folded into inline/1 on 2026-10-16.
  test "a dedication's line breaks are still new lines on the title page" do
    play =
      import_tei!(
        tei(
          front:
            ~s(<div type="dedicatoria"><head>DEDICATORIA</head><p>My Lord,<lb/>Whether the world</p></div>),
          body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">Verso</l></sp></div1>)
        )
      )

    dir = generate!([play], all: true)

    assert html!(dir, "plays/#{play.code}/index.html") |> LazyHTML.to_html() =~
             ~r{My Lord,<br/?>Whether the world}
  end

  describe "a split verse whose opening fragment holds an inline stage direction" do
    test "hides the stage's words in the continuing fragment's invisible lead too" do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>Clarín</speaker><lg type="free" part="I"><l n="6" part="I"><stage>(bajo)</stage> A mí <emph>no</emph></l></lg></sp>
          <sp><speaker>Criado</speaker><lg type="free" part="F"><l part="F">Llega a hablarle ya.</l></lg></sp>
        </div1>
        """)

      for file <- ["act-1.html", "text.html"] do
        ghost = dir |> page(play, file) |> LazyHTML.query(".ghost")

        # Hidden as the opening fragment's own stage is, or the continuing fragment would
        # keep a gap the width of the words that are no longer shown.
        assert [lead] = Enum.to_list(ghost)
        assert lead |> LazyHTML.query(".sdi") |> Enum.map(&LazyHTML.text/1) == ["(bajo)"]
        assert squish(LazyHTML.text(lead)) == "(bajo) A mí no"
      end
    end
  end

  # A stanza's first line steps in (rend="indent", 1,968 opening parts on dev): the lead
  # carries the step, or the later part starts 2em short of where the earlier one ended.
  test "a part after an indented opening part is lined up past the indent too" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><lg><l n="1" part="I" rend="indent">Verso</l></lg></sp>
        <sp><speaker>B</speaker><lg><l part="F">partido</l></lg></sp>
      </div1>
      """)

    [ghost] = dir |> page(play, "act-1.html") |> LazyHTML.query(".ghost") |> Enum.to_list()
    assert ghost |> LazyHTML.attribute("class") |> hd() |> String.split() == ["ghost", "indent"]
    assert read!(dir, "assets/style.css") =~ ~r/^\.ghost\.indent \{[^}]*padding-left: 2em/m
  end

  # EMOTHE0284's "O molto", EMOTHE0283's "Hippolita!": a part with no words before it to
  # line up after was printed at the margin. emothe.uv.es indented it by a fixed step
  # (`.versoM`, `.versoF`), as the play page does.
  test "a middle or last part with no first part before it is indented by a fixed step" do
    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <sp><speaker>A</speaker><p>Prosa.</p></sp>
        <sp><speaker>B</speaker><lg type="free" part="F"><l part="F">O molto</l></lg></sp>
        <sp><speaker>C</speaker><lg type="free" part="M"><l part="M">Hippolita!</l></lg></sp>
        <sp><speaker>D</speaker><lg type="free"><l n="1" part="I">Verso</l><l part="F">partido</l></lg></sp>
      </div1>
      """)

    for file <- ["act-1.html", "text.html"] do
      classes =
        for line <- dir |> page(play, file) |> LazyHTML.query(".l") |> Enum.to_list(),
            into: %{},
            do:
              {squish(LazyHTML.text(line)),
               line |> LazyHTML.attribute("class") |> hd() |> String.split()}

      assert classes["O molto"] == ["l", "part-f"]
      assert classes["Hippolita!"] == ["l", "part-m"]
      # B2 (2026-11-02): every later part takes the step, the lined-up one too, so a
      # reader without scripts sees the step; site.js lines it up where it fits.
      assert classes["Verso partido"] == ["l", "part-f"]
    end

    css = read!(dir, "assets/style.css")
    assert css =~ ~r/^\.l\.part-m \.t \{[^}]*padding-left/m
    assert css =~ ~r/^\.l\.part-f \.t \{[^}]*padding-left/m
    # The lead shows only once the script has measured the line and found room.
    assert css =~ ~r/^\.ghost \{[^}]*display: none/m
    assert css =~ ~r/\[data-aligned\] > \.ghost \{[^}]*visibility: hidden/
  end
end
