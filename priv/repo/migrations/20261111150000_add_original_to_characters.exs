defmodule Playcode.Repo.Migrations.AddOriginalToCharacters do
  @moduledoc """
  A researcher's correction of which original character a translation's character goes
  with (problem 5, step 3): the original character's `xml:id`, which survives the
  original's re-import, or "no original". An uncorrected character is paired by rule at
  every comparison. `characters` has its `play_row_changed()` trigger; a column needs
  nothing.
  """
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :original_xml_id, :string
      add :no_original, :boolean, default: false, null: false
    end
  end
end
