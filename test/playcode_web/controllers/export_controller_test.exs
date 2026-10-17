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
end
