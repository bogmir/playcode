defmodule Playcode.Repo.Migrations.AddContentChangedAtToPlays do
  @moduledoc """
  `plays.content_changed_at`: when `content_version` last moved, the date an EPUB gives
  as its `dcterms:modified`. `updated_at` misses every edit to a play's other rows. The
  two functions of 20261005120000_track_play_content_version set it beside the version,
  and the two plays triggers, last recreated by 20261102130000_team_note_moves_no_play,
  leave it out of their WHEN clause with the other bookkeeping columns, so a touch still
  never fans out. Existing plays start from their `updated_at`, which their EPUBs already
  give, so none changes until its play does.
  """
  use Ecto.Migration

  @ignored "content_version,content_txid,updated_at,team_note"

  def up do
    alter table(:plays) do
      add :content_changed_at, :utc_datetime, null: false, default: fragment("now()")
    end

    recreate_triggers("#{@ignored},content_changed_at")
    execute "UPDATE plays SET content_changed_at = updated_at"
    replace_functions(", content_changed_at = now()", "NEW.content_changed_at := now();")
  end

  def down do
    replace_functions("", "")
    recreate_triggers(@ignored)

    alter table(:plays) do
      remove :content_changed_at
    end
  end

  defp replace_functions(touch, bump) do
    execute """
    CREATE OR REPLACE FUNCTION touch_play(play uuid) RETURNS void AS $$
    BEGIN
      UPDATE plays
         SET content_version = nextval('play_content_version'), content_txid = txid_current()#{touch}
       WHERE id = play AND content_txid IS DISTINCT FROM txid_current();

      IF FOUND THEN
        PERFORM pg_notify('play_changed', play::text);
      END IF;
    END
    $$ LANGUAGE plpgsql
    """

    execute """
    CREATE OR REPLACE FUNCTION play_changed() RETURNS trigger AS $$
    BEGIN
      IF TG_WHEN = 'BEFORE' THEN
        NEW.content_version := nextval('play_content_version');
        NEW.content_txid := txid_current();
        #{bump}
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
