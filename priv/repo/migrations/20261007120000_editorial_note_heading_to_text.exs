defmodule Playcode.Repo.Migrations.EditorialNoteHeadingToText do
  use Ecto.Migration

  # EMOTHE0113 (Tartuffe) heads a front-matter epistle with 302 characters.
  def change do
    alter table(:play_editorial_notes) do
      modify :heading, :text, from: :string
    end
  end
end
