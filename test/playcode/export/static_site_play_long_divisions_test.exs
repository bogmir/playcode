defmodule Playcode.Export.StaticSitePlayLongDivisionsTest do
  @moduledoc "A play's act too long for one page, split into pages of its own."
  use Playcode.DataCase, async: true

  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers
  import Playcode.StaticSitePlayHelpers

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

    # Anchors are counted through the play, not per page: the full text prints every page,
    # and a line keeps one address on its scene's page and there.
    test "a line has the same anchor on its scene's page and in the full text", %{
      play: play,
      dir: dir
    } do
      assert line_ids(page(dir, play, "act-1-s2.html")) == ~w(p2)
      assert line_ids(page(dir, play, "act-2.html")) == ~w(p3)
      assert line_ids(page(dir, play, "text.html")) == ~w(sd1 p1 p2 p3)
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

  # As the file has it: the list that opens an act stands before the act's own text.
  test "a long act's opening cast list prints on its page, above the act's own text" do
    words = String.duplicate("palabra ", 9_000)

    {play, dir} =
      publish!("""
      <div1 type="acto" n="1"><head>Acto I</head>
        <castList><head>Figuras del acto</head><castItem><role xml:id="A">A</role></castItem></castList>
        <stage>Salen todos</stage>
        <div2 type="escena" n="1"><head>Escena 1</head><sp><speaker>A</speaker><p>#{words}uno</p></sp></div2>
        <div2 type="escena" n="2"><head>Escena 2</head><sp><speaker>A</speaker><p>#{words}dos</p></sp></div2>
      </div1>
      """)

    text = &(page(dir, play, &1) |> LazyHTML.query(".division") |> LazyHTML.text())

    assert in_order?(text.("act-1.html"), ["Figuras del acto", "Salen todos"])
    refute text.("act-1-s1.html") =~ "Figuras del acto"
  end
end
