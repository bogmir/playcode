defmodule Playcode.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :playcode,
    adapter: Ecto.Adapters.Postgres
end
