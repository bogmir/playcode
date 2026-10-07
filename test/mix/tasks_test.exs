defmodule Mix.Tasks.PlaycodeTasksTest do
  @moduledoc """
  The mix tasks, run the way an operator runs them: `Mix.Task.rerun/2` with
  command-line arguments, reading what they print.
  """
  # Mix.shell/1 is global to the VM, so these cannot run beside other tests.
  use PlaycodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Playcode.TestFixtures
  import Playcode.ImportHelpers

  alias Playcode.Accounts
  alias Playcode.Bibliography
  alias Playcode.Catalogue

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  defp run(task, args) do
    Mix.Task.rerun(task, args)
    output()
  end

  defp output(acc \\ []) do
    receive do
      {:mix_shell, _level, [line]} -> output([line | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "task-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end

  defp citations(play) do
    play.id
    |> Bibliography.list_links()
    |> Enum.map(&Playcode.Bibliography.Citation.plain(&1.entry, &1))
  end

  describe "playcode.invite" do
    # The break-glass path: on a fresh deployment with no SMTP, this is the only way
    # the first admin gets in.
    test "--print-url prints a link that lets the invitee set a password", %{conn: conn} do
      out = run("playcode.invite", ["jefa@uv.es", "--admin", "--print-url"])

      assert [path] = Regex.run(~r{/users/accept-invite/\S+}, out)
      refute_email_sent()
      assert Accounts.get_user_by_email("jefa@uv.es").role == :admin

      {:ok, lv, _html} = live(conn, path)
      assert has_element?(lv, "form")
    end

    test "without --print-url the link is mailed" do
      assert run("playcode.invite", ["nuevo@uv.es"]) =~ "invitation sent to nuevo@uv.es"
      assert_email_sent(to: "nuevo@uv.es")
    end

    test "an address with an active account is refused" do
      user = user_fixture()

      assert_raise Mix.Error, ~r/already has an active account/, fn ->
        Mix.Task.rerun("playcode.invite", [user.email])
      end
    end
  end

  describe "playcode.import.tei" do
    setup do
      dir = tmp_dir()
      File.write!(Path.join(dir, "TASK0001_Primera.xml"), tei(code: "TASK0001", title: "Primera"))
      %{dir: dir}
    end

    test "--dry-run reports what it would import and writes nothing", %{dir: dir} do
      out = run("playcode.import.tei", ["--dir", dir, "--dry-run"])

      assert out =~ "TASK0001  new"
      assert out =~ "dry run, nothing written"
      assert Catalogue.list_plays() == []
    end

    test "imports once, skips on the next run, and re-imports under --force", %{dir: dir} do
      assert run("playcode.import.tei", ["--dir", dir]) =~ "imported 1, skipped 0, failed 0"
      assert [%{title: "Primera"}] = Catalogue.list_plays()

      File.write!(Path.join(dir, "TASK0001_Primera.xml"), tei(code: "TASK0001", title: "Segunda"))

      assert run("playcode.import.tei", ["--dir", dir]) =~ "imported 0, skipped 1, failed 0"
      assert [%{title: "Primera"}] = Catalogue.list_plays()

      assert run("playcode.import.tei", ["--dir", dir, "--force"]) =~ "imported 1"
      assert [%{title: "Segunda"}] = Catalogue.list_plays()
    end

    test "one unreadable file does not stop the rest", %{dir: dir} do
      File.write!(Path.join(dir, "TASK0002_Rota.xml"), "<TEI><teiHeader>")

      out = run("playcode.import.tei", ["--dir", dir])

      assert out =~ "imported 1, skipped 0, failed 1"
      assert out =~ "TASK0002"
    end
  end

  describe "playcode.import.filemaker" do
    @export "test/fixtures/filemaker/export_sample.ndjson"

    setup do
      %{play: play_fixture(%{"code" => "EMOTHE0038_AntonyAndCleopatra", "language" => "es"})}
    end

    test "--dry-run prints the changes and writes nothing", %{play: play} do
      out = run("playcode.import.filemaker", ["--path", @export, "--dry-run"])

      assert out =~ "EMOTHE0038"
      assert out =~ ~s(language -> "en")
      assert out =~ "dry run, nothing written"
      assert Catalogue.get_play!(play.id).language == "es"
    end

    test "without --dry-run the changes are applied", %{play: play} do
      assert run("playcode.import.filemaker", ["--path", @export]) =~ "updated 1, failed 0"
      assert Catalogue.get_play!(play.id).language == "en"
    end

    # Same rule as /admin/filemaker and every Catalogue read.
    test "an archived play is left out", %{play: play} do
      {:ok, _} = Catalogue.delete_play(play)

      out = run("playcode.import.filemaker", ["--path", @export])

      refute out =~ "EMOTHE0038"
      assert out =~ "updated 0, failed 0"
      assert Catalogue.get_play!(play.id, include_deleted: true).language == "es"
    end

    test "a missing export is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.filemaker", [
          "--path",
          "test/fixtures/filemaker/nope.ndjson"
        ])
      end
    end
  end

  describe "playcode.export.site" do
    test "publishes complete plays into the given directory, and drafts only with --all" do
      complete = play_fixture(%{"is_complete" => true})
      draft = play_fixture()
      dir = tmp_dir()
      page = fn play -> File.exists?(Path.join([dir, "plays", play.code, "index.html"])) end

      run("playcode.export.site", ["-o", dir])
      assert page.(complete)
      refute page.(draft)

      run("playcode.export.site", ["-o", dir, "--all"])
      assert page.(draft)

      assert run("playcode.export.site", ["-o", dir, "--all"]) =~ "largest act page"
    end
  end

  describe "playcode.import.bibliography" do
    @dump "test/fixtures/filemaker/ctce_dades"

    setup do
      %{
        hamlet: play_fixture(%{"code" => "EMOTHE0010_Hamlet"}),
        antony: play_fixture(%{"code" => "EMOTHE0038_AntonyAndCleopatra"})
      }
    end

    test "--dry-run prints the plan and writes nothing", %{hamlet: hamlet} do
      out = run("playcode.import.bibliography", ["--path", @dump, "--dry-run"])

      assert out =~ "EMOTHE0010_Hamlet  5 links"
      assert out =~ "bibliography: 5 entries (0 already in Playcode), 6 links on 2 plays"
      assert out =~ "modern editions: 3 entries (0 already in Playcode), 4 links on 2 plays"
      assert out =~ "skipped, test_record: 1  T04:9"
      assert out =~ "links to versions not held: 1"
      assert out =~ "dry run, nothing written"
      assert Bibliography.list_links(hamlet.id) == []
    end

    test "writes each entry once, as FileMaker printed it, with each play's own pages", %{
      hamlet: hamlet,
      antony: antony
    } do
      assert run("playcode.import.bibliography", ["--path", @dump]) =~
               "created 8 entries and 10 links"

      assert "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 5. London: Jacob Tonson, 1709, pp. 2366-2466, 6 vols." in citations(
               hamlet
             )

      assert "Rowe, Nicholas, ed. Hamlet. Shakespeare, William. In: The Works of Mr. William Shakespeare. Vol. 7. London: Jacob Tonson, 1709, pp. 100-200, 6 vols." in citations(
               antony
             )

      assert "Peele, George. Altweibermär. Tra. Harbecke, Ulrich J. Weinheim: Deutscher Laienspiel-Verlag, 1967. Das Bühnenspiel. (Orig: Old Wife's Tale)" in citations(
               hamlet
             )

      assert "Thompson, Ann; Taylor, Neil, ed. Hamlet. Shakespeare, William. London: Thomson Learning, 2006. The Arden Shakespeare. Third series." in citations(
               hamlet
             )

      [rowe] = for l <- Bibliography.list_links(hamlet.id), l.entry.volumes_total == "6", do: l
      assert Bibliography.link_counts([rowe.entry_id]) == %{rowe.entry_id => 2}
      assert rowe.origin == "filemaker"
    end

    test "a re-run skips a play already imported, so a removal stays removed", %{hamlet: hamlet} do
      run("playcode.import.bibliography", ["--path", @dump])
      [first | _] = Bibliography.list_links(hamlet.id)
      {:ok, _} = Bibliography.unlink(first)

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "already imported: 2 plays"
      assert out =~ "created 0 entries and 0 links"
      assert length(Bibliography.list_links(hamlet.id)) == 4
    end

    test "a play added later shares the entries already imported" do
      run("playcode.import.bibliography", ["--path", @dump])
      later = play_fixture(%{"code" => "EMOTHE0038_AntonioYCleopatra"})

      out = run("playcode.import.bibliography", ["--path", @dump])

      assert out =~ "modern editions: 2 entries (2 already in Playcode), 2 links on 1 plays"
      assert out =~ "created 0 entries and 5 links"
      assert length(Bibliography.list_links(later.id)) == 5
    end

    test "an archived play is left out", %{antony: antony} do
      {:ok, _} = Catalogue.delete_play(antony)
      run("playcode.import.bibliography", ["--path", @dump])
      assert Bibliography.list_links(antony.id) == []
    end

    test "a missing dump is refused" do
      assert_raise Mix.Error, ~r/cannot read/, fn ->
        Mix.Task.rerun("playcode.import.bibliography", ["--path", "test/fixtures/filemaker/nope"])
      end
    end
  end
end
