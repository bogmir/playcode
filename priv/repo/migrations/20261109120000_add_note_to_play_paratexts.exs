defmodule Playcode.Repo.Migrations.AddNoteToPlayParatexts do
  use Ecto.Migration

  # A paratext's closing <note> (the researcher's review of 0756, 2026-11-09): 34 in the
  # corpus, dropped on import until now. play_paratexts already has play_row_changed().
  def change do
    alter table(:play_paratexts) do
      add :note, :text
    end
  end
end
