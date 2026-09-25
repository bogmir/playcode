defmodule PlaycodeWeb.Admin.ImportLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.Catalogue

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture(role: :researcher))}
  end

  defp upload(lv, files) do
    entries =
      Enum.map(files, fn {name, content} ->
        %{name: name, content: content, type: "application/xml"}
      end)

    input = file_input(lv, "#upload-form", :tei_files, entries)
    Enum.each(files, fn {name, _} -> render_upload(input, name) end)

    lv |> element("#upload-form") |> render_submit()
  end

  # The view imports one file per message it sends itself, then one more message to
  # report. A render queues behind whatever the view has already sent itself, so one
  # render per file plus one sees the finished import.
  defp await_import(lv, files \\ 1) do
    for _ <- 1..files, do: render(lv)
    render(lv)
  end

  defp import_tei(lv, name, xml),
    do: lv |> upload([{name, xml}]) |> then(fn _ -> await_import(lv) end)

  test "an uploaded corpus file becomes a play, readable on its public page", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/import")

    path = "test/fixtures/EMOTHE0759_AutoDeLaBarcaDelInfierno.xml"
    html = import_tei(lv, Path.basename(path), File.read!(path))

    assert html =~ t("Successfully imported %{count} play(s).", count: 1)

    play = Catalogue.get_play_by_code!("EMOTHE0759_AutoDeLaBarcaDelInfierno")
    assert html =~ play.title

    [%{action: "import", play_id: play_id}] = Playcode.ActivityLog.list_entries(action: "import")
    assert play_id == play.id

    {:ok, _public, page} = live(conn, ~p"/plays/#{play.code}")
    assert page =~ play.title
  end

  describe "a file whose code is already a play" do
    setup %{conn: conn} do
      code = "IMP#{System.unique_integer([:positive])}"
      import_tei!(tei(code: code, title: "Primera versión"))
      {:ok, lv, _html} = live(conn, ~p"/admin/plays/import")
      %{lv: lv, code: code}
    end

    test "asks before replacing it, and replaces it on confirmation", %{lv: lv, code: code} do
      html = upload(lv, [{"again.xml", tei(code: code, title: "Segunda versión")}])

      assert html =~ t("Replace and import")
      assert Catalogue.get_play_by_code!(code).title == "Primera versión"

      lv |> element("button", t("Replace and import")) |> render_click()
      await_import(lv)

      assert Catalogue.get_play_by_code!(code).title == "Segunda versión"
    end

    test "leaves it alone when cancelled", %{lv: lv, code: code} do
      upload(lv, [{"again.xml", tei(code: code, title: "Segunda versión")}])

      lv |> element("button", t("Cancel")) |> render_click()

      assert Catalogue.get_play_by_code!(code).title == "Primera versión"
    end
  end

  test "a malformed file is reported and imports nothing", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/import")

    html = import_tei(lv, "broken.xml", "<TEI><teiHeader>")

    assert html =~ t("Import errors")
    assert html =~ "broken.xml"
    assert Catalogue.list_plays() == []
  end

  # No form sends import_directory any more, so the handler went too: a researcher's
  # socket could push it and make the server read and import every .xml under any
  # path it named. The view now has no clause for the event and crashes, as it does
  # for any unknown event. This test pinned the hole before the fix.
  @tag :capture_log
  test "a pushed import_directory event reads nothing from the server", %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "import-dir-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    code = "IMP#{System.unique_integer([:positive])}"
    File.write!(Path.join(dir, "play.xml"), tei(code: code))

    {:ok, lv, _html} = live(conn, ~p"/admin/plays/import")
    Process.flag(:trap_exit, true)
    catch_exit(render_submit(lv, "import_directory", %{"directory" => dir}))

    assert Catalogue.list_plays() == []
  end
end
