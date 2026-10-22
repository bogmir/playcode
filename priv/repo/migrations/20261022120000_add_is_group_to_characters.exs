defmodule Playcode.Repo.Migrations.AddIsGroupToCharacters do
  @moduledoc """
  A character that is a group, TEI's `castItem ana="grupo"`: soldiers, servants, or,
  hidden as well (`ana="grupo oculto"`), speakers a speech names together, Hamlet's
  `#Hor_Mar_Bar`. `characters` has its `play_row_changed()` trigger; a column needs
  nothing.
  """
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :is_group, :boolean, default: false, null: false
    end
  end
end
