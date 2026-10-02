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
    end
  end
end
