defmodule Playcode.Repo.Migrations.AddRevisionsToPlays do
  @moduledoc """
  The file's revision history, `teiHeader/revisionDesc/change`: who revised the TEI and
  when, one change in 351 of the production files. Read on import, written back on
  export, shown on the play's admin page (`Catalogue.Revision`). A column of `plays`, so its
  trigger already moves `content_version`.
  """
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :revisions, :jsonb, null: false, default: fragment("'[]'::jsonb")
    end
  end
end
