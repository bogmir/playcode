defmodule Playcode.Repo.Migrations.AddNumberingToPlays do
  @moduledoc """
  A play's numbering rule: what is numbered (`V`, `VP`, `VL`, `S`), where the count starts
  again (`never`, `act`, `scene`), and whether its numbers are typed by hand (Manual, never
  recounted). Every play stored before this is Manual, so no save recounts a play nobody has
  looked at; `Playcode.Release.settle_numbering/1` then detects each one's rule. A new play
  is not Manual. The plays triggers compare whole rows, so a change moves `content_version`.
  """
  use Ecto.Migration

  def change do
    alter table(:plays) do
      add :numbering_type, :string, null: false, default: "V"
      add :numbering_restart, :string, null: false, default: "never"
      add :numbering_manual, :boolean, null: false, default: true
    end

    execute "ALTER TABLE plays ALTER COLUMN numbering_manual SET DEFAULT false",
            "ALTER TABLE plays ALTER COLUMN numbering_manual SET DEFAULT true"
  end
end
