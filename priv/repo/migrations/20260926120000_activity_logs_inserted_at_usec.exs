defmodule Playcode.Repo.Migrations.ActivityLogsInsertedAtUsec do
  use Ecto.Migration

  # Second precision left entries logged in the same second in random UUID
  # order. Widening a timestamp's precision does not rewrite the table.
  def change do
    alter table(:activity_logs) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
