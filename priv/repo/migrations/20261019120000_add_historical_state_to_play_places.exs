defmodule Playcode.Repo.Migrations.AddHistoricalStateToPlayPlaces do
  @moduledoc """
  `play_places.historical_state_id`: the state a place belonged to in this play (Castilla,
  Reino de Inglaterra), a place of the gazetteer like any other. Spec:
  docs/superpowers/specs/2026-10-19-s9b-places-import-design.md.

  A state's names are printed in the play's line, so `place_changed()` must also move
  the plays whose links name the changed place, or one inside it, as their state, not
  only those set there. One tree of places serves both columns.
  """
  use Ecto.Migration

  def up do
    alter table(:play_places) do
      add :historical_state_id, references(:places, type: :binary_id, on_delete: :restrict)
    end

    create index(:play_places, [:historical_state_id])

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
  end

  def down do
    # The function as 20261005120000_track_play_content_version created it.
    execute """
    CREATE OR REPLACE FUNCTION place_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id)
         FROM play_places
        WHERE place_id IN (
          WITH RECURSIVE tree(id) AS (
            SELECT (to_jsonb(OLD) ->> TG_ARGV[0])::uuid
            UNION
            SELECT (to_jsonb(NEW) ->> TG_ARGV[0])::uuid
            UNION
            SELECT places.id FROM places JOIN tree ON places.parent_place_id = tree.id
          )
          SELECT id FROM tree
        );

      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    drop index(:play_places, [:historical_state_id])

    alter table(:play_places) do
      remove :historical_state_id
    end
  end
end
