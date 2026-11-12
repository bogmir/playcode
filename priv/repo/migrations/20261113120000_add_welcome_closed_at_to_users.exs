defmodule Playcode.Repo.Migrations.AddWelcomeClosedAtToUsers do
  @moduledoc """
  When the user closed the play list's first-visit card. On the account, not in the
  browser, so it does not come back on another computer.
  """
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :welcome_closed_at, :utc_datetime
    end
  end
end
