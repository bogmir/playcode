defmodule Playcode.Repo.Migrations.AddCanon60EditorToPlaySources do
  @moduledoc """
  Who edited the printed source for CANON 60, `sourceDesc/bibl/editor[@role="canon60"]`:
  57 corpus files name one beside the source's own editor.
  """
  use Ecto.Migration

  def change do
    alter table(:play_sources) do
      add :canon60_editor, :string
    end
  end
end
