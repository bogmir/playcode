defmodule PlaycodeWeb.ExportControllerTest do
  @moduledoc "The public downloads at /export/:id/*, open to anyone."
  use PlaycodeWeb.ConnCase, async: true

  import Playcode.ImportHelpers

  setup do
    play =
      import_tei!(
        tei(
          title: "Obra descargable",
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso de prueba</l></sp></div1>)
        )
      )

    # An import is a draft, and a visitor may download only a complete play.
    %{play: Playcode.TestFixtures.mark_complete!(play)}
  end

  defp attachment(conn), do: conn |> get_resp_header("content-disposition") |> List.first()

  test "the TEI download is the play's TEI, as a named attachment", %{conn: conn, play: play} do
    conn = get(conn, ~p"/export/#{play.id}/tei")

    assert xml_texts(response(conn, 200), "l") == ["Verso de prueba"]
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.xml")
  end

  test "the HTML download is a standalone page with the text", %{conn: conn, play: play} do
    conn = get(conn, ~p"/export/#{play.id}/html")

    body = response(conn, 200)
    assert body =~ "<!DOCTYPE html>"
    assert body =~ "Obra descargable"
    assert body =~ "Verso de prueba"
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.html")
  end

  test "the EPUB download is an e-book carrying the text", %{conn: conn, play: play} do
    conn = get(conn, ~p"/export/#{play.id}/epub")

    assert {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
    text = Enum.map_join(files, fn {_name, content} -> content end)
    assert text =~ "Obra descargable"
    assert text =~ "Verso de prueba"
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.epub")
  end

  # A division's closing formula, printed after its text as the TEI file and the play page
  # carry it.
  test "the HTML and EPUB downloads print the closing formula", %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso de prueba</l></sp><trailer>FIN DEL PRIMER ACTO</trailer></div1>)
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    assert response(get(conn, ~p"/export/#{play.id}/html"), 200) =~ "FIN DEL PRIMER ACTO"

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    assert Enum.any?(files, fn {_name, content} -> content =~ "FIN DEL PRIMER ACTO" end)
  end

  # As emothe.uv.es set it: centred, in italics, an italic word in it set upright.
  test "the HTML and EPUB downloads set the closing formula centred and in italics",
       %{conn: conn, play: play} do
    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    {_name, epub_css} = Enum.find(files, fn {name, _} -> List.to_string(name) =~ "style.css" end)

    for css <- [html, epub_css] do
      assert css =~ ~r/\.trailer \{[^}]*text-align: center/
      assert css =~ ~r/\.trailer \{[^}]*font-style: italic/
      assert css =~ ~r/\.trailer em \{[^}]*font-style: normal/
    end
  end

  # As the published site prints them, in the downloads' English.
  test "the HTML and EPUB downloads print the dating and the historical time",
       %{conn: conn, play: play} do
    {:ok, play} =
      Playcode.Catalogue.update_play(play, %{
        "composition_date_from" => 1600,
        "composition_date_to" => 1601,
        "composition_date_note" => "¿1600? y ¿1601?",
        "historical_time" => "siglo_xvi",
        "historical_time_note" => "reinado de Felipe II"
      })

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    for {format, text} <- [html: html, epub: epub],
        expected <- ["1600–1601", "¿1600? y ¿1601?", "16th century", "reinado de Felipe II"] do
      assert text =~ expected, "#{format} lacks #{expected}"
    end
  end

  test "the HTML and EPUB downloads print a prose break as a new line, and its numbers",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><p n="5">Uno, <lb/>dos <lb n="6"/>tres.</p></sp></div1>)
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    assert html =~ ~s(<span class="pn">5</span>Uno,<br>dos <span class="pn">6</span>tres.)
    assert epub =~ ~s(<span class="pn">5</span>Uno,<br/>dos <span class="pn">6</span>tres.)
  end

  test "the HTML and EPUB downloads print the outline in order, each list its own entries",
       %{conn: conn} do
    play = outline_xml() |> import_tei!() |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    assert in_order?(html, outline_headings())
    assert occurrences(html, "de hombre") == 1
    assert occurrences(html, "Músicos") == 1

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    book = epub_text(files)
    assert in_order?(book, outline_headings())
    assert occurrences(book, "de hombre") == 1
    assert occurrences(book, "Músicos") == 1
  end

  # The book's chapters in its spine's order, as a reader turns the pages.
  defp epub_text(files) do
    chapters =
      Map.new(files, fn {name, content} -> {Path.basename(to_string(name), ".xhtml"), content} end)

    {_name, opf} =
      Enum.find(files, fn {name, _} -> String.ends_with?(to_string(name), ".opf") end)

    for [_, idref] <- Regex.scan(~r/<itemref[^>]*idref="([^"]+)"/, opf),
        into: "",
        do: Map.get(chapters, idref, "")
  end

  # After the cast list, as the play page and the published site print it.
  test "the HTML and EPUB downloads print the scene of the action after the cast list",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          front: """
          <div type="elenco"><castList><castItem><role xml:id="DON">Don Juan</role></castItem></castList></div>
          <set><head>SCENE:</head><p>An English wood.</p></set>
          """
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    assert [_before_cast, after_cast] = String.split(html, "Don Juan")
    assert after_cast =~ ~r/SCENE:.*An English wood\./s
    refute html =~ ~r/An English wood.*An English wood/s

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])

    assert Enum.any?(files, fn {_name, content} ->
             content =~ ~r/Don Juan.*SCENE:.*An English wood\./s
           end)
  end

  test "the HTML and EPUB downloads print italics outside the text as italics", %{conn: conn} do
    play =
      import_tei!(
        tei(
          source_desc:
            "<bibl><title>Aminta</title><note>Tasso. <emph>Aminta</emph>. Venezia.</note></bibl>",
          front: """
          <div type="dedicatoria"><head>A <emph>Damone</emph></head><p>Dedica <emph>Egle</emph>.</p></div>
          <div type="elenco"><head><emph>Dramatis Personae</emph></head><castList>
            <castItem><role xml:id="CORT"><emph>The courtiers</emph></role><roleDesc>(<emph>Spela</emph>), a servant</roleDesc></castItem>
          </castList></div>
          <set><p><emph>La Scena è in Atene.</emph></p></set>
          """
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    for {format, text} <- [html: html, epub: epub] do
      refute text =~ "&lt;&lt;", "#{format} prints the markers"

      for italic <- ~w(Aminta Damone Egle Spela) ++ ["The courtiers", "La Scena è in Atene."],
          do: assert(text =~ "<em>#{italic}</em>", "#{format} lacks #{italic}")
    end
  end

  # Question 10: the HTML keeps the break for its white-space: pre-line; an EPUB reader
  # need not honour that, so the EPUB writes <br/>.
  test "a paratext's line breaks are printed", %{conn: conn} do
    play =
      tei(
        front:
          ~s(<div type="dedicatoria"><p>The banished cavaliers!<lb/>A roving blade!</p></div>)
      )
      |> import_tei!()
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    # A <br> in the HTML since 2026-10-16, the one rule for a line break that the play
    # text shares; it used to be the \n itself, shown by white-space: pre-line.
    assert html =~ "The banished cavaliers!<br>A roving blade!"
    assert epub =~ "The banished cavaliers!<br/>A roving blade!"
  end

  # An EPUB chapter is XHTML: a note's line break is <br/> there, or the chapter does not
  # parse and a strict e-reader refuses the book.
  test "the EPUB prints a note's line break as XHTML", %{conn: conn} do
    play =
      tei(
        body:
          ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso<note n="1" type="editor"><p>Q2 ho!<lb/>F1 who’s</p></note></l></sp></div1>)
      )
      |> import_tei!()
      |> Playcode.TestFixtures.mark_complete!()

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])

    for {name, content} <- files, String.ends_with?(to_string(name), ".xhtml") do
      assert {:ok, _} = Saxy.SimpleForm.parse_string(content), "#{name} is not XHTML"
    end

    assert Enum.map_join(files, &elem(&1, 1)) =~ "Q2 ho!<br/>F1 who’s"
  end

  test "a line break inside italics is printed inside them", %{conn: conn, play: play} do
    {:ok, _} =
      Playcode.Catalogue.create_paratext(%{
        play_id: play.id,
        kind: "dedicatoria",
        content: "C <<una\ndos>> fin"
      })

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    refute epub =~ "&lt;&lt;"
    assert epub =~ "<em>una<br/>dos</em>"
  end

  test "the paratexts after the text are printed after it", %{conn: conn} do
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
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])

    assert [_text, after_text] = String.split(html, "Verso final.")
    assert after_text =~ ~r/EPILOGUE.*<em>cavaliers<\/em>.*Loado sea\./s

    # A chapter each, after the text's, in the reader's table of contents.
    {_name, toc} = Enum.find(files, fn {_name, content} -> content =~ ~s(epub:type="toc") end)

    assert Regex.scan(~r{<a href="[^"]+">([^<]+)</a>}, toc, capture: :all_but_first) ==
             [["Test Play"], ["ACTO I"], ["EPILOGUE"], [t("Colophon")]]

    assert Enum.any?(files, fn {_name, content} ->
             content =~ "Loado sea." and content =~ "<title>#{t("Colophon")}</title>"
           end)
  end

  # Question 41: the Arte nuevo's dedication, the poem's opener, before its first line.
  test "a poem's opener is printed before its lines", %{conn: conn} do
    play =
      tei(
        body:
          ~s(<div type="poem"><opener><salute>Dirigido a la Academia de Madrid</salute></opener><lg><l n="1">Mándanme, ingenios nobles</l></lg></div>)
      )
      |> import_tei!()
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    assert html =~ ~r{Dirigido a la Academia de Madrid.*Mándanme, ingenios nobles}s
    assert epub =~ ~r{Dirigido a la Academia de Madrid.*Mándanme, ingenios nobles}s
  end

  # Question 30: the sonnet after Les Contents, as verse, with its closing formula.
  test "a paratext in verse is printed with its closing formula", %{conn: conn} do
    play =
      tei(
        back: """
        <div type="epilogo"><head>SONNET</head>
          <lg><l>Réjouis-toi, Paris,</l><l>Un de tes citoyens</l></lg><trailer>FIN</trailer>
        </div>
        """
      )
      |> import_tei!()
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
    epub = Enum.map_join(files, fn {_name, content} -> content end)

    assert html =~
             ~r{Réjouis-toi, Paris,\s*(<br/?>)?\s*Un de tes citoyens.*<div class="trailer">FIN</div>}s

    assert epub =~ ~r{Réjouis-toi, Paris,<br/>Un de tes citoyens.*<div class="trailer">FIN</div>}s
  end

  # As the play page prints them: an asterisk in the line, the readings after the act's
  # notes; nothing for a play whose variants readers do not see.
  test "the HTML and EPUB downloads mark each variant and list it after the act's notes",
       %{conn: conn} do
    play =
      import_tei!(
        tei(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso<app n="1"><lem wit="#A">Verso</lem><rdg wit="#B">Canto</rdg></app> de prueba<note n="1" type="editor"><p>Glosa.</p></note></l></sp></div1>)
        )
      )
      |> Playcode.TestFixtures.mark_complete!()

    html = response(get(conn, ~p"/export/#{play.id}/html"), 200)
    doc = LazyHTML.from_document(html)

    assert doc |> LazyHTML.query(~s(a[href="#var-1"])) |> LazyHTML.text() == "*"

    assert doc |> LazyHTML.query("#var-1 p") |> Enum.map(&LazyHTML.text/1) == [
             "A Verso",
             "B Canto"
           ]

    assert html =~ ~r{id="note-1".*id="var-1"}s

    # The asterisk is styled as the note's number is (the CSS has no browser to test in).
    # (The rule also names the Folio F's, `sup.folio`, which are as small.)
    assert html =~ ".nref, .vref, sup.folio {"

    epub = fn ->
      {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])
      Enum.map_join(files, fn {_name, content} -> content end)
    end

    epub_text = epub.()

    assert epub_text =~ ~s(<a epub:type="noteref" href="#var-1">*</a>)

    assert epub_text =~
             ~s(<aside epub:type="footnote" id="var-1"><p><i>A</i> Verso</p><p><i>B</i> Canto</p></aside>)

    {:ok, _} = Playcode.Catalogue.update_play(play, %{show_variants: false})
    refute response(get(conn, ~p"/export/#{play.id}/html"), 200) =~ "var-1"
    refute epub.() =~ "var-1"
  end

  # The downloads have no switch, so they print Hamlet's Folio passages, in grey between
  # their F's, rather than lose them (question 38).
  describe "Hamlet's Folio passages" do
    defp epub_text(conn, play) do
      {:ok, files} =
        :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])

      Enum.map_join(files, fn {_name, content} -> content end)
    end

    test "the HTML and EPUB downloads print one in grey between its F's", %{conn: conn} do
      play =
        import_tei!(
          tei(
            body:
              ~s(<div1 type="acto" n="1"><sp><speaker>HAMLET</speaker><l n="316">O God, <app type="folio"><lem wit="#Q2"/><rdg wit="#F1">O</rdg></app> God,</l></sp></div1>)
          )
        )
        |> Playcode.TestFixtures.mark_complete!()

      html = response(get(conn, ~p"/export/#{play.id}/html"), 200)

      assert html =~
               ~s(O God, <sup class="folio">F</sup><span class="folio">O</span><sup class="folio">F</sup> God,)

      assert html =~ ".folio { color: #666; }"

      # The F is as small as a note's number, or a browser-default `sup` widens the line.
      assert html =~ ".nref, .vref, sup.folio { font-size: 0.7em; line-height: 0; }"

      epub = epub_text(conn, play)
      assert epub =~ ~s(<span class="folio">O</span>)
      assert epub =~ ".folio { color: #666; }"
      assert epub =~ "sup.folio { font-size: 0.7em; line-height: 0; }"
    end

    # Hamlet v. 2632: a passage inside an inline stage direction. The stage's span wraps
    # the passage's, as on the play page and the site, so an F stands inside the stage.
    test "the downloads put the F's of a passage inside a stage direction in its span",
         %{conn: conn} do
      folio = ~s(<code>&lt;span class="folio"&gt;</code>)
      folio_end = ~s(<code>&lt;/span&gt;</code>)
      f = ~s(<code>&lt;sup&gt;</code>F<code>&lt;/sup&gt;</code>)

      play =
        import_tei!(
          tei(
            body:
              ~s(<div1 type="acto" n="4"><sp><speaker>hamlet</speaker><p n="2631">Safely stowed. <stage type="delivery_">[Calling within#{folio}#{f} “Hamlet, Lord Hamlet!”#{f}#{folio_end}]</stage></p></sp></div1>)
          )
        )
        |> Playcode.TestFixtures.mark_complete!()

      html = response(get(conn, ~p"/export/#{play.id}/html"), 200)

      assert html =~ ~s(<span class="stage"><sup class="folio">F</sup></span>)

      assert html =~
               ~s(<span class="stage"><span class="folio">“Hamlet, Lord Hamlet!”</span></span>)

      epub = epub_text(conn, play)
      assert epub =~ ~s(<span class="stage"><sup class="folio">F</sup></span>)
    end
  end

  test "an archived play cannot be downloaded", %{conn: conn, play: play} do
    {:ok, _} = Playcode.Catalogue.delete_play(play)

    assert_error_sent 404, fn -> get(conn, ~p"/export/#{play.id}/tei") end
  end

  test "a draft is for staff only", %{conn: conn, play: play} do
    {:ok, draft} = Playcode.Catalogue.update_play(play, %{is_complete: false})

    for format <- ~w(tei html epub pdf) do
      assert_error_sent 404, fn -> get(conn, "/export/#{draft.id}/#{format}") end
    end

    staff = log_in_user(conn, Playcode.TestFixtures.user_fixture())

    for format <- ~w(tei html epub pdf) do
      assert response(get(staff, "/export/#{draft.id}/#{format}"), 200), format
    end
  end

  # Question 24, answered on 19 October 2026: what the edition holds beside the play.
  describe "what the downloads print of the edition (question 24)" do
    test "the HTML and EPUB downloads name the play a translation translates", %{conn: conn} do
      %{translation: translation} = Playcode.TestFixtures.translation_family_fixture()

      html = response(get(conn, ~p"/export/#{translation.id}/html"), 200)

      assert html |> LazyHTML.from_document() |> LazyHTML.query(".original") |> LazyHTML.text() ==
               "Translation of Original Play"

      assert epub_text(conn, translation) =~
               ~s(<p class="original">Translation of <cite>Original Play</cite></p>)

      # A play linked with no kind names no relation, as the play page and the site do.
      {:ok, _} = Playcode.Catalogue.update_play(translation, %{relationship_type: nil})
      refute response(get(conn, ~p"/export/#{translation.id}/html"), 200) =~ ~s(class="original")
    end

    test "a visitor's download names no draft original", %{conn: conn} do
      %{original: original, translation: translation} =
        Playcode.TestFixtures.translation_family_fixture()

      {:ok, _} = Playcode.Catalogue.update_play(original, %{is_complete: false})

      refute response(get(conn, ~p"/export/#{translation.id}/html"), 200) =~ "Original Play"
      refute epub_text(conn, translation) =~ "Original Play"
    end

    # A PDF is rendered once per version and served to whoever asks next (PdfCache), so
    # what staff download must be what a visitor may read.
    test "staff's download names no draft original either", %{conn: conn} do
      %{original: original, translation: translation} =
        Playcode.TestFixtures.translation_family_fixture()

      {:ok, _} = Playcode.Catalogue.update_play(original, %{is_complete: false})
      staff = log_in_user(conn, Playcode.TestFixtures.user_fixture())

      refute response(get(staff, ~p"/export/#{translation.id}/html"), 200) =~ "Original Play"

      refute response(get(staff, ~p"/admin/plays/#{translation.id}/export/html"), 200) =~
               "Original Play"
    end

    @list_wit ~s(<listWit><witness xml:id="Q1" n="Q1"><bibl type="edicion_antigua" subtype="suelta"><title>THE Tragicall Historie of HAMLET</title><pubPlace>London</pubPlace><date when="1603">1603</date></bibl></witness></listWit>)

    defp witness_play(opts) do
      [source_desc: @list_wit]
      |> Keyword.merge(opts)
      |> tei()
      |> import_tei!()
      |> Playcode.TestFixtures.mark_complete!()
    end

    test "the downloads print the witnesses of a play with variants", %{conn: conn} do
      play =
        witness_play(
          body:
            ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso<app n="1"><lem wit="#Q1">Verso</lem><rdg wit="#B">Canto</rdg></app></l></sp></div1>)
        )

      doc = LazyHTML.from_document(response(get(conn, ~p"/export/#{play.id}/html"), 200))
      assert doc |> LazyHTML.query(".witnesses h2") |> LazyHTML.text() == "Witnesses"

      assert doc |> LazyHTML.query(".witnesses li") |> LazyHTML.text() =~
               "Tragicall Historie of HAMLET"

      assert epub_text(conn, play) =~ "Tragicall Historie of HAMLET"

      # Its variants hidden, no reading names the witnesses, so they stay out too.
      {:ok, _} = Playcode.Catalogue.update_play(play, %{show_variants: false})
      refute response(get(conn, ~p"/export/#{play.id}/html"), 200) =~ "Tragicall"
    end

    test "a critical apparatus after the text makes a critical edition; another appendix does not",
         %{conn: conn} do
      body = ~s(<div1 type="acto" n="1"><sp><speaker>REY</speaker><l n="1">Verso</l></sp></div1>)

      apparatus =
        witness_play(
          body: body,
          back:
            ~s(<div type="apendice"><head>Critical Apparatus</head><p>1 Verso] Canto Q1.</p></div>)
        )

      # EMOTHE0310's translator's note is an appendix after the text too.
      note =
        witness_play(
          body: body,
          back: ~s(<div type="apendice"><head>Nota del traductor</head><p>Una nota.</p></div>)
        )

      assert response(get(conn, ~p"/export/#{apparatus.id}/html"), 200) =~ "Tragicall"
      assert epub_text(conn, apparatus) =~ "Tragicall"
      refute response(get(conn, ~p"/export/#{note.id}/html"), 200) =~ "Tragicall"
      refute epub_text(conn, note) =~ "Tragicall"
    end

    defp publication_lines(html) do
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query(".publication p")
      |> Enum.map(&LazyHTML.text/1)
    end

    test "the downloads print the publication details, the identifiers, the licence and the project statement",
         %{conn: conn, play: play} do
      {:ok, play} =
        Playcode.Catalogue.update_play(play, %{
          publisher: "Norton & Company",
          pub_place: "Valencia",
          publication_date: "2012",
          authority: "Universitat de València",
          emothe_id: "0555",
          licence_text: "CC BY-NC-ND 4.0",
          licence_url: "https://creativecommons.org/licenses/by-nc-nd/4.0/",
          availability_note: "Se ruega citar la procedencia.",
          project_description: "El proyecto EMOTHE.\n\nCarlos Muñoz Pons es responsable.",
          editorial_declaration: "Las presentes ediciones digitales están basadas…"
        })

      html = response(get(conn, ~p"/export/#{play.id}/html"), 200)

      assert publication_lines(html) == [
               "Publication: Norton & Company, Valencia, 2012",
               "Authority: Universitat de València",
               "Identifiers: #{play.code}, EMOTHE 0555",
               "Licence: CC BY-NC-ND 4.0 https://creativecommons.org/licenses/by-nc-nd/4.0/",
               "Se ruega citar la procedencia.",
               "El proyecto EMOTHE.",
               "Carlos Muñoz Pons es responsable."
             ]

      assert html =~ ~s(<a href="https://creativecommons.org/licenses/by-nc-nd/4.0/">)

      epub = epub_text(conn, play)
      assert epub =~ "Publication: Norton &amp; Company, Valencia, 2012"
      assert epub =~ "<p>Carlos Muñoz Pons es responsable.</p>"

      # The editorial statement, the same paragraph in every file, stays out (question 24).
      for text <- [html, epub], do: refute(text =~ "Las presentes ediciones")
    end

    test "the downloads print only what the play has, and link a licence only to a web address",
         %{conn: conn, play: play} do
      assert publication_lines(response(get(conn, ~p"/export/#{play.id}/html"), 200)) ==
               ["Identifiers: #{play.code}"]

      {:ok, play} = Playcode.Catalogue.update_play(play, %{licence_url: "javascript:alert(1)"})
      html = response(get(conn, ~p"/export/#{play.id}/html"), 200)

      assert publication_lines(html) == [
               "Identifiers: #{play.code}",
               "Licence: javascript:alert(1)"
             ]

      refute html =~ ~s(href="javascript:)
    end
  end
end
