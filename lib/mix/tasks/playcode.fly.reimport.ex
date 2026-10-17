defmodule Mix.Tasks.Playcode.Fly.Reimport do
  @shortdoc "Re-import the TEI corpus on production, in two steps"

  @moduledoc """
  The mechanical steps of `docs/production-reimport.md`, run from your machine with
  flyctl (`FLYCTL`, else `flyctl` on the PATH, else `~/.fly/bin/flyctl`). Deploy the code
  first, and push nothing to `main` until it is done: a deploy restarts the app.

      mix playcode.fly.reimport prepare [--dir doc/tei_corpus]
      mix playcode.fly.reimport run
      mix playcode.fly.reimport generate
      mix playcode.fly.reimport deploy
      mix playcode.fly.reimport scale-down

  `prepare` snapshots the database volume, wakes the app, uploads the corpus, scales both
  machines up with autostop off, runs the dry run, and stops: it lists the plays whose
  hand fixes the re-import would lose, for a person to look at with the project. Running
  it again is safe; a new upload starts the re-import over.

  `run` re-imports every play not imported since its file was uploaded
  (`Release.import_tei/2` with `force: true, resume: true`), running again up to three
  times when a run stops part way, and leaves the machines up. When a play fails it
  stops; `run` again retries only what is left.

  `generate` is Generate on `/admin/export` (`Release.generate_site/0`) on performance-1x:
  it scales both machines up, as `prepare` does (a machine `run` left up stays as it is),
  asks again when the session drops before the build's end, and when the build is done
  scales both back with autostop on. After a code change every play is rebuilt, six
  minutes there and over two hours on the shared CPU. `deploy`, once the
  preview is checked, is Deploy (`Release.deploy_site/0`). `scale-down` scales back by
  itself, after an aborted run or build.

  The counts that check what the re-import was for, and the preview, stay with you
  (steps 8 and 10 of the runbook).
  """

  use Mix.Task

  @app "playcode"
  @app_machine "7847063c04e7e8"
  @db "emothe-db-1g"
  @db_machine "d8d14e7b0465d8"
  @volume "vol_40l3p92ozj187o94"
  @remote_dir "/data/tei"
  @attempts 3

  @dry_run ~s[bin/playcode rpc 'Playcode.Release.import_tei("#{@remote_dir}", dry_run: true, force: true)']
  @import ~s[bin/playcode rpc 'Playcode.Release.import_tei("#{@remote_dir}", force: true, resume: true)']
  @generate ~s[bin/playcode rpc 'Playcode.Release.generate_site()']
  @deploy ~s[bin/playcode rpc 'Playcode.Release.deploy_site()']

  # A dry run's lines a person decides on: hand fixes the re-import loses, an archived
  # play it restores, a file it cannot read.
  @needs_a_look ~r/edited since their import|undoes|restores it|^  \S+: /

  @impl Mix.Task
  def run(["prepare" | args]) do
    {opts, _, _} = OptionParser.parse(args, strict: [dir: :string])
    dir = Keyword.get(opts, :dir, "doc/tei_corpus")
    files = dir |> Path.join("*.xml") |> Path.wildcard() |> Enum.map(&Path.basename/1)
    if files == [], do: Mix.raise("no .xml files in #{dir}")

    step("Snapshot of the database volume")
    snapshot!()

    step("Uploading #{length(files)} file(s) from #{dir}")
    wake!()
    upload!(dir, files)

    step("Scaling up, autostop off")
    scale_up!()

    step("Dry run")
    lines = ssh(@dry_run) |> String.split("\n")

    case Enum.filter(lines, &(&1 =~ @needs_a_look)) do
      [] ->
        Mix.shell().info("\nNothing needs a look.")

      flagged ->
        Mix.shell().info("\nLook at these with the project before running:")
        for line <- flagged, do: Mix.shell().info(line)
    end

    Mix.shell().info("\nThen: mix playcode.fly.reimport run")
  end

  def run(["run"]) do
    step("Re-importing")
    import_until_done(1)

    Mix.shell().info(
      "\nDone; the machines stay up. Check the counts, then: mix playcode.fly.reimport generate"
    )
  end

  def run(["generate"]) do
    step("Scaling up, autostop off")
    scale_up!()

    step("Generating the site")
    wake!()
    generate_until_done(1)

    step("Scaling back, autostop on")
    scale_down!()

    Mix.shell().info(
      "\nDone. Check the preview on /admin/export, then: mix playcode.fly.reimport deploy"
    )
  end

  def run(["deploy"]) do
    step("Deploying the site, autostop off")
    wake!()
    fly!(~w(machine update #{@app_machine} --autostop=off -a #{@app} --yes))
    output = ssh(@deploy)
    fly!(~w(machine update #{@app_machine} --autostop=stop -a #{@app} --yes))

    unless output =~ "site deployed",
      do: Mix.raise("the deploy failed or did not finish; see above")
  end

  def run(["scale-down"]) do
    step("Scaling back, autostop on")
    scale_down!()
  end

  def run(_args) do
    Mix.raise(
      "usage: mix playcode.fly.reimport prepare [--dir DIR] | run | generate | deploy | scale-down"
    )
  end

  defp snapshot! do
    requested = DateTime.add(DateTime.utc_now(), -60)
    fly!(~w(volumes snapshots create #{@volume} -a #{@db}))
    wait_for_snapshot(requested, 60)
  end

  defp wait_for_snapshot(_requested, 0),
    do: Mix.raise("the snapshot is not ready after 10 minutes; nothing else was done")

  defp wait_for_snapshot(requested, tries) do
    {json, 0} = System.cmd(flyctl(), ~w(volumes snapshots list #{@volume} -a #{@db} --json))

    ready? =
      json
      |> Jason.decode!()
      |> Enum.any?(&(&1["status"] == "created" and created_after?(&1["created_at"], requested)))

    unless ready? do
      Process.sleep(10_000)
      wait_for_snapshot(requested, tries - 1)
    end
  end

  # `tar -m` dates each file by its extraction, which `resume: true` compares the
  # plays' last imports with.
  defp upload!(dir, files) do
    tgz = Path.join(System.tmp_dir!(), "playcode-tei.tgz")
    {_, 0} = System.cmd("tar", ["czf", tgz, "-C", dir | files])

    ssh("rm -f /data/tei.tgz")
    fly!(["ssh", "sftp", "put", tgz, "/data/tei.tgz", "-a", @app])

    on_machine =
      ssh(
        "sh -c 'rm -rf #{@remote_dir} && mkdir #{@remote_dir} && " <>
          "tar xzmf /data/tei.tgz -C #{@remote_dir} && ls #{@remote_dir} | wc -l'"
      )

    count = to_string(length(files))

    case Regex.scan(~r/^\s*(\d+)\s*$/m, on_machine) |> List.last() do
      [_, ^count] -> Mix.shell().info("#{count} file(s) uploaded")
      _other -> Mix.raise("uploaded #{count} file(s), the machine lists:\n#{on_machine}")
    end
  end

  # A database restart ends whatever is running, so the database goes first. A machine
  # already on performance-1x, as `run` leaves both, is not resized: that restarts it.
  defp scale_up! do
    unless performance?(@db, @db_machine),
      do: fly!(~w(machine update #{@db_machine} --vm-size performance-1x -a #{@db} --yes))

    unless performance?(@app, @app_machine), do: fly!(~w(scale vm performance-1x -a #{@app}))
    fly!(~w(machine update #{@app_machine} --autostop=off -a #{@app} --yes))
  end

  defp performance?(app, machine) do
    {json, 0} = System.cmd(flyctl(), ~w(machine list -a #{app} --json))

    json
    |> Jason.decode!()
    |> Enum.any?(&(&1["id"] == machine and &1["config"]["guest"]["cpu_kind"] == "performance"))
  end

  defp scale_down! do
    fly!(~w(machine update #{@app_machine} --autostop=stop -a #{@app} --yes))
    fly!(~w(scale vm shared-cpu-1x --vm-memory 1024 -a #{@app}))

    fly!(
      ~w(machine update #{@db_machine} --vm-size shared-cpu-1x --vm-memory 512 -a #{@db} --yes)
    )
  end

  defp import_until_done(attempt) when attempt > @attempts,
    do: Mix.raise("the run stopped #{@attempts} times; see the machine's status above")

  defp import_until_done(attempt) do
    case Regex.run(~r/imported \d+, skipped \d+, failed (\d+)/, ssh(@import)) do
      [_, "0"] ->
        :ok

      [_, failed] ->
        Mix.raise(
          "#{failed} play(s) failed, listed above; the machines stay scaled up. " <>
            "Fix them and `run` again: it re-imports only what is left."
        )

      nil ->
        Mix.shell().info("\nThe run stopped before its end (#{attempt} of #{@attempts}); again.")
        stream(~w(machine status #{@app_machine} -a #{@app}))
        wake!()
        import_until_done(attempt + 1)
    end
  end

  # A dropped session leaves the build running in the app: asking again queues a Generate
  # behind it, which waits for it and then finds little or nothing left to do.
  defp generate_until_done(attempt) when attempt > @attempts,
    do: Mix.raise("the build was cut off #{@attempts} times; see the machine's status above")

  defp generate_until_done(attempt) do
    output = ssh(@generate)

    cond do
      output =~ "site generated" ->
        :ok

      output =~ "generate failed" ->
        Mix.raise(
          "the build failed, above; the machines stay up. `generate` again, or `scale-down`"
        )

      true ->
        Mix.shell().info(
          "\nThe session ended before the build (#{attempt} of #{@attempts}); again."
        )

        stream(~w(machine status #{@app_machine} -a #{@app}))
        wake!()
        generate_until_done(attempt + 1)
    end
  end

  # An app the proxy stopped for want of traffic has no VM to SSH into; starting one that
  # runs only says so.
  defp wake!, do: stream(~w(machine start #{@app_machine} -a #{@app}))

  defp created_after?(timestamp, time) do
    case DateTime.from_iso8601(timestamp || "") do
      {:ok, created, _offset} -> DateTime.after?(created, time)
      _not_yet -> false
    end
  end

  defp step(title), do: Mix.shell().info("\n==> #{title}")

  # Its output: a dropped connection shows as a run with no summary line.
  defp ssh(command) do
    {output, _status} = stream(["ssh", "console", "-a", @app, "-C", command])
    output
  end

  defp fly!(args) do
    case stream(args) do
      {output, 0} -> output
      {_output, status} -> Mix.raise("flyctl #{Enum.join(args, " ")} exited #{status}")
    end
  end

  # Prints flyctl's output line by line as it comes; returns it with the exit status.
  defp stream(args) do
    port =
      Port.open({:spawn_executable, flyctl()}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        line: 4096,
        args: args
      ])

    collect(port, [], "")
  end

  defp collect(port, lines, partial) do
    receive do
      {^port, {:data, {:noeol, part}}} ->
        collect(port, lines, partial <> part)

      {^port, {:data, {:eol, part}}} ->
        Mix.shell().info(partial <> part)
        collect(port, [partial <> part | lines], "")

      {^port, {:exit_status, status}} ->
        {[partial | lines] |> Enum.reverse() |> Enum.join("\n"), status}
    end
  end

  defp flyctl do
    System.get_env("FLYCTL") || System.find_executable("flyctl") ||
      Path.expand("~/.fly/bin/flyctl")
  end
end
