import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/playcode start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :playcode, PlaycodeWeb.Endpoint, server: true
end

config :playcode, PlaycodeWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

config :playcode,
  env: config_env(),
  admin_emails:
    System.get_env("ADMIN_EMAILS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

# Where Deploy pushes the static site, and the server it then tells to publish it
# (StaticSite.Deployer). Fly secrets in production; each may be unset.
config :playcode, :static_site_deploy,
  repo: System.get_env("STATIC_SITE_REPO"),
  github_token: System.get_env("GITHUB_DEPLOY_TOKEN"),
  publish_url: System.get_env("STATIC_SITE_PUBLISH_URL"),
  publish_token: System.get_env("STATIC_SITE_PUBLISH_TOKEN")

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :playcode, Playcode.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6,
    timeout: 60_000

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host =
    System.get_env("PHX_HOST") ||
      System.get_env("RENDER_EXTERNAL_HOSTNAME") ||
      "example.com"

  config :playcode, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :playcode, PlaycodeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :playcode, ChromicPDF,
    no_sandbox: true,
    # Chrome's stderr here is a desktop browser discovering it is on a server:
    # no D-Bus, no UPower, no Google push service. None of it touches rendering,
    # and it drowns the request log. Real failures still reach us either way —
    # print_to_pdf/2 returns {:error, _} to Playcode.Export.Pdf. Set to false to
    # debug Chrome itself. config/test.exs deliberately keeps it false, because a
    # failing PDF test is exactly when that output is worth having.
    discard_stderr: true,
    chrome_args: "--disable-dev-shm-usage",
    session_pool: [size: 1, timeout: 60_000, checkout_timeout: 60_000, init_timeout: 30_000]

  otel_traces_exporter =
    System.get_env("OTEL_TRACES_EXPORTER", "none")
    |> String.downcase()

  otel_traces_exporter_config =
    case otel_traces_exporter do
      "stdout" -> {:otel_exporter_stdout, []}
      "otlp" -> :otlp
      _ -> :none
    end

  config :opentelemetry,
    traces_exporter: otel_traces_exporter_config

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :playcode, PlaycodeWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :playcode, PlaycodeWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Mailer — SMTP via any provider (Postmark, Mailgun, SendGrid, etc.)
  # If SMTP_HOST is not set, emails are silently dropped (Local adapter).
  # Optional env vars: SMTP_HOST, SMTP_PORT (default 587), SMTP_USERNAME,
  #                    SMTP_PASSWORD, MAIL_FROM (default noreply@emothe.uv.es)
  if smtp_host = System.get_env("SMTP_HOST") do
    config :playcode, Playcode.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: String.to_integer(System.get_env("SMTP_PORT", "587")),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      tls: :always,
      auth: :always,
      no_mx_lookups: true,
      # gen_smtp defaults tls_options to versions [tlsv1, tlsv1.1, tlsv1.2].
      # OTP 28 dropped TLS 1.0 and 1.1, so :ssl rejects that list and every
      # STARTTLS attempt fails with {:temporary_failure, host, :tls_failed} —
      # which Swoosh reports as an error nobody was reading. Naming the
      # supported versions also lets us verify the relay's certificate against
      # the OS trust store the image already installs.
      tls_options: [
        versions: [:"tlsv1.2", :"tlsv1.3"],
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: to_charlist(smtp_host),
        depth: 3
      ]
  end

  config :playcode, :mail_from, System.get_env("MAIL_FROM", "noreply@emothe.uv.es")
end
