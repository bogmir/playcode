defmodule Playcode.Repo.Migrations.IdentifiersCountedOnExport do
  @moduledoc """
  Problem 2 (docs/superpowers/specs/2026-11-08-identifiers-on-export-design.md): a line's
  identifier is counted on every export, not stored. A variant's `to` named a line by the
  identifier its file gave it; it now names the line's row, `range_end_id`, resolved here
  through the identifier before `line_id` goes. A `to` naming no line of its play (four in
  the corpus, `#…-0000`) resolves to nothing. `play_notes` and `play_elements` have their
  `play_row_changed()` triggers already.
  """
  use Ecto.Migration

  def up do
    alter table(:play_notes) do
      add :range_end_id, references(:play_elements, type: :binary_id, on_delete: :nilify_all)
    end

    execute """
    UPDATE play_notes n SET range_end_id = e.id
    FROM play_elements e
    WHERE n.range_end IS NOT NULL AND e.play_id = n.play_id AND e.line_id IS NOT NULL
      AND e.line_id = ltrim(n.range_end, '#')
    """

    alter table(:play_notes), do: remove(:range_end)
    alter table(:play_elements), do: remove(:line_id)
  end

  def down do
    alter table(:play_elements), do: add(:line_id, :string)
    alter table(:play_notes), do: add(:range_end, :string)
    alter table(:play_notes), do: remove(:range_end_id)
  end
end
