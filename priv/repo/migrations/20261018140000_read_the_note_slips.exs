defmodule Playcode.Repo.Migrations.ReadTheNoteSlips do
  @moduledoc """
  Two notes carry a slip for a type (question 17): La tragedia española's note on
  "Belona" is typed "video", a translator's, and Marta la piadosa's one
  "nota_editor_digital", a digital editor's. The importer reads them as what they are
  now; this rewrites the notes already stored (one of each in dev), so readers see their
  label before the plays are re-imported.

  Not reversible: which rows were spelled the other way is not recorded. The triggers of
  migration 20261005120000 move the plays' `content_version`.
  """
  use Ecto.Migration

  def up do
    execute("UPDATE play_notes SET type = 'traductor' WHERE type = 'video'")
    execute("UPDATE play_notes SET type = 'editor_digital' WHERE type = 'nota_editor_digital'")
  end

  def down, do: :ok
end
