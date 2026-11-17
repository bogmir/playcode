defmodule PlaycodeWeb.ExportController do
  @moduledoc """
  The downloads under /export/:id that staff's preview offers: a play's TEI, HTML, PDF and
  EPUB, draft or complete. The PDF renders through headless Chrome on every request.
  """

  use PlaycodeWeb, :controller

  alias Playcode.Catalogue
  alias Playcode.Catalogue.Play
  alias Playcode.Export
  alias Playcode.Export.PdfCache
  alias PlaycodeWeb.PlayLabels

  def tei(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)
    xml = Export.TeiXml.generate(play)

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.xml"))
    |> send_resp(200, xml)
  end

  def html(conn, %{"id" => id}) do
    with_text(conn, id, fn play ->
      html = Export.Html.generate(play)

      conn
      |> put_resp_content_type("text/html")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.html"))
      |> send_resp(200, html)
    end)
  end

  def pdf(conn, %{"id" => id}), do: with_text(conn, id, &pdf_of(conn, &1))

  defp pdf_of(conn, play) do
    case PdfCache.fetch(play) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("application/pdf", nil)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.pdf"))
        |> send_file(200, path)

      {:error, reason} ->
        conn
        |> put_resp_header("retry-after", "60")
        |> put_resp_content_type("text/plain")
        |> send_resp(503, pdf_unavailable(reason))
    end
  end

  @doc "What a reader is told when `PdfCache.fetch/1` has no PDF for them yet."
  def pdf_unavailable(:pending),
    do: gettext("The PDF is being prepared. A long play takes a while: try again in a minute.")

  def pdf_unavailable(:busy), do: gettext("Other PDFs are being prepared. Try again in a minute.")
  def pdf_unavailable(_reason), do: gettext("The PDF could not be made. Try again later.")

  def epub(conn, %{"id" => id}), do: with_text(conn, id, &epub_of(conn, &1))

  defp epub_of(conn, play) do
    case Export.Epub.generate(play) do
      {:ok, epub_binary} ->
        conn
        |> put_resp_content_type("application/epub+zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.epub"))
        |> send_resp(200, epub_binary)

      {:error, _reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(500, "EPUB generation failed")
    end
  end

  defp with_text(conn, id, download),
    do: with_text(conn, Catalogue.get_play_with_all!(id), download, &~p"/plays/#{&1.code}")

  @doc """
  `download.(play)`, unless the play has no text: then nothing is rendered or cached, and
  the reader is sent to `back.(play)` with the notice. A play without a text has no HTML,
  PDF or EPUB.
  """
  def with_text(conn, play, download, back) do
    if Play.has_text?(play) do
      download.(play)
    else
      conn
      |> put_flash(:info, PlayLabels.no_text_notice())
      |> redirect(to: back.(play))
    end
  end
end
