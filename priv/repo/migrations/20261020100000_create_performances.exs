defmodule Playcode.Repo.Migrations.CreatePerformances do
  @moduledoc """
  A play's historical performances (S5): who staged it, when, where, with which cast, and
  the source that says so. Four tables: `play_performances`, its `performance_cast`, and
  the corpus-wide `performance_companies` and `performance_actors` they name. Spec:
  docs/superpowers/specs/2026-10-19-s5-performances-design.md.

  Performances show on the play's pages, so everything that reaches them moves
  `plays.content_version` (migration 20261005120000):

    * `play_performances` has the usual `play_row_changed()` line;
    * `performance_cast_changed()` touches the play of a cast row's performance;
    * `performance_name_changed()` touches the plays whose performances name a company or an
      actor that was renamed (`TG_ARGV[0]` is the column that names it);
    * `bibliography_entry_changed()` and `place_changed()` are replaced to reach the
      performances that cite the entry or are set at the place, in the state, or inside either.
  """
  use Ecto.Migration

  def up do
    create table(:performance_companies, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:performance_companies, ["lower(name)"])

    create table(:performance_actors, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :surname, :text
      add :forename, :text
      add :nickname, :text
      add :sex, :string

      timestamps(type: :utc_datetime)
    end

    create table(:play_performances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :play_id, references(:plays, type: :binary_id, on_delete: :delete_all), null: false
      add :date_text, :text
      add :year_from, :integer
      add :year_to, :integer
      add :venue, :text
      add :venue_type, :string

      add :company_id,
          references(:performance_companies, type: :binary_id, on_delete: :restrict)

      add :place_id, references(:places, type: :binary_id, on_delete: :restrict)
      add :historical_state_id, references(:places, type: :binary_id, on_delete: :restrict)
      add :note, :text

      add :source_entry_id,
          references(:bibliography_entries, type: :binary_id, on_delete: :restrict)

      add :source_volume, :text
      add :source_pages, :text
      add :cast_from_cast_list, :boolean, null: false, default: false
      add :position, :integer, null: false, default: 0
      add :origin, :string, null: false, default: "manual"
      add :filemaker_id, :text

      timestamps(type: :utc_datetime)
    end

    create index(:play_performances, [:play_id, :position])
    create index(:play_performances, [:company_id])
    create index(:play_performances, [:place_id])
    create index(:play_performances, [:historical_state_id])
    create index(:play_performances, [:source_entry_id])

    create unique_index(:play_performances, [:play_id],
             where: "cast_from_cast_list",
             name: :play_performances_one_cast_list_index
           )

    create table(:performance_cast, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :performance_id,
          references(:play_performances, type: :binary_id, on_delete: :delete_all),
          null: false

      add :actor_id, references(:performance_actors, type: :binary_id, on_delete: :restrict),
        null: false

      add :role, :text
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:performance_cast, [:performance_id, :position])
    create index(:performance_cast, [:actor_id])

    execute """
    CREATE TRIGGER play_performances_touch_play
      AFTER INSERT OR UPDATE OR DELETE ON play_performances
      FOR EACH ROW EXECUTE FUNCTION play_row_changed()
    """

    # A cast row changed: the play of its performance (both, for a row moved between two).
    execute """
    CREATE FUNCTION performance_cast_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id)
         FROM play_performances
        WHERE id IN (OLD.performance_id, NEW.performance_id);
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER performance_cast_touch_play
      AFTER INSERT OR UPDATE OR DELETE ON performance_cast
      FOR EACH ROW EXECUTE FUNCTION performance_cast_changed()
    """

    # A company or an actor was renamed: the plays whose performances name it, an actor
    # through the cast. TG_ARGV[0] is the column that names it, 'company_id' or 'actor_id'.
    # A new company or actor has no performances yet, and one in use cannot be deleted.
    execute """
    CREATE FUNCTION performance_name_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id)
         FROM play_performances
        WHERE (TG_ARGV[0] = 'company_id' AND company_id = NEW.id)
           OR (TG_ARGV[0] = 'actor_id'
               AND play_performances.id IN
                     (SELECT performance_id FROM performance_cast WHERE actor_id = NEW.id));
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE TRIGGER performance_companies_touch_plays
      AFTER UPDATE ON performance_companies
      FOR EACH ROW EXECUTE FUNCTION performance_name_changed('company_id')
    """

    execute """
    CREATE TRIGGER performance_actors_touch_plays
      AFTER UPDATE ON performance_actors
      FOR EACH ROW EXECUTE FUNCTION performance_name_changed('actor_id')
    """

    execute """
    CREATE OR REPLACE FUNCTION bibliography_entry_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id) FROM play_bibliography WHERE entry_id = NEW.id;
      PERFORM touch_play(play_id) FROM play_performances WHERE source_entry_id = NEW.id;
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE OR REPLACE FUNCTION place_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(related.play_id)
         FROM (
           WITH RECURSIVE tree(id) AS (
             SELECT (to_jsonb(OLD) ->> TG_ARGV[0])::uuid
             UNION
             SELECT (to_jsonb(NEW) ->> TG_ARGV[0])::uuid
             UNION
             SELECT places.id FROM places JOIN tree ON places.parent_place_id = tree.id
           )
           SELECT play_places.play_id
             FROM tree
             JOIN play_places
               ON play_places.place_id = tree.id OR play_places.historical_state_id = tree.id
           UNION
           SELECT play_performances.play_id
             FROM tree
             JOIN play_performances
               ON play_performances.place_id = tree.id
               OR play_performances.historical_state_id = tree.id
         ) AS related;

      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """
  end

  def down do
    # The function as 20261019120000_add_historical_state_to_play_places created it.
    execute """
    CREATE OR REPLACE FUNCTION place_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_places.play_id)
         FROM (
           WITH RECURSIVE tree(id) AS (
             SELECT (to_jsonb(OLD) ->> TG_ARGV[0])::uuid
             UNION
             SELECT (to_jsonb(NEW) ->> TG_ARGV[0])::uuid
             UNION
             SELECT places.id FROM places JOIN tree ON places.parent_place_id = tree.id
           )
           SELECT id FROM tree
         ) AS tree
         JOIN play_places
           ON play_places.place_id = tree.id OR play_places.historical_state_id = tree.id;

      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # The function as 20261007130000_create_bibliography created it.
    execute """
    CREATE OR REPLACE FUNCTION bibliography_entry_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id) FROM play_bibliography WHERE entry_id = NEW.id;
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # The tables go first: dropping them drops their triggers, which hold the functions.
    drop table(:performance_cast)
    drop table(:play_performances)
    drop table(:performance_actors)
    drop table(:performance_companies)

    execute "DROP FUNCTION performance_cast_changed()"
    execute "DROP FUNCTION performance_name_changed()"
  end
end
