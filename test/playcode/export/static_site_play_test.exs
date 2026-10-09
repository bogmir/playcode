defmodule Playcode.Export.StaticSitePlayTest do
  @moduledoc "A play's reading pages in the static site: one per act, the full text, statistics."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers
  import Playcode.TestFixtures

  @two_acts """
  <div1 type="jornada" n="1"><head>Jornada I</head>
    <stage>Salen músicos cantando</stage>
    <sp><speaker>Segismundo</speaker>
      <lg type="redondilla">
        <l n="1">¡Válgame el cielo!, ¿qué veo?</l>
        <l n="2">Dulce <emph>sueño</emph> mío</l>
        <l n="3">uno &amp; &lt;script&gt;alert(1)&lt;/script&gt;</l>
        <l n="4">con mucha duda lo creo.</l>
      </lg>
      <lg type="redondilla"><l n="5">¿Yo en palacios suntuosos?</l></lg>
    </sp>
    <sp><speaker>Clarín</speaker><lg type="free" part="I"><l n="6" part="I">A mí.</l></lg></sp>
    <sp><speaker>Criado 2</speaker><lg type="free" part="F"><l part="F">Llega a hablarle ya.</l></lg></sp>
  </div1>
  <div1 type="jornada" n="2"><head>Jornada II</head>
    <sp><speaker>Clotaldo</speaker><p>Señor, despierta.</p></sp>
  </div1>
  """

  defp publish!(body) do
    play = import_tei!(tei(body: body))
    {play, generate!([play], all: true)}
  end

  defp page(dir, play, file), do: html!(dir, "plays/#{play.code}/#{file}")
  defp ids(html), do: html |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")

  defp next(html),
    do: html |> LazyHTML.query(~s(a[rel="next"])) |> LazyHTML.attribute("href") |> Enum.uniq()

  defp links(html), do: html |> LazyHTML.query("main a") |> LazyHTML.attribute("href")

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
    play = import_tei!(tei(body: @two_acts))
    dir = generate!([play], all: true)

    assert read!(dir, "plays/#{play.code}/#{play.code}.xml") ==
             Playcode.Export.TeiXml.generate(Playcode.Catalogue.get_play!(play.id))
  end

  test "each act has its own page, linked to the acts before and after it" do
    {play, dir} = publish!(@two_acts)
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
    {play, dir} = publish!(@two_acts)
    act = page(dir, play, "act-1.html")

    assert act |> LazyHTML.query("#l2 em") |> LazyHTML.text() == "sueño"
    assert act |> LazyHTML.query("#l2") |> LazyHTML.text() =~ "Dulce sueño mío"
    refute read!(dir, "plays/#{play.code}/act-1.html") =~ "&lt;&lt;"
    assert act |> LazyHTML.query("#l3") |> LazyHTML.text() =~ "uno & <script>alert(1)</script>"

    assert act |> LazyHTML.query("script") |> LazyHTML.attribute("src") == [
             "../../assets/site.js"
           ]

    assert act |> LazyHTML.query("#l3 script") |> Enum.empty?()
    assert read!(dir, "plays/#{play.code}/act-1.html") =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
  end

  test "the second half of a split verse starts where the first half ended" do
    {play, dir} = publish!(@two_acts)

    assert texts(page(dir, play, "act-1.html"), ~s([aria-hidden="true"])) == ["A mí."]
  end

  test "a verse form is named once, where its passage starts" do
    {play, dir} = publish!(@two_acts)
    text = LazyHTML.text(page(dir, play, "act-1.html"))

    assert length(String.split(text, "Redondilla")) == 2
  end

  test "the full text carries every act on one page" do
    {play, dir} = publish!(@two_acts)
    full = page(dir, play, "text.html")

    assert Enum.filter(texts(full, "h2"), &String.starts_with?(&1, "Jornada")) == [
             "Jornada I",
             "Jornada II"
           ]

    assert LazyHTML.text(full) =~ "Señor, despierta."
  end

  test "a play that numbers each scene from 1 still gives every line its own anchor" do
    {play, dir} =
      publish!("""
      <div1 type="act" n="1"><head>Act I</head>
        <div2 type="scene" n="1"><head>Scene 1</head><sp><speaker>A</speaker><l n="1">one</l><l n="2">two</l></sp></div2>
        <div2 type="scene" n="2"><head>Scene 2</head><sp><speaker>B</speaker><l n="1">uno</l><l n="2">dos</l></sp></div2>
      </div1>
      """)

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

  describe "the statistics page" do
    test "a verse play its curator calls prose measures its characters in words" do
      play = import_tei!(tei(body: @two_acts))
      {:ok, play} = Playcode.Catalogue.update_play(play, %{form: "prose"})
      dir = generate!([play], all: true)

      assert LazyHTML.text(page(dir, play, "statistics.html")) =~ "most words"
    end

    test "shows the metrical synopsis, the characters and who shares the stage" do
      {play, dir} = publish!(@two_acts)
      stats = page(dir, play, "statistics.html")

      assert rows(stats, "#synopsis tbody tr") == [
               ["I", "Redondilla", "1–5", "5"],
               ["I", "Unmarked", "6", "1"]
             ]

      characters = rows(stats, "#characters tbody tr")
      assert Enum.map(characters, &hd/1) == ["Segismundo", "Criado 2", "Clarín", "Clotaldo"]
      assert ["Segismundo", "1", "5" | _] = hd(characters)
      assert "I, 1" in hd(characters)

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
    end
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

  describe "a division too long for one page" do
    setup do
      # 72,000 bytes of text per scene: 144,000 in the act, over the 120,000 threshold.
      words = String.duplicate("palabra ", 9_000)

      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I<note n="1" type="autor"><p>Del encabezado.</p></note></head>
          <stage>Salen todos<note n="2" type="editor"><p>Del acto.</p></note></stage>
          <div2 type="escena" n="1"><head>Escena<note n="3" type="traductor"><p>Del título.</p></note> 1</head><sp><speaker>A<note n="4" type="editor_critico"><p>Del hablante.</p></note></speaker><p>#{words}uno<note n="5" type="editor_digital"><p>De la escena uno.</p></note></p></sp></div2>
          <div2 type="escena" n="2"><head>Escena 2</head><sp><speaker>B</speaker><p>#{words}dos<note n="6" type="editor"><p>De la escena dos.</p></note></p></sp></div2>
        </div1>
        <div1 type="acto" n="2"><head>Acto II</head><sp><speaker>A</speaker><p>fin</p></sp></div1>
        """)

      %{play: play, dir: dir}
    end

    test "gets a page per scene, walked in order", %{play: play, dir: dir} do
      act = page(dir, play, "act-1.html")

      assert LazyHTML.text(act) =~ "Salen todos"
      refute LazyHTML.text(act) =~ "palabra"
      assert "act-1-s1.html" in links(act)
      assert "act-1-s2.html" in links(act)

      assert next(act) == ["act-1-s1.html"]
      assert next(page(dir, play, "act-1-s1.html")) == ["act-1-s2.html"]
      assert next(page(dir, play, "act-1-s2.html")) == ["act-2.html"]

      second = LazyHTML.text(page(dir, play, "act-1-s2.html"))
      assert second =~ "palabra dos"
      refute second =~ "palabra uno"
    end

    test "lists on each page the notes that page shows, numbered through the play", %{
      play: play,
      dir: dir
    } do
      listed = fn file ->
        page(dir, play, file) |> LazyHTML.query("li[popover]") |> LazyHTML.attribute("id")
      end

      # The act's own page lists its heading's and its stage direction's; a scene's page
      # lists the act heading it prints again, then its own, the speaker's before the lines'.
      assert listed.("act-1.html") == ["note-1", "note-2"]
      assert listed.("act-1-s1.html") == ["note-1", "note-3", "note-4", "note-5"]
      assert listed.("act-1-s2.html") == ["note-1", "note-6"]
      assert listed.("act-2.html") == []
      assert listed.("text.html") == Enum.map(1..6, &"note-#{&1}")
    end

    test "puts each note's number where its text is: heading, stage direction, speaker, line",
         %{play: play, dir: dir} do
      # The note a button opens, by the button's label, and the tag it sits in.
      opens = fn page, label, within ->
        page
        |> LazyHTML.query(~s(#{within} button[aria-label="#{label}"]))
        |> LazyHTML.attribute("popovertarget")
      end

      split = page(dir, play, "act-1.html")
      assert opens.(split, "Author's note 1", "h2") == ["note-1"]
      assert opens.(split, "Editor's note 2", "main") == ["note-2"]
      assert squish(LazyHTML.text(split)) =~ "Salen todos2"

      for file <- ["act-1-s1.html", "act-1-s2.html", "text.html"] do
        scene = page(dir, play, file)
        assert opens.(scene, "Author's note 1", "h2") == ["note-1"]
      end

      for file <- ["act-1-s1.html", "text.html"] do
        scene = page(dir, play, file)
        assert opens.(scene, "Translator's note 3", "h3") == ["note-3"]
        assert opens.(scene, "Critical editor's note 4", "main") == ["note-4"]
        assert opens.(scene, "Digital editor's note 5", "main") == ["note-5"]
        assert squish(LazyHTML.text(scene)) =~ "Escena3 1"
        assert squish(LazyHTML.text(scene)) =~ "A4 palabra"
      end

      for file <- ["act-1-s2.html", "text.html"] do
        scene = page(dir, play, file)
        assert opens.(scene, "Editor's note 6", "main") == ["note-6"]
        assert squish(LazyHTML.text(scene)) =~ "palabra dos6"
      end
    end

    test "the full text still holds every scene, once", %{play: play, dir: dir} do
      text = read!(dir, "plays/#{play.code}/text.html")

      assert text =~ "palabra uno"
      assert text =~ "palabra dos"
      # The scene pages are not divisions of their own: walked as such, the act would
      # be printed three times over, ids and all.
      anchors = ids(page(dir, play, "text.html"))
      assert anchors == Enum.uniq(anchors)
    end

    test "keeps its own anchor on its own page, which the rail links", %{play: play, dir: dir} do
      assert "act-1" in ids(page(dir, play, "act-1.html"))

      for scene <- ["act-1-s1.html", "act-1-s2.html"] do
        rail = page(dir, play, scene) |> LazyHTML.query(~s(nav[aria-label="Contents"] a))
        assert "act-1.html" in LazyHTML.attribute(rail, "href")
      end
    end

    test "a note's search result lands on the first page that shows its marker", %{
      play: play,
      dir: dir
    } do
      {"lines", _, %{"lines" => notes}} = load_js!(dir, "search/lines/#{play.code}/n0.js")

      # The act heading's note is printed again on every scene page; its result goes to
      # the act's own page. A scene heading's cites the scene.
      assert Enum.map(notes, &Enum.take(&1, 3)) == [
               ["act-1", "nref-1", "Acto I"],
               ["act-1", "nref-2", "I"],
               ["act-1-s1", "nref-3", "Acto I, Escena 1"],
               ["act-1-s1", "nref-4", "I"],
               ["act-1-s1", "nref-5", "I"],
               ["act-1-s2", "nref-6", "I"]
             ]

      for [slug, anchor | _] <- notes do
        assert anchor in ids(page(dir, play, slug <> ".html"))
      end
    end

    test "a search result lands on the scene's page", %{play: play, dir: dir} do
      {"lines", _, %{"lines" => lines}} = load_js!(dir, "search/lines/#{play.code}/0.js")

      assert ["act-1-s2" | _] =
               Enum.find(lines, &String.ends_with?(Enum.at(&1, 5), "palabra dos"))
    end
  end

  describe "the Notes page" do
    setup do
      {play, dir} =
        publish!("""
        <div1 type="acto" n="1"><head>Acto I<note n="1"><p>Del encabezado.</p></note></head>
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

      assert LazyHTML.attribute(items, "data-type") == [
               "untyped",
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
               ["", "untyped", "editor", "traductor"]

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

  test "the title page lists the bibliography by kind, linked from the contents, without researchers' notes" do
    play = import_tei!(tei(body: @two_acts))

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
    assert texts(title, "#bibliography h4") == ["Français"]
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
end
