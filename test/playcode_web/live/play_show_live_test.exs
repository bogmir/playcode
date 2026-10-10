defmodule PlaycodeWeb.PlayShowLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers

  alias Playcode.TestFixtures

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
end
