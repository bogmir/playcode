defmodule Playcode.Repo.Migrations.IndexPlayNotesRangeEnd do
  @moduledoc """
  `play_notes.range_end_id` (20261108130000) is nilified when its line is deleted, so every
  element deleted by a re-import or a purge looked for the notes reaching it across the whole
  table: 380 ms against 43 ms with this index for 1,000 elements on dev's 5,117 notes (the
  review of problem 2, 2026-11-08). `element_id` has had its index from the start.
  """
  use Ecto.Migration

  def change, do: create(index(:play_notes, [:range_end_id]))
end
