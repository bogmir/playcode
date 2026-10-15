defmodule Playcode.Repo.Migrations.RenameEditorialNotesToParatexts do
  @moduledoc """
  `play_editorial_notes` is `play_paratexts`, and its `section_type` is `kind`: the
  glossary's words (CONTEXT.md). A renamed table keeps its `play_row_changed()` trigger;
  its indexes, keys and trigger are renamed too so `\\d play_paratexts` reads cleanly.
  Old activity-log rows follow, so the log names them by the new word.
  """
  use Ecto.Migration

  @renamed [
    {"INDEX", "play_editorial_notes_pkey", "play_paratexts_pkey"},
    {"INDEX", "play_editorial_notes_play_id_index", "play_paratexts_play_id_index"},
    {"INDEX", "play_editorial_notes_play_id_origin_index", "play_paratexts_play_id_origin_index"}
  ]

  def change do
    rename table(:play_editorial_notes), to: table(:play_paratexts)
    rename table(:play_paratexts), :section_type, to: :kind

    for {kind, old, new} <- @renamed do
      execute "ALTER #{kind} #{old} RENAME TO #{new}", "ALTER #{kind} #{new} RENAME TO #{old}"
    end

    execute "ALTER TABLE play_paratexts RENAME CONSTRAINT play_editorial_notes_play_id_fkey TO play_paratexts_play_id_fkey",
            "ALTER TABLE play_paratexts RENAME CONSTRAINT play_paratexts_play_id_fkey TO play_editorial_notes_play_id_fkey"

    execute "ALTER TRIGGER play_editorial_notes_touch_play ON play_paratexts RENAME TO play_paratexts_touch_play",
            "ALTER TRIGGER play_paratexts_touch_play ON play_paratexts RENAME TO play_editorial_notes_touch_play"

    execute "UPDATE activity_logs SET resource_type = 'paratext' WHERE resource_type = 'editorial_note'",
            "UPDATE activity_logs SET resource_type = 'editorial_note' WHERE resource_type = 'paratext'"
  end
end
