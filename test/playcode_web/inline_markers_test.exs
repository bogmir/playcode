defmodule PlaycodeWeb.InlineMarkersTest do
  @moduledoc """
  No output prints a stored text's italics markers. Every text the TEI importer reads
  holds an `<emph>` as `<<…>>` (CLAUDE.md, "Inline markers in stored text"), and a text
  printed with `{text}` or `escape/1` shows them to readers as `&lt;&lt;…&gt;&gt;`: the
  comparison download did so in its headings and cast lists for weeks, and five more
  places were found only by sweeping the dev database by hand (2026-11-04).

  One play with italics in every text that carries them in the corpus goes through the
  play's public pages, its HTML, EPUB and TEI downloads, the comparison download and the
  static site. The header's texts (title, author, editors' names) and the dating notes are
  plain: no play has italics there, and every output prints them escaped
  (`docs/backlog.md`, "The front matter prints the header's texts through `escape/1`").
  """
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.ImportHelpers
  import Playcode.StaticSiteHelpers
  import Playcode.TestFixtures

  alias Playcode.Catalogue
  alias Playcode.PlayContent

  defp italics_everywhere do
    code = "MRK#{System.unique_integer([:positive])}"

    xml =
      tei(
        code: code,
        title: "La Celestina",
        title_stmt: """
        <author>Rojas, Fernando de</author>
        <editor role="edicion_critica"><persName>Durá, Rosa</persName></editor>
        """,
        source_desc: """
        <bibl><title>Base <emph>princeps</emph></title><note>Nota de <emph>fuente</emph></note></bibl>
        <listWit><witness n="A"><bibl><title>Testigo <emph>raro</emph></title><note>Nota <emph>testigo</emph></note></bibl></witness></listWit>
        """,
        front: """
        <div type="dedicatoria"><head>Al <emph>lector</emph></head><p>Prosa <emph>cursiva</emph> del prólogo.</p></div>
        <div type="elenco"><head>Las <emph>personas</emph></head><castList>
          <castItem><role xml:id="ANA">Doña <emph>Ana</emph></role><roleDesc>una <emph>dama</emph></roleDesc></castItem>
        </castList></div>
        """,
        body: """
        <div1 type="acto" n="1"><head>Acto <emph>primero</emph></head>
          <div2 type="escena" n="1"><head>Escena <emph>única</emph></head>
            <stage>Sale <emph>Ana</emph>.</stage>
            <sp who="#ANA"><speaker>Doña <emph>Ana</emph></speaker>
              <l n="1">Un verso <emph>cursivo</emph> aquí<note type="editor"><term>verso</term><p>Nota <emph>al verso</emph>.</p></note></l>
              <l n="2">y otro verso para el fin</l>
            </sp>
          </div2>
        </div1>
        """
      )

    {:ok, play} = xml |> import_tei!() |> Catalogue.update_play(%{"is_complete" => true})
    play
  end

  # Every place a marker shows, with the words around it, so one run names them all.
  defp refute_leak(output, where) do
    case Regex.scan(~r/.{0,50}(?:&lt;&lt;|&gt;&gt;|<<|>>).{0,30}/, output) do
      [] -> :ok
      found -> flunk("#{where} prints markers:\n" <> Enum.map_join(found, "\n", &"  …#{hd(&1)}…"))
    end
  end

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher)), play: italics_everywhere()}
  end

  test "the catalogue and every tab of the play's page", %{conn: conn, play: play} do
    {:ok, _lv, html} = live(conn, ~p"/plays")
    refute_leak(html, "the catalogue")

    {:ok, lv, html} = live(conn, ~p"/plays/#{play.code}")
    refute_leak(html, "the play's text")

    for tab <- ["Statistics", "Notes"] do
      lv |> element("button", t(tab)) |> render_click() |> refute_leak("the play's #{tab}")
    end
  end

  test "the HTML, EPUB and TEI downloads", %{conn: conn, play: play} do
    conn |> get(~p"/export/#{play.id}/html") |> response(200) |> refute_leak("the HTML")
    conn |> get(~p"/export/#{play.id}/tei") |> response(200) |> refute_leak("the TEI")

    {:ok, files} = :zip.unzip(response(get(conn, ~p"/export/#{play.id}/epub"), 200), [:memory])

    for {name, content} <- files, Path.extname(to_string(name)) in ~w(.xhtml .opf .ncx) do
      refute_leak(content, "the EPUB's #{name}")
    end
  end

  test "the comparison download", %{conn: conn, play: play} do
    other = italics_everywhere()

    conn
    |> get(~p"/admin/plays/compare/export/html?#{[plays: "#{play.id},#{other.id}"]}")
    |> response(200)
    |> refute_leak("the comparison")
  end

  test "the static site's pages", %{play: play} do
    dir = generate!([play])

    for path <- Path.wildcard(Path.join(dir, "**/*.html")) do
      path |> File.read!() |> refute_leak(Path.relative_to(path, dir))
    end
  end

  test "the play really holds the markers the outputs must not print", %{play: play} do
    assert [%{note: "Nota de <<fuente>>"}] = Catalogue.get_play_with_all!(play.id).sources
    assert "Doña <<Ana>>" in Enum.map(PlayContent.list_characters(play.id), & &1.name)
  end
end
