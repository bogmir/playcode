defmodule Playcode.Repo.Migrations.CastListIntroAndNote do
  @moduledoc """
  What a file says beside a cast list: the line before it that introduces it (24 corpus
  files, "Hablan en ella las personas siguientes:") and the note after it (55: the
  walk-on parts, the scene in prose, the editor's remarks on the list). Found by the
  2026-11-06 check against FileMaker's names; every one was lost on import. Only a cast
  list (`elenco`) holds them. The plays trigger on `play_divisions` moves
  `content_version` when they change.
  """
  use Ecto.Migration

  def change do
    alter table(:play_divisions) do
      add :intro, :text
      add :note, :text
    end
  end
end
