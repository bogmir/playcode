defmodule Playcode.Release do
  @moduledoc false

  alias Playcode.Import.{Bibliography, FilemakerSync, TeiCorpus, Witnesses}

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
  `mix playcode.import.tei` for a release: imports every TEI file under `dir`, one play
  per code. Copy the files onto the machine first (`fly ssh sftp put`), then:

      bin/playcode rpc 'Playcode.Release.import_tei("/tmp/tei", dry_run: true, force: true)'
      bin/playcode rpc 'Playcode.Release.import_tei("/tmp/tei", force: true)'

  Without `force: true` a play already imported is skipped. A forced re-import replaces a
  play's text and loses hand edits to it, which the dry run counts per play.
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
      TeiCorpus.run(files, [force: opts[:force] || false], report)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
