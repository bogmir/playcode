defmodule PlaycodeWeb.PdfDownloadTest do
  @moduledoc """
  The PDF downloads, public and staff, with Chrome replaced by
  `Playcode.PdfRendererStub`. Not async: every render goes through the one
  `Playcode.Export.PdfCache`, and the stub reads the application environment.
  """
  use PlaycodeWeb.ConnCase, async: false

  import Playcode.TestFixtures

  alias Playcode.Catalogue
  alias Playcode.Export.PdfCache

  setup do
    File.rm_rf!(PdfCache.dir())
    stub(mode: :ok)

    on_exit(fn ->
      Application.delete_env(:playcode, Playcode.PdfRendererStub)
      Application.delete_env(:playcode, :pdf_max_renders)
    end)

    %{play: play_fixture(%{"is_complete" => true})}
  end

  defp stub(opts),
    do: Application.put_env(:playcode, Playcode.PdfRendererStub, [notify: self()] ++ opts)

  defp download(conn, play), do: get(conn, ~p"/export/#{play.id}/pdf")

  defp preparing,
    do: t("The PDF is being prepared. A long play takes a while: try again in a minute.")

  defp busy, do: t("Other PDFs are being prepared. Try again in a minute.")
  defp failed, do: t("The PDF could not be made. Try again later.")

  test "a PDF is rendered once per version of the play, then served from disk",
       %{conn: conn, play: play} do
    first = download(conn, play)
    assert response(first, 200) =~ "%PDF"
    assert get_resp_header(first, "content-type") == ["application/pdf"]

    assert get_resp_header(first, "content-disposition") ==
             [~s(attachment; filename="#{play.code}.pdf")]

    assert_received {:rendering, _code, _renderer}

    assert response(download(conn, play), 200) == response(first, 200)
    refute_received {:rendering, _code, _renderer}

    # An edit moves the play's content_version: the next download renders that version,
    # and the file of the old one is removed.
    {:ok, _} = Catalogue.update_play(play, %{title: "Retitulada"})
    edited = Catalogue.get_play!(play.id)

    assert response(download(conn, play), 200) =~ "version #{edited.content_version}"
    assert_received {:rendering, _code, _renderer}
    assert [_one_file] = File.ls!(PdfCache.dir())
  end

  test "a long render says the PDF is being prepared, and finishes on its own",
       %{conn: conn, play: play} do
    stub(mode: :block)

    pending = download(conn, play)
    assert response(pending, 503) =~ preparing()
    assert get_resp_header(pending, "retry-after") == ["60"]
    assert_received {:rendering, _code, renderer}

    # A second request joins the render under way instead of starting another.
    assert response(download(conn, play), 503) =~ preparing()
    refute_received {:rendering, _code, _renderer}

    send(renderer, :release)
    assert response(download(conn, play), 200) =~ "%PDF"
    refute_received {:rendering, _code, _renderer}
  end

  # Each render starts a Chrome of its own, so by default only one runs: two at once
  # would not fit the 1 GB machine.
  test "while one play's PDF renders, another play's answers busy",
       %{conn: conn, play: play} do
    stub(mode: :block)

    assert response(download(conn, play), 503) =~ preparing()
    assert_received {:rendering, _code, renderer}

    refused = download(conn, play_fixture(%{"is_complete" => true}))
    assert response(refused, 503) =~ busy()
    assert get_resp_header(refused, "retry-after") == ["60"]
    refute_received {:rendering, _code, _renderer}

    send(renderer, :release)
    assert response(download(conn, play), 200) =~ "%PDF"
  end

  @tag :capture_log
  test "a render that fails or crashes says so, is not kept, and the next one tries again",
       %{conn: conn, play: play} do
    stub(mode: {:error, :timeout})
    assert response(download(conn, play), 503) =~ failed()

    stub(mode: :raise)
    assert response(download(conn, play), 503) =~ failed()

    stub(mode: :ok)
    assert response(download(conn, play), 200) =~ "%PDF"
  end

  test "staff get the same PDF from their tab, and a flash while it is prepared",
       %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    draft = play_fixture()

    assert response(get(conn, ~p"/admin/plays/#{draft.id}/export/pdf"), 200) =~ "%PDF"

    stub(mode: :block)
    other = play_fixture()
    pending = get(conn, ~p"/admin/plays/#{other.id}/export/pdf")

    assert redirected_to(pending) == ~p"/admin/plays/#{other.id}"
    assert Phoenix.Flash.get(pending.assigns.flash, :info) == preparing()

    assert_received {:rendering, _code, _first}
    assert_received {:rendering, _code, renderer}
    send(renderer, :release)
  end
end
