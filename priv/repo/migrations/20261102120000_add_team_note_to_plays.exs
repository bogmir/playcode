defmodule Playcode.Repo.Migrations.AddTeamNoteToPlays do
  @moduledoc """
  A team note on a play (question 58): a text only staff read, in the play form, never
  printed and never written to the TEI file. Like any column of `plays` it moves
  `content_version`, so editing it rebuilds the play's static pages unchanged.
  """
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :team_note, :text
    end
  end
end
