defmodule Mix.Tasks.Playcode.Fly.ReimportTest do
  @moduledoc """
  `mix playcode.fly.reimport` against a fake flyctl (`FLYCTL`) that records its calls and
  answers the ones the task reads: what production receives, in order, and where the
  task stops for a person. The fake keeps the uploaded tarball, so the file count the
  "machine" reports is the upload's.
  """
  # Mix.shell/1 and FLYCTL are global to the VM.
  use ExUnit.Case, async: false

  @fake ~S"""
  #!/bin/sh
  d=$(dirname "$0")
  echo "$*" >> "$d/calls"
  case "$*" in
    *"sftp put"*) cp "$4" "$d/uploaded.tgz" ;;
    *"wc -l"*) tar tzf "$d/uploaded.tgz" | grep -c xml ;;
    *"snapshots list"*) cat "$d/snapshots" ;;
    *dry_run*) cat "$d/dry_run.$(grep -c dry_run "$d/calls")" 2>/dev/null || cat "$d/dry_run" ;;
    *"resume: true"*) cat "$d/run.$(grep -c 'resume: true' "$d/calls")" 2>/dev/null ;;
    *generate_site*) cat "$d/generate.$(grep -c generate_site "$d/calls")" 2>/dev/null ;;
    *deploy_site*) cat "$d/deploy.$(grep -c deploy_site "$d/calls")" 2>/dev/null ;;
    *"machine list"*) cat "$d/sizes" 2>/dev/null || echo '[]' ;;
  esac
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "fly-#{System.unique_integer([:positive])}")
    corpus = Path.join(dir, "corpus")
    File.mkdir_p!(corpus)
    File.write!(Path.join(corpus, "EMOTHE0001_Uno.xml"), "<TEI/>")
    File.write!(Path.join(corpus, "EMOTHE0002_Dos.xml"), "<TEI/>")

    flyctl = Path.join(dir, "flyctl")
    File.write!(flyctl, @fake)
    File.chmod!(flyctl, 0o755)

    File.write!(
      Path.join(dir, "snapshots"),
      Jason.encode!([%{id: "vs_new", created_at: DateTime.utc_now(), status: "created"}])
    )

    Mix.shell(Mix.Shell.Process)
    System.put_env("FLYCTL", flyctl)

    on_exit(fn ->
      Mix.shell(Mix.Shell.IO)
      System.delete_env("FLYCTL")
      File.rm_rf(dir)
    end)

    %{dir: dir, corpus: corpus}
  end

  defp answer(dir, name, text), do: File.write!(Path.join(dir, name), text)

  defp calls(dir), do: dir |> Path.join("calls") |> File.read!() |> String.split("\n", trim: true)

  defp output(acc \\ []) do
    receive do
      {:mix_shell, _level, [line]} -> output([line | acc])
    after
      0 -> acc |> Enum.reverse() |> Enum.join("\n")
    end
  end

  # Each expected call appears, in this order, among the calls made.
  defp assert_in_order(calls, expected) do
    Enum.reduce(expected, calls, fn wanted, rest ->
      case Enum.drop_while(rest, &(not String.contains?(&1, wanted))) do
        [_found | after_it] ->
          after_it

        [] ->
          flunk(
            "no call #{inspect(wanted)} after the ones before it in:\n" <> Enum.join(calls, "\n")
          )
      end
    end)
  end

  describe "prepare" do
    test "snapshots, uploads, scales up, runs the dry run, and stops at what needs a look",
         %{dir: dir, corpus: corpus} do
      answer(dir, "dry_run", """
      2 file(s) in /data/tei
        EMOTHE0001  replaces 3 division(s), 40 element(s), 5 character(s), 2 TEI record(s)
        EMOTHE0002  replaces 2 division(s), 9 element(s), 4 character(s), 1 TEI record(s), undoes 2 hand edit(s) to its text

      dry run, nothing written — 0 new, 2 already imported (1 with hand edits since their last import), 0 unreadable
      """)

      Mix.Task.rerun("playcode.fly.reimport", ["prepare", "--dir", corpus])

      calls = calls(dir)

      assert_in_order(calls, [
        "volumes snapshots create vol_40l3p92ozj187o94 -a emothe-db-1g",
        "volumes snapshots list vol_40l3p92ozj187o94 -a emothe-db-1g --json",
        # An app stopped for want of traffic has no VM to upload to (2026-10-17).
        "machine start 7847063c04e7e8 -a playcode",
        "ssh sftp put",
        "tar xzmf /data/tei.tgz -C /data/tei",
        "machine update d8d14e7b0465d8 --vm-size performance-1x -a emothe-db-1g --yes",
        "scale vm performance-1x -a playcode",
        "machine update 7847063c04e7e8 --autostop=off -a playcode --yes",
        ~s[import_tei("/data/tei", dry_run: true, force: true)]
      ])

      refute Enum.any?(calls, &(&1 =~ "resume: true"))

      out = output()
      assert out =~ "2 file(s) uploaded"
      assert out =~ ~r/look.*\n.*EMOTHE0002 .*undoes 2 hand edit/i
      refute out =~ ~r/look.*\n.*EMOTHE0001/i
      assert out =~ "mix playcode.fly.reimport run"
    end

    # On 2026-10-18 the dry run's RPC reached an app still restarting from the resize,
    # and prepare said "Nothing needs a look" over output that held no dry run at all.
    test "a dry run that did not answer is asked again before anything is called clean",
         %{dir: dir, corpus: corpus} do
      answer(dir, "dry_run.1", """
      --rpc-eval : RPC failed with reason :noconnection
      Error: ssh shell: Process exited with status 1
      """)

      answer(dir, "dry_run.2", """
      2 file(s) in /data/tei
        EMOTHE0001  replaces 3 division(s), 40 element(s), 5 character(s), 2 TEI record(s)

      dry run, nothing written — 0 new, 2 already imported, 0 unreadable
      """)

      Mix.Task.rerun("playcode.fly.reimport", ["prepare", "--dir", corpus])

      assert_in_order(calls(dir), [
        ~s[import_tei("/data/tei", dry_run: true, force: true)],
        "machine start 7847063c04e7e8 -a playcode",
        ~s[import_tei("/data/tei", dry_run: true, force: true)]
      ])

      assert output() =~ "Nothing needs a look."
    end

    test "a dry run that never answers stops prepare, which calls nothing clean",
         %{dir: dir, corpus: corpus} do
      for n <- 1..3 do
        answer(dir, "dry_run.#{n}", "--rpc-eval : RPC failed with reason :noconnection\n")
      end

      assert_raise Mix.Error, ~r/dry run/, fn ->
        Mix.Task.rerun("playcode.fly.reimport", ["prepare", "--dir", corpus])
      end

      refute output() =~ "Nothing needs a look"
    end
  end

  describe "run" do
    # It used to scale back at the end; the machines now stay up for `generate`, which
    # builds the site faster on them and scales back after it (2026-10-17).
    test "runs again after a run that stopped part way, and leaves the machines up",
         %{dir: dir} do
      answer(dir, "run.1", "372 file(s) in /data/tei\nError: ssh shell: connection closed\n")
      answer(dir, "run.2", "372 file(s) in /data/tei\nimported 300, skipped 72, failed 0\n")

      Mix.Task.rerun("playcode.fly.reimport", ["run"])

      calls = calls(dir)

      assert_in_order(calls, [
        ~s[import_tei("/data/tei", force: true, resume: true)],
        "machine start 7847063c04e7e8 -a playcode",
        ~s[import_tei("/data/tei", force: true, resume: true)]
      ])

      refute Enum.any?(calls, &(&1 =~ "shared-cpu-1x"))
      assert output() =~ "mix playcode.fly.reimport generate"
    end

    test "stops at failed plays and keeps the machines scaled up", %{dir: dir} do
      answer(dir, "run.1", """
      372 file(s) in /data/tei
        EMOTHE0002: %DBConnection.ConnectionError{message: "timeout"}
      imported 371, skipped 0, failed 1
      """)

      assert_raise Mix.Error, ~r/1 play\(s\) failed/, fn ->
        Mix.Task.rerun("playcode.fly.reimport", ["run"])
      end

      refute Enum.any?(calls(dir), &(&1 =~ "shared-cpu-1x"))
      assert output() =~ "EMOTHE0002: %DBConnection.ConnectionError"
    end
  end

  describe "generate" do
    # It used to build on whatever machines it found, counting on `run` to have left them
    # scaled up; on its own, after a code change, it built on the shared CPU, where a full
    # rebuild takes over two hours instead of six minutes (2026-10-17).
    test "scales both machines up, builds the site, then scales back", %{dir: dir} do
      answer(dir, "generate.1", "371/371 EMOTHE0999\nsite generated: %{plays: 371}\n")

      Mix.Task.rerun("playcode.fly.reimport", ["generate"])

      assert_in_order(calls(dir), [
        "machine update d8d14e7b0465d8 --vm-size performance-1x -a emothe-db-1g --yes",
        "scale vm performance-1x -a playcode",
        "machine update 7847063c04e7e8 --autostop=off -a playcode --yes",
        "machine start 7847063c04e7e8 -a playcode",
        "Playcode.Release.generate_site()",
        "machine update 7847063c04e7e8 --autostop=stop -a playcode --yes",
        "scale vm shared-cpu-1x --vm-memory 1024 -a playcode",
        "machine update d8d14e7b0465d8 --vm-size shared-cpu-1x --vm-memory 512 -a emothe-db-1g --yes"
      ])

      assert output() =~ "mix playcode.fly.reimport deploy"
    end

    # A resize restarts the machine, the database's ending whatever it was serving.
    test "after a run, leaves the machines on performance-1x as they are", %{dir: dir} do
      answer(
        dir,
        "sizes",
        Jason.encode!([
          %{id: "d8d14e7b0465d8", config: %{guest: %{cpu_kind: "performance", cpus: 1}}},
          %{id: "7847063c04e7e8", config: %{guest: %{cpu_kind: "performance", cpus: 1}}}
        ])
      )

      answer(dir, "generate.1", "site generated: %{changed: 0}\n")

      Mix.Task.rerun("playcode.fly.reimport", ["generate"])

      calls = calls(dir)
      assert Enum.any?(calls, &(&1 =~ "generate_site"))
      refute Enum.any?(calls, &(&1 =~ "performance-1x"))
    end

    # The build goes on in the app when the SSH session drops; asking again waits for it.
    test "asks again after a session that dropped before the build's end", %{dir: dir} do
      answer(dir, "generate.1", "100/371 EMOTHE0100\nError: ssh shell: connection closed\n")
      answer(dir, "generate.2", "site generated: %{changed: 0}\n")

      Mix.Task.rerun("playcode.fly.reimport", ["generate"])

      calls = calls(dir)
      assert Enum.count(calls, &(&1 =~ "generate_site")) == 2
      assert Enum.any?(calls, &(&1 =~ "shared-cpu-1x"))
    end

    test "stops at a failed build and keeps the machines up", %{dir: dir} do
      answer(dir, "generate.1", "generate failed: :enospc\n")

      assert_raise Mix.Error, ~r/build failed/, fn ->
        Mix.Task.rerun("playcode.fly.reimport", ["generate"])
      end

      refute Enum.any?(calls(dir), &(&1 =~ "shared-cpu-1x"))
    end
  end

  describe "deploy" do
    test "wakes the app, pushes the built site, and puts autostop back", %{dir: dir} do
      answer(dir, "deploy.1", "deploy: pushing\nsite deployed: %{sha: \"abc\"}\n")

      Mix.Task.rerun("playcode.fly.reimport", ["deploy"])

      assert_in_order(calls(dir), [
        "machine start 7847063c04e7e8 -a playcode",
        "machine update 7847063c04e7e8 --autostop=off -a playcode --yes",
        "Playcode.Release.deploy_site()",
        "machine update 7847063c04e7e8 --autostop=stop -a playcode --yes"
      ])

      assert output() =~ "site deployed"
    end

    # Turning autostop off restarts the app, and the first call came before it answered
    # (2026-10-18): asking again is what generate does when its session ends early.
    test "asks again when the app is not up yet", %{dir: dir} do
      answer(dir, "deploy.1", "--rpc-eval : RPC failed with reason :noconnection\n")
      answer(dir, "deploy.2", "site deployed: %{sha: \"abc\"}\n")

      Mix.Task.rerun("playcode.fly.reimport", ["deploy"])

      calls = calls(dir)
      assert Enum.count(calls, &(&1 =~ "deploy_site")) == 2
      assert List.last(calls) =~ "--autostop=stop"
    end

    test "says so when the push fails, autostop back on all the same", %{dir: dir} do
      answer(dir, "deploy.1", "deploy failed: \"rejected\"\n")

      assert_raise Mix.Error, ~r/deploy failed/, fn ->
        Mix.Task.rerun("playcode.fly.reimport", ["deploy"])
      end

      assert Enum.any?(calls(dir), &(&1 =~ "--autostop=stop"))
    end
  end
end
