defmodule PlaycodeWeb.ExportController do
  @moduledoc """
  The public downloads under /export/:id: a play's TEI, HTML, PDF and EPUB. A draft is a
  404 except for staff. The PDF renders through headless Chrome on every request.
  """

  use PlaycodeWeb, :controller

  alias Playcode.{Authz, Catalogue}
  alias Playcode.Export
  alias Playcode.Export.PdfCache

  def tei(conn, %{"id" => id}) do
    play = visible_play!(conn, id)
    xml = Export.TeiXml.generate(play)

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.xml"))
    |> send_resp(200, xml)
  end

  def html(conn, %{"id" => id}) do
    play = visible_play!(conn, id)
    html = Export.Html.generate(play)

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.html"))
    |> send_resp(200, html)
  end

  def pdf(conn, %{"id" => id}) do
    play = visible_play!(conn, id)

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

  def epub(conn, %{"id" => id}) do
    play = visible_play!(conn, id)

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

  # A draft is for staff only; anyone else gets the 404 an unknown id gets.
  defp visible_play!(conn, id) do
    Catalogue.get_play_with_all!(id,
      complete: not Authz.can?(conn.assigns.current_user, :view_drafts)
    )
  end
end
