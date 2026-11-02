defmodule Playcode.Repo.Migrations.AddTeamNoteToPlays do
  @moduledoc """
  A team note on a play (question 58): a text only staff read, in the play form, never
  printed and never written to the TEI file. Its edits move no `content_version`
  (20261102130000_team_note_moves_no_play).
  """
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :team_note, :text
    end
  end
end
