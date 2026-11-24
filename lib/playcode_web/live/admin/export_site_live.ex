defmodule PlaycodeWeb.Admin.ExportSiteLive do
  @moduledoc """
  /admin/export: the static site. Publish brings it in line with the complete plays and
  deploys it; the page lists what is waiting to go online, measured against the live site
  (`Playcode.Export.SiteStatus`). The work runs in `Playcode.Export.SiteBuilder`, which
  broadcasts it, so every admin sees the same state. Admins only.
  """

  use PlaycodeWeb, :live_view

  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :deploy_site}}

  alias Phoenix.LiveView.JS
  alias Playcode.Catalogue
  alias Playcode.Export.{SiteBuilder, SiteStatus, StaticSite}
  alias Playcode.Export.StaticSite.Deployer

  @per_page 50

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, gettext("Export Static Site"))
      # The site's own version, so it is current for the form until someone changes it.
      |> assign(:version, StaticSite.built_version(StaticSite.output_dir()) || app_version())
      |> assign(:deploy_to, Deployer.target())
      |> assign(job: nil, step: nil, gen_current: 0, gen_total: 0, gen_detail: "")
      |> assign(deploy_status: nil, live_search: "", live_page: 1)

    # Subscribed before the status and the disk are read, so a job that ends after that
    # still arrives.
    if connected?(socket) do
      SiteBuilder.subscribe()
      %{job: job} = SiteBuilder.status()
      {:ok, socket |> started(job) |> refresh()}
    else
      {:ok, refresh(socket)}
    end
  end

  @impl true
  def handle_event("update_form", %{"version" => version}, socket),
    do: {:noreply, socket |> assign(:version, version) |> track_site()}

  def handle_event("generate", _params, socket),
    do: socket |> form_opts() |> SiteBuilder.generate() |> queued_flash(socket)

  # The repository is server config, never typed in: the GitHub token goes only to it.
  def handle_event("publish", _params, %{assigns: %{deploy_to: %{repo: repo}}} = socket),
    do: socket |> form_opts() |> SiteBuilder.publish(repo) |> queued_flash(socket)

  def handle_event("publish", _params, socket), do: {:noreply, socket}

  def handle_event("search_live", %{"search" => search}, socket),
    do: {:noreply, assign(socket, live_search: search, live_page: 1)}

  def handle_event("live_page", %{"page" => page}, socket),
    do: {:noreply, assign(socket, :live_page, String.to_integer(page))}

  @impl true
  def handle_info({:site_builder, :started, job}, socket), do: {:noreply, started(socket, job)}

  def handle_info({:site_builder, :progress, :generate, info}, socket) do
    {:noreply,
     assign(socket,
       step: :generate,
       gen_current: info.current,
       gen_total: info.total,
       gen_detail: info.detail
     )}
  end

  def handle_info({:site_builder, :progress, :deploy, status}, socket),
    do: {:noreply, assign(socket, step: :deploy, deploy_status: status)}

  def handle_info({:site_builder, :done, job, result}, socket),
    do: {:noreply, socket |> done(job, result) |> finished()}

  def handle_info({:site_builder, :failed, job, reason}, socket) do
    {:noreply,
     socket
     |> put_flash(:error, failed(failed_step(socket, job), crash_reason(reason)))
     |> finished()}
  end

  def handle_info({:site_builder, _event, _job}, socket), do: {:noreply, socket}

  # Postgres says a play changed (Playcode.Export.PlayChangeListener).
  # An edit changes no file on disk, so the site is not walked again for it.
  def handle_info({:play_changed, _play_id}, socket), do: {:noreply, regroup(socket)}

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        :to_publish,
        length(assigns.new) + length(assigns.changed) + length(assigns.leaving)
      )
      |> assign_live_page()

    ~H"""
    <.page width={:form}>
      <.page_header>
        {gettext("Export Static Site")}
        <:subtitle>
          {gettext(
            "Generate an Endings Project-compliant static website archive of the entire catalogue."
          )}
        </:subtitle>
      </.page_header>

      <section
        id="publish-card"
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
        aria-label={gettext("Publish")}
      >
        <div class="card-body gap-4">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <p class="text-xl font-semibold">
                {headline(@to_publish, @site_changed and @built_count > 0)}
              </p>
              <p class="text-sm text-base-content/70">
                {live_summary(@live, @deploy_to, @deployed_at)}
              </p>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <a
                :if={@built_count > 0}
                href={~p"/admin/export/preview/index.html"}
                target="_blank"
                class="btn btn-sm btn-ghost"
              >
                {gettext("Open preview")}
                <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" />
              </a>
              <button type="button" phx-click="generate" class="btn btn-sm" disabled={@job != nil}>
                {gettext("Generate preview")}
              </button>
              <button
                :if={@deploy_to}
                type="button"
                phx-click="publish"
                class="btn btn-sm btn-primary"
                disabled={@job != nil}
              >
                {if @to_publish > 0,
                  do: ngettext("Publish one play", "Publish %{count} plays", @to_publish),
                  else: gettext("Publish")}
              </button>
            </div>
          </div>

          <div :if={@site_changed and @built_count > 0} id="site-changed" class="alert alert-info">
            <.icon name="hero-information-circle" class="size-5" />
            <span>
              {gettext(
                "Playcode has changed since the last build: the next build rebuilds every complete play (%{count}).",
                count: @complete_count
              )}
              {gettext(
                "On production's shared CPU that takes over two hours: after the deploy, run mix playcode.fly.reimport generate instead, at a quiet hour, which builds on a faster machine in minutes."
              )}
            </span>
          </div>

          <div :if={@job} id="build-progress">
            <p class="text-sm text-base-content/70">
              <span :if={@job == :publish}>
                {if @step == :deploy, do: gettext("Step 2 of 2"), else: gettext("Step 1 of 2")} ·
              </span>
              {progress_text(assigns)}
            </p>
            <progress
              :if={@step == :generate and @gen_total > 0}
              value={@gen_current}
              max={@gen_total}
              class="progress progress-primary w-full"
            />
            <progress :if={@step != :generate or @gen_total == 0} class="progress w-full" />
          </div>

          <div
            id="site-facts"
            class="flex flex-wrap items-baseline gap-x-5 gap-y-1 border-t border-base-300 pt-3 text-sm text-base-content/70"
          >
            <details id="edition-version" phx-mounted={JS.ignore_attributes(["open"])}>
              <summary class="cursor-pointer">
                {gettext("Edition %{version}", version: @version)}
                <span class="link link-primary">{gettext("change")}</span>
              </summary>
              <form phx-change="update_form" class="mt-2 space-y-1" onsubmit="return false">
                <label for="edition-version-input" class="mr-2">{gettext("Version")}</label>
                <input
                  id="edition-version-input"
                  type="text"
                  name="version"
                  value={@version}
                  class="input input-sm input-bordered w-28"
                />
                <p class="text-xs">
                  {gettext(
                    "Printed in every page's footer, in the citation and on the About page. Changing it rebuilds every play: change it only for a new edition."
                  )}
                </p>
              </form>
            </details>
            <span id="site-plays">
              {ngettext("One play built", "%{count} plays built", @built_count)}
            </span>
            <span id="site-size">
              <.async_result :let={size} assign={@site_size}>
                <:loading>…</:loading>
                {format_size(size)}
              </.async_result>
            </span>
            <span>{gettext("Folder")} <code>{StaticSite.output_dir()}/</code></span>
            <span id="deploy-hint"><.deploy_hint target={@deploy_to} /></span>
          </div>
        </div>
      </section>

      <section
        class="card mb-6 border border-base-300 bg-base-100 shadow-sm"
        aria-label={gettext("Plays")}
      >
        <div class="card-body gap-4">
          <h2 class="card-title">{gettext("Plays")}</h2>

          <.play_group id="group-new" plays={@new} label={gettext("New")} badge="badge-info" />
          <.play_group
            id="group-changed"
            plays={@changed}
            label={gettext("Changed")}
            badge="badge-warning"
          />
          <.play_group
            id="group-leaving"
            plays={@leaving}
            label={gettext("Leaving")}
            badge="badge-neutral"
          />

          <details id="group-live" phx-mounted={JS.ignore_attributes(["open"])}>
            <summary class="cursor-pointer py-1">
              <span class="badge badge-sm badge-success">
                {gettext("Up to date (%{count})", count: length(@up_to_date))}
              </span>
            </summary>
            <form phx-change="search_live" class="my-2" onsubmit="return false">
              <input
                type="search"
                name="search"
                value={@live_search}
                placeholder={gettext("Search by title or code")}
                aria-label={gettext("Search the plays up to date")}
                class="input input-sm input-bordered w-full"
                phx-debounce="200"
              />
            </form>
            <ul class="divide-y divide-base-200">
              <.play_row :for={play <- @live_rows} play={play} />
            </ul>
            <div :if={@live_pages > 1} class="mt-2 flex items-center justify-between text-sm">
              <button
                type="button"
                class="btn btn-xs"
                phx-click="live_page"
                phx-value-page={@live_page - 1}
                disabled={@live_page == 1}
              >
                {gettext("Previous")}
              </button>
              <span>{@live_page} / {@live_pages}</span>
              <button
                type="button"
                class="btn btn-xs"
                phx-click="live_page"
                phx-value-page={@live_page + 1}
                disabled={@live_page == @live_pages}
              >
                {gettext("Next")}
              </button>
            </div>
          </details>
        </div>
      </section>

      <details class="text-sm text-base-content/70" phx-mounted={JS.ignore_attributes(["open"])}>
        <summary class="cursor-pointer">{gettext("About the Static Site")}</summary>
        <p class="mt-2 max-w-prose">
          {gettext("Follows the Endings Project principles for long-term digital preservation.")}
          {gettext("Pure HTML/CSS/JS — no server or database required to view.")}
          {gettext("TEI-XML source files included alongside each play.")}
          {gettext("Search needs JavaScript; the catalogue list reads without it.")}
          {gettext("Can be deployed to GitHub Pages, any web server, or opened locally.")}
        </p>
      </details>
    </.page>
    """
  end

  attr :id, :string, required: true
  attr :plays, :list, required: true
  attr :label, :string, required: true
  attr :badge, :string, required: true

  defp play_group(assigns) do
    ~H"""
    <div :if={@plays != []} id={@id}>
      <h3 class="flex items-center gap-2 border-b border-base-300 pb-1">
        <span class={["badge badge-sm", @badge]}>{@label}</span>
        <span class="text-sm text-base-content/70">{length(@plays)}</span>
      </h3>
      <ul class="divide-y divide-base-200">
        <.play_row :for={play <- @plays} play={play} />
      </ul>
    </div>
    """
  end

  attr :play, :map, required: true

  defp play_row(assigns) do
    ~H"""
    <li
      id={"play-#{@play.code}"}
      class="grid grid-cols-[minmax(0,1fr)_auto] items-baseline gap-x-3 py-1.5 sm:grid-cols-[17rem_minmax(0,1fr)_auto]"
    >
      <span
        class="truncate font-mono text-xs text-base-content/70 max-sm:col-span-2"
        title={@play.code}
      >
        {@play.code}
      </span>
      <span class="min-w-0 flex-1 truncate">{@play.title}</span>
      <span class="text-xs text-base-content/70">{@play.reason}</span>
    </li>
    """
  end

  defp refresh(socket), do: socket |> regroup() |> on_disk() |> track_site()

  # The plays by where they stand on the live site. A purged play still live has no row
  # left, only its code.
  defp regroup(socket) do
    dir = StaticSite.output_dir()
    live = SiteStatus.live(dir)
    plays = Catalogue.list_plays(sort: :title_sort, include_deleted: true)
    by_state = Enum.group_by(plays, &SiteStatus.state(&1, live))
    known = MapSet.new(plays, & &1.code)

    purged =
      for code <- Enum.sort(Map.keys(live)),
          not MapSet.member?(known, code),
          do: %{code: code, title: nil, reason: gettext("deleted")}

    socket
    |> assign(
      live: live,
      deployed_at: StaticSite.deployed_at(dir),
      complete_count: Enum.count(plays, &(&1.is_complete and is_nil(&1.deleted_at))),
      new: rows(by_state[:waiting], fn _ -> nil end),
      changed:
        rows(by_state[:changed], &gettext("edited %{date}", date: date(&1.content_changed_at))),
      leaving: rows(by_state[:leaving], &leaving_reason/1) ++ purged,
      up_to_date: rows(by_state[:live], fn _ -> nil end)
    )
  end

  defp rows(nil, _reason), do: []

  defp rows(plays, reason),
    do: for(play <- plays, do: %{code: play.code, title: play.title, reason: reason.(play)})

  defp leaving_reason(%{deleted_at: nil}), do: gettext("back to draft")
  defp leaving_reason(_archived), do: gettext("archived")

  defp date(nil), do: ""
  defp date(datetime), do: Calendar.strftime(datetime, "%Y-%m-%d")

  # The size walks every file of the site, seconds on production's volume: counted apart,
  # once connected, so the page does not wait for it.
  defp on_disk(socket) do
    dir = StaticSite.output_dir()

    socket
    |> assign(:built_count, length(StaticSite.list_exported_codes(dir)))
    |> assign_async(:site_size, fn -> {:ok, %{site_size: StaticSite.dir_size(dir)}} end)
  end

  defp track_site(socket),
    do:
      assign(socket,
        site_changed:
          StaticSite.site_changed?(StaticSite.output_dir(), version: socket.assigns.version)
      )

  defp assign_live_page(assigns) do
    search = String.downcase(String.trim(assigns.live_search))

    matching =
      Enum.filter(assigns.up_to_date, fn row ->
        search == "" or String.contains?(String.downcase("#{row.code} #{row.title}"), search)
      end)

    pages = max(1, ceil(length(matching) / @per_page))
    page = assigns.live_page |> max(1) |> min(pages)

    assign(assigns,
      live_pages: pages,
      live_page: page,
      live_rows: matching |> Enum.drop((page - 1) * @per_page) |> Enum.take(@per_page)
    )
  end

  defp headline(0, true), do: gettext("Every play is to be rebuilt.")
  defp headline(0, false), do: gettext("Everything is published.")

  defp headline(count, _site_changed),
    do: ngettext("One play to publish", "%{count} plays to publish", count)

  defp live_summary(live, nil, _deployed_at),
    do: ngettext("One play in the built site", "%{count} plays in the built site", map_size(live))

  defp live_summary(live, target, deployed_at) do
    on_site =
      ngettext("One play on %{host}", "%{count} plays on %{host}", map_size(live),
        host: target.host || target.repo
      )

    deploy =
      if deployed_at,
        do:
          gettext("last deploy %{date}", date: Calendar.strftime(deployed_at, "%Y-%m-%d %H:%M")),
        else: gettext("never deployed")

    on_site <> " · " <> deploy
  end

  defp progress_text(%{step: :deploy, deploy_status: status}), do: status

  defp progress_text(%{gen_total: total} = assigns) when total > 0 do
    gettext("Generating play %{current} of %{total}: %{detail}",
      current: assigns.gen_current,
      total: total,
      detail: assigns.gen_detail
    )
  end

  defp progress_text(assigns), do: assigns.gen_detail

  defp queued_flash(:started, socket), do: {:noreply, socket}

  defp queued_flash(:queued, socket) do
    {:noreply,
     put_flash(socket, :info, gettext("Queued: it starts when the current build finishes."))}
  end

  defp started(socket, nil), do: socket

  defp started(socket, job) do
    assign(socket,
      job: job,
      step: if(job == :deploy, do: :deploy, else: :generate),
      gen_current: 0,
      gen_total: 0,
      gen_detail: gettext("Starting..."),
      deploy_status: gettext("Starting deploy...")
    )
  end

  defp finished(socket), do: socket |> assign(job: nil, step: nil) |> refresh()

  attr :target, :map, default: nil

  defp deploy_hint(assigns) do
    {text, url} = hint_text(assigns.target)

    assigns =
      case url && String.split(text, assigns.target.repo, parts: 2) do
        [before, rest] -> assign(assigns, before: before, rest: rest, url: url)
        _ -> assign(assigns, before: text, rest: nil, url: nil)
      end

    ~H"""
    {@before}<a :if={@url} href={@url} class="link link-primary">{@target.repo}</a>{@rest}
    """
  end

  defp hint_text(nil),
    do: {gettext("To deploy, set STATIC_SITE_REPO where Playcode runs."), nil}

  defp hint_text(%{repo: repo, host: nil}),
    do: {gettext("Pushes the site to %{repo}.", repo: repo), repo_url(repo)}

  defp hint_text(%{repo: repo, host: host}) do
    {gettext("Pushes the site to %{repo}, then publishes it on %{host}.", repo: repo, host: host),
     repo_url(repo)}
  end

  # The page of a repository, where GitHub offers it as a zip; a local or ssh one has none.
  defp repo_url(repo) do
    cond do
      String.starts_with?(repo, ["https://", "http://"]) ->
        String.replace_suffix(repo, ".git", "")

      String.starts_with?(repo, ["git@", "file://"]) ->
        nil

      true ->
        "https://github.com/#{repo}"
    end
  end

  # The form values every build takes.
  defp form_opts(socket), do: [version: socket.assigns.version]

  defp done(socket, :generate, {:ok, %{plays: plays, size: size}}) do
    put_flash(
      socket,
      :info,
      gettext("Static site generated: %{count} plays (%{size})",
        count: plays,
        size: format_size(size)
      )
    )
  end

  defp done(socket, :generate, {:ok, %{changed: 0, assets: assets?, catalogue: catalogue?}}) do
    updated =
      Enum.filter(
        [
          catalogue? && gettext("The catalogue is updated."),
          assets? && gettext("The site's styles and scripts are updated.")
        ],
        & &1
      )

    put_flash(socket, :info, Enum.join(updated, " "))
  end

  defp done(socket, :generate, {:ok, %{changed: 0}}),
    do: put_flash(socket, :info, gettext("Nothing has changed since the last build."))

  defp done(socket, :generate, {:ok, %{changed: count}}),
    do:
      put_flash(
        socket,
        :info,
        ngettext("One play refreshed.", "%{count} plays refreshed.", count)
      )

  defp done(socket, job, {:ok, url}) when job in [:publish, :deploy],
    do: put_flash(socket, :info, gettext("Published at %{url}", url: url))

  defp done(socket, job, {:error, reason}),
    do: put_flash(socket, :error, failed(failed_step(socket, job), error_text(reason)))

  defp done(socket, _job, _result), do: socket

  defp failed_step(%{assigns: %{step: step}}, :publish) when step != nil, do: step
  defp failed_step(_socket, job), do: job

  defp error_text(reason) when is_binary(reason), do: reason
  defp error_text(reason), do: inspect(reason)

  defp failed(:generate, reason), do: gettext("Generation failed: %{reason}", reason: reason)
  defp failed(:deploy, reason), do: gettext("Deploy failed: %{reason}", reason: reason)
  defp failed(_publish, reason), do: gettext("Publishing failed: %{reason}", reason: reason)

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
end
