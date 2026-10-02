defmodule Playcode.Export.SiteBuilder do
  @moduledoc """
  The one process that writes and ships the admin's static site, `StaticSite.output_dir/0`.

  Adding or removing a play reads the search index on disk and writes it back, and a
  deploy pushes the whole directory, so two jobs at once would lose a play from search or
  publish a half-written site. The builder runs one job at a time and refuses another
  while it runs: each starter returns `:ok` or `{:error, :busy}`. Jobs are `:generate`,
  `{:add, play_id}`, `{:remove, code}` and `:deploy`.

  It broadcasts on `"static_site"`, so every admin page shows the same build whoever
  started it: `{:site_builder, :started, job}`, `{:site_builder, :progress, job, info}`,
  `{:site_builder, :done, job, result}` and `{:site_builder, :failed, job, reason}`.
  """

  # ponytail: one builder for the app's one output_dir/0. Should a second site ever
  # appear, register one builder per directory in a Registry.

  use GenServer

  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.Deployer

  @topic "static_site"
  @tasks __MODULE__.Tasks

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Playcode.PubSub, @topic)

  @doc "A full build with `StaticSite.generate/1` `opts`, but its own directory and progress."
  def generate(opts), do: start(:generate, opts)

  def add(play_id, opts), do: start({:add, play_id}, opts)
  def remove(code, opts), do: start({:remove, code}, opts)
  def deploy(repo), do: start(:deploy, repo)

  def status, do: GenServer.call(__MODULE__, :status)

  defp start(job, args), do: GenServer.call(__MODULE__, {:start, job, args})

  @impl true
  def init(nil), do: {:ok, %{job: nil, ref: nil}}

  @impl true
  def handle_call(:status, _from, state), do: {:reply, %{job: state.job}, state}

  def handle_call({:start, _job, _args}, _from, %{job: running} = state) when running != nil,
    do: {:reply, {:error, :busy}, state}

  def handle_call({:start, job, args}, _from, _state) do
    # Announced before the task starts, so no page hears its progress before it.
    broadcast({:site_builder, :started, job})
    task = Task.Supervisor.async_nolink(@tasks, fn -> run(job, args) end)
    {:reply, :ok, %{job: job, ref: task.ref}}
  end

  @impl true
  def handle_info({ref, result}, %{ref: ref, job: job}) do
    Process.demonitor(ref, [:flush])
    broadcast({:site_builder, :done, job, result})
    {:noreply, %{job: nil, ref: nil}}
  end

  # The reply is flushed with the monitor, so a :DOWN means the task gave no result.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{ref: ref, job: job}) do
    broadcast({:site_builder, :failed, job, reason})
    {:noreply, %{job: nil, ref: nil}}
  end

  defp run(:generate, opts),
    do: StaticSite.generate(opts |> in_site() |> Keyword.put(:on_progress, progress(:generate)))

  defp run({:add, play_id}, opts), do: StaticSite.generate_single_play(play_id, in_site(opts))
  defp run({:remove, code}, opts), do: StaticSite.remove_single_play(code, in_site(opts))

  # The StaticSite entry points set English themselves; Deployer translates nothing.
  defp run(:deploy, repo) do
    Deployer.deploy_to_github_pages(StaticSite.output_dir(), repo, on_progress: progress(:deploy))
  end

  defp in_site(opts), do: Keyword.put(opts, :output_dir, StaticSite.output_dir())
  defp progress(job), do: &broadcast({:site_builder, :progress, job, &1})

  defp broadcast(message), do: Phoenix.PubSub.broadcast(Playcode.PubSub, @topic, message)
end
