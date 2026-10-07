import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :playcode, Playcode.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "playcode_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :playcode, PlaycodeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "3ySNf4PvdqVIMzyo9+6ciUOSYNucw+BOVzy5MYaX4ZS07TB3wxOf10eaXAqYOTaZ",
  server: false

# In test we don't send emails
config :playcode, Playcode.Mailer, adapter: Swoosh.Adapters.Test

# No test touches the network.
config :playcode, :place_authority, Playcode.Places.Authority.Stub

# Cheapest bcrypt work factor. Every auth test hashes a password, and 12 rounds
# cost ~480ms each; 4 rounds cost ~4ms and prove the same behaviour.
config :bcrypt_elixir, log_rounds: 4

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Disable OpenTelemetry span export during tests
config :opentelemetry,
  traces_exporter: :none

config :playcode, ChromicPDF,
  on_demand: true,
  no_sandbox: true,
  discard_stderr: false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Pin ADMIN_EMAILS empty so a stray environment variable cannot alter tests
config :playcode, admin_emails: []

# The export page builds here, never into the developer's own _site/
config :playcode, :static_site_dir, Path.join(System.tmp_dir!(), "playcode-test-site")

# The publish server Deploy calls is a Req.Test stub in test.
config :playcode, :static_site_publish_req, plug: {Req.Test, Playcode.Export.StaticSite.Deployer}
