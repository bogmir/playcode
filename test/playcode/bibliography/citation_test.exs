defmodule Playcode.Bibliography.CitationTest do
  @moduledoc """
  How an entry is printed: one example per shape pins the order, labels and punctuation.
  test/playcode/bibliography/oracle_test.exs checks against FileMaker's own citations that
  nothing FileMaker printed is left out.
  """
  use ExUnit.Case, async: true

  alias Playcode.Bibliography.{Citation, Entry, Link}

  defp entry(attrs), do: struct(Entry, attrs)
  defp italics(parts), do: for(%{italic: true, text: text} <- parts, do: text)

  test "an article: author, quoted title, journal, then year, volume, issue and pages" do
    article =
      entry(
        kind: "criticism",
        pub_type: "article",
        analytic_author: "Barnett, Timothy Brian",
        analytic_title: "Lope and Tasso",
        monogr_author: "Not printed for a journal",
        monogr_title: "Bulletin of the Comediantes",
        year_text: "2005",
        volume: "57",
        issue: "2",
        pages: "238-294"
      )

    assert Citation.plain(article) ==
             ~s(Barnett, Timothy Brian. "Lope and Tasso". Bulletin of the Comediantes. 2005, 57, 2, p. 238-294.)
  end

  test "a play in an anthology: its translator, then the book's editor, title and imprint" do
    section =
      entry(
        kind: "translation",
        pub_type: "book_section",
        analytic_author: "Dryden, John",
        analytic_title: "Tutto per l'amore",
        analytic_translators: "Gerevini, Silvano",
        monogr_editors: "Obertello, Alfredo",
        monogr_title: "Teatro inglese",
        pub_place: "Milano",
        publisher: "Nuova Accademia",
        year_text: "1961",
        pages: "457-521"
      )

    assert Citation.plain(section) ==
             ~s(Dryden, John. "Tutto per l'amore". Tra. Gerevini, Silvano. Ed. Obertello, Alfredo. Teatro inglese. Milano: Nuova Accademia, 1961, p. 457-521.)
  end

  test "a translated book: series and original title close it, and no full stop is doubled" do
    book =
      entry(
        kind: "translation",
        pub_type: "book",
        monogr_author: "Peele, George",
        monogr_title: "Altweibermär",
        monogr_translators: "Harbecke, Ulrich J.",
        pub_place: "Weinheim",
        publisher: "Deutscher Laienspiel-Verlag",
        year_text: "1967",
        series: "Das Bühnenspiel",
        original_title: "Old Wife's Tale"
      )

    assert Citation.plain(book) ==
             "Peele, George. Altweibermär. Tra. Harbecke, Ulrich J. Weinheim: Deutscher Laienspiel-Verlag, 1967. Das Bühnenspiel. (Orig: Old Wife's Tale)"
  end

  test "a scholar's edition marks its editor, and a missing level leaves no stray full stop" do
    edition =
      entry(
        kind: "criticism",
        pub_type: "scholarly_edition",
        analytic_author: "Agheana, Ion T.",
        analytic_title: "La dialéctica",
        monogr_title: "Hispanic Studies in Honor of Frank P. Casa",
        pub_place: "New York",
        publisher: "Peter Lang",
        year_text: "1997",
        pages: "281-288"
      )

    assert Citation.plain(edition) ==
             ~s(Agheana, Ion T., ed. "La dialéctica". Hispanic Studies in Honor of Frank P. Casa. New York: Peter Lang, 1997, p. 281-288.)
  end

  test "a play in collected works: editor first, italic titles, In:, and the link's volume and pages" do
    rowe =
      entry(
        kind: "modern_edition",
        pub_type: "book_section",
        analytic_editors: "Rowe, Nicholas",
        analytic_title: "Hamlet",
        analytic_author: "Shakespeare, William",
        monogr_title: "The Works of Mr. William Shakespeare",
        pub_place: "London",
        publisher: "Jacob Tonson",
        year_text: "1709",
        volumes_total: "6",
        volume: "1",
        pages: "1-50"
      )

    link = %Link{volume: "5", pages: "2366-2466"}

    assert Citation.plain(rowe, link) ==
             "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 5. London: Jacob Tonson, 1709, pp. 2366-2466, 6 vols."

    assert italics(Citation.parts(rowe, link)) == [
             "Hamlet",
             "The Works of Mr. William Shakespeare"
           ]

    assert Citation.plain(rowe) =~ "Vol. 1. London: Jacob Tonson, 1709, pp. 1-50, 6 vols."
  end

  test "a modern edition as a book: series and the printed note close it; internal fields never print" do
    arden =
      entry(
        kind: "modern_edition",
        pub_type: "book",
        monogr_editors: "Thompson, Ann; Taylor, Neil",
        monogr_title: "Hamlet",
        monogr_author: "Shakespeare, William",
        pub_place: "London",
        publisher: "Thomson Learning",
        year_text: "2006",
        edition: "2nd",
        series: "The Arden Shakespeare",
        public_note: "Third series",
        note: "Revisar el cuarto",
        siglum: "ARD3Q2"
      )

    assert Citation.plain(arden, %Link{note: "Préstamo"}) ==
             "Thompson, Ann; Taylor, Neil, ed. Hamlet. Shakespeare, William. 2nd ed. London: Thomson Learning, 2006. The Arden Shakespeare. Third series."
  end

  test "an edition typed with its abbreviation is not abbreviated twice" do
    assert Citation.plain(
             entry(kind: "criticism", pub_type: "book", monogr_title: "T", edition: "2nd ed")
           ) == "T. 2nd ed."
  end

  test "<<…>> inside a title is italics" do
    grilli =
      entry(
        kind: "criticism",
        pub_type: "article",
        analytic_author: "Grilli, Giuseppe",
        analytic_title: "Lope y su fábula de <<Adonis y Venus>>",
        monogr_title: "Anuario Lope de Vega",
        year_text: "1998"
      )

    assert italics(Citation.parts(grilli)) == ["Adonis y Venus"]

    assert Citation.plain(grilli) ==
             ~s(Grilli, Giuseppe. "Lope y su fábula de Adonis y Venus". Anuario Lope de Vega. 1998.)
  end

  test "the web address comes last, with its access date" do
    kyd =
      entry(
        kind: "translation",
        pub_type: "book_section",
        analytic_author: "Kyd, Thomas",
        analytic_title: "La tragedia española",
        monogr_title: "EMOTHE",
        year_text: "2018",
        url: "https://emothe.uv.es/x.php",
        url_accessed_on: "2019-05-12"
      )

    assert Citation.plain(kyd) ==
             ~s|Kyd, Thomas. "La tragedia española". EMOTHE. 2018. URL: https://emothe.uv.es/x.php (acc. 2019-05-12)|

    assert %{url: "https://emothe.uv.es/x.php", href: "https://emothe.uv.es/x.php"} in Citation.parts(
             kyd
           )
  end

  # Review focus 1 and 5: what a curator or the FileMaker dump can put in a field.
  test "only http and https addresses become links, and every field is escaped" do
    base = entry(kind: "criticism", pub_type: "book", monogr_title: "<script>alert(1)</script>")

    for url <- ["javascript:alert(1)", ". http://emothe.uv.es/x.php"] do
      assert %{url: ^url, href: nil} = List.last(Citation.parts(%{base | url: url}))
      refute Phoenix.HTML.safe_to_string(Citation.html(%{base | url: url})) =~ "<a "
    end

    html =
      %{base | url: "https://e.org/?a=1&b=<2>"}
      |> Citation.html()
      |> Phoenix.HTML.safe_to_string()

    refute html =~ "<script>"
    assert html =~ "&lt;script&gt;alert(1)&lt;/script&gt;"
    assert html =~ ~s(<a href="https://e.org/?a=1&amp;b=&lt;2&gt;" rel="noopener">)
  end

  test "html marks italics with em" do
    html =
      entry(kind: "modern_edition", pub_type: "book", monogr_title: "Hamlet")
      |> Citation.html()
      |> Phoenix.HTML.safe_to_string()

    assert html == "<em>Hamlet</em>."
  end
end
