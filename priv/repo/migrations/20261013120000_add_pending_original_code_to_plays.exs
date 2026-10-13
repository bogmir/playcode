defmodule Playcode.Repo.Migrations.AddPendingOriginalCodeToPlays do
  @moduledoc """
  The short code of the original a translation's TEI file named
  (`notesStmt/relatedItem[@type="original"]`) while no play has it yet. Written by the
  TEI import, cleared by `Catalogue.link_waiting_translations/0` once the play has an
  original, so a translation imported before its original is linked when it arrives.
  """
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :pending_original_code, :string
    end
  end
end
