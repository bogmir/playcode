defmodule Playcode.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Set up OpenTelemetry instrumentation
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:playcode, :repo])

    # ETS table for rate limiting (used by PlaycodeWeb.RateLimit)
    :ets.new(:playcode_rate_limit, [:set, :public, :named_table])

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Playcode.Supervisor]
    Supervisor.start_link(children(), opts)
  end

  @doc """
  The supervision tree, in start order.

  `Playcode.Accounts.AdminBootstrap` must come after `PlaycodeWeb.Endpoint`: it
  builds the accept-invite URL with `PlaycodeWeb.Endpoint.url/0`, which raises
  until the endpoint has stored its persistent term. Because the reconciler is
  a `Task`, starting it earlier is a race it usually wins — but losing it
  creates the invited admins and then swallows the mail that carries their
  only way in. Ordered after the endpoint, there is no race to lose.
  """
  def children do
    [
      PlaycodeWeb.Telemetry,
      Playcode.Repo,
      {DNSCluster, query: Application.get_env(:playcode, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Playcode.PubSub},
      # The admin's static site: one process writes and ships it, its jobs run as tasks.
      {Task.Supervisor, name: Playcode.Export.SiteBuilder.Tasks},
      Playcode.Export.SiteBuilder,
      # Tells the export pages when a play changes, as soon as the edit commits.
      Playcode.Export.PlayChangeListener,
      # Start a worker by calling: Playcode.Worker.start_link(arg)
      # {Playcode.Worker, arg},
      # PDF generation via headless Chrome
      {ChromicPDF, Application.get_env(:playcode, ChromicPDF, [])},
      # Each play's PDF, rendered once per version; renders run as tasks.
      {Task.Supervisor, name: Playcode.Export.PdfCache.Tasks},
      Playcode.Export.PdfCache,
      # Start to serve requests, typically the last entry
      PlaycodeWeb.Endpoint,
      Playcode.Accounts.AdminBootstrap
    ]
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PlaycodeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
