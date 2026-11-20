defmodule Playcode.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # OpenTelemetry instrumentation, only when the spans go somewhere (dev's stdout,
    # production's OTEL_TRACES_EXPORTER): OpentelemetryEcto alone costs every query about
    # 55 µs, a sixth of a TEI import.
    if Application.get_env(:opentelemetry, :traces_exporter, :none) != :none do
      OpentelemetryBandit.setup()
      OpentelemetryPhoenix.setup(adapter: :bandit)
      OpentelemetryEcto.setup([:playcode, :repo])
    end

    PlaycodeWeb.RateLimit.create_table()

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
      {ChromicPDF, Application.get_env(:playcode, ChromicPDF, [])},
      # Each play's PDF, rendered once per version; renders run as tasks.
      {Task.Supervisor, name: Playcode.Export.PdfCache.Tasks},
      Playcode.Export.PdfCache,
      PlaycodeWeb.Endpoint,
      Playcode.Accounts.AdminBootstrap
    ]
  end

  @impl true
  def config_change(changed, _new, removed) do
    PlaycodeWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
