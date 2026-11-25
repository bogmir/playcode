defmodule Playcode.Repo.Migrations.SplitPlayCode do
  @moduledoc """
  A play's code becomes three columns, `library` (EMOTHE, AL for ARTELOPE, TEST), `number`
  (FileMaker's title id for EMOTHE) and `slug` (the readable name), and `code` a column
  Postgres generates from them: the number padded to four digits, never cut, so 12345 stays
  whole. `emothe_id` held the code's number or nothing, so it goes; the TEI export writes
  `<idno type="LIBRARY">` from the columns. A code that is no library and number (only
  dev's hand-made test plays) moves to TEST with a number of its own, as a draft. The plays triggers
  leave `code` out of their WHEN clause: a BEFORE trigger sees no generated value yet, and
  the three columns carry every change to it.
  """
  use Ecto.Migration

  @ignored "content_version,content_txid,updated_at,team_note,content_changed_at"
  @code_pattern "^(EMOTHE|AL|TEST)([0-9]+)(?:_([A-Za-z0-9]+))?$"

  def up do
    alter table(:plays) do
      add :library, :string
      add :number, :integer
      add :slug, :string
    end

    execute """
    UPDATE plays SET library = m[1], number = m[2]::integer, slug = m[3]
      FROM (SELECT id, regexp_match(code, '#{@code_pattern}') AS m FROM plays) parts
     WHERE parts.id = plays.id AND parts.m IS NOT NULL
    """

    execute """
    UPDATE plays SET library = 'TEST', number = odd.n, is_complete = false,
                     slug = nullif(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'), '')
      FROM (SELECT id, row_number() OVER (ORDER BY code)
                       + coalesce((SELECT max(number) FROM plays WHERE library = 'TEST'), 0) AS n
              FROM plays WHERE library IS NULL) odd
     WHERE odd.id = plays.id
    """

    recreate_triggers("#{@ignored},code")

    alter table(:plays) do
      remove :emothe_id
      remove :code
      modify :library, :string, null: false
      modify :number, :integer, null: false
    end

    execute """
    ALTER TABLE plays ADD COLUMN code text GENERATED ALWAYS AS (
      library || lpad(number::text, greatest(4, length(number::text)), '0')
              || coalesce('_' || slug, '')
    ) STORED
    """

    create unique_index(:plays, [:code])
    create unique_index(:plays, [:library, :number])
    create constraint(:plays, :library_known, check: "library IN ('EMOTHE', 'AL', 'TEST')")
    create constraint(:plays, :number_positive, check: "number > 0")
    create constraint(:plays, :slug_plain, check: "slug ~ '^[A-Za-z0-9]+$'")
    create constraint(:plays, :test_never_complete, check: "library <> 'TEST' OR NOT is_complete")
  end

  def down do
    drop constraint(:plays, :test_never_complete)
    drop constraint(:plays, :slug_plain)
    drop constraint(:plays, :number_positive)
    drop constraint(:plays, :library_known)
    drop unique_index(:plays, [:library, :number])

    execute "ALTER TABLE plays RENAME COLUMN code TO generated_code"

    alter table(:plays) do
      add :code, :string
      add :emothe_id, :string
    end

    execute "UPDATE plays SET code = generated_code"

    execute """
    UPDATE plays SET emothe_id = lpad(number::text, greatest(4, length(number::text)), '0')
     WHERE library = 'EMOTHE'
    """

    alter table(:plays) do
      remove :generated_code
      remove :library
      remove :number
      remove :slug
      modify :code, :string, null: false
    end

    create unique_index(:plays, [:code])
    recreate_triggers(@ignored)
  end

  defp recreate_triggers(ignored) do
    changed = """
    to_jsonb(OLD) - '{#{ignored}}'::text[]
      IS DISTINCT FROM to_jsonb(NEW) - '{#{ignored}}'::text[]
    """

    execute "DROP TRIGGER plays_bump ON plays"
    execute "DROP TRIGGER plays_touch_relatives ON plays"

    execute """
    CREATE TRIGGER plays_bump BEFORE UPDATE ON plays
      FOR EACH ROW WHEN (#{changed}) EXECUTE FUNCTION play_changed()
    """

    execute """
    CREATE TRIGGER plays_touch_relatives AFTER UPDATE ON plays
      FOR EACH ROW WHEN (#{changed}) EXECUTE FUNCTION play_changed()
    """
  end
end
