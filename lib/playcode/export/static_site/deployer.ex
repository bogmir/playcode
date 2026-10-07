defmodule Playcode.Export.StaticSite.Deployer do
  @moduledoc """
  Deploys a generated static site: pushes it to a git repository's `gh-pages` branch,
  then, when a publish URL is set, tells the server behind it to fetch that branch
  (`deploy/playcode-deploy.php` does it on emothe.uv.es).

  Its settings are the app's `:static_site_deploy`, read from the environment in
  config/runtime.exs; each may be unset:
    * `:repo` - where the export page deploys to (`STATIC_SITE_REPO`)
    * `:github_token` - pushes with it (`GITHUB_DEPLOY_TOKEN`); without it, git uses
      whatever credentials the machine has
    * `:publish_url`, `:publish_token` - the server to tell, and its key
      (`STATIC_SITE_PUBLISH_URL`, `STATIC_SITE_PUBLISH_TOKEN`)
  """

  require Logger

  @doc """
  Pushes the static site directory to `repo`, then has the publish server fetch it.

  ## Options
    * `:branch` - target branch (default: `"gh-pages"`)
    * `:message` - commit message (default: auto-generated with timestamp)
    * `:on_progress` - `fun(String.t()) -> :ok` callback for status updates

  Returns `{:ok, url}`, the published site's address (or the GitHub Pages one, with no
  publish server), or `{:error, reason}`.
  """
  def deploy(site_dir, repo, opts \\ []) do
    branch = opts[:branch] || "gh-pages"

    message =
      opts[:message] ||
        "Deploy EMOTHE static site — #{DateTime.utc_now() |> DateTime.to_iso8601()}"

    on_progress = opts[:on_progress] || fn _ -> :ok end
    settings = Application.get_env(:playcode, :static_site_deploy, [])

    with :ok <- validate_site_dir(site_dir),
         :ok <- validate_git_available(),
         {:ok, repo_url} <- resolve_repo_url(repo),
         :ok <- push(site_dir, repo_url, branch, message, settings[:github_token], on_progress) do
      publish(settings[:publish_url], settings[:publish_token], repo_url, on_progress)
    end
  end

  defp validate_site_dir(dir) do
    if File.exists?(Path.join(dir, "index.html")) do
      :ok
    else
      {:error, "No index.html found in #{dir}. Generate the site first."}
    end
  end

  defp validate_git_available do
    case System.cmd("git", ["--version"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      _ -> {:error, "git is not available on this system"}
    end
  end

  defp resolve_repo_url(repo) do
    cond do
      # Already a full URL; a local one (file://) or plain http only from config or tests
      String.starts_with?(repo, ["https://", "http://", "git@", "file://"]) ->
        {:ok, repo}

      # Short form: owner/repo
      String.contains?(repo, "/") and not String.contains?(repo, " ") ->
        {:ok, "https://github.com/#{repo}.git"}

      true ->
        {:error, "Invalid repository: #{repo}. Use 'owner/repo' or a full git URL."}
    end
  end

  defp push(site_dir, repo_url, branch, message, token, on_progress) do
    # Work in the site directory
    git_opts = [cd: site_dir, stderr_to_stdout: true, env: auth_env(repo_url, token)]

    steps = [
      {"Initializing git repository...", fn -> System.cmd("git", ["init"], git_opts) end},
      {"Configuring git...",
       fn ->
         System.cmd("git", ["config", "user.email", "playcode-deploy@noreply"], git_opts)
         System.cmd("git", ["config", "user.name", "EMOTHE Deploy"], git_opts)
       end},
      {"Staging files...", fn -> System.cmd("git", ["add", "-A"], git_opts) end},
      # Empty when nothing changed since the last deploy, whose .git the site keeps: a
      # retry after a failed push or publish must still push and publish.
      {"Creating commit...",
       fn -> System.cmd("git", ["commit", "--allow-empty", "-m", message], git_opts) end},
      {"Pushing to #{branch}...",
       fn ->
         System.cmd("git", ["push", "--force", repo_url, "HEAD:#{branch}"], git_opts)
       end}
    ]

    Enum.reduce_while(steps, :ok, fn {status, cmd_fn}, _acc ->
      on_progress.(status)

      case cmd_fn.() do
        {_output, 0} -> {:cont, :ok}
        {output, _code} -> {:halt, {:error, "Git error: " <> scrub(String.trim(output), token)}}
      end
    end)
  end

  # The token reaches git through its environment, as an HTTP header for this repository
  # only: never in the command line, which other processes can read, nor in a URL git
  # might print.
  defp auth_env(_repo_url, token) when token in [nil, ""], do: []

  defp auth_env(repo_url, token) do
    [
      {"GIT_CONFIG_COUNT", "1"},
      {"GIT_CONFIG_KEY_0", "http.#{repo_url}.extraheader"},
      {"GIT_CONFIG_VALUE_0", "Authorization: Basic " <> credentials(token)}
    ]
  end

  defp credentials(token), do: Base.encode64("x-access-token:" <> token)

  defp scrub(text, token) when token in [nil, ""], do: text

  defp scrub(text, token),
    do: text |> String.replace(token, "***") |> String.replace(credentials(token), "***")

  defp publish(nil, _token, repo_url, on_progress) do
    on_progress.("Deployed successfully!")
    {:ok, derive_pages_url(repo_url)}
  end

  # The server answers once it has the site in place, which takes as long as fetching it.
  defp publish(url, token, _repo_url, on_progress) do
    on_progress.("Publishing on #{URI.parse(url).host}...")

    options =
      [headers: [{"x-deploy-token", token || ""}], retry: false, receive_timeout: 300_000] ++
        Application.get_env(:playcode, :static_site_publish_req, [])

    case Req.post(url, options) do
      {:ok, %Req.Response{status: 200, body: %{"ok" => true, "target" => target}}} ->
        on_progress.("Deployed successfully!")
        {:ok, url |> URI.merge(target <> "/") |> URI.to_string()}

      {:ok, %Req.Response{body: %{"error" => error}}} ->
        {:error, "The server refused to publish: #{error}"}

      {:ok, %Req.Response{status: status}} ->
        {:error, "The server answered #{status} instead of publishing"}

      {:error, exception} ->
        {:error, "Could not reach the server to publish: #{Exception.message(exception)}"}
    end
  end

  defp derive_pages_url(repo_url) do
    # Extract owner/repo from URL
    cond do
      String.contains?(repo_url, "github.com") ->
        repo_url
        |> String.replace(~r{^https://github\.com/}, "")
        |> String.replace(~r{^git@github\.com:}, "")
        |> String.replace(~r{\.git$}, "")
        |> then(fn path ->
          case String.split(path, "/") do
            [owner, repo] -> "https://#{owner}.github.io/#{repo}/"
            _ -> repo_url
          end
        end)

      true ->
        repo_url
    end
  end
end
