defmodule Playcode.Export.SiteBuilder do
  @moduledoc """
  The one process that writes and ships the admin's static site, `StaticSite.output_dir/0`.

  Adding or removing a play reads the search index on disk and writes it back, and a
  deploy pushes the whole directory, so the builder runs one job at a time. A request
  that arrives while a job runs is queued, not refused: each starter returns `:started`
  or `:queued`. A request already waiting is not queued twice: it keeps its place and
  takes the options of the latest ask. When a job ends, the adds and removes at the front
  of the queue run as one batch, which publishes its pages first and rewrites the search
  index once (`StaticSite.apply_changes/2`); a generate, a rebuild or a deploy runs on its
  own, in its turn. Generate brings the site up to date when it runs: every play in it
  when the site's code or settings changed since it was built, only the changed plays
  otherwise. Rebuild always rebuilds every play.

  Jobs are `:generate`, `:rebuild`, `{:batch, [{:add, play_id} | {:remove, code}]}` and
  `:deploy`. It broadcasts on `"static_site"`, so every admin page shows the same state:
  `{:site_builder, :queued, request}` (`:generate`, `:rebuild`, `{:add, id}`,
  `{:remove, code}` or `:deploy`), `{:site_builder, :started, job}`,
  `{:site_builder, :progress, job, info}`, `{:site_builder, :published, job}` (a batch's
  pages are live, its search is next), `{:site_builder, :done, job, result}` and
  `{:site_builder, :failed, job, reason}`.
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

  @doc """
  Brings the site up to date. When its code or settings changed since it was built
  (`StaticSite.site_changed?/2`), or it holds no play, every play in it is rebuilt (every
  complete play if it is empty) and the result is `StaticSite.generate/1`'s. Otherwise
  only the plays that changed are written again and the ones no longer published taken
  out, in one batch, and the result is `{:ok, %{changed: count, skipped: [play_id]}}`.
  `opts` as `StaticSite.generate/1` takes them, but for the directory and plays.
  """
  def generate(opts), do: request(:generate, opts)

  @doc "Rebuilds every play in the site, whatever changed. Results as `generate/1`'s full build."
  def rebuild(opts), do: request(:rebuild, opts)

  def add(play_id, opts), do: request({:add, play_id}, opts)
  def remove(code, opts), do: request({:remove, code}, opts)
  def deploy(repo), do: request(:deploy, repo)

  @doc "The running job and the requests waiting behind it, oldest first."
  def status, do: GenServer.call(__MODULE__, :status)

  defp request(request, args), do: GenServer.call(__MODULE__, {:request, request, args})

  @impl true
  def init(nil), do: {:ok, %{job: nil, ref: nil, queue: []}}

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{job: state.job, queue: Enum.map(state.queue, &elem(&1, 0))}, state}
  end

  # Idle means the queue is empty: the request runs at once, as a job of its own.
  def handle_call({:request, request, args}, _from, %{job: nil} = state) do
    {:reply, :started, run_next(%{state | queue: [{request, args}]})}
  end

  def handle_call({:request, request, args}, _from, state) do
    if Enum.any?(state.queue, fn {queued, _} -> queued == request end) do
      # Latest wins, in place: a corrected repository or version must not be dropped.
      queue =
        Enum.map(state.queue, fn
          {^request, _} -> {request, args}
          entry -> entry
        end)

      {:reply, :queued, %{state | queue: queue}}
    else
      broadcast({:site_builder, :queued, request})
      {:reply, :queued, %{state | queue: state.queue ++ [{request, args}]}}
    end
  end

  @impl true
  def handle_info({ref, result}, %{ref: ref, job: job} = state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    broadcast({:site_builder, :done, job, result})
    {:noreply, run_next(state)}
  end

  # The reply is flushed with the monitor, so a :DOWN means the task gave no result.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{ref: ref, job: job} = state) do
    broadcast({:site_builder, :failed, job, reason})
    {:noreply, run_next(state)}
  end

  # Crashing on a stray message would restart the builder idle while its job ran on.
  def handle_info(_message, state), do: {:noreply, state}

  # Starts what is at the front of the queue: every add and remove there as one batch,
  # or a generate or a deploy on its own.
  defp run_next(%{queue: []} = state), do: %{state | job: nil, ref: nil}

  defp run_next(%{queue: queue} = state) do
    {job, args, rest} = take(queue)
    # Announced before the task starts, so no page hears its progress before it.
    broadcast({:site_builder, :started, job})
    task = Task.Supervisor.async_nolink(@tasks, fn -> run(job, args) end)
    %{state | job: job, ref: task.ref, queue: rest}
  end

  defp take([{request, args} | rest]) when request in [:generate, :rebuild, :deploy],
    do: {request, args, rest}

  defp take(queue) do
    {changes, rest} = Enum.split_while(queue, fn {request, _} -> change?(request) end)
    # A batch takes the form values of its latest request.
    {_, args} = List.last(changes)
    {{:batch, Enum.map(changes, &elem(&1, 0))}, args, rest}
  end

  defp change?({:add, _}), do: true
  defp change?({:remove, _}), do: true
  defp change?(_request), do: false

  # An empty site gets every complete play, whatever build.json says: the last switch
  # turned off leaves it the fingerprint of a site that is gone.
  defp run(:generate, opts) do
    dir = StaticSite.output_dir()

    if StaticSite.site_changed?(dir, opts) or StaticSite.list_exported_codes(dir) == [],
      do: build_all(:generate, opts),
      else: refresh(opts)
  end

  defp run(:rebuild, opts), do: build_all(:rebuild, opts)

  defp run({:batch, changes} = job, opts) do
    published = fn -> broadcast({:site_builder, :published, job}) end
    StaticSite.apply_changes(changes, opts |> in_site() |> Keyword.put(:on_published, published))
  end

  # The StaticSite entry points set English themselves; Deployer translates nothing.
  defp run(:deploy, repo) do
    Deployer.deploy_to_github_pages(StaticSite.output_dir(), repo, on_progress: progress(:deploy))
  end

  # Rebuilds the site as it stands when the job runs, not when it was asked for: an add
  # or remove queued before it keeps its change.
  defp build_all(job, opts) do
    opts
    |> in_site()
    |> Keyword.put(:play_codes, codes_in_site())
    |> Keyword.put(:on_progress, progress(job))
    |> StaticSite.generate()
  end

  # Only what changed since the last build; with nothing to do, nothing is written.
  defp refresh(opts) do
    case StaticSite.outdated(StaticSite.output_dir()) do
      [] ->
        {:ok, %{changed: 0, skipped: []}}

      changes ->
        {:ok, %{skipped: skipped}} = StaticSite.apply_changes(changes, in_site(opts))
        {:ok, %{changed: length(changes), skipped: skipped}}
    end
  end

  # An empty site gets every complete play: StaticSite drops a nil option.
  defp codes_in_site do
    case StaticSite.list_exported_codes(StaticSite.output_dir()) do
      [] -> nil
      codes -> codes
    end
  end

  defp in_site(opts), do: Keyword.put(opts, :output_dir, StaticSite.output_dir())
  defp progress(job), do: &broadcast({:site_builder, :progress, job, &1})

  defp broadcast(message), do: Phoenix.PubSub.broadcast(Playcode.PubSub, @topic, message)
end
