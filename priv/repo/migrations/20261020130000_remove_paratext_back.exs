defmodule Playcode.Repo.Migrations.RemoveParatextBack do
  @moduledoc """
  A paratext's side of the text is its place in the outline now: after the last division
  of the text is after the text (`Playcode.Outline.placement/1`). The cast list entries'
  migration ranked every paratext after the text by this column, so nothing it said is
  lost. A rollback brings the column back false throughout.
  """
  use Ecto.Migration

  def change do
    alter table(:play_paratexts) do
      remove :back, :boolean, default: false, null: false
    end
  end
end
