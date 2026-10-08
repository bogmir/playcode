defmodule PlaycodeWeb.Admin.ExportController do
  @moduledoc """
  Staff downloads: a play's TEI, HTML, PDF and EPUB, a side-by-side comparison as one HTML
  page, and the generated static site, as a .zip or browsed in place under
  /admin/export/preview. Each download is logged.
  """

  use PlaycodeWeb, :controller

  alias Playcode.Catalogue
  alias Playcode.Export
  alias Playcode.Export.PdfCache
  alias Playcode.ActivityLog

  def compare_html(conn, %{"plays" => play_ids_str}) do
    play_ids = String.split(play_ids_str, ",", trim: true)
    plays = Enum.map(play_ids, &Catalogue.get_play_with_all!/1)
    html = Export.CompareHtml.generate(plays)
    codes = Enum.map_join(plays, "_vs_", & &1.code)

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("content-disposition", ~s(attachment; filename="compare_#{codes}.html"))
    |> send_resp(200, html)
  end

  def tei(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)
    xml = Export.TeiXml.generate(play)

    log_export(conn, play, "tei")

    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.xml"))
    |> send_resp(200, xml)
  end

  def html(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)
    html = Export.Html.generate(play)

    log_export(conn, play, "html")

    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.html"))
    |> send_resp(200, html)
  end

  def pdf(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)

    case PdfCache.fetch(play) do
      {:ok, path} ->
        log_export(conn, play, "pdf")

        conn
        |> put_resp_content_type("application/pdf", nil)
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.pdf"))
        |> send_file(200, path)

      {:error, reason} ->
        kind = if reason == :pending, do: :info, else: :error

        conn
        |> put_flash(kind, PlaycodeWeb.ExportController.pdf_unavailable(reason))
        |> redirect(to: ~p"/admin/plays/#{id}")
    end
  end

  def epub(conn, %{"id" => id}) do
    play = Catalogue.get_play_with_all!(id)

    case Export.Epub.generate(play) do
      {:ok, epub_binary} ->
        log_export(conn, play, "epub")

        conn
        |> put_resp_content_type("application/epub+zip")
        |> put_resp_header("content-disposition", ~s(attachment; filename="#{play.code}.epub"))
        |> send_resp(200, epub_binary)

      {:error, reason} ->
        conn
        |> put_flash(
          :error,
          gettext("EPUB generation failed: %{reason}", reason: inspect(reason))
        )
        |> redirect(to: ~p"/admin/plays/#{id}")
    end
  end

  def download_zip(conn, _params) do
    zip_path = Path.join(System.tmp_dir!(), "emothe-static-site.zip")

    if File.exists?(zip_path) do
      conn
      |> put_resp_content_type("application/zip")
      |> put_resp_header("content-disposition", ~s(attachment; filename="emothe-static-site.zip"))
      |> send_file(200, zip_path)
    else
      conn
      |> put_flash(:error, gettext("No zip file found. Generate the static site first."))
      |> redirect(to: ~p"/admin/export")
    end
  end

  @doc """
  Serves the built static site from its output directory, so it can be checked before it
  is downloaded or deployed. Its links are relative, so it works under this prefix.
  """
  def preview(conn, %{"path" => path}) do
    root = Playcode.Export.StaticSite.output_dir()

    if File.regular?(Path.join(root, "index.html")),
      do: serve_site_file(conn, root, path),
      else:
        conn
        |> put_flash(:error, gettext("No site built yet. Generate the static site first."))
        |> redirect(to: ~p"/admin/export")
  end

  defp serve_site_file(conn, root, path) do
    with {:ok, relative} <- Path.safe_relative(Enum.join(path, "/")),
         file = Path.join(root, relative),
         true <- File.regular?(file) do
      conn
      |> put_resp_content_type(MIME.from_path(file))
      |> send_file(200, file)
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  defp log_export(conn, play, format) do
    user = conn.assigns[:current_user]

    ActivityLog.log!(%{
      user_id: user && user.id,
      play_id: play.id,
      action: "export",
      resource_type: "play",
      resource_id: play.id,
      metadata: %{format: format, title: play.title, code: play.code}
    })
  end
end
