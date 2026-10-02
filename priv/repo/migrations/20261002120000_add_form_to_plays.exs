defmodule Playcode.Repo.Migrations.AddFormToPlays do
  use Ecto.Migration

  def change do
    alter table(:plays) do
      # nil means automatic: Playcode.Catalogue.Play.form/1 derives it from is_verse.
      add :form, :string
    end
  end
end
