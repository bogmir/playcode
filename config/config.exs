# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :playcode,
  ecto_repos: [Playcode.Repo],
  generators: [timestamp_type: :utc_datetime]

config :playcode, PlaycodeWeb.Gettext,
  default_locale: "es",
  locales: ~w(es en)

# .ndjson has no registered MIME type by default; the FileMaker sync upload
# (lib/playcode_web/live/admin/filemaker_sync_live.ex) needs it for allow_upload's
# accept list.
config :mime, :types, %{
  "application/x-ndjson" => ["ndjson"]
}

# Configure the endpoint
config :playcode, PlaycodeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PlaycodeWeb.ErrorHTML, json: PlaycodeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Playcode.PubSub,
  live_view: [signing_salt: "HIhLQD3H"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :playcode, Playcode.Mailer, adapter: Swoosh.Adapters.Local

# A long play takes over a minute to print on one shared CPU, and with one Chrome session
# the next PDF waits its turn. The defaults (5 seconds each) failed the median play.
# Export.PdfCache bounds how many renders wait.
config :playcode, ChromicPDF,
  session_pool: [timeout: :timer.minutes(5), checkout_timeout: :timer.minutes(10)]

config :playcode, :place_authority, Playcode.Places.Authority.Wikidata

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  playcode: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  playcode: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# OpenTelemetry
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
