defmodule Playcode.Repo.Migrations.AddEditionNotesToPlays do
  @moduledoc """
  The notes on the edition, `fileDesc/notesStmt/note`, one text each: 15 in 14 of the
  production files. Read on import, written back on export, edited in the play form.
  A column of `plays`, so its trigger already moves `content_version`.
  """
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :edition_notes, {:array, :text}, null: false, default: []
    end
  end
end
