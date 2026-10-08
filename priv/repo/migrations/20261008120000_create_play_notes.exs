defmodule Playcode.Repo.Migrations.CreatePlayNotes do
  @moduledoc """
  In-text notes: an editor's or translator's gloss on one word of a line, a speaker label
  or a division heading, stored apart from that text and anchored by `offset`. Spec:
  docs/superpowers/specs/2026-10-08-in-text-notes-design.md.

  A note hangs on exactly one element or division, and goes with it.
  """
  use Ecto.Migration

  def change do
    create table(:play_notes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :element_id, references(:play_elements, type: :binary_id, on_delete: :delete_all)
      add :division_id, references(:play_divisions, type: :binary_id, on_delete: :delete_all)
      add :offset, :integer, null: false
      add :position, :integer, null: false, default: 0
      add :n, :string
      add :type, :string
      add :term, :text
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:play_notes, :one_anchor,
             check: "(element_id IS NULL) <> (division_id IS NULL)"
           )

    create constraint(:play_notes, :offset_not_negative, check: ~s("offset" >= 0))
    create index(:play_notes, [:element_id, :offset, :position])
    create index(:play_notes, [:division_id, :offset, :position])
    create index(:play_notes, [:play_id])

    execute "CREATE TRIGGER play_notes_touch_play AFTER INSERT OR UPDATE OR DELETE ON play_notes FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
            "DROP TRIGGER play_notes_touch_play ON play_notes"
  end
end
