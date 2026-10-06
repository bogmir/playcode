defmodule Playcode.Repo.Migrations.TrackPlayContentVersion do
  @moduledoc """
  `plays.content_version`: Postgres moves it whenever something a play's static pages
  show changes, so the export can tell which published plays are out of date. Spec:
  docs/superpowers/specs/2026-10-05-static-site-change-tracking-design.md.

  None of the functions names a data column, so adding a column to any table needs
  nothing. A new *table* with a `play_id` whose rows appear on a play's pages needs one
  line in its own migration:

      execute "CREATE TRIGGER my_table_touch_play AFTER INSERT OR UPDATE OR DELETE ON my_table FOR EACH ROW EXECUTE FUNCTION play_row_changed()",
              "DROP TRIGGER my_table_touch_play ON my_table"

  test/playcode/content_version_test.exs fails until it has it.
  """
  use Ecto.Migration

  # The tables with a play_id whose rows appear on a play's pages.
  @play_tables ~w(play_divisions play_elements characters play_editors play_sources
                  play_editorial_notes play_places)

  # True when an UPDATE of plays changed more than the bookkeeping columns. Moving the
  # version alone passes neither plays trigger, so a touch never fans out again.
  @data_changed """
  to_jsonb(OLD) - '{content_version,content_txid,updated_at}'::text[]
    IS DISTINCT FROM to_jsonb(NEW) - '{content_version,content_txid,updated_at}'::text[]
  """

  def up do
    execute "CREATE SEQUENCE play_content_version"

    alter table(:plays) do
      add :content_version, :bigint,
        null: false,
        default: fragment("nextval('play_content_version')")

      # The transaction that last moved content_version: it moves once per transaction.
      add :content_txid, :bigint
    end

    execute "ALTER SEQUENCE play_content_version OWNED BY plays.content_version"

    # Moves a play once per transaction, so an import writing thousands of rows updates
    # the play row once, and tells Playcode.Export.PlayChangeListener. Postgres sends the
    # notification on commit, one per play per transaction.
    execute """
    CREATE FUNCTION touch_play(play uuid) RETURNS void AS $$
    BEGIN
      UPDATE plays
         SET content_version = nextval('play_content_version'), content_txid = txid_current()
       WHERE id = play AND content_txid IS DISTINCT FROM txid_current();

      IF FOUND THEN
        PERFORM pg_notify('play_changed', play::text);
      END IF;
    END
    $$ LANGUAGE plpgsql
    """

    # A row of one of @play_tables changed. Both plays, for a row moved between them;
    # OLD is NULL on INSERT and NEW on DELETE, and touch_play(NULL) touches nothing.
    execute """
    CREATE FUNCTION play_row_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(OLD.play_id);
      PERFORM touch_play(NEW.play_id);
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # A speech's speakers changed: the play of the speech.
    execute """
    CREATE FUNCTION element_character_changed() RETURNS trigger AS $$
    BEGIN
      PERFORM touch_play(play_id) FROM play_elements WHERE id IN (OLD.element_id, NEW.element_id);
      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # A play's own row changed. BEFORE: its new version. AFTER: the plays whose title
    # pages show it, its original (before and after) and its translations.
    execute """
    CREATE FUNCTION play_changed() RETURNS trigger AS $$
    BEGIN
      IF TG_WHEN = 'BEFORE' THEN
        NEW.content_version := nextval('play_content_version');
        NEW.content_txid := txid_current();
        RETURN NEW;
      END IF;

      PERFORM pg_notify('play_changed', NEW.id::text);

      PERFORM touch_play(id)
         FROM plays
        WHERE id IN (OLD.parent_play_id, NEW.parent_play_id) OR parent_play_id = NEW.id;

      RETURN NULL;
    END
    $$ LANGUAGE plpgsql
    """

    # A place or one of its names changed: every play set there or anywhere inside it,
    # whose pages and TEI show the place with its ancestors. TG_ARGV[0] names the column
    # holding the place's id.
    execute """
    CREATE FUNCTION place_changed() RETURNS trigger AS $$
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

    for table <- @play_tables do
      execute """
      CREATE TRIGGER #{table}_touch_play AFTER INSERT OR UPDATE OR DELETE ON #{table}
        FOR EACH ROW EXECUTE FUNCTION play_row_changed()
      """
    end

    execute """
    CREATE TRIGGER element_characters_touch_play
      AFTER INSERT OR UPDATE OR DELETE ON element_characters
      FOR EACH ROW EXECUTE FUNCTION element_character_changed()
    """

    execute """
    CREATE TRIGGER plays_bump BEFORE UPDATE ON plays
      FOR EACH ROW WHEN (#{@data_changed}) EXECUTE FUNCTION play_changed()
    """

    execute """
    CREATE TRIGGER plays_touch_relatives AFTER UPDATE ON plays
      FOR EACH ROW WHEN (#{@data_changed}) EXECUTE FUNCTION play_changed()
    """

    # A new place has no plays yet, and a place a play links to cannot be deleted.
    execute """
    CREATE TRIGGER places_touch_plays AFTER UPDATE ON places
      FOR EACH ROW EXECUTE FUNCTION place_changed('id')
    """

    execute """
    CREATE TRIGGER place_names_touch_plays AFTER INSERT OR UPDATE OR DELETE ON place_names
      FOR EACH ROW EXECUTE FUNCTION place_changed('place_id')
    """
  end

  def down do
    # CASCADE drops the triggers that call each function.
    for function <-
          ~w[play_row_changed() element_character_changed() play_changed() place_changed()] do
      execute "DROP FUNCTION #{function} CASCADE"
    end

    execute "DROP FUNCTION touch_play(uuid)"

    # Dropping the column drops the sequence it owns.
    alter table(:plays) do
      remove :content_version
      remove :content_txid
    end
  end
end
