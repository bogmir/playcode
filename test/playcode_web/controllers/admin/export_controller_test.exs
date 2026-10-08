defmodule PlaycodeWeb.Admin.ExportControllerTest do
  use PlaycodeWeb.ConnCase, async: true

  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  setup %{conn: conn} do
    %{
      conn: log_in_user(conn, user_fixture(role: :researcher)),
      play: play_with_metadata_fixture()
    }
  end

  defp attachment(conn), do: conn |> get_resp_header("content-disposition") |> List.first()

  test "TEI and HTML downloads are named after the play, and each is logged",
       %{conn: conn, play: play} do
    tei = get(conn, ~p"/admin/plays/#{play.id}/export/tei")
    assert xml_texts(response(tei, 200), "title", within: "titleStmt") |> Enum.member?(play.title)
    assert get_resp_header(tei, "content-type") |> List.first() =~ "application/xml"
    assert attachment(tei) == ~s(attachment; filename="#{play.code}.xml")

    html = get(conn, ~p"/admin/plays/#{play.id}/export/html")
    assert response(html, 200) =~ play.title
    assert attachment(html) == ~s(attachment; filename="#{play.code}.html")

    formats =
      [action: "export", play_id: play.id]
      |> Playcode.ActivityLog.list_entries()
      |> Enum.map(& &1.metadata["format"])
      |> Enum.sort()

    assert formats == ["html", "tei"]
  end

  test "the EPUB download is an e-book with the play's title", %{conn: conn, play: play} do
    conn = get(conn, ~p"/admin/plays/#{play.id}/export/epub")

    assert {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
    assert Enum.any?(files, fn {_name, content} -> content =~ play.title end)
    assert attachment(conn) == ~s(attachment; filename="#{play.code}.epub")
  end

  test "two plays compared side by side download as one page", %{conn: conn, play: play} do
    other = play_fixture(%{"title" => "La otra versión"})

    conn = get(conn, ~p"/admin/plays/compare/export/html?#{[plays: "#{play.id},#{other.id}"]}")

    body = response(conn, 200)
    assert body =~ play.title
    assert body =~ "La otra versión"

    assert attachment(conn) ==
             ~s(attachment; filename="compare_#{play.code}_vs_#{other.code}.html")
  end

  # The page is opened from disk, so its sync script must carry the matcher inline and
  # its speeches the act keys the matcher reads, as on the live compare page.
  test "a downloaded comparison keys speeches by act, and its sync script runs alone",
       %{conn: conn} do
    %{original: original, translation: translation} = differently_numbered_editions()

    conn =
      get(
        conn,
        ~p"/admin/plays/compare/export/html?#{[plays: "#{original.id},#{translation.id}"]}"
      )

    page = conn |> response(200) |> LazyHTML.from_document()

    for panel <- ["panel-0", "panel-1"] do
      keys = fn attribute ->
        page
        |> LazyHTML.query("[data-panel='#{panel}'] [#{attribute}]")
        |> LazyHTML.attribute(attribute)
      end

      assert {panel, keys.("data-sync-div"), keys.("data-sync-act")} ==
               {panel, ["act-0", "act-1", "act-1/scene-0"], ["act-0", "act-1", "act-1"]}
    end

    script = page |> LazyHTML.query("script") |> LazyHTML.text()

    # A classic script, as a browser runs it: Node would otherwise accept `export`.
    {out, 0} =
      System.cmd("node", [
        "--input-type=commonjs",
        "-e",
        "globalThis.document = {addEventListener() {}};\n" <>
          script <>
          ~s|\nconsole.log(matchSpeech(["act-0", "act-1", "act-1"], ["act-0", "act-1"], 2))|
      ])

    assert String.trim(out) == "1"
  end

  describe "a play with in-text notes" do
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO I</head>
              <sp><speaker>ANA</speaker>
                <l n="1">Nous <emph>voyent</emph><note n="6089" type="editor"><term>voyent</term><p>Forme &amp; archaïque.</p></note> dans la ville</l>
              </sp>
            </div1>
            """
          )
        )

      %{noted: play}
    end

    test "the HTML download numbers a note after its word and lists it after the act",
         %{conn: conn, noted: play} do
      doc =
        conn
        |> get(~p"/admin/plays/#{play.id}/export/html")
        |> response(200)
        |> LazyHTML.from_document()

      text = doc |> LazyHTML.text() |> String.replace(~r/\s+/u, " ")

      assert text =~ "Nous voyent1 dans la ville"
      refute text =~ "<<"
      assert "voyent" in (doc |> LazyHTML.query("em") |> Enum.map(&LazyHTML.text/1))
      assert doc |> LazyHTML.query("sup a") |> LazyHTML.attribute("href") == ["#note-1"]

      endnote = doc |> LazyHTML.query("#note-1") |> LazyHTML.text()
      assert endnote =~ "Editor's note"
      assert endnote =~ "voyent"
      assert endnote =~ "Forme & archaïque."
      assert doc |> LazyHTML.query("#note-1 a") |> LazyHTML.attribute("href") == ["#ref-1"]

      # The endnote's back-link lands on the marker: the marker carries the id it points at.
      assert doc |> LazyHTML.query("sup a") |> LazyHTML.attribute("id") == ["ref-1"]
    end

    test "the EPUB marks a note as a noteref, with its footnote in the act's chapter",
         %{conn: conn, noted: play} do
      conn = get(conn, ~p"/admin/plays/#{play.id}/export/epub")
      {:ok, files} = :zip.unzip(response(conn, 200), [:memory])
      {_name, chapter} = Enum.find(files, fn {name, _} -> to_string(name) =~ "chapter-001" end)

      # Well-formed XHTML, or e-readers refuse the chapter. Saxy is given it without its
      # DOCTYPE, which is not what is being checked.
      assert {:ok, _} =
               chapter
               |> String.replace(~r/<!DOCTYPE[^>]*>/, "")
               |> Saxy.SimpleForm.parse_string()

      assert chapter =~ ~s(xmlns:epub="http://www.idpf.org/2007/ops")
      assert chapter =~ ~s(<a epub:type="noteref" href="#note-1">1</a>)
      assert chapter =~ ~s(<aside epub:type="footnote" id="note-1">)
      assert chapter =~ "Forme &amp; archaïque."
    end
  end

  describe "a play with a note in every place a note can sit" do
    setup do
      play =
        import_tei!(
          tei(
            body: """
            <div1 type="acto" n="1"><head>ACTO I<note n="1" type="autor"><p>Del encabezado.</p></note></head>
              <stage>Salen todos<note n="2" type="editor"><p>De la acotación.</p></note></stage>
              <div2 type="escena" n="1"><head>ESCENA<note n="3" type="traductor"><p>Del título.</p></note> I</head>
                <sp><speaker>ANA<note n="4" type="editor_critico"><p>Del hablante.</p></note></speaker>
                  <l n="1">verso<note n="5" type="editor_digital"><p>Del verso.</p></note></l>
                </sp>
                <sp><speaker>BLAS</speaker><p>prosa<note n="6" type="editor"><p>De la prosa.</p></note> final</p></sp>
              </div2>
            </div1>
            <div1 type="prologo" n="1"><head>LOA<note n="7" type="autor"><p>De la loa.</p></note></head>
              <stage>Sale la loa</stage>
            </div1>
            """
          )
        )

      %{everywhere: play}
    end

    test "the HTML download puts each number where its text is, in reading order",
         %{conn: conn, everywhere: play} do
      doc =
        conn
        |> get(~p"/admin/plays/#{play.id}/export/html")
        |> response(200)
        |> LazyHTML.from_document()

      text = doc |> LazyHTML.text() |> String.replace(~r/\s+/u, " ")

      # The act heading, a stage direction, the scene heading, a speaker, a line, a prose
      # paragraph and a prologue's heading: each number follows the word it glosses.
      for marked <- [
            "ACTO I1",
            "(Salen todos2)",
            "ESCENA3 I",
            "ANA4",
            "verso5",
            "prosa6 final",
            "LOA7"
          ] do
        assert text =~ marked
      end

      assert doc |> LazyHTML.query("sup a") |> LazyHTML.attribute("href") ==
               Enum.map(1..7, &"#note-#{&1}")

      # The act heading is an h2; the scene's and the prologue's headings are h3s.
      assert doc |> LazyHTML.query("h2 sup a") |> LazyHTML.attribute("href") == ["#note-1"]

      assert doc |> LazyHTML.query("h3 sup a") |> LazyHTML.attribute("href") ==
               ["#note-3", "#note-7"]

      # All seven are listed after their division, each with its type's label and its text.
      for {label, body, n} <- [
            {"Author's note", "Del encabezado.", 1},
            {"Editor's note", "De la acotación.", 2},
            {"Translator's note", "Del título.", 3},
            {"Critical editor's note", "Del hablante.", 4},
            {"Digital editor's note", "Del verso.", 5},
            {"Editor's note", "De la prosa.", 6},
            {"Author's note", "De la loa.", 7}
          ] do
        endnote = doc |> LazyHTML.query("#note-#{n}") |> LazyHTML.text()
        assert endnote =~ label
        assert endnote =~ body
      end
    end
  end
end
