defmodule PlaycodeWeb.PlayShowLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers

  import Playcode.TestFixtures, only: [bibliography_fixture: 2]

  alias Playcode.TestFixtures

  @italics ~w(Aminta Damone Egle Spela) ++
             ["The courtiers", "La Scena è in Atene.", "Dramatis Personae", "Actus Primus"]

  test "italics in the text render as emphasis, without the storage markers", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <sp><speaker>ANA</speaker><lg><l n="1">Dulce <emph>sueño</emph> mío</l></lg></sp>
          </div1>
          """
        )
      )

    TestFixtures.mark_complete!(play)

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert "sueño" in (html
                       |> LazyHTML.from_fragment()
                       |> LazyHTML.query("em")
                       |> Enum.map(&LazyHTML.text/1))

    refute html =~ "&lt;&lt;"
  end

  # Question 10: readers see every break of a paratext, as its file gives them.
  test "a paratext's line breaks are shown", %{conn: conn} do
    play =
      tei(
        front:
          ~s(<div type="dedicatoria"><p>The banished cavaliers!<lb/>A roving blade!</p></div>)
      )
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    # A <br> since 2026-10-16, the one rule for a line break that the play text shares;
    # it used to be the \n itself, shown by the paratext's white-space: pre-line.
    assert html =~ ~r{The banished cavaliers!<br/?>A roving blade!}
  end

  # Where emothe.uv.es prints them: after the text, each listed in the navigation, an
  # untitled one by its kind.
  test "the paratexts after the text follow it", %{conn: conn} do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><head>ACTO I</head><sp><speaker>A</speaker><p>Verso final.</p></sp></div1>),
        back: """
        <div type="epilogo"><head>EPILOGUE</head><p>The banished <emph>cavaliers</emph>!</p></div>
        <div type="colofon"><p>Loado sea.</p></div>
        """
      )
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")

    assert [_text, after_text] = String.split(html, "Verso final.")
    assert after_text =~ ~r/EPILOGUE.*<em>cavaliers<\/em>.*Loado sea\./s
    assert has_element?(view, "nav a", "EPILOGUE")
    assert has_element?(view, "nav a", t("Colophon"))
  end

  describe "an inline stage direction" do
    setup %{conn: conn} do
      play =
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <sp><speaker>CHIMÈNE</speaker><lg><l n="1"><stage>(A Léonor.)</stage>Allez l'entretenir.</l></lg></sp>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view, html: html}
    end

    defp squish(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

    test "reads in its line, set apart", %{html: html} do
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query(".inline-stage") |> Enum.map(&LazyHTML.text/1) == [
               "(A Léonor.)"
             ]

      assert squish(LazyHTML.text(doc)) =~ "(A Léonor.) Allez l'entretenir."
      refute html =~ "&lt;stage"
    end

    # The checkbox is a plain input that pushes this event; LiveViewTest cannot click a label.
    test "goes when the stage directions are hidden, and the words stay", %{view: view} do
      html = render_click(view, "toggle_stage_directions")

      refute html =~ "(A Léonor.)"
      # The page's text, not its markup: the markup escapes the apostrophe.
      assert squish(html |> LazyHTML.from_fragment() |> LazyHTML.text()) =~ "Allez l'entretenir."
    end
  end

  describe "a paragraph partly aside" do
    setup %{conn: conn} do
      play =
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <sp><speaker>BEATRICE</speaker><p>Me consola. <seg type="aside">(Cielo, te ringrazio.)</seg> El me consola.</p></sp>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view, html: html}
    end

    test "reads whole, without its markers", %{html: html} do
      assert squish(html |> LazyHTML.from_fragment() |> LazyHTML.text()) =~
               "Me consola. (Cielo, te ringrazio.) El me consola."

      refute html =~ "&lt;aside"
    end

    # Hiding the asides used to hide a paragraph holding one, its other words with it.
    test "stays when the asides are hidden", %{view: view} do
      html = render_click(view, "toggle_asides")

      assert squish(html |> LazyHTML.from_fragment() |> LazyHTML.text()) =~ "El me consola."
    end
  end

  describe "prose line breaks and numbers" do
    setup %{conn: conn} do
      play =
        tei(
          body: """
          <div1 type="acto" n="1"><head>Act II</head>
            <sp><speaker>HAMLET</speaker><p n="1319">Beggar that I am, <lb n="1320"/>but I thank you. <lb/>Come, come.</p></sp>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view, html: html}
    end

    test "a break is a new line and the numbers show where printed lines start", %{html: html} do
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query(".pn") |> Enum.map(&LazyHTML.text/1) == ["1319", "1320"]
      # The page's HTML as LiveViewTest serialises it: a void <br> may come out as <br/>.
      assert html =~ ~r{thank you\.<br/?>Come, come\.}
      refute html =~ "&lt;lb"
    end

    # The checkbox is a plain input that pushes this event, as the stage directions' does.
    test "the numbers go when the line numbers are hidden, and the words stay", %{view: view} do
      html = render_click(view, "toggle_line_numbers")
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query(".pn") |> Enum.count() == 0
      assert squish(LazyHTML.text(doc)) =~ "Beggar that I am, but I thank you."
    end
  end

  # The line's markup is built by hand (PlayText.part_html/2), not by HEEx, so nothing
  # else escapes it. The assertions read the raw HTML: LazyHTML.text decodes it again and
  # passes whether the page escaped or not.
  test "text typed with markup characters is escaped, in a line, in italics and in a stage", %{
    conn: conn
  } do
    play =
      tei(
        body: """
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>ANA</speaker><lg><l n="1">Di &lt;script&gt;alert(1)&lt;/script&gt; &amp; "adiós" <emph>&lt;b&gt;fuerte</emph> <stage type="delivery">(&lt;script&gt;alert(2)&lt;/script&gt; &amp; "bajo" <emph>&lt;i&gt;x</emph>)</stage></l></lg></sp>
        </div1>
        """
      )
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")

    for html <- [html, render(view)] do
      assert html =~ "Di &lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;adiós&quot;"
      assert html =~ "<em>&lt;b&gt;fuerte</em>"

      # Each piece of a stage is in a span of its own, an italic one included.
      assert html =~
               ~s|<span class="inline-stage">(&lt;script&gt;alert(2)&lt;/script&gt; &amp; &quot;bajo&quot; </span>|

      assert html =~ ~s|<span class="inline-stage"><em>&lt;i&gt;x</em></span>|

      refute html =~ "<script>alert"
      refute html =~ "<b>fuerte"
      refute html =~ "<i>x"
    end
  end

  test "a note is a number after its word, opening the note with its type, term and text",
       %{conn: conn} do
    play =
      tei(
        body: """
        <div1 type="acto" n="1"><head>Acto I</head>
          <sp><speaker>ANA</speaker><lg><l n="1">Nous voyent<note n="6089" type="traductor"><term>voyent</term><p>Forma arcaica.</p></note> dans la ville</l></lg></sp>
        </div1>
        """
      )
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")
    doc = LazyHTML.from_fragment(html)
    squish = &(&1 |> String.replace(~r/\s+/u, " ") |> String.trim())

    assert [target] =
             doc
             |> LazyHTML.query(~s(button[aria-label="#{t("Translator's note")} 1"]))
             |> LazyHTML.attribute("popovertarget")

    note = squish.(doc |> LazyHTML.query("#" <> target) |> LazyHTML.text())
    assert note =~ t("Translator's note")
    assert note =~ "voyent"
    assert note =~ "Forma arcaica."

    assert squish.(LazyHTML.text(doc)) =~ "Nous voyent1 dans la ville"
    assert doc |> LazyHTML.text() |> String.split("Forma arcaica.") |> length() == 2
  end

  test "the Notes view prints a glossed word in italics as italics", %{conn: conn} do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><sp><speaker>ANA</speaker><l n="1">Nous voyent<note n="2" type="editor"><term><emph>voyent</emph></term><p>Forma arcaica.</p></note> dans la ville</l></sp></div1>)
      )
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    html = view |> element("#play-sections-panel button", t("Notes")) |> render_click()

    refute html =~ "&lt;&lt;"

    assert "voyent" in (html
                        |> LazyHTML.from_fragment()
                        |> LazyHTML.query("#play-tab-notes em")
                        |> Enum.map(&LazyHTML.text/1))
  end

  describe "the Notes view" do
    setup %{conn: conn} do
      play =
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I</head>
            <div2 type="escena" n="1"><head>Escena 1</head>
              <sp><speaker>ANA<note n="1" type="falta_tipo"><p>La dama.</p></note></speaker>
                <lg><l n="12">Nous voyent<note n="2" type="traductor"><term>voyent</term><p>Forma arcaica.</p><p>Dos sílabas.</p></note> dans la ville</l></lg>
                <lg><l n="13">Ni un ratón se ha movido.<note n="3" type="traductor"><p>De soldado.</p></note></l></lg>
              </sp>
            </div2>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view}
    end

    defp open_notes(view),
      do: view |> element("#play-sections-panel button", t("Notes")) |> render_click()

    defp texts(doc, selector),
      do: doc |> LazyHTML.query(selector) |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

    defp listed(html) do
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#play-tab-notes li")
      |> Enum.map(&(&1 |> LazyHTML.text() |> String.replace(~r/\s+/u, " ") |> String.trim()))
    end

    test "lists every note: number, type, glossed word, where it is, and its text", %{
      view: view
    } do
      html = open_notes(view)
      doc = LazyHTML.from_fragment(html)

      assert doc |> LazyHTML.query("#play-tab-notes li") |> LazyHTML.attribute("value") ==
               ["1", "2", "3"]

      # Each part by itself: LiveViewTest drops the spaces between tags.
      parts = fn selector -> texts(doc, "#play-tab-notes li " <> selector) end

      # A type with no label of its own is a plain Note.
      assert parts.("b") == [t("Note"), t("Translator's note"), t("Translator's note")]

      assert parts.("i") == ["ANA", "voyent", "movido"]

      assert parts.("button") == [
               "Acto I, Escena 1",
               "Acto I, Escena 1, #{t("line %{n}", n: 12)}",
               "Acto I, Escena 1, #{t("line %{n}", n: 13)}"
             ]

      assert parts.("p + p") == ["La dama.", "Forma arcaica.", "Dos sílabas.", "De soldado."]
    end

    test "filters by type", %{view: view} do
      open_notes(view)

      html =
        view
        |> element("#play-tab-notes button", t("Translator's note"))
        |> render_click()

      assert [voyent, movido] = listed(html)
      assert voyent =~ "voyent"
      assert movido =~ "movido"

      assert texts(LazyHTML.from_fragment(html), "#play-tab-notes [role=group] button") == [
               t("All"),
               t("Note"),
               t("Translator's note")
             ]

      html = view |> element("#play-tab-notes button", t("All")) |> render_click()
      assert length(listed(html)) == 3
    end

    test "takes the reader back to the note's word in the text", %{view: view} do
      open_notes(view)

      html =
        view
        |> element(
          "#play-tab-notes li:nth-child(2) button",
          "Acto I, Escena 1, #{t("line %{n}", n: 12)}"
        )
        |> render_click()

      assert_push_event(view, "scroll-to", %{id: "nref-" <> _ = id})
      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("#play-tab-text") |> Enum.any?()

      assert html |> LazyHTML.from_fragment() |> LazyHTML.query("#" <> id) |> LazyHTML.text() ==
               "2"
    end

    test "ignores a note id that is not the play's", %{view: view} do
      open_notes(view)
      render_click(view, "show_note", %{"id" => Ecto.UUID.generate()})

      refute_push_event(view, "scroll-to", _)
      assert has_element?(view, "#play-tab-notes")
    end
  end

  test "a note in a division with no heading is placed by the division's type", %{conn: conn} do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="3">uno<note n="1" type="editor"><p>Glosa.</p></note></l></sp></div1>)
      )
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
    view |> element("#play-sections-panel button", t("Notes")) |> render_click()

    assert has_element?(view, "#play-tab-notes li button", "Acto, #{t("line %{n}", n: 3)}")
  end

  test "a play without notes has no Notes view", %{conn: conn} do
    play =
      tei(body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>))
      |> import_tei!()
      |> TestFixtures.mark_complete!()

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    refute has_element?(view, "#play-sections-panel button", t("Notes"))
  end

  describe "a note's number, wherever its word is" do
    # One note in each place the page draws text: an act heading, a stage direction, a
    # scene heading, a speaker, a verse line, a prose paragraph and a trailer.
    setup %{conn: conn} do
      play =
        tei(
          body: """
          <div1 type="acto" n="1"><head>Acto I<note n="1" type="autor"><p>Del encabezado.</p></note></head>
            <stage>Salen todos<note n="2" type="editor"><p>Del acto.</p></note></stage>
            <div2 type="escena" n="1"><head>Escena<note n="3" type="traductor"><p>Del título.</p></note> 1</head>
              <sp><speaker>ANA<note n="4" type="editor_critico"><p>Del hablante.</p></note></speaker><lg><l n="1">verso<note n="5" type="editor_digital"><p>Del verso.</p></note></l></lg></sp>
              <sp><speaker>BLAS</speaker><p>prosa<note n="6"><p>De la prosa.</p></note></p></sp>
              <trailer>FIN<note n="7" type="autor"><p>Del cierre.</p></note></trailer>
            </div2>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")
      %{doc: LazyHTML.from_fragment(html)}
    end

    # The text of the note a button opens, by the button's label, within `within`.
    defp opened_by(doc, label, within) do
      assert [target] =
               doc
               |> LazyHTML.query(~s(#{within} button[aria-label="#{label}"]))
               |> LazyHTML.attribute("popovertarget"),
             "no #{within} button labelled #{label}"

      doc |> LazyHTML.query("#" <> target) |> LazyHTML.text()
    end

    test "an act heading, a scene heading, a stage direction, a speaker, a line, a paragraph and a trailer each carry theirs",
         %{doc: doc} do
      text = doc |> LazyHTML.text() |> String.replace(~r/\s+/u, " ")

      assert opened_by(doc, "#{t("Author's note")} 1", "h2") =~ "Del encabezado."
      assert text =~ "Acto I1"

      assert opened_by(doc, "#{t("Editor's note")} 2", "main") =~ "Del acto."
      assert text =~ "Salen todos2"

      assert opened_by(doc, "#{t("Translator's note")} 3", "h3") =~ "Del título."
      assert text =~ "Escena3 1"

      assert opened_by(doc, "#{t("Critical editor's note")} 4", "main") =~ "Del hablante."
      assert text =~ "ANA4"

      assert opened_by(doc, "#{t("Digital editor's note")} 5", "main") =~ "Del verso."
      assert text =~ "verso5"

      assert opened_by(doc, "#{t("Note")} 6", "main") =~ "De la prosa."
      assert text =~ "prosa6"

      assert opened_by(doc, "#{t("Author's note")} 7", "main") =~ "Del cierre."
      assert text =~ "FIN7"
    end

    test "the notes are listed once each, in reading order: the speaker's before the lines'",
         %{doc: doc} do
      assert doc |> LazyHTML.query("li[popover]") |> LazyHTML.attribute("value") ==
               Enum.map(1..7, &to_string/1)

      ids = doc |> LazyHTML.query("li[popover]") |> LazyHTML.attribute("id")
      assert ids == Enum.uniq(ids)
    end
  end

  test "the play's form is the curator's when one is set", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">un verso</l></sp></div1>)
        )
      )

    {:ok, _} = Playcode.Catalogue.update_play(play, %{form: "mixed"})
    TestFixtures.mark_complete!(play)
    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert html =~ t("Verse and prose")
  end

  test "renders navigation panel with metadata and play section links", %{conn: conn} do
    %{play: play, act: act, scene: scene} = TestFixtures.play_with_structure_fixture()

    TestFixtures.mark_complete!(play)

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#play-sections-panel")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-overview']")
    assert has_element?(view, "#scroll-spy-nav a[href='#div-#{act.id}']")
    assert has_element?(view, "#scroll-spy-nav a[href='#div-#{scene.id}']")
  end

  test "tab navigation switches between text and statistics", %{conn: conn} do
    %{play: play} = TestFixtures.play_with_structure_fixture()

    TestFixtures.mark_complete!(play)

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#play-tab-text")
    refute has_element?(view, "#play-tab-statistics")

    view
    |> element("#scroll-spy-nav button[phx-value-tab='statistics']")
    |> render_click()

    assert has_element?(view, "#play-tab-statistics")
    refute has_element?(view, "#play-tab-text")

    view
    |> element("#scroll-spy-nav button[phx-value-tab='text']")
    |> render_click()

    assert has_element?(view, "#play-tab-text")
    refute has_element?(view, "#play-tab-statistics")
  end

  # "Procedencia" on emothe.uv.es; a placeholder ("Texto base") is not printed.
  # Where emothe.uv.es prints it: after the cast list, once, not among the front matter
  # above the text.
  test "the scene of the action follows the cast list", %{conn: conn} do
    play =
      import_tei!(
        tei(
          front: """
          <div type="dedicatoria"><head>Al lector</head><p>Dedicada.</p></div>
          <div type="elenco"><castList><castItem><role xml:id="DON">Don Juan</role></castItem></castList></div>
          <set><head>SCENE:</head><p>An English wood.</p></set>
          """
        )
      )

    TestFixtures.mark_complete!(play)
    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert [_before_cast, after_cast] = String.split(html, "Don Juan")
    assert [_, _] = String.split(after_cast, "SCENE:")
    assert [_, _] = String.split(after_cast, "An English wood.")
    refute html =~ ~r/An English wood.*An English wood/s
  end

  test "without a cast list, the scene of the action is printed with the front matter",
       %{conn: conn} do
    play = import_tei!(tei(front: "<set><p>An English wood.</p></set>"))

    TestFixtures.mark_complete!(play)
    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert html =~ "An English wood."
  end

  # Stored as <<…>>, as in the play's lines, and printed as italics, never as the markers:
  # the sidebar lists a heading in plain text.
  test "italics outside the text are printed as italics", %{conn: conn} do
    play =
      import_tei!(
        tei(
          source_desc:
            "<bibl><title><emph>Aminta</emph></title><note>Tasso. <emph>Aminta</emph>. Venezia.</note></bibl>",
          front: """
          <div type="dedicatoria"><head>A <emph>Damone</emph></head><p>Dedica <emph>Egle</emph>.</p></div>
          <div type="elenco"><head><emph>Dramatis Personae</emph></head><castList>
            <castItem><role xml:id="CORT"><emph>The courtiers</emph></role><roleDesc>(<emph>Spela</emph>), a servant</roleDesc></castItem>
          </castList></div>
          <set><p><emph>La Scena è in Atene.</emph></p></set>
          """,
          body:
            ~s(<div1 type="acto" n="1"><head><emph>Actus Primus</emph></head><sp><speaker>CORT</speaker><p>Texto.</p></sp></div1>)
        )
      )

    TestFixtures.mark_complete!(play)
    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    refute html =~ "&lt;&lt;"
    ems = html |> LazyHTML.from_fragment() |> LazyHTML.query("em") |> Enum.map(&LazyHTML.text/1)

    for italic <- @italics, do: assert(italic in ems, italic)
  end

  test "a source says where its digital text came from, unless that is a placeholder",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          source_desc: """
          <bibl><title>Aminta</title><note>Tasso, Torquato. Aminta.</note>
            <distributor>IntraText Digital Library</distributor></bibl>
          <bibl><title>Hamlet</title><distributor>Texto base</distributor></bibl>
          <bibl><title>El pastor fido</title><distributor>ProcedenciaFuente</distributor></bibl>
          """
        )
      )

    TestFixtures.mark_complete!(play)
    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#meta-sources", t("Provenance") <> ": IntraText Digital Library")
    refute has_element?(view, "#meta-sources", "Texto base")
    refute has_element?(view, "#meta-sources", "ProcedenciaFuente")
  end

  test "metadata links appear when metadata exists", %{conn: conn} do
    play = TestFixtures.play_with_metadata_fixture()

    TestFixtures.mark_complete!(play)

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#scroll-spy-nav a[href='#meta-sources']")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-editors']")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-note-1']")
  end

  test "renders the research metadata panel when the play has a historical time", %{conn: conn} do
    play =
      TestFixtures.play_fixture(%{
        "historical_time" => "antiguedad_clasica",
        "historical_time_note" => "First century BC."
      })

    TestFixtures.mark_complete!(play)

    {:ok, view, html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#meta-study")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-study']")
    # The page renders in Spanish by default, so the vocabulary label is translated.
    assert html =~ "Antigüedad clásica"
    assert html =~ "First century BC."
  end

  test "omits the research metadata panel when there is no historical time", %{conn: conn} do
    play = TestFixtures.play_fixture()

    TestFixtures.mark_complete!(play)

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    refute has_element?(view, "#meta-study")
    refute has_element?(view, "#scroll-spy-nav a[href='#meta-study']")
  end

  test "shows the composition date range", %{conn: conn} do
    play =
      TestFixtures.play_fixture(%{
        "code" => "CDPUB1",
        "composition_date_from" => 1606,
        "composition_date_to" => 1607,
        "composition_date_note" => "1606; 1607"
      })

    TestFixtures.mark_complete!(play)

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    # Inside the study section, after its label: not merely somewhere on the page, where
    # a code or a line number could match.
    study = view |> element("#meta-study") |> render()
    assert study =~ ~r/#{t("Composition")}.*?1606–1607/s
    assert study =~ "1606; 1607"
  end

  test "collapses a single year", %{conn: conn} do
    play =
      TestFixtures.play_fixture(%{
        "code" => "CDPUB2",
        "composition_date_from" => 1614,
        "composition_date_to" => 1614
      })

    TestFixtures.mark_complete!(play)

    {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")

    assert html =~ "1614"
    refute html =~ "1614–1614"
  end

  test "the study section appears for a dating alone", %{conn: conn} do
    play =
      TestFixtures.play_fixture(%{
        "code" => "CDPUB3",
        "composition_date_from" => 1614,
        "composition_date_to" => 1614
      })

    TestFixtures.mark_complete!(play)

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#meta-study")
    assert has_element?(view, "#scroll-spy-nav a[href='#meta-study']")
  end

  # The changeset permits a note with no years, and the FileMaker sync writes exactly
  # that (EMOTHE0341_EastwardHo). Without this the value is invisible to every reader.
  test "a note with no years still renders, with its own section and sidebar entry", %{conn: conn} do
    play =
      TestFixtures.play_fixture(%{
        "code" => "CDPUB4",
        "composition_date_note" => "¿1694? y ¿1605?"
      })

    TestFixtures.mark_complete!(play)

    {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

    assert has_element?(view, "#scroll-spy-nav a[href='#meta-study']")

    assert view |> element("#meta-study") |> render() =~
             ~r/#{t("Composition")}.*?¿1694\? y ¿1605\?/s
  end

  describe "the places panel" do
    test "is absent when the play has no places", %{conn: conn} do
      play = Playcode.TestFixtures.play_fixture()
      TestFixtures.mark_complete!(play)
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      refute has_element?(view, "#meta-places")
    end

    test "lists settings before mentions, with breadcrumb and note", %{conn: conn} do
      play = Playcode.TestFixtures.play_fixture()

      italy =
        Playcode.TestFixtures.place_fixture(%{"name" => "Italia", "type" => "country"})

      roma =
        Playcode.TestFixtures.place_fixture(%{"name" => "Roma", "parent_place_id" => italy.id})

      miseno = Playcode.TestFixtures.place_fixture(%{"name" => "Miseno"})

      Playcode.TestFixtures.play_place_fixture(play, miseno, %{
        "role" => "mentioned",
        "note" => "Named, not staged."
      })

      Playcode.TestFixtures.play_place_fixture(play, roma, %{"role" => "setting"})

      TestFixtures.mark_complete!(play)

      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      places = view |> element("#meta-places") |> render()
      assert places =~ t("Places")
      assert places =~ "Roma, Italia"
      assert places =~ "Named, not staged."

      # settings first, whatever order they were linked in
      assert :binary.match(places, "Roma") < :binary.match(places, "Miseno")
    end

    test "a place's historical state is printed, today's names in brackets", %{conn: conn} do
      play = Playcode.TestFixtures.play_fixture()
      europa = Playcode.TestFixtures.place_fixture(%{"name" => "Europa", "type" => "continent"})

      italia =
        Playcode.TestFixtures.place_fixture(%{
          "name" => "Italia",
          "type" => "country",
          "parent_place_id" => europa.id
        })

      roma =
        Playcode.TestFixtures.place_fixture(%{"name" => "Roma", "parent_place_id" => italia.id})

      republica =
        Playcode.TestFixtures.place_fixture(%{
          "name" => "República romana",
          "type" => "country",
          "parent_place_id" => europa.id
        })

      Playcode.TestFixtures.play_place_fixture(play, roma, %{
        "historical_state_id" => republica.id
      })

      TestFixtures.mark_complete!(play)

      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      assert render(element(view, "#meta-places")) =~
               "Roma, República romana, Europa (hoy Italia)"
    end

    test "a fictional place is marked", %{conn: conn} do
      play = Playcode.TestFixtures.play_fixture()

      atlantis =
        Playcode.TestFixtures.place_fixture(%{
          "name" => "Atlántida",
          "type" => "island",
          "is_fictional" => "true"
        })

      Playcode.TestFixtures.play_place_fixture(play, atlantis)

      TestFixtures.mark_complete!(play)

      {:ok, _view, html} = live(conn, ~p"/plays/#{play.code}")
      assert html =~ t("Fictional")
    end
  end

  test "shows the play's text: acts, speakers, verses and stage directions", %{conn: conn} do
    play =
      Playcode.ImportHelpers.import_tei!(
        Playcode.ImportHelpers.tei(
          body: """
          <div1 type="acto" n="1"><head>ACTO PRIMERO</head>
            <div2 type="escena" n="1"><head>ESCENA I</head>
              <stage>Salen el Rey y la Reina</stage>
              <sp><speaker>REY</speaker><lg><l n="1">Aquí comienza el verso</l></lg></sp>
              <sp><speaker>REINA</speaker><p>Y aquí la prosa.</p></sp>
            </div2>
          </div1>
          """
        )
      )

    TestFixtures.mark_complete!(play)

    {:ok, _lv, html} = live(conn, ~p"/plays/#{play.code}")

    for text <- [
          "ACTO PRIMERO",
          "ESCENA I",
          "REY",
          "REINA",
          "Salen el Rey y la Reina",
          "Aquí comienza el verso",
          "Y aquí la prosa."
        ] do
      assert html =~ text
    end
  end

  describe "the bibliography panel" do
    test "is absent when the play has none", %{conn: conn} do
      play = Playcode.TestFixtures.play_fixture()
      TestFixtures.mark_complete!(play)
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      refute has_element?(view, "#meta-bibliography")
      refute has_element?(view, ~s(a[href="#meta-bibliography"]))
    end

    test "lists the citations by kind, with its own sidebar entry, and no researcher's note", %{
      conn: conn
    } do
      play = Playcode.TestFixtures.play_fixture()

      Playcode.TestFixtures.bibliography_fixture(
        play,
        %{
          "monogr_author" => "Oleza, Joan",
          "monogr_title" => "Teatro y prácticas escénicas",
          "public_note" => "Reimpreso en 1990",
          "note" => "Revisar la fecha"
        },
        %{"note" => "Préstamo interbibliotecario"}
      )

      TestFixtures.mark_complete!(play)

      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      section = view |> element("#meta-bibliography") |> render()

      assert section =~ t("Criticism")
      assert section =~ "Oleza, Joan. Teatro y prácticas escénicas."
      assert section =~ "Reimpreso en 1990."
      refute section =~ "Revisar la fecha"
      refute section =~ "Préstamo interbibliotecario"
      assert has_element?(view, ~s(a[href="#meta-bibliography"]), t("Bibliography"))
    end
  end

  describe "the witnesses panel" do
    test "is absent when the play has none", %{conn: conn} do
      play = TestFixtures.mark_complete!(TestFixtures.play_fixture())
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      refute has_element?(view, "#meta-witnesses")
      refute has_element?(view, ~s(a[href="#meta-witnesses"]))
    end

    test "lists the witnesses as emothe.uv.es prints them, with a sidebar entry, no siglum or type",
         %{conn: conn} do
      play = TestFixtures.play_fixture()

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
          "title" => "El conde de Sex",
          "shelfmark" => "16722"
        })

      TestFixtures.mark_complete!(play)
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      section = view |> element("#meta-witnesses") |> render()

      assert section =~ "<em>THE Tragicall Historie of HAMLET</em>. 1603."
      assert section =~ "<em>El conde de Sex</em>. Archivo: 16722."
      refute section =~ "Q1"
      refute section =~ PlaycodeWeb.PlayLabels.witness_type_label("loose")
      assert has_element?(view, ~s(a[href="#meta-witnesses"]), t("Witnesses"))
    end
  end

  describe "the performances panel" do
    test "is absent when the play has none", %{conn: conn} do
      play = TestFixtures.mark_complete!(TestFixtures.play_fixture())
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      refute has_element?(view, "#meta-performances")
      refute has_element?(view, ~s(a[href="#meta-performances"]))
    end

    test "prints each performance as a line, its cast and note, and its source once below", %{
      conn: conn
    } do
      play = TestFixtures.play_fixture()

      source =
        TestFixtures.catalogue_fixture(%{
          "monogr_title" => "CATCOM",
          "public_note" => "Copyright DICAT."
        })

      {:ok, company} =
        Playcode.Performances.find_or_create_company(
          "Troupe del Roi #{System.unique_integer([:positive])}"
        )

      {:ok, actor} =
        Playcode.Performances.find_or_create_actor(%{
          "surname" => "Poquelin",
          "nickname" => "Molière"
        })

      for date <- ["1610", "1611"] do
        performance =
          TestFixtures.performance_fixture(play, %{
            "date_text" => date,
            "venue" => "Globe or Blackfriars",
            "company_id" => company.id,
            "venue_type" => "commercial_theatre",
            "note" => "The play was hissed.",
            "source_entry_id" => source.id,
            "source_volume" => "6",
            "source_pages" => "83"
          })

        {:ok, _} =
          Playcode.Performances.put_cast(performance, [
            %{"actor_id" => actor.id, "role" => "Argan"}
          ])
      end

      TestFixtures.mark_complete!(play)
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      section = view |> element("#meta-performances") |> render()

      assert section =~ "1610"
      assert section =~ "Globe or Blackfriars · #{company.name} · teatro comercial"
      assert section =~ "[1] vol. 6, p. 83"
      assert section =~ "Poquelin, “Molière” (Argan)"
      assert section =~ "The play was hissed."
      assert has_element?(view, "#meta-performances dt", t("Performances"))
      assert has_element?(view, ~s(a[href="#meta-performances"]), t("Performances"))

      # The source is printed once, with its public note, however many performances cite it.
      assert length(String.split(section, "Copyright DICAT.")) == 2
    end
  end

  # Every text the TEI importer reads holds <emph> as <<…>> (CLAUDE.md), a performance's too.
  describe "the performances panel's italics" do
    test "print as italics, never as markers", %{conn: conn} do
      play = TestFixtures.play_fixture()

      {:ok, _} =
        Playcode.PlayContent.create_character(%{
          play_id: play.id,
          xml_id: "ARGAN",
          name: "<<Argan>>",
          actor: "Mr. <<Betterton>>"
        })

      TestFixtures.performance_fixture(play, %{
        "venue" => "<<Globe>>",
        "note" => "Hissed <<twice>>.",
        "cast_from_cast_list" => "true",
        "cast" => [%{"surname" => "<<Mlle>> du Parc", "role" => "<<Toinette>>"}]
      })

      TestFixtures.mark_complete!(play)
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      section = view |> element("#meta-performances") |> render()

      for word <- ["Globe", "twice", "Betterton", "Argan", "Mlle", "Toinette"] do
        assert section =~ "<em>#{word}</em>", word
      end

      refute section =~ "&lt;&lt;"
    end
  end

  describe "related plays" do
    test "a draft translation is not linked from its original, except for staff", %{
      conn: conn
    } do
      original =
        TestFixtures.play_fixture(%{"title" => "Original publicado", "is_complete" => true})

      draft =
        TestFixtures.play_fixture(%{
          "title" => "Traducción en curso",
          "parent_play_id" => original.id,
          "relationship_type" => "traduccion"
        })

      {:ok, view, _html} = live(conn, ~p"/plays/#{original.code}")
      refute has_element?(view, ~s(a[href="/plays/#{draft.code}"]))

      staff = log_in_user(conn, TestFixtures.user_fixture())
      {:ok, view, _html} = live(staff, ~p"/plays/#{original.code}")
      assert has_element?(view, ~s(a[href="/plays/#{draft.code}"]), draft.title)
    end

    test "a draft original is not linked from its translation, except for staff", %{conn: conn} do
      draft = TestFixtures.play_fixture(%{"title" => "Original en curso"})

      translation =
        TestFixtures.play_fixture(%{
          "title" => "Traducción publicada",
          "parent_play_id" => draft.id,
          "relationship_type" => "traduccion",
          "is_complete" => true
        })

      {:ok, view, _html} = live(conn, ~p"/plays/#{translation.code}")
      refute has_element?(view, ~s(a[href="/plays/#{draft.code}"]))

      staff = log_in_user(conn, TestFixtures.user_fixture())
      {:ok, view, _html} = live(staff, ~p"/plays/#{translation.code}")
      assert has_element?(view, ~s(a[href="/plays/#{draft.code}"]), draft.title)
    end
  end

  describe "textual variants" do
    setup %{conn: conn} do
      play =
        tei(
          source_desc: """
          <listWit>
            <witness xml:id="H" n="H"><bibl type="manuscrito"><title>Manuscrito sin lugar ni fecha</title></bibl></witness>
            <witness xml:id="P3" n="P3"><bibl type="edicion_antigua"><title>Doce comedias</title><pubPlace>Madrid:</pubPlace><date>1653</date></bibl></witness>
            <witness xml:id="MP" n="MP"><bibl type="edicion_antigua"><title>Comedias</title><date>1735</date></bibl></witness>
          </listWit>
          """,
          body: """
          <div1 type="jornada" n="1"><head>Jornada I</head>
            <sp><speaker>FENISA</speaker>
              <l n="72">mucho la hermosura llama<app type="substantive" n="908"><lem wit="#H">llama<note>Corrección de <emph>Hartzenbusch</emph></note></lem><rdg wit="#P3">falta</rdg><rdg wit="#MP #X">infama</rdg><note>Por la rima.</note></app>,<note n="1" type="editor"><p>Glosa.</p></note></l>
              <l n="73">lovely<app n="909"><rdg wit="#BRA #JOW">lively</rdg><rdg/><rdg wit="#Dyce #POPE1">lowly</rdg><rdg wit="#">lonely</rdg></app> y más</l>
            </sp>
          </div1>
          """
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      for {siglum, editors, year} <- [
            {"H", "Hartzenbusch, J. E.", "1860"},
            {"BRA", "Bruster, Douglas; Rasmussen, Eric", "2009"},
            {"JOW", "Taylor, Gary; Jowett, John; Bourus, Terri", "2016"},
            {"Dyce", "Dyce, Alexander", "1831"},
            {"POPE1", nil, "1723"}
          ] do
        bibliography_fixture(play, %{
          "kind" => "modern_edition",
          "siglum" => siglum,
          "monogr_editors" => editors,
          "year_text" => year
        })
      end

      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      %{view: view, play: play}
    end

    defp squished(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

    defp variant_buttons(view) do
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query(~s(button[aria-label^="#{t("Textual variant")}"]))
    end

    test "an asterisk after the word opens the readings, each witness with what it names",
         %{view: view} do
      doc = view |> render() |> LazyHTML.from_fragment()

      # The line reads as the edition's text; the asterisk is apart from the note's number,
      # and the note is still the first.
      assert doc |> LazyHTML.query("#play-tab-text") |> LazyHTML.text() |> squished() =~
               "mucho la hermosura llama*,1"

      assert has_element?(view, ~s(button[aria-label="#{t("Editor's note")} 1"]))

      [first, second] = view |> variant_buttons() |> LazyHTML.attribute("popovertarget")

      # The variants are numbered in their own sequence, apart from the notes'.
      assert view |> variant_buttons() |> LazyHTML.attribute("aria-label") ==
               [t("Textual variant") <> " 1", t("Textual variant") <> " 2"]

      # H is a witness with neither place nor date and a modern edition's siglum too: the
      # witness's empty name must not hide the edition's.
      readings = fn id ->
        doc |> LazyHTML.query("##{id} p") |> Enum.map(&squished(LazyHTML.text(&1)))
      end

      assert readings.(first) == [
               "H (Hartzenbusch, 1860) llama (Corrección de Hartzenbusch)",
               "P3 (Madrid, 1653) falta",
               "MP (1735) X infama",
               "Por la rima."
             ]

      # An empty <rdg/> (a damaged entry, kept as written) prints no empty paragraph.
      assert readings.(second) == [
               "BRA (Bruster & Rasmussen, 2009) JOW (Taylor et al., 2016) lively",
               "Dyce (1831) POPE1 (1723) lowly",
               "lonely"
             ]
    end

    test "the Variants switch hides the asterisks, and the Notes view lists notes only",
         %{conn: conn, view: view} do
      assert has_element?(view, "label", t("Variants"))
      assert has_element?(view, ~s(#play-tab-text [data-variants="on"]))

      render_click(view, "toggle_variants")
      assert has_element?(view, ~s(#play-tab-text [data-variants="off"]))

      view |> element("#play-sections-panel button", t("Notes")) |> render_click()

      assert view
             |> render()
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#play-tab-notes li")
             |> Enum.count() == 1

      # A play with no variants has no switch.
      plain =
        tei(
          body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>)
        )
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, plain_view, _html} = live(conn, ~p"/plays/#{plain.code}")
      refute has_element?(plain_view, "label", t("Variants"))
    end
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

    setup %{conn: conn} do
      play = [body: @folio_body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      %{play: play, view: view}
    end

    test "are hidden until the switch shows them, in grey between their F's", %{view: view} do
      assert has_element?(view, "label", t("Folio interpolations"))
      assert has_element?(view, ~s(#play-tab-text [data-folio="off"]))

      text = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#play-tab-text")

      assert text |> LazyHTML.query("sup.folio") |> Enum.map(&LazyHTML.text/1) == ~w(F F F F F F)

      assert text |> LazyHTML.query("span.folio") |> Enum.map(&LazyHTML.text/1) |> Enum.take(1) ==
               ["O"]

      # The line all the Folio's, and the speech all the Folio's, go with their words.
      assert text |> LazyHTML.query(".verse-line.folio") |> Enum.count() == 1
      assert text |> LazyHTML.query(".speech.folio") |> Enum.count() == 1

      render_click(view, "toggle_folio")
      assert has_element?(view, ~s(#play-tab-text [data-folio="on"]))
    end

    test "is not governed by Show variant readings", %{conn: conn, play: play} do
      {:ok, play} = Playcode.Catalogue.update_play(play, %{show_variants: false})
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")
      assert has_element?(view, "label", t("Folio interpolations"))
    end

    # Each kind of element that can be the Folio's wholly goes with its words: the class is
    # how the stylesheet finds it, and a speech or group with one Folio line and one other
    # keeps its wrapper.
    test "a stage direction, a paragraph, a line group and a speaker label that are all the Folio's go",
         %{conn: conn} do
      body = """
      <div1 type="acto" n="1"><head>ACT I</head>
        <stage type="entrance">#{@folio_open}#{@f}Sound a Flourish.#{@f}#{@folio_close}</stage>
        <sp><speaker>HAMLET</speaker>
          <p n="1">#{@folio_open}#{@f}Denmark’s a prison.#{@f}#{@folio_close}</p>
          <lg>
            <l n="2">#{@folio_open}#{@f}One line,#{@f}#{@folio_close}</l>
            <l n="3">#{@folio_open}#{@f}and two.#{@f}#{@folio_close}</l>
          </lg>
          <lg>
            <l n="4">#{@folio_open}#{@f}A line#{@f}#{@folio_close} the Quarto has too.</l>
            <l n="5">#{@folio_open}#{@f}and two.#{@f}#{@folio_close}</l>
          </lg>
        </sp>
        <sp><speaker>#{@folio_open}#{@f}guildenstern#{@f}#{@folio_close}</speaker>
          <p n="6">My lord?</p>
        </sp>
        <sp><speaker>CLAUDIUS</speaker>
          <p n="7">#{@folio_open}#{@f}Only the Folio has this.#{@f}#{@folio_close}</p>
        </sp>
      </div1>
      """

      play = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      text = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#play-tab-text")

      folio_words = fn selector ->
        text |> LazyHTML.query(selector) |> Enum.map(&LazyHTML.text/1)
      end

      assert [flourish] = folio_words.(".stage-direction.folio")
      assert flourish =~ "Flourish"

      assert [prison, only] = folio_words.(".text-justify.folio")
      assert prison =~ "prison" and only =~ "Only the Folio"

      assert [group] = folio_words.(".line-group.folio")
      assert group =~ "One line," and group =~ "and two."
      assert folio_words.(".line-group") |> length() == 2

      assert [speaker] = folio_words.(".speaker.folio")
      assert speaker =~ "guildenstern"

      # No speech is the Folio's alone: Hamlet's has a line the Quarto shares, the second
      # speaker's paragraph is not the Folio's, and Claudius's only paragraph is, but his
      # name is not.
      assert folio_words.(".speech.folio") == []
    end

    test "a label that is the Folio's goes alone when the Quarto's words follow it", %{conn: conn} do
      body = """
      <div1 type="acto" n="5">
        <sp><speaker>#{@folio_open}#{@f}2 clown#{@folio_close}</speaker>
          <p n="3224">#{@folio_open}What, art a heathen?#{@f}#{@folio_close} I’ll put another question to thee.</p>
        </sp>
      </div1>
      """

      play = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      # Off: the label goes and the speech stays, with the Quarto's words in it.
      assert has_element?(view, ~s(#play-tab-text [data-folio="off"]))
      assert has_element?(view, ".speaker.folio", "2 clown")
      refute has_element?(view, ".speech.folio")
      assert has_element?(view, ".speech", "I’ll put another question to thee.")

      # On: nothing is hidden, so both show.
      render_click(view, "toggle_folio")
      assert has_element?(view, ~s(#play-tab-text [data-folio="on"]))
      assert has_element?(view, ".speaker", "2 clown")
      assert has_element?(view, ".speech span.folio", "What, art a heathen?")
    end

    test "a note inside a passage sits inside the part that is hidden, one outside it does not",
         %{conn: conn} do
      body = """
      <div1 type="acto" n="1">
        <sp><speaker>HAMLET</speaker>
          <l n="316">O God, #{@folio_open}#{@f}O<note n="1" type="editor"><p>An oath.</p></note> hear#{@f}#{@folio_close} God,<note n="2" type="editor"><p>Plain.</p></note></l>
        </sp>
      </div1>
      """

      play = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      note = fn n -> ~s(button[aria-label="#{t("Editor's note")} #{n}"]) end

      assert has_element?(view, ~s(#play-tab-text [data-folio="off"]))
      assert has_element?(view, "span.folio #{note.(1)}")
      assert has_element?(view, note.(2))
      refute has_element?(view, "span.folio #{note.(2)}")
    end

    # Hamlet v. 2632, a passage inside an inline stage direction.
    test "with the stage directions hidden, the F's of a passage inside one go with it",
         %{conn: conn} do
      body = """
      <div1 type="acto" n="4"><sp><speaker>hamlet</speaker>
        <p n="2631">Safely stowed. <stage type="delivery_">[Calling within#{@folio_open}#{@f} “Hamlet, Lord Hamlet!”#{@f}#{@folio_close}]</stage> But soft.</p>
      </sp></div1>
      """

      play = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      f_labels = fn ->
        view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("sup.folio")
      end

      assert Enum.count(f_labels.()) == 2

      render_click(view, "toggle_stage_directions")
      assert Enum.count(f_labels.()) == 0
      refute render(view) =~ "Calling within"
    end

    test "a passage in a scene shows the switch", %{conn: conn} do
      body = """
      <div1 type="acto" n="1"><head>ACT I</head>
        <div2 type="escena" n="1"><head>Scene 1</head>
          <sp><speaker>HAMLET</speaker><l n="1">O God, #{@folio_open}#{@f}O#{@f}#{@folio_close} God,</l></sp>
        </div2>
      </div1>
      """

      play = [body: body] |> tei() |> import_tei!() |> TestFixtures.mark_complete!()
      {:ok, view, _html} = live(conn, ~p"/plays/#{play.code}")

      assert has_element?(view, "label", t("Folio interpolations"))
    end

    test "a play with no Folio passage has no switch", %{conn: conn} do
      plain =
        [body: ~s(<div1 type="acto" n="1"><sp><speaker>A</speaker><l n="1">uno</l></sp></div1>)]
        |> tei()
        |> import_tei!()
        |> TestFixtures.mark_complete!()

      {:ok, plain_view, _html} = live(conn, ~p"/plays/#{plain.code}")
      refute has_element?(plain_view, "label", t("Folio interpolations"))
    end
  end
end
