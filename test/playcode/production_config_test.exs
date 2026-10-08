defmodule Playcode.ProductionConfigTest do
  @moduledoc """
  The settings the release boots with: `config/config.exs` (and `prod.exs`), then
  `config/runtime.exs`, both read for `:prod` as the release reads them. Not async:
  `runtime.exs` reads the environment variables this test sets.
  """
  use ExUnit.Case, async: false

  @required %{
    "DATABASE_URL" => "ecto://user:pass@localhost/playcode",
    "SECRET_KEY_BASE" => String.duplicate("x", 64)
  }

  setup do
    saved = Map.new(@required, fn {name, _} -> {name, System.get_env(name)} end)
    System.put_env(@required)

    on_exit(fn ->
      for {name, value} <- saved,
          do: if(value, do: System.put_env(name, value), else: System.delete_env(name))
    end)
  end

  defp prod_config do
    Config.Reader.merge(
      Config.Reader.read!("config/config.exs", env: :prod),
      Config.Reader.read!("config/runtime.exs", env: :prod)
    )
  end

  # A Chrome kept running for the app's whole life left a renderer behind for every
  # session start that timed out. On a machine throttled to 6.25% of a core the starts
  # timed out every 30 seconds, and 89 Chrome processes filled its memory and swap
  # (2026-10-08). Started per print, Chrome and whatever it leaks end with the print.
  test "Chrome runs only while a PDF prints, and a print never retries its start" do
    chrome = prod_config()[:playcode][ChromicPDF]
    pool = chrome[:session_pool]

    assert chrome[:on_demand]
    # A print waits for its Chrome no longer than the start may take, so a slow start
    # fails the print instead of spawning a second session in the same browser.
    assert pool[:checkout_timeout] <= pool[:init_timeout]
  end

  # runtime.exs once set 60 seconds here and silently undid config.exs's five minutes.
  test "a print may take the five minutes the longest play needs on a throttled machine" do
    assert prod_config()[:playcode][ChromicPDF][:session_pool][:timeout] >= :timer.minutes(5)
  end
end
