defmodule PlaycodeWeb.Admin.ExportSiteLive do
  use PlaycodeWeb, :live_view

  on_mount {PlaycodeWeb.UserAuth, {:ensure_can, :deploy_site}}

  alias Playcode.Export.StaticSite
  alias Playcode.Export.StaticSite.Deployer

  @impl true
  def mount(_params, _session, socket) do
    plays = Playcode.Catalogue.list_plays(sort: :title_sort, complete: true)
    exported_codes = StaticSite.list_exported_codes(StaticSite.output_dir())

    {:ok,
     socket
     |> assign(:page_title, gettext("Export Static Site"))
     |> assign(:version, app_version())
     |> assign(:base_url, "/")
     |> assign(:github_repo, "")
     |> assign(:plays, plays)
     |> assign(:exported_codes, MapSet.new(exported_codes))
     |> assign(:exporting_play, nil)
     |> assign(:removing_play, nil)
     |> assign(:complete_count, length(plays))
     |> assign(:total_count, Playcode.Catalogue.count_plays())
     |> assign(:generating, false)
     |> assign(:deploying, false)
     |> assign(:gen_current, 0)
     |> assign(:gen_total, 0)
     |> assign(:gen_detail, "")
     |> assign(:gen_result, nil)
     |> assign(:deploy_status, nil)
     |> assign(:deploy_url, nil)}
  end

  @impl true
  def handle_event("update_form", params, socket) do
    {:noreply,
     socket
     |> assign(:version, params["version"] || "")
     |> assign(:base_url, params["base_url"] || "/")
     |> assign(:github_repo, params["github_repo"] || "")}
  end

  def handle_event("generate", _params, socket) do
    lv = self()

    on_progress = fn info ->
      send(lv, {:gen_progress, info})
    end

    opts = [
      output_dir: StaticSite.output_dir(),
      version: socket.assigns.version,
      base_url: socket.assigns.base_url,
      play_codes: rebuild_codes(socket.assigns.exported_codes),
      on_progress: on_progress
    ]

    Task.start(fn ->
      result = StaticSite.generate(opts)
      send(lv, {:gen_done, result})
    end)

    {:noreply,
     socket
     |> assign(:generating, true)
     |> assign(:gen_current, 0)
     |> assign(:gen_total, 0)
     |> assign(:gen_detail, gettext("Starting..."))
     |> assign(:gen_result, nil)
     |> assign(:deploy_status, nil)
     |> assign(:deploy_url, nil)}
  end

  def handle_event("deploy", _params, socket) do
    repo = String.trim(socket.assigns.github_repo)

    if repo == "" do
      {:noreply, put_flash(socket, :error, gettext("Please enter a GitHub repository."))}
    else
      lv = self()

      on_progress = fn status ->
        send(lv, {:deploy_progress, status})
      end

      Task.start(fn ->
        result =
          Deployer.deploy_to_github_pages(StaticSite.output_dir(), repo, on_progress: on_progress)

        send(lv, {:deploy_done, result})
      end)

      {:noreply,
       socket
       |> assign(:deploying, true)
       |> assign(:deploy_status, gettext("Starting deploy..."))}
    end
  end

  # One build at a time: adding or removing a play rewrites the shared catalogue and index.
  def handle_event("toggle_play", _params, socket)
      when socket.assigns.generating or not is_nil(socket.assigns.exporting_play) or
             not is_nil(socket.assigns.removing_play),
      do: {:noreply, socket}

  def handle_event("toggle_play", %{"id" => id, "code" => code}, socket) do
    opts = [
      output_dir: StaticSite.output_dir(),
      version: socket.assigns.version,
      base_url: socket.assigns.base_url
    ]

    if MapSet.member?(socket.assigns.exported_codes, code) do
      lv = self()

      Task.start(fn ->
        StaticSite.remove_single_play(code, opts)
        send(lv, {:play_removed, code})
      end)

      {:noreply, assign(socket, :removing_play, id)}
    else
      lv = self()

      Task.start(fn ->
        StaticSite.generate_single_play(id, opts)
        send(lv, {:play_exported, id})
      end)

      {:noreply, assign(socket, :exporting_play, id)}
    end
  end

  def handle_event("download_zip", _params, socket) do
    # Create zip in temp dir and redirect to download
    zip_path = Path.join(System.tmp_dir!(), "emothe-static-site.zip")

    case create_zip(StaticSite.output_dir(), zip_path) do
      :ok ->
        {:noreply, redirect(socket, to: ~p"/admin/export/download-zip")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create zip: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:gen_progress, info}, socket) do
    {:noreply,
     socket
     |> assign(:gen_current, info.current)
     |> assign(:gen_total, info.total)
     |> assign(:gen_detail, info.detail)}
  end

  def handle_info({:gen_done, {:ok, result}}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> assign(:gen_result, result)
     |> assign(
       :exported_codes,
       MapSet.new(StaticSite.list_exported_codes(StaticSite.output_dir()))
     )
     |> put_flash(
       :info,
       gettext("Static site generated: %{count} plays (%{size})",
         count: result.plays,
         size: format_size(result.size)
       )
     )}
  end

  def handle_info({:play_exported, _id}, socket) do
    {:noreply,
     socket
     |> assign(
       :exported_codes,
       MapSet.new(StaticSite.list_exported_codes(StaticSite.output_dir()))
     )
     |> assign(:exporting_play, nil)
     |> put_flash(:info, gettext("Play exported to static site."))}
  end

  def handle_info({:play_removed, code}, socket) do
    {:noreply,
     socket
     |> assign(
       :exported_codes,
       MapSet.new(StaticSite.list_exported_codes(StaticSite.output_dir()))
     )
     |> assign(:removing_play, nil)
     |> put_flash(:info, gettext("Removed %{code} from static site.", code: code))}
  end

  def handle_info({:gen_done, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> put_flash(:error, "Generation failed: #{inspect(reason)}")}
  end

  def handle_info({:deploy_progress, status}, socket) do
    {:noreply, assign(socket, :deploy_status, status)}
  end

  def handle_info({:deploy_done, {:ok, url}}, socket) do
    {:noreply,
     socket
     |> assign(:deploying, false)
     |> assign(:deploy_url, url)
     |> put_flash(:info, gettext("Deployed to GitHub Pages!"))}
  end

  def handle_info({:deploy_done, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:deploying, false)
     |> put_flash(:error, "Deploy failed: #{reason}")}
  end

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

              <label class="form-control">
                <div class="label">
                  <span class="label-text">{gettext("Base URL")}</span>
                </div>
                <input
                  type="text"
                  name="base_url"
                  value={@base_url}
                  class="input input-bordered"
                  placeholder="/"
                />
              </label>
            </div>

            <label class="form-control">
              <div class="label">
                <span class="label-text">{gettext("GitHub Repository (for deploy)")}</span>
              </div>
              <input
                type="text"
                name="github_repo"
                value={@github_repo}
                class="input input-bordered"
                placeholder="owner/repo-name"
              />
              <div class="label">
                <span class="label-text-alt text-base-content/50">
                  {gettext("e.g. username/emothe-static — leave empty to skip deploy")}
                </span>
              </div>
            </label>

            <div class="flex items-center gap-4">
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@generating || @deploying || @exporting_play || @removing_play}
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
              {if MapSet.size(@exported_codes) == 0,
                do: gettext("Builds every complete play."),
                else:
                  gettext("Rebuilds the %{count} plays in the site.",
                    count: MapSet.size(@exported_codes)
                  )}
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
              exported: MapSet.size(@exported_codes),
              total: length(@plays)
            )}
          </p>

          <div :if={@plays != []} class="divide-y divide-base-200">
            <label
              :for={play <- @plays}
              id={"play-#{play.id}"}
              class="flex cursor-pointer items-center gap-3 py-2"
            >
              <span class="min-w-0 flex-1">
                <span class="font-mono text-xs text-base-content/50">{play.code}</span>
                <span class="font-medium ml-2 truncate">{play.title}</span>
              </span>
              <span
                :if={play.id in [@exporting_play, @removing_play]}
                class="loading loading-spinner loading-xs text-base-content/50"
              />
              <%!-- On means in the site; flipping it adds or removes the play at once. --%>
              <input
                type="checkbox"
                role="switch"
                class="toggle toggle-success toggle-sm"
                aria-label={gettext("In the site: %{title}", title: play.title)}
                checked={
                  (MapSet.member?(@exported_codes, play.code) or @exporting_play == play.id) and
                    @removing_play != play.id
                }
                disabled={@generating || @exporting_play || @removing_play}
                phx-click="toggle_play"
                phx-value-id={play.id}
                phx-value-code={play.code}
              />
            </label>
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
          <div :if={@gen_result} class="stats stats-horizontal shadow mt-2">
            <div class="stat">
              <div class="stat-title">{gettext("Plays")}</div>
              <div class="stat-value text-lg">{@gen_result.plays}</div>
            </div>
            <div class="stat">
              <div class="stat-title">{gettext("Total Size")}</div>
              <div class="stat-value text-lg">{format_size(@gen_result.size)}</div>
            </div>
            <div class="stat">
              <div class="stat-title">{gettext("Output")}</div>
              <div class="stat-value text-lg font-mono text-sm">{@gen_result.output_dir}/</div>
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
            <%!-- Deploy button --%>
            <button
              :if={@github_repo != ""}
              phx-click="deploy"
              class="btn btn-secondary"
              disabled={@deploying}
            >
              <span :if={@deploying} class="loading loading-spinner loading-sm"></span>
              {if @deploying, do: gettext("Deploying..."), else: gettext("Deploy to GitHub Pages")}
            </button>

            <%!-- Download zip --%>
            <button phx-click="download_zip" class="btn btn-outline" disabled={@deploying}>
              {gettext("Download .zip")}
            </button>
          </div>
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
          <p class="text-xs text-base-content/50 mt-1">
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

  # An existing site is rebuilt as it stands; with none, every complete play goes in.
  defp rebuild_codes(exported_codes) do
    case MapSet.to_list(exported_codes) do
      [] -> nil
      codes -> codes
    end
  end

  defp app_version do
    case :application.get_key(:playcode, :vsn) do
      {:ok, vsn} -> List.to_string(vsn)
      _ -> "1.0"
    end
  end

  defp format_size(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_size(bytes) when bytes < 1_048_576, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_size(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp create_zip(source_dir, zip_path) do
    files =
      source_dir
      |> Path.join("**/*")
      |> Path.wildcard()
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(fn path ->
        relative = Path.relative_to(path, source_dir)
        {String.to_charlist(relative), File.read!(path)}
      end)

    case :zip.create(String.to_charlist(zip_path), files) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
