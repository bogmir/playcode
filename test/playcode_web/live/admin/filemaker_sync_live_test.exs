defmodule PlaycodeWeb.Admin.FilemakerSyncLiveTest do
  use PlaycodeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playcode.TestFixtures

  alias Playcode.ActivityLog
  alias Playcode.Catalogue

  describe "access" do
    test "given an admin then the upload form is rendered", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      assert has_element?(lv, "#upload-form")
    end

    test "given a researcher then the page is refused", %{conn: conn} do
      conn = log_in_user(conn, user_fixture(role: :researcher))

      assert {:error, {:redirect, %{to: "/", flash: flash}}} = live(conn, ~p"/admin/filemaker")
      assert flash["error"] == t("You do not have access to that page.")
    end
  end

  @export "test/fixtures/filemaker/export_sample.ndjson"

  defp corpus do
    p38 =
      play_fixture(%{
        "code" => "EMOTHE0038",
        "title" => "Antony and Cleopatra",
        "historical_time" => "edad_media"
      })

    p52 =
      play_fixture(%{
        "code" => "EMOTHE0052",
        "title" => "Antonio y Cleopatra",
        "relationship_type" => "traduccion",
        "parent_play_id" => p38.id
      })

    p211 = play_fixture(%{"code" => "EMOTHE0211", "title" => "El caballero de Olmedo"})

    p393 =
      play_fixture(%{
        "code" => "HIE0393",
        "title" => "The Spanish Bawd",
        "historical_time" => "edad_media"
      })

    al = play_fixture(%{"code" => "AL0001", "title" => "Artelope play"})

    %{p38: p38, p52: p52, p211: p211, p393: p393, al: al}
  end

  defp upload_and_preview(lv, path) do
    lv
    |> file_input("#upload-form", :export, [
      %{name: Path.basename(path), content: File.read!(path), type: "application/x-ndjson"}
    ])
    |> render_upload(Path.basename(path))

    lv |> element("#upload-form") |> render_submit()
  end

  describe "preview" do
    setup do
      corpus()
      :ok
    end

    test "given the export then every bucket is reported", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      changes = lv |> element("#changes") |> render()
      assert changes =~ "EMOTHE0038"
      assert changes =~ "EMOTHE0211"
      assert changes =~ "HIE0393"
      refute changes =~ "AL0001"

      assert changes =~ t("Language")

      assert lv |> element("#unchanged") |> render() =~ "EMOTHE0052"

      missing = lv |> element("#missing") |> render()
      assert missing =~ "AL0001"
      assert missing =~ "EMOTHE0211"

      conflicts = lv |> element("#conflicts") |> render()
      assert conflicts =~ "EMOTHE0038"
      assert conflicts =~ "HIE0393"
    end

    # A play absent from the published index can still carry a T01 research
    # record. EMOTHE0341 is that case in the real export. Presenting the buckets
    # as tabs would imply they are exclusive; they are not.
    test "given a play with research metadata but no index entry then it is in both buckets",
         %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      assert lv |> element("#changes") |> render() =~ "EMOTHE0211"
      assert lv |> element("#missing") |> render() =~ "EMOTHE0211"
    end

    test "given a new value then the current one is shown beside it", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      changes = lv |> element("#changes") |> render()

      assert changes =~ t("Historical time")
      assert changes =~ PlaycodeWeb.PlayLabels.historical_time_label("siglo_xvii")
      # EMOTHE0211's historical_time is unset in the fixture corpus: the current
      # value beside the new one must read as blank, not merely be present.
      assert changes =~ t("(blank)")
    end

    test "given a rejected file then clicking preview does not crash the page", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      lv
      |> file_input("#upload-form", :export, [
        %{name: "notes.txt", content: "hello", type: "text/plain"}
      ])
      |> render_upload("notes.txt")

      lv |> element("#upload-form") |> render_submit()

      assert has_element?(lv, "#upload-form")
      refute has_element?(lv, "#changes")
    end

    test "given a change that clears a value then it renders as (blank), not empty",
         %{conn: conn} do
      # corpus/0, run by this describe's setup, already has EMOTHE0052 with
      # relationship_type "traduccion". This fixture's index credits it "ed."
      # instead, so relationship_for/1 sets it to nil.
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, "test/fixtures/filemaker/index_relationship_clear.ndjson")

      changes = lv |> element("#changes") |> render()
      assert changes =~ t("Relationship")
      assert changes =~ t("(blank)")
    end

    test "given discard then the upload form comes back", %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      assert has_element?(lv, "#changes")

      lv |> element("button", t("Discard")) |> render_click()

      assert has_element?(lv, "#upload-form")
      refute has_element?(lv, "#changes")
    end
  end

  describe "archived plays" do
    test "given an archived play then it is absent from the preview and apply still succeeds",
         %{conn: conn} do
      %{p38: p38, p211: p211} = corpus()
      {:ok, _} = Catalogue.delete_play(p38)

      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      refute lv |> element("#changes") |> render() =~ "EMOTHE0038"
      refute lv |> element("#conflicts") |> render() =~ "EMOTHE0038"

      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      assert has_element?(lv, "#results")
      assert Catalogue.get_play!(p211.id).historical_time == "siglo_xvii"
    end
  end

  describe "upload accept list" do
    test "given a .json file then it is rejected, matching the accepted-file message",
         %{conn: conn} do
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload =
        file_input(lv, "#upload-form", :export, [
          %{name: "export.json", content: "{}", type: "application/json"}
        ])

      # The upload message promises only .ndjson; the accept list must agree,
      # rather than silently taking .json too.
      assert {:error, [[_ref, :not_accepted]]} = render_upload(upload, "export.json")
    end
  end

  describe "counts card" do
    test "given nothing unchanged or missing then the counts card does not render",
         %{conn: conn} do
      # The only play in the DB and the only code in this index — one change,
      # nothing unchanged, nothing missing.
      play_fixture(%{
        "code" => "EMOTHE0052",
        "title" => "Antonio y Cleopatra",
        "relationship_type" => "traduccion"
      })

      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, "test/fixtures/filemaker/index_relationship_clear.ndjson")

      assert has_element?(lv, "#changes")
      refute has_element?(lv, "#counts")
    end
  end

  describe "datings the parse refused" do
    test "given a header with no year then it is listed and nothing is offered to tick",
         %{conn: conn} do
      %{p38: p38} = corpus()
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      upload_and_preview(lv, "test/fixtures/filemaker/index_dating_refused.ndjson")

      skipped = lv |> element("#skipped") |> render()
      assert skipped =~ t("%{count} dating(s) not imported", count: 1)
      assert skipped =~ "EMOTHE0038"

      # A refused dating is read-only: it must not arrive as a tickable conflict, and
      # nothing may be written for it.
      refute has_element?(lv, ~s(#conflicts input[phx-value-field="composition_date_from"]))

      lv |> element("#sync-actions button", t("Apply")) |> render_click()
      assert is_nil(Catalogue.get_play!(p38.id).composition_date_from)
    end
  end

  describe "a file that is not the export" do
    test "given a file with no FileMaker records then nothing is planned or written",
         %{conn: conn} do
      corpus()
      {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

      html = upload_and_preview(lv, "test/fixtures/filemaker/not_an_export.ndjson")

      assert html =~ t("No FileMaker records found in that file. Is it the right export?")
      refute has_element?(lv, "#changes")
      assert has_element?(lv, "#upload-form")
    end

    # A record the loader cannot read refuses the whole export, and the page names it. It
    # used to raise inside a blanket rescue, which showed the admin the inspected
    # exception and hid any real bug behind "Cannot read the file".
    test "given a malformed record then the page names it and stays on the upload form",
         %{conn: conn} do
      corpus()

      for {fixture, record} <- [{"malformed_version", "1"}, {"malformed_fields", "7"}] do
        {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")

        html = upload_and_preview(lv, "test/fixtures/filemaker/#{fixture}.ndjson")

        assert html =~ t("Cannot read the file: record %{record} is malformed.", record: record),
               fixture

        refute has_element?(lv, "#changes")
        assert has_element?(lv, "#upload-form")
      end
    end
  end

  describe "apply" do
    setup do
      Map.put(corpus(), :admin, admin_fixture())
    end

    test "given no conflict ticked then fills are written and curated values are left alone",
         %{conn: conn, admin: admin, p38: p38, p211: p211, p393: p393} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      # Blank columns filled.
      assert Catalogue.get_play!(p211.id).historical_time == "siglo_xvii"
      assert Catalogue.get_play!(p38.id).language == "en"

      assert Catalogue.get_play!(p38.id).historical_time_note ==
               "First century BC. The play dramatizes events taking place between 40 and 30 BC."

      # Curated values a researcher set are untouched.
      assert Catalogue.get_play!(p38.id).historical_time == "edad_media"
      assert Catalogue.get_play!(p393.id).historical_time == "edad_media"
    end

    test "given one conflict ticked then only that one is overwritten",
         %{conn: conn, admin: admin, p38: p38, p393: p393} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)

      lv
      |> element(~s(#conflicts input[phx-value-play-id="#{p393.id}"]))
      |> render_click()

      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      assert Catalogue.get_play!(p393.id).historical_time == "siglo_xvi"
      assert Catalogue.get_play!(p38.id).historical_time == "edad_media"
    end

    # apply_plan/2 already logs; only a LiveView has a user_id to give it. This
    # is the whole provenance argument for the page.
    test "given an apply then every write is attributed to the signed-in admin",
         %{conn: conn, admin: admin, p211: p211} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      entries = ActivityLog.list_entries(play_id: p211.id)

      assert Enum.any?(entries, fn entry ->
               entry.user_id == admin.id and entry.metadata["source"] == "filemaker_index"
             end)
    end

    test "given an apply then the results replace the preview", %{conn: conn, admin: admin} do
      {:ok, lv, _html} = live(log_in_user(conn, admin), ~p"/admin/filemaker")

      upload_and_preview(lv, @export)
      lv |> element("#sync-actions button", t("Apply")) |> render_click()

      assert has_element?(lv, "#results")
      refute has_element?(lv, "#changes")
    end
  end

  # Every field a shipped slice writes is named in the page's language, not by its
  # column name.
  test "a composition date conflict names its fields in Spanish", %{conn: conn} do
    play_fixture(%{
      "code" => "EMOTHE0038",
      "language" => "en",
      "composition_date_from" => 1600,
      "composition_date_to" => 1601,
      "composition_date_note" => "otra"
    })

    {:ok, lv, _html} = live(log_in_user(conn, admin_fixture()), ~p"/admin/filemaker")
    upload_and_preview(lv, "test/fixtures/filemaker/index_sample.ndjson")

    conflicts = lv |> element("#conflicts") |> render()

    for label <- ["Composition Date (from)", "Composition Date (to)", "Composition Date Note"] do
      assert conflicts =~ t(label)
    end

    # What the catch-all would print for a field with no label of its own.
    refute conflicts =~ "composition date"
  end
end
