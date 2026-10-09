defmodule PlaycodeWeb.Admin.ExportSiteLive do
  @moduledoc """
  /admin/export: the static site. Generate brings it up to date, a play's switch adds or
  removes that play, Deploy publishes it on emothe.uv.es. Every admin sees the same state:
  the work runs in `Playcode.Export.SiteBuilder`, which broadcasts it. Admins only.
  """

  use PlaycodeWeb, :live_view

  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :deploy_site}}

  alias Playcode.Export.{SiteBuilder, StaticSite}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> load_plays()
      |> on_disk()
      |> assign(:page_title, gettext("Export Static Site"))
      # The site's own version, so it is current for the form until someone changes it.
      |> assign(:version, StaticSite.built_version(StaticSite.output_dir()) || app_version())
      |> assign(:deploy_to, deploy_target())
      |> assign(:pending, %{})
      |> assign(:changed, MapSet.new())
      |> assign(:site_changed, false)
      |> assign(:assets_changed, false)
      |> assign(:busy, false)
      |> assign(:indexing, false)
      |> assign(:generating, false)
      |> assign(:deploying, false)
      |> assign(:gen_current, 0)
      |> assign(:gen_total, 0)
      |> assign(:gen_detail, "")
      |> assign(:gen_result, nil)
      |> assign(:deploy_status, nil)
      |> assign(:deploy_url, nil)

    # Subscribed before follow/2 reads the status and the disk, so a job that ends after
    # that still arrives.
    if connected?(socket) do
      SiteBuilder.subscribe()
      {:ok, follow(socket, SiteBuilder.status())}
    else
      {:ok, socket}
    end
  end

  @impl true
  def handle_event("update_form", params, socket) do
    {:noreply,
     socket
     |> assign(:version, params["version"] || "")
     |> track_changes()}
  end

  def handle_event("generate", _params, socket),
    do: socket |> form_opts() |> SiteBuilder.generate() |> queued_flash(socket)

  # A changed play already in the site: written again, in a batch like any add.
  def handle_event("refresh_play", %{"id" => id}, socket),
    do: id |> SiteBuilder.add(form_opts(socket)) |> queued_flash(socket)

  # The repository is server config, never typed in: the GitHub token goes only to it.
  def handle_event("deploy", _params, %{assigns: %{deploy_to: %{repo: repo}}} = socket),
    do: repo |> SiteBuilder.deploy() |> queued_flash(socket)

  def handle_event("deploy", _params, socket), do: {:noreply, socket}

  # A switch with a change on its way is disabled, so this decides by what is on disk.
  # Any play in the site can be switched off; only a published one can be switched on.
  def handle_event("toggle_play", %{"id" => id, "code" => code}, socket) do
    opts = form_opts(socket)

    cond do
      MapSet.member?(socket.assigns.exported_codes, code) -> SiteBuilder.remove(code, opts)
      Enum.any?(socket.assigns.plays, &(&1.id == id)) -> SiteBuilder.add(id, opts)
      true -> :not_published
    end

    {:noreply, socket}
  end

  # The zip is read from the directory a job would be rewriting.
  def handle_event("download_zip", _params, socket) do
    case SiteBuilder.status() do
      %{job: nil, queue: []} ->
        # Create zip in temp dir and redirect to download
        zip_path = Path.join(System.tmp_dir!(), "emothe-static-site.zip")

        case create_zip(StaticSite.output_dir(), zip_path) do
          :ok ->
            {:noreply, redirect(socket, to: ~p"/admin/export/download-zip")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to create zip: #{inspect(reason)}")}
        end

      _busy ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext("The site is busy with another build. Try again when it finishes.")
         )}
    end
  end

  # Jobs report back through the builder's broadcasts, which every open page receives,
  # whoever started the job.
  @impl true
  def handle_info({:site_builder, :queued, request}, socket),
    do: {:noreply, queued(socket, request)}

  def handle_info({:site_builder, :started, job}, socket), do: {:noreply, started(socket, job)}

  def handle_info({:site_builder, :published, {:batch, changes}}, socket),
    do: {:noreply, socket |> settle(changes) |> assign(:indexing, true)}

  def handle_info({:site_builder, :progress, :generate, info}, socket) do
    {:noreply,
     socket
     |> assign(:gen_current, info.current)
     |> assign(:gen_total, info.total)
     |> assign(:gen_detail, info.detail)}
  end

  def handle_info({:site_builder, :progress, :deploy, status}, socket) do
    {:noreply, assign(socket, :deploy_status, status)}
  end

  def handle_info({:site_builder, :done, job, result}, socket),
    do: {:noreply, socket |> finished(job) |> done(job, result)}

  def handle_info({:site_builder, :failed, job, reason}, socket) do
    {:noreply, socket |> finished(job) |> put_flash(:error, failed(job, crash_reason(reason)))}
  end

  # Postgres says a play changed (Playcode.Export.PlayChangeListener). Any play: the
  # page reads again which of its plays changed.
  def handle_info({:play_changed, _play_id}, socket),
    do: {:noreply, socket |> load_plays() |> track_changes()}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-3xl px-4 py-8">
      <div class="mb-6">
        <h1 class="text-3xl font-semibold tracking-tight text-base-content">
          {gettext("Export Static Site")}
        </h1>
        <p class="mt-1 text-sm text-base-content/70">
          {gettext(
            "Generate an Endings Project-compliant static website archive of the entire catalogue."
          )}
        </p>
      </div>

      <div
        :if={@site_changed and MapSet.size(@exported_codes) > 0}
        id="site-changed"
        class="alert alert-warning mb-6"
      >
        <.icon name="hero-exclamation-triangle" class="size-5" />
        <span>
          {gettext(
            "The site's design or settings changed since the last build. Generate will rebuild every play."
          )}
        </span>
      </div>

      <%!-- Configuration form --%>
      <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Configuration")}</h2>

          <form phx-change="update_form" phx-submit="generate" class="space-y-4 mt-2">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
              <label class="form-control">
                <div class="label">
                  <span class="label-text">{gettext("Version")}</span>
                </div>
                <input
                  type="text"
                  name="version"
                  value={@version}
                  class="input input-bordered"
                  placeholder="1.0"
                />
              </label>
            </div>

            <div class="flex items-center gap-4">
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@generating}
              >
                <span :if={@generating} class="loading loading-spinner loading-sm"></span>
                {if @generating, do: gettext("Generating..."), else: gettext("Generate Static Site")}
              </button>
              <span class="text-sm text-base-content/60">
                {gettext("%{complete} of %{total} plays marked as complete",
                  complete: @complete_count,
                  total: @total_count
                )}
              </span>
            </div>
            <p class="text-xs text-base-content/50">
              {generate_hint(@exported_codes, @site_changed, @assets_changed, @changed, @plays)}
            </p>
          </form>
        </div>
      </div>

      <%!-- Play list --%>
      <div class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <h2 class="card-title">{gettext("Plays")}</h2>

          <div :if={@plays == []} class="text-sm text-base-content/50 text-center py-4">
            {gettext("No plays marked as complete.")}
          </div>

          <p :if={@plays != []} class="text-sm text-base-content/60 mb-3">
            {gettext("%{exported} of %{total} complete plays exported",
              exported: Enum.count(@plays, &MapSet.member?(@exported_codes, &1.code)),
              total: length(@plays)
            )}
          </p>

          <div class="divide-y divide-base-200">
            <div :for={play <- @plays} id={"play-#{play.id}"} class="flex items-center gap-3 py-2">
              <.status_dot status={
                play_status(play, @exported_codes, @changed, @pending, @site_changed)
              } />
              <%!-- Only the name labels the switch: a label around Refresh would take it as its control. --%>
              <label for={"switch-#{play.id}"} class="min-w-0 flex-1 cursor-pointer">
                <span class="font-mono text-xs text-base-content/50">{play.code}</span>
                <span class="font-medium ml-2 truncate">{play.title}</span>
              </label>
              <button
                :if={
                  play_status(play, @exported_codes, @changed, @pending, @site_changed) ==
                    :changed
                }
                id={"refresh-#{play.id}"}
                type="button"
                phx-click="refresh_play"
                phx-value-id={play.id}
                class="btn btn-ghost btn-xs btn-square"
                title={gettext("Publish this play's changes")}
                aria-label={gettext("Refresh %{title}", title: play.title)}
              >
                <.icon name="hero-arrow-path-mini" class="size-4" />
              </button>
              <span
                :if={Map.has_key?(@pending, play.id)}
                class="loading loading-spinner loading-xs text-base-content/50"
              />
              <%!-- On means in the site; flipping it adds or removes the play at once. --%>
              <.site_switch
                play={play}
                checked={
                  (MapSet.member?(@exported_codes, play.code) and @pending[play.id] != :remove) or
                    @pending[play.id] == :add
                }
                pending={Map.has_key?(@pending, play.id)}
              />
            </div>
            <%!-- In the site but a draft or archived now: it stays until switched off or Generate. --%>
            <div
              :for={play <- leaving(@exported_codes, @plays, @others)}
              id={"play-#{play.id || play.code}"}
              class="flex items-center gap-3 py-2"
            >
              <.status_dot status={:leaving} />
              <label
                for={"switch-#{play.id || play.code}"}
                class="min-w-0 flex-1 cursor-pointer text-base-content/50"
              >
                <span class="font-mono text-xs">{play.code}</span>
                <span :if={play.title} class="ml-2 truncate">{play.title}</span>
              </label>
              <%!-- A removal is pending under the play's code: it is not among @plays. --%>
              <span
                :if={Map.has_key?(@pending, play.code)}
                class="loading loading-spinner loading-xs text-base-content/50"
              />
              <.site_switch
                play={play}
                checked={@pending[play.code] != :remove}
                pending={Map.has_key?(@pending, play.code)}
              />
            </div>
          </div>
        </div>
      </div>

      <%!-- Generation progress --%>
      <div
        :if={@generating}
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <div class="flex items-center gap-3">
            <span class="loading loading-spinner loading-md text-primary"></span>
            <span class="font-medium">
              {if @gen_total > 0,
                do:
                  gettext("Generating play %{current} of %{total}: %{detail}",
                    current: @gen_current,
                    total: @gen_total,
                    detail: @gen_detail
                  ),
                else: @gen_detail}
            </span>
          </div>
          <progress
            :if={@gen_total > 0}
            value={@gen_current}
            max={@gen_total}
            class="progress progress-primary w-full mt-2"
          />
        </div>
      </div>

      <%!-- Results --%>
      <div
        :if={(@gen_result || MapSet.size(@exported_codes) > 0) && !@generating}
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
      >
        <div class="card-body">
          <h2 :if={@gen_result} class="card-title text-success">
            {gettext("Generation Complete")}
          </h2>
          <h2 :if={!@gen_result} class="card-title">{gettext("Built site")}</h2>
          <%!-- The site on disk, so a switch changes these as much as Generate does. --%>
          <div class="stats stats-horizontal shadow mt-2">
            <div class="stat">
              <div class="stat-title">{gettext("Plays")}</div>
              <div id="site-plays" class="stat-value text-lg">{MapSet.size(@exported_codes)}</div>
            </div>
            <div class="stat">
              <div class="stat-title">{gettext("Total Size")}</div>
              <div id="site-size" class="stat-value text-lg">{format_size(@site_size)}</div>
            </div>
            <div class="stat">
              <div class="stat-title">{gettext("Output")}</div>
              <div class="stat-value text-lg font-mono text-sm">{StaticSite.output_dir()}/</div>
            </div>
          </div>

          <div class="flex gap-3 mt-4">
            <a
              href={~p"/admin/export/preview/index.html"}
              target="_blank"
              class="btn btn-primary btn-outline"
            >
              <.icon name="hero-eye-mini" class="size-4" />
              {gettext("Open preview")}
            </a>
            <span :if={@indexing} class="badge badge-ghost gap-1">
              <span class="loading loading-spinner loading-xs"></span>
              {gettext("Updating search…")}
            </span>
            <%!-- Deploy button --%>
            <button
              :if={@deploy_to}
              phx-click="deploy"
              class="btn btn-secondary"
              disabled={@deploying}
            >
              <span :if={@deploying} class="loading loading-spinner loading-sm"></span>
              {if @deploying, do: gettext("Deploying..."), else: gettext("Deploy")}
            </button>

            <%!-- Download zip --%>
            <button
              phx-click="download_zip"
              class="btn btn-outline"
              disabled={@busy}
            >
              {gettext("Download .zip")}
            </button>
          </div>
          <p class="text-xs text-base-content/50 mt-2">{deploy_hint(@deploy_to)}</p>
        </div>
      </div>

      <%!-- Deploy progress --%>
      <div :if={@deploying} class="card mb-6 border border-base-300 bg-base-100 shadow-sm">
        <div class="card-body">
          <div class="flex items-center gap-3">
            <span class="loading loading-spinner loading-md text-secondary"></span>
            <span class="font-medium">{@deploy_status}</span>
          </div>
        </div>
      </div>

      <%!-- Deploy success --%>
      <div
        :if={@deploy_url && !@deploying}
        class="card mb-6 border border-success/30 bg-success/5 shadow-sm"
      >
        <div class="card-body">
          <h2 class="card-title text-success">{gettext("Deployed!")}</h2>
          <p class="text-sm">
            {gettext("Your static site is live at:")}
            <a
              href={@deploy_url}
              target="_blank"
              class="link link-primary font-mono"
            >
              {@deploy_url}
            </a>
          </p>
          <p :if={!@deploy_to[:host]} class="text-xs text-base-content/50 mt-1">
            {gettext("Note: GitHub Pages may take a few minutes to update.")}
          </p>
        </div>
      </div>

      <%!-- Info box --%>
      <div class="card border border-base-300 bg-base-200/50">
        <div class="card-body text-sm text-base-content/70">
          <h3 class="font-semibold text-base-content">{gettext("About the Static Site")}</h3>
          <ul class="list-disc ml-4 space-y-1 mt-2">
            <li>
              {gettext("Follows the Endings Project principles for long-term digital preservation.")}
            </li>
            <li>{gettext("Pure HTML/CSS/JS — no server or database required to view.")}</li>
            <li>{gettext("TEI-XML source files included alongside each play.")}</li>
            <li>{gettext("Search needs JavaScript; the catalogue list reads without it.")}</li>
            <li>{gettext("Can be deployed to GitHub Pages, any web server, or opened locally.")}</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp queued_flash(:started, socket), do: {:noreply, socket}

  defp queued_flash(:queued, socket) do
    {:noreply,
     put_flash(socket, :info, gettext("Queued: it starts when the current build finishes."))}
  end

  # What the builder runs and what waits behind it, as a page opened now sees it.
  # Runs after subscribing, so the disk is read once nothing can end unheard.
  defp follow(socket, %{job: job, queue: queue}) do
    queue
    |> Enum.reduce(started(socket, job), &queued(&2, &1))
    |> on_disk()
    |> track_changes()
  end

  # A change on its way: its switch shows where the play is going until it lands.
  defp queued(socket, {:add, id}), do: pending(socket, id, :add)
  defp queued(socket, {:remove, code}), do: pending(socket, play_id(socket, code), :remove)
  defp queued(socket, _generate_or_deploy), do: assign(socket, :busy, true)

  defp pending(socket, id, change) do
    socket
    |> update(:pending, &Map.put(&1, id, change))
    |> assign(:busy, true)
  end

  defp started(socket, nil), do: socket

  defp started(socket, :generate) do
    socket
    |> assign(:busy, true)
    |> assign(:generating, true)
    |> assign(:gen_current, 0)
    |> assign(:gen_total, 0)
    |> assign(:gen_detail, gettext("Starting..."))
    |> assign(:gen_result, nil)
    |> assign(:deploy_status, nil)
    |> assign(:deploy_url, nil)
  end

  defp started(socket, {:batch, changes}),
    do: Enum.reduce(changes, assign(socket, :indexing, false), &queued(&2, &1))

  defp started(socket, :deploy) do
    socket
    |> assign(:busy, true)
    |> assign(:deploying, true)
    |> assign(:deploy_status, gettext("Starting deploy..."))
  end

  # A batch's pages are published: its switches settle on what is on disk.
  # Only the marks the batch fulfilled: a play switched the other way since stays pending.
  # The plays it wrote are current, though build.json says so only once it is :done.
  defp settle(socket, changes) do
    landed = Map.new(changes, &{change_id(socket, &1), direction(&1)})
    written = for play <- socket.assigns.plays, landed[play.id] == :add, do: play.code

    socket
    |> update(:pending, &Map.reject(&1, fn {id, change} -> landed[id] == change end))
    |> update(:changed, &MapSet.difference(&1, MapSet.new(written)))
    |> on_disk()
  end

  defp direction({:add, _}), do: :add
  defp direction({:remove, _}), do: :remove

  # A job ended. If requests wait, the builder's next :started marks the page busy again.
  defp finished(socket, {:batch, changes}),
    do: socket |> settle(changes) |> idle() |> track_changes()

  defp finished(socket, _job),
    do: socket |> on_disk() |> idle() |> track_changes()

  defp idle(socket),
    do: assign(socket, generating: false, deploying: false, indexing: false, busy: false)

  defp change_id(_socket, {:add, id}), do: id
  defp change_id(socket, {:remove, code}), do: play_id(socket, code)

  # The switches name plays by id; the builder names a removal by its code.
  defp play_id(socket, code),
    do: Enum.find_value(socket.assigns.plays, code, &(&1.code == code && &1.id))

  # What the site on disk holds: the plays the switches show, and its size.
  defp on_disk(socket) do
    dir = StaticSite.output_dir()

    assign(socket,
      exported_codes: MapSet.new(StaticSite.list_exported_codes(dir)),
      site_size: StaticSite.dir_size(dir)
    )
  end

  # Where Deploy goes, from the server's settings (StaticSite.Deployer): the repository,
  # and the host of the server told to publish, if any. nil when there is no repository.
  defp deploy_target do
    settings = Application.get_env(:playcode, :static_site_deploy, [])

    case settings[:repo] do
      repo when repo in [nil, ""] ->
        nil

      repo ->
        %{repo: repo, host: settings[:publish_url] && URI.parse(settings[:publish_url]).host}
    end
  end

  defp deploy_hint(nil), do: gettext("To deploy, set STATIC_SITE_REPO where Playcode runs.")

  defp deploy_hint(%{repo: repo, host: nil}),
    do: gettext("Pushes the site to %{repo}.", repo: repo)

  defp deploy_hint(%{repo: repo, host: host}),
    do:
      gettext("Pushes the site to %{repo}, then publishes it on %{host}.", repo: repo, host: host)

  # The form values every build takes.
  defp form_opts(socket), do: [version: socket.assigns.version]

  # Which published plays changed since they were written, and whether the site as a
  # whole did, for the version in the form.
  defp track_changes(socket) do
    dir = StaticSite.output_dir()

    assign(socket,
      changed: MapSet.new(StaticSite.changed_plays(dir)),
      site_changed: StaticSite.site_changed?(dir, version: socket.assigns.version),
      assets_changed: StaticSite.assets_changed?(dir)
    )
  end

  # A play in the site is :changed while it differs from its pages, :current otherwise.
  # Nothing while a change of it is on its way (the spinner shows), and nothing for any
  # play while the whole site changed: the banner covers them all, and none is current.
  defp play_status(play, exported, changed, pending, site_changed?) do
    cond do
      site_changed? or Map.has_key?(pending, play.id) -> nil
      MapSet.member?(changed, play.code) -> :changed
      MapSet.member?(exported, play.code) -> :current
      true -> nil
    end
  end

  attr :status, :atom, required: true

  # A fixed-width slot, so every row's name lines up, dot or not.
  defp status_dot(assigns) do
    ~H"""
    <span class="size-2 shrink-0">
      <span
        :if={@status == :changed}
        class="block size-2 rounded-full bg-warning"
        title={gettext("Unpublished changes")}
      >
        <span class="sr-only">{gettext("Unpublished changes")}</span>
      </span>
      <span
        :if={@status == :current}
        class="block size-2 rounded-full bg-success"
        title={gettext("Published and up to date")}
      >
        <span class="sr-only">{gettext("Published and up to date")}</span>
      </span>
      <span
        :if={@status == :leaving}
        class="block size-2 rounded-full border border-base-content/40"
        title={gettext("No longer published (a draft or archived); Generate takes it out.")}
      >
        <span class="sr-only">
          {gettext("No longer published (a draft or archived); Generate takes it out.")}
        </span>
      </span>
    </span>
    """
  end

  attr :play, :map, required: true
  attr :checked, :boolean, required: true
  attr :pending, :boolean, required: true

  # A play that is gone from the database keeps its row by code until switched off.
  defp site_switch(assigns) do
    ~H"""
    <input
      id={"switch-#{@play.id || @play.code}"}
      type="checkbox"
      role="switch"
      class="toggle toggle-success toggle-sm"
      aria-label={gettext("In the site: %{title}", title: @play.title || @play.code)}
      checked={@checked}
      disabled={@pending}
      phx-click="toggle_play"
      phx-value-id={@play.id}
      phx-value-code={@play.code}
    />
    """
  end

  # Every play, split: the published ones (complete, not archived) are the list; the
  # others are kept by code, for the ones still in the site.
  defp load_plays(socket) do
    all = Playcode.Catalogue.list_plays(sort: :title_sort, include_deleted: true)
    {plays, others} = Enum.split_with(all, &(&1.is_complete and is_nil(&1.deleted_at)))

    assign(socket,
      plays: plays,
      others: Map.new(others, &{&1.code, &1}),
      complete_count: length(plays),
      total_count: Enum.count(all, &is_nil(&1.deleted_at))
    )
  end

  # The plays in the site that are not published any more, by code; a purged one has
  # no row left, only its code.
  defp leaving(exported, plays, others) do
    published = MapSet.new(plays, & &1.code)

    for code <- Enum.sort(exported), not MapSet.member?(published, code) do
      Map.get(others, code, %{id: nil, code: code, title: nil})
    end
  end

  # What Generate will do, under its button. A play in the site but not in `plays`, the
  # complete ones, is archived or no longer complete, and Generate takes it out.
  defp generate_hint(exported, site_changed?, assets_changed?, changed, plays) do
    removed = MapSet.size(MapSet.difference(exported, MapSet.new(plays, & &1.code)))

    cond do
      MapSet.size(exported) == 0 ->
        gettext("Builds every complete play.")

      site_changed? ->
        gettext("Rebuilds the %{count} plays in the site.", count: MapSet.size(exported))

      MapSet.size(changed) == 0 and removed == 0 and not assets_changed? ->
        gettext("Every play in the site is up to date.")

      true ->
        Enum.join(
          assets_hint(assets_changed?) ++
            changed_hint(MapSet.size(changed)) ++ removed_hint(removed),
          " "
        )
    end
  end

  defp assets_hint(false), do: []

  defp assets_hint(true),
    do: [gettext("The site's styles and scripts have changed. Generate updates them.")]

  defp changed_hint(0), do: []

  defp changed_hint(count) do
    [
      ngettext(
        "One published play has changed. Generate refreshes it.",
        "%{count} published plays have changed. Generate refreshes them.",
        count
      )
    ]
  end

  defp removed_hint(0), do: []

  defp removed_hint(count) do
    [
      ngettext(
        "One play in the site is no longer published. Generate takes it out.",
        "%{count} plays in the site are no longer published. Generate takes them out.",
        count
      )
    ]
  end

  defp done(socket, :generate, {:ok, %{plays: plays, size: size} = result}) do
    socket
    |> assign(:gen_result, result)
    |> put_flash(
      :info,
      gettext("Static site generated: %{count} plays (%{size})",
        count: plays,
        size: format_size(size)
      )
    )
  end

  defp done(socket, :generate, {:ok, %{changed: 0, assets: true}}),
    do: put_flash(socket, :info, gettext("The site's styles and scripts are updated."))

  defp done(socket, :generate, {:ok, %{changed: 0}}),
    do: put_flash(socket, :info, gettext("Nothing has changed since the last build."))

  defp done(socket, :generate, {:ok, %{changed: count}}) do
    put_flash(socket, :info, ngettext("One play refreshed.", "%{count} plays refreshed.", count))
  end

  defp done(socket, {:batch, [{:add, _}]}, {:ok, %{skipped: []}}),
    do: put_flash(socket, :info, gettext("Play exported to static site."))

  defp done(socket, {:batch, [{:remove, code}]}, {:ok, %{skipped: []}}),
    do: put_flash(socket, :info, gettext("Removed %{code} from static site.", code: code))

  defp done(socket, {:batch, changes}, {:ok, %{skipped: []}}) do
    put_flash(
      socket,
      :info,
      gettext("%{count} changes applied to the static site.", count: length(changes))
    )
  end

  defp done(socket, {:batch, _changes}, {:ok, %{skipped: skipped}}) do
    put_flash(
      socket,
      :error,
      ngettext(
        "A play that no longer exists was skipped.",
        "%{count} plays that no longer exist were skipped.",
        length(skipped)
      )
    )
  end

  defp done(socket, :deploy, {:ok, url}) do
    socket
    |> assign(:deploy_url, url)
    |> put_flash(:info, gettext("Deployed to GitHub Pages!"))
  end

  defp done(socket, :generate, {:error, reason}),
    do: put_flash(socket, :error, failed(:generate, inspect(reason)))

  defp done(socket, :deploy, {:error, reason}),
    do: put_flash(socket, :error, failed(:deploy, reason))

  defp failed(:generate, reason),
    do: gettext("Generation failed: %{reason}", reason: reason)

  defp failed(:deploy, reason), do: gettext("Deploy failed: %{reason}", reason: reason)

  defp failed({:batch, [{:add, _}]}, reason),
    do: gettext("Could not add the play: %{reason}", reason: reason)

  defp failed({:batch, [{:remove, code}]}, reason),
    do: gettext("Could not remove %{code}: %{reason}", code: code, reason: reason)

  defp failed({:batch, changes}, reason) do
    gettext("Could not apply %{count} changes to the site: %{reason}",
      count: length(changes),
      reason: reason
    )
  end

  # A crashed task exits with its exception and stacktrace; the message is what to show.
  defp crash_reason({exception, _stacktrace}) when is_exception(exception),
    do: Exception.message(exception)

  defp crash_reason(reason), do: inspect(reason)

  defp app_version do
    case :application.get_key(:playcode, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      _ -> "1.0"
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  # Names only, so :zip reads each file from disk as it adds it: the whole site in memory
  # at once would not fit the machine at a few hundred plays.
  defp create_zip(source_dir, zip_path) do
    files =
      source_dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&String.to_charlist(Path.relative_to(&1, source_dir)))

    case :zip.create(String.to_charlist(zip_path), files, cwd: String.to_charlist(source_dir)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
