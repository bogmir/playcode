defmodule PlaycodeWeb.Admin.ImportLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.Catalogue
  alias Playcode.Import.TeiImport

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

    # The slow corpus sweep (roundtrip_test.exs) imports this file at the same time. Under
    # its own code the upload never waits on the sweep's uncommitted plays.code, which it
    # did until the sandbox cancelled it.
    path = "test/fixtures/EMOTHE0759_AutoDeLaBarcaDelInfierno.xml"
    code = "LIVE0759_AutoDeLaBarcaDelInfierno"
    xml = path |> File.read!() |> String.replace("EMOTHE0759_AutoDeLaBarcaDelInfierno", code)
    html = import_tei(lv, Path.basename(path), xml)

    assert html =~ t("Successfully imported %{count} play(s).", count: 1)

    play = Catalogue.get_play_by_code!(code)
    assert html =~ play.title

    [%{action: "import", play_id: play_id}] = Playcode.ActivityLog.list_entries(action: "import")
    assert play_id == play.id

    {:ok, _public, page} = live(conn, ~p"/plays/#{play.code}")
    assert page =~ play.title
  end

  # A new play whose file brings references: the curator sees which before they come in,
  # since one may duplicate a reference Playcode holds under a corrected description.
  test "a new play that would add references is shown first, and imported on confirmation",
       %{conn: conn} do
    code = "IMP#{System.unique_integer([:positive])}"
    {:ok, lv, _html} = live(conn, ~p"/admin/plays/import")

    html =
      upload(lv, [
        {"new.xml",
         tei(
           code: code,
           back:
             ~s(<div type="bibliografia"><listBibl type="critica"><biblStruct type="libro"><monogr>) <>
               ~s(<author>Autor, Ana</author><title level="m">Libro nuevo</title><imprint><date/></imprint>) <>
               ~s(</monogr></biblStruct></listBibl></div>)
         )}
      ])

    assert html =~ t("Adds %{count} reference(s) to the bibliography:", count: 1)
    assert html =~ "Libro nuevo"
    assert Catalogue.list_plays(search: code) == []

    lv |> element("button", ~r/^\s*#{t("Import")}\s*$/) |> render_click()
    await_import(lv)

    assert Catalogue.get_play_by_code!(code)
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

    test "lists the references a re-import would add", %{lv: lv, code: code} do
      html =
        upload(lv, [
          {"again.xml",
           tei(
             code: code,
             back:
               ~s(<div type="bibliografia"><listBibl type="critica"><biblStruct type="libro"><monogr>) <>
                 ~s(<author>Autor, Ana</author><title level="m">Libro nuevo</title><imprint><date/></imprint>) <>
                 ~s(</monogr></biblStruct></listBibl></div>)
           )}
        ])

      assert html =~ t("Adds %{count} reference(s) to the bibliography:", count: 1)
      assert html =~ "Libro nuevo"
    end

    test "lists the references a re-import would skip", %{lv: lv, code: code} do
      html =
        upload(lv, [
          {"again.xml",
           tei(
             code: code,
             back:
               ~s(<div type="bibliografia"><listBibl type="critica"><biblStruct type="libro" xml:lang="la">) <>
                 ~s(<monogr><author>Autor, Ana</author><title level="m">Liber</title><imprint><date/></imprint>) <>
                 ~s(</monogr></biblStruct></listBibl></div>)
           )}
        ])

      assert html =~ t("Skips %{count} reference(s) Playcode cannot store:", count: 1)
      assert html =~ "Liber"
    end

    test "says how many of the file's rows were edited since their import",
         %{lv: lv, code: code} do
      cast =
        ~s(<div type="elenco"><castList><castItem><role xml:id="REY">REY</role></castItem></castList></div>)

      play = tei(code: code, front: cast) |> import_tei!() |> Playcode.TestFixtures.age_rows!()
      [character] = Playcode.PlayContent.list_characters(play.id)
      {:ok, _} = Playcode.PlayContent.update_character(character, %{"actor" => "Mr. Betterton"})

      html = upload(lv, [{"again.xml", tei(code: code, title: "Segunda versión")}])

      assert html =~
               t(
                 "%{count} row(s) from the file were edited by hand since its import: importing replaces them too.",
                 count: 1
               )
    end

    # The preview names every column `TeiImport` keeps (`TeiImport.platform_owned/0`, in that
    # order); a column without a label crashed the page. A column added to the list fails here
    # until it has a value to set and a label to read, not in production.
    test "names the columns a curator set, which the import keeps", %{lv: lv, code: code} do
      relative = play_fixture(%{"title" => "Original"})

      curated = %{
        language: {"en", "language"},
        relationship_type: {"traduccion", "relationship"},
        parent_play_id: {relative.id, "parent play"},
        is_complete: {true, "completeness"},
        show_variants: {false, "variant readings"},
        historical_time: {"edad_media", "historical time"},
        historical_time_note: {"Reinado de Juan I", "historical time note"},
        composition_date_from: {1606, "composition date (from)"},
        composition_date_to: {1607, "composition date (to)"},
        composition_date_note: {"typed by a curator", "composition date note"},
        form: {"mixed", "form"}
      }

      assert Enum.sort(Map.keys(curated)) == Enum.sort(TeiImport.platform_owned())

      {:ok, _} =
        code
        |> Catalogue.get_play_by_code!()
        |> Catalogue.update_play(Map.new(curated, fn {column, {value, _}} -> {column, value} end))

      html = upload(lv, [{"again.xml", tei(code: code)}])

      fields =
        Enum.map_join(TeiImport.platform_owned(), ", ", fn column ->
          {_value, label} = Map.fetch!(curated, column)
          t(label)
        end)

      assert html =~ t("Keeps: %{fields}", fields: fields)
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
