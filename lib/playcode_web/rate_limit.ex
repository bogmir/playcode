defmodule PlaycodeWeb.RateLimit do
  @moduledoc """
  Simple fixed-window rate limiter backed by ETS.

  Best-effort (not perfectly atomic under concurrent load), which is
  acceptable for auth-endpoint protection — the goal is blocking bots,
  not enforcing a hard cap to the exact request.

  `create_table/0` makes the ETS table `:playcode_rate_limit`, from
  `Playcode.Application.start/2`, and sweeps it every minute.
  """

  @table :playcode_rate_limit
  @sweep_every 60_000

  @doc "Creates the table and sweeps expired counters from it every minute."
  @spec create_table() :: :ok
  def create_table do
    :ets.new(@table, [:set, :public, :named_table])
    {:ok, _} = :timer.apply_interval(@sweep_every, __MODULE__, :sweep, [])
    :ok
  end

  @doc """
  Checks the rate for `key`.

  Returns `:ok` if under the limit, or `{:error, :rate_limited}` if the
  limit has been reached within the current window.

  - `limit` — max requests allowed per window
  - `window_ms` — window size in milliseconds
  """
  @spec check_rate(String.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :rate_limited}
  def check_rate(key, limit, window_ms) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, count, expires_at}] when now < expires_at ->
        if count >= limit do
          {:error, :rate_limited}
        else
          # The default row stands in for one swept or reset since the lookup.
          :ets.update_counter(@table, key, {2, 1}, {key, 0, now + window_ms})
          :ok
        end

      _ ->
        :ets.insert(@table, {key, 1, now + window_ms})
        :ok
    end
  end

  @doc """
  Clears the counter for `key`. Called after a successful login so only
  failures consume the budget.
  """
  @spec reset(String.t()) :: :ok
  def reset(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc "Deletes every counter whose window has passed; returns how many."
  @spec sweep() :: non_neg_integer()
  def sweep do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
  end
end
