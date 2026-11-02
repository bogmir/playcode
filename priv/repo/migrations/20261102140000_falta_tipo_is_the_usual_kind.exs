defmodule Playcode.Repo.Migrations.FaltaTipoIsTheUsualKind do
  @moduledoc """
  Question 17: a note whose kind was never chosen (`falta_tipo`) is the play's usual
  kind, a translator's note in a translation and an editor's elsewhere, as the TEI import
  now reads one. The notes already stored change here; `play_notes`' trigger moves their
  plays' `content_version`, so Generate rebuilds them. The files keep `falta_tipo` until
  Playcode's export is put in their place; there is no way back to it.
  """
  use Ecto.Migration

  def up do
    execute """
    UPDATE play_notes AS n
       SET type = CASE WHEN p.relationship_type = 'traduccion' THEN 'traductor' ELSE 'editor' END
      FROM plays AS p
     WHERE p.id = n.play_id AND n.type = 'falta_tipo'
    """
  end

  def down, do: :ok
end
