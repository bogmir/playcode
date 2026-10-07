defmodule Playcode.Release do
  @moduledoc false

  alias Playcode.Import.{Bibliography, FilemakerSync}

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

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
