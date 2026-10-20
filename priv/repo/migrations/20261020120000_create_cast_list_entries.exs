defmodule Playcode.Repo.Migrations.CreateCastListEntries do
  @moduledoc """
  A cast list's lines (`cast_list_entries`): each holds what its list prints, and names the
  character it declares, or none. A character's name, description and place become its
  first entry's.

  The data, in this order: an `elenco` division for every play with characters and none;
  one position sequence for each play's top-level paratexts and divisions, in the order the
  export wrote them until now (front paratexts, the cast list, the scene of the action, the
  body, the paratexts after the text); an entry for every character in its play's first
  cast list. A play with several lists gets every entry in the first: re-importing its file
  puts each where it belongs. `down` leaves the positions as they are.
  """
  use Ecto.Migration

  def up do
    create table(:cast_list_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false

      add :cast_list_id, references(:play_divisions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :character_id, references(:characters, type: :binary_id, on_delete: :delete_all)
      add :name, :text, null: false
      add :description, :text
      add :group_heading, :text
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:cast_list_entries, [:cast_list_id, :position])
    create index(:cast_list_entries, [:character_id])
    create index(:cast_list_entries, [:play_id])

    execute """
    CREATE TRIGGER cast_list_entries_touch_play
      AFTER INSERT OR UPDATE OR DELETE ON cast_list_entries
      FOR EACH ROW EXECUTE FUNCTION play_row_changed()
    """

    execute """
    INSERT INTO play_divisions (id, play_id, type, position, inserted_at, updated_at)
    SELECT gen_random_uuid(), p.id, 'elenco', 0, now(), now()
      FROM plays p
     WHERE EXISTS (SELECT 1 FROM characters c WHERE c.play_id = p.id)
       AND NOT EXISTS (SELECT 1 FROM play_divisions d WHERE d.play_id = p.id AND d.type = 'elenco')
    """

    execute """
    CREATE TEMP TABLE outline_rank AS
    SELECT id, item, row_number() OVER (PARTITION BY play_id ORDER BY grp, position, id) - 1 AS pos
      FROM (
        SELECT id, play_id, 'paratext' AS item, position,
               CASE WHEN back THEN 4 WHEN kind = 'lugar_accion' THEN 2 ELSE 0 END AS grp
          FROM play_paratexts
        UNION ALL
        SELECT id, play_id, 'division', position, CASE WHEN type = 'elenco' THEN 1 ELSE 3 END
          FROM play_divisions
         WHERE parent_id IS NULL
      ) items
    """

    execute """
    UPDATE play_paratexts p SET position = r.pos
      FROM outline_rank r WHERE r.item = 'paratext' AND r.id = p.id
    """

    execute """
    UPDATE play_divisions d SET position = r.pos
      FROM outline_rank r WHERE r.item = 'division' AND r.id = d.id
    """

    execute "DROP TABLE outline_rank"

    execute """
    INSERT INTO cast_list_entries
      (id, play_id, cast_list_id, character_id, name, description, position, inserted_at, updated_at)
    SELECT gen_random_uuid(), c.play_id, l.id, c.id, c.name, c.description, c.position, now(), now()
      FROM characters c
      JOIN LATERAL (
        SELECT d.id FROM play_divisions d
         WHERE d.play_id = c.play_id AND d.type = 'elenco'
         ORDER BY coalesce((SELECT a.position FROM play_divisions a WHERE a.id = d.parent_id),
                           d.position),
                  d.parent_id IS NOT NULL, d.position, d.id
         LIMIT 1
      ) l ON true
    """
  end

  def down do
    drop table(:cast_list_entries)
  end
end
