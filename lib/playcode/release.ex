defmodule Playcode.Release do
  @moduledoc false

  alias Playcode.Export.{SiteBuilder, StaticSite}
  alias Playcode.Import.{Bibliography, FilemakerSync, Performances, Places, TeiCorpus, Witnesses}

  @app :playcode

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Prints an accept-invite URL for `email`, creating the invitation if needed.

  Break-glass for a deployment whose SMTP is not working yet.
  """
  def invite_url(email, role \\ :admin) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    case Playcode.Accounts.invite_user(email, role, nil) do
      {:ok, _user, token} ->
        IO.puts(Playcode.Accounts.AdminBootstrap.invite_url(token))

      {:error, reason} ->
        IO.puts("could not invite #{email}: #{inspect(reason)}")
    end
  end

  @doc """
  S4's one-time bibliography import, for a release, which has no mix tasks. Copy the six
  tables onto the machine first (`fly ssh sftp shell`), then:

      bin/playcode rpc 'Playcode.Release.import_bibliography("/tmp/ctce", dry_run: true)'
      bin/playcode rpc 'Playcode.Release.import_bibliography("/tmp/ctce")'
  """
  def import_bibliography(dir, opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    case Bibliography.load(dir) do
      {:ok, data} ->
        plan = Bibliography.plan(data, FilemakerSync.all_plays())
        Enum.each(Bibliography.report(plan), &IO.puts/1)

        if opts[:dry_run] do
          IO.puts("dry run, nothing written")
        else
          {:ok, written} = Bibliography.apply_plan(plan)
          IO.puts("created #{written.entries} entries and #{written.links} links")
        end

      {:error, {file, reason}} ->
        IO.puts("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end

  @doc """
  S3's one-time witness import, for a release, which has no mix tasks. Copy
  `T03_ObraTestimonio.xml` and `T03.2_Atribucion.xml` onto the machine first
  (`fly ssh sftp shell`), then:

      bin/playcode rpc 'Playcode.Release.import_witnesses("/tmp/ctce", dry_run: true)'
      bin/playcode rpc 'Playcode.Release.import_witnesses("/tmp/ctce")'
  """
  def import_witnesses(dir, opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    case Witnesses.load(dir) do
      {:ok, data} ->
        plan = Witnesses.plan(data, FilemakerSync.all_plays())
        Enum.each(Witnesses.report(plan), &IO.puts/1)

        if opts[:dry_run] do
          IO.puts("dry run, nothing written")
        else
          {:ok, written} = Witnesses.apply_plan(plan)
          IO.puts("created #{written.witnesses} witnesses")
        end

      {:error, {file, reason}} ->
        IO.puts("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end

  @doc """
  S9b's one-time import of FileMaker's places of action, for a release, which has no mix
  tasks. Copy the eight `T10*` tables onto the machine first (`fly ssh sftp shell`), then:

      bin/playcode rpc 'Playcode.Release.import_places("/tmp/ctce", dry_run: true)'
      bin/playcode rpc 'Playcode.Release.import_places("/tmp/ctce")'
  """
  def import_places(dir, opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    case Places.load(dir) do
      {:ok, data} ->
        plan = Places.plan(data, FilemakerSync.all_plays())
        Enum.each(Places.report(plan), &IO.puts/1)

        if opts[:dry_run] do
          IO.puts("dry run, nothing written")
        else
          {:ok, written} = Places.apply_plan(plan)
          IO.puts("created #{written.places} places and #{written.links} links")
        end

      {:error, {file, reason}} ->
        IO.puts("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end

  @doc """
  S5's one-time import of FileMaker's historical performances, for a release, which has no mix
  tasks. Copy the `T10*`, `T11*` and `T13*` tables, and `T11.12_ActorSexo.tab`, onto the
  machine first (`fly ssh sftp shell`), then:

      bin/playcode rpc 'Playcode.Release.import_performances("/tmp/ctce", dry_run: true)'
      bin/playcode rpc 'Playcode.Release.import_performances("/tmp/ctce")'
  """
  def import_performances(dir, opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    case Performances.load(dir) do
      {:ok, data} ->
        plan = Performances.plan(data, FilemakerSync.all_plays())
        Enum.each(Performances.report(plan), &IO.puts/1)

        if opts[:dry_run] do
          IO.puts("dry run, nothing written")
        else
          write_performances(plan)
        end

      {:error, {file, reason}} ->
        IO.puts("cannot read #{Path.join(dir, file)}: #{inspect(reason)}")
    end
  end

  defp write_performances(plan) do
    case Performances.apply_plan(plan) do
      {:ok, written} ->
        IO.puts(
          "created #{written.performances} performances, #{written.companies} companies, " <>
            "#{written.actors} actors, #{written.entries} entries and #{written.places} places"
        )

      {:error, refused} ->
        IO.puts("nothing written, #{Performances.error_message(refused)}")
    end
  end

  @doc """
  `mix playcode.import.tei` for a release: imports every TEI file under `dir`, one play
  per code. Copy the files onto the machine first (`fly ssh sftp put`), then:

      bin/playcode rpc 'Playcode.Release.import_tei("/tmp/tei", dry_run: true, force: true)'
      bin/playcode rpc 'Playcode.Release.import_tei("/tmp/tei", force: true)'

  Without `force: true` a play already imported is skipped. A forced re-import replaces a
  play's text and loses hand edits to it, which the dry run counts per play. With
  `resume: true` as well, a play imported since its file was written is skipped, so a run
  that stopped part way carries on when run again.
  """
  def import_tei(dir, opts \\ []) do
    load_app()
    {:ok, _} = Application.ensure_all_started(:playcode)

    files = TeiCorpus.collect_files([dir])
    IO.puts("#{length(files)} file(s) in #{dir}")
    report = fn {_level, line} -> IO.puts(line) end

    if opts[:dry_run] do
      TeiCorpus.dry_run(files, [force: opts[:force] || false], report)
    else
      TeiCorpus.run(files, Keyword.take(opts, [:force, :resume]), report)
    end
  end

  @doc """
  Generate on `/admin/export`, from the console: brings the static site up to date with
  the app's one builder (`SiteBuilder.generate/1`, the version the site was built with)
  and waits for it, printing its progress, so an SSH session can stand in for the open
  page. Returns `:ok` or `{:error, reason}`.

      bin/playcode rpc 'Playcode.Release.generate_site()'
  """
  def generate_site do
    dir = StaticSite.output_dir()
    version = StaticSite.built_version(dir) || to_string(Application.spec(@app, :vsn))
    await_site_job(:generate, fn -> SiteBuilder.generate(version: version) end)
  end

  @doc """
  Deploy on `/admin/export`, from the console: pushes the built site to `STATIC_SITE_REPO`
  and waits for the push. Returns `:ok` or `{:error, reason}`.

      bin/playcode rpc 'Playcode.Release.deploy_site()'
  """
  def deploy_site do
    case Application.get_env(@app, :static_site_deploy, [])[:repo] do
      repo when repo in [nil, ""] ->
        IO.puts("deploy failed: set STATIC_SITE_REPO where Playcode runs")
        {:error, :no_repo}

      repo ->
        await_site_job(:deploy, fn -> SiteBuilder.deploy(repo) end)
    end
  end

  # Subscribed before asking, so the job's start is heard even when it runs at once; a
  # job of the same kind already running ends before ours starts.
  defp await_site_job(job, request) do
    SiteBuilder.subscribe()
    if request.() == :queued, do: IO.puts("#{job}: queued behind the builder's current job")
    await_start(job)
  end

  defp await_start(job) do
    receive do
      {:site_builder, :started, ^job} -> await_end(job)
    end
  end

  defp await_end(job) do
    receive do
      {:site_builder, :progress, :generate, %{current: current, total: total} = info} ->
        if current == total or rem(current, 25) == 0,
          do: IO.puts("#{current}/#{total} #{info[:detail]}")

        await_end(job)

      {:site_builder, :progress, :deploy, status} ->
        IO.puts("deploy: #{status}")
        await_end(job)

      {:site_builder, :done, ^job, {:ok, result}} ->
        IO.puts("site #{past(job)}: #{inspect(result)}")

      {:site_builder, :done, ^job, {:error, reason}} ->
        IO.puts("#{job} failed: #{inspect(reason)}")
        {:error, reason}

      {:site_builder, :failed, ^job, reason} ->
        IO.puts("#{job} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp past(:generate), do: "generated"
  defp past(:deploy), do: "deployed"

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
