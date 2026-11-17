# `:slow` tests are excluded by default; run them with `mix test --include slow`.
# Tagged: test/playcode/export/tei_validator_test.exs (xmllint against the TEI
# RelaxNG schema, ~20s) and the full-corpus sweep in test/playcode/roundtrip_test.exs
# (every tracked fixture plus test/fixtures/tei_files/ when present, a few minutes).
# `:browser` tests drive headless Chrome over a generated site, which CI has not got:
# `mix test --include browser test/playcode/export/static_site_browser_test.exs`.
ExUnit.start(exclude: [:slow, :browser])
Ecto.Adapters.SQL.Sandbox.mode(Playcode.Repo, :manual)
